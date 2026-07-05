// Verticals: What You're Walking Into - typed const datasets for the read-only
// field/trade reference screen (Field & Trade Reference set, 2026-07-05). This
// entry is text-reference (no decoder plate); it is the index that points at
// the other reference entries.
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/14-by-vertical-index.md,
// SOP-020 PASS): the ten-vertical map, the retail/PCI and high-density notes,
// and the framing prose. No copy is rewritten here - the screen only lays it
// out.
//
// GL-005 / truthfulness: the ten-vertical map is the load-bearing content, so
// the widget test asserts the anchor rows (Oil/gas -> hazloc, Healthcare ->
// Healthcare Wi-Fi, Retail -> PCI note) against these consts so a future edit
// cannot silently drift a value away from Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; "802.1X" casing.

/// Stable catalog tool id - backs the route, the help entry, and the tests.
/// Permanent. Text-reference: no bundled plate.
const String kByVerticalIndexToolId = 'by-vertical-index';

/// One row of the vertical map. [vertical] is the industry you name; [triggers]
/// is what it tends to trigger; [readFirst] is the reference entry to open.
class VerticalRow {
  const VerticalRow({
    required this.vertical,
    required this.triggers,
    required this.readFirst,
  });

  /// The industry, e.g. `Oil, gas, chemical, refining`.
  final String vertical;

  /// What the vertical tends to trigger on site.
  final String triggers;

  /// The reference entry (or note) to read first.
  final String readFirst;
}

/// The ten-vertical map, verbatim from the copy.
const List<VerticalRow> kVerticals = <VerticalRow>[
  VerticalRow(
    vertical: 'Manufacturing and heavy industry',
    triggers:
        'Possible hazardous (classified) location; metal and racking '
        'multipath; ruggedized wide-temperature gear',
    readFirst: 'Hazardous (Classified) Locations; Enclosure Ratings',
  ),
  VerticalRow(
    vertical: 'Oil, gas, chemical, refining',
    triggers:
        'Almost-certain hazloc (Class I, ATEX or IECEx); rated APs or remote '
        'antennas; corrosion',
    readFirst: 'Hazardous (Classified) Locations; Enclosure Ratings',
  ),
  VerticalRow(
    vertical: 'Warehouse and distribution',
    triggers:
        'High-bay mounting; forklift zones where you are a pedestrian; fast '
        'roaming across many APs; devices at 3 to 6 ft, not desk height; dust '
        'and temperature',
    readFirst: 'Know Before You Go: Site Access; Enclosure Ratings',
  ),
  VerticalRow(
    vertical: 'Healthcare and hospitals',
    triggers:
        'The full clinical stack: WMTS telemetry, medical-device EMC, RTLS '
        'grade, zero-tolerance roaming, four authorities, ICRA and ILSM during '
        'construction',
    readFirst: 'Healthcare Wi-Fi; Know Before You Go: Site Access',
  ),
  VerticalRow(
    vertical: 'Hospitality, stadiums, arenas',
    triggers:
        'Very-high-density design: capacity over coverage, tight RF cells, '
        'airtime fairness, under-seat and overhead AP patterns',
    readFirst: 'see the density note below',
  ),
  VerticalRow(
    vertical: 'Education, K-12 and higher-ed',
    triggers:
        'Coverage plus density plus 802.1X; background checks or '
        'fingerprinting; work scheduled around students',
    readFirst: 'Know Before You Go: Site Access',
  ),
  VerticalRow(
    vertical: 'Retail',
    triggers:
        'PCI DSS scope when Wi-Fi touches cardholder data; guest and payment '
        'segmentation',
    readFirst: 'see the PCI note below',
  ),
  VerticalRow(
    vertical: 'Data centers and telecom facilities',
    triggers:
        'Production Wi-Fi usually minimal; RF-hostile racks and containment; '
        'escort, NDA, and change-control access',
    readFirst:
        'Data Centers and Wi-Fi; Telecom Spaces; Know Before You Go: Site '
        'Access',
  ),
  VerticalRow(
    vertical: 'Maritime, ports, offshore',
    triggers:
        'Salt corrosion (NEMA 4X or high IP with an explicit corrosion spec); '
        'over-water rules; TWIC; possible offshore hazloc',
    readFirst: 'Know Before You Go: Site Access; Enclosure Ratings',
  ),
  VerticalRow(
    vertical: 'Correctional and government',
    triggers: 'Cleared access, escort, tool control, hardening',
    readFirst: 'Know Before You Go: Site Access',
  ),
];

