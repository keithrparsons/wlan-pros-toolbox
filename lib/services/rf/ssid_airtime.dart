// SSID Airtime — management-frame airtime as a share of CHANNEL time.
//
// PROVENANCE. This is a port of Jonathan Finney's SSID Airtime Calculator,
// https://github.com/fintheman/wifi-tools (single-file HTML, MIT licensed,
// Copyright (c) 2026 Jonathan Finney). Ported with his explicit permission,
// 2026-08-29. Source read at his VERSION "1.0", VDATE "29 August 2026".
// Attribution belongs in the TOOL UI, not in a credits screen (Keith, 2026-08-30).
//
// WHY THE TOOL EXISTS, in his words: it bugged him "for a couple of years every
// time I saw the 3-4 SSID requirements in best practice documents everywhere."
// The output is the marginal cost of SSID N+1, which is the number that settles
// the argument with a customer.
//
// WHAT IS MODELLED. Beacons and (optionally) probe exchanges, expressed as a
// percentage of CHANNEL time rather than AP time — airtime is a property of the
// channel, so `co` (audible co-channel APs) multiplies the whole figure. That
// framing is his and it is the correct one.
//
// WHAT IS NOT MODELLED, stated so nobody reads a number that is not there:
//   - MCS / spatial streams. Management frames go out at a basic rate, so this
//     is deliberate, not a gap.
//   - DTIM, TIM bitmaps, buffered multicast.
//   - Data-frame airtime beyond the user-supplied offered load.
//   - RTS/CTS and ERP protection. Real, and NOT counted here — see the note in
//     `SsidAirtimeResult.total`.
//
// TWO DELIBERATE DIFFERENCES FROM THE UPSTREAM SOURCE, both documented:
//   1. `kBasicRates` includes 48 Mbps. Upstream's RATES list omits it
//      (verified 2026-08-30 against his source). 48 is a legal OFDM rate and a
//      legitimate basic-rate choice; its absence is an oversight, not a model
//      decision. Report it upstream.
//   2. Nothing else. The arithmetic below is his, function for function.
//
// A BUG PAX REPORTED ON 2026-08-21 IS NO LONGER PRESENT. His earlier build
// selected the DSSS branch with `rate<6`, which sent 11 Mbps — an HR/DSSS (CCK)
// rate — through the OFDM symbol formula. He fixed it before 2026-08-29 by
// testing membership of the DSSS set. Do not "re-fix" it and do not describe it
// as a live defect.
//
// TIMING. HR/DSSS and OFDM do not share timing, and deriving both from the rate
// is what keeps 2.4 GHz honest (his comment, and it is the subtle part):
//   OFDM     preamble 20 us, SIFS 16, slot 9,  CWmin 15
//   HR/DSSS  preamble 192 us (long), SIFS 10, slot 20, CWmin 31

import 'dart:math' as math;

/// The four HR/DSSS (CCK) rates. Membership of this set selects the DSSS PHY.
const List<double> kDsssRates = <double>[1, 2, 5.5, 11];

/// Basic-rate choices offered by the UI. Includes 48, which upstream omits.
const List<double> kBasicRates = <double>[1, 2, 5.5, 6, 9, 11, 12, 18, 24, 36, 48, 54];

/// Amendment presets. Beacon sizes are estimates; replace them from a capture.
///
/// EHT is larger because it adds EHT Capabilities/Operation, the Multi-Link
/// elements, and a mandatory MME for beacon protection.
enum WifiAmendment {
  ac('802.11ac (VHT)', 320, 260, 50),
  ax('802.11ax (HE)', 400, 320, 60),
  be('802.11be (EHT)', 480, 400, 70);

  const WifiAmendment(this.label, this.beaconBytes, this.commonBytes, this.profileBytes);

  final String label;

  /// Full beacon size for a legacy (non-MBSSID) BSS.
  final int beaconBytes;

  /// The shared portion of an MBSSID beacon.
  final int commonBytes;

  /// Per-additional-BSS profile cost inside an MBSSID beacon.
  final int profileBytes;
}

