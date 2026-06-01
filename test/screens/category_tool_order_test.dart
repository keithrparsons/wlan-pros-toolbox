// Unit tests for orderedCategoryTools — the per-category display ordering.
//
// Rule: every category lists its tools alphabetically by title, EXCEPT
// Networking Tools, which pins Wi-Fi Information then Network Quality to the
// top and sorts the remainder alphabetically.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/category_screen.dart';

void main() {
  group('orderedCategoryTools', () {
    test('non-networking categories are sorted alphabetically by title', () {
      for (final ToolCategory cat in kToolCategories) {
        if (cat.id == 'networking') continue;
        final List<String> titles =
            orderedCategoryTools(cat).map((ToolEntry t) => t.title).toList();
        final List<String> sorted = <String>[...titles]
          ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
        expect(titles, sorted, reason: 'category "${cat.id}" should be A-Z');
      }
    });

    test('Networking pins Wi-Fi Information then Network Quality, rest A-Z', () {
      final ToolCategory net =
          kToolCategories.firstWhere((ToolCategory c) => c.id == 'networking');
      final List<ToolEntry> ordered = orderedCategoryTools(net);

      // First two are the pinned ids, in the specified order.
      expect(ordered[0].id, 'wifi-info');
      expect(ordered[1].id, 'net-quality');

      // The remainder (everything after the two pins) is alphabetical and
      // contains neither pinned id.
      final List<ToolEntry> rest = ordered.sublist(kNetworkingPinnedToolIds.length);
      expect(rest.any((ToolEntry t) => kNetworkingPinnedToolIds.contains(t.id)), isFalse);
      final List<String> restTitles = rest.map((ToolEntry t) => t.title).toList();
      final List<String> sorted = <String>[...restTitles]
        ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
      expect(restTitles, sorted);

      // No tools dropped or duplicated.
      expect(ordered.length, net.tools.length);
      expect(ordered.map((ToolEntry t) => t.id).toSet().length, ordered.length);
    });
  });
}
