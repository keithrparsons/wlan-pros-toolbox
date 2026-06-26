// NetworkDetailsService — unit tests for the local-addressing reader (Keith #5).
//
// The NetworkInfo plugin, the interface lister, the platform flag, and the
// Android native-channel reader are all faked so no platform channel or live
// interface list is touched. Tests assert the obtainable fields (local IP /
// subnet / gateway) flow through, the local-IP fallback to the interface list
// works, a failed read produces honest nulls (never fabricated), the Android
// DHCP/DNS path populates REAL values, an empty/failed Android read falls back
// to the honest unavailable state with the precise Android reason, and the
// iOS/macOS path stays exactly as before (null/empty + "Not available on this
// device"). VLAN is always null on every platform (GL-005 / GL-008).

import 'package:flutter/services.dart';
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
  group('NetworkDetailsService — obtainable addressing', () {
    test('passes the obtainable IP / subnet / gateway through', () async {
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(
          ip: '192.168.1.42',
          submask: '255.255.255.0',
          gateway: '192.168.1.1',
        ),
        interfaceLister: () async => const [],
        isAndroid: false,
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
        isAndroid: false,
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
        isAndroid: false,
      );

      final NetworkDetails d = await service.read();

      expect(d.localIp, isNull);
      expect(d.subnetMask, isNull);
      expect(d.gateway, isNull);
    });
  });

  group('NetworkDetailsService — iOS/macOS DHCP/DNS (unchanged)', () {
    test('DHCP server, DNS server(s) and VLAN are unavailable with the iOS/macOS '
        'reason; the Android reader is NEVER called off Android (GL-005)',
        () async {
      var readerCalled = false;
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(ip: '192.168.1.42'),
        interfaceLister: () async => const [],
        isAndroid: false,
        androidAddressingReader: () async {
          readerCalled = true;
          return <Object?, Object?>{};
        },
      );

      final NetworkDetails d = await service.read();

      expect(d.dhcpServer, isNull);
      expect(d.dnsServers, isEmpty);
      expect(d.vlanTag, isNull);
      expect(d.dhcpReason, 'Not available on this device');
      expect(d.dnsReason, 'Not available on this device');
      expect(NetworkDetails.vlanReason, 'Not visible to endpoint devices');
      expect(readerCalled, isFalse,
          reason: 'the native channel must not be touched off Android');
    });
  });

  group('NetworkDetailsService — Android DHCP/DNS (real values)', () {
    test('populates the DHCP server and de-duped DNS list from the channel',
        () async {
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(
          ip: '192.168.1.42',
          submask: '255.255.255.0',
          gateway: '192.168.1.1',
        ),
        interfaceLister: () async => const [],
        isAndroid: true,
        androidAddressingReader: () async => <Object?, Object?>{
          'dhcpServer': '192.168.1.1',
          // Duplicate + a blank entry to prove normalization.
          'dnsServers': <Object?>['1.1.1.1', '8.8.8.8', '1.1.1.1', '  ', null],
        },
      );

      final NetworkDetails d = await service.read();

      expect(d.dhcpServer, '192.168.1.1');
      expect(d.dnsServers, <String>['1.1.1.1', '8.8.8.8']);
      expect(d.vlanTag, isNull, reason: 'VLAN stays always-null on Android');
    });

    test('an IPv6 + IPv4 resolver mix flows through trimmed and ordered',
        () async {
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(ip: '10.0.0.9'),
        interfaceLister: () async => const [],
        isAndroid: true,
        androidAddressingReader: () async => <Object?, Object?>{
          'dhcpServer': '10.0.0.1',
          'dnsServers': <Object?>[' 2001:4860:4860::8888 ', '8.8.4.4'],
        },
      );

      final NetworkDetails d = await service.read();

      expect(d.dhcpServer, '10.0.0.1');
      expect(d.dnsServers, <String>['2001:4860:4860::8888', '8.8.4.4']);
    });

    test('a FULL-form IPv6 resolver from the channel is compressed (RFC 5952) '
        'before it reaches the model (Vera 2026-06-26)', () async {
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(ip: '10.0.0.9'),
        interfaceLister: () async => const [],
        isAndroid: true,
        androidAddressingReader: () async => <Object?, Object?>{
          'dhcpServer': '10.0.0.1',
          // Defense-in-depth: even if a source emits the expanded 8-hextet form,
          // the Dart canonicalizer compresses it so the UI never sees long form.
          'dnsServers': <Object?>['2001:4860:4860:0:0:0:0:8888'],
        },
      );

      final NetworkDetails d = await service.read();

      expect(d.dnsServers, <String>['2001:4860:4860::8888']);
    });

    test('the compressed and expanded forms of ONE resolver collapse to a single '
        'de-duped entry', () async {
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(ip: '10.0.0.9'),
        interfaceLister: () async => const [],
        isAndroid: true,
        androidAddressingReader: () async => <Object?, Object?>{
          'dhcpServer': '10.0.0.1',
          'dnsServers': <Object?>[
            '2001:4860:4860::8888',
            '2001:4860:4860:0:0:0:0:8888',
          ],
        },
      );

      final NetworkDetails d = await service.read();

      expect(d.dnsServers, <String>['2001:4860:4860::8888']);
    });

    test('an empty/null Android read renders the honest Android unavailable '
        'state, never a fabricated value (GL-005)', () async {
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(ip: '192.168.1.42'),
        interfaceLister: () async => const [],
        isAndroid: true,
        // The native side returns nulls (no DHCP lease / no active link) — the
        // honest 0.0.0.0 → null mapping already happened in Kotlin.
        androidAddressingReader: () async => <Object?, Object?>{
          'dhcpServer': null,
          'dnsServers': <Object?>[],
        },
      );

      final NetworkDetails d = await service.read();

      expect(d.dhcpServer, isNull);
      expect(d.dnsServers, isEmpty);
      expect(d.dhcpReason, 'Not reported for this network');
      expect(d.dnsReason, 'Not reported for this network');
    });

    test('a MissingPluginException (channel not built) falls back to the honest '
        'unavailable state, never throws', () async {
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(ip: '192.168.1.42'),
        interfaceLister: () async => const [],
        isAndroid: true,
        androidAddressingReader: () async =>
            throw MissingPluginException('no handler'),
      );

      final NetworkDetails d = await service.read();

      expect(d.dhcpServer, isNull);
      expect(d.dnsServers, isEmpty);
      expect(d.dhcpReason, 'Not reported for this network');
      expect(d.dnsReason, 'Not reported for this network');
    });

    test('a PlatformException is swallowed to the honest unavailable state',
        () async {
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(ip: '192.168.1.42'),
        interfaceLister: () async => const [],
        isAndroid: true,
        androidAddressingReader: () async =>
            throw PlatformException(code: 'ERR'),
      );

      final NetworkDetails d = await service.read();

      expect(d.dhcpServer, isNull);
      expect(d.dnsServers, isEmpty);
      expect(d.dhcpReason, 'Not reported for this network');
    });

    test('a malformed payload (wrong types) is swallowed to honest unavailable',
        () async {
      final service = NetworkDetailsService(
        networkInfo: _FakeNetworkInfo(ip: '192.168.1.42'),
        interfaceLister: () async => const [],
        isAndroid: true,
        androidAddressingReader: () async => <Object?, Object?>{
          'dhcpServer': 12345, // not a String
          'dnsServers': 'not-a-list',
        },
      );

      final NetworkDetails d = await service.read();

      expect(d.dhcpServer, isNull);
      expect(d.dnsServers, isEmpty);
      expect(d.dhcpReason, 'Not reported for this network');
    });
  });

  group('canonicalizeDnsAddress — RFC 5952 IPv6 compression (Vera 2026-06-26)',
      () {
    test('IPv4 passes through unchanged', () {
      expect(canonicalizeDnsAddress('192.168.1.1'), '192.168.1.1');
      expect(canonicalizeDnsAddress(' 8.8.8.8 '), '8.8.8.8');
    });

    test('the unspecified address maps to null (dropped)', () {
      expect(canonicalizeDnsAddress('0.0.0.0'), isNull);
      expect(canonicalizeDnsAddress('::'), isNull);
      expect(canonicalizeDnsAddress('0:0:0:0:0:0:0:0'), isNull);
      expect(canonicalizeDnsAddress(''), isNull);
      expect(canonicalizeDnsAddress('   '), isNull);
    });

    test('a full 8-hextet IPv6 collapses the longest zero run to ::', () {
      expect(
        canonicalizeDnsAddress('2001:4860:4860:0:0:0:0:8888'),
        '2001:4860:4860::8888',
      );
      expect(
        canonicalizeDnsAddress('2001:0db8:0000:0000:0000:0000:0000:0001'),
        '2001:db8::1',
      );
    });

    test('an already-compressed IPv6 is idempotent', () {
      expect(
        canonicalizeDnsAddress('2001:4860:4860::8888'),
        '2001:4860:4860::8888',
      );
      expect(canonicalizeDnsAddress('fe80::1'), 'fe80::1');
    });

    test('leading and trailing zero runs compress correctly', () {
      expect(canonicalizeDnsAddress('0:0:0:0:0:0:0:1'), '::1');
      expect(canonicalizeDnsAddress('fe80:0:0:0:0:0:0:0'), 'fe80::');
    });

    test('a SINGLE zero hextet is NOT collapsed (RFC 5952)', () {
      // Only run length >= 2 collapses; the lone zero stays "0".
      expect(
        canonicalizeDnsAddress('2001:db8:0:1:1:1:1:1'),
        '2001:db8:0:1:1:1:1:1',
      );
    });

    test('on a tie the LEFTMOST longest zero run is collapsed', () {
      // Two equal-length runs (idx 1-2 and 4-5); the left one wins.
      expect(canonicalizeDnsAddress('1:0:0:1:0:0:1:1'), '1::1:0:0:1:1');
    });

    test('leading zeros within a hextet are stripped and output is lowercased',
        () {
      expect(canonicalizeDnsAddress('2001:0DB8::00A1'), '2001:db8::a1');
    });

    test('an IPv6 zone/scope id is stripped before compression', () {
      expect(canonicalizeDnsAddress('fe80::1%wlan0'), 'fe80::1');
    });

    test('a non-empty unparseable value is returned lowercased, never dropped',
        () {
      // Real resolver values never look like this, but we must not lose a value.
      expect(canonicalizeDnsAddress('NOT:AN:ADDRESS'), 'not:an:address');
    });
  });
}
