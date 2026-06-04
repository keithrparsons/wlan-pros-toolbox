// Per-category display ordering — the pin list + alphabetical fallback.
//
// Lives in the data layer (not the screen) so both the category screen and the
// grouping helper (tool_subgroups.dart) can use it without a screen↔data import
// cycle. The catalog stays the source of truth; this is purely presentation
// order.

import 'tool_catalog.dart';

/// The id of the one category with a hand-pinned tool order. Since the
/// 2026-06-01 reorganization the live diagnostics live in Test Network (they
/// moved out of Networking Tools, which is now plain alphabetical).
const String kPinnedCategoryId = 'test-network';

/// Tool ids pinned to the top of Test Network, in this exact order (Keith's
/// ordering, 2026-06-01): the consumer one-tap tool first, then the deeper pro
/// tools — Test My Connection, Network Quality, Wi-Fi Information,
/// Wi-Fi vs Internet.
const List<String> kTestNetworkPinnedToolIds = <String>[
  'test-my-connection',
  'net-quality',
  'wifi-info',
  'wifi-vs-internet',
];

/// Display order for a category's tools: alphabetical by title, EXCEPT the
/// Test Network category, which pins [kTestNetworkPinnedToolIds] to the top
/// (in that order) and sorts the remainder alphabetically.
List<ToolEntry> orderedCategoryTools(ToolCategory category) {
  int byTitle(ToolEntry a, ToolEntry b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());

  if (category.id != kPinnedCategoryId) {
    return <ToolEntry>[...category.tools]..sort(byTitle);
  }

  final List<ToolEntry> pinned = <ToolEntry>[];
  for (final String id in kTestNetworkPinnedToolIds) {
    final int i = category.tools.indexWhere((ToolEntry t) => t.id == id);
    if (i != -1) pinned.add(category.tools[i]);
  }
  final List<ToolEntry> rest =
      category.tools
          .where((ToolEntry t) => !kTestNetworkPinnedToolIds.contains(t.id))
          .toList()
        ..sort(byTitle);
  return <ToolEntry>[...pinned, ...rest];
}
