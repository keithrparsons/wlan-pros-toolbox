// Credentials, Licenses, and Federal IDs - typed const datasets for the
// read-only field/trade reference screen (Field & Trade Reference set,
// 2026-07-05). Companion to the Site Access entry.
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/13-credentials-licenses.md,
// SOP-020 PASS): the three FCC concepts, the "you do not need a GROL" facts,
// the six-credential lead-time table, the three lead-time clusters, and the
// framing prose. No copy is rewritten here - the screen only lays it out.
//
// GL-005 / truthfulness: the six-credential table and the two GROL facts are
// the load-bearing content, so the widget test asserts the anchor rows (TWIC
// maritime / 5 years, the Part 101 microwave-does-not-need-a-GROL fact) against
// these consts so a future edit cannot silently drift a value away from Penn's
// approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing.

/// Stable catalog tool id - backs the route, the help entry, the bundled
/// credential-lead-time plate (assets/reference/credentials-licenses.png), and
/// the tests. Permanent.
const String kCredentialsLicensesToolId = 'credentials-licenses';

/// One row of the site-gating credentials table. [credential] is the ID or
/// license; [authority] issues it; [gatesYou] is where it gates you;
/// [leadTime] is the typical lead time; [validity] is how long it lasts.
class CredentialRow {
  const CredentialRow({
    required this.credential,
    required this.authority,
    required this.gatesYou,
    required this.leadTime,
    required this.validity,
  });

  /// The credential name, e.g. `TWIC`.
  final String credential;

  /// The issuing authority.
  final String authority;

  /// Where the credential gates you.
  final String gatesYou;

  /// The typical lead time.
  final String leadTime;

  /// The validity window.
  final String validity;
}

/// The six site-gating credentials, verbatim from the copy.
const List<CredentialRow> kCredentials = <CredentialRow>[
  CredentialRow(
    credential: 'TWIC',
    authority: 'TSA / USCG',
    gatesYou:
        'Secure areas of maritime facilities and vessels: ports, terminals, '
        'container yards',
    leadTime: 'Enroll 60+ days ahead; processing can exceed 45 days',
    validity: '5 years',
  ),
  CredentialRow(
    credential: 'CAC',
    authority: 'DoD (sponsor required)',
    gatesYou: 'DoD contractors with an ongoing need on military installations',
    leadTime:
        'Card can issue on a favorable fingerprint check, but the underlying '
        'investigation (formerly NACI) can run many months',
    validity: '~3 years / contract term',
  ),
  CredentialRow(
    credential: 'DBIDS',
    authority: 'DoD installation',
    gatesYou: 'Contractors needing base access without a CAC',
    leadTime:
        'Identity vetting, a paper pass first, then up to 180 days for the '
        'physical card',
    validity: 'Set by installation',
  ),
  CredentialRow(
    credential: 'SIDA badge',
    authority: 'Airport authority (under TSA)',
    gatesYou:
        'Unescorted access to the airport airside / Security Identification '
        'Display Area',
    leadTime: '~7-10 days up to ~3 weeks',
    validity: 'Per airport',
  ),
  CredentialRow(
    credential: 'HAZWOPER 40-hr',
    authority: 'Employer, to OSHA 29 CFR 1910.120(e)',
    gatesYou: 'Hazardous-waste cleanup and uncontrolled-hazardous-waste sites',
    leadTime: '40-hour course plus 3 days supervised field time',
    validity: '8-hour annual refresher',
  ),
  CredentialRow(
    credential: 'School / corrections background check',
    authority: 'State or district',
    gatesYou:
        'Regular or unsupervised contact in K-12, childcare, and corrections',
    leadTime: 'Days to weeks',
    validity: 'Per state or district',
  ),
];

/// The three blurred FCC concepts, verbatim from the copy.
const List<String> kFccConcepts = <String>[
  'Operator license (the GROL). The General Radiotelephone Operator License is '
      'required to adjust, maintain, or internally repair FCC-licensed '
      'transmitters in the aviation, maritime, and international-fixed-public '
      'radio services. Wi-Fi is none of those.',
  'Equipment authorization (Part 15). This is testing and listing that a '
      'device meets FCC emission rules before it can be sold. It says the AP is '
      'legal to sell, not that a person is licensed to touch it.',
  'Amateur (ham) license. A hobbyist authorization under Part 97. Not a '
      'commercial work credential.',
];

/// The two facts that settle the license question for WLAN work, verbatim.
const List<String> kGrolFacts = <String>[
  'Unlicensed Wi-Fi (FCC Part 15) needs no operator license. The device is '
      'authorized; the operator is not licensed. Installing, tuning, or '
      'servicing an 802.11 AP requires no FCC operator credential of any kind.',
  'Licensed point-to-point microwave backhaul does not require a GROL either. '
      'This is the one pros get wrong. Licensed fixed microwave links (11, 18, '
      '23 GHz and similar) fall under Part 101 Fixed Microwave Services, '
      'classified separately from the aviation and maritime services the GROL '
      'covers. Operating or maintaining a Part 101 link does not, by itself, '
      'require a GROL.',
];

