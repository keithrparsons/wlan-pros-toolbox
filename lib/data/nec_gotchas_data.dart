// NEC Gotchas on a WLAN Job — typed const datasets for the read-only reference
// screen (#4 of the Field & Trade Reference set, 2026-07-05).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/03-nec-gotchas.md):
// the code articles that bite a WLAN installer, the cable-rating ladder, the
// two recognize-and-STOP callouts (PoE bundle ampacity, firestop assembly), and
// the framing prose. No copy is rewritten here — the screen only lays it out.
// This is recognize-and-defer, never how-to-comply: each article names what to
// recognize on site, then hands it to the AHJ, a licensed electrician, or the
// equipment listing. It never adds procedure.
//
// GL-005 / truthfulness: these articles are load-bearing code facts, so the
// widget test asserts the anchor rows (the hoistway rule, the CMP-plenum rung,
// the PoE-bundle STOP, the firestop STOP, and the AHJ / licensed-electrician
// defer line) against these consts so a future edit cannot silently drift a
// value away from Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; "802.3bt" style code shown as written.

/// Stable catalog tool id — backs the route, the help entry, the bundled diagram
/// PNG (assets/reference/nec-gotchas.png), and the tests. Permanent.
const String kNecGotchasToolId = 'nec-gotchas';

// ─────────────────────────────── framing lead ───────────────────────────────

/// The lead: what the article set is and the recognize-and-defer stance.
const String kNecLead =
    'The six code articles that actually bite a WLAN installer. Each one is here '
    'so you can recognize it on site, then hand it to the AHJ, a licensed '
    'electrician, or the equipment listing. This is recognize-and-defer, never '
    'how-to-comply.';

// ─────────────────────────────── the articles ───────────────────────────────

/// One NEC-article "gotcha" card. [stop] carries an optional recognize-and-STOP
/// warning-band line (the two articles where eyeballing a number is dangerous);
/// [caveat] carries an optional honest-limits note (the grounding article).
class NecArticle {
  const NecArticle({
    required this.title,
    required this.body,
    this.bullets = const <String>[],
    this.tail,
    this.stop,
    this.caveat,
  });

  /// Article heading, e.g. `Elevator hoistways (Article 620, especially
  /// 620.37)`.
  final String title;

  /// The main explanatory paragraph.
  final String body;

  /// Optional bulleted rungs (the Article 800 cable-rating ladder).
  final List<String> bullets;

  /// Optional trailing paragraph after the bullets (e.g. the "Substitution runs
  /// downhill only" note).
  final String? tail;

  /// Optional recognize-and-STOP line, rendered as a warning band. Present only
  /// on the two articles where a number must not be eyeballed.
  final String? stop;

  /// Optional honest-limits caveat, rendered as an info band (the grounding
  /// article's "nothing survives a direct strike").
  final String? caveat;
}

