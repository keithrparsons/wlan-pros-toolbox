// Plan-Set Literacy - typed const datasets for the read-only field/trade
// reference screen (Field & Trade Reference set, 2026-07-05).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/05-plan-set-
// literacy.md, SOP-020 PASS): the discipline-designator table, the sheet-type
// digit table, the Reflected Ceiling Plan section, the plan-set elements, the
// scales note, and the framing prose. No copy is rewritten here - the screen
// only lays it out.
//
// GL-005 / truthfulness: the two designator tables and the RCP reasons are the
// load-bearing facts, so the widget test asserts the anchor rows (the A/E/T
// disciplines, the sheet-type digits, the three RCP reasons) against these
// consts so a future edit cannot silently drift a value away from Penn's copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; the sheet number and scales shown in DM Mono (AppMonoText.inlineCode).

/// Stable catalog tool id - backs the route, the help entry, the bundled diagram
/// PNG (assets/reference/plan-set-literacy.png), and the tests. Permanent.
const String kPlanSetLiteracyToolId = 'plan-set-literacy';

/// One discipline designator: the letter that leads a sheet number and the
/// discipline that owns the sheet. [letter] is the single-letter code (e.g.
/// `A`); [discipline] is what it stands for (e.g. `Architectural`).
class DisciplineDesignator {
  const DisciplineDesignator({required this.letter, required this.discipline});

  /// The single-letter discipline code, e.g. `A`.
  final String letter;

  /// The discipline it designates, e.g. `Architectural`.
  final String discipline;
}

/// The primary discipline designators (National CAD Standard), verbatim. A/E/T
/// are the disciplines a WLAN pro reads most; the "plus others" tail and the
/// second-letter rule are carried in the section captions.
const List<DisciplineDesignator> kDisciplineDesignators =
    <DisciplineDesignator>[
  DisciplineDesignator(letter: 'G', discipline: 'General'),
  DisciplineDesignator(letter: 'C', discipline: 'Civil'),
  DisciplineDesignator(letter: 'L', discipline: 'Landscape'),
  DisciplineDesignator(letter: 'S', discipline: 'Structural'),
  DisciplineDesignator(letter: 'A', discipline: 'Architectural'),
  DisciplineDesignator(letter: 'I', discipline: 'Interiors'),
  DisciplineDesignator(letter: 'F', discipline: 'Fire Protection'),
  DisciplineDesignator(letter: 'P', discipline: 'Plumbing'),
  DisciplineDesignator(letter: 'M', discipline: 'Mechanical'),
  DisciplineDesignator(letter: 'E', discipline: 'Electrical'),
  DisciplineDesignator(letter: 'T', discipline: 'Telecommunications'),
];

/// One sheet-type digit: the digit that follows the discipline letter and the
/// kind of drawing it names. [digit] is the code (e.g. `1`); [meaning] is the
/// drawing type (e.g. `Plans`).
class SheetTypeDigit {
  const SheetTypeDigit({required this.digit, required this.meaning});

  /// The sheet-type digit as printed, e.g. `1` or `7 and 8`.
  final String digit;

  /// The kind of drawing that digit names.
  final String meaning;
}

