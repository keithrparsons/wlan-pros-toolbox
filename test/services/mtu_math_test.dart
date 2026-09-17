// MTU and MSS arithmetic. The numbers here are the ones a network engineer
// already knows by heart, which is the point: if the tool disagrees with 1460
// it is wrong, and no amount of internal consistency saves it.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/mtu_math.dart';

void main() {
  group('the figures everyone already knows', () {
    test('Ethernet 1500 over IPv4 gives the famous 1460', () {
      expect(
        MtuMath.mssFromMtu(linkMtu: 1500, ipv6: false, tcpTimestamps: false),
        1460,
      );
    });

    test('Ethernet 1500 over IPv6 gives 1440, because the header is 40', () {
      expect(
        MtuMath.mssFromMtu(linkMtu: 1500, ipv6: true, tcpTimestamps: false),
        1440,
      );
    });

    test('PPPoE gives 1452, the DSL number', () {
      // 1500 - 8 PPPoE - 40 headers.
      expect(
        MtuMath.mssFromMtu(
          linkMtu: 1500,
          ipv6: false,
          tcpTimestamps: false,
          tunnels: <String>['pppoe'],
        ),
        1452,
      );
    });

    test('timestamps take another 12, which is the overlooked one', () {
      expect(
        MtuMath.mssFromMtu(linkMtu: 1500, ipv6: false, tcpTimestamps: true),
        1448,
      );
    });

    test('WireGuard over IPv4 lands on 1400', () {
      // 1500 - 60 - 40. The 60 is a 20-byte outer IPv4, an 8-byte UDP header
      // and WireGuard's 32 bytes (16-byte data header plus the 16-byte
      // Poly1305 tag). Over IPv6 the outer header is 40 instead of 20, which
      // is where wg-quick's default MTU of 1420 comes from.
      //
      // I first wrote 1380 here and the test was wrong, not the code.
      expect(
        MtuMath.mssFromMtu(
          linkMtu: 1500,
          ipv6: false,
          tcpTimestamps: false,
          tunnels: <String>['wireguard4'],
        ),
        1400,
      );
    });
  });

  group('a VLAN tag costs nothing, and that is why it is on the list', () {
    test('adding it changes no number', () {
      final int? without =
          MtuMath.mssFromMtu(linkMtu: 1500, ipv6: false, tcpTimestamps: false);
      final int? with_ = MtuMath.mssFromMtu(
        linkMtu: 1500,
        ipv6: false,
        tcpTimestamps: false,
        tunnels: <String>['vlan'],
      );
      expect(with_, without);
      expect(with_, 1460);
    });

    test('and it carries the explanation, since the answer is counterintuitive',
        () {
      final MtuOverhead vlan = MtuMath.overheadById('vlan')!;
      expect(vlan.bytes, 0);
      expect(vlan.note, contains('extends the Ethernet header'));
    });
  });

  group('a variable overhead is a RANGE and is sized to the high end', () {
    test('IPsec ESP reports a range rather than a fabricated number', () {
      final MtuOverhead esp = MtuMath.overheadById('ipsec-esp')!;
      expect(esp.isRange, isTrue);
      expect(esp.costLabel, '56 to 73');
    });

    test('sizing uses the HIGH end, so the answer does not fail later', () {
      // 1500 - 73 - 40 = 1387. Using the low end would print 1404 and work
      // until the day the cipher or the padding changed.
      expect(
        MtuMath.mssFromMtu(
          linkMtu: 1500,
          ipv6: false,
          tcpTimestamps: false,
          tunnels: <String>['ipsec-esp'],
        ),
        1387,
      );
    });
  });

  group('the inverse, which is the half that teaches', () {
    test('an observed 1452 implies a 1492 path, the PPPoE signature', () {
      expect(
        MtuMath.mtuFromMss(mss: 1452, ipv6: false, tcpTimestamps: false),
        1492,
      );
    });

    test('and the 8 missing bytes are named as a candidate, not asserted', () {
      final int gap = MtuMath.unexplainedBytes(
        mss: 1452,
        ipv6: false,
        tcpTimestamps: false,
      );
      expect(gap, 8);
      final List<MtuOverhead> candidates = MtuMath.candidatesForGap(gap);
      expect(candidates.map((MtuOverhead o) => o.id), contains('pppoe'));
    });

    test('a fully explained path leaves no gap', () {
      final int gap = MtuMath.unexplainedBytes(
        mss: 1452,
        ipv6: false,
        tcpTimestamps: false,
        tunnels: <String>['pppoe'],
      );
      expect(gap, 0);
      expect(MtuMath.candidatesForGap(gap), isEmpty);
    });

    test('forward and inverse are exact inverses of each other', () {
      for (final int mtu in <int>[1500, 1492, 1400, 1280, 576]) {
        for (final bool v6 in <bool>[true, false]) {
          for (final bool ts in <bool>[true, false]) {
            final int? mss = MtuMath.mssFromMtu(
              linkMtu: mtu,
              ipv6: v6,
              tcpTimestamps: ts,
              tunnels: <String>['gre'],
            );
            expect(mss, isNotNull);
            expect(
              MtuMath.mtuFromMss(
                mss: mss!,
                ipv6: v6,
                tcpTimestamps: ts,
                tunnels: <String>['gre'],
              ),
              mtu,
            );
          }
        }
      }
    });
  });

  group('the honest refusals', () {
    test('a stack that costs more than the link carries returns null', () {
      // 100-byte link, IPv6 + timestamps + WireGuard = 72 + 60 = 132.
      expect(
        MtuMath.mssFromMtu(
          linkMtu: 100,
          ipv6: true,
          tcpTimestamps: true,
          tunnels: <String>['wireguard4'],
        ),
        isNull,
        reason: 'null here means TCP cannot pass one byte of payload, which is '
            'a real answer rather than an error',
      );
    });

    test('an exactly-zero MSS is also null, not a working link', () {
      expect(
        MtuMath.mssFromMtu(linkMtu: 40, ipv6: false, tcpTimestamps: false),
        isNull,
      );
      expect(
        MtuMath.mssFromMtu(linkMtu: 41, ipv6: false, tcpTimestamps: false),
        1,
      );
    });

    test('the IP-version floors are the documented ones', () {
      expect(MtuMath.isBelowIpFloor(mtu: 1279, ipv6: true), isTrue);
      expect(MtuMath.isBelowIpFloor(mtu: 1280, ipv6: true), isFalse);
      expect(MtuMath.isBelowIpFloor(mtu: 575, ipv6: false), isTrue);
      expect(MtuMath.isBelowIpFloor(mtu: 576, ipv6: false), isFalse);
    });

    test('an unknown tunnel id is ignored rather than throwing', () {
      expect(MtuMath.tunnelBytes(<String>['not-a-tunnel']), 0);
    });
  });

  group('every overhead carries its source', () {
    test('no entry ships an unsourced number', () {
      for (final MtuOverhead o in MtuMath.overheads) {
        expect(o.source, isNotEmpty, reason: '${o.id} has no source');
        expect(o.source.toLowerCase(),
            anyOf(contains('rfc'), contains('ieee'), contains('paper')),
            reason: '${o.id} cites "${o.source}", which is not a document');
      }
    });
  });
}
