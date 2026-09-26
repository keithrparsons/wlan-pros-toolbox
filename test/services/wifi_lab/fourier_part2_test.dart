// Unit tests for part 2 of the Wi-Fi Classroom "Fourier and FFT" tool: the swept
// vs FFT race (fourier_race.dart) and OFDM as an inverse FFT
// (fourier_ofdm.dart).
//
// The first group is spec 11 part 2's "Done means" list, one test each. The
// rest hold the exact swept-catch solver to a brute-force time walk, check
// the cyclic prefix and the scene's timings, and pin the analyzer rainbow to
// GL-003 §8.22 and the fingerprint wording to the Spectrum Analysis module.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_race_controls.dart';
import 'package:wlan_pros_toolbox/services/rf/modulation_math.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fourier_dsp.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fourier_ofdm.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fourier_race.dart';
import 'package:wlan_pros_toolbox/theme/app_analyzer_rainbow.dart';

OfdmSymbol _symbol(
  OfdmNumerology nu,
  int n,
  Iterable<int> ks,
  Modulation m, {
  int seed = 7,
  double? gi,
}) => OfdmMath.build(
  numerology: nu,
  n: n,
  guardSeconds: gi ?? nu.guardOptionsSeconds.first,
  points: OfdmMath.randomPoints(indices: ks, modulation: m, seed: seed),
);

