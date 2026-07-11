// RED-FIRST regression suite for the TCP-probe liveness class defect.
//
// THE BUG (measured on macOS, 2026-07-10, Socket.connect timeout: 600ms):
//
//   Scenario                  | Exception            | errno | osError != null?
//   --------------------------|----------------------|-------|------------------
//   Live host, closed port    | Connection refused   |  61   | true  → ALIVE  ✅
//   DEAD host                 | Connection timed out |  110  | true  → DEAD   🔴
//
// Dart's OWN connect-timeout populates `osError` with a synthetic errno 110. So
// the shorthand "osError != null means the host answered" is FALSE: it catches
// timeouts, unreachable, and host-down right alongside genuine refusals. Five
// probes hand-rolled that shorthand; four got it wrong, and every dead IP on a
// subnet was reported alive (Keith's /24 sweep: "254 / 254 · 254 live").
//
// The pre-existing unit tests never caught this because their fakes encoded the
// SAME false assumption — they simulated a timeout as
// `SocketException('timed out')` with a NULL osError, which is not what the
// platform actually throws. These tests use the real shape.
//
// Every test here fails on the unfixed code. All four tools must:
//   - count a REFUSED host as alive (a RST proves the host answered the SYN —
//     tcping semantics, deliberate), and
//   - count a TIMED-OUT / unreachable / host-down probe as DEAD.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/arp_ndp_service.dart';
import 'package:wlan_pros_toolbox/services/network/ping_service.dart';
import 'package:wlan_pros_toolbox/services/network/ping_sweep_service.dart';
import 'package:wlan_pros_toolbox/services/network/port_scan_service.dart';

/// The exception a DEAD host actually produces: Dart's own connect-timeout,
/// which carries a NON-null osError with the synthetic errno 110. This is the
/// value that broke every probe.
SocketException deadHostException() => const SocketException(
      'Connection timed out',
      osError: OSError('Connection timed out', 110),
    );

/// The exception a LIVE host with a CLOSED port produces: ECONNREFUSED (61 on
/// BSD/macOS/iOS). The host answered the SYN with a RST — it is ALIVE.
SocketException refusedException() => const SocketException(
      'Connection refused',
      osError: OSError('Connection refused', 61),
    );

/// A connector that always throws [e]. Matches the seam every service exposes.
Future<Socket> Function(String, int, {required Duration timeout}) throwing(
  SocketException e,
) {
  return (String host, int port, {required Duration timeout}) async => throw e;
}

