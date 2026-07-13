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
/// NOTE: the 10 laminated PDF cards that used to live under a "Reference Cards"
/// section here moved to the Educational Resources category on 2026-06-04
/// (Keith); they now render at the top of EducationalResourcesScreen, not as a
/// Quick Reference subgroup. The two INTERACTIVE checklists stayed in the
/// "Checklists" section below.
const Map<String, List<String>> kCategorySubgroupOrder = <String, List<String>>{
  'quick-reference': <String>[
    'Wi-Fi & RF',
    // Ham Radio (2026-06-28): the band-dependent amateur-radio references that
    // pair with the pure-math Ham Radio tools in Calculators & Tools. Sits right
    // after Wi-Fi & RF since these are RF-spectrum references a Wi-Fi pro
    // crosses into. Members: US Amateur Band Plan, Band Names & Wavelengths,
    // Spectrum Band Designations, Part 15 vs Part 97.
    'Ham Radio',
    // Addressing & Subnetting (2026-06-08): IP address reference, CIDR/subnet
    // table, naming/addressing conventions.
    'Addressing & Subnetting',
    'Protocols',
    // Models & Standards (2026-06-08): 802.1X/EAP types, 802.11 feature matrix.
    'Models & Standards',
    'Cabling & Connectors',
    // Power & Cooling (2026-06-08): demoted from a standalone top-level
    // category to a Quick Reference subgroup. Power phasing/voltages, the
    // Ohm's-Law power wheel, thermal conversions, and the IEC/NEMA/
    // international connector references. Sits after Cabling & Connectors —
    // connectors lead into the power feeds they carry.
    'Power & Cooling',
    // Travel & Field (2026-06-12): on-site-international field aids for a Wi-Fi
    // pro travelling to a job. Sits right after Power & Cooling (which holds the
    // International Power Plugs reference) since both answer "what do I need to
    // know before I land on this site". First member: Emergency Phrases.
    'Travel & Field',
    'Encoding',
    // Time & Formats (2026-06-08): date/time standards, data units.
    'Time & Formats',
    'CLI & Capture',
    'Checklists',
    // Step-by-step how-tos that bundle a downloadable companion file
    // (FreeRADIUS on WLAN Pi). Added 2026-06-05.
    'Guides',
    // Codes & Safety (2026-07-05): the field/trade-reference cluster — the
    // codes, ratings, and standards a Wi-Fi pro reads on spec sheets and job
    // sites but was never taught. Pilot member: Enclosure Ratings (IP / NEMA
    // ingress protection). Keeps Enclosure Ratings, Hazardous Locations, NEC
    // Gotchas, Safety Basics, Site Access, and Credentials & Licenses.
    'Codes & Safety',
    // AEC & Documentation (2026-07-05): the built-environment / plan-set
    // literacy cluster, split OUT of Codes & Safety on Keith's confirmed
    // topical-subgroup taxonomy. Members re-homed from Codes & Safety: Plan-Set
    // Literacy, CAD & BIM Formats, Structured Cabling, AEC Process & Glossary.
    // (Separate from the same-named Calculators subgroup that holds the
    // Architectural Scale calc — that calc stays in rf-calculators.)
    'AEC & Documentation',
    // Compliance & Governance (2026-07-05): the "before you upload / when the
    // framework reaches the WLAN" cluster. Members: Cloud Tool Trust (reading a
    // cloud tool's security badges) and Network in Scope (PCI/HIPAA/SOX/GDPR).
    'Compliance & Governance',
    // Wireless Landscape (2026-07-05): the non-Wi-Fi radios a WLAN pro
    // coexists with and designs around. Member: Adjacent Radio Systems.
    'Wireless Landscape',
    // Verticals (2026-07-05): what each industry tends to trigger. Members:
    // Verticals Index, Healthcare Wi-Fi, Data Centers & Wi-Fi, Telecom Spaces.
    'Verticals',
    // Vendor & Hardware (2026-07-05): the two INTERACTIVE drill-down references
    // for identifying gear in the field — the cross-vendor AP status-LED decoder
    // (LED Decoder) and the per-vendor model-number scheme reader (Vendor Model
    // Decode). NAME flagged for Keith's confirmation ("Vendor & Hardware" vs
    // "Hardware ID"); defaulted here so the catalog compiles. Sits last as the
    // hardware-identification pillar of Quick Reference.
    'Vendor & Hardware',
  ],
  'rf-calculators': <String>[
    'RF & Propagation',
    'Antenna & Coverage',
    'Capacity & Power',
    'Coordinates & GPS',
    'Conversions',
    // Ham Radio (2026-06-28): amateur-radio pure-math tools that are useful to
    // Wi-Fi work too (Maidenhead grid squares for PtP planning, antenna-element
    // sizing). A dedicated section so the band-dependent ham tools coming next
    // have a home. First members: Antenna Length, Maidenhead Grid Square.
    'Ham Radio',
    // Learn / RF intuition (2026-06-28): interactive teaching tools that build
    // RF intuition by sense, not just computation. First member: Hear the
    // Frequency (a real-time tone generator bridging audio pitch/octaves/
    // harmonics to RF). Sits after the pure-math sections and before the
    // standalone generators. SUBGROUP NAME flagged for Iris/Keith confirmation.
    'Learn / RF intuition',
    // Batch 4b/4c: standalone field utilities that aren't unit conversions or
    // RF math (QR Code Generator, DTMF Generator).
    'Utilities & Generators',
    // AEC & Documentation (2026-07-05): the built-environment / plan-set
    // literacy set. Pilot member: Architectural Scale (scale↔ratio +
    // drawn↔real). Sits last — a distinct pillar from the RF/ham math above.
    // Future plan-set-reading references land in Quick Reference, not here.
    'AEC & Documentation',
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
