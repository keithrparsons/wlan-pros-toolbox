// ConnectedApCache — the app-wide, most-recent connected-AP reading (Batch 8).
//
// THE PROBLEM IT SOLVES. On iOS every Wi-Fi field comes from running the
// companion "WLAN Pros Live" Shortcut, which bounces the user to the Shortcuts
// app. Interface Info never fires that Shortcut; it only reads the LAST stored
// payload (`WiFiDetailsBridge.readLatest`). So if no tool has run the Shortcut
// this session, Interface Info's SSID/BSSID come back null and the screen
// honestly says "not available" — even though the Wi-Fi Information tool, once
// run, demonstrably has the data. The two tools were not sharing the reading.
//
// THE FIX. A single, app-lifetime cache holds the most-recent [ConnectedAp]
// from ANY source. The Wi-Fi Information tool WRITES to it on every reading it
// obtains (the macOS CoreWLAN poll and each iOS live payload). Interface Info
// (and any other consumer) READS from it. Once any tool has a reading, the
// others can show the same identity fields without re-bouncing to Shortcuts.
//
// WHAT THIS IS NOT. It is not an at-launch auto-run of the Shortcut (that would
// yank the user into the Shortcuts app on every cold start — explicitly out of
// scope). It is a passive cache: it only ever holds what a tool already read.
// An on-demand "Refresh Wi-Fi" affordance (a user-initiated Shortcut bounce, on
// iOS) is the honest way to populate it directly; that lives in the UI layer.
//
// HONESTY (GL-005 / GL-008). The cache stores readings verbatim; it never
// fabricates a field. An empty cache reads as exactly that — null, "no reading
// yet" — never a guessed value. Platform-unavailable fields stay null in the
// cached [ConnectedAp] just as they are at the source.
//
// CROSS-PLATFORM. Both platforms feed the same cache cleanly: macOS writes the
// CoreWLAN snapshot, iOS writes the Shortcut-derived (and security-enriched)
// reading. Consumers read one model regardless of which platform produced it.
//
// Web-safe: pure Dart, no `dart:io`, no platform channel. A web build can hold
// the (always-empty) cache without reaching any native code.

import 'package:flutter/foundation.dart';

import 'connected_ap.dart';

/// Holds the most-recent [ConnectedAp] reading for the whole app, so a reading
/// obtained by one tool (the Wi-Fi Information tool) is visible to another
/// (Interface Info) without re-running the iOS Shortcut.
///
/// A [ChangeNotifier]: consumers can listen for live updates, or read [latest]
/// synchronously for a one-shot warm read. Exposed as a process-wide singleton
/// via [instance]; tests construct their own isolated instance.
class ConnectedApCache extends ChangeNotifier {
  /// Creates an isolated cache. Production code uses the shared [instance];
  /// tests build their own so cached state never leaks between cases.
  @visibleForTesting
  ConnectedApCache();

  /// The process-wide shared cache. The Wi-Fi Information tool writes here; the
  /// Interface Info tool (and future consumers) read here.
  static final ConnectedApCache instance = ConnectedApCache();

  ConnectedAp? _latest;
  DateTime? _updatedAt;

  /// The most-recent reading, or null when nothing has been cached yet (cold
  /// cache — no tool has obtained a reading this session). A cold read is the
  /// honest "no reading yet" state, never a fabricated value.
  ConnectedAp? get latest => _latest;

  /// Wall-clock time of the most-recent [update], or null when cold. Lets a
  /// consumer show "as of HH:MM" or decide a cached reading is too stale to
  /// trust without re-reading.
  DateTime? get updatedAt => _updatedAt;

  /// True once any tool has cached at least one reading with real data.
  bool get hasReading => _latest != null;

  /// Records the most-recent reading and notifies listeners. Ignores a null or
  /// data-empty reading so a transient empty payload never clears a good cached
  /// value (an all-null [ConnectedAp] means the source delivered nothing this
  /// cycle, not that the link dropped — the last good reading stands).
  ///
  /// Called by the Wi-Fi Information tool on every reading it obtains: the macOS
  /// CoreWLAN snapshot/poll and each iOS live (security-enriched) payload.
  void update(ConnectedAp? ap) {
    if (ap == null || !ap.hasAnyData) return;
    _latest = ap;
    _updatedAt = DateTime.now();
    notifyListeners();
  }

  /// Clears the cache (back to the honest cold state). Not used in the normal
  /// flow — the cache is intentionally sticky so Interface Info keeps showing
  /// the last reading — but provided for tests and any future "forget" affordance.
  @visibleForTesting
  void clear() {
    _latest = null;
    _updatedAt = null;
    notifyListeners();
  }
}
