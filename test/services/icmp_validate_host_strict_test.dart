// IcmpService.validateHost — now delegates to the shared NetworkTarget
// validator, so the ICMP Ping and Mobile Traceroute screens reject the SAME
// malformed input every other host/IP tool rejects. Before this wiring the
// check was "intentionally permissive" and SILENTLY accepted an out-of-range
// octet or a pasted URL — the 2026-07-14 "thought the tool was broke" report.
//
// RED before the delegation (the loose check returned null → accepted); GREEN
// after. Pure Dart: no sockets.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/icmp_service.dart';

void main() {
  group('IcmpService.validateHost — strict, shared rules', () {
    test('valid hosts and IPs still pass (return null)', () {
      for (final String s in <String>[
        'example.com',
        '1.1.1.1',
        '  8.8.8.8  ', // trims
        '::1',
        'fe80::1%en0',
      ]) {
        expect(IcmpService.validateHost(s), isNull, reason: s);
      }
    });

    test('malformed typos are now rejected (return a message)', () {
      for (final String s in <String>[
        '192.168.1.256', // out-of-range octet
        '192.168..1', // empty octet
        'http://host', // pasted scheme
        '1.2.3', // too few octets
        '256.256.256.256',
        '12345', // bare number, not a host
      ]) {
        expect(IcmpService.validateHost(s), isNotNull, reason: s);
      }
    });

    test('empty and whitespace-only are rejected', () {
      expect(IcmpService.validateHost(''), isNotNull);
      expect(IcmpService.validateHost('   '), isNotNull);
    });
  });
}
