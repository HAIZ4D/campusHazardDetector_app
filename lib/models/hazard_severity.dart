// =============================================================================
// HazardSeverity
// -----------------------------------------------------------------------------
// Coarse 3-level severity scale derived at capture time from:
//   - the meta-classifier's PARENT category (which family of hazard), and
//   - the meta-classifier's SPECIFIC confidence (how sure the model is).
//
// Rule (per assignment spec):
//   - Structural/Injury Hazard         → High
//   - Surface/Ground or Obstruction    → Medium
//   - Hygiene Hazard                   → Low
//   - Anything else / unknown parent   → Medium (conservative fallback)
// Then BUMP one level up if specificConfidence > 0.85, CAPPED at High.
//
// We deliberately picked the 3-level cap over a 4-level Low/Medium/High/
// Critical scale because the spec only enumerated three levels. If the rubric
// ever asks for Critical, this enum gains a fourth value and `_bumped`
// gains one more case — nothing else has to change.
// =============================================================================

enum HazardSeverity {
  low(displayName: 'Low'),
  medium(displayName: 'Medium'),
  high(displayName: 'High');

  final String displayName;
  const HazardSeverity({required this.displayName});

  /// Compute severity from the meta-classifier's parent label + specific
  /// confidence. Pure function — no state, fully driven by inputs.
  static HazardSeverity compute({
    required String parentLabel,
    required double specificConfidence,
  }) {
    final base = _baseFor(parentLabel);
    // Bump one level when the specific classifier is highly confident
    // (assignment spec threshold = 0.85). High already at the top, so the
    // cap inside _bumped keeps things sane.
    if (specificConfidence > 0.85) return _bumped(base);
    return base;
  }

  static HazardSeverity _baseFor(String parentLabel) {
    switch (parentLabel) {
      case 'Structural/Injury Hazard':
        return HazardSeverity.high;
      case 'Surface/Ground Hazard':
      case 'Obstruction Hazard':
        return HazardSeverity.medium;
      case 'Hygiene Hazard':
        return HazardSeverity.low;
      default:
        // Unknown parent — be conservative and treat as medium so the user
        // isn't lulled into ignoring a hazard the rule doesn't recognise.
        return HazardSeverity.medium;
    }
  }

  static HazardSeverity _bumped(HazardSeverity base) {
    switch (base) {
      case HazardSeverity.low:
        return HazardSeverity.medium;
      case HazardSeverity.medium:
        return HazardSeverity.high;
      case HazardSeverity.high:
        // Cap — already at top of the scale.
        return HazardSeverity.high;
    }
  }
}
