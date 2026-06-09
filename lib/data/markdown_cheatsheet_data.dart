// Markdown Cheatsheet data — the typed const rows for the read-only reference.
//
// SCOPE / HONESTY (GL-005): standard, stable syntax — CommonMark plus GitHub
// Flavored Markdown (GFM). CommonMark is the de-facto core spec; GFM is the most
// widely-implemented superset (GitHub, GitLab, many static-site generators).
// Rows whose syntax is a GFM extension (strikethrough, task lists, tables,
// autolinks) carry `gfm: true` so the page flags them — a renderer that
// implements only plain CommonMark will not render those. Nothing here is
// presented as universal beyond the CommonMark core unless it is core.
//
// Each row is the (Element | You type | Renders as) triple the page renders as a
// table. `youType` holds the LITERAL markdown the user would write (e.g.
// `**bold**`), stored as a raw/escaped Dart string so the asterisks/backticks
// survive as text and are NEVER interpreted as formatting. `rendersAs` describes
// (in words, or with the rendered text) what the markup produces — the page does
// not run a markdown renderer, so the "renders as" column is a faithful textual
// description, not a live render (the concept graphic at the top shows the live
// idea).
//
// Glyph hygiene (GL-004): ASCII only, no em dash, US spelling, "Wi-Fi" if it
// ever appears. The backslash escapes in `youType` are literal markdown syntax,
// not Dart escapes — raw strings (r'...') keep them literal.

import 'package:flutter/foundation.dart';

/// One cheatsheet row: the element name, the literal markdown to type, a textual
/// description of what it renders as, and whether the syntax is a GFM extension
/// (vs CommonMark core).
@immutable
class MarkdownRow {
  const MarkdownRow({
    required this.element,
    required this.youType,
    required this.rendersAs,
    this.gfm = false,
  });

  /// The element name, e.g. `Bold`, `Heading 1`, `Task list`.
  final String element;

  /// The LITERAL markdown a user types, e.g. `**bold**`. Stored so the literal
  /// asterisks/backticks render as text, never as formatting.
  final String youType;

  /// A faithful textual description of the rendered result, e.g.
  /// `bold text` or `<h1> top-level heading`.
  final String rendersAs;

  /// True when the syntax is a GitHub Flavored Markdown extension rather than
  /// CommonMark core. Drives the per-row "GFM" badge so divergence is visible.
  final bool gfm;
}

/// A titled group of rows, with an optional footnote.
@immutable
class MarkdownSection {
  const MarkdownSection(this.title, this.rows, {this.footnote});

  final String title;
  final List<MarkdownRow> rows;
  final String? footnote;
}

/// The canonical CommonMark + GFM cheatsheet data, grouped in display order.
class MarkdownCheatsheetData {
  MarkdownCheatsheetData._();

  /// Scope banner label + note, pinned above the tables (mirrors the regex
  /// page's dialect banner). States the CommonMark + GFM scope so a reader knows
  /// flagged rows may not work in a plain-CommonMark renderer.
  static const String scopeLabel = 'Flavor: CommonMark + GitHub Flavored Markdown';
  static const String scopeNote =
      'CommonMark is the core spec; rows marked GFM are GitHub Flavored Markdown '
      'extensions (strikethrough, task lists, tables, autolinks). A plain '
      'CommonMark renderer will not render the GFM rows. Markdown has no single '
      'universal authority; this page is scoped to the CommonMark core plus the '
      'widely-implemented GFM superset.';

  static const String intro =
      'Type the left column literally; the right column is what it renders as. '
      'Rows flagged GFM are GitHub Flavored Markdown extensions on top of the '
      'CommonMark core.';

  /// Text-emphasis and inline elements.
  static const MarkdownSection textAndEmphasis = MarkdownSection(
    'Text and emphasis',
    <MarkdownRow>[
      MarkdownRow(
        element: 'Heading 1 to 6',
        youType: '# H1   ## H2   ### H3 ... ###### H6',
        rendersAs: 'Headings, largest (H1) to smallest (H6). One space after the #.',
      ),
      MarkdownRow(
        element: 'Bold',
        youType: '**bold**',
        rendersAs: 'bold text (also __bold__)',
      ),
      MarkdownRow(
        element: 'Italic',
        youType: '*italic*',
        rendersAs: 'italic text (also _italic_)',
      ),
      MarkdownRow(
        element: 'Bold + italic',
        youType: '***bold italic***',
        rendersAs: 'bold and italic together',
      ),
      MarkdownRow(
        element: 'Strikethrough',
        youType: '~~struck~~',
        rendersAs: 'struck-through text',
        gfm: true,
      ),
      MarkdownRow(
        element: 'Inline code',
        youType: '`code`',
        rendersAs: 'monospaced code, special chars taken literally',
      ),
    ],
  );

