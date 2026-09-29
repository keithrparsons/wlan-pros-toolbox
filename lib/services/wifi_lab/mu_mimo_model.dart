// OFDMA vs MU-MIMO (Wi-Fi Classroom, 2026-09-29): the pure-Dart model.
//
// CLEAN-ROOM BUILD per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 47-ofdma-vs-mumimo.md and Deliverables/2026-09-29-classroom-eight-features/
// PLAN.md, Feature 8. Written from linear algebra, IEEE Std 802.11-2024 and
// the two Classroom models it reuses. No outside lab tool was opened: do not
// open any folder under myPKA/Deliverables/ whose name contains `mirror`,
// `siam` or `semfio`. Pure Dart, no Flutter imports, pinned by
// test/services/wifi_lab/mu_mimo_model_test.dart.
//
// This is a TEACHING model. Zero-forcing, the line-of-sight channel and the
// optional reflection are ideal pictures that show why MU-MIMO needs clients
// in different directions; they are not a prediction of any real AP's
// scheduler. Every airtime figure is an estimate built from the assumptions
// in [MuAssumption], each shown on screen.
//
// 1. CHANNEL. The AP is a uniform linear array of M elements at half-wave
//    spacing. A client at angle theta from broadside has the line-of-sight
//    channel h = a(theta), a_n = e^{j pi n sin(theta)}, n = 0..M-1 (the same
//    geometry as MimoMath.arrayFactor at d = lambda/2). With the reflection on,
//    h = a(theta) - 0.5 a(theta'), where theta' is the direction of the
//    client's mirror image in a side wall (ILLUSTRATIVE: half strength, phase
//    held at a fixed pi so the numbers do not flicker as a client is dragged).
//
// 2. ZERO-FORCING. Rows of H are h_k^H. W = H^H (H H^H)^-1, so H W = I: each
//    client hears only its own stream. Column k of W has squared norm
//    [(H H^H)^-1]_kk; normalized to unit power, client k's gain is
//    1 / [(H H^H)^-1]_kk, against ||h_k||^2 if the AP beamformed to it alone.
//    The ratio is the ZF loss factor, between 0 and 1. For two clients it is
//    1 - |rho|^2, rho = h_1^H h_2 / (||h_1|| ||h_2||). Tse & Viswanath,
//    Fundamentals of Wireless Communication (2005), ch. 10 (linear precoding
//    on the multi-antenna downlink).
//
// 3. LINK BUDGET. Received power from Rate vs Range (RateVsRangeMath:
//    20 dBm EIRP, log-distance, n = 3, 5.5 GHz). OFDMA: not beamformed; the
//    same power per tone as one client alone, so each client keeps its own SNR
//    and MCS. MU-MIMO: the AP splits its power over K streams (-10 log10 K) and
//    gains the array (+10 log10 M), then loses the ZF factor. MCS from the
//    receiver sensitivity table (RateVsRangeMath.mcsFor), capped at HE MCS 11.
//
// 4. AIRTIME, K clients with one frame each, repeated for the exchanges that
//    share one sounding:
//      OFDMA:   computeOfdma(...).dl, every exchange, UNCHANGED, so this tool
//               and OFDMA Resource Units agree to the tenth of a microsecond.
//      MU-MIMO: AIFS, backoff, HE TB sounding (802.11-2024 26.7.3: NDPA with
//               one STA Info per client, SIFS, NDP, SIFS, BFRP Trigger, SIFS,
//               every report at once in an HE TB PPDU), SIFS, then the HE MU
//               PPDU (one stream per client over the whole channel), SIFS and
//               the block acks. Later exchanges: AIFS, backoff, PPDU, SIFS,
//               acks. The same AIFS, backoff, SIFS, trigger formula and ack
//               formula as the OFDMA timeline.
//
// ARITHMETIC. Whole tenths of a microsecond, as in ofdma_model.dart.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'airtime_anatomy.dart';
import 'complex.dart';
import 'mimo_beamforming_model.dart'
    show ChannelWidth, MimoMath, SoundingAssumptions, SoundingEstimate;
import 'ofdma_model.dart';
import 'rate_vs_range_math.dart';

// ── Limits and fixed inputs ─────────────────────────────────────────────────

/// Array sizes, clients and widths the tool offers.
abstract final class MuLimits {
  static const int minAntennas = 2;
  static const int maxAntennas = 8;
  static const int minClients = 2;
  static const int maxClients = 4;
  static const List<int> widthsMhz = <int>[20, 40, 80, 160];
  static const List<int> exchangeChoices = <int>[1, 2, 4, 8];
  static const List<int> payloadChoices = <int>[100, 500, 1500];

  /// Client distances the stage allows, meters.
  static const double minDistanceM = 2;
  static const double maxDistanceM = 35;

  /// Highest HE MCS.
  static const int maxMcs = 11;

  /// 802.11-2024 27.1.1: MU-MIMO in an RU needs 106 tones or more; up to
  /// 8 users, up to 4 streams each, 8 in total. This tool sends one stream
  /// per client over the whole channel, so every limit holds.
  static const int maxUsersPerRu = 8;
}

/// The fixed link budget, from Rate vs Range.
abstract final class MuLink {
  static const double eirpDbm = 20;
  static const double exponent = 3;
  static const double freqMHz = 5500;
  static const double clientGainDbi = 0;

  /// Side wall for the illustrative reflection: this far to the right of the
  /// AP, meters.
  static const double wallOffsetM = 20;

