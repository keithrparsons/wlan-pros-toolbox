// Unit tests for groupedCategoryTools — the grouped category sections (Ticket 2).
//
// Invariants mirrored from the existing category-order test: sections appear in
// kCategorySubgroupOrder; counts equal the tools in each; every tool appears
// exactly once (no drops/dupes); every subgroup is a known header (no orphan
// "Other"); flat categories return a single unnamed section.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';

void main() {
  ToolCategory cat(String id) =>
      kToolCategories.firstWhere((ToolCategory c) => c.id == id);

  group('groupedCategoryTools — grouped categories', () {
    for (final String id in kCategorySubgroupOrder.keys) {
      test('$id: sections appear in kCategorySubgroupOrder', () {
        final List<ToolSection> sections = groupedCategoryTools(cat(id));
        final List<String> headers =
            sections.map((ToolSection s) => s.header).toList();
        // Headers present must be a subsequence of the editorial order (empty
        // sections are dropped), and there must be no trailing "Other".
        expect(headers.contains('Other'), isFalse,
            reason: '$id orphaned a tool into "Other"');
        final List<String> order = kCategorySubgroupOrder[id]!;
        int lastIdx = -1;
        for (final String h in headers) {
          final int idx = order.indexOf(h);
          expect(idx, greaterThan(lastIdx),
              reason: '$id section "$h" out of editorial order');
          lastIdx = idx;
        }
      });

      test('$id: each section count equals its tools length', () {
        for (final ToolSection s in groupedCategoryTools(cat(id))) {
          expect(s.count, s.tools.length);
        }
      });

      test('$id: every tool appears exactly once across sections', () {
        final List<ToolSection> sections = groupedCategoryTools(cat(id));
        final List<String> placedIds = <String>[
          for (final ToolSection s in sections)
            for (final ToolEntry t in s.tools) t.id,
        ];
        final List<String> catIds =
            cat(id).tools.map((ToolEntry t) => t.id).toList();
        expect(placedIds.toSet().length, placedIds.length,
            reason: '$id placed a tool in two sections');
        expect(placedIds.toSet(), catIds.toSet(),
            reason: '$id dropped or added a tool');
      });

      test('$id: every tool has a subgroup that is a known header', () {
        final Set<String> known = kCategorySubgroupOrder[id]!.toSet();
        for (final ToolEntry t in cat(id).tools) {
          expect(t.subgroup, isNotNull,
              reason: '$id tool "${t.id}" has no subgroup');
          expect(known.contains(t.subgroup), isTrue,
              reason: '$id tool "${t.id}" subgroup "${t.subgroup}" is unknown');
        }
      });

      test('$id: each section is alphabetized by title', () {
        for (final ToolSection s in groupedCategoryTools(cat(id))) {
          final List<String> titles =
              s.tools.map((ToolEntry t) => t.title.toLowerCase()).toList();
          final List<String> sorted = <String>[...titles]..sort();
          expect(titles, sorted, reason: '$id section "${s.header}" not A-Z');
        }
      });
    }
  });

  group('groupedCategoryTools — flat categories', () {
    test('test-network returns a single unnamed section in pinned order', () {
      final List<ToolSection> sections = groupedCategoryTools(cat('test-network'));
      expect(sections, hasLength(1));
      expect(sections.single.header, isEmpty);
      // The flat path preserves the pin order. Wave 4 (2026-06-04): the merged
      // connection tile was removed from the catalog, so Network Quality leads.
      expect(sections.single.tools.first.id, 'net-quality');
    });

    test('networking returns a single unnamed section', () {
      final List<ToolSection> sections = groupedCategoryTools(cat('networking'));
      expect(sections, hasLength(1));
      expect(sections.single.header, isEmpty);
      expect(sections.single.count, cat('networking').tools.length);
    });
  });
}
