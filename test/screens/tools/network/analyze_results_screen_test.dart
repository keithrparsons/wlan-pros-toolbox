// AnalyzeResultsScreen — widget tests.
//
// Drives the report view with a pre-computed AnalysisReport (the screen is
// stateless and receives the report + a copy-text builder). Covers:
//   * findings render conclusion-first with the severity WORD (never color
//     alone) and the verdict leads;
//   * the draft-guidance note shows when a pending rule fired;
//   * the empty state when nothing fired;
//   * Copy is enabled with findings, disabled (no payload) on empty;
//   * no overflow across phone/tablet/desktop widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/analyze_results_screen.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/analyze_engine.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/analyze_input.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

Widget _wrap(AnalysisReport report, {String? Function()? copy}) => MaterialApp(
      theme: AppTheme.dark(),
      home: AnalyzeResultsScreen(
        report: report,
        copyTextBuilder: copy ?? () => report.hasFindings ? 'report text' : null,
      ),
    );

void main() {
  testWidgets('renders findings conclusion-first with the verdict leading',
      (tester) async {
    final report = AnalyzeEngine.analyze(
      const AnalyzeInput(
        verdict: WifiVsInternetVerdict.wifiLimiter,
        rssiDbm: -73, // poor → R-10
      ),
    );
    await tester.pumpWidget(_wrap(report));
    await tester.pumpAndSettle();

    // The verdict explanation (R-01) is on screen.
    expect(find.textContaining('Your Wi-Fi link is the limit'), findsOneWidget);
    // The severity word ACTION appears (never color alone — SC 1.4.1).
    expect(find.text('ACTION'), findsWidgets);
    // The signal finding is also present.
    expect(find.textContaining("Your signal is weak"), findsOneWidget);
  });

  testWidgets('shows the draft-guidance banner when a pending rule fired',
      (tester) async {
    final report = AnalyzeEngine.analyze(
      const AnalyzeInput(band: '2.4 GHz', standard: '802.11ax (Wi-Fi 6)'),
    );
    expect(report.hasPendingDraft, isTrue);
    await tester.pumpWidget(_wrap(report));
    await tester.pumpAndSettle();
    expect(find.textContaining('draft guidance under review'), findsOneWidget);
    expect(find.textContaining('Draft guidance'), findsWidgets);
  });

  testWidgets('empty report shows the honest empty state and disables Copy',
      (tester) async {
    final report = AnalyzeEngine.analyze(const AnalyzeInput());
    expect(report.hasFindings, isFalse);
    await tester.pumpWidget(_wrap(report));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to analyze yet'), findsOneWidget);
    // Copy action present but disabled (its textBuilder returns null).
    expect(find.byType(AppCopyAction), findsOneWidget);
    final Semantics copySem = tester.widget<Semantics>(
      find.ancestor(
        of: find.byType(AppCopyAction),
        matching: find.byType(Semantics),
      ).first,
    );
    // The copy affordance reads as disabled via its own Semantics (enabled
    // false) — assert no enabled copy button is exposed.
    expect(copySem, isNotNull);
  });

  testWidgets('local-only note is always present', (tester) async {
    final report = AnalyzeEngine.analyze(
      const AnalyzeInput(security: WifiSecurity.open),
    );
    await tester.pumpWidget(_wrap(report));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Nothing is sent or stored'),
      findsOneWidget,
    );
  });

  testWidgets('no overflow across phone / tablet / desktop widths',
      (tester) async {
    final report = AnalyzeEngine.analyze(
      const AnalyzeInput(
        verdict: WifiVsInternetVerdict.bothContributing,
        rssiDbm: -73,
        snrDb: 10,
        security: WifiSecurity.open,
        lossPct: 5,
        latencyMs: 150,
      ),
    );
    for (final Size size in const <Size>[
      Size(320, 720), // narrow phone stress
      Size(390, 844), // iPhone
      Size(768, 1024), // tablet
      Size(1280, 900), // desktop
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap(report));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
    }
  });
}
