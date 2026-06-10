// TracerouteService unit tests — the load-bearing logic here is line parsing
// (Unix traceroute + Windows tracert) and the platform-capability gate. Both
// are pure/static, so they test without a real subprocess or network. The
// parse helpers are exercised through a tiny test seam.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/traceroute_service.dart';

void main() {
  group('platform gate', () {
    test('desktop platforms are supported', () {
      for (final String os in <String>['macos', 'windows', 'linux']) {
        final TracerouteService svc =
            TracerouteService(platformOverride: os);
        expect(svc.isSupportedPlatform, isTrue, reason: os);
      }
    });

    test('mobile platforms are not supported', () {
      for (final String os in <String>['ios', 'android']) {
        final TracerouteService svc =
            TracerouteService(platformOverride: os);
        expect(svc.isSupportedPlatform, isFalse, reason: os);
      }
    });

    test('mobile trace() emits an unsupported-platform verdict, no hops',
        () async {
      final TracerouteService svc =
          TracerouteService(platformOverride: 'ios');
      final List<TracerouteEvent> events =
          await svc.trace(host: 'example.com').toList();
      expect(events.length, 1);
      final TracerouteResult? r = events.single.result;
      expect(r, isA<TracerouteUnavailable>());
      expect(
        (r! as TracerouteUnavailable).reason,
        TracerouteUnavailableReason.unsupportedPlatform,
      );
    });
  });

  group('host validation — argument-injection guard', () {
    test('a `-`/`--`-leading host never spawns and reports invalidHost',
        () async {
      for (final String evil in <String>['-foo', '--help', '-O', '--mtu']) {
        bool spawned = false;
        final TracerouteService svc = TracerouteService(
          platformOverride: 'macos',
          processStarter: (String exe, List<String> args) async {
            spawned = true;
            throw StateError('must not spawn for "$evil"');
          },
        );
        final List<TracerouteEvent> events =
            await svc.trace(host: evil).toList();
        expect(spawned, isFalse, reason: evil);
        expect(events.length, 1, reason: evil);
        final TracerouteResult? r = events.single.result;
        expect(r, isA<TracerouteUnavailable>(), reason: evil);
        expect((r! as TracerouteUnavailable).reason,
            TracerouteUnavailableReason.invalidHost,
            reason: evil);
      }
    });

    test('a valid host DOES spawn (no false positive)', () async {
      List<String>? captured;
      final TracerouteService svc = TracerouteService(
        platformOverride: 'macos',
        processStarter: (String exe, List<String> args) async {
          captured = args;
          // Return a fake process that immediately completes with no output.
          return _FakeProcess();
        },
      );
      await svc.trace(host: 'example.com').toList();
      expect(captured, isNotNull);
      // The literal `--` terminator must precede the host in the arg vector.
      expect(captured!.contains('--'), isTrue);
      expect(captured!.indexOf('--') < captured!.indexOf('example.com'), isTrue);
      expect(captured!.last, 'example.com');
    });
  });

  group('Unix line parsing', () {
    TracerouteHop? parse(String line) =>
        TracerouteServiceTestHook.parseUnix(line);

    test('named hop with three RTTs', () {
      final TracerouteHop? h =
          parse(' 1  router.local (192.168.1.1)  1.234 ms  1.111 ms  1.050 ms');
      expect(h, isNotNull);
      expect(h!.ttl, 1);
      expect(h.host, 'router.local');
      expect(h.ip, '192.168.1.1');
      expect(h.rttsMs.length, 3);
      expect(h.bestRttMs, closeTo(1.050, 0.001));
      expect(h.timedOut, isFalse);
    });

    test('all-timeout hop (* * *)', () {
      final TracerouteHop? h = parse(' 5  * * *');
      expect(h, isNotNull);
      expect(h!.ttl, 5);
      expect(h.timedOut, isTrue);
      expect(h.ip, isNull);
      expect(h.bestRttMs, isNull);
    });

    test('bare-IP hop without rDNS', () {
      final TracerouteHop? h = parse(' 7  10.0.0.1 (10.0.0.1)  9.9 ms');
      expect(h, isNotNull);
      expect(h!.ip, '10.0.0.1');
      expect(h.rttsMs, <double>[9.9]);
    });

    test('partial-timeout hop (one star among RTTs)', () {
      final TracerouteHop? h =
          parse(' 7  10.0.0.1 (10.0.0.1)  9.9 ms  *  10.1 ms');
      expect(h, isNotNull);
      expect(h!.ip, '10.0.0.1');
      expect(h.rttsMs.length, 2);
      expect(h.timedOut, isFalse);
    });

    test('header / non-hop line returns null', () {
      expect(parse('traceroute to example.com (93.184.216.34), 30 hops max'),
          isNull);
      expect(parse(''), isNull);
    });
  });

  group('Windows line parsing', () {
    TracerouteHop? parse(String line) =>
        TracerouteServiceTestHook.parseWindows(line);

    test('hop with three RTTs and a trailing IP', () {
      final TracerouteHop? h = parse('  1     1 ms     1 ms     1 ms  192.168.1.1');
      expect(h, isNotNull);
      expect(h!.ttl, 1);
      expect(h.ip, '192.168.1.1');
      expect(h.rttsMs.length, 3);
    });

    test('sub-millisecond <1 ms is parsed', () {
      final TracerouteHop? h = parse('  2    <1 ms    <1 ms    <1 ms  10.0.0.1');
      expect(h, isNotNull);
      expect(h!.rttsMs.length, 3);
      expect(h.ip, '10.0.0.1');
    });

    test('request timed out', () {
      final TracerouteHop? h =
          parse('  3     *        *        *     Request timed out.');
      expect(h, isNotNull);
      expect(h!.timedOut, isTrue);
      expect(h.ip, isNull);
    });

    test('header / non-hop line returns null', () {
      expect(parse('Tracing route to example.com [93.184.216.34]'), isNull);
      expect(parse('over a maximum of 30 hops:'), isNull);
    });
  });

  group('TracerouteHop.bestRttMs', () {
    test('returns the minimum of the probes', () {
      const TracerouteHop h = TracerouteHop(
        ttl: 1,
        ip: '1.1.1.1',
        rttsMs: <double>[12.0, 8.5, 10.0],
      );
      expect(h.bestRttMs, closeTo(8.5, 0.001));
    });
  });
}

/// Minimal [Process] fake for the spawn-path test: empty stdout/stderr and an
/// immediate clean exit, so `trace()` runs to completion without a real
/// subprocess. Only the members the service touches are implemented.
class _FakeProcess implements Process {
  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Future<int> get exitCode => Future<int>.value(0);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  int get pid => 0;

  @override
  IOSink get stdin => throw UnimplementedError();
}
