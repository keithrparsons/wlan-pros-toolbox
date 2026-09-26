// Uplink vs Downlink: the pure model for the Wi-Fi Classroom tool
// (uplink-downlink).
//
// CLEAN-ROOM BUILD (2026-09-26) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/28-uplink-downlink.md.
// Regulatory client limits from
// Deliverables/2026-09-25-wifi-lab-wave3-research/brief.md section 1
// (47 CFR 15.407 and ETSI EN 303 687, read by Pax, tagged P), through the
// PowerClass table the 6 GHz Power and PSD tool already carries.
//
// THE LESSON THIS MODEL MUST NEVER CONTRADICT (Keith; myPKA
// Team Knowledge/memory/feedback_ap_client_txpower_matching_is_a_vendor_trope.md):
// AP and client transmit power rarely match, and asymmetry is normal. The
// client is the weak end and needs the AP's extra power. Turning the AP down
// "to match" shrinks the downlink cell and does nothing for the uplink. The
// model offers that action only to SHOW what it does.
//
// REUSED, NOT RE-DERIVED:
//   - path loss, received power, ring radius, MCS lookup, noise floor:
//     RateVsRangeMath (rate_vs_range_math.dart), which itself uses
//     FsplMath.logDistanceDb, PL(d) = FSPL(1 m) + 10 n log10(d), the same
//     log-distance model Roaming Walk uses.
//   - the sensitivity table: RateVsRangeMath.sensitivityTable.
//   - 6 GHz limits and the client -6 dB rule: SixGhzPsdMath.eirp over
//     PowerClass (six_ghz_psd_math.dart).
//
// EACH DIRECTION. Downlink (AP to client) = AP transmit power + AP antenna
// gain - path loss + client antenna gain. Uplink (client to AP) = client
// transmit power + client antenna gain - path loss + AP antenna gain. Path
// loss is the same both ways (one channel, one path). So the two directions
// differ by exactly (AP transmit power - client transmit power): each
// antenna's gain appears in both.
//
// Pure Dart, no Flutter imports, deterministic: every input is explicit and
// nothing is random. Pinned by
// test/services/wifi_lab/uplink_downlink_model_test.dart.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import '../../data/channel_frequency_data.dart';
import 'rate_vs_range_math.dart';
import 'six_ghz_psd_math.dart';

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kUplinkDownlinkToolId = 'uplink-downlink';

/// The 20 MHz channel path loss is taken at, per band. The same channels the
/// FSPL Simulator and Rate vs Range default to (2.4 GHz ch 6, 5 GHz ch 100,
/// 6 GHz ch 37 = 6135 MHz, which sits inside U-NII-5 and inside the EU band,
/// so every 6 GHz preset is legal on it).
const Map<WifiBand, int> kUdChannels = <WifiBand, int>{
  WifiBand.band24: 6,
  WifiBand.band5: 100,
  WifiBand.band6: 37,
};

/// A regulatory preset: which limits set each end's power.
enum UdPreset {
  /// No rule: both transmit powers are free.
  custom(
    label: 'Custom (no rule applied)',
    short: 'Custom',
    apClass: null,
    clientClass: null,
  ),

  /// US 6 GHz Standard Power: client at most 6 dB below the AP's authorized
  /// power, 47 CFR 15.407(a)(8)(i).
  usStandardPower(
    label: 'US 6 GHz Standard Power',
    short: 'US Standard Power',
    apClass: PowerClass.usSpAp,
    clientClass: PowerClass.usSpClient,
  ),

  /// US 6 GHz Geofenced Variable Power: client at most 6 dB below the AP's
  /// authorized power, 47 CFR 15.407(a)(8)(iii).
  usGvp(
    label: 'US 6 GHz Geofenced Variable Power (GVP)',
    short: 'US GVP',
    apClass: PowerClass.usGvpAp,
    clientClass: PowerClass.usGvpClient,
  ),

  /// US 6 GHz Low Power Indoor: the client limit is a flat number, not tied
  /// to the AP, 47 CFR 15.407(a)(5) and (a)(8)(ii).
  usLpi(
    label: 'US 6 GHz Low Power Indoor (LPI)',
    short: 'US LPI',
    apClass: PowerClass.usLpiAp,
    clientClass: PowerClass.usLpiClient,
  ),

  /// EU 6 GHz Low Power Indoor: AP and client share one limit, no offset,
  /// ETSI EN 303 687 Tables 2 and 3.
  euLpi(
    label: 'EU 6 GHz Low Power Indoor (LPI)',
    short: 'EU LPI',
    apClass: PowerClass.euLpi,
    clientClass: PowerClass.euLpi,
  );

