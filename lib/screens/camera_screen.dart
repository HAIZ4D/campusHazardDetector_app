import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../ensemble/classified_detection.dart';
import '../ensemble/ensemble_detector.dart';
import '../models/detection_record.dart';
import '../models/hazard_severity.dart';
import '../models/hazard_zone.dart';
import '../services/app_settings_service.dart';
import '../services/detection_history_service.dart';
import '../widgets/bounding_box_overlay.dart';

/// Live camera tab.
///
/// As of the UI overhaul, this is NO LONGER a top-level Scaffold — it lives
/// inside [MainShell]'s [IndexedStack] as a body widget. The shell owns the
/// global NavigationBar at the bottom; the camera fills everything above it.
///
/// Layout:
///   - Camera preview behind everything (kept at native aspect ratio).
///   - Floating top overlay: zone picker chip + detection count chip.
///   - Floating big circular shutter button at the bottom centre.
///   - Bounding box overlay paints over the camera preview.
///
/// `isActive` is passed by the shell so the image stream pauses on tab
/// switch (saves battery without unmounting the camera).
class CameraScreen extends StatefulWidget {
  final bool isActive;
  const CameraScreen({super.key, this.isActive = true});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;

  /// Initial frameSkip is whatever AppSettingsService had on disk; we
  /// rebind it live whenever Settings is changed (see didChangeDependencies
  /// + the Consumer in build).
  late EnsembleDetector _detector;

  List<ClassifiedDetection> _classified = [];
  bool _isDetecting = false;

  bool _isCapturing = false;
  String? _errorMessage;

  /// Local mirror of [AppSettingsService.lastZone] — we read the persisted
  /// value once in initState (via `read`) and update the service whenever
  /// the user picks a new zone.
  HazardZone _selectedZone = HazardZone.unspecified;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Read initial settings synchronously from the providers above us.
    final settings = context.read<AppSettingsService>();
    _selectedZone = settings.lastZone;
    _detector = EnsembleDetector(frameSkip: settings.frameSkip);

