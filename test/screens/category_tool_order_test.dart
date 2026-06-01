// Unit tests for orderedCategoryTools — the per-category display ordering.
//
// Rule (since the 2026-06-01 reorganization): every category lists its tools
// alphabetically by title, EXCEPT Test Network, which pins Wi-Fi vs Internet,
// Wi-Fi Information, then Network Quality to the top and sorts the remainder
// alphabetically. Networking Tools is now plain alphabetical like the rest.

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

    test('Test Network pins Wi-Fi vs Internet, Wi-Fi Information, Network '
        'Quality, then rest A-Z', () {
      final ToolCategory net = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'test-network',
      );
      final List<ToolEntry> ordered = orderedCategoryTools(net);

      // First three are the pinned ids, in the specified order.
      expect(ordered[0].id, 'wifi-vs-internet');
      expect(ordered[1].id, 'wifi-info');
      expect(ordered[2].id, 'net-quality');

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
