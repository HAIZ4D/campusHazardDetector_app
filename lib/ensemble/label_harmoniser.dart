// =============================================================================
// LabelHarmoniser
// -----------------------------------------------------------------------------
// Maps each raw YOLO class name (as the four models emit them, in their own
// idiosyncratic capitalisation and snake_case styles) onto:
//   1. a normalised label   — one of the 17 canonical labels the
//                              meta-classifier was trained on, AND
//   2. a parent category    — one of the 4 hazard families.
//
// The map is the contract between the team's four heterogeneous models and
// the shared downstream pipeline (matching, meta-classifier, UI). Two raw
// labels can intentionally map to the SAME normalised label — e.g.
// 'uncovered_drain' (sabrina) and 'open_drain' (hafiy) both → 'Open/Uncovered
// Drain'. This is what lets the matcher form cross-model agreement groups
// even when the underlying class names disagree.
//
// If a raw class name is missing from this map, harmonise() returns null and
// the detection is silently dropped by the ensemble — log a warning so the
// gap is visible during development.
// =============================================================================

import 'package:flutter/foundation.dart' show debugPrint;

import '../detection/detection_result.dart';
import 'harmonised_detection.dart';

/// A `(normalised label, parent category)` pair.
class HarmonisedLabel {
  final String normalised;
  final String parent;
  const HarmonisedLabel(this.normalised, this.parent);
}

class LabelHarmoniser {
  LabelHarmoniser._();

  /// The 19 unique raw class names across all 4 models → harmonised label.
  /// Keys are CASE-SENSITIVE and match the strings the YOLO models emit.
  static const Map<String, HarmonisedLabel> _map = {
    // ── Haizad's model ─────────────────────────────────────────────────────
    'Mossy Surface':
        HarmonisedLabel('Mossy Surface', 'Surface/Ground Hazard'),
    'Overgrown Vegetation':
        HarmonisedLabel('Overgrown Vegetation', 'Obstruction Hazard'),
    'Protruding Fastener':
        HarmonisedLabel('Protruding Fastener', 'Structural/Injury Hazard'),
    'Rusted Equipment':
        HarmonisedLabel('Rusted Equipment', 'Structural/Injury Hazard'),
    'Waterlogged field':
        HarmonisedLabel('Waterlogged Field', 'Surface/Ground Hazard'),

    // ── Sabrina's model ────────────────────────────────────────────────────
    'damaged_flooring':
        HarmonisedLabel('Damaged Flooring', 'Surface/Ground Hazard'),
    'fallen_branch':
        HarmonisedLabel('Fallen Branch', 'Obstruction Hazard'),
    'overflowing_trash':
        HarmonisedLabel('Overflowing Trash Bin', 'Hygiene Hazard'),
    'uncovered_drain':
        HarmonisedLabel('Open/Uncovered Drain', 'Surface/Ground Hazard'),
    'water_accumulation':
        HarmonisedLabel('Wet Floor', 'Surface/Ground Hazard'),

    // ── Hafiy's model ──────────────────────────────────────────────────────
    'open_drain':
        HarmonisedLabel('Open/Uncovered Drain', 'Surface/Ground Hazard'),
    'overgrown_vegetation':
        HarmonisedLabel('Overgrown Vegetation', 'Obstruction Hazard'),
    'pothole':
        HarmonisedLabel('Pothole', 'Surface/Ground Hazard'),
    'sharp_object':
        HarmonisedLabel('Sharp Object', 'Structural/Injury Hazard'),
    'uneven_floor':
        HarmonisedLabel('Uneven Floor', 'Surface/Ground Hazard'),

    // ── Yasmin's model ─────────────────────────────────────────────────────
    'broken_fence':
        HarmonisedLabel('Broken Fence', 'Structural/Injury Hazard'),
    'broken_lamppost':
        HarmonisedLabel('Broken Lamp Post', 'Structural/Injury Hazard'),
    'broken_signboard':
        HarmonisedLabel('Unclear/Broken Signboard', 'Structural/Injury Hazard'),
    // 'fallen_branch' already mapped above (sabrina) — same target.
    'obstacle_walkway':
        HarmonisedLabel('Obstacle Walkway', 'Obstruction Hazard'),
  };

  /// Wrap a raw [det] with its normalised label and parent category.
  ///
  /// Returns `null` when the raw class name is not in [_map]; this should
  /// only happen if a model is updated with new classes and this map is
  /// forgotten. The caller (the ensemble) drops such detections silently
  /// because feeding the meta-classifier a one-hot of an unknown label
  /// would produce garbage.
  static HarmonisedDetection? harmonise(DetectionResult det) {
    final h = _map[det.className];
    if (h == null) {
      debugPrint(
        '[LabelHarmoniser] Unmapped raw class "${det.className}" from '
        'model "${det.sourceModel}" — detection dropped. Add it to '
        'LabelHarmoniser._map.',
      );
      return null;
    }
    return HarmonisedDetection(
      raw: det,
      normalisedLabel: h.normalised,
      parentCategory: h.parent,
    );
  }

  /// Convenience batch wrapper: harmonise a list, dropping unknowns.
  static List<HarmonisedDetection> harmoniseAll(
    Iterable<DetectionResult> detections,
  ) {
    final out = <HarmonisedDetection>[];
    for (final d in detections) {
      final h = harmonise(d);
      if (h != null) out.add(h);
    }
    return out;
  }
}
