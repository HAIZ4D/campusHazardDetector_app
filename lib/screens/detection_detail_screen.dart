// =============================================================================
// DetectionDetailScreen
// -----------------------------------------------------------------------------
// Opened by tapping a card on the history screen. Shows the full record
// (large image + all the metadata the card already surfaces) plus a "Safety
// recommendation" block that calls the Gemini API on demand.
//
// State machine for the recommendation block (held locally in this widget):
//
//      [idle]
//         │  user taps "Get recommendation"
//         ▼
//     [loading] ─── error ──▶ [error]
//         │                        │ user taps retry
//         │  success               ▼
//         ▼                   [loading]   (back to top of loop)
//   cache into record
//   via updateRecord
//         │
//         ▼
//      [cached]   ← also entered immediately on screen open if the record
//                    already has a cached recommendation (no API call)
//
// Looking up the record by id (not capturing it as a constructor argument)
// means:
//   - the Consumer rebuilds when updateRecord lands the cached response,
//   - if the user deletes this record from another screen while we're open
//     we render a graceful "deleted" state instead of crashing on a stale
//     reference.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/detection_record.dart';
import '../services/detection_history_service.dart';
import '../services/gemini_service.dart';
import '../widgets/display_rules.dart';
import '../widgets/parent_category_palette.dart';

class DetectionDetailScreen extends StatefulWidget {
  /// We pass the id (not the record itself) so the Consumer below can pick
  /// up the latest version from DetectionHistoryService — important once
  /// the cached recommendation lands.
  final String recordId;

  const DetectionDetailScreen({super.key, required this.recordId});

  @override
  State<DetectionDetailScreen> createState() => _DetectionDetailScreenState();
}

/// Three local states for the recommendation block. The cached state is
/// inferred from the record itself (record.hasRecommendation), so we only
/// need to track loading and error here.
class _DetectionDetailScreenState extends State<DetectionDetailScreen> {
  bool _loading = false;
  GeminiServiceException? _error;

  Future<void> _fetchRecommendation(DetectionRecord record) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final text = await GeminiService.instance.generateRecommendation(record);
      // Persist into the record via the service so re-opening this screen
      // shows the cached response without another API call.
      if (mounted) {
        context
            .read<DetectionHistoryService>()
            .updateRecord(record.copyWith(recommendation: text));
      }
    } on GeminiServiceException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detection Detail'),
      ),
      // Consumer so we rebuild when updateRecord lands the cached response.
      body: Consumer<DetectionHistoryService>(
        builder: (_, service, __) {
          final record = service.recordById(widget.recordId);
          if (record == null) {
            // User deleted the record from another route while we were open.
            return _buildDeletedState();
          }
          return _buildBody(record);
        },
      ),
    );
  }

  Widget _buildDeletedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline, size: 48, color: Colors.black26),
            const SizedBox(height: 12),
            const Text(
              'This record was deleted.',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(DetectionRecord record) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ImageHeader(path: record.imagePath),
          const SizedBox(height: 12),
          if (record.hasHazard) ...[
            _MetadataCard(record: record),
            const SizedBox(height: 12),
            _RecommendationCard(
              record: record,
              loading: _loading,
              error: _error,
              onFetch: () => _fetchRecommendation(record),
            ),
          ] else
            // Empty-detection card: no metadata, no recommendation block —
            // there's nothing for Gemini to talk about.
            _NoHazardCard(record: record),
        ],
      ),
    );
  }
}

/// Minimal placeholder shown when the user captured a snapshot but no
/// hazard was detected at the time.
class _NoHazardCard extends StatelessWidget {
  final DetectionRecord record;
  const _NoHazardCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No hazard detected at capture time.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black54,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            _KvRow(k: 'Zone', v: record.zone.displayName),
            const SizedBox(height: 6),
            Text(
              DateFormat('d MMM yyyy, HH:mm:ss').format(record.timestamp),
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Image header ─────────────────────────────────────────────────────────────

class _ImageHeader extends StatelessWidget {
  final String path;
  const _ImageHeader({required this.path});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : Container(
                color: Colors.grey.shade300,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image,
                    size: 48, color: Colors.black26),
              ),
      ),
    );
  }
}

// ── Metadata card ────────────────────────────────────────────────────────────

