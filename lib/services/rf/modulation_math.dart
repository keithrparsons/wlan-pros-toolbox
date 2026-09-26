// Modulation math for the Wi-Fi Classroom Modulation Simulator
// (modulation-simulator).
//
// CLEAN-ROOM BUILD. Written from the IEEE 802.11 constellation mapping
// (Gray-coded square QAM, K_MOD normalization) and textbook AWGN math only.
// Spec: myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 01-modulation-simulator.md. No third-party simulator was consulted.
//
// Everything here is pure and static so the screen stays a thin view and the
// unit tests can pin the math without a widget tree:
//
//   * constellation: square M-QAM, M = 2^k, k even; each axis carries k/2
//     bits and takes the odd levels -(sqrt(M)-1) .. +(sqrt(M)-1). BPSK is the
//     one-axis special case (I = +/-1, Q = 0). QPSK is 4-QAM.
//   * Gray mapping: each axis is Gray-coded independently (level index i
//     carries bits gray(i) = i ^ (i >> 1)), so horizontally or vertically
//     adjacent points differ in exactly one bit. The first k/2 bits of a
//     symbol drive I, the last k/2 drive Q (802.11 clause 17 ordering).
//   * normalization: K_MOD = 1 / sqrt(2(M-1)/3), so average symbol energy
//     Es = 1 (BPSK: K_MOD = 1).
//   * noise: per-axis sigma = sqrt(1 / (2 * SNR_linear)).
//   * decision: nearest ideal point. On a square grid the nearest point is
//     found exactly by slicing each axis on its own, which is what [decide]
//     does; a test proves it agrees with a brute-force nearest search.
//   * EVM: with AWGN alone, EVM_rms = 1 / sqrt(SNR_linear), so EVM(dB) is
//     -SNR(dB). Measured EVM is the RMS error vector over the simulated points,
//     normalized to the constellation's average power (1 by construction).

import 'dart:convert';
import 'dart:math' as math;

/// The seven modulations the simulator teaches, BPSK through 4096-QAM.
enum Modulation {
  bpsk(label: 'BPSK', bitsPerSymbol: 1, firstUsed: '802.11a/g (OFDM)'),
  qpsk(label: 'QPSK', bitsPerSymbol: 2, firstUsed: '802.11a/g'),
  qam16(label: '16-QAM', bitsPerSymbol: 4, firstUsed: '802.11a/g'),
  qam64(label: '64-QAM', bitsPerSymbol: 6, firstUsed: '802.11a/g'),
  qam256(label: '256-QAM', bitsPerSymbol: 8, firstUsed: '802.11ac (VHT)'),
  qam1024(label: '1024-QAM', bitsPerSymbol: 10, firstUsed: '802.11ax (HE)'),
  qam4096(label: '4096-QAM', bitsPerSymbol: 12, firstUsed: '802.11be (EHT)');

  const Modulation({
    required this.label,
    required this.bitsPerSymbol,
    required this.firstUsed,
  });

  /// Display name.
  final String label;

  /// k: bits carried by one symbol.
  final int bitsPerSymbol;

  /// The 802.11 amendment that first used it.
  final String firstUsed;

  /// M = 2^k constellation points.
  int get points => 1 << bitsPerSymbol;

  /// True for the one-axis BPSK case.
  bool get isBpsk => this == Modulation.bpsk;

  /// Bits carried on each axis (BPSK: 1 on I, 0 on Q).
  int get bitsPerAxis => isBpsk ? 1 : bitsPerSymbol ~/ 2;

  /// Amplitude levels on each axis (BPSK: 2 on I; Q unused).
  int get levelsPerAxis => 1 << bitsPerAxis;
}

/// One point of a constellation: the k-bit symbol value it carries and its
/// normalized (Es = 1) position on the I/Q plane.
class ConstellationPoint {
  const ConstellationPoint({
    required this.symbol,
    required this.i,
    required this.q,
    required this.levelI,
    required this.levelQ,
  });

  /// The k-bit symbol value (MSB first = first bit sent).
  final int symbol;

  /// Normalized in-phase coordinate (K_MOD applied).
  final double i;

  /// Normalized quadrature coordinate (K_MOD applied).
  final double q;

  /// Unscaled odd-integer level on I (e.g. -3, -1, +1, +3).
  final int levelI;

  /// Unscaled odd-integer level on Q (0 for BPSK).
  final int levelQ;

  /// Carrier amplitude A = sqrt(I^2 + Q^2).
  double get amplitude => math.sqrt(i * i + q * q);

