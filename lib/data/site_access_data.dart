// Site Access ("Know Before You Go") - typed const datasets for the read-only
// field/trade reference screen (Field & Trade Reference set, 2026-07-05).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/06-site-access.md,
// SOP-020 PASS): the pre-mobilization checklist (environment / what may gate
// you / ask about) and the framing prose. No copy is rewritten here - the
// screen only lays it out.
//
// GL-005 / truthfulness: the eight-row access checklist is the load-bearing
// content, so the widget test asserts the anchor rows (rail screening, hospital
// ICRA, maritime NEMA 4X, correctional tool control) against these consts so a
// future edit cannot silently drift a value away from Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing.

/// Stable catalog tool id - backs the route, the help entry, the bundled diagram
/// PNG (assets/reference/site-access.png), and the tests. Permanent.
const String kSiteAccessToolId = 'site-access';

/// One row of the site-access checklist. [environment] is the site type;
/// [gate] is what may gate you (the credential, screening, or orientation);
/// [askAbout] is the short "ask about" list to scope before you quote.
class SiteAccessRow {
  const SiteAccessRow({
    required this.environment,
    required this.gate,
    required this.askAbout,
  });

  /// The site type, e.g. `Rail or near active track`.
  final String environment;

  /// What may gate you before you reach the work.
  final String gate;

  /// The short "ask about" list to confirm before quoting and mobilizing.
  final String askAbout;
}

/// The eight-environment pre-mobilization checklist, verbatim from the copy.
const List<SiteAccessRow> kSiteAccessRows = <SiteAccessRow>[
  SiteAccessRow(
    environment: 'Aerial and man-lifts (boom, scissor)',
    gate:
        'You generally may not run a lift without documented operator '
        'training, and GCs demand proof. Boom lifts and scissor lifts fall '
        'under different rules but the same practical gate.',
    askAbout:
        'Operator training records, or a rental with an operator. Note: there '
        'is no OSHA-issued "lift license"; the employer trains and certifies.',
  ),
  SiteAccessRow(
    environment: 'Rail or near active track',
    gate:
        'Class I railroads require background screening plus railroad-specific '
        'safety orientation before you set foot on property, and often a '
        'railroad flagman for track clearance. Transit authorities run their '
        'own equivalents. Lead times are long.',
    askAbout:
        'Screening (programs like eRailSafe), orientation, flagman '
        'requirement. Budget weeks.',
  ),
  SiteAccessRow(
    environment: 'Hospitals and active patient care',
    gate:
        'Cabling and AP work triggers ICRA (Infection Control Risk '
        'Assessment: dust containment, barriers, HEPA) and ILSM (protecting '
        'fire and egress during work), plus badging, escort, and patient-area '
        'rules. Many systems require ICRA-awareness training before badging.',
    askAbout:
        'ICRA permit, ILSM measures, badge and escort process, EMI-sensitive '
        'areas.',
  ),
  SiteAccessRow(
    environment: 'Maritime, over-water, docks',
    gate:
        'Adds personal-flotation and drowning-hazard rules, vessel-access '
        'rules, and heavy salt corrosion (spec NEMA 4X or high-IP with '
        'explicit corrosion resistance). Some ports are security-controlled.',
    askAbout:
        'PFD and over-water rules, TWIC card for secure port areas, '
        'corrosion-rated enclosures.',
  ),
  SiteAccessRow(
    environment: 'Warehouse and distribution centers',
    gate:
        'You are a pedestrian among moving forklifts and busy docks. Many DCs '
        'mandate hi-vis, pedestrian lanes, spotter rules, and a site '
        'orientation before floor access.',
    askAbout:
        'Forklift-zone orientation, hi-vis, pedestrian and dock-edge rules.',
  ),
  SiteAccessRow(
    environment: 'Schools and childcare',
    gate:
        'Access almost always requires a background check or fingerprinting, '
        'and often restricts work to after-hours or breaks.',
    askAbout: 'Background check, scheduling around students.',
  ),
  SiteAccessRow(
    environment: 'Data centers',
    gate:
        'Strict access control and escort, sometimes background checks and '
        'NDAs, anti-static and PPE rules, no photography, and change-control '
        'windows.',
    askAbout: 'Escort, change-control window, NDA, ESD discipline.',
  ),
  SiteAccessRow(
    environment: 'Correctional facilities',
    gate:
        'Background clearance, escort, tool control (every tool counted in and '
        'out), no contraband, movement lockdowns.',
    askAbout: 'Clearance, escort, tool-control process.',
  ),
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead: what this checklist is and why it is a scheduling factor.
const String kSiteAccessLead =
    'A pre-mobilization checklist. On many sites you cannot even reach the work '
    'area without a specific credential, background check, orientation, or '
    'escort. That is a quoting and scheduling factor, not just a safety one. '
    'Underestimating it is how a one-day install becomes a three-week '
    'mobilization.';

/// The shared pattern across every checklist item, verbatim.
const String kSiteAccessPattern =
    'The pattern across every item: the requirement is set by someone other '
    'than you (the general contractor, site owner, rail or transit authority, '
    'or accreditation body), it must be satisfied before work starts, and it '
    'carries real lead time and cost. Confirm each one before you quote and '
    'before you mobilize.';

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kSiteAccessWlanCares =
    'The credential you do not have is the schedule you cannot keep. Rail '
    'screening, an ICRA permit, or lift-operator proof can each add days or '
    'weeks between winning the job and touching a cable. Scope these before you '
    'quote so the timeline you promise is the timeline you can hit.';

/// The defer footer (rendered as an info band). Verbatim - note this one differs
/// from the standard AHJ/electrician footer.
const String kSiteAccessDeferNote =
    'This is a field reference, not code or design guidance. The site, general '
    'contractor, and authority set every requirement above. Confirm each one '
    'with them before you mobilize. The Toolbox certifies nothing and clears '
    'no one.';
