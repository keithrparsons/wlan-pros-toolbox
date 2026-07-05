// Enterprise AP Model-Number Decoder (per vendor) — typed const datasets for
// the INTERACTIVE drill-down reference screen (Field & Trade Reference set,
// 2026-07-05). Pick a vendor -> read that vendor's model-number scheme (what
// each segment encodes) plus a worked example.
//
// IMPORTANT (GL-005, load-bearing): this is deliberately NOT a "paste a model
// number -> auto-decode" input. Several vendors (Extreme especially) do not
// digit-encode Wi-Fi generation / streams / antenna, so an auto-decoder would
// fabricate precision the SKU does not carry. The honest shape is a per-vendor
// schema plus the "confirm on the per-model datasheet" caveat where the content
// flags it. Every vendor encodes differently, so this is a per-vendor decoder,
// never a shared letter dictionary — the letter E alone means a regulatory
// domain (Cisco), an external antenna (Aruba even last digit), and a product
// tier (UniFi Enterprise).
//
// Every string is rendered VERBATIM from Penn's / Pax's voice-gated,
// fact-confirmed copy
// (Deliverables/2026-07-05-field-trade-reference/content/19-vendor-model-decode.md,
// SOP-020 PASS). No copy is rewritten here; the screen only lays it out.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; "802.11ax/ac" casing preserved.

/// Stable catalog tool id — backs the route, the help entry, and the tests.
/// Permanent. Interactive drill-down: no bundled plate.
const String kVendorModelDecodeToolId = 'vendor-model-decode';

/// One ordered token in a vendor's model-number scheme, read left to right.
class ModelToken {
  const ModelToken({
    required this.token,
    required this.encodes,
    required this.example,
  });

  /// The segment as it appears in the SKU, e.g. `C prefix`, `First digit`.
  final String token;

  /// What that segment encodes.
  final String encodes;

  /// One or more example values.
  final String example;
}

/// One decoded step of a worked example.
class DecodeStep {
  const DecodeStep({required this.segment, required this.meaning});

  /// The segment being decoded, e.g. `C`, `9130`, `-B`.
  final String segment;

  /// What that segment resolves to.
  final String meaning;
}

/// One vendor's decode module: the token table, a worked example, and the
/// confidence / caveats note.
class DecodeVendor {
  const DecodeVendor({
    required this.id,
    required this.name,
    required this.confidence,
    required this.intro,
    required this.tokens,
    required this.exampleSku,
    required this.exampleSteps,
    required this.readBack,
    required this.confidenceNote,
    this.suffixTitle,
    this.suffixMeanings = const <String>[],
  });

  /// Stable vendor id, e.g. `cisco`, `aruba`, `unifi`.
  final String id;

  /// The vendor name shown in the picker and the detail heading.
  final String name;

  /// The confidence label, e.g. `High`, `High (with one age caveat)`,
  /// `Medium`.
  final String confidence;

  /// The framing paragraph for the vendor.
  final String intro;

  /// The ordered token -> meaning table, read left to right.
  final List<ModelToken> tokens;

  /// The SKU decoded in the worked example, e.g. `C9130AXI-B`.
  final String exampleSku;

  /// The worked example, segment by segment.
  final List<DecodeStep> exampleSteps;

  /// The plain-language read-back for the worked example.
  final String readBack;

  /// The confidence + caveats note (carries the "per-model datasheet lookup"
  /// caveat and, for Aruba, the even/odd "confirmed back to Wi-Fi 5, 200-series
  /// unverified" note).
  final String confidenceNote;

  /// Optional title for a suffix-meaning list (UniFi).
  final String? suffixTitle;

  /// Optional suffix-word meanings (UniFi tiers / form factors).
  final List<String> suffixMeanings;
}

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead.
const String kDecodeLead =
    'A reference that turns an opaque access point SKU into plain facts. Model '
    'numbers are position- and suffix-encoded, stable within a vendor '
    'generation, and documented in datasheets, so a clean decode is possible '
    'offline. The catch is that every vendor encodes differently, so this is a '
    'per-vendor decoder, never a shared parser. Pick the vendor, read its own '
    'token rules and a worked example.';

/// The "one rule that keeps this honest" — the E-letter collision, rendered as
/// a warning band up front.
const String kDecodeHonestRule =
    'Decode per-vendor. Never build a shared letter dictionary. The letter E '
    'alone means three different things depending on the vendor: Cisco -E '
    '(trailing, after the dash) = a regulatory domain; Aruba even last digit '
    '(an E-style external variant) = external antenna; UniFi Enterprise = a '
    'product tier. A single universal letter map would turn all three into one '
    'wrong answer. Resolve the vendor first, then apply that vendor\'s own token '
    'rules.';

