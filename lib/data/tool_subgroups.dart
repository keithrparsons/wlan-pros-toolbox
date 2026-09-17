// Category subgroup ordering + the grouped-tools helper for the category screen.
//
// The redesign (mockup 02) groups Quick Reference (37 tools) and Calculators &
// Tools (24) into section headers in ONE scroll. Section ORDER is editorial, not
// alphabetical on the subgroup string, so it lives here as an ordered list per
// category. A tool's section membership is its ToolEntry.subgroup (set in the
// catalog). Categories absent from kCategorySubgroupOrder render FLAT (one
// unnamed section, no headers) — so the pinned Test Network ordering is
// untouched by this change, as is Educational Resources.
// NETWORKING TOOLS WAS IN THAT FLAT SET UNTIL 2026-09-13 and is now grouped.

import 'tool_catalog.dart';
import 'tool_ordering.dart';

/// Editorial section order per category, by category id. The order of the
/// strings IS the on-screen order of the sections (mockup 02). A subgroup a tool
/// claims that is NOT in its category's list here would be orphaned — the
/// `tool_subgroups_test` asserts every grouped tool's subgroup is a known header
/// so a future catalog edit cannot silently drop a tool into "Other".
///
/// NOTE: the 10 laminated PDF cards that used to live under a "Reference Cards"
/// section here moved to the Educational Resources category on 2026-06-04
/// (Keith); they now render at the top of EducationalResourcesScreen, not as a
/// Quick Reference subgroup. The two INTERACTIVE checklists stayed in the
/// "Checklists" section below.
const Map<String, List<String>> kCategorySubgroupOrder = <String, List<String>>{
  'quick-reference': <String>[
    // REORGANISED 2026-09-16, applying the rule Keith set for CATEGORIES on
    // 2026-06-01 ("Planning Tools / Command & Capture / Checklists dissolved
    // into survivors") one layer down, to subgroups. 19 sections -> 13.
    //
    // The disease it cured: 'Wi-Fi & RF' held 24 tools -- nearly a quarter of
    // the category and everything Wi-Fi-shaped -- while NINE sections held three
    // or fewer and THREE held exactly one. A section of one is not a section.
    //
    // 'Wi-Fi & RF' split four ways by the JOB, not the topic: what is in the air
    // (Radio & Spectrum), what the spec says (Wi-Fi Standards & Terminology),
    // how you get on (Security & Auth), what the client end does (Clients &
    // Field Wi-Fi). 'Models & Standards' dissolved into TWO different survivors,
    // which is correct rather than untidy -- a feature matrix and an EAP-type
    // table are looked up on different days.
    //
    // Order below is editorial and runs from the air outward: the RF, the
    // standard, getting on, the client, debugging it, the wire, the plant, the
    // power, the rules, the building -- then the adjacent and the incidental.
    //
    // NOTE 'Ham Radio' is ALSO a subgroup name under rf-calculators. Subgroups
    // are scoped per category, and the 2026-09-16 rewrite was confined to this
    // quick-reference block for exactly that reason; a global rename would
    // have silently rewritten a different category.
    //
    // CORRECTED 2026-09-17: this said 'AEC & Documentation' was shared too. It
    // stopped being true on 2026-09-16, when this very rewrite absorbed that
    // section here, and the comment was not updated with the list beneath it.
    // Caught by a test written for an unrelated change, which had trusted the
    // comment and asserted the name still existed here. It does not.
    'Radio & Spectrum',
    'Wi-Fi Standards & Terminology',
    'Security & Auth',
    'Clients & Field Wi-Fi',
    'Capture & Troubleshooting',
    'Networking & Protocols',
    'Cabling, Connectors & Hardware',
    'Power & Cooling',
    'Codes, Safety & Compliance',
    'Buildings & Verticals',
    'Ham Radio',
    'Encoding & Formats',
    'Travel & International',
  ],
  'rf-calculators': <String>[
    'RF & Propagation',
    'Antenna & Coverage',
    'Capacity & Power',
    // IP & Addressing (2026-08-25): the three IP subnet calculators, moved in
    // from Networking Tools because Keith went looking for a subnet calculator
    // in Calculators & Tools, did not find one, and reasonably concluded the
    // app only had reference tables.
    //
    // Placed in the top half, after the core RF sections and ahead of
    // Coordinates & GPS: IP addressing is closer to daily network work than
    // grid squares are, but it does not outrank the RF math this app is for.
    // The position is editorial and reversible — it is Keith's to overrule.
    'IP & Addressing',
    'Coordinates & GPS',
    'Conversions',
    // Ham Radio (2026-06-28): amateur-radio pure-math tools that are useful to
    // Wi-Fi work too (Maidenhead grid squares for PtP planning, antenna-element
    // sizing). A dedicated section so the band-dependent ham tools coming next
    // have a home. First members: Antenna Length, Maidenhead Grid Square.
    'Ham Radio',
    // Batch 4b/4c: standalone field utilities that aren't unit conversions or
    // RF math (QR Code Generator, DTMF Generator, Morse Code) plus, since
    // 2026-09-17, Hear the Frequency.
    'Utilities & Generators',
    //
    // TWO NAMES WERE REMOVED FROM THIS LIST ON 2026-09-17 AND NO TOOL WAS.
    //
    // 'Learn / RF intuition' and 'AEC & Documentation' each held exactly one
    // tool, which fails the floor the Quick Reference guard enforces. Keith
    // ruled them dissolved and said what that had to mean: "we don't want to
    // LOSE the runts, just put them under a different category."
    //
    //   hear-frequency       -> 'Utilities & Generators'
    //   architectural-scale  -> 'Conversions'
    //
    // Both ids and both routeNames are unchanged, so routes, tests, help
    // entries and the keyword index are all untouched. This is a shelving
    // change and nothing else.
    //
    // 'AEC & Documentation' still EXISTS under quick-reference and is a
    // different subgroup that happens to share a name. Subgroups are scoped
    // per category, which is why the 2026-09-16 rewrite was confined to the
    // quick-reference block, and why this change is confined to this one.
  ],
  // Networking Tools (2026-09-13, Keith): 25 tools rendering FLAT was the one
  // real findability gap left in the app. Every other oversized category was
  // already grouped; this one had never been given an entry here, so its 25
  // tools arrived as one undifferentiated alphabetical list.
  //
  // SECTIONED BY THE JOB, NOT BY THE PROTOCOL. The order below is the order a
  // troubleshooting job actually unfolds: start where you are, find out whether
  // you can get out, see what else is on the wire, work out who something is,
  // then poke the service itself. Grouping by protocol family instead would put
  // Ping (ICMP) and Ping (TCP) in different sections, which is precisely the
  // distinction a person hunting for "ping" does not have in mind yet.
  //
  // Five sections of five. Editorial and reversible — Keith's to overrule.
  'networking': <String>[
    'This Device',
    'Reachability & Path',
    'Discovery & Scanning',
    'Names & Ownership',
    'Services & Protocols',
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
      sections.add((header: header, count: inSection.length, tools: inSection));
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
