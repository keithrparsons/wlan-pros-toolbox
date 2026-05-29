// ArpNdpService unit tests — the regression-prone parts: subnet/host
// derivation, /proc/net/arp parsing (incomplete-entry filtering, no fabricated
// MACs), the honest per-platform capability matrix, and active discovery with
// an injected connector + ARP-table reader (no network, no filesystem).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/arp_ndp_service.dart';

void main() {
  group('hostsForSubnet', () {
    test('/24 yields 254 usable hosts, excludes network + broadcast', () {
      final List<String> hosts =
          ArpNdpService.hostsForSubnet('192.168.1.50', 24);
      expect(hosts.length, 254);
      expect(hosts.first, '192.168.1.1');
      expect(hosts.last, '192.168.1.254');
      expect(hosts, isNot(contains('192.168.1.0'))); // network
      expect(hosts, isNot(contains('192.168.1.255'))); // broadcast
    });

    test('/30 yields 2 usable hosts', () {
      final List<String> hosts =
          ArpNdpService.hostsForSubnet('10.0.0.1', 30);
      expect(hosts, <String>['10.0.0.1', '10.0.0.2']);
    });

    test('refuses prefixes wider than /22 (never sweeps a /8)', () {
      expect(ArpNdpService.hostsForSubnet('10.0.0.1', 8), isEmpty);
      expect(ArpNdpService.hostsForSubnet('10.0.0.1', 16), isEmpty);
    });

    test('IPv6 / malformed input → empty', () {
      expect(ArpNdpService.hostsForSubnet('fe80::1', 64), isEmpty);
      expect(ArpNdpService.hostsForSubnet('not.an.ip', 24), isEmpty);
    });
  });

  group('defaultLanHosts', () {
    test('derives /24 and excludes the device own IP', () {
      final List<String> hosts = ArpNdpService.defaultLanHosts('192.168.1.50');
      expect(hosts.length, 253); // 254 minus self
      expect(hosts, isNot(contains('192.168.1.50')));
      expect(hosts, contains('192.168.1.1'));
    });
  });

  group('parseProcNetArp', () {
    const String sample = '''
IP address       HW type     Flags       HW address            Mask     Device
192.168.1.1      0x1         0x2         aa:bb:cc:dd:ee:ff     *        wlan0
192.168.1.42     0x1         0x2         11:22:33:44:55:66     *        wlan0
192.168.1.99     0x1         0x0         00:00:00:00:00:00     *        wlan0
192.168.1.7      0x1         0x2         00:00:00:00:00:00     *        wlan0
''';

    test('parses complete entries into IP → MAC', () {
      final Map<String, String> table = ArpNdpService.parseProcNetArp(sample);
      expect(table['192.168.1.1'], 'aa:bb:cc:dd:ee:ff');
      expect(table['192.168.1.42'], '11:22:33:44:55:66');
    });

    test('drops incomplete (flag 0x0) and all-zero MAC rows — no fakes', () {
      final Map<String, String> table = ArpNdpService.parseProcNetArp(sample);
      expect(table.containsKey('192.168.1.99'), isFalse); // flag 0x0
      expect(table.containsKey('192.168.1.7'), isFalse); // zero MAC
      expect(table.length, 2);
    });

    test('empty/garbage text → empty map', () {
      expect(ArpNdpService.parseProcNetArp(''), isEmpty);
      expect(ArpNdpService.parseProcNetArp('header only line'), isEmpty);
    });
  });

  group('capabilityFor', () {
    test('iOS → unavailable', () {
      expect(
        ArpNdpService.capabilityFor(isIOSOverride: true),
        ArpCapability.unavailable,
      );
    });
    test('Android / Linux → sweepWithMac', () {
      expect(
        ArpNdpService.capabilityFor(
            isIOSOverride: false, isAndroidOverride: true),
        ArpCapability.sweepWithMac,
      );
      expect(
        ArpNdpService.capabilityFor(
            isIOSOverride: false,
            isAndroidOverride: false,
            isLinuxOverride: true),
        ArpCapability.sweepWithMac,
      );
    });
    test('macOS / Windows (none of the above) → sweepNoMac', () {
      expect(
        ArpNdpService.capabilityFor(
          isIOSOverride: false,
          isAndroidOverride: false,
          isLinuxOverride: false,
        ),
        ArpCapability.sweepNoMac,
      );
    });
  });

  group('discover', () {
    // A connector that "connects" (host up) for an allow-listed set, and
    // throws a timeout-style SocketException (no osError) otherwise (host down).
    Future<Socket> Function(String, int, {required Duration timeout})
        connectorFor(Set<String> upHosts) {
      return (String host, int port, {required Duration timeout}) async {
        if (upHosts.contains(host)) {
          // We can't easily fabricate a real Socket; throw a refusal instead,
          // which the probe treats as "host up" (osError present).
          throw SocketException(
            'Connection refused',
            osError: const OSError('Connection refused', 61),
          );
        }
        throw const SocketException('timed out'); // no osError → down
      };
    }

    test('lists only responders; down hosts excluded', () async {
      final ArpNdpService svc = ArpNdpService(
        connector: connectorFor(<String>{'192.168.1.1', '192.168.1.5'}),
        arpTableReader: () async => null, // sweepNoMac path
      );
      final List<Neighbor> found = <Neighbor>[];
      await for (final ArpScanProgress p in svc.discover(
        hosts: <String>['192.168.1.1', '192.168.1.2', '192.168.1.5'],
        capabilityOverride: ArpCapability.sweepNoMac,
      )) {
        if (p.lastFound != null) found.add(p.lastFound!);
      }
      final Set<String> ips = found.map((Neighbor n) => n.ip).toSet();
      expect(ips, <String>{'192.168.1.1', '192.168.1.5'});
      // sweepNoMac → no MAC fabricated.
      expect(found.every((Neighbor n) => n.mac == null), isTrue);
    });

    test('sweepWithMac attaches real MAC from the injected ARP table', () async {
      final ArpNdpService svc = ArpNdpService(
        connector: connectorFor(<String>{'192.168.1.1'}),
        arpTableReader: () async => '''
IP address  HW type  Flags  HW address         Mask  Device
192.168.1.1 0x1      0x2    de:ad:be:ef:00:01  *     eth0
''',
      );
      final List<Neighbor> found = <Neighbor>[];
      await for (final ArpScanProgress p in svc.discover(
        hosts: <String>['192.168.1.1', '192.168.1.2'],
        capabilityOverride: ArpCapability.sweepWithMac,
      )) {
        if (p.lastFound != null) found.add(p.lastFound!);
      }
      expect(found.length, 1);
      expect(found.first.ip, '192.168.1.1');
      expect(found.first.mac, 'de:ad:be:ef:00:01');
    });

    test('empty host list closes immediately with a 0/0 tick', () async {
      final ArpNdpService svc = ArpNdpService(
        connector: connectorFor(<String>{}),
        arpTableReader: () async => null,
      );
      final List<ArpScanProgress> ticks = await svc
          .discover(
            hosts: const <String>[],
            capabilityOverride: ArpCapability.sweepNoMac,
          )
          .toList();
      expect(ticks.length, 1);
      expect(ticks.first.total, 0);
      expect(ticks.first.found, 0);
    });

    test('cancel stops the sweep early', () async {
      final Completer<void> cancel = Completer<void>();
      final ArpNdpService svc = ArpNdpService(
        connector: (String host, int port, {required Duration timeout}) async {
          // Slow "down" responses so cancel can fire mid-sweep.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          throw const SocketException('timed out');
        },
        arpTableReader: () async => null,
      );
      final List<String> hosts =
          List<String>.generate(200, (int i) => '10.0.0.${i + 1}');
      int probed = 0;
      final StreamSubscription<ArpScanProgress> sub = svc
          .discover(
            hosts: hosts,
            capabilityOverride: ArpCapability.sweepNoMac,
            cancel: cancel.future,
            concurrency: 4,
          )
          .listen((ArpScanProgress p) => probed = p.probed);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      cancel.complete();
      await sub.asFuture<void>();
      await sub.cancel();
      expect(probed, lessThan(hosts.length));
    });
  });
}
