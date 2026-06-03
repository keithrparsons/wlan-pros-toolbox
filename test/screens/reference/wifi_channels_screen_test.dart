// Tests for the Wi-Fi Channels reference screen.
//
// Two layers (mirrors standards_screen_test.dart):
//  1. Data assertions against the public `WifiChannelsScreen.channels24 / 5 / 6`
//     consts — the same single source the UI renders. Locks the key rows to the
//     values ported from the rf-tools-pwa `channels` tool (www/app.js: CH24,
//     CH5, PSC6/CH6). Catches any silent drift from the PWA source.
//  2. One widget test in a phone viewport — pumps the screen, asserts the title
//     and the default (2.4 GHz) table render, then switches to 6 GHz and checks
//     a PSC channel appears, all without overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_channels_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('WifiChannelsScreen 2.4 GHz dataset', () {
    test('covers channels 1–14', () {
      expect(
        WifiChannelsScreen.channels24.map((Channel24 c) => c.channel),
        List<int>.generate(14, (int i) => i + 1),
      );
    });

    test('channel 6 centers on 2437 MHz (2.437 GHz)', () {
      final Channel24 ch6 = WifiChannelsScreen.channels24
          .firstWhere((Channel24 c) => c.channel == 6);
      expect(ch6.centerGhz, 2.437);
      expect((ch6.centerGhz * 1000).round(), 2437);
    });

    test('only 1, 6, 11 are non-overlapping', () {
      final List<int> nonOverlap = WifiChannelsScreen.channels24
          .where((Channel24 c) => c.nonOverlap)
          .map((Channel24 c) => c.channel)
          .toList();
      expect(nonOverlap, <int>[1, 6, 11]);
    });

    test('channels 1–11 are US; 12–13 EU; 14 JP', () {
      expect(
        WifiChannelsScreen.channels24
            .firstWhere((Channel24 c) => c.channel == 11)
            .regulatory,
        'US',
      );
      expect(
        WifiChannelsScreen.channels24
            .firstWhere((Channel24 c) => c.channel == 13)
            .regulatory,
        'EU',
      );
      final Channel24 ch14 = WifiChannelsScreen.channels24
          .firstWhere((Channel24 c) => c.channel == 14);
      expect(ch14.regulatory, 'JP');
      // Ch 14 takes the special 12 MHz step above ch 13 → 2484 MHz.
      expect(ch14.centerGhz, 2.484);
    });
  });

  group('WifiChannelsScreen 5 GHz dataset', () {
    test('reproduces the 25 US UNII rows', () {
      expect(WifiChannelsScreen.channels5, hasLength(25));
    });

    test('UNII-1 (36–48) and UNII-3 (149–165) are not DFS', () {
      final List<int> noDfs = WifiChannelsScreen.channels5
          .where((Channel5 c) => !c.dfs)
          .map((Channel5 c) => c.channel)
          .toList();
      expect(noDfs, <int>[36, 40, 44, 48, 149, 153, 157, 161, 165]);
    });

    test('UNII-2A and UNII-2C are DFS', () {
      final bool allDfs = WifiChannelsScreen.channels5
          .where((Channel5 c) => c.band == 'UNII-2A' || c.band == 'UNII-2C')
          .every((Channel5 c) => c.dfs);
      expect(allDfs, isTrue);
    });

    test('channel 36 centers on 5.180 GHz in UNII-1', () {
      final Channel5 ch36 = WifiChannelsScreen.channels5
          .firstWhere((Channel5 c) => c.channel == 36);
      expect(ch36.centerGhz, 5.180);
      expect(ch36.band, 'UNII-1');
      expect(ch36.dfs, isFalse);
    });
  });

  group('WifiChannelsScreen 6 GHz dataset', () {
    test('exposes the 15 Preferred Scanning Channels', () {
      expect(WifiChannelsScreen.channels6, hasLength(15));
      expect(
        WifiChannelsScreen.channels6.every((Channel6 c) => c.psc),
        isTrue,
      );
    });

    test('PSC channel set matches the PWA PSC6 const', () {
      expect(
        WifiChannelsScreen.channels6.map((Channel6 c) => c.channel),
        <int>[5, 21, 37, 53, 69, 85, 101, 117, 133, 149, 165, 181, 197, 213, 229],
      );
    });

    test('PSC ch 5 centers on 5.975 GHz ((5950 + 5×5) MHz)', () {
      final Channel6 ch5 = WifiChannelsScreen.channels6
          .firstWhere((Channel6 c) => c.channel == 5);
      expect(ch5.centerGhz, 5.975);
    });
  });

  group('WifiChannelsScreen HaLow (802.11ah) dataset', () {
    test('US scheme has 26 odd-numbered 1 MHz channels 1..51', () {
      expect(WifiChannelsScreen.halowUs1Mhz, hasLength(26));
      expect(
        WifiChannelsScreen.halowUs1Mhz.map((ChannelHalow c) => c.channel),
        List<int>.generate(26, (int i) => 2 * i + 1),
      );
    });

    test('center frequency follows 902.5 + 0.5 × (ch − 1) MHz', () {
      for (final ChannelHalow c in WifiChannelsScreen.halowUs1Mhz) {
        final double expected = 902.5 + 0.5 * (c.channel - 1);
        expect(c.centerMhz, closeTo(expected, 1e-9),
            reason: 'ch ${c.channel}');
      }
    });

    test('endpoints: ch 1 = 902.5 MHz, ch 51 = 927.5 MHz (not 930.5)', () {
      expect(WifiChannelsScreen.halowUs1Mhz.first.centerMhz, 902.5);
      expect(WifiChannelsScreen.halowUs1Mhz.last.centerMhz, 927.5);
      // The rejected faulty extraction (930.5 MHz) never appears.
      expect(
        WifiChannelsScreen.halowUs1Mhz.any((c) => c.centerMhz == 930.5),
        isFalse,
      );
    });

    test('every US channel stays inside the 902-928 MHz band', () {
      for (final ChannelHalow c in WifiChannelsScreen.halowUs1Mhz) {
        expect(c.centerMhz, greaterThanOrEqualTo(902.0));
        expect(c.centerMhz, lessThanOrEqualTo(928.0));
      }
    });

    test('US width blocks carry the verified counts 26/13/6/3/1', () {
      final Map<int, int> byWidth = <int, int>{
        for (final HalowWidthBlock w in WifiChannelsScreen.halowUsWidths)
          w.widthMhz: w.count,
      };
      expect(byWidth, <int, int>{1: 26, 2: 13, 4: 6, 8: 3, 16: 1});
    });

    test('China region is flagged uncertain, never a hard channel count', () {
      final HalowRegion china = WifiChannelsScreen.halowRegions
          .firstWhere((HalowRegion r) => r.region == 'China');
      expect(china.note.toLowerCase(), contains('uncertain'));
      expect(china.note, contains('CMIIT'));
    });
  });

  group('WifiChannelsScreen widget', () {
    testWidgets('renders title and default 2.4 GHz table in a phone viewport', (
      WidgetTester tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const WifiChannelsScreen(),
          ),
        );
        await tester.pump();

        // App-bar title.
        expect(find.text('Wi-Fi Channels'), findsOneWidget);
        // Default band card + table.
        expect(find.text('2.4 GHz'), findsWidgets);
        expect(find.text('2.437'), findsOneWidget); // ch 6 center
        // Band selector (§8.14 AppSelect) shows the default value closed.
        // The other bands live in the menu, revealed on tap (see the
        // band-switching tests below).
      });
    });

    testWidgets('switching to 6 GHz reveals a PSC channel', (
      WidgetTester tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const WifiChannelsScreen(),
          ),
        );
        await tester.pump();

        // Open the band AppSelect (§8.14), then pick the 6 GHz menu item.
        await tester.tap(find.byType(DropdownButton<WifiBand>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('6 GHz').last);
        await tester.pumpAndSettle();

        // PSC ch 5 center frequency renders in the 6 GHz table.
        expect(find.text('5.975'), findsOneWidget);
        expect(find.text('PSC'), findsWidgets);
      });
    });

    testWidgets('switching to HaLow reveals the US 1 MHz channel table', (
      WidgetTester tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const WifiChannelsScreen(),
          ),
        );
        await tester.pump();

        // Open the band AppSelect (§8.14), then pick the HaLow menu item.
        await tester.tap(find.byType(DropdownButton<WifiBand>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('HaLow').last);
        await tester.pumpAndSettle();

        // Ch 1 = 902.5 MHz and ch 51 = 927.5 MHz render in the HaLow table.
        expect(find.text('902.5'), findsOneWidget);
        expect(find.text('927.5'), findsOneWidget);
      });
    });
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    for (final double width in <double>[320, 375, 768, 1280]) {
      await _withViewport(tester, Size(width, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const WifiChannelsScreen()),
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
