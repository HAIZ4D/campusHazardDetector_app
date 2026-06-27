// =============================================================================
// HarmonisedDetection
// -----------------------------------------------------------------------------
// A thin immutable wrapper that pairs a raw [DetectionResult] with the
// normalised label and parent category produced by [LabelHarmoniser]. Keeping
// the raw detection accessible means the rendering layer can still query the
// source model, original confidence, original box, etc., while downstream
// logic (matching, feature-vector construction) operates on the harmonised
// labels.
// =============================================================================

import 'package:flutter/material.dart';

import '../detection/detection_result.dart';

class HarmonisedDetection {
  /// The original YOLO output (with bbox, confidence, raw className, etc.).
  final DetectionResult raw;

  /// One of the 17 canonical labels — matches the meta-classifier's
  /// `specific_classes` and `onehot_categories` ordering in the config JSON.
  final String normalisedLabel;

  /// One of the 4 parent categories: Hygiene Hazard, Obstruction Hazard,
  /// Structural/Injury Hazard, Surface/Ground Hazard.
  final String parentCategory;

  const HarmonisedDetection({
    required this.raw,
    required this.normalisedLabel,
    required this.parentCategory,
  });

  // Pass-through getters so callers don't have to write `.raw.X` constantly.
  String get sourceModel => raw.sourceModel;
  double get confidence => raw.confidence;
  Rect get boundingBox => raw.boundingBox;
  Color get color => raw.color;
  String get rawClassName => raw.className;
}