class _MetadataCard extends StatelessWidget {
  final DetectionRecord record;
  const _MetadataCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final parentColor =
        ParentCategoryPalette.colorFor(record.parentLabel);
    final shortParent =
        ParentCategoryPalette.shortLabel(record.parentLabel);
    final decision = DisplayRules.resolveMainLabel(
      specificLabel: record.specificLabel,
      specificConfidence: record.specificConfidence,
      parentLabel: record.parentLabel,
      parentConfidence: record.parentConfidence,
    );

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main label + parent badge (same visual language as the overlay).
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: decision.isGeneralFallback
                        ? const Color(0xFF8D6E63)
                        : Colors.black87,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    decision.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: parentColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    shortParent,
                    style: TextStyle(
                      color: parentColor.computeLuminance() > 0.6
                          ? Colors.black
                          : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Confidence numbers.
            _KvRow(
              k: 'Specific confidence',
              v: '${(record.specificConfidence * 100).toStringAsFixed(1)}%',
            ),
            _KvRow(
              k: 'Parent confidence',
              v: '${(record.parentConfidence * 100).toStringAsFixed(1)}%',
            ),

            const Divider(height: 18),

            // Zone + severity (the new fields that feed Gemini).
            _KvRow(k: 'Zone', v: record.zone.displayName),
            _KvRow(k: 'Severity', v: record.severity.displayName),

            const Divider(height: 18),

            // Provenance — per-model chips, in canonical order.
            Text(
              record.isMultiModelAgreement
                  ? '${record.numModelsAgreeing} models agreed'
                  : '1 model only',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final entry in record.perModelConfidences.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black26, width: 1),
                    ),
                    child: Text(
                      '${entry.key} '
                      '${(entry.value * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black87,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),
            Text(
              DateFormat('d MMM yyyy, HH:mm:ss').format(record.timestamp),
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small reusable key:value row.
class _KvRow extends StatelessWidget {
  final String k;
  final String v;
  const _KvRow({required this.k, required this.v});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              k,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          Text(
            v,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recommendation card ──────────────────────────────────────────────────────

/// Holds the recommendation state machine: idle → loading → success/error.
/// Success state is read directly from `record.hasRecommendation`, so once
/// cached the card stays in "success" forever (until the record is deleted).
class _RecommendationCard extends StatelessWidget {
  final DetectionRecord record;
  final bool loading;
  final GeminiServiceException? error;
  final VoidCallback onFetch;

  const _RecommendationCard({
    required this.record,
    required this.loading,
    required this.error,
    required this.onFetch,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome,
                    size: 18, color: Colors.deepPurple),
                const SizedBox(width: 6),
                const Text(
                  'Safety recommendation',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Gemini',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final bool hasCached = record.hasRecommendation;
    final String? cachedText = record.recommendation;

    // ── Loading ────────────────────────────────────────────────────────────
    // If we already have a cached recommendation, keep it visible (dimmed)
    // below the spinner so the user has something to read while regen runs.
    if (loading) {
      if (hasCached) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _LoadingState(isRegenerate: true),
            const SizedBox(height: 12),
            Opacity(
              opacity: 0.45,
              child: _CachedRecommendation(text: cachedText!),
            ),
          ],
        );
      }
      return const _LoadingState(isRegenerate: false);
    }

    // ── Error ──────────────────────────────────────────────────────────────
    // With cached: small error banner above; cached text stays intact below.
    // Without cached: full error state (unchanged from before).
    if (error != null) {
      if (hasCached) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ErrorBanner(error: error!, onRetry: onFetch),
            const SizedBox(height: 12),
            _CachedRecommendation(text: cachedText!),
          ],
        );
      }
      return _ErrorState(error: error!, onRetry: onFetch);
    }

    // ── Cached (steady state) ──────────────────────────────────────────────
    // Show the formatted recommendation + a small Regenerate control at the
    // bottom. Users can re-ask Gemini any time; each tap is one API call.
    if (hasCached) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CachedRecommendation(text: cachedText!),
          const SizedBox(height: 12),
          Divider(color: Colors.black.withValues(alpha: 0.06), height: 1),
          const SizedBox(height: 10),
          _RegenerateRow(onRegenerate: onFetch),
        ],
      );
    }

    // ── Idle ───────────────────────────────────────────────────────────────
    return _IdleState(onFetch: onFetch);
  }
}

