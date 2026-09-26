// MIMO, spatial streams and beamforming model (Wi-Fi Classroom, 2026-09-25).
//
// Pure Dart, no Flutter imports. Built clean-room from MIMO fundamentals and
// the 802.11 sounding frame formats, per the Wi-Fi Classroom spec
// (myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 06-mimo-beamforming.md). This is a TEACHING model: every gain here is an
// ideal upper bound, and every airtime figure is an estimate built from the
// assumptions named beside it.
//
// 1. STREAMS. A link carries Nss = min(Ntx, Nrx, client max) spatial
//    streams. The minimum is symmetric, so a 4x4 AP and a 2x2 client run 2
//    streams in both directions.
//
// 2. SPARE CHAINS. Chains beyond Nss are not wasted:
//      transmit beamforming, ideal:  10 log10(Ntx / Nss) dB
//      receive combining, ideal:     10 log10(Nrx / Nss) dB
//    Both are upper bounds. Real gain is lower and depends on the channel.
//
// 3. BEAM PATTERN. A uniform linear array of N elements at spacing d, steered
//    toward the client, has the array factor
//      AF(theta) = | sum_{n=0}^{N-1} e^{j n (k d cos(theta) + beta)} |
//    with theta measured from the array axis, k = 2 pi / lambda and the
//    steering phase beta = -k d cos(theta0). The screen uses the angle from
//    broadside, phi = 90 deg - theta, so cos(theta) = sin(phi). At d = lambda/2,
//    k d = pi.
//
// 4. SOUNDING. Beamforming needs a fresh channel estimate:
//      NDPA -> SIFS -> NDP -> SIFS -> compressed beamforming report
//    The report carries Givens angles for an Nr x Nc matrix per reported
//    subcarrier group, so it grows with Nr x Nc and with the channel width.
//
// 5. CAPTURE. A sniffer with fewer receive chains than a frame's streams
//    cannot separate them. The FCS-failure contrast for beamformed frames is
//    OUR MEASUREMENT (see [CaptureMeasurement]), never a model output.

import 'dart:math' as math;

/// dB floor for an exact null, so a pattern null is finite on a plot.
const double kPatternFloorDb = -120;

/// SIFS in the 5 and 6 GHz bands, microseconds.
const double kSifsUs = 16;

double _log10(double x) => math.log(x) / math.ln10;

/// 10 log10(ratio), floored at [kPatternFloorDb].
double powerRatioDb(double ratio) => ratio <= 0
    ? kPatternFloorDb
    : math.max(kPatternFloorDb, 10 * _log10(ratio));

// ── Streams and spare chains ────────────────────────────────────────────────

/// Which side transmits.
enum LinkDirection {
  downlink('Downlink', 'AP to client'),
  uplink('Uplink', 'client to AP');

  const LinkDirection(this.label, this.detail);

  final String label;
  final String detail;
}

/// One direction of an AP-client link, and what its chains do.
class MimoLink {
  const MimoLink({
    required this.apChains,
    required this.clientChains,
    required this.direction,
    this.clientMaxStreams,
    this.beamforming = true,
  });

  /// Antenna chains on the AP (1 to 8).
  final int apChains;

  /// Antenna chains on the client (1 to 4).
  final int clientChains;

  final LinkDirection direction;

  /// Streams the client advertises; null means as many as it has chains.
  final int? clientMaxStreams;

  /// AP transmit beamforming. It only acts on the downlink: in this model the
  /// client never beamforms (see the help entry for why).
  final bool beamforming;

  /// Transmitting side's chains.
  int get txChains =>
      direction == LinkDirection.downlink ? apChains : clientChains;

  /// Receiving side's chains.
  int get rxChains =>
      direction == LinkDirection.downlink ? clientChains : apChains;

  /// Nss = min(Ntx, Nrx, client max).
  int get streams =>
      MimoMath.spatialStreams(apChains, clientChains, clientMaxStreams);

  int get spareTx => txChains - streams;
  int get spareRx => rxChains - streams;

  /// True when the transmitter beamforms: downlink, switched on, and at
  /// least two AP chains to steer with.
  bool get isBeamformed =>
      beamforming && direction == LinkDirection.downlink && apChains >= 2;

  /// Ideal transmit beamforming gain, dB (0 when not beamformed).
  double get idealTxBfGainDb =>
      isBeamformed ? MimoMath.idealArrayGainDb(txChains, streams) : 0;

  /// Ideal receive combining gain, dB.
  double get idealCombiningGainDb =>
      MimoMath.idealArrayGainDb(rxChains, streams);
}

/// The pure functions the screen and the tests share.
abstract final class MimoMath {
  /// Nss = min(AP chains, client chains, client max). Never below 1 for
  /// valid inputs (every side has at least one chain).
  static int spatialStreams(int apChains, int clientChains, [int? clientMax]) {
    int n = math.min(apChains, clientChains);
    if (clientMax != null) n = math.min(n, clientMax);
    return math.max(0, n);
  }

