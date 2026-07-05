// Tests for the Network in Scope reference screen, a Field & Trade Reference set
// entry (2026-07-05). Three layers: data fidelity (the five PCI asks, four
// HIPAA safeguards, three SOX touches, plus the no-em-dash / "Wi-Fi" guards),
// registration (a live "Compliance & Governance" Quick Reference tile, route,
// keywords), and widget render (dark + light, no overflow at 320/375/768/1280,
// plate omitted when unbundled and shown once when bundled).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/network_in_scope_data.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/network_in_scope_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

List<String> _allProse() => <String>[
      kNetScopeLead,
      kPciIntro,
      kPciAsksIntro,
      ...kPciAsks,
      kPciRouteTo,
      kHipaaIntro,
      kHipaaSafeguardsIntro,
      ...kHipaaSafeguards,
      kHipaaNuance,
      kHipaaRouteTo,
      kSoxIntro,
      kSoxTouchesIntro,
      ...kSoxTouches,
      kSoxNarrowest,
      kGdprNetworkSide,
      kNetScopeWlanCares,
      kNetScopeDeferNote,
    ];

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('PCI asks: exactly 5; CDE steered to 802.1X/EAP and the quarterly scan',
        () {
      expect(kPciAsks.length, 5);
      expect(
        kPciAsks[1].contains(
          'PCI guidance steers the cardholder-data environment to 802.1X/EAP; '
          'PSK is discouraged there',
        ),
        isTrue,
      );
      expect(kPciAsks[3].contains('at least quarterly'), isTrue);
    });

    test('HIPAA safeguards: exactly 4; transmission security is last', () {
      expect(kHipaaSafeguards.length, 4);
      expect(kHipaaSafeguards.last.contains('Transmission security'), isTrue);
    });

    test('SOX touches: exactly 3', () {
      expect(kSoxTouches.length, 3);
      expect(kSoxTouches.first.contains('Access controls'), isTrue);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      for (final String s in _allProse()) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('WiFi'), isFalse, reason: 'must be "Wi-Fi" in "$s"');
      }
    });
  });

  group('registration (catalog + subgroup + router + keywords)', () {
    test('live Quick Reference tile in "Compliance & Governance"', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final ToolEntry t = qr.tools.firstWhere(
        (ToolEntry e) => e.id == 'network-in-scope',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/network-in-scope');
      expect(t.title, 'Network in Scope');
      expect(t.subgroup, 'Compliance & Governance');
    });

    test('grouping places the tool under "Compliance & Governance", not "Other"',
        () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final List<ToolSection> sections = groupedCategoryTools(qr);
      for (final ToolSection s
          in sections.where((ToolSection s) => s.header == 'Other')) {
        expect(
          s.tools.any((ToolEntry e) => e.id == 'network-in-scope'),
          isFalse,
          reason: 'network-in-scope orphaned into Other',
        );
      }
      final ToolSection cg = sections.firstWhere(
        (ToolSection s) => s.header == 'Compliance & Governance',
      );
      expect(cg.tools.any((ToolEntry e) => e.id == 'network-in-scope'), isTrue);
    });

    test('route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/network-in-scope'), isTrue);
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('network-in-scope'), isTrue);
      expect(kToolKeywords['network-in-scope']!, isNotEmpty);
      expect(kToolKeywords['network-in-scope']!.contains('pci'), isTrue);
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
        await _withViewport(tester, const Size(375, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(theme: theme, home: const NetworkInScopeScreen()),
          );
          await tester.pump();
          expect(find.text('Network in Scope'), findsWidgets);
          expect(
            find.text('PCI DSS: cardholder data over Wi-Fi'),
            findsOneWidget,
          );
          expect(find.text('Why a WLAN pro cares'), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(DarkRasterDiagramCard), findsNothing);
        });
      }
    });

    testWidgets('shows exactly one plate card when the PNG is bundled',
        (tester) async {
      ReferenceImages.debugSetBundled(<String>{
        ReferenceImages.pathFor('network-in-scope'),
      });
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const NetworkInScopeScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(DarkRasterDiagramCard), findsOneWidget);
      });
    });

    testWidgets('no overflow at 320/375/768/1280 widths', (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const NetworkInScopeScreen(),
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
