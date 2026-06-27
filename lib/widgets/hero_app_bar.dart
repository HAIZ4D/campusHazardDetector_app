// =============================================================================
// HeroAppBar
// -----------------------------------------------------------------------------
// A taller, more expressive AppBar designed for the secondary screens
// (History, Hazards, Settings, Detection Detail). Drops into Scaffold.appBar
// as a PreferredSizeWidget — no Sliver gymnastics required.
//
// Visual anatomy:
//
//   ┌─────────────────────────────────────────────────────────┐
//   │  ┏━━━┓                                                  │
//   │  ┃IC ┃   TITLE  (24sp, w900, charcoal)        [actions] │
//   │  ┗━━━┛   subtitle (12.5sp, w500, muted)                 │
//   └─────────────────────────────────────────────────────────┘
//        ▲                                          ▲
//   icon badge with glow             optional action buttons
//   (accent-coloured, rounded)       (e.g. Clear All)
//
// Background is a soft diagonal gradient from the cream surface to a hint
// of the accent colour, with a hairline shadow at the bottom edge. Each
// screen can override the accent (the detection-detail screen ties its
// appbar accent to the record's parent-category colour for continuity).
// =============================================================================

import 'package:flutter/material.dart';

class HeroAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Main heading text shown at full size.
  final String title;

  /// Smaller subtitle below the title — give the user one line of context.
  final String subtitle;

  /// Hero icon that lives in the badge on the left.
  final IconData icon;

  /// Optional trailing widgets (e.g. an IconButton for Clear All).
  final List<Widget>? actions;

  /// Override the default accent (defaults to the theme's primary). The
  /// detail screen uses this to colour-match the displayed record's parent
  /// hazard category.
  final Color? accentColor;

  /// Optional back-button override; defaults to Navigator.maybePop when
  /// inside a route that can be popped.
  final VoidCallback? onBack;

  /// When true, shows a back arrow on the left (before the icon badge).
  final bool showBackButton;

  /// AppBar height (does NOT include the status bar — that's drawn through
  /// the gradient automatically).
  static const double _contentHeight = 112;
  static const double _statusBarFallback = 24;

  const HeroAppBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.actions,
    this.accentColor,
    this.onBack,
    this.showBackButton = false,
  });

  @override
  Size get preferredSize =>
      const Size.fromHeight(_contentHeight + _statusBarFallback);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color accent = accentColor ?? scheme.primary;
    final Color onAccent = _onColor(accent);
    final double topInset = MediaQuery.of(context).padding.top;

    return Container(
      // Container takes the FULL preferredSize so the gradient extends
      // behind the status bar — gives the modern "edge-to-edge" feel.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surface,
            Color.alphaBlend(accent.withValues(alpha: 0.18), scheme.surface),
          ],
          stops: const [0.25, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.only(top: topInset),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Optional back button ───────────────────────────────────
              if (showBackButton) ...[
                _RoundIconButton(
                  icon: Icons.arrow_back,
                  onTap: onBack ?? () => Navigator.of(context).maybePop(),
                  background: scheme.surface,
                  iconColor: scheme.onSurface,
                ),
                const SizedBox(width: 8),
              ],

              // ── Hero icon badge ───────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.40),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(icon, color: onAccent, size: 22),
              ),
              const SizedBox(width: 14),

              // ── Title + subtitle stack ────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: scheme.onSurface,
                        height: 1.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurface.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // ── Optional action widgets on the right ──────────────────
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }

  /// Pick black text on light accents, white on dark ones.
  static Color _onColor(Color bg) =>
      bg.computeLuminance() > 0.6 ? Colors.black : Colors.white;
}

/// Helper: small rounded icon button used by the back arrow.
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color background;
  final Color iconColor;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.background,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }
}

/// Drop-in for [HeroAppBar.actions]: a compact circular icon button that
/// fits the look of the hero header. Use this instead of IconButton for
/// uniform styling in the actions slot.
class HeroAppBarAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const HeroAppBarAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget button = Material(
      color: scheme.surface.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: scheme.onSurface, size: 20),
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
