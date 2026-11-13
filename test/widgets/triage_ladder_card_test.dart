// TriageLadderCard, widget tests: every status is a WORD plus a glyph (never
// color alone), it fits a 320 px phone at large text, and it renders nothing
// when there is no ladder.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/triage_ladder.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/triage_ladder_card.dart';

TriageLadder _ladder({
  WifiVsInternetVerdict verdict = WifiVsInternetVerdict.bothHealthy,
  bool notOnWifi = false,
  bool wired = false,
  TriageDnsState dns = TriageDnsState.resolved,
  int dnsMs = 20,
}) => TriageLadder.compute(
  TriageInput(
    verdict: wired ? WifiVsInternetVerdict.wifiUnknown : verdict,
    rssiDbm: wired ? null : -55,
    notOnWifi: notOnWifi,
    dns: dns,
    dnsMs: dnsMs,
    evidence: const OnlineEvidence(
      dnsResolved: true,
      publicIpObtained: true,
      cloudReachable: true,
    ),
    internetMeasured: true,
    internetHealth: InternetHealth.good,
    cloudPanelPresent: true,
    cloudReachableCount: 14,
    cloudTotalCount: 14,
  ),
);

Widget _host(
  TriageLadder ladder, {
  bool showReasons = false,
  double width = 320,
  double textScale = 1,
  bool light = false,
}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 800),
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: SizedBox(
            width: width,
            child: TriageLadderCard(ladder: ladder, showReasons: showReasons),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('empty ladder renders nothing', (WidgetTester tester) async {
    await tester.pumpWidget(_host(TriageLadder.compute(const TriageInput())));
    expect(find.text('Where it looks off'), findsNothing);
  });

  testWidgets('shows the title, each rung name and a status word', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_ladder()));
    expect(find.text('Where it looks off'), findsOneWidget);
    for (final String name in <String>[
      'Wi-Fi link',
      'Name lookup (DNS)',
      'The internet',
      'Services',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Looks fine'), findsNWidgets(4));
  });

  testWidgets('every status word is paired with a glyph', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _ladder(
          verdict: WifiVsInternetVerdict.wifiLimiter,
          dns: TriageDnsState.pending,
        ),
      ),
    );
    final int rungs = 4;
    expect(find.byType(Icon), findsNWidgets(rungs));
    expect(find.text('Looks off'), findsOneWidget);
    expect(find.text('Checking'), findsOneWidget);
  });

  testWidgets('summary appears only when something looks off', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_ladder()));
    expect(find.textContaining('It looks like'), findsNothing);
    await tester.pumpWidget(_host(_ladder(dnsMs: 900)));
    expect(
      find.text('It looks like the trouble sits at name lookup (DNS).'),
      findsOneWidget,
    );
  });

  testWidgets('reasons show only when asked, caption with them', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_ladder(dnsMs: 900)));
    expect(find.text('Names are resolving slowly (900 ms).'), findsNothing);
    await tester.pumpWidget(_host(_ladder(dnsMs: 900), showReasons: true));
    expect(find.text('Names are resolving slowly (900 ms).'), findsOneWidget);
    expect(find.textContaining('Looks fine means'), findsOneWidget);
  });

  testWidgets('fits 320 px at 2x text with the longest status word', (
    WidgetTester tester,
  ) async {
    for (final bool light in <bool>[false, true]) {
      await tester.pumpWidget(
        _host(
          _ladder(wired: true, dnsMs: 900),
          showReasons: true,
          textScale: 2,
          light: light,
        ),
      );
      expect(find.text("Can't check on this device"), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a row reads aloud as name, status word and reason', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(_ladder(dnsMs: 900), showReasons: true));
    expect(
      find.bySemanticsLabel(
        RegExp(r'Name lookup \(DNS\), Looks off\. Names are resolving slowly'),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
