// Roam detector — records BSSID transitions (roams) within the SAME SSID during
// a foreground monitoring session (Feature 2, Felix 2026-06-13, per Pax's gap
// brief Deliverables/2026-06-13-toolbox-gap-feasibility/feasibility-brief.md).
//
// The data already flows: the live sampler folds a full [ConnectedAp] per sample
// into the rolling window on both platforms, and [ConnectedAp] carries `bssid`
// (iOS from the companion Shortcut's BSSID field; macOS from CoreWLAN). The
// sparkline [WifiTimeSeries] retains only RSSI/SNR/Tx/Rx, so a BSSID change — the
// definition of a roam — was invisible to the app. This pure structure closes
// that: feed it each sample (with its timestamp) and it emits a [RoamEvent]
// whenever the BSSID changes while the SSID is unchanged.
//
// HONESTY (GL-005 / GL-008): a roam is recorded ONLY when both the prior and the
// current BSSID are non-null AND non-empty. A null/blank BSSID (the link was
// momentarily unreadable, or the platform hid it) breaks the chain — we never
// invent a roam across an unknown gap, and we never treat "BSSID went null then
// came back" as a roam unless the value genuinely changed. An SSID change is a
// network switch, NOT a roam, and is explicitly excluded. On iOS this captures
// roams during an active FOREGROUND session only (no background Wi-Fi callbacks
// exist on iOS — the same ceiling Wi-Fi Check shares); macOS polls continuously
// while the screen is open.

import 'ap_name_cache.dart';
import 'connected_ap.dart';