/// PHY timing constants for one modulation family.
class PhyTiming {
  const PhyTiming({
    required this.preambleUs,
    required this.sifsUs,
    required this.slotUs,
    required this.cwMin,
  });

  final double preambleUs;
  final double sifsUs;
  final double slotUs;
  final double cwMin;

  static const PhyTiming ofdm =
      PhyTiming(preambleUs: 20, sifsUs: 16, slotUs: 9, cwMin: 15);

  /// Long preamble and long slot: the honest 802.11b numbers.
  static const PhyTiming dsss =
      PhyTiming(preambleUs: 192, sifsUs: 10, slotUs: 20, cwMin: 31);
}

/// Settings shared across all three band columns.
class SsidAirtimeShared {
  const SsidAirtimeShared({
    this.countContention = false,
    this.countProbes = false,
    this.wildcardPercent = 100,
    this.amendment = WifiAmendment.ax,
    this.mlLinks = 1,
    this.mlBytes = 40,
    this.ofdm = PhyTiming.ofdm,
    this.dsss = PhyTiming.dsss,
  });

  /// When false (the default) the model reports pure OCCUPANCY — the time the
  /// frames themselves are on the air. When true it adds DIFS plus average
  /// backoff, i.e. the channel time an AP consumes to WIN the medium.
  ///
  /// Off by default because occupancy is the figure that survives an argument:
  /// it makes no assumption about contention and cannot be accused of inflating.
  final bool countContention;

  /// Probe exchanges are off by default: they depend on client behaviour, which
  /// is the least defensible input in the model.
  final bool countProbes;

  /// Share of probe requests that are WILDCARD (0..100). A wildcard probe draws
  /// a response from EVERY BSS; a directed probe for a known SSID draws one.
  /// This split decides whether probe cost scales with SSID count at all.
  final double wildcardPercent;

  final WifiAmendment amendment;

  /// 802.11be multi-link: number of links advertised (1..4).
  final int mlLinks;

  /// Bytes added per ADDITIONAL link for the Multi-Link element.
  final double mlBytes;

  final PhyTiming ofdm;
  final PhyTiming dsss;

  /// Extra beacon bytes contributed by 802.11be multi-link advertising.
  double get multiLinkExtraBytes => amendment == WifiAmendment.be
      ? math.max(0, mlLinks - 1) * math.max(0.0, mlBytes)
      : 0.0;

  SsidAirtimeShared copyWith({
    bool? countContention,
    bool? countProbes,
    double? wildcardPercent,
    WifiAmendment? amendment,
    int? mlLinks,
    double? mlBytes,
  }) {
    return SsidAirtimeShared(
      countContention: countContention ?? this.countContention,
      countProbes: countProbes ?? this.countProbes,
      wildcardPercent: wildcardPercent ?? this.wildcardPercent,
      amendment: amendment ?? this.amendment,
      mlLinks: mlLinks ?? this.mlLinks,
      mlBytes: mlBytes ?? this.mlBytes,
      ofdm: ofdm,
      dsss: dsss,
    );
  }
}

/// One band column: 2.4, 5 or 6 GHz.
class SsidAirtimeBand {
  const SsidAirtimeBand({
    required this.name,
    this.ssids = 8,
    this.mbssid = false,
    this.rate = 6,
    this.coChannelAps = 1,
    this.clients = 25,
    this.probesPerMinute = 6,
    this.activeScanning = true,
    this.noCck = false,
    this.beaconIntervalTu = 100,
    this.beaconBytes,
    this.commonBytes,
    this.profileBytes,
    this.probeRequestBytes = 70,
    this.probeResponseBytes = 400,
  });

  final String name;

  /// SSIDs advertised by ONE access point on this band.
  final int ssids;

  /// Multiple BSSID: one beacon carrying a common part plus per-BSS profiles,
  /// instead of one full beacon per SSID.
  final bool mbssid;

  /// The basic rate management frames are sent at, in Mbps.
  final double rate;

  /// Audible co-channel APs, INCLUDING this one. Airtime is a channel property,
  /// so this multiplies the result.
  final int coChannelAps;

  final int clients;
  final double probesPerMinute;
  final bool activeScanning;

