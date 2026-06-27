// =============================================================================
// GeminiService
// -----------------------------------------------------------------------------
// Thin wrapper around the official `google_generative_ai` Dart SDK. Builds a
// structured prompt from a [DetectionRecord] and asks Gemini to return a
// short, friendly 3-section safety recommendation.
//
// Why a singleton?
//   The [GenerativeModel] is cheap to construct but stateless across calls.
//   Reusing one instance avoids re-reading the API key from dotenv on every
//   tap and avoids constructing a fresh HTTP client per request.
//
// Error model:
//   We surface failures as a typed exception ([GeminiServiceException]) with
//   a small enum so the UI layer can render contextual messages — e.g.
//   "API key not configured" vs "no network" vs "Gemini refused the
//   request". This is more useful than dumping the raw SDK exception string
//   to the user.
//
// Cost discipline:
//   This is called ON DEMAND only — never from a per-frame loop. The history
//   UI is responsible for not retriggering for records that already have a
//   cached recommendation.
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/detection_record.dart';

/// The Gemini model the service calls by default. Picked for low cost +
/// sub-second responses — overkill quality is wasted on a 100-word reply.
const String kGeminiModelName = 'gemini-2.5-flash';

/// Typed failure modes the UI can switch on to show a useful message.
enum GeminiFailureKind {
  /// `.env` was missing, malformed, or didn't contain GEMINI_API_KEY.
  missingApiKey,

  /// The device has no network, DNS failed, or the connection dropped
  /// mid-request.
  network,

  /// Gemini responded but with no usable text (rare — usually means the
  /// prompt was filtered or the API quota was exhausted).
  emptyResponse,

  /// Anything else — wrapped SDK exception. The `message` field on
  /// [GeminiServiceException] carries the original message.
  unknown,
}

class GeminiServiceException implements Exception {
  final GeminiFailureKind kind;
  final String message;
  GeminiServiceException(this.kind, this.message);

  @override
  String toString() => 'GeminiServiceException(${kind.name}): $message';
}

class GeminiService {
  /// Singleton instance — `GeminiService.instance` everywhere.
  static final GeminiService instance = GeminiService._();
  GeminiService._();

  /// Lazily constructed on first call so the app can still launch without an
  /// API key configured (the recommendation button shows an error on tap
  /// instead of preventing app startup).
  GenerativeModel? _model;

  /// Internal: build (or return cached) the [GenerativeModel].
  /// Throws [GeminiServiceException] with [GeminiFailureKind.missingApiKey]
  /// when `.env` doesn't contain a usable key.
  GenerativeModel _ensureModel() {
    if (_model != null) return _model!;

    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null ||
        key.isEmpty ||
        key.startsWith('replace_me') ||
        key.startsWith('your_')) {
      throw GeminiServiceException(
        GeminiFailureKind.missingApiKey,
        'GEMINI_API_KEY is not set. Copy .env.example to .env and add '
        'your key from https://aistudio.google.com/apikey.',
      );
    }

    _model = GenerativeModel(model: kGeminiModelName, apiKey: key);
    return _model!;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Asks Gemini for a short safety recommendation for [record], using the
  /// 5 structured fields the assignment specifies. Returns the recommendation
  /// text on success; throws [GeminiServiceException] on any failure so the
  /// UI can render typed error states.
  Future<String> generateRecommendation(DetectionRecord record) async {
    if (!record.hasHazard) {
      throw GeminiServiceException(
        GeminiFailureKind.unknown,
        'No hazard in this record — nothing to ask Gemini about.',
      );
    }

    final model = _ensureModel(); // throws on missing key
    final prompt = _buildPrompt(record);

    if (kDebugMode) {
      debugPrint('[GeminiService] prompt:\n$prompt');
    }

    try {
      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text?.trim() ?? '';
      if (text.isEmpty) {
        throw GeminiServiceException(
          GeminiFailureKind.emptyResponse,
          'Gemini returned no text. The prompt may have been filtered, or '
          'your API quota may be exhausted.',
        );
      }
      if (kDebugMode) {
        debugPrint('[GeminiService] response:\n$text');
      }
      return text;
    } on GeminiServiceException {
      rethrow;
    } on SocketException catch (e) {
      // Thrown by the underlying HTTP client when DNS / connection fails.
      throw GeminiServiceException(
        GeminiFailureKind.network,
        'Network error: ${e.message}',
      );
    } on TimeoutException catch (e) {
      throw GeminiServiceException(
        GeminiFailureKind.network,
        'Request timed out: ${e.message ?? "no response in time"}',
      );
    } catch (e) {
      // GenerativeAIException, server errors, malformed responses, etc.
      throw GeminiServiceException(
        GeminiFailureKind.unknown,
        e.toString(),
      );
    }
  }

  // ── Prompt construction ───────────────────────────────────────────────────

  /// Builds the structured prompt fed into Gemini. Kept in one place so the
  /// prompt template can be tweaked / quoted in the technical report without
  /// hunting through the code.
  ///
  /// All 5 fields the assignment requires are included:
  ///   1. Hazard class       → record.specificLabel
  ///   2. General category   → record.parentLabel
  ///   3. Location zone      → record.zone.displayName
  ///   4. Severity           → record.severity.displayName
  ///   5. Confidence         → record.specificConfidence (formatted as %)
  String _buildPrompt(DetectionRecord record) {
    final confidencePct =
        (record.specificConfidence * 100).toStringAsFixed(0);

    return '''
You are a friendly campus safety advisor speaking to a student or staff member.
A hazard has just been detected on campus. Here is the structured context:

- Hazard type: ${record.specificLabel}
- General category: ${record.parentLabel}
- Location zone: ${record.zone.displayName}
- Severity: ${record.severity.displayName}
- Detection confidence: $confidencePct%

Write a friendly, informative safety note with EXACTLY 3 sections, in this
order, each heading on its own line followed by the explanation:

What this means:
<2–3 sentences in plain language describing what this hazard is and how it
typically looks or shows up on a campus. Mention any everyday context that
helps the reader picture it.>

Why it matters:
<2–3 sentences on the real-world consequences if it is ignored, including
likely injuries, slips, equipment damage, or knock-on problems. Be concrete
and specific to this hazard, not generic.>

What to do:
<2–3 sentences with practical, actionable advice covering BOTH immediate
protection (how to stay safe right now) AND prevention/reporting (who to
tell or what to do so it gets fixed).>

Keep the entire response between 120 and 200 words. Use everyday language.
Avoid clinical jargon, bullet lists inside sections, and overly formal
phrasing. Do not add any extra sections, disclaimers, or sign-offs.
''';
  }
}
