// Ipv4Forms unit tests — integer, hex and binary renderings, and the prefix
// boundary marker.
//
// EXPECTED VALUES, WORKED BEFORE THE ASSERTIONS:
//   10.20.0.0        integer 169,082,880   (10·2^24 + 20·2^16)
//                    hex     0x0A140000
//                    dotted  0A.14.00.00
//                    binary  00001010.00010100.00000000.00000000
//   0.0.0.0          integer 0             hex 0x00000000
//   255.255.255.255  integer 4,294,967,295 hex 0xFFFFFFFF
//   192.168.1.1      integer 3,232,235,777 hex 0xC0A80101
//
// BOUNDARY PLACEMENT (10.20.0.0):
//   /22  00001010.00010100.000000/00.00000000   mid-octet, the whole point
//   /24  00001010.00010100.00000000/00000000    the "/" REPLACES the dot
//   /8   00001010/00010100.00000000.00000000    same rule at octet 1
//   /0   /00001010.00010100.00000000.00000000   leading, no network bits
//   /32  00001010.00010100.00000000.00000000/   trailing, no host bits
//   none 00001010.00010100.00000000.00000000    plain, three dots
//
// Edges covered: both ends of the address space, a boundary at each of the two
// degenerate prefixes, a boundary that coincides with an octet dot, and the
// invariant that the rendering always carries exactly three separators plus
// at most one boundary marker.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ipv4_forms.dart';
import 'package:wlan_pros_toolbox/services/network/subnet_calc_service.dart';

int _ip(String s) => SubnetCalcService.parseIpv4ToInt(s)!;

void main() {
  group('integer and hex', () {
    test('the worked example and both ends of the space', () {
      expect(Ipv4Forms.toInteger(_ip('10.20.0.0')), 169082880);
      expect(Ipv4Forms.toHex(_ip('10.20.0.0')), '0x0A140000');
      expect(Ipv4Forms.toDottedHex(_ip('10.20.0.0')), '0A.14.00.00');

      expect(Ipv4Forms.toInteger(_ip('0.0.0.0')), 0);
      expect(Ipv4Forms.toHex(_ip('0.0.0.0')), '0x00000000');

      expect(Ipv4Forms.toInteger(_ip('255.255.255.255')), 4294967295);
      expect(Ipv4Forms.toHex(_ip('255.255.255.255')), '0xFFFFFFFF');

      expect(Ipv4Forms.toInteger(_ip('192.168.1.1')), 3232235777);
      expect(Ipv4Forms.toHex(_ip('192.168.1.1')), '0xC0A80101');
    });
  });

  group('binary with the prefix boundary', () {
    const String plain = '00001010.00010100.00000000.00000000';

    test('no boundary is plain dotted binary', () {
      expect(Ipv4Forms.toBinary(_ip('10.20.0.0')), plain);
    });

    test('a mid-octet boundary cuts inside the octet', () {
      expect(
        Ipv4Forms.toBinary(_ip('10.20.0.0'), boundary: 22),
        '00001010.00010100.000000/00.00000000',
      );
    });

    test('a boundary on an octet edge REPLACES the dot, never doubles it', () {
      expect(
        Ipv4Forms.toBinary(_ip('10.20.0.0'), boundary: 24),
        '00001010.00010100.00000000/00000000',
      );
      expect(
        Ipv4Forms.toBinary(_ip('10.20.0.0'), boundary: 8),
        '00001010/00010100.00000000.00000000',
      );
      expect(
        Ipv4Forms.toBinary(_ip('10.20.0.0'), boundary: 16),
        '00001010.00010100/00000000.00000000',
      );
    });

    test('the two degenerate prefixes land outside the bits', () {
      expect(Ipv4Forms.toBinary(_ip('10.20.0.0'), boundary: 0), '/$plain');
      expect(Ipv4Forms.toBinary(_ip('10.20.0.0'), boundary: 32), '$plain/');
    });

    test('the mask renders with the same boundary, which is what makes the '
        'rule visible', () {
      expect(
        Ipv4Forms.toBinary(
          SubnetCalcService.maskIntForPrefix(22),
          boundary: 22,
        ),
        '11111111.11111111.111111/00.00000000',
      );
    });

    test('always 32 bits, three dots, and at most one boundary mark', () {
      for (int p = 0; p <= 32; p++) {
        final String s = Ipv4Forms.toBinary(_ip('172.16.5.3'), boundary: p);
        expect(RegExp('[01]').allMatches(s).length, 32, reason: '/$p');
        expect('/'.allMatches(s).length, 1, reason: '/$p');
        // A boundary on an octet edge eats one dot; otherwise all three stay.
        expect(
          '.'.allMatches(s).length,
          (p % 8 == 0 && p != 0 && p != 32) ? 2 : 3,
          reason: '/$p',
        );
      }
    });
  });
}
