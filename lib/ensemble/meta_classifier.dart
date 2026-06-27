// =============================================================================
// MetaClassifier
// -----------------------------------------------------------------------------
// Owns the two small dense-NN TFLite models that turn a [MatchGroup] into a
// pair of refined labels:
//
//   feature vector (24)  ─┬──► meta_classifier_specific.tflite ─► [1, 17] softmax
//                         └──► meta_classifier_parent.tflite   ─► [1,  4] softmax
//
// The 24-D feature vector layout is driven entirely by `MetaClassifierConfig`
// (loaded from `assets/models/meta_classifier_config.json`), so re-training
// the meta-classifier with a different feature schema only requires updating
// the JSON file — not this code.
//
// Layout of the input vector:
//
//   [ feature_order[0]  ]  ── Haizad_confidence    \
//   [ feature_order[1]  ]  ── Sabrina_confidence    \
//   [ feature_order[2]  ]  ── Hafiy_confidence       |  7 numeric
//   [ feature_order[3]  ]  ── Yasmin_confidence      |  features
//   [ feature_order[4]  ]  ── num_models_agreeing    |
//   [ feature_order[5]  ]  ── max_confidence        /
//   [ feature_order[6]  ]  ── avg_confidence       /
//   [ 7  ..  7 + 17 - 1 ]  ── one-hot of representative's normalised label
//                              (indexed by onehot_categories order)
//
// Per the team's training notebook:
//   - avg_confidence = mean across FIRING models only (i.e. group members),
//     NOT mean across all 4 slots including zeros.
//   - The two output models have a softmax layer baked into their head, so
//     we read the top-1 softmax value directly as confidence — no manual
//     softmax in Dart.
// =============================================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'match_group.dart';
import 'meta_classifier_config.dart';
import 'meta_classifier_output.dart';

class MetaClassifier {
  /// Asset paths — kept here rather than in a separate constants file because
  /// these two models are tightly coupled to this class.
  static const String _specificAsset =
      'assets/models/meta_classifier_specific.tflite';
  static const String _parentAsset =
      'assets/models/meta_classifier_parent.tflite';

  /// Loaded once and shared. The matching feature_order / onehot_categories
  /// drive every per-frame feature-vector build.
  final MetaClassifierConfig config;

  Interpreter? _specific;
  Interpreter? _parent;

  /// One-shot guard: print the model output sum on the first frame so we can
  /// confirm at runtime that the model really does emit softmax-normalised
  /// probabilities (sum ≈ 1.0). Trips off after the first prediction.
  bool _firstPredictionLogged = false;

  MetaClassifier({required this.config});

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> loadModels() async {
    _specific = await Interpreter.fromAsset(_specificAsset);
    _parent = await Interpreter.fromAsset(_parentAsset);

    final sIn = _specific!.getInputTensor(0);
    final sOut = _specific!.getOutputTensor(0);
    final pIn = _parent!.getInputTensor(0);
    final pOut = _parent!.getOutputTensor(0);
    debugPrint(
      '[MetaClassifier:specific] '
      'In ${sIn.shape} ${sIn.type}   Out ${sOut.shape} ${sOut.type}',
    );
    debugPrint(
      '[MetaClassifier:parent]   '
      'In ${pIn.shape} ${pIn.type}   Out ${pOut.shape} ${pOut.type}',
    );

    // Hard fail if any shape contradicts the config — better to surface this
    // at startup than silently mis-predict for the next hour.
    _assertShapeMatches('specific input', sIn.shape,
        [1, config.expectedFeatureVectorLength]);
    _assertShapeMatches('specific output', sOut.shape,
        [1, config.specificClasses.length]);
    _assertShapeMatches('parent input', pIn.shape,
        [1, config.expectedFeatureVectorLength]);
    _assertShapeMatches('parent output', pOut.shape,
        [1, config.parentClasses.length]);
  }

  static void _assertShapeMatches(
      String which, List<int> actual, List<int> expected) {
    if (actual.length != expected.length ||
        !List.generate(actual.length, (i) => actual[i] == expected[i])
            .every((b) => b)) {
      throw StateError(
        'MetaClassifier $which shape $actual does not match expected '
        '$expected (driven by meta_classifier_config.json). The TFLite '
        'model and the config JSON are out of sync.',
      );
    }
  }

