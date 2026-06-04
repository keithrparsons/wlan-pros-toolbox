// PingPlotController unit tests — exercise the bounded rolling window, the
// stats/jitter math over that window, honest dropped-packet handling, and the
// start/stop/dispose lifecycle (no leaked subscription/timer), all with an
// injected synthetic PingProgress stream so NO real socket ever opens.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ping_plot_controller.dart';
import 'package:wlan_pros_toolbox/services/network/ping_service.dart';

/// Build a PingProgress for one probe. A null [rttMs] models a lost probe.
PingProgress _progress(int seq, double? rttMs, {String? error}) {
  final bool success = rttMs != null;
  final PingReply reply = PingReply(
    sequence: seq,
    success: success,
    rtt: success ? Duration(microseconds: (rttMs * 1000).round()) : null,
    errorLabel: success ? null : (error ?? 'timeout'),
  );
  // PingPlotController only reads `reply` off PingProgress; stats here are a
  // throwaway empty fold (the controller maintains its own window).
  return PingProgress(reply: reply, stats: PingStats.empty);
}

/// A controller wired to a caller-driven stream so tests push samples by hand
/// and assert the resulting state. Returns the controller and the sink.
({PingPlotController controller, StreamController<PingProgress> sink})
    _wire({int windowSize = 60}) {
  final StreamController<PingProgress> sink =
      StreamController<PingProgress>();
  final PingPlotController controller = PingPlotController(
    windowSize: windowSize,
    pingStreamFactory: ({
      required String host,
      required int port,
      required Duration interval,
      required Duration timeout,
      Future<void>? cancel,
    }) =>
        sink.stream,
  );
  return (controller: controller, sink: sink);
}

