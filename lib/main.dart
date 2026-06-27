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

/// Root widget — Material 3 light theme. Camera tab keeps a dark camera
/// preview internally for image contrast, but every other surface in the
/// app reads as a polished light Material 3 surface.
class HazardDetectorApp extends StatelessWidget {
  const HazardDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.deepOrange,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Campus Hazard Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F7FA),

        // ── AppBars: light, no elevation, bold title ─────────────────────
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
          indicatorColor: colorScheme.primaryContainer,
          surfaceTintColor: Colors.transparent,
          height: 72,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
            );
          }),
        ),

        // ── Cards: soft, rounded, subtle elevation ────────────────────────
        cardTheme: CardThemeData(
          color: colorScheme.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          margin: EdgeInsets.zero,
        ),

        // ── Filled buttons: punchy primary ────────────────────────────────
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // ── Outlined buttons: soft outline ────────────────────────────────
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),

        // ── Snackbars: floating, rounded ──────────────────────────────────
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: colorScheme.inverseSurface,
          contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        ),
      ),
      home: const MainShell(),
    );
  }
}
