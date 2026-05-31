// SPIKE-HSD-01 — unit tests for the two bits worth locking before the build
// ticket: the device-type heuristic rule table and the subnet-seed derivation.
// Both are pure (no sockets, no plugins), so they run fast and deterministically
// with no device. The throwaway debug UI itself needs no tests (deleted with the
// spike).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/connect_scan.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/device_type.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/lan_discovery_engine.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/mdns_browse.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/multicast_lock.dart';
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

/// A SubnetSeedDeriver fed a fixed ip/mask, with no plugin call, so the engine
/// runs its full pipeline in a unit test with no device. The given [ip]/[mask]
/// drive the derived host count (a /29-ish mask keeps it small + predictable).
SubnetSeedDeriver _seedDeriver({required String ip, required String mask}) {
  return SubnetSeedDeriver(
    reader: () async => (ip: ip, mask: mask, gateway: null),
  );
}

/// A fake [MdnsDiscovery] that replays a scripted list of [MdnsDiscoveryEvent]s
/// for one service type — no native plugin, no multicast, fully deterministic.
/// Events fire on the next microtask so the browse's listen() is wired first.
class _FakeMdnsDiscovery implements MdnsDiscovery {
  _FakeMdnsDiscovery(this.serviceType, this._scripted);

  @override
  final String serviceType;
  final List<MdnsDiscoveryEvent> _scripted;
  final StreamController<MdnsDiscoveryEvent> _out =
      StreamController<MdnsDiscoveryEvent>();
  bool disposed = false;

  @override
  Stream<MdnsDiscoveryEvent> start() {
    scheduleMicrotask(() {
      for (final MdnsDiscoveryEvent e in _scripted) {
        if (!_out.isClosed) _out.add(e);
      }
    });
    return _out.stream;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!_out.isClosed) await _out.close();
  }
}

/// A fake discovery whose stream emits an error — exercises the browse's
/// non-fatal onError path.
class _ErroringMdnsDiscovery implements MdnsDiscovery {
  _ErroringMdnsDiscovery(this.serviceType);

  @override
  final String serviceType;

  @override
  Stream<MdnsDiscoveryEvent> start() => Stream<MdnsDiscoveryEvent>.error(
      const SocketException('mDNS unavailable in test'));

  @override
  Future<void> dispose() async {}
}

/// Builds an [MdnsBrowser] whose discovery factory yields fakes scripted from
/// [byType] (service type → events). Anything not in the map yields a fake with
/// no events. A short timeout keeps tests fast.
MdnsBrowser _fakeMdnsBrowser({
  Map<String, List<MdnsDiscoveryEvent>> byType = const {},
  List<String>? serviceTypes,
  List<_FakeMdnsDiscovery>? created,
}) =>
    MdnsBrowser(
      serviceTypes: serviceTypes ?? kBrowsedServiceTypes,
      timeout: const Duration(milliseconds: 30),
      discoveryFactory: (String type) {
        final _FakeMdnsDiscovery d =
            _FakeMdnsDiscovery(type, byType[type] ?? const <MdnsDiscoveryEvent>[]);
        created?.add(d);
        return d;
      },
    );