/// The SIX NEC articles that bite a WLAN job, verbatim from the copy, in order.
///
/// The Article 800 communications-cable rating ladder is deliberately NOT one
/// of these six. The lead ([kNecLead]) and the recap ([kNecWlanCares]) both
/// name exactly "six code articles," and Vera's approved cutaway plate shows
/// six numbered callouts plus a SEPARATE supporting fire-rating-ladder band.
/// The ladder is a supporting reference (which jacket rating goes where), not a
/// seventh peer gotcha, so it lives on its own in [kNecCableLadder] and renders
/// as a set-apart "Supporting reference" section. Keeping it out of this list is
/// what makes the screen honor its own "six" claim (no six-vs-seven
/// self-contradiction) and match the plate.
const List<NecArticle> kNecArticles = <NecArticle>[
  NecArticle(
    title: 'Elevator hoistways (Article 620, especially 620.37)',
    body:
        'Only wiring and equipment used directly for the elevator is permitted '
        'in the hoistway, machine room, or machinery space. A Wi-Fi AP serving '
        'building coverage is not elevator equipment, so it cannot go in the '
        'shaft. The rule keeps non-elevator techs out of a space full of moving '
        'machinery. Cover elevator Wi-Fi from the adjacent hallway or lobby and '
        'let RF into the car through the doors, or use the elevator vendor\'s '
        'own in-car system (its traveling cable is elevator equipment and is '
        'permitted). Do not sneak an AP into the hoistway.',
  ),
  NecArticle(
    title: 'Plenum and environmental air spaces (Article 300.22)',
    body:
        'Where the space above a ceiling or below a raised floor is used to '
        'move HVAC air, cable and equipment left there must be rated for it. '
        'Plenum cable is Type CMP. This applies only where the space is '
        'actually an air-handling plenum. A dropped ceiling with ducted return '
        'is not automatically a plenum, a common misread. An AP mounted in a '
        'plenum must be listed for the use (many are; check the listing).',
  ),
  NecArticle(
    title: 'PoE bundle heat (Article 725.144)',
    body:
        'When cabling carries power and data together (PoE), current heats the '
        'copper, and cables in the center of a fat bundle cannot shed that '
        'heat. The code caps allowable per-conductor current by wire gauge, '
        'bundle size, and cable temperature rating. This became a real concern '
        'with the 60 W (Type 3) and roughly 90 W (Type 4, 802.3bt) APs now '
        'common. Tight bundles in conduit at high ambient temperature are where '
        'it bites.',
    stop:
        'STOP: the exact ampacity and bundle-count numbers come from the code '
        'table and the specific install conditions. Do not eyeball them. Size '
        'the bundle with a licensed electrician or the cabling designer against '
        'the current adopted NEC.',
  ),
  NecArticle(
    title: 'Antenna and mast grounding and bonding (Article 810)',
    body:
        'Outdoor APs, sector and panel antennas, and masts must be grounded and '
        'bonded, with a listed antenna discharge unit (surge arrestor) on each '
        'lead-in near the point of entry. The grounding conductor runs as '
        'straight as practical and is protected from damage. The purpose is to '
        'bleed off static and give a nearby lightning strike a low-impedance '
        'path to earth so surge does not ride the coax into the building.',
    caveat:
        'Honest caveat: nothing survives a direct strike. Bonding and surge '
        'protection mitigate nearby strikes and static, not a direct hit. '
        'Conductor sizing and bonding details are an electrician\'s call.',
  ),
  NecArticle(
    title: 'Firestopping fire-rated walls and floors (Article 300.21)',
    body:
        'When cable passes through a fire-rated wall or floor, the opening '
        'around it must be firestopped to restore the assembly\'s rating and '
        'stop smoke and flame spread. A rated wall is usually placarded above '
        'the ceiling.',
    stop:
        'STOP: the approved firestop is a specific listed assembly, matched to '
        'the wall type, the penetrant, and the opening, and enforced by the '
        'building code and AHJ. Never improvise it and never pick the assembly '
        'yourself. Recognize the rated wall, then it is a listed-system and AHJ '
        'matter.',
  ),
  NecArticle(
    title: 'Abandoned cable (Article 800.25)',
    body:
        'The accessible portion of communications cable that is not terminated '
        'at equipment and not tagged for future use must be removed. Decades of '
        'dead cable is a fuel load in the ceiling. Cable inside a raceway is '
        'treated as concealed and is not "accessible." On a refresh, you own '
        'removing the old runs, not just adding new ones.',
  ),
];

// ─────────────────── supporting reference: the cable ladder ──────────────────

/// The heading that sets the cable-rating ladder apart from the six gotchas,
/// mirroring the plate's separate supporting band. Verbatim label.
const String kNecCableLadderSectionTitle =
    'Supporting reference: the cable fire-rating ladder';

/// The Article 800 communications-cable rating ladder — a SUPPORTING reference,
/// not one of the six gotchas. Verbatim from the copy. Rendered set apart under
/// [kNecCableLadderSectionTitle] so the six numbered gotchas stay a clean set of
/// six (matching the lead, the recap, and the plate's separate ladder band).
const NecArticle kNecCableLadder = NecArticle(
  title: 'The communications-cable rating ladder (Article 800)',
  body: 'This is a jacket fire-rating only. It says nothing about data '
      'performance.',
  bullets: <String>[
    'CMP: plenum. Highest, usable anywhere.',
    'CMR: riser. Vertical shafts, between floors.',
    'CM / CMG: general purpose.',
    'CMX: dwelling or limited use.',
  ],
  tail:
      'Substitution runs downhill only. CMP can replace CMR anywhere, but CMR '
      'cannot be used in a plenum. Parallel ladders exist for power-limited '
      'cable (CL2P/CL3P) and optical (OFNP/OFCP).',
);

// ────────────────────────── Why a WLAN pro cares ────────────────────────────

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kNecWlanCares =
    'These six are the code articles most likely to surface on an everyday '
    'install: the hoistway you cannot use, the plenum that dictates your cable '
    'jacket, the PoE bundle that overheats, the antenna that needs grounding, '
    'the fire wall you must not breach, and the dead cable you must pull. '
    'Recognize each one, then defer to the right authority.';

/// The recognize-and-defer footer (rendered as an info band). Verbatim.
const String kNecDeferNote =
    'This is a field reference, not code or design guidance. Confirm '
    'requirements with the AHJ, the architect of record, and a licensed '
    'electrician.';
