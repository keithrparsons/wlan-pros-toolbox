// AEC Process and Glossary - typed const datasets for the read-only field/trade
// reference screen (Field & Trade Reference set, 2026-07-05).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/09-aec-process-
// glossary.md, SOP-020 PASS): the design-phase table (with when Wi-Fi should
// engage), the AIA note, and the AEC glossary that trips WLAN pros up. No copy
// is rewritten here - the screen only lays it out. This entry is text-reference
// (no decoder plate) and is glossary-heavy; a plate can be added later.
//
// GL-005 / truthfulness: the six design phases and the glossary terms are the
// load-bearing facts, so the widget test asserts the anchor rows (SD engages
// RF requirements, RFI, AHJ, submittal) against these consts so a future edit
// cannot silently drift a value away from Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; phase and glossary designators (SD, DD, CD, CA, RFI, AHJ, ...) shown
// in DM Mono (AppMonoText.inlineCode).

/// Stable catalog tool id - backs the route, the help entry, and the tests.
/// Permanent.
const String kAecProcessGlossaryToolId = 'aec-process-glossary';

/// One design-and-construction phase. [abbr] is the mono phase designator (e.g.
/// `SD`), empty for phases with no acronym; [phase] is the readable phase name;
/// [whatHappens] is what the phase produces; [whenWifi] is when Wi-Fi should
/// engage.
class AecPhase {
  const AecPhase({
    required this.abbr,
    required this.phase,
    required this.whatHappens,
    required this.whenWifi,
  });

  /// The phase acronym (e.g. `SD`), or '' when the phase has none.
  final String abbr;

  /// The readable phase name.
  final String phase;

  /// What happens in the phase.
  final String whatHappens;

  /// When Wi-Fi should engage in the phase.
  final String whenWifi;
}

/// The six AEC design phases (US convention, AIA), verbatim from the copy.
const List<AecPhase> kAecPhases = <AecPhase>[
  AecPhase(
    abbr: '',
    phase: 'Programming',
    whatHappens: 'Needs and space list, pre-design',
    whenWifi: 'Gather density and use-case requirements if you can',
  ),
  AecPhase(
    abbr: 'SD',
    phase: 'Schematic Design',
    whatHappens: 'Rough form and general arrangement',
    whenWifi:
        'The moment to establish RF requirements and reserve IDF and ceiling '
        'access',
  ),
  AecPhase(
    abbr: 'DD',
    phase: 'Design Development',
    whatHappens: 'Systems get defined: MEP, structural, ceilings',
    whenWifi: 'Coordinate AP locations and mounting against the developing RCP',
  ),
  AecPhase(
    abbr: 'CD',
    phase: 'Construction Documents',
    whatHappens: 'The biddable, buildable drawing set',
    whenWifi:
        'Finalize AP plans, mounting details, cabling, and telecom sheets',
  ),
  AecPhase(
    abbr: '',
    phase: 'Bidding / Negotiation',
    whatHappens: 'The set goes out for price',
    whenWifi: 'Answer bidder questions if asked',
  ),
  AecPhase(
    abbr: 'CA',
    phase: 'Construction Administration',
    whatHappens: 'The build: RFIs, submittals, site observation',
    whenWifi:
        'Answer RFIs, review submittals, verify install, walk the punch list',
  ),
];

/// One glossary entry. [abbr] is the mono designator (e.g. `RFI`), empty when
/// the term is a plain word; [term] is the readable expansion or name, empty
/// when the entry is designator-only; [definition] is the body.
///
/// Reconstruction matches Penn's copy exactly: when [abbr] and [term] are both
/// set it reads `ABBR (Term): definition`; abbr-only reads `ABBR: definition`;
/// plain reads `Term: definition`.
class GlossaryTerm {
  const GlossaryTerm({
    required this.abbr,
    required this.term,
    required this.definition,
  });

  /// The acronym designator (e.g. `RFI`), or '' when the term is a plain word.
  final String abbr;

  /// The readable expansion or name, or '' when the entry is designator-only.
  final String term;

  /// The definition body.
  final String definition;
}

