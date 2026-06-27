// =============================================================================
// ParentCategoryPalette
// -----------------------------------------------------------------------------
// Centralised colour + short-label assignment for the 4 parent hazard
// categories. Used by the overlay (bounding box + badge) and will be reused
// by the history screen in step 6, so changing the colour scheme in one
// place updates the whole app.
//
// Colour choices are semantic and high-contrast:
//   - Surface/Ground Hazard   → blue   (water / ground association)
//   - Obstruction Hazard      → orange (warning / blocking the path)
//   - Structural/Injury Hazard → red    (danger / injury)
//   - Hygiene Hazard          → yellow (waste / caution)
//
// If `meta_classifier_config.json` ever gains a new parent category, the
// lookup defaults to neutral grey + the raw label rather than crashing — the
// app will still render, just without the proper visual coding, so the bug
// is visible to the developer without breaking the live demo.
// =============================================================================

import 'package:flutter/material.dart';

class ParentCategoryPalette {
  ParentCategoryPalette._();

  static const Color _surfaceGround = Color(0xFF2196F3); // blue
  static const Color _obstruction = Color(0xFFFF9800); // orange
  static const Color _structuralInjury = Color(0xFFF44336); // red
  static const Color _hygiene = Color(0xFFFFC107); // amber — more saturated
                                                   // than #FFEB3B yellow, holds
                                                   // up better against bright
                                                   // outdoor backgrounds.

  /// Lookup: parent label → display colour.
  /// Keys MUST match `parent_classes` in meta_classifier_config.json
  /// (case- and punctuation-sensitive).
  static const Map<String, Color> _colorByParent = {
    'Surface/Ground Hazard': _surfaceGround,
    'Obstruction Hazard': _obstruction,
    'Structural/Injury Hazard': _structuralInjury,
    'Hygiene Hazard': _hygiene,
  };

  /// Lookup: parent label → short label suitable for a small badge.
  /// Trims "Hazard"/"Injury" so the badge stays compact at small text sizes.
  static const Map<String, String> _shortByParent = {
    'Surface/Ground Hazard': 'GROUND',
    'Obstruction Hazard': 'OBSTRUCTION',
    'Structural/Injury Hazard': 'STRUCTURAL',
    'Hygiene Hazard': 'HYGIENE',
  };

  /// Returns the colour for [parentLabel], or a neutral grey when unknown.
  /// Unknown labels indicate a config drift; the grey is intentionally
  /// drab so it stands out visually as "something is wrong".
  static Color colorFor(String parentLabel) =>
      _colorByParent[parentLabel] ?? Colors.grey;

  /// Returns the short badge text for [parentLabel], or the raw label if
  /// unknown (so the developer at least sees the value being misassigned).
  static String shortLabel(String parentLabel) =>
      _shortByParent[parentLabel] ?? parentLabel.toUpperCase();
}
