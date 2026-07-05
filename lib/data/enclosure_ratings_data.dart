// Enclosure Ratings (IP and NEMA) — typed const datasets for the read-only
// reference screen. Every string is rendered VERBATIM from Penn's voice-gated
// copy (Deliverables/2026-07-05-field-trade-reference/content/01-enclosure-
// ratings.md, SOP-020 PASS): the two IP-digit ladders, the common-IP table, the
// NEMA types, the one-way NEMA->IP mapping, the placement guidance, the myths,
// and the framing prose. No copy is rewritten here — the screen only lays it out.
//
// GL-005 / truthfulness: these tables are the load-bearing facts, so the widget
// test asserts the anchor rows (IP first-digit 6 = dust-tight, second-digit 7 =
// immersion, NEMA 4X = corrosion, the one-way rule) against these consts so a
// future edit cannot silently drift a value away from Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; "802.1X"/"802.3" style not used here. A "-" in a `detail`/`meaning`
// cell renders the source's "no test / none" dash exactly as the copy shows it.

/// Stable catalog tool id — backs the route, the help entry, the bundled diagram
/// PNG (assets/reference/enclosure-ratings.png), and the tests. Permanent.
const String kEnclosureRatingsToolId = 'enclosure-ratings';

/// One row of an IP-code digit ladder (first digit = solids/dust, second digit
/// = water). [code] is the digit as printed (`0`..`6`, `0`..`9K`); [label] is
/// the short protection name; [detail] is the plain meaning / test gate.
class IpDigit {
  const IpDigit({required this.code, required this.label, required this.detail});

  /// The digit as printed in the code, e.g. `6` or `9K`.
  final String code;

  /// Short protection name, e.g. `Dust-tight` or `Immersion`.
  final String label;

  /// Plain meaning or the defined lab-test gate for this digit.
  final String detail;
}

/// First IP digit: solids and dust, 0 to 6. The object-size ladder ends at 4
/// (1 mm); 5 and 6 switch to a dust-chamber test.
const List<IpDigit> kIpSolidsDigits = <IpDigit>[
  IpDigit(code: '0', label: 'None', detail: '-'),
  IpDigit(
    code: '1',
    label: 'Large body part',
    detail: 'Objects 50 mm and larger (back of the hand)',
  ),
  IpDigit(
    code: '2',
    label: 'Fingers',
    detail: 'Objects 12.5 mm and larger',
  ),
  IpDigit(
    code: '3',
    label: 'Tools, thick wires',
    detail: 'Objects 2.5 mm and larger',
  ),
  IpDigit(
    code: '4',
    label: 'Fine wires, screws',
    detail: 'Objects 1.0 mm and larger',
  ),
  IpDigit(
    code: '5',
    label: 'Dust-protected',
    detail: 'Some dust may enter, not enough to interfere with operation',
  ),
  IpDigit(code: '6', label: 'Dust-tight', detail: 'No dust ingress at all'),
];

/// Second IP digit: water, 0 to 9K. Two levels get misread: 8 is
/// manufacturer-defined depth, and 9K is pressure-washing, not immersion.
const List<IpDigit> kIpWaterDigits = <IpDigit>[
  IpDigit(code: '0', label: 'None', detail: '-'),
  IpDigit(code: '1', label: 'Vertical drips', detail: 'Light dripping straight down'),
  IpDigit(
    code: '2',
    label: 'Tilted drips',
    detail: 'Drips with the enclosure tilted up to 15 degrees',
  ),
  IpDigit(
    code: '3',
    label: 'Spray',
    detail: 'Sprayed water up to 60 degrees from vertical',
  ),
  IpDigit(code: '4', label: 'Splash', detail: 'Splashed from any direction'),
  IpDigit(code: '5', label: 'Jets', detail: 'Low-pressure jets from any direction'),
  IpDigit(
    code: '6',
    label: 'Powerful jets',
    detail: 'High-volume jets from any direction',
  ),
  IpDigit(
    code: '7',
    label: 'Immersion',
    detail: 'Temporary immersion to 1 m for 30 min',
  ),
  IpDigit(
    code: '8',
    label: 'Deep immersion',
    detail: 'Beyond 1 m, depth and time set by the manufacturer',
  ),
  IpDigit(
    code: '9K',
    label: 'High-pressure hot jets',
    detail: 'Close-range steam and pressure-wash (car wash, food plant)',
  ),
];

/// One row of the "common IP ratings you actually see" table.
class IpRating {
  const IpRating({
    required this.rating,
    required this.meaning,
    required this.example,
  });

  /// The full IP code, e.g. `IP66`.
  final String rating;

  /// Plain-language meaning.
  final String meaning;

  /// Typical WLAN example.
  final String example;
}

