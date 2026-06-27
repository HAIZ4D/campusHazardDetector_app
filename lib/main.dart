import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'ensemble/meta_classifier_config.dart';
import 'screens/main_shell.dart';
import 'services/app_settings_service.dart';
import 'services/detection_history_service.dart';

/// Entry point.
///
/// Two services are provided at the root of the widget tree:
///   - [DetectionHistoryService] : the persisted history of captures.
///   - [AppSettingsService]      : user-tunable runtime settings (frame skip,
///                                  last-used zone).
///
/// Both load their disk state BEFORE runApp so the UI opens to the right
/// state instead of flashing defaults.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── .env (Gemini key) ─────────────────────────────────────────────────────
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint(
      '[main] .env not loaded ($e). Copy .env.example to .env and add '
      'your Gemini API key to enable AI recommendations.',
    );
  }

  // ── Meta-classifier config schema ─────────────────────────────────────────
  try {
    final config = await MetaClassifierConfig.loadFromAsset();
    debugPrint(config.prettyPrint());
  } catch (e, st) {
    debugPrint('[main] Failed to load meta_classifier_config.json: $e\n$st');
    rethrow;
  }

  // ── Stateful services ─────────────────────────────────────────────────────
  // Constructed synchronously (Provider needs that) and then their disk
  // state is awaited before runApp.
  final historyService = DetectionHistoryService();
  final settingsService = AppSettingsService();
  await Future.wait([
    historyService.loadFromDisk(),
    settingsService.loadFromDisk(),
  ]);

  // Light status-bar contents on the (soon to be light) chrome.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<DetectionHistoryService>.value(
          value: historyService,
        ),
        ChangeNotifierProvider<AppSettingsService>.value(
          value: settingsService,
        ),
      ],
      child: const HazardDetectorApp(),
    ),
  );
}

/// Root widget — Material 3 light theme built around a rich-amber palette.
///
/// Why we don't just use `ColorScheme.fromSeed(amber)` straight:
///   M3 derives `primary` to ensure WCAG contrast on a white surface, which
///   pushes any yellow seed toward a brownish-orange. We want the UI to
///   read as visibly YELLOW, so we override `primary` and
///   `primaryContainer` directly and let the generated palette fill in the
///   harmonised neutrals and tertiaries around them.
///
/// Reads as: warm cream surfaces, gold primary, charcoal text. A premium
/// "safety-yellow" tone that thematically fits a hazard-detection app.
class HazardDetectorApp extends StatelessWidget {
  const HazardDetectorApp({super.key});

  // ── Yellow palette ─────────────────────────────────────────────────────
  // Tuned by hand so primary stays genuinely yellow/gold (not the
  // brown-orange M3 derives by default).
  static const Color _gold = Color(0xFFFFB300); // Amber 600 — rich gold
  static const Color _goldDeep = Color(0xFFFF8F00); // Amber 800 — deeper accent
  static const Color _goldLight = Color(0xFFFFE082); // Amber 200 — soft container
  static const Color _cream = Color(0xFFFFFBEF); // very warm white surface
  static const Color _scaffoldBg = Color(0xFFFFF8E1); // amber 50 — soft bg
  static const Color _charcoal = Color(0xFF2D2A26); // warm dark text
  static const Color _onContainer = Color(0xFF3E2723); // brown 900-ish

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: _gold,
      brightness: Brightness.light,
    ).copyWith(
      primary: _gold,
      onPrimary: Colors.black, // dark text on yellow = readable
      primaryContainer: _goldLight,
      onPrimaryContainer: _onContainer,
      secondary: _goldDeep,
      onSecondary: Colors.white,
      surface: _cream,
      onSurface: _charcoal,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: _cream,
      surfaceContainer: const Color(0xFFFFF3E0), // amber 50 warmer
      surfaceContainerHigh: const Color(0xFFFFE8B3),
      outlineVariant: const Color(0xFFE6DCC2), // warm beige outline
    );

    return MaterialApp(
      title: 'Campus Hazard Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: _scaffoldBg,

        // ── AppBars (default — overridden per screen by HeroAppBar) ───────
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),

        // ── Bottom NavigationBar (Material 3) ─────────────────────────────
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: colorScheme.surface,
          indicatorColor: _goldLight, // soft yellow pill behind active icon
          surfaceTintColor: Colors.transparent,
          height: 72,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected
                  ? _onContainer
                  : colorScheme.onSurfaceVariant,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? _onContainer : colorScheme.onSurfaceVariant,
              size: 24,
            );
          }),
        ),

        // ── Cards: soft, rounded, hairline border ─────────────────────────
        cardTheme: CardThemeData(
          color: Colors.white, // white pops cleanly against cream scaffold
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          margin: EdgeInsets.zero,
        ),

        // ── Filled buttons: gold with dark text ───────────────────────────
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),

        // ── Outlined buttons: soft amber outline ──────────────────────────
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            side: BorderSide(
              color: _goldDeep.withValues(alpha: 0.45),
              width: 1.2,
            ),
            foregroundColor: _onContainer,
          ),
        ),

        // ── Sliders: gold track ───────────────────────────────────────────
        sliderTheme: SliderThemeData(
          activeTrackColor: _gold,
          inactiveTrackColor: _goldLight.withValues(alpha: 0.5),
          thumbColor: _goldDeep,
          overlayColor: _gold.withValues(alpha: 0.15),
          valueIndicatorColor: _onContainer,
          valueIndicatorTextStyle: const TextStyle(color: Colors.white),
        ),

        // ── Snackbars: floating, rounded ──────────────────────────────────
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: _onContainer,
          contentTextStyle: const TextStyle(color: Colors.white),
        ),

        // ── Progress indicator default colour ─────────────────────────────
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: _gold,
        ),
      ),
      home: const MainShell(),
    );
  }
}
