// Tests for the Naming & Addressing Conventions screen.
//
// Datasets are sourced verbatim from the verified addressing dataset
// (Deliverables/2026-06-08-reference-batch/addressing-data.md, Section 3). These
// tests assert the load-bearing anchor rows (hostname length limits, MAC EUI
// definitions, the U/L and I/G bit meanings), confirm the named MAC bit-field
// diagram degrades gracefully when its asset is absent, and run a phone-viewport
// widget test (mirrors the poe reference test) confirming the read-only screen
// renders without a RenderFlex overflow at 320/375/768/1280 widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/mac_bit_field_diagram.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/naming_conventions_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Hostname / DNS label rules — match the verified dataset', () {
    ConventionRule ruleFor(String name) => NamingConventionsScreen.hostnameRules
        .firstWhere((ConventionRule r) => r.name == name);

    test('Max label length = 63 octets', () {
      expect(ruleFor('Max label length').spec, contains('63 octets'));
    });

    test('Max FQDN length = 253 characters (255 octets on the wire)', () {
      final ConventionRule r = ruleFor('Max FQDN length');
      expect(r.spec, contains('253 characters'));
      expect(r.spec, contains('255 octets'));
    });

    test('First character may be a letter or a digit (RFC 1123 relaxation)', () {
      final ConventionRule r = ruleFor('First character');
      expect(r.spec, contains('letter OR a digit'));
      expect(r.source, contains('RFC 1123'));
    });

    test('eight hostname rules', () {
      expect(NamingConventionsScreen.hostnameRules.length, 8);
    });
  });

  group('MAC format — EUI-48 / EUI-64', () {
    ConventionRule ruleFor(String name) => NamingConventionsScreen.macFormat
        .firstWhere((ConventionRule r) => r.name == name);

    test('EUI-48 = 48-bit, 6 octets, 12 hex digits', () {
      final ConventionRule r = ruleFor('EUI-48');
      expect(r.spec, contains('48-bit'));
      expect(r.spec, contains('12 hex digits'));
    });

    test('Modified EUI-64 inserts FF-FE and inverts U/L (RFC 4291 App A)', () {
      final ConventionRule r = ruleFor('Modified EUI-64 (IPv6)');
      expect(r.spec, contains('FF-FE'));
      expect(r.spec, contains('invert'));
      expect(r.source, contains('RFC 4291'));
    });
  });

  group('U/L and I/G bits — first octet', () {
    MacBit bitFor(String bit) =>
        NamingConventionsScreen.macBits.firstWhere((MacBit b) => b.bit == bit);

    test('I/G bit 0: individual (unicast) vs group (multicast)', () {
      final MacBit b = bitFor('I/G');
      expect(b.position, contains('bit 0'));
      expect(b.value0, contains('Individual'));
      expect(b.value1, contains('Group'));
    });

    test('U/L bit 1: universal vs locally administered', () {
      final MacBit b = bitFor('U/L');
      expect(b.position, contains('bit 1'));
      expect(b.value0, contains('Universally administered'));
      expect(b.value1, contains('Locally administered'));
    });

    test('low-nibble note names the 2/6/A/E rule', () {
      expect(NamingConventionsScreen.nibbleNote, contains('2/6/A/E'));
    });

    test('CID concept: U/L bit set so it never collides with OUI space', () {
      final ConventionRule cid = NamingConventionsScreen.ouiConcepts
          .firstWhere((ConventionRule r) => r.name == 'CID');
      expect(cid.spec, contains('U/L bit set to 1'));
      expect(cid.spec, contains('never collide'));
    });
  });

  group('NamingConventionsScreen widget', () {
    // The named MAC bit-field diagram must degrade gracefully when absent.
    setUp(() => MacBitFieldDiagram.debugSetBundled(<String>{}));
    tearDown(MacBitFieldDiagram.debugReset);

    testWidgets('renders title and all four section headings with the diagram '
        'absent', (tester) async {
      await _withViewport(tester, const Size(375, 1600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const NamingConventionsScreen(),
          ),
        );

        expect(find.text('Naming & Addressing Conventions'), findsWidgets);
        expect(find.text('Hostname / DNS label rules'), findsOneWidget);
        expect(find.text('MAC format (EUI-48 / EUI-64)'), findsOneWidget);
        expect(find.text('U/L and I/G bits (first octet)'), findsOneWidget);
        expect(find.text('OUI / CID concept'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths '
        '(diagram absent)', (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1800), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const NamingConventionsScreen(),
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
