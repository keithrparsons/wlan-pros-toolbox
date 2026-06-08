// Tests for the IP Address Reference screen.
//
// Datasets are sourced verbatim from the verified addressing dataset
// (Deliverables/2026-06-08-reference-batch/addressing-data.md, Section 1). These
// tests assert the load-bearing anchor rows so a future edit cannot silently
// drift a value, confirm the multicast-registry split flag is set on exactly the
// two flagged blocks, and run a phone-viewport widget test (mirrors the poe
// reference test) confirming the read-only screen renders without a RenderFlex
// overflow at 320/375/768/1280 widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ip_address_reference_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('IPv4 special-purpose blocks — match the verified dataset', () {
    SpecialUseBlock v4For(String cidr) => IpAddressReferenceScreen.ipv4Blocks
        .firstWhere((SpecialUseBlock b) => b.cidr == cidr);

    test('10.0.0.0/8 = Private-Use (RFC 1918)', () {
      final SpecialUseBlock b = v4For('10.0.0.0/8');
      expect(b.purpose, 'Private-Use (RFC 1918)');
      expect(b.rfc, 'RFC 1918');
      expect(b.multicastRegistry, isFalse);
    });

    test('100.64.0.0/10 = Shared Address Space (CGNAT), RFC 6598', () {
      final SpecialUseBlock b = v4For('100.64.0.0/10');
      expect(b.purpose, contains('Shared Address Space'));
      expect(b.rfc, 'RFC 6598');
    });

    test('169.254.0.0/16 = Link-Local (APIPA), RFC 3927', () {
      final SpecialUseBlock b = v4For('169.254.0.0/16');
      expect(b.purpose, contains('Link-Local'));
      expect(b.rfc, 'RFC 3927');
    });

    test('224.0.0.0/4 = Multicast, flagged multicast-registry', () {
      final SpecialUseBlock b = v4For('224.0.0.0/4');
      expect(b.purpose, contains('Multicast'));
      expect(b.multicastRegistry, isTrue, reason: 'split-registry flag');
      expect(b.rfc, contains('RFC 1112'));
    });

    test('25 IPv4 blocks; exactly one multicast-registry flag', () {
      expect(IpAddressReferenceScreen.ipv4Blocks.length, 25);
      final int flagged = IpAddressReferenceScreen.ipv4Blocks
          .where((SpecialUseBlock b) => b.multicastRegistry)
          .length;
      expect(flagged, 1, reason: 'only 224.0.0.0/4 lives in the IPv4 '
          'multicast registry');
    });
  });

  group('IPv6 special-purpose blocks — match the verified dataset', () {
    SpecialUseBlock v6For(String cidr) => IpAddressReferenceScreen.ipv6Blocks
        .firstWhere((SpecialUseBlock b) => b.cidr == cidr);

    test('::1/128 = Loopback (RFC 4291)', () {
      final SpecialUseBlock b = v6For('::1/128');
      expect(b.purpose, 'Loopback Address');
      expect(b.rfc, 'RFC 4291');
    });

    test('fc00::/7 = Unique-Local (ULA)', () {
      final SpecialUseBlock b = v6For('fc00::/7');
      expect(b.purpose, contains('Unique-Local'));
    });

    test('2001:db8::/32 = Documentation (RFC 3849)', () {
      final SpecialUseBlock b = v6For('2001:db8::/32');
      expect(b.purpose, 'Documentation');
      expect(b.rfc, 'RFC 3849');
    });

    test('ff00::/8 = Multicast, flagged multicast-registry (RFC 4291 §2.7)', () {
      final SpecialUseBlock b = v6For('ff00::/8');
      expect(b.purpose, 'Multicast');
      expect(b.multicastRegistry, isTrue, reason: 'split-registry flag');
      expect(b.rfc, 'RFC 4291 §2.7');
    });

    test('20 IPv6 blocks; exactly one multicast-registry flag', () {
      expect(IpAddressReferenceScreen.ipv6Blocks.length, 20);
      final int flagged = IpAddressReferenceScreen.ipv6Blocks
          .where((SpecialUseBlock b) => b.multicastRegistry)
          .length;
      expect(flagged, 1, reason: 'only ff00::/8 lives in the IPv6 multicast '
          'registry');
    });
  });

  group('IPv6 notation rules', () {
    test('six rules; zero-compression rule present', () {
      expect(IpAddressReferenceScreen.ipv6Notation.length, 6);
      final bool hasCompression = IpAddressReferenceScreen.ipv6Notation
          .any((Ipv6NotationRule r) => r.rule.contains('Zero compression'));
      expect(hasCompression, isTrue);
    });

    test('no em dash in any notation definition', () {
      for (final Ipv6NotationRule r in IpAddressReferenceScreen.ipv6Notation) {
        expect(r.definition.contains('—'), isFalse, reason: 'no em dash');
      }
    });
  });

  group('IpAddressReferenceScreen widget', () {
    testWidgets('renders title and both block table headings in a phone '
        'viewport', (tester) async {
      await _withViewport(tester, const Size(375, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const IpAddressReferenceScreen(),
          ),
        );

        expect(find.text('IP Address Reference'), findsWidgets);
        expect(find.text('IPv4 special-purpose blocks'), findsOneWidget);
        expect(find.text('IPv6 special-purpose blocks'), findsOneWidget);
        expect(find.text('IPv6 notation rules'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1400), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const IpAddressReferenceScreen(),
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
