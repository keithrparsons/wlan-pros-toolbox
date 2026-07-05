// Tests for the Data Centers & Wi-Fi reference screen, a Field & Trade Reference
// set entry (2026-07-05). Text-reference only (no decoder plate). Three layers:
// data fidelity (the two resilience frameworks, the four-rung Uptime Tier
// ladder, plus the no-em-dash / "Wi-Fi" guards), registration (a live
// "Verticals" Quick Reference tile, route, keywords), and widget render (dark +
// light, no overflow at 320/375/768/1280, the Rated-vs-Tier caution rendered as
// a warning band; no plate).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/data_centers_wifi_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/data_centers_wifi_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

List<String> _allProse() => <String>[
      kDataCenterLead,
      kDataCenterMinimalIntro,
      ...kDataCenterWifiRoles,
      kDataCenterClarify,
      kDataCenterRfIntro,
      ...kDataCenterRfFights,
      kDataCenterCoverage,
      kDataCenterFrameworksIntro,
      kDataCenterConflateWarning,
      kUptimeLadderIntro,
      ...kUptimeTiers,
      kDataCenterTierDefer,
      kDataCenterAccess,
      kDataCenterWhatToDoIntro,
      ...kDataCenterWhatToDo,
      kDataCenterWlanCares,
      kDataCenterDeferNote,
      for (final ResilienceFramework f in kResilienceFrameworks) ...<String>[
        f.framework,
        f.owner,
        f.levels,
        f.rates,
      ],
    ];

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('frameworks: exactly 2; TIA says Rated, Uptime says Tier', () {
      expect(kResilienceFrameworks.length, 2);
      final ResilienceFramework tia = kResilienceFrameworks
          .firstWhere((ResilienceFramework f) => f.framework == 'ANSI/TIA-942');
      final ResilienceFramework uptime = kResilienceFrameworks.firstWhere(
        (ResilienceFramework f) => f.framework == 'Uptime Institute Tiers',
      );
      expect(tia.levels, 'Rated-1 to Rated-4');
      expect(uptime.levels, 'Tier I to Tier IV');
    });

    test('Uptime Tier ladder: exactly 4; Tier III concurrently maintainable',
        () {
      expect(kUptimeTiers.length, 4);
      expect(kUptimeTiers[2].contains('Concurrently Maintainable'), isTrue);
      expect(kDataCenterWifiRoles.length, 3);
      expect(kDataCenterWhatToDo.length, 4);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      for (final String s in _allProse()) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('WiFi'), isFalse, reason: 'must be "Wi-Fi" in "$s"');
      }
    });
  });

  group('registration (catalog + subgroup + router + keywords)', () {
    test('live Quick Reference tile in "Verticals"', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final ToolEntry t = qr.tools.firstWhere(
        (ToolEntry e) => e.id == 'data-centers-wifi',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/data-centers-wifi');
      expect(t.title, 'Data Centers & Wi-Fi');
      expect(t.subgroup, 'Verticals');
    });

    test('grouping places the tool under "Verticals", not "Other"', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final List<ToolSection> sections = groupedCategoryTools(qr);
      for (final ToolSection s
          in sections.where((ToolSection s) => s.header == 'Other')) {
        expect(
          s.tools.any((ToolEntry e) => e.id == 'data-centers-wifi'),
          isFalse,
          reason: 'data-centers-wifi orphaned into Other',
        );
      }
      final ToolSection v = sections.firstWhere(
        (ToolSection s) => s.header == 'Verticals',
      );
      expect(v.tools.any((ToolEntry e) => e.id == 'data-centers-wifi'), isTrue);
    });

    test('route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/data-centers-wifi'), isTrue);
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('data-centers-wifi'), isTrue);
      expect(kToolKeywords['data-centers-wifi']!, isNotEmpty);
      expect(kToolKeywords['data-centers-wifi']!.contains('tia-942'), isTrue);
    });
  });

  group('widget render (dark + light, no overflow)', () {
    testWidgets(
        'renders title + key content + warning band in dark + light, no plate',
        (tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
      ]) {
        await _withViewport(tester, const Size(375, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(theme: theme, home: const DataCentersWifiScreen()),
          );
          await tester.pump();
          expect(find.text('Data Centers & Wi-Fi'), findsWidgets);
          expect(find.text('Two frameworks people mix up'), findsOneWidget);
          expect(find.text('Why a WLAN pro cares'), findsOneWidget);
          expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(DarkRasterDiagramCard), findsNothing);
        });
      }
    });

    testWidgets('no overflow at 320/375/768/1280 widths', (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const DataCentersWifiScreen(),
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow at ${width}px',
          );
        });
      }
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
