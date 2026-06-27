// =============================================================================
// ClassifiedDetection
// -----------------------------------------------------------------------------
// The end-of-pipeline product, one per physical hazard on the current frame.
// Couples the raw YOLO evidence (the [MatchGroup] of harmonised detections)
// with the meta-classifier's refined verdict ([MetaClassifierOutput]).
//
// Why both?
//   - The [MatchGroup] holds geometry (union bounding box for rendering),
//     source-model attribution (for the step-6 history), and per-model
//     confidences (for the report).
//   - The [MetaClassifierOutput] is the *displayed* label and parent: the
//     meta-classifier is allowed to override the raw YOLO label (e.g.
//     "Pothole" + agreement → "Open/Uncovered Drain") and the UI must show
//     its verdict, not the raw majority vote.
// =============================================================================

import 'match_group.dart';
import 'meta_classifier_output.dart';

class ClassifiedDetection {
  final MatchGroup group;
  final MetaClassifierOutput meta;

  const ClassifiedDetection({
    required this.group,
    required this.meta,
  });
}
