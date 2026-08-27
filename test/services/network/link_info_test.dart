// LinkInfo / LinkTable parsing.
//
// THE FIXTURE IS NOT INVENTED. `_wlanpiA02` is the verbatim body of
// GET /toolboxapi/links from Keith's WLAN Pi M4+ (`wlanpi-a02`, OS 3.4.4) on
// 2026-08-27, captured while eth0 and wlan0 were both up on 192.168.8.0/24. It
// is kept whole rather than trimmed to the assertions, because the shape of a
// real box is the thing under test: a Bluetooth bridge, two monitor interfaces,
// a down radio, a sentinel speed, and two live interfaces on one subnet where
// only one routes.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/link_info.dart';

const String _wlanpiA02 = '''
{
  "links": [
    {"name": "eth0", "kind": "wired", "operstate": "UP", "carrier": true,
     "speed_mbps": 1000, "duplex": "full", "mtu": 1500,
     "mac": "d8:3a:dd:95:9a:02", "driver": "bcmgenet", "bus": "platform",
     "is_default_route_v4": true, "is_default_route_v6": false,
     "addresses": [
       {"family": "inet", "address": "192.168.8.176", "prefixlen": 24,
        "scope": "global", "dynamic": true, "link_local": false},
       {"family": "inet6", "address": "fe80::da3a:ddff:fe95:9a02",
        "prefixlen": 64, "scope": "link", "dynamic": false, "link_local": true}
     ]},
    {"name": "lo", "kind": "loopback", "operstate": "UNKNOWN", "carrier": true,
     "speed_mbps": null, "duplex": null, "mtu": 65536,
     "mac": "00:00:00:00:00:00", "driver": null, "bus": "virtual",
     "is_default_route_v4": false, "is_default_route_v6": false,
     "addresses": [
       {"family": "inet", "address": "127.0.0.1", "prefixlen": 8,
        "scope": "host", "dynamic": false, "link_local": false}
     ]},
    {"name": "wlanpi0", "kind": "monitor", "operstate": "UNKNOWN",
     "carrier": true, "speed_mbps": null, "duplex": null, "mtu": 1500,
     "mac": "9c:ef:d5:f6:43:83", "driver": "mt7921u", "bus": "usb",
     "is_default_route_v4": false, "is_default_route_v6": false,
     "addresses": []},
    {"name": "wlanpi1", "kind": "monitor", "operstate": "UNKNOWN",
     "carrier": true, "speed_mbps": null, "duplex": null, "mtu": 1500,
     "mac": "44:38:e8:b2:a8:9a", "driver": "iwlwifi", "bus": "pci",
     "is_default_route_v4": false, "is_default_route_v6": false,
     "addresses": []},
    {"name": "pan0", "kind": "virtual", "operstate": "UNKNOWN", "carrier": true,
     "speed_mbps": -1, "duplex": "unknown", "mtu": 1500,
     "mac": "56:0b:81:5c:c6:e6", "driver": null, "bus": "virtual",
     "is_default_route_v4": false, "is_default_route_v6": false,
     "addresses": [
       {"family": "inet", "address": "169.254.43.1", "prefixlen": 24,
        "scope": "global", "dynamic": false, "link_local": true}
     ]},
    {"name": "wlan0", "kind": "wifi", "operstate": "UP", "carrier": true,
     "speed_mbps": null, "duplex": null, "mtu": 1500,
     "mac": "9c:ef:d5:f6:43:83", "driver": "mt7921u", "bus": "usb",
     "is_default_route_v4": false, "is_default_route_v6": false,
     "addresses": [
       {"family": "inet", "address": "192.168.8.152", "prefixlen": 24,
        "scope": "global", "dynamic": true, "link_local": false},
       {"family": "inet6", "address": "fe80::9eef:d5ff:fef6:4383",
        "prefixlen": 64, "scope": "link", "dynamic": false, "link_local": true}
     ]},
    {"name": "wlan1", "kind": "wifi", "operstate": "DOWN", "carrier": false,
     "speed_mbps": null, "duplex": null, "mtu": 1500,
     "mac": "44:38:e8:b2:a8:9a", "driver": "iwlwifi", "bus": "pci",
     "is_default_route_v4": false, "is_default_route_v6": false,
     "addresses": []}
  ],
  "default_route": {"inet": {"dev": "eth0", "gateway": "192.168.8.1"}},
  "source": "sysfs + ip addr on the WLAN Pi (no ethtool; it is not installed)"
}
''';

LinkTable _parse(String body) =>
    LinkTable.fromJson(jsonDecode(body) as Map<String, dynamic>);

