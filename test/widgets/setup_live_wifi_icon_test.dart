// Widget tests for the bespoke Tier-2 "Set up Live Wi-Fi" icon
// (assets/tool-icons/setup-live-wifi.svg), resolved by the <id>.svg convention
// in ToolAssets and rendered by SetupLiveWifiIcon on the install-the-companion
// buttons (GL-003 §8.6.3).
//
// Mirrors glossary_edu_icons_test.dart: assert the SVG path is taken (an
// SvgPicture renders) rather than the fallback (the Material download glyph).
// Asset presence is simulated with ToolAssets.debugSetBundledAssets so the test
// does not depend on a real bundle.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_assets.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/setup_live_wifi_icon.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  tearDown(ToolAssets.debugReset);

  group('SetupLiveWifiIcon', () {
    testWidgets(
      'renders the bespoke SVG (not the download fallback) when bundled',
      (tester) async {
        ToolAssets.debugSetBundledAssets(
          <String>{'assets/tool-icons/setup-live-wifi.svg'},
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: SetupLiveWifiIcon()),
          ),
        );

        // The convention-resolved SVG renders...
        expect(find.byType(SvgPicture), findsOneWidget);
        // ...and NOT the download-glyph fallback shown when no icon is built.
        expect(find.byIcon(Icons.download_outlined), findsNothing);
      },
    );

    testWidgets(
      'falls back to the download glyph when the asset is not bundled',
      (tester) async {
        ToolAssets.debugSetBundledAssets(<String>{});
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: SetupLiveWifiIcon()),
          ),
        );

        expect(find.byIcon(Icons.download_outlined), findsOneWidget);
        expect(find.byType(SvgPicture), findsNothing);
      },
    );

    test('the convention path resolves to the bundled tool-icons asset', () {
      expect(
        ToolAssets.iconPath('setup-live-wifi'),
        'assets/tool-icons/setup-live-wifi.svg',
      );
    });
  });
}
