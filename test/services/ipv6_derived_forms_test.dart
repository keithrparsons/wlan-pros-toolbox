// Solicited-node multicast and ip6.arpa, tested against the RFCs' OWN worked
// examples rather than against examples I chose.
//
// That distinction is the whole value here. An example I invent tests that the
// code agrees with my reading of the spec. An example printed inside the spec
// tests that the code agrees with the spec.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ipv6_address.dart';

void main() {
  group('solicited-node multicast, RFC 4291 s2.7.1', () {
    test("the RFC's own worked example", () {
      // RFC 4291 s2.7.1 gives 4037::01:800:200E:8C6C -> FF02::1:FF0E:8C6C.
      expect(
        Ipv6Address.solicitedNodeMulticast('4037::01:800:200E:8C6C'),
        'ff02::1:ff0e:8c6c',
      );
    });

    test('only the low 24 bits matter, which is the rule stated as a test', () {
      // Two addresses in different /64s sharing their last 24 bits MUST map to
      // the same group. This is why the group is a useful filter and not a
      // unique identifier.
      final String? a =
          Ipv6Address.solicitedNodeMulticast('2001:db8:1::aa:bbcc');
      final String? b =
          Ipv6Address.solicitedNodeMulticast('fe80::9999:9999:aa:bbcc');
      expect(a, b);
      expect(a, 'ff02::1:ffaa:bbcc');
    });

    test('an address whose low 24 bits are zero still lands in the prefix', () {
      expect(
        Ipv6Address.solicitedNodeMulticast('2001:db8::'),
        'ff02::1:ff00:0',
      );
    });

    test('a link-local built from a modified EUI-64 maps correctly', () {
      // fe80::021a:2bff:fe3c:4d5e is the SLAAC address for MAC 00:1a:2b:3c:4d:5e.
      // Low 24 bits are 3c:4d:5e.
      expect(
        Ipv6Address.solicitedNodeMulticast('fe80::021a:2bff:fe3c:4d5e'),
        'ff02::1:ff3c:4d5e',
      );
    });

    test('garbage returns null rather than a plausible-looking address', () {
      expect(Ipv6Address.solicitedNodeMulticast('not-an-address'), isNull);
      expect(Ipv6Address.solicitedNodeMulticast('2001:db8::zzzz'), isNull);
      expect(Ipv6Address.solicitedNodeMulticast(''), isNull);
    });
  });

  group('ip6.arpa reverse name, RFC 3596 s2.5', () {
    test("the RFC's own worked example, all 32 nibbles", () {
      // RFC 3596 s2.5: 4321:0:1:2:3:4:567:89ab reverses to
      // b.a.9.8.7.6.5.0.4.0.0.0.3.0.0.0.2.0.0.0.1.0.0.0.0.0.0.0.1.2.3.4.IP6.ARPA
      expect(
        Ipv6Address.toIp6Arpa('4321:0:1:2:3:4:567:89ab'),
        'b.a.9.8.7.6.5.0.4.0.0.0.3.0.0.0.2.0.0.0.1.0.0.0.0.0.0.0.1.2.3.4.'
            'ip6.arpa',
      );
    });

    test('a compressed address expands before reversing', () {
      // The all-zeros address is 32 zero nibbles. If :: were not expanded first
      // this would come back far too short, which is the classic bug here.
      final String? arpa = Ipv6Address.toIp6Arpa('::');
      expect(arpa, '${'0.' * 32}ip6.arpa');
      expect(arpa!.split('.').length, 34, reason: '32 nibbles + ip6 + arpa');
    });

    test('every address produces exactly 32 nibbles', () {
      for (final String a in <String>[
        '::1',
        '2001:db8::1',
        'fe80::021a:2bff:fe3c:4d5e',
        'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff',
      ]) {
        final String? arpa = Ipv6Address.toIp6Arpa(a);
        expect(arpa, isNotNull, reason: a);
        expect(arpa!.split('.').length, 34, reason: a);
      }
    });

    test('no trailing dot, because a UI is not a zone file', () {
      expect(Ipv6Address.toIp6Arpa('::1')!.endsWith('ip6.arpa'), isTrue);
      expect(Ipv6Address.toIp6Arpa('::1')!.endsWith('.'), isFalse);
    });

    test('garbage returns null', () {
      expect(Ipv6Address.toIp6Arpa('192.0.2.1'), isNull);
      expect(Ipv6Address.toIp6Arpa('2001:db8::zzzz'), isNull);
    });
  });
}
