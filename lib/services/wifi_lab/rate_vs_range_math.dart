// Rate vs Range math for the Wi-Fi Lab (rate-vs-range).
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/18-rate-vs-range.md. The
// sensitivity table is copied cell for cell from
// Deliverables/2026-09-25-wifi-lab-wave3-research/brief.md section 10
// (Rohde & Schwarz 802.11be white paper Table 6-4 and RF Wireless World, which
// agree cell for cell). Pure Dart, no Flutter imports, pinned by
// test/services/wifi_lab/rate_vs_range_math_test.dart.
//
// REUSED, NOT RE-DERIVED (spec 18):
//   - path loss: FsplMath.logDistanceDb (fspl_math.dart), FSPL(1 m) plus
//     10 n log10(d)
//   - thermal noise: SixGhzPsdMath.noiseFloorDbm, -174 dBm/Hz +
//     10 log10(BW Hz) + NF
//   - beacon airtime: SsidAirtimeCalculator (lib/services/rf/ssid_airtime.dart,
//     the ssid-airtime tool), untouched
//
// THE LEGACY RATES ARE MCS-EQUIVALENT. Only 6 Mbps = -82 dBm is backed by the
// brief (through the equal MCS 0 value). 12 to 54 Mbps are mapped to the MCS
// with the same modulation and coding (12 = MCS 1, 18 = MCS 2, 24 = MCS 3,
// 36 = MCS 4, 48 = MCS 5, 54 = MCS 6) and take that MCS's 20 MHz floor, so
// every one of them is labeled "MCS-equivalent" wherever it is shown. 9 Mbps
// (BPSK 3/4) has no MCS with the same modulation and coding and the brief says
// not to ship its -81 figure without a source, so it is not offered. The
// DSSS rates (1, 2, 5.5, 11) have no sensitivity in the brief and are not
// offered either.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'fspl_math.dart';
import 'six_ghz_psd_math.dart';
import '../rf/ssid_airtime.dart';

/// Modulation and coding of one MCS row.
typedef RvrMcsInfo = ({String modulation, String codeRate});

/// A legacy (non-HT OFDM) basic rate and the MCS it is equivalent to.
enum RvrBasicRate {
  mbps6(6, 0),
  mbps12(12, 1),
  mbps18(18, 2),
  mbps24(24, 3),
  mbps36(36, 4),
  mbps48(48, 5),
  mbps54(54, 6);

  const RvrBasicRate(this.mbps, this.equivalentMcs);

  /// Legacy data rate, Mbps.
  final double mbps;

  /// The MCS with the same modulation and coding.
  final int equivalentMcs;

  /// True only for 6 Mbps, whose -82 dBm floor the brief backs directly.
  bool get isSourcedDirectly => this == RvrBasicRate.mbps6;

  String get label => '${mbps.round()} Mbps';
}

abstract final class RateVsRangeMath {
  /// Channel widths, MHz, in table column order.
  static const List<int> widthsMHz = <int>[20, 40, 80, 160, 320];

  /// Highest MCS in the table.
  static const int maxMcs = 13;

  /// Default receiver noise figure, dB (spec 18).
  static const double defaultNoiseFigureDb = 7;

  /// Minimum receiver sensitivity, dBm at 10 % PER (4096-byte PSDU), by MCS
  /// (row) and width (column, 20 / 40 / 80 / 160 / 320 MHz). Brief section
  /// 10, cell for cell. These are conformance floors: real radios do better.
  static const List<List<double>> sensitivityTable = <List<double>>[
    <double>[-82, -79, -76, -73, -70], // MCS 0  BPSK 1/2
    <double>[-79, -76, -73, -70, -67], // MCS 1  QPSK 1/2
    <double>[-77, -74, -71, -68, -65], // MCS 2  QPSK 3/4
    <double>[-74, -71, -68, -65, -62], // MCS 3  16-QAM 1/2
    <double>[-70, -67, -64, -61, -58], // MCS 4  16-QAM 3/4
    <double>[-66, -63, -60, -57, -54], // MCS 5  64-QAM 2/3
    <double>[-65, -62, -59, -56, -53], // MCS 6  64-QAM 3/4
    <double>[-64, -61, -58, -55, -52], // MCS 7  64-QAM 5/6
    <double>[-59, -56, -53, -50, -47], // MCS 8  256-QAM 3/4
    <double>[-57, -54, -51, -48, -45], // MCS 9  256-QAM 5/6
    <double>[-54, -51, -48, -45, -42], // MCS 10 1024-QAM 3/4
    <double>[-52, -49, -46, -43, -40], // MCS 11 1024-QAM 5/6
    <double>[-49, -46, -43, -40, -37], // MCS 12 4096-QAM 3/4
    <double>[-46, -43, -40, -37, -34], // MCS 13 4096-QAM 5/6
  ];

  static const List<RvrMcsInfo> mcsInfo = <RvrMcsInfo>[
    (modulation: 'BPSK', codeRate: '1/2'),
    (modulation: 'QPSK', codeRate: '1/2'),
    (modulation: 'QPSK', codeRate: '3/4'),
    (modulation: '16-QAM', codeRate: '1/2'),
    (modulation: '16-QAM', codeRate: '3/4'),
    (modulation: '64-QAM', codeRate: '2/3'),
    (modulation: '64-QAM', codeRate: '3/4'),
    (modulation: '64-QAM', codeRate: '5/6'),
    (modulation: '256-QAM', codeRate: '3/4'),
    (modulation: '256-QAM', codeRate: '5/6'),
    (modulation: '1024-QAM', codeRate: '3/4'),
    (modulation: '1024-QAM', codeRate: '5/6'),
    (modulation: '4096-QAM', codeRate: '3/4'),
    (modulation: '4096-QAM', codeRate: '5/6'),
  ];

