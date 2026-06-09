// Wi-Fi Regulatory Domains — per-jurisdiction reference dataset.
//
// A jurisdiction-level directory of the radio regulator that governs Wi-Fi in
// each market: the regulator's full name + abbreviation, its official website,
// the governing regulation / standard, and a 2.4 / 5 / 6 GHz band-and-power
// note. The richer companion to the older region-level FCC / ETSI / ITU summary
// (which this page supersedes).
//
// SOURCE OF TRUTH (verbatim, do NOT invent): the Pax-verified, cross-source
// snapshot at
//   Deliverables/2026-06-08-regulatory-domains-db/REGULATORY-DOMAINS-DATA.md
// (MAIN TABLE rows 1-43, the DISTINCT REGULATORS SUMMARY, and the abbreviation-
// collision warning). This file is a DATED SNAPSHOT, not change-tracked.
//
// CONFIDENCE / VOLATILITY (per the brief and GL-005): the regulator name,
// abbreviation, governing-document citation, and website URL are STABLE and
// cross-source verified. The band / power note is VOLATILE — every band cell is
// implicitly "as of [kRegulatorySnapshotDate], verify with the regulator". The
// screen carries a persistent snapshot banner stating exactly that; never
// present a band note as a settled constant.
//
// ABBREVIATION COLLISIONS (brief, "Abbreviation-collision warning"): "NCC" =
// Taiwan, Nigeria (and the Korea/Philippines families); "TRA" = Oman, Bahrain;
// "CRA" = Qatar. Where an abbreviation collides across jurisdictions the screen
// appends the jurisdiction to the badge/label so it is unambiguous — the data
// here carries the raw abbreviation and the jurisdiction separately so the UI,
// the logo key, and the search index all stay correct.
//
// LOGO KEY: each record's `logoKey` is `regulator-<abbrev-lowercased>` with
// non-alphanumerics collapsed to single hyphens, matched against bundled assets
// by RegulatoryLogos (lib/data/regulatory_logos.dart). Where the abbreviation
// collides, the key is suffixed with a short jurisdiction slug so two regulators
// that share an abbreviation (Oman/Bahrain "TRA") never collide on one asset.
//
// Glyph hygiene (GL-004): "Wi-Fi" never "WiFi"; "802.1X" never "802.1x"; ASCII
// hyphen-minus only, no em dash; US spelling. Regulator NAMES are reproduced as
// the regulator spells them (e.g. "Agencia" / "Telecomunicaciones") — proper
// nouns are not Americanized.

/// The dated snapshot this dataset was verified against. Surfaced verbatim in
/// the screen's persistent snapshot banner and the copy payload. Bump only when
/// the dataset is re-verified against the regulators.
const String kRegulatorySnapshotDate = '2026-06-08';

/// One jurisdiction's Wi-Fi regulatory record. Every field is typed and
/// non-null; an absent governing-doc or note would be an empty string, never
/// `null`, so the row renders consistently.
class RegulatoryDomain {
  const RegulatoryDomain({
    required this.jurisdiction,
    required this.ituRegion,
    required this.regulatorName,
    required this.abbreviation,
    required this.websiteUrl,
    required this.governingDocs,
    required this.bandNotes,
    this.abbreviationCollides = false,
    this.logoKeySuffix = '',
  });

  /// The market this record governs, e.g. `United States`, `Taiwan`. Primary
  /// search key and the row's headline.
  final String jurisdiction;

  /// ITU region number (1, 2, or 3) as a string for display. Stable.
  final String ituRegion;

  /// The regulator's full legal name, e.g.
  /// `Federal Communications Commission`. Stable, cross-source verified.
  final String regulatorName;

  /// The regulator's abbreviation, e.g. `FCC`, `Ofcom`, `NCC`. Rendered in
  /// DM Mono as an identifier. Stable.
  final String abbreviation;

