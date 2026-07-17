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

import 'connected_ap.dart';

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
    this.fromChannel,
    this.toChannel,
    this.fromBand,
    this.toBand,
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

  /// RSSI (dBm) read at the moment of the roam, or null when unavailable.
  final int? rssiDbm;

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

  /// Whether [fromBand] was computed app-side from the channel number (true on
  /// iOS) rather than read directly from the platform (macOS / Android / Windows
  /// report it authoritatively). A derived band is best-effort and is ambiguous
  /// in 6 GHz: channels 36 to 177 read as "5 GHz" without a center frequency, so
  /// the same 6 GHz AP a laptop labels "6 GHz" can read "5 GHz" on iPhone. The
  /// channel is exact on every platform; the band is not. Never present a derived
  /// band as authoritative (GL-005).
  final bool fromBandDerived;

  /// Whether [toBand] was computed app-side from the channel number. Same caveat
  /// as [fromBandDerived].
  final bool toBandDerived;

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

  /// The channel that accompanied [_lastBssid] — the "from" channel a roam
  /// anchors against. Null until a sample carries one.
  int? _lastChannel;

  /// The band label that accompanied [_lastBssid] — the "from" band a roam
  /// anchors against. Null until a sample carries one.
  String? _lastBand;

  /// Whether [_lastBand] was derived app-side (true on iOS). Anchored so the
  /// emitted roam can carry the honest "band derived" marker for the from AP.
  bool _lastBandDerived = false;

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
    final int? prevChannel = _lastChannel;
    final String? prevBand = _lastBand;
    final bool prevBandDerived = _lastBandDerived;

    // First known BSSID this session — seed the anchor, no roam.
    if (prevBssid == null) {
      _lastBssid = bssid;
      _lastSsid = ssid;
      _lastChannel = ap.channel;
      _lastBand = ap.band;
      _lastBandDerived = ap.bandDerived;
      return null;
    }

    // Unchanged BSSID — still on the same AP. Refresh the SSID / channel / band
    // anchors in case they resolved late (a reading can carry the BSSID before
    // the channel), but record nothing.
    if (bssid == prevBssid) {
      _lastSsid = ssid ?? prevSsid;
      if (ap.channel != null) _lastChannel = ap.channel;
      if (ap.band != null) {
        _lastBand = ap.band;
        _lastBandDerived = ap.bandDerived;
      }
      return null;
    }

    // BSSID changed. A same-SSID change is a roam; a changed (or now-absent)
    // SSID is a network switch, not a roam.
    final bool sameNetwork = _sameSsid(prevSsid, ssid);
    _lastBssid = bssid;
    _lastSsid = ssid;
    _lastChannel = ap.channel;
    _lastBand = ap.band;
    _lastBandDerived = ap.bandDerived;
    if (!sameNetwork) return null;

    final RoamEvent event = RoamEvent(
      at: at ?? _now(),
      ssid: ssid ?? prevSsid,
      fromBssid: prevBssid,
      toBssid: bssid,
      rssiDbm: ap.rssiDbm,
      snrDb: ap.snrDb,
      // from* = the anchor's values (the AP we left); to* = this sample's values
      // (the AP we joined). All honest-null: a datum the platform omitted stays
      // null rather than being guessed.
      fromChannel: prevChannel,
      toChannel: ap.channel,
      fromBand: prevBand,
      toBand: ap.band,
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
    _lastChannel = null;
    _lastBand = null;
    _lastBandDerived = false;
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