/// Common IP ratings a WLAN pro reads on spec sheets, verbatim from the copy.
const List<IpRating> kCommonIpRatings = <IpRating>[
  IpRating(
    rating: 'IP20',
    meaning: 'Finger-safe, no water rating',
    example: 'Indoor AP or switch',
  ),
  IpRating(
    rating: 'IP54',
    meaning: 'Dust-protected, splash-resistant',
    example: 'Covered outdoor or soffit gear',
  ),
  IpRating(
    rating: 'IP65',
    meaning: 'Dust-tight, low-pressure jets',
    example: 'Light outdoor',
  ),
  IpRating(
    rating: 'IP66',
    meaning: 'Dust-tight, powerful jets',
    example: 'Mainstream outdoor AP or antenna',
  ),
  IpRating(
    rating: 'IP67',
    meaning: 'Dust-tight, 30 min at 1 m',
    example: 'Common outdoor or ruggedized AP',
  ),
  IpRating(
    rating: 'IP68',
    meaning: 'Dust-tight, deep immersion (maker-defined)',
    example: 'Submersible gear',
  ),
  IpRating(
    rating: 'IP69K',
    meaning: 'Dust-tight, high-pressure hot wash',
    example: 'Washdown environments',
  ),
];

/// One NEMA type row (the four that matter for Wi-Fi).
class NemaType {
  const NemaType({required this.type, required this.meaning});

  /// NEMA type designation, e.g. `4X`.
  final String type;

  /// Plain meaning.
  final String meaning;
}

/// The four NEMA types that matter for Wi-Fi, verbatim from the copy.
const List<NemaType> kNemaTypes = <NemaType>[
  NemaType(
    type: '3R',
    meaning: 'Rain, sleet, snow. Rain-tight, not dust-tight, not hose-rated.',
  ),
  NemaType(
    type: '4',
    meaning: 'Type 3 plus hose-down and splash. The workhorse outdoor rating.',
  ),
  NemaType(
    type: '4X',
    meaning:
        'Type 4 plus corrosion resistance. The coastal, marine, and chemical '
        'default. The "X" is the whole point.',
  ),
  NemaType(
    type: '6 / 6P',
    meaning: 'Adds temporary (6) or prolonged (6P) submersion.',
  ),
];

/// One row of the NEMA-to-IP minimum-equivalent table. The relationship is
/// one-way: a NEMA type maps to a MINIMUM IP; the reverse is not valid.
class NemaIpMapping {
  const NemaIpMapping({required this.nemaType, required this.minimumIp});

  /// NEMA type, e.g. `4X`.
  final String nemaType;

  /// Minimum IP commonly cited (both values shown where sources disagree).
  final String minimumIp;
}

/// NEMA -> IP minimum equivalents, verbatim. Approximate floors, never certified
/// equivalences; 3R and 6P vary by source, so both cited values are shown.
const List<NemaIpMapping> kNemaToIp = <NemaIpMapping>[
  NemaIpMapping(nemaType: '3R', minimumIp: 'IP14, also cited as IP24'),
  NemaIpMapping(nemaType: '4', minimumIp: 'IP66'),
  NemaIpMapping(
    nemaType: '4X',
    minimumIp: 'IP66 (plus corrosion, which IP does not capture)',
  ),
  NemaIpMapping(nemaType: '6', minimumIp: 'IP67'),
  NemaIpMapping(nemaType: '6P', minimumIp: 'IP67, also cited as IP68'),
];

/// One row of the "what rating for what placement" guidance table.
class PlacementGuidance {
  const PlacementGuidance({
    required this.placement,
    required this.reachFor,
    required this.why,
  });

  /// Where the gear mounts, e.g. `Coastal or marine`.
  final String placement;

  /// The rating to reach for.
  final String reachFor;

  /// Why that rating fits the hazard at this placement.
  final String why;
}

