// Why a Busy Line Lags: the pure model for the Wi-Fi Classroom tool
// (latency-under-load).
//
// CLEAN-ROOM BUILD (2026-09-27) from myPKA
// Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md section 3,
// candidate 1, and section 5 (anti-pattern 2: no invented AQM-fixed figure).
//
// THE LESSON. A video call's packets share the home line's upload queue with
// everything else. When someone else's upload runs, it fills that queue, and
// every call packet waits behind it: the call's delay climbs from the idle
// figure to hundreds of milliseconds. A faster plan drains the queue faster,
// but the upload still fills it. Smart queue management (SQM) in the router
// keeps the queue short and sends each conversation in turn, so the call's
// delay stays near idle.
//
// THE MEASURED SIDE (FCC, Measuring Broadband America, 13th report, FCC
// 24-136, 2022 test period, published 2024):
//   - idle latency, quoted from p. 18: fiber 7 to 14 ms, cable 12 to 24 ms,
//     DSL 23 to 34 ms. The idle figure here is the middle of each range.
//   - latency under UPSTREAM load, read by eye from the bars of Chart 7
//     (p. 19): fiber ISPs about 25 to 40 ms, cable about 85 to 250 ms, DSL
//     about 180 to 720 ms. Each "busy" figure is the median ISP bar of its
//     group (fiber 30, cable 225, DSL 665), rounded. These are chart
//     readings, approximate, and the screen says so.
//   - The FCC samples latency under load at 10 packets a second, so the
//     trace is drawn from one sample every 100 ms.
//
// THE ILLUSTRATIVE SIDE (no published consumer measurement exists; the
// screen labels it):
//   - with SQM on, the call's delay under the upload is idle + 5 ms. The 5 ms
//     is FQ-CoDel's default target queue delay (RFC 8290 section 4.2, "The
//     default target value is 5 ms"), used as a stand-in, not a measurement.
//   - the shape of the climb (the queue fills with a 0.8 s time constant)
//     and the scenario's timing (a 20 s run, the upload from 4 s to 16 s).
//   - the drain: a queue holding D ms of data empties in D ms at line rate
//     once the upload stops. That part is arithmetic, not a choice.
//
// Pure Dart, no Flutter imports, deterministic: no randomness, no jitter.
// Pinned by test/services/wifi_lab/latency_under_load_model_test.dart.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kLatencyUnderLoadToolId = 'latency-under-load';

/// Length of one run, seconds.
const double kLulRunS = 20;

/// When someone else's upload starts and stops, seconds into the run
/// (illustrative scenario timing).
const double kLulUploadStartS = 4;
const double kLulUploadEndS = 16;

/// Time constant of the queue filling after the upload starts, seconds
/// (illustrative).
const double kLulFillTauS = 0.8;

/// FQ-CoDel's default target queue delay, ms (RFC 8290 section 4.2). Used as
/// the illustrative queue delay with smart queue management on.
const double kLulSqmTargetMs = 5;

/// One latency sample every 100 ms: the FCC's 10 packets a second under
/// load.
const double kLulSampleS = 0.1;

/// The home line's technology, with the FCC's measured figures.
enum LulLine {
  fiber(
    label: 'Fiber',
    idleLowMs: 7,
    idleHighMs: 14,
    busyLowMs: 25,
    busyHighMs: 40,
    busyMs: 30,
    axisMaxMs: 100,
  ),
  cable(
    label: 'Cable',
    idleLowMs: 12,
    idleHighMs: 24,
    busyLowMs: 85,
    busyHighMs: 250,
    busyMs: 225,
    axisMaxMs: 300,
  ),
  dsl(
    label: 'DSL',
    idleLowMs: 23,
    idleHighMs: 34,
    busyLowMs: 180,
    busyHighMs: 720,
    busyMs: 665,
    axisMaxMs: 800,
  );

  const LulLine({
    required this.label,
    required this.idleLowMs,
    required this.idleHighMs,
    required this.busyLowMs,
    required this.busyHighMs,
    required this.busyMs,
    required this.axisMaxMs,
  });

  /// Short name on the toggle. DSL is spelled out where it is explained.
  final String label;

  /// FCC idle latency range, ms (quoted, p. 18).
  final double idleLowMs;
  final double idleHighMs;

