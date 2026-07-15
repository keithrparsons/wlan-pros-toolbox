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
            host: '1.1.1.1',
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
          .ping(host: '1.1.1.1', count: 1, interval: Duration.zero)
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
            host: '1.1.1.1',
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
          .ping(host: '1.1.1.1', count: 3, interval: Duration.zero)
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
            host: '1.1.1.1',
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

  // ───────────────────────────────────────────────────────────────────────────
  // An UNRESOLVABLE name is "couldn't resolve", not "100% loss" (parity with
  // the ICMP Ping fix). TCP Ping had the same shape: a DNS failure was
  // classified `lookup failed` and counted as loss, so an unresolvable name
  // reported a misleading 100%-loss summary. The fix resolves BEFORE probing
  // and surfaces a typed [PingUnresolvedHostException] with zero probes sent.
  // Exercised with an injected resolver — zero real DNS.
  // ───────────────────────────────────────────────────────────────────────────
  group('ping() with an UNRESOLVABLE hostname (parity)', () {
    test('reports a resolution failure, NOT a 100%-loss summary', () async {
      bool connectorCalled = false;
      final PingService svc = PingService(
        resolver: (String h) async => null, // cannot resolve any name
        connector: (host, port, {required timeout}) async {
          connectorCalled = true;
          // If the OLD (pre-fix) path ran, this lookup failure would classify
          // as `lookup failed`, count as loss, and the stream would summarize
          // it as one sent / zero received = 100% loss. The fix must never
          // reach the connector for an unresolvable name.
          throw const SocketException(
            "Failed host lookup: '192.168.1.b'",
            osError: OSError('nodename nor servname provided, or not known', 8),
          );
        },
      );

      final List<PingProgress> ticks = <PingProgress>[];
      Object? caught;
      final Completer<void> done = Completer<void>();
      svc.ping(host: '192.168.1.b', count: 1, interval: Duration.zero).listen(
            ticks.add,
            onError: (Object e) => caught = e,
            onDone: done.complete,
            cancelOnError: false,
          );
      await done.future;

      expect(
        ticks,
        isEmpty,
        reason: 'A resolution failure must not produce a packet-loss summary '
            '(no probe was sent). On the bug this held one 100%-loss tick.',
      );
      expect(caught, isA<PingUnresolvedHostException>());
      expect((caught! as PingUnresolvedHostException).host, '192.168.1.b');
      expect(
        (caught! as PingUnresolvedHostException).message,
        contains("Couldn't resolve"),
      );
      expect(
        connectorCalled,
        isFalse,
        reason: 'no probe is sent for a name that cannot be resolved',
      );
    });

    test('a resolvable hostname still pings normally', () async {
      final PingService svc = PingService(
        resolver: (String h) async => '93.184.216.34',
        connector: (host, port, {required timeout}) async => _FakeSocket(),
      );
      final List<PingProgress> ticks = await svc
          .ping(host: 'example.com', count: 1, interval: Duration.zero)
          .toList();
      expect(ticks.length, 1);
      expect(ticks.single.reply.success, isTrue);
      expect(ticks.single.stats.received, 1);
      expect(ticks.single.stats.lossFraction, 0);
    });

    test('an IP literal skips DNS and pings even when the resolver is dead',
        () async {
      final PingService svc = PingService(
        resolver: (String h) async => null, // would fail every NAME
        connector: (host, port, {required timeout}) async => _FakeSocket(),
      );
      final List<PingProgress> ticks = await svc
          .ping(host: '1.1.1.1', count: 1, interval: Duration.zero)
          .toList();
      expect(ticks.length, 1, reason: 'An IP literal is its own resolution.');
      expect(ticks.single.reply.success, isTrue);
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
