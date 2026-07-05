// Reading a Cloud Tool's Trust Claims - typed const datasets for the read-only
// field/trade reference screen (Field & Trade Reference set, 2026-07-05).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/10-cloud-tool-trust.md,
// SOP-020 PASS): the ISO 27001 / SOC 2 / GDPR reads, the five Trust Services
// Criteria, the adjacent-badge table, the six trust-page questions, and the
// framing prose. No copy is rewritten here - the screen only lays it out.
//
// GL-005 / truthfulness: the five Trust Services Criteria, the four adjacent
// badges, and the six trust-page questions are the load-bearing facts, so the
// widget test asserts the anchor rows against these consts so a future edit
// cannot silently drift a value away from Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing.

/// Stable catalog tool id - backs the route, the help entry, the bundled decoder
/// plate (assets/reference/cloud-tool-trust.png), and the tests. Permanent.
const String kCloudToolTrustToolId = 'cloud-tool-trust';

/// One row of the SOC 2 Trust Services Criteria table. [criterion] names the
/// criterion; [covers] is what it covers.
class TrustServicesCriterion {
  const TrustServicesCriterion({required this.criterion, required this.covers});

  /// The criterion name, e.g. `Availability`.
  final String criterion;

  /// What the criterion covers.
  final String covers;
}

/// The five Trust Services Criteria, verbatim from the copy. Security is always
/// present (the "common criteria"); the other four are optional.
const List<TrustServicesCriterion> kTrustServicesCriteria =
    <TrustServicesCriterion>[
  TrustServicesCriterion(
    criterion: 'Security (the "common criteria")',
    covers: 'Protection against unauthorized access. Always present.',
  ),
  TrustServicesCriterion(
    criterion: 'Availability',
    covers: 'Uptime, backups, disaster recovery, continuity.',
  ),
  TrustServicesCriterion(
    criterion: 'Confidentiality',
    covers:
        'Protection of information designated confidential across its '
        'lifecycle.',
  ),
  TrustServicesCriterion(
    criterion: 'Processing Integrity',
    covers: 'The system processes completely, accurately, and as intended.',
  ),
  TrustServicesCriterion(
    criterion: 'Privacy',
    covers:
        'Handling of personal information per the entity\'s privacy notice.',
  ),
];

/// One adjacent-badge row. [badge] is the badge name; [whatItIs] is what it is;
/// [buyerRead] is the one-line buyer read.
class AdjacentBadge {
  const AdjacentBadge({
    required this.badge,
    required this.whatItIs,
    required this.buyerRead,
  });

  /// The badge name, e.g. `ISO/IEC 27017`.
  final String badge;

  /// What the badge is.
  final String whatItIs;

  /// The one-line buyer read.
  final String buyerRead;
}

/// The four adjacent badges, verbatim from the copy.
const List<AdjacentBadge> kAdjacentBadges = <AdjacentBadge>[
  AdjacentBadge(
    badge: 'ISO/IEC 27017',
    whatItIs: 'Cloud-security extension of 27001/27002',
    buyerRead: 'A cloud-maturity add-on to 27001; a good sign, not standalone '
        'proof.',
  ),
  AdjacentBadge(
    badge: 'ISO/IEC 27018',
    whatItIs:
        'Code of practice for protecting personal data in public clouds as a '
        'processor',
    buyerRead:
        'Relevant when the tool holds personal data; pairs with the GDPR '
        'questions.',
  ),
  AdjacentBadge(
    badge: 'FedRAMP',
    whatItIs: 'US federal-government cloud authorization',
    buyerRead:
        'Irrelevant to most private WLAN work; matters only if the client is a '
        'US federal agency.',
  ),
  AdjacentBadge(
    badge: 'CSA STAR',
    whatItIs: 'Cloud Security Alliance registry',
    buyerRead:
        'Level 2 is a third-party audit and meaningful; Level 1 is '
        'self-assessed. Read which level.',
  ),
];

