// Hazardous (Classified) Locations — typed const datasets for the read-only
// reference screen (#3 of the Field & Trade Reference set, 2026-07-05).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/02-hazardous-
// locations.md): the Class / Division / Zone ladders, the Division-to-Zone
// mapping, the protection-concept table, and the framing prose. No copy is
// rewritten here — the screen only lays it out. This is a recognize-and-defer
// reference: it names the hazard and the concepts, then stops. It never adds
// procedure.
//
// GL-005 / truthfulness: these tables are load-bearing safety facts, so the
// widget test asserts the anchor rows (Class I = flammable gas, Division 1 =
// present in normal operation, the "commercial AP is a genuine ignition source"
// takeaway, and the AHJ / licensed-electrician defer line) against these consts
// so a future edit cannot silently drift a value away from Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing.

/// Stable catalog tool id — backs the route, the help entry, the bundled diagram
/// PNG (assets/reference/hazardous-locations.png), and the tests. Permanent.
const String kHazardousLocationsToolId = 'hazardous-locations';

// ─────────────────────────────── framing lead ───────────────────────────────

/// The lead: what the classified-location system is and which standard runs it.
const String kHazLead =
    'The system that decides whether you can put wireless in a refinery, grain '
    'elevator, fuel depot, or spray booth at all. In the US it runs on NEC '
    'Article 500 (Class and Division). The rest of the world, and increasingly '
    'the US, uses the IEC Zone system.';

// ─────────────────────────── Class: the hazard type ─────────────────────────

/// One row of the Class table (what the hazard is made of).
class HazClass {
  const HazClass({
    required this.cls,
    required this.hazard,
    required this.environments,
  });

  /// Class designation, e.g. `Class I`.
  final String cls;

  /// What the hazard is made of.
  final String hazard;

  /// Real environments where the class shows up.
  final String environments;
}

/// Class: what the hazard is made of, verbatim from the copy.
const List<HazClass> kHazClasses = <HazClass>[
  HazClass(
    cls: 'Class I',
    hazard: 'Flammable gases or vapors',
    environments:
        'Refineries, oil and gas, chemical plants, paint and spray booths, '
        'fuel storage, solvent rooms',
  ),
  HazClass(
    cls: 'Class II',
    hazard: 'Combustible dust',
    environments:
        'Grain elevators, flour and feed mills, sugar, coal handling, '
        'metal-dust machining',
  ),
  HazClass(
    cls: 'Class III',
    hazard: 'Ignitable fibers or flyings',
    environments: 'Textile mills, cotton gins, woodworking, some paper operations',
  ),
];

// ──────────────────────── Division: how often present ───────────────────────

/// Division: how often the hazard is present, verbatim (two bullets).
const List<String> kHazDivisions = <String>[
  'Division 1: the ignitable atmosphere is present during normal operation. '
      'Expect it to be explosive.',
  'Division 2: the atmosphere is present only under fault conditions, a leak, '
      'spill, or ventilation failure. Fine until something breaks.',
];

/// The Division market note.
const String kHazDivisionNote =
    'Div 2 is a far larger and more common market for rated wireless than Div 1.';

// ─────────────────────────── Zone: the IEC system ───────────────────────────

/// Zone-section intro.
const String kHazZoneIntro =
    'NEC Article 505 (gases) and Article 506 (dusts) adopt the IEC Zone system '
    'used worldwide under ATEX and IECEx. It splits the same risk into three '
    'bands.';

/// One row of the Zone table.
class HazZone {
  const HazZone({
    required this.hazard,
    required this.zones,
    required this.meaning,
  });

  /// Hazard family, e.g. `Gas or vapor` or `Dust`.
  final String hazard;

  /// The zone token(s), e.g. `Zone 0` or `Zone 20 / 21 / 22`.
  final String zones;

  /// Plain meaning of that zone band.
  final String meaning;
}

/// The Zone ladder, verbatim from the copy.
const List<HazZone> kHazZones = <HazZone>[
  HazZone(
    hazard: 'Gas or vapor',
    zones: 'Zone 0',
    meaning: 'Present continuously or for long periods',
  ),
  HazZone(
    hazard: 'Gas or vapor',
    zones: 'Zone 1',
    meaning: 'Present in normal operation',
  ),
  HazZone(
    hazard: 'Gas or vapor',
    zones: 'Zone 2',
    meaning: 'Present only briefly, under fault',
  ),
  HazZone(
    hazard: 'Dust',
    zones: 'Zone 20 / 21 / 22',
    meaning: 'Same continuous, normal, fault ladder',
  ),
];

/// Intro to the Division-to-Zone mapping bullets.
const String kHazZoneMappingIntro = 'Division to Zone, the mapping pros need:';

/// Division-to-Zone mapping, verbatim (two bullets).
const List<String> kHazZoneMapping = <String>[
  'Division 1 is roughly Zone 0 plus Zone 1 (gas), or Zone 20 plus 21 (dust).',
  'Division 2 is roughly Zone 2 (gas), or Zone 22 (dust).',
];

