// Unit tests for the Why a Busy Line Lags model (research brief candidate
// 1): the teaching claims. Idle follows the FCC's quoted ranges; the upload
// raises the call's delay to hundreds of milliseconds on cable and DSL with
// SQM off; SQM on keeps it within the 5 ms FQ-CoDel target of idle; DSL
// jumps most; the queue drains in its own delay once the upload stops; the
// trace samples at the FCC's 10 packets a second; and nothing is random.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/latency_under_load_model.dart';

void main() {
  group('the measured side (FCC 13th MBA report)', () {
    test(
      'idle ranges are the ones quoted on p. 18, and idle is the middle',
      () {
        expect((LulLine.fiber.idleLowMs, LulLine.fiber.idleHighMs), (7, 14));
        expect((LulLine.cable.idleLowMs, LulLine.cable.idleHighMs), (12, 24));
        expect((LulLine.dsl.idleLowMs, LulLine.dsl.idleHighMs), (23, 34));
        for (final LulLine l in LulLine.values) {
          expect(l.idleMs, (l.idleLowMs + l.idleHighMs) / 2);
          expect(lulLatencyMs(l, sqm: false, tS: 0), l.idleMs);
        }
      },
    );

    test('each busy figure sits inside its own chart range, and inside the '
        'chart axis', () {
      for (final LulLine l in LulLine.values) {
        expect(l.busyMs, inInclusiveRange(l.busyLowMs, l.busyHighMs));
        expect(l.busyHighMs, lessThanOrEqualTo(l.axisMaxMs));
      }
    });

    test('with SQM off the upload takes cable and DSL to hundreds of ms', () {
      expect(lulLatencyMs(LulLine.cable, sqm: false, tS: 15), greaterThan(200));
      expect(lulLatencyMs(LulLine.dsl, sqm: false, tS: 15), greaterThan(600));
    });

    test('the jump from idle is most pronounced on DSL', () {
      double ratio(LulLine l) => LulSummary(LulConfig(line: l)).timesIdle;
      expect(ratio(LulLine.dsl), greaterThan(ratio(LulLine.cable)));
      expect(ratio(LulLine.cable), greaterThan(ratio(LulLine.fiber)));
    });

    test('samples every 100 ms, the FCC\'s 10 packets a second', () {
      final List<LulSample> t = lulTrace(LulLine.cable, sqm: false);
      expect(t, hasLength(201));
      expect(t[1].tS - t[0].tS, closeTo(0.1, 1e-12));
      expect(t.last.tS, closeTo(kLulRunS, 1e-9));
    });
  });

  group('the illustrative side', () {
    test('SQM on keeps the call within FQ-CoDel\'s 5 ms target of idle', () {
      expect(kLulSqmTargetMs, 5);
      for (final LulLine l in LulLine.values) {
        for (final LulSample s in lulTrace(l, sqm: true)) {
          expect(s.ms, lessThanOrEqualTo(l.idleMs + 5 + 1e-9));
          expect(s.ms, greaterThanOrEqualTo(l.idleMs));
        }
      }
    });

    test(
      'the same upload: SQM on is far below SQM off (the visible change)',
      () {
        final double off = lulLatencyMs(LulLine.cable, sqm: false, tS: 12);
        final double on = lulLatencyMs(LulLine.cable, sqm: true, tS: 12);
        expect(off / on, greaterThan(8));
      },
    );
  });

  group('the queue over the run', () {
    test('no queue before the upload starts', () {
      expect(
        lulQueueMs(LulLine.dsl, sqm: false, tS: kLulUploadStartS - 0.01),
        0,
      );
      expect(lulUploading(kLulUploadStartS - 0.01), isFalse);
      expect(lulUploading(kLulUploadStartS), isTrue);
      expect(lulUploading(kLulUploadEndS), isFalse);
    });

    test('the queue only grows while the upload runs', () {
      double prev = -1;
      for (double t = kLulUploadStartS; t < kLulUploadEndS; t += 0.1) {
        final double q = lulQueueMs(LulLine.cable, sqm: false, tS: t);
        expect(q, greaterThanOrEqualTo(prev));
        prev = q;
      }
      // Full by the end of a 12 s upload.
      expect(
        lulQueueMs(LulLine.cable, sqm: false, tS: kLulUploadEndS - 0.001),
        closeTo(LulLine.cable.busyMs - LulLine.cable.idleMs, 0.01),
      );
    });

    test('once the upload stops, a queue of D ms empties in D ms', () {
      final double d = lulQueueMs(LulLine.dsl, sqm: false, tS: kLulUploadEndS);
      expect(d, greaterThan(600));
      final double halfway = kLulUploadEndS + d / 2000;
      expect(
        lulQueueMs(LulLine.dsl, sqm: false, tS: halfway),
        closeTo(d / 2, 1e-6),
      );
      expect(
        lulQueueMs(LulLine.dsl, sqm: false, tS: kLulUploadEndS + d / 1000),
        closeTo(0, 1e-6),
      );
      expect(
        lulLatencyMs(LulLine.dsl, sqm: false, tS: kLulRunS),
        LulLine.dsl.idleMs,
      );
    });
  });

  group('summary and formatting', () {
    test('cable defaults: 18 ms idle, 225 ms busy (12.5 times), 23 ms with '
        'SQM', () {
      final LulSummary off = LulSummary(const LulConfig());
      expect(off.idleMs, 18);
      expect(off.busyMs, 225);
      expect(lulTimes(off.timesIdle), '12.5 times idle');
      final LulSummary on = LulSummary(const LulConfig(sqm: true));
      expect(on.busyMs, 23);
      expect(lulTimes(on.timesIdle), '1.3 times idle');
    });

    test('DSL from 29 ms to 665 ms, 23.3 times idle (the help example)', () {
      final LulSummary s = LulSummary(const LulConfig(line: LulLine.dsl));
      expect(lulMs(s.idleMs), '29 ms');
      expect(lulMs(s.busyMs), '665 ms');
      expect(lulTimes(s.timesIdle), '23.3 times idle');
    });

    test('deterministic: the same setting gives the same trace', () {
      final List<LulSample> a = lulTrace(LulLine.fiber, sqm: false);
      final List<LulSample> b = lulTrace(LulLine.fiber, sqm: false);
      expect(a, b);
    });
  });
}
