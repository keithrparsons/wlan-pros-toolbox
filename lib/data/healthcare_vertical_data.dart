// Healthcare Wi-Fi - typed const datasets for the read-only field/trade
// reference screen (Field & Trade Reference set, 2026-07-05).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/15-healthcare-vertical.md,
// SOP-020 PASS): the WMTS protected-telemetry bands, the EMC / IEC 60601-1-2
// read, the roaming/RTLS grades, the four-authorities table, the pre-quote
// checklist, and the framing prose. No copy is rewritten here - the screen only
// lays it out.
//
// GL-005 / truthfulness: the three WMTS bands, the four (plus biomed)
// authorities, and the eight-item pre-quote checklist are the load-bearing
// facts, so the widget test asserts the anchor items (the 608-614 MHz band, the
// biomed handoff, the voice-and-RTLS grade) against these consts so a future
// edit cannot silently drift a value away from Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing.

/// Stable catalog tool id - backs the route, the help entry, the bundled
/// healthcare-demands plate (assets/reference/healthcare-vertical.png), and the
/// tests. Permanent.
const String kHealthcareVerticalToolId = 'healthcare-vertical';

/// One row of the authorities table. [authority] is the body; [governs] is what
/// it governs for you; [yourMove] is your move.
class HealthcareAuthority {
  const HealthcareAuthority({
    required this.authority,
    required this.governs,
    required this.yourMove,
  });

  /// The authority, e.g. `FDA`.
  final String authority;

  /// What it governs for you.
  final String governs;

  /// Your move.
  final String yourMove;
}

/// The four authorities plus the in-house biomed handoff, verbatim from the
/// copy.
const List<HealthcareAuthority> kHealthcareAuthorities = <HealthcareAuthority>[
  HealthcareAuthority(
    authority: 'HIPAA (HHS)',
    governs:
        'Protected health information: encryption, access control, audit '
        'logging, segmentation',
    yourMove:
        'Design for it; defer policy, business-associate agreements, and risk '
        'analysis to the health system\'s compliance officer',
  ),
  HealthcareAuthority(
    authority: 'FDA',
    governs:
        'Wireless inside the medical device: selection, quality of service, '
        'coexistence, security, EMC, now expected in premarket submissions',
    yourMove:
        'Provide a sane RF environment; defer device qualification to the '
        'maker and biomed',
  ),
  HealthcareAuthority(
    authority: 'FCC',
    governs:
        'Spectrum: WMTS licensing and coordination, and the unlicensed 2.4, 5, '
        'and 6 GHz rules',
    yourMove: 'Respect WMTS as protected; design Wi-Fi within Part 15',
  ),
  HealthcareAuthority(
    authority: 'The Joint Commission',
    governs:
        'Accreditation: Environment of Care, the alarm-management safety goal, '
        'and ICRA and ILSM during construction',
    yourMove:
        'Coordinate; ICRA and ILSM site access is covered in the site-access '
        'reference',
  ),
  HealthcareAuthority(
    authority: 'Clinical and biomedical engineering (in-house)',
    governs: 'The medical devices, their EMC posture, and the telemetry systems',
    yourMove:
        'The single most important handoff: coordinate with biomed before '
        'touching a clinical RF environment',
  ),
];

/// The three WMTS protected-telemetry bands, verbatim from the copy.
const List<String> kWmtsBands = <String>[
  '608 to 614 MHz',
  '1395 to 1400 MHz',
  '1427 to 1432 MHz',
];

/// The RTLS location-tech landscape, verbatim from the copy.
const List<String> kRtlsLandscape = <String>[
  'Wi-Fi-based location, from signal strength or time-of-flight, usually '
      'accurate to several meters unless the APs are dense.',
  'BLE, now the most widely deployed approach, and many enterprise APs can '
      'receive BLE without extra hardware.',
  'Infrared or ultrasound overlays for true room-level or bay-level certainty '
      'where clinical-grade accuracy matters.',
];