/// An [MdnsBrowser] that discovers nothing — keeps engine tests fast and off the
/// real network.
MdnsBrowser _silentMdnsBrowser() => _fakeMdnsBrowser();

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

    test('REGRESSION: Sonos (_sonos mDNS + port 22 open) → speaker, NOT '
        'sshHost and NOT appleDevice', () {
      // On-device finding: a Sonos speaker exposes SSH (22) for management and
      // also advertises _raop/AirPlay. The lone-SSH rule used to fire first and
      // mislabel it "SSH host"; the _raop rule would mislabel it "Apple device".
      // mDNS identity must win, and the Sonos rule must precede the Apple rule.
      final DeviceType t = inferDeviceType(
        openPorts: <int>{22},
        mdnsServices: <String>{'_sonos._tcp', '_raop._tcp'},
      );
      expect(t, DeviceType.speaker);
      expect(t, isNot(DeviceType.sshHost));
      expect(t, isNot(DeviceType.appleDevice));
    });

    test('Chromecast (_googlecast mDNS) → media streamer', () {
      expect(
        inferDeviceType(
          openPorts: <int>{8009, 8443},
          mdnsServices: <String>{'_googlecast._tcp'},
        ),
        DeviceType.mediaStreamer,
      );
    });

    test('Apple device (_airplay/_raop WITHOUT _sonos) → still appleDevice', () {
      expect(
        inferDeviceType(
          openPorts: <int>{7000},
          mdnsServices: <String>{'_airplay._tcp', '_raop._tcp'},
        ),
        DeviceType.appleDevice,
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

  group('MdnsBrowser.browse — bonsoir seam → IP→{name,services} mapping', () {
    test('a _sonos._tcp resolved event produces a record whose services '
        'contain _sonos._tcp, keyed by its IPv4', () async {
      final List<_FakeMdnsDiscovery> created = <_FakeMdnsDiscovery>[];
      final MdnsBrowser browser = _fakeMdnsBrowser(
        serviceTypes: const <String>['_sonos._tcp'],
        byType: <String, List<MdnsDiscoveryEvent>>{
          '_sonos._tcp': <MdnsDiscoveryEvent>[
            const MdnsDiscoveryEvent(
              serviceType: '_sonos._tcp',
              name: 'Living Room',
              hostAddresses: <String>['192.168.1.42'],
            ),
          ],
        },
        created: created,
      );

      final Map<String, MdnsRecord> result = await browser.browse();

      expect(result.keys, contains('192.168.1.42'));
      final MdnsRecord rec = result['192.168.1.42']!;
      expect(rec.name, 'Living Room');
      expect(rec.services, contains('_sonos._tcp'));
      // Every discovery the factory built MUST be disposed (no native leak).
      expect(created.every((_FakeMdnsDiscovery d) => d.disposed), isTrue);
    });

    test('events across multiple service types fold onto the same IP', () async {
      final MdnsBrowser browser = _fakeMdnsBrowser(
        serviceTypes: const <String>['_airplay._tcp', '_raop._tcp'],
        byType: <String, List<MdnsDiscoveryEvent>>{
          '_airplay._tcp': <MdnsDiscoveryEvent>[
            const MdnsDiscoveryEvent(
              serviceType: '_airplay._tcp',
              name: 'Apple TV',
              hostAddresses: <String>['192.168.1.10'],
            ),
          ],
          '_raop._tcp': <MdnsDiscoveryEvent>[
            const MdnsDiscoveryEvent(
              serviceType: '_raop._tcp',
              name: 'Apple TV',
              hostAddresses: <String>['192.168.1.10'],
            ),
          ],
        },
      );

      final Map<String, MdnsRecord> result = await browser.browse();

      expect(result, hasLength(1));
      expect(result['192.168.1.10']!.services,
          containsAll(<String>['_airplay._tcp', '_raop._tcp']));
    });

    test('non-IPv4 host addresses are skipped; IPv4 from the same event kept',
        () async {
      final MdnsBrowser browser = _fakeMdnsBrowser(
        serviceTypes: const <String>['_http._tcp'],
        byType: <String, List<MdnsDiscoveryEvent>>{
          '_http._tcp': <MdnsDiscoveryEvent>[
            const MdnsDiscoveryEvent(
              serviceType: '_http._tcp',
              name: 'NAS',
              hostAddresses: <String>['fe80::1', '10.0.0.5'],
            ),
          ],
        },
      );

      final Map<String, MdnsRecord> result = await browser.browse();

      expect(result.keys, <String>['10.0.0.5']);
      expect(result.containsKey('fe80::1'), isFalse);
    });

    test('a discovery whose stream errors is non-fatal; browse returns empty',
        () async {
      final MdnsBrowser browser = MdnsBrowser(
        serviceTypes: const <String>['_http._tcp'],
        timeout: const Duration(milliseconds: 30),
        discoveryFactory: (String type) => _ErroringMdnsDiscovery(type),
      );

      final Map<String, MdnsRecord> result = await browser.browse();

      expect(result, isEmpty);
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

  group('LanDiscoveryEngine — streamed scanning progress (Fix 2 regression)', () {
    // A live ServerSocket so "open" probes hand back a real openable socket.
    late ServerSocket server;
    late int livePort;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      livePort = server.port;
      server.listen((Socket s) => s.destroy());
    });

    tearDown(() async {
      await server.close();
    });

    test('emits MULTIPLE increasing scanning-phase fractions, not one at 0.05 '
        'then a jump to 0.6', () async {
      // /29 over .1 → several hosts; a multi-port set → many probes, so the
      // in-process scan reports progress repeatedly. The fake connector marks
      // port 80 open (handshake to loopback) and refuses the rest, so every host
      // is alive and the run completes normally.
      final LanDiscoveryEngine engine = LanDiscoveryEngine(
        runInIsolate: false,
        seedDeriver: _seedDeriver(ip: '10.0.0.1', mask: '255.255.255.248'),
        mdnsBrowser: _silentMdnsBrowser(),
        multicastLock: const NoopMulticastLock(),
        reverseDns: (String ip) async => null,
        ports: const <int>[22, 80, 443, 445, 8080],
        connector: (String host, int port, Duration timeout) {
          if (port == 80) {
            return Socket.connect(InternetAddress.loopbackIPv4, livePort,
                timeout: timeout);
          }
          return Future<Socket>.error(_errnoEx(61, 'Connection refused'));
        },
      );

      final List<DiscoveryProgress> events =
          await engine.run().toList();

      // Collect the scanning-phase fractions in order. There must be MORE than
      // one (the bug was: only 0.05, then a jump straight to 0.6).
      final List<double> scanFractions = events
          .where((DiscoveryProgress p) => p.phase == DiscoveryPhase.scanning)
          .map((DiscoveryProgress p) => p.fraction)
          .toList();

      expect(scanFractions.length, greaterThan(2),
          reason: 'progress must tick repeatedly during the scan, not jump');

      // Strictly within the scanning band [0.05, 0.6], and non-decreasing.
      for (final double f in scanFractions) {
        expect(f, greaterThanOrEqualTo(0.05));
        expect(f, lessThanOrEqualTo(0.6));
      }
      for (int i = 1; i < scanFractions.length; i++) {
        expect(scanFractions[i], greaterThanOrEqualTo(scanFractions[i - 1]),
            reason: 'fractions must be monotonic');
      }
      // At least one intermediate value strictly between the seed (0.05) and the
      // band end (0.6) — proves real mid-scan progress was reported.
      expect(
        scanFractions.any((double f) => f > 0.05 && f < 0.6),
        isTrue,
        reason: 'expected at least one mid-scan fraction, not just 0.05 → 0.6',
      );

      // A 'probed X / Y' note shows up so the debug screen can display it.
      final bool hasProbedNote = events.any((DiscoveryProgress p) =>
          p.phase == DiscoveryPhase.scanning &&
          (p.note?.startsWith('probed ') ?? false));
      expect(hasProbedNote, isTrue);

      // The run still completes successfully with the alive hosts.
      expect(events.last.phase, DiscoveryPhase.complete);
      expect(engine.lastResult, isNotNull);
      expect(engine.lastResult!.error, isNull);
      expect(engine.lastResult!.hosts, isNotEmpty);
    });

    test('a scan that throws surfaces as a failed DiscoveryResult, not a hang',
        () async {
      final LanDiscoveryEngine engine = LanDiscoveryEngine(
        runInIsolate: false,
        seedDeriver: _seedDeriver(ip: '10.0.0.1', mask: '255.255.255.252'),
        mdnsBrowser: _silentMdnsBrowser(),
        multicastLock: const NoopMulticastLock(),
        reverseDns: (String ip) async => null,
        ports: const <int>[80],
        // A connector whose throw is NOT a SocketException — runConnectScan
        // classifies it as dead, so this alone would not fail the scan. Instead
        // inject a runner that throws to exercise the failure path.
        scanRunner: (ConnectScanRequest request) =>
            Future<List<HostPorts>>.error(StateError('scan blew up')),
      );

      final List<DiscoveryProgress> events = await engine.run().toList();

      expect(events.last.phase, DiscoveryPhase.failed);
      expect(engine.lastResult, isNotNull);
      expect(engine.lastResult!.error, contains('Connect-scan failed'));
    });
  });
}
