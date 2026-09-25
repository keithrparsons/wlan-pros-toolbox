// OFDM as an inverse FFT: the pure-Dart math behind mode 4 of the Wi-Fi Lab
// "Fourier and FFT" tool (fourier-fft). No Flutter imports.
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/11-fourier-part2.md and the research brief §4 (the Wi-Fi
// OFDM numerology table and the symbol equation). No third-party Fourier or
// OFDM tool was consulted.
//
// The symbol:  s(t) = sum_k X_k e^(j 2 pi k df t),  0 <= t < T = 1/df
// Sampled at t = n T / N (a sample rate of N x df), s(n T / N) is exactly
// N x IDFT(X)[n], so the transmitter builds the symbol with an inverse FFT and
// the receiver gets X back with a forward FFT over the same N samples.
//
// The cyclic prefix copies the last GI of the symbol to its front. Because
// s(t) repeats every T, the prefix is simply s(t) for -GI <= t < 0.
//
// Each subcarrier on its own, over the receiver's T-long FFT window, has the
// spectrum X_k T sinc((f - k df) T), with sinc(x) = sin(pi x) / (pi x). At
// every other subcarrier center f = m df (m != k) the argument is the nonzero
// integer m - k, where sinc is zero: that is orthogonality.
//
// Constellation points come from ModulationMath (the Modulation Simulator),
// unmodified, so the two tools draw the same points.

import 'dart:math' as math;
import 'dart:typed_data';

import '../rf/modulation_math.dart';
import 'fourier_dsp.dart';

/// Legacy and HE subcarrier numerology at 20 MHz (research brief §4 table).
enum OfdmNumerology {
  legacy(
    label: 'Legacy (802.11a/g/n/ac)',
    shortLabel: 'Legacy',
    spacingHz: 312500,
    guardOptionsSeconds: <double>[0.8e-6],
    realFftSize: 64,
  ),
  he(
    label: 'HE (802.11ax/be)',
    shortLabel: 'HE',
    spacingHz: 78125,
    guardOptionsSeconds: <double>[0.8e-6, 1.6e-6, 3.2e-6],
    realFftSize: 256,
  );

  const OfdmNumerology({
    required this.label,
    required this.shortLabel,
    required this.spacingHz,
    required this.guardOptionsSeconds,
    required this.realFftSize,
  });

  final String label;
  final String shortLabel;

  /// Subcarrier spacing, delta f.
  final double spacingHz;

  /// Guard intervals offered. The first is the default.
  final List<double> guardOptionsSeconds;

  /// FFT size of a 20 MHz channel (20 MS/s divided by the spacing).
  final int realFftSize;

  /// Useful symbol time T = 1 / delta f.
  double get usefulSeconds => 1 / spacingHz;

  /// Subcarrier indices a 20 MHz channel uses. Legacy 802.11a/g: 52 tones,
  /// -26 .. +26 without DC (48 data + 4 pilot). HE: the 242-tone RU,
  /// -122 .. -2 and +2 .. +122.
  List<int> get realUsedIndices => switch (this) {
    OfdmNumerology.legacy => <int>[
      for (int k = -26; k <= 26; k++)
        if (k != 0) k,
    ],
    OfdmNumerology.he => <int>[
      for (int k = -122; k <= 122; k++)
        if (k.abs() >= 2) k,
    ],
  };
}

/// One OFDM symbol: the constellation point on each active subcarrier, the N
/// time samples an inverse FFT makes of them, and the cyclic prefix length.
class OfdmSymbol {
  OfdmSymbol({
    required this.numerology,
    required this.n,
    required this.guardSeconds,
    required Map<int, ConstellationPoint> points,
    required this.re,
    required this.im,
  }) : points = Map<int, ConstellationPoint>.unmodifiable(points);

  final OfdmNumerology numerology;

  /// IFFT size.
  final int n;
  final double guardSeconds;

  /// Subcarrier index k (negative below the channel center) to its point.
  final Map<int, ConstellationPoint> points;

  /// s(n T / N), n = 0 .. N-1: the useful part of the symbol, before the CP.
  final Float64List re;
  final Float64List im;

  double get spacingHz => numerology.spacingHz;
  double get usefulSeconds => numerology.usefulSeconds;
  double get totalSeconds => usefulSeconds + guardSeconds;
  double get sampleRateHz => OfdmMath.sampleRateHz(n, spacingHz);
  int get cpSamples => OfdmMath.cpSamples(n, guardSeconds, spacingHz);

  /// Active subcarrier indices, lowest first.
  List<int> get indices => points.keys.toList()..sort();

  /// The transmitted samples: the last [cpSamples] copied to the front.
  ({Float64List re, Float64List im}) withCyclicPrefix() {
    final int cp = cpSamples;
    final Float64List r = Float64List(n + cp);
    final Float64List q = Float64List(n + cp);
    for (int i = 0; i < cp; i++) {
      r[i] = re[n - cp + i];
      q[i] = im[n - cp + i];
    }
    for (int i = 0; i < n; i++) {
      r[cp + i] = re[i];
      q[cp + i] = im[i];
    }
    return (re: r, im: q);
  }

  /// s(t) straight from the sum, for any t (it repeats every T, so negative t
  /// lands in the cyclic prefix).
  ({double re, double im}) valueAt(double tSeconds) {
    double r = 0;
    double q = 0;
    points.forEach((int k, ConstellationPoint p) {
      final double a = 2 * math.pi * k * spacingHz * tSeconds;
      final double c = math.cos(a);
      final double s = math.sin(a);
      r += p.i * c - p.q * s;
      q += p.i * s + p.q * c;
    });
    return (re: r, im: q);
  }

  /// Largest |I| or |Q| over the N samples (at least 1e-9).
  double get peakComponent {
    double m = 1e-9;
    for (int i = 0; i < n; i++) {
      m = math.max(m, math.max(re[i].abs(), im[i].abs()));
    }
    return m;
  }
}

/// What the receiver's FFT gives back on each subcarrier.
typedef RecoveredPoint = ({int k, double i, double q, double error});

abstract final class OfdmMath {
  /// Teaching view: 16 subcarriers, k = -8 .. +7.
  static const int teachingN = 16;
  static const List<int> teachingIndices = <int>[
    -8,
    -7,
    -6,
    -5,
    -4,
    -3,
    -2,
    -1,
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
  ];

  /// The 20 MHz channel's sample rate.
  static const double channelSampleRateHz = 20e6;

  /// FFT bin that holds subcarrier k (negative k wrap to the top half).
  static int bin(int k, int n) => ((k % n) + n) % n;

  /// Sample rate of an N-point symbol at [spacingHz]: N x delta f.
  static double sampleRateHz(int n, double spacingHz) => n * spacingHz;

  /// Subcarrier spacing a receiver sampling at [fs] with an N-point FFT gets:
  /// its bin spacing, Fs / N.
  static double spacingFor(double fs, int n) => FourierDsp.binSpacingHz(fs, n);

  /// Cyclic prefix length in samples: GI x N x delta f.
  static int cpSamples(int n, double guardSeconds, double spacingHz) =>
      (guardSeconds * n * spacingHz).round();

  /// sin(pi x) / (pi x), 1 at x = 0.
  static double sinc(double x) {
    if (x.abs() < 1e-12) return 1;
    final double a = math.pi * x;
    return math.sin(a) / a;
  }

  /// Subcarrier k's spectrum at [fHz] (offset from the channel center),
  /// normalized so its peak is 1: sinc((f - k df) / df).
  static double subcarrierSpectrum(int k, double fHz, double spacingHz) =>
      sinc((fHz - k * spacingHz) / spacingHz);

  /// Builds the symbol with an inverse FFT: X_k in bin(k), then
  /// s(n T / N) = N x IFFT(X)[n].
  static OfdmSymbol build({
    required OfdmNumerology numerology,
    required int n,
    required double guardSeconds,
    required Map<int, ConstellationPoint> points,
  }) {
    if (!FourierDsp.isPowerOfTwo(n)) {
      throw ArgumentError('N must be a power of two, got $n');
    }
    final Float64List re = Float64List(n);
    final Float64List im = Float64List(n);
    points.forEach((int k, ConstellationPoint p) {
      if (k < -n ~/ 2 || k >= n ~/ 2) {
        throw ArgumentError('subcarrier $k does not fit in N = $n');
      }
      re[bin(k, n)] = p.i;
      im[bin(k, n)] = p.q;
    });
    FourierDsp.ifftInPlace(re, im);
    for (int i = 0; i < n; i++) {
      re[i] *= n;
      im[i] *= n;
    }
    return OfdmSymbol(
      numerology: numerology,
      n: n,
      guardSeconds: guardSeconds,
      points: points,
      re: re,
      im: im,
    );
  }

  /// The receiver: drop the cyclic prefix, FFT the N useful samples, divide
  /// by N, and read each active subcarrier's bin.
  static List<RecoveredPoint> receive(OfdmSymbol s) {
    final ({Float64List re, Float64List im}) tx = s.withCyclicPrefix();
    final int cp = s.cpSamples;
    final Float64List re = Float64List(s.n);
    final Float64List im = Float64List(s.n);
    for (int i = 0; i < s.n; i++) {
      re[i] = tx.re[cp + i];
      im[i] = tx.im[cp + i];
    }
    FourierDsp.fftInPlace(re, im);
    return <RecoveredPoint>[
      for (final int k in s.indices)
        () {
          final int b = bin(k, s.n);
          final double i = re[b] / s.n;
          final double q = im[b] / s.n;
          final ConstellationPoint p = s.points[k]!;
          final double di = i - p.i;
          final double dq = q - p.q;
          return (k: k, i: i, q: q, error: math.sqrt(di * di + dq * dq));
        }(),
    ];
  }

  /// A point per index, drawn from [modulation] with a seeded generator, so
  /// the same seed always gives the same data.
  static Map<int, ConstellationPoint> randomPoints({
    required Iterable<int> indices,
    required Modulation modulation,
    required int seed,
  }) {
    final math.Random rng = math.Random(seed);
    final Map<int, ConstellationPoint> out = <int, ConstellationPoint>{};
    // Draw for the widest set so a subcarrier keeps its point when others are
    // toggled: the k-th draw always belongs to subcarrier k.
    final List<int> sorted = indices.toList()..sort();
    final Map<int, int> symbolFor = <int, int>{};
    for (int k = -128; k < 128; k++) {
      symbolFor[k] = ModulationMath.randomSymbol(modulation, rng);
    }
    for (final int k in sorted) {
      out[k] = ModulationMath.map(modulation, symbolFor[k]!);
    }
    return out;
  }
}
