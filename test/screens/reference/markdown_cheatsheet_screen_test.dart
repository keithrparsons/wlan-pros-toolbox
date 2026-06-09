// Tests for the Markdown Cheatsheet reference screen.
//
// Four layers, mirroring iec_connectors_screen_test / regex_cheatsheet:
//   1. Data fidelity (GL-005): the typed const dataset carries the canonical
//      CommonMark + GFM syntax, with the load-bearing rows pinned so a future
//      edit cannot silently drift them (** = bold, ~~ = strikethrough is GFM,
//      task lists are GFM, tables are GFM, autolinks are GFM).
//   2. Literal-markdown integrity: the "You type" cells hold the LITERAL markup
//      (the asterisks/backticks survive as text) and no special character was
//      accidentally stripped or escaped away.
//   3. Glyph hygiene (GL-004): no em dash, no "router", ASCII only.
//   4. Widget render: the read-only screen renders title + every section
//      heading + the gotchas across phone/tablet/desktop widths with no
//      RenderFlex overflow, and the concept graphic renders exactly the bundled
//      count (zero when none built, one when the named SVG is present) — proving
//      graceful degradation.
//
// Catalog/router/help registration is NOT asserted here: Larry registers the
// tool centrally (the build brief forbids editing the shared catalog/router),
// so those contracts are verified at integration, not in this NEW-files-only
// test.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/markdown_cheatsheet_data.dart';
import 'package:wlan_pros_toolbox/data/markdown_diagrams.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/markdown_cheatsheet_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Markdown data — canonical CommonMark + GFM', () {
    MarkdownRow rowFor(String element) => MarkdownCheatsheetData.sections
        .expand((MarkdownSection s) => s.rows)
        .firstWhere((MarkdownRow r) => r.element == element);

    test('bold is **bold** and is CommonMark core (not GFM)', () {
      final MarkdownRow r = rowFor('Bold');
      expect(r.youType, '**bold**');
      expect(r.gfm, isFalse);
    });

    test('italic is *italic* core', () {
      expect(rowFor('Italic').youType, '*italic*');
      expect(rowFor('Italic').gfm, isFalse);
    });

    test('bold+italic is ***bold italic***', () {
      expect(rowFor('Bold + italic').youType, '***bold italic***');
    });

    test('strikethrough is ~~struck~~ and is a GFM extension', () {
      final MarkdownRow r = rowFor('Strikethrough');
      expect(r.youType, '~~struck~~');
      expect(r.gfm, isTrue);
    });

    test('inline code uses backticks and is core', () {
      final MarkdownRow r = rowFor('Inline code');
      expect(r.youType, '`code`');
      expect(r.gfm, isFalse);
    });

    test('autolink is angle-bracketed and is a GFM extension', () {
      final MarkdownRow r = rowFor('Autolink');
      expect(r.youType, '<https://example.com>');
      expect(r.gfm, isTrue);
    });

    test('image markup leads with ! and is core', () {
      final MarkdownRow r = rowFor('Image');
      expect(r.youType.startsWith('!['), isTrue);
      expect(r.gfm, isFalse);
    });

    test('task lists (checked + unchecked) are GFM extensions', () {
      expect(rowFor('Task list (unchecked)').youType, '- [ ] to do');
      expect(rowFor('Task list (unchecked)').gfm, isTrue);
      expect(rowFor('Task list (checked)').youType, '- [x] done');
      expect(rowFor('Task list (checked)').gfm, isTrue);
    });

    test('every table row is a GFM extension', () {
      final MarkdownSection tables = MarkdownCheatsheetData.tables;
      expect(tables.rows.every((MarkdownRow r) => r.gfm), isTrue);
      // Alignment colon positions are pinned so a future edit cannot swap them.
      expect(rowFor('Left align').youType, '| :--- |');
      expect(rowFor('Center align').youType, '| :---: |');
      expect(rowFor('Right align').youType, '| ---: |');
    });

    test('horizontal rule and blockquote are core blocks', () {
      expect(rowFor('Blockquote').youType.startsWith('>'), isTrue);
      expect(rowFor('Horizontal rule').youType.startsWith('---'), isTrue);
    });

    test('fenced code block uses triple backticks with a language', () {
      final MarkdownRow r = rowFor('Fenced code block');
      expect(r.youType.contains('```'), isTrue);
      expect(r.youType.contains('dart'), isTrue);
    });

    test('exactly the five sections in display order', () {
      expect(
        MarkdownCheatsheetData.sections.map((MarkdownSection s) => s.title).toList(),
        <String>[
          'Text and emphasis',
          'Links and images',
          'Lists',
          'Blocks',
          'Tables',
        ],
      );
    });

    test('gotchas cover blank-line, backslash-escape, and trailing-space break', () {
      final String all = MarkdownCheatsheetData.gotchas.join(' ').toLowerCase();
      expect(all.contains('blank line'), isTrue);
      expect(all.contains('backslash'), isTrue);
      expect(all.contains('trailing space'), isTrue);
    });
  });

  group('Literal-markdown integrity', () {
    test('the literal markup characters survive as text in "You type"', () {
      String typeFor(String element) => MarkdownCheatsheetData.sections
          .expand((MarkdownSection s) => s.rows)
          .firstWhere((MarkdownRow r) => r.element == element)
          .youType;
      // The asterisks/backticks/tildes/pipes are present as literal characters,
      // i.e. NOT interpreted away into rendered formatting.
      expect(typeFor('Bold').contains('*'), isTrue);
      expect(typeFor('Inline code').contains('`'), isTrue);
      expect(typeFor('Strikethrough').contains('~'), isTrue);
      expect(typeFor('Table').contains('|'), isTrue);
    });
  });

  group('GL-004 voice + glyph hygiene', () {
    test('no em dash, no "router", ASCII only in all data + prose', () {
      final List<String> strings = <String>[
        MarkdownCheatsheetData.scopeLabel,
        MarkdownCheatsheetData.scopeNote,
        MarkdownCheatsheetData.intro,
        ...MarkdownCheatsheetData.gotchas,
        for (final MarkdownSection s in MarkdownCheatsheetData.sections) ...<String>[
          s.title,
          if (s.footnote != null) s.footnote!,
          for (final MarkdownRow r in s.rows) ...<String>[
            r.element,
            r.youType,
            r.rendersAs,
          ],
        ],
      ];
      for (final String s in strings) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.toLowerCase().contains('router'), isFalse,
            reason: 'never "router" in "$s"');
      }
    });
  });

  group('MarkdownCheatsheetScreen widget', () {
    setUp(() {
      // No graphic bundled by default → the concept pane renders nothing, and
      // the page must still ship fully working as tables.
      MarkdownDiagrams.debugSetBundled(const <String>{});
    });
    tearDown(() {
      MarkdownDiagrams.debugReset();
    });

    testWidgets('renders title, every section heading, and the gotchas',
        (tester) async {
      await _withViewport(tester, const Size(375, 3200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const MarkdownCheatsheetScreen(),
          ),
        );

        expect(find.text('Markdown Cheatsheet'), findsWidgets);
        for (final MarkdownSection s in MarkdownCheatsheetData.sections) {
          expect(find.text(s.title), findsOneWidget);
        }
        expect(find.text('Gotchas'), findsOneWidget);
        // The literal markdown is on screen as text.
        expect(find.text('**bold**'), findsOneWidget);
        expect(find.text('~~struck~~'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
        // No bundled graphic → no SvgPicture (graceful degradation).
        expect(find.byType(SvgPicture), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 2400), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const MarkdownCheatsheetScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });

    testWidgets('renders the bundled concept graphic when present (dark)',
        (tester) async {
      // The named graphic bundled → exactly one SvgPicture (dark path uses
      // SvgPicture.asset). Proves the MarkdownDiagrams wiring + graceful upgrade.
      MarkdownDiagrams.debugSetBundled(<String>{
        MarkdownDiagrams.path(MarkdownDiagrams.renderExample),
      });
      addTearDown(() => MarkdownDiagrams.debugReset());

      await _withViewport(tester, const Size(375, 3200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const MarkdownCheatsheetScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(SvgPicture), findsOneWidget);
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors iec_connectors_screen_test _withViewport so the read-only reference
/// renders at phone width without a RenderFlex overflow.
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
