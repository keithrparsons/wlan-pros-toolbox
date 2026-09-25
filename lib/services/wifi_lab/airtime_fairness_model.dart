// Airtime Fairness model (Wi-Fi Lab, 2026-09-25) — airtime-fairness.
//
// One AP, N saturated downlink clients, no collisions. Each client wins a
// transmission opportunity and sends n frames of L bytes at its PHY rate. The
// model compares two ways of sharing the air:
//
//   Packet fairness (plain DCF): every client gets one transmission per round.
//     Round = sum of T_j. Throughput_i = 8 * n_i * L / sum(T_j).
//   Airtime fairness: every client gets 1/N of the time.
//     Throughput_i = (1/N) * 8 * n_i * L / T_i.
//
// where T_i = overhead_i + 8 * n_i * (L + 34) / R_i  (microseconds, R in Mbps).
//
// Built clean-room from IEEE 802.11 timing and Heusse, Rousseau,
// Berger-Sabbatel and Duda, "Performance Anomaly of 802.11b", IEEE INFOCOM
// 2003. Spec: myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 04-throughput-airtime-fairness.md. This is a TEACHING model; the exact
// per-PHY airtime lives in Airtime Anatomy (spec 05).
//
// Pure Dart: no Flutter imports, so the unit tests run without a widget tree.

import 'dart:math' as math;

/// Every timing constant the model uses, in one place, with its source.
abstract final class AirtimeConstants {
  /// AIFS for best effort at 5 GHz: SIFS 16 us + AIFSN 3 x 9 us slot
  /// (IEEE 802.11 EDCA default parameter set, AC_BE).
  static const double aifsUs = 43;

  /// Average backoff: CWmin 15 for AC_BE, mean draw 7.5 slots x 9 us.
  static const double avgBackoffUs = 67.5;

  /// Legacy OFDM (802.11a/g) preamble plus SIGNAL field: 16 + 4 us.
  static const double preambleLegacyUs = 20;

  /// HT / VHT / HE preamble. The real value varies with PHY, stream count and
  /// format; 40 us is a single teaching value (spec 04).
  static const double preambleHtUs = 40;

  /// SIFS at 5 GHz (OFDM PHY).
  static const double sifsUs = 16;

  /// A 14-byte ACK at 24 Mbps: 20 + 4 x ceil((16 + 112 + 6) / 96) = 28 us.
  static const double ackUs = 28;

  /// A 32-byte compressed Block Ack at 24 Mbps:
  /// 20 + 4 x ceil((16 + 256 + 6) / 96) = 32 us.
  static const double blockAckUs = 32;

  /// Per-frame bytes on top of the payload: MAC header 26 + FCS 4 + A-MPDU
  /// delimiter 4 (the delimiter is counted on every frame, as spec 04 does).
  static const int perFrameOverheadBytes = 34;

  /// Default payload per frame.
  static const int defaultPayloadBytes = 1500;

  /// Client-count bounds on screen.
  static const int minClients = 1;
  static const int maxClients = 8;

  /// Custom PHY-rate bounds, Mbps.
  static const double minRateMbps = 1;
  static const double maxRateMbps = 10000;
}

/// PHY generation, only as far as the model needs it (the preamble).
enum PhyFamily {
  legacy('Legacy'),
  ht('HT'),
  vht('VHT'),
  he('HE');

  const PhyFamily(this.label);

  final String label;

  bool get isLegacy => this == PhyFamily.legacy;
}

/// The PHY-rate presets spec 04 names.
enum RatePreset {
  legacy6(6, PhyFamily.legacy),
  legacy24(24, PhyFamily.legacy),
  legacy54(54, PhyFamily.legacy),
  ht150(150, PhyFamily.ht),
  ht300(300, PhyFamily.ht),
  vht433(433, PhyFamily.vht),
  vht867(867, PhyFamily.vht),
  he600(600, PhyFamily.he),
  he1201(1201, PhyFamily.he);

  const RatePreset(this.mbps, this.family);

  final double mbps;
  final PhyFamily family;