/// The retail/PCI load-bearing facts, verbatim from the copy.
const List<String> kRetailPciFacts = <String>[
  'APs that do not carry cardholder data must be segmented from the Cardholder '
      'Data Environment.',
  'A guest SSID goes on its own VLAN, internet-only, firewalled off the '
      'payment VLAN.',
  'WEP and WPA-TKIP are prohibited, WPA2-PSK is inadequate for the payment '
      'environment, and WPA3-Enterprise with 802.1X is the recommended posture.',
  'VLANs alone are not sufficient segmentation, so the separation has to be '
      'tested.',
  'A wireless intrusion-detection capability plus at least quarterly rogue-AP '
      'scans are expected.',
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead.
const String kVerticalLead =
    'A plain-language index of the industries you quote, and what each one '
    'tends to trigger. It is not a NAICS code decoder. Nobody standing in a '
    'building thinks "this is NAICS 622110." You think "it\'s a hospital," '
    '"it\'s a distribution center," "it\'s a stadium." This entry maps the '
    'vertical you name to the other reference entries you should read before '
    'you quote it.';

/// The classification-codes framing paragraph, verbatim.
const String kVerticalCodesNote =
    'The classification codes (NAICS, SIC, GICS, ISIC, NACE) are real, but '
    'they are back-office systems built for government statistics and equity '
    'indexing, not for anyone deciding where an AP goes. Treat a code as a '
    'filing label a client hands you, never a design input. What matters on '
    'site is the cluster of realities a vertical carries, and this index '
    'points you to the entry that owns each one.';

/// The transition line into the two note-only verticals, verbatim.
const String kVerticalTwoNotes =
    'Two verticals have no home in another entry, so they carry a short note '
    'here.';

/// Lead-in to the retail/PCI facts, verbatim.
const String kRetailPciIntro =
    'When Wi-Fi touches cardholder data, it lands in PCI DSS scope, and that '
    'is a data-plane question, not an RF one. The load-bearing facts:';

/// The retail/PCI defer line, verbatim.
const String kRetailPciDefer =
    'Recognize you are in PCI scope, then defer the ruling to the client\'s '
    'Qualified Security Assessor.';

/// The very-high-density venues paragraph, verbatim.
const String kHighDensityNote =
    'In a stadium, arena, or large venue the design axis flips from coverage '
    'to capacity. You contain RF into small cells, fight co-channel contention '
    '(a lazy static channel plan can cost a large share of usable capacity), '
    'lean on airtime fairness and OFDMA, and place APs under seats or overhead '
    'rather than on distant walls. The seat count and the peak concurrent-user '
    'load drive the AP count, not the floor area.';

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kVerticalWlanCares =
    'The vertical you name in the first phone call tells you which reference '
    'entry to open before you quote. Miss the hazloc on an oil site, the ICRA '
    'gate on a hospital, or the PCI scope in retail, and the timeline and '
    'price you promised were wrong before you started. Use this index the '
    'other direction too. Pick the industry, see the cluster, read the entry '
    'that owns the detail.';

/// The defer footer (rendered as an info band). Verbatim.
const String kVerticalDeferNote =
    'This is a field reference, not code, design, or compliance guidance. '
    'Confirm every requirement with the client, the authority having '
    'jurisdiction, and the relevant assessor for the specific project. The '
    'Toolbox certifies nothing.';
