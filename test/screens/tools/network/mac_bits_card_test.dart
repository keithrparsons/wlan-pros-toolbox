// MacOuiScreen — the bit-decode card folded onto the existing vendor screen.
//
// The bit decoder itself is unit-tested in test/services/mac_address_bits_test
// (the values, the RFC 4291 derivation, the edge cases). This file only asserts
// what the SCREEN promises on top of that:
//
//   * the card is absent before a lookup (idle state) and after an invalid
//     input (the vendor error card owns that surface, and two error treatments
//     stacked would be worse than one);
//   * it renders for a matched global unicast MAC, alongside the vendor card;
//   * it ALSO renders for a locally-administered MAC, which is the case the
//     vendor card has to decline — that is the whole reason it exists;
//   * multicast gets the honest "no EUI-64" reason instead of a derivation;
//   * the Copy payload carries the bits, not just the vendor verdict;
//   * no overflow at the narrowest supported width.
//
// The service is injected from an in-memory table, so no asset load runs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/mac_oui_screen.dart';
import 'package:wlan_pros_toolbox/services/network/mac_oui_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

final MacOuiService _svc = MacOuiService.fromTable(<String, String>{
  'B827EB': 'Raspberry Pi Foundation',
});

Widget _host() => MaterialApp(
  theme: AppTheme.dark(),
  home: MacOuiScreen(service: _svc),
);

/// Drive the REAL test viewport, not just a MediaQuery wrapper.
///
/// This matters, and it is easy to get wrong: wrapping a screen in
/// `MediaQuery(data: MediaQueryData(size: ...))` changes what the widget is
/// TOLD about the window while the render surface stays at the 800x600 default,
/// so a "renders at 320 wide" assertion written that way never rendered at 320
/// and could not fail. `tester.view.physicalSize` is what actually resizes the
/// surface. Same helper as test/widget_test.dart and test/screens/home_screen_test.dart.
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

Future<void> _lookup(WidgetTester tester, String mac) async {
  await tester.enterText(find.byType(TextField), mac);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Look up'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('idle: no bits card before a lookup', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('Address bits'), findsNothing);
    expect(find.text('EUI-64'), findsNothing);
  });

  testWidgets('invalid input: the vendor error card owns the surface, no bits '
      'card', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _lookup(tester, 'b8:27:eb:01:23');
    expect(find.text('Check your input'), findsOneWidget);
    expect(find.text('Address bits'), findsNothing);
  });

  testWidgets('global unicast: vendor AND bits render together', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _lookup(tester, 'B8:27:EB:01:23:45');

    expect(find.text('Raspberry Pi Foundation'), findsOneWidget);
    expect(find.text('Address bits'), findsOneWidget);
    expect(find.text('B8 = 10111000'), findsOneWidget);
    expect(find.text('0 (unicast, one interface)'), findsOneWidget);
    expect(
      find.text('0 (globally unique, from an IEEE block)'),
      findsOneWidget,
    );
    expect(find.text('b8:27:eb:ff:fe:01:23:45'), findsOneWidget);
    expect(find.text('ba27:ebff:fe01:2345'), findsOneWidget);
    expect(find.text('fe80::ba27:ebff:fe01:2345'), findsOneWidget);
    // The notation block gives the forms a capture tool or a CLI wants.
    expect(find.text('B8-27-EB-01-23-45'), findsOneWidget);
    expect(find.text('b827.eb01.2345'), findsOneWidget);
    expect(find.text('b827eb012345'), findsOneWidget);
  });

  testWidgets('locally administered: the bits card carries the answer the '
      'vendor card cannot', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _lookup(tester, 'ba:27:eb:01:23:45');

    // Vendor lookup declines, correctly.
    expect(find.text('Locally administered'), findsOneWidget);
    // The bits card still renders, and still derives an EUI-64 (a local MAC is
    // still a unicast interface).
    expect(find.text('Address bits'), findsOneWidget);
    expect(
      find.text('1 (locally administered, assigned by software)'),
      findsOneWidget,
    );
    expect(find.text('0 (unicast, one interface)'), findsOneWidget);
    expect(find.text('ba:27:eb:ff:fe:01:23:45'), findsOneWidget);
    // And it offers the U/L-cleared form, which is how you get back to an OUI.
    expect(find.textContaining('b8:27:eb:01:23:45'), findsWidgets);
  });

  testWidgets('multicast: an honest no-EUI-64 reason, never a derivation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _lookup(tester, '01:00:5E:00:00:FB');

    expect(find.text('Address bits'), findsOneWidget);
    expect(find.text('1 (multicast, a group of stations)'), findsOneWidget);
    expect(
      find.textContaining('EUI-64 is defined for a unicast interface'),
      findsOneWidget,
    );
    // No interface-ID row, because there is no interface.
    expect(find.text('Interface ID'), findsNothing);
    expect(find.text('Link-local'), findsNothing);
  });

  testWidgets('broadcast gets its own reason', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _lookup(tester, 'ff:ff:ff:ff:ff:ff');
    expect(find.text('1 (broadcast, every station)'), findsOneWidget);
    expect(
      find.textContaining('The broadcast address is not one interface'),
      findsOneWidget,
    );
  });

  testWidgets('the Copy payload carries the bits, not just the vendor', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _lookup(tester, 'B8:27:EB:01:23:45');

    final AppCopyAction action = tester.widget<AppCopyAction>(
      find.byType(AppCopyAction),
    );
    final String? payload = action.textBuilder();
    expect(payload, isNotNull);
    expect(payload, contains('Vendor: Raspberry Pi Foundation'));
    expect(payload, contains('First octet: B8 = 10111000'));
    expect(payload, contains('I/G bit: 0 (unicast)'));
    expect(payload, contains('U/L bit: 0 (globally unique)'));
    expect(payload, contains('EUI-64: b8:27:eb:ff:fe:01:23:45'));
    expect(
      payload,
      contains('Interface ID (modified EUI-64): ba27:ebff:fe01:2345'),
    );
    expect(payload, contains('Link-local: fe80::ba27:ebff:fe01:2345'));
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
        await _lookup(tester, 'B8:27:EB:01:23:45');
        expect(tester.takeException(), isNull, reason: '\$size');
      });
    }
  });
}
