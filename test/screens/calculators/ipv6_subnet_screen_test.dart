// Tests for the IPv6 Subnet calculator.
//
// The math is verified against the RF Tools PWA reference (app.js calcIPv6 /
// expandIPv6 / compressIPv6 / detectIPv6Type, line 2155+). Expected strings
// below were produced by running the exact PWA functions on the same inputs, so
// the native app and PWA agree field-for-field on expansion, the 128-bit math,
// host counts, and type detection.
//
// COMPRESSION IS THE ONE DIVERGENCE, and it is Keith's 2026-08-02 ruling. This
// file used to assert the PWA's quirk verbatim — "2001:db8::" → "2001:db8",
// "::1" → "1" — under the reasoning that matching the reference was the
// contract. Those strings are not IPv6 addresses, and the screen rejected them
// when they were pasted back into its own field. The assertions below now state
// the RFC 5952 form, and the paste-back group makes the property structural:
// whatever the screen prints, the screen must accept.
//
// Two widget tests confirm the screen pumps in a phone viewport and that the
// rendered Compressed row survives a round trip through the address field.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ipv6_subnet_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/value_row.dart';
import 'package:wlan_pros_toolbox/services/network/ipv6_transition.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

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

  group('compressIPv6 — RFC 5952, both ends of the zero run', () {
    test('all zeros compresses to ::', () {
      expect(
        Ipv6SubnetScreen.compressIPv6('0000:0000:0000:0000:0000:0000:0000:0000'),
        '::',
      );
    });

    test('a zero run at the START keeps its leading "::"', () {
      // Was asserted as "1" — the PWA quirk. Keith ruled it out 2026-08-02.
      expect(
        Ipv6SubnetScreen.compressIPv6('0000:0000:0000:0000:0000:0000:0000:0001'),
        '::1',
      );
      expect(
        Ipv6SubnetScreen.compressIPv6('0000:0000:0000:0000:0000:ffff:c000:0201'),
        '::ffff:c000:201',
      );
    });

    test('a zero run at the END keeps its trailing "::"', () {
      // Was asserted as "2001:db8" / "fe80".
      expect(
        Ipv6SubnetScreen.compressIPv6('2001:0db8:0000:0000:0000:0000:0000:0000'),
        '2001:db8::',
      );
      expect(
        Ipv6SubnetScreen.compressIPv6('fe80:0000:0000:0000:0000:0000:0000:0000'),
        'fe80::',
      );
    });

    test('a run of ONE zero group is never collapsed (RFC 5952 §4.2.2)', () {
      expect(
        Ipv6SubnetScreen.compressIPv6('2001:0db8:0000:0001:0001:0001:0001:0001'),
        '2001:db8:0:1:1:1:1:1',
      );
    });

    test('the screen and the transition decoder share one compressor', () {
      // HIGH-1 in one line: these two call sites are ~200 px apart on screen.
      expect(
        Ipv6SubnetScreen.compressIPv6('0000:0000:0000:0000:0000:ffff:c000:0201'),
        Ipv6Transition.encode('192.0.2.1').mappedHex,
      );
    });
  });

  group('calculate — PWA field-for-field, RFC 5952 for the address text', () {
    test('2001:db8::/32', () {
      final Ipv6Result r = Ipv6SubnetScreen.calculate('2001:db8::', 32);
      expect(r.isValid, isTrue);
      expect(r.expanded, '2001:0db8:0000:0000:0000:0000:0000:0000');
      expect(r.compressed, '2001:db8::');
      expect(r.network, '2001:db8::/32');
      expect(r.first, '2001:db8::');
      expect(r.last, '2001:db8:ffff:ffff:ffff:ffff:ffff:ffff');
      expect(r.hosts, 'More than 2^63');
      expect(r.type, 'Documentation (2001:db8::/32)');
    });

    test('2001:db8::1/64', () {
      final Ipv6Result r = Ipv6SubnetScreen.calculate('2001:db8::1', 64);
      expect(r.expanded, '2001:0db8:0000:0000:0000:0000:0000:0001');
      expect(r.compressed, '2001:db8::1');
      expect(r.network, '2001:db8::/64');
      expect(r.first, '2001:db8::');
      expect(r.last, '2001:db8::ffff:ffff:ffff:ffff');
      expect(r.hosts, 'More than 2^63');
    });

    test('fe80::1/10 detects link-local', () {
      final Ipv6Result r = Ipv6SubnetScreen.calculate('fe80::1', 10);
      // Was 'fe80/10'. Link-local is the most common IPv6 a WLAN engineer
      // touches, and a bare "fe80" prefix is not an address.
      expect(r.network, 'fe80::/10');
      expect(r.last, 'febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff');
      expect(r.type, 'Link-Local (fe80::/10)');
    });

    test('::1/128 is a single address (loopback)', () {
      final Ipv6Result r = Ipv6SubnetScreen.calculate('::1', 128);
      expect(r.network, '::1/128');
      expect(r.first, '::1');
      expect(r.last, '::1');
      expect(r.hosts, '1 address');
      expect(r.type, 'Loopback (::1)');
    });

    test('::/0 covers the whole space and detects unspecified', () {
      final Ipv6Result r = Ipv6SubnetScreen.calculate('::', 0);
      expect(r.network, '::/0');
      expect(r.first, '::');
      expect(r.last, 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff');
      expect(r.hosts, 'More than 2^63');
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

  // PASTE-BACK, added 2026-08-02 with Keith's compressor ruling. This is the
  // property Vera's gate broke by hand: the screen printed
  // "Compressed: ffff:c000:201" and then answered "Invalid IPv6 address
  // format." when that exact string was pasted back into its own field
  // (Deliverables/2026-08-02-ip-address-math-gate/evidence/paste-back-proof/).
  //
  // These cases FAILED RED against the PWA-parity compressor — every address
  // whose longest zero run touches either end lost half its "::", so the row
  // was not an IPv6 literal at all. They are the guard that the Subnet card
  // and the transition card can never print two different compressions of the
  // same address again.
  group('every address the screen prints, the screen accepts (paste-back)', () {
    /// Feeds each printed address row back through [Ipv6SubnetScreen.calculate]
    /// and requires two things of it: the screen accepts its own output, and
    /// that output is already canonical (compressing it again returns it
    /// unchanged). The second half is what makes this more than a validity
    /// check — a fixed point cannot be reached by a compressor that mangles.
    void expectEveryRowPastesBack(String input, int prefix) {
      final Ipv6Result r = Ipv6SubnetScreen.calculate(input, prefix);
      expect(r.isValid, isTrue, reason: r.error ?? 'setup: $input/$prefix');

      // The Network row carries "/prefix"; the address is everything before it.
      final String networkAddr = r.network.substring(
        0,
        r.network.lastIndexOf('/'),
      );
      final Map<String, String> printed = <String, String>{
        'Compressed': r.compressed,
        'Network': networkAddr,
        'First': r.first,
        'Last': r.last,
      };

      printed.forEach((String row, String value) {
        final Ipv6Result back = Ipv6SubnetScreen.calculate(value, prefix);
        expect(
          back.isValid,
          isTrue,
          reason:
              'for input "$input/$prefix" the $row row printed "$value", '
              'which this same screen rejects: ${back.error}',
        );
        expect(
          back.compressed,
          value,
          reason:
              'the $row row printed "$value", which is not the canonical form '
              'of the address it names (recompresses to "${back.compressed}")',
        );
      });

      // The Compressed row specifically must name the SAME 128 bits it was
      // computed from — a valid-but-different address would pass the two
      // checks above and still be a wrong answer.
      expect(
        Ipv6SubnetScreen.calculate(r.compressed, prefix).expanded,
        r.expanded,
        reason: 'the Compressed row must round-trip to the same address',
      );
    }

    test('IPv4-mapped — the gate\'s own case', () {
      expectEveryRowPastesBack('::ffff:192.0.2.1', 96);
    });

    test('link-local, the most common IPv6 on a WLAN', () {
      expectEveryRowPastesBack('fe80::1', 10);
      expectEveryRowPastesBack('fe80::1', 64);
    });

    test('a zone index does not change what is printed', () {
      expectEveryRowPastesBack('fe80::1%en0', 64);
    });

    test('documentation prefix, both ends of the zero run', () {
      expectEveryRowPastesBack('2001:db8::', 32);
      expectEveryRowPastesBack('2001:db8::1', 64);
    });

    test('loopback and unspecified', () {
      expectEveryRowPastesBack('::1', 128);
      expectEveryRowPastesBack('::', 0);
    });

    test('6to4 prefix, zero run at the end', () {
      expectEveryRowPastesBack('2002:c000:201::', 16);
    });

    test('the Subnet card and the transition card agree, character for '
        'character', () {
      // HIGH-1: the two cards sit ~200 px apart on one screen. They must not
      // print two different compressions of one address.
      const String literal = '::ffff:192.0.2.1';
      final Ipv6Result r = Ipv6SubnetScreen.calculate(literal, 96);
      expect(
        r.compressed,
        Ipv6Transition.encode('192.0.2.1').mappedHex,
        reason: 'the Subnet card and the transition card must use one '
            'compressor',
      );
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
      // ENUMERATE the fields, then assert the count MATCHES the enumeration.
      // This assertion used to be a bare `findsNWidgets(2)` with the comment
      // "address + prefix". When the transition section added its IPv4 field
      // on 2026-08-02 the count broke, and a bare count cannot say WHICH field
      // is new or whether it was meant to be there. The labels are the
      // contract; the count exists only so a fourth, un-enumerated field
      // fails here instead of shipping unnoticed.
      const List<String> expectedFields = <String>[
        'IPv6 address',
        'Prefix length',
        'IPv4 address', // transition section, added 2026-08-02
      ];
      for (final String label in expectedFields) {
        expect(
          find.text(label),
          findsOneWidget,
          reason: 'the "$label" input is part of this screen\'s contract',
        );
      }
      expect(
        find.byType(TextField),
        findsNWidgets(expectedFields.length),
        reason: 'a TextField exists that is not in expectedFields — add it '
            'there (with its label) or remove it from the screen',
      );

      // Seeded with 2001:db8::1 /32 → Documentation type row renders.
      expect(find.text('Documentation (2001:db8::/32)'), findsOneWidget);
    });

    testWidgets('pasting the rendered Compressed row back into the field is '
        'accepted, not rejected', (tester) async {
      // The RENDERED form of the paste-back proof. Nothing here hardcodes what
      // the screen ought to print: the test reads whatever the Compressed row
      // actually renders and types that string back into the address field.
      // Against the parity compressor this rendered "ffff:c000:201" and the
      // screen answered "Check your input", which is the defect Vera captured
      // in evidence/paste-back-proof/paste_ffff_c000_201.png.
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const Ipv6SubnetScreen()),
      );
      await tester.pumpAndSettle();

      final Finder addressField = find.byWidgetPredicate(
        (Widget w) => w is TextField && w.decoration?.hintText == '2001:db8::1',
        description: 'the IPv6 address field',
      );

      String renderedRow(String label) => tester
          .widget<ValueRow>(
            find.byWidgetPredicate(
              (Widget w) => w is ValueRow && w.label == label,
              description: 'the $label row',
            ),
          )
          .value!;

      await tester.enterText(addressField, '::ffff:192.0.2.1');
      await tester.pumpAndSettle();

      final String expandedBefore = renderedRow('Expanded');
      final String printed = renderedRow('Compressed');

      await tester.enterText(addressField, printed);
      await tester.pumpAndSettle();

      expect(
        find.text('Check your input'),
        findsNothing,
        reason: 'the screen rejected its own printed value "$printed"',
      );
      expect(
        renderedRow('Expanded'),
        expandedBefore,
        reason: 'pasting "$printed" back must name the same address',
      );
    });

    // MEDIUM-1, Vera's gate 2026-08-02. "fe80::1%25" rendered a bare
    // "Zone: 25" — one of two defensible readings, printed as though it were
    // the only one. The parser is right to stand on a reading (RFC 4007 keeps
    // the zone outside the 128 bits, so nothing computed depends on it); the
    // ROW was wrong to state it without the other reading. These fail red
    // against a screen that renders the value alone.
    testWidgets('an ambiguous zone names its other reading on the screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const Ipv6SubnetScreen()),
      );
      await tester.pumpAndSettle();

      final Finder addressField = find.byWidgetPredicate(
        (Widget w) => w is TextField && w.decoration?.hintText == '2001:db8::1',
        description: 'the IPv6 address field',
      );

      // A bare "%25": ifindex 25, or a URL-escaped "%" with the name cut off.
      await tester.enterText(addressField, 'fe80::1%25');
      await tester.pumpAndSettle();
      expect(find.text('Zone'), findsOneWidget);
      expect(find.textContaining('may have been cut off'), findsOneWidget);

      // "%2512": the URL form of 12, or a plain ifindex 2512. BOTH numbers
      // have to be on screen, or the row is still asserting one of them.
      await tester.enterText(addressField, 'fe80::1%2512');
      await tester.pumpAndSettle();
      expect(find.textContaining('the zone is 12'), findsOneWidget);
      expect(find.textContaining('it would be 2512'), findsOneWidget);

      // A name has one reading, so the line says why it changed nothing
      // instead of inventing an alternative.
      await tester.enterText(addressField, 'fe80::1%en0');
      await tester.pumpAndSettle();
      expect(find.textContaining('changes nothing above'), findsOneWidget);
      expect(find.textContaining('cut off'), findsNothing);
    });

    testWidgets('the copy payload carries the zone caveat when the reading is '
        'a guess, and not when it is not', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const Ipv6SubnetScreen()),
      );
      await tester.pumpAndSettle();

      final Finder addressField = find.byWidgetPredicate(
        (Widget w) => w is TextField && w.decoration?.hintText == '2001:db8::1',
        description: 'the IPv6 address field',
      );
      String? payload() => tester
          .widget<AppCopyAction>(find.byType(AppCopyAction))
          .textBuilder();

      await tester.enterText(addressField, 'fe80::1%25');
      await tester.pumpAndSettle();
      // Pasting a bare "Zone: 25" into a ticket would re-commit the same
      // defect in another medium.
      expect(payload(), contains('Zone: 25'));
      expect(payload(), contains('Zone note:'));

      await tester.enterText(addressField, 'fe80::1%en0');
      await tester.pumpAndSettle();
      expect(payload(), contains('Zone: en0'));
      expect(
        payload(),
        isNot(contains('Zone note:')),
        reason: 'an unambiguous zone needs no qualifier in a pasted ticket',
      );
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

      // Clear the ADDRESS field → result panel disappears. Found by its hint
      // rather than by position: the transition section added a third field
      // on 2026-08-02, and `.at(0)` only happened to still be the address
      // because the form card renders above the transition card. A positional
      // finder silently re-aims at whatever moves into slot 0.
      await tester.enterText(
        find.byWidgetPredicate(
          (Widget w) =>
              w is TextField && w.decoration?.hintText == '2001:db8::1',
          description: 'the IPv6 address field',
        ),
        '',
      );
      await tester.pumpAndSettle();
      expect(find.text('Subnet'), findsNothing);
    });
  });
}