  String get label => '${mbps.round()} Mbps (${family.label})';
}

/// One client as the model sees it.
class ClientConfig {
  const ClientConfig({
    required this.rateMbps,
    required this.legacy,
    this.aggregation = 1,
  });

  factory ClientConfig.preset(RatePreset p, {int aggregation = 1}) =>
      ClientConfig(
        rateMbps: p.mbps,
        legacy: p.family.isLegacy,
        aggregation: aggregation,
      );

  /// PHY rate, Mbps.
  final double rateMbps;

  /// Legacy OFDM client: 20 us preamble and no aggregation.
  final bool legacy;

  /// Frames per transmission as configured.
  final int aggregation;

  /// Frames per transmission the model uses: legacy clients cannot aggregate.
  int get frames => legacy ? 1 : math.max(1, aggregation);
}

/// Fixed overhead of one transmission to [c], microseconds.
double overheadUs(ClientConfig c) =>
    AirtimeConstants.aifsUs +
    AirtimeConstants.avgBackoffUs +
    (c.legacy
        ? AirtimeConstants.preambleLegacyUs
        : AirtimeConstants.preambleHtUs) +
    AirtimeConstants.sifsUs +
    (c.frames == 1 ? AirtimeConstants.ackUs : AirtimeConstants.blockAckUs);

/// Time the data frames of one transmission take on the air, microseconds.
double dataUs(
  ClientConfig c, {
  int payloadBytes = AirtimeConstants.defaultPayloadBytes,
}) =>
    8 *
    c.frames *
    (payloadBytes + AirtimeConstants.perFrameOverheadBytes) /
    c.rateMbps;

/// T_i: airtime of one transmission to [c], microseconds.
double airtimeUs(
  ClientConfig c, {
  int payloadBytes = AirtimeConstants.defaultPayloadBytes,
}) => overheadUs(c) + dataUs(c, payloadBytes: payloadBytes);

/// Payload bits one transmission to [c] delivers.
double payloadBits(
  ClientConfig c, {
  int payloadBytes = AirtimeConstants.defaultPayloadBytes,
}) => 8.0 * c.frames * payloadBytes;

/// How the AP shares the air.
enum FairnessMode {
  packet('Packet fairness'),
  airtime('Airtime fairness');

  const FairnessMode(this.label);

  final String label;
}

/// One client's outcome under one fairness mode.
class ClientResult {
  const ClientResult({
    required this.index,
    required this.config,
    required this.airtimePerTxUs,
    required this.overheadPerTxUs,
    required this.throughputMbps,
    required this.airtimeShare,
    required this.soloThroughputMbps,
  });

  final int index;
  final ClientConfig config;

  /// T_i, microseconds.
  final double airtimePerTxUs;

  /// The fixed-overhead part of T_i, microseconds.
  final double overheadPerTxUs;

  /// Delivered payload throughput, Mbps.
  final double throughputMbps;

  /// Fraction of all airtime this client uses, 0 to 1.
  final double airtimeShare;

  /// Throughput if this client had the air to itself, Mbps.
  final double soloThroughputMbps;
}

/// The whole cell under one fairness mode.
class FairnessResult {
  const FairnessResult({
    required this.mode,
    required this.clients,
    required this.payloadBytes,
  });

  final FairnessMode mode;
  final List<ClientResult> clients;
  final int payloadBytes;

  double get aggregateMbps =>
      clients.fold(0, (double s, ClientResult c) => s + c.throughputMbps);
}