  /// 5 and 6 GHz have no CCK. A DSSS rate selected here is coerced to 6 Mbps.
  final bool noCck;

  final double beaconIntervalTu;

  /// Byte sizes. When null they come from the shared amendment preset.
  final double? beaconBytes;
  final double? commonBytes;
  final double? profileBytes;

  final double probeRequestBytes;
  final double probeResponseBytes;

  /// The rate actually used, after the no-CCK coercion.
  double effectiveRate(SsidAirtimeShared shared) =>
      (noCck && kDsssRates.contains(rate)) ? 6 : rate;

  SsidAirtimeBand copyWith({
    int? ssids,
    bool? mbssid,
    double? rate,
    int? coChannelAps,
    int? clients,
    double? probesPerMinute,
    bool? activeScanning,
    double? beaconIntervalTu,
    double? beaconBytes,
    double? commonBytes,
    double? profileBytes,
    double? probeRequestBytes,
    double? probeResponseBytes,
  }) {
    return SsidAirtimeBand(
      name: name,
      ssids: ssids ?? this.ssids,
      mbssid: mbssid ?? this.mbssid,
      rate: rate ?? this.rate,
      coChannelAps: coChannelAps ?? this.coChannelAps,
      clients: clients ?? this.clients,
      probesPerMinute: probesPerMinute ?? this.probesPerMinute,
      activeScanning: activeScanning ?? this.activeScanning,
      noCck: noCck,
      beaconIntervalTu: beaconIntervalTu ?? this.beaconIntervalTu,
      beaconBytes: beaconBytes ?? this.beaconBytes,
      commonBytes: commonBytes ?? this.commonBytes,
      profileBytes: profileBytes ?? this.profileBytes,
      probeRequestBytes: probeRequestBytes ?? this.probeRequestBytes,
      probeResponseBytes: probeResponseBytes ?? this.probeResponseBytes,
    );
  }
}

/// Severity band for a utilisation figure. Thresholds are Finney's.
enum AirtimeSeverity { healthy, busy, congested, oversubscribed }

/// One band's computed airtime.
class SsidAirtimeResult {
  const SsidAirtimeResult({
    required this.beaconPercent,
    required this.probePercent,
    required this.marginalPercent,
    required this.longestTxopUs,
    required this.beaconSizeBytes,
    required this.perApUs,
  });

  /// Beacon airtime as a percentage of channel time.
  final double beaconPercent;

  /// Probe-exchange airtime as a percentage of channel time. Zero unless
  /// probes are switched on.
  final double probePercent;

  /// What advertising ONE MORE SSID would add, in percentage points. This is
  /// the number the whole tool exists to produce.
  final double marginalPercent;

  /// The longest single transmit opportunity, in microseconds. A large value
  /// is a latency argument rather than a throughput one.
  final double longestTxopUs;

  /// Beacon size actually used, in bytes.
  final double beaconSizeBytes;

  /// Total beacon airtime for one AP per beacon interval, in microseconds.
  final double perApUs;

  /// Total MANAGEMENT airtime. This is not total channel utilisation: it counts
  /// no data frames, no RTS/CTS, no ERP protection and no retries.
  double get total => beaconPercent + probePercent;

  AirtimeSeverity get severity {
    if (total > 100) return AirtimeSeverity.oversubscribed;
    if (total < 5) return AirtimeSeverity.healthy;
    if (total < 15) return AirtimeSeverity.busy;
    return AirtimeSeverity.congested;
  }
}

/// The model. Every function below is a direct port; names match the source.
class SsidAirtimeCalculator {
  const SsidAirtimeCalculator(this.shared);

  final SsidAirtimeShared shared;

  /// True when [rate] is an HR/DSSS (CCK) rate.
  bool _isDsss(double rate) => kDsssRates.contains(rate);

  PhyTiming _timing(double rate) => _isDsss(rate) ? shared.dsss : shared.ofdm;

  double _sifsUs(double rate) => _timing(rate).sifsUs;