/// The standing caveat shown on every lookup (info band).
const String kDecodeStandingCaveat =
    'A decode is a heuristic. If a segment does not match a known token it reads '
    'as "unrecognized segment", never a guess. Confirm against the exact '
    'model\'s datasheet or ordering guide. Rules are stable within a generation; '
    'only the per-model lookup grows over time.';

/// The reference-only defer footer (info band).
const String kDecodeDeferNote =
    'This is a field reference, not a guarantee. A model-number decode is a '
    'heuristic. Confirm against the exact model\'s datasheet or ordering guide '
    'before you spec, order, or troubleshoot on it.';

/// The backlog note — vendors deliberately not decoded here.
const String kDecodeBacklogNote =
    'Not decoded here (flagged for a later pass): Juniper Mist, Fortinet, '
    'Cambium, and Omada. When built they get their own module; do not stretch '
    'another vendor\'s rules onto them.';

// ──────────────────────────────── the data ──────────────────────────────────

/// Every vendor module, in picker order.
const List<DecodeVendor> kDecodeVendors = <DecodeVendor>[
  // ─────────────────────────────── CISCO ───────────────────────────────
  DecodeVendor(
    id: 'cisco',
    name: 'Cisco (Catalyst / Aironet / IW, plus Meraki CW)',
    confidence: 'High',
    intro:
        'Cisco encodes position by position, and the trailing letter after the '
        'dash is the regulatory domain. Do not confuse that trailing E (a '
        'domain) with the antenna E.',
    tokens: <ModelToken>[
      ModelToken(
        token: 'C prefix',
        encodes: 'Catalyst product family',
        example: 'C9130...',
      ),
      ModelToken(
        token: 'IW prefix',
        encodes: 'Industrial Wireless (ruggedized)',
        example: 'IW9167',
      ),
      ModelToken(
        token: '9130 (4-digit)',
        encodes:
            'Model within the Catalyst 9100 family; higher generally means '
            'newer or higher tier',
        example: '9105 / 9115 / 9120 / 9130 / 9136 / 9162 / 9164 / 9166',
      ),
      ModelToken(
        token: 'AX',
        encodes: 'Radio standard (802.11ax)',
        example: 'AX',
      ),
      ModelToken(
        token: 'I or E (letter before the dash)',
        encodes: 'Antenna type: I = internal, E = external',
        example: '...AXI = internal',
      ),
      ModelToken(
        token: '-B / -A / -E (letter after the dash)',
        encodes: 'Regulatory domain (do not read as antenna)',
        example: '-B = a domain',
      ),
      ModelToken(
        token: 'MR or CW (Meraki naming)',
        encodes:
            'MR = classic cloud-managed line; CW = Catalyst Wireless converged '
            'naming',
        example: 'MR46, CW9166',
      ),
    ],
    exampleSku: 'C9130AXI-B',
    exampleSteps: <DecodeStep>[
      DecodeStep(segment: 'C', meaning: 'Catalyst family'),
      DecodeStep(
        segment: '9130',
        meaning:
            'Model within the Catalyst 9100 family (higher tier than a 9120, '
            'lower than a 9136)',
      ),
      DecodeStep(segment: 'AX', meaning: '802.11ax radio'),
      DecodeStep(segment: 'I', meaning: 'Internal antennas'),
      DecodeStep(
        segment: '-B',
        meaning: 'Regulatory domain (a domain code, not the antenna E)',
      ),
    ],
    readBack:
        'Catalyst 9130, 802.11ax, internal antennas, US-class regulatory '
        'domain.',
    confidenceNote:
        'Confidence: High. Sourced from the Catalyst 9130AX datasheet, the '
        'Getting Started Guide, the 9100 FAQ, and reseller SKU listings '
        'corroborating the internal/external and domain split. The '
        'trailing-letter-equals-domain rule is the one users most often misread; '
        'it is called out explicitly above.',
  ),

  // ───────────────────────────── HPE ARUBA ─────────────────────────────
  DecodeVendor(
    id: 'aruba',
    name: 'HPE Aruba (5xx / 6xx / 7xx)',
    confidence: 'High (with one age caveat)',
    intro:
        'Aruba encodes generation in the first digit and antenna type in the '
        'even/odd of the last digit. Region lives in a SKU suffix, not in the '
        'base AP-NNN.',
    tokens: <ModelToken>[
      ModelToken(
        token: 'AP- prefix',
        encodes: 'Aruba access point',
        example: 'AP-635',
      ),
      ModelToken(
        token: 'First digit',
        encodes: 'Generation: 5 = Wi-Fi 6, 6 = Wi-Fi 6E, 7 = Wi-Fi 7',
        example: '6xx = Wi-Fi 6E',
      ),
      ModelToken(
        token: 'Middle digit',
        encodes: 'Performance / stream tier',
        example: 'higher = higher tier',
      ),
      ModelToken(
        token: 'Last digit (even or odd)',
        encodes: 'Antenna type: even = external antenna, odd = internal',
        example: '514 external / 515 internal; 634 external / 635 internal',
      ),
      ModelToken(
        token: 'SKU suffix (separate)',
        encodes: 'Regulatory region: US / RW / EG / IL / JP',
        example: '...-US',
      ),
    ],
    exampleSku: 'AP-635 (vs AP-634)',
    exampleSteps: <DecodeStep>[
      DecodeStep(segment: 'AP-', meaning: 'Aruba access point'),
      DecodeStep(segment: '6', meaning: 'Wi-Fi 6E generation'),
      DecodeStep(segment: '3', meaning: 'Performance / stream tier'),
      DecodeStep(
        segment: '5 (odd)',
        meaning:
            'Internal antenna; the paired AP-634 (even) is the external-antenna '
            'variant',
      ),
      DecodeStep(
        segment: 'Region',
        meaning: 'Carried in the ordering suffix, not in AP-635 itself',
      ),
    ],
    readBack:
        'Aruba Wi-Fi 6E access point, mid stream-tier, internal antenna.',
    confidenceNote:
        'Confidence: High. The even/odd antenna rule is confirmed back to the '
        'Wi-Fi 5 (802.11ac Wave 2) 300 series: AP-314 = four RP-SMA '
        'external-antenna connectors, AP-315 = four integrated internal '
        'antennas, identical radios otherwise. So the rule holds across the '
        'current 5xx/6xx pairs and back through the 300 series. '
        'Reported-but-unverified: the 200 series (AP-214/215, AP-224/225) is '
        'widely said to follow the same pattern but was not confirmed against a '
        'datasheet. Treat pre-300-series as decode-from-per-model-lookup, not '
        'from the even/odd rule. Source: Aruba 310 Series datasheet.',
  ),

  // ─────────────────────────── UBIQUITI UNIFI ──────────────────────────
  DecodeVendor(
    id: 'unifi',
    name: 'Ubiquiti UniFi (U6 / U7 plus suffix)',
    confidence: 'High',
    intro:
        'UniFi encodes generation in the U6/U7 prefix and form-factor or tier '
        'in the suffix word. There is no embedded regulatory letter.',
    tokens: <ModelToken>[
      ModelToken(
        token: 'U6 / U7 prefix',
        encodes: 'Wi-Fi generation (6 or 7)',
        example: 'U7 = Wi-Fi 7',
      ),
      ModelToken(
        token: 'Suffix word',
        encodes: 'Tier or form factor',
        example: 'see the suffix list',
      ),
      ModelToken(
        token: '(no token)',
        encodes: 'Regulatory domain not encoded in the name',
        example: 'region handled outside the model string',
      ),
    ],
    suffixTitle: 'Suffix meanings',
    suffixMeanings: <String>[
      'Lite = entry tier',
      'Pro / Pro Max = higher tier',
      'Enterprise = 6 GHz flagship tier',
      'LR = Long Range (semi-outdoor, IP54)',
      'Mesh = outdoor / backhaul',
      'IW = In-Wall',
      'Outdoor = outdoor form factor',
    ],
    exampleSku: 'U7-Pro',
    exampleSteps: <DecodeStep>[
      DecodeStep(segment: 'U7', meaning: 'Wi-Fi 7 generation'),
      DecodeStep(segment: 'Pro', meaning: 'Higher performance tier'),
      DecodeStep(segment: '(name)', meaning: 'No regulatory letter in the name'),
    ],
    readBack: 'UniFi Wi-Fi 7, Pro tier.',
    confidenceNote:
        'Confidence: High. Sourced from UniFi Tech Specs, ui.com product pages, '
        'and independent guides. Note the E collision: UniFi Enterprise is a '
        'tier, not an external-antenna marker and not a regulatory domain.',
  ),

  // ─────────────────────────────── RUCKUS ──────────────────────────────
  DecodeVendor(
    id: 'ruckus',
    name: 'Ruckus (R / T / H / E series)',
    confidence: 'High',
    intro:
        'Ruckus encodes the deployment environment in the letter prefix and the '
        'performance tier in the number.',
    tokens: <ModelToken>[
      ModelToken(
        token: 'Letter prefix',
        encodes:
            'Environment: R = indoor, T = outdoor, H = wall-plate / hospitality '
            '(with switch ports), E = outdoor external-antenna',
        example: 'R730, T350, H350',
      ),
      ModelToken(
        token: 'XX0 (number)',
        encodes: 'Performance tier',
        example: 'higher = higher tier',
      ),
    ],
    exampleSku: 'R730',
    exampleSteps: <DecodeStep>[
      DecodeStep(segment: 'R', meaning: 'Indoor environment'),
      DecodeStep(
        segment: '730',
        meaning: 'Performance tier within the indoor line',
      ),
    ],
    readBack:
        'Ruckus indoor access point, 730-tier. A T350 would read "outdoor, '
        '350-tier"; an H350 "wall-plate / hospitality with switch ports, '
        '350-tier".',
    confidenceNote:
        'Confidence: High. Sourced from the Ruckus product guide and the R730 / '
        'T350 / H350 datasheets. The environment prefix is the load-bearing '
        'token; get that right and the rest is tier.',
  ),

  // ─────────────────────────── EXTREME NETWORKS ────────────────────────
  DecodeVendor(
    id: 'extreme',
    name: 'Extreme Networks (AP3000 / AP4000 / AP5010 "Universal")',
    confidence: 'Medium',
    intro:
        'Extreme uses AP plus a 4-digit number, but only the first digit '
        'encodes anything decodable: the performance tier. Wi-Fi generation, '
        'stream count, and antenna type are stated per model in the datasheet, '
        'not digit-encoded. This is the least systematic scheme in the set, so '
        'there is no auto-decode here, because a decoder that inferred those '
        'segments would fabricate precision the SKU does not carry.',
    tokens: <ModelToken>[
      ModelToken(
        token: 'AP prefix',
        encodes: 'Extreme access point',
        example: 'AP3000',
      ),
      ModelToken(
        token: 'First digit',
        encodes: 'Performance tier: 3 = value, 4 = mid, 5 = premium',
        example: '3000 value / 4000 mid / 5010 premium',
      ),
      ModelToken(
        token: 'Remaining digits',
        encodes:
            'Not a reliable code, read with the first digit as the model label',
        example: '3000, 4000, 5010',
      ),
      ModelToken(
        token: '"Universal" label',
        encodes: 'Runs multiple Extreme operating systems',
        example: 'Universal AP',
      ),
      ModelToken(
        token: 'Wi-Fi generation / stream count / antenna',
        encodes: 'Stated per model, NOT digit-encoded',
        example: 'read from the datasheet',
      ),
      ModelToken(
        token: 'Trailing letters',
        encodes:
            'X = added / extended radio variant (AP3000X); W or -WW = worldwide '
            'regulatory (AP5010-WW)',
        example: 'AP3000X, AP5010-WW',
      ),
    ],
    exampleSku: 'AP4000',
    exampleSteps: <DecodeStep>[
      DecodeStep(segment: 'AP', meaning: 'Extreme access point'),
      DecodeStep(
        segment: '4 (first digit)',
        meaning: 'Mid tier (above the value AP3000, below the premium AP5010)',
      ),
      DecodeStep(
        segment: '000',
        meaning: 'Model label, not a further code',
      ),
      DecodeStep(
        segment: 'Wi-Fi gen / streams / antenna',
        meaning: 'Come from the AP4000 datasheet, not from the name',
      ),
    ],
    readBack:
        'Extreme AP4000, mid tier; confirm Wi-Fi generation, stream count, and '
        'antenna from the datasheet.',
    confidenceNote:
        'Confidence: Medium. Only the first digit is decodable (tier). '
        'Everything else needs a per-model datasheet lookup, and this is far '
        'less systematic than Cisco or Aruba. Do not infer a segment that '
        'Extreme does not encode. Source: Extreme AP3000 / AP4000 / AP5010 '
        'product pages.',
  ),
];
