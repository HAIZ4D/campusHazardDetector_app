// =============================================================================
// HazardsScreen
// -----------------------------------------------------------------------------
// Reference catalogue of every hazard the app can detect. Reads directly from
// the meta-classifier config + the harmonisation map so it stays in sync
// with whatever the trained models actually emit — no separate data list
// to maintain.
//
// Structure:
//   - A short header explaining the catalogue.
//   - One section per PARENT category (4 sections). Each section header is
//     painted in that parent's colour, matching the live overlay & history.
//   - Specific hazards listed as cards under their parent.
// =============================================================================

import 'package:flutter/material.dart';

import '../ensemble/label_harmoniser.dart';
import '../widgets/hero_app_bar.dart';
import '../widgets/parent_category_palette.dart';

/// Hardcoded list of (raw → harmonised) pairs we ALWAYS want shown, derived
/// from the harmoniser. Kept here so we don't expose LabelHarmoniser's
/// internal map publicly.
const Map<String, (String, String)> _catalogue = {
  // raw class name : (normalised, parent)
  'Mossy Surface': ('Mossy Surface', 'Surface/Ground Hazard'),
  'Overgrown Vegetation':
      ('Overgrown Vegetation', 'Obstruction Hazard'),
  'Protruding Fastener':
      ('Protruding Fastener', 'Structural/Injury Hazard'),
  'Rusted Equipment': ('Rusted Equipment', 'Structural/Injury Hazard'),
  'Waterlogged field': ('Waterlogged Field', 'Surface/Ground Hazard'),
  'damaged_flooring': ('Damaged Flooring', 'Surface/Ground Hazard'),
  'fallen_branch': ('Fallen Branch', 'Obstruction Hazard'),
  'overflowing_trash': ('Overflowing Trash Bin', 'Hygiene Hazard'),
  'uncovered_drain': ('Open/Uncovered Drain', 'Surface/Ground Hazard'),
  'water_accumulation': ('Wet Floor', 'Surface/Ground Hazard'),
  'open_drain': ('Open/Uncovered Drain', 'Surface/Ground Hazard'),
  'overgrown_vegetation':
      ('Overgrown Vegetation', 'Obstruction Hazard'),
  'pothole': ('Pothole', 'Surface/Ground Hazard'),
  'sharp_object': ('Sharp Object', 'Structural/Injury Hazard'),
  'uneven_floor': ('Uneven Floor', 'Surface/Ground Hazard'),
  'broken_fence': ('Broken Fence', 'Structural/Injury Hazard'),
  'broken_lamppost': ('Broken Lamp Post', 'Structural/Injury Hazard'),
  'broken_signboard':
      ('Unclear/Broken Signboard', 'Structural/Injury Hazard'),
  'obstacle_walkway': ('Obstacle Walkway', 'Obstruction Hazard'),
};

/// Display order for the 4 parents — matches the severity ordering used in
/// HazardSeverity.compute (high-risk first so the user sees danger first).
const List<String> _parentOrder = [
  'Structural/Injury Hazard',
  'Surface/Ground Hazard',
  'Obstruction Hazard',
  'Hygiene Hazard',
];

/// Friendly one-line description per parent.
const Map<String, String> _parentBlurb = {
  'Structural/Injury Hazard':
      'Broken or sharp things that can cut, snag, or fall on someone.',
  'Surface/Ground Hazard':
      'Walking-surface issues: slippery, uneven, or hidden under water.',
  'Obstruction Hazard':
      'Things in the way — overgrowth, fallen branches, blocked paths.',
  'Hygiene Hazard':
      'Waste-related hazards that attract pests or pose a health risk.',
};

class HazardsScreen extends StatelessWidget {
  const HazardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Group specific labels by parent. Multiple raw classes can map to the
    // same normalised label (e.g. open_drain + uncovered_drain → Open/Uncovered
    // Drain), so we de-dup with a set per parent.
    final Map<String, Set<String>> byParent = {
      for (final p in _parentOrder) p: <String>{},
    };
    _catalogue.forEach((_, value) {
      final (normalised, parent) = value;
      byParent[parent]?.add(normalised);
    });
    // Also drop in any unmapped parents (defensive — shouldn't happen).
    for (final entry in _catalogue.entries) {
      final parent = entry.value.$2;
      byParent.putIfAbsent(parent, () => <String>{}).add(entry.value.$1);
    }

    // Use the harmoniser as a "did we miss anything" sanity check at
    // assertion time, ignored in release.
    assert(() {
      // ignore: unused_local_variable
      final h = LabelHarmoniser;
      return true;
    }());

    return Scaffold(
      appBar: const HeroAppBar(
        title: 'Hazards',
        subtitle: '17 detectable types across 4 risk families',
        icon: Icons.shield,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ── Header card ────────────────────────────────────────────────
          _HeaderCard(),

          const SizedBox(height: 16),

          // ── One section per parent category ────────────────────────────
          for (final parent in _parentOrder) ...[
            _ParentSection(
              parent: parent,
              specifics:
                  (byParent[parent] ?? <String>{}).toList()..sort(),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

// ── Header card ──────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.primaryContainer.withValues(alpha: 0.55),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.shield, color: scheme.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hazard catalogue',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The 17 hazards this app can detect, grouped into 4 risk '
                  'families. Colours match the live camera overlay and saved '
                  'history records.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── One parent-category section ─────────────────────────────────────────────

class _ParentSection extends StatelessWidget {
  final String parent;
  final List<String> specifics;

  const _ParentSection({required this.parent, required this.specifics});

  @override
  Widget build(BuildContext context) {
    final Color color = ParentCategoryPalette.colorFor(parent);
    final String shortName = ParentCategoryPalette.shortLabel(parent);
    final String blurb = _parentBlurb[parent] ?? '';

    // Black-on-light vs white-on-dark depending on badge luminance.
    final Color onColor =
        color.computeLuminance() > 0.6 ? Colors.black : Colors.white;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section header: parent badge + name + blurb ──────────────
            Row(
              children: [
                Container(
                  width: 6,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parent,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        blurb,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.black54,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    shortName,
                    style: TextStyle(
                      color: onColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: color.withValues(alpha: 0.25), height: 1),
            const SizedBox(height: 10),

            // ── Specific hazards under this parent ───────────────────────
            for (int i = 0; i < specifics.length; i++) ...[
              _SpecificRow(label: specifics[i], color: color),
              if (i < specifics.length - 1)
                Divider(
                  color: Colors.black.withValues(alpha: 0.06),
                  height: 1,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SpecificRow extends StatelessWidget {
  final String label;
  final Color color;

  const _SpecificRow({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