/// The "do not mix" note under the mapping.
const String kHazZoneNote =
    'Both systems are legal in the US, but you cannot mix Division and Zone '
    'classification in the same installation. Which one is in force is set by '
    'the facility\'s area-classification drawing and the AHJ, not by the '
    'installer.';

// ─────────────────── Why a commercial AP cannot go there ─────────────────────

/// The lead sentence of the "why not" section (rendered as body).
const String kHazApBody =
    'A standard commercial AP has internal energy (radios, PoE, capacitors, '
    'switching) fully capable of igniting a flammable atmosphere on a fault, or '
    'even in normal operation.';

/// The load-bearing safety takeaway (rendered as a warning band). Verbatim.
const String kHazApWarning =
    'Mounting one in a classified area is illegal, uninsurable, and a genuine '
    'ignition source. That is the one-line takeaway.';

/// Intro to the protection-concept table.
const String kHazProtectionIntro =
    'To put wireless in a classified area you need a recognized protection '
    'concept matched to the Division or Zone:';

/// One row of the protection-concept table.
class HazConcept {
  const HazConcept({
    required this.concept,
    required this.how,
    required this.where,
  });

  /// Protection concept, e.g. `Intrinsically safe (Ex i)`.
  final String concept;

  /// How it protects.
  final String how;

  /// Where it applies (Division / Zone).
  final String where;
}

/// The recognized protection concepts, verbatim from the copy.
const List<HazConcept> kHazConcepts = <HazConcept>[
  HazConcept(
    concept: 'Explosion-proof / flameproof (Ex d)',
    how:
        'Enclosure contains an internal explosion; engineered gaps cool '
        'escaping gas below ignition temp',
    where: 'Zone 1 / Div 1',
  ),
  HazConcept(
    concept: 'Intrinsically safe (Ex i)',
    how:
        'Circuit energy limited so low it cannot ignite even on a fault; the '
        'only concept accepted in Zone 0',
    where: 'Low-power sensors, some radios',
  ),
  HazConcept(
    concept: 'Purged / pressurized (Ex p)',
    how:
        'Kept under clean-air or inert positive pressure so no flammable '
        'atmosphere gets in',
    where: 'Larger cabinets',
  ),
  HazConcept(
    concept: 'Increased safety / restricted breathing (Ex e / Ex nR)',
    how: 'Sealed against gas ingress, no arcing parts',
    where: 'Zone 2 / Div 2, the common wireless case',
  ),
];

/// The listing-standards note under the concept table.
const String kHazListingNote =
    'US listing runs to UL 1203 under NEC 500, 505, and 506. Internationally, '
    'ATEX (mandatory in Europe) and IECEx (global) apply.';

// ──────────────── What "Class I Div 2 rated" actually buys you ───────────────

/// The two paragraphs of the "what it buys you" section, verbatim.
const List<String> kHazDiv2Buys = <String>[
  'Permission to install that specific listed device, in that specific '
      'Division or Zone, wired per its control drawing. It is not a blanket '
      '"safe anywhere" stamp. A Div 2 device is not approved for Div 1, and the '
      'gas or dust group and temperature class still have to match the specific '
      'atmosphere.',
  'Purpose-built rated APs are real. Cisco\'s Catalyst IW9167E-HZ ("Heavy '
      'Duty") is certified Class I Div 2, ATEX Zone 2/22, and IECEx, for '
      'example. A second pattern puts a standard AP inside a certified '
      'Ex-rated enclosure with the antenna routed out through certified glands. '
      'Both patterns exist, so know which one a spec sheet is describing.',
];

// ─────────────────────────────── The field read ─────────────────────────────

/// "The field read" bullets, verbatim.
const List<String> kHazFieldRead = <String>[
  'Recognize a classified area before you quote. Look for the facility '
      'area-classification drawing, warning placards, conduit seal fittings, '
      'purge panels, and the obvious sites (refinery, tank farm, grain, spray '
      'booth, solvent or hydrogen room).',
  'Default move: keep the AP out of the classified envelope. Mount it in the '
      'adjacent general-purpose area and remote the antenna into the zone '
      'through a rated penetration. Use a rated AP or enclosure only where '
      'coverage genuinely requires being inside.',
  'Never just mount a commercial AP there.',
];

// ────────────────────────── Why a WLAN pro cares ────────────────────────────

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kHazWlanCares =
    'Misreading a classified area gets someone hurt and gets you sued. Knowing '
    'Class, Division, and Zone lets you recognize the site, quote it honestly, '
    'and route the install to the right rated gear and the AHJ instead of '
    'walking into a job you cannot legally do.';

/// The recognize-and-defer footer (rendered as an info band). Verbatim.
const String kHazDeferNote =
    'This is a field reference, not code or design guidance. Confirm '
    'requirements with the AHJ, the architect of record, and a licensed '
    'electrician.';