/// The AEC glossary that trips WLAN pros up, verbatim from the copy.
const List<GlossaryTerm> kAecGlossary = <GlossaryTerm>[
  GlossaryTerm(
    abbr: 'RFI',
    term: 'Request for Information',
    definition:
        'a formal question to the design team when documents are unclear or '
        'conflicting. The mechanism you use when the RCP and the AP plan '
        'collide.',
  ),
  GlossaryTerm(
    abbr: '',
    term: 'Submittal',
    definition:
        'the contractor\'s proof (product data, shop drawings, samples) that '
        'what they will install matches the spec. Your APs, mounts, and cable '
        'are submittals.',
  ),
  GlossaryTerm(
    abbr: '',
    term: 'Shop drawings',
    definition:
        'detailed drawings the contractor or fabricator derives from the '
        'construction documents.',
  ),
  GlossaryTerm(
    abbr: 'ASI',
    term: 'Architect\'s Supplemental Instructions',
    definition: 'a minor clarification with no cost or time impact.',
  ),
  GlossaryTerm(
    abbr: '',
    term: 'Change Order',
    definition:
        'a formal, signed change to scope, cost, or schedule (what an ASI is '
        'not).',
  ),
  GlossaryTerm(
    abbr: 'RFP / RFQ',
    term: '',
    definition: 'Request for Proposal / Qualifications.',
  ),
  GlossaryTerm(
    abbr: '',
    term: 'Punch list',
    definition:
        'the end-of-job list of incomplete or deficient items to fix before '
        'final acceptance.',
  ),
  GlossaryTerm(
    abbr: 'AHJ',
    term: 'Authority Having Jurisdiction',
    definition:
        'the building official, fire marshal, or inspector who interprets and '
        'enforces code locally. The AHJ\'s word governs.',
  ),
  GlossaryTerm(
    abbr: 'GC',
    term: 'General Contractor',
    definition:
        'builds the project and hires subs. Sub: a subcontractor; the '
        'low-voltage or IT sub often owns cabling and AP install.',
  ),
  GlossaryTerm(
    abbr: 'MEP',
    term: 'Mechanical, Electrical, Plumbing',
    definition:
        'the engineering disciplines whose ceiling and wall equipment you '
        'coordinate against.',
  ),
  GlossaryTerm(
    abbr: 'OAC',
    term: '',
    definition:
        'the recurring Owner-Architect-Contractor coordination meeting. If '
        'Wi-Fi matters, someone carries it into the OAC.',
  ),
  GlossaryTerm(
    abbr: 'AOR / EOR',
    term: 'Architect of Record / Engineer of Record',
    definition:
        'the licensed professional who stamps the drawings and bears '
        'responsibility.',
  ),
  GlossaryTerm(
    abbr: 'BOD / OPR',
    term: 'Basis of Design / Owner\'s Project Requirements',
    definition:
        'the intent documents your RF requirements should land in.',
  ),
  GlossaryTerm(
    abbr: '',
    term: 'Addendum',
    definition:
        'a pre-bid change to the documents. Bulletin or SI: a post-award '
        'change instruction.',
  ),
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead: what the AEC process and glossary are, and the US (AIA)
/// convention it follows.
const String kAecProcessLead =
    'The design-and-construction workflow you work inside, and the shorthand '
    'the other trades use. Speak it fluently and you look like a peer in the '
    'room instead of the network person who wandered in. US convention (AIA).';

/// The note under the phase table on engaging at SD, verbatim.
const String kEngageSdNote =
    'Engaging at SD is the difference between designing Wi-Fi in and '
    'retrofitting it later.';

/// The AIA note, verbatim.
const String kAiaNote =
    'The American Institute of Architects is the professional body for '
    'architects and the publisher of the industry\'s standard contract '
    'documents (owner-architect and owner-contractor agreements, general '
    'conditions like A201, and the BIM and digital-data exhibits). You rarely '
    'sign these, but you constantly work under them, so recognizing the '
    'vocabulary matters. Treat anything about contractual responsibility as '
    '"confirm with the architect of record and your contract," never as a '
    'ruling.';

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kAecProcessWlanCares =
    'The RFI, the submittal, the punch list, and the OAC are the levers that '
    'get your coverage design built the way you drew it. Knowing when to raise '
    'an RFI (the moment the RCP and your AP plan disagree) and how to get your '
    'gear approved as a submittal is the difference between a design that '
    'survives construction and one that gets value-engineered away while you '
    'were not in the room.';

/// The defer footer (rendered as an info band). Verbatim.
const String kAecProcessDeferNote =
    'Reference only. Confirm contractual responsibility, code compliance, and '
    'phase deliverables with the architect of record, the AHJ, and your '
    'contract for the specific project.';
