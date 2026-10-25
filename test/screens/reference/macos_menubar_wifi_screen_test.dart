// Tests for the macOS Menu-Bar Wi-Fi reference screen.
//
// Dataset assertions guard the four built-in paths, the per-field RF tables
// (this screen OWNS the "what each field means" reference), and the two
// load-bearing on-screen callouts: the wdutil needs-sudo note and the
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

    // Corrected 25 OCT 2026: on macOS 26.7.1 plain `wdutil info` prints only
    // its usage text. It does not run and mask fields, so the old
    // "masked without sudo" claim was wrong.
    test('the sudo callout says wdutil info needs sudo, not that it masks', () {
      expect(kMenuBarSudoCallout.contains('sudo wdutil info'), isTrue);
      for (final String s in <String>[
        kMenuBarWdutilIntro,
        kMenuBarSudoCallout,
        for (final RfField f in kMenuBarWdutilFields) f.meaning,
      ]) {
        expect(s.toLowerCase().contains('masked'), isFalse, reason: s);
      }
    });

    test('the Option-click list carries Security, MCS Index and NSS', () {
      for (final String field in <String>['Security', 'MCS Index', 'NSS']) {
        expect(
          kMenuBarOptionClickFields.any((f) => f.field == field),
          isTrue,
          reason: 'Option-click table missing $field',
        );
      }
    });

    // Keith's Mac, macOS 26.7.1, Option-click screenshot 25 OCT 2026. Interface
    // Name and Hardware Address sit above the network list; the rest are under
    // the connected network name, in this order.
    test('Option-click fields are in the order macOS prints them', () {
      expect(
        kMenuBarOptionClickFields.map((f) => f.field).toList(),
        <String>[
          'Interface Name',
          'Hardware Address',
          'IP Address',
          'Router',
          'MAC Address',
          'Security',
          'BSSID',
          'Channel',
          'Country Code',
          'RSSI',
          'Noise',
          'Tx Rate',
          'PHY Mode',
          'MCS Index',
          'NSS',
        ],
      );
    });

    test('Channel shows the "DFS, " prefix macOS prints on a DFS channel', () {
      final RfField channel =
          kMenuBarOptionClickFields.firstWhere((f) => f.field == 'Channel');
      expect(channel.meaning, contains('149 (5 GHz, 80 MHz)'));
      expect(channel.meaning, contains('DFS, 108 (5 GHz, 80 MHz)'));
    });

    test('Option-click prints width inside Channel, not as its own line', () {
      expect(
        kMenuBarOptionClickFields.any((f) => f.field == 'Channel width'),
        isFalse,
      );
      final RfField channel =
          kMenuBarOptionClickFields.firstWhere((f) => f.field == 'Channel');
      expect(channel.meaning.contains('MHz'), isTrue);
    });

    test('both Security rows warn that macOS reports OWE as open', () {
      for (final List<RfField> list in <List<RfField>>[
        kMenuBarOptionClickFields,
        kMenuBarWdutilFields,
      ]) {
        final RfField security = list.firstWhere((f) => f.field == 'Security');
        final String text = '${security.meaning} ${security.proNote ?? ''}';
        expect(text.contains('Enhanced Open (OWE)'), isTrue, reason: text);
      }
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
        for (final RfField f in kMenuBarOptionClickFields) f.proNote ?? '',
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