  /// Reflection strength (amplitude), illustrative.
  static const double reflectionAmplitude = 0.5;

  /// Pair loss beyond which the tool calls a pair "not separable", dB.
  /// Illustrative: at 3 dB the pair has lost half its signal to the nulls.
  static const double separableLimitDb = 3;
}

/// The labeled assumptions. Each one is shown on screen.
enum MuAssumption {
  teaching(
    'Teaching model',
    'Zero-forcing on a line-of-sight channel is the textbook picture of '
        'MU-MIMO, not how any one AP chooses its groups. Real channels '
        'scatter, and real APs regroup clients as they move.',
  ),
  reflection(
    'Reflection (illustrative)',
    'With the wall on, each client also arrives from its mirror image in a '
        'wall 20 m to the right, at half strength and with a fixed phase, so '
        'the numbers hold still while you drag.',
  ),
  linkBudget(
    'Link budget',
    'The same as Rate vs Range: 20 dBm EIRP, distance loss exponent 3, '
        '5.5 GHz, sensitivity floors per MCS. OFDMA keeps each client\'s own '
        'signal; MU-MIMO splits the power over the streams, gains the array '
        'and loses the zero-forcing factor.',
  ),
  report(
    'Sounding report size',
    'Each client reports one column for M antennas with the MU codebook '
        '(9 and 7 bits per angle pair, Ng = 4), 8 bits of average SNR and a '
        '4-bit delta SNR per reported subcarrier (802.11-2024 Table 9-45 and '
        '9.4.1.64). The subcarrier count and frame overhead are the MIMO and '
        'Beamforming tool\'s estimates.',
  ),
  controlRate(
    'Control frames at 24 Mbps',
    'NDPA and BFRP Trigger go at 24 Mbps, like the OFDMA tool\'s trigger. '
        'The MIMO and Beamforming tool sends its NDPA at 6 Mbps, which would '
        'make sounding longer here.',
  ),
  sameTxop(
    'Sounding and the first frame share one TXOP',
    'The first MU PPDU follows the reports after a SIFS. Every later '
        'exchange waits for the medium again, as OFDMA does.',
  ),
  ofdmaEstimates(
    'OFDMA estimates carried over',
    'HE-SIG-B length, the trigger size and the block-ack rate are the '
        'OFDMA Resource Units tool\'s estimates, used on both sides.',
  );

  const MuAssumption(this.title, this.detail);

  final String title;
  final String detail;
}

// ── Scenario ────────────────────────────────────────────────────────────────

/// One client: where it sits relative to the AP.
class MuClient {
  const MuClient({required this.angleDeg, required this.distanceM});

  /// From broadside (straight ahead), -90 to 90 degrees; positive is right.
  final double angleDeg;
  final double distanceM;

  MuClient copyWith({double? angleDeg, double? distanceM}) => MuClient(
    angleDeg: angleDeg ?? this.angleDeg,
    distanceM: distanceM ?? this.distanceM,
  );

  /// Position in meters, AP at the origin, +y straight ahead, +x right.
  (double, double) get xy {
    final double t = angleDeg * math.pi / 180;
    return (distanceM * math.sin(t), distanceM * math.cos(t));
  }

  /// The client at [x], [y] meters, clamped to the allowed distances and to
  /// the half-plane in front of the array.
  static MuClient fromXy(double x, double y) {
    final double yy = math.max(0, y);
    final double d = math
        .sqrt(x * x + yy * yy)
        .clamp(MuLimits.minDistanceM, MuLimits.maxDistanceM);
    final double a = (math.atan2(x, yy) * 180 / math.pi).clamp(-90.0, 90.0);
    return MuClient(angleDeg: a, distanceM: d);
  }

  @override
  bool operator ==(Object other) =>
      other is MuClient &&
      other.angleDeg == angleDeg &&
      other.distanceM == distanceM;

  @override
  int get hashCode => Object.hash(angleDeg, distanceM);
}

/// The inputs.
class MuScenario {
  MuScenario({
    required this.antennas,
    required List<MuClient> clients,
    this.widthMhz = 80,
    this.payloadBytes = 1500,
    this.exchangesPerSounding = 4,
    this.reflection = false,
  }) : clients = List<MuClient>.unmodifiable(clients),
       assert(antennas >= 1),
       assert(clients.isNotEmpty),
       assert(payloadBytes > 0),
       assert(exchangesPerSounding >= 1);

  /// AP antennas, M.
  final int antennas;
  final List<MuClient> clients;
  final int widthMhz;
  final int payloadBytes;

  /// MU exchanges sent on one sounding (the channel is assumed to hold still
  /// that long).
  final int exchangesPerSounding;

  /// The illustrative side-wall reflection.
  final bool reflection;

  int get k => clients.length;
}

// ── Linear algebra ──────────────────────────────────────────────────────────

/// Steering vector of an M-element half-wave ULA toward [angleDeg].
List<Complex> steeringVector(int m, double angleDeg) {
  final double psi = math.pi * math.sin(angleDeg * math.pi / 180);
  return <Complex>[for (int n = 0; n < m; n++) Complex.polar(1, n * psi)];
}

/// Inner product a^H b.
Complex innerH(List<Complex> a, List<Complex> b) {
  Complex s = Complex.zero;
  for (int i = 0; i < a.length; i++) {
    s = s + a[i].conjugate * b[i];
  }
  return s;
}

/// ||v||^2.
double normSq(List<Complex> v) =>
    v.fold<double>(0, (double s, Complex c) => s + c.abs2);

