// Wi-Fi Standards & Industry Bodies - reference dataset.
//
// The organizations that CREATE, CERTIFY, and COORDINATE Wi-Fi (and the
// adjacent radio tech a Wi-Fi pro runs into). DISTINCT from the Regulatory
// Domains page, which lists the per-country radio REGULATORS (FCC, Ofcom,
// ACMA, the ETSI-aligned EU bloc). The teaching frame is the three-layer model:
//
//   * Standards body  - defines HOW the radio works (PHY/MAC/framing).
//   * Certification body - verifies products from different vendors INTEROPERATE.
//   * Regulator - sets the LEGAL channel/power rules per country.
//
// SOURCE OF TRUTH (verbatim, do NOT invent): the Pax-verified, cross-source
// brief at
//   Deliverables/2026-06-09-wifi-standards-bodies/RESEARCH-BRIEF.md
// Keith's build decisions, applied here:
//   * IEEE is ONE tile ("IEEE / 802.11 Working Group"), not split into WG +
//     IEEE-SA (brief offered the split as optional; Keith chose one tile).
//   * Ecma International is KEPT but marked CONTEXT-ONLY - its only Wi-Fi
//     touchpoint is NFC; it is not a Wi-Fi body.
//   * ETSI appears here as a STANDARDS body and is noted as also the EU's
//     referenced harmonizer. The national/legal spectrum rules are NOT restated
//     here - the screen cross-links to the Regulatory Domains page (SSOT).
//
// CONFIDENCE / VOLATILITY (GL-005): unlike the regulatory data, this set is
// STABLE - org names, roles, what they own, and official URLs do not drift. The
// only moving cell is "current generation = Wi-Fi 7 (802.11be)", date-stamped
// in the IEEE / Wi-Fi Alliance copy and in [kWifiBodiesSnapshotDate].
//
// LOGO KEY: each record's `logoKey` is `body-<abbrev-lowercased>` with runs of
// non-alphanumerics collapsed to a single hyphen, matched against bundled assets
// by WifiBodiesLogos (lib/data/wifi_bodies_logos.dart). Mack fetches the
// wordmarks in parallel; a missing asset degrades to a styled abbreviation
// badge (never a broken image). Trademark caution (per the brief): use the
// plain wordmark for editorial reference, never the "Wi-Fi CERTIFIED" seal.
//
// Glyph hygiene (GL-004): "Wi-Fi" never "WiFi"; "802.1X" never "802.1x"; ASCII
// hyphen-minus only, no em dash; US spelling.

/// The dated snapshot this dataset was verified against. The org-level facts
/// are stable; this stamps the one volatile cell ("current Wi-Fi generation").
const String kWifiBodiesSnapshotDate = '2026-06-09';

/// The three-layer model the page teaches. The grouping the brief asked for is
/// BY LAYER, not alphabetical, so each body declares the layer it belongs to.
enum BodyLayer {
  /// Defines how the radio works: the PHY, MAC, framing, modulation, and the
  /// protocols Wi-Fi carries above the link layer.
  standards,

  /// Verifies that products from different vendors interoperate, and brands the
  /// conformance (also the professional human-skills certification layer).
  certification,

  /// Coordinates radio spectrum globally, above every national regulator.
  spectrum,

  /// Wireless standards / certification alliances BEYOND Wi-Fi that a WLAN pro
  /// increasingly meets - non-Wi-Fi radios (IoT mesh, smart-home, LPWAN). These
  /// are standards/certification-layer bodies, NOT regulators; they sit in their
  /// own sub-group so they never blur into the 802.11 story.
  iotAdjacent,
}

/// Display metadata for a [BodyLayer] section header. Title plus a one-line
/// gloss that restates the layer's job so the teaching lands above the tiles.
class BodyLayerInfo {
  const BodyLayerInfo({required this.title, required this.gloss});

  final String title;
  final String gloss;

  static const Map<BodyLayer, BodyLayerInfo> all = <BodyLayer, BodyLayerInfo>{
    BodyLayer.standards: BodyLayerInfo(
      title: 'Defines the radio',
      gloss: 'Standards bodies. They define how the radio actually works: the '
          'PHY, the MAC, framing, and the protocols Wi-Fi carries.',
    ),
    BodyLayer.certification: BodyLayerInfo(
      title: 'Certifies and brands',
      gloss: 'Certification bodies. They verify that products from different '
          'vendors interoperate, and they own the brands and the credentials.',
    ),
    BodyLayer.spectrum: BodyLayerInfo(
      title: 'Coordinates spectrum globally',
      gloss: 'Sits above every national regulator. Its decisions cascade into '
          'each country\'s legal channel and power rules.',
    ),
    BodyLayer.iotAdjacent: BodyLayerInfo(
      title: 'IoT / adjacent wireless',
      gloss: 'Wireless standards beyond Wi-Fi that a WLAN pro increasingly '
          'meets - Matter rides IP straight over the WLAN.',
    ),
  };