  /// Carrier phase phi = atan2(Q, I), radians.
  double get phase => math.atan2(q, i);
}

/// One transmitted-and-received symbol.
class SimulatedSymbol {
  const SimulatedSymbol({
    required this.sent,
    required this.receivedI,
    required this.receivedQ,
    required this.decided,
  });

  /// The ideal point that was sent.
  final ConstellationPoint sent;

  /// Received I after noise.
  final double receivedI;

  /// Received Q after noise.
  final double receivedQ;

  /// The ideal point the receiver chose (nearest to the received point).
  final ConstellationPoint decided;

  /// True when the receiver picked the wrong point.
  bool get isSymbolError => decided.symbol != sent.symbol;

  /// Bits that differ between what was sent and what was decided.
  int get bitErrors => ModulationMath.popCount(sent.symbol ^ decided.symbol);

  /// Squared length of the error vector (received minus sent).
  double get errorVectorSquared {
    final double di = receivedI - sent.i;
    final double dq = receivedQ - sent.q;
    return di * di + dq * dq;
  }
}

/// Bits grouped into k-bit symbols, with the zero padding the last symbol
/// needed.
class SymbolFrame {
  const SymbolFrame({required this.symbols, required this.padBits});

  /// k-bit symbol values in send order.
  final List<int> symbols;

  /// Zero bits appended to fill the final symbol (0 when the bits divide
  /// evenly).
  final int padBits;
}

/// One row of the 802.11 transmit modulation accuracy requirement.
class EvmRequirement {
  const EvmRequirement({required this.codingRates, required this.requiredDb});

  /// Coding rate(s) this limit applies to, e.g. '3/4' or '3/4, 5/6'.
  final String codingRates;

  /// Maximum allowed transmit EVM (relative constellation error), dB.
  final double requiredDb;
}

/// Pure modulation math. Static only; never instantiated.
class ModulationMath {
  ModulationMath._();

  // ── Normalization ─────────────────────────────────────────────────────────

  /// The 802.11 K_MOD normalization factor: 1 for BPSK, else
  /// 1 / sqrt(2(M-1)/3). Gives average symbol energy Es = 1.
  static double kMod(Modulation m) {
    if (m.isBpsk) return 1.0;
    return 1.0 / math.sqrt(2.0 * (m.points - 1) / 3.0);
  }

  // ── Gray coding per axis ──────────────────────────────────────────────────

  /// Binary-reflected Gray code of [n].
  static int gray(int n) => n ^ (n >> 1);

  /// Inverse Gray code: the level index whose Gray code is [g].
  static int inverseGray(int g) {
    int n = g;
    for (int shift = g >> 1; shift != 0; shift >>= 1) {
      n ^= shift;
    }
    return n;
  }

  /// Odd-integer level for a level index on an axis with [levels] levels:
  /// index 0 is the most negative, e.g. 4 levels -> -3, -1, +1, +3.
  static int levelForIndex(int index, int levels) => 2 * index - (levels - 1);

  /// Level index for an odd-integer level (inverse of [levelForIndex]).
  static int indexForLevel(int level, int levels) => (level + levels - 1) ~/ 2;

  // ── Mapping ───────────────────────────────────────────────────────────────

  /// The ideal point for a k-bit [symbol].
  static ConstellationPoint map(Modulation m, int symbol) {
    final double k = kMod(m);
    final int levels = m.levelsPerAxis;
    if (m.isBpsk) {
      final int level = levelForIndex(inverseGray(symbol & 1), levels);
      return ConstellationPoint(
        symbol: symbol & 1,
        i: level * k,
        q: 0,
        levelI: level,
        levelQ: 0,
      );
    }
    final int half = m.bitsPerAxis;
    final int mask = levels - 1;
    final int bitsI = (symbol >> half) & mask;
    final int bitsQ = symbol & mask;
    final int levelI = levelForIndex(inverseGray(bitsI), levels);
    final int levelQ = levelForIndex(inverseGray(bitsQ), levels);
    return ConstellationPoint(
      symbol: symbol & (m.points - 1),
      i: levelI * k,
      q: levelQ * k,
      levelI: levelI,
      levelQ: levelQ,
    );
  }

  /// Every ideal point, indexed by symbol value.
  static List<ConstellationPoint> constellation(Modulation m) =>
      List<ConstellationPoint>.generate(m.points, (int s) => map(m, s));

