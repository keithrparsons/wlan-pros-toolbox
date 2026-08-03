// MacAddressBits unit tests — the I/G and U/L control bits, the four notation
// forms, the U/L flip, and the RFC 4291 Appendix A EUI-64 derivation.
//
// EXPECTED VALUES, STATED BEFORE THE ASSERTIONS (they were worked by hand from
// the RFC, not read back off the implementation):
//
//   B8:27:EB:01:23:45   first octet 0xB8 = 1011 1000. Bit 0 (I/G) = 0 →
//                       unicast. Bit 1 (U/L) = 0 → globally administered.
//                       IEEE EUI-64      b8:27:eb:ff:fe:01:23:45
//                       modified EUI-64  ba27:ebff:fe01:2345   (0xB8^0x02=0xBA)
//                       link-local       fe80::ba27:ebff:fe01:2345
//                       U/L flipped      ba:27:eb:01:23:45
//
//   02:00:00:00:00:01   0x02 = 0000 0010 → unicast, LOCALLY administered.
//                       IEEE EUI-64      02:00:00:ff:fe:00:00:01
//                       modified EUI-64  0000:00ff:fe00:0001   (0x02^0x02=0x00)
//                       link-local       fe80::ff:fe00:1
//                         (the four zero groups of fe80 plus the leading 0000
//                          of the interface ID are ONE five-group zero run)
//                       U/L flipped      00:00:00:00:00:01
//
//   01:00:5E:00:00:FB   0x01 = 0000 0001 → MULTICAST (IPv4 mDNS group), U/L=0.
//                       No EUI-64: a group address is not one interface.
//
//   33:33:00:00:00:01   0x33 = 0011 0011 → multicast AND locally administered
//                       (the IPv6 all-nodes group). Both bits set. No EUI-64.
//
//   FF:FF:FF:FF:FF:FF   broadcast. isBroadcast true, multicast, local, and no
//                       EUI-64 with the broadcast-specific reason.
//
//   00:00:00:00:00:00   0x00 = 0000 0000 → unicast, global, NOT broadcast.
//                       modified EUI-64  0200:00ff:fe00:0000  (0x00^0x02=0x02)
//                       link-local       fe80::200:ff:fe00:0
//                         (TWO zero runs: three groups after fe80, and a single
//                          group at the end. The longest wins, so "::" lands on
//                          the run of three and the trailing single zero group
//                          survives as ":0" — RFC 5952 never collapses a run of
//                          one. My first hand-computed value here missed the
//                          fe80 run and the test caught it.)
//
// Edge cases deliberately covered: both control bits set at once, the all-zero
// first octet where the U/L flip SETS rather than clears the bit, a link-local
// whose zero run spans the boundary between the fe80 half and the interface ID,
// a link-local with a one-group zero run that must NOT compress, the broadcast
// special case, and four rejection shapes.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/mac_address_bits.dart';

