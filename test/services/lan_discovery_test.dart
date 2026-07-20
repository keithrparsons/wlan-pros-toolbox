// SPIKE-HSD-01 — unit tests for the two bits worth locking before the build
// ticket: the device-type heuristic rule table and the subnet-seed derivation.
// Both are pure (no sockets, no plugins), so they run fast and deterministically
// with no device. The throwaway debug UI itself needs no tests (deleted with the
// spike).

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/arp_reader.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/connect_scan.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/device_type.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/lan_discovery_engine.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/lan_host.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/mdns_browse.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/multicast_lock.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/subnet_seed.dart';
import 'package:wlan_pros_toolbox/services/network/mac_oui_service.dart';

/// A fake [ArpReader] that returns a scripted result with no platform channel —
/// so engine tests exercise the ARP-enrichment fold deterministically.
class _FakeArpReader implements ArpReader {
  _FakeArpReader(this._result);
  final ArpReadResult _result;

  /// Engine tests stand in for a desktop platform that HAS a reader; the
  /// incapable case is driven through `ArpReadResult.unsupported` instead.
  @override
  bool get readsMac => true;

  @override
  Future<ArpReadResult> read() async => _result;
}

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

  // M1 — vendor/hostname HINTS. Vendor shows a class ONLY on an obvious match;
  // an unrecognized vendor leaves Unknown first-class (never fabricated).
  group('inferDeviceType — M1 vendor/hostname hints', () {
    test('a networking vendor WITH a Wi-Fi keyword → access point', () {
      expect(
        inferDeviceType(
          openPorts: <int>{443},
          mdnsServices: <String>{},
          vendor: 'Ubiquiti Inc.',
          hostname: 'unifi-ap-livingroom',
        ),
        DeviceType.accessPoint,
      );
    });

    test('a networking vendor with NO Wi-Fi keyword → generic network gear, '
        'never promoted to access point on the vendor alone', () {
      final DeviceType t = inferDeviceType(
        openPorts: <int>{443},
        mdnsServices: <String>{},
        vendor: 'Cisco Systems',
        hostname: 'sw-core-01',
      );
      expect(t, DeviceType.networkGear);
      expect(t, isNot(DeviceType.accessPoint));
    });

    test('an obvious printer vendor → printer even with no printer port open',
        () {
      expect(
        inferDeviceType(
          openPorts: <int>{80},
          mdnsServices: <String>{},
          vendor: 'Brother Industries',
        ),
        DeviceType.printer,
      );
    });

    test('an UNRECOGNIZED vendor contributes nothing — a bare-port host stays '
        'its port guess, and a portless one stays Unknown (GL-005)', () {
      // Unrecognized vendor + no ports/mDNS → still Unknown, not invented.
      expect(
        inferDeviceType(
          openPorts: <int>{},
          mdnsServices: <String>{},
          vendor: 'Acme Widgets LLC',
          hostname: 'some-host',
        ),
        DeviceType.unknown,
      );
      // Unrecognized vendor + lone SSH → the weak port guess, unchanged by M1.
      expect(
        inferDeviceType(
          openPorts: <int>{22},
          mdnsServices: <String>{},
          vendor: 'Acme Widgets LLC',
        ),
        DeviceType.sshHost,
      );
    });

    test('a raw-OUI fallback string (e.g. "B8:27:EB") trips no keyword → the '
        'host keeps its port/mDNS class, not a vendor-invented one', () {
      // The vendorLabelFor fallback hands the heuristic a hex OUI, not an
      // English vendor word; it must not read as networking gear.
      expect(
        inferDeviceType(
          openPorts: <int>{443},
          mdnsServices: <String>{},
          vendor: 'B8:27:EB',
        ),
        DeviceType.webServer,
      );
    });

    test('strong port evidence still wins over a vendor hint (SMB beats a '
        'networking vendor)', () {
      // A host with 445 open is an SMB host even if its OUI is a networking
      // vendor — hard evidence outranks the M1 hint.
      expect(
        inferDeviceType(
          openPorts: <int>{445},
          mdnsServices: <String>{},
          vendor: 'Netgear',
          hostname: 'nas-wifi',
        ),
        DeviceType.windowsHost,
      );
    });

    test('backward compatible: vendor + hostname default to null', () {
      // The pre-M1 call shape (ports + mDNS only) is unchanged.
      expect(
        inferDeviceType(openPorts: <int>{22}, mdnsServices: <String>{}),
        DeviceType.sshHost,
      );
    });
  });

  group('MdnsBrowser.browse — NWBrowser seam → IP→{name,services} mapping', () {
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

  group('NWBrowserMdnsDiscovery.parseNativeEvent — native payload normalization',
      () {
    test('well-formed payload → event with name + IPv4 address', () {
      final MdnsDiscoveryEvent? ev = NWBrowserMdnsDiscovery.parseNativeEvent(
        '_sonos._tcp',
        <Object?, Object?>{
          'serviceType': '_sonos._tcp',
          'name': 'Living Room',
          'hostAddresses': <Object?>['10.0.10.42'],
        },
      );
      expect(ev, isNotNull);
      expect(ev!.serviceType, '_sonos._tcp');
      expect(ev.name, 'Living Room');
      expect(ev.hostAddresses, <String>['10.0.10.42']);
    });

    test('missing name → empty name, address preserved', () {
      final MdnsDiscoveryEvent? ev = NWBrowserMdnsDiscovery.parseNativeEvent(
        '_http._tcp',
        <Object?, Object?>{
          'hostAddresses': <Object?>['192.168.1.5'],
        },
      );
      expect(ev, isNotNull);
      expect(ev!.name, '');
      expect(ev.hostAddresses, <String>['192.168.1.5']);
    });

    test('no addresses → null (resolved-only contract)', () {
      expect(
        NWBrowserMdnsDiscovery.parseNativeEvent(
          '_http._tcp',
          <Object?, Object?>{'name': 'x', 'hostAddresses': <Object?>[]},
        ),
        isNull,
      );
    });

    test('malformed payloads → null, never throws', () {
      expect(
        NWBrowserMdnsDiscovery.parseNativeEvent('_http._tcp', null),
        isNull,
      );
      expect(
        NWBrowserMdnsDiscovery.parseNativeEvent('_http._tcp', 'not a map'),
        isNull,
      );
      expect(
        NWBrowserMdnsDiscovery.parseNativeEvent(
          '_http._tcp',
          <Object?, Object?>{'hostAddresses': 'not a list'},
        ),
        isNull,
      );
      // Non-string / empty-string entries in the address list are filtered out;
      // if nothing usable remains, the event is dropped.
      expect(
        NWBrowserMdnsDiscovery.parseNativeEvent(
          '_http._tcp',
          <Object?, Object?>{
            'hostAddresses': <Object?>[42, '', null],
          },
        ),
        isNull,
      );
    });
  });

  group('UnavailableMdnsDiscovery — non-iOS/macOS clean empty discovery', () {
    test('start() yields no events and browse() folds nothing', () async {
      final UnavailableMdnsDiscovery disc =
          const UnavailableMdnsDiscovery('_http._tcp');
      expect(await disc.start().toList(), isEmpty);
      await disc.dispose(); // idempotent, never throws

      final MdnsBrowser browser = MdnsBrowser(
        serviceTypes: const <String>['_http._tcp', '_sonos._tcp'],
        timeout: const Duration(milliseconds: 20),
        discoveryFactory: (String type) => UnavailableMdnsDiscovery(type),
      );
      expect(await browser.browse(), isEmpty);
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

    test(
        'also drops on ENETUNREACH / EHOSTDOWN / ETIMEDOUT / the Dart '
        'connect-timeout (errno 110)', () async {
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
              // Dart's OWN connect-timeout. It carries a NON-null osError with
              // the synthetic errno 110 — measured, not assumed. This fake used
              // to throw a null-osError SocketException and carried a comment
              // asserting that "our own connect-timeout surfaces a null
              // osError". That belief is FALSE and is the belief that caused the
              // whole class defect; it has no business living in the test file
              // for the one probe that got the fix right.
              return Future<Socket>.error(
                  _errnoEx(110, 'Connection timed out'));
          }
        },
      );
      expect(result, isEmpty);
    });

    test(
        'REGRESSION: errno 110 alone drops the host — the exact errno behind '
        '"254 / 254 · 254 live"', () async {
      // connect_scan had the classification right, but never had a test for
      // the one errno that broke the other four probes. Pin it here too: the
      // shared classifier is now load-bearing for this file.
      final List<HostPorts> result = await runConnectScan(
        const ConnectScanRequest(
          hosts: <String>['10.0.0.7', '10.0.0.8'],
          ports: <int>[22, 80, 443, 445, 515, 631],
        ),
        connector: connectorWith(
          openPorts: const <int>{},
          thrown: (_) => _errnoEx(110, 'Connection timed out'),
        ),
      );
      expect(result, isEmpty,
          reason: 'errno 110 is Dart\'s own connect-timeout: NOBODY answered. '
              'Reading it as "the host replied" is what listed every dead IP '
              'on the subnet as live.');
    });

    test('a REFUSED host is still kept (no over-correction on errno 61)',
        () async {
      final List<HostPorts> result = await runConnectScan(
        const ConnectScanRequest(
          hosts: <String>['10.0.0.9'],
          ports: <int>[22, 80],
        ),
        connector: connectorWith(
          openPorts: const <int>{},
          thrown: (_) => _errnoEx(61, 'Connection refused'), // ECONNREFUSED
        ),
      );
      expect(result, hasLength(1),
          reason: 'a RST proves the host answered the SYN — alive, ports closed');
      expect(result.single.openPorts, isEmpty);
      expect(result.single.alive, isTrue);
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

  group('MacOuiService.vendorLabelFor — W2 discovery vendor resolver', () {
    // The production MAC→vendor seam the engine injects. Backs the full bundled
    // IEEE registry in the app; here a tiny in-memory table exercises the same
    // honesty contract that replaced the throwaway OuiVendor inline table.
    final MacOuiService svc = MacOuiService.fromTable(<String, String>{
      'FCECDA': 'Ubiquiti', // a known /24
    });

    test('a known OUI resolves to the named vendor', () {
      expect(svc.vendorLabelFor('fc:ec:da:01:23:45'), 'Ubiquiti');
    });

    test('an unknown but globally-administered OUI falls back to the raw OUI, '
        'never null/invented', () {
      expect(svc.vendorLabelFor('00:11:22:33:44:55'), '00:11:22');
    });

    test('a locally-administered (U/L bit set) MAC returns null — the screen '
        'renders "Randomized (local)" itself, never a fabricated vendor', () {
      // 0x02 set in the first octet → locally administered.
      expect(svc.vendorLabelFor('02:fc:ec:da:00:01'), isNull);
    });

    test('a multicast (I/G bit set) MAC returns null — not a single NIC', () {
      // 0x01 set in the first octet → multicast / group.
      expect(svc.vendorLabelFor('01:00:5e:00:00:01'), isNull);
    });

    test('accepts hyphen, dot, and bare notations; case-insensitive', () {
      expect(svc.vendorLabelFor('FC-EC-DA-01-23-45'), 'Ubiquiti');
      expect(svc.vendorLabelFor('fcec.da01.2345'), 'Ubiquiti');
      expect(svc.vendorLabelFor('fcecda012345'), 'Ubiquiti');
    });

    test('an invalid MAC (wrong length) returns null, never throws', () {
      expect(svc.vendorLabelFor('fc:ec:da'), isNull);
      expect(svc.vendorLabelFor('not-a-mac'), isNull);
    });
  });

  group('MethodChannelArpReader.parsePayload — Swift payload → ArpReadResult',
      () {
    test('available:true with entries → mapped IP→MAC, lower-cased', () {
      final ArpReadResult r = MethodChannelArpReader.parsePayload(
        <String, Object?>{
          'available': true,
          'entries': <Object?>[
            <String, Object?>{'ip': '10.0.10.5', 'mac': 'B8:27:EB:01:23:45'},
            <String, Object?>{'ip': '10.0.10.6', 'mac': 'fc:ec:da:aa:bb:cc'},
          ],
        },
      );
      expect(r.available, isTrue);
      expect(r.error, isNull);
      expect(r.byIp['10.0.10.5'], 'b8:27:eb:01:23:45'); // lower-cased
      expect(r.byIp['10.0.10.6'], 'fc:ec:da:aa:bb:cc');
    });

    test('available:true with empty entries is a VALID success, not a failure',
        () {
      final ArpReadResult r = MethodChannelArpReader.parsePayload(
        <String, Object?>{'available': true, 'entries': <Object?>[]},
      );
      expect(r.available, isTrue);
      expect(r.entries, isEmpty);
      expect(r.error, isNull);
    });

    test('available:false surfaces a sandbox-blocked message with the errno',
        () {
      final ArpReadResult r = MethodChannelArpReader.parsePayload(
        <String, Object?>{
          'available': false,
          'entries': <Object?>[],
          'error': 'sysctl(fetch) failed: errno 1 (Operation not permitted)',
        },
      );
      expect(r.available, isFalse);
      expect(r.error, contains('sandbox-blocked'));
      expect(r.error, contains('Operation not permitted'));
    });

    test('a malformed payload (not a Map) becomes an honest unavailable result',
        () {
      final ArpReadResult r = MethodChannelArpReader.parsePayload('garbage');
      expect(r.available, isFalse);
      expect(r.error, isNotNull);
    });

    test('entries with missing/empty fields are skipped, never faked', () {
      final ArpReadResult r = MethodChannelArpReader.parsePayload(
        <String, Object?>{
          'available': true,
          'entries': <Object?>[
            <String, Object?>{'ip': '10.0.0.1', 'mac': ''}, // empty mac
            <String, Object?>{'ip': '', 'mac': 'aa:bb:cc:dd:ee:ff'}, // empty ip
            <String, Object?>{'ip': '10.0.0.2'}, // missing mac
            <String, Object?>{'ip': '10.0.0.3', 'mac': 'aa:bb:cc:00:11:22'},
          ],
        },
      );
      expect(r.entries, hasLength(1));
      expect(r.byIp['10.0.0.3'], 'aa:bb:cc:00:11:22');
    });
  });

  group('LanDiscoveryEngine — ARP enrichment (Gate 2 fold)', () {
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

    // A small in-memory IEEE registry so the W2 vendor fold is exercised against
    // the real MacOuiService.vendorLabelFor path (the production resolver), not
    // a stand-in. fc:ec:da is a known Ubiquiti /24; 00:11:22 is deliberately
    // absent so the raw-OUI fallback is tested.
    final MacOuiService oui = MacOuiService.fromTable(<String, String>{
      'FCECDA': 'Ubiquiti',
    });

    LanDiscoveryEngine engineWithArp(ArpReader arpReader) => LanDiscoveryEngine(
          runInIsolate: false,
          seedDeriver: _seedDeriver(ip: '10.0.10.1', mask: '255.255.255.252'),
          mdnsBrowser: _silentMdnsBrowser(),
          multicastLock: const NoopMulticastLock(),
          reverseDns: (String ip) async => null,
          arpReader: arpReader,
          vendorResolver: oui.vendorLabelFor,
          ports: const <int>[80],
          connector: (String host, int port, Duration timeout) {
            // Every host in the /30 is alive on port 80 (handshake to loopback).
            return Socket.connect(InternetAddress.loopbackIPv4, livePort,
                timeout: timeout);
          },
        );

    test('a successful ARP read populates MAC + vendor on matching hosts', () async {
      // /30 over .1 → hosts .1 and .2.
      final ArpReadResult arp = ArpReadResult(
        available: true,
        entries: const <ArpEntry>[
          ArpEntry(ip: '10.0.10.1', mac: 'fc:ec:da:01:23:45'), // Ubiquiti
          ArpEntry(ip: '10.0.10.2', mac: '00:11:22:33:44:55'), // unknown → raw
        ],
      );
      final LanDiscoveryEngine engine = engineWithArp(_FakeArpReader(arp));

      await engine.run().toList();
      final DiscoveryResult r = engine.lastResult!;

      expect(r.arp, isNotNull);
      expect(r.arp!.available, isTrue);
      final LanHost h1 = r.hosts.firstWhere((LanHost h) => h.ip == '10.0.10.1');
      expect(h1.mac, 'fc:ec:da:01:23:45');
      expect(h1.vendor, 'Ubiquiti');
      final LanHost h2 = r.hosts.firstWhere((LanHost h) => h.ip == '10.0.10.2');
      expect(h2.mac, '00:11:22:33:44:55');
      expect(h2.vendor, '00:11:22'); // raw-OUI fallback, never null
    });

    test('an unavailable ARP read leaves MAC/vendor null and surfaces the '
        'reason — the run still completes', () async {
      final LanDiscoveryEngine engine = engineWithArp(
        _FakeArpReader(const ArpReadResult.unsupported(
          'iOS sandbox cannot read the ARP table.',
        )),
      );

      final List<DiscoveryProgress> events = await engine.run().toList();
      final DiscoveryResult r = engine.lastResult!;

      expect(events.last.phase, DiscoveryPhase.complete);
      expect(r.error, isNull); // not a failed run; ARP is enrichment-only
      expect(r.arp, isNotNull);
      expect(r.arp!.available, isFalse);
      expect(r.arp!.error, contains('sandbox'));
      expect(r.hosts.every((LanHost h) => h.mac == null), isTrue);
      expect(r.hosts.every((LanHost h) => h.vendor == null), isTrue);
    });

    test('the run emits an arp progress phase', () async {
      final LanDiscoveryEngine engine = engineWithArp(
        _FakeArpReader(const ArpReadResult(available: true)),
      );
      final List<DiscoveryProgress> events = await engine.run().toList();
      expect(
        events.any((DiscoveryProgress p) => p.phase == DiscoveryPhase.arp),
        isTrue,
      );
    });
  });

  // The 2026-05-31 stream-lifecycle fix: the production transport must open
  // EXACTLY ONE EventChannel stream for the whole browse (a Flutter EventChannel
  // allows only one active stream per name), pass the full service-type list as
  // the single listen argument, demultiplex incoming events by `serviceType`,
  // and cancel exactly once when the last per-type discovery disposes. These
  // tests stand in a mock platform channel for the native side.
  group('mDNS single-stream transport (production EventChannel lifecycle)', () {
    const String channel = kMdnsBrowseChannel;
    const MethodCodec codec = StandardMethodCodec();

    late TestDefaultBinaryMessenger messenger;
    late int listenCount;
    late int cancelCount;
    late Object? lastListenArgs;
    void Function(Object? event)? sink;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      messenger = TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger;
      listenCount = 0;
      cancelCount = 0;
      lastListenArgs = null;
      sink = null;

      // Mock the native side of the EventChannel: record listen/cancel calls and
      // expose a sink that pushes events back up the broadcast stream, exactly
      // as the native BrowseSession's `emit` does.
      messenger.setMockMethodCallHandler(
        MethodChannel(channel, codec),
        (MethodCall call) async {
          if (call.method == 'listen') {
            listenCount++;
            lastListenArgs = call.arguments;
            sink = (Object? event) {
              messenger.handlePlatformMessage(
                channel,
                codec.encodeSuccessEnvelope(event),
                (ByteData? _) {},
              );
            };
            return codec.encodeSuccessEnvelope(null);
          }
          if (call.method == 'cancel') {
            cancelCount++;
            sink = null;
            return codec.encodeSuccessEnvelope(null);
          }
          return null;
        },
      );
    });

    test('a 16-type browse opens ONE stream with the full type list, not 16',
        () async {
      final MdnsBrowser browser = MdnsBrowser(
        serviceTypes: kBrowsedServiceTypes,
        timeout: const Duration(milliseconds: 60),
      );

      // While the browse is in its dwell window, push a Sonos event up the ONE
      // stream tagged with its service type; the transport must demux it to the
      // _sonos._tcp discovery and fold it into the result.
      final Future<Map<String, MdnsRecord>> browsing = browser.browse();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sink?.call(<String, Object?>{
        'serviceType': '_sonos._tcp',
        'name': 'Living Room',
        'hostAddresses': <String>['192.168.1.42'],
      });
      final Map<String, MdnsRecord> result = await browsing;

      // ONE listen for the whole browse — the bug was 16.
      expect(listenCount, 1);
      // The single listen argument is the FULL service-type list.
      expect(lastListenArgs, kBrowsedServiceTypes);
      // Exactly one cancel when the browse's dwell window ends.
      expect(cancelCount, 1);
      // The event was demultiplexed to the right type and folded in.
      expect(result['192.168.1.42']?.name, 'Living Room');
      expect(result['192.168.1.42']?.services, contains('_sonos._tcp'));
      // Exercises the production EventChannel transport (NWBrowser native seam),
      // which has no Linux implementation; skip on the Linux CI runner only.
    }, skip: Platform.isLinux);

    test('back-to-back browses each open and cancel exactly one stream',
        () async {
      Future<void> oneBrowse() async {
        await MdnsBrowser(
          serviceTypes: const <String>['_http._tcp', '_sonos._tcp'],
          timeout: const Duration(milliseconds: 30),
        ).browse();
      }

      await oneBrowse();
      await oneBrowse();

      expect(listenCount, 2); // one per browse, never one-per-type
      expect(cancelCount, 2);
      // Same production EventChannel transport seam — skip on Linux CI only.
    }, skip: Platform.isLinux);

    tearDown(() {
      messenger.setMockMethodCallHandler(MethodChannel(channel, codec), null);
    });
  });

  group('DiscoveryResult.hostsOutsideSweep', () {
    // The screen prints a swept range and a host list. This getter is what
    // stops those two from contradicting each other. Held against the LITERAL
    // probed set rather than the label's endpoints, because the seed clamps at
    // kMaxScanHosts: a range check would call a clamped-off address "in range"
    // when it was never probed.

    test('empty when every host was probed', () {
      final DiscoveryResult r = DiscoveryResult(
        hosts: <LanHost>[LanHost(ip: '10.0.0.5'), LanHost(ip: '10.0.0.6')],
        subnetLabel: '10.0.0.1-10.0.0.254',
        sweptIps: const <String>['10.0.0.5', '10.0.0.6'],
      );
      expect(r.hostsOutsideSweep, isEmpty);
    });

    test('names only the hosts that were never probed', () {
      final DiscoveryResult r = DiscoveryResult(
        hosts: <LanHost>[
          LanHost(ip: '172.20.29.10'),
          LanHost(ip: '172.20.0.2'),
          LanHost(ip: '172.20.0.69'),
        ],
        subnetLabel: '172.20.29.1-172.20.29.254',
        sweptIps: const <String>['172.20.29.10'],
      );
      expect(
        r.hostsOutsideSweep.map((LanHost h) => h.ip),
        <String>['172.20.0.2', '172.20.0.69'],
      );
    });

    test('an unknown sweep set accuses nobody', () {
      final DiscoveryResult r = DiscoveryResult(
        hosts: <LanHost>[LanHost(ip: '10.0.0.5')],
        subnetLabel: '10.0.0.1-10.0.0.254',
      );
      expect(r.sweptIps, isEmpty);
      expect(r.hostsOutsideSweep, isEmpty);
    });

    test('an address inside the label but outside the probed set is a stray',
        () {
      // Contract test for the getter, driven by a hand-built sweptIps: an
      // address can sit inside the LABEL's range and still not have been
      // probed, and membership must follow the probed set, not the label.
      //
      // NOTE: the engine cannot currently produce this input. An earlier
      // comment here claimed kMaxScanHosts (254) could cut the seed short; it
      // cannot, because subnet_seed.dart:110 clamps the prefix to >=24 first,
      // so a /24 exactly meets the cap. This test guards the getter's contract
      // against that clamp order ever being relaxed -- it is a guard on the
      // shape, not a reproduction of a reachable engine state.
      final DiscoveryResult r = DiscoveryResult(
        hosts: <LanHost>[LanHost(ip: '10.0.0.200')],
        subnetLabel: '10.0.0.1-10.0.0.254',
        sweptIps: const <String>['10.0.0.1', '10.0.0.2'],
      );
      expect(r.hostsOutsideSweep.single.ip, '10.0.0.200');
    });
  });

  group('the engine RECORDS what it probed (sweptIps wiring)', () {
    // WHY THIS GROUP EXISTS. sweptIps is what lets the screen say "Swept
    // <range>" and then honestly flag hosts that came from mDNS/ARP outside it.
    // Every OTHER test builds a DiscoveryResult by hand with an explicit
    // sweptIps:, so deleting the real wiring in the engine left all 80 tests
    // green. That gap is worse than ordinary missing coverage: sweptIps empty
    // means "unknown", which by design suppresses the caveat -- so a regression
    // in ONE line silently restores the original defect (a stated range with
    // out-of-range hosts printed under it and no explanation) while every test
    // still passes. These tests drive the REAL engine.
    //
    // Mutation-tested: deleting `sweptIps: seed.hosts` on the success path or
    // on the connect-scan-failure path turns exactly one test here red.

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

    test('success path: records the probed set, and an mDNS host outside it is '
        'reported AND flagged as outside', () async {
      // /29 over 10.0.0.1 → probes 10.0.0.1-10.0.0.6. The mDNS fake announces
      // 10.0.99.7, which is real, wanted, and was never probed.
      final LanDiscoveryEngine engine = LanDiscoveryEngine(
        runInIsolate: false,
        seedDeriver: _seedDeriver(ip: '10.0.0.1', mask: '255.255.255.248'),
        mdnsBrowser: _fakeMdnsBrowser(
          serviceTypes: const <String>['_http._tcp'],
          byType: const <String, List<MdnsDiscoveryEvent>>{
            '_http._tcp': <MdnsDiscoveryEvent>[
              MdnsDiscoveryEvent(
                serviceType: '_http._tcp',
                name: 'Stray',
                hostAddresses: <String>['10.0.99.7'],
              ),
            ],
          },
        ),
        multicastLock: const NoopMulticastLock(),
        reverseDns: (String ip) async => null,
        ports: const <int>[80],
        connector: (String host, int port, Duration timeout) => Socket.connect(
            InternetAddress.loopbackIPv4, livePort,
            timeout: timeout),
      );

      await engine.run().toList();
      final DiscoveryResult r = engine.lastResult!;

      // The engine recorded the addresses it actually probed.
      expect(r.sweptIps, <String>[
        '10.0.0.1',
        '10.0.0.2',
        '10.0.0.3',
        '10.0.0.4',
        '10.0.0.5',
        '10.0.0.6',
      ]);

      // Capability intact: the out-of-range host is still reported.
      expect(r.hosts.map((LanHost h) => h.ip), contains('10.0.99.7'));

      // Honesty: and it is flagged as outside the sweep, which is the whole
      // point of recording sweptIps.
      expect(
        r.hostsOutsideSweep.map((LanHost h) => h.ip),
        <String>['10.0.99.7'],
      );
    });

    test('success path: an all-in-range run flags nobody', () async {
      final LanDiscoveryEngine engine = LanDiscoveryEngine(
        runInIsolate: false,
        seedDeriver: _seedDeriver(ip: '10.0.0.1', mask: '255.255.255.252'),
        mdnsBrowser: _silentMdnsBrowser(),
        multicastLock: const NoopMulticastLock(),
        reverseDns: (String ip) async => null,
        ports: const <int>[80],
        connector: (String host, int port, Duration timeout) => Socket.connect(
            InternetAddress.loopbackIPv4, livePort,
            timeout: timeout),
      );

      await engine.run().toList();
      final DiscoveryResult r = engine.lastResult!;

      expect(r.sweptIps, isNotEmpty);
      expect(r.hosts, isNotEmpty);
      expect(r.hostsOutsideSweep, isEmpty);
    });

    test('connect-scan failure path: still records what it MEANT to probe',
        () async {
      // A failed run reports no hosts, so nothing can be flagged -- but the
      // result must still carry the sweep it attempted rather than silently
      // reporting "unknown".
      final LanDiscoveryEngine engine = LanDiscoveryEngine(
        runInIsolate: false,
        seedDeriver: _seedDeriver(ip: '10.0.0.1', mask: '255.255.255.252'),
        mdnsBrowser: _silentMdnsBrowser(),
        multicastLock: const NoopMulticastLock(),
        reverseDns: (String ip) async => null,
        ports: const <int>[80],
        scanRunner: (ConnectScanRequest request) =>
            Future<List<HostPorts>>.error(StateError('scan blew up')),
      );

      await engine.run().toList();
      final DiscoveryResult r = engine.lastResult!;

      expect(r.error, contains('Connect-scan failed'));
      expect(r.sweptIps, <String>['10.0.0.1', '10.0.0.2']);
    });
  });
}
