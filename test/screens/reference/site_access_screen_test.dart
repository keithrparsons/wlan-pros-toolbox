// Tests for the Site Access ("Know Before You Go") reference screen, a Field &
// Trade Reference set entry (2026-07-05). Three layers, mirroring the Enclosure
// Ratings reference tests:
//   1. Data fidelity (GL-005): the typed const dataset carries Penn's approved,
//      voice-gated facts verbatim (the eight-environment access checklist, its
//      gates and ask-about lists), plus the no-em-dash and "Wi-Fi" glyph
//      guards across all rendered prose, with a data-fidelity count guard.
//   2. Registration: a live Quick Reference tile in the "Codes & Safety"
//      subgroup, a registered route builder, a keyword set, and a help entry.
//   3. Widget render: the read-only screen renders its title and key content in
//      BOTH dark and light themes with no RenderFlex overflow; the embedded-PNG
//      plate is omitted when the asset is not bundled and shown once when it is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/site_access_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/site_access_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('access checklist: exactly 8 environments', () {
      expect(kSiteAccessRows.length, 8);
      expect(
        kSiteAccessRows.map((SiteAccessRow r) => r.environment).toList(),
        <String>[
          'Aerial and man-lifts (boom, scissor)',
          'Rail or near active track',
          'Hospitals and active patient care',
          'Maritime, over-water, docks',
          'Warehouse and distribution centers',
          'Schools and childcare',
          'Data centers',
          'Correctional facilities',
        ],
      );
    });

    test('anchor gates carry the load-bearing credential facts', () {
      SiteAccessRow byEnv(String prefix) => kSiteAccessRows
          .firstWhere((SiteAccessRow r) => r.environment.startsWith(prefix));
      expect(byEnv('Rail').gate.contains('background screening'), isTrue);
      expect(byEnv('Rail').askAbout.contains('eRailSafe'), isTrue);
      expect(byEnv('Hospitals').gate.contains('ICRA'), isTrue);
      expect(byEnv('Maritime').gate.contains('NEMA 4X'), isTrue);
      expect(byEnv('Correctional').gate.contains('tool control'), isTrue);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      final List<String> prose = <String>[
        kSiteAccessLead,
        kSiteAccessPattern,
        kSiteAccessWlanCares,
        kSiteAccessDeferNote,
        for (final SiteAccessRow r in kSiteAccessRows) ...<String>[
          r.environment,
          r.gate,
          r.askAbout,
        ],
      ];
      for (final String s in prose) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('WiFi'), isFalse, reason: 'must be "Wi-Fi" in "$s"');
      }
    });
  });

  group('registration (catalog + subgroup + router + keywords)', () {
    test('live Quick Reference tile in the "Codes & Safety" subgroup', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final ToolEntry t = qr.tools.firstWhere(
        (ToolEntry e) => e.id == 'site-access',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/site-access');
      expect(t.title, 'Site Access');
      expect(t.subgroup, 'Codes & Safety');
    });

    test('grouping places the tool under "Codes & Safety", not "Other"', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final List<ToolSection> sections = groupedCategoryTools(qr);
      for (final ToolSection s in sections.where(
        (ToolSection s) => s.header == 'Other',
      )) {
        expect(
          s.tools.any((ToolEntry e) => e.id == 'site-access'),
          isFalse,
          reason: 'site-access orphaned into Other',
        );
      }
      final ToolSection codes =
          sections.firstWhere((ToolSection s) => s.header == 'Codes & Safety');
      expect(
        codes.tools.any((ToolEntry e) => e.id == 'site-access'),
        isTrue,
      );
    });

    test('route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/site-access'), isTrue);
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('site-access'), isTrue);
      expect(kToolKeywords['site-access']!, isNotEmpty);
      expect(kToolKeywords['site-access']!.contains('icra'), isTrue);
    });
  });

  group('widget render (dark + light, no overflow)', () {
    setUp(() {
      ReferenceImages.debugSetBundled(const <String>{});
    });
    tearDown(ReferenceImages.debugReset);

    testWidgets('renders title + key content in dark + light, plate omitted',
        (tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
      ]) {
        await _withViewport(tester, const Size(375, 4600), () async {
          await tester.pumpWidget(
            MaterialApp(theme: theme, home: const SiteAccessScreen()),
          );
          await tester.pump();
          expect(find.text('Site Access'), findsWidgets);
          expect(find.text('The checklist'), findsOneWidget);
          expect(find.text('Why a WLAN pro cares'), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(DarkRasterDiagramCard), findsNothing);
        });
      }
    });

    testWidgets('shows exactly one plate card when the PNG is bundled',
        (tester) async {
      ReferenceImages.debugSetBundled(<String>{
        ReferenceImages.pathFor('site-access'),
      });
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 4600), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const SiteAccessScreen()),
        );
        await tester.pump();
        expect(find.byType(DarkRasterDiagramCard), findsOneWidget);
      });
    });

    testWidgets('no overflow at 320/375/768/1280 widths', (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 4200), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const SiteAccessScreen(),
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
