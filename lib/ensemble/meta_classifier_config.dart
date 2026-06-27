// =============================================================================
// MetaClassifierConfig
// -----------------------------------------------------------------------------
// Loads and validates `assets/models/meta_classifier_config.json`, which is the
// "schema" that ties together the 4 YOLO models and the 2 meta-classifier
// TFLite models in this project.
//
// Why a typed wrapper instead of a raw Map<String, dynamic>?
//   - The order of the lists in this file is load-bearing: the index in
//     `specific_classes` matches the softmax index of the specific meta-classifier
//     model, the index in `parent_classes` matches the parent meta-classifier's
//     softmax index, `onehot_categories` defines the order of the one-hot tail
//     of the meta-classifier input vector, and `feature_order` defines the order
//     of the 7 numeric features that come BEFORE the one-hot tail.
//   - Wrapping it in a class lets us assert (`assert(...)`) the expected sizes
//     once at load time, instead of silently producing nonsense later when an
//     index is off by one.
//   - It also documents the contract at the type level for the rest of the
//     pipeline (`expectedFeatureVectorLength`, lookup helpers, etc.).
// =============================================================================

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Asset path of the JSON file. Bundled by the `assets/models/` line in
/// `pubspec.yaml`, so it is mmap-readable on the device once the APK is built.
const String kMetaClassifierConfigAsset =
    'assets/models/meta_classifier_config.json';

/// Typed view of `meta_classifier_config.json`.
///
/// All fields are immutable lists of strings. Use [loadFromAsset] to construct
/// — never call the const constructor directly outside of tests.
class MetaClassifierConfig {
  /// Ordered list of the 17 class names produced by
  /// `meta_classifier_specific.tflite`. Index N in this list == softmax index N
  /// in the model's output tensor.
  final List<String> specificClasses;

  /// Ordered list of the 4 parent-category names produced by
  /// `meta_classifier_parent.tflite`. Index N == softmax index N.
  final List<String> parentClasses;

  /// Ordered list of 17 normalised label names defining the one-hot encoding
  /// used for the *input* to both meta-classifiers. Index N here is the
  /// position in the one-hot tail of the input feature vector.
  ///
  /// In this project this list happens to equal [specificClasses], but they
  /// are conceptually distinct (one drives the output, the other drives the
  /// input encoding) and we keep them separate so the pipeline stays correct
  /// if the meta-classifier is retrained with a different one-hot scheme.
  final List<String> onehotCategories;

  /// Ordered list of the 7 numeric feature names that come BEFORE the one-hot
  /// tail in the meta-classifier input vector. Currently:
  ///   [Haizad_confidence, Sabrina_confidence, Hafiy_confidence,
  ///    Yasmin_confidence, num_models_agreeing, max_confidence, avg_confidence]
  final List<String> featureOrder;

  const MetaClassifierConfig({
    required this.specificClasses,
    required this.parentClasses,
    required this.onehotCategories,
    required this.featureOrder,
  });

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  /// Reads the JSON file from the app bundle, parses it, and returns a typed
  /// config. Throws [FormatException] if a required key is missing or if the
  /// list lengths violate the expected invariants. This is intentional: a
  /// silent failure here would corrupt every downstream prediction.
  static Future<MetaClassifierConfig> loadFromAsset({
    String assetPath = kMetaClassifierConfigAsset,
  }) async {
    // rootBundle is Flutter's read-only access to files declared in
    // pubspec.yaml under `assets:`. It is mmap-backed on Android, so this
    // does NOT copy the file into memory more than once.
    final String raw = await rootBundle.loadString(assetPath);
    final Map<String, dynamic> json =
        jsonDecode(raw) as Map<String, dynamic>;

    final config = MetaClassifierConfig(
      specificClasses: _stringList(json, 'specific_classes'),
      parentClasses: _stringList(json, 'parent_classes'),
      onehotCategories: _stringList(json, 'onehot_categories'),
      featureOrder: _stringList(json, 'feature_order'),
    );

    config._validate();
    return config;
  }

  /// Helper: extract a `List<String>` from the parsed JSON map and throw a
  /// descriptive [FormatException] if the field is missing or of the wrong
  /// shape.
  static List<String> _stringList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! List) {
      throw FormatException(
        'meta_classifier_config.json: expected list at key "$key", got '
        '${value.runtimeType}',
      );
    }
    return List<String>.unmodifiable(value.map((e) => e.toString()));
  }

  /// Sanity-check the structural invariants the rest of the pipeline relies on.
  /// Throws [FormatException] when violated.
  void _validate() {
    if (specificClasses.isEmpty) {
      throw const FormatException('specific_classes is empty');
    }
    if (parentClasses.isEmpty) {
      throw const FormatException('parent_classes is empty');
    }
    if (onehotCategories.isEmpty) {
      throw const FormatException('onehot_categories is empty');
    }
    if (featureOrder.length != 7) {
      // The meta-classifier was trained on a fixed-shape feature vector. If
      // this ever drifts, the model would still happily multiply matrices
      // with the wrong data — making the failure silent. Fail loud instead.
      throw FormatException(
        'feature_order must contain exactly 7 entries '
        '(got ${featureOrder.length})',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Convenience accessors
  // ---------------------------------------------------------------------------

  /// Total length of the meta-classifier input feature vector =
  /// 7 numeric features + N one-hot slots, where N = onehotCategories.length.
  /// For the current config this is 7 + 17 = 24.
  int get expectedFeatureVectorLength =>
      featureOrder.length + onehotCategories.length;

  /// Returns the index of [normalisedLabel] within [onehotCategories], or `-1`
  /// when the label is not in the encoding scheme. Used when building the
  /// one-hot tail of the feature vector.
  int onehotIndexOf(String normalisedLabel) =>
      onehotCategories.indexOf(normalisedLabel);

  // ---------------------------------------------------------------------------
  // Diagnostics
  // ---------------------------------------------------------------------------

  /// Human-readable dump used by `main.dart` at startup to confirm the file
  /// parsed correctly. Kept in this class (rather than the call site) so the
  /// formatting can evolve alongside the schema.
  String prettyPrint() {
    final buf = StringBuffer()
      ..writeln('==== MetaClassifierConfig ====')
      ..writeln(
        'specific_classes (${specificClasses.length}): $specificClasses',
      )
      ..writeln(
        'parent_classes   (${parentClasses.length}): $parentClasses',
      )
      ..writeln(
        'onehot_categories(${onehotCategories.length}): $onehotCategories',
      )
      ..writeln('feature_order    (${featureOrder.length}): $featureOrder')
      ..writeln(
        'expected meta-classifier input length = '
        '$expectedFeatureVectorLength',
      )
      ..writeln('==============================');
    return buf.toString();
  }

  @override
  String toString() => prettyPrint();
}
