// =============================================================================
// MatchGroup
// -----------------------------------------------------------------------------
// One physical hazard, as agreed (or seen by a single model) across the
// ensemble. Members are HarmonisedDetections — at most one per source model.
//
// Why "at most one per model"?
//   Within a single YOLO model, NMS has already removed overlapping boxes of
//   the same class. The cross-model matcher only groups boxes from DIFFERENT
//   models (per the assignment spec), so a group can contain at most
//   `numModels` (=4) members. A size-1 group is a "loner" — only one model
//   noticed this hazard.
//
// What this class deliberately does NOT do:
//   - Pick a canonical label or parent. That decision (highest-confidence
//     member wins) is made on demand via `representative`. The meta-classifier
//     then refines/overrides it in step 4.
//   - Build the meta-classifier feature vector. That lives in step 4.
// =============================================================================

import 'package:flutter/material.dart';

import 'harmonised_detection.dart';

class MatchGroup {
  /// Members of this group. Guaranteed: at least 1 member; at most one entry
  /// per `sourceModel`. Ordered by descending confidence (matcher establishes
  /// this so `members.first` is always the representative).
  final List<HarmonisedDetection> members;

  MatchGroup({required this.members}) : assert(members.isNotEmpty);

  // ── Group-level summaries ────────────────────────────────────────────────

  /// Number of distinct source models that voted in this group.
  /// (Equivalent to `members.length` because the matcher enforces uniqueness.)
  int get size => members.length;

  /// True when more than one model contributed — the "agreement" case the
  /// meta-classifier benefits from most.
  bool get isMultiModel => members.length > 1;

  /// Set of source-model keys that contributed (e.g. {'haizad', 'hafiy'}).
  /// Used as a fast lookup when building the meta-classifier feature vector.
  Set<String> get sourceModels =>
      members.map((m) => m.sourceModel).toSet();

  /// Highest-confidence member. Used as the "voice" of the group:
  ///   - its normalisedLabel becomes the one-hot input to the meta-classifier
  ///   - its color is the temporary box colour in step-3 visualisation
  HarmonisedDetection get representative => members.first;

  // ── Geometry ─────────────────────────────────────────────────────────────

  /// The smallest axis-aligned rectangle enclosing every member's box.
  /// Wider than any single member's box — useful for rendering because it
  /// communicates "the ensemble agrees the hazard is somewhere in here".
  Rect get unionBoundingBox {
    double l = members.first.boundingBox.left;
    double t = members.first.boundingBox.top;
    double r = members.first.boundingBox.right;
    double b = members.first.boundingBox.bottom;
    for (final m in members.skip(1)) {
      if (m.boundingBox.left < l) l = m.boundingBox.left;
      if (m.boundingBox.top < t) t = m.boundingBox.top;
      if (m.boundingBox.right > r) r = m.boundingBox.right;
      if (m.boundingBox.bottom > b) b = m.boundingBox.bottom;
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  // ── Stats used by step 4 (feature-vector construction) ──────────────────

  /// Highest confidence among all members.
  double get maxConfidence {
    double m = members.first.confidence;
    for (final det in members.skip(1)) {
      if (det.confidence > m) m = det.confidence;
    }
    return m;
  }

  /// Mean confidence across members.
  double get avgConfidence {
    double sum = 0;
    for (final det in members) {
      sum += det.confidence;
    }
    return sum / members.length;
  }

  /// Map from sourceModel key → that model's confidence in this group, or 0
  /// when the model did not contribute. Used directly when building the
  /// 4 per-model confidence slots of the meta-classifier feature vector.
  double confidenceFor(String modelKey) {
    for (final det in members) {
      if (det.sourceModel == modelKey) return det.confidence;
    }
    return 0.0;
  }

  // ── Debug ────────────────────────────────────────────────────────────────

  /// One-line summary used in EnsembleDetector debug logs.
  String summary() {
    final votes = members
        .map((m) =>
            '${m.sourceModel}:${m.normalisedLabel}@${(m.confidence * 100).toStringAsFixed(0)}%')
        .join(', ');
    return 'MatchGroup(size=$size) [$votes]';
  }
}
