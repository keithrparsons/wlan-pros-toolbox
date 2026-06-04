// Unit tests for orderedCategoryTools — the per-category display ordering.
//
// Rule (Wave 4, 2026-06-04): every category lists its tools alphabetically by
// title, EXCEPT Test Network, which pins Network Quality then Wi-Fi Information
// to the top and sorts any remainder (e.g. Cellular Information) alphabetically.
// The merged Test My Connection / Wi-Fi vs Internet tile was removed from the
// catalog entirely (reached via the home hero card), so neither id pins here.
// Networking Tools is plain alphabetical like the rest.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/category_screen.dart';

void main() {
  group('orderedCategoryTools', () {
    test('non-pinned categories are sorted alphabetically by title', () {
      for (final ToolCategory cat in kToolCategories) {
        if (cat.id == 'test-network') continue;
        final List<String> titles = orderedCategoryTools(
          cat,
        ).map((ToolEntry t) => t.title).toList();
        final List<String> sorted = <String>[...titles]
          ..sort(
            (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
          );
        expect(titles, sorted, reason: 'category "${cat.id}" should be A-Z');
      }
    });

    test('Test Network pins Network Quality, Wi-Fi Information, then rest A-Z', () {
      final ToolCategory net = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'test-network',
      );
      final List<ToolEntry> ordered = orderedCategoryTools(net);

      // The pinned ids lead (Wave 4, 2026-06-04). The merged connection tile is
      // gone from the catalog, so net-quality + wifi-info are the only pins.
      expect(ordered[0].id, 'net-quality');
      expect(ordered[1].id, 'wifi-info');

      // Neither merged-away id appears in the category at all.
      final Set<String> ids = ordered.map((ToolEntry t) => t.id).toSet();
      expect(ids.contains('test-my-connection'), isFalse);
      expect(ids.contains('wifi-vs-internet'), isFalse);

      // The remainder (everything after the pins) is alphabetical and
      // contains none of the pinned ids.
      final List<ToolEntry> rest = ordered.sublist(
        kTestNetworkPinnedToolIds.length,
      );
      expect(
        rest.any((ToolEntry t) => kTestNetworkPinnedToolIds.contains(t.id)),
        isFalse,
      );
      final List<String> restTitles = rest
          .map((ToolEntry t) => t.title)
          .toList();
      final List<String> sorted = <String>[...restTitles]
        ..sort(
          (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
        );
      expect(restTitles, sorted);

      // No tools dropped or duplicated.
      expect(ordered.length, net.tools.length);
      expect(ordered.map((ToolEntry t) => t.id).toSet().length, ordered.length);
    });
  });
}
