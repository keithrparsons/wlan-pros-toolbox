// Tests for the NEC Gotchas reference screen — Field Reference #4 of the Field
// & Trade Reference set (2026-07-05).
//
// Three layers, mirroring the enclosure-ratings pilot test:
//   1. Data fidelity (GL-005): the typed const dataset carries Penn's approved,
//      voice-gated facts verbatim (the article set, the CMP-plenum cable rung,
//      the two recognize-and-STOP callouts, the grounding caveat, the AHJ /
//      licensed-electrician defer line), plus the no-em-dash and "Wi-Fi" glyph
//      rules across all rendered prose.
//   2. Registration: the tool has a live Quick Reference tile in the "Codes &
//      Safety" subgroup, a registered route builder, and a keyword set. The help
//      count guard is asserted in tool_help_loader_test.
//   3. Widget render: the read-only screen renders its title and key content
//      across phone/tablet/desktop widths, in BOTH dark and light themes, with
//      no RenderFlex overflow; the embedded-PNG plate is omitted when the asset
//      is not bundled (graceful degradation) and shown once when it is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/nec_gotchas_data.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/nec_gotchas_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('article set: exactly SIX gotchas, first is the hoistway rule (620)',
        () {
      // Regression (Vera HIGH): the lead and the recap both say "six code
      // articles," and the approved plate shows six numbered callouts plus a
      // SEPARATE ladder band. The Article 800 cable-rating ladder must NOT be
      // one of these six, or the screen renders seven peer cards under a "six"
      // claim (a self-contradiction and a native-vs-plate mismatch).
      expect(kNecArticles.length, 6);
      expect(kNecArticles.first.title.contains('Article 620'), isTrue);
      expect(
        kNecArticles.first.body.contains('not elevator equipment'),
        isTrue,
      );
      // The ladder is not smuggled back into the six.
      expect(
        kNecArticles.any((NecArticle a) => a.title.contains('Article 800)')),
        isFalse,
        reason: 'the cable ladder is a supporting reference, not a 7th gotcha',
      );
      // The six named in the recap: hoistway, plenum, PoE bundle, antenna,
      // fire wall, dead cable — no cable-rating ladder among them.
      expect(kNecWlanCares.contains('These six'), isTrue);
    });

    test('cable ladder (800): a SEPARATE supporting reference, CMP top rung', () {
      // Lifted out of the six into its own const, rendered under its own
      // "Supporting reference" heading (mirrors the plate's separate band).
      expect(kNecCableLadder.title.contains('Article 800)'), isTrue);
      expect(
        kNecCableLadder.bullets.first,
        'CMP: plenum. Highest, usable anywhere.',
      );
      expect(
        kNecCableLadder.tail!.contains('Substitution runs downhill only'),
        isTrue,
      );
      expect(
        kNecCableLadderSectionTitle,
        'Supporting reference: the cable fire-rating ladder',
      );
    });

    test('PoE bundle heat (725.144) carries a recognize-and-STOP band', () {
      final NecArticle poe = kNecArticles.firstWhere(
        (NecArticle a) => a.title.contains('725.144'),
      );
      expect(poe.stop, isNotNull);
      expect(poe.stop!.startsWith('STOP:'), isTrue);
      expect(poe.stop!.contains('Do not eyeball them'), isTrue);
    });

    test('firestopping (300.21) carries a recognize-and-STOP band', () {
      final NecArticle fire = kNecArticles.firstWhere(
        (NecArticle a) => a.title.contains('300.21'),
      );
      expect(fire.stop, isNotNull);
      expect(fire.stop!.contains('Never improvise it'), isTrue);
    });

    test('grounding (810) carries the honest direct-strike caveat', () {
      final NecArticle ground = kNecArticles.firstWhere(
        (NecArticle a) => a.title.contains('Article 810'),
      );
      expect(ground.caveat, isNotNull);
      expect(
        ground.caveat!.contains('nothing survives a direct strike'),
        isTrue,
      );
    });

    test('defer footer names the AHJ and a licensed electrician', () {
      expect(kNecDeferNote.contains('AHJ'), isTrue);
      expect(kNecDeferNote.contains('licensed electrician'), isTrue);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      final List<String> prose = <String>[
        kNecLead,
        kNecWlanCares,
        kNecDeferNote,
        kNecCableLadderSectionTitle,
        for (final NecArticle a in <NecArticle>[
          ...kNecArticles,
          kNecCableLadder,
        ]) ...<String>[
          a.title,
          a.body,
          ...a.bullets,
          if (a.tail != null) a.tail!,
          if (a.stop != null) a.stop!,
          if (a.caveat != null) a.caveat!,
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
        (ToolEntry e) => e.id == 'nec-gotchas',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/nec-gotchas');
      expect(t.title, 'NEC Gotchas');
      expect(t.subgroup, 'Codes & Safety');
    });

    test('no orphaned subgroup — grouping places the tool under its header', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final List<ToolSection> sections = groupedCategoryTools(qr);
      final ToolSection codes =
          sections.firstWhere((ToolSection s) => s.header == 'Codes & Safety');
      expect(
        codes.tools.any((ToolEntry e) => e.id == 'nec-gotchas'),
        isTrue,
      );
    });

    test('route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/nec-gotchas'), isTrue);
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('nec-gotchas'), isTrue);
      expect(kToolKeywords['nec-gotchas']!, isNotEmpty);
      expect(kToolKeywords['nec-gotchas']!.contains('plenum'), isTrue);
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
        await _withViewport(tester, const Size(375, 7000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: const NecGotchasScreen(),
            ),
          );
          await tester.pump();
          expect(find.text('NEC Gotchas'), findsWidgets);
          expect(
            find.text('Elevator hoistways (Article 620, especially 620.37)'),
            findsOneWidget,
          );
          expect(find.text('PoE bundle heat (Article 725.144)'), findsOneWidget);
          // The cable ladder is set apart under its supporting-reference
          // heading, rendered once, distinct from the six gotcha cards.
          expect(
            find.text('Supporting reference: the cable fire-rating ladder'),
            findsOneWidget,
          );
          expect(
            find.text('The communications-cable rating ladder (Article 800)'),
            findsOneWidget,
          );
          expect(find.text('Why a WLAN pro cares'), findsOneWidget);
          // Read-only reference: no inputs.
          expect(find.byType(TextField), findsNothing);
          // No PNG bundled -> no embedded plate.
          expect(find.byType(DarkRasterDiagramCard), findsNothing);
        });
      }
    });

    testWidgets('shows exactly one plate card when the PNG is bundled',
        (tester) async {
      ReferenceImages.debugSetBundled(<String>{
        ReferenceImages.pathFor('nec-gotchas'),
      });
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 7000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const NecGotchasScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(DarkRasterDiagramCard), findsOneWidget);
      });
    });

    testWidgets('no overflow at 320/375/768/1280 widths', (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 7000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const NecGotchasScreen(),
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

/// Helper — run [body] with the test view sized to [size], then restore.
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
