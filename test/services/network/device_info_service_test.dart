// DeviceInfoService.parseCellular unit tests — the pdp_ip0 cellular-interface
// heuristic and its honest "no cellular interface" / addressless states
// (Batch 6).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/device_info_service.dart';

/// Minimal fake of the abstract [NetworkInterface] — only the fields
/// `parseCellular` reads (`name`, `addresses`) carry data.
class _FakeInterface implements NetworkInterface {
  _FakeInterface(this.name, this.addresses);

  @override
  final String name;

  @override
  final List<InternetAddress> addresses;

  @override
  int get index => 0;
}

void main() {
  group('parseCellular', () {
    test('no pdp_ip0 → not present, empty, honest', () {
      final result = DeviceInfoService.parseCellular(<NetworkInterface>[
        _FakeInterface('en0', <InternetAddress>[InternetAddress('192.168.1.5')]),
        _FakeInterface('lo0', <InternetAddress>[InternetAddress('127.0.0.1')]),
      ]);
      expect(result.present, isFalse);
      expect(result.name, isNull);
      expect(result.addrs, isEmpty);
    });

    test('empty interface list → not present', () {
      final result = DeviceInfoService.parseCellular(const <NetworkInterface>[]);
      expect(result.present, isFalse);
      expect(result.addrs, isEmpty);
    });

    test('pdp_ip0 with an IPv4 → present with that address', () {
      final result = DeviceInfoService.parseCellular(<NetworkInterface>[
        _FakeInterface('en0', <InternetAddress>[InternetAddress('10.0.0.2')]),
        _FakeInterface(
          kCellularInterfaceName,
          <InternetAddress>[InternetAddress('100.64.12.34')],
        ),
      ]);
      expect(result.present, isTrue);
      expect(result.name, kCellularInterfaceName);
      expect(result.addrs.length, 1);
      expect(result.addrs.single.ip, '100.64.12.34');
      expect(result.addrs.single.isIPv4, isTrue);
    });

    test('pdp_ip0 present but addressless → present, empty addresses', () {
      final result = DeviceInfoService.parseCellular(<NetworkInterface>[
        _FakeInterface(kCellularInterfaceName, const <InternetAddress>[]),
      ]);
      expect(result.present, isTrue);
      expect(result.addrs, isEmpty);
    });

    test('cellularIPv4 picks the IPv4 over a co-bound IPv6', () {
      final result = DeviceInfoService.parseCellular(<NetworkInterface>[
        _FakeInterface(
          kCellularInterfaceName,
          <InternetAddress>[
            InternetAddress('2607:fb90::1'),
            InternetAddress('100.64.12.34'),
          ],
        ),
      ]);
      final snapshot = DeviceInfoSnapshot(
        cellularInterfaceName: result.name,
        cellularAddresses: result.addrs,
        cellularInterfacePresent: result.present,
      );
      expect(snapshot.cellularIPv4, '100.64.12.34');
      expect(snapshot.cellularAddresses.length, 2);
    });
  });

  group('DeviceInfoSnapshot convenience getters', () {
    test('memory + uptime labels delegate to the formatter', () {
      const snap = DeviceInfoSnapshot(
        totalMemoryBytes: 8 * 1024 * 1024 * 1024,
        uptimeSeconds: 274320,
      );
      expect(snap.totalMemoryLabel, '8 GB');
      expect(snap.uptimeLabel, '3d 4h 12m');
    });

    test('null sources → null labels (honest unavailable)', () {
      const snap = DeviceInfoSnapshot();
      expect(snap.totalMemoryLabel, isNull);
      expect(snap.uptimeLabel, isNull);
      expect(snap.cellularIPv4, isNull);
      // The OS version is nullable and defaults to the honest null.
      expect(snap.osVersion, isNull);
    });

    test('osVersion carries the human OS version when supplied', () {
      const snap = DeviceInfoSnapshot(modelName: 'MacBook Air', osVersion: '26.1');
      expect(snap.osVersion, '26.1');
      expect(snap.modelName, 'MacBook Air');
    });
  });

  group('formatMacOsVersion (pure macOS product-version formatter)', () {
    test('major.minor when the patch is 0 (drops the trailing .0)', () {
      expect(DeviceInfoService.formatMacOsVersion(26, 1, 0), '26.1');
      expect(DeviceInfoService.formatMacOsVersion(14, 0, 0), '14.0');
    });

    test('appends the patch only when it is non-zero', () {
      expect(DeviceInfoService.formatMacOsVersion(26, 1, 1), '26.1.1');
      expect(DeviceInfoService.formatMacOsVersion(13, 6, 3), '13.6.3');
    });

    test(
        'null (honest floor) when the components are absent (major <= 0), never '
        'a fabricated "0.0"', () {
      expect(DeviceInfoService.formatMacOsVersion(0, 0, 0), isNull);
      expect(DeviceInfoService.formatMacOsVersion(-1, 2, 3), isNull);
    });
  });
}