  static BodyLayerInfo of(BodyLayer layer) => all[layer]!;
}

/// One standards / industry body record. Every field is typed and non-null; an
/// absent value would be an empty string, never `null`, so the tile renders
/// consistently.
class WifiBody {
  const WifiBody({
    required this.name,
    required this.abbreviation,
    required this.layer,
    required this.roleType,
    required this.owns,
    required this.whyCare,
    required this.websiteUrl,
    this.contextOnly = false,
  });

  /// The body's full name, e.g. `Wi-Fi Alliance`. Primary search key and the
  /// tile's headline.
  final String name;

  /// The abbreviation rendered in DM Mono as an identifier, e.g. `WFA`, `IEEE`.
  /// Also the seed for [logoKey] and the abbreviation badge.
  final String abbreviation;

  /// The three-layer bucket this body sits in. Drives the on-screen grouping.
  final BodyLayer layer;

  /// The body's role / type, e.g. `Certification + branding`. Short, scannable.
  final String roleType;

  /// What the body actually OWNS or produces - the concrete standard, program,
  /// trademark, or specification.
  final String owns;

  /// One line on why a Wi-Fi pro cares. The teaching payload of the tile.
  final String whyCare;

  /// The official URL - the tappable `url_launcher` target. HTTPS, opened in the
  /// system browser (GL-008 browser hand-off, not an in-app fetch). Stable.
  final String websiteUrl;

  /// `true` for a body included for context that is NOT a Wi-Fi body (Ecma -
  /// NFC is its only wireless touchpoint). The tile flags this so it never reads
  /// as load-bearing for Wi-Fi.
  final bool contextOnly;

  /// The asset key for this body's logo: `body-<abbrev>` lowercased with runs of
  /// non-alphanumerics collapsed to a single hyphen. Matched against bundled
  /// assets by [WifiBodiesLogos]; a missing asset degrades to a badge.
  String get logoKey {
    final String slug = abbreviation
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'body-$slug';
  }

  /// Lower-cased haystack for the search-as-you-type field: name + abbreviation
  /// + role + what-they-own + why-care. Lets a search hit "OpenRoaming",
  /// "trademark", "RFC", "cellular", etc., not just the org name.
  String get searchHaystack =>
      '$name $abbreviation $roleType $owns $whyCare'.toLowerCase();
}

