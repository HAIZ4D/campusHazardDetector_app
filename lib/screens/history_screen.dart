import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/detection_record.dart';
import '../services/detection_history_service.dart';
import '../widgets/display_rules.dart';
import '../widgets/parent_category_palette.dart';
import 'detection_detail_screen.dart';

/// Secondary screen showing all saved detection evidence records.
///
/// Each card displays:
///   - Thumbnail of the captured JPEG
///   - Main label (specific or parent-fallback per DisplayRules — matches
///     the live overlay)
///   - Parent-category coloured badge
///   - Specific + parent confidence numbers
///   - Per-model contribution chips (which YOLO models fired, with their
///     individual confidences) — the "useful for my report" data
///   - Agreement summary chip ("1 model only" / "N models agreed")
///   - Timestamp
///
/// Records can be individually deleted with the trailing delete icon.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          // Clear-all button — only shown when there are records.
          Consumer<DetectionHistoryService>(
            builder: (_, service, __) {
              if (service.count == 0) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: 'Clear all records',
                onPressed: () => _confirmClearAll(context, service),
              );
            },
          ),
        ],
      ),
      body: Consumer<DetectionHistoryService>(
        builder: (_, service, __) {
          if (service.records.isEmpty) {
            return _buildEmptyState();
          }
          // The header is rendered as item 0 so it scrolls with the list —
          // makes it possible to capture header + a card in one screenshot
          // for the report's results section.
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: service.records.length + 1,
            itemBuilder: (_, index) {
              if (index == 0) {
                return _HistoryStatsHeader(records: service.records);
              }
              return _DetectionCard(record: service.records[index - 1]);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, size: 64, color: Colors.black26),
          SizedBox(height: 12),
          Text(
            'No detections saved yet.\nTap Capture on the camera screen.',
            style: TextStyle(color: Colors.black45, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearAll(
      BuildContext context, DetectionHistoryService service) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear all records?'),
        content: const Text('This will remove all saved detections from the list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      for (final record in List.of(service.records)) {
        service.removeRecord(record.id);
      }
    }
  }
}

// ── Stats header (scrolls with the list) ─────────────────────────────────────

/// Summary stats over all saved records, intended for the report's results
/// section. Shows total count, single- vs multi-model split (with a visual
/// bar), and a per-group-size breakdown.
///
/// Captures with no hazard detected are counted in the total but excluded
/// from the multi/single split — they have no `numModelsAgreeing` to bucket.
class _HistoryStatsHeader extends StatelessWidget {
  final List<DetectionRecord> records;

  const _HistoryStatsHeader({required this.records});

  @override
  Widget build(BuildContext context) {
    final int total = records.length;

    // Records that actually contain a hazard — these are the only ones the
    // multi-vs-single split is meaningful for.
    final hazardRecords = records.where((r) => r.hasHazard).toList();
    final int hazards = hazardRecords.length;
    final int multi =
        hazardRecords.where((r) => r.isMultiModelAgreement).length;
    final int single = hazards - multi;

    // Per-group-size histogram (1..4 models).
    final Map<int, int> bySize = {1: 0, 2: 0, 3: 0, 4: 0};
    for (final r in hazardRecords) {
      final n = r.numModelsAgreeing;
      bySize[n] = (bySize[n] ?? 0) + 1;
    }

    final double multiPct = hazards == 0 ? 0 : (multi * 100.0 / hazards);
    final double singlePct = hazards == 0 ? 0 : (single * 100.0 / hazards);

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row: totals ──────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.bar_chart, size: 18, color: Colors.black54),
                const SizedBox(width: 6),
                Text(
                  '$total record${total == 1 ? '' : 's'}'
                  '${total != hazards ? '   ($hazards with hazards)' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),

            // If we have no hazard records, the bar + breakdown wouldn't
            // mean anything — skip them with a friendly note instead.
            if (hazards == 0) ...[
              const SizedBox(height: 6),
              const Text(
                'No hazard detections captured yet.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black45,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              // ── Visual split bar ──────────────────────────────────────
              _MultiSingleBar(multiPct: multiPct),
              const SizedBox(height: 6),
              // Numeric legend underneath the bar — explicit because the
              // report will quote the percentages.
              Row(
                children: [
                  _LegendDot(color: const Color(0xFF4CAF50)),
                  const SizedBox(width: 4),
                  Text(
                    '$multi multi-model '
                    '(${multiPct.toStringAsFixed(1)}%)',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                  _LegendDot(color: const Color(0xFFFFA000)),
                  const SizedBox(width: 4),
                  Text(
                    '$single single-model '
                    '(${singlePct.toStringAsFixed(1)}%)',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),

              const SizedBox(height: 10),
              // ── Per-group-size breakdown ──────────────────────────────
              const Text(
                'Group sizes:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final entry in bySize.entries)
                    _SizeChip(
                      size: entry.key,
                      count: entry.value,
                      totalHazards: hazards,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Horizontal stacked bar: green = multi-model share, amber = single-model.
class _MultiSingleBar extends StatelessWidget {
  final double multiPct;
  const _MultiSingleBar({required this.multiPct});

  @override
  Widget build(BuildContext context) {
    final double multiFraction = multiPct / 100.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            // Multi-model share (left).
            Expanded(
              flex: (multiFraction * 1000).round(),
              child: Container(color: const Color(0xFF4CAF50)),
            ),
            // Single-model share (right).
            Expanded(
              flex: ((1.0 - multiFraction) * 1000).round(),
              child: Container(color: const Color(0xFFFFA000)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// One chip for "Nm: count (pct%)", e.g. "2m: 5 (41.7%)".
class _SizeChip extends StatelessWidget {
  final int size;
  final int count;
  final int totalHazards;

  const _SizeChip({
    required this.size,
    required this.count,
    required this.totalHazards,
  });

  @override
  Widget build(BuildContext context) {
    final double pct = totalHazards == 0 ? 0 : count * 100.0 / totalHazards;
    final bool empty = count == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: empty
            ? Colors.black.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: empty ? Colors.black12 : Colors.black26,
          width: 1,
        ),
      ),
      child: Text(
        '${size}m: $count'
        '${empty ? '' : ' (${pct.toStringAsFixed(1)}%)'}',
        style: TextStyle(
          fontSize: 11,
          color: empty ? Colors.black38 : Colors.black87,
          fontWeight: empty ? FontWeight.normal : FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ── Individual detection card ────────────────────────────────────────────────

class _DetectionCard extends StatelessWidget {
  final DetectionRecord record;

  const _DetectionCard({required this.record});

  @override
  Widget build(BuildContext context) {
    // Special-case "captured but no hazard" — render a minimal card so the
    // user can still see the saved photo with a plain timestamp.
    if (!record.hasHazard) {
      return _buildEmptyDetectionCard();
    }

    final Color parentColor =
        ParentCategoryPalette.colorFor(record.parentLabel);
    final String shortParent =
        ParentCategoryPalette.shortLabel(record.parentLabel);

    // Same fallback rule the live overlay uses, via the shared helper.
    final mainDecision = DisplayRules.resolveMainLabel(
      specificLabel: record.specificLabel,
      specificConfidence: record.specificConfidence,
      parentLabel: record.parentLabel,
      parentConfidence: record.parentConfidence,
    );

    final String formattedTime =
        DateFormat('d MMM yyyy, HH:mm:ss').format(record.timestamp);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      // InkWell wraps the entire card surface for the tap-to-open-detail
      // gesture. The delete IconButton further down intercepts its own
      // taps (IconButton has its own GestureDetector), so a tap on the
      // delete icon does NOT also open the detail screen.
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetectionDetailScreen(recordId: record.id),
          ),
        ),
        child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Thumbnail ──────────────────────────────────────────────────
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: SizedBox(
                width: 100,
                child: _ThumbnailImage(path: record.imagePath),
              ),
            ),

            // Vertical accent stripe in the parent-category colour, so the
            // family is visible at a glance when scrolling the list.
            Container(width: 4, color: parentColor),

            // ── Details ────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: main label + parent badge
                    _LabelRow(
                      mainText: mainDecision.text,
                      isGeneralFallback: mainDecision.isGeneralFallback,
                      badgeText: shortParent,
                      badgeColor: parentColor,
                    ),
                    const SizedBox(height: 8),

                    // Confidence summary line — keeps BOTH numbers visible
                    // even when the main label is the parent fallback, so
                    // the report can compare the two heads' agreement.
                    Text(
                      'specific ${(record.specificConfidence * 100).toStringAsFixed(1)}%   '
                      '·   parent ${(record.parentConfidence * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Agreement summary + per-model contribution chips.
                    _ModelAttribution(record: record),

                    const SizedBox(height: 6),
                    Text(
                      formattedTime,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black45),
                    ),
                  ],
                ),
              ),
            ),

            // ── Delete button ──────────────────────────────────────────────
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.black38),
                tooltip: 'Delete this record',
                onPressed: () => context
                    .read<DetectionHistoryService>()
                    .removeRecord(record.id),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildEmptyDetectionCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Builder(
        builder: (context) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetectionDetailScreen(recordId: record.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 80,
                height: 80,
                child: _ThumbnailImage(path: record.imagePath),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No hazard detected',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('d MMM yyyy, HH:mm:ss').format(record.timestamp),
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

/// Top row of a hazard card: main label + parent badge — designed to be
/// visually similar to the live overlay so the user can recognise records
/// at a glance.
class _LabelRow extends StatelessWidget {
  final String mainText;
  final bool isGeneralFallback;
  final String badgeText;
  final Color badgeColor;

  const _LabelRow({
    required this.mainText,
    required this.isGeneralFallback,
    required this.badgeText,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    // Same brown/amber-vs-black background convention as the overlay so
    // fallback records are visually distinct from confident specific ones.
    final Color mainBg =
        isGeneralFallback ? const Color(0xFF8D6E63) : Colors.black87;
    final Color badgeFg =
        badgeColor.computeLuminance() > 0.6 ? Colors.black : Colors.white;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        // Main label pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: mainBg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            mainText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // Parent badge pill — matches overlay shape and contrast logic.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            badgeText,
            style: TextStyle(
              color: badgeFg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// The "useful for my report" block: how many models agreed, and which
/// ones with what confidence.
class _ModelAttribution extends StatelessWidget {
  final DetectionRecord record;

  const _ModelAttribution({required this.record});

  @override
  Widget build(BuildContext context) {
    final n = record.numModelsAgreeing;

    // Agreement-summary chip colour goes from amber (1 model only — weakest
    // ensemble evidence) through to deep green (all 4 agreed — strongest).
    final Color agreementColor = switch (n) {
      1 => const Color(0xFFFFA000), // amber
      2 => const Color(0xFF8BC34A), // light green
      3 => const Color(0xFF4CAF50), // green
      _ => const Color(0xFF1B5E20), // deep green for 4
    };
    final String agreementText = record.isMultiModelAgreement
        ? '$n models agreed'
        : '1 model only';

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        // Agreement summary chip.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: agreementColor.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: agreementColor, width: 1),
          ),
          child: Text(
            agreementText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: agreementColor,
            ),
          ),
        ),
        // Per-model contribution chips (firing models only, canonical order).
        for (final entry in record.perModelConfidences.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black26, width: 1),
            ),
            child: Text(
              '${entry.key} ${(entry.value * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.black87,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Thumbnail widget ─────────────────────────────────────────────────────────

/// Shows the saved image, or a fallback icon if the file no longer exists.
class _ThumbnailImage extends StatelessWidget {
  final String path;
  const _ThumbnailImage({required this.path});

  @override
  Widget build(BuildContext context) {
    final File file = File(path);
    if (!file.existsSync()) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, color: Colors.black26),
      );
    }
    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, color: Colors.black26),
      ),
    );
  }
}
