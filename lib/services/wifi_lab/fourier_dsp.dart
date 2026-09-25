// Fourier DSP: the pure-Dart math behind the Wi-Fi Lab "Fourier and FFT" tool
// (fourier-fft). No Flutter imports, so every number the screen shows can be
// unit-tested headless.
//
// CLEAN-ROOM BUILD (2026-09-25) from textbook DSP, per myPKA Deliverables/
// 2026-09-25-wifi-lab-cleanroom/specs/11-fourier-part1.md and the research
// brief's §4 (Keysight AN 150, the Tektronix RTSA primer, Harris 1978). No
// third-party Fourier tool's code or visuals were consulted.
//
// What lives here:
//   - a signal model: a sum of sines, x(t) = sum A_i cos(2 pi f_i t + phi_i)
//   - sampling that signal at Fs with N points
//   - five cosine-sum windows (DFT-even / periodic form, the form used for
//     spectral analysis, which is why Hann's ENBW comes out exactly 1.50)
//   - ENBW computed from the window itself: N * sum(w^2) / (sum w)^2
//   - an iterative radix-2 FFT and a direct DFT (the DFT is the reference the
//     tests hold the FFT to): X[k] = sum_n x[n] e^(-j 2 pi k n / N)
//   - a one-sided amplitude spectrum in dBFS, scaled so a sine of amplitude A
//     that lands exactly on a bin reads 20 log10(A) with any window
//   - bin spacing Fs/N and capture time N/Fs (their product is always 1)

import 'dart:math' as math;
import 'dart:typed_data';

/// One sine in the sum: A cos(2 pi f t + phi).
class SineComponent {
  const SineComponent({
    required this.amplitude,
    required this.frequencyHz,
    this.phaseDeg = 0,
  });

  /// Peak amplitude, linear (1.0 = full scale = 0 dBFS).
  final double amplitude;

  /// Frequency in hertz.
  final double frequencyHz;

  /// Phase in degrees at t = 0.
  final double phaseDeg;

  double get phaseRad => phaseDeg * math.pi / 180;

  /// Level in dB relative to full scale (amplitude 1). -infinity at 0.
  double get levelDb => amplitude <= 0
      ? double.negativeInfinity
      : 20 * math.log(amplitude) / math.ln10;

  /// The value of this sine at time [tSeconds].
  double valueAt(double tSeconds) =>
      amplitude * math.cos(2 * math.pi * frequencyHz * tSeconds + phaseRad);

  SineComponent copyWith({
    double? amplitude,
    double? frequencyHz,
    double? phaseDeg,
  }) => SineComponent(
    amplitude: amplitude ?? this.amplitude,
    frequencyHz: frequencyHz ?? this.frequencyHz,
    phaseDeg: phaseDeg ?? this.phaseDeg,
  );

  @override
  bool operator ==(Object other) =>
      other is SineComponent &&
      other.amplitude == amplitude &&
      other.frequencyHz == frequencyHz &&
      other.phaseDeg == phaseDeg;

  @override
  int get hashCode => Object.hash(amplitude, frequencyHz, phaseDeg);
}

/// The analyzer windows the tool offers. Every one is a cosine-sum window,
///   w[n] = sum_k (-1)^k a_k cos(2 pi k n / N),  n = 0 .. N-1,
/// in its DFT-even (periodic) form.
///
/// [publishedSidelobeDb] is the highest-sidelobe figure from the research
/// brief's table (Harris 1978 as restated by two sources; flat top from the
/// Berkeley Nucleonics RTSA book). The spec asks for that published figure on
/// screen; ENBW, by contrast, is computed from the window itself.
enum SpectrumWindow {
  rectangular('Rectangular', <double>[1], -13),
  hann('Hann', <double>[0.5, 0.5], -32),
  hamming('Hamming', <double>[0.54, 0.46], -43),
  blackmanHarris('Blackman-Harris (4-term)', <double>[
    0.35875,
    0.48829,
    0.14128,
    0.01168,
  ], -92),
  flatTop('Flat top', <double>[
    0.21557895,
    0.41663158,
    0.277263158,
    0.083578947,
    0.006947368,
  ], -88);

