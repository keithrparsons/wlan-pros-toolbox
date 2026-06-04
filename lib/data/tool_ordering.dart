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

/// Tool ids pinned to the top of Test Network, in this exact order.
///
/// Wave 4 (Keith, 2026-06-04): the consumer `test-my-connection` and pro
/// `wifi-vs-internet` tools MERGED into one tool reached via the home hero card,
/// so both tiles were removed from this category entirely. The grid now shows
/// Network Quality first, then Wi-Fi Information (Cellular Information sorts in
/// alphabetically after the pins).
const List<String> kTestNetworkPinnedToolIds = <String>[
  'net-quality',
  'wifi-info',
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
