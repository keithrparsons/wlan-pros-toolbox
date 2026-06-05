// ThemeController — owns the app's ThemeMode (System / Light / Dark).
//
// GL-003 §8.20.5: three modes mapping to Flutter `ThemeMode.system` /
// `ThemeMode.light` / `ThemeMode.dark`; DEFAULT is System (honor the OS
// appearance on first run); an explicit Light/Dark pick is PERSISTED across
// launches; System re-reads the OS each launch.
//
// Persistence is via shared_preferences (one string key). A read/write failure
// must never block the app — the controller falls back to System and renders
// fine (the dark brand-default still applies where the OS expresses no
// preference). No network, no entitlement (NSUserDefaults / SharedPreferences /
// localStorage under the hood).

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [ChangeNotifier] holding the selected [ThemeMode]. Wire it into
/// `MaterialApp(themeMode:)` and listen so the app re-themes on change.
class ThemeController extends ChangeNotifier {
  ThemeController({ThemeMode initialMode = ThemeMode.system})
      : _mode = initialMode;

  /// The shared_preferences key for the persisted appearance pick.
  static const String prefsKey = 'app_theme_mode';

  ThemeMode _mode;

  /// The active theme mode. `MaterialApp.themeMode` reads this.
  ThemeMode get mode => _mode;

  /// Loads the persisted pick (if any) and applies it. Safe to call before
  /// `runApp`; on any error it leaves the mode at its constructed default
  /// (System) and does not throw.
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? stored = prefs.getString(prefsKey);
      final ThemeMode? parsed = _parse(stored);
      if (parsed != null && parsed != _mode) {
        _mode = parsed;
        notifyListeners();
      }
    } catch (_) {
      // Storage unavailable → keep the System default. No crash.
    }
  }

  /// Sets and persists the user's explicit pick. System is also persisted (so a
  /// user who switched back to System stays on System), and re-reads the OS each
  /// launch by virtue of being `ThemeMode.system`.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, _encode(mode));
    } catch (_) {
      // Persist failed → the in-memory pick still applies this session. No crash.
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'system';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
    }
  }

  static ThemeMode? _parse(String? raw) {
    switch (raw) {
      case 'system':
        return ThemeMode.system;
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return null;
    }
  }
}

/// Exposes the app's [ThemeController] down the tree so the Appearance toggle
/// (and any future surface) can read and drive it without a constructor thread.
/// Wrapped around `MaterialApp` in main.dart.
class ThemeControllerScope extends InheritedNotifier<ThemeController> {
  const ThemeControllerScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The nearest controller. Returns null when no scope is present (e.g. a
  /// widget test that pumps a bare screen) so callers can degrade gracefully.
  static ThemeController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ThemeControllerScope>()
        ?.notifier;
  }
}