  const UdPreset({
    required this.label,
    required this.short,
    required this.apClass,
    required this.clientClass,
  });

  final String label;
  final String short;

  /// The AP's regulatory class, or null for [custom].
  final PowerClass? apClass;

  /// The client's regulatory class, or null for [custom].
  final PowerClass? clientClass;

  /// True for every preset that applies a rule (all of them are 6 GHz).
  bool get isRegulated => this != UdPreset.custom;

  /// True where the client's limit follows the AP's authorized power.
  bool get clientFollowsAp => clientClass?.followsAp != null;

  /// One or two sentences on what the rule says, for the controls.
  String get rule => switch (this) {
    UdPreset.custom =>
      'No regulatory rule: set both transmit powers with the sliders.',
    UdPreset.usStandardPower =>
      'The client may transmit up to 6 dB below its AP\'s authorized power '
          '(47 CFR 15.407(a)(8)(i), the US Code of Federal Regulations), so '
          'its limit moves with the AP. The AP itself may radiate at most '
          '36 dBm.',
    UdPreset.usGvp =>
      'The client may transmit up to 6 dB below its AP\'s authorized power '
          '(47 CFR 15.407(a)(8)(iii), the US Code of Federal Regulations), so '
          'its limit moves with the AP. The AP itself may radiate at most '
          '24 dBm.',
    UdPreset.usLpi =>
      'The client limit is a flat number, not tied to the AP: -1 dBm per MHz '
          'up to 24 dBm, against the AP\'s 5 dBm per MHz up to 30 dBm. The '
          '6 dB gap between them is a coincidence of two flat numbers, not a '
          'rule linking them.',
    UdPreset.euLpi =>
      'AP and client share one limit, 10 dBm per MHz up to 23 dBm, with no '
          'client offset (the European standard EN 303 687).',
  };
}

/// What one direction of the link reads at the client's position.
typedef UdDirection = ({
  double rssiDbm,
  double snrDb,

  /// Highest MCS this direction supports, or null below MCS 0.
  int? mcs,
});

/// The whole link, immutable. Every operation returns a new config.
class UdConfig {
  const UdConfig({
    this.band = WifiBand.band5,
    this.widthMHz = 20,
    this.apTxDbm = defaultApTxDbm,
    this.clientTxDbm = defaultClientTxDbm,
    this.apGainDbi = defaultApGainDbi,
    this.clientGainDbi = defaultClientGainDbi,
    this.exponent = defaultExponent,
    this.preset = UdPreset.custom,
    this.authorizedApEirpDbm,
    this.clientDistanceM = defaultClientDistanceM,
    this.apTxBeforeMatchDbm,
  });

  // ── Ranges and defaults (spec 28). The defaults are ILLUSTRATIVE. ───────

  static const double apTxMin = 0;
  static const double apTxMax = 30;
  static const double clientTxMin = 0;
  static const double clientTxMax = 24;
  static const double apGainMin = 0;
  static const double apGainMax = 8;
  static const double clientGainMin = -5;
  static const double clientGainMax = 3;
  static const double exponentMin = 2;
  static const double exponentMax = 4;

  /// Illustrative.
  static const double defaultApTxDbm = 20;

  /// Illustrative.
  static const double defaultClientTxDbm = 14;

  /// Illustrative.
  static const double defaultApGainDbi = 4;

  /// Illustrative: a phone-class antenna.
  static const double defaultClientGainDbi = -2;

  static const double defaultExponent = 3;
  static const double defaultClientDistanceM = 20;
  static const double minDistanceM = 1;

  /// Receiver noise figure, both ends, dB (the Rate vs Range default).
  static const double noiseFigureDb = RateVsRangeMath.defaultNoiseFigureDb;

  final WifiBand band;
  final int widthMHz;

  /// The AP's transmit power setting, dBm (before its antenna).
  final double apTxDbm;

  /// The client's transmit power setting, dBm, as the slider holds it. Used
  /// only under [UdPreset.custom]; a preset sets the client to its limit
  /// ([clientTxEffectiveDbm]).
  final double clientTxDbm;
  final double apGainDbi;
  final double clientGainDbi;

  /// Path-loss exponent n of the log-distance model.
  final double exponent;
  final UdPreset preset;

  /// Under Standard Power or GVP: the AP's authorized EIRP (its grant). It
  /// follows the AP's own setting, except that "turn AP down to match"
  /// lowers only what the AP transmits, not its grant. Null otherwise.
  final double? authorizedApEirpDbm;
  final double clientDistanceM;

