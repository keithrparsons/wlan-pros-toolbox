// Data Centers and Wi-Fi - typed const datasets for the read-only field/trade
// reference screen (Field & Trade Reference set, 2026-07-05). Text-reference
// (no decoder plate).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/16-data-centers-wifi.md,
// SOP-020 PASS): the three Wi-Fi roles, why the room fights RF, the two
// resilience frameworks, the Uptime Tier ladder, the access regime, and the
// framing prose. No copy is rewritten here - the screen only lays it out.
//
// GL-005 / truthfulness: the TIA-942-Rated-vs-Uptime-Tier distinction and the
// four-rung Tier ladder are the load-bearing facts, so the widget test asserts
// the anchor items (TIA says Rated / Uptime says Tier, Tier III concurrently
// maintainable) against these consts so a future edit cannot silently drift a
// value away from Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing.

/// Stable catalog tool id - backs the route, the help entry, and the tests.
/// Permanent. Text-reference: no bundled plate.
const String kDataCentersWifiToolId = 'data-centers-wifi';

/// One row of the resilience-frameworks table. [framework] is the system;
/// [owner] owns it; [levels] is its level scale; [rates] is what it rates.
class ResilienceFramework {
  const ResilienceFramework({
    required this.framework,
    required this.owner,
    required this.levels,
    required this.rates,
  });

  /// The framework, e.g. `ANSI/TIA-942`.
  final String framework;

  /// Who owns the framework.
  final String owner;

  /// The level scale it uses.
  final String levels;

  /// What it rates.
  final String rates;
}

/// The two resilience frameworks people mix up, verbatim from the copy.
const List<ResilienceFramework> kResilienceFrameworks = <ResilienceFramework>[
  ResilienceFramework(
    framework: 'ANSI/TIA-942',
    owner: 'TIA',
    levels: 'Rated-1 to Rated-4',
    rates:
        'Data-center infrastructure across four areas: telecommunications, '
        'architectural, mechanical, and electrical. A full facility standard.',
  ),
  ResilienceFramework(
    framework: 'Uptime Institute Tiers',
    owner: 'Uptime Institute',
    levels: 'Tier I to Tier IV',
    rates:
        'Topology and operational resilience. "Tier" is the Uptime trademark.',
  ),
];

/// The three roles Wi-Fi plays on a data-center floor, verbatim from the copy.
const List<String> kDataCenterWifiRoles = <String>[
  'Out-of-band management and provisioning.',
  'Staff and contractor mobility, for technicians with laptops, handhelds, and '
      'scanners.',
  'Guest.',
];

/// The three ways the room fights your RF, verbatim from the copy.
const List<String> kDataCenterRfFights = <String>[
  'Dense metal racks and cabinets create heavy reflection and multipath.',
  'Hot-aisle and cold-aisle containment, with physical barriers and ducted '
      'ceilings, chops the space into sealed RF pockets.',
  'Overhead cable trays, busway, and power distribution add clutter.',
];

/// The Uptime Tier ladder in one line each, verbatim from the copy.
const List<String> kUptimeTiers = <String>[
  'Tier I, Basic Capacity. A single non-redundant distribution path. Planned '
      'and unplanned downtime both hit the load.',
  'Tier II, Redundant Capacity Components. Adds redundant power and cooling '
      'components, but still a single distribution path.',
  'Tier III, Concurrently Maintainable. Redundant components and multiple '
      'distribution paths with one active, so any component or path can be '
      'taken down for planned maintenance without dropping the load.',
  'Tier IV, Fault Tolerant. Multiple independent active distribution paths, so '
      'the facility withstands a single unplanned failure anywhere without '
      'impact.',
];

