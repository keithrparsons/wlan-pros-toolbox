// Swept vs FFT race: the pure-Dart model behind mode 3 of the Wi-Fi Classroom
// "Fourier and FFT" tool (fourier-fft). No Flutter imports.
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/11-fourier-part2.md and the research brief §4 (the swept
// sweep-time formula from Keysight AN 150, and the interferer timing table).
// No third-party analyzer or Fourier tool was consulted.
//
// THE SCENE IS SYNTHETIC and the screen says so. One 2.4 GHz band with:
//   - a microwave oven: on for half of each mains cycle (8.3 of 16.7 ms at
//     60 Hz, 10 of 20 ms at 50 Hz), its frequency climbing across a sweep
//     width that is a parameter, because the sources disagree on it
//   - Bluetooth Classic: 79 x 1 MHz channels, 2402 to 2480 MHz, one hop per
//     625 us slot (1,600 hops/s), channels drawn uniformly at random (the real
//     sequence is pseudo-random). Each hop is drawn as its full slot.
//   - BLE advertising on 37/38/39 = 2402/2426/2480 MHz
//   - an analog video camera: continuous and fixed, its bandwidth a parameter
//   - Wi-Fi OFDM on channel 6: 16.6 MHz occupied, 1500-byte frames at
//     54 Mbps (244 us, from the Medium Access Simulator's airtime formula),
//     each followed by DIFS plus a random backoff (0 to 15 slots of 9 us)
//
// TWO ANALYZERS WATCH IT.
//   Swept: sweep time ST = k x Span / RBW^2, k = 2.5 (AN 150: k is 2 to 3 for
//   analog near-Gaussian RBW filters). Its tuned frequency climbs linearly
//   from the bottom of the span to the top once per ST, then flies back. It
//   sees an emission only if, at some instant, the emission is within RBW/2
//   of where it is tuned. [SweptAnalyzer.catches] solves that exactly: within
//   one sweep both frequencies are linear in time, so their difference is too.
//   FFT: an ideal gapless real-time analyzer. It transforms the whole span
//   every frame (about 1/RBW long) with no gaps between frames, so every
//   emission at least one frame long is caught.
//
// Digital RBW filters and FFT-assisted sweeps beat the formula (AN 150); the
// screen says so.

import 'dart:math' as math;
import 'dart:typed_data';

import 'medium_access_engine.dart';

/// The sources in the scene.
enum RaceSource {
  microwave('Microwave oven'),
  bluetooth('Bluetooth Classic'),
  ble('Bluetooth Low Energy (BLE)'),
  video('Analog video camera'),
  wifi('Wi-Fi (channel 6)');

  const RaceSource(this.label);
  final String label;
}

/// One transmission: from [t0] to [t1] seconds, its center frequency moving
/// linearly from [startMhz] to [endMhz] (equal for everything but the oven),
/// [bandwidthMhz] wide, received at [dbm].
class RaceEmission {
  const RaceEmission({
    required this.source,
    required this.t0,
    required this.t1,
    required this.startMhz,
    required this.endMhz,
    required this.bandwidthMhz,
    required this.dbm,
  });

  final RaceSource source;
  final double t0;
  final double t1;
  final double startMhz;
  final double endMhz;
  final double bandwidthMhz;
  final double dbm;

  double get duration => t1 - t0;

  /// Center frequency at time [t] (clamped to the emission's life).
  double centerAt(double t) {
    if (t1 <= t0 || startMhz == endMhz) return startMhz;
    final double u = ((t - t0) / (t1 - t0)).clamp(0.0, 1.0);
    return startMhz + (endMhz - startMhz) * u;
  }

  /// Lowest and highest frequency it touches between [ta] and [tb].
  (double, double) rangeDuring(double ta, double tb) {
    final double a = centerAt(math.max(ta, t0));
    final double b = centerAt(math.min(tb, t1));
    final double h = bandwidthMhz / 2;
    return (math.min(a, b) - h, math.max(a, b) + h);
  }

  /// True when any part of it falls inside [loMhz] .. [hiMhz].
  bool inSpan(double loMhz, double hiMhz) {
    final (double lo, double hi) = rangeDuring(t0, t1);
    return hi >= loMhz && lo <= hiMhz;
  }
}

/// A swept-tuned analyzer.
class SweptAnalyzer {
  const SweptAnalyzer({
    required this.startMhz,
    required this.spanMhz,
    required this.rbwHz,
    this.k = kSweepK,
  });

  /// AN 150's k for analog near-Gaussian RBW filters is 2 to 3.
  static const double kSweepK = 2.5;

  final double startMhz;
  final double spanMhz;
  final double rbwHz;
  final double k;

  /// ST = k x Span / RBW^2, in seconds (span and RBW in hertz).
  static double sweepTimeSeconds({
    required double spanHz,
    required double rbwHz,
    double k = kSweepK,
  }) => k * spanHz / (rbwHz * rbwHz);

  double get sweepSeconds =>
      sweepTimeSeconds(spanHz: spanMhz * 1e6, rbwHz: rbwHz, k: k);

  double get rbwMhz => rbwHz / 1e6;

  /// Where the analyzer is tuned at time [t].
  double tunedMhzAt(double t) {
    final double st = sweepSeconds;
    final double u = t / st - (t / st).floorToDouble();
    return startMhz + spanMhz * u;
  }

  /// Exact: is there an instant when [e] is within RBW/2 of the tuned
  /// frequency? Walks the sweeps that overlap the emission; within each, the
  /// gap between the two frequencies is linear in time, so checking both ends
  /// of the overlap is enough.
  bool catches(RaceEmission e) {
    final double st = sweepSeconds;
    final double tol = e.bandwidthMhz / 2 + rbwMhz / 2;
    final int m0 = (e.t0 / st).floor();
    final int m1 = (e.t1 / st).floor();
    for (int m = m0; m <= m1; m++) {
      final double a = math.max(e.t0, m * st);
      final double b = math.min(e.t1, (m + 1) * st);
      if (b <= a) continue;
      double tunedAt(double t) => startMhz + spanMhz * (t - m * st) / st;
      final double da = tunedAt(a) - e.centerAt(a);
      final double db = tunedAt(b) - e.centerAt(b);
      if (math.min(da, db) <= tol && math.max(da, db) >= -tol) return true;
    }
    return false;
  }
}

/// An ideal gapless real-time FFT analyzer.
class FftAnalyzer {
  const FftAnalyzer({required this.rbwHz});
  final double rbwHz;

  /// About 1/RBW: the capture time N/Fs of a rectangular-window FFT whose bin
  /// spacing is the RBW (part 1: bin spacing x capture time = 1).
  double get frameSeconds => 1 / rbwHz;

  /// Gapless, so anything at least one frame long is caught.
  bool catches(RaceEmission e) => e.duration >= frameSeconds;
}

/// The knobs of the scene.
class RaceSceneConfig {
  const RaceSceneConfig({
    this.seed = 1,
    this.runSeconds = 0.2,
    this.mainsHz = 60,
    this.microwaveSweepMhz = 20,
    this.videoBandwidthMhz = 8,
  });

  final int seed;
  final double runSeconds;

  /// 60 or 50.
  final double mainsHz;

  /// How far the oven's frequency climbs during each on-period.
  final double microwaveSweepMhz;

  /// Width of the analog video camera's signal.
  final double videoBandwidthMhz;

  RaceSceneConfig copyWith({
    int? seed,
    double? runSeconds,
    double? mainsHz,
    double? microwaveSweepMhz,
    double? videoBandwidthMhz,
  }) => RaceSceneConfig(
    seed: seed ?? this.seed,
    runSeconds: runSeconds ?? this.runSeconds,
    mainsHz: mainsHz ?? this.mainsHz,
    microwaveSweepMhz: microwaveSweepMhz ?? this.microwaveSweepMhz,
    videoBandwidthMhz: videoBandwidthMhz ?? this.videoBandwidthMhz,
  );
}

/// Synthetic scene constants. Levels are what the analyzer receives; they
/// are chosen to sit inside the -95 to -30 dBm legend, not measured.
abstract final class RaceScene {
  static const double bandLowMhz = 2400;
  static const double bandHighMhz = 2500;

  static const double microwaveCenterMhz = 2457; // channel 10
  static const double microwaveInstantMhz = 2;
  static const double microwaveDbm = -35;

  static const double btFirstMhz = 2402;
  static const int btChannels = 79;
  static const double btSlotSeconds = 625e-6;
  static const double btDbm = -60;

  static const List<double> bleAdvMhz = <double>[2402, 2426, 2480];
  static const double bleIntervalSeconds = 0.1;
  static const double blePacketSeconds = 376e-6;
  static const double bleGapSeconds = 0.5e-3;
  static const double bleDbm = -62;

  static const double videoCenterMhz = 2414;
  static const double videoDbm = -48;
  static const double videoSideDbm = -58;

  static const double wifiCenterMhz = 2437; // channel 6
  static const double wifiOccupiedMhz = 16.6; // 52 x 312.5 kHz
  static const double wifiDbm = -55;
  static const int wifiFrameBytes = 1500;
  static const int wifiRateMbps = 54;
  static const int wifiCwMin = 15;

  /// 244 us, from the Medium Access Simulator's airtime formula.
  static double get wifiFrameSeconds =>
      OfdmTiming.frameDurationUs(wifiFrameBytes, wifiRateMbps) * 1e-6;

  static double microwaveOnSeconds(double mainsHz) => 0.5 / mainsHz;

  /// Every emission in [c.runSeconds], seeded.
  static List<RaceEmission> generate(RaceSceneConfig c) {
    final math.Random rng = math.Random(c.seed);
    final double run = c.runSeconds;
    final List<RaceEmission> out = <RaceEmission>[];

    // Microwave oven: on for half of each mains cycle, climbing.
    final double period = 1 / c.mainsHz;
    final double on = microwaveOnSeconds(c.mainsHz);
    final double phase = rng.nextDouble() * period;
    for (double t = phase - period; t < run; t += period) {
      if (t + on <= 0) continue;
      out.add(
        RaceEmission(
          source: RaceSource.microwave,
          t0: t,
          t1: t + on,
          startMhz: microwaveCenterMhz - c.microwaveSweepMhz / 2,
          endMhz: microwaveCenterMhz + c.microwaveSweepMhz / 2,
          bandwidthMhz: microwaveInstantMhz,
          dbm: microwaveDbm,
        ),
      );
    }

    // Bluetooth Classic: one hop per slot, uniform over 79 channels.
    final int slots = (run / btSlotSeconds).ceil();
    for (int i = 0; i < slots; i++) {
      final double f = btFirstMhz + rng.nextInt(btChannels);
      out.add(
        RaceEmission(
          source: RaceSource.bluetooth,
          t0: i * btSlotSeconds,
          t1: (i + 1) * btSlotSeconds,
          startMhz: f,
          endMhz: f,
          bandwidthMhz: 1,
          dbm: btDbm,
        ),
      );
    }

    // BLE advertising: an event every ~100 ms plus a 0-10 ms random delay,
    // one packet on each of 37, 38, 39.
    double adv = rng.nextDouble() * bleIntervalSeconds;
    while (adv < run) {
      for (int j = 0; j < bleAdvMhz.length; j++) {
        final double t = adv + j * (blePacketSeconds + bleGapSeconds);
        out.add(
          RaceEmission(
            source: RaceSource.ble,
            t0: t,
            t1: t + blePacketSeconds,
            startMhz: bleAdvMhz[j],
            endMhz: bleAdvMhz[j],
            bandwidthMhz: 2,
            dbm: bleDbm,
          ),
        );
      }
      adv += bleIntervalSeconds + rng.nextDouble() * 0.01;
    }

    // Analog video camera: three adjacent continuous carriers, fixed.
    final double vb = c.videoBandwidthMhz;
    for (final (double off, double level) in <(double, double)>[
      (0, videoDbm),
      (-vb / 3, videoSideDbm),
      (vb / 3, videoSideDbm),
    ]) {
      out.add(
        RaceEmission(
          source: RaceSource.video,
          t0: 0,
          t1: run,
          startMhz: videoCenterMhz + off,
          endMhz: videoCenterMhz + off,
          bandwidthMhz: vb / 3,
          dbm: level,
        ),
      );
    }

    // Wi-Fi: back-to-back frames with DIFS plus backoff between them.
    final double frame = wifiFrameSeconds;
    double t = rng.nextDouble() * 1e-3;
    while (t < run) {
      out.add(
        RaceEmission(
          source: RaceSource.wifi,
          t0: t,
          t1: t + frame,
          startMhz: wifiCenterMhz,
          endMhz: wifiCenterMhz,
          bandwidthMhz: wifiOccupiedMhz,
          dbm: wifiDbm,
        ),
      );
      final int slotsBackoff = rng.nextInt(wifiCwMin + 1);
      t +=
          frame + (OfdmTiming.difsUs + slotsBackoff * OfdmTiming.slotUs) * 1e-6;
    }
    return out;
  }
}

/// Caught and missed for one source.
class RaceTally {
  const RaceTally({
    required this.total,
    required this.sweptCaught,
    required this.fftCaught,
  });
  final int total;
  final int sweptCaught;
  final int fftCaught;
  int get sweptMissed => total - sweptCaught;
  int get fftMissed => total - fftCaught;
}

/// Everything the screen draws for one run: the emissions in view, which
/// analyzer caught each, and both waterfalls.
class RaceRun {
  RaceRun._({
    required this.config,
    required this.swept,
    required this.fft,
    required this.emissions,
    required this.sweptCaught,
    required this.fftCaught,
    required this.rows,
    required this.cols,
    required this.fftGrid,
    required this.sweptGrid,
  });

  /// Floor of the dBm legend: an empty cell that was looked at.
  static const double noiseFloorDbm = -95;

  /// Top of the dBm legend.
  static const double topDbm = -30;

  final RaceSceneConfig config;
  final SweptAnalyzer swept;
  final FftAnalyzer fft;

  /// The emissions inside the span, in time order.
  final List<RaceEmission> emissions;
  final List<bool> sweptCaught;
  final List<bool> fftCaught;

  /// Waterfall size. Row 0 is the start of the run (drawn at the bottom;
  /// newest at the top).
  final int rows;
  final int cols;

  /// dBm per cell, row-major. FFT: every cell measured.
  final Float32List fftGrid;

  /// dBm per cell; NaN where the swept analyzer never looked in that row.
  final Float32List sweptGrid;

  double get runSeconds => config.runSeconds;
  double get rowSeconds => runSeconds / rows;
  double get colMhz => swept.spanMhz / cols;

  /// How many sweeps fit in the run (can be below 1).
  double get sweepsInRun => runSeconds / swept.sweepSeconds;

  /// Share of the span the swept analyzer looked at, at least once, by the
  /// end of the run (0 to 1).
  double get spanCoveredFraction => math.min(1, sweepsInRun);

  /// Caught and missed for [source], counting only emissions that start
  /// before [untilSeconds].
  RaceTally tally(RaceSource source, {double? untilSeconds}) {
    final double until = untilSeconds ?? double.infinity;
    int total = 0;
    int s = 0;
    int f = 0;
    for (int i = 0; i < emissions.length; i++) {
      final RaceEmission e = emissions[i];
      if (e.source != source || e.t0 >= until) continue;
      total++;
      if (sweptCaught[i]) s++;
      if (fftCaught[i]) f++;
    }
    return RaceTally(total: total, sweptCaught: s, fftCaught: f);
  }

  static RaceRun compute({
    required RaceSceneConfig config,
    required double spanMhz,
    required double rbwHz,
    double centerMhz = 2450,
    int rows = 96,
    int cols = 200,
  }) {
    final double start = centerMhz - spanMhz / 2;
    final double end = centerMhz + spanMhz / 2;
    final SweptAnalyzer swept = SweptAnalyzer(
      startMhz: start,
      spanMhz: spanMhz,
      rbwHz: rbwHz,
    );
    final FftAnalyzer fft = FftAnalyzer(rbwHz: rbwHz);
    final List<RaceEmission> all =
        RaceScene.generate(config)
            .where((RaceEmission e) => e.t0 < config.runSeconds)
            .where((RaceEmission e) => e.inSpan(start, end))
            .toList()
          ..sort((RaceEmission a, RaceEmission b) => a.t0.compareTo(b.t0));

    final List<bool> sc = <bool>[
      for (final RaceEmission e in all) swept.catches(e),
    ];
    final List<bool> fc = <bool>[
      for (final RaceEmission e in all) fft.catches(e),
    ];

    final double run = config.runSeconds;
    final double dt = run / rows;
    final double colW = spanMhz / cols;
    final double rbwHalf = rbwHz / 2e6;

    final Float32List fg = Float32List(rows * cols)
      ..fillRange(0, rows * cols, noiseFloorDbm);
    final Float32List sg = Float32List(rows * cols)
      ..fillRange(0, rows * cols, double.nan);

    int colOf(double mhz) => ((mhz - start) / colW).floor();

    // Pieces short enough that a chirp's range within one is small.
    Iterable<RaceEmission> pieces(RaceEmission e) sync* {
      if (e.startMhz == e.endMhz) {
        yield e;
        return;
      }
      final int parts = math.max(1, (e.duration / 0.25e-3).ceil());
      final double step = e.duration / parts;
      for (int p = 0; p < parts; p++) {
        final double a = e.t0 + p * step;
        final double b = a + step;
        yield RaceEmission(
          source: e.source,
          t0: a,
          t1: b,
          startMhz: e.centerAt(a),
          endMhz: e.centerAt(b),
          bandwidthMhz: e.bandwidthMhz,
          dbm: e.dbm,
        );
      }
    }

    void maxInto(Float32List g, int r, int c, double v) {
      final int i = r * cols + c;
      final double cur = g[i];
      if (cur.isNaN || v > cur) g[i] = v;
    }

    // Where the swept analyzer looked: in each column, one visit per sweep,
    // lasting colW / span x ST. The first visit starts at off(c).
    final double st = swept.sweepSeconds;
    double visitStart(int c) => (c * colW) / spanMhz * st;
    final double visitLen = colW / spanMhz * st;

    // Mark every looked-at cell with the noise floor first.
    for (int c = 0; c < cols; c++) {
      final double off = visitStart(c);
      if (st <= dt) {
        final int r0 = math.max(0, (off / dt).floor());
        for (int r = r0; r < rows; r++) {
          maxInto(sg, r, c, noiseFloorDbm);
        }
      } else {
        for (int m = 0; m * st + off < run; m++) {
          final int r = ((m * st + off) / dt).floor();
          if (r < rows) maxInto(sg, r, c, noiseFloorDbm);
        }
      }
    }

    for (final RaceEmission e in all) {
      for (final RaceEmission p in pieces(e)) {
        final double t0 = math.max(0, p.t0);
        final double t1 = math.min(run, p.t1);
        if (t1 <= t0) continue;
        final (double lo, double hi) = p.rangeDuring(p.t0, p.t1);
        // Both analyzers blur a signal by their RBW.
        final int c0 = math.max(0, colOf(lo - rbwHalf));
        final int c1 = math.min(cols - 1, colOf(hi + rbwHalf));
        if (c1 < c0) continue;
        final int r0 = (t0 / dt).floor();
        final int r1 = math.min(rows - 1, ((t1 - 1e-12) / dt).floor());

        // FFT: every cell the emission touches.
        for (int r = r0; r <= r1; r++) {
          for (int c = c0; c <= c1; c++) {
            maxInto(fg, r, c, p.dbm);
          }
        }

        // Swept: only the visits that overlap the emission in time. Each is
        // logged at the moment the overlap happens (a visit can start just
        // before the emission does), so it lands in the same row as on the
        // FFT waterfall.
        int rowAt(double t) =>
            (math.max(t0, math.min(t, t1 - 1e-12)) / dt).floor();
        for (int c = c0; c <= c1; c++) {
          final double off = visitStart(c);
          final int m0 = math.max(0, ((t0 - off - visitLen) / st).ceil());
          final int m1 = ((t1 - off) / st).floor();
          if (m1 < m0) continue;
          if (st <= dt) {
            final int ra = math.max(0, rowAt(m0 * st + off));
            final int rb = math.min(rows - 1, rowAt(m1 * st + off));
            for (int r = ra; r <= rb; r++) {
              maxInto(sg, r, c, p.dbm);
            }
          } else {
            for (int m = m0; m <= m1; m++) {
              final int r = rowAt(m * st + off);
              if (r >= 0 && r < rows) maxInto(sg, r, c, p.dbm);
            }
          }
        }
      }
    }

    return RaceRun._(
      config: config,
      swept: swept,
      fft: fft,
      emissions: List<RaceEmission>.unmodifiable(all),
      sweptCaught: List<bool>.unmodifiable(sc),
      fftCaught: List<bool>.unmodifiable(fc),
      rows: rows,
      cols: cols,
      fftGrid: fg,
      sweptGrid: sg,
    );
  }
}