  /// The AP transmit power before "turn AP down to match", so the change can
  /// be shown and put back. Null when no match is in effect.
  final double? apTxBeforeMatchDbm;

  bool get isMatched => apTxBeforeMatchDbm != null;

  // ── Frequency ─────────────────────────────────────────────────────────

  int get channel => kUdChannels[band]!;

  double get freqMHz => channelToFrequency(band, channel)!.toDouble();

  // ── Each end's power ──────────────────────────────────────────────────

  /// AP EIRP, dBm: transmit power + antenna gain.
  double get apEirpDbm => apTxDbm + apGainDbi;

  /// The most EIRP the preset lets the AP radiate at this width, or null
  /// under [UdPreset.custom].
  double? get apCeilingEirpDbm {
    final PowerClass? c = preset.apClass;
    return c == null ? null : SixGhzPsdMath.eirp(c, widthMHz).eirpDbm;
  }

  /// The client's EIRP limit under the preset at this width, or null under
  /// [UdPreset.custom]. For Standard Power and GVP it is also held 6 dB
  /// below the AP's authorized power.
  double? get clientLimitEirpDbm {
    final PowerClass? c = preset.clientClass;
    if (c == null) return null;
    final double auth = authorizedApEirpDbm ?? apEirpDbm;
    return SixGhzPsdMath.eirp(
      c,
      widthMHz,
      spAuthorizedDbm: auth,
      gvpAuthorizedDbm: auth,
    ).eirpDbm;
  }

  /// The client's transmit power in use, dBm. Custom: the slider. Under a
  /// preset the client transmits at the preset's limit, so this is the limit
  /// minus the client antenna gain (and can sit outside the slider's range:
  /// the rule is a ceiling, and many clients cannot reach it).
  double get clientTxEffectiveDbm {
    final double? limit = clientLimitEirpDbm;
    return limit == null ? clientTxDbm : limit - clientGainDbi;
  }

  /// Client EIRP, dBm.
  double get clientEirpDbm => clientTxEffectiveDbm + clientGainDbi;

  // ── The two directions ────────────────────────────────────────────────

  double pathLossDb(double distanceM) =>
      RateVsRangeMath.pathLossDb(distanceM, freqMHz, exponent);

  double get noiseFloorDbm =>
      RateVsRangeMath.noiseFloorDbm(widthMHz, noiseFigureDb);

  /// MCS 0 sensitivity at this width: the level each ring is drawn at.
  double get decodeFloorDbm => RateVsRangeMath.sensitivityDbm(0, widthMHz);

  /// Downlink (AP to client) received level at [distanceM], dBm.
  double downlinkDbmAt(double distanceM) => RateVsRangeMath.receivedDbm(
    eirpDbm: apEirpDbm,
    clientGainDbi: clientGainDbi, // the client's antenna receives
    distanceM: distanceM,
    freqMHz: freqMHz,
    exponent: exponent,
  );

  /// Uplink (client to AP) received level at [distanceM], dBm.
  double uplinkDbmAt(double distanceM) => RateVsRangeMath.receivedDbm(
    eirpDbm: clientEirpDbm,
    clientGainDbi: apGainDbi, // here the AP's antenna receives
    distanceM: distanceM,
    freqMHz: freqMHz,
    exponent: exponent,
  );

  UdDirection _direction(double rssi) => (
    rssiDbm: rssi,
    snrDb: rssi - noiseFloorDbm,
    mcs: RateVsRangeMath.mcsFor(rssi, widthMHz),
  );

  /// The downlink at the client's position.
  UdDirection get downlink => _direction(downlinkDbmAt(clientDistanceM));

  /// The uplink at the client's position.
  UdDirection get uplink => _direction(uplinkDbmAt(clientDistanceM));

  /// Downlink minus uplink, dB. The same at every distance: it equals the
  /// AP's transmit power minus the client's.
  double get imbalanceDb => downlinkDbmAt(1) - uplinkDbmAt(1);

  /// How far the client can still decode the AP (downlink at MCS 0), m.
  double get downlinkRingM => RateVsRangeMath.radiusM(
    thresholdDbm: decodeFloorDbm,
    eirpDbm: apEirpDbm,
    clientGainDbi: clientGainDbi,
    freqMHz: freqMHz,
    exponent: exponent,
  );

