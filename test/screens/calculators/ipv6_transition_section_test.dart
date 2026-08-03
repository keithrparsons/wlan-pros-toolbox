// Ipv6SubnetScreen — the transition-address section added 2026-08-02.
//
// The decode and encode are unit-tested in test/services/ipv6_transition_test.
// This file asserts only what the SCREEN owes:
//
//   * the section reads the SAME address field as the breakdown above, so a
//     pasted log line only has to go in one place;
//   * a plain IPv6 address gets an honest "no IPv4 inside", never a fabricated
//     one;
//   * a Teredo address shows the server and the client port as well, because
//     the inverted client half is the thing that confuses people;
//   * the IPv4 field drives the other direction independently;
//   * the copy payload carries an embedded IPv4 when there is one and stays
//     silent when there is not;
//   * no overflow at phone, tablet and desktop widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ipv6_subnet_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

Widget _host() =>
    MaterialApp(theme: AppTheme.dark(), home: const Ipv6SubnetScreen());

/// Drive the REAL test viewport. A MediaQuery wrapper only changes what the
/// widget is TOLD about the window; the render surface stays at 800x600, so a
/// width assertion written that way cannot fail.
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

/// Field 0 is the IPv6 address, field 1 the prefix, field 2 the section's IPv4.
Finder _field(int i) => find.byType(TextField).at(i);

String? _copyPayload(WidgetTester tester) =>
    tester.widget<AppCopyAction>(find.byType(AppCopyAction)).textBuilder();

