// =============================================================================
// SettingsScreen
// -----------------------------------------------------------------------------
// Tab #4 of MainShell. Three sections:
//   1. Detection  : frame-skip slider (live — updates EnsembleDetector.frameSkip
//                                       through AppSettingsService).
//   2. AI         : Gemini API key status + a tiny self-test button.
//   3. Storage    : clear all detections (asks for confirmation).
//   4. About      : app description + the dev-friendly numbers from the
//                    technical report (model count, threshold etc.).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import '../models/detection_record.dart';
import '../models/hazard_severity.dart';
import '../models/hazard_zone.dart';
import '../services/app_settings_service.dart';
import '../services/detection_history_service.dart';
import '../services/gemini_service.dart';
import '../widgets/display_rules.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: const [
          _DetectionSection(),
          SizedBox(height: 16),
          _AiSection(),
          SizedBox(height: 16),
          _StorageSection(),
          SizedBox(height: 16),
          _AboutSection(),
        ],
      ),
    );
  }
}

// ── 1. Detection ────────────────────────────────────────────────────────────

class _DetectionSection extends StatelessWidget {
  const _DetectionSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSettingsService>(
      builder: (_, settings, __) {
        final fs = settings.frameSkip;
        return _SettingsCard(
          icon: Icons.speed,
          title: 'Detection frequency',
          subtitle: 'How often the 4-model ensemble runs on the camera '
              'feed. Lower = more accurate but slower UI; higher = '
              'smoother but staler.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Every $fs frame${fs == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _frameSkipColor(fs).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _frameSkipColor(fs), width: 1),
                    ),
                    child: Text(
                      _frameSkipLabel(fs),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _frameSkipColor(fs),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Slider(
                value: fs.toDouble(),
                min: AppSettingsService.minFrameSkip.toDouble(),
                max: AppSettingsService.maxFrameSkip.toDouble(),
                divisions: AppSettingsService.maxFrameSkip -
                    AppSettingsService.minFrameSkip,
                label: '$fs',
                onChanged: (v) => settings.setFrameSkip(v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Most accurate',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                  Text(
                    'Smoothest',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Specific-vs-parent fallback threshold: '
                '${(kSpecificFallbackThreshold * 100).toStringAsFixed(0)}% '
                '(compile-time)',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        );
      },
    );
  }

  static Color _frameSkipColor(int fs) {
    switch (fs) {
      case 1:
        return const Color(0xFFE53935); // most accurate, slowest UI
      case 2:
        return const Color(0xFFFB8C00);
      case 3:
        return const Color(0xFF8BC34A);
      case 4:
      default:
        return const Color(0xFF4CAF50); // smoothest
    }
  }

  static String _frameSkipLabel(int fs) {
    switch (fs) {
      case 1:
        return 'MAX ACCURACY';
      case 2:
        return 'BALANCED';
      case 3:
        return 'SMOOTHER';
      case 4:
      default:
        return 'SMOOTHEST';
    }
  }
}

// ── 2. AI ───────────────────────────────────────────────────────────────────

class _AiSection extends StatefulWidget {
  const _AiSection();

  @override
  State<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends State<_AiSection> {
  bool _testing = false;
  String? _testResult;
  Color? _testResultColor;

  bool get _hasKey {
    final k = dotenv.env['GEMINI_API_KEY'];
    return k != null &&
        k.isNotEmpty &&
        !k.startsWith('replace_me') &&
        !k.startsWith('your_');
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      // Self-test: build a throwaway DetectionRecord with realistic values
      // and run it through the SAME path the recommendation button uses.
      // Validates: key is present, network is reachable, key restrictions
      // accept this app's requests.
      await GeminiService.instance.generateRecommendation(_synthRecord());
      setState(() {
        _testResult = 'Connection OK — Gemini returned a response.';
        _testResultColor = Colors.green.shade700;
      });
    } on GeminiServiceException catch (e) {
      setState(() {
        _testResult = '${e.kind.name}: ${e.message}';
        _testResultColor = Colors.red.shade700;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// Throwaway record for the self-test. Never written to the history list;
  /// only used as input to the prompt builder.
  static DetectionRecord _synthRecord() {
    return DetectionRecord(
      id: 'settings-self-test',
      timestamp: DateTime.now(),
      specificLabel: 'Pothole',
      specificConfidence: 0.80,
      parentLabel: 'Surface/Ground Hazard',
      parentConfidence: 0.90,
      perModelConfidences: const {'haizad': 0.80},
      zone: HazardZone.unspecified,
      severity: HazardSeverity.medium,
      imagePath: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.auto_awesome,
      title: 'AI recommendations',
      subtitle:
          'Gemini generates a short safety note per saved hazard. Calls are '
          'on-demand only (never from a per-frame loop) and cached into the '
          'record so re-opening does not re-call the API.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _hasKey ? Icons.check_circle : Icons.error_outline,
                size: 16,
                color: _hasKey ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 6),
              Text(
                _hasKey
                    ? 'API key configured'
                    : 'API key missing (edit .env)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _hasKey ? Colors.green.shade800 : Colors.red.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Model: gemini-2.5-flash',
            style: TextStyle(
              fontSize: 11,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _runTest,
              icon: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt, size: 16),
              label: Text(_testing ? 'Testing…' : 'Test Gemini connection'),
            ),
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _testResultColor!.withValues(alpha: 0.08),
                border: Border.all(
                    color: _testResultColor!.withValues(alpha: 0.5), width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _testResult!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: _testResultColor,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

}

// ── 3. Storage ──────────────────────────────────────────────────────────────

class _StorageSection extends StatelessWidget {
  const _StorageSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<DetectionHistoryService>(
      builder: (_, history, __) {
        return _SettingsCard(
          icon: Icons.storage,
          title: 'Storage',
          subtitle:
              'History records and Gemini recommendations are persisted to '
              'the app documents directory and survive restarts.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_outlined,
                      size: 16, color: Colors.black.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Text(
                    'Saved records: ${history.count}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: history.count == 0
                      ? null
                      : () => _confirmClearAll(context, history),
                  icon: const Icon(Icons.delete_sweep, size: 16),
                  label: const Text('Clear all detection records'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmClearAll(
      BuildContext context, DetectionHistoryService history) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear all records?'),
        content: const Text(
            'This will remove every saved detection from history. '
            'Saved JPEG files on disk will not be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      for (final r in List.of(history.records)) {
        history.removeRecord(r.id);
      }
    }
  }
}

// ── 4. About ────────────────────────────────────────────────────────────────

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.info_outline,
      title: 'About',
      subtitle: null,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AboutRow(k: 'App', v: 'Campus Hazard Detector'),
          _AboutRow(k: 'Course', v: 'CSC4602'),
          _AboutRow(k: 'YOLO models', v: '4 × YOLOv8n (640×640)'),
          _AboutRow(k: 'Meta-classifier', v: '24 → 17 / 24 → 4 dense NN'),
          _AboutRow(k: 'AI advice', v: 'Gemini 2.5 Flash (on demand)'),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final String k;
  final String v;
  const _AboutRow({required this.k, required this.v});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              k,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                fontSize: 12.5,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable card shell ──────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon,
                      size: 16, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