/// Inverse of a square complex matrix by Gauss-Jordan with partial pivoting,
/// or null when it is singular (a pivot below [tolerance] of the largest
/// entry).
List<List<Complex>>? invertComplex(
  List<List<Complex>> a, {
  double tolerance = 1e-9,
}) {
  final int n = a.length;
  double scale = 0;
  for (final List<Complex> row in a) {
    for (final Complex c in row) {
      scale = math.max(scale, c.abs);
    }
  }
  if (scale == 0) return null;
  final List<List<Complex>> m = <List<Complex>>[
    for (int i = 0; i < n; i++)
      <Complex>[
        ...a[i],
        for (int j = 0; j < n; j++) i == j ? Complex.one : Complex.zero,
      ],
  ];
  for (int col = 0; col < n; col++) {
    int pivot = col;
    for (int r = col + 1; r < n; r++) {
      if (m[r][col].abs > m[pivot][col].abs) pivot = r;
    }
    if (m[pivot][col].abs < tolerance * scale) return null;
    if (pivot != col) {
      final List<Complex> t = m[pivot];
      m[pivot] = m[col];
      m[col] = t;
    }
    final Complex p = m[col][col];
    for (int j = 0; j < 2 * n; j++) {
      m[col][j] = m[col][j] / p;
    }
    for (int r = 0; r < n; r++) {
      if (r == col) continue;
      final Complex f = m[r][col];
      if (f == Complex.zero) continue;
      for (int j = 0; j < 2 * n; j++) {
        m[r][j] = m[r][j] - f * m[col][j];
      }
    }
  }
  return <List<Complex>>[for (int i = 0; i < n; i++) m[i].sublist(n)];
}

double _log10(double x) => math.log(x) / math.ln10;

/// Loss in dB for a gain factor between 0 and 1 (infinite at 0).
double lossDbOf(double factor) =>
    factor <= 0 ? double.infinity : -10 * _log10(math.min(1, factor));

// ── Precoding result ────────────────────────────────────────────────────────

/// Two clients and how well zero-forcing separates them.
class MuPair {
  const MuPair({required this.a, required this.b, required this.correlation});

  final int a;
  final int b;

  /// |rho|: 0 = orthogonal, 1 = the same direction.
  final double correlation;

  /// 1 - |rho|^2: what each would keep if these two were the whole group.
  double get factor => math.max(0, 1 - correlation * correlation);

  double get lossDb => lossDbOf(factor);

  bool get separable => lossDb <= MuLink.separableLimitDb;
}

/// Why MU-MIMO cannot serve this group.
enum MuBlock {
  /// A client is too far to decode even alone (OFDMA stops too).
  outOfRange,

  /// More clients than AP antennas: zero-forcing needs K <= M.
  tooManyClients,

  /// Two clients have the same channel, so no null can split them.
  singular,

  /// Zero-forcing is possible, but the loss leaves a stream below MCS 0.
  lossTooHigh,
}

/// What zero-forcing gives this group.
class MuPrecoding {
  const MuPrecoding({
    required this.channels,
    required this.weights,
    required this.factors,
    required this.pairs,
  });

  /// h_k per client.
  final List<List<Complex>> channels;

  /// Unit-norm ZF column w_k per client; null when ZF is impossible.
  final List<List<Complex>>? weights;

  /// ZF loss factor per client (0 to 1); all 0 when ZF is impossible.
  final List<double> factors;

  final List<MuPair> pairs;

  bool get possible => weights != null;

  /// Per-client SNR loss, dB (infinite when impossible).
  List<double> get lossesDb => <double>[
    for (final double f in factors) lossDbOf(f),
  ];

  bool get allSeparable => pairs.every((MuPair p) => p.separable);

  /// Beam power of client [k]'s ZF column toward [angleDeg], relative to the
  /// M-element single-user peak (1.0 = the full array gain M).
  double beamGain(int k, double angleDeg) {
    final List<List<Complex>>? w = weights;
    if (w == null) return 0;
    final List<Complex> a = steeringVector(w[k].length, angleDeg);
    return innerH(a, w[k]).abs2 / w[k].length;
  }
}

/// Channel vector for [c] with [m] antennas.
List<Complex> channelFor(MuClient c, int m, {required bool reflection}) {
  final List<Complex> los = steeringVector(m, c.angleDeg);
  if (!reflection) return los;
  final (double x, double y) = c.xy;
  final double imageX = 2 * MuLink.wallOffsetM - x;
  final double imageDeg = math.atan2(imageX, y) * 180 / math.pi;
  final List<Complex> img = steeringVector(m, imageDeg);
  return <Complex>[
    for (int n = 0; n < m; n++)
      los[n] - img[n].scale(MuLink.reflectionAmplitude),
  ];
}

/// Angle of [c]'s mirror image in the side wall, degrees.
double reflectionAngleDeg(MuClient c) {
  final (double x, double y) = c.xy;
  return math.atan2(2 * MuLink.wallOffsetM - x, y) * 180 / math.pi;
}

