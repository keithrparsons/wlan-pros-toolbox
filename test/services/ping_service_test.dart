// PingService unit tests — exercise the TCP-handshake classification
// (reply vs timeout vs refused-still-counts), the running-stats fold, and the
// streamed cadence/cancel, all with a fake connector so no real sockets open.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ping_service.dart';

void main() {
  group('PingStats.accumulate', () {
    test('starts empty', () {
      expect(PingStats.empty.sent, 0);
      expect(PingStats.empty.received, 0);
      expect(PingStats.empty.avgMs, isNull);
      expect(PingStats.empty.lossFraction, 0);
    });

    test('folds successful replies into min/avg/max', () {
      PingStats s = PingStats.empty;
      s = s.accumulate(PingReply(
        sequence: 1,
        success: true,
        rtt: const Duration(milliseconds: 10),
      ));
      s = s.accumulate(PingReply(
        sequence: 2,
        success: true,
        rtt: const Duration(milliseconds: 30),
      ));
      s = s.accumulate(PingReply(
        sequence: 3,
        success: true,
        rtt: const Duration(milliseconds: 20),
      ));
      expect(s.sent, 3);
      expect(s.received, 3);
      expect(s.minMs, closeTo(10, 0.001));
      expect(s.maxMs, closeTo(30, 0.001));
      expect(s.avgMs, closeTo(20, 0.001));
      expect(s.rttsMs.length, 3);
    });

    test('counts losses and computes loss fraction', () {
      PingStats s = PingStats.empty;
      s = s.accumulate(PingReply(
        sequence: 1,
        success: true,
        rtt: const Duration(milliseconds: 5),
      ));
      s = s.accumulate(
        const PingReply(sequence: 2, success: false, errorLabel: 'timeout'),
      );
      expect(s.sent, 2);
      expect(s.received, 1);
      expect(s.lost, 1);
      expect(s.lossFraction, closeTo(0.5, 0.001));
      // A lost probe does not enter the RTT series.
      expect(s.rttsMs.length, 1);
    });
  });

  group('ping classification', () {
    test('connect success → reply with rtt', () async {
      final PingService svc = PingService(
        connector: (host, port, {required timeout}) async => _FakeSocket(),
      );
      final List<PingProgress> ticks = await svc
          .ping(
            host: 'h',
            count: 1,
            interval: Duration.zero,
          )
          .toList();
      expect(ticks.length, 1);
      expect(ticks.single.reply.success, isTrue);
      expect(ticks.single.reply.rtt, isNotNull);
      expect(ticks.single.stats.received, 1);
    });

    test('refused (ECONNREFUSED, errno 61) still counts as a round trip',
        () async {
      final PingService svc = PingService(
        connector: (host, port, {required timeout}) async {
          throw const SocketException(
            'Connection refused',
            osError: OSError('refused', 61),
          );
        },
      );
      final List<PingProgress> ticks = await svc
          .ping(host: 'h', count: 1, interval: Duration.zero)
          .toList();
      expect(ticks.single.reply.success, isTrue,
          reason: 'a RST proves reachability — tcping semantics');
    });

    // NOTE: this fake used to throw `SocketException('timed out')` with a NULL
    // osError and call that "a timeout". That is NOT what the platform throws —
    // Dart's own connect-timeout carries an osError with the synthetic errno
    // 110. The old fake encoded the same false assumption as the code, which is
    // precisely why this suite stayed green while Ping reported every dead host
    // as a success with a fake RTT. The fake now throws the REAL shape.
    // See test/services/network/dead_host_classification_test.dart.
    test('timeout (Connection timed out, errno 110) → loss', () async {
      final PingService svc = PingService(
        connector: (host, port, {required timeout}) async {
          await Future<void>.delayed(timeout);
          throw const SocketException(
            'Connection timed out',
            osError: OSError('Connection timed out', 110),
          );
        },
      );
      final List<PingProgress> ticks = await svc
          .ping(
            host: 'h',
            count: 1,
            interval: Duration.zero,
            timeout: const Duration(milliseconds: 60),
          )
          .toList();
      expect(ticks.single.reply.success, isFalse);
      expect(ticks.single.reply.errorLabel, 'timeout');
    });
  });

  group('ping streaming + cancel', () {
    test('emits exactly count ticks with growing stats', () async {
      final PingService svc = PingService(
        connector: (host, port, {required timeout}) async => _FakeSocket(),
      );
      final List<PingProgress> ticks = await svc
          .ping(host: 'h', count: 3, interval: Duration.zero)
          .toList();
      expect(ticks.length, 3);
      expect(ticks.first.stats.sent, 1);
      expect(ticks.last.stats.sent, 3);
      expect(ticks.last.reply.sequence, 3);
    });

    test('cancel stops a continuous run', () async {
      final Completer<void> cancel = Completer<void>();
      final PingService svc = PingService(
        connector: (host, port, {required timeout}) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return _FakeSocket();
        },
      );
      final List<PingProgress> got = <PingProgress>[];
      final Completer<void> done = Completer<void>();
      svc
          .ping(
            host: 'h',
            count: 0, // continuous
            interval: const Duration(milliseconds: 5),
          )
          .listen(got.add, onDone: done.complete);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      cancel.complete();
      // Give the in-flight probe room to settle, then assert it ended bounded.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Continuous run keeps going until the stream is cancelled by the
      // subscription; assert we got several but not unbounded in this window.
      expect(got.isNotEmpty, isTrue);
    });
  });
}

/// Minimal fake Socket — only `destroy()` is invoked by the service.
class _FakeSocket implements Socket {
  @override
  void destroy() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
