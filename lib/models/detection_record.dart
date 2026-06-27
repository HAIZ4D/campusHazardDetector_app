// =============================================================================
// DetectionRecord
// -----------------------------------------------------------------------------
// One evidence record, created when the user taps Capture. The schema mirrors
// the meta-classifier verdict + the YOLO provenance + the user-selected zone
// and a derived severity, so:
//   - the history screen can reproduce the live overlay exactly,
//   - the technical report can quote per-detection provenance, AND
//   - GeminiService has all 5 structured fields ready to feed into the prompt.
//
// Recommendation caching:
//   [recommendation] is mutable across copies via [copyWith]. The history
//   service replaces the record with a new instance once Gemini returns, so
//   subsequent views render from the cache without re-calling the API.
//
// Note on fallback labels:
//   The record stores RAW meta-classifier outputs (specific + parent label/
//   conf). The "show parent when specific < threshold" UI rule is applied at
//   render time (see widgets/display_rules.dart), not baked into the record.
// =============================================================================

import 'hazard_severity.dart';
import 'hazard_zone.dart';

class DetectionRecord {
  /// Unique identifier — generated from the capture timestamp in milliseconds.
  final String id;

  /// When the capture was taken.
  final DateTime timestamp;

  // ── Meta-classifier verdict ────────────────────────────────────────────────

  /// Top-1 label from `meta_classifier_specific.tflite` at capture time
  /// (e.g. "Pothole"). Empty string when no hazard was detected.
  final String specificLabel;

  /// Softmax probability of [specificLabel] (range [0.0, 1.0]).
  final double specificConfidence;

  /// Top-1 label from `meta_classifier_parent.tflite` at capture time
  /// (e.g. "Surface/Ground Hazard"). Empty string when no hazard was detected.
  final String parentLabel;

  /// Softmax probability of [parentLabel] (range [0.0, 1.0]).
  final double parentConfidence;

  // ── YOLO provenance ────────────────────────────────────────────────────────

  /// Map: source-model key → that model's raw YOLO confidence in this group.
  /// Contains ONLY firing models (no zero entries), in canonical model order
  /// (haizad, sabrina, hafiy, yasmin). Empty when no hazard was detected.
  final Map<String, double> perModelConfidences;

  // ── Context for the Gemini recommendation ──────────────────────────────────

  /// Location zone selected by the user before pressing capture.
  /// Defaults to [HazardZone.unspecified] when the user hasn't picked one.
  final HazardZone zone;

  /// Severity bucket derived at capture time via [HazardSeverity.compute].
  /// Stored (not re-derived on read) so the displayed severity matches what
  /// was sent to Gemini even if the rule changes in a future version.
  final HazardSeverity severity;

  /// Cached Gemini recommendation text. `null` until the user has tapped
  /// "Get Recommendation" and the API has returned successfully.
  final String? recommendation;

  /// Absolute path to the JPEG file saved in the app's documents directory.
  final String imagePath;

  const DetectionRecord({
    required this.id,
    required this.timestamp,
    required this.specificLabel,
    required this.specificConfidence,
    required this.parentLabel,
    required this.parentConfidence,
    required this.perModelConfidences,
    required this.zone,
    required this.severity,
    required this.imagePath,
    this.recommendation,
  });

  // ── Derived ───────────────────────────────────────────────────────────────

  /// Number of YOLO models that contributed (1–4); 0 when no hazard.
  int get numModelsAgreeing => perModelConfidences.length;

  /// True when more than one model contributed — the meta-classifier gained
  /// the most signal from cross-model evidence in these cases.
  bool get isMultiModelAgreement => numModelsAgreeing > 1;

  /// True when at least one YOLO model fired (i.e. this record represents an
  /// actual detection, not a "captured but nothing seen" snapshot).
  bool get hasHazard => numModelsAgreeing > 0;

  /// True when a Gemini recommendation has been fetched and cached.
  bool get hasRecommendation =>
      recommendation != null && recommendation!.isNotEmpty;

  // ── Immutable update ──────────────────────────────────────────────────────

  /// Returns a copy of this record with selected fields replaced. Used by
  /// the history service to write a fetched [recommendation] back into the
  /// record while keeping the record itself immutable.
  ///
  /// Note: pass `recommendation: null` does NOT clear the existing value
  /// (would be indistinguishable from "not provided"). To explicitly clear,
  /// pass an empty string.
  DetectionRecord copyWith({
    String? recommendation,
  }) {
    return DetectionRecord(
      id: id,
      timestamp: timestamp,
      specificLabel: specificLabel,
      specificConfidence: specificConfidence,
      parentLabel: parentLabel,
      parentConfidence: parentConfidence,
      perModelConfidences: perModelConfidences,
      zone: zone,
      severity: severity,
      imagePath: imagePath,
      recommendation: recommendation ?? this.recommendation,
    );
  }

  // ── JSON serialisation ────────────────────────────────────────────────────
  // Used by DetectionHistoryService to persist the records list to a JSON
  // file in the app's documents directory, so the history survives app
  // restarts. Schema is intentionally flat (no nested objects) to keep
  // it easy to eyeball on disk.
  //
  // Enums are stored as their `.name` string (e.g. "campusPark", "high").
  // On read we use `firstWhere(..., orElse: <default>)`, so renaming or
  // removing an enum value later results in records falling back to a
  // sensible default instead of crashing the parse.

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'specificLabel': specificLabel,
        'specificConfidence': specificConfidence,
        'parentLabel': parentLabel,
        'parentConfidence': parentConfidence,
        'perModelConfidences': perModelConfidences,
        'zone': zone.name,
        'severity': severity.name,
        'recommendation': recommendation,
        'imagePath': imagePath,
      };

  factory DetectionRecord.fromJson(Map<String, dynamic> json) {
    return DetectionRecord(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      specificLabel: json['specificLabel'] as String,
      specificConfidence: (json['specificConfidence'] as num).toDouble(),
      parentLabel: json['parentLabel'] as String,
      parentConfidence: (json['parentConfidence'] as num).toDouble(),
      perModelConfidences: _parseConfidences(json['perModelConfidences']),
      zone: HazardZone.values.firstWhere(
        (z) => z.name == json['zone'],
        orElse: () => HazardZone.unspecified,
      ),
      severity: HazardSeverity.values.firstWhere(
        (s) => s.name == json['severity'],
        orElse: () => HazardSeverity.medium,
      ),
      recommendation: json['recommendation'] as String?,
      imagePath: json['imagePath'] as String,
    );
  }

  /// Numeric values come back from `jsonDecode` as `num`; cast each one to
  /// `double` and preserve the original insertion order (LinkedHashMap).
  static Map<String, double> _parseConfidences(dynamic raw) {
    if (raw is! Map) return {};
    final result = <String, double>{};
    raw.forEach((k, v) {
      if (k is String && v is num) result[k] = v.toDouble();
    });
    return result;
  }
}