  /// Links and images.
  static const MarkdownSection linksAndImages = MarkdownSection(
    'Links and images',
    <MarkdownRow>[
      MarkdownRow(
        element: 'Link',
        youType: '[text](https://example.com)',
        rendersAs: 'a clickable link reading "text"',
      ),
      MarkdownRow(
        element: 'Link with title',
        youType: '[text](https://example.com "hover title")',
        rendersAs: 'a link whose tooltip shows on hover',
      ),
      MarkdownRow(
        element: 'Image',
        youType: '![alt text](https://example.com/x.png)',
        rendersAs: 'an embedded image; alt text shows if it fails to load',
      ),
      MarkdownRow(
        element: 'Autolink',
        youType: '<https://example.com>',
        rendersAs: 'the bare URL rendered as a clickable link',
        gfm: true,
      ),
    ],
    footnote: 'An image is a link with a leading ! and the same bracket/paren '
        'shape.',
  );

  /// Lists, including nesting and task lists.
  static const MarkdownSection lists = MarkdownSection(
    'Lists',
    <MarkdownRow>[
      MarkdownRow(
        element: 'Unordered',
        youType: '- item   (or * item, or + item)',
        rendersAs: 'a bulleted list',
      ),
      MarkdownRow(
        element: 'Ordered',
        youType: '1. first   2. second',
        rendersAs: 'a numbered list (the renderer renumbers from the first value)',
      ),
      MarkdownRow(
        element: 'Nested',
        youType: '- parent\n  - child   (indent 2 spaces)',
        rendersAs: 'a child list nested under its parent item',
      ),
      MarkdownRow(
        element: 'Task list (unchecked)',
        youType: '- [ ] to do',
        rendersAs: 'an unchecked checkbox item',
        gfm: true,
      ),
      MarkdownRow(
        element: 'Task list (checked)',
        youType: '- [x] done',
        rendersAs: 'a checked checkbox item',
        gfm: true,
      ),
    ],
  );

  /// Block-level elements: quotes, rules, breaks, code blocks.
  static const MarkdownSection blocks = MarkdownSection(
    'Blocks',
    <MarkdownRow>[
      MarkdownRow(
        element: 'Blockquote',
        youType: '> quoted line',
        rendersAs: 'an indented quote block; nest with >>',
      ),
      MarkdownRow(
        element: 'Horizontal rule',
        youType: '---   (or *** or ___ on their own line)',
        rendersAs: 'a full-width divider line',
      ),
      MarkdownRow(
        element: 'Line break',
        youType: 'line one(two trailing spaces)\\nline two',
        rendersAs: 'a soft break within one paragraph (end the line with 2 spaces)',
      ),
      MarkdownRow(
        element: 'Paragraph break',
        youType: 'para one\\n\\npara two   (blank line between)',
        rendersAs: 'two separate paragraphs',
      ),
      MarkdownRow(
        element: 'Fenced code block',
        youType: '```dart\\nvoid main() {}\\n```',
        rendersAs: 'a syntax-highlighted code block (language after the fence)',
      ),
      MarkdownRow(
        element: 'Indented code block',
        youType: '    void main() {}   (4 leading spaces)',
        rendersAs: 'a code block with no language hint',
      ),
    ],
    footnote: 'Fenced blocks are clearer than indented ones and carry a language '
        'tag for highlighting. Use three backticks, or three tildes (~~~).',
  );

  /// GFM tables, with alignment.
  static const MarkdownSection tables = MarkdownSection(
    'Tables',
    <MarkdownRow>[
      MarkdownRow(
        element: 'Table',
        youType: '| A | B |\\n| - | - |\\n| 1 | 2 |',
        rendersAs: 'a two-column table with a header row and a separator row',
        gfm: true,
      ),
      MarkdownRow(
        element: 'Left align',
        youType: '| :--- |',
        rendersAs: 'column text aligned left (colon on the left)',
        gfm: true,
      ),
      MarkdownRow(
        element: 'Center align',
        youType: '| :---: |',
        rendersAs: 'column text centered (colons both sides)',
        gfm: true,
      ),
      MarkdownRow(
        element: 'Right align',
        youType: '| ---: |',
        rendersAs: 'column text aligned right (colon on the right)',
        gfm: true,
      ),
    ],
    footnote: 'The separator row sets alignment; the colon positions decide left, '
        'center, or right. Outer pipes are optional but read more clearly.',
  );

  /// Gotchas — the small "watch out for" notes the brief asks for.
  static const List<String> gotchas = <String>[
    'Block elements need a blank line between them. A heading, list, or code '
        'block jammed against the previous paragraph often will not render.',
    r'Escape a special character with a backslash: \* renders a literal '
        'asterisk, not italic. Same for backtick, underscore, hash, and the '
        'other markup characters.',
    'A line break inside a paragraph needs two trailing spaces (or a backslash '
        'at end of line in some renderers). A single newline is usually folded '
        'into the same line.',
    'GFM extensions (tables, task lists, strikethrough, autolinks) are not in '
        'plain CommonMark. If a renderer ignores them, it is CommonMark-only.',
  ];

  /// All sections in display order.
  static const List<MarkdownSection> sections = <MarkdownSection>[
    textAndEmphasis,
    linksAndImages,
    lists,
    blocks,
    tables,
  ];
}
