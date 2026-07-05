// Structured Cabling Standards - typed const datasets for the read-only
// field/trade reference screen (Field & Trade Reference set, 2026-07-05).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/08-structured-
// cabling.md, SOP-020 PASS): the TIA standards family, the 90+10 m channel
// rule, the cable-category table, the topology note, and the BICSI note. No
// copy is rewritten here - the screen only lays it out. This entry is
// text-reference (no decoder plate); a plate can be added later.
//
// GL-005 / truthfulness: the four TIA standards and the four cable categories
// are the load-bearing facts, so the widget test asserts the anchor rows
// (TIA-568, TIA-607, Cat 6A, the 90 m rule) against these consts so a future
// edit cannot silently drift a value away from Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; standard numbers and cable categories shown in DM Mono
// (AppMonoText.inlineCode).

/// Stable catalog tool id - backs the route, the help entry, and the tests.
/// Permanent.
const String kStructuredCablingToolId = 'structured-cabling';

/// One TIA standard. [number] is the standard designator (e.g. `ANSI/TIA-568`);
/// [description] is what it covers.
class TiaStandard {
  const TiaStandard({required this.number, required this.description});

  /// The standard designator, e.g. `ANSI/TIA-568`.
  final String number;

  /// What the standard covers.
  final String description;
}

/// The TIA family, verbatim from the copy.
const List<TiaStandard> kTiaStandards = <TiaStandard>[
  TiaStandard(
    number: 'ANSI/TIA-568',
    description:
        'cabling itself (components, categories, performance, T568A/B '
        'pin-outs). The one most cited.',
  ),
  TiaStandard(
    number: 'ANSI/TIA-569',
    description:
        'pathways and spaces (conduits, trays, telecom rooms, entrance '
        'facilities).',
  ),
  TiaStandard(
    number: 'ANSI/TIA-606',
    description:
        'administration and labeling (how you label and document cables, '
        'ports, and records).',
  ),
  TiaStandard(
    number: 'ANSI/TIA-607 (also J-STD-607)',
    description:
        'bonding and grounding for telecom infrastructure. Electrical-safety '
        'grounding under the NEC is separate and belongs to the codes '
        'reference.',
  ),
];

/// One cable category. [category] is the designator (e.g. `Cat 6A`); [reach] is
/// its practical reach.
class CableCategory {
  const CableCategory({required this.category, required this.reach});

  /// The cable-category designator, e.g. `Cat 6A`.
  final String category;

  /// The practical reach for that category.
  final String reach;
}

/// The cable categories, verbatim from the copy.
const List<CableCategory> kCableCategories = <CableCategory>[
  CableCategory(category: 'Cat 5e', reach: '1 Gbps'),
  CableCategory(
    category: '2.5G / 5G (NBASE-T, IEEE 802.3bz)',
    reach:
        '2.5 and 5 Gbps on existing Cat 5e to 100 m, no re-pull. Why Wi-Fi 6 '
        'and 6E AP uplinks run over the cable already in the wall.',
  ),
  CableCategory(
    category: 'Cat 6',
    reach:
        '1 Gbps to 100 m; 10 Gbps to about 55 m in the favorable case, but the '
        'dense-bundle planning distance is 37 m',
  ),
  CableCategory(
    category: 'Cat 6A',
    reach:
        '10 Gbps to 100 m. The practical bar for Wi-Fi 6, 6E, and 7 APs '
        'needing multi-gig uplinks.',
  ),
  CableCategory(
    category: 'Cat 8',
    reach: '25/40 Gbps to about 30 m; data-center short reach',
  ),
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead: what structured-cabling standards are and the line drawn
/// against the NEC codes reference.
const String kStructuredCablingLead =
    'The telecom-cabling standards that decide where an AP can go and what '
    'feeds it. The physical grounding-as-safety side lives in the NEC (see the '
    'codes reference). This is the TIA and BICSI infrastructure side.';

/// The 90+10 m channel intro, verbatim.
const String kChannelIntro =
    'Know this one cold. The horizontal permanent link is a maximum of 90 m of '
    'solid horizontal cable, from the telecom room to the work-area outlet. '
    'Add up to 10 m of stranded patch and equipment cords and you get a 100 m '
    'channel maximum. Exceed it and you are outside TIA.';

/// The AP-cable-run reality check under the channel rule, verbatim.
const String kChannelApReality =
    'For a WLAN pro this is the AP-cable-run reality check. An AP more than '
    'about 90 m of cable-path from the IDF needs an intermediate closet, a '
    'different topology, or fiber. That constraint shapes where IDFs go, and '
    'therefore where APs can go.';

/// The T568A/B pin-out note under the cable-category table, verbatim.
const String kPinoutNote =
    'T568A and T568B are the two pin-out standards. A jack is wired to one, so '
    'be consistent end to end.';

/// The topology-and-rooms note, verbatim.
const String kTopologyNote =
    'The path runs MDF (main equipment room) to backbone and riser cabling to '
    'IDF (telecom room per floor or zone) to horizontal cabling to the '
    'work-area outlet or AP. AP count and placement drive IDF count and '
    'PoE-switch port budgeting, and the 90 m rule ties AP locations to IDF '
    'locations. This is where the WLAN design and the cabling design have to '
    'talk to each other.';

/// The BICSI note, verbatim.
const String kBicsiNote =
    'BICSI is the professional body for the cabling trade. Its flagship '
    'credential is the RCDD (Registered Communications Distribution Designer), '
    'and the TDMM (Telecommunications Distribution Methods Manual) is the '
    'RCDD\'s core reference. Knowing who the RCDD is on a job tells you who '
    'owns the cabling design you must coordinate with.';

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kStructuredCablingWlanCares =
    'The 90 m rule and the Cat 6A bar shape real decisions. They set the outer '
    'edge of where you can place an AP and what uplink it can carry, which '
    'quietly drives IDF placement, switch selection, and the whole coverage '
    'plan.';

/// The defer footer (rendered as an info band). Verbatim.
const String kStructuredCablingDeferNote =
    'Reference only. Confirm cabling design and standards currency with the '
    'RCDD, the architect of record, and your contract for the specific '
    'project.';