  /// The point at odd-integer levels ([levelI], [levelQ]).
  static ConstellationPoint pointAtLevels(
    Modulation m,
    int levelI,
    int levelQ,
  ) {
    final int levels = m.levelsPerAxis;
    if (m.isBpsk) {
      return map(m, gray(indexForLevel(levelI, levels)));
    }
    final int bitsI = gray(indexForLevel(levelI, levels));
    final int bitsQ = gray(indexForLevel(levelQ, levels));
    return map(m, (bitsI << m.bitsPerAxis) | bitsQ);
  }

  // ── Decision ──────────────────────────────────────────────────────────────

  /// Slices one normalized coordinate to the nearest odd-integer level.
  static int _sliceLevel(double v, double k, int levels) {
    final double unscaled = v / k;
    // Nearest odd integer, then clamp to the outermost level.
    int level = (2 * ((unscaled - 1) / 2).round() + 1);
    final int maxLevel = levels - 1;
    if (level > maxLevel) level = maxLevel;
    if (level < -maxLevel) level = -maxLevel;
    return level;
  }

  /// The ideal point nearest to the received (i, q). Exact for square QAM:
  /// on a separable grid, the per-axis nearest level is the Euclidean nearest.
  static ConstellationPoint decide(Modulation m, double i, double q) {
    final double k = kMod(m);
    final int levels = m.levelsPerAxis;
    final int levelI = _sliceLevel(i, k, levels);
    if (m.isBpsk) return pointAtLevels(m, levelI, 0);
    final int levelQ = _sliceLevel(q, k, levels);
    return pointAtLevels(m, levelI, levelQ);
  }

  // ── Bits in ───────────────────────────────────────────────────────────────

  /// UTF-8 bytes of [text] as a flat MSB-first bit list.
  static List<int> textToBits(String text) {
    final List<int> bytes = utf8.encode(text);
    final List<int> bits = <int>[];
    for (final int b in bytes) {
      for (int shift = 7; shift >= 0; shift--) {
        bits.add((b >> shift) & 1);
      }
    }
    return bits;
  }

