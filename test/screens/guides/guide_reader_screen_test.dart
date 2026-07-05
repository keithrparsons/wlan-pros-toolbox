// GuideReaderScreen widget tests (help-embed, 2026-06-07).
//
// Covers the in-app markdown reader that renders the two bundled guides:
//   * content renders (headings + body prose reflow into the reader);
//   * the AppBar "Contents" action opens the table-of-contents sheet, the TOC
//     lists the document's section headings (jump-to-section nav), and tapping a
//     heading dismisses the sheet;
//   * the §8.16 "Copy guide text" affordance is present once loaded.
//
// Markdown is injected via [GuideReaderScreen.markdownOverride] so the tests do
// not depend on the asset bundle. A tall viewport is used so the document's
// ListView lays out enough rows for the assertions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:wlan_pros_toolbox/data/app_version.dart';
import 'package:wlan_pros_toolbox/screens/guides/guide_reader_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A compact, structured markdown fixture standing in for a bundled guide:
/// a single H1 part, two H2 sections, and an H3 subsection — enough to prove
/// heading rendering, body reflow, and a multi-level table of contents.
const String _fixture = '''
# A Guide for Everyone

This is the opening paragraph of the guide. It reflows as themed prose.

## Start here

Tap Check My Connection to get the everyday answer.

### One note for iPhone owners

A short subsection under Start here.

## A tour of the app

A second top-level section with its own body copy.
''';

/// A fixture carrying an asset-image figure, to prove the reader renders a
/// bundled `![alt](assets/...)` figure (the "Wi-Fi vs Cellular vs Internet"
/// chapter's signal-meters diagram) rather than dropping or overflowing it.
const String _fixtureWithFigure = '''
# A Guide for Everyone

Some intro copy above the figure.

![Signal meters diagram](assets/guides/signal-meters.png)

Some copy below the figure.
''';

Future<void> _pump(
  WidgetTester tester, {
  String title = 'A Guide for Everyone',
  ThemeData? theme,
  String markdown = _fixture,
  String? initialHeadingAnchor,
}) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: GuideReaderScreen(
        assetPath: kUserGuideAsset,
        title: title,
        markdownOverride: markdown,
        initialHeadingAnchor: initialHeadingAnchor,
      ),
    ),
  );
  // markdown_widget renders each block inside a VisibilityDetector, whose
  // periodic update timer means the tree never fully "settles" — pumpAndSettle
  // would time out. Pump a fixed window instead so the document lays out.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// A fixture carrying the runtime app-version placeholder in a metadata line,
/// mirroring the real guides' header (`_A 5-minute tour of the app · app
/// v{{app_version}}_`). Proves the reader FILLS the placeholder with the actual
/// version instead of printing the raw token or a baked-in literal that drifts.
const String _fixtureWithVersion = '''
# A Guide for Everyone

app v{{app_version}} — the tour of the app.
''';

void main() {
  // Pure substitution: the version fill is a plain string replace, unit-tested
  // in isolation so both the production load path and the widget-test override
  // path share one verified transform.
  test('applyGuidePlaceholders fills {{app_version}} with the given version',
      () {
    expect(
      applyGuidePlaceholders('app v{{app_version}} shipped', '1.7.0'),
      'app v1.7.0 shipped',
    );
    // No placeholder → returned unchanged.
    expect(applyGuidePlaceholders('no token here', '1.7.0'), 'no token here');
    // Every occurrence is filled, not just the first.
    expect(
      applyGuidePlaceholders('{{app_version}}/{{app_version}}', '9.9.9'),
      '9.9.9/9.9.9',
    );
  });

  setUp(() {
    // markdown_widget wraps each block in a VisibilityDetector whose periodic
    // update timer otherwise leaves a pending timer at test teardown. Zeroing
    // the interval makes updates fire synchronously so the test tree settles.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('renders the guide title and body content', (tester) async {
    await _pump(tester);

    // AppBar title.
    expect(find.text('A Guide for Everyone'), findsWidgets);
    // Body prose reflowed by the markdown reader.
    expect(
      find.textContaining('opening paragraph of the guide'),
      findsOneWidget,
    );
    // Section headings render in the document.
    expect(find.text('Start here'), findsWidgets);
    expect(find.text('A tour of the app'), findsWidgets);
  });

  testWidgets('Contents action opens a TOC with the section headings',
      (tester) async {
    await _pump(tester);

    // Open the Contents sheet from the AppBar action.
    await tester.tap(find.byTooltip('Contents'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The TOC sheet header renders.
    expect(find.text('Contents'), findsOneWidget);
    // The document's headings appear as navigable rows inside the TocWidget.
    final Finder toc = find.byType(TocWidget);
    expect(toc, findsOneWidget);
    expect(
      find.descendant(of: toc, matching: find.text('Start here')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: toc, matching: find.text('One note for iPhone owners')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: toc, matching: find.text('A tour of the app')),
      findsOneWidget,
    );
  });

  testWidgets('tapping a TOC heading dismisses the Contents sheet',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('Contents'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Contents'), findsOneWidget);

    // Tap a heading inside the sheet (scoped to the TocWidget) → jump-to-section
    // + close the sheet.
    await tester.tap(
      find.descendant(
        of: find.byType(TocWidget),
        matching: find.text('A tour of the app'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The sheet (and its "Contents" header) is gone.
    expect(find.text('Contents'), findsNothing);
  });

  testWidgets('renders the Copy guide text affordance once loaded',
      (tester) async {
    await _pump(tester);
    expect(find.byTooltip('Copy guide text'), findsOneWidget);
  });

  testWidgets('fills the {{app_version}} placeholder with the runtime version',
      (tester) async {
    await _pump(tester, markdown: _fixtureWithVersion);

    // The reader renders the ACTUAL version (the const fallback stands in for
    // the runtime PackageInfo read in tests), never the raw placeholder token.
    expect(
      find.textContaining('app v${AppVersion.fallback.version}'),
      findsOneWidget,
    );
    expect(find.textContaining('{{app_version}}'), findsNothing);
  });

  testWidgets('renders under the light theme too', (tester) async {
    await _pump(tester, theme: AppTheme.light());
    expect(
      find.textContaining('opening paragraph of the guide'),
      findsOneWidget,
    );
    expect(find.text('Start here'), findsWidgets);
  });

  testWidgets('renders a bundled asset figure with its alt-text label',
      (tester) async {
    await _pump(tester, markdown: _fixtureWithFigure);

    // The themed figure builder produces an Image (the asset need not decode in
    // the test bundle — the widget is built either way).
    expect(find.byType(Image), findsOneWidget);
    // Alt text becomes the accessible image label (SC 1.1.1) so a screen reader
    // announces the figure.
    expect(find.bySemanticsLabel('Signal meters diagram'), findsOneWidget);
    // Prose on both sides of the figure still reflows.
    expect(find.textContaining('above the figure'), findsOneWidget);
    expect(find.textContaining('below the figure'), findsOneWidget);
  });

  testWidgets('an initialHeadingAnchor deep-link renders without error',
      (tester) async {
    // Passing an anchor that matches a heading exercises the tocList lookup +
    // jumpToIndex path; the document must still render (the jump is a scroll,
    // not a filter).
    await _pump(tester, initialHeadingAnchor: 'A tour of the app');
    expect(find.text('A tour of the app'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unmatched initialHeadingAnchor is a safe no-op',
      (tester) async {
    await _pump(tester, initialHeadingAnchor: 'No Such Heading');
    // Falls back to the top of the guide, rendered normally, no throw.
    expect(
      find.textContaining('opening paragraph of the guide'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