  /// DIFS plus average backoff, or zero when reporting occupancy only.
  double accessUs(double rate) {
    if (!shared.countContention) return 0;
    final PhyTiming t = _timing(rate);
    return t.sifsUs + 2 * t.slotUs + (t.cwMin / 2) * t.slotUs;
  }

  /// Time on air for a frame of [bytes] at [rate] Mbps.
  ///
  /// DSSS: long preamble plus the PSDU at the CCK rate.
  /// OFDM: preamble plus WHOLE 4 us symbols, including the 22-bit SERVICE and
  /// tail overhead. The ceiling is the part naive implementations miss.
  double frameUs(double bytes, double rate) {
    final PhyTiming t = _timing(rate);
    if (_isDsss(rate)) return t.preambleUs + (8 * bytes) / rate;
    return t.preambleUs + (((22 + 8 * bytes) / (rate * 4)).ceil()) * 4;
  }

  double _beaconBytes(SsidAirtimeBand b) =>
      b.beaconBytes ?? shared.amendment.beaconBytes.toDouble();
  double _commonBytes(SsidAirtimeBand b) =>
      b.commonBytes ?? shared.amendment.commonBytes.toDouble();
  double _profileBytes(SsidAirtimeBand b) =>
      b.profileBytes ?? shared.amendment.profileBytes.toDouble();

  /// Beacon airtime for ONE AP advertising [n] SSIDs, in microseconds.
  ///
  /// MBSSID sends ONE beacon carrying a common part plus (n-1) profiles.
  /// Without it, each SSID costs a whole separate beacon — which is the entire
  /// difference the tool is built to show.
  ({double us, double size}) beaconAp(SsidAirtimeBand b, int n) {
    final double x = shared.multiLinkExtraBytes;
    final double r = b.effectiveRate(shared);
    if (b.mbssid) {
      final double size = _commonBytes(b) + x + (n - 1) * _profileBytes(b);
      return (us: frameUs(size, r) + accessUs(r), size: size);
    }
    final double size = _beaconBytes(b) + x;
    return (us: n * (frameUs(size, r) + accessUs(r)), size: size);
  }

  /// Probe-exchange airtime for one AP, in microseconds per second.
  double probeApPerSec(SsidAirtimeBand b, int n) {
    if (!shared.countProbes || !b.activeScanning) return 0;
    final double rps = b.clients * b.probesPerMinute / 60;
    final double r = b.effectiveRate(shared);
    final double req = frameUs(b.probeRequestBytes, r) + accessUs(r);
    // Response, then SIFS, then the client's ACK (14 bytes).
    final double resp =
        accessUs(r) + frameUs(b.probeResponseBytes, r) + _sifsUs(r) + frameUs(14, r);
    final double w = (shared.wildcardPercent / 100).clamp(0.0, 1.0);
    // A wildcard request is answered by every BSS; a directed one by exactly one.
    final double perReq = w * n + (1 - w) * 1;
    return rps * (req + perReq * resp);
  }

  SsidAirtimeResult compute(SsidAirtimeBand b) {
    final int n = math.max(1, b.ssids);
    final double intervalUs = b.beaconIntervalTu * 1024; // 1 TU = 1024 us, not 1000.
    final ({double us, double size}) beacon = beaconAp(b, n);
    final double probe = probeApPerSec(b, n);

    final double beaconPercent = 100 * beacon.us * b.coChannelAps / intervalUs;
    final double probePercent = 100 * probe * b.coChannelAps / 1e6;

    final double beacon2 = beaconAp(b, n + 1).us;
    final double probe2 = probeApPerSec(b, n + 1);
    final double marginal = 100 * (beacon2 - beacon.us) * b.coChannelAps / intervalUs +
        100 * (probe2 - probe) * b.coChannelAps / 1e6;

    final double r = b.effectiveRate(shared);
    final double txop = (b.mbssid ? beacon.us : beacon.us / n) - accessUs(r);

    return SsidAirtimeResult(
      beaconPercent: beaconPercent,
      probePercent: probePercent,
      marginalPercent: marginal,
      longestTxopUs: txop,
      beaconSizeBytes: beacon.size,
      perApUs: beacon.us,
    );
  }
}
