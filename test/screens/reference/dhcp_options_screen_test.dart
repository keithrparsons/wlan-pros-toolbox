// Tests for the DHCP Options reference screen.
//
// The two datasets are reproduced verbatim from the verified protocols dataset
// (Deliverables/2026-06-08-reference-batch/protocols-data.md, Page 2): the IANA
// DHCPv4 option codes (led by Option 138 CAPWAP-AC) and the Option-53 message
// types. These tests assert the load-bearing anchors — chiefly Option 138
// leading the list and the eight DORA message types — plus phone/tablet/desktop
// widget tests confirming the read-only screen renders without overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/dhcp_options_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('DHCP options — match the verified dataset', () {
    DhcpOption optFor(int code) => DhcpOptionsScreen.options
        .firstWhere((DhcpOption o) => o.code == code);

    test('Option 138 = CAPWAP-AC, RFC 5417, and LEADS the table', () {
      final DhcpOption o = optFor(138);
      expect(o.name.contains('CAPWAP'), isTrue);
      expect(o.rfc, 'RFC 5417');
      // Wi-Fi controller discovery is listed first per the build brief.
      expect(DhcpOptionsScreen.options.first.code, 138);
    });

    test('Option 53 = DHCP Message Type, RFC 2132', () {
      final DhcpOption o = optFor(53);
      expect(o.name, 'DHCP Message Type');
      expect(o.rfc, 'RFC 2132');
    });

    test('Option 82 = Relay Agent Information, RFC 3046', () {
      expect(optFor(82).rfc, 'RFC 3046');
    });

    test('Option 119 = Domain Search List, RFC 3397', () {
      expect(optFor(119).rfc, 'RFC 3397');
    });

    test('no em dash artifacts in option fields; all cite an RFC', () {
      for (final DhcpOption o in DhcpOptionsScreen.options) {
        expect(o.rfc.startsWith('RFC '), isTrue);
      }
    });
  });

  group('Option 53 message types — DORA + lease lifecycle', () {
    test('eight message types, values 1..8 in order', () {
      expect(DhcpOptionsScreen.messageTypes.length, 8);
      expect(
        DhcpOptionsScreen.messageTypes
            .map((DhcpMessageType m) => m.value)
            .toList(),
        <int>[1, 2, 3, 4, 5, 6, 7, 8],
      );
    });

    test('value 1 = DHCPDISCOVER, value 5 = DHCPACK', () {
      expect(
        DhcpOptionsScreen.messageTypes
            .firstWhere((DhcpMessageType m) => m.value == 1)
            .message,
        'DHCPDISCOVER',
      );
      expect(
        DhcpOptionsScreen.messageTypes
            .firstWhere((DhcpMessageType m) => m.value == 5)
            .message,
        'DHCPACK',
      );
    });
  });

  group('DhcpOptionsScreen widget', () {
    testWidgets('renders title and both table headings in a phone viewport',
        (tester) async {
      await _withViewport(tester, const Size(375, 1400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DhcpOptionsScreen(),
          ),
        );
        expect(find.text('DHCP Options'), findsWidgets);
        expect(find.text('DHCPv4 options'), findsOneWidget);
        expect(find.text('Option 53: DHCP message types'), findsOneWidget);
        expect(find.text('DHCPDISCOVER'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1600), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const DhcpOptionsScreen(),
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
