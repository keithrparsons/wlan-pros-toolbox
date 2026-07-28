// Widget tests for ConceptGraphicBand — the §8.6.2 per-tool concept-graphic
// header band and its convention-based, gracefully-degrading asset lookup.
//
// Covers the contract the build brief locked in:
//   - present: when the tool's graphic IS bundled, the band renders an
//     SvgPicture inside a card-styled container at the band height;
//   - absent (graceful fallback): when the graphic is NOT bundled, the band
//     collapses to SizedBox.shrink() — no SvgPicture, no broken-image box,
//     layout unchanged;
//   - decorative for screen readers AT THE LEAF, never at a wrapper
//     (GL-003 §8.6.2.2, ratified 2026-07-27): `excludeFromSemantics: true` on
//     every SvgPicture render path silences the art, while ZoomableGraphic's
//     labeled zoom button stays in the semantics tree. The band is deliberately
//     NOT wrapped in ExcludeSemantics — that wrapper deleted the control from
//     the screen-reader tree on all 98 call sites. Both halves are pinned
//     against the semantics tree, never the widget tree;
//   - full-content-width, aspect-ratio-driven height (reworked 2026-06-08 off
//     the retired fixed 140/160dp strip): the band fills the width and derives
//     height from the graphic's viewBox aspect, clamped to a floor and a
//     viewport-fraction ceiling.
//
// Uses ToolAssets.debugSetBundledAssets to simulate the build-time manifest so
// the test never depends on a real asset bundle.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PipelineOwner;
import 'package:flutter/semantics.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_assets.dart';
import 'package:wlan_pros_toolbox/screens/tools/concept_graphic_band.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

// ── Semantics-tree probes ────────────────────────────────────────────────────
// These read the REAL SemanticsNode tree the band produces, not the widget
// tree. A widget-type assertion (`find.byType(ExcludeSemantics)`) cannot tell
// whether a control survived into the a11y tree — it only proves a widget of
// that type exists somewhere, which stays true whether or not the control is
// announced. The nodes are what VoiceOver / TalkBack actually read.

void _walk(SemanticsNode node, void Function(SemanticsNode) visit) {
  visit(node);
  node.visitChildren((SemanticsNode child) {
    _walk(child, visit);
    return true;
  });
}

/// The semantics owner lives on a CHILD PipelineOwner in Flutter's multi-view
/// tree, not on the root one, so walk down to find it rather than reaching for
/// the deprecated `binding.pipelineOwner`.
SemanticsNode? _rootSemanticsNode(WidgetTester tester) {
  SemanticsNode? found;
  void visit(PipelineOwner owner) {
    found ??= owner.semanticsOwner?.rootSemanticsNode;
    owner.visitChildren(visit);
  }

  visit(tester.binding.rootPipelineOwner);
  return found;
}

List<SemanticsNode> _allNodes(WidgetTester tester) {
  final SemanticsNode? root = _rootSemanticsNode(tester);
  final List<SemanticsNode> nodes = <SemanticsNode>[];
  if (root != null) _walk(root, nodes.add);
  return nodes;
}

/// Every non-empty label a screen reader would announce, in tree order.
List<String> _spokenLabels(WidgetTester tester) => _allNodes(tester)
    .map((SemanticsNode n) => n.getSemanticsData().label)
    .where((String l) => l.isNotEmpty)
    .toList();

/// Nodes carrying a given action — `tap` is the operable-control signal.
List<SemanticsNode> _nodesWithAction(
        WidgetTester tester, SemanticsAction action) =>
    _allNodes(tester)
        .where((SemanticsNode n) => n.getSemanticsData().hasAction(action))
        .toList();

/// Nodes the platform would announce as an image. The decorative SVG must
/// produce NONE — that is what `excludeFromSemantics: true` on every
/// SvgPicture buys, and dropping it on any branch shows up here.
List<SemanticsNode> _imageNodes(WidgetTester tester) => _allNodes(tester)
    .where((SemanticsNode n) => n.getSemanticsData().flagsCollection.isImage)
    .toList();

