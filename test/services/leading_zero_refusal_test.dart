// A LEADING ZERO IS REFUSED, NOT READ. Keith, 2026-09-17: "refuse the leading
// zero."
//
// THE MEASUREMENT THAT PROMPTED IT, taken on this machine:
//
//   subnet calculator (before)   192.0.2.010/32  ->  192.0.2.10
//   inet_aton / ping             192.0.2.010     ->  192.0.2.8
//
// inet_aton reads a leading zero as octal. Our Ping tool resolves through
// InternetAddress.lookup (ping_service.dart:206), which goes to the OS, so the
// SAME APP answered one string two ways with nothing on screen to show it.
//
// Refusing is the only answer that cannot be wrong, and it is what this parser
// already did with three-octet shorthand.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/subnet_calc_service.dart';

const SubnetCalcService _svc = SubnetCalcService();

void main() {
  group('the octal-ambiguous forms are refused', () {
    for (final String addr in <String>[
      '192.0.2.010', // the measured case: .8 to the OS, .10 to us
      '192.0.2.01',
      '10.0.0.07',
      '010.0.0.1', // first octet
      '192.00.2.1', // 00 is still a leading zero
    ]) {
      test(addr, () {
        final SubnetResult r = _svc.calculate(address: addr, prefix: 24);
        expect(r.isValid, isFalse, reason: 'accepted $addr');
        expect(r.error, isNotNull);
      });
    }
  });

  group('the refusal explains itself, because the input LOOKS valid', () {
    test('it names the octet and what to write instead', () {
      final SubnetResult r = _svc.calculate(address: '192.0.2.010', prefix: 24);
      expect(r.error, contains('010'));
      expect(r.error, contains('octal'));
      expect(r.error, contains('10'));
      // A bare "invalid address" on a string the user believes is fine teaches
      // nothing and reads as a bug in us.
      expect(r.error, isNot(contains('Four octets')));
    });

    test('other rejections keep the generic message', () {
      final SubnetResult r = _svc.calculate(address: '192.0.2.999', prefix: 24);
      expect(r.error, contains('Four octets'));
      expect(r.error, isNot(contains('octal')));
    });
  });

  group('a bare zero is not a leading zero', () {
    test('0.0.0.0/0 still works, and so does every ordinary address', () {
      expect(_svc.calculate(address: '0.0.0.0', prefix: 0).isValid, isTrue);
      expect(_svc.calculate(address: '10.0.0.0', prefix: 8).isValid, isTrue);
      expect(_svc.calculate(address: '192.0.2.0', prefix: 24).isValid, isTrue);
      expect(_svc.calculate(address: '255.255.255.255', prefix: 32).isValid,
          isTrue);
    });

    test('the predicate itself', () {
      expect(SubnetCalcService.hasLeadingZeroOctet('0'), isFalse);
      expect(SubnetCalcService.hasLeadingZeroOctet('10'), isFalse);
      expect(SubnetCalcService.hasLeadingZeroOctet('01'), isTrue);
      expect(SubnetCalcService.hasLeadingZeroOctet('00'), isTrue);
    });
  });
}