void main() {
  group('LinkTable — the wlanpi-a02 reading, 2026-08-27', () {
    late LinkTable t;
    setUp(() => t = _parse(_wlanpiA02));

    test('parses every interface the box reported', () {
      expect(t.links.map((LinkInfo l) => l.name), <String>[
        'eth0', 'lo', 'wlanpi0', 'wlanpi1', 'pan0', 'wlan0', 'wlan1',
      ]);
    });

    test('THE POINT: two interfaces are up on one subnet and only eth0 routes',
        () {
      final LinkInfo wlan0 =
          t.links.firstWhere((LinkInfo l) => l.name == 'wlan0');
      expect(wlan0.operState, 'UP');
      expect(wlan0.firstRoutableIPv4, '192.168.8.152');
      expect(wlan0.isDefaultRoute, isFalse,
          reason: 'wlan0 is up and addressed but carries nothing');

      expect(t.primary?.name, 'eth0');
      expect(t.defaultRouteInterfaceV4, 'eth0');
      expect(t.defaultGatewayV4, '192.168.8.1');
    });

    test('the wired link reports what only a link table can report', () {
      final LinkInfo eth0 = t.primary!;
      expect(eth0.kind, LinkKind.wired);
      expect(eth0.speedMbps, 1000);
      expect(eth0.duplex, 'full');
      expect(eth0.carrier, isTrue);
      expect(eth0.driver, 'bcmgenet');
      expect(eth0.bus, 'platform');
      expect(eth0.firstRoutableIPv4, '192.168.8.176');
    });

    test('MONITOR INTERFACES ARE NOT CONNECTIONS. The name heuristic called '
        'these Wi-Fi', () {
      for (final String n in <String>['wlanpi0', 'wlanpi1']) {
        final LinkInfo l = t.links.firstWhere((LinkInfo x) => x.name == n);
        expect(l.kind, LinkKind.monitor, reason: n);
        expect(l.isUsable, isFalse, reason: n);
      }
      expect(t.usable.map((LinkInfo l) => l.name),
          <String>['eth0', 'wlan0', 'wlan1']);
    });

    test('pan0 is virtual, not wired: a Bluetooth bridge is not a cable', () {
      final LinkInfo pan0 = t.links.firstWhere((LinkInfo l) => l.name == 'pan0');
      expect(pan0.kind, LinkKind.virtual);
      expect(pan0.isUsable, isFalse);
      expect(pan0.driver, isNull, reason: 'a bridge has no driver');
    });

    test('a -1 speed is a sentinel and must never reach a UI', () {
      final LinkInfo pan0 = t.links.firstWhere((LinkInfo l) => l.name == 'pan0');
      expect(pan0.speedMbps, isNull);
      expect(pan0.duplex, isNull, reason: '"unknown" is not a duplex');
    });

    test('link-local addresses are flagged and never offered as THE address',
        () {
      final LinkInfo pan0 = t.links.firstWhere((LinkInfo l) => l.name == 'pan0');
      expect(pan0.addresses.single.isLinkLocal, isTrue);
      expect(pan0.firstRoutableIPv4, isNull);
      expect(pan0.hasOnlyLinkLocalIPv4, isTrue,
          reason: 'the link came up and DHCP never answered');

      final LinkInfo eth0 = t.primary!;
      expect(eth0.hasOnlyLinkLocalIPv4, isFalse);
      expect(eth0.addresses.firstWhere((LinkAddress a) => !a.isIPv4).isLinkLocal,
          isTrue,
          reason: 'fe80:: is link-local too, and eth0 has one');
      expect(eth0.addresses.first.isDynamic, isTrue, reason: 'DHCP assigned');
    });

    test('a down radio is DOWN with no carrier, not merely address-less', () {
      final LinkInfo wlan1 =
          t.links.firstWhere((LinkInfo l) => l.name == 'wlan1');
      expect(wlan1.operState, 'DOWN');
      expect(wlan1.carrier, isFalse);
      expect(wlan1.addresses, isEmpty);
    });

    test('the two radios sit on different buses, which the app could not see',
        () {
      expect(t.links.firstWhere((LinkInfo l) => l.name == 'wlan0').bus, 'usb');
      expect(t.links.firstWhere((LinkInfo l) => l.name == 'wlan1').bus, 'pci');
    });

    test('the source is stated in the reading, not assumed by the reader', () {
      expect(t.source, contains('sysfs'));
      expect(t.source, contains('no ethtool'));
    });
  });

  group('LinkTable — states the fixture cannot show', () {
    test('a usable link that routes nothing is named, not silently primary', () {
      final LinkTable t = _parse('''
        {"links": [
          {"name": "eth0", "kind": "wired", "operstate": "UP", "carrier": true,
           "is_default_route_v4": false, "is_default_route_v6": false,
           "addresses": [{"family": "inet", "address": "169.254.9.9",
                          "prefixlen": 16, "link_local": true}]}
        ], "default_route": null}
      ''');
      expect(t.primary, isNull);
      expect(t.hasLinkButNoRoute, isTrue);
      expect(t.links.single.hasOnlyLinkLocalIPv4, isTrue);
    });

    test('no usable links at all is a different state from no route', () {
      final LinkTable t = _parse(
          '{"links": [{"name": "lo", "kind": "loopback"}], "default_route": null}');
      expect(t.usable, isEmpty);
      expect(t.hasLinkButNoRoute, isFalse,
          reason: 'nothing is plugged in; that is not "plugged in, no route"');
    });

    test('IPv6-only routing still yields a primary', () {
      final LinkTable t = _parse('''
        {"links": [
          {"name": "eth0", "kind": "wired", "is_default_route_v4": false,
           "is_default_route_v6": true, "addresses": []}
        ], "default_route": {"inet6": {"dev": "eth0", "gateway": "fe80::1"}}}
      ''');
      expect(t.primary?.name, 'eth0');
      expect(t.defaultRouteInterfaceV6, 'eth0');
      expect(t.defaultGatewayV6, 'fe80::1');
      expect(t.defaultRouteInterfaceV4, isNull);
    });

    test('an unknown kind degrades to other and is not treated as usable', () {
      final LinkTable t =
          _parse('{"links": [{"name": "wwan0", "kind": "cellular-ish"}]}');
      expect(t.links.single.kind, LinkKind.other);
      expect(t.usable, isEmpty);
    });

    test('a nameless entry is dropped rather than rendered blank', () {
      final LinkTable t =
          _parse('{"links": [{"name": "", "kind": "wired"}, {"kind": "wired"}]}');
      expect(t.links, isEmpty);
    });

    test('an empty body parses to an empty table, never throws', () {
      final LinkTable t = _parse('{}');
      expect(t.links, isEmpty);
      expect(t.primary, isNull);
      expect(t.source, isNull);
    });
  });
}
