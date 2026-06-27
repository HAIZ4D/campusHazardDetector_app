// =============================================================================
// Static specifications for the 4 YOLO models in the ensemble.
// -----------------------------------------------------------------------------
// Each [HazardDetectorSpec] declares:
//   - key        : short identifier used as `sourceModel` on every detection
//                  and in log lines. MUST match the prefix used in
//                  `meta_classifier_config.json` `feature_order` entries
//                  (e.g. key 'haizad' ↔ 'Haizad_confidence').
//   - assetPath  : path to the .tflite file in the app bundle.
//   - classNames : ordered list of class labels — the index MUST match the
//                  class index produced by the trained model.
//   - classColors: one colour per class. For step 2 we colour ALL classes of
//                  the same model with the same hue so you can visually tell
//                  which model produced which bounding box. Step 5 of the
//                  project replaces this with parent-category colouring.
// =============================================================================

import 'package:flutter/material.dart';

import '../detection/detector.dart';

// ── Per-model colours (used for step-2 visual debugging) ────────────────────
//
// Each model gets one distinctive hue so all of its boxes appear in that
// colour on screen — this makes it trivial to see, at a glance, that all 4
// models are firing. These will be replaced in step 5 by parent-category
// colours derived from the meta-classifier output.
const Color _haizadHue = Color(0xFFFF9800); // Orange
const Color _sabrinaHue = Color(0xFF00BCD4); // Cyan
const Color _hafiyHue = Color(0xFFE91E63); // Magenta/Pink
const Color _yasminHue = Color(0xFFFFEB3B); // Yellow

/// The four YOLOv8n models that make up the ensemble. Order matters for
/// logging clarity but is NOT semantic — the meta-classifier feature vector
/// is built by looking up each model's key, not by position in this list.
const List<HazardDetectorSpec> kEnsembleModelSpecs = [
  HazardDetectorSpec(
    key: 'haizad',
    assetPath: 'assets/models/haizad_model.tflite',
    classNames: [
      'Mossy Surface',         // 0
      'Overgrown Vegetation',  // 1
      'Protruding Fastener',   // 2
      'Rusted Equipment',      // 3
      'Waterlogged field',     // 4
    ],
    // 5 classes → 5 colour slots, all the same hue.
    classColors: [
      _haizadHue, _haizadHue, _haizadHue, _haizadHue, _haizadHue,
    ],
  ),
  HazardDetectorSpec(
    key: 'sabrina',
    assetPath: 'assets/models/sabrina_model.tflite',
    classNames: [
      'damaged_flooring',      // 0
      'fallen_branch',         // 1
      'overflowing_trash',     // 2
      'uncovered_drain',       // 3
      'water_accumulation',    // 4
    ],
    classColors: [
      _sabrinaHue, _sabrinaHue, _sabrinaHue, _sabrinaHue, _sabrinaHue,
    ],
  ),
  HazardDetectorSpec(
    key: 'hafiy',
    assetPath: 'assets/models/hafiy_model.tflite',
    classNames: [
      'open_drain',            // 0
      'overgrown_vegetation',  // 1
      'pothole',               // 2
      'sharp_object',          // 3
      'uneven_floor',          // 4
    ],
    classColors: [
      _hafiyHue, _hafiyHue, _hafiyHue, _hafiyHue, _hafiyHue,
    ],
  ),
  HazardDetectorSpec(
    key: 'yasmin',
    assetPath: 'assets/models/yasmin_model.tflite',
    classNames: [
      'broken_fence',          // 0
      'broken_lamppost',       // 1
      'broken_signboard',      // 2
      'fallen_branch',         // 3
      'obstacle_walkway',      // 4
    ],
    classColors: [
      _yasminHue, _yasminHue, _yasminHue, _yasminHue, _yasminHue,
    ],
  ),
];
