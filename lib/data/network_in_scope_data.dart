// Frameworks That Put Your Wi-Fi in Scope - typed const datasets for the
// read-only field/trade reference screen (Field & Trade Reference set,
// 2026-07-05).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/
// 11-network-in-scope-compliance.md, SOP-020 PASS): the PCI DSS / HIPAA / SOX /
// GDPR reads, what each framework asks of the network, the route-to owners, and
// the framing prose. No copy is rewritten here - the screen only lays it out.
//
// GL-005 / truthfulness: the five PCI asks, the four HIPAA safeguards, and the
// three SOX touches are the load-bearing facts, so the widget test asserts the
// anchor items (WPA2-PSK inadequate for the CDE, the quarterly rogue scan,
// transmission security) against these consts so a future edit cannot silently
// drift a value away from Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; "802.1X" casing.

/// Stable catalog tool id - backs the route, the help entry, the bundled
/// compliance-scope plate (assets/reference/network-in-scope.png), and the
/// tests. Permanent.
const String kNetworkInScopeToolId = 'network-in-scope';

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead.
const String kNetScopeLead =
    'The regulatory frameworks that reach the network itself. When the Wi-Fi '
    'carries cardholder data (PCI DSS), electronic health information (HIPAA), '
    'or sits inside a public company\'s financial systems (SOX), the design '
    'inherits requirements. The move on every one is the same: recognize the '
    'trigger, know what the framework generally wants of the network, then '
    'route the specifics to the owner. Never tell a client the design "meets" '
    'any of them.';

// PCI DSS
const String kPciIntro =
    'You are in scope when the Wi-Fi touches cardholder data, or connects to '
    'systems that store or process it. Retail, hospitality, any card-present '
    'site. The current standard is PCI DSS v4.0.1, and the future-dated v4.x '
    'requirements became mandatory 31 March 2025, so any older write-up that '
    'still calls them "future-dated" is describing rules that are now live.';
const String kPciAsksIntro =
    'What it generally asks of the network, at a high level:';
const List<String> kPciAsks = <String>[
  'Segmentation from the Cardholder Data Environment. APs and networks not '
      'carrying cardholder data should be segmented from the CDE; put guest '
      'Wi-Fi on a separate VLAN, internet-only, firewalled off the payment '
      'path. Carry this caution: VLANs alone are not automatically '
      '"segmentation" in PCI\'s eyes, and segmentation effectiveness has to be '
      'validated.',
  'Strong cryptography. The current bar is WPA2-AES or WPA3 at a minimum, with '
      'no fallback to weaker protocols. WEP and WPA/TKIP are prohibited, and '
      'WPA2-PSK is inadequate for the CDE. If you are working from a 2011-era '
      'wireless guideline that still frames WPA2-PSK as the standard, it is out '
      'of date.',
  'No default credentials or settings on wireless gear: SSIDs, keys, SNMP '
      'strings, admin passwords.',
  'Rogue and unauthorized wireless scanning, at least quarterly, under '
      'Requirement 11.2.1. The sharp part: this is required even at a site with '
      'no Wi-Fi at all, because a rogue AP is cheap to plant and hard to spot. '
      'A wireless IDS/IPS satisfies the continuous-monitoring intent.',
  'Logging and audit trails on the in-scope network.',
];
const String kPciRouteTo =
    'Route to: the client\'s QSA (Qualified Security Assessor) or internal PCI '
    'compliance lead, who owns scoping and validation.';

// HIPAA
const String kHipaaIntro =
    'You are in scope when the network carries, or connects to systems '
    'holding, electronic protected health information (ePHI). Covered entities '
    'and their business associates. The Security Rule technical safeguards '
    '(section 164.312) are the part that touches the network.';
const String kHipaaSafeguardsIntro =
    'The technical safeguards, as they reach the network:';
const List<String> kHipaaSafeguards = <String>[
  'Access control: unique user IDs and emergency access.',
  'Audit controls: record access to and activity in systems holding ePHI.',
  'Integrity: protect ePHI from improper alteration or destruction.',
  'Transmission security: protect ePHI crossing a network, which in practice '
      'means strong encryption (TLS 1.2 or better in transit, WPA2 or '
      'WPA3-Enterprise on the WLAN) plus integrity controls.',
];
const String kHipaaNuance =
    'One nuance to flag, because it is moving: HIPAA today distinguishes '
    '"required" from "addressable" specifications, and encryption is currently '
    'addressable. Addressable does not mean optional; it means you either '
    'implement it or document a defensible reason not to. A Notice of Proposed '
    'Rulemaking published 6 January 2025 proposes ending that distinction and '
    'making encryption mandatory. State the current rule and the pending '
    'change; do not print a frozen answer.';
const String kHipaaRouteTo =
    'For the RF and design depth on hospitals, see the healthcare entry. Route '
    'to: the health system\'s privacy or security officer, and for the '
    'medical-device side, clinical or biomedical engineering.';

// SOX and SEC
const String kSoxIntro =
    'You are in scope when the client is a US public company, and some pre-IPO '
    'companies preparing to file. SOX does not regulate Wi-Fi directly. It '
    'reaches the network through IT General Controls over the systems that '
    'support financial reporting, under Section 404.';
const String kSoxTouchesIntro =
    'What it generally touches on the network side:';
const List<String> kSoxTouches = <String>[
  'Access controls: who can reach financial-reporting systems and the network '
      'segments they live on; least privilege; provisioning and '
      'de-provisioning.',
  'Change management: network changes to in-scope systems follow a documented, '
      'approved, auditable process, not ad-hoc console edits.',
  'Audit trails: retained evidence that the controls actually operate, kept '
      'for the auditor.',
];
const String kSoxNarrowest =
    'This is the narrowest fit of the four. The network is rarely the star of '
    'a SOX audit; it shows up as the access-and-change-control substrate under '
    'the financial systems. The useful thing to understand is why your AP '
    'config changes at a public-company client can suddenly need a ticket and '
    'an approver. Route to: the client\'s internal audit or IT compliance '
    'function and the external auditor.';

// GDPR on the network side
const String kGdprNetworkSide =
    'Where the network itself processes EU personal data (captive-portal guest '
    'logins, MAC or identity logging, real-time location of identifiable '
    'people), GDPR\'s principles apply to the design: data minimization, '
    'storage limitation (retention windows on Wi-Fi logs), security of '
    'processing, and the residency-and-sovereignty question of wherever those '
    'logs land, including any cloud Wi-Fi management platform holding them. '
    'That last point loops straight back to reading a cloud tool\'s trust '
    'claims. Route to: the client\'s privacy officer or Data Protection '
    'Officer.';

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kNetScopeWlanCares =
    'These frameworks decide what your design has to support long before '
    'anyone audits it. Recognizing that a site sits in PCI, HIPAA, SOX, or '
    'GDPR scope, and knowing the general shape of what each asks of the '
    'network, lets you quote it honestly and design toward the requirement '
    'instead of retrofitting after the auditor shows up. What you never do is '
    'tell a client the design "meets PCI" or "is HIPAA compliant." You '
    'recognize the framework; the QSA, the auditor, and the compliance officer '
    'rule on it.';

/// The defer footer (rendered as an info band). Verbatim.
const String kNetScopeDeferNote =
    'Reference only. Whether a given network is in scope, and whether a design '
    'is sufficient, is determined by the client\'s compliance or security '
    'officer and a qualified auditor (a QSA, a CPA firm, or counsel), not by '
    'this tool. This is literacy, not compliance advice.';