/// The three lead-time clusters, verbatim from the copy.
const List<String> kLeadTimeClusters = <String>[
  'Fast, you control it: a GROL is a one-time exam; a school background check '
      'is days to a couple of weeks; HAZWOPER-40 is a scheduled course.',
  'Weeks, plan before you quote: SIDA, TWIC (enroll 60 days ahead), and DBIDS.',
  'Weeks to months, the real landmine: a CAC, whose underlying investigation '
      'can run many months.',
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead.
const String kCredentialsLead =
    'The portable IDs and licenses a WLAN pro carries from job to job, and the '
    'mobilization landmine hiding in them. Two things to get straight. You '
    'almost never need an FCC operator license to do Wi-Fi work, even licensed '
    'microwave backhaul. And the federal and background-check credentials that '
    'gate restricted sites carry weeks to months of lead time you cannot '
    'compress. The credential you do not already hold is the schedule you '
    'cannot keep, so scope it before you quote. Companion to the Site Access '
    'entry, which covers site-specific orientation and escort.';

/// Lead-in to the three FCC concepts, verbatim.
const String kFccConceptsIntro =
    'Three FCC concepts get blurred, and keeping them straight is half the '
    'value here:';

/// Lead-in to the two GROL facts, verbatim.
const String kGrolFactsIntro = 'Two facts settle it for WLAN work:';

/// The GROL-exception closer, verbatim.
const String kGrolException =
    'You would only need a GROL if the work crossed into servicing aviation or '
    'marine radios, for example a maritime job that also touches the vessel\'s '
    'licensed VHF radiotelephone. That is outside a normal WLAN scope of work.';

/// Lead-in to the credentials table, verbatim.
const String kCredentialsTableIntro =
    'These are the lead-time landmines: portable IDs and background checks '
    'that a restricted site requires before you can reach the work area. '
    'Several take weeks to months, and you cannot get them on the day you need '
    'them.';

/// The five per-credential explanatory paragraphs, verbatim from the copy.
const List<String> kCredentialNotes = <String>[
  'TWIC gets you the maritime jobs: port, terminal, container-yard, and '
      'shipboard Wi-Fi. TSA tells applicants to enroll at least 60 days out '
      'and warns processing can exceed 45 days. This entry is the source of '
      'truth for TWIC detail; the Site Access maritime row just points here.',
  'CAC versus DBIDS is the military-base question. The CAC is for contractors '
      'with an ongoing DoD affiliation, and it needs a sponsor, a favorable '
      'FBI fingerprint check, and a background investigation whose full run can '
      'take many months; the investigation formerly called NACI is now part of '
      'the federal Tier system (Tier 1 to 5). DBIDS is the lighter path for a '
      'contractor who just '
      'needs to get on base: identity vetting, a paper pass first, then up to '
      '180 days for the physical card. Which one applies is set by the '
      'installation and the contract.',
  'SIDA badges cover terminal, gate-area, ramp, and airside Wi-Fi. The '
      'applicant passes a TSA Security Threat Assessment, a fingerprint-based '
      'criminal history check, and SIDA training, sponsored by an authorized '
      'signatory.',
  'HAZWOPER-40 is a training certification, not an ID card, under OSHA 29 CFR '
      '1910.120(e). It gates environmental-remediation, brownfield, and some '
      'heavy-industrial sites where the owner mandates it for anyone on the '
      'ground. Narrower audience, but a real gate where it applies.',
  'Background checks gate a large slice of ordinary WLAN work. K-12 and '
      'childcare access almost universally requires a state fingerprint check '
      'for contractors with regular or unsupervised student contact, and '
      'correctional facilities add a facility clearance on top of the escort '
      'and tool control the Site Access entry already covers.',
];

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kCredentialsWlanCares =
    'Same failure as an unscoped site orientation, one layer up: the '
    'credential you do not already carry is the schedule you cannot keep. A '
    'TWIC, a base credential, or a SIDA badge can each add weeks between the '
    'award and touching a cable. Scope the credential before you quote, not '
    'after you win. And do not chase a license you do not need, because pure '
    'Wi-Fi and licensed microwave work require no FCC operator license at all.';

/// The defer footer (rendered as an info band). Verbatim.
const String kCredentialsDeferNote =
    'Reference only. The issuing authority (the FCC, TSA, the DoD or '
    'installation, the airport authority, an OSHA-trained employer, the state '
    'or district) sets and grants every credential above. Confirm what your '
    'specific job requires before you quote and before you mobilize. The '
    'Toolbox certifies nothing and clears no one.';
