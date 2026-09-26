// The field manual says it documents every tool, "grouped and ordered the same
// way they appear in the app". Until 2026-09-26 that was prose nobody checked:
// the header count had a guard (field_manual_count_guard_test.dart), the body
// did not. The header could read the right number while 33 tools had no entry,
// the Quick Reference sections were three reorganisations out of date, and 13
// lessons and handouts sat under a section they had left.
//
// This guard makes the body claim mechanical:
//   1. every live catalog tool's help name is a `### ` heading exactly once;
//   2. it sits under its app category (`# `) and, for grouped categories, its
//      app shelf (`## `);
//   3. every other `### ` heading is a named supplementary entry (a feature
//      inside a tool, or the Test My Connection front door), so a stray or
//      renamed entry cannot hide;
//   4. every stated count (category, shelf, and the Contents list) equals the
//      entries actually under it.
//
// Keith, 2026-09-15: the Field Guide and the help files must always match the
// shipping software. Keith, 2026-09-26: add all the help sections to the Field
// Manual so it is also up to date.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';

/// Entries in the manual that are not catalog tools. Each one documents a
/// feature inside a tool or the home-screen front door, and sits next to the
/// tool it belongs to. Adding a heading here is a deliberate act; a heading
/// that is neither a tool nor listed here fails the guard.
const Set<String> kManualSupplementaryHeadings = <String>{
  'Test My Connection',
  'Analyze Results',
  'How the Toolbox Measures Throughput',
  'Blue Box (MF)',
  'Red Box (US coin tones)',
  'Fiber Connectors & Polish (a section within the Fiber Optic tool)',
};

class _Heading {
  _Heading(this.name, this.category, this.shelf);
  final String name;
  final String? category;
  final String? shelf;
}

