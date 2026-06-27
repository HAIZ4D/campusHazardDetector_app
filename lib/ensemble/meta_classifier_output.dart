// =============================================================================
// MetaClassifierOutput
// -----------------------------------------------------------------------------
// Result of running ONE match group through both meta-classifier TFLite
// models. The "voice of the ensemble" — these are the labels that drive the
// final UI in step 5 and the history entries in step 6.
//
// We expose both the top-1 result (label + confidence) AND the full softmax
// vectors so the UI / report can show "the model's second guess was X with
// 18%" if useful for debugging.
// =============================================================================

import 'dart:typed_data';

class MetaClassifierOutput {
  /// Top-1 label from `meta_classifier_specific.tflite` (e.g. "Pothole").
  /// One of the 17 entries in `MetaClassifierConfig.specificClasses`.
  final String specificLabel;

  /// Softmax probability of [specificLabel] (range [0.0, 1.0]).
  /// The UI in step 5 uses this for the "fall back to parent if below 0.5"
  /// rule.
  final double specificConfidence;

  /// Top-1 parent category from `meta_classifier_parent.tflite` (e.g.
  /// "Surface/Ground Hazard"). One of the 4 entries in
  /// `MetaClassifierConfig.parentClasses`.
  final String parentLabel;

  /// Softmax probability of [parentLabel] (range [0.0, 1.0]).
  final double parentConfidence;

  /// Full softmax vector from the specific model (17 entries, same order as
  /// `MetaClassifierConfig.specificClasses`). Kept for reporting / debug
  /// surfaces. Backed by [Float32List] to avoid per-frame boxed-double GC.
  final Float32List specificSoftmax;

  /// Full softmax vector from the parent model (4 entries, same order as
  /// `MetaClassifierConfig.parentClasses`).
  final Float32List parentSoftmax;

  const MetaClassifierOutput({
    required this.specificLabel,
    required this.specificConfidence,
    required this.parentLabel,
    required this.parentConfidence,
    required this.specificSoftmax,
    required this.parentSoftmax,
  });

  /// One-line debug summary used by EnsembleDetector logging.
  String summary() =>
      '$specificLabel ${(specificConfidence * 100).toStringAsFixed(1)}% '
      '| $parentLabel ${(parentConfidence * 100).toStringAsFixed(1)}%';
}
