// =============================================================================
// CrossModelMatcher
// -----------------------------------------------------------------------------
// Groups harmonised detections that come from DIFFERENT YOLO models and that
// overlap geometrically (IoU >= kIouThreshold). Detections from the SAME
// model are never merged with each other — the assignment spec is explicit
// about this, and it matches how the meta-classifier was trained.
//
// Algorithm (greedy, confidence-anchored):
//   1. Sort all detections by confidence DESCENDING.
//   2. Walk the sorted list. The first unassigned detection becomes the
//      "seed" of a new group.
//   3. For each later unassigned detection whose sourceModel is NOT already
//      in the group, compute IoU with the SEED only.
//        - If IoU >= threshold, add it to the group and mark it assigned.
//   4. Continue until all detections are assigned.
//
// Why IoU-with-seed-only (instead of IoU with any group member)?
//   Seed-only is slightly under-grouping but more predictable. It avoids
//   "chaining" (A overlaps B 0.35, B overlaps C 0.35, but A and C do not
//   actually overlap at all). The cost of mistakenly under-grouping is small:
//   the meta-classifier will simply receive two singleton feature vectors
//   instead of one merged one, and each can still be correctly classified
//   from its own per-model confidence.
//
// Complexity: O(n²) IoU computations, where n = total raw detections per
// frame. Typically n < 20 across all 4 models, so this is trivially fast
// compared to even one YOLO inference pass.
// =============================================================================

import 'package:flutter/material.dart';

import 'harmonised_detection.dart';
import 'match_group.dart';

class CrossModelMatcher {
  CrossModelMatcher._();

  /// IoU threshold above which two boxes from different models are
  /// considered to be looking at the same physical hazard. The assignment
  /// specifies 0.3 — looser than typical NMS (0.45–0.5) because the four
  /// models were trained independently and tend to put boxes in slightly
  /// different places for the same object.
  static const double kIouThreshold = 0.3;

  /// Returns one [MatchGroup] per physical detection. Each input detection
  /// appears in exactly one returned group.
  static List<MatchGroup> match(List<HarmonisedDetection> detections) {
    if (detections.isEmpty) return const [];

    // Sort descending by confidence so the most reliable box is always the
    // seed of any group it's in.
    final sorted = List<HarmonisedDetection>.of(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final List<bool> assigned = List<bool>.filled(sorted.length, false);
    final List<MatchGroup> groups = [];

    for (int i = 0; i < sorted.length; i++) {
      if (assigned[i]) continue;

      final seed = sorted[i];
      assigned[i] = true;

      // Members start with just the seed; we add at most one detection per
      // OTHER source model below.
      final groupMembers = <HarmonisedDetection>[seed];
      final groupModels = <String>{seed.sourceModel};

      for (int j = i + 1; j < sorted.length; j++) {
        if (assigned[j]) continue;
        final cand = sorted[j];

        // Skip if this model has already contributed to the group — keeps
        // the group's "at most one per model" invariant.
        if (groupModels.contains(cand.sourceModel)) continue;

        if (_iou(seed.boundingBox, cand.boundingBox) >= kIouThreshold) {
          groupMembers.add(cand);
          groupModels.add(cand.sourceModel);
          assigned[j] = true;
        }
      }

      groups.add(MatchGroup(members: groupMembers));
    }
    return groups;
  }

  /// Standard axis-aligned IoU = intersection_area / union_area.
  /// Returns 0 when the boxes do not intersect.
  static double _iou(Rect a, Rect b) {
    final double interLeft = a.left > b.left ? a.left : b.left;
    final double interTop = a.top > b.top ? a.top : b.top;
    final double interRight = a.right < b.right ? a.right : b.right;
    final double interBottom = a.bottom < b.bottom ? a.bottom : b.bottom;

    final double interW = interRight - interLeft;
    final double interH = interBottom - interTop;
    if (interW <= 0 || interH <= 0) return 0.0;

    final double interArea = interW * interH;
    final double aArea = (a.right - a.left) * (a.bottom - a.top);
    final double bArea = (b.right - b.left) * (b.bottom - b.top);

    return interArea / (aArea + bArea - interArea);
  }
}