  /// How far the AP can still decode the client (uplink at MCS 0), m.
  double get uplinkRingM => RateVsRangeMath.radiusM(
    thresholdDbm: decodeFloorDbm,
    eirpDbm: clientEirpDbm,
    clientGainDbi: apGainDbi,
    freqMHz: freqMHz,
    exponent: exponent,
  );

  /// Width of the zone where one end decodes the other but not the reverse,
  /// m. Zero when the rings coincide.
  double get asymmetryZoneM => (downlinkRingM - uplinkRingM).abs();

  /// True when the client sits where it decodes the AP but the AP cannot
  /// decode it (or the reverse when the uplink ring is the larger).
  bool get clientInZone {
    final double lo = math.min(downlinkRingM, uplinkRingM);
    final double hi = math.max(downlinkRingM, uplinkRingM);
    return clientDistanceM > lo && clientDistanceM <= hi;
  }

  /// A distance inside the asymmetry zone, where one direction decodes and
  /// the other does not: the geometric middle of the zone. Null when the
  /// rings are within 1 % of each other.
  double? get zoneMiddleM {
    final double lo = math.min(downlinkRingM, uplinkRingM);
    final double hi = math.max(downlinkRingM, uplinkRingM);
    if (hi <= lo * 1.01 || hi < minDistanceM) return null;
    return math.sqrt(math.max(lo, minDistanceM) * hi);
  }

  // ── "Turn AP down to match" ───────────────────────────────────────────

  /// True when the AP transmits more than the client and the client's power
  /// is inside the AP slider's range, so the AP can be turned down to it.
  bool get canMatch =>
      !isMatched &&
      clientTxEffectiveDbm < apTxDbm &&
      clientTxEffectiveDbm >= apTxMin;

  // ── Operations: each returns a new config ─────────────────────────────

  UdConfig _copy({
    WifiBand? band,
    int? widthMHz,
    double? apTxDbm,
    double? clientTxDbm,
    double? apGainDbi,
    double? clientGainDbi,
    double? exponent,
    UdPreset? preset,
    double? Function()? authorized,
    double? clientDistanceM,
    double? Function()? beforeMatch,
  }) => UdConfig(
    band: band ?? this.band,
    widthMHz: widthMHz ?? this.widthMHz,
    apTxDbm: apTxDbm ?? this.apTxDbm,
    clientTxDbm: clientTxDbm ?? this.clientTxDbm,
    apGainDbi: apGainDbi ?? this.apGainDbi,
    clientGainDbi: clientGainDbi ?? this.clientGainDbi,
    exponent: exponent ?? this.exponent,
    preset: preset ?? this.preset,
    authorizedApEirpDbm: authorized == null
        ? authorizedApEirpDbm
        : authorized(),
    clientDistanceM: clientDistanceM ?? this.clientDistanceM,
    apTxBeforeMatchDbm: beforeMatch == null
        ? apTxBeforeMatchDbm
        : beforeMatch(),
  );

  /// Re-applies the preset after an AP-side change: the AP is held under its
  /// ceiling, the grant follows the AP, and any match is cleared.
  UdConfig _settle() {
    double ap = apTxDbm.clamp(apTxMin, apTxMax);
    final double? ceiling = apCeilingEirpDbm;
    if (ceiling != null) ap = math.min(ap, ceiling - apGainDbi);
    ap = math.max(ap, apTxMin);
    final UdConfig held = _copy(apTxDbm: ap, beforeMatch: () => null);
    return held._copy(
      authorized: () =>
          held.preset.clientFollowsAp ? held.apEirpDbm : null,
    );
  }

  UdConfig withApTx(double v) => _copy(apTxDbm: v)._settle();

  /// Ignored under a preset, where the rule sets the client.
  UdConfig withClientTx(double v) => preset.isRegulated
      ? this
      : _copy(
          clientTxDbm: v.clamp(clientTxMin, clientTxMax),
          beforeMatch: () => null,
        );

  UdConfig withApGain(double v) =>
      _copy(apGainDbi: v.clamp(apGainMin, apGainMax))._settle();

  UdConfig withClientGain(double v) => _copy(
    clientGainDbi: v.clamp(clientGainMin, clientGainMax),
    beforeMatch: () => null,
  );

  UdConfig withExponent(double v) => _copy(
    exponent: v.clamp(exponentMin, exponentMax),
    beforeMatch: () => null,
  );

  /// Every preset is a 6 GHz rule, so leaving 6 GHz returns to Custom.
  UdConfig withBand(WifiBand b) {
    final int w = b.widthsMHz.contains(widthMHz) ? widthMHz : b.widthsMHz.last;
    final UdPreset p = b == WifiBand.band6 ? preset : UdPreset.custom;
    return _copy(band: b, widthMHz: w, preset: p)._settle();
  }