/// The bodies, grouped by layer in [BodyLayer] declaration order, then by the
/// brief's build order within each layer. Ported from the Pax-verified brief
/// MAIN TABLE with Keith's decisions applied (IEEE = one tile; Ecma context-
/// only; ETSI here as a standards body).
const List<WifiBody> kWifiBodies = <WifiBody>[
  // ---- Defines the radio (standards) ----------------------------------------
  WifiBody(
    name: 'IEEE / 802.11 Working Group',
    abbreviation: 'IEEE',
    layer: BodyLayer.standards,
    roleType: 'Standards development',
    owns: 'The actual Wi-Fi standard. "IEEE Std 802.11, Part 11: Wireless LAN '
        'MAC and PHY Specifications" and every amendment (11n / ac / ax / be). '
        'The IEEE Standards Association ratifies and publishes it.',
    whyCare: 'This is where Wi-Fi is genuinely defined. 802.11be is Wi-Fi 7, '
        '802.11ax is Wi-Fi 6. The amendment letter is the real name; the '
        '"Wi-Fi 7" label is Wi-Fi Alliance marketing. Current generation = '
        'Wi-Fi 7 (802.11be) as of $kWifiBodiesSnapshotDate; Wi-Fi 8 (802.11bn) '
        'is in development.',
    websiteUrl: 'https://www.ieee802.org/11/',
  ),
  WifiBody(
    name: 'European Telecommunications Standards Institute',
    abbreviation: 'ETSI',
    layer: BodyLayer.standards,
    roleType: 'Standards development (EU-recognized SDO)',
    owns: 'Harmonised European Standards (EN 300 328 for 2.4 GHz, EN 301 893 '
        'for 5 GHz, EN 303 687 for 6 GHz) that underpin RED / CE compliance. '
        'A 3GPP Organizational Partner.',
    whyCare: 'Dual role. Here it is a standards developer. It is also the EU\'s '
        'referenced harmonizer: comply with the EN and you get presumption of '
        'conformity for CE marking. ETSI shapes EU radio rules but is NOT the '
        'legal regulator; the national authority is. See Regulatory Domains for '
        'the legal per-country rules.',
    websiteUrl: 'https://www.etsi.org',
  ),
  WifiBody(
    name: '3rd Generation Partnership Project',
    abbreviation: '3GPP',
    layer: BodyLayer.standards,
    roleType: 'Standards development (cellular)',
    owns: 'The cellular standards: GSM / UMTS / LTE / 5G NR / 5G-Advanced. A '
        'partnership of seven SDOs (ARIB, ATIS, CCSA, ETSI, TSDSI, TTA, TTC).',
    whyCare: 'Context and convergence. 3GPP specs define non-3GPP-access '
        'interworking: how Wi-Fi offload, Wi-Fi / cellular handoff, and '
        'OpenRoaming\'s cellular side actually work.',
    websiteUrl: 'https://www.3gpp.org',
  ),
  WifiBody(
    name: 'Internet Engineering Task Force',
    abbreviation: 'IETF',
    layer: BodyLayer.standards,
    roleType: 'Standards development (open, no formal membership)',
    owns: 'The IP / transport / application protocols Wi-Fi carries: IP, TCP, '
        'UDP, QUIC, TLS, DNS, DHCP, RADIUS - published as RFCs. Runs on "rough '
        'consensus and running code."',
    whyCare: 'Wi-Fi is just the link layer. Everything above it - addressing, '
        'DHCP, TLS, RADIUS auth for 802.1X enterprise Wi-Fi, captive portals, '
        'Passpoint auth - rides IETF protocols.',
    websiteUrl: 'https://www.ietf.org',
  ),
  WifiBody(
    name: 'Bluetooth Special Interest Group',
    abbreviation: 'Bluetooth SIG',
    layer: BodyLayer.standards,
    roleType: 'Standards development + certification + trade association',
    owns: 'The Bluetooth core specification, the Bluetooth qualification '
        '(certification) program, and the Bluetooth trademark licensing.',
    whyCare: 'Adjacent PAN tech sharing the 2.4 GHz band - a coexistence and '
        'interference factor on every Wi-Fi deployment. Also an instructive '
        'parallel: one body that does BOTH the standard and the cert, unlike '
        'Wi-Fi\'s IEEE / Wi-Fi Alliance split.',
    websiteUrl: 'https://www.bluetooth.com',
  ),
  WifiBody(
    name: 'Ecma International',
    abbreviation: 'Ecma',
    layer: BodyLayer.standards,
    roleType: 'Standards development (general ICT)',
    owns: 'ECMAScript (JavaScript), Office Open XML, Dart - and, relevant here, '
        'NFC standards (with ETSI / ISO) and close-proximity data-transfer '
        'specs.',
    whyCare: 'Context only - adjacent, NOT a Wi-Fi body. NFC is its single '
        'wireless touchpoint. Shown to round out the ICT-standards landscape.',
    websiteUrl: 'https://ecma-international.org',
    contextOnly: true,
  ),

  // ---- Certifies and brands (interoperability + people) ---------------------
  WifiBody(
    name: 'Wi-Fi Alliance',
    abbreviation: 'WFA',
    layer: BodyLayer.certification,
    roleType: 'Certification + industry advocacy + branding',
    owns: 'The Wi-Fi CERTIFIED interoperability program; the "Wi-Fi" '
        'trademark; the consumer generation names (Wi-Fi 4 / 5 / 6 / 6E / 7); '
        'programs like WPA3, Passpoint, and EasyMesh.',
    whyCare: 'Owns the brand and the interop seal - it does NOT write 802.11. '
        'The Wi-Fi 6 / 7 names you sell to clients come from here, not from '
        'IEEE. "Wi-Fi" is a Wi-Fi Alliance trademark, not an acronym, and does '
        'NOT stand for "Wireless Fidelity."',
    websiteUrl: 'https://www.wi-fi.org',
  ),
  WifiBody(
    name: 'Wireless Broadband Alliance',
    abbreviation: 'WBA',
    layer: BodyLayer.certification,
    roleType: 'Industry advocacy + guidelines + certification',
    owns: 'OpenRoaming (the global secure Wi-Fi roaming federation) and the '
        'WRIX roaming-exchange standards; Wi-Fi industry trials, guidelines, '
        'and advocacy. Founded 2003.',
    whyCare: 'OpenRoaming is the "connect once, roam everywhere" framework '
        'bridging Wi-Fi and cellular identities. The body driving carrier-grade '
        'public Wi-Fi.',
    websiteUrl: 'https://wballiance.com',
  ),
  WifiBody(
    name: 'CWNP (Certified Wireless Network Professional)',
    abbreviation: 'CWNP',
    layer: BodyLayer.certification,
    roleType: 'Professional certification (vendor-neutral)',
    owns: 'The vendor-neutral enterprise Wi-Fi certification track: CWNA, then '
        'CWAP / CWDP / CWSP / CWNT, up to CWNE (plus newer Wireless IoT '
        'credentials). Tracks as of 2026; CWNP periodically revises them. '
        'Founded 1999.',
    whyCare: 'The credential that validates real 802.11 skill across any '
        'vendor\'s gear. The professional, human-skills layer beneath all the '
        'org acronyms - it certifies people, not products.',
    websiteUrl: 'https://www.cwnp.com',
  ),

  // ---- Coordinates spectrum globally ----------------------------------------
  WifiBody(
    name: 'International Telecommunication Union, Radiocommunication Sector',
    abbreviation: 'ITU-R',
    layer: BodyLayer.spectrum,
    roleType: 'Global spectrum coordination (UN agency sector)',
    owns: 'Global radio-spectrum allocation: the Radio Regulations, the World '
        'Radiocommunication Conferences (WRC), and the IMT framework '
        '(IMT-2020 = 5G, IMT-2030 = 6G). Maintains the Master International '
        'Frequency Register.',
    whyCare: 'Sits above every national regulator. WRC decisions - for example '
        'whether 6 GHz goes to Wi-Fi or to IMT / 5G - cascade into the FCC, '
        'Ofcom, and ETSI-aligned rules. See Regulatory Domains for how those '
        'land per country.',
    websiteUrl: 'https://www.itu.int/en/ITU-R/',
  ),

  // ---- IoT / adjacent wireless (standards/certification, NOT regulators) -----
  // Keith: the WLAN Pros audience does "all things wireless," IoT included.
  // These three govern non-Wi-Fi radios; they sit at the standards/certification
  // layer (never the regulator layer) and group separately from the 802.11
  // story. Logo keys resolve from the abbreviation: Wi-SUN -> body-wi-sun,
  // CSA -> body-csa, LoRa Alliance -> body-lora-alliance.
  WifiBody(
    name: 'Wi-SUN Alliance',
    abbreviation: 'Wi-SUN',
    layer: BodyLayer.iotAdjacent,
    roleType: 'Industry alliance + certification',
    owns: 'The Wi-SUN FAN (Field Area Network) specification and its '
        'certification program - an IPv6 sub-GHz wireless mesh built on '
        'IEEE 802.15.4g (PHY) / 802.15.4e (MAC), the IEEE 802.15.4-SUN family. '
        'Current spec FAN 1.1. Also issues cybersecurity certificates.',
    whyCare: 'The dominant standard for utility-scale outdoor IoT mesh - smart '
        'metering (AMI), distribution automation, smart streetlighting, smart '
        'cities. The sub-GHz, long-range, many-hop counterpart to the Wi-Fi you '
        'design indoors.',
    websiteUrl: 'https://wi-sun.org',
  ),
  WifiBody(
    name: 'Connectivity Standards Alliance',
    abbreviation: 'CSA',
    layer: BodyLayer.iotAdjacent,
    roleType: 'Standards development + certification',
    owns: 'Owns and maintains BOTH Zigbee (its founding 802.15.4-based mesh) '
        'AND Matter (the IP-based, royalty-free smart-home interoperability '
        'standard, backed by Apple / Google / Amazon / Samsung). Runs the '
        'certification programs for both. Formerly the Zigbee Alliance, renamed '
        '11 May 2021.',
    whyCare: 'The body behind most smart-home radios your clients already run. '
        'Matter rides IP over Wi-Fi and Thread, so it lands directly on the '
        'WLAN - Matter-over-Wi-Fi traffic is on your network whether you '
        'planned for it or not.',
    websiteUrl: 'https://csa-iot.org',
  ),
  WifiBody(
    name: 'LoRa Alliance',
    abbreviation: 'LoRa Alliance',
    layer: BodyLayer.iotAdjacent,
    roleType: 'Industry alliance + certification',
    owns: 'Develops, maintains, and certifies the LoRaWAN standard - the open '
        'LPWAN MAC-layer / network protocol. LoRaWAN runs OVER the LoRa '
        'physical layer, which is the proprietary spread-spectrum PHY owned by '
        'Semtech (Semtech is a member, not the standards body).',
    whyCare: 'The carrier-grade, kilometers-range, battery-decade LPWAN for '
        'sensors - a different problem than Wi-Fi solves, often deployed '
        'alongside it. Know the split: LoRa = Semtech\'s PHY / chip; '
        'LoRaWAN = the LoRa Alliance\'s open standard.',
    websiteUrl: 'https://lora-alliance.org',
  ),
];