  void dispose() {
    _specific?.close();
    _parent?.close();
    _specific = null;
    _parent = null;
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  /// Runs both meta-classifier models on the feature vector derived from
  /// [group], and returns their combined top-1 verdict.
  MetaClassifierOutput predict(MatchGroup group) {
    if (_specific == null || _parent == null) {
      throw StateError('MetaClassifier.loadModels() not awaited before predict().');
    }

    // ── Build the 24-D feature vector ──────────────────────────────────────
    final Float32List input = buildFeatureVector(group);

    // ── Run the specific classifier (17-way) ───────────────────────────────
    final specificOut = List<List<double>>.generate(
      1,
      (_) => List<double>.filled(config.specificClasses.length, 0.0),
    );
    _specific!.run(input.buffer.asUint8List(), specificOut);
    final Float32List specificSoftmax = Float32List.fromList(specificOut[0]);

    // ── Run the parent classifier (4-way) ──────────────────────────────────
    final parentOut = List<List<double>>.generate(
      1,
      (_) => List<double>.filled(config.parentClasses.length, 0.0),
    );
    _parent!.run(input.buffer.asUint8List(), parentOut);
    final Float32List parentSoftmax = Float32List.fromList(parentOut[0]);

    // ── Top-1 + sanity-check probability sum on first frame ────────────────
    final (sIdx, sConf) = _argmax(specificSoftmax);
    final (pIdx, pConf) = _argmax(parentSoftmax);

    if (!_firstPredictionLogged) {
      _firstPredictionLogged = true;
      final sSum = specificSoftmax.fold<double>(0, (a, b) => a + b);
      final pSum = parentSoftmax.fold<double>(0, (a, b) => a + b);
      debugPrint(
        '[MetaClassifier] first prediction sanity check — '
        'specific sum=${sSum.toStringAsFixed(3)} '
        'parent sum=${pSum.toStringAsFixed(3)} '
        '(both should be ≈ 1.0 if softmax is baked in)',
      );
    }

    return MetaClassifierOutput(
      specificLabel: config.specificClasses[sIdx],
      specificConfidence: sConf,
      parentLabel: config.parentClasses[pIdx],
      parentConfidence: pConf,
      specificSoftmax: specificSoftmax,
      parentSoftmax: parentSoftmax,
    );
  }

  // ── Feature-vector construction ───────────────────────────────────────────

  /// Assembles the 24-D Float32 input for both meta-classifier models.
  /// Public so it can be unit-tested independently of the TFLite runtime.
  Float32List buildFeatureVector(MatchGroup group) {
    final vec = Float32List(config.expectedFeatureVectorLength);

    // ── Slots 0..6: numeric features (order = config.featureOrder) ─────────
    for (int i = 0; i < config.featureOrder.length; i++) {
      vec[i] = _resolveNumericFeature(config.featureOrder[i], group);
    }

    // ── Slots 7..23: one-hot of representative's normalised label ──────────
    // The representative is the highest-confidence member; its normalised
    // label is what we tell the meta-classifier "this group is about". The
    // meta-classifier is free to refine or override based on the numeric
    // features.
    final ohIdx = config.onehotIndexOf(group.representative.normalisedLabel);
    if (ohIdx >= 0) {
      vec[config.featureOrder.length + ohIdx] = 1.0;
    } else {
      // This means LabelHarmoniser produced a normalised label that isn't in
      // the config's onehot_categories — a contract violation between
      // label_harmoniser.dart and the JSON config.
      debugPrint(
        '[MetaClassifier] WARNING: representative label '
        '"${group.representative.normalisedLabel}" not in '
        'onehot_categories. The one-hot tail will be all zeros and the '
        'prediction will be unreliable.',
      );
    }

    return vec;
  }

  /// Maps a `feature_order` entry name to its value for this group.
  double _resolveNumericFeature(String name, MatchGroup group) {
    switch (name) {
      // The 4 per-model confidence slots. MatchGroup.confidenceFor returns
      // 0.0 when the named model did not contribute — exactly what the
      // meta-classifier was trained on.
      case 'Haizad_confidence':
        return group.confidenceFor('haizad');
      case 'Sabrina_confidence':
        return group.confidenceFor('sabrina');
      case 'Hafiy_confidence':
        return group.confidenceFor('hafiy');
      case 'Yasmin_confidence':
        return group.confidenceFor('yasmin');

      // Group-level summary stats. Per the training notebook,
      // avg_confidence is the mean over FIRING models only (= group members),
      // not the mean over all 4 confidence slots including zeros.
      case 'num_models_agreeing':
        return group.size.toDouble();
      case 'max_confidence':
        return group.maxConfidence;
      case 'avg_confidence':
        return group.avgConfidence;

      default:
        throw StateError(
          'Unknown feature_order entry "$name" in meta_classifier_config.json '
          '— add a case for it in MetaClassifier._resolveNumericFeature.',
        );
    }
  }

  /// Returns the (index, value) of the largest entry in [vec].
  static (int, double) _argmax(Float32List vec) {
    int bestIdx = 0;
    double bestVal = vec[0];
    for (int i = 1; i < vec.length; i++) {
      if (vec[i] > bestVal) {
        bestVal = vec[i];
        bestIdx = i;
      }
    }
    return (bestIdx, bestVal);
  }
}
