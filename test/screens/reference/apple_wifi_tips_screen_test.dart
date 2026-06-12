// Tests for the Apple Wi-Fi Support Tips reference screen.
//
// Dataset assertions guard the four sections and the GL-005 honesty caveats
// (transmit-power silence, single-Apple-source iOS flag). Widget smokes confirm
// render, the source link-out (injectable launcher), the launch-error state, and
// the navigation hook to the macOS Menu-Bar Wi-Fi companion.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/apple_wifi_tips_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/apple_wifi_tips_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Apple Wi-Fi Tips — dataset', () {
    test('all four sections carry content', () {
      expect(kAppleSettings, isNotEmpty);
      expect(kAppleDiagSteps, isNotEmpty);
      expect(kAppleDiagUtilities, isNotEmpty);
      expect(kAppleIosSteps.length, 10);
    });

    test('three Apple sources are present and are https Apple URLs', () {
      for (final String id in <String>['settings', 'diag', 'ios']) {
        final AppleSource? s = kAppleSources[id];
        expect(s, isNotNull, reason: 'missing source $id');
        expect(s!.url.startsWith('https://support.apple.com'), isTrue);
      }
    });

    test('the WPA3 security recommendation is the SSID single-name guidance',
        () {
      final AppleSettingRow ssid =
          kAppleSettings.firstWhere((r) => r.setting == 'Network name (SSID)');
      expect(ssid.recommendation.contains('single'), isTrue);
      expect(ssid.recommendation.contains('all bands'), isTrue);
    });

    test('GL-005 honesty caveats are carried, not hidden', () {
      // Transmit-power silence is stated.
      expect(kAppleSettingsSilenceNote.toLowerCase().contains('transmit power'),
          isTrue);
      // iOS single-source flag is stated.
      expect(kAppleIosSingleSourceNote.contains('111786'), isTrue);
    });

    test('no em dash anywhere in the data', () {
      final List<String> all = <String>[
        kAppleSettingsIntro,
        kAppleSettingsSilenceNote,
        kAppleSettingsKeithNote,
        kAppleDiagIntro,
        kAppleOptionClickBody,
        kAppleOptionClickLinkNote,
        kAppleIosIntro,
        kAppleIosSingleSourceNote,
        for (final AppleSettingRow r in kAppleSettings) r.recommendation,
        for (final AppleStep s in kAppleDiagSteps) s.body,
        for (final AppleStep s in kAppleIosSteps) s.body,
      ];
      for (final String s in all) {
        expect(s.contains('—'), isFalse, reason: s);
      }
    });
  });

  group('AppleWifiTipsScreen widget', () {
    testWidgets('renders title and the four section headings', (tester) async {
      await _withViewport(tester, const Size(375, 3600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const AppleWifiTipsScreen(),
          ),
        );
        expect(find.text('Apple Wi-Fi Support Tips'), findsWidgets);
        expect(find.text('A. Recommended router / Wi-Fi settings'),
            findsOneWidget);
        expect(find.text('D. iOS / iPadOS Wi-Fi troubleshooting'),
            findsOneWidget);
      });
    });

    testWidgets('tapping a source chip calls the injected launcher',
        (tester) async {
      Uri? opened;
      await _withViewport(tester, const Size(375, 3600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: AppleWifiTipsScreen(
              launcher: (Uri u) async {
                opened = u;
                return true;
              },
            ),
          ),
        );
        final Finder chip = find.text('Open Apple article').first;
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pump();
        expect(opened, isNotNull);
        expect(opened!.toString().startsWith('https://support.apple.com'),
            isTrue);
      });
    });

    testWidgets('a failed launch shows the honest error card', (tester) async {
      await _withViewport(tester, const Size(375, 3600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: AppleWifiTipsScreen(
              launcher: (Uri u) async => false,
            ),
          ),
        );
        final Finder chip = find.text('Open Apple article').first;
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pump();
        expect(find.text('Could not open the link'), findsOneWidget);
      });
    });

    testWidgets('the companion-screen chip fires the navigation hook',
        (tester) async {
      bool navigated = false;
      await _withViewport(tester, const Size(375, 3600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: AppleWifiTipsScreen(
              onOpenMenuBarWifi: () => navigated = true,
            ),
          ),
        );
        final Finder chip = find.text('Open macOS Menu-Bar Wi-Fi');
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pump();
        expect(navigated, isTrue);
      });
    });

    testWidgets('renders without overflow at 320/768 widths', (tester) async {
      for (final double width in <double>[320, 768]) {
        await _withViewport(tester, Size(width, 4000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const AppleWifiTipsScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });

    testWidgets('renders in light mode without exception', (tester) async {
      await _withViewport(tester, const Size(375, 3600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: const AppleWifiTipsScreen(),
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
