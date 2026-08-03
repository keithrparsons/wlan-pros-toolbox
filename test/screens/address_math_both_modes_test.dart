// The surfaces of the 2026-08-02 address-math pass, rendered in BOTH color
// modes at phone, tablet and desktop width.
//
// WHY THIS FILE EXISTS. Each of the four screens already carries its own
// responsive test, and every one of them renders in dark mode only. Light mode
// is not a repaint of the same tree: GL-003 §8.20.7 swaps surface, border and
// muted-text tokens, and a row whose contrast or wrap behavior only works on
// the dark substrate fails silently on the light one because nothing renders
// it. A per-screen test that pins one mode proves that mode.
//
// WHAT IT ASSERTS, and what it deliberately does NOT. It drives the real test
// viewport (a MediaQuery wrapper only changes what the widget is TOLD about the
// window; the render surface stays 800x600, so a width assertion written that
// way cannot fail), enters real input so the RESULT rows render rather than an
// empty form, and requires no exception — which is what a RenderFlex overflow
// raises. It does not compare pixels. Contrast and hue are Vera's gate and a
// golden's job, not this file's, and claiming otherwise here would be a check
// that reports on something it never looked at.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ipv6_subnet_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/transfer_time_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/mac_oui_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/subnet_calc_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/subnet_planner_screen.dart';
import 'package:wlan_pros_toolbox/services/network/mac_oui_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// In-memory OUI table, so no asset load runs. Same shape the MAC screen's own
/// suite uses; without it `pumpAndSettle` never returns.
final MacOuiService _macSvc = MacOuiService.fromTable(<String, String>{
  'B827EB': 'Raspberry Pi Foundation',
});

/// Phone, tablet, desktop. The same three widths the per-screen suites use.
const List<Size> _viewports = <Size>[
  Size(320, 720),
  Size(768, 1024),
  Size(1280, 900),
];

Future<void> _renderBothModes(
  WidgetTester tester,
  String name,
  Widget Function() build, {
  Future<void> Function(WidgetTester)? drive,
}) async {
  for (final bool light in <bool>[false, true]) {
    for (final Size size in _viewports) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: light ? AppTheme.light() : AppTheme.dark(),
          home: build(),
        ),
      );
      await tester.pumpAndSettle();
      if (drive != null) {
        await drive(tester);
        await tester.pumpAndSettle();
      }

      expect(
        tester.takeException(),
        isNull,
        reason: '$name overflowed at $size in '
            '${light ? 'light' : 'dark'} mode',
      );
    }
  }
}

void main() {
  testWidgets('Subnet Planner — Split, with a carve on screen', (
    WidgetTester tester,
  ) async {
    await _renderBothModes(
      tester,
      'Subnet Planner (split)',
      () => const SubnetPlannerScreen(),
      drive: (WidgetTester t) async {
        // The results table is the part that can overflow, so it has to be
        // ON SCREEN when the assertion runs. An empty form cannot overflow.
        await t.enterText(find.byType(TextField).at(0), '10.20.0.0/22');
        await t.enterText(
          find.byType(TextField).at(1),
          'Staff 500\nGuest 200\nIoT 60\nUplink 2',
        );
      },
    );
  });

  testWidgets('Transfer Time — with a result showing', (
    WidgetTester tester,
  ) async {
    await _renderBothModes(
      tester,
      'Transfer Time',
      () => const TransferTimeScreen(),
    );
  });

  testWidgets('IPv4 Subnet — the number-form rows', (
    WidgetTester tester,
  ) async {
    await _renderBothModes(
      tester,
      'IPv4 Subnet (number forms)',
      () => const SubnetCalcScreen(),
      drive: (WidgetTester t) async {
        // The binary row is 32 characters plus a boundary mark and is the
        // widest thing on the screen, which makes it the overflow candidate.
        await t.enterText(find.byType(TextField).at(0), '10.20.30.40/22');
      },
    );
  });

  testWidgets('IPv6 Subnet — the zone caveat, which is the longest wrapped '
      'line the Subnet card renders', (WidgetTester tester) async {
    // Added 2026-08-02 with Vera's MEDIUM-1. The caveat is a labelSmall
    // caption in `textTertiary`, and GL-003 §3's line-height rule warns that
    // small wrapped text is where a caption stops fitting. 320 dp light mode
    // is the tightest combination the app ships.
    await _renderBothModes(
      tester,
      'IPv6 Subnet (zone caveat)',
      () => const Ipv6SubnetScreen(),
      drive: (WidgetTester t) async {
        // "%2512" is the longest of the three caveat strings: it names both
        // readings, so it carries two interpolated numbers.
        await t.enterText(find.byType(TextField).at(0), 'fe80::1%2512');
      },
    );
  });

  testWidgets('IPv6 Subnet — the transition section, with a Teredo decode', (
    WidgetTester tester,
  ) async {
    await _renderBothModes(
      tester,
      'IPv6 Subnet (transition)',
      () => const Ipv6SubnetScreen(),
      drive: (WidgetTester t) async {
        // Teredo renders the most rows of any decode (server, port, client,
        // role and the inversion note), so it is the worst case for height
        // and for the longest single value.
        await t.enterText(
          find.byType(TextField).at(0),
          '2001:0:4136:e378:8000:63bf:3fff:fdd2',
        );
      },
    );
  });

  testWidgets('MAC screen — the bit decode and EUI-64 rows', (
    WidgetTester tester,
  ) async {
    await _renderBothModes(
      tester,
      'MAC (bit decode)',
      () => MacOuiScreen(service: _macSvc),
      drive: (WidgetTester t) async {
        // Locally administered, so the vendor card declines and the bit card
        // is the whole answer — the state this pass added and the one whose
        // rows have to survive the light substrate.
        await t.enterText(find.byType(TextField), '02:1A:2B:3C:4D:5E');
        await t.pump();
        await t.tap(find.widgetWithText(FilledButton, 'Look up'));
      },
    );
  });
}
