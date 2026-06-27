// =============================================================================
// AppSettingsService
// -----------------------------------------------------------------------------
// Small in-memory + on-disk store for user-tunable runtime settings.
// Currently:
//   - frameSkip   : how often the camera tab runs the 4-model ensemble
//                    (1 = every frame, higher = smoother UX but staler data)
//   - lastZone   : the last HazardZone the user picked in the camera screen
//                    (restored on next launch so they don't have to re-pick)
//
// Persisted as a JSON file in the app docs directory, the same pattern as
// DetectionHistoryService. Loaded once at startup, awaited before runApp.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/hazard_zone.dart';

class AppSettingsService extends ChangeNotifier {
  // Sensible defaults — match what we shipped before settings became
  // user-tunable.
  static const int defaultFrameSkip = 2;
  static const HazardZone defaultZone = HazardZone.unspecified;

  /// Min / max frame-skip values exposed in the UI slider. 1 = every frame
  /// (most accurate, slowest UI); 4 = every 4th (smoothest, stalest).
  static const int minFrameSkip = 1;
  static const int maxFrameSkip = 4;

  int _frameSkip = defaultFrameSkip;
  HazardZone _lastZone = defaultZone;

  int get frameSkip => _frameSkip;
  HazardZone get lastZone => _lastZone;

  /// Storage file is resolved lazily and cached.
  File? _storageFile;
  static const String _storageFileName = 'app_settings.json';

  // ── Mutators ──────────────────────────────────────────────────────────────

  void setFrameSkip(int value) {
    final clamped = value.clamp(minFrameSkip, maxFrameSkip);
    if (clamped == _frameSkip) return;
    _frameSkip = clamped;
    notifyListeners();
    _persist();
  }

  void setLastZone(HazardZone zone) {
    if (zone == _lastZone) return;
    _lastZone = zone;
    notifyListeners();
    _persist();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> loadFromDisk() async {
    try {
      final file = await _resolveStorageFile();
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      _frameSkip = (decoded['frameSkip'] as int? ?? defaultFrameSkip)
          .clamp(minFrameSkip, maxFrameSkip);
      _lastZone = HazardZone.values.firstWhere(
        (z) => z.name == decoded['lastZone'],
        orElse: () => defaultZone,
      );
      notifyListeners();
      debugPrint(
        '[AppSettingsService] Loaded: frameSkip=$_frameSkip '
        'lastZone=${_lastZone.name}',
      );
    } catch (e) {
      debugPrint('[AppSettingsService] loadFromDisk failed: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _resolveStorageFile();
      final json = jsonEncode({
        'frameSkip': _frameSkip,
        'lastZone': _lastZone.name,
      });
      await file.writeAsString(json, flush: true);
    } catch (e) {
      debugPrint('[AppSettingsService] _persist failed: $e');
    }
  }

  Future<File> _resolveStorageFile() async {
    final cached = _storageFile;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final file = File('${docs.path}/$_storageFileName');
    _storageFile = file;
    return file;
  }
}