/// What to do when asked for Wi-Fi in or around a data center, verbatim.
const List<String> kDataCenterWhatToDo = <String>[
  'Clarify the actual use case first. It is rarely production; it is usually '
      'out-of-band management, staff mobility, or guest.',
  'Survey with the containment in place. Empty-room predictions lie once the '
      'racks and aisle barriers are up.',
  'Plan low-power, contained, sometimes directional cells for a hostile RF '
      'box.',
  'Budget the access and credentialing lead time up front.',
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead.
const String kDataCenterLead =
    'The read a WLAN pro needs before quoting Wi-Fi in or around a data '
    'center. Two things carry the entry. Production Wi-Fi inside a data-center '
    'floor is usually minimal, because the room is wired and RF-hostile by '
    'construction. And the two resilience frameworks you will hear (TIA-942 '
    'and the Uptime Institute Tiers) are different systems that people mix up '
    'constantly.';

/// "Production Wi-Fi is usually minimal" intro, verbatim.
const String kDataCenterMinimalIntro =
    'A data center runs on cable. Fiber and copper are run structured to every '
    'rack, and the production data path does not ride Wi-Fi. When Wi-Fi is '
    'present on the floor, it is almost always one of three roles:';

/// The clarify-the-request note, verbatim.
const String kDataCenterClarify =
    'If someone asks you to blanket a data-center white space in production '
    'Wi-Fi, that request is usually wrong on its face. Clarify the real use '
    'case first.';

/// "Why the room fights your RF" intro, verbatim.
const String kDataCenterRfIntro =
    'A data center is built in a way that wrecks the RF behavior you would '
    'expect from an office:';

/// The coverage-collapses paragraph, verbatim.
const String kDataCenterCoverage =
    'Coverage that behaves in an office collapses here. The design problem is '
    'coverage, not capacity: the servers are on cable, and you are covering a '
    'metal maze for a handful of roaming technicians. The telecom rooms '
    'themselves (the MDF and IDF spaces, covered in the Telecom Spaces '
    'reference) are small and metal-dense, so APs often go outside or at the '
    'doorway rather than inside the rack cage.';

/// "Two frameworks people mix up" intro, verbatim.
const String kDataCenterFrameworksIntro =
    'You will hear a data center described by a resilience level. There are '
    'two separate systems, and using the wrong word marks you as an outsider.';

/// The "do not conflate them" caution (rendered as a warning band), verbatim.
const String kDataCenterConflateWarning =
    'Do not conflate them. TIA-942 says Rated, Uptime says Tier. Calling '
    'something a "Tier 3 TIA rating" mixes two frameworks and is a common, '
    'telling error.';

/// Lead-in to the Uptime Tier ladder, verbatim.
const String kUptimeLadderIntro = 'The Uptime ladder in one line each:';

/// The recognize-and-defer line under the Tier ladder, verbatim.
const String kDataCenterTierDefer =
    'Recognize the tier in conversation and defer the certification to the '
    'operator and its design engineer. The WLAN pro does not rate the '
    'facility.';

/// "The access regime is the real gate" paragraph, verbatim.
const String kDataCenterAccess =
    'Getting in to survey or install is a credentialing exercise, not a '
    'walk-in. Expect badging (often biometric), access portals or mantraps, '
    'cameras, escort, no-photography rules, NDAs, and change-control windows. '
    'This is the same "know before you go" pattern as any high-security site '
    '(see the site-access reference), and it carries real lead time. Budget it '
    'before you quote.';

/// Lead-in to the "what to do" list, verbatim.
const String kDataCenterWhatToDoIntro =
    'What to do when asked for Wi-Fi in or around a data center:';

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kDataCenterWlanCares =
    'Walk into a data center expecting office-style coverage and you get two '
    'things wrong at once: you fight an RF environment engineered to reflect '
    'and contain, and you quote a schedule that ignores the badging and '
    'change-control gate. Knowing that production Wi-Fi is usually minimal, '
    'that the room is RF-hostile by construction, and that Rated and Tier are '
    'different words keeps you credible in the room and honest in the bid.';

/// The defer footer (rendered as an info band). Verbatim.
const String kDataCenterDeferNote =
    'This is a field reference, not design or facility-rating guidance. '
    'Confirm resilience ratings, access requirements, and change-control rules '
    'with the data-center operator, its design engineer, and your contract for '
    'the specific site.';