void main() {
  group('window + stats math', () {
    test('folds landed RTTs into min/avg/max over the window', () async {
      final w = _wire();
      addTearDown(w.controller.dispose);
      addTearDown(w.sink.close);
      w.controller.start(host: 'h');

      w.sink.add(_progress(1, 10));
      w.sink.add(_progress(2, 30));
      w.sink.add(_progress(3, 20));
      await Future<void>.delayed(Duration.zero);

      final PingPlotState s = w.controller.state;
      expect(s.windowSent, 3);
      expect(s.windowReceived, 3);
      expect(s.minMs, closeTo(10, 0.001));
      expect(s.maxMs, closeTo(30, 0.001));
      expect(s.avgMs, closeTo(20, 0.001));
      expect(s.lastMs, closeTo(20, 0.001));
      expect(s.totalSent, 3);
      expect(s.totalReceived, 3);
    });

    test('jitter is mean absolute consecutive RTT delta', () async {
      final w = _wire();
      addTearDown(w.controller.dispose);
      addTearDown(w.sink.close);
      w.controller.start(host: 'h');

      // RTTs 10, 30, 20 → deltas |20|, |-10| → mean 15.
      w.sink.add(_progress(1, 10));
      w.sink.add(_progress(2, 30));
      w.sink.add(_progress(3, 20));
      await Future<void>.delayed(Duration.zero);

      expect(w.controller.state.jitterMs, closeTo(15, 0.001));
    });

    test('a lost probe breaks the jitter chain (no pairing across a gap)',
        () async {
      final w = _wire();
      addTearDown(w.controller.dispose);
      addTearDown(w.sink.close);
      w.controller.start(host: 'h');

      // 10, LOST, 30 → no consecutive landed pair, so jitter is null.
      w.sink.add(_progress(1, 10));
      w.sink.add(_progress(2, null));
      w.sink.add(_progress(3, 30));
      await Future<void>.delayed(Duration.zero);

      final PingPlotState s = w.controller.state;
      expect(s.jitterMs, isNull, reason: 'gap must break the consecutive chain');
      expect(s.minMs, closeTo(10, 0.001));
      expect(s.maxMs, closeTo(30, 0.001));
      expect(s.avgMs, closeTo(20, 0.001));
    });
  });

  group('honest dropped-packet handling (GL-005)', () {
    test('a lost probe is a gap with null RTT, never a 0', () async {
      final w = _wire();
      addTearDown(w.controller.dispose);
      addTearDown(w.sink.close);
      w.controller.start(host: 'h');

      w.sink.add(_progress(1, 12));
      w.sink.add(_progress(2, null, error: 'unreachable'));
      await Future<void>.delayed(Duration.zero);

      final PingPlotState s = w.controller.state;
      expect(s.samples.length, 2);
      final PingSample lost = s.samples[1];
      expect(lost.lost, isTrue);
      expect(lost.rttMs, isNull, reason: 'never fabricate a 0 for a loss');
      expect(lost.errorLabel, 'unreachable');
      // Loss reflected in counts, not hidden.
      expect(s.windowReceived, 1);
      expect(s.totalLossFraction, closeTo(0.5, 0.001));
      // lastMs reflects the literal last sample (a loss) → null.
      expect(s.lastMs, isNull);
      // landedRttsMs excludes the loss (no 0 sneaks into the line).
      expect(s.landedRttsMs, <double>[12]);
    });

    test('all-lost run reports 100% loss and no RTT stats', () async {
      final w = _wire();
      addTearDown(w.controller.dispose);
      addTearDown(w.sink.close);
      w.controller.start(host: 'h');

      w.sink.add(_progress(1, null));
      w.sink.add(_progress(2, null));
      await Future<void>.delayed(Duration.zero);

      final PingPlotState s = w.controller.state;
      expect(s.totalLossFraction, closeTo(1.0, 0.001));
      expect(s.minMs, isNull);
      expect(s.avgMs, isNull);
      expect(s.maxMs, isNull);
      expect(s.landedRttsMs, isEmpty);
    });
  });

  group('bounded rolling window', () {
    test('retains only the last windowSize samples; totals keep counting',
        () async {
      final w = _wire(windowSize: 3);
      addTearDown(w.controller.dispose);
      addTearDown(w.sink.close);
      w.controller.start(host: 'h');

      for (int i = 1; i <= 5; i++) {
        w.sink.add(_progress(i, i.toDouble()));
      }
      await Future<void>.delayed(Duration.zero);

      final PingPlotState s = w.controller.state;
      // Window holds 3 (samples 3,4,5); the oldest two scrolled out.
      expect(s.samples.length, 3);
      expect(s.samples.first.sequence, 3);
      expect(s.samples.last.sequence, 5);
      expect(s.windowSent, 3);
      // Totals are run-lifetime, not window-bounded.
      expect(s.totalSent, 5);
      expect(s.totalReceived, 5);
      // Stats are over the window only.
      expect(s.minMs, closeTo(3, 0.001));
      expect(s.maxMs, closeTo(5, 0.001));
    });

    test('elapsed time is monotonic across samples (chart X axis)', () async {
      final w = _wire();
      addTearDown(w.controller.dispose);
      addTearDown(w.sink.close);
      w.controller.start(host: 'h');

      w.sink.add(_progress(1, 5));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      w.sink.add(_progress(2, 5));
      await Future<void>.delayed(Duration.zero);

      final List<PingSample> s = w.controller.state.samples;
      expect(s[1].elapsed >= s[0].elapsed, isTrue);
    });
  });

  group('lifecycle — no leaks', () {
    test('emits one state per sample', () async {
      final w = _wire();
      addTearDown(w.controller.dispose);
      addTearDown(w.sink.close);

      final List<PingPlotState> seen = <PingPlotState>[];
      w.controller.states.listen(seen.add);
      w.controller.start(host: 'h');

      w.sink.add(_progress(1, 10));
      w.sink.add(_progress(2, 20));
      await Future<void>.delayed(Duration.zero);

      expect(seen.length, 2);
      expect(seen.last.totalSent, 2);
    });

    test('stop() tears down: no further states after stop', () async {
      final w = _wire();
      addTearDown(w.controller.dispose);
      addTearDown(w.sink.close);

      final List<PingPlotState> seen = <PingPlotState>[];
      w.controller.states.listen(seen.add);
      w.controller.start(host: 'h');
      w.sink.add(_progress(1, 10));
      await Future<void>.delayed(Duration.zero);

      expect(w.controller.running, isTrue);
      w.controller.stop();
      expect(w.controller.running, isFalse);

      final int countAtStop = seen.length;
      // Anything the (now-cancelled) source emits must NOT reach the controller.
      w.sink.add(_progress(2, 20));
      await Future<void>.delayed(Duration.zero);
      expect(seen.length, countAtStop, reason: 'subscription cancelled on stop');
    });

    test('start() while running is a no-op (single run)', () async {
      final w = _wire();
      addTearDown(w.controller.dispose);
      addTearDown(w.sink.close);
      w.controller.start(host: 'h');
      w.sink.add(_progress(1, 10));
      await Future<void>.delayed(Duration.zero);

      // A second start must not reset the window mid-run.
      w.controller.start(host: 'other');
      expect(w.controller.state.totalSent, 1);
    });

    test('dispose() stops the run and closes the stream', () async {
      final w = _wire();
      addTearDown(w.sink.close);

      bool closed = false;
      w.controller.states.listen(null, onDone: () => closed = true);
      w.controller.start(host: 'h');
      w.sink.add(_progress(1, 10));
      await Future<void>.delayed(Duration.zero);

      w.controller.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(closed, isTrue, reason: 'states stream closed on dispose');
      expect(w.controller.running, isFalse);

      // Post-dispose: start is inert, source emissions are ignored.
      w.controller.start(host: 'h');
      w.sink.add(_progress(2, 20));
      await Future<void>.delayed(Duration.zero);
      expect(w.controller.running, isFalse);
    });

    test('dispose signals the engine cancel completer', () async {
      // Wire a factory that captures the cancel future so we can prove the
      // controller completes it on dispose (no leaked engine loop).
      bool cancelled = false;
      final StreamController<PingProgress> sink =
          StreamController<PingProgress>();
      addTearDown(sink.close);
      final PingPlotController controller = PingPlotController(
        pingStreamFactory: ({
          required String host,
          required int port,
          required Duration interval,
          required Duration timeout,
          Future<void>? cancel,
        }) {
          cancel?.then((_) => cancelled = true);
          return sink.stream;
        },
      );
      controller.start(host: 'h');
      controller.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue, reason: 'engine cancel completed on dispose');
    });
  });
}