/// Zero-forcing for [s].
MuPrecoding zeroForcing(MuScenario s) {
  final int m = s.antennas;
  final int k = s.k;
  final List<List<Complex>> h = <List<Complex>>[
    for (final MuClient c in s.clients)
      channelFor(c, m, reflection: s.reflection),
  ];
  final List<MuPair> pairs = <MuPair>[
    for (int i = 0; i < k; i++)
      for (int j = i + 1; j < k; j++)
        MuPair(
          a: i,
          b: j,
          correlation: math.min(
            1,
            innerH(h[i], h[j]).abs / math.sqrt(normSq(h[i]) * normSq(h[j])),
          ),
        ),
  ];
  List<List<Complex>>? inv;
  if (k <= m) {
    // G = H H^H, G_ij = h_i^H h_j.
    inv = invertComplex(<List<Complex>>[
      for (int i = 0; i < k; i++)
        <Complex>[for (int j = 0; j < k; j++) innerH(h[i], h[j])],
    ]);
  }
  if (inv == null) {
    return MuPrecoding(
      channels: h,
      weights: null,
      factors: List<double>.filled(k, 0),
      pairs: pairs,
    );
  }
  // W = H^H G^-1: column k is sum_j h_j (G^-1)_jk.
  final List<List<Complex>> w = <List<Complex>>[];
  final List<double> factors = <double>[];
  for (int c = 0; c < k; c++) {
    final List<Complex> col = List<Complex>.filled(m, Complex.zero);
    for (int j = 0; j < k; j++) {
      for (int n = 0; n < m; n++) {
        col[n] = col[n] + h[j][n] * inv[j][c];
      }
    }
    final double nn = normSq(col);
    final double diag = inv[c][c].re;
    // Unit-norm column; gain 1/diag against the lone-client ||h||^2.
    w.add(<Complex>[for (final Complex x in col) x.scale(1 / math.sqrt(nn))]);
    final double f = diag <= 0 ? 0 : 1 / (diag * normSq(h[c]));
    factors.add(f.clamp(0.0, 1.0));
  }
  return MuPrecoding(channels: h, weights: w, factors: factors, pairs: pairs);
}

// ── Sounding ────────────────────────────────────────────────────────────────

/// Fixed sizes for the HE TB sounding sequence, pinned in 802.11-2024.
abstract final class MuSounding {
  /// HE NDP Announcement: FC 2, Duration 2, RA 6, TA 6, Sounding Dialog
  /// Token 1, STA Info n x 4, FCS 4 (9.3.1.19, Figure 9-79).
  static const int ndpaFixedBytes = 21;
  static const int ndpaPerStaBytes = 4;

  /// MU codebook, Ng = 4: (phi, psi) = (9, 7) (Table 9-45).
  static const int phiBits = 9;
  static const int psiBits = 7;

  /// Average SNR per stream, 8 bits (9.4.1.63); delta SNR per stream per
  /// reported subcarrier, 4 bits (9.4.1.64, Table 9-127).
  static const int avgSnrBits = 8;
  static const int deltaSnrBits = 4;

  /// Reports go at MCS 4, or the client's own MCS if lower (the same cap the
  /// OFDMA tool uses for its uplink block acks).
  static const int reportMcsCap = 4;

  static int ndpaBytes(int clients) =>
      ndpaFixedBytes + ndpaPerStaBytes * clients;

  /// BFRP Trigger: Common 16 + 8, User Info 5 + 1 (Feedback Segment
  /// Retransmission Bitmap, 9.3.1.22.3 Figure 9-97), FCS 4. The same size as
  /// the OFDMA tool's Basic trigger.
  static int bfrpBytes(int clients) =>
      OfdmaConstants.triggerFixedBytes +
      OfdmaConstants.triggerPerUserBytes * clients;
}

ChannelWidth _channelWidth(int mhz) => switch (mhz) {
  20 => ChannelWidth.w20,
  40 => ChannelWidth.w40,
  80 => ChannelWidth.w80,
  _ => ChannelWidth.w160,
};

/// One client's MU compressed beamforming report, estimated.
class MuReportEstimate {
  MuReportEstimate({required this.antennas, required this.widthMhz})
    : _su = SoundingEstimate(
        nr: antennas,
        nc: 1,
        width: _channelWidth(widthMhz),
      );

  final int antennas;
  final int widthMhz;
  final SoundingEstimate _su;

  /// Reported subcarriers (the MIMO tool's estimate).
  int get subcarrierGroups => _su.subcarrierGroups;

  /// Givens angles per subcarrier for M x 1.
  int get angles => _su.angles;

  int get bodyBits =>
      MuSounding.avgSnrBits +
      subcarrierGroups *
          ((angles ~/ 2) * (MuSounding.phiBits + MuSounding.psiBits) +
              MuSounding.deltaSnrBits);

  int get bytes =>
      (bodyBits / 8).ceil() + SoundingAssumptions.reportOverheadBytes;

  /// The single-user report the MIMO tool would size for the same M x 1,
  /// for comparison.
  int get suBytes => _su.reportBytes;

  /// HE sounding NDP, microseconds (the MIMO tool's estimate for M antennas).
  double get ndpUs => _su.ndpUs;
}

// ── Result ──────────────────────────────────────────────────────────────────

/// One client's link in each scheme.
class MuClientLink {
  const MuClientLink({
    required this.rxDbm,
    required this.ofdmaMcs,
    required this.muSnrChangeDb,
    required this.muMcs,
    required this.zfLossDb,
  });

  /// Received power alone, dBm.
  final double rxDbm;

  /// MCS in OFDMA (the client's own link), or null when out of range.
  final int? ofdmaMcs;

  /// MU-MIMO signal against OFDMA: array gain minus power split minus ZF
  /// loss, dB (minus infinity when ZF is impossible).
  final double muSnrChangeDb;

  /// MCS in MU-MIMO, or null when the stream cannot be decoded.
  final int? muMcs;

  /// Zero-forcing SNR loss, dB.
  final double zfLossDb;
}