  /// Under a preset whose AP ceiling depends on width (the PSD-limited
  /// classes), an AP sitting at its old ceiling moves to the new one.
  UdConfig withWidth(int w) {
    if (!band.widthsMHz.contains(w)) return this;
    final double? oldCeiling = apCeilingEirpDbm;
    final bool atCeiling =
        oldCeiling != null && (apEirpDbm - oldCeiling).abs() < 1e-9;
    UdConfig next = _copy(widthMHz: w);
    if (atCeiling) next = next._copy(apTxDbm: next.apCeilingEirpDbm! - apGainDbi);
    return next._settle();
  }

  /// Choosing a preset moves to 6 GHz. Under the flat-limit presets (US and
  /// EU LPI) the AP goes to the most the preset allows, so the two flat
  /// numbers show side by side. Under Standard Power and GVP the AP stays
  /// where it is (held under its cap): there the lesson is that the client
  /// follows the AP as the AP moves.
  UdConfig withPreset(UdPreset p) {
    if (!p.isRegulated) return _copy(preset: p)._settle();
    final UdConfig on6 = _copy(
      preset: p,
      band: WifiBand.band6,
      widthMHz: WifiBand.band6.widthsMHz.contains(widthMHz) ? widthMHz : 20,
    );
    if (p.clientFollowsAp) return on6._settle();
    return on6._copy(apTxDbm: on6.apCeilingEirpDbm! - apGainDbi)._settle();
  }

  UdConfig withClientDistance(double d) => _copy(
    clientDistanceM: d.isFinite ? math.max(minDistanceM, d) : clientDistanceM,
  );

  /// "Turn AP down to match": the AP's transmit power becomes the client's.
  /// Only the AP's transmitter changes. Under Standard Power and GVP the
  /// grant stays where it was, so the client's limit does not move.
  UdConfig matchApToClient() {
    if (!canMatch) return this;
    return _copy(
      apTxDbm: clientTxEffectiveDbm,
      beforeMatch: () => apTxDbm,
    );
  }

  /// Puts the AP back where it was before the match.
  UdConfig undoMatch() {
    final double? before = apTxBeforeMatchDbm;
    if (before == null) return this;
    return _copy(apTxDbm: before, beforeMatch: () => null);
  }

  /// Back to the defaults, keeping the client where it is.
  UdConfig reset() => UdConfig(clientDistanceM: clientDistanceM);

  /// The same link with the AP where it was before the match (or this one).
  UdConfig get beforeMatch => undoMatch();
}

/// Number formatting shared by stage, controls and copy.
abstract final class UdFormat {
  static String n(double v, [int decimals = 1]) {
    final String s = v.toStringAsFixed(decimals);
    return RegExp(r'^-0\.?0*$').hasMatch(s) ? s.substring(1) : s;
  }

  static String dbm(double v) => '${n(v)} dBm';

  static String dist(double d) {
    if (!d.isFinite) return 'beyond range';
    if (d < 1) return 'under 1 m';
    if (d < 10) return '${d.toStringAsFixed(1)} m';
    if (d < 1000) return '${d.round()} m';
    return '${(d / 1000).toStringAsFixed(2)} km';
  }

  static String mcs(int? m) => m == null ? 'below MCS 0' : 'MCS $m';
}

/// The words for what "turn AP down to match" did, from the link before and
/// after. Says what changed and what did not; never calls it an improvement.
String udMatchSummary(UdConfig before, UdConfig after) {
  final String Function(double, [int]) n = UdFormat.n;
  final double downLoss =
      before.downlinkDbmAt(after.clientDistanceM) -
      after.downlinkDbmAt(after.clientDistanceM);
  return 'The AP went from ${n(before.apTxDbm)} to ${n(after.apTxDbm)} dBm, '
      'the client\'s power. What changed: the downlink lost ${n(downLoss)} dB '
      'at every distance, so the ring where the client can decode the AP '
      'shrank from ${UdFormat.dist(before.downlinkRingM)} to '
      '${UdFormat.dist(after.downlinkRingM)}. What did not change: the '
      'uplink. It is still ${UdFormat.dbm(after.uplink.rssiDbm)} here and the '
      'AP still decodes the client out to ${UdFormat.dist(after.uplinkRingM)}, '
      'because the AP\'s transmit power is not part of the uplink. The weak '
      'side of the link is exactly as weak as before.';
}