  const SpectrumWindow(this.label, this.coefficients, this.publishedSidelobeDb);

  /// Display name.
  final String label;

  /// Cosine-sum coefficients a_0 .. a_K (signs alternate in the formula).
  final List<double> coefficients;

  /// Highest sidelobe in dB, from the brief's published table.
  final double publishedSidelobeDb;
}

/// Result of analyzing one capture: the samples, the window, the full N-bin
/// complex DFT, and the one-sided dBFS spectrum the screen draws.
class SpectrumAnalysis {
  const SpectrumAnalysis({
    required this.sampleRateHz,
    required this.n,
    required this.window,
    required this.samples,
    required this.windowValues,
    required this.re,
    required this.im,
    required this.levelsDb,
  });

  final double sampleRateHz;
  final int n;
  final SpectrumWindow window;

  /// x[n], the raw samples (before windowing).
  final Float64List samples;

  /// w[n].
  final Float64List windowValues;

  /// Real and imaginary parts of X[k], k = 0 .. N-1 (the full N-bin DFT of
  /// the windowed samples).
  final Float64List re;
  final Float64List im;

  /// One-sided amplitude spectrum in dBFS for bins k = 0 .. N/2. A sine of
  /// amplitude A exactly on bin k reads 20 log10(A). Bins with no energy are
  /// -infinity; the painter clamps to its floor.
  final Float64List levelsDb;

  /// Fs / N, the spacing between bins.
  double get binSpacingHz => FourierDsp.binSpacingHz(sampleRateHz, n);

  /// N / Fs, how long the capture takes.
  double get captureSeconds => FourierDsp.captureSeconds(sampleRateHz, n);

  /// Equivalent noise bandwidth of the window, in bins.
  double get enbwBins => FourierDsp.enbwBins(windowValues);

  /// Resolution bandwidth in hertz: ENBW (bins) times the bin spacing.
  double get rbwHz => enbwBins * binSpacingHz;

  /// Frequency of bin [k].
  double binFrequencyHz(int k) => k * binSpacingHz;

  /// Index of the tallest one-sided bin (ties go to the lowest index).
  int get peakBin {
    int best = 0;
    for (int k = 1; k < levelsDb.length; k++) {
      if (levelsDb[k] > levelsDb[best]) best = k;
    }
    return best;
  }
}

/// Pure DSP helpers. All static; no state.
abstract final class FourierDsp {
  /// The FFT sizes the tool offers: powers of two from 64 to 4096.
  static const List<int> fftSizes = <int>[64, 128, 256, 512, 1024, 2048, 4096];

  /// Bin spacing, Fs / N, in hertz.
  static double binSpacingHz(double sampleRateHz, int n) => sampleRateHz / n;

  /// Capture (frame) time, N / Fs, in seconds.
  static double captureSeconds(double sampleRateHz, int n) => n / sampleRateHz;

  /// True when [n] is a positive power of two.
  static bool isPowerOfTwo(int n) => n > 0 && (n & (n - 1)) == 0;

  /// x(t) for a sum of sines.
  static double sumAt(List<SineComponent> parts, double tSeconds) {
    double v = 0;
    for (final SineComponent p in parts) {
      v += p.valueAt(tSeconds);
    }
    return v;
  }

  /// Largest possible |x(t)|: the sum of the amplitudes.
  static double peakBound(List<SineComponent> parts) {
    double s = 0;
    for (final SineComponent p in parts) {
      s += p.amplitude.abs();
    }
    return s;
  }

  /// x[n] = x(n / Fs) for n = 0 .. N-1.
  static Float64List sample(
    List<SineComponent> parts,
    double sampleRateHz,
    int n,
  ) {
    final Float64List out = Float64List(n);
    for (int i = 0; i < n; i++) {
      out[i] = sumAt(parts, i / sampleRateHz);
    }
    return out;
  }

