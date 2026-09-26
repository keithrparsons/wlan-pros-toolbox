// Tests for the Wi-Fi Classroom Modulation Simulator math (clean-room build).
//
// Spec "Done means": K_MOD values, Gray adjacency for all seven orders, the
// text-to-bits round trip, the EVM formula, and error detection at very high
// SNR (0 errors) and very low SNR (errors > 0) with a seeded RNG.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/rf/modulation_math.dart';

void main() {
  group('K_MOD normalization', () {
    // The seven 802.11 values, written as the standard states them.
    final Map<Modulation, double> expected = <Modulation, double>{
      Modulation.bpsk: 1.0,
      Modulation.qpsk: 1 / math.sqrt(2),
      Modulation.qam16: 1 / math.sqrt(10),
      Modulation.qam64: 1 / math.sqrt(42),
      Modulation.qam256: 1 / math.sqrt(170),
      Modulation.qam1024: 1 / math.sqrt(682),
      Modulation.qam4096: 1 / math.sqrt(2730),
    };

    for (final Modulation m in Modulation.values) {
      test('${m.label}: K_MOD = ${expected[m]}', () {
        expect(ModulationMath.kMod(m), closeTo(expected[m]!, 1e-12));
      });

      test('${m.label}: average symbol energy is exactly 1', () {
        final List<ConstellationPoint> pts = ModulationMath.constellation(m);
        final double es =
            pts.fold<double>(0, (double a, ConstellationPoint p) {
              return a + p.i * p.i + p.q * p.q;
            }) /
            pts.length;
        expect(es, closeTo(1.0, 1e-12));
      });
    }
  });

  group('constellation shape', () {
    test('points and bits per symbol match the spec table', () {
      expect(
        Modulation.values.map((Modulation m) => m.bitsPerSymbol).toList(),
        <int>[1, 2, 4, 6, 8, 10, 12],
      );
      expect(Modulation.values.map((Modulation m) => m.points).toList(), <int>[
        2,
        4,
        16,
        64,
        256,
        1024,
        4096,
      ]);
    });

    test('BPSK sits on the I axis at +/-1', () {
      final List<ConstellationPoint> pts = ModulationMath.constellation(
        Modulation.bpsk,
      );
      expect(pts.map((ConstellationPoint p) => p.i).toSet(), <double>{
        -1.0,
        1.0,
      });
      expect(pts.every((ConstellationPoint p) => p.q == 0), isTrue);
    });

    test('16-QAM I axis follows the 802.11 Gray map 00,01,11,10', () {
      // b0b1 -> I level: 00 -> -3, 01 -> -1, 11 -> +1, 10 -> +3.
      int levelIFor(int b0b1) =>
          ModulationMath.map(Modulation.qam16, b0b1 << 2).levelI;
      expect(levelIFor(0x0), -3);
      expect(levelIFor(0x1), -1);
      expect(levelIFor(0x3), 1);
      expect(levelIFor(0x2), 3);
    });

    for (final Modulation m in Modulation.values) {
      test('${m.label}: every symbol maps to a distinct point', () {
        final Set<String> seen = <String>{};
        for (final ConstellationPoint p in ModulationMath.constellation(m)) {
          seen.add('${p.levelI},${p.levelQ}');
        }
        expect(seen.length, m.points);
      });
    }
  });

  group('Gray adjacency: nearest neighbors differ by exactly one bit', () {
    for (final Modulation m in Modulation.values) {
      test(m.label, () {
        final List<ConstellationPoint> pts = ModulationMath.constellation(m);
        // Nearest-neighbor distance is 2 * K_MOD (adjacent odd levels).
        final double dMin = 2 * ModulationMath.kMod(m);
        int pairs = 0;
        for (int a = 0; a < pts.length; a++) {
          for (int b = a + 1; b < pts.length; b++) {
            final double di = pts[a].i - pts[b].i;
            final double dq = pts[a].q - pts[b].q;
            final double d = math.sqrt(di * di + dq * dq);
            if ((d - dMin).abs() < 1e-9) {
              pairs++;
              expect(
                ModulationMath.popCount(pts[a].symbol ^ pts[b].symbol),
                1,
                reason:
                    '${m.label} neighbors '
                    '${ModulationMath.bitString(pts[a].symbol, m.bitsPerSymbol)}'
                    ' and '
                    '${ModulationMath.bitString(pts[b].symbol, m.bitsPerSymbol)}',
              );
            }
          }
        }
        // A sqrt(M) x sqrt(M) grid has 2 * n * (n - 1) adjacent pairs; BPSK 1.
        final int n = m.levelsPerAxis;
        expect(pairs, m.isBpsk ? 1 : 2 * n * (n - 1));
      });
    }
  });

  group('decision', () {
    test('slicer agrees with brute-force nearest point (seeded)', () {
      final math.Random rng = math.Random(7);
      for (final Modulation m in Modulation.values) {
        final List<ConstellationPoint> pts = ModulationMath.constellation(m);
        final double span = ModulationMath.maxAmplitude(m) * 1.3;
        for (int t = 0; t < 200; t++) {
          final double i = (rng.nextDouble() * 2 - 1) * span;
          final double q = m.isBpsk ? 0 : (rng.nextDouble() * 2 - 1) * span;
          ConstellationPoint best = pts.first;
          double bestD = double.infinity;
          for (final ConstellationPoint p in pts) {
            final double d = (p.i - i) * (p.i - i) + (p.q - q) * (p.q - q);
            if (d < bestD) {
              bestD = d;
              best = p;
            }
          }
          expect(
            ModulationMath.decide(m, i, q).symbol,
            best.symbol,
            reason: '${m.label} at ($i, $q)',
          );
        }
      }
    });

    test('an ideal point decides to itself', () {
      for (final Modulation m in Modulation.values) {
        for (final ConstellationPoint p in ModulationMath.constellation(m)) {
          expect(ModulationMath.decide(m, p.i, p.q).symbol, p.symbol);
        }
      }
    });
  });

  group('bits in', () {
    test('text -> bits -> text round trip, including multi-byte UTF-8', () {
      const String msg = 'Hello, Wi-Fi! café \u{1F4F6}';
      final List<int> bits = ModulationMath.textToBits(msg);
      expect(bits.length % 8, 0);
      expect(ModulationMath.bitsToText(bits), msg);
    });

    test('ASCII A is 01000001', () {
      expect(ModulationMath.textToBits('A'), <int>[0, 1, 0, 0, 0, 0, 0, 1]);
    });

    test('round trip survives grouping into symbols for every order', () {
      const String msg = 'Modulation 123 é';
      final List<int> bits = ModulationMath.textToBits(msg);
      for (final Modulation m in Modulation.values) {
        final SymbolFrame f = ModulationMath.groupBits(bits, m.bitsPerSymbol);
        final List<int> back = ModulationMath.symbolsToBits(
          f.symbols,
          m.bitsPerSymbol,
        );
        expect(back.length, bits.length + f.padBits);
        expect(back.sublist(bits.length).every((int b) => b == 0), isTrue);
        expect(
          ModulationMath.bitsToText(back.sublist(0, bits.length)),
          msg,
          reason: m.label,
        );
      }
    });

    test('last symbol is zero padded and the pad count is reported', () {
      // 8 bits into 6-bit symbols: 2 symbols, 4 pad bits.
      final SymbolFrame f = ModulationMath.groupBits(
        ModulationMath.textToBits('A'),
        6,
      );
      expect(f.symbols, <int>[0x10, 0x10]); // 010000 010000
      expect(f.padBits, 4);
      // 8 bits into 4-bit symbols divides evenly.
      expect(
        ModulationMath.groupBits(ModulationMath.textToBits('A'), 4).padBits,
        0,
      );
    });
  });

  group('EVM', () {
    test('theoretical EVM in dB is exactly -SNR in dB', () {
      for (final double snr in <double>[0, 10, 20, 25, 35, 45]) {
        expect(
          ModulationMath.evmToDb(ModulationMath.theoreticalEvmRms(snr)),
          closeTo(-snr, 1e-9),
        );
      }
      expect(ModulationMath.theoreticalEvmRms(20), closeTo(0.1, 1e-12));
    });

    test('noise sigma is sqrt(1 / (2 SNR))', () {
      expect(ModulationMath.noiseSigma(0), closeTo(math.sqrt(0.5), 1e-12));
      expect(ModulationMath.noiseSigma(20), closeTo(math.sqrt(1 / 200), 1e-12));
    });

    test('measured EVM converges on theory (seeded, 20,000 symbols)', () {
      final math.Random rng = math.Random(42);
      for (final double snr in <double>[10, 25]) {
        double sum = 0;
        const int n = 20000;
        for (int t = 0; t < n; t++) {
          final SimulatedSymbol s = ModulationMath.transmit(
            Modulation.qam64,
            ModulationMath.randomSymbol(Modulation.qam64, rng),
            snr,
            rng,
          );
          sum += s.errorVectorSquared;
        }
        final double measuredDb = ModulationMath.evmToDb(
          ModulationMath.measuredEvmRms(sum, n),
        );
        expect(measuredDb, closeTo(-snr, 0.2));
      }
    });

    test('meetsRequirement: lower (more negative) EVM passes', () {
      expect(ModulationMath.meetsRequirement(-26, -25), isTrue);
      expect(ModulationMath.meetsRequirement(-25, -25), isTrue);
      expect(ModulationMath.meetsRequirement(-24, -25), isFalse);
    });

    test('required EVM table matches the spec', () {
      List<double> db(Modulation m) => ModulationMath.requiredEvm(
        m,
      ).map((EvmRequirement r) => r.requiredDb).toList();
      expect(db(Modulation.bpsk), <double>[-5]);
      expect(db(Modulation.qpsk), <double>[-10, -13]);
      expect(db(Modulation.qam16), <double>[-16, -19]);
      expect(db(Modulation.qam64), <double>[-22, -25, -27]);
      expect(db(Modulation.qam256), <double>[-30, -32]);
      expect(db(Modulation.qam1024), <double>[-35]);
      expect(db(Modulation.qam4096), <double>[-38]);
    });
  });

  group('error detection (seeded RNG)', () {
    ({int symbolErrors, int bitErrors}) run(Modulation m, double snr) {
      final math.Random rng = math.Random(2026);
      int se = 0;
      int be = 0;
      for (int t = 0; t < 2000; t++) {
        final SimulatedSymbol s = ModulationMath.transmit(
          m,
          ModulationMath.randomSymbol(m, rng),
          snr,
          rng,
        );
        if (s.isSymbolError) se++;
        be += s.bitErrors;
      }
      return (symbolErrors: se, bitErrors: be);
    }

    for (final Modulation m in Modulation.values) {
      test('${m.label} at 45 dB: zero errors', () {
        final r = run(m, 45);
        expect(r.symbolErrors, 0);
        expect(r.bitErrors, 0);
      });

      test('${m.label} at 0 dB: errors are detected', () {
        final r = run(m, 0);
        expect(r.symbolErrors, greaterThan(0));
        expect(r.bitErrors, greaterThan(0));
      });
    }

    test('a Gray-coded neighbor error costs exactly one bit', () {
      // Push a 16-QAM point just past the boundary toward its I neighbor.
      final ConstellationPoint p = ModulationMath.pointAtLevels(
        Modulation.qam16,
        -1,
        1,
      );
      final double k = ModulationMath.kMod(Modulation.qam16);
      final ConstellationPoint d = ModulationMath.decide(
        Modulation.qam16,
        p.i + 1.1 * k,
        p.q,
      );
      expect(d.levelI, 1);
      expect(ModulationMath.popCount(p.symbol ^ d.symbol), 1);
    });
  });

  group('carrier', () {
    test('I cos - Q sin equals A cos(theta + phi)', () {
      for (final ConstellationPoint p in ModulationMath.constellation(
        Modulation.qam16,
      )) {
        for (double th = 0; th < 2 * math.pi; th += 0.37) {
          expect(
            ModulationMath.carrier(p.i, p.q, th),
            closeTo(p.amplitude * math.cos(th + p.phase), 1e-12),
          );
        }
      }
    });
  });
}
