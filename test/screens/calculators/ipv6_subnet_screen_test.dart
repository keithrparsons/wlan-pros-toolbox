// Tests for the IPv6 Subnet calculator.
//
// The math is verified against the RF Tools PWA reference (app.js calcIPv6 /
// expandIPv6 / compressIPv6 / detectIPv6Type, line 2155+). Expected strings
// below were produced by running the exact PWA functions on the same inputs, so
// the native app and PWA agree field-for-field — including the PWA's
// compression quirk where a trailing all-zero run drops its closing "::"
// (e.g. "2001:db8::" → "2001:db8", "::1" → "1"). Matching the reference is the
// contract here, so those strings are asserted verbatim.
//
// One widget test confirms the screen pumps and renders in a phone viewport.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ipv6_subnet_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('expandIPv6 — matches PWA expandIPv6', () {
    test('compressed 2001:db8::1 expands to 8 padded groups', () {
      expect(
        Ipv6SubnetScreen.expandIPv6('2001:db8::1'),
        '2001:0db8:0000:0000:0000:0000:0000:0001',
      );
    });

    test(':: expands to all zeros', () {
      expect(
        Ipv6SubnetScreen.expandIPv6('::'),
        '0000:0000:0000:0000:0000:0000:0000:0000',
      );
    });

    test('::1 expands to the loopback', () {
      expect(
        Ipv6SubnetScreen.expandIPv6('::1'),
        '0000:0000:0000:0000:0000:0000:0000:0001',
      );
    });

    test('an already-full address is just zero-padded per group', () {
      expect(
        Ipv6SubnetScreen.expandIPv6('2001:0db8:0:42:0:8a2e:370:7334'),
        '2001:0db8:0000:0042:0000:8a2e:0370:7334',
      );
    });

    test('more than one "::" run is rejected as malformed', () {
      expect(
        () => Ipv6SubnetScreen.expandIPv6('2001::db8::1'),
        throwsFormatException,
      );
    });
  });

  group('compressIPv6 — matches PWA compressIPv6 (incl. its quirks)', () {
    test('all zeros compresses to ::', () {
      expect(
        Ipv6SubnetScreen.compressIPv6('0000:0000:0000:0000:0000:0000:0000:0000'),
        '::',
      );
    });

    test('loopback compresses to PWA "1" (trailing-run quirk)', () {
      expect(
        Ipv6SubnetScreen.compressIPv6('0000:0000:0000:0000:0000:0000:0000:0001'),
        '1',
      );
    });

    test('2001:db8 prefix compresses to PWA "2001:db8" (trailing-run quirk)',
        () {
      expect(
        Ipv6SubnetScreen.compressIPv6('2001:0db8:0000:0000:0000:0000:0000:0000'),
        '2001:db8',
      );
    });
  });

  group('calculate — matches PWA calcIPv6 field-for-field', () {
    test('2001:db8::/32', () {
      final Ipv6Result r = Ipv6SubnetScreen.calculate('2001:db8::', 32);
      expect(r.isValid, isTrue);
      expect(r.expanded, '2001:0db8:0000:0000:0000:0000:0000:0000');
      expect(r.compressed, '2001:db8');
      expect(r.network, '2001:db8/32');
      expect(r.first, '2001:db8');
      expect(r.last, '2001:db8:ffff:ffff:ffff:ffff:ffff:ffff');
      expect(r.hosts, 'More than 2⁶³');
      expect(r.type, 'Documentation (2001:db8::/32)');
    });

    test('2001:db8::1/64', () {
      final Ipv6Result r = Ipv6SubnetScreen.calculate('2001:db8::1', 64);
      expect(r.expanded, '2001:0db8:0000:0000:0000:0000:0000:0001');
      expect(r.compressed, '2001:db8::1');
      expect(r.network, '2001:db8/64');
      expect(r.first, '2001:db8');
      expect(r.last, '2001:db8::ffff:ffff:ffff:ffff');
      expect(r.hosts, 'More than 2⁶³');
    });

    test('fe80::1/10 detects link-local', () {
      final Ipv6Result r = Ipv6SubnetScreen.calculate('fe80::1', 10);
      expect(r.network, 'fe80/10');
      expect(r.last, 'febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff');
      expect(r.type, 'Link-Local (fe80::/10)');
    });

    test('::1/128 is a single address (loopback)', () {
      final Ipv6Result r = Ipv6SubnetScreen.calculate('::1', 128);
      expect(r.network, '1/128');
      expect(r.first, '1');
      expect(r.last, '1');
      expect(r.hosts, '1 address');
      expect(r.type, 'Loopback (::1)');
    });

    test('::/0 covers the whole space and detects unspecified', () {
      final Ipv6Result r = Ipv6SubnetScreen.calculate('::', 0);
      expect(r.network, '::/0');
      expect(r.first, '::');
      expect(r.last, 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff');
      expect(r.hosts, 'More than 2⁶³');
      expect(r.type, 'Unspecified (::)');
    });

    test('host count is exact and thousands-grouped below 2^63', () {
      // /96 → 32 host bits → 2^32 = 4,294,967,296 addresses.
      final Ipv6Result r = Ipv6SubnetScreen.calculate('2001:db8::', 96);
      expect(r.hosts, '2^32 = 4,294,967,296 addresses');
    });

    test('uppercase input is normalized like the PWA toLowerCase', () {
      final Ipv6Result r = Ipv6SubnetScreen.calculate('2001:DB8::1', 64);
      expect(r.compressed, '2001:db8::1');
    });
  });

  group('calculate — error states', () {
    test('empty address is rejected', () {
      final Ipv6Result r = Ipv6SubnetScreen.calculate('', 64);
      expect(r.isValid, isFalse);
      expect(r.error, 'Enter an IPv6 address.');
    });

    test('out-of-range prefix is rejected', () {
      expect(Ipv6SubnetScreen.calculate('2001:db8::1', 129).error,
          'Prefix must be 0–128.');
      expect(Ipv6SubnetScreen.calculate('2001:db8::1', -1).error,
          'Prefix must be 0–128.');
    });

    test('malformed address is rejected', () {
      expect(
        Ipv6SubnetScreen.calculate('not:an:address', 64).isValid,
        isFalse,
      );
      expect(
        Ipv6SubnetScreen.calculate('gggg::1', 64).isValid,
        isFalse,
      );
      // Nine groups — too long for IPv6.
      expect(
        Ipv6SubnetScreen.calculate('1:2:3:4:5:6:7:8:9', 64).isValid,
        isFalse,
      );
    });
  });

  group('Ipv6SubnetScreen widget', () {
    testWidgets('renders title, input labels, and a seeded result in a phone '
        'viewport', (tester) async {
      // Phone viewport, mirroring widget_test.dart `_withViewport`.
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Ipv6SubnetScreen(),
        ),
      );
      // Drain the post-frame seed recompute.
      await tester.pumpAndSettle();

      expect(find.text('IPv6 Subnet Calculator'), findsWidgets);
      expect(find.text('IPv6 address'), findsOneWidget);
      expect(find.text('Prefix length'), findsOneWidget);
      // Two inputs: address + prefix.
      expect(find.byType(TextField), findsNWidgets(2));

      // Seeded with 2001:db8::1 /32 → Documentation type row renders.
      expect(find.text('Documentation (2001:db8::/32)'), findsOneWidget);
    });

    testWidgets('clearing the address blanks the result with no crash',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Ipv6SubnetScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Subnet'), findsOneWidget);

      // Clear the address field (first TextField) → result panel disappears.
      await tester.enterText(find.byType(TextField).at(0), '');
      await tester.pumpAndSettle();
      expect(find.text('Subnet'), findsNothing);
    });
  });
}