  /// FCC latency under upstream load across the ISPs of this technology, ms
  /// (read from Chart 7, approximate).
  final double busyLowMs;
  final double busyHighMs;

  /// The median ISP's latency under upstream load, ms (read from Chart 7,
  /// approximate, rounded). The trace plateaus here with SQM off.
  final double busyMs;

  /// Top of the chart's millisecond axis. Fixed per line, so switching SQM
  /// never rescales the chart and the drop stays visible.
  final double axisMaxMs;

  /// The name inside a sentence: "fiber", "cable", but "DSL".
  String get inSentence => this == LulLine.dsl ? label : label.toLowerCase();

  /// The idle figure the trace uses: the middle of the FCC's range.
  double get idleMs => (idleLowMs + idleHighMs) / 2;
}

/// One setting of the tool.
class LulConfig {
  const LulConfig({this.line = LulLine.cable, this.sqm = false});

  final LulLine line;

  /// Smart queue management on the home router.
  final bool sqm;

  LulConfig copyWith({LulLine? line, bool? sqm}) =>
      LulConfig(line: line ?? this.line, sqm: sqm ?? this.sqm);

  @override
  bool operator ==(Object other) =>
      other is LulConfig && other.line == line && other.sqm == sqm;

  @override
  int get hashCode => Object.hash(line, sqm);
}

/// True while someone else's upload runs at [tS] seconds.
bool lulUploading(double tS) => tS >= kLulUploadStartS && tS < kLulUploadEndS;

/// The standing queue the upload builds, ms: what a call packet waits behind
/// once the queue is full.
double lulFullQueueMs(LulLine line, {required bool sqm}) =>
    sqm ? kLulSqmTargetMs : line.busyMs - line.idleMs;

/// Time the call's packets spend waiting in the upload queue at [tS]
/// seconds into the run, ms.
double lulQueueMs(LulLine line, {required bool sqm, required double tS}) {
  final double full = lulFullQueueMs(line, sqm: sqm);
  double filled(double t) =>
      full * (1 - math.exp(-(t - kLulUploadStartS) / kLulFillTauS));
  if (tS < kLulUploadStartS) return 0;
  if (tS < kLulUploadEndS) return filled(tS);
  // The upload has stopped: the queue drains at line rate, and a queue
  // holding D ms of data takes D ms to empty.
  final double atEnd = filled(kLulUploadEndS);
  final double drainedMs = (tS - kLulUploadEndS) * 1000;
  return math.max(0, atEnd - drainedMs);
}

/// The video call's round-trip delay at [tS] seconds into the run, ms.
double lulLatencyMs(LulLine line, {required bool sqm, required double tS}) =>
    line.idleMs + lulQueueMs(line, sqm: sqm, tS: tS);

/// One point of the trace.
typedef LulSample = ({double tS, double ms});

/// The trace: one sample every [kLulSampleS] from 0 to [kLulRunS]
/// inclusive.
List<LulSample> lulTrace(LulLine line, {required bool sqm}) {
  final int n = (kLulRunS / kLulSampleS).round();
  return <LulSample>[
    for (int i = 0; i <= n; i++)
      (
        tS: i * kLulSampleS,
        ms: lulLatencyMs(line, sqm: sqm, tS: i * kLulSampleS),
      ),
  ];
}

/// The headline figures for one setting.
class LulSummary {
  LulSummary(this.config)
    : idleMs = config.line.idleMs,
      busyOffMs = config.line.busyMs,
      busyOnMs = config.line.idleMs + kLulSqmTargetMs;

  final LulConfig config;

  /// The call's delay on an idle line, ms (FCC, middle of the range).
  final double idleMs;

  /// Under the upload with SQM off, ms (FCC chart reading).
  final double busyOffMs;

  /// Under the upload with SQM on, ms (illustrative).
  final double busyOnMs;

  /// Under the upload in the current setting, ms.
  double get busyMs => config.sqm ? busyOnMs : busyOffMs;

  /// How many times the idle figure the busy figure is.
  double get timesIdle => busyMs / idleMs;
}

/// "18 ms" or "0.5 ms" style formatting: whole milliseconds from 10 up.
String lulMs(double ms) =>
    ms >= 10 ? '${ms.round()} ms' : '${ms.toStringAsFixed(1)} ms';

/// "12.5 times idle" / "1.3 times idle".
String lulTimes(double x) => '${x.toStringAsFixed(1)} times idle';