void main() {
  group('spec: Done means', () {
    test('sweep time, k = 2.5, 100 MHz span: 0.25 ms at 1 MHz RBW, 25 ms at '
        '100 kHz, 2.5 s at 10 kHz', () {
      double st(double rbw) =>
          SweptAnalyzer.sweepTimeSeconds(spanHz: 100e6, rbwHz: rbw);
      expect(SweptAnalyzer.kSweepK, 2.5);
      expect(st(1e6), closeTo(0.25e-3, 1e-15));
      expect(st(100e3), closeTo(25e-3, 1e-15));
      expect(st(10e3), closeTo(2.5, 1e-12));
    });

    test('an OFDM symbol built by IFFT and then FFT\'d recovers the sent '
        'constellation points exactly (no noise)', () {
      for (final Modulation m in Modulation.values) {
        for (final (OfdmNumerology nu, int n, List<int> ks)
            in <(OfdmNumerology, int, List<int>)>[
              (
                OfdmNumerology.legacy,
                OfdmMath.teachingN,
                OfdmMath.teachingIndices,
              ),
              (
                OfdmNumerology.legacy,
                64,
                OfdmNumerology.legacy.realUsedIndices,
              ),
              (OfdmNumerology.he, 256, OfdmNumerology.he.realUsedIndices),
            ]) {
          final OfdmSymbol s = _symbol(nu, n, ks, m);
          final List<RecoveredPoint> got = OfdmMath.receive(s);
          expect(got.length, ks.length);
          for (final RecoveredPoint p in got) {
            final ConstellationPoint sent = s.points[p.k]!;
            expect(p.i, closeTo(sent.i, 1e-12), reason: '${m.label} k=${p.k}');
            expect(p.q, closeTo(sent.q, 1e-12), reason: '${m.label} k=${p.k}');
            // And it slices back to the same symbol.
            expect(ModulationMath.decide(m, p.i, p.q).symbol, sent.symbol);
          }
        }
      }
    });

    test(
      'a subcarrier\'s spectrum is zero at every other subcarrier center',
      () {
        for (final OfdmNumerology nu in OfdmNumerology.values) {
          final double df = nu.spacingHz;
          for (int k = -26; k <= 26; k++) {
            expect(OfdmMath.subcarrierSpectrum(k, k * df, df), 1);
            for (int m = -30; m <= 30; m++) {
              if (m == k) continue;
              expect(
                OfdmMath.subcarrierSpectrum(k, m * df, df).abs(),
                lessThan(1e-12),
                reason: '${nu.shortLabel}: sinc of $k at center $m',
              );
            }
          }
        }
        // The same, measured: a symbol carrying one subcarrier puts energy in
        // its own FFT bin and nothing in any other.
        final OfdmSymbol one = _symbol(OfdmNumerology.legacy, 64, <int>[
          5,
        ], Modulation.qpsk);
        final Float64List re = Float64List.fromList(one.re);
        final Float64List im = Float64List.fromList(one.im);
        FourierDsp.fftInPlace(re, im);
        for (int b = 0; b < 64; b++) {
          final double mag = math.sqrt(re[b] * re[b] + im[b] * im[b]) / 64;
          if (b == 5) {
            expect(mag, closeTo(1, 1e-12)); // QPSK points have unit amplitude
          } else {
            expect(mag, lessThan(1e-12), reason: 'bin $b');
          }
        }
      },
    );

    test('20 MS/s / 64 = 312.5 kHz, and HE is 78.125 kHz with a 12.8 µs '
        'symbol', () {
      expect(OfdmMath.spacingFor(20e6, 64), 312500);
      expect(OfdmNumerology.legacy.spacingHz, 312500);
      expect(OfdmNumerology.legacy.usefulSeconds, closeTo(3.2e-6, 1e-18));
      expect(OfdmMath.spacingFor(20e6, 256), 78125);
      expect(OfdmNumerology.he.spacingHz, 78125);
      expect(OfdmNumerology.he.usefulSeconds, closeTo(12.8e-6, 1e-18));
      // The symbol stretches exactly 4x.
      expect(
        OfdmNumerology.he.usefulSeconds / OfdmNumerology.legacy.usefulSeconds,
        closeTo(4, 1e-12),
      );
      // Both real FFT sizes sample at 20 MS/s.
      for (final OfdmNumerology nu in OfdmNumerology.values) {
        expect(OfdmMath.sampleRateHz(nu.realFftSize, nu.spacingHz), 20e6);
      }
    });

    test('with the default scene, the FFT analyzer catches more Bluetooth '
        'hops than a swept analyzer at 100 kHz RBW (seeded)', () {
      final RaceRun run = RaceRun.compute(
        config: const RaceSceneConfig(),
        spanMhz: 100,
        rbwHz: 100e3,
      );
      final RaceTally bt = run.tally(RaceSource.bluetooth);
      expect(bt.total, greaterThan(300)); // 200 ms / 625 us = 320 slots
      expect(bt.fftCaught, bt.total);
      expect(bt.fftCaught, greaterThan(bt.sweptCaught));
      // Expected catch rate is about (0.625 + 0.275) / 25 ms, under 10%.
      expect(bt.sweptCaught / bt.total, lessThan(0.1));
      // Same seed, same answer.
      final RaceRun again = RaceRun.compute(
        config: const RaceSceneConfig(),
        spanMhz: 100,
        rbwHz: 100e3,
      );
      expect(again.tally(RaceSource.bluetooth).sweptCaught, bt.sweptCaught);
    });
  });

  group('swept analyzer', () {
    test('catches agrees with a brute-force walk through time', () {
      final math.Random rng = math.Random(3);
      for (final double rbw in <double>[1e6, 100e3, 30e3]) {
        final SweptAnalyzer a = SweptAnalyzer(
          startMhz: 2400,
          spanMhz: 100,
          rbwHz: rbw,
        );
        final double st = a.sweepSeconds;
        for (int i = 0; i < 300; i++) {
          final double t0 = rng.nextDouble() * 0.05;
          final double dur = 50e-6 + rng.nextDouble() * 8e-3;
          final double f0 = 2400 + rng.nextDouble() * 100;
          final double f1 = rng.nextBool()
              ? f0
              : f0 + (rng.nextDouble() - 0.5) * 30;
          final RaceEmission e = RaceEmission(
            source: RaceSource.microwave,
            t0: t0,
            t1: t0 + dur,
            startMhz: f0,
            endMhz: f1,
            bandwidthMhz: 1,
            dbm: -40,
          );
          // Brute force: step finely enough that the tuned frequency moves
          // far less than the tolerance between steps.
          final double tol = 0.5 + rbw / 2e6;
          final double step = math.min(st * tol / 100 / 20, dur / 2000);
          bool hit = false;
          for (double t = e.t0; t <= e.t1 && !hit; t += step) {
            if ((a.tunedMhzAt(t) - e.centerAt(t)).abs() <= tol * 0.999) {
              hit = true;
            }
          }
          if (hit) {
            expect(a.catches(e), isTrue, reason: 'rbw $rbw, emission $i');
          }
          if (!a.catches(e)) expect(hit, isFalse);
        }
      }
    });

    test('at 1 MHz RBW the sweep (0.25 ms) outruns every hop and catches '
        'them all', () {
      final RaceRun run = RaceRun.compute(
        config: const RaceSceneConfig(),
        spanMhz: 100,
        rbwHz: 1e6,
      );
      final RaceTally bt = run.tally(RaceSource.bluetooth);
      expect(bt.sweptCaught, bt.total);
    });

    test('at 10 kHz RBW one sweep outlasts a 200 ms run: it covers 8% of the '
        'span', () {
      final RaceRun run = RaceRun.compute(
        config: const RaceSceneConfig(),
        spanMhz: 100,
        rbwHz: 10e3,
      );
      expect(run.sweepsInRun, closeTo(0.08, 1e-12));
      expect(run.spanCoveredFraction, closeTo(0.08, 1e-12));
      // The swept waterfall has cells it never looked at.
      expect(run.sweptGrid.any((double v) => v.isNaN), isTrue);
      // The FFT waterfall has none.
      expect(run.fftGrid.any((double v) => v.isNaN), isFalse);
    });

    test('the swept waterfall only holds signal where it looked', () {
      final RaceRun run = RaceRun.compute(
        config: const RaceSceneConfig(),
        spanMhz: 100,
        rbwHz: 100e3,
      );
      int looked = 0;
      for (int i = 0; i < run.sweptGrid.length; i++) {
        final double v = run.sweptGrid[i];
        if (!v.isNaN) looked++;
        // Anything the swept analyzer measured, the FFT analyzer measured
        // at least as strong in the same cell.
        if (!v.isNaN) expect(run.fftGrid[i], greaterThanOrEqualTo(v));
      }
      // 25 ms sweeps over 96 rows of about 2 ms: each row sees about 1/12 of
      // the columns.
      expect(looked / run.sweptGrid.length, closeTo(1 / 12, 0.03));
    });
  });

  group('scene', () {
    test('microwave: on 8.3 of 16.7 ms at 60 Hz, 10 of 20 ms at 50 Hz', () {
      expect(RaceScene.microwaveOnSeconds(60), closeTo(8.333e-3, 1e-6));
      expect(RaceScene.microwaveOnSeconds(50), closeTo(10e-3, 1e-12));
      final List<RaceEmission> e = RaceScene.generate(
        const RaceSceneConfig(mainsHz: 50, runSeconds: 1),
      ).where((RaceEmission x) => x.source == RaceSource.microwave).toList();
      expect(e.length, inInclusiveRange(50, 51));
      expect(e[1].t0 - e[0].t0, closeTo(0.02, 1e-12));
    });

    test('Bluetooth: 1,600 hops per second over 2402 to 2480 MHz, 1 MHz '
        'wide', () {
      final List<RaceEmission> bt = RaceScene.generate(
        const RaceSceneConfig(runSeconds: 1),
      ).where((RaceEmission x) => x.source == RaceSource.bluetooth).toList();
      expect(bt.length, 1600);
      final Set<double> channels = <double>{
        for (final RaceEmission h in bt) h.startMhz,
      };
      expect(channels.every((double f) => f >= 2402 && f <= 2480), isTrue);
      expect(channels.length, greaterThan(70)); // uniform over 79
      expect(bt.every((RaceEmission h) => h.bandwidthMhz == 1), isTrue);
    });

    test('BLE advertises on 2402, 2426 and 2480 MHz only', () {
      final Set<double> f = <double>{
        for (final RaceEmission x in RaceScene.generate(
          const RaceSceneConfig(runSeconds: 1),
        ))
          if (x.source == RaceSource.ble) x.startMhz,
      };
      expect(f, <double>{2402, 2426, 2480});
    });

    test('Wi-Fi frames last 244 µs, 16.6 MHz wide on channel 6, with at '
        'least DIFS between them', () {
      expect(RaceScene.wifiFrameSeconds, closeTo(244e-6, 1e-15));
      final List<RaceEmission> w = RaceScene.generate(
        const RaceSceneConfig(),
      ).where((RaceEmission x) => x.source == RaceSource.wifi).toList();
      for (int i = 1; i < w.length; i++) {
        final double gap = w[i].t0 - w[i - 1].t1;
        expect(gap, greaterThanOrEqualTo(34e-6 - 1e-12));
        expect(gap, lessThanOrEqualTo((34 + 15 * 9) * 1e-6 + 1e-12));
      }
      expect(w.first.startMhz, 2437);
      expect(w.first.bandwidthMhz, 16.6);
    });

    test('the video camera is continuous for the whole run', () {
      final List<RaceEmission> v = RaceScene.generate(
        const RaceSceneConfig(),
      ).where((RaceEmission x) => x.source == RaceSource.video).toList();
      expect(v, isNotEmpty);
      for (final RaceEmission c in v) {
        expect(c.t0, 0);
        expect(c.t1, 0.2);
        expect(c.startMhz, c.endMhz);
      }
    });
  });

  group('OFDM symbol', () {
    test('the inverse FFT undoes the FFT', () {
      final math.Random rng = math.Random(11);
      final Float64List re = Float64List(64);
      final Float64List im = Float64List(64);
      final List<double> r0 = <double>[];
      final List<double> i0 = <double>[];
      for (int i = 0; i < 64; i++) {
        re[i] = rng.nextDouble() - 0.5;
        im[i] = rng.nextDouble() - 0.5;
        r0.add(re[i]);
        i0.add(im[i]);
      }
      FourierDsp.fftInPlace(re, im);
      FourierDsp.ifftInPlace(re, im);
      for (int i = 0; i < 64; i++) {
        expect(re[i], closeTo(r0[i], 1e-14));
        expect(im[i], closeTo(i0[i], 1e-14));
      }
    });

    test('the IFFT samples are samples of s(t)', () {
      final OfdmSymbol s = _symbol(OfdmNumerology.he, 16, <int>[
        -3,
        1,
        2,
        7,
      ], Modulation.qam16);
      for (int i = 0; i < s.n; i++) {
        final ({double re, double im}) v = s.valueAt(i * s.usefulSeconds / s.n);
        expect(v.re, closeTo(s.re[i], 1e-12));
        expect(v.im, closeTo(s.im[i], 1e-12));
      }
    });

    test('the cyclic prefix is the last GI of the symbol', () {
      for (final double gi in OfdmNumerology.he.guardOptionsSeconds) {
        final OfdmSymbol s = _symbol(
          OfdmNumerology.he,
          256,
          OfdmNumerology.he.realUsedIndices,
          Modulation.qam64,
          gi: gi,
        );
        expect(s.cpSamples, (gi / 12.8e-6 * 256).round());
        final ({Float64List re, Float64List im}) tx = s.withCyclicPrefix();
        expect(tx.re.length, 256 + s.cpSamples);
        for (int i = 0; i < s.cpSamples; i++) {
          expect(tx.re[i], s.re[256 - s.cpSamples + i]);
          expect(tx.im[i], s.im[256 - s.cpSamples + i]);
        }
      }
      // Legacy 0.8 us at N = 64: 16 samples. Teaching N = 16: 4.
      expect(OfdmMath.cpSamples(64, 0.8e-6, 312500), 16);
      expect(OfdmMath.cpSamples(16, 0.8e-6, 312500), 4);
      expect(OfdmMath.cpSamples(16, 0.8e-6, 78125), 1);
    });

    test('20 MHz subcarrier counts: legacy 52 without DC, HE 242', () {
      expect(OfdmNumerology.legacy.realUsedIndices.length, 52);
      expect(OfdmNumerology.legacy.realUsedIndices.contains(0), isFalse);
      expect(OfdmNumerology.he.realUsedIndices.length, 242);
    });

    test('a subcarrier keeps its point when others are toggled', () {
      final Map<int, ConstellationPoint> a = OfdmMath.randomPoints(
        indices: <int>[1, 2, 3],
        modulation: Modulation.qam16,
        seed: 4,
      );
      final Map<int, ConstellationPoint> b = OfdmMath.randomPoints(
        indices: <int>[-5, 2, 6],
        modulation: Modulation.qam16,
        seed: 4,
      );
      expect(b[2]!.symbol, a[2]!.symbol);
    });
  });

  group('analyzer rainbow (GL-003 §8.22)', () {
    test('the stops are §8.22\'s table exactly', () {
      expect(AppAnalyzerRainbow.stops, const <Color>[
        Color(0xFF0A1A3F),
        Color(0xFF173A8C),
        Color(0xFF1C84C4),
        Color(0xFF2BAE5E),
        Color(0xFFE6D324),
        Color(0xFFF09A2C),
        Color(0xFFDE2F2F),
        Color(0xFFFFFFFF),
      ]);
    });

    test('dBm maps weak to strong: NaN 0, floor 1, top 7', () {
      expect(AppAnalyzerRainbow.stopFor(double.nan), 0);
      expect(AppAnalyzerRainbow.stopFor(-120), 1);
      expect(AppAnalyzerRainbow.stopFor(-95), 1);
      expect(AppAnalyzerRainbow.stopFor(-30), 7);
      expect(AppAnalyzerRainbow.stopFor(-10), 7);
      int last = 0;
      for (double d = -100; d <= -25; d += 0.5) {
        final int s = AppAnalyzerRainbow.stopFor(d);
        expect(s, greaterThanOrEqualTo(last));
        last = s;
      }
      for (int s = 1; s <= 7; s++) {
        expect(AppAnalyzerRainbow.stopFor(AppAnalyzerRainbow.dbmForStop(s)), s);
      }
    });
  });

  test('the fingerprints are word for word the Spectrum Analysis cards', () {
    // Join the module's adjacent string literals, then look for each line.
    final String src = File(
      'lib/screens/tools/educational/spectrum_analysis_screen.dart',
    ).readAsStringSync().replaceAll(RegExp(r"'\s*\n\s*'"), '');
    expect(kRaceFingerprints, hasLength(4));
    for (final String f in kRaceFingerprints.values) {
      expect(src.contains(f), isTrue, reason: f);
    }
  });
}
