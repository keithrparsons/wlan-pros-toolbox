// BLIND REFERENCE VECTORS vs the shipped IPv4 subnet calculator. 2026-09-17.
//
// Derived by Pax from the RFCs without sight of this repository. Brief:
//   Deliverables/2026-09-17-addressing-blind-vectors/VECTORS.md section 3
//
// The traps here are the ones a "2^(32-n) - 2" implementation gets wrong: /31
// prints 0 usable, /32 prints -1, /0 overflows a signed accumulator, and /1
// lands exactly on the signed 32-bit boundary.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/subnet_calc_service.dart';

const SubnetCalcService _svc = SubnetCalcService();

SubnetResult _calc(String addr, int prefix) =>
    _svc.calculate(address: addr, prefix: prefix);

void main() {
  group('A7/A8 the /31, RFC 3021 s2.1', () {
    test('both addresses are hosts, from either end of the pair', () {
      for (final String a in <String>['198.51.100.4', '198.51.100.5']) {
        final SubnetResult r = _calc(a, 31);
        expect(r.isValid, isTrue, reason: r.error);
        expect(r.usableHosts, 2,
            reason: 'a 2^(32-n)-2 implementation returns 0 here, and RFC 3021 '
                's2.1 says the two addresses MUST be interpreted as hosts');
        expect(r.totalAddresses, 2);
        expect(r.dottedMask, '255.255.255.254');
        expect(r.wildcardMask, '0.0.0.1');
        expect(r.firstHost, '198.51.100.4');
        expect(r.lastHost, '198.51.100.5');
      }
    });

    test('a /31 has no directed broadcast, RFC 3021 s2.2', () {
      final SubnetResult r = _calc('198.51.100.4', 31);
      expect(r.broadcastAddress, anyOf(isNull, 'N/A', ''),
          reason: 'got "${r.broadcastAddress}"');
    });
  });

  group('A9/A10 the /32', () {
    test('a single host route, never -1 and never 0 usable', () {
      final SubnetResult r = _calc('203.0.113.7', 32);
      expect(r.isValid, isTrue, reason: r.error);
      expect(r.totalAddresses, 1);
      expect(r.usableHosts, 1, reason: '2^0 - 2 returns -1 here');
      expect(r.dottedMask, '255.255.255.255');
      expect(r.wildcardMask, '0.0.0.0');
      expect(r.networkAddress, '203.0.113.7');
      expect(r.firstHost, '203.0.113.7');
      expect(r.lastHost, '203.0.113.7');
    });

    test('255.255.255.255/32 does not overflow a signed accumulator', () {
      final SubnetResult r = _calc('255.255.255.255', 32);
      expect(r.isValid, isTrue, reason: r.error);
      expect(r.networkAddress, '255.255.255.255');
      expect(r.usableHosts, 1);
    });
  });

  group('A11/A12 /0 and /1, where the count overflows or misleads', () {
    test('/0 counts 2^32 exactly', () {
      final SubnetResult r = _calc('0.0.0.0', 0);
      expect(r.isValid, isTrue, reason: r.error);
      expect(r.totalAddresses, 4294967296,
          reason: 'a signed 32-bit accumulator wraps this to 0');
      expect(r.usableHosts, 4294967294);
      expect(r.dottedMask, '0.0.0.0');
      expect(r.wildcardMask, '255.255.255.255');
      expect(r.networkAddress, '0.0.0.0');
      expect(r.broadcastAddress, '255.255.255.255');
    });

    test('/1 sits exactly on the signed 32-bit boundary', () {
      final SubnetResult r = _calc('128.0.0.0', 1);
      expect(r.isValid, isTrue, reason: r.error);
      expect(r.totalAddresses, 2147483648,
          reason: 'a signed int wraps 2^31 to -2147483648');
      expect(r.usableHosts, 2147483646);
      expect(r.dottedMask, '128.0.0.0');
      expect(r.wildcardMask, '127.255.255.255');
      expect(r.broadcastAddress, '255.255.255.255');
    });
  });

  group('A13-A16 non-contiguous masks are refused', () {
    // RFC 4632 s5.1 constrains route advertisement rather than calculators, and
    // RFC 950 s2.1 explicitly permits non-contiguous subnet bits. So refusing
    // is Pax's judgment call, marked [J] in the brief, and it is the right one:
    // answering a question whose premise is broken teaches the premise.
    for (final String m in <String>[
      '255.255.0.255',
      '255.0.255.0',
      '0.255.255.255',
      '255.255.255.253', // 253 = 11111101, a one-bit hole
    ]) {
      test('mask $m', () {
        final SubnetResult r = _svc.calculate(address: '192.0.2.1', mask: m);
        expect(r.isValid, isFalse, reason: 'accepted a non-contiguous mask');
        expect(r.error, isNotNull);
      });
    }
  });

  group('A17-A20 malformed input is refused', () {
    test('/33 and /-1 are outside RFC 4632 s3.1', () {
      expect(_calc('192.0.2.1', 33).isValid, isFalse);
      expect(_calc('192.0.2.1', -1).isValid, isFalse);
    });

    test('an octet above 255 is refused, RFC 791 s3.1', () {
      expect(_calc('192.0.2.256', 24).isValid, isFalse);
    });

    test('three-octet shorthand is refused rather than guessed at', () {
      // inet_aton would read 192.0.2 as 192.0.0.2. A calculator should not
      // pick one of two historical readings on the user's behalf.
      expect(_calc('192.0.2', 24).isValid, isFalse);
    });
  });
}
