// =============================================================================
// HazardDetector
// -----------------------------------------------------------------------------
// Owns ONE TFLite interpreter for ONE YOLOv8n hazard model. The ensemble in
// `lib/ensemble/ensemble_detector.dart` constructs four of these (one per
// teammate's model) and runs them on the same preprocessed frame.
//
// Notable design choices:
//   - Construction takes a [HazardDetectorSpec] (asset path, model key, class
//     names, per-class colors) so the same code services all four models.
//   - [detectFromTensor] accepts a pre-built input tensor. This lets the
//     ensemble call FramePreprocessor.preprocess() ONCE per frame and reuse
//     the result across all 4 interpreters — preprocessing is currently the
//     dominant cost on this device, so avoiding 4× preprocessing is critical.
//   - Every returned [DetectionResult] is stamped with [HazardDetectorSpec.key]
//     in `sourceModel`, which the downstream IoU matcher and meta-classifier
//     feature builder rely on.
// =============================================================================

import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detection_result.dart';
import 'frame_preprocessor.dart';
import 'yolo_processor.dart';

/// Confidence threshold applied to raw YOLO output before NMS. Below this
/// value, anchors are discarded entirely. Shared across all 4 models so the
/// meta-classifier sees a comparable signal from each.
const double kConfidenceThreshold = 0.5;

/// Static configuration of one model in the ensemble.
class HazardDetectorSpec {
  /// Short identifier used in logs and in `DetectionResult.sourceModel`.
  /// MUST match the *prefix* used in `meta_classifier_config.json`'s
  /// `feature_order` (e.g. key 'haizad' ↔ 'Haizad_confidence').
  final String key;

  /// Asset path of the .tflite file (e.g. 'assets/models/haizad_model.tflite').
  final String assetPath;

  /// Ordered list of class names — index must match the model's output order.
  final List<String> classNames;

  /// One distinct colour per class for bounding boxes and labels.
  /// (Step 5 of the project will replace this with parent-category colours;
  /// for now this is what the overlay paints.)
  final List<Color> classColors;

  const HazardDetectorSpec({
    required this.key,
    required this.assetPath,
    required this.classNames,
    required this.classColors,
  });
}

/// Wraps a single TFLite YOLOv8n interpreter and post-processes its output.
class HazardDetector {
  final HazardDetectorSpec spec;

  Interpreter? _interpreter;

  /// Guards against launching a second inference while one is still running
  /// on this specific interpreter.
  bool _isRunning = false;

  HazardDetector({required this.spec});

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Loads this detector's TFLite model from the app's bundled assets.
  /// Must be awaited before calling [detect] or [detectFromTensor].
  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset(spec.assetPath);

    // Log both shape AND dtype for every interpreter — this is the
    // single source of truth for "are all 4 models pinned to the same
    // input contract?". A mismatch here will silently corrupt the
    // shared input tensor used by EnsembleDetector.
    final inTensor = _interpreter!.getInputTensor(0);
    final outTensor = _interpreter!.getOutputTensor(0);
    debugPrint(
      '[HazardDetector:${spec.key}] '
      'Input shape: ${inTensor.shape} dtype: ${inTensor.type}   '
      'Output shape: ${outTensor.shape} dtype: ${outTensor.type}',
    );
  }

  /// Frees the native interpreter resources. Call from owning `dispose()`.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  /// Convenience: preprocess [cameraImage] *inside* this detector and run
  /// inference. Used by single-model unit tests; the ensemble path uses
  /// [detectFromTensor] instead so preprocessing is shared across models.
  Future<List<DetectionResult>?> detect(CameraImage cameraImage) async {
    final tensor = FramePreprocessor.preprocess(cameraImage);
    if (tensor == null) return null;
    return detectFromTensor(tensor);
  }

  /// Runs YOLOv8 inference on an *already-preprocessed* input tensor.
  /// The tensor must be a flat Float32List of length
  /// `1 * kInputSize * kInputSize * 3` in row-major (H, W, C) order with
  /// values in [0.0, 1.0]. The caller retains ownership — this method does
  /// not mutate the tensor, making it safe to share across detectors.
  ///
  /// Returns `null` if the model is not loaded or another inference on this
  /// detector is already in progress.
  Future<List<DetectionResult>?> detectFromTensor(Float32List tensor) async {
    if (_interpreter == null || _isRunning) return null;
    _isRunning = true;

    try {
      // YOLOv8 5-class output shape: [1, 9, 8400]
      //   9    = 4 bbox coords + 5 class scores
      //   8400 = sum of anchors across the three detection scales
      final List<List<List<double>>> outputBuffer = List.generate(
        1,
        (_) => List.generate(
          9,
          (_) => List<double>.filled(8400, 0.0),
        ),
      );

      // Pass raw bytes (Uint8List) not Float32List. tflite_flutter 0.12.x
      // calls computeShapeOf() on Float32List inputs and reshapes the input
      // tensor to flat 1-D, which breaks the PAD kernel. Uint8List bypasses
      // that shape-detection path entirely — see CLAUDE.md "Bug 3".
      _interpreter!.run(tensor.buffer.asUint8List(), outputBuffer);

      // Strip the batch dimension and let YoloProcessor do threshold + NMS.
      // We stamp the source model key on every detection so the ensemble can
      // tell which model produced which box during cross-model matching.
      return YoloProcessor.process(
        outputBuffer[0],
        classNames: spec.classNames,
        classColors: spec.classColors,
        confidenceThreshold: kConfidenceThreshold,
        sourceModel: spec.key,
      );
    } finally {
      _isRunning = false;
    }
  }
}