void main() {
  group('Ping Sweep — a dead host must NOT be counted live', () {
    test('every host times out → 0 live, nothing listed (was: all live)',
        () async {
      final PingSweepService svc =
          PingSweepService(connector: throwing(deadHostException()));
      final SweepSpec spec = PingSweepService.parseSpec('10.99.99.1-4');
      expect(spec.hosts, hasLength(4));

      final List<SweepProgress> ticks =
          await svc.sweep(spec: spec, ports: const <int>[443]).toList();

      final SweepProgress last = ticks.last;
      expect(last.completed, 4);
      expect(last.live, 0, reason: 'a timed-out host answered nothing');
      expect(
        ticks.where((SweepProgress p) => p.lastResponsive != null),
        isEmpty,
        reason: 'no dead host may be listed as a responsive row',
      );
    });

    test('a refused host still counts as responsive (RST = alive)', () async {
      final PingSweepService svc =
          PingSweepService(connector: throwing(refusedException()));
      final List<SweepProgress> ticks = await svc
          .sweep(
            spec: PingSweepService.parseSpec('10.99.99.7'),
            ports: const <int>[443],
          )
          .toList();
      expect(ticks.last.live, 1);
      expect(ticks.last.lastResponsive?.responded, isTrue);
    });
  });

  group('Ping (TCP) — a dead host must report loss, not a fake RTT', () {
    test('timed-out probe → success:false, errorLabel timeout, 100% loss',
        () async {
      final PingService svc =
          PingService(connector: throwing(deadHostException()));
      final List<PingProgress> ticks = await svc
          .ping(
            host: '10.99.99.1',
            count: 3,
            interval: Duration.zero,
            timeout: const Duration(milliseconds: 600),
          )
          .toList();

      expect(ticks, hasLength(3));
      for (final PingProgress p in ticks) {
        expect(p.reply.success, isFalse,
            reason: 'a dead host is a LOST packet, not a round trip');
        expect(p.reply.rtt, isNull, reason: 'no fake RTT equal to the timeout');
        expect(p.reply.errorLabel, 'timeout');
      }
      final PingStats stats = ticks.last.stats;
      expect(stats.received, 0);
      expect(stats.lost, 3);
      expect(stats.lossFraction, 1.0,
          reason: 'Ping could never report packet loss before the fix');
      expect(stats.avgMs, isNull);
    });

    test('a refused probe is still a successful round trip (tcping semantics)',
        () async {
      final PingService svc =
          PingService(connector: throwing(refusedException()));
      final List<PingProgress> ticks = await svc
          .ping(host: '10.99.99.7', count: 2, interval: Duration.zero)
          .toList();
      expect(ticks.every((PingProgress p) => p.reply.success), isTrue);
      expect(ticks.last.stats.received, 2);
      expect(ticks.last.stats.lossFraction, 0.0);
    });
  });

  group('Port Scan — a dead host is FILTERED, never "closed"', () {
    test('timed-out host → every port filtered (was: every port closed)',
        () async {
      final PortScanService svc =
          PortScanService(connector: throwing(deadHostException()));
      final List<PortScanProgress> ticks = await svc
          .scan(host: '10.99.99.1', ports: const <int>[22, 80, 443])
          .toList();

      final List<PortResult> results = <PortResult>[
        for (final PortScanProgress p in ticks)
          if (p.lastResult != null) p.lastResult!,
      ];
      expect(results, hasLength(3));
      for (final PortResult r in results) {
        expect(
          r.status,
          PortStatus.filtered,
          reason: 'port ${r.port}: "closed" would tell a network pro the host '
              'is UP and refusing — the exact opposite of the truth',
        );
      }
    });

    test('a refused port on a live host is CLOSED (not filtered)', () async {
      final PortScanService svc =
          PortScanService(connector: throwing(refusedException()));
      final List<PortScanProgress> ticks =
          await svc.scan(host: '10.99.99.7', ports: const <int>[443]).toList();
      final PortResult r =
          ticks.firstWhere((PortScanProgress p) => p.lastResult != null)
              .lastResult!;
      expect(r.status, PortStatus.closed);
    });
  });

  group('ARP/NDP — a dead host must not be discovered as a neighbor', () {
    Future<ArpScanProgress> runDiscover(SocketException thrown) async {
      final ArpNdpService svc = ArpNdpService(
        connector: throwing(thrown),
        arpTableReader: () async => null,
      );
      final List<ArpScanProgress> ticks = await svc
          .discover(
            hosts: const <String>['10.99.99.1', '10.99.99.2', '10.99.99.3'],
            capabilityOverride: ArpCapability.sweepNoMac,
          )
          .toList();
      return ticks.last;
    }

    test('timed-out hosts → 0 found (its _isUnreachable misses "timed out")',
        () async {
      final ArpScanProgress last = await runDiscover(deadHostException());
      expect(last.probed, 3);
      expect(last.found, 0);
    });

    test('refused hosts → found (a RST proves the neighbor is there)',
        () async {
      final ArpScanProgress last = await runDiscover(refusedException());
      expect(last.found, 3);
    });
  });

  group('cross-platform errno coverage (the same probe on every target)', () {
    // errno differs per platform; the classification must not be BSD-only.
    final Map<String, SocketException> aliveCases = <String, SocketException>{
      'ECONNREFUSED (BSD 61)': const SocketException('Connection refused',
          osError: OSError('Connection refused', 61)),
      'ECONNRESET (BSD 54)': const SocketException('Connection reset by peer',
          osError: OSError('Connection reset by peer', 54)),
      'ECONNREFUSED (Linux 111)': const SocketException('Connection refused',
          osError: OSError('Connection refused', 111)),
      'WSAECONNREFUSED (Windows 10061)': const SocketException(
          'No connection could be made because the target machine actively '
          'refused it',
          osError: OSError('actively refused it', 10061)),
    };

    final Map<String, SocketException> deadCases = <String, SocketException>{
      'Dart connect-timeout (synthetic 110)': const SocketException(
          'Connection timed out',
          osError: OSError('Connection timed out', 110)),
      'EHOSTUNREACH (BSD 65)': const SocketException('No route to host',
          osError: OSError('No route to host', 65)),
      'EHOSTDOWN (BSD 64)': const SocketException('Host is down',
          osError: OSError('Host is down', 64)),
      'ENETUNREACH (Linux 101)': const SocketException('Network is unreachable',
          osError: OSError('Network is unreachable', 101)),
      'EHOSTUNREACH (Linux 113)': const SocketException('No route to host',
          osError: OSError('No route to host', 113)),
      'WSAETIMEDOUT (Windows 10060)': const SocketException(
          'A connection attempt failed because the connected party did not '
          'properly respond after a period of time',
          osError: OSError('did not properly respond', 10060)),
      'failed host lookup (no osError)': const SocketException(
          'Failed host lookup: nowhere.invalid'),
    };

    aliveCases.forEach((String label, SocketException e) {
      test('$label → Ping Sweep counts the host LIVE', () async {
        final PingSweepService svc = PingSweepService(connector: throwing(e));
        final List<SweepProgress> ticks = await svc
            .sweep(
              spec: PingSweepService.parseSpec('10.99.99.7'),
              ports: const <int>[443],
            )
            .toList();
        expect(ticks.last.live, 1);
      });
    });

    deadCases.forEach((String label, SocketException e) {
      test('$label → Ping Sweep counts the host DEAD', () async {
        final PingSweepService svc = PingSweepService(connector: throwing(e));
        final List<SweepProgress> ticks = await svc
            .sweep(
              spec: PingSweepService.parseSpec('10.99.99.7'),
              ports: const <int>[443],
            )
            .toList();
        expect(ticks.last.live, 0, reason: label);
      });
    });
  });
}
