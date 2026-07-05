// Safety Basics: PPE + ESD - typed const datasets for the read-only field/trade
// reference screen (Field & Trade Reference set, 2026-07-05).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/04-safety-basics.md,
// SOP-020 PASS): the PPE ladder table, the ESD note, and the recognize-and-STOP
// hazards (named-and-stopped, no procedure). No copy is rewritten here - the
// screen only lays it out.
//
// GL-005 / truthfulness: the PPE ladder and the four STOP hazards are the
// load-bearing facts, so the widget test asserts the anchor rows (the four PPE
// standards, the four named STOP items) against these consts so a future edit
// cannot silently drift a value away from Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; standards designators shown in DM Mono (AppMonoText.inlineCode).

/// Stable catalog tool id - backs the route, the help entry, the bundled diagram
/// PNG (assets/reference/safety-basics.png), and the tests. Permanent.
const String kSafetyBasicsToolId = 'safety-basics';

/// One row of the PPE ladder: the item, the standard it is rated to, and what
/// the rating means. [name] is the gear; [standard] is the ASTM/ANSI/ISEA
/// designator (rendered in mono); [meaning] is the plain read of the rating.
class PpeItem {
  const PpeItem({
    required this.name,
    required this.standard,
    required this.meaning,
  });

  /// The PPE item, e.g. `Hard hat / safety helmet`.
  final String name;

  /// The standard it is rated to, e.g. `ANSI/ISEA Z89.1`.
  final String standard;

  /// What the rating means in the field.
  final String meaning;
}

/// The four PPE items that are the common "let me on the site" baseline,
/// verbatim from the copy.
const List<PpeItem> kPpeItems = <PpeItem>[
  PpeItem(
    name: 'Hard hat / safety helmet',
    standard: 'ANSI/ISEA Z89.1',
    meaning:
        'Type I = top impact only; Type II = top and lateral. Electrical: '
        'Class G (general, to 2,200 V), Class E (to 20,000 V), Class C '
        '(conductive, no electrical protection).',
  ),
  PpeItem(
    name: 'Safety-toe footwear',
    standard: 'ASTM F2413',
    meaning:
        'Impact and compression toe protection; look for the EH mark for '
        'electrical-hazard shock resistance.',
  ),
  PpeItem(
    name: 'High-visibility apparel',
    standard: 'ANSI/ISEA 107',
    meaning:
        'Class 1, 2, or 3 by environment and traffic speed. Class 2 is the '
        'common jobsite bar; Class 3 for high-speed traffic or low light.',
  ),
  PpeItem(
    name: 'Eye protection',
    standard: 'ANSI Z87.1',
    meaning:
        'Impact-rated glasses (marked Z87+); side shields for the drilling '
        'and cutting an install involves.',
  ),
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead: what this reference is and what it is not.
const String kSafetyLead =
    'The personal protective equipment a general contractor expects before it '
    'badges you onto an active site, plus a short note on protecting the '
    'electronics you carry. This is awareness and lookup, not compliance '
    'instruction. The site and your employer own the PPE assessment.';

/// PPE-ladder section intro.
const String kPpeIntro =
    'Four items are the common "let me on the site" baseline: hard hat, '
    'safety-toe footwear, high-visibility apparel, and eye protection. On a '
    'finished office install, street clothes are usually fine. On active '
    'construction, expect the GC to require the four to badge on.';

/// The hard-hat proof-test clarification, rendered as a caption directly under
/// the PPE ladder (a load-bearing safety correction: the dielectric figures are
/// proof-test voltages, never a safe-working limit). Verbatim from the copy.
const String kPpeProofTestNote =
    'The hard-hat Class G (2,200 V) and Class E (20,000 V) figures are '
    'dielectric proof-test voltages, not safe-working ratings; never treat them '
    'as a safe working limit.';

/// Caption under the PPE ladder.
const String kPpeNote =
    'Confirm the site\'s specific PPE policy. The employer and GC set what is '
    'required, not the Toolbox.';

/// The ESD section, protecting the gear not the person. Two paragraphs verbatim.
const List<String> kEsdParagraphs = <String>[
  'Static discharge damages the electronics you install: APs, switches, SFP '
      'and optics modules, line cards, and bare boards. The insidious part is '
      'latent damage. A part passes your initial test, then fails in the field '
      'weeks later.',
  'Controls are cheap and standardized under ANSI/ESD S20.20: a grounded '
      'wrist strap, an ESD mat, and ESD-safe bags for transport. A compliant '
      'wrist strap reads in the high-kilohm to low-megohm range to ground. The '
      'risk is highest in data centers and any time you handle bare optics or '
      'boards. For a sealed AP coming out of a static bag, mounted and cabled, '
      'the risk is lower but not zero.',
];

/// Recognize-and-STOP section intro.
const String kSafetyStopIntro =
    'Some hazards mean stop work and call it in. Recognize them and hand them '
    'off. Do not improvise a workaround.';

/// The four recognize-and-STOP hazards, named-and-stopped, verbatim. Each is a
/// full "recognize it, then stop and hand it off" line - no procedure.
const List<String> kSafetyStopHazards = <String>[
  'Asbestos or lead in older buildings. Drilling or cutting in pre-1980 '
      'construction can disturb asbestos ceiling tiles, plaster, or lead paint. '
      'Stop, do not disturb it, notify the building owner and a licensed '
      'abatement contractor.',
  'Arc flash and energized electrical work. If you see an arc-flash label or '
      'an open energized panel, do not open or work it. That is '
      'qualified-electrician and NFPA 70E / lockout-tagout territory.',
  'Confined spaces. A crawlspace, tunnel, manhole, or some mechanical rooms '
      'can be a permit-required confined space. Stop and check before you enter.',
  'Seismic bracing and ceiling support. Independent support and seismic '
      'bracing design belong to the structural engineer and the AHJ, not to a '
      'field workaround.',
];

/// The closing line under the STOP hazards.
const String kSafetyStopClosing =
    'Never treat any of these as a procedure to run yourself.';

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kSafetyWlanCares =
    'Half your installs happen on a ladder or lift, on an active site, around '
    'other trades. Knowing the PPE ratings a GC will ask for keeps you from '
    'being turned away at the gate, and a few dollars of ESD gear keeps a '
    'switch or optic from a latent failure you will get blamed for. The '
    'stop-and-call-it-in flags keep a drill bit from turning a routine cable '
    'pull into a health or legal incident.';

/// The recognize-and-defer footer (rendered as an info band). Verbatim.
const String kSafetyDeferNote =
    'This is a field reference, not code or design guidance. Confirm '
    'requirements with the AHJ, the architect of record, and a licensed '
    'electrician.';
