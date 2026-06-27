// =============================================================================
// BoundingBoxOverlay
// -----------------------------------------------------------------------------
// Draws the meta-classifier's final verdict over the camera preview, one
// rectangle per [ClassifiedDetection].
//
// Display rule (per assignment spec):
//   - Main label:
//       * If the SPECIFIC classifier's confidence ≥ kSpecificFallbackThreshold,
//         show the specific label + its confidence.
//       * Otherwise FALL BACK to the parent label, prefixed with "GENERAL:"
//         to make the lower-confidence/coarser nature visible at a glance.
//   - Parent badge:
//       * Always shown, regardless of fallback. A small coloured pill next
//         to the main label, colour-coded per parent category via
//         ParentCategoryPalette.
//   - Bounding box stroke colour:
//       * Also driven by parent category, so a quick glance tells the user
//         which family of hazard this is even before reading any text.
//
// The overlay fills whatever space its parent gives it (use Positioned.fill
// or SizedBox.expand). Bounding box coords are normalised to [0,1] and are
// simply scaled by the canvas Size at paint time.
// =============================================================================

import 'package:flutter/material.dart';

import '../ensemble/classified_detection.dart';
import 'display_rules.dart';
import 'parent_category_palette.dart';

class BoundingBoxOverlay extends StatelessWidget {
  final List<ClassifiedDetection> detections;

  const BoundingBoxOverlay({
    super.key,
    required this.detections,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BoundingBoxPainter(detections: detections),
    );
  }
}

// ── Painter ──────────────────────────────────────────────────────────────────

class _BoundingBoxPainter extends CustomPainter {
  final List<ClassifiedDetection> detections;

  _BoundingBoxPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in detections) {
      // ── Geometry: scale normalised [0,1] coords to canvas pixels ────────
      final unionBox = c.group.unionBoundingBox;
      final Rect rect = Rect.fromLTRB(
        unionBox.left * size.width,
        unionBox.top * size.height,
        unionBox.right * size.width,
        unionBox.bottom * size.height,
      );

      // ── Colour & label resolution ──────────────────────────────────────
      final Color parentColor =
          ParentCategoryPalette.colorFor(c.meta.parentLabel);
      final String shortParent =
          ParentCategoryPalette.shortLabel(c.meta.parentLabel);

      // Apply the shared specific-vs-parent fallback rule. The history
      // card consults the same helper so the two surfaces can't drift.
      final decision = DisplayRules.resolveMainLabel(
        specificLabel: c.meta.specificLabel,
        specificConfidence: c.meta.specificConfidence,
        parentLabel: c.meta.parentLabel,
        parentConfidence: c.meta.parentConfidence,
      );
      final bool isGeneralFallback = decision.isGeneralFallback;
      final String mainLabel = decision.text;

      // ── Draw ───────────────────────────────────────────────────────────
      _drawBox(canvas, rect, parentColor);
      _drawLabelRow(
        canvas: canvas,
        rect: rect,
        canvasSize: size,
        mainLabel: mainLabel,
        badgeText: shortParent,
        badgeColor: parentColor,
        isGeneralFallback: isGeneralFallback,
      );
    }
  }

  /// Coloured rectangular border around the union of all matched boxes.
  void _drawBox(Canvas canvas, Rect rect, Color color) {
    final Paint boxPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRect(rect, boxPaint);
  }

  /// Paints "[main label][parent badge]" as a single horizontal row, placed
  /// just above the box (or just inside the top edge if too close to the
  /// canvas top).
  void _drawLabelRow({
    required Canvas canvas,
    required Rect rect,
    required Size canvasSize,
    required String mainLabel,
    required String badgeText,
    required Color badgeColor,
    required bool isGeneralFallback,
  }) {
    // ── Main label: white text on dark (or amber for fallback) bg ────────
    final Color mainBg = isGeneralFallback
        // Distinct background tint so even peripheral vision picks up that
        // this label is a low-confidence fallback rather than a confident
        // specific identification.
        ? const Color(0xCC8D6E63) // semi-transparent brown/amber
        : const Color(0xCC000000); // semi-transparent black

    final TextPainter mainTp = _buildTextPainter(
      text: mainLabel,
      color: Colors.white,
      fontSize: 12.0,
      weight: FontWeight.w600,
    );

    // ── Badge: white text on parent-category-coloured pill ───────────────
    // Black text when the badge background is yellow (poor contrast on
    // white); white otherwise.
    final Color badgeFg =
        badgeColor.computeLuminance() > 0.6 ? Colors.black : Colors.white;
    final TextPainter badgeTp = _buildTextPainter(
      text: badgeText,
      color: badgeFg,
      fontSize: 10.0,
      weight: FontWeight.w700,
    );

    // Horizontal padding around each text block.
    const double pad = 4.0;
    final double mainW = mainTp.width + pad * 2;
    final double mainH = mainTp.height + pad;
    final double badgeW = badgeTp.width + pad * 2;
    final double badgeH = badgeTp.height + pad;
    final double rowH = mainH > badgeH ? mainH : badgeH;

    // Position above the box, or inside the top edge if too close to canvas top.
    final double topY = rect.top - rowH - 2 >= 0
        ? rect.top - rowH - 2
        : rect.top + 2;
    final double leftX = rect.left;

    // ── Paint main label ─────────────────────────────────────────────────
    final Rect mainRect = Rect.fromLTWH(leftX, topY, mainW, rowH);
    canvas.drawRect(mainRect, Paint()..color = mainBg);
    mainTp.paint(
      canvas,
      Offset(leftX + pad, topY + (rowH - mainTp.height) / 2),
    );

    // ── Paint badge (right of main label) ────────────────────────────────
    final double badgeLeft = leftX + mainW + 2;
    // Clamp so badge doesn't run off the right edge.
    final double maxLeft = canvasSize.width - badgeW;
    final double clampedBadgeLeft =
        badgeLeft > maxLeft ? maxLeft : badgeLeft;
    final Rect badgeRect =
        Rect.fromLTWH(clampedBadgeLeft, topY, badgeW, rowH);

    // Rounded-rect "pill" for the badge to visually distinguish it from
    // the rectangular main label.
    final RRect badgeRRect =
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(4));
    canvas.drawRRect(badgeRRect, Paint()..color = badgeColor);
    badgeTp.paint(
      canvas,
      Offset(clampedBadgeLeft + pad, topY + (rowH - badgeTp.height) / 2),
    );
  }

  /// Helper: build a laid-out TextPainter for one text run.
  TextPainter _buildTextPainter({
    required String text,
    required Color color,
    required double fontSize,
    required FontWeight weight,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  /// Only repaint when the list of detections has actually changed.
  @override
  bool shouldRepaint(_BoundingBoxPainter oldDelegate) =>
      !identical(oldDelegate.detections, detections);
}