  /// Ideal array gain of [chains] over [streams]: 10 log10(chains / streams).
  /// This is the upper bound for transmit beamforming (chains = Ntx) and for
  /// receive combining (chains = Nrx).
  static double idealArrayGainDb(int chains, int streams) {
    if (streams <= 0 || chains <= streams) return 0;
    return 10 * _log10(chains / streams);
  }

  /// Magnitude of the array factor for [elements] at spacing
  /// [spacingWavelengths] (d / lambda), steered to [steerDeg], observed at
  /// [angleDeg]. Angles are from broadside (0 = straight ahead). Not
  /// normalized: the peak is [elements].
  static double arrayFactor({
    required int elements,
    required double angleDeg,
    required double steerDeg,
    double spacingWavelengths = 0.5,
  }) {
    final double kd = 2 * math.pi * spacingWavelengths;
    // cos(theta from the axis) = sin(phi from broadside).
    final double beta = -kd * math.sin(steerDeg * math.pi / 180);
    final double psi = kd * math.sin(angleDeg * math.pi / 180) + beta;
    double re = 0;
    double im = 0;
    for (int n = 0; n < elements; n++) {
      re += math.cos(n * psi);
      im += math.sin(n * psi);
    }
    return math.sqrt(re * re + im * im);
  }

  /// Pattern in dB relative to the steered peak: 20 log10(AF / N).
  static double patternDb({
    required int elements,
    required double angleDeg,
    required double steerDeg,
    double spacingWavelengths = 0.5,
  }) {
    if (elements <= 1) return 0;
    final double af = arrayFactor(
      elements: elements,
      angleDeg: angleDeg,
      steerDeg: steerDeg,
      spacingWavelengths: spacingWavelengths,
    );
    return powerRatioDb((af / elements) * (af / elements));
  }

  /// True when a receiver with [receiveChains] can separate [streams].
  static bool canDecode({required int receiveChains, required int streams}) =>
      receiveChains >= streams;
}

// ── Sounding ────────────────────────────────────────────────────────────────

/// HE channel widths with their data subcarriers and full-band RU size.
enum ChannelWidth {
  w20(20, 234, 242),
  w40(40, 468, 484),
  w80(80, 980, 996),
  w160(160, 1960, 1992);

  const ChannelWidth(this.mhz, this.dataSubcarriers, this.ruTones);

  final int mhz;

  /// HE data subcarriers (sets the report's PHY rate).
  final int dataSubcarriers;

  /// Tones in the full-band HE resource unit (sets how many subcarrier
  /// groups the report covers).
  final int ruTones;

  String get label => '$mhz MHz';
}

/// The assumptions the sounding estimate rests on. Every one is shown on
/// screen or in the help entry, so the estimate is never a bare number.
abstract final class SoundingAssumptions {
  /// NDPA rate: the lowest mandatory OFDM rate, the usual basic rate.
  static const double ndpaRateMbps = 6;

  /// Subcarrier grouping for the report (Ng = 4, the finer HE option).
  static const int grouping = 4;

  /// Codebook bits per angle, HE single-user fine codebook: phi 6, psi 4.
  static const int phiBits = 6;
  static const int psiBits = 4;

  /// The report is sent as an HE SU PPDU, 1 stream, MCS 4 (16-QAM, rate
  /// 3/4), 0.8 us GI.
  static const int reportBitsPerSubcarrier = 3; // 4 bits x 3/4
  static const double heSymbolUs = 13.6; // 12.8 + 0.8 GI

  /// HE legacy + HE-SIG-A preamble before the HE-LTFs: L-STF 8, L-LTF 8,
  /// L-SIG 4, RL-SIG 4, HE-SIG-A 8, HE-STF 4.
  static const double hePreambleBaseUs = 36;

  /// One 2x HE-LTF at 0.8 us GI (report) and at 1.6 us GI (NDP).
  static const double heLtfReportUs = 7.2;
  static const double heLtfNdpUs = 8.0;

  /// Packet extension on the sounding NDP.
  static const double ndpPacketExtensionUs = 4;

  /// Bytes around the report body: 24 MAC header, 1 category, 1 HE action,
  /// 5 HE MIMO Control, 4 FCS.
  static const int reportOverheadBytes = 35;

  /// NDPA with one STA Info field: FC 2, Duration 2, RA 6, TA 6, dialog
  /// token 1, STA Info 4, FCS 4.
  static const int ndpaBytes = 25;
}

/// One segment of the sounding exchange, for the airtime bar.
typedef SoundingSegment = ({String name, double us, bool isGap});

/// The sounding exchange for one beamformee, estimated.
class SoundingEstimate {
  SoundingEstimate({required this.nr, required this.nc, required this.width});

  /// Rows: the beamformer's transmit antennas (the AP chains).
  final int nr;

