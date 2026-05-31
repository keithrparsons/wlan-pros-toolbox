// LiveQualityMonitor — unit tests.
//
// No network and no real timer: the latency sampler is a fake that returns a
// scripted LatencyStats (or throws), and ticks are driven deterministically via
// tickNow(). No test waits the 30 s interval (spec §2: "no test may hit the
// real network or wall-clock wait 30 s").

import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/live_quality_monitor.dart';

/// Builds a LatencyStats with the given avg/jitter/loss; sent/received are set
/// so `received > 0` unless loss is 100.
LatencyStats _stats({
  double avg = 18,
  double jitter = 2,
  double loss = 0,
}) =>
    LatencyStats(
      avgMs: avg,
      minMs: avg,
      maxMs: avg,
      jitterMs: jitter,
      lossPct: loss,
      sent: 5,
      received: loss >= 100 ? 0 : 5,
    );

void main() {
  group('start + first tick', () {
    test('fires one sample immediately on start', () async {
      var calls = 0;
      final monitor = LiveQualityMonitor(
        sampler: () async {
          calls++;
          return _stats(avg: 18);
        },
      );
      addTearDown(monitor.dispose);

      monitor.start();
      // start() fires the first tick without awaiting; let the microtask drain.
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1, reason: 'one immediate sample on start');
      expect(monitor.historyFor(MetricIds.latency), hasLength(1));
      expect(monitor.historyFor(MetricIds.jitter), hasLength(1));
      expect(monitor.historyFor(MetricIds.loss), hasLength(1));
      expect(monitor.historyFor(MetricIds.latency).single.value, 18);
    });

    test('start is idempotent (no double first sample)', () async {
      var calls = 0;
      final monitor = LiveQualityMonitor(sampler: () async {
        calls++;
        return _stats();
      });
      addTearDown(monitor.dispose);

      monitor.start();
      monitor.start();
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
    });
  });

  group('grades at band boundaries', () {
    test('latency grades match the engine at boundaries', () async {
      // 20 → good (excellent is < 20), 19.9 → excellent, 50 → fair, 100 → poor.
      for (final (double v, QualityGrade g) in <(double, QualityGrade)>[
        (19.9, QualityGrade.excellent),
        (20, QualityGrade.good),
        (49.9, QualityGrade.good),
        (50, QualityGrade.fair),
        (99.9, QualityGrade.fair),
        (100, QualityGrade.poor),
      ]) {
        final monitor =
            LiveQualityMonitor(sampler: () async => _stats(avg: v, loss: 0));
        await monitor.tickNow();
        expect(
          monitor.historyFor(MetricIds.latency).single.grade,
          g,
          reason: 'latency $v should grade $g',
        );
        monitor.dispose();
      }
    });

    test('loss grades match the engine at boundaries', () async {
      for (final (double v, QualityGrade g) in <(double, QualityGrade)>[
        (0, QualityGrade.excellent),
        (0.5, QualityGrade.good),
        (1, QualityGrade.fair),
        (2.4, QualityGrade.fair),
        (2.5, QualityGrade.poor),
      ]) {
        // loss < 100 keeps received > 0 so latency/jitter are also recorded.
        final monitor =
            LiveQualityMonitor(sampler: () async => _stats(loss: v));
        await monitor.tickNow();
        expect(
          monitor.historyFor(MetricIds.loss).single.grade,
          g,
          reason: 'loss $v should grade $g',
        );
        monitor.dispose();
      }
    });
  });

  group('ring-buffer cap', () {
    test('history never exceeds historyCap', () async {
      final monitor = LiveQualityMonitor(sampler: () async => _stats(avg: 30));
      addTearDown(monitor.dispose);

      for (var i = 0; i < LiveQualityMonitor.historyCap + 25; i++) {
        await monitor.tickNow();
      }

      expect(
        monitor.historyFor(MetricIds.latency),
        hasLength(LiveQualityMonitor.historyCap),
      );
    });

    test('cap trims from the front (oldest dropped first)', () async {
      var n = 0;
      final monitor = LiveQualityMonitor(sampler: () async {
        n++;
        return _stats(avg: n.toDouble());
      });
      addTearDown(monitor.dispose);

      for (var i = 0; i < LiveQualityMonitor.historyCap + 5; i++) {
        await monitor.tickNow();
      }

      final history = monitor.historyFor(MetricIds.latency);
      // After cap+5 ticks, the oldest retained value is 6 (1..5 were dropped).
      expect(history.first.value, 6);
      expect(history.last.value, (LiveQualityMonitor.historyCap + 5).toDouble());
    });
  });

  group('failed tick resilience', () {
    test('a throwing sampler records a 100% loss tick and keeps looping',
        () async {
      var calls = 0;
      final monitor = LiveQualityMonitor(sampler: () async {
        calls++;
        if (calls == 2) throw const SocketException('down');
        return _stats(avg: 18, loss: 0);
      });
      addTearDown(monitor.dispose);

      await monitor.tickNow(); // ok
      await monitor.tickNow(); // throws → 100% loss
      await monitor.tickNow(); // loop survived → ok again

      // Loss recorded on all three ticks; the failed tick is loss=100, poor.
      final loss = monitor.historyFor(MetricIds.loss);
      expect(loss, hasLength(3));
      expect(loss[1].value, 100);
      expect(loss[1].grade, QualityGrade.poor);

      // Latency/jitter only recorded on the two successful ticks (a fully-lost
      // tick has no RTT to plot).
      expect(monitor.historyFor(MetricIds.latency), hasLength(2));
      expect(monitor.historyFor(MetricIds.jitter), hasLength(2));
      expect(calls, 3, reason: 'loop did not stop after the throw');
    });

    test('a 100%-loss stats result (no exception) is also a loss-only tick',
        () async {
      final monitor =
          LiveQualityMonitor(sampler: () async => _stats(loss: 100));
      addTearDown(monitor.dispose);

      await monitor.tickNow();

      expect(monitor.historyFor(MetricIds.loss).single.value, 100);
      expect(monitor.historyFor(MetricIds.latency), isEmpty);
      expect(monitor.historyFor(MetricIds.jitter), isEmpty);
    });
  });

  group('addFullResult', () {
    test('appends a point to all six metric histories', () {
      final monitor = LiveQualityMonitor(sampler: () async => _stats());
      addTearDown(monitor.dispose);

      monitor.addFullResult(MockQualityClient().scriptedResult);

      for (final id in LiveQualityMonitor.metricIds) {
        expect(
          monitor.historyFor(id),
          hasLength(1),
          reason: '$id should get one point from a full result',
        );
      }
      // The expensive trio only ever gets points this way.
      expect(monitor.historyFor(MetricIds.download).single.value, 512.4);
      expect(monitor.historyFor(MetricIds.responsiveness).single.value, 820);
    });

    test('skips unavailable (null-value) metrics', () {
      final result = QualityResult(
        source: QualitySource.mock,
        measuredAt: DateTime.utc(2026, 1, 1),
        metrics: const <QualityMetric>[
          QualityMetric(
            id: MetricIds.latency,
            label: 'Latency',
            value: 14,
            unit: 'ms',
            grade: QualityGrade.excellent,
          ),
          QualityMetric.unavailable(
            id: MetricIds.download,
            label: 'Download',
            unit: 'Mbps',
            note: 'no route',
          ),
        ],
      );
      final monitor = LiveQualityMonitor(sampler: () async => _stats());
      addTearDown(monitor.dispose);

      monitor.addFullResult(result);

      expect(monitor.historyFor(MetricIds.latency), hasLength(1));
      expect(monitor.historyFor(MetricIds.download), isEmpty);
    });
  });

  group('pause / resume / dispose', () {
    test('pause stops sampling; resume restarts and fires immediately',
        () async {
      var calls = 0;
      final monitor = LiveQualityMonitor(sampler: () async {
        calls++;
        return _stats();
      });
      addTearDown(monitor.dispose);

      monitor.start();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(monitor.isRunning, isTrue);

      monitor.pause();
      expect(monitor.isRunning, isFalse);

      monitor.resume();
      await Future<void>.delayed(Duration.zero);
      expect(monitor.isRunning, isTrue);
      expect(calls, 2, reason: 'resume fires one immediate sample');
    });

    test('dispose cancels the timer and is inert afterward', () async {
      var calls = 0;
      final monitor = LiveQualityMonitor(
        sampler: () async {
          calls++;
          return _stats();
        },
        interval: const Duration(milliseconds: 10),
      );

      monitor.start();
      await Future<void>.delayed(Duration.zero);
      final int afterStart = calls;

      monitor.dispose();
      // Wait well past several intervals; a cancelled timer must not fire.
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(calls, afterStart, reason: 'no ticks after dispose');
      // start/resume are no-ops after dispose (and must not throw).
      monitor.start();
      monitor.resume();
      await Future<void>.delayed(Duration.zero);
      expect(calls, afterStart);
    });
  });
}

/// Local SocketException stand-in so the test does not import dart:io just for
/// a throw type. Any Object thrown is treated as a failed tick by the monitor.
class SocketException implements Exception {
  const SocketException(this.message);
  final String message;
  @override
  String toString() => 'SocketException: $message';
}