  /// Inverse of [textToBits]. Trailing bits that do not fill a byte are
  /// dropped; malformed UTF-8 (from bit errors) decodes to U+FFFD rather
  /// than throwing, so a garbled message still shows how it was garbled.
  static String bitsToText(List<int> bits) {
    final int byteCount = bits.length ~/ 8;
    final List<int> bytes = List<int>.generate(byteCount, (int n) {
      int b = 0;
      for (int j = 0; j < 8; j++) {
        b = (b << 1) | (bits[n * 8 + j] & 1);
      }
      return b;
    });
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Groups [bits] into [bitsPerSymbol]-bit symbols (first bit = MSB),
  /// zero-padding the last symbol.
  static SymbolFrame groupBits(List<int> bits, int bitsPerSymbol) {
    final List<int> symbols = <int>[];
    int padBits = 0;
    for (int start = 0; start < bits.length; start += bitsPerSymbol) {
      int s = 0;
      for (int j = 0; j < bitsPerSymbol; j++) {
        final int idx = start + j;
        final int bit;
        if (idx < bits.length) {
          bit = bits[idx] & 1;
        } else {
          bit = 0;
          padBits++;
        }
        s = (s << 1) | bit;
      }
      symbols.add(s);
    }
    return SymbolFrame(symbols: symbols, padBits: padBits);
  }

  /// Flattens symbols back to bits, MSB first.
  static List<int> symbolsToBits(List<int> symbols, int bitsPerSymbol) {
    final List<int> bits = <int>[];
    for (final int s in symbols) {
      for (int shift = bitsPerSymbol - 1; shift >= 0; shift--) {
        bits.add((s >> shift) & 1);
      }
    }
    return bits;
  }

  /// The k-bit string for [symbol], e.g. '1011'.
  static String bitString(int symbol, int bitsPerSymbol) =>
      symbol.toRadixString(2).padLeft(bitsPerSymbol, '0');

  /// A uniformly random k-bit symbol.
  static int randomSymbol(Modulation m, math.Random rng) =>
      rng.nextInt(m.points);

  // ── Noise, EVM ────────────────────────────────────────────────────────────

  /// 10^(dB/10).
  static double snrLinear(double snrDb) => math.pow(10, snrDb / 10).toDouble();

  /// Per-axis noise standard deviation for Es = 1: sqrt(1 / (2 SNR)).
  static double noiseSigma(double snrDb) =>
      math.sqrt(1.0 / (2.0 * snrLinear(snrDb)));

  /// Theoretical RMS EVM under AWGN alone: 1 / sqrt(SNR_linear).
  static double theoreticalEvmRms(double snrDb) =>
      1.0 / math.sqrt(snrLinear(snrDb));

  /// RMS EVM (a ratio) in dB: 20 log10(evm).
  static double evmToDb(double evmRms) => 20 * math.log(evmRms) / math.ln10;

  /// Measured RMS EVM from the sum of squared error-vector lengths over
  /// [count] symbols, normalized to average constellation power (1).
  static double measuredEvmRms(double sumErrorSquared, int count) {
    if (count <= 0) return double.nan;
    return math.sqrt(sumErrorSquared / count);
  }

  /// One standard-normal sample (Box-Muller).
  static double gaussian(math.Random rng) {
    double u1 = rng.nextDouble();
    // Guard log(0); nextDouble() can return exactly 0.
    while (u1 <= 0) {
      u1 = rng.nextDouble();
    }
    final double u2 = rng.nextDouble();
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  /// Sends one [symbol] through AWGN at [snrDb] and decides it.
  static SimulatedSymbol transmit(
    Modulation m,
    int symbol,
    double snrDb,
    math.Random rng,
  ) {
    final ConstellationPoint sent = map(m, symbol);
    final double sigma = noiseSigma(snrDb);
    final double ri = sent.i + sigma * gaussian(rng);
    final double rq = sent.q + sigma * gaussian(rng);
    return SimulatedSymbol(
      sent: sent,
      receivedI: ri,
      receivedQ: rq,
      decided: decide(m, ri, rq),
    );
  }

  /// Population count (number of 1 bits).
  static int popCount(int v) {
    int n = v;
    int c = 0;
    while (n != 0) {
      n &= n - 1;
      c++;
    }
    return c;
  }

  // ── Carrier ───────────────────────────────────────────────────────────────

  /// Carrier sample for symbol (i, q) at carrier phase [theta] = 2 pi f_c t:
  /// s = I cos(theta) - Q sin(theta), which equals A cos(theta + phi).
  static double carrier(double i, double q, double theta) =>
      i * math.cos(theta) - q * math.sin(theta);

  /// Largest carrier amplitude any point of [m] can have (the corner point).
  static double maxAmplitude(Modulation m) {
    final double k = kMod(m);
    final int maxLevel = m.levelsPerAxis - 1;
    if (m.isBpsk) return maxLevel * k;
    return maxLevel * k * math.sqrt2;
  }

  // ── Required transmit EVM ─────────────────────────────────────────────────

  /// IEEE 802.11 transmit modulation accuracy (relative constellation error)
  /// limits, per the spec table (clauses 17, 19, 21, 27, 36). These bound the
  /// TRANSMITTER's accuracy; they are not receiver sensitivity thresholds.
  static List<EvmRequirement> requiredEvm(Modulation m) {
    switch (m) {
      case Modulation.bpsk:
        return const <EvmRequirement>[
          EvmRequirement(codingRates: '1/2', requiredDb: -5),
        ];
      case Modulation.qpsk:
        return const <EvmRequirement>[
          EvmRequirement(codingRates: '1/2', requiredDb: -10),
          EvmRequirement(codingRates: '3/4', requiredDb: -13),
        ];
      case Modulation.qam16:
        return const <EvmRequirement>[
          EvmRequirement(codingRates: '1/2', requiredDb: -16),
          EvmRequirement(codingRates: '3/4', requiredDb: -19),
        ];
      case Modulation.qam64:
        return const <EvmRequirement>[
          EvmRequirement(codingRates: '2/3', requiredDb: -22),
          EvmRequirement(codingRates: '3/4', requiredDb: -25),
          EvmRequirement(codingRates: '5/6', requiredDb: -27),
        ];
      case Modulation.qam256:
        return const <EvmRequirement>[
          EvmRequirement(codingRates: '3/4', requiredDb: -30),
          EvmRequirement(codingRates: '5/6', requiredDb: -32),
        ];
      case Modulation.qam1024:
        return const <EvmRequirement>[
          EvmRequirement(codingRates: '3/4, 5/6', requiredDb: -35),
        ];
      case Modulation.qam4096:
        return const <EvmRequirement>[
          EvmRequirement(codingRates: '3/4, 5/6', requiredDb: -38),
        ];
    }
  }

  /// Whether an EVM of [evmDb] is at or better than (below) [requiredDb].
  static bool meetsRequirement(double evmDb, double requiredDb) =>
      evmDb <= requiredDb;
}