class _IdleState extends StatelessWidget {
  final VoidCallback onFetch;
  const _IdleState({required this.onFetch});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tap below to get a short, friendly safety note for this hazard, '
          'tailored to its category, location and severity.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onFetch,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Get recommendation'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  /// True when we're refreshing an existing recommendation; affects the
  /// label so the user knows we kept the old text underneath.
  final bool isRegenerate;
  const _LoadingState({required this.isRegenerate});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(
          isRegenerate ? 'Regenerating…' : 'Asking Gemini…',
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
      ],
    );
  }
}

/// Small inline error chip used when a REGENERATE fails — leaves the cached
/// recommendation visible underneath. The "first generate" error case still
/// uses the full-screen [_ErrorState] further down.
class _ErrorBanner extends StatelessWidget {
  final GeminiServiceException error;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final bool canRetry = error.kind != GeminiFailureKind.missingApiKey;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.red),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Regenerate failed',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.red.shade800,
                  ),
                ),
                Text(
                  error.message,
                  style:
                      const TextStyle(fontSize: 11, color: Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (canRetry) ...[
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small "Regenerate" row shown under a cached recommendation. Each tap is
/// one new Gemini API call — that's intentional and matches the
/// "on demand, never per-frame" cost rule from the assignment.
class _RegenerateRow extends StatelessWidget {
  final VoidCallback onRegenerate;
  const _RegenerateRow({required this.onRegenerate});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            'Want a fresh take? Each tap calls Gemini again.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onRegenerate,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Regenerate'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.deepPurple,
            side: BorderSide(color: Colors.deepPurple.withValues(alpha: 0.4)),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final GeminiServiceException error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    // Contextual headline per failure kind. The retry button is hidden for
    // missingApiKey because retrying without fixing .env will just fail
    // again immediately.
    final (String headline, bool showRetry) = switch (error.kind) {
      GeminiFailureKind.missingApiKey => (
        'Gemini API key is not configured.',
        false,
      ),
      GeminiFailureKind.network => ('Network error.', true),
      GeminiFailureKind.emptyResponse =>
        ('Gemini returned no usable response.', true),
      GeminiFailureKind.unknown => ('Something went wrong.', true),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: Colors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      headline,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                error.message,
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ],
          ),
        ),
        if (showRetry) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Renders the cached Gemini response. We try to parse the 3 expected
/// sections ("What this means", "Why it matters", "What to do") and render
/// each with a bold heading; if the response doesn't look like that shape,
/// we just print the raw text rather than mangling it.
class _CachedRecommendation extends StatelessWidget {
  final String text;
  const _CachedRecommendation({required this.text});

  static const _expectedHeadings = [
    'What this means:',
    'Why it matters:',
    'What to do:',
  ];

  @override
  Widget build(BuildContext context) {
    final sections = _parseSections(text);
    if (sections.isEmpty) {
      // Parse failed — render the raw text.
      return SelectableText(
        text,
        style: const TextStyle(fontSize: 13, height: 1.4),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Text(
            sections[i].heading,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            sections[i].body,
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
        ],
      ],
    );
  }

  /// Look for the 3 expected headings; return their bodies in order. Empty
  /// list means the parse failed and the caller should fall back to raw.
  static List<({String heading, String body})> _parseSections(String raw) {
    final positions = <int>[];
    for (final h in _expectedHeadings) {
      positions.add(raw.indexOf(h));
    }
    // Bail if any heading missing OR they appear out of order.
    if (positions.any((p) => p < 0)) return const [];
    for (int i = 1; i < positions.length; i++) {
      if (positions[i] < positions[i - 1]) return const [];
    }

    final result = <({String heading, String body})>[];
    for (int i = 0; i < _expectedHeadings.length; i++) {
      final start = positions[i] + _expectedHeadings[i].length;
      final end = i + 1 < _expectedHeadings.length
          ? positions[i + 1]
          : raw.length;
      result.add((
        heading: _expectedHeadings[i].replaceAll(':', ''),
        body: raw.substring(start, end).trim(),
      ));
    }
    return result;
  }
}
