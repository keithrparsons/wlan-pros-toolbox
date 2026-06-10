// NetworkTarget unit tests — the security choke point for any user/response
// supplied host or IP. Covers the malicious cases the audit flagged:
//   - `-foo` / `--help` host (traceroute argument/flag injection)
//   - `refer: 169.254.169.254` / `127.0.0.1` (WHOIS referral SSRF)
// plus the valid hostnames/IPs that must keep passing.
//
// Pure-Dart: no sockets, no subprocess, no Flutter binding needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/network_target.dart';

void main() {
  group('validateHostOrIp — accepts valid targets', () {
    test('valid hostnames pass', () {
      for (final String h in <String>[
        'example.com',
        'whois.verisign-grs.com',
        'a.b.c.d.example.org',
        'xn--mnchen-3ya.de', // punycode IDN
        'localhost',
        'host-with-hyphen.example.com',
        'EXAMPLE.COM', // case preserved, still valid
        'example.com.', // trailing-dot FQDN
      ]) {
        expect(NetworkTarget.validateHostOrIp(h).isValid, isTrue, reason: h);
      }
    });

    test('valid IPv4 literals pass (including private — not blocked here)', () {
      for (final String ip in <String>[
        '8.8.8.8',
        '1.1.1.1',
        '192.168.1.1', // private is LEGITIMATE for traceroute
        '10.0.0.1',
        '127.0.0.1',
        '255.255.255.255',
        '0.0.0.0',
      ]) {
        expect(NetworkTarget.validateHostOrIp(ip).isValid, isTrue, reason: ip);
      }
    });

    test('valid IPv6 literals pass', () {
      for (final String ip in <String>[
        '::1',
        '2001:4860:4860::8888',
        'fe80::1',
        'fe80::1%eth0', // zone id
        '::ffff:192.168.1.1',
        '2001:db8:85a3:0:0:8a2e:370:7334',
      ]) {
        expect(NetworkTarget.validateHostOrIp(ip).isValid, isTrue, reason: ip);
      }
    });

    test('the normalized value is trimmed', () {
      final NetworkTargetResult r =
          NetworkTarget.validateHostOrIp('  example.com  ');
      expect(r, isA<ValidNetworkTarget>());
      expect((r as ValidNetworkTarget).value, 'example.com');
    });
  });

  group('validateHostOrIp — rejects malicious / malformed input', () {
    test('empty and whitespace-only are rejected as empty', () {
      for (final String s in <String>['', '   ', '\t']) {
        final NetworkTargetResult r = NetworkTarget.validateHostOrIp(s);
        expect(r, isA<InvalidNetworkTarget>());
        expect((r as InvalidNetworkTarget).reason,
            NetworkTargetRejection.empty);
      }
    });

    test('FLAG INJECTION: a `-`/`--`-leading host is rejected', () {
      for (final String s in <String>[
        '-foo',
        '--help',
        '-O',
        '--mtu',
        '-f',
        '-i eth0', // also has whitespace
      ]) {
        final NetworkTargetResult r = NetworkTarget.validateHostOrIp(s);
        expect(r.isValid, isFalse, reason: s);
        expect((r as InvalidNetworkTarget).reason,
            NetworkTargetRejection.malformedSyntax);
      }
    });

    test('whitespace and shell-metacharacter hosts are rejected', () {
      for (final String s in <String>[
        'example.com; rm -rf /',
        'a b.com',
        r'example.com | cat',
        r'$(whoami).com',
        'host`id`.com',
        'a.com&',
      ]) {
        expect(NetworkTarget.validateHostOrIp(s).isValid, isFalse, reason: s);
      }
    });

    test('malformed IPs and over-long input are rejected', () {
      for (final String s in <String>[
        '999.1.1.1',
        '1.2.3',
        '1.2.3.4.5',
        '256.256.256.256',
        '12345', // bare number, not a host, not an IPv4
        'gggg::1', // bad IPv6 hextet
        '2001:::1', // double '::' nonsense
      ]) {
        expect(NetworkTarget.validateHostOrIp(s).isValid, isFalse, reason: s);
      }
    });
  });

  group('validateReferralTarget — WHOIS SSRF guard', () {
    test('SSRF: cloud-metadata link-local 169.254.169.254 is rejected', () {
      final NetworkTargetResult r =
          NetworkTarget.validateReferralTarget('169.254.169.254');
      expect(r.isValid, isFalse);
      expect((r as InvalidNetworkTarget).reason,
          NetworkTargetRejection.privateOrInternal);
    });

    test('SSRF: loopback and RFC-1918 referral targets are rejected', () {
      for (final String ip in <String>[
        '127.0.0.1',
        '10.0.0.1',
        '192.168.1.1',
        '172.16.0.1',
        '172.31.255.255',
        '100.64.0.1', // CGNAT
        '0.0.0.0',
      ]) {
        final NetworkTargetResult r =
            NetworkTarget.validateReferralTarget(ip);
        expect(r.isValid, isFalse, reason: ip);
        expect((r as InvalidNetworkTarget).reason,
            NetworkTargetRejection.privateOrInternal);
      }
    });

    test('SSRF: internal IPv6 referral targets are rejected', () {
      for (final String ip in <String>[
        '::1', // loopback
        '::', // unspecified
        'fe80::1', // link-local
        'fc00::1', // unique-local
        'fd12:3456::1', // unique-local
        '::ffff:192.168.1.1', // IPv4-mapped private
      ]) {
        final NetworkTargetResult r =
            NetworkTarget.validateReferralTarget(ip);
        expect(r.isValid, isFalse, reason: ip);
        expect((r as InvalidNetworkTarget).reason,
            NetworkTargetRejection.privateOrInternal);
      }
    });

    test('public referral servers still pass', () {
      for (final String h in <String>[
        'whois.verisign-grs.com',
        'whois.iana.org',
        '8.8.8.8',
        '2001:4860:4860::8888',
      ]) {
        expect(NetworkTarget.validateReferralTarget(h).isValid, isTrue,
            reason: h);
      }
    });

    test('a flag-leading or malformed referral is also rejected', () {
      expect(NetworkTarget.validateReferralTarget('-evil').isValid, isFalse);
      expect(NetworkTarget.validateReferralTarget('').isValid, isFalse);
    });
  });
}
