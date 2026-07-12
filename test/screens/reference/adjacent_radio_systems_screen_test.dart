// Tests for the Adjacent Radio Systems reference screen, a Field & Trade
// Reference set entry (2026-07-05). Three layers: data fidelity (the ten-system
// coexistence table, the five 2.4 GHz contenders, the three corrections, plus
// the no-em-dash / "Wi-Fi" guards), registration (a live "Wireless Landscape"
// Quick Reference tile, route, keywords), and widget render (dark + light, no
// overflow at 320/375/768/1280, the envelope caution rendered as a warning
// band, plate omitted when unbundled and shown once when bundled).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/adjacent_radio_systems_data.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/adjacent_radio_systems_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

List<String> _allProse() => <String>[
      kAdjacentLead,
      kTwoFourIntro,
      ...kTwoFourContenders,
      kTwoFourCoordinate,
      kSubGhzIntro,
      kEnvelopeWarning,
      ...kRadioCorrections,
      kWhichRadioIntro,
      ...kWhichRadioWhen,
      kAdjacentWlanCares,
      kAdjacentDeferNote,
      for (final RadioSystemRow r in kRadioSystems) ...<String>[
        r.system,
        r.band,
        r.range,
        r.dataRate,
        r.sharesTwoFour,
      ],
    ];

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('coexistence table: exactly 10 systems, shares-2.4 anchored', () {
      expect(kRadioSystems.length, 10);
      RadioSystemRow bySystem(String s) =>
          kRadioSystems.firstWhere((RadioSystemRow r) => r.system == s);
      expect(bySystem('LoRaWAN').sharesTwoFour, 'No');
      expect(bySystem('Zigbee').sharesTwoFour, 'Yes');
      expect(bySystem('BLE').sharesTwoFour, 'Yes');
      expect(bySystem('Private 5G / CBRS').sharesTwoFour, 'No');
    });

    test('2.4 GHz contenders (4 bullets, 5 named systems) and 3 corrections',
        () {
      // The copy lists FIVE 2.4 GHz systems but folds BLE and Bluetooth Classic
      // into a single bullet, so there are four bullet rows; the five are named
      // verbatim in the lead.
      expect(kTwoFourContenders.length, 4);
      expect(
        kAdjacentLead
            .contains('BLE, Bluetooth Classic, Zigbee, Thread, and ANT+'),
        isTrue,
      );
      expect(kRadioCorrections.length, 3);
      expect(kRadioCorrections[2].contains('CBRS and private 5G do not '
          'interfere'), isTrue);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      for (final String s in _allProse()) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('WiFi'), isFalse, reason: 'must be "Wi-Fi" in "$s"');
      }
    });
  });

  group('registration (catalog + subgroup + router + keywords)', () {
    test('live Quick Reference tile in "Wireless Landscape"', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final ToolEntry t = qr.tools.firstWhere(
        (ToolEntry e) => e.id == 'adjacent-radio-systems',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/adjacent-radio-systems');
      expect(t.title, 'Adjacent Radio Systems');
      expect(t.subgroup, 'Wireless Landscape');
    });

    test('grouping places the tool under "Wireless Landscape", not "Other"', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final List<ToolSection> sections = groupedCategoryTools(qr);
      for (final ToolSection s
          in sections.where((ToolSection s) => s.header == 'Other')) {
        expect(
          s.tools.any((ToolEntry e) => e.id == 'adjacent-radio-systems'),
          isFalse,
          reason: 'adjacent-radio-systems orphaned into Other',
        );
      }
      final ToolSection wl = sections.firstWhere(
        (ToolSection s) => s.header == 'Wireless Landscape',
      );
      expect(
        wl.tools.any((ToolEntry e) => e.id == 'adjacent-radio-systems'),
        isTrue,
      );
    });

    test('route resolves to a registered builder', () {
      expect(
        AppRouter.routes.containsKey('/tools/adjacent-radio-systems'),
        isTrue,
      );
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('adjacent-radio-systems'), isTrue);
      expect(kToolKeywords['adjacent-radio-systems']!, isNotEmpty);
      expect(kToolKeywords['adjacent-radio-systems']!.contains('zigbee'), isTrue);
    });
  });

  group('widget render (dark + light, no overflow)', () {
    setUp(() {
      ReferenceImages.debugSetBundled(const <String>{});
    });
    tearDown(ReferenceImages.debugReset);

    testWidgets(
        'renders title + key content + warning band in dark + light, plate '
        'omitted', (tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
      ]) {
        await _withViewport(tester, const Size(375, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: const AdjacentRadioSystemsScreen(),
            ),
          );
          await tester.pump();
          expect(find.text('Adjacent Radio Systems'), findsWidgets);
          // WAS: 'What does not touch your air'. That heading sat directly above
          // Zigbee, Thread and BLE, each rendering "Shares 2.4 GHz: Yes" — the
          // card contradicted every one of its own rows. Retitled to point at
          // the per-row answer instead of pre-empting it with a false claim.
          expect(
            find.text('The other radios, and which share your air'),
            findsOneWidget,
          );
          expect(find.text('Why a WLAN pro cares'), findsOneWidget);
          expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(DarkRasterDiagramCard), findsNothing);
        });
      }
    });

    testWidgets('shows exactly one plate card when the PNG is bundled',
        (tester) async {
      ReferenceImages.debugSetBundled(<String>{
        ReferenceImages.pathFor('adjacent-radio-systems'),
      });
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const AdjacentRadioSystemsScreen(),
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
              home: const AdjacentRadioSystemsScreen(),
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