    _initCameraAndModel();
  }

  @override
  void didUpdateWidget(CameraScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Tab-visibility lifecycle: pause stream when shell deactivates this tab,
    // resume when it comes back.
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _resumeStreamIfPossible();
      } else {
        _pauseStreamIfPossible();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller!.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCameraAndModel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _detector.dispose();
    super.dispose();
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  Future<void> _initCameraAndModel() async {
    final PermissionStatus cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      setState(() => _errorMessage =
          'Camera permission denied.\nGo to Settings → App permissions to grant it.');
      return;
    }

    final List<CameraDescription> cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _errorMessage = 'No cameras found on this device.');
      return;
    }

    final CameraDescription backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
    } catch (e) {
      setState(() => _errorMessage = 'Failed to initialise camera: $e');
      return;
    }

    try {
      await _detector.loadModels();
    } catch (e) {
      setState(() => _errorMessage =
          'Failed to load TFLite models.\n'
          'Make sure all 4 *_model.tflite files are in assets/models/\n($e)');
      return;
    }

    if (widget.isActive) {
      await _controller!.startImageStream(_onFrameAvailable);
    }

    if (mounted) setState(() {});
  }

  Future<void> _pauseStreamIfPossible() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isStreamingImages) {
      await c.stopImageStream();
    }
  }

  Future<void> _resumeStreamIfPossible() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (!c.value.isStreamingImages) {
      await c.startImageStream(_onFrameAvailable);
    }
  }

  // ── Frame processing ───────────────────────────────────────────────────────

  void _onFrameAvailable(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      final List<ClassifiedDetection>? results =
          await _detector.detect(image);
      if (results != null && mounted) {
        setState(() => _classified = results);
      }
    } finally {
      _isDetecting = false;
    }
  }

  // ── Capture ────────────────────────────────────────────────────────────────

  Future<void> _captureDetection() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      await _controller!.stopImageStream();
      final XFile photo = await _controller!.takePicture();

      final Directory docsDir = await getApplicationDocumentsDirectory();
      final String capturesDir = '${docsDir.path}/hazard_captures';
      await Directory(capturesDir).create(recursive: true);

      final DateTime now = DateTime.now();
      final String filename =
          'hazard_${DateFormat('yyyyMMdd_HHmmss').format(now)}.jpg';
      final String savedPath = '$capturesDir/$filename';

      await File(photo.path).copy(savedPath);

      ClassifiedDetection? best;
      for (final c in _classified) {
        if (best == null ||
            c.group.size > best.group.size ||
            (c.group.size == best.group.size &&
                c.meta.specificConfidence > best.meta.specificConfidence)) {
          best = c;
        }
      }

      const canonicalOrder = ['haizad', 'sabrina', 'hafiy', 'yasmin'];
      final Map<String, double> perModelConfidences = {};
      if (best != null) {
        for (final key in canonicalOrder) {
          final conf = best.group.confidenceFor(key);
          if (conf > 0) perModelConfidences[key] = conf;
        }
      }

      final HazardSeverity severity = best == null
          ? HazardSeverity.low
          : HazardSeverity.compute(
              parentLabel: best.meta.parentLabel,
              specificConfidence: best.meta.specificConfidence,
            );

      final DetectionRecord record = DetectionRecord(
        id: now.millisecondsSinceEpoch.toString(),
        timestamp: now,
        specificLabel: best?.meta.specificLabel ?? '',
        specificConfidence: best?.meta.specificConfidence ?? 0.0,
        parentLabel: best?.meta.parentLabel ?? '',
        parentConfidence: best?.meta.parentConfidence ?? 0.0,
        perModelConfidences: perModelConfidences,
        zone: _selectedZone,
        severity: severity,
        imagePath: savedPath,
      );

      final String snackLabel = best == null
          ? 'Captured (no hazard detected)'
          : 'Detection saved: ${record.specificLabel}';

      if (mounted) {
        context.read<DetectionHistoryService>().addRecord(record);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackLabel),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capture failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (_controller != null &&
          _controller!.value.isInitialized &&
          widget.isActive) {
        await _controller!.startImageStream(_onFrameAvailable);
      }
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Subscribe to settings changes — when frameSkip changes elsewhere
    // (Settings tab), reflect it live on the detector.
    final settings = context.watch<AppSettingsService>();
    if (_detector.frameSkip != settings.frameSkip) {
      _detector.frameSkip = settings.frameSkip;
    }

    if (_errorMessage != null) return _buildErrorScreen(_errorMessage!);
    if (_controller == null || !_controller!.value.isInitialized) {
      return _buildLoadingScreen();
    }

    // Black backdrop is intentional — the camera preview shines best on
    // black; the floating chip overlays carry the light theme on top.
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ───────────────────────────────────────────────
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: CameraPreview(_controller!),
            ),
          ),

          // ── Bounding boxes ──────────────────────────────────────────────
          Positioned.fill(
            child: BoundingBoxOverlay(detections: _classified),
          ),

          // ── Floating top overlay: zone + detection count chips ──────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Row(
              children: [
                _ZonePickerChip(
                  current: _selectedZone,
                  onChanged: (z) {
                    setState(() => _selectedZone = z);
                    context.read<AppSettingsService>().setLastZone(z);
                  },
                ),
                const Spacer(),
                _DetectionCountChip(count: _classified.length),
              ],
            ),
          ),

          // ── Floating big shutter button ─────────────────────────────────
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: _ShutterButton(
                isCapturing: _isCapturing,
                onTap: _captureDetection,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.deepOrange),
          SizedBox(height: 16),
          Text(
            'Initialising camera & models…',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen(String message) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              setState(() => _errorMessage = null);
              _initCameraAndModel();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ── Big circular shutter button ─────────────────────────────────────────────

/// Classic camera-app shutter: large white ring around a coloured inner
/// circle. Renders a small spinner inside while a capture is in progress.
class _ShutterButton extends StatelessWidget {
  final bool isCapturing;
  final VoidCallback onTap;

  const _ShutterButton({
    required this.isCapturing,
    required this.onTap,
  });

  static const double _outerSize = 84;
  static const double _innerSize = 64;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isCapturing ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _outerSize,
        height: _outerSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.20),
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: _innerSize,
            height: _innerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCapturing
                  ? Colors.white.withValues(alpha: 0.6)
                  : Colors.deepOrange,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: isCapturing
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.camera_alt, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}

// ── Detection count chip ────────────────────────────────────────────────────

class _DetectionCountChip extends StatelessWidget {
  final int count;
  const _DetectionCountChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final bool active = count > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? Colors.red.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            active
                ? '$count hazard${count > 1 ? 's' : ''}'
                : 'All clear',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Zone picker chip ─────────────────────────────────────────────────────────

class _ZonePickerChip extends StatelessWidget {
  final HazardZone current;
  final ValueChanged<HazardZone> onChanged;

  const _ZonePickerChip({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<HazardZone>(
      tooltip: 'Set zone for the next capture',
      initialValue: current,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final z in HazardZone.values)
          PopupMenuItem<HazardZone>(
            value: z,
            child: Row(
              children: [
                Icon(z.icon, size: 18, color: Colors.black54),
                const SizedBox(width: 10),
                Text(z.displayName),
                if (z == current) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check, size: 16, color: Colors.black54),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(current.icon, size: 14, color: Colors.white70),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                current.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
            const Icon(Icons.arrow_drop_down,
                size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}
