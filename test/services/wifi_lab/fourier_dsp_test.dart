// Unit tests for FourierDsp (Wi-Fi Classroom "Fourier and FFT", part 1).
//
// The first block is the spec's "Done means" list, one test each: ENBW for
// Hann and rectangular, an on-bin tone landing in bins k and N-k only,
// Parseval, bin spacing Fs/N, and the 20 MS/s, N = 64 Wi-Fi case. The rest
// hold the FFT to the direct DFT and check that each lesson preset on the
// screen really shows what its hint text says it shows.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fourier_dsp.dart';

double _mag(SpectrumAnalysis a, int k) =>
    math.sqrt(a.re[k] * a.re[k] + a.im[k] * a.im[k]);

void main() {
  group('spec: Done means', () {
    test('ENBW computed from the window: Hann 1.50, rectangular 1.00', () {
      for (final int n in FourierDsp.fftSizes) {
        final double hann = FourierDsp.enbwBins(
          FourierDsp.windowValues(SpectrumWindow.hann, n),
        );
        final double rect = FourierDsp.enbwBins(
          FourierDsp.windowValues(SpectrumWindow.rectangular, n),
        );
        expect(hann, closeTo(1.50, 0.01), reason: 'Hann at N = $n');
        expect(rect, closeTo(1.00, 0.01), reason: 'rectangular at N = $n');
      }
    });

    test('an on-bin tone with a rectangular window lands in bins k and N-k '
        'only', () {
      const int n = 256;
      const double fs = 25600;
      for (final int k in <int>[1, 20, 37, 127]) {
        final SpectrumAnalysis a = FourierDsp.analyze(
          parts: <SineComponent>[
            SineComponent(
              amplitude: 0.7,
              frequencyHz: k * fs / n,
              phaseDeg: 30,
            ),
          ],
          sampleRateHz: fs,
          n: n,
          window: SpectrumWindow.rectangular,
        );
        double total = 0;
        for (int b = 0; b < n; b++) {
          total += _mag(a, b) * _mag(a, b);
        }
        final double inKAndMirror =
            _mag(a, k) * _mag(a, k) + _mag(a, n - k) * _mag(a, n - k);
        expect(inKAndMirror / total, closeTo(1, 1e-12), reason: 'k = $k');
        // Each of the two bins holds A*N/2 in magnitude.
        expect(_mag(a, k), closeTo(0.7 * n / 2, 1e-9));
        expect(_mag(a, n - k), closeTo(0.7 * n / 2, 1e-9));
        // And the one-sided dBFS reading is the true level.
        expect(a.levelsDb[k], closeTo(20 * math.log(0.7) / math.ln10, 1e-9));
      }
    });

    test('Parseval holds: sum |x|^2 = (1/N) sum |X|^2', () {
      final math.Random rng = math.Random(11);
      for (final int n in FourierDsp.fftSizes) {
        final Float64List x = Float64List(n);
        for (int i = 0; i < n; i++) {
          x[i] = rng.nextDouble() * 2 - 1;
        }
        final Float64List re = Float64List.fromList(x);
        final Float64List im = Float64List(n);
        FourierDsp.fftInPlace(re, im);
        final double t = FourierDsp.timeEnergy(x);
        final double f = FourierDsp.frequencyEnergy(re, im);
        expect((t - f).abs() / t, lessThan(1e-12), reason: 'N = $n');
      }
    });

    test(
      'bin spacing is Fs/N and capture time is N/Fs; their product is 1',
      () {
        for (final double fs in <double>[12800, 25600, 51200, 102400]) {
          for (final int n in FourierDsp.fftSizes) {
            expect(FourierDsp.binSpacingHz(fs, n), fs / n);
            expect(FourierDsp.captureSeconds(fs, n), n / fs);
            expect(
              FourierDsp.binSpacingHz(fs, n) * FourierDsp.captureSeconds(fs, n),
              closeTo(1, 1e-12),
            );
          }
        }
      },
    );

    test('20 MS/s with N = 64 gives 312.5 kHz bins and a 3.2 us frame; '
        'HE (N = 256) gives 78.125 kHz and 12.8 us', () {
      expect(FourierDsp.binSpacingHz(20e6, 64), 312500);
      expect(FourierDsp.captureSeconds(20e6, 64), closeTo(3.2e-6, 1e-18));
      expect(FourierDsp.binSpacingHz(20e6, 256), 78125);
      expect(FourierDsp.captureSeconds(20e6, 256), closeTo(12.8e-6, 1e-18));
    });
  });

  group('FFT', () {
    test('matches the direct DFT from the definition', () {
      final math.Random rng = math.Random(3);
      for (final int n in <int>[64, 128, 512]) {
        final List<double> x = <double>[
          for (int i = 0; i < n; i++) rng.nextDouble() * 2 - 1,
        ];
        final ({Float64List re, Float64List im}) ref = FourierDsp.dft(x);
        final Float64List re = Float64List.fromList(x);
        final Float64List im = Float64List(n);
        FourierDsp.fftInPlace(re, im);
        for (int k = 0; k < n; k++) {
          expect(re[k], closeTo(ref.re[k], 1e-9), reason: 'Re X[$k], N $n');
          expect(im[k], closeTo(ref.im[k], 1e-9), reason: 'Im X[$k], N $n');
        }
      }
    });

    test('rejects a length that is not a power of two', () {
      expect(
        () => FourierDsp.fftInPlace(Float64List(100), Float64List(100)),
        throwsArgumentError,
      );
    });

    test('a DC offset lands in bin 0 and reads its true level', () {
      // A cosine at 0 Hz with amplitude 0.5 is a constant 0.5.
      final SpectrumAnalysis a = FourierDsp.analyze(
        parts: const <SineComponent>[
          SineComponent(amplitude: 0.5, frequencyHz: 0),
        ],
        sampleRateHz: 25600,
        n: 64,
        window: SpectrumWindow.hann,
      );
      expect(a.levelsDb[0], closeTo(20 * math.log(0.5) / math.ln10, 1e-9));
    });
  });

  group('windows', () {
    test('every window is DFT-even and peaks at 1 in the middle', () {
      for (final SpectrumWindow w in SpectrumWindow.values) {
        final Float64List v = FourierDsp.windowValues(w, 64);
        expect(v[32], closeTo(1, 1e-6), reason: w.label);
        for (int i = 1; i < 32; i++) {
          expect(v[i], closeTo(v[64 - i], 1e-12), reason: '${w.label} $i');
        }
      }
    });

    test('ENBW of the other windows matches the brief within 0.02 bins', () {
      double enbw(SpectrumWindow w) =>
          FourierDsp.enbwBins(FourierDsp.windowValues(w, 1024));
      expect(enbw(SpectrumWindow.hamming), closeTo(1.36, 0.02));
      expect(enbw(SpectrumWindow.blackmanHarris), closeTo(2.0, 0.02));
      expect(enbw(SpectrumWindow.flatTop), closeTo(3.77, 0.02));
    });

    test('scalloping loss computed from the window matches the brief', () {
      double loss(SpectrumWindow w) =>
          FourierDsp.scallopingLossDb(FourierDsp.windowValues(w, 1024));
      expect(loss(SpectrumWindow.rectangular), closeTo(3.9, 0.05));
      expect(loss(SpectrumWindow.hann), closeTo(1.4, 0.05));
      expect(loss(SpectrumWindow.hamming), closeTo(1.8, 0.1));
      expect(loss(SpectrumWindow.blackmanHarris), closeTo(0.8, 0.05));
      expect(loss(SpectrumWindow.flatTop), lessThan(0.02));
    });

    test('measured highest sidelobe agrees with the published figure; flat '
        'top matches it at N = 64 and falls toward -93 dB as N grows', () {
      for (final SpectrumWindow w in <SpectrumWindow>[
        SpectrumWindow.rectangular,
        SpectrumWindow.hann,
        SpectrumWindow.hamming,
        SpectrumWindow.blackmanHarris,
      ]) {
        for (final int n in <int>[64, 256]) {
          expect(
            FourierDsp.measuredHighestSidelobeDb(w, n: n),
            closeTo(w.publishedSidelobeDb, 0.7),
            reason: '${w.label}, N = $n',
          );
        }
      }
      // The brief's -88 dB flat-top figure is what this window measures at
      // N = 64. At larger N its far sidelobes drop to about -93 dB, so the
      // screen shows the published figure and the measured one side by side.
      expect(
        FourierDsp.measuredHighestSidelobeDb(SpectrumWindow.flatTop, n: 64),
        closeTo(SpectrumWindow.flatTop.publishedSidelobeDb, 0.5),
      );
      expect(
        FourierDsp.measuredHighestSidelobeDb(
          SpectrumWindow.flatTop,
          n: 1024,
          pad: 16,
        ),
        closeTo(-93, 0.5),
      );
    });
  });

  group('lesson presets show what their hints claim', () {
    const double fs = 25600;
    const List<SineComponent> neighbor = <SineComponent>[
      SineComponent(amplitude: 1, frequencyHz: 2050),
      SineComponent(amplitude: 0.01, frequencyHz: 2700),
    ];

    // Peak prominence of bin k over the lower of its two neighbors two bins
    // out; > 6 dB reads as a separate peak.
    double prominence(SpectrumAnalysis a, int k) =>
        a.levelsDb[k] - math.max(a.levelsDb[k - 2], a.levelsDb[k + 2]);

    test('weak neighbor 40 dB down: rectangular hides it, Blackman-Harris '
        'shows it at its true level', () {
      final SpectrumAnalysis rect = FourierDsp.analyze(
        parts: neighbor,
        sampleRateHz: fs,
        n: 256,
        window: SpectrumWindow.rectangular,
      );
      final SpectrumAnalysis bh = FourierDsp.analyze(
        parts: neighbor,
        sampleRateHz: fs,
        n: 256,
        window: SpectrumWindow.blackmanHarris,
      );
      const int k = 27; // 2700 Hz / 100 Hz
      // Rectangular: leakage from the main tone sits ~15 dB above -40 dB.
      expect(rect.levelsDb[k], greaterThan(-30));
      expect(prominence(rect, k), lessThan(3));
      // Blackman-Harris: a distinct peak at -40 dB.
      expect(bh.levelsDb[k], closeTo(-40, 0.5));
      expect(prominence(bh, k), greaterThan(10));
    });

    test('tone between bins: rectangular reads about 3.9 dB low, flat top '
        'reads the true level', () {
      const List<SineComponent> tone = <SineComponent>[
        SineComponent(amplitude: 1, frequencyHz: 2050),
      ];
      SpectrumAnalysis run(SpectrumWindow w) =>
          FourierDsp.analyze(parts: tone, sampleRateHz: fs, n: 256, window: w);
      final SpectrumAnalysis rect = run(SpectrumWindow.rectangular);
      final SpectrumAnalysis flat = run(SpectrumWindow.flatTop);
      expect(rect.levelsDb[rect.peakBin], closeTo(-3.9, 0.1));
      expect(flat.levelsDb[flat.peakBin], closeTo(0, 0.05));
    });

    test('halve N: two tones 300 Hz apart split at N = 256 and merge at '
        'N = 128 with Hann', () {
      const List<SineComponent> pair = <SineComponent>[
        SineComponent(amplitude: 1, frequencyHz: 2000),
        SineComponent(amplitude: 1, frequencyHz: 2300),
      ];
      SpectrumAnalysis run(int n) => FourierDsp.analyze(
        parts: pair,
        sampleRateHz: fs,
        n: n,
        window: SpectrumWindow.hann,
      );
      final SpectrumAnalysis big = run(256); // 100 Hz bins
      final SpectrumAnalysis small = run(128); // 200 Hz bins
      // At N = 256 the bins between the tones (21, 22) dip below both peaks.
      final double dip = math.max(big.levelsDb[21], big.levelsDb[22]);
      expect(big.levelsDb[20] - dip, greaterThan(3));
      expect(big.levelsDb[23] - dip, greaterThan(3));
      // At N = 128 (bins 10 and 11.5) there is no dip: one lump.
      final List<double> l = small.levelsDb.sublist(9, 14);
      int localMaxima = 0;
      for (int i = 1; i < l.length - 1; i++) {
        if (l[i] > l[i - 1] && l[i] >= l[i + 1]) localMaxima++;
      }
      expect(localMaxima, 1);
      expect(small.binSpacingHz, 2 * big.binSpacingHz);
      expect(small.captureSeconds, big.captureSeconds / 2);
    });
  });
}