  /// Column of [widthMHz] in [sensitivityTable]. Throws on a width the table
  /// does not carry.
  static int widthIndex(int widthMHz) {
    final int i = widthsMHz.indexOf(widthMHz);
    if (i < 0) throw ArgumentError.value(widthMHz, 'widthMHz');
    return i;
  }

  /// Minimum sensitivity of [mcs] at [widthMHz], dBm.
  static double sensitivityDbm(int mcs, int widthMHz) =>
      sensitivityTable[mcs][widthIndex(widthMHz)];

  /// Cell-edge sensitivity of a legacy basic rate, dBm. Legacy PPDUs are
  /// 20 MHz, so this never moves with the data channel width.
  static double basicRateSensitivityDbm(RvrBasicRate r) =>
      sensitivityTable[r.equivalentMcs][0];

  /// Thermal noise in [widthMHz] before the noise figure, dBm:
  /// -174 dBm/Hz + 10 log10(BW Hz).
  static double thermalNoiseDbm(int widthMHz) =>
      SixGhzPsdMath.noiseFloorDbm(widthMHz, 0);

  /// Receiver noise floor, dBm: thermal noise plus the noise figure.
  static double noiseFloorDbm(int widthMHz, double noiseFigureDb) =>
      SixGhzPsdMath.noiseFloorDbm(widthMHz, noiseFigureDb);

  /// Log-distance path loss, dB: FSPL(1 m) + 10 n log10(d). Below 1 m the
  /// model is not defined, so the distance is held at 1 m.
  static double pathLossDb(double distanceM, double freqMHz, double exponent) =>
      FsplMath.logDistanceDb(math.max(1, distanceM), freqMHz, exponent);

  /// Received power, dBm: AP EIRP + client antenna gain - path loss.
  static double receivedDbm({
    required double eirpDbm,
    required double clientGainDbi,
    required double distanceM,
    required double freqMHz,
    required double exponent,
  }) => FsplMath.receivedPowerDbm(
    txPowerDbm: eirpDbm,
    txGainDbi: 0,
    rxGainDbi: clientGainDbi,
    pathLossDb: pathLossDb(distanceM, freqMHz, exponent),
  );

  /// Distance, m, where received power falls to [thresholdDbm]: the inverse
  /// of [receivedDbm]. Solves EIRP + G - FSPL(1 m) - 10 n log10(d) = threshold.
  /// May come out below 1 m, where the model is not defined; callers say so.
  static double radiusM({
    required double thresholdDbm,
    required double eirpDbm,
    required double clientGainDbi,
    required double freqMHz,
    required double exponent,
  }) {
    final double budget =
        eirpDbm + clientGainDbi - FsplMath.fsplDb(1, freqMHz) - thresholdDbm;
    return math.pow(10, budget / (10 * exponent)).toDouble();
  }

  /// Ring radius of [mcs] at [widthMHz], m: where received power equals the
  /// MCS sensitivity plus [marginDb].
  static double ringRadiusM({
    required int mcs,
    required int widthMHz,
    required double eirpDbm,
    required double clientGainDbi,
    required double freqMHz,
    required double exponent,
    double marginDb = 0,
  }) => radiusM(
    thresholdDbm: sensitivityDbm(mcs, widthMHz) + marginDb,
    eirpDbm: eirpDbm,
    clientGainDbi: clientGainDbi,
    freqMHz: freqMHz,
    exponent: exponent,
  );

  /// Highest MCS whose sensitivity plus [marginDb] is at or below
  /// [receivedDbm], or null when even MCS 0 cannot be decoded.
  static int? mcsFor(double receivedDbm, int widthMHz, {double marginDb = 0}) {
    int? best;
    for (int m = 0; m <= maxMcs; m++) {
      if (receivedDbm >= sensitivityDbm(m, widthMHz) + marginDb) best = m;
    }
    return best;
  }

  /// Beacon airtime as a percentage of channel time for one AP advertising
  /// [ssids] SSIDs at [rate], from the ssid-airtime tool's calculator with its
  /// defaults (802.11ax beacon size, no MBSSID, occupancy only, no probes, one
  /// AP on the channel, 100 TU beacon interval).
  static double beaconAirtimePercent(RvrBasicRate rate, int ssids) {
    const SsidAirtimeCalculator calc = SsidAirtimeCalculator(
      SsidAirtimeShared(),
    );
    return calc
        .compute(
          SsidAirtimeBand(
            name: 'rate-vs-range',
            ssids: ssids,
            rate: rate.mbps,
            coChannelAps: 1,
          ),
        )
        .beaconPercent;
  }

  /// Time on air of one beacon at [rate], microseconds (same calculator).
  static double beaconFrameUs(RvrBasicRate rate) {
    const SsidAirtimeShared shared = SsidAirtimeShared();
    const SsidAirtimeCalculator calc = SsidAirtimeCalculator(shared);
    return calc.frameUs(shared.amendment.beaconBytes.toDouble(), rate.mbps);
  }
}