/// The AP name to RENDER for a roam-log row, resolved at READ time.
///
/// WHY THIS EXISTS. A [RoamEvent] captures `toApName` at the INSTANT the BSSID
/// changes. The AP-name beacon scan is fire-and-forget, so when the client roams
/// to an AP whose name has never been decoded, that name is still null right
/// then — and the event, once appended to history, is never backfilled. Seconds
/// later the shared [ApNameCache] knows the name, but the history row stays
/// frozen at BSSID-only. Resolving at render time instead of trusting only the
/// capture-instant value closes that race for every row already on screen.
///
/// PRECEDENCE. A name captured ON the event is authoritative and is returned
/// unchanged; the cache is consulted ONLY when the captured name is null or
/// blank. A cache value can therefore never REPLACE a different captured name.
///
/// THE HAZARD THIS GUARDS. Looking a name up by BSSID means a wrong key shows a
/// REAL AP name against the WRONG BSSID — authoritative-looking fabricated data,
/// inside a report a consultant hands to a client. Two rules keep that
/// impossible, and neither may be relaxed:
///   1. The key comes from [ApNameCache.normalizeBssid] — the SAME normalizer
///      the cache keys on. A second hand-rolled normalizer is free to drift, and
///      a drifted key misses silently. Never inline a substitute.
///   2. The lookup is EXACT-KEY only. There is no nearest match, no prefix/OUI
///      match, no fallback to "the last name we saw". A null, blank, or
///      unparseable BSSID resolves to NO name, and a BSSID absent from the cache
///      resolves to NO name.
///
/// HONEST-NULL SURVIVES. An AP that genuinely advertises no name is simply
/// absent from the cache, so it resolves to null here and renders BSSID-only —
/// forever. This backfills a LOST name; it never invents a missing one.
String? resolveApName({
  required String? capturedName,
  required String? bssid,
  ApNameCache? cache,
}) {
  // A name captured at roam time wins outright — never overwritten by the cache.
  final String? captured = capturedName?.trim();
  if (captured != null && captured.isNotEmpty) return captured;

  final String? key = ApNameCache.normalizeBssid(bssid);
  if (key == null) return null; // null/blank BSSID → no name, never a guess.

  final String? cached = (cache ?? ApNameCache.instance).nameFor(key);
  final String? trimmed = cached?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// A single recorded roam: the device moved from [fromBssid] to [toBssid] on the
/// same [ssid], at [at], with the signal, band, and channel read at the moment
/// of the roam.
class RoamEvent {
  const RoamEvent({
    required this.at,
    required this.ssid,
    required this.fromBssid,
    required this.toBssid,
    required this.rssiDbm,
    required this.snrDb,
    this.fromRssiDbm,
    this.fromChannel,
    this.toChannel,
    this.fromBand,
    this.toBand,
    this.fromApName,
    this.toApName,
    this.fromBandDerived = false,
    this.toBandDerived = false,
  });

  /// Wall-clock time the roam was observed (the timestamp of the sample that
  /// first carried the new BSSID).
  final DateTime at;

  /// The network name the roam happened within. Null only when the platform did
  /// not expose the SSID for the sample (the roam is still recorded if both
  /// BSSIDs are known and the SSID did not visibly change).
  final String? ssid;

  /// The BSSID the device left.
  final String fromBssid;

  /// The BSSID the device joined.
  final String toBssid;

  /// RSSI (dBm) on the NEW ("to") AP: the reading at the moment of the roam,
  /// i.e. the first sample that carried the joined BSSID. Null when the platform
  /// omitted RSSI for that sample. See [fromRssiDbm] for the old AP's last
  /// reading, and [toRssiDbm] for a name that mirrors the from/to pair.
  final int? rssiDbm;

  /// RSSI (dBm) on the OLD ("from") AP: the last signal recorded on the prior AP
  /// before the BSSID changed (the anchor's final reading). Null when that AP's
  /// samples carried no RSSI. Honest-null, never guessed: read side by side with
  /// [rssiDbm] this shows whether the client left a weakening AP for a stronger
  /// one, or roamed sideways.
  final int? fromRssiDbm;

  /// Alias for [rssiDbm] that reads symmetrically with [fromRssiDbm]: the RSSI on
  /// the AP the device JOINED. Same value, clearer at a from/to call site.
  int? get toRssiDbm => rssiDbm;

  /// SNR (dB) read at the moment of the roam, or null when unavailable.
  final int? snrDb;

  /// Primary channel of the AP the device left, or null when the sample that
  /// anchored the prior AP carried no channel. Honest-null, never guessed.
  final int? fromChannel;

  /// Primary channel of the AP the device joined, or null when unavailable.
  final int? toChannel;

  /// Band label of the AP the device left ("2.4 GHz" / "5 GHz" / "6 GHz"), or
  /// null when unknown. See [fromBandDerived] for the honesty caveat.
  final String? fromBand;

  /// Band label of the AP the device joined, or null when unknown. See
  /// [toBandDerived] for the honesty caveat.
  final String? toBand;

  /// Vendor-advertised name of the AP the device LEFT (the prior sample's
  /// [ConnectedAp.apName]), or null when that AP advertised none / the platform
  /// exposed no IEs. Honest-null, never guessed.
  final String? fromApName;

  /// Vendor-advertised name of the AP the device JOINED (this sample's
  /// [ConnectedAp.apName]), or null when unavailable. Honest-null, never guessed.
  final String? toApName;

  /// Whether [fromBand] is a computed BEST GUESS rather than a platform-reported
  /// certainty. On iOS the band is computed from the channel number, but it is
  /// only UNCERTAIN when that channel number is valid in more than one band — the
  /// genuinely ambiguous numbers 1/2/5/9/13 (2.4 vs 6 GHz) and 149..177 (5 vs
  /// 6 GHz), per [WiFiBand.bandFromChannelIsAmbiguous]. There the same AP a
  /// laptop labels "6 GHz" can read as the lower band on iPhone. An unambiguous
  /// channel (e.g. 37, 69, 197) resolves to one certain band even on iOS, so this
  /// stays false. macOS / Android / Windows report the band authoritatively. The
  /// channel is exact on every platform; only an ambiguous band is a guess.
  /// Never present a genuinely-derived band as authoritative (GL-005).
  final bool fromBandDerived;

  /// Whether [toBand] was computed app-side from the channel number. Same caveat
  /// as [fromBandDerived].
  final bool toBandDerived;

  /// The AP name to RENDER for the AP the device left — the captured
  /// [fromApName] when one was captured, else the shared cache's decoded name
  /// for [fromBssid]. See [resolveApName].
  String? resolvedFromApName({ApNameCache? cache}) => resolveApName(
        capturedName: fromApName,
        bssid: fromBssid,
        cache: cache,
      );

  /// The AP name to RENDER for the AP the device joined — the captured
  /// [toApName] when one was captured, else the shared cache's decoded name for
  /// [toBssid]. See [resolveApName].
  String? resolvedToApName({ApNameCache? cache}) => resolveApName(
        capturedName: toApName,
        bssid: toBssid,
        cache: cache,
      );

  @override
  String toString() =>
      'RoamEvent($ssid: $fromBssid -> $toBssid @ ${at.toIso8601String()})';
}

/// Detects and retains roam events across a stream of [ConnectedAp] samples.
///
/// Pure and deterministic (an injectable clock keeps it testable): no timers, no
/// I/O. The live sampler calls [observe] for each sample; the UI reads [events].
class RoamDetector {
  RoamDetector({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  final List<RoamEvent> _events = <RoamEvent>[];

  /// The last sample's non-empty BSSID, or null when none has been seen yet (or
  /// the chain was broken by an unreadable sample).
  String? _lastBssid;

  /// The SSID that accompanied [_lastBssid], for the same-network guard.
  String? _lastSsid;

  /// The last RSSI (dBm) recorded on [_lastBssid] — the "from" signal a roam
  /// anchors against (the old AP's final reading). Null until a sample on the
  /// current AP carries one; a later same-AP sample that omits RSSI keeps the
  /// last known good value rather than dropping it.
  int? _lastRssi;

  /// The channel that accompanied [_lastBssid] — the "from" channel a roam
  /// anchors against. Null until a sample carries one.
  int? _lastChannel;

  /// The band label that accompanied [_lastBssid] — the "from" band a roam
  /// anchors against. Null until a sample carries one.
  String? _lastBand;

  /// Whether [_lastBand] was derived app-side (true on iOS). Anchored so the
  /// emitted roam can carry the honest "band derived" marker for the from AP.
  bool _lastBandDerived = false;

  /// The vendor-advertised AP name that accompanied [_lastBssid] — the "from"
  /// AP name a roam anchors against. Null until a sample carries one.
  String? _lastApName;

  /// All roam events observed this session, oldest→newest. Unmodifiable view.
  List<RoamEvent> get events => List<RoamEvent>.unmodifiable(_events);

  /// Number of roams recorded this session.
  int get count => _events.length;

  /// True until the first roam is recorded.
  bool get isEmpty => _events.isEmpty;

  /// The most recent roam, or null when none recorded.
  RoamEvent? get latest => _events.isEmpty ? null : _events.last;

  /// Feeds one connected-AP sample. Records a [RoamEvent] when the BSSID changes
  /// while the device stays on the same SSID. Returns the new event, or null
  /// when this sample was not a roam.
  ///
  /// Rules (GL-005):
  ///   - A null/blank current BSSID breaks the chain (we keep the prior anchor
  ///     so a brief unreadable sample does not fabricate or lose a roam, but we
  ///     never compare against an unknown value).
  ///   - The first known BSSID seeds the anchor; it is not a roam.
  ///   - Same BSSID → no roam.
  ///   - Different BSSID + same SSID → a roam (recorded).
  ///   - Different BSSID + different/absent SSID → a network switch, NOT a roam
  ///     (the anchor is re-seeded; no event recorded).
  RoamEvent? observe(ConnectedAp ap, {DateTime? at}) {
    final String? bssid = _normalize(ap.bssid);
    // An unreadable BSSID does not advance or break the anchor: keep the last
    // known good value so a one-sample gap mid-walk does not split a roam.
    if (bssid == null) return null;

    final String? ssid = ap.ssid;
    final String? prevBssid = _lastBssid;
    final String? prevSsid = _lastSsid;
    final int? prevRssi = _lastRssi;
    final int? prevChannel = _lastChannel;
    final String? prevBand = _lastBand;
    final bool prevBandDerived = _lastBandDerived;
    final String? prevApName = _lastApName;

    // First known BSSID this session — seed the anchor, no roam.
    if (prevBssid == null) {
      _lastBssid = bssid;
      _lastSsid = ssid;
      _lastRssi = ap.rssiDbm;
      _lastChannel = ap.channel;
      _lastBand = ap.band;
      _lastBandDerived = ap.bandDerived;
      _lastApName = ap.apName;
      return null;
    }

    // Unchanged BSSID — still on the same AP. Refresh the SSID / channel / band
    // anchors in case they resolved late (a reading can carry the BSSID before
    // the channel), but record nothing.
    if (bssid == prevBssid) {
      _lastSsid = ssid ?? prevSsid;
      // Track the latest RSSI on this AP so the "from" reading a future roam
      // anchors is the old AP's FINAL signal. A sample that omitted RSSI keeps
      // the last known good value rather than erasing it (honest-null: never
      // fabricate, but do not discard a real prior reading).
      if (ap.rssiDbm != null) _lastRssi = ap.rssiDbm;
      if (ap.channel != null) _lastChannel = ap.channel;
      if (ap.band != null) {
        _lastBand = ap.band;
        _lastBandDerived = ap.bandDerived;
      }
      if (ap.apName != null) _lastApName = ap.apName;
      return null;
    }

    // BSSID changed. A same-SSID change is a roam; a changed (or now-absent)
    // SSID is a network switch, not a roam.
    final bool sameNetwork = _sameSsid(prevSsid, ssid);
    _lastBssid = bssid;
    _lastSsid = ssid;
    _lastRssi = ap.rssiDbm;
    _lastChannel = ap.channel;
    _lastBand = ap.band;
    _lastBandDerived = ap.bandDerived;
    // DELIBERATELY UNGUARDED, unlike the same-BSSID anchor update above. There
    // the guard is right: the BSSID did not change, so a null name is a missing
    // reading for an AP we already named. HERE the BSSID DID change, so the
    // anchor now describes a DIFFERENT radio — carrying the old AP's name
    // forward with an `if (!= null)` guard would attach a real name to the wrong
    // BSSID, which is exactly the fabrication this feature must never commit. A
    // name lost here is recovered honestly at render time by [resolveApName],
    // keyed on the BSSID it actually belongs to. Do not "make these consistent".
    _lastApName = ap.apName;
    if (!sameNetwork) return null;

    final RoamEvent event = RoamEvent(
      at: at ?? _now(),
      ssid: ssid ?? prevSsid,
      fromBssid: prevBssid,
      toBssid: bssid,
      // rssiDbm is the NEW ("to") AP's reading; fromRssiDbm is the old AP's last
      // recorded signal (the anchor). Read together they show whether the client
      // left a weakening AP for a stronger one, or roamed sideways.
      rssiDbm: ap.rssiDbm,
      fromRssiDbm: prevRssi,
      snrDb: ap.snrDb,
      // from* = the anchor's values (the AP we left); to* = this sample's values
      // (the AP we joined). All honest-null: a datum the platform omitted stays
      // null rather than being guessed.
      fromChannel: prevChannel,
      toChannel: ap.channel,
      fromBand: prevBand,
      toBand: ap.band,
      // from = the AP we left (anchor); to = the AP we joined (this sample).
      fromApName: prevApName,
      toApName: ap.apName,
      fromBandDerived: prevBandDerived,
      toBandDerived: ap.bandDerived,
    );
    _events.add(event);
    return event;
  }

  /// Resets the session: clears recorded events and the BSSID anchor. Called
  /// when monitoring stops/restarts so a new walk does not inherit the prior
  /// session's roams.
  void reset() {
    _events.clear();
    _lastBssid = null;
    _lastSsid = null;
    _lastRssi = null;
    _lastChannel = null;
    _lastBand = null;
    _lastBandDerived = false;
    _lastApName = null;
  }

  /// A BSSID is usable only when non-null and non-blank. Returns the trimmed
  /// value, or null when the sample carried no real BSSID.
  static String? _normalize(String? bssid) {
    if (bssid == null) return null;
    final String trimmed = bssid.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Same-network test for the roam guard. Two non-null SSIDs must match
  /// (case-sensitive — SSIDs are case-sensitive). When either side is null the
  /// SSID is unknown, so we cannot assert a network switch: treat an unknown
  /// SSID on a BSSID change as a roam within the (assumed) same network rather
  /// than dropping a real roam — the BSSID change is the stronger signal, and
  /// macOS/iOS both supply the SSID in practice.
  static bool _sameSsid(String? a, String? b) {
    if (a == null || b == null) return true;
    return a == b;
  }
}