/// Which scheme needs less airtime here.
enum MuWinner { ofdma, muMimo, tie, muUnavailable, outOfRange }

class MuResult {
  const MuResult._({
    required this.scenario,
    required this.precoding,
    required this.links,
    required this.ofdmaRu,
    required this.ofdmaMcs,
    required this.ofdmaSingle,
    required this.ofdma,
    required this.mu,
    required this.block,
    required this.soundingTenths,
    required this.soundingStartTenths,
    required this.muDataSymbols,
    required this.report,
  });

  final MuScenario scenario;
  final MuPrecoding precoding;
  final List<MuClientLink> links;

  /// Equal RU each client gets in OFDMA.
  final RuSize ofdmaRu;

  /// The one MCS computeOfdma runs at: the slowest client's, capped at 9
  /// below a 242-tone RU. Null when a client is out of range.
  final int? ofdmaMcs;

  /// computeOfdma for one exchange, untouched (null when out of range).
  final OfdmaResult? ofdmaSingle;

  /// OFDMA, every exchange (null when out of range).
  final OfdmaTimeline? ofdma;

  /// MU-MIMO: sounding plus every exchange (null when [block] is set).
  final OfdmaTimeline? mu;

  final MuBlock? block;

  /// The sounding sequence alone, NDPA to the SIFS after the reports,
  /// tenths (0 when not computed).
  final int soundingTenths;

  /// Where the sounding starts on the MU-MIMO clock, tenths.
  final int soundingStartTenths;

  /// MU PPDU data symbols per client (empty when not computed).
  final List<int> muDataSymbols;

  final MuReportEstimate report;

  int get exchanges => scenario.exchangesPerSounding;

  /// Relative margin under which the two count as a tie.
  static const double tieShare = 0.02;

  MuWinner get winner {
    final OfdmaTimeline? o = ofdma;
    if (o == null) return MuWinner.outOfRange;
    final OfdmaTimeline? m = mu;
    if (m == null) return MuWinner.muUnavailable;
    final int diff = o.totalTenths - m.totalTenths;
    if (diff.abs() <= o.totalTenths * tieShare) return MuWinner.tie;
    return diff > 0 ? MuWinner.muMimo : MuWinner.ofdma;
  }

  /// OFDMA data time per exchange, tenths.
  int get ofdmaDataTenths => ofdmaSingle?.dl?.partTenths(OfdmaPart.data) ?? 0;

  /// MU PPDU data time per exchange, tenths.
  int get muDataTenths => muDataSymbols.isEmpty
      ? 0
      : muDataSymbols.reduce(math.max) * OfdmaConstants.symbolDlTenths;

  /// OFDMA HE MU preamble per exchange, tenths.
  int get ofdmaPreambleTenths =>
      ofdmaSingle?.dl?.partTenths(OfdmaPart.preamble) ?? 0;

  /// MU-MIMO HE MU preamble per exchange, tenths.
  int get muPreambleTenthsEach =>
      mu == null ? 0 : muPreambleTenths(scenario.widthMhz, scenario.k);

  /// OFDMA minus MU-MIMO, tenths (positive: MU-MIMO needs less). Equals
  /// exchanges x (data saved + preamble saved) - sounding.
  int? get savedTenths {
    final OfdmaTimeline? o = ofdma;
    final OfdmaTimeline? m = mu;
    if (o == null || m == null) return null;
    return o.totalTenths - m.totalTenths;
  }

  /// Microseconds the full bar width represents.
  double get scaleUs => math.max(ofdma?.totalUs ?? 0, mu?.totalUs ?? 0);
}

/// HE MU preamble for [users] streams in one full-channel RU, tenths:
/// L-STF 8 + L-LTF 8 + L-SIG 4 + RL-SIG 4 + HE-SIG-A 8, HE-SIG-B (the OFDMA
/// tool's estimate), HE-STF 4, and one 2x HE-LTF per the total stream count
/// (802.11-2024 27.3.11.10, Table 21-13: 1, 2, 4, 4 for 1 to 4 streams).
int muPreambleTenths(int widthMhz, int users) =>
    (OfdmaConstants.legacyAndSigAUs + OfdmaConstants.heStfMuUs) * 10 +
    sigBLength(widthMhz, users).tenths +
    SoundingEstimate.heLtfCount(users) * OfdmaConstants.heLtfDlTenths;

int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;

/// The subframe bytes the OFDMA tool puts in each RU for [payload]: the same
/// Airtime Anatomy call computeOfdma makes.
int ofdmaSubframeBytes(int widthMhz, int payload, int mcs) => computeAirtime(
  AirtimeScenario(
    band: AirtimeBand.ghz5,
    phy: AirtimePhy.he,
    widthMhz: widthMhz,
    mcs: mcs,
    streams: 1,
    guardInterval: GuardInterval.gi08,
    payloadBytes: payload,
    framesAggregated: 1,
    encryptionBytes: OfdmaConstants.encryptionBytes,
    accessCategory: OfdmaConstants.accessCategory,
    controlRateMbps: OfdmaConstants.controlRateMbps,
  ),
).subframeBytes;

/// MCS for a received level: the sensitivity table, capped at HE MCS 11.
int? _mcsAt(double dbm, int widthMhz) {
  final int? m = RateVsRangeMath.mcsFor(dbm, widthMhz);
  return m == null ? null : math.min(m, MuLimits.maxMcs);
}

