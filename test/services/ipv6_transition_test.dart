// Ipv6Transition unit tests — decoding IPv4 out of an IPv6 address, and
// writing an IPv4 address the four ways IPv6 can carry it.
//
// EXPECTED VALUES, WORKED BEFORE THE ASSERTIONS.
//
// DECODE
//   ::ffff:192.0.2.1          IPv4-mapped, 192.0.2.1        RFC 4291 §2.5.5.2
//   ::ffff:c000:0201          the same address in pure hex   (c0 00 02 01)
//   64:ff9b::192.0.2.33       NAT64 well-known, 192.0.2.33   RFC 6052 §2.1
//   64:ff9b::c000:221         the same (0x0221 = 2.33)
//   2002:c000:204::1          6to4, 192.0.2.4                RFC 3056
//   ::192.0.2.1               IPv4-compatible, DEPRECATED    RFC 4291 §2.5.5.1
//   ::                        NOT a transition address (unspecified)
//   ::1                       NOT a transition address (loopback), even though
//                             it sits numerically inside ::/96
//   2001:db8::1               no IPv4 inside
//
//   2001:0:4136:e378:8000:63bf:3fff:fdd2   Teredo (RFC 4380 §6 example)
//       server = groups 2-3   = 4136:e378 = 65.54.227.120
//       port   = ~group 5     = ~0x63bf = 0x9c40 = 40000
//       client = ~groups 6-7  = ~(3fff:fdd2) = c000:022d = 192.0.2.45
//     The inversion is the whole trap: read raw, the client looks like
//     63.255.253.210 and the port looks like 25535.
//
// ENCODE, for 192.0.2.1 (0xC0000201)
//   mapped dotted    ::ffff:192.0.2.1
//   mapped hex       ::ffff:c000:201        (compression strips the leading 0)
//   mapped expanded  0000:0000:0000:0000:0000:ffff:c000:0201
//   compatible       ::192.0.2.1            (deprecated)
//   6to4 prefix      2002:c000:201::/48     (a PREFIX for a site, not a host)
//   nat64 dotted     64:ff9b::192.0.2.1
//   nat64 hex        64:ff9b::c000:201
//
// EDGES: the two addresses that look like IPv4-compatible but are not, a
// dotted-quad literal and its pure-hex twin decoding identically, the
// bit-inverted Teredo halves, an octet above 255, a wrong octet count, and an
// unparseable IPv6 literal.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ipv6_address.dart';
import 'package:wlan_pros_toolbox/services/network/ipv6_transition.dart';

