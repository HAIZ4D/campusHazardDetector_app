// =============================================================================
// DisplayRules
// -----------------------------------------------------------------------------
// Single source of truth for presentation rules that need to be IDENTICAL
// between the live overlay (CustomPainter) and the saved-records history
// card (widget tree). Both consult this helper so they can't drift apart.
//
// Currently:
//   - kSpecificFallbackThreshold: the specific-confidence threshold below
//     which we display the PARENT category as the main label with a
//     "GENERAL:" prefix instead of the specific label.
//   - resolveMainLabel(): given the four meta-classifier numbers, returns
//     (mainText, isGeneralFallback) so the caller knows whether to apply
//     the fallback visual treatment.
// =============================================================================

/// Specific-confidence threshold below which we fall back to displaying the
/// parent category as the main label. 0.5 per the assignment spec.
const double kSpecificFallbackThreshold = 0.5;

/// What to render as the main label and whether it's a fallback.
class MainLabelDecision {
  final String text;

  /// True when [text] is the parent fallback (specific conf was below the
  /// threshold). Callers use this to apply a distinct visual treatment so
  /// fallback detections are recognisable at a glance.
  final bool isGeneralFallback;

  const MainLabelDecision({
    required this.text,
    required this.isGeneralFallback,
  });
}

class DisplayRules {
  DisplayRules._();

  /// Decide what the main label should say. Pure function — fully driven by
  /// the four meta-classifier numbers, no widget/canvas state involved.
  static MainLabelDecision resolveMainLabel({
    required String specificLabel,
    required double specificConfidence,
    required String parentLabel,
    required double parentConfidence,
  }) {
    if (specificConfidence < kSpecificFallbackThreshold) {
      return MainLabelDecision(
        text: 'GENERAL: $parentLabel  '
            '${(parentConfidence * 100).toStringAsFixed(0)}%',
        isGeneralFallback: true,
      );
    }
    return MainLabelDecision(
      text: '$specificLabel  '
          '${(specificConfidence * 100).toStringAsFixed(0)}%',
      isGeneralFallback: false,
    );
  }
}