/// Repeats [single]'s segments [n] times on one clock.
OfdmaTimeline repeatTimeline(OfdmaTimeline single, int n) {
  final List<OfdmaSegment> out = <OfdmaSegment>[];
  int at = 0;
  for (int e = 0; e < n; e++) {
    for (final OfdmaSegment s in single.segments) {
      out.add(_seg(s, at));
      at += s.tenths;
    }
  }
  return OfdmaTimeline(mode: single.mode, segments: out);
}

OfdmaSegment _seg(OfdmaSegment s, int start) => OfdmaSegment(
  kind: s.kind,
  label: s.label,
  shortLabel: s.shortLabel,
  tenths: s.tenths,
  startTenths: start,
  formula: s.formula,
  estimate: s.estimate,
  client: s.client,
  lanes: s.lanes,
);

class _Seq {
  final List<OfdmaSegment> segments = <OfdmaSegment>[];
  int at = 0;

  void add(
    OfdmaSegmentKind kind,
    String label,
    String shortLabel,
    int tenths,
    String formula, {
    OfdmaAssumption? estimate,
    List<int>? lanes,
  }) {
    segments.add(
      OfdmaSegment(
        kind: kind,
        label: label,
        shortLabel: shortLabel,
        tenths: tenths,
        startTenths: at,
        formula: formula,
        estimate: estimate,
        lanes: lanes,
      ),
    );
    at += tenths;
  }
}