void main() {
  group('the dotted-quad literal is legal IPv6 and now expands', () {
    test('::ffff:192.0.2.1 folds its tail into two hex groups', () {
      expect(
        Ipv6Address.expand('::ffff:192.0.2.1'),
        '0000:0000:0000:0000:0000:ffff:c000:0201',
      );
      expect(
        Ipv6Address.expand('0:0:0:0:0:ffff:192.0.2.1'),
        '0000:0000:0000:0000:0000:ffff:c000:0201',
      );
    });

    test('an address with no tail is untouched', () {
      expect(
        Ipv6Address.expand('2001:db8::1'),
        '2001:0db8:0000:0000:0000:0000:0000:0001',
      );
      expect(
        Ipv6Address.expand('::'),
        '0000:0000:0000:0000:0000:0000:0000:0000',
      );
    });

    test('a malformed tail throws rather than answering wrongly', () {
      expect(
        () => Ipv6Address.expand('::ffff:192.0.2'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => Ipv6Address.expand('::ffff:192.0.2.999'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // REGRESSION, 2026-08-02. Ipv6Address.compress used to tidy its "::" seam
  // with `.replaceAll(RegExp(r'^:|:$'), '')`, which could not tell a seam colon
  // from the colon that IS the "::". Any zero run touching either end lost half
  // its "::", and the shipped IPv6 Subnetting screen printed "2001:db8/64" and
  // "fe80/64" in its Network row and rendered ::1 as "1". These cases failed
  // red before the fix.
  group('compress keeps the "::" at both ends (regression)', () {
    String c(String literal) =>
        Ipv6Address.compress(Ipv6Address.expand(literal));

    test('a zero run at the START keeps its leading "::"', () {
      expect(c('::1'), '::1');
      expect(c('::ffff:c000:201'), '::ffff:c000:201');
      expect(c('::ffff:192.0.2.1'), '::ffff:c000:201');
      expect(c('0:0:0:0:0:0:0:5'), '::5');
    });

    test('a zero run at the END keeps its trailing "::"', () {
      expect(c('2001:db8::'), '2001:db8::');
      expect(c('fe80::'), 'fe80::');
      expect(c('2002:c000:201::'), '2002:c000:201::');
    });

    test('an all-zero address is "::" and not empty', () {
      expect(c('::'), '::');
    });

    test('a run in the MIDDLE still compresses, as it always did', () {
      expect(c('2001:db8::1'), '2001:db8::1');
      expect(c('2001:0db8:0000:0000:0000:0000:0000:0001'), '2001:db8::1');
    });

    test('a single zero group is never collapsed (RFC 5952 4.2.2)', () {
      expect(c('2001:db8:0:1:1:1:1:1'), '2001:db8:0:1:1:1:1:1');
    });
  });

  group('decode', () {
    test('IPv4-mapped, in both spellings', () {
      for (final String s in <String>[
        '::ffff:192.0.2.1',
        '::ffff:c000:0201',
        '0:0:0:0:0:ffff:192.0.2.1',
        '::FFFF:192.0.2.1',
      ]) {
        final Ipv6ToIpv4Result r = Ipv6Transition.decode(s);
        expect(r.isValid, isTrue, reason: s);
        expect(r.kind, TransitionKind.ipv4Mapped, reason: s);
        expect(r.ipv4, '192.0.2.1', reason: s);
        expect(r.rfc, contains('4291'), reason: s);
      }
    });

    test('NAT64 well-known prefix, and the honest limit on a custom one', () {
      final Ipv6ToIpv4Result r = Ipv6Transition.decode('64:ff9b::192.0.2.33');
      expect(r.kind, TransitionKind.nat64WellKnown);
      expect(r.ipv4, '192.0.2.33');
      expect(Ipv6Transition.decode('64:ff9b::c000:221').ipv4, '192.0.2.33');
      // The caveat is not optional: a network-specific prefix decodes to a
      // different address and the length is not in the bits.
      expect(r.note, contains('/32'));
      expect(r.note, contains('not carried in the address'));
    });

    test('6to4 reads the 32 bits after 2002', () {
      final Ipv6ToIpv4Result r = Ipv6Transition.decode('2002:c000:204::1');
      expect(r.kind, TransitionKind.sixToFour);
      expect(r.ipv4, '192.0.2.4');
      expect(r.ipv4Role, contains('site'));
    });

    test(
      'Teredo: the client half is stored inverted, and comes back flipped',
      () {
        final Ipv6ToIpv4Result r = Ipv6Transition.decode(
          '2001:0:4136:e378:8000:63bf:3fff:fdd2',
        );
        expect(r.kind, TransitionKind.teredo);
        expect(r.teredoServer, '65.54.227.120');
        expect(r.teredoPort, 40000);
        expect(r.ipv4, '192.0.2.45');
        expect(r.note, contains('INVERTED'));
      },
    );

    test('IPv4-compatible is decoded AND flagged as deprecated', () {
      final Ipv6ToIpv4Result r = Ipv6Transition.decode('::192.0.2.1');
      expect(r.kind, TransitionKind.ipv4Compatible);
      expect(r.ipv4, '192.0.2.1');
      expect(r.label, contains('deprecated'));
    });

    test(':: and ::1 sit inside ::/96 but are NOT transition addresses', () {
      final Ipv6ToIpv4Result unspec = Ipv6Transition.decode('::');
      expect(unspec.kind, TransitionKind.none);
      expect(unspec.ipv4, isNull);
      expect(unspec.label, contains('Unspecified'));

      final Ipv6ToIpv4Result loop = Ipv6Transition.decode('::1');
      expect(loop.kind, TransitionKind.none);
      expect(loop.ipv4, isNull);
      expect(loop.label, contains('Loopback'));
    });

    test('an ordinary IPv6 address says so instead of inventing an IPv4', () {
      final Ipv6ToIpv4Result r = Ipv6Transition.decode('2001:db8::1');
      expect(r.isValid, isTrue);
      expect(r.kind, TransitionKind.none);
      expect(r.ipv4, isNull);
      expect(r.note, contains('no IPv4 address hiding'));
    });

    test('rejection', () {
      expect(Ipv6Transition.decode('').isValid, isFalse);
      expect(Ipv6Transition.decode('not an address').isValid, isFalse);
      expect(Ipv6Transition.decode('2001::db8::1').isValid, isFalse);
      expect(Ipv6Transition.decode('gggg::1').isValid, isFalse);
    });
  });

  group('encode', () {
    test('192.0.2.1 in all four formats', () {
      final Ipv4ToIpv6Result r = Ipv6Transition.encode('192.0.2.1');
      expect(r.isValid, isTrue);
      expect(r.mappedDotted, '::ffff:192.0.2.1');
      expect(r.mappedHex, '::ffff:c000:201');
      expect(r.mappedExpanded, '0000:0000:0000:0000:0000:ffff:c000:0201');
      expect(r.compatibleDotted, '::192.0.2.1');
      expect(r.sixToFourPrefix, '2002:c000:201::/48');
      expect(r.nat64Dotted, '64:ff9b::192.0.2.1');
      expect(r.nat64Hex, '64:ff9b::c000:201');
    });

    test('a round trip: every encoded form decodes back to the input', () {
      const String ip = '203.0.113.77';
      final Ipv4ToIpv6Result e = Ipv6Transition.encode(ip);
      expect(Ipv6Transition.decode(e.mappedDotted!).ipv4, ip);
      expect(Ipv6Transition.decode(e.mappedHex!).ipv4, ip);
      expect(Ipv6Transition.decode(e.compatibleDotted!).ipv4, ip);
      expect(Ipv6Transition.decode(e.nat64Dotted!).ipv4, ip);
      // The 6to4 value is a PREFIX, so strip the /48 before decoding it.
      final String sixToFour = e.sixToFourPrefix!.split('/').first;
      expect(Ipv6Transition.decode(sixToFour).ipv4, ip);
    });

    test('0.0.0.0 and 255.255.255.255 both encode without a special case', () {
      expect(Ipv6Transition.encode('0.0.0.0').mappedDotted, '::ffff:0.0.0.0');
      expect(Ipv6Transition.encode('0.0.0.0').mappedHex, '::ffff:0:0');
      expect(
        Ipv6Transition.encode('255.255.255.255').mappedHex,
        '::ffff:ffff:ffff',
      );
    });

    test('rejection names what is wrong', () {
      expect(Ipv6Transition.encode('').isValid, isFalse);
      expect(Ipv6Transition.encode('192.0.2').isValid, isFalse);
      expect(Ipv6Transition.encode('192.0.2.1.5').isValid, isFalse);
      expect(Ipv6Transition.encode('192.0.2.256').error, contains('0 to 255'));
      expect(Ipv6Transition.encode('a.b.c.d').isValid, isFalse);
    });
  });
}
