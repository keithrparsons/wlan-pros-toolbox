// SPIKE-HSD-01 — unit tests for the two bits worth locking before the build
// ticket: the device-type heuristic rule table and the subnet-seed derivation.
// Both are pure (no sockets, no plugins), so they run fast and deterministically
// with no device. The throwaway debug UI itself needs no tests (deleted with the
// spike).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/connect_scan.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/device_type.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/subnet_seed.dart';

// --- Fake-connector helpers for the connect-scan classification tests. ---
//
// `Socket` has no public constructor, so a genuinely-OPEN probe is simulated by
// connecting to a real loopback ServerSocket the test stands up. REFUSED and
// DEAD are simulated by throwing a SocketException with a constructed OSError
// carrying the errno we want to exercise — no real network for those. errno
// values used (BSD = iOS/macOS): EHOSTUNREACH=65, ECONNREFUSED=61, ECONNRESET=54.

/// Builds a SocketException with the given errno, like a failed connect.
SocketException _errnoEx(int code, String message) =>
    SocketException(message, osError: OSError(message, code));

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

  group('runConnectScan — three-outcome classification (the on-device bug)', () {
    // A genuinely-open probe needs a real socket (Socket has no public ctor), so
    // these tests connect to a loopback ServerSocket for "open" ports. The
    // server's actual port is irrelevant — the fake connector decides per the
    // probed port number, then connects to the live loopback port to hand back a
    // real, openable socket.
    late ServerSocket server;
    late int livePort;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      livePort = server.port;
      // Accept and immediately drop — we only need the handshake to complete.
      server.listen((Socket s) => s.destroy());
    });

    tearDown(() async {
      await server.close();
    });

    /// Connector that returns a real (open) socket for ports in [openPorts],
    /// otherwise throws [thrown] (an exception factory keyed by the probed port).
    Connector connectorWith({
      required Set<int> openPorts,
      required SocketException Function(int port) thrown,
    }) {
      return (String host, int port, Duration timeout) {
        if (openPorts.contains(port)) {
          return Socket.connect(
            InternetAddress.loopbackIPv4,
            livePort,
            timeout: timeout,
          );
        }
        return Future<Socket>.error(thrown(port));
      };
    }

    test('REGRESSION: every probe EHOSTUNREACH → host is DROPPED, not reported '
        'with all ports open', () async {
      // This is exactly the iOS/macOS dead-IP behavior the old code mis-read:
      // EHOSTUNREACH carries a non-null osError. A dead IP must NOT appear.
      final List<HostPorts> result = await runConnectScan(
        const ConnectScanRequest(
          hosts: <String>['10.0.0.99'],
          ports: <int>[22, 80, 443, 445, 515, 631],
        ),
        connector: connectorWith(
          openPorts: const <int>{},
          thrown: (_) => _errnoEx(65, 'No route to host'), // EHOSTUNREACH (BSD)
        ),
      );
      expect(result, isEmpty,
          reason: 'a host that only ever produced EHOSTUNREACH is dead');
    });

    test('also drops on ENETUNREACH / EHOSTDOWN / ETIMEDOUT and null osError',
        () async {
      final List<HostPorts> result = await runConnectScan(
        const ConnectScanRequest(
          hosts: <String>['10.0.0.1', '10.0.0.2', '10.0.0.3', '10.0.0.4'],
          ports: <int>[80, 443],
        ),
        connector: (String host, int port, Duration timeout) {
          // Map each host to a distinct "dead" failure mode.
          switch (host) {
            case '10.0.0.1':
              return Future<Socket>.error(
                  _errnoEx(51, 'Network is unreachable')); // ENETUNREACH (BSD)
            case '10.0.0.2':
              return Future<Socket>.error(
                  _errnoEx(64, 'Host is down')); // EHOSTDOWN (BSD)
            case '10.0.0.3':
              return Future<Socket>.error(
                  _errnoEx(60, 'Operation timed out')); // ETIMEDOUT (BSD)
            default:
              // Our own connect-timeout surfaces a null osError.
              return Future<Socket>.error(
                  const SocketException('Connection timed out'));
          }
        },
      );
      expect(result, isEmpty);
    });

    test('some ports connect, others refuse → openPorts holds only the '
        'connected ports; host is present', () async {
      final List<HostPorts> result = await runConnectScan(
        const ConnectScanRequest(
          hosts: <String>['192.168.1.10'],
          ports: <int>[22, 80, 443, 445],
        ),
        connector: connectorWith(
          openPorts: const <int>{80, 443}, // these two genuinely open
          thrown: (_) => _errnoEx(61, 'Connection refused'), // ECONNREFUSED BSD
        ),
      );
      expect(result, hasLength(1));
      final HostPorts host = result.single;
      expect(host.ip, '192.168.1.10');
      expect(host.alive, isTrue);
      expect(host.openPorts, <int>[80, 443],
          reason: 'refused ports (22, 445) must not appear as open');
    });

    test('every port refuses → host present, alive, openPorts EMPTY, and the '
        'device-type heuristic returns unknown (NOT printer)', () async {
      final List<HostPorts> result = await runConnectScan(
        const ConnectScanRequest(
          hosts: <String>['192.168.1.20'],
          ports: <int>[22, 80, 443, 445, 515, 631], // includes printer ports
        ),
        connector: connectorWith(
          openPorts: const <int>{}, // nothing open
          thrown: (_) => _errnoEx(61, 'Connection refused'), // all refused
        ),
      );
      expect(result, hasLength(1));
      final HostPorts host = result.single;
      expect(host.alive, isTrue);
      expect(host.openPorts, isEmpty);
      // The whole point: no open ports means no printer-port fingerprint, so the
      // heuristic must NOT stamp this as Printer.
      expect(
        inferDeviceType(
          openPorts: host.openPorts.toSet(),
          mdnsServices: const <String>{},
        ),
        DeviceType.unknown,
      );
    });

    test('Linux/Android errno ECONNREFUSED=111 / ECONNRESET=104 also count as '
        'alive (cross-platform, not iOS-only-correct)', () async {
      final List<HostPorts> result = await runConnectScan(
        const ConnectScanRequest(
          hosts: <String>['192.168.1.30', '192.168.1.31'],
          ports: <int>[80],
        ),
        connector: (String host, int port, Duration timeout) {
          if (host == '192.168.1.30') {
            return Future<Socket>.error(
                _errnoEx(111, 'Connection refused')); // ECONNREFUSED (Linux)
          }
          return Future<Socket>.error(
              _errnoEx(104, 'Connection reset by peer')); // ECONNRESET (Linux)
        },
      );
      expect(result, hasLength(2),
          reason: 'both Linux refusal errnos prove liveness');
      expect(result.every((HostPorts h) => h.alive && h.openPorts.isEmpty),
          isTrue);
    });

    test('mixed subnet: open host kept, refused host kept, dead host dropped',
        () async {
      final List<HostPorts> result = await runConnectScan(
        const ConnectScanRequest(
          hosts: <String>['10.1.1.1', '10.1.1.2', '10.1.1.3'],
          ports: <int>[80, 443],
        ),
        connector: (String host, int port, Duration timeout) {
          switch (host) {
            case '10.1.1.1': // genuinely open on 443
              if (port == 443) {
                return Socket.connect(InternetAddress.loopbackIPv4, livePort,
                    timeout: timeout);
              }
              return Future<Socket>.error(_errnoEx(61, 'Connection refused'));
            case '10.1.1.2': // alive but everything refused
              return Future<Socket>.error(_errnoEx(61, 'Connection refused'));
            default: // 10.1.1.3 — dead
              return Future<Socket>.error(_errnoEx(65, 'No route to host'));
          }
        },
      );
      // Host order is scan order; dead host is absent.
      expect(result.map((HostPorts h) => h.ip).toList(),
          <String>['10.1.1.1', '10.1.1.2']);
      expect(result[0].openPorts, <int>[443]);
      expect(result[1].openPorts, isEmpty);
      expect(result.every((HostPorts h) => h.alive), isTrue);
    });
  });
}