/// Runs both schemes for [s].
MuResult computeMuVsOfdma(MuScenario s) {
  final int k = s.k;
  final int m = s.antennas;
  final int w = s.widthMhz;
  final String Function(int) t = formatTenthsUs;
  final MuPrecoding zf = zeroForcing(s);
  final MuReportEstimate report = MuReportEstimate(antennas: m, widthMhz: w);

  // ── Links ────────────────────────────────────────────────────────────────
  final double gainDb = 10 * _log10(m / k);
  final List<MuClientLink> links = <MuClientLink>[];
  for (int i = 0; i < k; i++) {
    final MuClient c = s.clients[i];
    final double rx = RateVsRangeMath.receivedDbm(
      eirpDbm: MuLink.eirpDbm,
      clientGainDbi: MuLink.clientGainDbi,
      distanceM: c.distanceM,
      freqMHz: MuLink.freqMHz,
      exponent: MuLink.exponent,
    );
    final double loss = zf.possible ? lossDbOf(zf.factors[i]) : double.infinity;
    final double change = gainDb - loss;
    links.add(
      MuClientLink(
        rxDbm: rx,
        ofdmaMcs: _mcsAt(rx, w),
        muSnrChangeDb: change,
        muMcs: change.isFinite ? _mcsAt(rx + change, w) : null,
        zfLossDb: loss,
      ),
    );
  }

  final RuSize ru = OfdmaTonePlan.largestEqualFit(w, k);
  final bool anyOut = links.any((MuClientLink l) => l.ofdmaMcs == null);
  int? ofdmaMcs;
  if (!anyOut) {
    ofdmaMcs = links.map((MuClientLink l) => l.ofdmaMcs!).reduce(math.min);
    if (ru.tones < RuSize.ru242.tones) ofdmaMcs = math.min(ofdmaMcs, 9);
  }

  MuBlock? block;
  if (anyOut) {
    block = MuBlock.outOfRange;
  } else if (k > m) {
    block = MuBlock.tooManyClients;
  } else if (!zf.possible) {
    block = MuBlock.singular;
  } else if (links.any((MuClientLink l) => l.muMcs == null)) {
    block = MuBlock.lossTooHigh;
  }

  if (anyOut) {
    return MuResult._(
      scenario: s,
      precoding: zf,
      links: links,
      ofdmaRu: ru,
      ofdmaMcs: null,
      ofdmaSingle: null,
      ofdma: null,
      mu: null,
      block: block,
      soundingTenths: 0,
      soundingStartTenths: 0,
      muDataSymbols: const <int>[],
      report: report,
    );
  }

  // ── OFDMA: computeOfdma, untouched ──────────────────────────────────────
  final OfdmaResult single = computeOfdma(
    OfdmaScenario(
      widthMhz: w,
      ruSizes: List<RuSize>.filled(k, ru),
      payloadBytes: s.payloadBytes,
      mcs: ofdmaMcs!,
    ),
  );
  final OfdmaTimeline ofdma = repeatTimeline(
    single.dl!,
    s.exchangesPerSounding,
  );

  if (block != null) {
    return MuResult._(
      scenario: s,
      precoding: zf,
      links: links,
      ofdmaRu: ru,
      ofdmaMcs: ofdmaMcs,
      ofdmaSingle: single,
      ofdma: ofdma,
      mu: null,
      block: block,
      soundingTenths: 0,
      soundingStartTenths: 0,
      muDataSymbols: const <int>[],
      report: report,
    );
  }

  // ── MU-MIMO ──────────────────────────────────────────────────────────────
  // Shared pieces, from the same sources as the OFDMA timeline.
  final List<OfdmaSegment> dl = single.dl!.segments;
  final OfdmaSegment aifsSeg = dl.firstWhere(
    (OfdmaSegment x) => x.kind == OfdmaSegmentKind.aifs,
  );
  final OfdmaSegment backoffSeg = dl.firstWhere(
    (OfdmaSegment x) => x.kind == OfdmaSegmentKind.backoff,
  );
  final OfdmaSegment sifsSeg = dl.firstWhere(
    (OfdmaSegment x) => x.kind == OfdmaSegmentKind.sifs,
  );
  final OfdmaSegment ackSeg = dl.firstWhere(
    (OfdmaSegment x) => x.kind == OfdmaSegmentKind.ack,
  );
  final int sifs = sifsSeg.tenths;
  const int rate = OfdmaConstants.controlRateMbps;

  final int ndpaBytes = MuSounding.ndpaBytes(k);
  final int ndpa = controlFrameTenths(ndpaBytes, rate, 0);
  final int ndp = (report.ndpUs * 10).round();
  final int bfrpBytes = MuSounding.bfrpBytes(k);
  final int bfrp = controlFrameTenths(bfrpBytes, rate, 0);

  // Reports: every client at once in an HE TB PPDU, each in an equal RU.
  final int tbPre =
      (OfdmaConstants.legacyAndSigAUs + OfdmaConstants.heStfTbUs) * 10 +
      OfdmaConstants.heLtfTbTenths;
  final int reportBits =
      16 + 8 * (report.bytes + AirtimeConstants.ampduDelimiterBytes);
  int reportSym = 0;
  final List<int> reportMcs = <int>[];
  for (final MuClientLink l in links) {
    final int mcs = math.min(l.ofdmaMcs!, MuSounding.reportMcsCap);
    reportMcs.add(mcs);
    reportSym = math.max(
      reportSym,
      _ceilDiv(reportBits, ruBitsPerSymbol(ru, mcs)),
    );
  }
  final int reports = tbPre + reportSym * OfdmaConstants.symbolTbTenths;

  // The MU PPDU.
  final int sub = ofdmaSubframeBytes(w, s.payloadBytes, ofdmaMcs);
  final RuSize full = OfdmaTonePlan.fullChannel(w);
  final List<int> symbols = <int>[
    for (final MuClientLink l in links)
      _ceilDiv(16 + 8 * sub, ruBitsPerSymbol(full, l.muMcs!)),
  ];
  final int maxSym = symbols.reduce(math.max);
  final int pre = muPreambleTenths(w, k);
  final SigBLength sigB = sigBLength(w, k);
  final int slowest = symbols.indexOf(maxSym);

  final _Seq q = _Seq();
  void exchange({required bool afterSounding}) {
    if (!afterSounding) {
      q
        ..add(
          OfdmaSegmentKind.aifs,
          'AIFS',
          'AIFS',
          aifsSeg.tenths,
          aifsSeg.formula,
        )
        ..add(
          OfdmaSegmentKind.backoff,
          'Backoff',
          'Backoff',
          backoffSeg.tenths,
          backoffSeg.formula,
        );
    }
    q
      ..add(
        OfdmaSegmentKind.preamble,
        'HE MU preamble',
        'Preamble',
        pre,
        'L-STF 8 + L-LTF 8 + L-SIG 4 + RL-SIG 4 + HE-SIG-A 8 + HE-SIG-B '
            '${sigB.symbols} x 4 + HE-STF 4 + '
            '${SoundingEstimate.heLtfCount(k)} HE-LTF x 7.2 (one per stream, '
            '$k streams) = ${t(pre)} µs.',
        estimate: OfdmaAssumption.sigB,
      )
      ..add(
        OfdmaSegmentKind.data,
        'Data, every stream at once',
        'Data',
        maxSym * OfdmaConstants.symbolDlTenths,
        'Every client gets the whole ${full.toneLabel} channel, one stream '
            'each. Set by the slowest stream: ceil((16 + 8 x $sub bytes) / '
            '${ruBitsPerSymbol(full, links[slowest].muMcs!)} bits per symbol '
            'at MCS ${links[slowest].muMcs} for ${clientLetter(slowest)}) = '
            '$maxSym symbols x 13.6 µs = '
            '${t(maxSym * OfdmaConstants.symbolDlTenths)} µs.',
        lanes: <int>[
          for (final int x in symbols) x * OfdmaConstants.symbolDlTenths,
        ],
      )
      ..add(OfdmaSegmentKind.sifs, 'SIFS', 'SIFS', sifs, sifsSeg.formula)
      ..add(
        OfdmaSegmentKind.ack,
        'Block acks (HE TB PPDU)',
        'BAs',
        ackSeg.tenths,
        '${ackSeg.formula} The same answer as after OFDMA: each client '
            'replies in its own ${ru.toneLabel} RU.',
        estimate: OfdmaAssumption.dlAck,
      );
  }

  q
    ..add(
      OfdmaSegmentKind.aifs,
      'AIFS',
      'AIFS',
      aifsSeg.tenths,
      aifsSeg.formula,
    )
    ..add(
      OfdmaSegmentKind.backoff,
      'Backoff',
      'Backoff',
      backoffSeg.tenths,
      backoffSeg.formula,
    );
  final int soundStart = q.at;
  q
    ..add(
      OfdmaSegmentKind.trigger,
      'HE NDP Announcement',
      'NDPA',
      ndpa,
      'FC 2 + Duration 2 + RA 6 + TA 6 + Dialog Token 1 + $k STA Info x 4 + '
          'FCS 4 = $ndpaBytes bytes at $rate Mbps: 20 + 4 x ceil((16 + 8 x '
          '$ndpaBytes + 6) / ${rate * 4}) = ${t(ndpa)} µs '
          '(802.11-2024 Figure 9-79).',
    )
    ..add(OfdmaSegmentKind.sifs, 'SIFS', 'SIFS', sifs, sifsSeg.formula)
    ..add(
      OfdmaSegmentKind.preamble,
      'HE sounding NDP',
      'NDP',
      ndp,
      'HE preamble 36 + ${SoundingEstimate.heLtfCount(m)} HE-LTF x 8.0 '
          '(one per AP antenna, $m antennas) + packet extension 4 = '
          '${t(ndp)} µs, no data (the MIMO and Beamforming tool\'s estimate).',
    )
    ..add(OfdmaSegmentKind.sifs, 'SIFS', 'SIFS', sifs, sifsSeg.formula)
    ..add(
      OfdmaSegmentKind.trigger,
      'BFRP Trigger',
      'BFRP',
      bfrp,
      'Common 16 + 8, User Info 6 x $k, FCS 4 = $bfrpBytes bytes at $rate '
          'Mbps = ${t(bfrp)} µs (9.3.1.22.3).',
      estimate: OfdmaAssumption.trigger,
    )
    ..add(OfdmaSegmentKind.sifs, 'SIFS', 'SIFS', sifs, sifsSeg.formula)
    ..add(
      OfdmaSegmentKind.ack,
      'Beamforming reports (HE TB PPDU)',
      'Reports',
      reports,
      'Every client at once in its own ${ru.toneLabel} RU. Each report: '
          '${report.subcarrierGroups} subcarriers x (${report.angles ~/ 2} x '
          '(${MuSounding.phiBits} + ${MuSounding.psiBits}) angle bits + '
          '${MuSounding.deltaSnrBits} delta SNR) + ${MuSounding.avgSnrBits} '
          '= ${report.bodyBits} bits, ${report.bytes} bytes with headers. '
          'HE TB preamble ${t(tbPre)} + $reportSym symbols x 14.4 at MCS '
          '${reportMcs.reduce(math.min)} = ${t(reports)} µs.',
    )
    ..add(OfdmaSegmentKind.sifs, 'SIFS', 'SIFS', sifs, sifsSeg.formula);
  final int soundingTenths = q.at - soundStart;
  exchange(afterSounding: true);
  for (int e = 1; e < s.exchangesPerSounding; e++) {
    exchange(afterSounding: false);
  }
  final OfdmaTimeline mu = OfdmaTimeline(
    mode: OfdmaMode.dl,
    segments: q.segments,
  );

  return MuResult._(
    scenario: s,
    precoding: zf,
    links: links,
    ofdmaRu: ru,
    ofdmaMcs: ofdmaMcs,
    ofdmaSingle: single,
    ofdma: ofdma,
    mu: mu,
    block: null,
    soundingTenths: soundingTenths,
    soundingStartTenths: soundStart,
    muDataSymbols: List<int>.unmodifiable(symbols),
    report: report,
  );
}

