// Tests for the Packet Decode / Protocol Reference screen.
//
// The datasets are transcribed VERBATIM from Pax's source-pinned brief
// (Deliverables/2026-07-18-packet-decode-reference/decode-data.md), which fetched
// every value from the primary RFC / IANA registry. These tests pin the
// load-bearing facts a decoder must not get wrong -- field offsets and widths,
// the RFC 9293 canonical TCP flag layout (with the historic NS -> AE bit shown
// but NOT presented as a current flag), ICMP type 4 marked deprecated, the IPv4
// ToS octet shown as DSCP+ECN, and the IP-protocol-number values the IPv4
// Protocol / IPv6 Next Header fields point at -- plus phone/tablet/desktop
// widget tests confirming the read-only screen renders without overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/packet_decode_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  PacketField ipv4(String field) => PacketDecodeScreen.ipv4Header
      .firstWhere((PacketField f) => f.field == field);
  PacketField ipv6(String field) => PacketDecodeScreen.ipv6Header
      .firstWhere((PacketField f) => f.field == field);
  PacketField tcp(String field) => PacketDecodeScreen.tcpHeader
      .firstWhere((PacketField f) => f.field == field);
  PacketField udp(String field) => PacketDecodeScreen.udpHeader
      .firstWhere((PacketField f) => f.field == field);

  group('IPv4 header (RFC 791)', () {
    test('Protocol field is at bit offset 72, width 8', () {
      final PacketField p = ipv4('Protocol');
      expect(p.offset, '72');
      expect(p.length, '8');
    });

    test('TTL at 64/8, Source Address at 96/32, Destination at 128/32', () {
      expect(ipv4('Time to Live').offset, '64');
      expect(ipv4('Source Address').offset, '96');
      expect(ipv4('Source Address').length, '32');
      expect(ipv4('Destination Address').offset, '128');
    });

    test('ToS octet is shown as DSCP (6) + ECN (2), not RFC 791 precedence', () {
      final List<String> names =
          PacketDecodeScreen.ipv4ToS.map((b) => b.name).toList();
      expect(names, containsAll(<String>['DSCP', 'ECN']));
      expect(names.contains('Precedence'), isFalse);
      // The DSCP row occupies bits 8-13; ECN 14-15.
      final BitFieldRow dscp = PacketDecodeScreen.ipv4ToS
          .firstWhere((b) => b.name == 'DSCP');
      expect(dscp.bits, '8-13');
    });

    test('IPv4 Flags: DF at bit 49, MF at bit 50', () {
      final BitFieldRow df = PacketDecodeScreen.ipv4Flags
          .firstWhere((b) => b.name.startsWith('DF'));
      final BitFieldRow mf = PacketDecodeScreen.ipv4Flags
          .firstWhere((b) => b.name.startsWith('MF'));
      expect(df.bits, '49');
      expect(mf.bits, '50');
    });
  });

  group('IPv6 header (RFC 8200)', () {
    test('Version = 6, fixed 40-byte header, addresses at 64 and 192', () {
      expect(ipv6('Version').meaning.contains('always 6'), isTrue);
      expect(ipv6('Source Address').offset, '64');
      expect(ipv6('Source Address').length, '128');
      expect(ipv6('Destination Address').offset, '192');
      expect(PacketDecodeScreen.ipv6Note.contains('40 octets'), isTrue);
    });
  });

  group('Common IP protocol numbers (IANA)', () {
    int numFor(String name) => PacketDecodeScreen.protocolNumbers
        .firstWhere((p) => p.name == name)
        .number;

    test('the anchor values are correct', () {
      expect(numFor('ICMP'), 1);
      expect(numFor('TCP'), 6);
      expect(numFor('UDP'), 17);
      expect(numFor('GRE'), 47);
      expect(numFor('ESP'), 50);
      expect(numFor('AH'), 51);
      expect(numFor('ICMPv6'), 58);
      expect(numFor('EIGRP'), 88);
      expect(numFor('OSPF'), 89);
      expect(numFor('SCTP'), 132);
    });

    test('the citation points ports at the Well-Known Ports reference', () {
      expect(
        PacketDecodeScreen.protoNumbersCitation.contains('Well-Known Ports'),
        isTrue,
      );
    });
  });

  group('TCP header + flags (RFC 9293)', () {
    test('Control Bits at offset 104, width 8', () {
      expect(tcp('Control Bits').offset, '104');
      expect(tcp('Control Bits').length, '8');
    });

    test('the 8 canonical control bits are CWR..FIN at bits 104-111', () {
      final Map<String, int> bitFor = <String, int>{
        for (final TcpFlagRow f in PacketDecodeScreen.tcpFlags)
          if (!f.historic) f.flag: f.bit,
      };
      expect(bitFor['CWR'], 104);
      expect(bitFor['ECE'], 105);
      expect(bitFor['URG'], 106);
      expect(bitFor['ACK'], 107);
      expect(bitFor['PSH'], 108);
      expect(bitFor['RST'], 109);
      expect(bitFor['SYN'], 110);
      expect(bitFor['FIN'], 111);
      // Exactly 8 non-historic control bits.
      expect(bitFor.length, 8);
    });

    test('the historic bit 103 is flagged historic and names AE / RFC 9768, '
        'not presented as a current NS flag', () {
      final TcpFlagRow hist =
          PacketDecodeScreen.tcpFlags.firstWhere((f) => f.historic);
      expect(hist.bit, 103);
      // The status is carried in TEXT (never color alone).
      expect(hist.flag.toLowerCase().contains('was ns'), isTrue);
      expect(hist.meaning.contains('AE'), isTrue);
      expect(hist.meaning.contains('RFC 9768'), isTrue);
      // No non-historic flag is literally named "NS".
      final bool anyCurrentNs = PacketDecodeScreen.tcpFlags
          .any((f) => !f.historic && f.flag == 'NS');
      expect(anyCurrentNs, isFalse);
    });
  });

  group('UDP header (RFC 768)', () {
    test('four fields; Length minimum 8; Checksum at offset 48', () {
      expect(PacketDecodeScreen.udpHeader.length, 4);
      expect(udp('Length').meaning.contains('minimum 8'), isTrue);
      expect(udp('Checksum').offset, '48');
    });
  });

  group('TCP states + handshake / teardown (RFC 9293)', () {
    test('the 11 states include the key ones', () {
      final List<String> names =
          PacketDecodeScreen.tcpStates.map((s) => s.state).toList();
      expect(names.length, 11);
      expect(
        names,
        containsAll(<String>[
          'CLOSED',
          'LISTEN',
          'SYN-SENT',
          'SYN-RECEIVED',
          'ESTABLISHED',
          'TIME-WAIT',
        ]),
      );
    });

    test('three-way handshake has 3 steps, teardown has 4', () {
      expect(PacketDecodeScreen.handshake.length, 3);
      expect(PacketDecodeScreen.teardown.length, 4);
      expect(PacketDecodeScreen.handshake.first.detail.contains('SYN'), isTrue);
    });
  });

  group('ICMP + ICMPv6 (RFC 792 / RFC 4443)', () {
    test('ICMP type 4 (Source Quench) is present and marked deprecated', () {
      final IcmpTypeRow t4 =
          PacketDecodeScreen.icmpTypes.firstWhere((t) => t.type == 4);
      expect(t4.name, 'Source Quench');
      expect(t4.deprecated, isTrue);
    });

    test('ICMP echo request = 8, echo reply = 0', () {
      expect(
        PacketDecodeScreen.icmpTypes.firstWhere((t) => t.type == 8).name,
        'Echo Request',
      );
      expect(
        PacketDecodeScreen.icmpTypes.firstWhere((t) => t.type == 0).name,
        'Echo Reply',
      );
    });

    test('ICMP Type 3 code 3 = Port unreachable, code 4 = path MTU', () {
      final IcmpCodeRow c3 =
          PacketDecodeScreen.icmpType3Codes.firstWhere((c) => c.code == 3);
      final IcmpCodeRow c4 =
          PacketDecodeScreen.icmpType3Codes.firstWhere((c) => c.code == 4);
      expect(c3.meaning, 'Port unreachable');
      expect(c4.meaning.contains('DF set'), isTrue);
    });

    test('ICMPv6 echo request = 128, and NDP has the 5 messages 133-137', () {
      expect(
        PacketDecodeScreen.icmpv6Types.firstWhere((t) => t.type == 128).name,
        'Echo Request',
      );
      final List<int> ndp =
          PacketDecodeScreen.icmpv6Ndp.map((t) => t.type).toList();
      expect(ndp, <int>[133, 134, 135, 136, 137]);
    });
  });

  group('voice: no em dash in any dataset string', () {
    // Belt-and-suspenders alongside the app-wide voice guard.
    Iterable<String> allStrings() sync* {
      for (final PacketField f in <PacketField>[
        ...PacketDecodeScreen.ipv4Header,
        ...PacketDecodeScreen.ipv6Header,
        ...PacketDecodeScreen.tcpHeader,
        ...PacketDecodeScreen.udpHeader,
        ...PacketDecodeScreen.icmpHeader,
        ...PacketDecodeScreen.icmpv6Header,
      ]) {
        yield f.field;
        yield f.meaning;
      }
      for (final TcpFlagRow f in PacketDecodeScreen.tcpFlags) {
        yield f.flag;
        yield f.meaning;
      }
      for (final TcpState s in PacketDecodeScreen.tcpStates) {
        yield s.meaning;
      }
      for (final IcmpTypeRow t in <IcmpTypeRow>[
        ...PacketDecodeScreen.icmpTypes,
        ...PacketDecodeScreen.icmpv6Types,
        ...PacketDecodeScreen.icmpv6Ndp,
      ]) {
        yield t.name;
        yield t.codes;
      }
    }

    test('no em dash', () {
      for (final String s in allStrings()) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
      }
    });
  });

  group('PacketDecodeScreen widget', () {
    testWidgets('renders the title and key section headings (phone)',
        (tester) async {
      await _withViewport(tester, const Size(375, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const PacketDecodeScreen(),
          ),
        );
        expect(find.text('Packet Decode'), findsWidgets);
        expect(find.text('IPv4 header'), findsOneWidget);
        expect(find.text('TCP flags (control bits 104-111)'), findsOneWidget);
        expect(find.text('Common IP protocol numbers'), findsOneWidget);
        // No search field: this is a static stacked reference.
        expect(find.byType(TextField), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 8000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const PacketDecodeScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
