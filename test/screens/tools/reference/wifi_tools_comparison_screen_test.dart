// Wi-Fi Tools Comparison wiring + screen tests. Guards (a) the catalog/route
// wiring for the new `wifi-tools-comparison` id and (b) that the screen renders
// the disclaimer band (beta + pricing date-stamp + modeled-estimate + neutrality
// + no-logos), the activity sections, the TCO figures, the vendor link-out
// chips, search, and the honest empty state. A pre-built service + a fake
// launcher are injected so the tests do not depend on the bundled asset or a
// real browser.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_tools_comparison_screen.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_tools_comparison_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _fixture = '''
{
  "_meta": {
    "pricingDate": "February 2026",
    "pricingNote": "Pricing as of February 2026. Confirm current pricing with the vendor before you buy.",
    "estimateNote": "Cost figures are modeled estimates, not vendor-published quotes.",
    "betaNote": "This comparison is in beta review. Vendors are being consulted on the figures.",
    "neutralityNote": "This is a capability and cost reference, not a ranking.",
    "noLogosNote": "No vendor logos or product photos appear here.",
    "currency": "USD",
    "tcoLabel": "3-year TCO",
    "source": "V6 workbook + Pax brief 2026-06-05"
  },
  "activities": [
    {
      "id": "design",
      "title": "Wi-Fi Design",
      "intro": "Design is the planning phase.",
      "configs": [
        { "vendor": "Ekahau", "product": "AI Pro + Connect", "costModel": "subscription", "upFront": 7990, "tco3yr": 11980, "notes": "AI Pro with 4G/5G planning." },
        { "vendor": "Hamina", "product": "Planner", "costModel": "subscription", "upFront": 980, "tco3yr": 2940, "notes": "SaaS pricing." }
      ]
    },
    {
      "id": "spectrum",
      "title": "Spectrum Analysis",
      "intro": "Spectrum analysis looks below Wi-Fi.",
      "configs": [
        { "vendor": "Oscium", "product": "Chanalyzer + Wi-Spy Lucid", "costModel": "perpetual", "upFront": 1599, "tco3yr": 1899, "notes": "Triband spectrum analyzer." }
      ]
    }
  ],
  "toolkits": [
    { "vendor": "Sidos", "product": "Wave, Cloud & MicroApps", "tco3yr": 8964, "notes": "No spectrum analysis." }
  ],
  "vendors": [
    { "name": "Ekahau", "summary": "Design and survey company.", "website": "https://www.ekahau.com", "docs": "https://support.ekahau.com" }
  ]
}
''';

WifiToolsComparisonService _svc() =>
    WifiToolsComparisonService.fromJson(_fixture);

Widget _harness(
  WifiToolsComparisonService svc, {
  Future<bool> Function(Uri)? launcher,
}) =>
    MaterialApp(
      theme: AppTheme.dark(),
      home: WifiToolsComparisonScreen(service: svc, launcher: launcher),
    );

ToolEntry _entry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'wifi-tools-comparison');

void main() {
  group('catalog + route wiring', () {
    test('the tool id resolves to a live ToolEntry in Quick Reference', () {
      final ToolEntry entry = _entry();
      expect(entry.title, 'Wi-Fi Tools Comparison');
      expect(entry.routeName, '/tools/wifi-tools-comparison');
      expect(entry.isLive, isTrue);
      expect(entry.subgroup, 'Wi-Fi & RF');

      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'wifi-tools-comparison'),
      );
      expect(cat.id, 'quick-reference');
    });

    test('the route is registered and follows the /tools/<id> convention', () {
      expect(
        AppRouter.routes.containsKey(AppRouter.wifiToolsComparison),
        isTrue,
      );
      expect(AppRouter.wifiToolsComparison, '/tools/wifi-tools-comparison');
    });

    test('the bundled asset + tool-id constants are stable', () {
      expect(
        kWifiToolsComparisonAsset,
        'assets/data/wifi_tools_comparison.json',
      );
      expect(kWifiToolsComparisonToolId, 'wifi-tools-comparison');
    });

    test('search keywords are registered for discovery', () {
      final List<String>? kw = kToolKeywords['wifi-tools-comparison'];
      expect(kw, isNotNull);
      expect(
        kw,
        containsAll(<String>['comparison', 'survey', 'spectrum', 'tco', 'cost']),
      );
    });
  });

  group('screen', () {
    testWidgets('renders the title, the disclaimer band, and the activities',
        (tester) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();

      expect(find.text('Wi-Fi Tools Comparison'), findsWidgets);
      // The honesty disclaimers are all on-screen (not just in data).
      expect(find.textContaining('beta review'), findsOneWidget);
      expect(find.textContaining('Pricing as of February 2026'), findsOneWidget);
      expect(find.textContaining('modeled estimates'), findsOneWidget);
      expect(find.textContaining('not a ranking'), findsOneWidget);
      expect(find.textContaining('No vendor logos'), findsOneWidget);
      // Activity headings + a known config.
      expect(find.text('Wi-Fi Design'), findsOneWidget);
      expect(find.text('Spectrum Analysis'), findsOneWidget);
      expect(find.text('Ekahau'), findsWidgets);
      expect(find.text('AI Pro + Connect'), findsOneWidget);
      // The search field is present.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders the modeled TCO figures', (tester) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();
      // The Ekahau design config carries up-front + 3-year TCO.
      expect(find.text('\$7,990'), findsOneWidget);
      expect(find.text('\$11,980'), findsOneWidget);
      // The Sidos toolkit roll-up figure.
      expect(find.text('\$8,964'), findsOneWidget);
    });

    testWidgets('renders the vendor summary + a website link-out chip',
        (tester) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();
      expect(find.text('Design and survey company.'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
      expect(find.text('Docs'), findsOneWidget);
    });

    testWidgets('tapping a link chip invokes the launcher with the URL',
        (tester) async {
      Uri? opened;
      await tester.pumpWidget(
        _harness(
          _svc(),
          launcher: (Uri u) async {
            opened = u;
            return true;
          },
        ),
      );
      await tester.pump();

      // The vendor link-out chips sit below the fold in the 800x600 test
      // viewport; scroll the Website chip into view before tapping it.
      final Finder website = find.text('Website');
      await tester.ensureVisible(website);
      await tester.pumpAndSettle();
      await tester.tap(website, warnIfMissed: false);
      await tester.pump();
      expect(opened.toString(), 'https://www.ekahau.com');
    });

    testWidgets('typing a query narrows activities in place', (tester) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'oscium');
      await tester.pump();

      expect(find.text('Chanalyzer + Wi-Spy Lucid'), findsOneWidget);
      // The non-matching design configs are gone from the activity list.
      expect(find.text('AI Pro + Connect'), findsNothing);
    });

    testWidgets('a no-match query shows the honest empty state', (tester) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'zzznotapresentword');
      await tester.pump();

      expect(find.text('No match'), findsOneWidget);
      expect(find.text('AI Pro + Connect'), findsNothing);
    });
  });
}
