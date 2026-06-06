// Tests for the Channel Map reference screen.
//
// Two layers (mirrors wifi_channels_screen_test.dart):
//  1. Data assertions against the public `ChannelMapScreen.map*` consts — the
//     same single source the UI renders. Locks the key rows to the values
//     ported from the rf-tools-pwa `chanmap` tool (www/app.js: buildChanMap +
//     CM5_40/80/160, CM6_CHS/40/80/160, CM6_PSC5, CH24/CH5). Catches any
//     silent drift from the PWA source.
//  2. One widget test in a 390x844 phone viewport — pumps the screen, asserts
//     the title and default (2.4 GHz) map render, then switches to 5 GHz and
//     6 GHz and checks a known bonded center channel appears, all without a
//     RenderFlex overflow.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/channel_map_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('ChannelMapScreen 2.4 GHz map', () {
    test('covers channels 1–11', () {
      expect(
        ChannelMapScreen.map24.map((ChanMap24 c) => c.channel),
        List<int>.generate(11, (int i) => i + 1),
      );
    });

    test('only channels 1, 6, 11 are non-overlapping', () {
      final List<int> nonOverlap = ChannelMapScreen.map24
          .where((ChanMap24 c) => c.nonOverlap)
          .map((ChanMap24 c) => c.channel)
          .toList();
      expect(nonOverlap, [1, 6, 11]);
    });

    test('channel 6 centers on 2437 MHz', () {
      final ChanMap24 ch6 =
          ChannelMapScreen.map24.firstWhere((ChanMap24 c) => c.channel == 6);
      expect(ch6.freqMhz, 2437);
    });
  });

  group('ChannelMapScreen 5 GHz bonding', () {
    test('20 MHz row has 25 channels (UNII-1/2A/2C/3)', () {
      expect(ChannelMapScreen.map5_20.length, 25);
    });

    test('40 MHz bonds: 12 blocks, first centers ch 38 (36+40)', () {
      expect(ChannelMapScreen.map5_40.length, 12);
      final BondedBlock first = ChannelMapScreen.map5_40.first;
      expect(first.centerChannel, 38);
      expect(first.lowChannel, 36);
      expect(first.highChannel, 40);
      expect(first.widthMhz, 40);
      expect(first.subChannels, 2);
    });

    test('80 MHz bonds match PWA CM5_80 centers', () {
      expect(
        ChannelMapScreen.map5_80.map((BondedBlock b) => b.centerChannel),
        [42, 58, 106, 122, 138, 155],
      );
    });

    test('160 MHz bonds: ch 50 spans 36–64 and is DFS-mixed', () {
      final BondedBlock ch50 = ChannelMapScreen.map5_160
          .firstWhere((BondedBlock b) => b.centerChannel == 50);
      expect(ch50.lowChannel, 36);
      expect(ch50.highChannel, 64);
      expect(ch50.widthMhz, 160);
      expect(ch50.subChannels, 8);
      expect(ch50.dfs, DfsClass.mixed);
    });

    test('UNII-1 (36–48) is no-DFS, UNII-2A (52–64) is DFS', () {
      final BondedBlock ch36 = ChannelMapScreen.map5_20
          .firstWhere((BondedBlock b) => b.centerChannel == 36);
      final BondedBlock ch52 = ChannelMapScreen.map5_20
          .firstWhere((BondedBlock b) => b.centerChannel == 52);
      expect(ch36.dfs, DfsClass.noDfs);
      expect(ch52.dfs, DfsClass.dfs);
    });
  });

  group('ChannelMapScreen 6 GHz bonding (full US band, ch 1–233)', () {
    test('20 MHz row is the full band ch 1,5,9,…,233 (59 channels)', () {
      // v1.1.1 fix: the map was truncated at ch 93 (UNII-5 only). The full US
      // 6 GHz plan (5925–7125 MHz) is 59 × 20 MHz channels, ch 1 to 233 step 4.
      expect(ChannelMapScreen.map6_20.length, 59);
      expect(ChannelMapScreen.map6_20.first.centerChannel, 1);
      expect(ChannelMapScreen.map6_20.last.centerChannel, 233);
      expect(
        ChannelMapScreen.map6_20.map((BondedBlock b) => b.centerChannel),
        List<int>.generate(59, (int i) => 1 + i * 4),
      );
    });

    test('every 20 MHz block is itself a 1-wide span at its own channel', () {
      for (final BondedBlock b in ChannelMapScreen.map6_20) {
        expect(b.widthMhz, 20);
        expect(b.lowChannel, b.centerChannel);
        expect(b.highChannel, b.centerChannel);
        expect(b.subChannels, 1);
      }
    });

    test('PSC channels are every 4th 20 MHz channel from 5 (15 total)', () {
      final List<int> psc = ChannelMapScreen.map6_20
          .where((BondedBlock b) => b.dfs == DfsClass.psc)
          .map((BondedBlock b) => b.centerChannel)
          .toList();
      expect(psc, [
        5, 21, 37, 53, 69, 85, 101, 117, 133, 149, 165, 181, 197, 213, 229,
      ]);
    });

    test('40 MHz bonds: 29 blocks, centers = low+2, up to ch 227', () {
      expect(ChannelMapScreen.map6_40.length, 29);
      expect(
        ChannelMapScreen.map6_40.map((BondedBlock b) => b.centerChannel),
        List<int>.generate(29, (int i) => 3 + i * 8),
      );
      expect(ChannelMapScreen.map6_40.last.centerChannel, 227);
      expect(ChannelMapScreen.map6_40.last.highChannel, 229);
      for (final BondedBlock b in ChannelMapScreen.map6_40) {
        expect(b.centerChannel, b.lowChannel + 2);
        expect(b.highChannel, b.lowChannel + 4);
        expect(b.subChannels, 2);
      }
    });

    test('80 MHz bonds: 14 blocks, centers = low+6, up to ch 215', () {
      expect(ChannelMapScreen.map6_80.length, 14);
      expect(ChannelMapScreen.map6_80.first.centerChannel, 7);
      expect(ChannelMapScreen.map6_80.last.centerChannel, 215);
      expect(ChannelMapScreen.map6_80.last.highChannel, 221);
      for (final BondedBlock b in ChannelMapScreen.map6_80) {
        expect(b.centerChannel, b.lowChannel + 6);
        expect(b.highChannel, b.lowChannel + 12);
        expect(b.subChannels, 4);
      }
    });

    test('160 MHz bonds: 7 blocks, centers = low+14, up to ch 207', () {
      expect(ChannelMapScreen.map6_160.length, 7);
      expect(ChannelMapScreen.map6_160.first.centerChannel, 15);
      expect(ChannelMapScreen.map6_160.first.lowChannel, 1);
      expect(ChannelMapScreen.map6_160.first.highChannel, 29);
      expect(ChannelMapScreen.map6_160.last.centerChannel, 207);
      expect(ChannelMapScreen.map6_160.last.highChannel, 221);
      for (final BondedBlock b in ChannelMapScreen.map6_160) {
        expect(b.centerChannel, b.lowChannel + 14);
        expect(b.highChannel, b.lowChannel + 28);
        expect(b.subChannels, 8);
      }
    });

    test('320 MHz: 3 primary (31/95/159) + 3 alternative (63/127/191)', () {
      expect(ChannelMapScreen.map6_320.length, 6);
      final List<BondedBlock> primary = ChannelMapScreen.map6_320
          .where((BondedBlock b) => !b.alt)
          .toList();
      final List<BondedBlock> alt = ChannelMapScreen.map6_320
          .where((BondedBlock b) => b.alt)
          .toList();
      expect(primary.map((BondedBlock b) => b.centerChannel), [31, 95, 159]);
      expect(alt.map((BondedBlock b) => b.centerChannel), [63, 127, 191]);
      for (final BondedBlock b in ChannelMapScreen.map6_320) {
        expect(b.widthMhz, 320);
        expect(b.subChannels, 16);
        expect(b.centerChannel, b.lowChannel + 30);
        expect(b.highChannel, b.lowChannel + 60);
      }
      // Top 320 MHz alternative reaches ch 221 (highest 320 MHz sub-channel).
      expect(alt.last.highChannel, 221);
    });

    test('no bonded block exceeds the band ceiling of ch 233', () {
      final Iterable<BondedBlock> all = <BondedBlock>[
        ...ChannelMapScreen.map6_20,
        ...ChannelMapScreen.map6_40,
        ...ChannelMapScreen.map6_80,
        ...ChannelMapScreen.map6_160,
        ...ChannelMapScreen.map6_320,
      ];
      for (final BondedBlock b in all) {
        expect(b.highChannel, lessThanOrEqualTo(233));
        expect(b.lowChannel, greaterThanOrEqualTo(1));
      }
    });
  });

  testWidgets(
    'Channel Map renders and switches bands in a 390x844 phone viewport',
    (tester) async {
      await _withViewport(tester, const Size(390, 844), () async {
        final List<Object> overflow = <Object>[];
        final FlutterExceptionHandler? previous = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          final String msg = details.exception.toString();
          if (msg.contains('RenderFlex overflowed') ||
              msg.contains('overflowed by')) {
            overflow.add(details.exception);
          } else {
            previous?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = previous);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const ChannelMapScreen(),
          ),
        );
        await tester.pump();

        // Title + default 2.4 GHz map.
        expect(find.text('Channel Map'), findsOneWidget);
        expect(find.text('2.4 GHz — 20 MHz channels (US)'), findsOneWidget);

        // Switch to 5 GHz — the 80 MHz bond center ch 42 is a known PWA cell.
        await tester.tap(find.text('5 GHz'));
        await tester.pumpAndSettle();
        expect(find.text('5 GHz — bonded widths (US, FCC)'), findsOneWidget);
        expect(find.text('42'), findsWidgets);
        // 3-digit 5 GHz channel renders fully (no ellipsis) — the clipping fix.
        expect(find.text('100'), findsWidgets);
        expect(find.text('161'), findsWidgets);

        // Switch to 6 GHz — full band now reaches ch 233; alt 320 MHz blocks
        // are labelled "63 alt" / "127 alt" / "191 alt".
        await tester.tap(find.text('6 GHz'));
        await tester.pumpAndSettle();
        expect(
          find.text('6 GHz — full US band, ch 1–233 (UNII-5 to UNII-8)'),
          findsOneWidget,
        );
        expect(find.text('233'), findsWidgets);
        expect(find.text('63 alt'), findsOneWidget);
        expect(find.text('191 alt'), findsOneWidget);

        expect(
          overflow,
          isEmpty,
          reason:
              'Channel Map must not log a RenderFlex overflow at 390x844 — '
              'got: ${overflow.map((Object e) => e.toString()).join("; ")}',
        );
      });
    },
  );

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    for (final double width in <double>[320, 375, 768, 1280]) {
      await _withViewport(tester, Size(width, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const ChannelMapScreen()),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      });
    }
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors test/widget_test.dart `_withViewport`.
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
