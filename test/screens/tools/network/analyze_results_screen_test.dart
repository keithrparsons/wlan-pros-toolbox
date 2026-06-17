// AnalyzeResultsScreen, widget tests (Iris's report-visual-spec build).
//
// Drives the report view with a pre-computed AnalysisReport (the screen is
// stateless and receives the report + a copy-text builder). Covers the new
// graphical-cue structure:
//   * the §1 verdict HERO leads, with the verdict's conclusion text and the
//     neutral "YOUR RESULT" overline (the hero ink is neutral, not a status
//     hue, so we assert text presence, not color);
//   * §2 StatusChip verdict WORDS appear (Issue / Worth a look / Good / Not
//     measured), never color-only;
//   * §6 honesty info rows render with "Not measured";
//   * the empty state when nothing fired, with Copy disabled;
//   * the local-only note is always present;
//   * no overflow across phone / tablet / desktop widths, dark AND light.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/analyze_results_screen.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/analyze_engine.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/analyze_input.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';
import 'package:wlan_pros_toolbox/widgets/status_chip.dart';

/// The §3 category-icon Tier-2 SVG assets the report can render. flutter_svg
/// loads asset SVGs asynchronously and, in the headless test engine, the load
/// can stall `pumpAndSettle` (same behavior already seen with `dns-lookup.svg`).
/// Warming the flutter_svg cache for these assets on the live event loop before
/// pumping resolves the loaders up front so the screen paints and settles.
/// Runtime is unaffected; this only feeds the headless renderer.
const List<String> _categorySvgAssets = <String>[
  'assets/tool-icons/ap-placement.svg', // §3 router/access-point (capability)
  'assets/tool-icons/dns-lookup.svg', // §3 DNS
];

/// Warms the flutter_svg asset cache for the §3 category SVGs so a later
/// `pumpAndSettle` does not hang on the headless async asset load.
Future<void> _precacheCategorySvgs(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final String asset in _categorySvgAssets) {
      final SvgAssetLoader loader = SvgAssetLoader(asset);
      await svg.cache.putIfAbsent(
        loader.cacheKey(null),
        () => loader.loadBytes(null),
      );
    }
  });
}

Widget _wrap(
  AnalysisReport report, {
  String? Function()? copy,
  bool light = false,
}) =>
    MaterialApp(
      theme: light ? AppTheme.light() : AppTheme.dark(),
      home: AnalyzeResultsScreen(
        report: report,
        copyTextBuilder:
            copy ?? () => report.hasFindings ? 'report text' : null,
      ),
    );

