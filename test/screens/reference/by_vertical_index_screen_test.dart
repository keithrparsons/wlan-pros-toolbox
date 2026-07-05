// Tests for the Verticals Index reference screen, a Field & Trade Reference set
// entry (2026-07-05). Text-reference only (no decoder plate). Three layers: data
// fidelity (the ten-vertical map, the five retail/PCI facts, plus the
// no-em-dash / "Wi-Fi" guards), registration (a live "Verticals" Quick Reference
// tile, route, keywords), and widget render (dark + light, no overflow at
// 320/375/768/1280; no plate).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/by_vertical_index_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/by_vertical_index_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

List<String> _allProse() => <String>[
      kVerticalLead,
      kVerticalCodesNote,
      kVerticalTwoNotes,
      kRetailPciIntro,
      ...kRetailPciFacts,
      kRetailPciDefer,
      kHighDensityNote,
      kVerticalWlanCares,
      kVerticalDeferNote,
      for (final VerticalRow v in kVerticals) ...<String>[
        v.vertical,
        v.triggers,
        v.readFirst,
      ],
    ];

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('vertical map: exactly 10; anchor read-first pointers', () {
      expect(kVerticals.length, 10);
      VerticalRow byName(String prefix) => kVerticals
          .firstWhere((VerticalRow v) => v.vertical.startsWith(prefix));
      expect(byName('Oil').readFirst.contains('Hazardous'), isTrue);
      expect(byName('Healthcare').readFirst.contains('Healthcare Wi-Fi'), isTrue);
      expect(byName('Retail').readFirst, 'see the PCI note below');
    });

    test('retail/PCI facts: exactly 5', () {
      expect(kRetailPciFacts.length, 5);
      expect(kRetailPciFacts[2].contains('WPA2-PSK is inadequate'), isTrue);
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
        (ToolEntry e) => e.id == 'by-vertical-index',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/by-vertical-index');
      expect(t.title, 'Verticals Index');
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
          s.tools.any((ToolEntry e) => e.id == 'by-vertical-index'),
          isFalse,
          reason: 'by-vertical-index orphaned into Other',
        );
      }
      final ToolSection v = sections.firstWhere(
        (ToolSection s) => s.header == 'Verticals',
      );
      expect(v.tools.any((ToolEntry e) => e.id == 'by-vertical-index'), isTrue);
    });

    test('route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/by-vertical-index'), isTrue);
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('by-vertical-index'), isTrue);
      expect(kToolKeywords['by-vertical-index']!, isNotEmpty);
      expect(kToolKeywords['by-vertical-index']!.contains('retail'), isTrue);
    });
  });

  group('widget render (dark + light, no overflow)', () {
    testWidgets('renders title + key content in dark + light, no plate',
        (tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
      ]) {
        await _withViewport(tester, const Size(375, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(theme: theme, home: const ByVerticalIndexScreen()),
          );
          await tester.pump();
          expect(find.text('Verticals Index'), findsWidgets);
          expect(find.text('The map'), findsOneWidget);
          expect(find.text('Why a WLAN pro cares'), findsOneWidget);
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
              home: const ByVerticalIndexScreen(),
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
