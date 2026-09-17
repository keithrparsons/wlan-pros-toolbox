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
        final List<String> headers = sections
            .map((ToolSection s) => s.header)
            .toList();
        // Headers present must be a subsequence of the editorial order (empty
        // sections are dropped), and there must be no trailing "Other".
        expect(
          headers.contains('Other'),
          isFalse,
          reason: '$id orphaned a tool into "Other"',
        );
        final List<String> order = kCategorySubgroupOrder[id]!;
        int lastIdx = -1;
        for (final String h in headers) {
          final int idx = order.indexOf(h);
          expect(
            idx,
            greaterThan(lastIdx),
            reason: '$id section "$h" out of editorial order',
          );
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
        final List<String> catIds = cat(
          id,
        ).tools.map((ToolEntry t) => t.id).toList();
        expect(
          placedIds.toSet().length,
          placedIds.length,
          reason: '$id placed a tool in two sections',
        );
        expect(
          placedIds.toSet(),
          catIds.toSet(),
          reason: '$id dropped or added a tool',
        );
      });

      test('$id: every tool has a subgroup that is a known header', () {
        final Set<String> known = kCategorySubgroupOrder[id]!.toSet();
        for (final ToolEntry t in cat(id).tools) {
          expect(
            t.subgroup,
            isNotNull,
            reason: '$id tool "${t.id}" has no subgroup',
          );
          expect(
            known.contains(t.subgroup),
            isTrue,
            reason: '$id tool "${t.id}" subgroup "${t.subgroup}" is unknown',
          );
        }
      });

      test('$id: each section is alphabetized by title', () {
        for (final ToolSection s in groupedCategoryTools(cat(id))) {
          final List<String> titles = s.tools
              .map((ToolEntry t) => t.title.toLowerCase())
              .toList();
          final List<String> sorted = <String>[...titles]..sort();
          expect(titles, sorted, reason: '$id section "${s.header}" not A-Z');
        }
      });
    }
  });

  // ── The anti-decay guard (2026-09-16) ───────────────────────────────────
  //
  // Quick Reference was reorganised on 2026-09-16 because it had rotted: 19
  // sections, one holding 24 tools and THREE holding exactly one. It rotted
  // quietly, one well-meaning addition at a time, and nothing noticed for
  // months. Without a floor it will rot the same way again.
  //
  // Keith asked for this guard by name when he approved the reorg.
  //
  // SCOPE: quick-reference only, deliberately. rf-calculators FAILS this floor
  // today -- 'Learn / RF intuition' and 'AEC & Documentation' hold one tool each
  // -- and that is RECORDED rather than silently fixed, because collapsing
  // someone else's category to make a test pass is how a guard becomes a lie.
  // When rf-calculators gets the same treatment, add it to the set below.
  const Set<String> kFloorEnforced = <String>{'quick-reference'};
  const int kMinSectionSize = 4;

  group('subgroup floor — a section of one is not a section', () {
    for (final String id in kFloorEnforced) {
      test('$id: no section holds fewer than $kMinSectionSize tools', () {
        final List<ToolSection> tooSmall = groupedCategoryTools(
          cat(id),
        ).where((ToolSection s) => s.count < kMinSectionSize).toList();
        expect(
          tooSmall.map((ToolSection s) => '${s.header} (${s.count})').toList(),
          isEmpty,
          reason:
              '$id has sections below the floor. Do not shrink the floor to '
              'make this pass -- dissolve the runt into its nearest survivor, '
              'which is the rule Keith set on 2026-06-01.',
        );
      });

      test('$id: no section holds more than a third of the category', () {
        // The other half of the same disease. Wi-Fi & RF held 24 of 102 before
        // the reorg; a third is a generous ceiling that still catches a giant.
        final List<ToolSection> sections = groupedCategoryTools(cat(id));
        final int total = sections.fold<int>(
          0,
          (int n, ToolSection s) => n + s.count,
        );
        final int ceiling = (total / 3).ceil();
        final List<String> tooBig = sections
            .where((ToolSection s) => s.count > ceiling)
            .map((ToolSection s) => '${s.header} (${s.count} of $total)')
            .toList();
        expect(
          tooBig,
          isEmpty,
          reason:
              '$id has a section above $ceiling. Split it by the JOB a '
              'reader was doing, not by topic.',
        );
      });
    }
  });

  group('groupedCategoryTools — flat categories', () {
    test('test-network returns a single unnamed section in pinned order', () {
      final List<ToolSection> sections = groupedCategoryTools(
        cat('test-network'),
      );
      expect(sections, hasLength(1));
      expect(sections.single.header, isEmpty);
      // The flat path preserves the pin order. Wave 4 (2026-06-04): the merged
      // connection tile was removed from the catalog, so Network Quality leads.
      expect(sections.single.tools.first.id, 'net-quality');
    });

    // Networking Tools was asserted flat here until 2026-09-13, when Keith had
    // its 25 tools sectioned. It is now covered by the grouped-category block
    // above, which loops kCategorySubgroupOrder.keys. Educational Resources
    // takes its place as the flat case so this branch keeps a real subject.
    test('educational-resources returns a single unnamed section', () {
      final List<ToolSection> sections = groupedCategoryTools(
        cat('educational-resources'),
      );
      expect(sections, hasLength(1));
      expect(sections.single.header, isEmpty);
      expect(sections.single.count, cat('educational-resources').tools.length);
    });

    test('networking is no longer flat, and is sectioned five ways', () {
      final List<ToolSection> sections = groupedCategoryTools(
        cat('networking'),
      );
      expect(sections, hasLength(5));
      expect(sections.map((ToolSection s) => s.header).toList(), <String>[
        'This Device',
        'Reachability & Path',
        'Discovery & Scanning',
        'Names & Ownership',
        'Services & Protocols',
      ]);
      // Every tool placed, none orphaned into "Other", none duplicated.
      final int placed = sections.fold<int>(
        0,
        (int n, ToolSection s) => n + s.count,
      );
      expect(placed, cat('networking').tools.length);
    });
  });
}
