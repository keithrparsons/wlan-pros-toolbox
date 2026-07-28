// Regression test for the LargeGraphic a11y defect Vera reported (shipping in
// 1.8.4): LargeGraphic wrapped its WHOLE subtree in `ExcludeSemantics`, which
// swallowed the `Semantics(button: true, label: 'Zoom …')` node that
// ZoomableGraphic publishes. Result: on every face-card page (IEC / NEMA /
// International connectors, screw drives, rack units, fiber, bend radius,
// batteries, SD cards …) the tap-to-zoom control was invisible to VoiceOver /
// TalkBack. On pages whose graphic renders below the GL-003 minimum text size,
// zoom is the ONLY accessible path to the content.
//
// SCOPE — read this before extending the file. It pins the SCREEN-READER
// contract only. The zoom control is still NOT reachable by physical keyboard
// (WCAG 2.2 SC 2.1.1 is failing; see the KNOWN GAP note in
// zoomable_graphic.dart's ACCESSIBILITY header). Nothing here asserts focus
// traversal, and passing this file must never be read as "zoom is accessible."
//
// The contract this file pins, per that same header:
//   * the ZOOM BUTTON is a real, labeled, operable semantics node;
//   * the PAINTED GRAPHIC stays silent — no SVG internal text runs, no image
//     node, no second label. Getting that backwards is worse than the bug, so
//     the node-level assertion carries an explicit `isImage: false`: without it
//     the whole file survives flipping `excludeFromSemantics` to false on all
//     four SvgPicture sites (Vera, mutation-tested 2026-07-27).
//
// Asserted against the real SEMANTICS TREE (not the widget tree), because
// `ExcludeSemantics` only shows up there — a widget-tree finder would happily
// find a Semantics widget that never reaches a screen reader.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/bend_diagrams.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/large_face_card.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A real bundled face graphic, so the render path is the production one
/// (manifest-gated resolver -> SvgPicture), not a stub.
const String _assetName = BendDiagrams.arcVsKink;

/// The label LargeGraphic derives from the asset name (`-` -> space).
const String _zoomLabel = 'Zoom bend radius arc vs kink';

Widget _host(ThemeData theme) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      body: Center(
        child: LargeGraphic(
          assetName: _assetName,
          path: BendDiagrams.path,
          has: BendDiagrams.has,
        ),
      ),
    ),
  );
}

/// Every non-empty label in the live SEMANTICS tree — what a screen reader
/// actually walks. `find.semantics` searches the semantics tree itself, so
/// anything swallowed by an `ExcludeSemantics` simply is not here.
List<String> _labels() => find.semantics
    .byPredicate((SemanticsNode n) => n.label.isNotEmpty)
    .evaluate()
    .map((SemanticsNode n) => n.label)
    .toList();

/// Runs [body] with the semantics tree materialized, disposing the handle
/// inside the test body — `addTearDown` runs too late for flutter_test's
/// end-of-test handle verification.
Future<void> _withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final SemanticsHandle handle = tester.ensureSemantics();
  try {
    await body();
  } finally {
    handle.dispose();
  }
}

/// The semantics node carrying [label], or `null` when nothing announces it.
SemanticsNode? _nodeLabelled(String label) {
  final Iterable<SemanticsNode> hits =
      find.semantics.byLabel(label).evaluate();
  return hits.isEmpty ? null : hits.single;
}

/// Mounts [host] and lets its real asset I/O land.
///
/// LargeGraphic's LIGHT path awaits `rootBundle.loadString` + the §8.20.7 colour
/// swap before it renders anything at all, and that is genuine file I/O — a
/// plain `pumpAndSettle` runs in fake-async and never lets it complete, so the
/// light branch would sit at `SizedBox.shrink()` forever and the test would pass
/// or fail for the wrong reason. `runAsync` gives the load a real event loop.
Future<void> _pumpAndLoad(WidgetTester tester, Widget host) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(host);
    // Alternate real-time waits with frames so the aspect parse and the
    // light-mode string swap both resolve and get painted.
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pump();
}

void main() {
  group('LargeGraphic a11y — the zoom control must reach the semantics tree',
      () {
    setUp(() {
      BendDiagrams.debugSetBundled(<String>{
        for (final String name in BendDiagrams.all) BendDiagrams.path(name),
      });
    });
    tearDown(BendDiagrams.debugReset);

    for (final ({String mode, ThemeData theme}) variant
        in <({String mode, ThemeData theme})>[
      (mode: 'dark', theme: AppTheme.dark()),
      (mode: 'light', theme: AppTheme.light()),
    ]) {
      testWidgets('${variant.mode}: zoom button is a labeled, operable node',
          (WidgetTester tester) async {
        await _withSemantics(tester, () async {
          await _pumpAndLoad(tester, _host(variant.theme));

          final SemanticsNode? zoom = _nodeLabelled(_zoomLabel);
          expect(
            zoom,
            isNotNull,
            reason:
                'the tap-to-zoom control must be announceable; found labels: '
                '${_labels()}',
          );
          // It must read as an OPERABLE BUTTON and carry a tap action, so
          // screen-reader "activate" opens the full-screen zoom.
          //
          // `isImage: false` is NOT decoration on this matcher — it is the only
          // assertion holding the "graphic stays silent" half of the contract
          // at the NODE level. Vera proved it by mutation (2026-07-27): flip
          // `excludeFromSemantics: true -> false` on all four SvgPicture sites
          // and, without this line, all five tests still pass while the node
          // quietly gains `isImage` and VoiceOver starts announcing
          // "…, image, button". The label-only assertion cannot see that.
          expect(
            zoom,
            isSemantics(
              label: _zoomLabel,
              isButton: true,
              hasTapAction: true,
              isImage: false,
            ),
          );
        });
      });

      testWidgets(
          '${variant.mode}: the painted graphic stays silent (zoom label is the '
          'ONLY label)', (WidgetTester tester) async {
        await _withSemantics(tester, () async {
          await _pumpAndLoad(tester, _host(variant.theme));

          // Exposing the zoom button must NOT also expose the decorative SVG
          // (its internal text runs are duplicated in the page's real Text).
          expect(
            _labels(),
            <String>[_zoomLabel],
            reason: 'the decorative graphic must contribute no semantics',
          );
        });
      });
    }

    testWidgets('graceful degradation: no bundled asset -> no zoom node',
        (WidgetTester tester) async {
      BendDiagrams.debugSetBundled(const <String>{});
      await _withSemantics(tester, () async {
        await _pumpAndLoad(tester, _host(AppTheme.dark()));

        expect(_nodeLabelled(_zoomLabel), isNull,
            reason: 'no graphic means no zoom affordance to announce');
      });
    });
  });
}
