// Category subgroup ordering + the grouped-tools helper for the category screen.
//
// The redesign (mockup 02) groups Quick Reference (37 tools) and Calculators &
// Tools (24) into section headers in ONE scroll. Section ORDER is editorial, not
// alphabetical on the subgroup string, so it lives here as an ordered list per
// category. A tool's section membership is its ToolEntry.subgroup (set in the
// catalog). Categories absent from kCategorySubgroupOrder render FLAT (one
// unnamed section, no headers) — so the pinned Test Network ordering and the
// plain Networking list are untouched by this change.

import 'tool_catalog.dart';
import 'tool_ordering.dart';

/// Editorial section order per category, by category id. The order of the
/// strings IS the on-screen order of the sections (mockup 02). A subgroup a tool
/// claims that is NOT in its category's list here would be orphaned — the
/// `tool_subgroups_test` asserts every grouped tool's subgroup is a known header
/// so a future catalog edit cannot silently drop a tool into "Other".
///
/// NOTE (interim): the "Reference Cards" section under quick-reference holds the
/// 10 laminated PDF cards until the Educational Resources category lands; see the
/// TODO(educational-resources) marker in tool_catalog.dart. When that category
/// is built, the cards move and "Reference Cards" is removed from this list.
const Map<String, List<String>> kCategorySubgroupOrder = <String, List<String>>{
  'quick-reference': <String>[
    'Wi-Fi & RF',
    'Cabling & Connectors',
    'Protocols',
    'Encoding',
    'CLI & Capture',
    'Checklists',
    'Reference Cards',
  ],
  'rf-calculators': <String>[
    'RF & Propagation',
    'Antenna & Coverage',
    'Capacity & Power',
    'Coordinates & GPS',
    'Conversions',
  ],
};

/// One rendered section of a category screen: a header (empty for the flat
/// single-section case), its tool count, and its (alphabetized) tools.
typedef ToolSection = ({String header, int count, List<ToolEntry> tools});

/// Returns the ordered, alphabetized sections for [category].
///
///   * If the category has an entry in [kCategorySubgroupOrder], tools are
///     bucketed by [ToolEntry.subgroup] into those sections in that order, each
///     bucket sorted alphabetically by title. A trailing "Other" section is
///     appended ONLY if some tool has a null/unknown subgroup (defensive — the
///     orphan test should keep this empty in practice).
///   * Otherwise the category renders flat: a single section with an empty
///     header (the screen draws no header for it) containing every tool sorted
///     by the existing [orderedCategoryTools] (preserving the Test Network pin
///     and plain-alphabetical behavior).
List<ToolSection> groupedCategoryTools(ToolCategory category) {
  final List<String>? order = kCategorySubgroupOrder[category.id];

  // Flat path — unchanged ordering semantics (pins + alphabetical) via the
  // existing helper. Empty header signals "draw no header".
  if (order == null) {
    final List<ToolEntry> flat = orderedCategoryTools(category);
    return <ToolSection>[(header: '', count: flat.length, tools: flat)];
  }

  int byTitle(ToolEntry a, ToolEntry b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());

  final List<ToolSection> sections = <ToolSection>[];
  final Set<ToolEntry> placed = <ToolEntry>{};

  for (final String header in order) {
    final List<ToolEntry> inSection =
        category.tools.where((ToolEntry t) => t.subgroup == header).toList()
          ..sort(byTitle);
    placed.addAll(inSection);
    if (inSection.isNotEmpty) {
      sections.add(
        (header: header, count: inSection.length, tools: inSection),
      );
    }
  }

  // Anything not claimed by a known header falls into a trailing "Other".
  final List<ToolEntry> leftover =
      category.tools.where((ToolEntry t) => !placed.contains(t)).toList()
        ..sort(byTitle);
  if (leftover.isNotEmpty) {
    sections.add((header: 'Other', count: leftover.length, tools: leftover));
  }

  return sections;
}
