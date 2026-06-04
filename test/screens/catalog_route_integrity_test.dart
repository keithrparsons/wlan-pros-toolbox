// Catalog ↔ router integrity, plus coverage of the 10 PDF reference cards.
//
// Closes a previously-untested gap: nothing asserted that every live tool's
// `routeName` actually resolves to a registered builder in `AppRouter.routes`.
// A live tool whose route is missing (typo, forgotten map entry) would compile
// fine and only fail when a user taps it — exactly the kind of deferred bug a
// contract test should catch. Added with the PDF-reference-card work
// (feat/pdf-reference-cards).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';

/// Every tool entry across all categories, flattened.
List<ToolEntry> _allTools() =>
    kToolCategories.expand((ToolCategory c) => c.tools).toList();

void main() {
  group('catalog ↔ router integrity', () {
    test('every live tool routeName resolves to a registered builder', () {
      final List<String> missing = <String>[];
      for (final ToolEntry t in _allTools()) {
        if (!t.isLive) continue;
        if (!AppRouter.routes.containsKey(t.routeName)) {
          missing.add('${t.id} -> ${t.routeName}');
        }
      }
      expect(
        missing,
        isEmpty,
        reason: 'live tools with no registered route: ${missing.join(", ")}',
      );
    });

    test('tool ids are globally unique', () {
      final List<String> ids = _allTools().map((ToolEntry t) => t.id).toList();
      expect(
        ids.toSet().length,
        ids.length,
        reason: 'duplicate tool id(s) in the catalog',
      );
    });

    test('tool routeNames are globally unique', () {
      final List<String> routes = _allTools()
          .map((ToolEntry t) => t.routeName)
          .toList();
      expect(
        routes.toSet().length,
        routes.length,
        reason: 'duplicate routeName(s) in the catalog',
      );
    });

    // IA-redesign schema guards (2026-06-03).
    test('every tool has a non-null keywords list', () {
      for (final ToolEntry t in _allTools()) {
        // keywords defaults to const [] and is folded from the vocabulary; it
        // must never be null. (Empty is allowed for a tool with no extra terms.)
        expect(t.keywords, isNotNull, reason: '${t.id} has null keywords');
      }
    });

    test('grouped-category tools carry a subgroup that is a known header', () {
      for (final ToolCategory c in kToolCategories) {
        final List<String>? order = kCategorySubgroupOrder[c.id];
        if (order == null) continue; // flat categories don't require a subgroup
        for (final ToolEntry t in c.tools) {
          expect(t.subgroup, isNotNull,
              reason: '${c.id}/${t.id} missing a subgroup');
          expect(order.contains(t.subgroup), isTrue,
              reason: '${c.id}/${t.id} subgroup "${t.subgroup}" not in order');
        }
      }
    });
  });

  group('PDF reference cards', () {
    // id → title contract for the 10 laminated cards. Titles are kept verbatim
    // from the brief (brand-checked); a rename here is a deliberate breaking
    // change, not an accident. Since 2026-06-04 ALL 10 cards live in the
    // Educational Resources category (moved out of Quick Reference; ids/titles/
    // routes/assets unchanged by the move). They render as a "Reference Cards"
    // section at the top of EducationalResourcesScreen.
    const Map<String, String> referenceCards = <String, String>{
      'bubble-diagram': 'WLAN Pros Bubble Diagram',
      'troubleshooting-causes': 'Wireless LAN Troubleshooting Causes',
      'channel-allocations-24ghz': '2.4 GHz Channel Allocations',
      'channel-allocations-5ghz': '5 GHz Channel Allocations',
      'channel-allocations-6ghz': '6 GHz Channel Allocations',
      'mcs-index-card': 'Modulation and Coding Schemes (MCS Index)',
    };
    const Map<String, String> checklistCards = <String, String>{
      'top-20-checklist': 'Top 20 Wi-Fi Checklist',
      'extended-checklist': 'Extended Wi-Fi Checklist',
      'extended-checklist-nonadvertised':
          'Extended Checklist (Non-Advertised Items)',
      'connection-checklist': 'Wi-Fi Connection Checklist',
    };
    // Every PDF card, regardless of category — for route-resolution checks.
    final Map<String, String> allCards = <String, String>{
      ...referenceCards,
      ...checklistCards,
    };

    // Assert a set of id→title cards all live in the named category with the
    // expected title/route, and are live.
    void expectCardsInCategory(String categoryId, Map<String, String> cards) {
      final ToolCategory category = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == categoryId,
      );
      final Map<String, ToolEntry> byId = <String, ToolEntry>{
        for (final ToolEntry t in category.tools) t.id: t,
      };
      cards.forEach((String id, String title) {
        expect(
          byId.containsKey(id),
          isTrue,
          reason: 'missing PDF card "$id" in $categoryId',
        );
        final ToolEntry t = byId[id]!;
        expect(t.title, title, reason: 'title mismatch for "$id"');
        expect(t.isLive, isTrue, reason: '"$id" must be live');
        expect(
          t.routeName,
          '/tools/$id',
          reason: 'route convention /tools/<id> for "$id"',
        );
      });
    }

    test('the 6 reference PDF cards live in educational-resources', () {
      expectCardsInCategory('educational-resources', referenceCards);
    });

    test('the 4 checklist PDF cards now live in educational-resources too', () {
      expectCardsInCategory('educational-resources', checklistCards);
    });

    test('each PDF card route resolves to a builder', () {
      for (final String id in allCards.keys) {
        expect(
          AppRouter.routes.containsKey('/tools/$id'),
          isTrue,
          reason: 'no registered route for PDF card "$id"',
        );
      }
    });

    test(
      'mcs-index-card does not collide with the existing mcs-index table',
      () {
        final List<String> ids = _allTools()
            .map((ToolEntry t) => t.id)
            .toList();
        expect(
          ids.contains('mcs-index'),
          isTrue,
          reason: 'existing mcs-index table should still be present',
        );
        expect(
          ids.contains('mcs-index-card'),
          isTrue,
          reason: 'new mcs-index-card should be present',
        );
      },
    );
  });
}
