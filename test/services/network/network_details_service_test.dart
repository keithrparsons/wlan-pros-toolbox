// NetworkDetailsService — unit tests for the local-addressing reader (Keith #5).
//
// The NetworkInfo plugin and the interface lister are faked so no platform
// channel or live interface list is touched. Tests assert the obtainable fields
// (local IP / subnet / gateway) flow through, the local-IP fallback to the
// interface list works, a failed read produces honest nulls (never fabricated),
// and the structurally-unavailable fields (DHCP / DNS server / VLAN) stay null
// with the documented honest reasons (GL-005 / GL-008).

import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/services/network/network_details_service.dart';

/// A fake NetworkInfo whose Wi-Fi addressing getters return controlled values
/// (or throw, to exercise the swallow-to-null path). `NetworkInfo` has only a
/// factory constructor so it is `implement`ed (with a noSuchMethod catch-all);
/// only the three getters the service uses are overridden. No platform channel.
class _FakeNetworkInfo implements NetworkInfo {
  _FakeNetworkInfo({this.ip, this.submask, this.gateway, this.throwAll = false});

  final String? ip;
  final String? submask;
  final String? gateway;
  final bool throwAll;

  @override
  Future<String?> getWifiIP() async {
    if (throwAll) throw Exception('denied');
    return ip;
  }

  @override
  Future<String?> getWifiSubmask() async {
    if (throwAll) throw Exception('denied');
    return submask;
  }

  @override
  Future<String?> getWifiGatewayIP() async {
    if (throwAll) throw Exception('denied');
    return gateway;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('NetworkDetailsService', () {
    test('passes the obtainable IP / subnet / gateway through', () async {
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(
          ip: '192.168.1.42',
          submask: '255.255.255.0',
          gateway: '192.168.1.1',
        ),
        interfaceLister: () async => const [],
      );

      final NetworkDetails d = await service.read();

      expect(d.localIp, '192.168.1.42');
      expect(d.subnetMask, '255.255.255.0');
      expect(d.gateway, '192.168.1.1');
    });

    test('a null subnet / gateway stays null — honest, never fabricated',
        () async {
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(ip: '10.0.0.5'),
        interfaceLister: () async => const [],
      );

      final NetworkDetails d = await service.read();

      expect(d.localIp, '10.0.0.5');
      expect(d.subnetMask, isNull);
      expect(d.gateway, isNull);
    });

    test('a thrown plugin call swallows to honest nulls, never throws',
        () async {
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(throwAll: true),
        interfaceLister: () async => const [],
      );

      final NetworkDetails d = await service.read();

      expect(d.localIp, isNull);
      expect(d.subnetMask, isNull);
      expect(d.gateway, isNull);
    });

    test('DHCP server, DNS server(s) and VLAN are always unavailable with the '
        'honest documented reasons (GL-005)', () async {
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(ip: '192.168.1.42'),
        interfaceLister: () async => const [],
      );

      final NetworkDetails d = await service.read();

      expect(d.dhcpServer, isNull);
      expect(d.dnsServers, isEmpty);
      expect(d.vlanTag, isNull);
      expect(NetworkDetails.dhcpReason, 'Not available on this device');
      expect(NetworkDetails.dnsReason, 'Not available on this device');
      expect(NetworkDetails.vlanReason, 'Not visible to endpoint devices');
    });
  });
}
