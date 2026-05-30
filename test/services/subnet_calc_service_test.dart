// SubnetCalcService unit tests — known-good vectors per prefix, the /31 (RFC
// 3021) and /32 edge cases, mask ⇄ prefix round-trips, and malformed-input
// rejection. Pure math, no I/O.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/subnet_calc_service.dart';

void main() {
  const SubnetCalcService svc = SubnetCalcService();

  group('standard prefixes', () {
    test('/22 — host inside the block reports the base network', () {
      final SubnetResult r = svc.calculate(address: '10.20.0.37', prefix: 22);
      expect(r.isValid, isTrue);
      expect(r.networkAddress, '10.20.0.0');
      expect(r.broadcastAddress, '10.20.3.255');
      expect(r.dottedMask, '255.255.252.0');
      expect(r.wildcardMask, '0.0.3.255');
      expect(r.firstHost, '10.20.0.1');
      expect(r.lastHost, '10.20.3.254');
      expect(r.totalAddresses, 1024);
      expect(r.usableHosts, 1022);
    });

    test('/24 — classic 256/254 split', () {
      final SubnetResult r = svc.calculate(address: '192.168.1.10', prefix: 24);
      expect(r.networkAddress, '192.168.1.0');
      expect(r.broadcastAddress, '192.168.1.255');
      expect(r.firstHost, '192.168.1.1');
      expect(r.lastHost, '192.168.1.254');
      expect(r.totalAddresses, 256);
      expect(r.usableHosts, 254);
    });

    test('/30 — point-to-point pair with reserved net/broadcast', () {
      final SubnetResult r = svc.calculate(address: '192.0.2.1', prefix: 30);
      expect(r.networkAddress, '192.0.2.0');
      expect(r.broadcastAddress, '192.0.2.3');
      expect(r.firstHost, '192.0.2.1');
      expect(r.lastHost, '192.0.2.2');
      expect(r.totalAddresses, 4);
      expect(r.usableHosts, 2);
    });

    test('/0 — whole space, 2^32 total', () {
      final SubnetResult r = svc.calculate(address: '8.8.8.8', prefix: 0);
      expect(r.networkAddress, '0.0.0.0');
      expect(r.broadcastAddress, '255.255.255.255');
      expect(r.dottedMask, '0.0.0.0');
      expect(r.totalAddresses, 4294967296);
      expect(r.usableHosts, 4294967294);
    });
  });

  group('edge cases /31 and /32', () {
    test('/31 — RFC 3021: both addresses usable, no broadcast', () {
      final SubnetResult r = svc.calculate(address: '10.0.0.4', prefix: 31);
      expect(r.networkAddress, '10.0.0.4');
      expect(r.broadcastAddress, isNull);
      expect(r.firstHost, '10.0.0.4');
      expect(r.lastHost, '10.0.0.5');
      expect(r.totalAddresses, 2);
      expect(r.usableHosts, 2);
    });

    test('/32 — single host, first == last == the address, no broadcast', () {
      final SubnetResult r = svc.calculate(address: '10.0.0.9', prefix: 32);
      expect(r.networkAddress, '10.0.0.9');
      expect(r.broadcastAddress, isNull);
      expect(r.firstHost, '10.0.0.9');
      expect(r.lastHost, '10.0.0.9');
      expect(r.totalAddresses, 1);
      expect(r.usableHosts, 1);
    });
  });

  group('dotted mask input', () {
    test('mask 255.255.252.0 resolves to /22', () {
      final SubnetResult r =
          svc.calculate(address: '10.20.0.0', mask: '255.255.252.0');
      expect(r.isValid, isTrue);
      expect(r.prefix, 22);
      expect(r.broadcastAddress, '10.20.3.255');
    });

    test('mask and prefix agree on the same network', () {
      final SubnetResult byMask =
          svc.calculate(address: '172.16.5.5', mask: '255.255.0.0');
      final SubnetResult byPrefix =
          svc.calculate(address: '172.16.5.5', prefix: 16);
      expect(byMask.networkAddress, byPrefix.networkAddress);
      expect(byMask.broadcastAddress, byPrefix.broadcastAddress);
    });

    test('non-contiguous mask is rejected', () {
      final SubnetResult r =
          svc.calculate(address: '10.0.0.0', mask: '255.0.255.0');
      expect(r.isValid, isFalse);
      expect(r.error, isNotNull);
    });
  });

  group('mask round-trips', () {
    test('prefixFromMask and maskForPrefix invert each other', () {
      for (int p = 0; p <= 32; p++) {
        final String mask = SubnetCalcService.maskForPrefix(p);
        expect(SubnetCalcService.prefixFromMask(mask), p, reason: '/\$p');
      }
    });

    test('known mask values', () {
      expect(SubnetCalcService.maskForPrefix(22), '255.255.252.0');
      expect(SubnetCalcService.maskForPrefix(24), '255.255.255.0');
      expect(SubnetCalcService.maskForPrefix(32), '255.255.255.255');
      expect(SubnetCalcService.maskForPrefix(0), '0.0.0.0');
      expect(SubnetCalcService.prefixFromMask('255.255.255.192'), 26);
    });
  });

  group('validation / malformed input', () {
    test('octet out of range is rejected', () {
      final SubnetResult r = svc.calculate(address: '10.20.300.0', prefix: 24);
      expect(r.isValid, isFalse);
      expect(r.error, contains('IPv4'));
    });

    test('too few octets is rejected', () {
      expect(svc.calculate(address: '10.20.0', prefix: 24).isValid, isFalse);
    });

    test('prefix out of range is rejected', () {
      expect(svc.calculate(address: '10.0.0.0', prefix: 33).isValid, isFalse);
      expect(svc.calculate(address: '10.0.0.0', prefix: -1).isValid, isFalse);
    });

    test('neither prefix nor mask is rejected', () {
      expect(svc.calculate(address: '10.0.0.0').isValid, isFalse);
    });

    test('both prefix and mask is rejected (ambiguous)', () {
      final SubnetResult r = svc.calculate(
        address: '10.0.0.0',
        prefix: 24,
        mask: '255.255.255.0',
      );
      expect(r.isValid, isFalse);
    });

    test('isValidIpv4 helper', () {
      expect(SubnetCalcService.isValidIpv4('255.255.255.255'), isTrue);
      expect(SubnetCalcService.isValidIpv4('256.0.0.0'), isFalse);
      expect(SubnetCalcService.isValidIpv4('1.2.3'), isFalse);
    });
  });

  group('subnetContains polish', () {
    test('host inside and outside the block', () {
      expect(
        svc.subnetContains(
            networkAddress: '10.20.0.0', prefix: 22, host: '10.20.3.200'),
        isTrue,
      );
      expect(
        svc.subnetContains(
            networkAddress: '10.20.0.0', prefix: 22, host: '10.20.4.1'),
        isFalse,
      );
    });
  });
}