final RegExp _catRe = RegExp(r'^# (.+) \((\d+) tools?\)$');
final RegExp _shelfRe = RegExp(r'^## (.+) \((\d+)\)$');
final RegExp _tocCatRe = RegExp(r'^- \*\*(.+)\*\* \((\d+) tools?\)$');
final RegExp _tocShelfRe = RegExp(r'^  - (.+) \((\d+)\)$');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> lines;
  late ToolHelpStore help;
  late List<ToolEntry> live;
  late Map<String, String> shelfOf; // tool id -> shelf header ('' if flat)
  late Map<String, String> categoryOf; // tool id -> category title

  setUpAll(() async {
    lines = (await rootBundle.loadString(
      'assets/guides/field-manual.md',
    )).split('\n');
    help = ToolHelpStore.fromJson(
      await rootBundle.loadString('assets/help/tool_help.json'),
    );
    live = <ToolEntry>[];
    shelfOf = <String, String>{};
    categoryOf = <String, String>{};
    for (final ToolCategory c in kToolCategories) {
      for (final ToolSection s in groupedCategoryTools(c)) {
        for (final ToolEntry t in s.tools.where((ToolEntry t) => t.isLive)) {
          live.add(t);
          shelfOf[t.id] = s.header;
          categoryOf[t.id] = c.title;
        }
      }
    }
  });

  /// Every `### ` heading with the `# ` category and `## ` shelf above it.
  List<_Heading> headings() {
    final List<_Heading> out = <_Heading>[];
    String? cat;
    String? shelf;
    for (final String l in lines) {
      final RegExpMatch? c = _catRe.firstMatch(l);
      if (c != null) {
        cat = c.group(1);
        shelf = null;
        continue;
      }
      final RegExpMatch? s = _shelfRe.firstMatch(l);
      if (s != null) {
        shelf = s.group(1);
        continue;
      }
      if (l.startsWith('### ')) out.add(_Heading(l.substring(4), cat, shelf));
    }
    return out;
  }

  test('every live catalog tool has exactly one entry, under its app '
      'category and shelf', () {
    final List<_Heading> hs = headings();
    final List<String> problems = <String>[];
    for (final ToolEntry t in live) {
      final ToolHelp? h = help.forId(t.id);
      if (h == null) {
        problems.add('${t.id}: no help entry to draw the manual entry from');
        continue;
      }
      final List<_Heading> found = hs
          .where((_Heading x) => x.name == h.name)
          .toList();
      if (found.length != 1) {
        problems.add('"${h.name}" (${t.id}) appears ${found.length} times');
        continue;
      }
      final _Heading at = found.single;
      if (at.category != categoryOf[t.id]) {
        problems.add(
          '"${h.name}" is under "${at.category}", the app has it in '
          '"${categoryOf[t.id]}"',
        );
      }
      final String shelf = shelfOf[t.id]!;
      if (shelf.isNotEmpty && at.shelf != shelf) {
        problems.add(
          '"${h.name}" is under shelf "${at.shelf}", the app has it on '
          '"$shelf"',
        );
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('every other entry is a named supplementary entry', () {
    final Set<String> toolNames = <String>{
      for (final ToolEntry t in live)
        if (help.forId(t.id) != null) help.forId(t.id)!.name,
    };
    final List<String> strays = headings()
        .map((_Heading h) => h.name)
        .where(
          (String n) =>
              !toolNames.contains(n) &&
              !kManualSupplementaryHeadings.contains(n),
        )
        .toList();
    expect(
      strays,
      isEmpty,
      reason:
          'these `### ` headings match no live tool help name and are not '
          'listed supplementary entries. A renamed tool leaves exactly this '
          'behind: $strays',
    );
  });

  test('every stated count matches the entries under it, and the Contents '
      'list matches the body', () {
    final Set<String> toolNames = <String>{
      for (final ToolEntry t in live)
        if (help.forId(t.id) != null) help.forId(t.id)!.name,
    };
    final Map<String, int> statedCat = <String, int>{};
    final Map<String, int> statedShelf = <String, int>{};
    final Map<String, int> actualCat = <String, int>{};
    final Map<String, int> actualShelf = <String, int>{};
    final Map<String, int> tocCat = <String, int>{};
    final Map<String, int> tocShelf = <String, int>{};

    String? cat;
    String? shelfKey;
    String? tocCurrent;
    bool inBody = false;
    for (final String l in lines) {
      if (!inBody) {
        final RegExpMatch? tc = _tocCatRe.firstMatch(l);
        if (tc != null) {
          tocCurrent = tc.group(1);
          tocCat[tocCurrent!] = int.parse(tc.group(2)!);
          continue;
        }
        final RegExpMatch? ts = _tocShelfRe.firstMatch(l);
        if (ts != null && tocCurrent != null) {
          tocShelf['$tocCurrent / ${ts.group(1)}'] = int.parse(ts.group(2)!);
          continue;
        }
      }
      final RegExpMatch? c = _catRe.firstMatch(l);
      if (c != null) {
        inBody = true;
        cat = c.group(1);
        shelfKey = null;
        statedCat[cat!] = int.parse(c.group(2)!);
        actualCat[cat] = 0;
        continue;
      }
      final RegExpMatch? s = _shelfRe.firstMatch(l);
      if (s != null && cat != null) {
        shelfKey = '$cat / ${s.group(1)}';
        statedShelf[shelfKey] = int.parse(s.group(2)!);
        actualShelf[shelfKey] = 0;
        continue;
      }
      if (l.startsWith('### ') && toolNames.contains(l.substring(4))) {
        if (cat != null) actualCat[cat] = actualCat[cat]! + 1;
        if (shelfKey != null) actualShelf[shelfKey] = actualShelf[shelfKey]! + 1;
      }
    }

    expect(statedCat, isNotEmpty);
    expect(statedCat, actualCat, reason: 'category counts vs entries');
    expect(statedShelf, actualShelf, reason: 'shelf counts vs entries');
    expect(tocCat, actualCat, reason: 'Contents category counts vs body');
    expect(tocShelf, actualShelf, reason: 'Contents shelf counts vs body');

    // The categories are the app's, in the app's order.
    expect(
      statedCat.keys.toList(),
      kToolCategories
          .where((ToolCategory c) => c.tools.any((ToolEntry t) => t.isLive))
          .map((ToolCategory c) => c.title)
          .toList(),
    );
  });
}
