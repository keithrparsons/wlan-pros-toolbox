// App-wide shared AP-name cache (feature/shared-apname-cache).
//
// A decoded vendor-advertised AP name is a fact about a BSSID, not about the
// screen that happened to decode it: AP names are stable per BSSID. Before this
// cache, every name-enriching adapter (MacWifiInfoAdapter) held its OWN
// per-instance name map and scan-throttle, so each screen (Wi-Fi Information,
// Interface Info, Test My Connection, the Roaming Log sampler) started COLD —
// even though another screen had decoded the same AP's name seconds earlier, a
// freshly-opened screen re-ran the slow beacon scan and made the user wait.
//
// This singleton hoists BOTH the decoded-name map AND the per-BSSID last-scan
// timestamp out of the adapter and into one app-wide store, so:
//   * once ANY surface decodes a name for a BSSID, EVERY surface serves it
//     instantly on its next read with NO scan (the cross-screen cache hit);
//   * a genuinely-new BSSID triggers exactly ONE throttled fire-and-forget scan
//     app-wide — two adapters can no longer each scan the same not-yet-known
//     BSSID inside the throttle window, because the throttle timestamp is shared.
//
// Concurrency: Dart runs one isolate on a single-threaded event loop, so a plain
// singleton with plain maps needs no locking — no two turns of the loop mutate
// these maps at the same instant.
//
// Honesty (GL-005): this cache stores ONLY names that were really decoded from
// the beacon/probe IEs. A BSSID with no advertised name is simply absent from
// the map (null stays null); the cache NEVER holds a guessed or BSSID-derived
// name. It is a store of already-decoded truth, not a source of guesses.

/// App-wide, BSSID-keyed cache of decoded AP names plus the per-BSSID scan
/// throttle. Adapters read/write [instance]; tests may construct an isolated
/// cache directly, or call [clear] to reset the singleton between cases.
class ApNameCache {
  /// The app-wide shared cache. Every name-enriching adapter reads and writes
  /// THIS instance, so a name decoded on one screen shows instantly on all.
  static final ApNameCache instance = ApNameCache();

  /// Public so tests can construct an isolated cache; app code uses [instance].
  ApNameCache();

  /// Decoded AP names keyed by normalized (trimmed, lowercase) BSSID. AP names
  /// are stable for a BSSID, so once decoded a name is reused with no re-scan.
  final Map<String, String> _nameByBssid = <String, String>{};

  /// Last scan-ATTEMPT time per normalized BSSID, for the shared re-scan
  /// throttle. A BSSID that was scanned and found to advertise no name is not
  /// re-scanned until the floor elapses, so unnamed APs do not storm the radio —
  /// and because the timestamp is shared, two adapters cannot each scan the same
  /// not-yet-known BSSID inside that window.
  final Map<String, DateTime> _lastScanAtByBssid = <String, DateTime>{};

  /// The cached decoded name for [normBssid], or null when none has been decoded
  /// yet. A null return is honest "not decoded", never a guess.
  String? nameFor(String normBssid) => _nameByBssid[normBssid];

  /// Records a REAL decoded name for [normBssid]. Callers must only pass a name
  /// that was actually decoded from the beacon/probe IEs (never a guess).
  void cacheName(String normBssid, String name) {
    _nameByBssid[normBssid] = name;
  }

  /// The last time a scan was ATTEMPTED for [normBssid], or null if never.
  DateTime? lastScanAt(String normBssid) => _lastScanAtByBssid[normBssid];

  /// Stamps a scan attempt for [normBssid] at [at]. Called even when the scan
  /// finds no name, so the throttle protects the radio for unnamed BSSIDs.
  void markScanAttempt(String normBssid, DateTime at) {
    _lastScanAtByBssid[normBssid] = at;
  }

  /// Resets both maps. For test isolation only — the app never clears the cache
  /// (a decoded name stays valid for the life of the process).
  void clear() {
    _nameByBssid.clear();
    _lastScanAtByBssid.clear();
  }
}
