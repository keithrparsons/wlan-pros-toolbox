// Cross-category tool search — pure Dart, no dependency.
//
// Powers both the global search (search_screen.dart, all categories) and the
// in-category filter (category_screen.dart, scoped to one category). Reads
// [kToolCategories], which is the same full set on every platform (interface
// parity, Keith 2026-06-09) — on web the network tools are searchable too and
// open to their honest web-unavailable screen.
//
// Match rule (v1): case-insensitive SUBSTRING match against the tool's title,
// description, and each keyword. The matched FIELD is recorded so the results
// row can show the "matches '<term>' in content" sub-label for hits that only
// matched the description/keywords (mockup 04). Sort: title matches first, then
// description, then keyword; alphabetical by title within each tier. Empty query
// → empty list.

import 'tool_catalog.dart';

/// Which field a search hit matched on, best-tier-first. Used both for sort
/// priority and to drive the results-row sub-label (title hits need no extra
/// note; description/keyword hits show "matches in content").
enum ToolMatchField { title, description, keyword }

/// A single search result: the tool, its owning category (for the grouped
/// results screen and the source tag), and which field matched.
class ToolSearchHit {
  const ToolSearchHit({
    required this.tool,
    required this.categoryId,
    required this.categoryTitle,
    required this.matchedOn,
    required this.matchedKeyword,
  });

  final ToolEntry tool;
  final String categoryId;
  final String categoryTitle;

  /// The strongest field that matched (title > description > keyword).
  final ToolMatchField matchedOn;

  /// When [matchedOn] is [ToolMatchField.keyword], the specific keyword that
  /// matched (so the row can quote it, e.g. matches "speed test"). Null for
  /// title/description hits.
  final String? matchedKeyword;
}

/// Searches every tool in [kToolCategories] (the full set on every platform)
/// for [query].
///
/// Returns hits sorted title-first, then description, then keyword, alphabetical
/// within each tier. An empty or whitespace-only query returns an empty list.
/// When [categoryId] is non-null, the search is scoped to that one category
/// (used by the in-category filter); otherwise it spans all categories.
List<ToolSearchHit> searchTools(String query, {String? categoryId}) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return const <ToolSearchHit>[];

  final List<ToolSearchHit> hits = <ToolSearchHit>[];

  for (final ToolCategory category in kToolCategories) {
    if (categoryId != null && category.id != categoryId) continue;

    for (final ToolEntry tool in category.tools) {
      final bool titleHit = tool.title.toLowerCase().contains(q);
      final bool descHit = tool.description.toLowerCase().contains(q);
      String? keywordHit;
      for (final String kw in tool.keywords) {
        if (kw.toLowerCase().contains(q)) {
          keywordHit = kw;
          break;
        }
      }

      if (!titleHit && !descHit && keywordHit == null) continue;

      // Strongest tier wins for sort + sub-label.
      final ToolMatchField matchedOn = titleHit
          ? ToolMatchField.title
          : (descHit ? ToolMatchField.description : ToolMatchField.keyword);

      hits.add(
        ToolSearchHit(
          tool: tool,
          categoryId: category.id,
          categoryTitle: category.title,
          matchedOn: matchedOn,
          matchedKeyword:
              matchedOn == ToolMatchField.keyword ? keywordHit : null,
        ),
      );
    }
  }

  hits.sort((ToolSearchHit a, ToolSearchHit b) {
    final int byTier = a.matchedOn.index.compareTo(b.matchedOn.index);
    if (byTier != 0) return byTier;
    return a.tool.title.toLowerCase().compareTo(b.tool.title.toLowerCase());
  });

  return hits;
}

/// Number of distinct categories represented in [hits] — for the
/// "N results across M categories" count line (mockup 04).
int distinctCategoryCount(List<ToolSearchHit> hits) =>
    hits.map((ToolSearchHit h) => h.categoryId).toSet().length;