/// Computes throughput and airtime share for every client under [mode].
///
/// Throws [ArgumentError] on an empty list or a non-positive rate or payload.
FairnessResult computeFairness(
  List<ClientConfig> clients,
  FairnessMode mode, {
  int payloadBytes = AirtimeConstants.defaultPayloadBytes,
}) {
  if (clients.isEmpty) {
    throw ArgumentError.value(clients, 'clients', 'needs at least one client');
  }
  if (payloadBytes <= 0) {
    throw ArgumentError.value(payloadBytes, 'payloadBytes', 'must be > 0');
  }
  for (final ClientConfig c in clients) {
    if (!(c.rateMbps > 0) || !c.rateMbps.isFinite) {
      throw ArgumentError.value(c.rateMbps, 'rateMbps', 'must be > 0');
    }
  }
  final int n = clients.length;
  final List<double> t = <double>[
    for (final ClientConfig c in clients)
      airtimeUs(c, payloadBytes: payloadBytes),
  ];
  final double round = t.fold(0, (double s, double v) => s + v);

  return FairnessResult(
    mode: mode,
    payloadBytes: payloadBytes,
    clients: <ClientResult>[
      for (int i = 0; i < n; i++)
        ClientResult(
          index: i,
          config: clients[i],
          airtimePerTxUs: t[i],
          overheadPerTxUs: overheadUs(clients[i]),
          soloThroughputMbps:
              payloadBits(clients[i], payloadBytes: payloadBytes) / t[i],
          airtimeShare: mode == FairnessMode.packet ? t[i] / round : 1 / n,
          throughputMbps: mode == FairnessMode.packet
              ? payloadBits(clients[i], payloadBytes: payloadBytes) / round
              : payloadBits(clients[i], payloadBytes: payloadBytes) / t[i] / n,
        ),
    ],
  );
}

/// One transmission in a drawn schedule.
class ScheduledTx {
  const ScheduledTx({
    required this.client,
    required this.startUs,
    required this.overheadUs,
    required this.durationUs,
  });

  final int client;
  final double startUs;

  /// Overhead part at the start of the block (wait, preamble, SIFS, ACK;
  /// drawn together for teaching).
  final double overheadUs;

  /// Whole block, T_i.
  final double durationUs;

  double get endUs => startUs + durationUs;
}

/// The order of transmissions over [windowUs] of air.
///
/// Packet fairness: round robin, one transmission each per round.
/// Airtime fairness: the client with the least airtime used so far goes next
/// (ties to the lowest index), which converges on equal time shares. The last
/// block may run past [windowUs]; the painter clips it.
List<ScheduledTx> buildSchedule(
  List<ClientConfig> clients,
  FairnessMode mode, {
  required double windowUs,
  int payloadBytes = AirtimeConstants.defaultPayloadBytes,
}) {
  if (clients.isEmpty || !(windowUs > 0)) return const <ScheduledTx>[];
  final int n = clients.length;
  final List<double> t = <double>[
    for (final ClientConfig c in clients)
      airtimeUs(c, payloadBytes: payloadBytes),
  ];
  final List<double> used = List<double>.filled(n, 0);
  final List<ScheduledTx> out = <ScheduledTx>[];
  double now = 0;
  int next = 0;
  // Bound the loop: the shortest block is at least the fixed overhead, so this
  // many blocks always covers the window.
  final int cap = (windowUs / t.reduce(math.min)).ceil() + n + 1;
  while (now < windowUs && out.length < cap) {
    int i;
    if (mode == FairnessMode.packet) {
      i = next;
      next = (next + 1) % n;
    } else {
      i = 0;
      for (int j = 1; j < n; j++) {
        if (used[j] < used[i] - 1e-9) i = j;
      }
    }
    out.add(
      ScheduledTx(
        client: i,
        startUs: now,
        overheadUs: overheadUs(clients[i]),
        durationUs: t[i],
      ),
    );
    used[i] += t[i];
    now += t[i];
  }
  return out;
}

/// The window the round view draws: long enough for one packet-fair round and
/// for the slowest client to take one airtime-fair turn while every other
/// client catches up to it.
double roundWindowUs(
  List<ClientConfig> clients, {
  int payloadBytes = AirtimeConstants.defaultPayloadBytes,
}) {
  if (clients.isEmpty) return 0;
  final List<double> t = <double>[
    for (final ClientConfig c in clients)
      airtimeUs(c, payloadBytes: payloadBytes),
  ];
  final double round = t.fold(0, (double s, double v) => s + v);
  return math.max(round, clients.length * t.reduce(math.max));
}

/// Client letter by position: A, B, C ...
String clientLetter(int index) => String.fromCharCode(0x41 + index);
