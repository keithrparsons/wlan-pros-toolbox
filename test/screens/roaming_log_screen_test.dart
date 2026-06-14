// RoamingLogScreen — widget tests (Feature 2, Felix 2026-06-13). The live
// sampler is never started (enableSampling: false or an unsupported source), so
// these run hermetically with no platform channel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/roaming_log_screen.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help_loader.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/tool_help_footer.dart';

void main() {
  setUpAll(() async {
    await ToolHelpLoader.ensureLoaded();
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(560, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: screen));
    await tester.pump();
  }

  testWidgets('unsupported platform shows the honest unavailable view',
      (t) async {
    await pump(
      t,
      const RoamingLogScreen(
        sourceOverride: WifiInfoSource.unsupported,
        enableSampling: false,
      ),
    );
    expect(find.text('Roaming Log'), findsOneWidget);
    // No live card and no help footer on the unavailable branch.
    expect(find.text('Roams this session'), findsNothing);
  });

  testWidgets('web shows the unavailable view', (t) async {
    await pump(
      t,
      const RoamingLogScreen(
        sourceOverride: WifiInfoSource.web,
        enableSampling: false,
      ),
    );
    expect(find.text('Roaming Log'), findsOneWidget);
    expect(find.text('Roams this session'), findsNothing);
  });

  testWidgets(
      'iOS source renders the intro + footer (sampling disabled in test)',
      (t) async {
    await pump(
      t,
      const RoamingLogScreen(
        sourceOverride: WifiInfoSource.iosShortcuts,
        enableSampling: false,
      ),
    );
    expect(find.text('Roaming Log'), findsOneWidget);
    // The iOS intro names the foreground-only limit honestly.
    expect(
      find.textContaining('There is no'),
      findsOneWidget,
    );
    // The §8.16.1 help footer is wired to roaming-log.
    expect(find.byType(ToolHelpFooter), findsOneWidget);
    expect(find.text('About this tool'), findsOneWidget);
  });
}
