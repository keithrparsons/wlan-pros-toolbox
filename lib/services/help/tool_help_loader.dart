// ToolHelpLoader — loads assets/help/tool_help.json ONCE and caches the parsed
// [ToolHelpStore] for the process lifetime, plus the global `helpForId` lookup.
//
// This is the thin Flutter-facing wrapper around the pure parser in
// tool_help.dart. The model + parse stay Flutter-free (unit-testable from an
// in-memory string); this file owns the rootBundle load and the cache, matching
// the bundled-asset idiom of PortReferenceService / MacOuiService (loaded +
// parsed once, cached in memory, no HTTP).
//
// Usage:
//   await ToolHelpLoader.ensureLoaded();   // once, at app start (main.dart)
//   final ToolHelp? h = helpForId('fspl'); // synchronous after load; null-safe
//
// Before ensureLoaded completes, helpForId returns null (no help, never faked),
// so a screen built before the load finishes simply hides its help affordance
// and gains it on the next rebuild. App start awaits the load so this window is
// effectively never hit in practice.

import 'package:flutter/services.dart' show rootBundle;

import 'tool_help.dart';

/// The bundled help asset path (declared in pubspec.yaml under `assets:`).
const String kToolHelpAsset = 'assets/help/tool_help.json';

/// Loads and caches the [ToolHelpStore] from the bundled JSON asset.
class ToolHelpLoader {
  ToolHelpLoader._();

  static ToolHelpStore? _store;
  static Future<ToolHelpStore>? _inFlight;

  /// The cached store, or null until [ensureLoaded] completes. Synchronous.
  static ToolHelpStore? get store => _store;

  /// Load + parse the help asset once. Idempotent: concurrent callers share one
  /// in-flight future, and a completed load returns the cached store
  /// immediately. Safe to call from app start and again from any screen.
  static Future<ToolHelpStore> ensureLoaded() {
    final ToolHelpStore? cached = _store;
    if (cached != null) return Future<ToolHelpStore>.value(cached);
    return _inFlight ??= _load();
  }

  static Future<ToolHelpStore> _load() async {
    final String raw = await rootBundle.loadString(kToolHelpAsset);
    final ToolHelpStore parsed = ToolHelpStore.fromJson(raw);
    _store = parsed;
    _inFlight = null;
    return parsed;
  }

  /// Test seam: inject a pre-built store (e.g. from a fixture) so widget tests
  /// don't need an asset bundle. Pass null to reset to the unloaded state.
  static void debugSetStore(ToolHelpStore? store) {
    _store = store;
    _inFlight = null;
  }
}

/// Global help lookup by catalog tool id. Returns null when there is no help
/// entry for [id] (the affordance is hidden, never faked) or before the asset
/// has loaded. Synchronous; reads the cached store.
ToolHelp? helpForId(String id) => ToolHelpLoader.store?.forId(id);
