// =============================================================================
// DetectionHistoryService
// -----------------------------------------------------------------------------
// In-memory list of saved evidence records, BACKED BY a JSON file on disk so
// captures (and their cached Gemini recommendations) survive app restarts.
//
// Storage layout:
//   <app-docs>/detection_history.json   — the records list, one big JSON array
//   <app-docs>/hazard_captures/*.jpg    — the JPEGs themselves (saved by
//                                          CameraScreen during capture)
//
// Lifecycle:
//   - construct synchronously (Provider wants this)
//   - main() awaits loadFromDisk() ONCE before runApp; the service replays
//     the saved records into the in-memory list and notifies listeners.
//   - every subsequent add/remove/update fires a fire-and-forget _persist()
//     so the disk file stays in sync with memory.
//
// Why JSON-on-disk and not sqflite / hive?
//   The records list is small (tens of entries) and writes are infrequent
//   (only on capture or recommendation cache). Adding a real DB dependency
//   would dwarf the data being stored. The trade-off is that we rewrite the
//   whole file on every change — fine at this scale.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/detection_record.dart';

class DetectionHistoryService extends ChangeNotifier {
  final List<DetectionRecord> _records = [];

  /// Storage file inside the app's documents directory. Resolved lazily on
  /// first use and cached so we don't re-resolve the path on every write.
  File? _storageFile;

  static const String _storageFileName = 'detection_history.json';

  /// Read-only view of all saved records, newest first.
  List<DetectionRecord> get records => List.unmodifiable(_records);

  /// Total number of saved records.
  int get count => _records.length;

  // ── Mutators (each triggers persist) ──────────────────────────────────────

  /// Adds a new record to the top of the list and notifies listeners.
  void addRecord(DetectionRecord record) {
    _records.insert(0, record);
    notifyListeners();
    _persist(); // fire-and-forget
  }

  /// Removes the record with the given [id] and notifies listeners.
  void removeRecord(String id) {
    final removed = _records.length;
    _records.removeWhere((r) => r.id == id);
    if (_records.length != removed) {
      notifyListeners();
      _persist();
    }
  }

  /// Replaces the record with the same id, preserving its list position,
  /// and notifies listeners. Used to write a fetched Gemini recommendation
  /// back into the corresponding record without disturbing its place in
  /// the timeline.
  ///
  /// No-op if no record with [DetectionRecord.id] equal to [updated.id]
  /// currently exists (e.g. user deleted it while Gemini was still working).
  void updateRecord(DetectionRecord updated) {
    final idx = _records.indexWhere((r) => r.id == updated.id);
    if (idx == -1) return;
    _records[idx] = updated;
    notifyListeners();
    _persist();
  }

  /// Look up a record by id, or null when not found.
  DetectionRecord? recordById(String id) {
    for (final r in _records) {
      if (r.id == id) return r;
    }
    return null;
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Loads the records list from disk. Idempotent — safe to call once at
  /// startup; should NOT be called repeatedly. Designed to be awaited from
  /// `main()` before `runApp()` so the UI opens to the right state.
  ///
  /// Failures (missing file, corrupt JSON, IO error) are swallowed with a
  /// debug log — we'd rather start with an empty history than crash the
  /// whole app over a parse error.
  Future<void> loadFromDisk() async {
    try {
      final file = await _resolveStorageFile();
      if (!await file.exists()) {
        // First launch ever, or user cleared app data. Nothing to load.
        return;
      }
      final raw = await file.readAsString();
      if (raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        debugPrint(
          '[DetectionHistoryService] Unexpected JSON root (not a list) — '
          'ignoring.',
        );
        return;
      }

      _records.clear();
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        try {
          _records.add(DetectionRecord.fromJson(entry));
        } catch (e) {
          // Skip individual bad records rather than failing the whole load.
          debugPrint(
            '[DetectionHistoryService] Skipping unparseable record: $e',
          );
        }
      }
      notifyListeners();
      debugPrint(
        '[DetectionHistoryService] Loaded ${_records.length} record(s) '
        'from $_storageFileName',
      );
    } catch (e, st) {
      debugPrint(
        '[DetectionHistoryService] loadFromDisk failed: $e\n$st',
      );
    }
  }

  /// Writes the current records list to disk. Fire-and-forget from mutators
  /// — we don't make addRecord etc. async because callers don't actually
  /// care about persist completion. Failures are logged but otherwise
  /// silent; the in-memory list remains authoritative for this session.
  Future<void> _persist() async {
    try {
      final file = await _resolveStorageFile();
      final json = jsonEncode(_records.map((r) => r.toJson()).toList());
      await file.writeAsString(json, flush: true);
    } catch (e) {
      debugPrint('[DetectionHistoryService] _persist failed: $e');
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
