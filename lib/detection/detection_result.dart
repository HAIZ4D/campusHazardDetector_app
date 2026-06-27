import 'package:flutter/material.dart';

/// Holds the data for a single object detected in one inference pass.
///
/// All bounding box coordinates are normalised to [0.0, 1.0] relative to the
/// image dimensions, so they can be scaled to any display size without
/// knowing the original pixel dimensions.
class DetectionResult {
  /// Index into the source model's class list. The class list is
  /// model-specific — index 2 from `haizad_model` is NOT the same hazard as
  /// index 2 from `sabrina_model`. Always interpret via [className].
  final int classIndex;

  /// Raw human-readable hazard label as produced by the source YOLO model,
  /// e.g. "Rusted Equipment" or "uncovered_drain". This is the *unharmonised*
  /// label — label normalisation happens later in the ensemble pipeline.
  final String className;

  /// Model confidence for this detection, range [0.0, 1.0].
  final double confidence;

  /// Normalised bounding box [left, top, right, bottom], each in [0.0, 1.0].
  final Rect boundingBox;

  /// Per-class (or per-source-model) display colour used for the bounding box
  /// and label background.
  final Color color;

  /// Identifier of the YOLO model that produced this detection
  /// (e.g. 'haizad', 'sabrina', 'hafiy', 'yasmin').
  ///
  /// This is critical for the ensemble pipeline: cross-model IoU matching
  /// must NEVER merge two boxes from the same model, and the meta-classifier
  /// feature vector has one confidence slot per source model.
  final String sourceModel;

  const DetectionResult({
    required this.classIndex,
    required this.className,
    required this.confidence,
    required this.boundingBox,
    required this.color,
    required this.sourceModel,
  });
}
