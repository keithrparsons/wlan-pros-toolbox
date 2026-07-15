// IcmpService unit tests — exercise the SHARED ICMP foundation that both Real
// ICMP Ping and Mobile Traceroute sit on, WITHOUT the dart_ping package and
// WITHOUT a live ICMP round-trip (per the brief: no device-dependent tests).
//
// Covered here (everything testable off-device):
//   - per-platform echo capability gating (iOS/Android available, desktop
//     sandboxed-out, web)
//   - per-platform traceroute capability gating (Android available, iOS
//     no-TimeExceeded, desktop sandboxed-out, web) — the load-bearing honesty
//     decision that iOS can echo but cannot TTL-walk
//   - host validation / malformed-input handling
//   - IcmpStats.accumulate fold (min/avg/max/loss)
//   - foldHop: collapsing replies at one TTL into a hop (answered / timed out)
//   - ping() streaming + running stats via a fake backend
//   - traceroute() TTL sequencing: advances per TTL, stops on target, caps at
//     maxHops, surfaces a terminal complete event
//   - the no-backend StateError seam (honest failure, never fabricated data)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/icmp_service.dart';

void main() {
  group('echo capability gating', () {
    test('iOS and Android can run ICMP echo', () {
      for (final String os in <String>['ios', 'android']) {
        final IcmpService svc =
            IcmpService(platformOverride: os, isWebOverride: false);
        expect(svc.echoCapability, IcmpEchoCapability.available, reason: os);
      }
    });

    test('desktop is sandboxed out of ICMP echo', () {
      for (final String os in <String>['macos', 'windows', 'linux']) {
        final IcmpService svc =
            IcmpService(platformOverride: os, isWebOverride: false);
        expect(svc.echoCapability, IcmpEchoCapability.sandboxedDesktop,
            reason: os);
      }
    });

    test('web is excluded', () {
      final IcmpService svc =
          IcmpService(platformOverride: 'ios', isWebOverride: true);
      expect(svc.echoCapability, IcmpEchoCapability.web);
    });
  });

  group('traceroute capability gating (the honesty matrix)', () {
    test('Android supports a TTL-walk', () {
      final IcmpService svc =
          IcmpService(platformOverride: 'android', isWebOverride: false);
      expect(svc.tracerouteCapability, IcmpTracerouteCapability.available);
    });

    test('iOS can echo but CANNOT TTL-walk (no TimeExceeded)', () {
      final IcmpService svc =
          IcmpService(platformOverride: 'ios', isWebOverride: false);
      // The decisive finding: echo yes, traceroute no — decoupled capabilities.
      expect(svc.echoCapability, IcmpEchoCapability.available);
      expect(
        svc.tracerouteCapability,
        IcmpTracerouteCapability.noTimeExceeded,
      );
    });

    test('desktop traceroute is sandboxed out of the ICMP path', () {
      for (final String os in <String>['macos', 'windows', 'linux']) {
        final IcmpService svc =
            IcmpService(platformOverride: os, isWebOverride: false);
        expect(svc.tracerouteCapability,
            IcmpTracerouteCapability.sandboxedDesktop,
            reason: os);
      }
    });

    test('web is excluded', () {
      final IcmpService svc =
          IcmpService(platformOverride: 'android', isWebOverride: true);
      expect(svc.tracerouteCapability, IcmpTracerouteCapability.web);
    });
  });

  group('host validation', () {
    test('accepts a plain host and IP', () {
      expect(IcmpService.validateHost('example.com'), isNull);
      expect(IcmpService.validateHost('1.1.1.1'), isNull);
      expect(IcmpService.validateHost('  8.8.8.8  '), isNull); // trims
    });

    test('rejects empty / whitespace', () {
      expect(IcmpService.validateHost(''), isNotNull);
      expect(IcmpService.validateHost('   '), isNotNull);
    });

    test('rejects embedded spaces', () {
      expect(IcmpService.validateHost('exa mple.com'), isNotNull);
    });

    test('rejects shell-metacharacter injection defensively', () {
      for (final String bad in <String>[
        'a;b',
        r'a$b',
        'a|b',
        'a`b',
        'a&b',
        'a<b',
      ]) {
        expect(IcmpService.validateHost(bad), isNotNull, reason: bad);
      }
    });

    test('rejects an over-long host', () {
      expect(IcmpService.validateHost('a' * 254), isNotNull);
    });
  });

  group('IcmpStats.accumulate', () {
    test('starts empty', () {
      expect(IcmpStats.empty.sent, 0);
      expect(IcmpStats.empty.received, 0);
      expect(IcmpStats.empty.avgMs, isNull);
      expect(IcmpStats.empty.lossFraction, 0);
    });

    test('folds replies into min/avg/max', () {
      IcmpStats s = IcmpStats.empty;
      s = s.accumulate(
          const IcmpReply(sequence: 1, success: true, rttMs: 10));
      s = s.accumulate(
          const IcmpReply(sequence: 2, success: true, rttMs: 30));
      s = s.accumulate(
          const IcmpReply(sequence: 3, success: true, rttMs: 20));
      expect(s.sent, 3);
      expect(s.received, 3);
      expect(s.minMs, closeTo(10, 0.001));
      expect(s.maxMs, closeTo(30, 0.001));
      expect(s.avgMs, closeTo(20, 0.001));
    });

    test('counts losses and loss fraction; lost probe is not in the series',
        () {
      IcmpStats s = IcmpStats.empty;
      s = s.accumulate(
          const IcmpReply(sequence: 1, success: true, rttMs: 5));
      s = s.accumulate(
          const IcmpReply(sequence: 2, success: false, errorLabel: 'timeout'));
      expect(s.sent, 2);
      expect(s.received, 1);
      expect(s.lost, 1);
      expect(s.lossFraction, closeTo(0.5, 0.001));
      expect(s.rttsMs.length, 1);
    });
  });

  group('foldHop (TTL → one hop)', () {
    test('answered hop takes the first source and best RTT', () {
      final IcmpHop h = IcmpService.foldHop(5, '9.9.9.9', <IcmpReply>[
        const IcmpReply(
            sequence: 1, success: true, fromIp: '10.0.0.1', rttMs: 12),
        const IcmpReply(
            sequence: 2, success: true, fromIp: '10.0.0.1', rttMs: 8),
      ]);
      expect(h.ttl, 5);
      expect(h.fromIp, '10.0.0.1');
      expect(h.rttMs, closeTo(8, 0.001));
      expect(h.timedOut, isFalse);
    });

    test('all-timeout hop is marked timedOut with no source', () {
      final IcmpHop h = IcmpService.foldHop(7, '9.9.9.9', <IcmpReply>[
        const IcmpReply(sequence: 1, success: false, errorLabel: 'timeout'),
        const IcmpReply(sequence: 2, success: false, errorLabel: 'timeout'),
      ]);
      expect(h.ttl, 7);
      expect(h.fromIp, isNull);
      expect(h.rttMs, isNull);
      expect(h.timedOut, isTrue);
    });

    test('target hop reports the target as the source', () {
      final IcmpHop h = IcmpService.foldHop(3, '9.9.9.9', <IcmpReply>[
        const IcmpReply(
            sequence: 1, success: true, fromIp: '9.9.9.9', rttMs: 20),
      ]);
      expect(h.fromIp, '9.9.9.9');
      expect(h.timedOut, isFalse);
    });
  });

  group('ping() streaming over a fake backend', () {
    test('emits one progress per reply with growing stats', () async {
      final IcmpService svc = IcmpService(
        platformOverride: 'android',
        isWebOverride: false,
        backend: _FakeBackend.replies(<IcmpReply>[
          const IcmpReply(sequence: 1, success: true, rttMs: 10),
          const IcmpReply(sequence: 2, success: true, rttMs: 20),
          const IcmpReply(sequence: 3, success: false, errorLabel: 'timeout'),
        ]),
      );
      final List<IcmpProgress> ticks =
          await svc.ping(host: '1.1.1.1', count: 3).toList();
      expect(ticks.length, 3);
      expect(ticks.first.stats.sent, 1);
      expect(ticks.last.stats.sent, 3);
      expect(ticks.last.stats.received, 2);
      expect(ticks.last.stats.lossFraction, closeTo(1 / 3, 0.001));
    });

    test('throws on a platform where ICMP echo is unavailable', () {
      final IcmpService svc = IcmpService(
        platformOverride: 'macos',
        isWebOverride: false,
        backend: _FakeBackend.replies(const <IcmpReply>[]),
      );
      expect(() => svc.ping(host: '1.1.1.1'), throwsStateError);
    });

    test('with no backend wired, a run surfaces an honest StateError', () {
      final IcmpService svc =
          IcmpService(platformOverride: 'android', isWebOverride: false);
      // No fabricated data: a missing native backend throws loudly rather than
      // returning an empty/fake stream.
      expect(() => svc.ping(host: '1.1.1.1', count: 1), throwsStateError);
    });
  });

  group('traceroute() TTL sequencing over a fake backend', () {
    test('walks TTLs, names each hop, stops when the target answers', () async {
      // Hop 1 → router, hop 2 → router, hop 3 → target (== host).
      final IcmpService svc = IcmpService(
        platformOverride: 'android',
        isWebOverride: false,
        backend: _FakeBackend.perTtl(<int, List<IcmpReply>>{
          1: <IcmpReply>[
            const IcmpReply(
                sequence: 1, success: true, fromIp: '10.0.0.1', rttMs: 1)
          ],
          2: <IcmpReply>[
            const IcmpReply(
                sequence: 1, success: true, fromIp: '172.16.0.1', rttMs: 5)
          ],
          3: <IcmpReply>[
            const IcmpReply(
                sequence: 1, success: true, fromIp: '9.9.9.9', rttMs: 9)
          ],
        }, host: '9.9.9.9'),
      );

      final List<IcmpTraceEvent> events =
          await svc.traceroute(host: '9.9.9.9', maxHops: 30).toList();

      final List<IcmpHop> hops =
          events.where((e) => e.hop != null).map((e) => e.hop!).toList();
      expect(hops.length, 3, reason: 'stops at the target, not maxHops');
      expect(hops[0].fromIp, '10.0.0.1');
      expect(hops[1].fromIp, '172.16.0.1');
      expect(hops[2].fromIp, '9.9.9.9');

      final IcmpTraceEvent terminal = events.last;
      expect(terminal.done, isTrue);
      expect(terminal.reachedTarget, isTrue);
    });

    test('a timed-out hop does not stop the walk', () async {
      final IcmpService svc = IcmpService(
        platformOverride: 'android',
        isWebOverride: false,
        backend: _FakeBackend.perTtl(<int, List<IcmpReply>>{
          1: <IcmpReply>[
            const IcmpReply(sequence: 1, success: false, errorLabel: 'timeout')
          ],
          2: <IcmpReply>[
            const IcmpReply(
                sequence: 1, success: true, fromIp: '9.9.9.9', rttMs: 9)
          ],
        }, host: '9.9.9.9'),
      );
      final List<IcmpTraceEvent> events =
          await svc.traceroute(host: '9.9.9.9', maxHops: 30).toList();
      final List<IcmpHop> hops =
          events.where((e) => e.hop != null).map((e) => e.hop!).toList();
      expect(hops.length, 2);
      expect(hops[0].timedOut, isTrue);
      expect(hops[1].fromIp, '9.9.9.9');
      expect(events.last.reachedTarget, isTrue);
    });

    test('caps at maxHops without reaching the target', () async {
      // Every TTL times out; cap at 3 hops, never reach target.
      final IcmpService svc = IcmpService(
        platformOverride: 'android',
        isWebOverride: false,
        backend: _FakeBackend.alwaysTimeout(),
      );
      final List<IcmpTraceEvent> events =
          await svc.traceroute(host: '9.9.9.9', maxHops: 3).toList();
      final int hopCount =
          events.where((e) => e.hop != null).length;
      expect(hopCount, 3);
      expect(events.last.done, isTrue);
      expect(events.last.reachedTarget, isFalse);
    });

    test('throws where a TTL-walk is unavailable (iOS)', () {
      final IcmpService svc = IcmpService(
        platformOverride: 'ios',
        isWebOverride: false,
        backend: _FakeBackend.replies(const <IcmpReply>[]),
      );
      expect(() => svc.traceroute(host: '9.9.9.9'), throwsStateError);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // HOSTNAME TARGETS — the bug the old fakes could not see.
  //
  // Every fake above feeds an IP LITERAL as the host, so `hop.fromIp == host`
  // happened to work. Trace a NAME and the comparison is against the
  // un-resolved user string: it never matches, the walk never stops, and the
  // target IP is emitted over and over as hops n…maxHops.
  //
  // A resolver seam makes this testable with zero DNS.
  // ───────────────────────────────────────────────────────────────────────────
  group('traceroute() with a HOSTNAME target', () {
    test('stops at the target when the hop matches the RESOLVED IP', () async {
      final IcmpService svc = IcmpService(
        platformOverride: 'android',
        isWebOverride: false,
        resolver: (String h) async =>
            h == 'google.com' ? '142.250.72.14' : null,
        backend: _FakeBackend.perTtl(<int, List<IcmpReply>>{
          1: <IcmpReply>[
            const IcmpReply(
                sequence: 1, success: true, fromIp: '10.0.0.1', rttMs: 1)
          ],
          2: <IcmpReply>[
            const IcmpReply(
                sequence: 1, success: true, fromIp: '172.16.0.1', rttMs: 5)
          ],
          3: <IcmpReply>[
            const IcmpReply(
                sequence: 1, success: true, fromIp: '142.250.72.14', rttMs: 9)
          ],
        }, host: 'google.com'),
      );

      final List<IcmpTraceEvent> events =
          await svc.traceroute(host: 'google.com', maxHops: 30).toList();

      final List<IcmpHop> hops =
          events.where((e) => e.hop != null).map((e) => e.hop!).toList();

      expect(
        hops.length,
        3,
        reason: 'On the bug this runs all 30 TTLs and emits 142.250.72.14 as '
            'hops 3…30.',
      );
      expect(hops[2].fromIp, '142.250.72.14');
      expect(events.last.done, isTrue);
      expect(
        events.last.reachedTarget,
        isTrue,
        reason: 'The trace plainly reached google.com.',
      );
    });

    test('does not emit the target IP as a run of duplicate hops', () async {
      // The precise shipped symptom, pinned.
      final IcmpService svc = IcmpService(
        platformOverride: 'android',
        isWebOverride: false,
        resolver: (String h) async => '93.184.216.34',
        backend: _FakeBackend.perTtl(<int, List<IcmpReply>>{
          1: <IcmpReply>[
            const IcmpReply(
                sequence: 1, success: true, fromIp: '10.0.0.1', rttMs: 1)
          ],
          2: <IcmpReply>[
            const IcmpReply(
                sequence: 1, success: true, fromIp: '93.184.216.34', rttMs: 9)
          ],
        }, host: 'example.com'),
      );

      final List<IcmpTraceEvent> events =
          await svc.traceroute(host: 'example.com', maxHops: 30).toList();
      final List<IcmpHop> hops =
          events.where((e) => e.hop != null).map((e) => e.hop!).toList();

      final int targetHops =
          hops.where((IcmpHop h) => h.fromIp == '93.184.216.34').length;
      expect(
        targetHops,
        1,
        reason: 'The target must appear exactly once, as the final hop.',
      );
      expect(hops.length, 2);
    });

    test('an IP-literal target still works when DNS is unavailable', () async {
      // Resolver returns null (no DNS). An IP literal is its own resolution,
      // so the walk must still stop at the target — no regression.
      final IcmpService svc = IcmpService(
        platformOverride: 'android',
        isWebOverride: false,
        resolver: (String h) async => null,
        backend: _FakeBackend.perTtl(<int, List<IcmpReply>>{
          1: <IcmpReply>[
            const IcmpReply(
                sequence: 1, success: true, fromIp: '10.0.0.1', rttMs: 1)
          ],
          2: <IcmpReply>[
            const IcmpReply(
                sequence: 1, success: true, fromIp: '9.9.9.9', rttMs: 9)
          ],
        }, host: '9.9.9.9'),
      );

      final List<IcmpTraceEvent> events =
          await svc.traceroute(host: '9.9.9.9', maxHops: 30).toList();
      final List<IcmpHop> hops =
          events.where((e) => e.hop != null).map((e) => e.hop!).toList();
      expect(hops.length, 2);
      expect(events.last.reachedTarget, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // FIX A — an UNRESOLVABLE name is "couldn't resolve", not "100% loss".
  //
  // The 2026-07-15 device report: Keith typed `192.168.1.b` into ICMP Ping. It
  // is a syntactically valid HOSTNAME (last label is alphabetic), so it is
  // accepted, tried, and — on real DNS — fails to resolve. The old flow handed
  // the name straight to the backend, which produced a lost probe, and the
  // stream summarized that as "0/1 · 100% loss". That is the wrong kind of null:
  // 100% loss implies a real host that did not answer, when in fact the NAME was
  // never resolved and NO probe was ever sent.
  //
  // The fix resolves BEFORE probing: on resolution failure the stream carries an
  // [IcmpUnresolvedHostException] and emits ZERO progress ticks (so the screen
  // renders no packet-loss summary). All exercised with an injected resolver —
  // zero real DNS.
  // ───────────────────────────────────────────────────────────────────────────
  group('ping() with an UNRESOLVABLE hostname (Fix A)', () {
    test('reports a resolution failure, NOT a 100%-loss summary', () async {
      final IcmpService svc = IcmpService(
        platformOverride: 'ios',
        isWebOverride: false,
        resolver: (String h) async => null, // cannot resolve any name
        // If the OLD (pre-fix) path ran, this backend would emit a lost probe
        // and the stream would summarize it as one sent / zero received =
        // 100% loss. The fix must never reach the backend for an unresolvable
        // name.
        backend: _FakeBackend.replies(<IcmpReply>[
          const IcmpReply(
              sequence: 1, success: false, errorLabel: 'unknownHost'),
        ]),
      );

      final List<IcmpProgress> ticks = <IcmpProgress>[];
      Object? caught;
      final Completer<void> done = Completer<void>();
      svc.ping(host: '192.168.1.b', count: 1).listen(
            ticks.add,
            onError: (Object e) => caught = e,
            onDone: () => done.complete(),
            cancelOnError: false,
          );
      await done.future;

      expect(
        ticks,
        isEmpty,
        reason: 'A resolution failure must not produce a packet-loss summary '
            '(no probe was sent). On the bug this held one 100%-loss tick.',
      );
      expect(caught, isA<IcmpUnresolvedHostException>());
      expect((caught! as IcmpUnresolvedHostException).host, '192.168.1.b');
      expect(
        (caught! as IcmpUnresolvedHostException).message,
        contains("Couldn't resolve"),
      );
    });

    test('a resolvable hostname still pings normally', () async {
      final IcmpService svc = IcmpService(
        platformOverride: 'ios',
        isWebOverride: false,
        resolver: (String h) async => '93.184.216.34',
        backend: _FakeBackend.replies(<IcmpReply>[
          const IcmpReply(sequence: 1, success: true, rttMs: 14),
        ]),
      );
      final List<IcmpProgress> ticks =
          await svc.ping(host: 'example.com', count: 1).toList();
      expect(ticks.length, 1);
      expect(ticks.single.stats.received, 1);
      expect(ticks.single.stats.lossFraction, 0);
    });

    test('an IP literal skips DNS and pings even when the resolver is dead',
        () async {
      final IcmpService svc = IcmpService(
        platformOverride: 'ios',
        isWebOverride: false,
        resolver: (String h) async => null, // would fail every NAME
        backend: _FakeBackend.replies(<IcmpReply>[
          const IcmpReply(sequence: 1, success: true, rttMs: 3),
        ]),
      );
      final List<IcmpProgress> ticks =
          await svc.ping(host: '1.1.1.1', count: 1).toList();
      expect(ticks.length, 1, reason: 'An IP literal is its own resolution.');
      expect(ticks.single.stats.received, 1);
    });
  });
}

// ── Test helpers ────────────────────────────────────────────────────────────

/// A fake IcmpBackend so the foundation's logic is exercised with zero I/O.
class _FakeBackend implements IcmpBackend {
  _FakeBackend._(this._mode, {this.flat, this.perTtlMap, this.host});

  factory _FakeBackend.replies(List<IcmpReply> replies) =>
      _FakeBackend._(_Mode.flat, flat: replies);

  factory _FakeBackend.perTtl(Map<int, List<IcmpReply>> map,
          {required String host}) =>
      _FakeBackend._(_Mode.perTtl, perTtlMap: map, host: host);

  factory _FakeBackend.alwaysTimeout() => _FakeBackend._(_Mode.timeout);

  final _Mode _mode;
  final List<IcmpReply>? flat;
  final Map<int, List<IcmpReply>>? perTtlMap;
  final String? host;

  @override
  Stream<IcmpReply> echo({
    required String host,
    required int count,
    required Duration interval,
    required Duration timeout,
    int? ttl,
    Future<void>? cancel,
  }) async* {
    switch (_mode) {
      case _Mode.flat:
        for (final IcmpReply r in flat!) {
          yield r;
        }
      case _Mode.perTtl:
        final List<IcmpReply> rs = perTtlMap![ttl] ?? const <IcmpReply>[];
        for (final IcmpReply r in rs) {
          yield r;
        }
      case _Mode.timeout:
        yield IcmpReply(
            sequence: 1, success: false, errorLabel: 'timeout');
    }
  }
}

enum _Mode { flat, perTtl, timeout }