  /// The official MAIN regulator URL — the tappable `url_launcher` target. HTTPS
  /// (opened in the system browser; GL-008 browser hand-off, not an in-app
  /// fetch). Stable.
  final String websiteUrl;

  /// The governing regulation / standard citation, e.g.
  /// `47 CFR 15.247; 15.407`. Stable.
  final String governingDocs;

  /// The 2.4 / 5 / 6 GHz band + power note. VOLATILE — a snapshot to verify
  /// against the regulator, never a settled constant (see file header).
  final String bandNotes;

  /// `true` when this regulator's abbreviation is shared by another jurisdiction
  /// in this dataset (NCC, TRA, CRA per the brief's collision warning). The
  /// screen appends the jurisdiction to the badge/label when this is set so the
  /// abbreviation is unambiguous.
  final bool abbreviationCollides;

  /// Optional extra slug appended to the logo key to disambiguate a colliding
  /// abbreviation's asset (e.g. `om` / `bh` for the two "TRA" regulators). Empty
  /// for non-colliding records.
  final String logoKeySuffix;

  /// The asset key for this regulator's logo: `regulator-<abbrev>` lowercased
  /// with runs of non-alphanumerics collapsed to a single hyphen, plus the
  /// disambiguation suffix where present. Matched against bundled assets by
  /// [RegulatoryLogos]; a missing asset degrades to a styled abbreviation badge.
  String get logoKey {
    final String slug = abbreviation
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return logoKeySuffix.isEmpty
        ? 'regulator-$slug'
        : 'regulator-$slug-$logoKeySuffix';
  }

  /// Lower-cased haystack for the search-as-you-type field: jurisdiction +
  /// regulator name + abbreviation + governing docs. Band notes are intentionally
  /// excluded so a volatile cell never anchors a search hit.
  String get searchHaystack =>
      '$jurisdiction $regulatorName $abbreviation $governingDocs'.toLowerCase();
}