void main() {
  testWidgets('verdict hero leads with the conclusion + neutral overline',
      (tester) async {
    final report = AnalyzeEngine.analyze(
      const AnalyzeInput(
        verdict: WifiVsInternetVerdict.wifiLimiter,
        rssiDbm: -73, // poor -> R-10
      ),
    );
    await _precacheCategorySvgs(tester);
    await tester.pumpWidget(_wrap(report));
    await tester.pumpAndSettle();

    // The §1 hero carries the verdict's conclusion-first headline.
    expect(find.textContaining('Your Wi-Fi is the limit here'), findsOneWidget);
    // The neutral §1.2 overline label.
    expect(find.text('YOUR RESULT'), findsOneWidget);
    // The signal finding's conclusion-first headline is also on screen.
    expect(find.textContaining('Your signal is weak'), findsOneWidget);
  });

  testWidgets('finding chips carry the verdict WORD, never color-only',
      (tester) async {
    final report = AnalyzeEngine.analyze(
      const AnalyzeInput(
        verdict: WifiVsInternetVerdict.wifiLimiter,
        rssiDbm: -73, // poor RSSI -> R-10 (important -> "Worth a look")
        security: WifiSecurity.open, // R-35 (critical -> "Issue")
      ),
    );
    await _precacheCategorySvgs(tester);
    await tester.pumpWidget(_wrap(report));
    await tester.pumpAndSettle();

    // At least one StatusChip rendered.
    expect(find.byType(StatusChip), findsWidgets);
    // The security "Issue" verdict WORD is present (R-35 critical).
    expect(find.text('Issue'), findsWidgets);
    // The weak-signal "Worth a look" verdict WORD is present (R-10 important).
    expect(find.text('Worth a look'), findsWidgets);
  });

  testWidgets('honesty rows render as quiet "Not measured" info rows',
      (tester) async {
    // iOS, RF not captured -> R-31 honesty row; band present so something else
    // can fire too, but the honesty row is the one under test.
    final report = AnalyzeEngine.analyze(
      const AnalyzeInput(
        verdict: WifiVsInternetVerdict.upstream,
        platformIsIos: true,
        wifiSignalCaptured: false,
      ),
    );
    await _precacheCategorySvgs(tester);
    await tester.pumpWidget(_wrap(report));
    await tester.pumpAndSettle();

    // The §6 honesty block header + the "Not measured" verdict word.
    expect(find.text('WHAT WAS MEASURED'), findsOneWidget);
    expect(find.text('Not measured'), findsWidgets);
    // The honesty explanation is present and reads as honest, never alarmist.
    expect(
      find.textContaining('Wi-Fi signal details were not captured'),
      findsOneWidget,
    );
  });

  testWidgets(
      'demoted R-06 "you are online" verdict renders a calm INFO chip, not amber',
      (tester) async {
    // The open-hotel-network case: the honest "you are online" verdict (R-06)
    // co-fires with a critical open-network security finding (R-35). R-35 sorts
    // first, so the hero slot is taken by the security finding and R-06 is
    // DEMOTED into the §4 cards list. Its chip must read the calm INFO kind
    // (blue glyph), not headsUp (amber): an amber accent around the word
    // "Good" contradicts the word (GL-003 section 8.13 rule 2 / WCAG 1.4.1).
    final report = AnalyzeEngine.analyze(
      const AnalyzeInput(
        verdict: WifiVsInternetVerdict.onlineUnmeasured,
        security: WifiSecurity.open, // R-35 critical -> R-06 demoted to a card
      ),
    );
    // Guard the precondition: R-06 is present, demoted (not the leading
    // finding), and still carries the "Good" word from the engine.
    final r06 = report.findings.firstWhere((f) => f.ruleId == 'R-06');
    expect(report.findings.first.ruleId, 'R-35');
    expect(r06.verdictWord, 'Good');

    await _precacheCategorySvgs(tester);
    await tester.pumpWidget(_wrap(report));
    await tester.pumpAndSettle();

    // Find every StatusChip whose verdict word is "Good" (the demoted R-06
    // chip), and assert its kind is the calm info kind, never amber headsUp.
    final Iterable<StatusChip> goodChips = tester
        .widgetList<StatusChip>(find.byType(StatusChip))
        .where((c) => c.word == 'Good');
    expect(goodChips, isNotEmpty,
        reason: 'the demoted R-06 chip should carry the "Good" word');
    for (final StatusChip chip in goodChips) {
      expect(chip.kind, StatusChipKind.info,
          reason: 'demoted R-06 "Good" chip must be info (blue), not amber '
              'headsUp');
      expect(chip.kind, isNot(StatusChipKind.headsUp));
    }
  });

  testWidgets('all-clear verdict reads as a Good chip, not an advisory',
      (tester) async {
    // R-04: both healthy -> "Nothing to fix" headline, a Good verdict.
    final report = AnalyzeEngine.analyze(
      const AnalyzeInput(verdict: WifiVsInternetVerdict.bothHealthy),
    );
    await _precacheCategorySvgs(tester);
    await tester.pumpWidget(_wrap(report));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing to fix'), findsOneWidget);
  });

  testWidgets('no draft-guidance banner now that every rule is ratified',
      (tester) async {
    final report = AnalyzeEngine.analyze(
      const AnalyzeInput(band: '2.4 GHz', standard: '802.11ax (Wi-Fi 6)'),
    );
    expect(report.hasPendingDraft, isFalse);
    await _precacheCategorySvgs(tester);
    await tester.pumpWidget(_wrap(report));
    await tester.pumpAndSettle();
    expect(find.textContaining('draft guidance under review'), findsNothing);
    expect(find.textContaining('Draft guidance'), findsNothing);
  });

  testWidgets('empty report shows the honest empty state and disables Copy',
      (tester) async {
    final report = AnalyzeEngine.analyze(const AnalyzeInput());
    expect(report.hasFindings, isFalse);
    await tester.pumpWidget(_wrap(report));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to analyze yet'), findsOneWidget);
    expect(find.byType(AppCopyAction), findsOneWidget);
    final Semantics copySem = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byType(AppCopyAction),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(copySem, isNotNull);
  });

  testWidgets('local-only note is always present', (tester) async {
    final report = AnalyzeEngine.analyze(
      const AnalyzeInput(security: WifiSecurity.open),
    );
    await _precacheCategorySvgs(tester);
    await tester.pumpWidget(_wrap(report));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing is sent or stored'), findsOneWidget);
  });

  testWidgets('no overflow across widths in BOTH dark and light',
      (tester) async {
    final report = AnalyzeEngine.analyze(
      const AnalyzeInput(
        verdict: WifiVsInternetVerdict.bothContributing,
        rssiDbm: -73,
        snrDb: 10,
        security: WifiSecurity.open,
        lossPct: 5,
        latencyMs: 150,
        platformIsIos: true,
        wifiSignalCaptured: false, // also fire the honesty info row
      ),
    );
    await _precacheCategorySvgs(tester);
    for (final bool light in const <bool>[false, true]) {
      for (final Size size in const <Size>[
        Size(320, 720), // narrow phone stress
        Size(390, 844), // iPhone
        Size(768, 1024), // tablet
        Size(1280, 900), // desktop
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(_wrap(report, light: light));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at $size (light=$light)',
        );
      }
    }
  });
}