/// Placement -> rating guidance, verbatim from the copy.
const List<PlacementGuidance> kPlacementGuidance = <PlacementGuidance>[
  PlacementGuidance(
    placement: 'Exposed rooftop or pole',
    reachFor: 'IP66 to IP67, or NEMA 4',
    why: 'Blowing dust and wind-driven rain from every angle',
  ),
  PlacementGuidance(
    placement: 'Covered soffit or under eave',
    reachFor: 'IP54 to IP65, or NEMA 3R',
    why: 'Shielded from direct rain; dust and splash are the real threat',
  ),
  PlacementGuidance(
    placement: 'Warehouse or dusty indoor',
    reachFor: 'IP5X to IP6X',
    why: 'Water is rarely the issue; airborne particulate is',
  ),
  PlacementGuidance(
    placement: 'Coastal or marine',
    reachFor: 'High IP plus NEMA 4X',
    why: 'IP tests fresh water only; salt needs a corrosion spec',
  ),
  PlacementGuidance(
    placement: 'Car wash or food washdown',
    reachFor: 'IP69K (plus IP67)',
    why: 'High-pressure hot water is the test, not immersion',
  ),
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead: what enclosure ratings are and why pros translate.
const String kEnclosureLead =
    'The two rating systems that tell you whether an enclosure, AP, antenna, or '
    'PoE injector will survive dust and water where you plan to mount it. IP '
    'comes from IEC 60529 (international). NEMA comes from NEMA 250 (US). US '
    'spec sheets quote NEMA, international sheets quote IP, and pros translate '
    'between them.';

/// IP-code section intro.
const String kIpCodeIntro =
    'An IP rating reads left to right: IP then two digits. First digit is solids '
    'and dust. Second digit is water. Each digit maps to a defined lab test, '
    'which is why the code is trustworthy and "waterproof" is not.';

/// The worked IP67 example line.
const String kIpCodeExample =
    'IP 6 7 means 6 = dust-tight, 7 = survives temporary immersion.';

/// Caption under the solids-digit ladder.
const String kIpSolidsNote =
    'The object-size ladder ends at 4 (1 mm). Levels 5 and 6 switch to a '
    'dust-chamber test, so they are about dust, not a bigger object.';

/// Caption under the water-digit ladder.
const String kIpWaterNote =
    'Two levels get misread. 8 is manufacturer-defined, not a fixed depth. 9K '
    'is about pressure-washing, a different hazard than immersion.';

/// "The X placeholder and the letters" bullets, verbatim.
const List<String> kIpLetterNotes = <String>[
  'X means "not tested," not "zero." IPX7 is water-rated 7 with the solids '
      'digit unrated. IP6X is dust-tight but not water-tested. Read X as "no '
      'data," never as "fails."',
  'Optional letters after the digits (A, B, C, D) rate access to hazardous '
      'parts. Supplementary letters H, M, S, W flag test conditions (M = the '
      'gear was running during the water test, S = it was stationary). These are '
      'rare on AP gear.',
  'The letters F, O, and K you sometimes see belong to the automotive standard '
      'ISO 20653, not IEC 60529. Recognize them, do not treat them as IP letters.',
];

/// NEMA section intro.
const String kNemaIntro =
    'NEMA types describe the same idea for US spec sheets, and they test things '
    'IP never checks: corrosion, external icing, gasket aging, and oil. The four '
    'types that matter for Wi-Fi:';

/// Note under the NEMA types table (the full type list).
const String kNemaFullListNote =
    'The full type list also includes 1, 2, 3, 3S, 5, 12, and 13 (indoor and '
    'specialized).';

/// NEMA-to-IP section intro.
const String kNemaToIpIntro =
    'A NEMA type maps to a minimum IP equivalent. The reverse is not valid. '
    'NEMA tests corrosion, icing, gasket aging, and oil, so a NEMA 4X enclosure '
    'exceeds IP66, but an IP66 enclosure is not automatically NEMA 4X. It was '
    'never corrosion-tested.';

/// The one-way rule as a pull-quote.
const String kNemaToIpRule =
    'NEMA to IP: valid as a minimum. IP to NEMA: not valid.';

/// Caption under the NEMA-to-IP table.
const String kNemaToIpNote =
    'NEMA publishes no exact conversion, and reputable charts disagree on a '
    'couple of rows. Where they differ, both values are shown. Treat these as '
    'approximate floors, never as certified equivalences.';

/// "Myths worth killing" bullets, verbatim.
const List<String> kEnclosureMyths = <String>[
  '"Waterproof" is not an IP claim. The standard never uses the word. IP68 '
      'depth is manufacturer-defined, so two "IP68" devices can survive very '
      'different things.',
  'The water ladder is not a clean superset past 6. An IP67 (immersion) device '
      'is not guaranteed to pass IP66 (jets). Gear that must survive both is '
      'dual-marked, such as IP66/IP67.',
  'The two digits are independent. A high water number says nothing about dust.',
  'IP tests use fresh water only. Salt, detergents, and solvents need separate '
      'chemical-resistance verification.',
  'A bigger number is not always more protection. Match the digit to the hazard.',
];

/// "Why a WLAN pro cares" paragraphs, verbatim.
const List<String> kEnclosureWlanCares = <String>[
  'You read these codes on every outdoor and industrial AP, antenna, PoE '
      'injector, and enclosure spec sheet. The injector zip-tied under an eave '
      'is the classic weak install. Spec the enclosure to the actual hazard, '
      'and translate NEMA to IP (or back) so you can compare US and '
      'international gear on the same terms.',
  'A rating describes a lab test, not a guarantee. Verify the manufacturer\'s '
      'stated rating on the real spec sheet (for IP68, the stated depth and '
      'time), and match it to the real hazard at the mount point.',
];

/// The recognize-and-defer footer (rendered as an info band). Verbatim.
const String kEnclosureDeferNote =
    'This is a field reference, not code or design guidance. Confirm '
    'requirements with the AHJ, the architect of record, and a licensed '
    'electrician.';
