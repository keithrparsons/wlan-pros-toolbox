// Host/IP input-validation — the exact typo cases from the 2026-07-14 user
// report ("stumbled on my phone and thought tool was broke but it was a typo").
//
// These lock the SHARED validator (NetworkTarget.validateHostOrIp) against the
// classic phone-keyboard mistakes that used to be silently accepted and made
// the tool "appear broken". The validator already existed and is the single
// source of truth (already wired into traceroute_service); this file pins the
// report's cases against it so a future regression is caught.
//
// Pure Dart: no sockets, no subprocess, no Flutter binding.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/network_target.dart';

void main() {
  bool valid(String s) => NetworkTarget.validateHostOrIp(s).isValid;

  group('valid addresses keep passing (no legitimate input blocked)', () {
    test('IPv4 literals', () {
      for (final String s in <String>[
        '1.1.1.1',
        '8.8.8.8',
        '192.168.1.1',
        '10.0.0.1',
        '255.255.255.255',
        '0.0.0.0',
      ]) {
        expect(valid(s), isTrue, reason: s);
      }
    });

    test('IPv6 literals incl. :: compression and zone id', () {
      for (final String s in <String>[
        '::1',
        '::',
        '2001:4860:4860::8888',
        'fe80::1',
        'fe80::1%en0',
        '::ffff:192.168.1.1',
        '2001:db8:85a3:0:0:8a2e:370:7334',
      ]) {
        expect(valid(s), isTrue, reason: s);
      }
    });

    test('hostnames / FQDNs', () {
      for (final String s in <String>[
        'example.com',
        'WLANPros.com',
        'a.b.c.example.org',
        'host-with-hyphen.example.com',
        'localhost',
        'example.com.', // FQDN root dot
      ]) {
        expect(valid(s), isTrue, reason: s);
      }
    });

    test('a trailing space (the classic phone typo) is trimmed, not rejected',
        () {
      expect(valid('  8.8.8.8  '), isTrue);
      expect(valid('example.com '), isTrue);
    });
  });

  group('the user-report typos are rejected honestly', () {
    test('an out-of-range octet (192.168.1.256) is NOT accepted', () {
      // 256 > 255 → not a valid IPv4; the all-numeric last label → not a valid
      // hostname either. This is the exact "thought the tool was broke" case.
      expect(valid('192.168.1.256'), isFalse);
    });

    test('a double-dot / empty octet (192.168..1) is rejected', () {
      expect(valid('192.168..1'), isFalse);
      expect(valid('192.168.1.'), isFalse); // trailing dotted-numeric, not FQDN
    });

    test('a pasted URL scheme (http://host) is rejected', () {
      expect(valid('http://host'), isFalse);
      expect(valid('https://example.com/path'), isFalse);
    });

    test('too-few / too-many octets are rejected', () {
      expect(valid('1.2.3'), isFalse);
      expect(valid('1.2.3.4.5'), isFalse);
    });

    test('empty and whitespace-only are rejected', () {
      expect(valid(''), isFalse);
      expect(valid('   '), isFalse);
      expect(valid('\t'), isFalse);
    });

    test('a bare number is not a host', () {
      expect(valid('12345'), isFalse);
    });

    test('an embedded space is rejected', () {
      expect(valid('exa mple.com'), isFalse);
    });
  });
}
