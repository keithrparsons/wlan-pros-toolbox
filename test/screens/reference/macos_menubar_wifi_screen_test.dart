// Tests for the macOS Menu-Bar Wi-Fi reference screen.
//
// Dataset assertions guard the four built-in paths, the per-field RF tables
// (this screen OWNS the "what each field means" reference), and the two
// load-bearing on-screen callouts: the wdutil sudo-masks-RF note and the
// airport-is-gone standing decision. Widget smokes confirm render at small
// widths and in both color modes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/macos_menubar_wifi_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/macos_menubar_wifi_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('macOS Menu-Bar Wi-Fi — dataset', () {
    test('the four built-in paths are present', () {
      expect(kMenuBarPaths.length, 4);
      expect(kMenuBarPaths.any((p) => p.path == 'wdutil info'), isTrue);
    });

    test('the per-field RF tables carry RSSI, noise, Tx Rate, BSSID', () {
      for (final String field in <String>['RSSI', 'Noise', 'Tx Rate', 'BSSID']) {
        expect(
          kMenuBarOptionClickFields.any((f) => f.field == field),
          isTrue,
          reason: 'Option-click table missing $field',
        );
      }
      expect(kMenuBarWdutilFields.any((f) => f.field == 'MCS Index'), isTrue);
      expect(kMenuBarWdutilFields.any((f) => f.field == 'NSS'), isTrue);
    });

    test('the sudo-masks-RF callout is carried (load-bearing)', () {
      expect(kMenuBarSudoCallout.contains('sudo'), isTrue);
      expect(kMenuBarSudoCallout.toLowerCase().contains('masked'), isTrue);
    });

    test('airport is documented as gone, never as a working path', () {
      expect(kMenuBarAirportGone.contains('airport'), isTrue);
      expect(kMenuBarAirportGone.contains('gone'), isTrue);
    });

    test('no em dash anywhere in the data', () {
      final List<String> all = <String>[
        kMenuBarIntro,
        kMenuBarOptionClickIntro,
        kMenuBarOptionClickNote,
        kMenuBarWdutilIntro,
        kMenuBarSudoCallout,
        kMenuBarWdutilNote,
        kMenuBarAirportGone,
        kMenuBarDiagIntro,
        kMenuBarDiagNote,
        kMenuBarShortcutsBody,
        for (final MenuBarPath p in kMenuBarPaths) ...<String>[p.what, p.detail],
        for (final RfField f in kMenuBarOptionClickFields) f.meaning,
        for (final RfField f in kMenuBarWdutilFields) f.meaning,
      ];
      for (final String s in all) {
        expect(s.contains('—'), isFalse, reason: s);
      }
    });
  });

  group('MacosMenubarWifiScreen widget', () {
    testWidgets('renders title and the four section headings', (tester) async {
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const MacosMenubarWifiScreen(),
          ),
        );
        expect(find.text('macOS Menu-Bar Wi-Fi'), findsWidgets);
        expect(find.text('A. Option-click Wi-Fi menu fields'), findsOneWidget);
        expect(find.text('B. sudo wdutil info (the Wi-Fi block)'),
            findsOneWidget);
      });
    });

    testWidgets('renders without overflow at 320/768 widths', (tester) async {
      for (final double width in <double>[320, 768]) {
        await _withViewport(tester, Size(width, 4400), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const MacosMenubarWifiScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });

    testWidgets('renders in light mode without exception', (tester) async {
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: const MacosMenubarWifiScreen(),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    });
  });
}

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