/// The eight-item pre-quote checklist, verbatim from the copy.
const List<String> kHealthcarePreQuote = <String>[
  'You are entering a life-critical, EMC-regulated RF environment. Coordinate '
      'with clinical and biomedical engineering first.',
  'Not all patient monitoring is on Wi-Fi. WMTS telemetry is a separate, '
      'licensed system on 608 to 614, 1395 to 1400, and 1427 to 1432 MHz.',
  'Design to voice-and-RTLS grade, not data grade: continuous facility-wide '
      'roaming, overlapping cells, no dead zones.',
  'Segment for performance and for HIPAA, with guest, clinical, device, and '
      'RTLS traffic kept apart.',
  'Design around shielded rooms, and do not fight the MRI Faraday cage.',
  'Coexist on 2.4 GHz respectfully, and lean on 5 and 6 GHz.',
  'Construction access is its own gate: ICRA permit, ILSM measures, and '
      'badging before you drill (see the site-access reference).',
  'Defer the rulings. EMC goes to biomed and the device maker, PHI policy to '
      'compliance, spectrum coordination to the WMTS coordinator, and code and '
      'access to the authority having jurisdiction and the facility.',
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead.
const String kHealthcareLead =
    'The reason a hospital is the one building where you cannot design Wi-Fi '
    'like an office. The air is shared with life-critical, EMC-regulated '
    'devices and a protected telemetry band, a dropped roam can mean a missed '
    'alarm, and four separate authorities plus the in-house biomed team all '
    'have a say. Recognize that stack before you quote, and defer the clinical '
    'and compliance rulings to the people who own them.';

/// The through-line, verbatim.
const String kHealthcareThroughLine =
    'The through-line for the whole entry: coordinate with clinical and '
    'biomedical engineering before you touch a hospital RF environment. '
    'Everything below is why.';

/// "Why it is not an office" paragraph, verbatim.
const String kHealthcareNotOffice =
    'In an office, a slow re-auth is a buffering annoyance. In a hospital, the '
    'same half-second can be a missed telemetry alarm or a paused medication '
    'order. Clinical Wi-Fi carries telemetry, VoWi-Fi nurse-call handsets, '
    'bedside EHR, PACS imaging, and connected infusion pumps, and it is '
    'engineered for no roaming failures and no authentication delay. That is a '
    'different design target than office coverage, and it drives every '
    'decision that follows.';

/// WMTS section intro, verbatim.
const String kWmtsIntro =
    'The Wireless Medical Telemetry Service (WMTS) is a licensed radio service '
    'the FCC created in 2000 to give patient telemetry protected, '
    'interference-managed spectrum. It is a separate radio system from your '
    'Wi-Fi, and it occupies three allocated bands:';

/// WMTS 14-MHz history paragraph, verbatim.
const String kWmtsHistory =
    '14 MHz of protected spectrum in total. The 608 to 614 MHz band sits on TV '
    'channel 37, which no television station uses because it is reserved for '
    'radio astronomy, so it was already quiet. Before WMTS existed, telemetry '
    'rode vacant TV channels and had to accept interference. The digital-TV '
    'transition lit those channels up, and hospitals could lose telemetry when '
    'a local station went digital. WMTS gave telemetry a home that other '
    'services must protect.';

/// WMTS designer-takeaways paragraph, verbatim.
const String kWmtsTakeaway =
    'Two things a WLAN designer has to take from this. WMTS is coordinated by a '
    'designated WMTS coordinator, not something you plan on your own Wi-Fi. And '
    'you must not assume all patient monitoring lives on Wi-Fi. Design over the '
    'WMTS band blind and you can walk into a telemetry system you did not know '
    'was there.';

/// "The shared 2.4 and 5 GHz air" paragraph, verbatim.
const String kHealthcareSharedAir =
    'Plenty of clinical gear does live on standard Wi-Fi or on 2.4 GHz ISM: '
    'infusion pumps, some physiological monitors, ECG carts, wireless pulse '
    'oximeters. In a hospital, 2.4 GHz is a crowded, contended, life-adjacent '
    'band. Treat it with respect, lean on 5 and 6 GHz for capacity, and never '
    'assume clean spectrum.';

/// EMC / IEC 60601-1-2 paragraph 1, verbatim.
const String kEmcStandard =
    'IEC 60601-1-2 is the electromagnetic-compatibility standard in the IEC '
    '60601 family for medical electrical equipment. It governs two directions. '
    'Emissions: a device must not spray interference, with limits based on '
    'CISPR 11. Immunity: a device must keep its essential performance while '
    'bathed in radiated RF, electrostatic discharge, bursts, and surges. '
    'Current editions deliberately raised the immunity test levels because the '
    'RF environment around patients got far busier with Wi-Fi, cellular, and '
    'BLE.';

/// EMC / IEC 60601-1-2 paragraph 2 (the designer's read), verbatim.
const String kEmcDesignerRead =
    'Here is the designer\'s read. Medical devices are tested to tolerate a '
    'defined RF environment, but tested to a limit is not the same as immune '
    'to anything. A dense, high-power Wi-Fi deployment or a mis-sited '
    'high-gain antenna can push local field strength toward what a nearby '
    'monitor or pump was qualified for. Your job is coexistence awareness, not '
    'EMC engineering. Recognize that the devices sharing the space have '
    'essential-performance requirements, and route the EMC questions to '
    'clinical and biomedical engineering, who own the device side.';

/// Roaming paragraph, verbatim.
const String kRoamingHard =
    'Roaming is the hard problem. Clinician handsets, mobile carts, and '
    'telemetry move constantly and must roam facility-wide with no dead zones, '
    'including stairwells, elevators, and back-of-house where a code-alarm '
    'device still has to work. That means overlapping cells, fast-roaming '
    'support (802.11r, k, v), and voice-grade RF planning.';

/// Coverage-grade paragraph, verbatim.
const String kCoverageGrade =
    'Coverage grade drives AP count more than floor area does. The industry '
    'designs to three grades, each needing progressively more APs: data grade, '
    'then voice grade, then voice-and-RTLS grade. A hospital quoted at '
    'data-grade density will fail when it has to carry voice handsets and '
    'location services. Under-scoping here is one of the most common and '
    'expensive mistakes.';

/// RTLS intro, verbatim.
const String kRtlsIntro =
    'RTLS (real-time location of assets, staff, and patients) is one of the '
    'highest-value hospital wireless applications, and it often has to run on '
    'the same infrastructure you are already building. The landscape:';

/// RTLS grade-driver note, verbatim.
const String kRtlsGradeDriver =
    'Supporting RTLS is what pushes the design to the voice-and-RTLS grade in '
    'the first place.';

/// Segmentation paragraph, verbatim.
const String kHealthcareSegmentation =
    'Segmentation is a performance control here, not only a security one. A '
    'ward full of guests streaming video must not share airtime with voice '
    'handsets, mobile chart sessions, or telemetry. Guest, clinical, device, '
    'and RTLS traffic get separated for airtime protection as much as for '
    'HIPAA.';

/// The "building fights you" caution (rendered as a warning band), verbatim.
const String kHealthcareBuildingWarning =
    'And the building fights you. Lead-lined radiology walls and RF-shielded '
    'MRI suites (Faraday cages, where RF deliberately does not pass) shape '
    'propagation in ways an office never does. Design around the shielded '
    'rooms, and do not expect coverage into an MRI room.';

/// Lead-in to the authorities table, verbatim.
const String kHealthcareAuthoritiesIntro =
    'No single WLAN certification teaches this stack. Recognize each '
    'authority, then defer.';

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kHealthcareWlanCares =
    'A hospital is the highest-stakes Wi-Fi you will design, and the "just '
    'cover it like an office" instinct is exactly the mistake that gets '
    'telemetry stepped on and alarms missed. Knowing the WMTS band, the EMC '
    'standard, the roaming and RTLS grades, and the four authorities lets you '
    'quote it honestly and hand the clinical rulings to biomed instead of '
    'guessing.';

/// The defer footer (rendered as an info band). Verbatim.
const String kHealthcareDeferNote =
    'This is a field reference, not clinical, code, or compliance guidance. '
    'Confirm every requirement with clinical and biomedical engineering, the '
    'health system\'s compliance and security officers, the WMTS coordinator, '
    'and the authority having jurisdiction for the specific facility. The '
    'Toolbox asserts no compliance ruling and certifies nothing.';
