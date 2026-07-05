// Telecom Spaces: MDF, IDF, TR, and the Data Closet - typed const datasets for
// the read-only field/trade reference screen (Field & Trade Reference set,
// 2026-07-05).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/17-facility-spaces.md,
// SOP-020 PASS): the "same room, several names" correction, the six-term decode
// table, the hierarchical-star topology, the ISO/IEC 11801 parallel, and the
// framing prose. No copy is rewritten here - the screen only lays it out.
//
// GL-005 / truthfulness: the six-term decode table is the load-bearing content,
// so the widget test asserts the anchor rows (TR is the current TIA-569 term,
// IDF is a legacy frame term functionally the same as a TR) against these
// consts so a future edit cannot silently drift a value away from Penn's
// approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing.

/// Stable catalog tool id - backs the route, the help entry, the bundled
/// facility-spaces-topology plate (assets/reference/facility-spaces.png), and
/// the tests. Permanent.
const String kFacilitySpacesToolId = 'facility-spaces';

/// One row of the telecom-spaces decode table. [term] is the space name;
/// [whatItIs] is what it is; [standardOrField] flags whether it is standard
/// vocabulary or a legacy/field term.
class TelecomSpaceRow {
  const TelecomSpaceRow({
    required this.term,
    required this.whatItIs,
    required this.standardOrField,
  });

  /// The space name, e.g. `Telecommunications Room (TR)`.
  final String term;

  /// What the space is.
  final String whatItIs;

  /// Whether it is a standard, legacy, or slang term.
  final String standardOrField;
}

/// The six telecom-space terms, decoded, verbatim from the copy.
const List<TelecomSpaceRow> kTelecomSpaces = <TelecomSpaceRow>[
  TelecomSpaceRow(
    term: 'Entrance Facility (EF)',
    whatItIs:
        'Where outside-plant and service-provider cabling enters the '
        'building. The demarcation point between the carrier and the building, '
        'usually on the lowest floor.',
    standardOrField: 'TIA-569 term',
  ),
  TelecomSpaceRow(
    term: 'Equipment Room (ER)',
    whatItIs:
        'A larger, centralized space housing equipment that serves the whole '
        'building or campus. Often co-located with, or is, the MDF.',
    standardOrField: 'TIA-569 term',
  ),
  TelecomSpaceRow(
    term: 'Telecommunications Room (TR)',
    whatItIs:
        'The current TIA-569 term for the floor or zone space that houses the '
        'cross-connects and active gear serving a work-area zone. This is what '
        'people call an IDF or a wiring closet. One per floor at minimum, more '
        'for large floors, because horizontal runs are distance-limited.',
    standardOrField: 'Current standard vocabulary',
  ),
  TelecomSpaceRow(
    term: 'MDF (Main Distribution Frame)',
    whatItIs:
        'Legacy term for the primary distribution point, the main equipment '
        'room, the hub. Typically the building\'s demarcation and entrance '
        'point for external service.',
    standardOrField: 'Legacy frame term, used universally',
  ),
  TelecomSpaceRow(
    term: 'IDF (Intermediate Distribution Frame)',
    whatItIs:
        'Legacy term for a satellite or floor telecom room that cross-connects '
        'horizontal cabling to the backbone. Functionally the same as a TR.',
    standardOrField: 'Legacy frame term, used universally',
  ),
  TelecomSpaceRow(
    term: 'Data closet',
    whatItIs: 'Informal catch-all for any TR or IDF. Not a standard term at all.',
    standardOrField: 'Slang',
  ),
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead.
const String kFacilityLead =
    'A decoder for the room names that get used interchangeably and are not '
    'interchangeable. The trap is that MDF, IDF, TR, telecom closet, and "data '
    'closet" are often four or five names for the same room. TIA-569\'s '
    'current term is Telecommunications Room; MDF and IDF are legacy '
    'distribution-frame words the field still uses every day.';

/// The governing-standard paragraph, verbatim.
const String kFacilityStandard =
    'The governing standard for these spaces is ANSI/TIA-569, '
    '"Telecommunications Pathways and Spaces," current revision -E. It sits '
    'alongside ANSI/TIA-568, which covers the cabling itself. This entry '
    'decodes the space names. The cable mechanics (the 90 meter horizontal '
    'link, categories, PoE budgeting) live in the Structured Cabling reference '
    'and are not repeated here.';

/// "Same room, several names" paragraph, verbatim.
const String kFacilitySameRoom =
    'Here is the correction that saves you in a coordination meeting. "MDF" '
    'and "IDF" are distribution-frame terms carried over from telephone-era '
    'practice. TIA-569 modernized the vocabulary to Equipment Room and '
    'Telecommunications Room. The standard says "TR" while the field still '
    'says "IDF," and both describe the same space. When you hear IDF, TR, '
    'telecom closet, and data closet in one conversation, they are usually the '
    'same room under different names.';

/// The topology paragraph 1, verbatim.
const String kFacilityTopology =
    'The cabling runs as a hierarchical star, per TIA-568. Service enters at '
    'the Entrance Facility, feeds the MDF or Equipment Room at the center, '
    'runs backbone (riser) cabling out to the IDF or TR on each floor or zone, '
    'and from there horizontal cabling reaches the work-area outlet or the AP.';

/// The topology paragraph 2 (the shape), verbatim.
const String kFacilityShape =
    'MDF at the center, IDFs and TRs as satellites, backbone between them, '
    'horizontal from the IDF or TR out to the AP. That is the shape. The '
    'distance limit on the horizontal run, and the way AP count drives IDF '
    'count and switch-port budget, are covered in the Structured Cabling '
    'reference.';

/// The international parallel paragraph, verbatim.
const String kFacilityInternational =
    'Outside the US, ISO/IEC 11801 describes the same hierarchy with '
    '"distributor" terms: Campus Distributor, Building Distributor, and Floor '
    'Distributor. Worth recognizing on an international job, not worth '
    'memorizing.';

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kFacilityWlanCares =
    'When the electrician says "MDF," the architect\'s drawing says "TR," and '
    'the client says "the data closet," knowing they mean the same room keeps '
    'you from designing a phantom extra space or missing a real one. The IDF '
    'and TR locations are where your APs get their uplink and their power, so '
    'reading the space names correctly is the first step to placing APs that '
    'can actually be cabled.';

/// The defer footer (rendered as an info band). Verbatim.
const String kFacilityDeferNote =
    'Reference only. Confirm the space names, standards currency, and cabling '
    'design with the architect of record, the RCDD, and your contract for the '
    'specific project.';
