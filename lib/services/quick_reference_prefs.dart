// QuickReferencePrefs: the Favorites and Recents lists on the Quick Reference
// screen (Keith, 2026-11-01).
//
// Stored on the device only, through shared_preferences (already a dependency,
// BSD-3-Clause): NSUserDefaults on iOS and macOS, SharedPreferences on Android,
// localStorage in a browser (so web and WLAN Pi web keep them per browser),
// and a JSON file on Windows and Linux. Each list is a string list of catalog
// tool ids. Nothing leaves the device.
//
// Mirrors UnitSystemController: listeners fire before the write, and a storage
// failure never blocks the screen (the lists still work for the session).

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuickReferencePrefs extends ChangeNotifier {
  static const String favoritesKey = 'quick_reference_favorites';
  static const String recentsKey = 'quick_reference_recents';

  /// How many recently opened items the Recents group keeps.
  static const int maxRecents = 10;

  List<String> _favorites = <String>[];
  List<String> _recents = <String>[];

  /// Favorite tool ids, in the order they were starred.
  List<String> get favorites => List<String>.unmodifiable(_favorites);

  /// Recently opened tool ids, most recent first, at most [maxRecents].
  List<String> get recents => List<String>.unmodifiable(_recents);

  bool isFavorite(String id) => _favorites.contains(id);

  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _favorites = prefs.getStringList(favoritesKey) ?? <String>[];
      _recents = (prefs.getStringList(recentsKey) ?? <String>[])
          .take(maxRecents)
          .toList();
      notifyListeners();
    } catch (_) {
      // Storage unavailable: start empty.
    }
  }

  Future<void> toggleFavorite(String id) async {
    _favorites = isFavorite(id)
        ? _favorites.where((String f) => f != id).toList()
        : <String>[..._favorites, id];
    notifyListeners();
    await _save(favoritesKey, _favorites);
  }

  /// Moves [id] to the front of Recents, dropping the oldest past [maxRecents].
  Future<void> recordOpened(String id) async {
    _recents = <String>[
      id,
      ..._recents.where((String r) => r != id),
    ].take(maxRecents).toList();
    notifyListeners();
    await _save(recentsKey, _recents);
  }

  Future<void> clearRecents() async {
    _recents = <String>[];
    notifyListeners();
    await _save(recentsKey, _recents);
  }

  Future<void> _save(String key, List<String> value) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, value);
    } catch (_) {
      // Persist failed: the in-memory list still applies this session.
    }
  }
}
