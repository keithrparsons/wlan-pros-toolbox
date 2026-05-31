// SPIKE-HSD-01 — unit tests for the two bits worth locking before the build
// ticket: the device-type heuristic rule table and the subnet-seed derivation.
// Both are pure (no sockets, no plugins), so they run fast and deterministically
// with no device. The throwaway debug UI itself needs no tests (deleted with the
// spike).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/device_type.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/subnet_seed.dart';

void main() {
  group('inferDeviceType — ordered rule table', () {
    test('IPP/LPD/9100 ports → printer', () {
      expect(
        inferDeviceType(openPorts: <int>{631}, mdnsServices: <String>{}),
        DeviceType.printer,
      );
      expect(
        inferDeviceType(openPorts: <int>{515}, mdnsServices: <String>{}),
        DeviceType.printer,
      );
      expect(
        inferDeviceType(openPorts: <int>{9100, 80}, mdnsServices: <String>{}),
        DeviceType.printer,
      );
    });

    test('_ipp mDNS service → printer even with only a web port open', () {
      expect(
        inferDeviceType(
          openPorts: <int>{80},
          mdnsServices: <String>{'_ipp._tcp'},
        ),
        DeviceType.printer,
      );
    });

    test('554 RTSP → camera', () {
      expect(
        inferDeviceType(openPorts: <int>{554}, mdnsServices: <String>{}),
        DeviceType.camera,
      );
    });

    test('62078 lockdownd → iOS device', () {
      expect(
        inferDeviceType(openPorts: <int>{62078}, mdnsServices: <String>{}),
        DeviceType.iosDevice,
      );
    });

    test('_airplay / _raop service → Apple device', () {
      expect(
        inferDeviceType(
          openPorts: <int>{7000},
          mdnsServices: <String>{'_airplay._tcp'},
        ),
        DeviceType.appleDevice,
      );
      expect(
        inferDeviceType(
          openPorts: <int>{},
          mdnsServices: <String>{'_raop._tcp'},
        ),
        DeviceType.appleDevice,
      );
    });

    test('445 SMB → Windows / SMB host', () {
      expect(
        inferDeviceType(openPorts: <int>{445, 80}, mdnsServices: <String>{}),
        DeviceType.windowsHost,
      );
    });

    test('80/443/8080 only → web server', () {
      expect(
        inferDeviceType(openPorts: <int>{443}, mdnsServices: <String>{}),
        DeviceType.webServer,
      );
      expect(
        inferDeviceType(openPorts: <int>{8080}, mdnsServices: <String>{}),
        DeviceType.webServer,
      );
    });

    test('22 SSH only → SSH host', () {
      expect(
        inferDeviceType(openPorts: <int>{22}, mdnsServices: <String>{}),
        DeviceType.sshHost,
      );
    });

    test('mDNS-only (no port rule) → generic mDNS device', () {
      expect(
        inferDeviceType(
          openPorts: <int>{},
          mdnsServices: <String>{'_device-info._tcp'},
        ),
        DeviceType.mdnsDevice,
      );
      expect(
        inferDeviceType(openPorts: <int>{5353}, mdnsServices: <String>{}),
        DeviceType.mdnsDevice,
      );
    });

    test('no signals → unknown', () {
      expect(
        inferDeviceType(openPorts: <int>{}, mdnsServices: <String>{}),
        DeviceType.unknown,
      );
    });

    test('rule ORDER: printer wins over the SMB rule when both present', () {
      // A device with 445 AND 631 open is a printer (rule 1) not an SMB host
      // (rule 5) — most-specific-first.
      expect(
        inferDeviceType(openPorts: <int>{445, 631}, mdnsServices: <String>{}),
        DeviceType.printer,
      );
    });

    test('rule ORDER: camera wins over web when both 554 and 80 open', () {
      expect(
        inferDeviceType(openPorts: <int>{80, 554}, mdnsServices: <String>{}),
        DeviceType.camera,
      );
    });
  });

  group('SubnetSeedDeriver.computeSeed — pure derivation', () {
    test('/24 mask expands to 254 usable hosts, excludes net + broadcast', () {
      final SubnetSeed s = SubnetSeedDeriver.computeSeed(
        ip: '192.168.1.50',
        mask: '255.255.255.0',
      );
      expect(s.isValid, isTrue);
      expect(s.hosts.length, 254);
      expect(s.hosts.first, '192.168.1.1');
      expect(s.hosts.last, '192.168.1.254');
      expect(s.hosts.contains('192.168.1.0'), isFalse);
      expect(s.hosts.contains('192.168.1.255'), isFalse);
      expect(s.label, '192.168.1.1–192.168.1.254');
    });

    test('null mask falls back to /24', () {
      final SubnetSeed s = SubnetSeedDeriver.computeSeed(
        ip: '10.0.0.5',
        mask: null,
      );
      expect(s.isValid, isTrue);
      expect(s.hosts.length, 254);
      expect(s.hosts.first, '10.0.0.1');
      expect(s.hosts.last, '10.0.0.254');
    });

    test('wider-than-/24 mask is clamped to the device own /24', () {
      // A /16 would be 65k hosts — discovery clamps to the /24 the device sits
      // in (192.168.7.x here), never enumerating the whole /16.
      final SubnetSeed s = SubnetSeedDeriver.computeSeed(
        ip: '192.168.7.42',
        mask: '255.255.0.0',
      );
      expect(s.isValid, isTrue);
      expect(s.hosts.length, lessThanOrEqualTo(kMaxScanHosts));
      expect(s.hosts.first, '192.168.7.1');
      expect(s.hosts.last, '192.168.7.254');
    });

    test('/25 mask is honored (narrower than /24)', () {
      final SubnetSeed s = SubnetSeedDeriver.computeSeed(
        ip: '192.168.1.10',
        mask: '255.255.255.128',
      );
      expect(s.isValid, isTrue);
      expect(s.hosts.first, '192.168.1.1');
      expect(s.hosts.last, '192.168.1.126');
      expect(s.hosts.length, 126);
    });

    test('gateway is passed through unchanged', () {
      final SubnetSeed s = SubnetSeedDeriver.computeSeed(
        ip: '192.168.1.50',
        mask: '255.255.255.0',
        gateway: '192.168.1.1',
      );
      expect(s.gateway, '192.168.1.1');
      expect(s.selfIp, '192.168.1.50');
    });

    test('null / malformed IP → invalid with an honest reason', () {
      final SubnetSeed a =
          SubnetSeedDeriver.computeSeed(ip: null, mask: '255.255.255.0');
      expect(a.isValid, isFalse);
      expect(a.error, isNotNull);
      expect(a.hosts, isEmpty);

      final SubnetSeed b =
          SubnetSeedDeriver.computeSeed(ip: 'not.an.ip', mask: null);
      expect(b.isValid, isFalse);
      expect(b.error, isNotNull);
    });

    test('a non-contiguous mask falls back to /24 rather than mis-deriving', () {
      final SubnetSeed s = SubnetSeedDeriver.computeSeed(
        ip: '192.168.5.20',
        mask: '255.0.255.0', // invalid contiguous mask
      );
      expect(s.isValid, isTrue);
      expect(s.hosts.first, '192.168.5.1');
      expect(s.hosts.last, '192.168.5.254');
    });
  });
}
