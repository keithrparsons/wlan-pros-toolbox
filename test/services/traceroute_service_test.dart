// TracerouteService unit tests — the load-bearing logic here is line parsing
// (Unix traceroute + Windows tracert) and the platform-capability gate. Both
// are pure/static, so they test without a real subprocess or network. The
// parse helpers are exercised through a tiny test seam.

import 'dart:async';
import 'dart:convert';
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

  // ───────────────────────────────────────────────────────────────────────────
  // TARGET MATCHING — the hostname bug.
  //
  // The old fakes emitted NO output at all, and every parse test fed an IP
  // literal, so nothing ever exercised the reached-target comparison against a
  // hostname. It was comparing the hop IP to the UN-RESOLVED user string, so a
  // trace to `google.com` never matched, never stopped early, and reported
  // "target not reached" on a trace that plainly succeeded.
  //
  // These fakes stream REAL traceroute transcripts, hostname targets included.
  // ───────────────────────────────────────────────────────────────────────────
  group('reached-target detection — hostname targets (Unix)', () {
    test('a hostname target IS reached when a hop matches the resolved IP',
        () async {
      final TracerouteService svc = TracerouteService(
        platformOverride: 'macos',
        processStarter: (String exe, List<String> args) async =>
            _ScriptedProcess(<String>[
          // The binary itself tells us what it resolved the name to.
          'traceroute to google.com (142.250.72.14), 30 hops max, 60 byte packets',
          ' 1  router.local (192.168.1.1)  1.234 ms  1.111 ms  1.050 ms',
          ' 2  10.0.0.1 (10.0.0.1)  9.9 ms  10.1 ms  9.8 ms',
          ' 3  lax17s34-in-f14.1e100.net (142.250.72.14)  12.0 ms  11.8 ms  12.2 ms',
        ]),
      );

      final List<TracerouteEvent> events =
          await svc.trace(host: 'google.com').toList();

      final List<TracerouteHop> hops = events
          .map((TracerouteEvent e) => e.hop)
          .whereType<TracerouteHop>()
          .toList();
      final TracerouteResult result =
          events.last.result!; // terminal event

      expect(hops.length, 3);
      expect(result, isA<TracerouteComplete>());
      expect(
        (result as TracerouteComplete).reachedTarget,
        isTrue,
        reason: 'Hop 3 IS google.com (142.250.72.14). Reporting "target not '
            'reached" here is the shipped bug.',
      );
    });

    test('a hostname target is NOT reported reached when the path dies', () async {
      final TracerouteService svc = TracerouteService(
        platformOverride: 'macos',
        processStarter: (String exe, List<String> args) async =>
            _ScriptedProcess(<String>[
          'traceroute to google.com (142.250.72.14), 30 hops max, 60 byte packets',
          ' 1  router.local (192.168.1.1)  1.234 ms',
          ' 2  * * *',
          ' 3  * * *',
        ]),
      );

      final List<TracerouteEvent> events =
          await svc.trace(host: 'google.com').toList();
      final TracerouteResult result = events.last.result!;
      expect(result, isA<TracerouteComplete>());
      expect((result as TracerouteComplete).reachedTarget, isFalse);
    });

    test('the rDNS name of the final hop also counts as reaching the target',
        () async {
      // Some traceroutes print the target's own name on the last hop. If the
      // header is missing/unparseable, a name match is still a match.
      final TracerouteService svc = TracerouteService(
        platformOverride: 'macos',
        processStarter: (String exe, List<String> args) async =>
            _ScriptedProcess(<String>[
          ' 1  router.local (192.168.1.1)  1.2 ms',
          ' 2  example.com (93.184.216.34)  12.0 ms',
        ]),
      );

      final List<TracerouteEvent> events =
          await svc.trace(host: 'example.com').toList();
      final TracerouteResult result = events.last.result!;
      expect((result as TracerouteComplete).reachedTarget, isTrue);
    });

    test('an IP-literal target still works (no regression)', () async {
      final TracerouteService svc = TracerouteService(
        platformOverride: 'macos',
        processStarter: (String exe, List<String> args) async =>
            _ScriptedProcess(<String>[
          'traceroute to 9.9.9.9 (9.9.9.9), 30 hops max, 60 byte packets',
          ' 1  router.local (192.168.1.1)  1.2 ms',
          ' 2  9.9.9.9 (9.9.9.9)  12.0 ms',
        ]),
      );

      final List<TracerouteEvent> events =
          await svc.trace(host: '9.9.9.9').toList();
      final TracerouteResult result = events.last.result!;
      expect((result as TracerouteComplete).reachedTarget, isTrue);
    });
  });

  group('reached-target detection — hostname targets (Windows)', () {
    test('tracert hostname target IS reached via the bracketed header IP',
        () async {
      final TracerouteService svc = TracerouteService(
        platformOverride: 'windows',
        processStarter: (String exe, List<String> args) async =>
            _ScriptedProcess(<String>[
          '',
          'Tracing route to google.com [142.250.72.14]',
          'over a maximum of 30 hops:',
          '',
          '  1     1 ms     1 ms     1 ms  192.168.1.1',
          '  2     9 ms     9 ms     9 ms  10.0.0.1',
          '  3    12 ms    11 ms    12 ms  142.250.72.14',
          '',
          'Trace complete.',
        ]),
      );

      final List<TracerouteEvent> events =
          await svc.trace(host: 'google.com').toList();
      final TracerouteResult result = events.last.result!;
      expect(result, isA<TracerouteComplete>());
      expect((result as TracerouteComplete).reachedTarget, isTrue);
    });
  });

  group('header parsing — the resolved target IP', () {
    test('Unix header yields the resolved IP', () {
      expect(
        TracerouteServiceTestHook.parseResolvedTargetIp(
          'traceroute to google.com (142.250.72.14), 30 hops max, 60 byte packets',
          windows: false,
        ),
        '142.250.72.14',
      );
    });

    test('traceroute6 header yields the resolved IPv6', () {
      expect(
        TracerouteServiceTestHook.parseResolvedTargetIp(
          'traceroute6 to example.com (2606:2800:220:1:248:1893:25c8:1946), 30 hops max',
          windows: false,
        ),
        '2606:2800:220:1:248:1893:25c8:1946',
      );
    });

    test('Windows header yields the resolved IP', () {
      expect(
        TracerouteServiceTestHook.parseResolvedTargetIp(
          'Tracing route to google.com [142.250.72.14]',
          windows: true,
        ),
        '142.250.72.14',
      );
    });

    test('a hop line is not a header', () {
      expect(
        TracerouteServiceTestHook.parseResolvedTargetIp(
          ' 1  router.local (192.168.1.1)  1.2 ms',
          windows: false,
        ),
        isNull,
      );
      expect(
        TracerouteServiceTestHook.parseResolvedTargetIp(
          '  1     1 ms     1 ms     1 ms  192.168.1.1',
          windows: true,
        ),
        isNull,
      );
    });
  });
}

/// A [Process] fake that streams a scripted transcript on stdout, so the
/// reached-target logic is exercised against real traceroute output — hostname
/// header line included. The previous `_FakeProcess` emitted nothing, which is
/// exactly why the hostname bug survived the suite.
class _ScriptedProcess implements Process {
  _ScriptedProcess(this.lines);

  final List<String> lines;

  @override
  Stream<List<int>> get stdout => Stream<List<int>>.fromIterable(
        lines.map((String l) => utf8.encode('$l\n')),
      );

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