/// The six questions to ask a trust page, verbatim from the copy.
const List<String> kCloudSixQuestions = <String>[
  'Certificate or attestation? ISO is a certificate; SOC 2 is a report plus an '
      'opinion. "SOC 2 certificate" is a wording tell.',
  'What is the scope? Does it cover the actual product you will use, or the '
      'vendor\'s corporate IT?',
  'Type 2 or Type 1? For SOC 2, was operating effectiveness tested over a '
      'period, or just designed on a date?',
  'Which criteria or controls? Is Confidentiality (and Privacy, if personal '
      'data) in the SOC 2 scope? What does the ISO scope statement say?',
  'How fresh? Report or certificate within about 12 months? Bridge letter if '
      'older? Certificate still live?',
  'Where does the data live, and under whose law? Hosting region and the '
      'vendor\'s legal jurisdiction. Residency is not sovereignty.',
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead.
const String kCloudTrustLead =
    'How to read the security badges on a cloud Wi-Fi tool before you upload a '
    'client\'s floor plan, AP inventory, or survey data into it. A compliance '
    'badge is a claim about a defined scope and a time window, not a guarantee '
    'about your data. Read the badge; do not just see the logo. None of these '
    'claims means "your client\'s data is safe here." Each one means something '
    'specific and limited, and the value is knowing what.';

/// ISO 27001 section, verbatim.
const String kCloudIso27001Intro =
    'ISO/IEC 27001 (current edition 2022) certifies that an organization runs '
    'an Information Security Management System, a governed, risk-based process '
    'for managing security, assessed by an accredited third-party '
    'certification body. It is a formal certificate.';
const String kCloudIso27001Proves =
    'What it proves: the organization did a risk assessment, picked controls '
    'from Annex A (the 2022 revision defines 93 controls in four themes), and '
    'documented which it applies, and why it excluded the rest, in a Statement '
    'of Applicability. An organization does not implement all 93. It picks '
    'based on its own risk assessment. So the certificate proves process '
    'discipline over a defined scope, not that any specific control you care '
    'about is in place.';
const String kCloudIso27001Trap =
    'The trap: the certificate names a scope. A vendor can be "ISO 27001 '
    'certified" for its corporate IT while the specific cloud product you use '
    'sits outside the certified scope. The scope statement is the whole '
    'ballgame. Read it, and ask for the certificate number to confirm it is '
    'live, not lapsed.';

/// SOC 2 section, verbatim.
const String kCloudSoc2Intro =
    'SOC 2 is a CPA attestation under the AICPA framework. A licensed audit '
    'firm examines a service organization\'s controls and issues a report '
    'carrying a professional opinion. There is no "SOC 2 certificate" and no '
    'body that certifies anyone. A vendor that says "SOC 2 certified" has '
    'already told you something: the phrase is technically wrong, and hearing '
    'it is a mild literacy signal on its own. What exists is a report with a '
    'scope you have to read.';
const String kCloudSoc2TypeIntro =
    'Type 1 versus Type 2 is the distinction that matters most:';
const List<String> kCloudSoc2TypeItems = <String>[
  'Type 1 is control design at a single point in time. On this date, the '
      'controls were suitably designed. A snapshot.',
  'Type 2 is design plus operating effectiveness over a period, usually 6 to '
      '12 months. The auditor tested that the controls held up over time. Type '
      '2 is the report that carries weight. A Type 1 alone is a starting '
      'posture, often the first report a young vendor produces.',
];
const String kCloudSoc2CriteriaIntro =
    'Only one of the five Trust Services Criteria is mandatory:';
const String kCloudSoc2CriteriaMatter =
    'Here is why the criteria in scope matter: a vendor can hold a clean SOC 2 '
    'that covers only Security, and that badge tells you nothing about '
    'Availability or Confidentiality unless those criteria were in the report. '
    'For a tool holding client network designs, Confidentiality, and Privacy '
    'if personal data is involved, is exactly what you want in scope.';
const String kCloudSoc2ReadFour =
    'The report is shared under NDA, and a vendor unwilling to share it under '
    'NDA is itself a flag. When you get it, read four things: the opinion '
    '(unqualified or clean is good; a qualified opinion means the auditor '
    'found exceptions, so read them), the scope (confirm the product you use '
    'is covered, not a sibling service), the period and date (current if '
    'issued within about 12 months; older with no bridge letter is stale), and '
    'the complementary controls the report says you are responsible for.';

/// GDPR section, verbatim.
const String kCloudGdprIntro =
    'The EU General Data Protection Regulation governs processing of the '
    'personal data of people in the EU and EEA, wherever the processor sits. '
    '"GDPR compliant" is not a certification. It is a self-asserted statement '
    'of conformity, so treat the phrase as a starting question.';
const String kCloudGdprResSovIntro =
    'Residency versus sovereignty is the pair that trips people up:';
const List<String> kCloudGdprResSovItems = <String>[
  'Data residency is where the bytes physically sit. EU-region hosting, data '
      'stays in Frankfurt.',
  'Data sovereignty is whose laws reach the data.',
];
const String kCloudGdprNotSame =
    'These are not the same thing. EU hosting does not by itself solve GDPR. '
    'If the vendor is US-headquartered, or otherwise subject to a third '
    'country\'s law, that legal reach (for example the US CLOUD Act) can make '
    'the data a restricted transfer even when the servers sit physically in '
    'Europe. Physical location is not legal control.';
const String kCloudGdprIfClient =
    'If a client\'s data includes EU personal data (guest Wi-Fi logs, staff '
    'records, anything identifying EU individuals), ask the vendor three '
    'things: where the data is hosted, what transfer mechanism they rely on, '
    'and whether EU-region processing is an option. Then route the sufficiency '
    'call to the client\'s privacy officer or counsel.';

/// Adjacent-badges intro + hierarchy line, verbatim.
const String kCloudBadgesIntro =
    'So an unfamiliar logo does not bluff you, one line each:';
const String kCloudHierarchy =
    'The hierarchy in one line: third-party-audited claims (ISO 27001 '
    'certificate, SOC 2 Type 2, CSA STAR Level 2, FedRAMP) outrank '
    'self-asserted ones ("GDPR compliant," "DPF-listed," CSA STAR Level 1), '
    'and even an audited claim only covers the scope, criteria, and time '
    'window printed on it.';

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kCloudWlanCares =
    'You are the one uploading a client\'s network into someone else\'s cloud. '
    'The badge on the vendor\'s trust page does not clear you of that '
    'judgment; it tells you which questions to ask. Read the scope, read '
    'whether it is a certificate or an attestation, read where the data lives '
    'and under whose law, and you can tell a real assurance from a logo. Some '
    'data, a client\'s full network design, is sensitive enough that the right '
    'home is your own device, not a cloud you never vetted.';

/// The defer footer (rendered as an info band). Verbatim.
const String kCloudDeferNote =
    'Reference only. Compliance status, scope, and sufficiency depend on a '
    'client\'s specific obligations and are determined by their security or '
    'compliance officer and a qualified auditor (a CPA firm or counsel), not '
    'by this tool. This is literacy, not compliance advice.';