/// The sheet-type digits, verbatim. So `A-1xx` is an architectural plan and
/// `E-6xx` an electrical schedule (carried in the caption).
const List<SheetTypeDigit> kSheetTypeDigits = <SheetTypeDigit>[
  SheetTypeDigit(digit: '0', meaning: 'General (legends, notes, symbols)'),
  SheetTypeDigit(digit: '1', meaning: 'Plans'),
  SheetTypeDigit(digit: '2', meaning: 'Elevations'),
  SheetTypeDigit(digit: '3', meaning: 'Sections'),
  SheetTypeDigit(digit: '4', meaning: 'Large-scale views'),
  SheetTypeDigit(digit: '5', meaning: 'Details'),
  SheetTypeDigit(digit: '6', meaning: 'Schedules and Diagrams'),
  SheetTypeDigit(digit: '7 and 8', meaning: 'User-defined'),
  SheetTypeDigit(digit: '9', meaning: '3D and isometric'),
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead: what plan-set literacy is and the US convention it follows.
const String kPlanSetLead =
    'How to read an architectural drawing set, so you can find the sheet you '
    'need, speak the same shorthand as the other trades, and put your APs on '
    'the one sheet that actually shows whether they fit. US convention (the '
    'National CAD Standard); sheet-numbering practice varies on smaller jobs.';

/// "Reading a sheet number" section intro.
const String kSheetNumberIntro =
    'A sheet number is a discipline letter, a sheet-type digit, and a sequence '
    'number.';

/// The worked sheet-number example (rendered on a mono band).
const String kSheetNumberExample =
    'A-201 is Architectural, an elevation, sheet 01.';

/// Caption under the discipline-designator table (the "plus others" tail and
/// the second-letter subdivision rule).
const String kDisciplineNote =
    'Plus others (H, V, B, Q, D, R, X, Z, O). A second letter subdivides on big '
    'jobs (TN = Telecom / Data Networks, TY = Telecom / Security, EP = '
    'Electrical Power).';

/// The Telecom-is-its-own-discipline body, verbatim.
const String kTelecomDisciplineNote =
    'Telecom (T) is its own discipline. Structured cabling and often the WLAN '
    'live on the T sheets, and that is where your drawings coordinate.';

/// Caption under the sheet-type digit table (the worked A-1xx / E-6xx read).
const String kSheetTypeNote =
    'So A-1xx is an architectural plan and E-6xx an electrical schedule.';

/// The Reflected Ceiling Plan section intro.
const String kRcpIntro =
    'An RCP is drawn as if a mirror on the floor reflects the ceiling upward, '
    'so you see the ceiling in the same left-right orientation as the floor '
    'plan below it. It shows the ceiling grid (the T-bar layout, usually 2x2 or '
    '2x4 ft tiles), mounting heights and ceiling elevations, and every '
    'ceiling-mounted element: light fixtures, HVAC diffusers and returns, '
    'sprinkler heads, speakers, exit signs, access panels, soffits, and '
    'bulkheads.';

/// Lead-in to the RCP reasons.
const String kRcpWhyIntro = 'Why it is the sheet for AP placement:';

/// The three reasons the RCP is the AP sheet, verbatim.
const List<String> kRcpReasons = <String>[
  'It is where mounting-height reality shows up. A 9 ft grid ceiling and a '
      '22 ft open-to-deck warehouse are different coverage problems.',
  'It is where physical conflicts surface on paper. An AP proposed dead-center '
      'of a room may collide with a diffuser, a light troffer, a sprinkler, or '
      'a soffit. Overlay your AP locations on the RCP and resolve the conflict '
      'before rough-in.',
  'Ceiling construction type (lay-in grid, hard-lid drywall, open plenum, '
      'clouds) drives the mounting method and back-box coordination.',
];

/// The RCP anti-pattern, rendered as a warning band. Verbatim.
const String kRcpAntiPattern =
    'Anti-pattern: placing APs on the architectural floor plan alone and never '
    'opening the RCP. The floor plan tells you the room. The RCP tells you '
    'whether the AP can physically go where you want it, and how high.';

/// "The rest of a plan set worth knowing" bullets, verbatim.
const List<String> kPlanSetElements = <String>[
  'Title block: project, sheet number, revision, scale, north arrow, seal.',
  'Legend or symbol schedule: every job invents its own symbols. Read the '
      'legend, do not assume.',
  'Keynotes: numbered callouts pointing to a note list.',
  'Revision clouds and delta triangles: the cloud marks what changed, the '
      'triangle carries the revision number. Always build to the latest '
      'revision.',
  'North arrow: watch the difference between true north and plan north.',
  'Detail and section callout bubbles: the circle-with-a-line that says '
      '"this detail is drawn on sheet X."',
];

/// The scales note, verbatim.
const String kScalesNote =
    'US architectural sheets use fractional-inch scales: 1/8" = 1\'-0" (1:96), '
    '1/4" = 1\'-0" (1:48), 1/2" = 1\'-0" (1:24), 1" = 1\'-0" (1:12). Site and '
    'civil sheets use the engineer\'s decimal scale (1" = 20\', 1" = 50\', '
    '1" = 100\'). To get the ratio, invert the fraction and multiply by 12: '
    '1/8" gives 8 x 12 = 1:96.';

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kPlanSetWlanCares =
    'A designer who can pull the right sheet, read the RCP, and speak in sheet '
    'numbers looks like a peer to the other trades instead of a junior. The RCP '
    'in particular is where your coverage design meets the physical ceiling, '
    'and catching an AP-versus-diffuser conflict on paper is far cheaper than '
    'catching it at rough-in.';

/// The defer footer (rendered as an info band). Verbatim - note this one differs
/// from the standard AHJ/electrician footer.
const String kPlanSetDeferNote =
    'Reference only. Confirm drawing conventions, revisions, and responsibility '
    'with the architect of record and your contract for the specific project.';