  /// w[n] for [window], length [n], DFT-even (periodic) form.
  static Float64List windowValues(SpectrumWindow window, int n) {
    final Float64List w = Float64List(n);
    final List<double> a = window.coefficients;
    for (int i = 0; i < n; i++) {
      double v = 0;
      for (int k = 0; k < a.length; k++) {
        final double term = a[k] * math.cos(2 * math.pi * k * i / n);
        v += k.isEven ? term : -term;
      }
      w[i] = v;
    }
    return w;
  }

  /// Equivalent noise bandwidth in bins, computed from the window itself:
  /// N * sum(w^2) / (sum w)^2.
  static double enbwBins(List<double> w) {
    double s1 = 0;
    double s2 = 0;
    for (final double v in w) {
      s1 += v;
      s2 += v * v;
    }
    return w.length * s2 / (s1 * s1);
  }

  /// Scalloping loss in dB (a positive number): how much low a tone exactly
  /// half-way between two bins reads, compared with the same tone on a bin.
  /// Computed from the window: |sum w[n] e^(-j pi n / N)| / sum w[n].
  static double scallopingLossDb(List<double> w) {
    final int n = w.length;
    double re = 0;
    double im = 0;
    double sum = 0;
    for (int i = 0; i < n; i++) {
      final double a = math.pi * i / n;
      re += w[i] * math.cos(a);
      im -= w[i] * math.sin(a);
      sum += w[i];
    }
    final double ratio = math.sqrt(re * re + im * im) / sum;
    return -20 * math.log(ratio) / math.ln10;
  }

  /// Highest sidelobe of [window] in dB relative to the main-lobe peak,
  /// measured on a zero-padded transform. Used by the tests to check the
  /// published figures against the coefficients this file actually uses.
  static double measuredHighestSidelobeDb(
    SpectrumWindow window, {
    int n = 64,
    int pad = 64,
  }) {
    final int m = n * pad;
    final Float64List re = Float64List(m);
    final Float64List im = Float64List(m);
    final Float64List w = windowValues(window, n);
    for (int i = 0; i < n; i++) {
      re[i] = w[i];
    }
    fftInPlace(re, im);
    final Float64List mag = Float64List(m ~/ 2);
    for (int k = 0; k < m ~/ 2; k++) {
      mag[k] = math.sqrt(re[k] * re[k] + im[k] * im[k]);
    }
    // Walk down the main lobe to its first null (first local minimum).
    int k = 1;
    while (k < mag.length - 1 &&
        !(mag[k] <= mag[k - 1] && mag[k] <= mag[k + 1])) {
      k++;
    }
    double side = 0;
    for (int j = k; j < mag.length; j++) {
      if (mag[j] > side) side = mag[j];
    }
    if (side <= 0) return double.negativeInfinity;
    return 20 * math.log(side / mag[0]) / math.ln10;
  }

  static final Map<(SpectrumWindow, int), double> _sidelobeCache =
      <(SpectrumWindow, int), double>{};

  /// [measuredHighestSidelobeDb] for [window] at length [n], zero-padded to
  /// 65,536 points (at least 16x), cached. The screen shows this beside the
  /// published figure, because a window's far sidelobes can shift with N
  /// (flat top: about -88 dB at N = 64, about -93 dB from N = 256 up).
  static double measuredSidelobeAt(SpectrumWindow window, int n) =>
      _sidelobeCache.putIfAbsent(
        (window, n),
        () => measuredHighestSidelobeDb(
          window,
          n: n,
          pad: math.max(16, 65536 ~/ n),
        ),
      );

