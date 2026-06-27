import 'package:flutter/material.dart';
import 'detection_result.dart';

/// Converts raw YOLOv8 TFLite output tensors into [DetectionResult] objects.
///
/// ── YOLOv8 TFLite output format ───────────────────────────────────────────
/// Shape  : [9, 8400]   (after stripping the batch dimension)
/// Row 0  : cx  — box centre-x, normalised [0, 1]
/// Row 1  : cy  — box centre-y, normalised [0, 1]
/// Row 2  : w   — box width,  normalised [0, 1]
/// Row 3  : h   — box height, normalised [0, 1]
/// Row 4–8: per-class confidence scores (one per hazard class)
///
/// The 8400 columns come from three detection scales:
///   640/8  × 640/8  = 6400 anchors  (large objects)
///   640/16 × 640/16 = 1600 anchors  (medium objects)
///   640/32 × 640/32 =  400 anchors  (small objects)
/// ──────────────────────────────────────────────────────────────────────────
class YoloProcessor {
  YoloProcessor._(); // not instantiable — all methods are static

  /// Processes the raw output and returns filtered, NMS-reduced detections.
  ///
  /// [rawOutput] has shape [9][8400] (batch dimension already stripped).
  /// [sourceModel] is stamped onto every returned [DetectionResult] so the
  /// ensemble pipeline can later tell which model produced which box during
  /// cross-model IoU matching.
  static List<DetectionResult> process(
    List<List<double>> rawOutput, {
    required List<String> classNames,
    required List<Color> classColors,
    required double confidenceThreshold,
    required String sourceModel,
  }) {
    final int numAnchors = rawOutput[0].length; // 8400
    final int numClasses = classNames.length;   // 5

    final List<_RawDetection> candidates = [];

    for (int i = 0; i < numAnchors; i++) {
      // Find the class with the highest confidence for this anchor point.
      double maxScore = 0.0;
      int bestClass = 0;

      for (int c = 0; c < numClasses; c++) {
        // Class scores start at row index 4 (after cx, cy, w, h).
        final double score = rawOutput[4 + c][i];
        if (score > maxScore) {
          maxScore = score;
          bestClass = c;
        }
      }

      // Discard anchors below the confidence threshold (typically 0.5).
      if (maxScore < confidenceThreshold) continue;

      // Convert centre-format (cx, cy, w, h) to corner-format (x1, y1, x2, y2).
      final double cx = rawOutput[0][i];
      final double cy = rawOutput[1][i];
      final double w  = rawOutput[2][i];
      final double h  = rawOutput[3][i];

      candidates.add(_RawDetection(
        classIndex: bestClass,
        confidence: maxScore,
        left:   cx - w / 2,
        top:    cy - h / 2,
        right:  cx + w / 2,
        bottom: cy + h / 2,
      ));
    }

    // Remove overlapping boxes for the same class using Greedy NMS.
    final List<_RawDetection> kept = _nonMaxSuppression(
      candidates,
      iouThreshold: 0.45,
    );

    // Map filtered raw detections to the public DetectionResult type.
    return kept.map((det) {
      return DetectionResult(
        classIndex: det.classIndex,
        className:  classNames[det.classIndex],
        confidence: det.confidence,
        // Clamp to [0,1] in case the model predicts slightly out-of-bounds boxes.
        boundingBox: Rect.fromLTRB(
          det.left.clamp(0.0, 1.0),
          det.top.clamp(0.0, 1.0),
          det.right.clamp(0.0, 1.0),
          det.bottom.clamp(0.0, 1.0),
        ),
        color: classColors[det.classIndex],
        sourceModel: sourceModel,
      );
    }).toList();
  }

  // ── Non-Maximum Suppression ────────────────────────────────────────────────

  /// Greedy NMS: keeps the highest-confidence box and suppresses any other
  /// box of the *same class* whose IoU with it exceeds [iouThreshold].
  static List<_RawDetection> _nonMaxSuppression(
    List<_RawDetection> boxes, {
    double iouThreshold = 0.45,
  }) {
    // Sort by confidence descending so the best box is always picked first.
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));

    final List<_RawDetection> result = [];
    final List<bool> suppressed = List.filled(boxes.length, false);

    for (int i = 0; i < boxes.length; i++) {
      if (suppressed[i]) continue;
      result.add(boxes[i]);

      for (int j = i + 1; j < boxes.length; j++) {
        if (suppressed[j]) continue;
        // Only suppress boxes that share the same class label.
        if (boxes[j].classIndex != boxes[i].classIndex) continue;
        if (_intersectionOverUnion(boxes[i], boxes[j]) > iouThreshold) {
          suppressed[j] = true;
        }
      }
    }
    return result;
  }

  /// Computes the Intersection-over-Union ratio between two bounding boxes.
  static double _intersectionOverUnion(_RawDetection a, _RawDetection b) {
    final double interLeft   = a.left   > b.left   ? a.left   : b.left;
    final double interTop    = a.top    > b.top    ? a.top    : b.top;
    final double interRight  = a.right  < b.right  ? a.right  : b.right;
    final double interBottom = a.bottom < b.bottom ? a.bottom : b.bottom;

    final double interW = interRight  - interLeft;
    final double interH = interBottom - interTop;
    if (interW <= 0 || interH <= 0) return 0.0;

    final double interArea = interW * interH;
    final double aArea = (a.right - a.left) * (a.bottom - a.top);
    final double bArea = (b.right - b.left) * (b.bottom - b.top);

    return interArea / (aArea + bArea - interArea);
  }
}

// ── Internal data class ──────────────────────────────────────────────────────

/// Intermediate representation used only inside [YoloProcessor].
class _RawDetection {
  final int classIndex;
  final double confidence;
  final double left, top, right, bottom;

  const _RawDetection({
    required this.classIndex,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
}
