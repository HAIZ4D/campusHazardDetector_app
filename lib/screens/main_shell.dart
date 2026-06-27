// =============================================================================
// MainShell
// -----------------------------------------------------------------------------
// The app's root scaffold. Owns a Material 3 NavigationBar at the bottom and
// an IndexedStack of the 4 tabs above it:
//
//   0 ── Camera      (live ensemble detection + capture)
//   1 ── History     (saved evidence records + Gemini cache)
//   2 ── Hazards     (catalog of all 17 detectable hazard types)
//   3 ── Settings    (frame skip, Gemini status, clear data, about)
//
// Why IndexedStack and not a fresh widget per tap?
//   The camera tab owns a CameraController + 4 loaded TFLite interpreters.
//   Re-initialising them every time the user switches tabs would feel slow.
//   IndexedStack keeps every tab mounted so switching is instant and the
//   camera stream stays warm.
//
//   The trade-off: the camera tab keeps consuming CPU even when hidden. We
//   pass `isActive` into CameraScreen so it can pause the image stream while
//   on other tabs — fixes the battery cost without losing the warm-state UX.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/detection_history_service.dart';
import 'camera_screen.dart';
import 'hazards_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        // IndexedStack keeps every tab mounted; we control camera lifecycle
        // by passing isActive down so the stream pauses while hidden.
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            CameraScreen(isActive: _selectedIndex == 0),
            const HistoryScreen(),
            const HazardsScreen(),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: Consumer<DetectionHistoryService>(
        builder: (_, historyService, __) {
          return NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.camera_alt_outlined),
                selectedIcon: Icon(Icons.camera_alt),
                label: 'Camera',
              ),
              NavigationDestination(
                // Badge with current record count, so the user can see at a
                // glance how much evidence they've captured.
                icon: Badge(
                  isLabelVisible: historyService.count > 0,
                  label: Text('${historyService.count}'),
                  child: const Icon(Icons.history_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: historyService.count > 0,
                  label: Text('${historyService.count}'),
                  child: const Icon(Icons.history),
                ),
                label: 'History',
              ),
              const NavigationDestination(
                icon: Icon(Icons.shield_outlined),
                selectedIcon: Icon(Icons.shield),
                label: 'Hazards',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          );
        },
      ),
    );
  }
}