/// The 43 jurisdiction records, ported verbatim from the snapshot's MAIN TABLE
/// (rows 1-43). Order matches the brief. The band note compresses the brief's
/// 2.4 / 5 / 6 GHz columns into one volatile sentence per row.
const List<RegulatoryDomain> kRegulatoryDomains = <RegulatoryDomain>[
  RegulatoryDomain(
    jurisdiction: 'United States',
    ituRegion: '2',
    regulatorName: 'Federal Communications Commission',
    abbreviation: 'FCC',
    websiteUrl: 'https://www.fcc.gov',
    governingDocs: '47 CFR 15.247 (2.4 / 5.8 ISM); 15.407 (UNII incl. 6 GHz)',
    bandNotes: '2.4 GHz ch 1-11. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz FULL (5925-7125): LPI + VLP unlicensed, SP via AFC. Defines the '
        'FCC-aligned reference family.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Canada',
    ituRegion: '2',
    regulatorName: 'Innovation, Science and Economic Development Canada',
    abbreviation: 'ISED',
    websiteUrl: 'https://ised-isde.canada.ca',
    governingDocs: 'RSS-247 (2.4 / 5 GHz LE-LAN); RSS-248 Issue 3 (6 GHz RLAN)',
    bandNotes: '2.4 GHz ch 1-11. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz FULL (5925-7125): LPI + VLP, SP via AFC. RSS-248 Issue 3 '
        '(2024-10-11) supersedes Issue 2.',
  ),
  RegulatoryDomain(
    jurisdiction: 'European Union (CEPT/ETSI bloc)',
    ituRegion: '1',
    regulatorName: 'European Telecommunications Standards Institute',
    abbreviation: 'ETSI',
    websiteUrl: 'https://www.etsi.org',
    governingDocs: 'EN 300 328; EN 301 893; EN 303 687; ECC Dec (20)01; '
        'CID (EU) 2021/1067',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz 5.15-5.35 + 5.47-5.725 (DFS). '
        '6 GHz LOWER (5945-6425): LPI + VLP; upper band under study. Each '
        'member-state NRA is the legal authority. Defines the ETSI-aligned '
        'family.',
  ),
  RegulatoryDomain(
    jurisdiction: 'United Kingdom',
    ituRegion: '1',
    regulatorName: 'Office of Communications',
    abbreviation: 'Ofcom',
    websiteUrl: 'https://www.ofcom.org.uk',
    governingDocs: 'IR 2030 (UK Interface Requirements); 6 GHz statements '
        '2024-2026',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz as EU (DFS). 6 GHz LOWER expanding: '
        'LPI (250 mW) + VLP (25 mW); 2026 Ofcom authorizing SP via AFC + upper '
        '6 GHz sharing. UK moving ahead of the EU; verify in-force date.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Australia',
    ituRegion: '3',
    regulatorName: 'Australian Communications and Media Authority',
    abbreviation: 'ACMA',
    websiteUrl: 'https://www.acma.gov.au',
    governingDocs: 'Radiocommunications (Low Interference Potential Devices) '
        'Class Licence 2015 (LIPD)',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425): LPI (250 mW) + VLP (25 mW); upper band AFC '
        'under consideration (contested with IMT).',
  ),
  RegulatoryDomain(
    jurisdiction: 'New Zealand',
    ituRegion: '3',
    regulatorName: 'Radio Spectrum Management (MBIE)',
    abbreviation: 'RSM',
    websiteUrl: 'https://www.rsm.govt.nz',
    governingDocs: 'General User Radio Licence (GURL) for Short Range Devices',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425): LPI + VLP.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Japan',
    ituRegion: '3',
    regulatorName: 'Ministry of Internal Affairs and Communications '
        '(conformity via TELEC; standards via ARIB)',
    abbreviation: 'MIC',
    websiteUrl: 'https://www.tele.soumu.go.jp/e/',
    governingDocs: 'ARIB STD-T66 (2.4 GHz); STD-T71 (5 GHz); STD-T109 (6 GHz)',
    bandNotes: '2.4 GHz ch 1-13 + ch 14 (DSSS / 802.11b legacy only, '
        '2471-2497). 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). 6 GHz LOWER '
        '(5925-6425): LPI + VLP. Ch 14 is Japan-only.',
  ),
  RegulatoryDomain(
    jurisdiction: 'South Korea',
    ituRegion: '3',
    regulatorName: 'Korea Communications Commission (spectrum via RRA)',
    abbreviation: 'KCC',
    websiteUrl: 'https://eng.kcc.go.kr',
    governingDocs: 'KC certification; RRA radio equipment notifications',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz FULL (5925-7125). One of the few full-band markets in Asia.',
  ),
  RegulatoryDomain(
    jurisdiction: 'China (mainland)',
    ituRegion: '3',
    regulatorName: 'Ministry of Industry and Information Technology '
        '(type-approval via SRRC)',
    abbreviation: 'MIIT',
    websiteUrl: 'https://www.miit.gov.cn',
    governingDocs: 'SRRC type approval; MIIT radio regulations',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz narrower (5.15-5.35, 5.725-5.85). '
        '6 GHz NOT PERMITTED for Wi-Fi (5925-7125 designated for IMT, 2023); '
        'China-specific firmware required.',
  ),
  RegulatoryDomain(
    jurisdiction: 'India',
    ituRegion: '3',
    regulatorName: 'Department of Telecommunications '
        '(spectrum via WPC; conformity via TEC)',
    abbreviation: 'DoT',
    websiteUrl: 'https://dot.gov.in',
    governingDocs: 'WPC ETA / ETA-SD; 6 GHz delicensing rules (2026)',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425) delicensed for indoor Wi-Fi 2026-01; upper '
        'band reserved for IMT. Verify indoor-only conditions.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Singapore',
    ituRegion: '3',
    regulatorName: 'Info-communications Media Development Authority',
    abbreviation: 'IMDA',
    websiteUrl: 'https://www.imda.gov.sg',
    governingDocs: 'IMDA equipment registration; technical specs (TS SRD)',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Hong Kong',
    ituRegion: '3',
    regulatorName: 'Office of the Communications Authority',
    abbreviation: 'OFCA',
    websiteUrl: 'https://www.ofca.gov.hk',
    governingDocs: 'OFCA HKCA specifications',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Taiwan',
    ituRegion: '3',
    regulatorName: 'National Communications Commission',
    abbreviation: 'NCC',
    abbreviationCollides: true,
    logoKeySuffix: 'tw',
    websiteUrl: 'https://www.ncc.gov.tw',
    governingDocs: 'NCC type approval; LP0002 low-power device regs',
    bandNotes: '2.4 GHz ch 1-11 (FCC-leaning). 5 GHz UNII-1/2A/2C/3 (DFS on '
        '2A/2C). 6 GHz LOWER (5925-6425).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Brazil',
    ituRegion: '2',
    regulatorName: 'Agencia Nacional de Telecomunicacoes',
    abbreviation: 'ANATEL',
    websiteUrl: 'https://www.gov.br/anatel',
    governingDocs: 'Ato / Resolucao on restricted-radiation equipment; '
        '6 GHz acts',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz FULL (5925-7125) in force; a 2025 consultation may narrow toward '
        'the EU model. Verify.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Mexico',
    ituRegion: '2',
    regulatorName: 'Instituto Federal de Telecomunicaciones',
    abbreviation: 'IFT',
    websiteUrl: 'https://www.ift.org.mx',
    governingDocs: 'IFT Disposicion Tecnica (homologacion)',
    bandNotes: '2.4 GHz ch 1-11. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425); full band under consideration.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Saudi Arabia',
    ituRegion: '1',
    regulatorName: 'Communications, Space & Technology Commission',
    abbreviation: 'CST',
    websiteUrl: 'https://www.cst.gov.sa',
    governingDocs: 'CST technical specifications / RLAN regulations',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz FULL (5925-7125). Early and aggressive full-band adopter.',
  ),
  RegulatoryDomain(
    jurisdiction: 'United Arab Emirates',
    ituRegion: '1',
    regulatorName: 'Telecommunications and Digital Government Regulatory '
        'Authority',
    abbreviation: 'TDRA',
    websiteUrl: 'https://tdra.gov.ae',
    governingDocs: 'TDRA equipment type approval; SRD regs',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425). (Formerly TRA UAE.)',
  ),
  RegulatoryDomain(
    jurisdiction: 'Qatar',
    ituRegion: '1',
    regulatorName: 'Communications Regulatory Authority',
    abbreviation: 'CRA',
    abbreviationCollides: true,
    websiteUrl: 'https://www.cra.gov.qa',
    governingDocs: 'CRA SRD / type-approval regs',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425); upper band under consideration.',
  ),
  RegulatoryDomain(
    jurisdiction: 'South Africa',
    ituRegion: '1',
    regulatorName: 'Independent Communications Authority of South Africa',
    abbreviation: 'ICASA',
    websiteUrl: 'https://www.icasa.org.za',
    governingDocs: 'Radio Frequency Spectrum Regulations; type approval',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Israel',
    ituRegion: '1',
    regulatorName: 'Ministry of Communications',
    abbreviation: 'MoC',
    websiteUrl:
        'https://www.gov.il/en/departments/ministry_of_communications',
    governingDocs: 'MoC frequency allocation / type approval',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Switzerland',
    ituRegion: '1',
    regulatorName: 'Federal Office of Communications (BAKOM)',
    // BAKOM (German), not OFCOM: Switzerland's regulator is OFCOM in French but
    // is known internationally as BAKOM to avoid colliding with the UK's Ofcom
    // (which also shared the logo key). Keith correction 2026-06-09.
    abbreviation: 'BAKOM',
    websiteUrl: 'https://www.bakom.admin.ch',
    governingDocs: 'RIR (Radio Interface Regulations); follows CEPT/ETSI',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz EN 301 893 (DFS as EU). 6 GHz LOWER '
        '(5945-6425). Non-EU but CEPT/ETSI-harmonized.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Norway',
    ituRegion: '1',
    regulatorName: 'Norwegian Communications Authority',
    abbreviation: 'Nkom',
    websiteUrl: 'https://www.nkom.no',
    governingDocs: 'Follows CEPT/ETSI; national frequency plan',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz EN 301 893 (DFS as EU). 6 GHz LOWER '
        '(5945-6425). EEA/CEPT-harmonized.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Iceland',
    ituRegion: '1',
    regulatorName: 'Electronic Communications Office of Iceland '
        '(Fjarskiptastofa)',
    abbreviation: 'ECOI',
    websiteUrl: 'https://www.fjarskiptastofa.is',
    governingDocs: 'Follows CEPT/ETSI',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz EN 301 893 (DFS as EU). 6 GHz LOWER '
        '(5945-6425). EEA/CEPT-harmonized.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Russian Federation',
    ituRegion: '1',
    regulatorName: 'Federal Service for Supervision of Communications '
        '(spectrum via SCRF / GKRCh)',
    abbreviation: 'Roskomnadzor',
    websiteUrl: 'https://rkn.gov.ru',
    governingDocs: 'GKRCh decisions; national frequency table',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz national allocation (narrower; verify). '
        '6 GHz LOWER (5925-6425) per WFA list. Low confidence on enforcement; '
        'sanctions complicate device availability. Verify.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Turkey',
    ituRegion: '1',
    regulatorName: 'Information and Communication Technologies Authority',
    abbreviation: 'BTK',
    websiteUrl: 'https://www.btk.gov.tr',
    governingDocs: 'Follows CEPT/ETSI broadly',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz EN 301 893 (DFS as EU). 6 GHz LOWER '
        '(5925-6425) adopted / in progress. Verify.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Malaysia',
    ituRegion: '3',
    regulatorName: 'Malaysian Communications and Multimedia Commission',
    abbreviation: 'MCMC',
    websiteUrl: 'https://www.mcmc.gov.my',
    governingDocs: 'MCMC class assignment / SRD specs',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Thailand',
    ituRegion: '3',
    regulatorName: 'National Broadcasting and Telecommunications Commission',
    abbreviation: 'NBTC',
    websiteUrl: 'https://www.nbtc.go.th',
    governingDocs: 'NBTC SRD regulations',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Indonesia',
    ituRegion: '3',
    regulatorName: 'Ministry of Communication and Digital (SDPPI directorate)',
    abbreviation: 'Komdigi',
    websiteUrl: 'https://www.komdigi.go.id',
    governingDocs: 'SDPPI type approval; national frequency plan',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425). Ministry renamed 2024 (formerly Kominfo); '
        'verify current domain.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Philippines',
    ituRegion: '3',
    regulatorName: 'National Telecommunications Commission',
    abbreviation: 'NTC',
    abbreviationCollides: true,
    logoKeySuffix: 'ph',
    websiteUrl: 'https://ntc.gov.ph',
    governingDocs: 'NTC SRD memorandum circulars',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Vietnam',
    ituRegion: '3',
    regulatorName: 'Authority of Radio Frequency Management (MIC)',
    abbreviation: 'ARFM',
    websiteUrl: 'https://www.mic.gov.vn',
    governingDocs: 'National frequency plan; type approval',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Argentina',
    ituRegion: '2',
    regulatorName: 'Ente Nacional de Comunicaciones',
    abbreviation: 'ENACOM',
    websiteUrl: 'https://www.enacom.gob.ar',
    governingDocs: 'ENACOM Resolucion on RLAN / SRD',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz FULL (5925-7125) per WFA; verify scope.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Chile',
    ituRegion: '2',
    regulatorName: 'Subsecretaria de Telecomunicaciones',
    abbreviation: 'SUBTEL',
    websiteUrl: 'https://www.subtel.gob.cl',
    governingDocs: 'SUBTEL Resolucion on RLAN',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Colombia',
    ituRegion: '2',
    regulatorName: 'Agencia Nacional del Espectro (MinTIC)',
    abbreviation: 'ANE',
    websiteUrl: 'https://www.ane.gov.co',
    governingDocs: 'ANE / MinTIC spectrum resolutions',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz FULL (5925-7125) per WFA.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Peru',
    ituRegion: '2',
    regulatorName: 'Ministerio de Transportes y Comunicaciones',
    abbreviation: 'MTC',
    websiteUrl: 'https://www.gob.pe/mtc',
    governingDocs: 'MTC spectrum / homologacion regs',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz FULL (5925-7125).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Egypt',
    ituRegion: '1',
    regulatorName: 'National Telecom Regulatory Authority',
    abbreviation: 'NTRA',
    websiteUrl: 'https://www.tra.gov.eg',
    governingDocs: 'NTRA type approval / SRD',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425) / considering. Verify.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Kenya',
    ituRegion: '1',
    regulatorName: 'Communications Authority of Kenya',
    abbreviation: 'CA',
    websiteUrl: 'https://www.ca.go.ke',
    governingDocs: 'CA type approval / SRD',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Nigeria',
    ituRegion: '1',
    regulatorName: 'Nigerian Communications Commission',
    abbreviation: 'NCC',
    abbreviationCollides: true,
    logoKeySuffix: 'ng',
    websiteUrl: 'https://www.ncc.gov.ng',
    governingDocs: 'NCC type approval / national frequency plan',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425). Shares the NCC abbreviation with Taiwan.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Morocco',
    ituRegion: '1',
    regulatorName: 'Agence Nationale de Reglementation des '
        'Telecommunications',
    abbreviation: 'ANRT',
    websiteUrl: 'https://www.anrt.ma',
    governingDocs: 'ANRT type approval / SRD',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Kazakhstan',
    ituRegion: '3',
    regulatorName: 'Ministry of Digital Development (MDDIAI) / spectrum '
        'authority',
    abbreviation: 'MDDIAI',
    websiteUrl: 'https://www.gov.kz/memleket/entities/mdai',
    governingDocs: 'National frequency plan',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz national allocation. 6 GHz FULL '
        '(5925-7125) per WFA. Verify regulator entity name (machinery-of-'
        'government changes).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Jordan',
    ituRegion: '1',
    regulatorName: 'Telecommunications Regulatory Commission',
    abbreviation: 'TRC',
    websiteUrl: 'https://trc.gov.jo',
    governingDocs: 'TRC SRD / type approval',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425).',
  ),
  RegulatoryDomain(
    jurisdiction: 'Oman',
    ituRegion: '1',
    regulatorName: 'Telecommunications Regulatory Authority',
    abbreviation: 'TRA',
    abbreviationCollides: true,
    logoKeySuffix: 'om',
    websiteUrl: 'https://tra.gov.om',
    governingDocs: 'TRA type approval / SRD',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425) / considering. Shares the TRA abbreviation '
        'with Bahrain.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Bahrain',
    ituRegion: '1',
    regulatorName: 'Telecommunications Regulatory Authority',
    abbreviation: 'TRA',
    abbreviationCollides: true,
    logoKeySuffix: 'bh',
    websiteUrl: 'https://www.tra.org.bh',
    governingDocs: 'TRA type approval / SRD',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425). Shares the TRA abbreviation with Oman.',
  ),
  RegulatoryDomain(
    jurisdiction: 'Kuwait',
    ituRegion: '1',
    regulatorName: 'Communication and Information Technology Regulatory '
        'Authority',
    abbreviation: 'CITRA',
    websiteUrl: 'https://www.citra.gov.kw',
    governingDocs: 'CITRA SRD / type approval',
    bandNotes: '2.4 GHz ch 1-13. 5 GHz UNII-1/2A/2C/3 (DFS on 2A/2C). '
        '6 GHz LOWER (5925-6425).',
  ),
];