void main() {
  testWidgets('the seeded 2001:db8::1 carries no IPv4, and the screen says so '
      'rather than inventing one', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('IPv4 inside this address'), findsOneWidget);
    expect(find.text('No IPv4 inside'), findsOneWidget);
    expect(find.textContaining('no IPv4 address hiding'), findsOneWidget);
  });

  testWidgets('an IPv4-mapped address decodes from the SAME field the '
      'breakdown uses', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(_field(0), '::ffff:192.0.2.1');
    await tester.pumpAndSettle();

    // The decode's Format row. The encode block below it says "As
    // IPv4-mapped", deliberately worded differently so one screen never shows
    // the same string as both a label and a value.
    expect(find.text('IPv4-mapped'), findsOneWidget);
    expect(find.text('192.0.2.1'), findsWidgets);
    expect(find.text('RFC 4291 §2.5.5.2'), findsOneWidget);
    expect(find.text('The IPv4 peer'), findsOneWidget);
  });

  testWidgets('NAT64 decodes, and names the prefix it assumed', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(_field(0), '64:ff9b::192.0.2.33');
    await tester.pumpAndSettle();

    expect(find.text('NAT64 (well-known prefix)'), findsOneWidget);
    expect(find.text('192.0.2.33'), findsWidgets);
    expect(find.textContaining('not carried in the address'), findsOneWidget);
  });

  testWidgets('Teredo shows the server and the client port too', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(_field(0), '2001:0:4136:e378:8000:63bf:3fff:fdd2');
    await tester.pumpAndSettle();

    expect(find.text('Teredo'), findsOneWidget);
    expect(find.text('65.54.227.120'), findsOneWidget);
    expect(find.text('40000'), findsOneWidget);
    expect(find.text('192.0.2.45'), findsWidgets);
    expect(find.textContaining('INVERTED'), findsOneWidget);
  });

  testWidgets('6to4 names the value as a site endpoint, not a host', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(_field(0), '2002:c000:204::1');
    await tester.pumpAndSettle();

    expect(find.text('6to4'), findsOneWidget);
    expect(find.text('192.0.2.4'), findsWidgets);
    expect(find.textContaining("site's IPv4 endpoint"), findsOneWidget);
  });

  testWidgets('the IPv4 field drives the other direction on its own', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // Seeded with 192.0.2.1.
    expect(find.text('::ffff:192.0.2.1'), findsOneWidget);
    expect(find.text('::ffff:c000:201'), findsOneWidget);
    expect(find.text('64:ff9b::192.0.2.1'), findsOneWidget);
    expect(find.text('2002:c000:201::/48'), findsOneWidget);
    expect(find.text('::192.0.2.1'), findsOneWidget);

    await tester.enterText(_field(2), '203.0.113.77');
    await tester.pumpAndSettle();
    expect(find.text('::ffff:203.0.113.77'), findsOneWidget);
    expect(find.text('2002:cb00:714d::/48'), findsOneWidget);
    // The IPv6 breakdown above is untouched by the IPv4 field. Anchored on the
    // EXPANDED row, which is the same string under either compressor. Keith
    // ruled on the compressor 2026-08-02 and the Network row now prints
    // "2001:db8::/32"; the Network row's own values are asserted in
    // ipv6_subnet_screen_test.dart, so this test stays off them either way.
    expect(
      find.text('2001:0db8:0000:0000:0000:0000:0000:0001'),
      findsOneWidget,
    );
  });

  testWidgets('a malformed IPv4 in the section is an inline message, and does '
      'not disturb the breakdown', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(_field(2), '192.0.2.256');
    await tester.pumpAndSettle();

    expect(find.textContaining('0 to 255'), findsOneWidget);
    expect(
      find.text('2001:0db8:0000:0000:0000:0000:0000:0001'),
      findsOneWidget,
    );
  });

  testWidgets('the Copy payload carries an embedded IPv4 only when there is '
      'one', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // 2001:db8::1 has none, so the payload must not say anything about it.
    expect(_copyPayload(tester), isNot(contains('Embedded IPv4')));

    await tester.enterText(_field(0), '64:ff9b::192.0.2.33');
    await tester.pumpAndSettle();
    final String p = _copyPayload(tester)!;
    expect(p, contains('Embedded IPv4: 192.0.2.33'));
    expect(p, contains('NAT64 (well-known prefix)'));
    expect(p, contains('RFC 6052'));
  });

  // REGRESSION, live defect found 2026-08-02. The address field's input
  // formatter allowed `[0-9A-Fa-f:.]` only, so pasting `fe80::1%en0` off
  // `ifconfig` dropped the `%` and the `n` and left `fe80::1e0` — a valid but
  // DIFFERENT address, breaking down confidently and wrongly with nothing on
  // screen to say anything had been removed. This failed red before the fix.
  testWidgets('a pasted link-local is not silently mangled by the field', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(_field(0), 'fe80::1%en0');
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(_field(0)).controller!.text,
      'fe80::1%en0',
      reason: 'the field must keep every character the user pasted',
    );
    expect(
      find.text('fe80:0000:0000:0000:0000:0000:00e0:0000'),
      findsNothing,
      reason: 'the mangled fe80::1e0 breakdown must not appear',
    );
  });

  // A zone index (`%en0`) is what a link-local address looks like everywhere a
  // WLAN engineer meets one. It is stripped for the math, so the screen owes
  // the user an acknowledgement that it was read rather than ignored.
  testWidgets('a zoned link-local computes, and the Zone is shown back', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // No zone typed → no Zone row. Asserted FIRST so the row's appearance
    // below is a change and not a constant.
    expect(find.text('Zone'), findsNothing);

    await tester.enterText(_field(0), 'fe80::1%en0');
    await tester.pumpAndSettle();

    expect(find.text('Link-Local (fe80::/10)'), findsOneWidget);
    expect(
      find.text('fe80:0000:0000:0000:0000:0000:0000:0001'),
      findsOneWidget,
      reason: 'the zone must not change the address',
    );
    expect(find.text('Zone'), findsOneWidget);
    expect(find.text('en0'), findsOneWidget);
    expect(_copyPayload(tester), contains('Zone: en0'));
  });

  testWidgets('a half-typed zone is an error, not a silent truncation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(_field(0), 'fe80::1%');
    await tester.pumpAndSettle();

    expect(find.text('Invalid IPv6 address format.'), findsOneWidget);
    expect(find.text('Zone'), findsNothing);
    expect(
      _copyPayload(tester),
      isNull,
      reason: 'there is no valid breakdown to copy',
    );
  });

  testWidgets('no overflow at phone, tablet or desktop width', (
    WidgetTester tester,
  ) async {
    for (final Size size in <Size>[
      const Size(320, 720),
      const Size(768, 1024),
      const Size(1280, 900),
    ]) {
      await _withViewport(tester, size, () async {
        await tester.pumpWidget(_host());
        await tester.pumpAndSettle();
        await tester.enterText(
          _field(0),
          '2001:0:4136:e378:8000:63bf:3fff:fdd2',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size');

        // The zone helper line, added 2026-08-02, is the longest wrapped text
        // the Subnet card can render. 320 dp is the narrowest phone the app
        // supports, so it is the width where a caption would blow the box.
        await tester.enterText(_field(0), 'fe80::1%2512');
        await tester.pumpAndSettle();
        expect(find.textContaining('it would be 2512'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'zone caveat at $size');
      });
    }
  });
}