void main() {
  group('notation forms', () {
    test('every accepted notation decodes to the same four forms', () {
      for (final String input in <String>[
        'B8:27:EB:01:23:45',
        'b8-27-eb-01-23-45',
        'b827.eb01.2345',
        'B827EB012345',
        'b8 27 eb 01 23 45',
        '  B8:27:eb:01:23:45  ',
      ]) {
        final MacBitsResult r = MacAddressBits.decode(input);
        expect(r.isValid, isTrue, reason: input);
        expect(r.colonForm, 'b8:27:eb:01:23:45', reason: input);
        expect(r.hyphenForm, 'B8-27-EB-01-23-45', reason: input);
        expect(r.ciscoForm, 'b827.eb01.2345', reason: input);
        expect(r.bareForm, 'b827eb012345', reason: input);
      }
    });
  });

  group('control bits', () {
    test('B8 — unicast, globally administered', () {
      final MacBitsResult r = MacAddressBits.decode('B8:27:EB:01:23:45');
      expect(r.firstOctetHex, 'B8');
      expect(r.firstOctetBinary, '10111000');
      expect(r.cast, MacCast.unicast);
      expect(r.administration, MacAdministration.global);
      expect(r.isBroadcast, isFalse);
      expect(r.ulFlippedForm, 'ba:27:eb:01:23:45');
    });

    test('02 — unicast, locally administered (a randomized client MAC)', () {
      final MacBitsResult r = MacAddressBits.decode('02:00:00:00:00:01');
      expect(r.firstOctetBinary, '00000010');
      expect(r.cast, MacCast.unicast);
      expect(r.administration, MacAdministration.local);
      // Flipping the bit back is how you recover the form whose first three
      // octets would carry an OUI, if the address was derived from a real one.
      expect(r.ulFlippedForm, '00:00:00:00:00:01');
    });

    test('01:00:5E — multicast, globally administered', () {
      final MacBitsResult r = MacAddressBits.decode('01:00:5E:00:00:FB');
      expect(r.firstOctetBinary, '00000001');
      expect(r.cast, MacCast.multicast);
      expect(r.administration, MacAdministration.global);
      expect(r.isBroadcast, isFalse);
    });

    test('33:33 — BOTH control bits set', () {
      final MacBitsResult r = MacAddressBits.decode('33:33:00:00:00:01');
      expect(r.firstOctetBinary, '00110011');
      expect(r.cast, MacCast.multicast);
      expect(r.administration, MacAdministration.local);
    });

    test('all-ones is broadcast, and is flagged as such', () {
      final MacBitsResult r = MacAddressBits.decode('FF:FF:FF:FF:FF:FF');
      expect(r.isBroadcast, isTrue);
      expect(r.cast, MacCast.multicast);
      expect(r.administration, MacAdministration.local);
      expect(r.firstOctetBinary, '11111111');
    });

    test('all-zero is unicast and global, and is NOT broadcast', () {
      final MacBitsResult r = MacAddressBits.decode('00:00:00:00:00:00');
      expect(r.isBroadcast, isFalse);
      expect(r.cast, MacCast.unicast);
      expect(r.administration, MacAdministration.global);
      expect(r.firstOctetBinary, '00000000');
      // The flip SETS the bit here rather than clearing it.
      expect(r.ulFlippedForm, '02:00:00:00:00:00');
    });
  });

  group('EUI-64 derivation', () {
    test(
      'global unicast — IEEE form keeps the bit, modified form flips it',
      () {
        final MacBitsResult r = MacAddressBits.decode('B8:27:EB:01:23:45');
        expect(r.eui64, 'b8:27:eb:ff:fe:01:23:45');
        expect(r.modifiedEui64, 'ba27:ebff:fe01:2345');
        expect(r.linkLocal, 'fe80::ba27:ebff:fe01:2345');
        expect(r.eui64UnavailableReason, isNull);
      },
    );

    test('local unicast — the flip CLEARS the bit, and the zero run spans '
        'the fe80 half into the interface ID', () {
      final MacBitsResult r = MacAddressBits.decode('02:00:00:00:00:01');
      expect(r.eui64, '02:00:00:ff:fe:00:00:01');
      expect(r.modifiedEui64, '0000:00ff:fe00:0001');
      expect(r.linkLocal, 'fe80::ff:fe00:1');
    });

    test('the LONGEST zero run wins, and a run of one never collapses', () {
      final MacBitsResult r = MacAddressBits.decode('00:00:00:00:00:00');
      expect(r.eui64, '00:00:00:ff:fe:00:00:00');
      expect(r.modifiedEui64, '0200:00ff:fe00:0000');
      // fe80:0000:0000:0000:0200:00ff:fe00:0000 — "::" takes the run of three,
      // and the trailing single zero group stays visible as ":0".
      expect(r.linkLocal, 'fe80::200:ff:fe00:0');
    });

    test('multicast has NO EUI-64, with the reason given', () {
      final MacBitsResult r = MacAddressBits.decode('01:00:5E:00:00:FB');
      expect(r.eui64, isNull);
      expect(r.modifiedEui64, isNull);
      expect(r.linkLocal, isNull);
      expect(r.eui64UnavailableReason, isNotNull);
      expect(r.eui64UnavailableReason, contains('group'));
    });

    test('broadcast gets its own reason, not the generic group one', () {
      final MacBitsResult r = MacAddressBits.decode('FF:FF:FF:FF:FF:FF');
      expect(r.eui64, isNull);
      expect(r.eui64UnavailableReason, contains('broadcast'));
    });
  });

  group('rejection', () {
    test('wrong length, non-hex, and empty all come back invalid', () {
      for (final String bad in <String>[
        'b8:27:eb:01:23', // 5 bytes
        'b8:27:eb:01:23:45:67', // 8 bytes (an EUI-64, not a MAC)
        'gg:27:eb:01:23:45', // not hex
        '', // empty
      ]) {
        final MacBitsResult r = MacAddressBits.decode(bad);
        expect(r.isValid, isFalse, reason: bad);
        expect(r.error, isNotNull, reason: bad);
        expect(r.colonForm, isNull, reason: bad);
        expect(r.eui64, isNull, reason: bad);
      }
    });
  });
}
