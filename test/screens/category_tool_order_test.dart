// Unit tests for orderedCategoryTools — the per-category display ordering.
//
// Rule (since the 2026-06-01 reorganization): every category lists its tools
// alphabetically by title, EXCEPT Test Network, which pins Test My Connection,
// Network Quality, Wi-Fi Information, then Wi-Fi vs Internet to the top and
// sorts any remainder alphabetically. Networking Tools is now plain
// alphabetical like the rest.

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

    test('Test Network pins Test My Connection, Network Quality, Wi-Fi '
        'Information, Wi-Fi vs Internet, then rest A-Z', () {
      final ToolCategory net = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'test-network',
      );
      final List<ToolEntry> ordered = orderedCategoryTools(net);

      // The pinned ids lead, in Keith's specified order (2026-06-01).
      expect(ordered[0].id, 'test-my-connection');
      expect(ordered[1].id, 'net-quality');
      expect(ordered[2].id, 'wifi-info');
      expect(ordered[3].id, 'wifi-vs-internet');

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