  /// In-place iterative radix-2 FFT. [re] and [im] must share a power-of-two
  /// length. Computes X[k] = sum_n x[n] e^(-j 2 pi k n / N).
  static void fftInPlace(Float64List re, Float64List im) {
    final int n = re.length;
    if (im.length != n) {
      throw ArgumentError('re and im lengths differ: $n vs ${im.length}');
    }
    if (!isPowerOfTwo(n)) {
      throw ArgumentError('FFT length must be a power of two, got $n');
    }
    // Bit-reversal permutation.
    for (int i = 1, j = 0; i < n; i++) {
      int bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final double tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final double ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    // Butterflies.
    for (int len = 2; len <= n; len <<= 1) {
      final double ang = -2 * math.pi / len;
      final double wr = math.cos(ang);
      final double wi = math.sin(ang);
      final int half = len >> 1;
      for (int i = 0; i < n; i += len) {
        double cr = 1;
        double ci = 0;
        for (int j = 0; j < half; j++) {
          final int a = i + j;
          final int b = a + half;
          final double xr = re[b] * cr - im[b] * ci;
          final double xi = re[b] * ci + im[b] * cr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
          final double nr = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = nr;
        }
      }
    }
  }

  /// Direct O(N^2) DFT of a real sequence, straight from the definition.
  /// Works for any N; the reference the FFT is tested against.
  static ({Float64List re, Float64List im}) dft(List<double> x) {
    final int n = x.length;
    final Float64List re = Float64List(n);
    final Float64List im = Float64List(n);
    for (int k = 0; k < n; k++) {
      double sr = 0;
      double si = 0;
      for (int i = 0; i < n; i++) {
        final double a = -2 * math.pi * k * i / n;
        sr += x[i] * math.cos(a);
        si += x[i] * math.sin(a);
      }
      re[k] = sr;
      im[k] = si;
    }
    return (re: re, im: im);
  }

  /// Samples [parts] at [sampleRateHz] with [n] points, applies [window], and
  /// transforms. [n] must be a power of two.
  static SpectrumAnalysis analyze({
    required List<SineComponent> parts,
    required double sampleRateHz,
    required int n,
    required SpectrumWindow window,
  }) {
    final Float64List x = sample(parts, sampleRateHz, n);
    final Float64List w = windowValues(window, n);
    final Float64List re = Float64List(n);
    final Float64List im = Float64List(n);
    double sumW = 0;
    for (int i = 0; i < n; i++) {
      re[i] = x[i] * w[i];
      sumW += w[i];
    }
    fftInPlace(re, im);
    return SpectrumAnalysis(
      sampleRateHz: sampleRateHz,
      n: n,
      window: window,
      samples: x,
      windowValues: w,
      re: re,
      im: im,
      levelsDb: oneSidedLevelsDb(re, im, sumW),
    );
  }

  /// One-sided amplitude spectrum in dBFS for k = 0 .. N/2, normalized by the
  /// window's coherent sum [sumW] so an on-bin sine of amplitude A reads
  /// 20 log10(A). DC and the Nyquist bin have no mirror image, so they are
  /// not doubled.
  static Float64List oneSidedLevelsDb(
    Float64List re,
    Float64List im,
    double sumW,
  ) {
    final int n = re.length;
    final int half = n ~/ 2;
    final Float64List out = Float64List(half + 1);
    for (int k = 0; k <= half; k++) {
      final double mag = math.sqrt(re[k] * re[k] + im[k] * im[k]);
      final double scale = (k == 0 || k == half) ? 1 / sumW : 2 / sumW;
      final double a = mag * scale;
      out[k] = a <= 0 ? double.negativeInfinity : 20 * math.log(a) / math.ln10;
    }
    return out;
  }

  /// Sum of |x[n]|^2 (time-domain energy).
  static double timeEnergy(List<double> x) {
    double s = 0;
    for (final double v in x) {
      s += v * v;
    }
    return s;
  }

  /// (1/N) sum of |X[k]|^2 over all N bins (frequency-domain energy).
  static double frequencyEnergy(List<double> re, List<double> im) {
    double s = 0;
    for (int k = 0; k < re.length; k++) {
      s += re[k] * re[k] + im[k] * im[k];
    }
    return s / re.length;
  }
}
