// Tests for the 802.11 Standards reference screen.
//
// Two layers:
//  1. Data assertions against the public `StandardsScreen.standards` const —
//     the same single source the UI renders. Locks the key rows to the values
//     ported from the rf-tools-pwa `STANDARDS` const (www/app.js): generation
//     names, bands, and counts. Catches any silent drift from the PWA source.
//  2. One widget test in a phone viewport — pumps the screen and asserts the
//     title, an intro line, and key rows render without overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/standards_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('StandardsScreen.standards dataset', () {
    StandardEntry byGen(String generation) => StandardsScreen.standards
        .firstWhere((StandardEntry e) => e.generation == generation);

    test('reproduces all nine PWA rows', () {
      expect(StandardsScreen.standards, hasLength(9));
    });

    test('802.11ax is Wi-Fi 6 with the right PHY profile', () {
      final StandardEntry wifi6 = byGen('Wi-Fi 6');
      expect(wifi6.std, '802.11ax');
      expect(wifi6.year, 2019);
      expect(wifi6.bands, '2.4 / 5');
      expect(wifi6.maxRate, '9.6 Gbps');
      expect(wifi6.mimo, '8×8 MU-MIMO');
      expect(wifi6.channelWidth, '20–160');
      expect(wifi6.modulation, '1024-QAM OFDMA');
    });

    test('802.11ax also covers Wi-Fi 6E adding the 6 GHz band', () {
      final StandardEntry wifi6e = byGen('Wi-Fi 6E');
      expect(wifi6e.std, '802.11ax');
      expect(wifi6e.year, 2021);
      expect(wifi6e.bands, '2.4 / 5 / 6');
      expect(wifi6e.hasBand6, isTrue);
    });

    test('802.11be is Wi-Fi 7 on three bands with MLO', () {
      final StandardEntry wifi7 = byGen('Wi-Fi 7');
      expect(wifi7.std, '802.11be');
      expect(wifi7.year, 2024);
      expect(wifi7.bands, '2.4 / 5 / 6');
      expect(wifi7.maxRate, '46 Gbps');
      expect(wifi7.mimo, '16×16 MLO');
      expect(wifi7.channelWidth, '20–320');
      expect(wifi7.modulation, '4K-QAM OFDMA');
    });

    test('802.11ac is Wi-Fi 5, 5 GHz only', () {
      final StandardEntry wifi5 = byGen('Wi-Fi 5');
      expect(wifi5.std, '802.11ac');
      expect(wifi5.bands, '5');
      expect(wifi5.hasBand24, isFalse);
      expect(wifi5.hasBand6, isFalse);
    });

    test('802.11n is Wi-Fi 4 on 2.4 and 5 GHz', () {
      final StandardEntry wifi4 = byGen('Wi-Fi 4');
      expect(wifi4.std, '802.11n');
      expect(wifi4.bands, '2.4 / 5');
      expect(wifi4.hasBand24, isTrue);
      expect(wifi4.hasBand5, isTrue);
      expect(wifi4.hasBand6, isFalse);
    });

    test('the original 802.11 has no marketing generation', () {
      final StandardEntry first = StandardsScreen.standards.first;
      expect(first.std, '802.11');
      expect(first.generation, '—');
      expect(first.year, 1997);
      expect(first.maxRate, '2 Mbps');
    });

    test('only two amendments reach the 6 GHz band', () {
      final List<StandardEntry> band6 = StandardsScreen.standards
          .where((StandardEntry e) => e.hasBand6)
          .toList();
      expect(
        band6.map((StandardEntry e) => e.generation),
        containsAll(<String>['Wi-Fi 6E', 'Wi-Fi 7']),
      );
      expect(band6, hasLength(2));
    });
  });

  group('StandardsScreen widget', () {
    testWidgets('renders title and key rows in a phone viewport', (
      WidgetTester tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const StandardsScreen()),
        );
        await tester.pump();

        // App-bar title.
        expect(find.text('802.11 Standards'), findsOneWidget);
        // The newest two generations render as badges.
        expect(find.text('Wi-Fi 7'), findsOneWidget);
        expect(find.text('Wi-Fi 6E'), findsOneWidget);
        // 802.11ax appears twice (Wi-Fi 6 and Wi-Fi 6E share the std string).
        expect(find.text('802.11ax'), findsNWidgets(2));
        // Spec values render.
        expect(find.text('46 Gbps'), findsOneWidget);
      });
    });
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    for (final double width in <double>[320, 375, 768, 1280]) {
      await _withViewport(tester, Size(width, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const StandardsScreen()),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      });
    }
  });
}

/// Run [body] with the test view sized to [size], then restore — mirrors the
/// `_withViewport` helper in test/widget_test.dart.
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