Future<void> _pump(
  WidgetTester tester, {
  required String toolId,
  bool isDesktop = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: ConceptGraphicBand(toolId: toolId, isDesktop: isDesktop),
      ),
    ),
  );
}

void main() {
  setUp(() {
    ToolAssets.debugReset();
    ConceptGraphicBand.debugClearCaches();
  });
  tearDown(() {
    ToolAssets.debugReset();
    ConceptGraphicBand.debugClearCaches();
  });

  group('ConceptGraphicBand', () {
    testWidgets('renders an SvgPicture when the graphic is bundled',
        (tester) async {
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fspl.svg'});
      await _pump(tester, toolId: 'fspl');

      expect(find.byType(SvgPicture), findsOneWidget);
      // It sits in a card-styled container (its own Container with decoration).
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('collapses to nothing when the graphic is NOT bundled',
        (tester) async {
      ToolAssets.debugSetBundledAssets(<String>{}); // nothing built
      await _pump(tester, toolId: 'fspl');

      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget); // the shrink sentinel
    });

    testWidgets('a different tool with no asset also degrades cleanly',
        (tester) async {
      // Only fspl is bundled; link-budget is not → link-budget collapses.
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fspl.svg'});
      await _pump(tester, toolId: 'link-budget');

      expect(find.byType(SvgPicture), findsNothing);
    });

    // GL-003 §8.6.2.2 (ratified 2026-07-27) — "Test obligation: both halves, or
    // the pin is fake." A test that pins only "the graphic is silent" passes
    // while the control is gone; one that pins only "the control is announced"
    // passes while the graphic leaks. This asserts BOTH, against the semantics
    // tree. It replaces a `find.byType(ExcludeSemantics), findsWidgets` check
    // that this test's own name made a false claim about: it asserted a widget
    // TYPE exists somewhere, so it stayed green when the graphic stopped being
    // decorative entirely — §8.6.2.2 makes a widget-tree assertion here a
    // FINDING for exactly that reason.
    testWidgets('is decorative for screen readers AND keeps its zoom control '
        'announced', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fresnel.svg'});
      ConceptGraphicBand.debugSeedCaches('fresnel', aspect: 2.0);
      await _pump(tester, toolId: 'fresnel');
      await tester.pump();

      // HALF 1 — the art is silent. The exposure is not leaked SVG text
      // (flutter_svg rasterises glyphs); it is the empty-labeled `image` node
      // vector_graphics emits for the picture. `excludeFromSemantics: true` on
      // every render path is what suppresses it, so isImage is the dimension
      // that can actually go red.
      expect(_imageNodes(tester), isEmpty,
          reason: 'GL-003 §8.6.2.2 rule 1 — every SvgPicture render path must '
              'pass excludeFromSemantics: true');

      // HALF 2 — the control survives. An ExcludeSemantics at or above the
      // band deletes this node, which is the defect this branch fixes.
      final List<SemanticsNode> tappable =
          _nodesWithAction(tester, SemanticsAction.tap);
      expect(tappable, hasLength(1),
          reason: 'GL-003 §8.6.2.2 rule 2 — no ExcludeSemantics at or above the '
              'graphic container; it would swallow the zoom control');
      expect(_spokenLabels(tester), <String>['Zoom graphic']);
      expect(tappable.single.getSemanticsData().flagsCollection.isButton, isTrue);

      handle.dispose();
    });

    testWidgets('renders a full-width band sized above the retired 140/160dp '
        'strip', (tester) async {
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/eirp.svg'});
      // Seed the eirp aspect (320×160 → 2.0) synchronously so the dark path
      // sizes from the real ratio on the first frame without bundle I/O.
      ConceptGraphicBand.debugSeedCaches('eirp', aspect: 2.0);
      await _pump(tester, toolId: 'eirp', isDesktop: false);
      await tester.pump();

      // The band's own full-width sizing box: width fills, height is the
      // aspect-driven band height, never the old 140/160dp strip and never
      // below the 180dp floor.
      final Finder bandBox = find.byWidgetPredicate(
        (Widget w) => w is SizedBox && w.width == double.infinity,
      );
      expect(bandBox, findsWidgets);
      final SizedBox box = tester.widgetList<SizedBox>(bandBox).firstWhere(
            (SizedBox s) => s.width == double.infinity && s.height != null,
          );
      expect(box.height, greaterThanOrEqualTo(180));
      expect(box.height, greaterThan(160)); // strictly bigger than the old band
    });
  });

  // ── REGRESSION: the band's zoom control must reach the a11y tree ──────────
  //
  // The band used to wrap its whole subtree in `ExcludeSemantics`. That is
  // strictly stronger than "the graphic is decorative": it also swallowed
  // ZoomableGraphic's `Semantics(button: true, label: 'Zoom graphic')`, so on
  // every tool screen that renders a concept graphic (98 call sites in lib/ —
  // `grep -rn "ConceptGraphicBand(" lib/ | grep -v concept_graphic_band.dart |
  // wc -l`) VoiceOver / TalkBack found NO operable control at all: the band
  // announced nothing and the zoom view was unreachable without vision.
  //
  // These tests read the real SemanticsNode tree, so they fail if the outer
  // ExcludeSemantics ever comes back. Both render branches are covered
  // separately — dark draws `SvgPicture.asset`, light draws `SvgPicture.string`
  // through a second FutureBuilder, and only one of them being right would
  // still leave half the users without a control.
  group('ConceptGraphicBand a11y — semantics tree (regression)', () {
    testWidgets('DARK: announces exactly one operable "Zoom graphic" button',
        (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fspl.svg'});
      ConceptGraphicBand.debugSeedCaches('fspl', aspect: 2.0);
      await _pump(tester, toolId: 'fspl');
      await tester.pump();

      // The control reaches the a11y tree, and it is the ONLY thing announced.
      expect(_spokenLabels(tester), <String>['Zoom graphic']);

      final List<SemanticsNode> tappable =
          _nodesWithAction(tester, SemanticsAction.tap);
      expect(tappable, hasLength(1));
      expect(tappable.single.getSemanticsData().flagsCollection.isButton, isTrue,
          reason: 'the zoom target must announce as a button, not an image');

      // Dispose explicitly, not via addTearDown: a tearDown callback runs
      // AFTER the test binding has already torn the semantics owner down.
      handle.dispose();
    });

    testWidgets('LIGHT: announces exactly one operable "Zoom graphic" button',
        (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fspl.svg'});
      // Seeding both caches keeps the light path in fake-async. The seed is
      // required — dropping `lightSvg` fails this group. With the aspect
      // already seeded, the §8.20.7 string load is the only pending future and
      // nothing drives it under the fake clock, so pumpAndSettle would hang
      // and the branch would need tester.runAsync. That is a property of this
      // cache ordering, not a universal rule about SVG loads in tests.
      ConceptGraphicBand.debugSeedCaches(
        'fspl',
        aspect: 2.0,
        lightSvg: '<svg viewBox="0 0 320 160" fill="none">'
            '<rect width="320" height="160" stroke="#5A7A1C"/></svg>',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ConceptGraphicBand(toolId: 'fspl')),
        ),
      );
      await tester.pump();

      expect(_spokenLabels(tester), <String>['Zoom graphic']);

      final List<SemanticsNode> tappable =
          _nodesWithAction(tester, SemanticsAction.tap);
      expect(tappable, hasLength(1));
      expect(tappable.single.getSemanticsData().flagsCollection.isButton, isTrue,
          reason: 'the zoom target must announce as a button, not an image');

      handle.dispose();
    });

    // THE TRAP THIS GUARDS: un-silencing the band is worse than the original
    // bug if the decorative SVG starts announcing itself. `excludeFromSemantics:
    // true` on every SvgPicture is what prevents it — vector_graphics wraps the
    // render in `Semantics(image: true)` when that flag is false
    // (vector_graphics-1.2.2 lib/src/vector_graphics.dart:559), which is the
    // ONLY place the SVG stack touches semantics. Drop the flag on any branch
    // and an image node appears here.
    testWidgets('the decorative graphic itself stays silent (no image node)',
        (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fspl.svg'});
      ConceptGraphicBand.debugSeedCaches('fspl', aspect: 2.0);
      await _pump(tester, toolId: 'fspl');
      await tester.pump();

      expect(_imageNodes(tester), isEmpty,
          reason: 'the concept graphic is decorative — every fact it depicts is '
              'already in the screen text; announcing it doubles the content');

      handle.dispose();
    });

    testWidgets('LIGHT: the decorative graphic itself stays silent',
        (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fspl.svg'});
      ConceptGraphicBand.debugSeedCaches(
        'fspl',
        aspect: 2.0,
        lightSvg: '<svg viewBox="0 0 320 160" fill="none">'
            '<rect width="320" height="160" stroke="#5A7A1C"/></svg>',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ConceptGraphicBand(toolId: 'fspl')),
        ),
      );
      await tester.pump();

      expect(_imageNodes(tester), isEmpty);

      handle.dispose();
    });

    // The band builds FOUR SvgPictures, not two: an in-page render and a
    // zoom-view render, on each of the dark and light branches. The two above
    // cover the in-page pair; these two drive the control and check the zoom
    // route the fix just made reachable by screen reader. The zoomed graphic
    // must be silent too, and the only announced controls are the ones the user
    // can act on.
    testWidgets('DARK: the zoom view announces a close button, not the graphic',
        (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fspl.svg'});
      ConceptGraphicBand.debugSeedCaches('fspl', aspect: 2.0);
      await _pump(tester, toolId: 'fspl');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Zoom graphic'));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(_spokenLabels(tester), contains('Close zoom'));
      expect(_imageNodes(tester), isEmpty,
          reason: 'the zoomed graphic is the same decorative art — still silent');

      handle.dispose();
    });

    testWidgets('LIGHT: the zoom view announces a close button, not the graphic',
        (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fspl.svg'});
      ConceptGraphicBand.debugSeedCaches(
        'fspl',
        aspect: 2.0,
        lightSvg: '<svg viewBox="0 0 320 160" fill="none">'
            '<rect width="320" height="160" stroke="#5A7A1C"/></svg>',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ConceptGraphicBand(toolId: 'fspl')),
        ),
      );
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Zoom graphic'));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(_spokenLabels(tester), contains('Close zoom'));
      expect(_imageNodes(tester), isEmpty);

      handle.dispose();
    });

    testWidgets('an unbundled graphic still announces nothing at all',
        (tester) async {
      // The graceful-degradation branch must not gain a phantom control now
      // that the outer ExcludeSemantics is gone.
      final SemanticsHandle handle = tester.ensureSemantics();
      ToolAssets.debugSetBundledAssets(<String>{});
      await _pump(tester, toolId: 'fspl');
      await tester.pump();

      expect(_spokenLabels(tester), isEmpty);
      expect(_nodesWithAction(tester, SemanticsAction.tap), isEmpty);

      handle.dispose();
    });
  });

  group('ConceptGraphicBand sizing (aspect-ratio-driven)', () {
    test('parseAspectRatio reads width/height from a viewBox', () {
      expect(
        ConceptGraphicBand.parseAspectRatio(
            '<svg viewBox="0 0 320 160"></svg>'),
        closeTo(2.0, 1e-9),
      );
      expect(
        ConceptGraphicBand.parseAspectRatio(
            '<svg viewBox="0 0 640 560"></svg>'),
        closeTo(640 / 560, 1e-9),
      );
    });

    test('parseAspectRatio falls back to width/height attrs, then 2:1', () {
      expect(
        ConceptGraphicBand.parseAspectRatio('<svg width="900" height="300">'),
        closeTo(3.0, 1e-9),
      );
      // No viewBox and no usable dims → the dominant 2:1 fallback.
      expect(
        ConceptGraphicBand.parseAspectRatio('<svg></svg>'),
        closeTo(2.0, 1e-9),
      );
    });

    test('bandHeightFor fills width for a wide graphic, capped by the ceiling',
        () {
      // A wide 2:1 graphic at 680dp content → 340dp natural, but the phone
      // ceiling (max 320) clamps it down.
      final double h = ConceptGraphicBand.bandHeightFor(
        availableWidth: 680,
        aspectRatio: 2.0,
        viewportHeight: 2000, // tall viewport so the fraction isn't the binder
        isDesktop: false,
      );
      expect(h, 320); // mobile absolute ceiling
    });

    test('bandHeightFor never drops below the 180dp floor', () {
      // A very wide 4:1 graphic on a narrow phone → 343/4 ≈ 86dp natural,
      // floored up to 180 so it still reads.
      final double h = ConceptGraphicBand.bandHeightFor(
        availableWidth: 343,
        aspectRatio: 4.0,
        viewportHeight: 812,
        isDesktop: false,
      );
      expect(h, 180);
    });

    test('bandHeightFor respects the viewport fraction on a short viewport',
        () {
      // Short landscape viewport (height 400) → ceiling = 400 * 0.40 = 160,
      // but the 180 floor wins, so the band stays at least 180 even there.
      final double h = ConceptGraphicBand.bandHeightFor(
        availableWidth: 680,
        aspectRatio: 1.2, // near-square would want ~567dp, gets clamped
        viewportHeight: 400,
        isDesktop: false,
      );
      expect(h, 180);
    });

    test('bandHeightFor lets a tall graphic grow to the desktop ceiling', () {
      // Near-square graphic on a tall desktop window: natural 680/1.2 ≈ 567dp,
      // capped at min(1200*0.40=480, 420) = 420.
      final double h = ConceptGraphicBand.bandHeightFor(
        availableWidth: 680,
        aspectRatio: 1.2,
        viewportHeight: 1200,
        isDesktop: true,
      );
      expect(h, 420);
    });
  });

  group('ConceptGraphicBand light-mode swap (§8.20.7)', () {
    test('recolors scaffold / muted / lime-foreground / status hues', () {
      const String svg =
          '<svg><path stroke="#E5E5E5"/><line stroke="#9C9C9C"/>'
          '<path stroke="#A2CC3A"/><rect stroke="#3A3A3A"/>'
          '<path stroke="#F26E6E"/><path stroke="#E0A23A"/>'
          '<path stroke="#5BD68A"/>'
          '<circle fill="rgba(162,204,58,0.08)"/></svg>';
      final String out = ConceptGraphicBand.debugApplyLightSwap(svg);

      // Dark scaffold/lime/status hexes are gone…
      expect(out.contains('#E5E5E5'), isFalse);
      expect(out.contains('#9C9C9C'), isFalse);
      expect(out.contains('#A2CC3A'), isFalse);
      expect(out.contains('#3A3A3A'), isFalse);
      expect(out.contains('#F26E6E'), isFalse);
      expect(out.contains('#E0A23A'), isFalse);
      expect(out.contains('#5BD68A'), isFalse);
      expect(out.contains('rgba(162,204,58,0.08)'), isFalse);

      // …replaced by the §8.20.1 / §8.20.2 light values.
      expect(out.contains('#4A4A4A'), isTrue); // textSecondary
      expect(out.contains('#646464'), isTrue); // textTertiary
      expect(out.contains('#5A7A1C'), isTrue); // textAccent (lime split)
      expect(out.contains('#E2E1E2'), isTrue); // border (faint hatch)
      expect(out.contains('#C62D2D'), isTrue); // statusDanger
      expect(out.contains('#8A5A00'), isTrue); // statusWarning (bronze)
      expect(out.contains('#1B7340'), isTrue); // statusSuccess (Iris nudge for AA)
      expect(out.contains('rgba(90,122,28,0.10)'), isTrue); // lime wash
    });

    test('PRESERVES §1d canonical T568 / copper data colors and #1A1A1A', () {
      const String svg =
          '<svg><rect fill="#C9A227"/><rect fill="#F58A1F"/>'
          '<rect fill="#3CA03C"/><rect fill="#2D6CDF"/>'
          '<rect fill="#7A4A22"/><circle fill="#1A1A1A"/></svg>';
      final String out = ConceptGraphicBand.debugApplyLightSwap(svg);

      // The color IS the information (T568 pinout, copper) — must survive intact.
      expect(out.contains('#C9A227'), isTrue); // copper/gold
      expect(out.contains('#F58A1F'), isTrue); // T568 orange
      expect(out.contains('#3CA03C'), isTrue); // T568 green
      expect(out.contains('#2D6CDF'), isTrue); // T568 blue
      expect(out.contains('#7A4A22'), isTrue); // T568 brown
      expect(out.contains('#1A1A1A'), isTrue); // anchor dot (no-op)
      // Nothing else changed: input == output for a canonical-only graphic.
      expect(out, equals(svg));
    });

    testWidgets('light theme renders the recolored graphic (no broken box)',
        (tester) async {
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fspl.svg'});
      // Seed the aspect + swapped-light source caches synchronously so the
      // light render path resolves without real bundle I/O (keeps the test in
      // fake-async; no runAsync, no real-timer timeout). The swapped source is
      // a minimal valid SVG carrying a light-target hex — proving the string
      // path renders an SvgPicture rather than a broken box.
      ConceptGraphicBand.debugSeedCaches(
        'fspl',
        aspect: 2.0,
        lightSvg: '<svg viewBox="0 0 320 160" fill="none">'
            '<rect width="320" height="160" stroke="#5A7A1C"/></svg>',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: ConceptGraphicBand(toolId: 'fspl'),
          ),
        ),
      );
      // One pump delivers the (already-resolved) Future.value to the inner
      // FutureBuilder, painting the SvgPicture.string.
      await tester.pump();

      // The light path draws via SvgPicture.string once the future resolves.
      expect(find.byType(SvgPicture), findsOneWidget);
    });
  });

  group('ToolAssets convention paths', () {
    test('icon and graphic paths derive from the tool id verbatim', () {
      expect(ToolAssets.iconPath('dbm-watt-converter'),
          'assets/tool-icons/dbm-watt-converter.svg');
      expect(ToolAssets.graphicPath('dbm-watt-converter'),
          'assets/tool-graphics/dbm-watt-converter.svg');
    });

    test('has* is false until the manifest is loaded (safe default)', () {
      ToolAssets.debugReset();
      expect(ToolAssets.hasGraphic('fspl'), isFalse);
      expect(ToolAssets.hasIcon('link-budget'), isFalse);
    });

    test('has* reflects the bundled set once loaded', () {
      ToolAssets.debugSetBundledAssets({
        'assets/tool-graphics/fspl.svg',
        'assets/tool-icons/link-budget.svg',
      });
      expect(ToolAssets.hasGraphic('fspl'), isTrue);
      expect(ToolAssets.hasGraphic('link-budget'), isFalse);
      expect(ToolAssets.hasIcon('link-budget'), isTrue);
      expect(ToolAssets.hasIcon('fspl'), isFalse);
    });
  });
}
