// =============================================================================
// EnsembleDetector
// -----------------------------------------------------------------------------
// Full per-frame ensemble pipeline:
//   1. Preprocess the camera frame ONCE   (shared 640×640 RGB Float32 tensor)
//   2. Run all 4 YOLO models on it        (sequential CPU inference)
//   3. Harmonise each raw detection       (raw class → normalised + parent)
//   4. Cross-model IoU matching           (groups boxes from DIFFERENT models
//                                          with IoU ≥ 0.3)
//   5. Meta-classifier inference          (build 24-D feature vector per
//                                          group, run specific + parent NNs)
//
// Output: one [ClassifiedDetection] per physical hazard — couples the YOLO
// evidence (geometry, source models, per-model confidences) with the
// meta-classifier's refined label + parent + their confidences.
//
// Performance (Samsung A13, debug build) — roughly:
//   ~ 300–600 ms   pure-Dart YUV→RGB + resize (shared)
//   ~  50–200 ms   per YOLOv8n CPU inference × 4
//   ~   1–5 ms     harmonise + match
//   ~  <1 ms       meta-classifier × N groups (tiny dense NNs)
//   ────────────────────────────────────────────
//   ~ 500–1400 ms total → 0.7–2 fps
// The dominant cost is preprocessing, not inference; raising [frameSkip] is
// the cheapest knob to dial latency down.
// =============================================================================

import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../detection/detection_result.dart';
import '../detection/detector.dart';
import '../detection/frame_preprocessor.dart';
import 'classified_detection.dart';
import 'cross_model_matcher.dart';
import 'ensemble_models.dart';
import 'label_harmoniser.dart';
import 'meta_classifier.dart';
import 'meta_classifier_config.dart';

class EnsembleDetector {
  /// The 4 model detectors, in the order defined by [kEnsembleModelSpecs].
  final List<HazardDetector> _detectors;

  /// Loaded lazily inside [loadModels] — keeps construction synchronous so
  /// the CameraScreen can hold this as a `final` field without async-init
  /// gymnastics.
  MetaClassifier? _metaClassifier;

  /// Process 1 out of every [frameSkip] camera frames. 1 = every frame.
  /// Higher values smooth real-time feel at the cost of staler results.
  int frameSkip;

  bool _isRunning = false;
  int _framesSinceLastProcessed = 0;

  EnsembleDetector({this.frameSkip = 1})
      : _detectors = kEnsembleModelSpecs
            .map((spec) => HazardDetector(spec: spec))
            .toList();

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Loads all 6 TFLite interpreters (4 YOLO + 2 meta-classifier) plus the
  /// meta-classifier JSON config. Done sequentially to avoid spiking RAM
  /// during the .tflite parse phase.
  Future<void> loadModels() async {
    debugPrint(
      '[EnsembleDetector] Loading ${_detectors.length} YOLO models '
      '(${_detectors.map((d) => d.spec.key).join(', ')})…',
    );
    for (final detector in _detectors) {
      await detector.loadModel();
    }

    debugPrint('[EnsembleDetector] Loading meta-classifier…');
    final metaConfig = await MetaClassifierConfig.loadFromAsset();
    _metaClassifier = MetaClassifier(config: metaConfig);
    await _metaClassifier!.loadModels();

    debugPrint('[EnsembleDetector] All models loaded.');
  }

  void dispose() {
    for (final detector in _detectors) {
      detector.dispose();
    }
    _metaClassifier?.dispose();
    _metaClassifier = null;
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  /// Runs the full pipeline on [cameraImage] and returns one
  /// [ClassifiedDetection] per physical hazard, or `null` when:
  ///   - this frame is being skipped by the [frameSkip] policy,
  ///   - a previous inference is still running, OR
  ///   - YUV→RGB preprocessing failed.
  ///
  /// In all "null" cases the caller should keep displaying whatever it had
  /// before — null means "no fresh data this tick", NOT "no detections".
  Future<List<ClassifiedDetection>?> detect(CameraImage cameraImage) async {
    // ── Frame-skip gate ──────────────────────────────────────────────────
    _framesSinceLastProcessed++;
    if (_framesSinceLastProcessed < frameSkip) return null;
    if (_isRunning) return null;

    _framesSinceLastProcessed = 0;
    _isRunning = true;

    try {
      // ── Step 1: Preprocess the frame ONCE ──────────────────────────────
      final Float32List? inputTensor =
          FramePreprocessor.preprocess(cameraImage);
      if (inputTensor == null) return null;

      // ── Step 2: Run each YOLO on the shared tensor ─────────────────────
      final List<DetectionResult> allRaw = [];
      for (final detector in _detectors) {
        final results = await detector.detectFromTensor(inputTensor);
        if (results != null) allRaw.addAll(results);
      }

      // ── Step 3: Harmonise (raw class → normalised label + parent) ──────
      final harmonised = LabelHarmoniser.harmoniseAll(allRaw);

      // ── Step 4: Cross-model IoU matching ───────────────────────────────
      final groups = CrossModelMatcher.match(harmonised);

      // ── Step 5: Meta-classifier inference for every group ──────────────
      // Each call runs two tiny dense NNs (24→17 and 24→4). Sub-millisecond
      // each on this device, so we don't bother with batching or threading.
      final meta = _metaClassifier;
      final List<ClassifiedDetection> classified = [];
      if (meta != null) {
        for (final g in groups) {
          classified.add(ClassifiedDetection(
            group: g,
            meta: meta.predict(g),
          ));
        }
      }

      // Debug visibility — useful while developing step 5.
      if (classified.isNotEmpty) {
        final perModel = <String, int>{};
        for (final d in allRaw) {
          perModel[d.sourceModel] = (perModel[d.sourceModel] ?? 0) + 1;
        }
        final sizeHistogram = <int, int>{};
        for (final c in classified) {
          sizeHistogram[c.group.size] =
              (sizeHistogram[c.group.size] ?? 0) + 1;
        }
        debugPrint(
          '[EnsembleDetector] raw=$perModel  '
          'groups=${classified.length} (sizes=$sizeHistogram)',
        );
        for (final c in classified) {
          debugPrint(
            '  ${c.group.summary()}  →  ${c.meta.summary()}',
          );
        }
      }

      return classified;
    } finally {
      _isRunning = false;
    }
  }
}