  /// Columns: the streams the client reports.
  final int nc;
  final ChannelWidth width;

  /// Givens angles per subcarrier: sum over i = 1..min(Nc, Nr - 1) of
  /// 2 (Nr - i). 2x1 and 2x2 give 2, 4x2 gives 10, 4x4 gives 12.
  static int angleCount(int nr, int nc) {
    int a = 0;
    for (int i = 1; i <= math.min(nc, nr - 1); i++) {
      a += 2 * (nr - i);
    }
    return a;
  }

  /// HE-LTFs needed to sound [n] antennas: 1, 2, 4, 4, 6, 6, 8, 8.
  static int heLtfCount(int n) {
    if (n <= 1) return 1;
    if (n == 2) return 2;
    return n.isOdd ? n + 1 : n;
  }

  /// Reported subcarrier groups, estimated as the RU tones over Ng, plus one.
  int get subcarrierGroups =>
      (width.ruTones / SoundingAssumptions.grouping).ceil() + 1;

  int get angles => angleCount(nr, nc);

  /// Report body bits: 8 bits of average SNR per column, then the angles for
  /// every subcarrier group (half phi, half psi).
  int get reportBodyBits =>
      8 * nc +
      subcarrierGroups *
          (angles ~/ 2) *
          (SoundingAssumptions.phiBits + SoundingAssumptions.psiBits);

  /// Whole report frame, bytes (estimate).
  int get reportBytes =>
      (reportBodyBits / 8).ceil() + SoundingAssumptions.reportOverheadBytes;

  /// NDPA duration: legacy OFDM, 20 us preamble plus 4 us symbols of
  /// 16 service bits, the frame, and 6 tail bits.
  double get ndpaUs {
    const double bitsPerSymbol = SoundingAssumptions.ndpaRateMbps * 4;
    final int symbols =
        ((16 + 8 * SoundingAssumptions.ndpaBytes + 6) / bitsPerSymbol).ceil();
    return 20 + 4.0 * symbols;
  }

  /// NDP duration: the HE preamble with one HE-LTF per sounded antenna
  /// (rounded up to the allowed counts), no data, and the packet extension.
  double get ndpUs =>
      SoundingAssumptions.hePreambleBaseUs +
      heLtfCount(nr) * SoundingAssumptions.heLtfNdpUs +
      SoundingAssumptions.ndpPacketExtensionUs;

  /// PHY rate the report is sent at, Mbps.
  double get reportRateMbps =>
      width.dataSubcarriers *
      SoundingAssumptions.reportBitsPerSubcarrier /
      SoundingAssumptions.heSymbolUs;

  /// Report duration: HE SU preamble with one HE-LTF, then data symbols.
  double get reportUs {
    final int ndbps =
        width.dataSubcarriers * SoundingAssumptions.reportBitsPerSubcarrier;
    final int symbols = ((16 + 8 * reportBytes) / ndbps).ceil();
    return SoundingAssumptions.hePreambleBaseUs +
        SoundingAssumptions.heLtfReportUs +
        symbols * SoundingAssumptions.heSymbolUs;
  }

  List<SoundingSegment> get segments => <SoundingSegment>[
    (name: 'NDPA', us: ndpaUs, isGap: false),
    (name: 'SIFS', us: kSifsUs, isGap: true),
    (name: 'NDP', us: ndpUs, isGap: false),
    (name: 'SIFS', us: kSifsUs, isGap: true),
    (name: 'Report', us: reportUs, isGap: false),
  ];

  /// The whole exchange, NDPA start to report end, microseconds. Leaves out
  /// the wait for the medium before the NDPA.
  double get totalUs => ndpaUs + kSifsUs + ndpUs + kSifsUs + reportUs;

  /// Share of airtime spent sounding one client every [intervalMs].
  double shareOfAirtime(double intervalMs) =>
      intervalMs <= 0 ? 0 : math.min(1, totalUs / (intervalMs * 1000));
}

// ── The capture measurement ─────────────────────────────────────────────────

/// OUR MEASUREMENT, not a model output. From the number audit in myPKA
/// Deliverables/2026-08-19-beamforming-blinds-the-sniffer/NUMBER-AUDIT.md:
/// one 802.11ax capture, signal-matched (RSSI values where both groups hold
/// at least 200 frames). Only these corrected figures are used.
abstract final class CaptureMeasurement {
  /// FCS failure, beamformed frames: 14,825 frames.
  static const double fcsFailBeamformedPct = 50.8;
  static const int beamformedFrames = 14825;

  /// FCS failure, frames not beamformed: 6,891 frames.
  static const double fcsFailNotBeamformedPct = 5.1;
  static const int notBeamformedFrames = 6891;

  /// Share of the client's frames that were not beamformed (14,638 of
  /// 15,669).
  static const int clientFramesNotBeamformedPct = 93;

  /// About 10 times (50.75 / 5.11).
  static const int ratio = 10;
}
