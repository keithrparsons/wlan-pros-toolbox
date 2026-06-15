// DnsProbeService — unit tests for the DNS resolution-time probe (Keith #3).
//
// The resolver seam is faked so no live DNS is touched: tests drive a
// controlled duration / failure and assert the probe reports a REAL measured
// time when a host resolves and an honest unavailable state when none do
// (GL-005 — never a fabricated time).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/dns_probe_service.dart';

InternetAddress _addr() => InternetAddress('1.1.1.1');

void main() {
  group('DnsProbeService', () {
    test('reports the host + a measured time when the first host resolves',
        () async {
      final List<String> probed = <String>[];
      final service = DnsProbeService(
        hosts: const <String>['first.example', 'second.example'],
        resolver: (String host) async {
          probed.add(host);
          return <InternetAddress>[_addr()];
        },
      );

      final DnsProbeResult result = await service.measure();

      expect(result.isAvailable, isTrue);
      expect(result.host, 'first.example');
      expect(result.millis, isNotNull);
      expect(result.millis, greaterThanOrEqualTo(0));
      // The first host resolved, so the second is never tried.
      expect(probed, <String>['first.example']);
    });

    test('falls through to the next host when the first lookup throws',
        () async {
      final List<String> probed = <String>[];
      final service = DnsProbeService(
        hosts: const <String>['dead.example', 'live.example'],
        resolver: (String host) async {
          probed.add(host);
          if (host == 'dead.example') {
            throw const SocketException('NXDOMAIN');
          }
          return <InternetAddress>[_addr()];
        },
      );

      final DnsProbeResult result = await service.measure();

      expect(result.isAvailable, isTrue);
      expect(result.host, 'live.example');
      expect(probed, <String>['dead.example', 'live.example']);
    });

    test('an empty answer is not counted as a hit; it tries the next host',
        () async {
      final service = DnsProbeService(
        hosts: const <String>['empty.example', 'live.example'],
        resolver: (String host) async => host == 'empty.example'
            ? <InternetAddress>[]
            : <InternetAddress>[_addr()],
      );

      final DnsProbeResult result = await service.measure();

      expect(result.host, 'live.example');
      expect(result.isAvailable, isTrue);
    });

    test('reports the honest unavailable state when no host resolves (GL-005)',
        () async {
      final service = DnsProbeService(
        hosts: const <String>['a.example', 'b.example'],
        resolver: (String host) async =>
            throw const SocketException('offline'),
      );

      final DnsProbeResult result = await service.measure();

      expect(result.isAvailable, isFalse);
      expect(result.host, isNull);
      expect(result.millis, isNull);
    });

    test('a lookup that exceeds the timeout marks DNS unavailable, never hangs',
        () async {
      final service = DnsProbeService(
        hosts: const <String>['slow.example'],
        timeout: const Duration(milliseconds: 20),
        resolver: (String host) =>
            Future<List<InternetAddress>>.delayed(
          const Duration(seconds: 5),
          () => <InternetAddress>[_addr()],
        ),
      );

      final DnsProbeResult result = await service.measure();

      expect(result.isAvailable, isFalse);
    });
  });
}