/// Pattern of [MimoMath.arrayFactor] reused for the single-user comparison
/// beam: power toward [angleDeg] when the AP steers all M antennas at
/// [steerDeg], relative to the peak.
double singleUserBeamGain(int m, double angleDeg, double steerDeg) {
  final double af = MimoMath.arrayFactor(
    elements: m,
    angleDeg: angleDeg,
    steerDeg: steerDeg,
  );
  return (af / m) * (af / m);
}

// ── Scenarios (Keith's four, 2026-09-29) ───────────────────────────────────

enum MuPreset {
  spreadBig(
    'Spread out, big frames',
    'Four clients in four directions with 1500-byte frames.',
  ),
  bunched(
    'Bunched together',
    'Three clients within 10 degrees of each other, in front of a '
        'four-antenna AP.',
  ),
  tinyFrames(
    'Many tiny frames',
    'The same four spread-out clients, now with 100-byte frames.',
  ),
  oneFar(
    'One far client',
    'Three clients spread out, one of them 20 m away at a low MCS. Both '
        'schemes end each transmission when the slowest client is done.',
  );

  const MuPreset(this.label, this.detail);

  final String label;
  final String detail;

  MuScenario get scenario => switch (this) {
    MuPreset.spreadBig => MuScenario(
      antennas: 4,
      clients: const <MuClient>[
        MuClient(angleDeg: -50, distanceM: 8),
        MuClient(angleDeg: -15, distanceM: 10),
        MuClient(angleDeg: 20, distanceM: 9),
        MuClient(angleDeg: 55, distanceM: 7),
      ],
      payloadBytes: 1500,
      exchangesPerSounding: 8,
    ),
    MuPreset.bunched => MuScenario(
      antennas: 4,
      clients: const <MuClient>[
        MuClient(angleDeg: 8, distanceM: 9),
        MuClient(angleDeg: 13, distanceM: 11),
        MuClient(angleDeg: 18, distanceM: 8),
      ],
      payloadBytes: 1500,
      exchangesPerSounding: 8,
    ),
    MuPreset.tinyFrames => MuScenario(
      antennas: 4,
      clients: const <MuClient>[
        MuClient(angleDeg: -50, distanceM: 8),
        MuClient(angleDeg: -15, distanceM: 10),
        MuClient(angleDeg: 20, distanceM: 9),
        MuClient(angleDeg: 55, distanceM: 7),
      ],
      payloadBytes: 100,
      exchangesPerSounding: 8,
    ),
    MuPreset.oneFar => MuScenario(
      antennas: 4,
      clients: const <MuClient>[
        MuClient(angleDeg: -55, distanceM: 9),
        MuClient(angleDeg: 5, distanceM: 20),
        MuClient(angleDeg: 50, distanceM: 10),
      ],
      payloadBytes: 1500,
      exchangesPerSounding: 8,
    ),
  };
}
