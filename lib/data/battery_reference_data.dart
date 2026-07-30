// Batteries — typed const datasets for the read-only "decode the markings"
// reference screen (Quick Reference / Power & Cooling).
//
// SOLE DATA SOURCE (GL-005): Pax's clean-room research brief
// Deliverables/2026-07-25-battery-sd-reference/FINDINGS.md, Part 1. Every
// dimension, voltage, date, and phone number below traces to that file, which
// in turn cites IEC 60086-1:2021 / 60086-2:2021 publisher previews, Energizer /
// Renata / FDK datasheets, the CPSC button-cell rule, and FAA PackSafe. No
// figure is added here that FINDINGS does not carry.
//
// The brief's explicit DO-NOT-PRINT list is honored:
//   * The AA 1907 / AAA 1911 introduction dates are UNVERIFIED (Wikipedia and
//     content farms only). Absent.
//   * "The B size was skipped to avoid clashing with the radio B battery" is
//     FOLKLORE with no primary source. Absent. The DISTINCTION between the two
//     senses of "B battery" is solid and IS shown; the causal claim is not.
//   * The 1.5 V USB-C rechargeable Li-ion AA has no standards designation and no
//     usable datasheet, so it appears as prose caution with NO numbers.
//   * No capacity is stated as a bare single number. Capacity is load-dependent
//     and the two figures that do appear (FDK HR-AUE 2700 mAh, LiFePO4 cycle
//     life) are labeled to their specific cell and datasheet. The FDK figure
//     additionally names itself a NAMEPLATE rating, because it is a rated
//     number with no load behind it, which is a different kind of number from
//     the load-stated capacities the page argues for (FINDINGS, "the FDK figure
//     is a nameplate rating", corrected 2026-07-25 after Vera found it shipping
//     bare). A capacity with neither a load nor a nameplate label is guarded
//     against by test.
//
// FOUR RETRACTIONS, 2026-07-25. This file shipped four claims that FINDINGS has
// since refuted. All four are now guarded by name in batteries_screen_test.dart
// so they cannot walk back in:
//   * "A five-digit code splits three plus two; CR2450 is 24.5 mm by 5.0 mm,
//     read as 245 then 0." REFUTED on its own arithmetic. CR2450 has FOUR
//     digits, and under the rule this page teaches (height group in tenths of a
//     millimeter) a height group of `0` is 0.0 mm, not 5.0. The second example
//     failed too: `14505` split three-plus-two gives 0.5 mm against the 50.5 mm
//     the same sentence asserted. Replaced with the datasheet-pinned rule below.
//   * "PR1154 is the dimensional code for the same can LR44 names by catalog
//     number." REFUTED twice over. The split does not parse (digits 1,1,5,4:
//     "11.5" consumes 1,1,5 and "5.4" then needs 5,4, so the 5 does double
//     duty), AND `PR1154` is not a designation. No manufacturer datasheet and no
//     standards document carries it; every manufacturer calls that zinc-air cell
//     `PR44`. It survives only on retail cross-reference pages. REMOVED, not
//     corrected. `LR1154` does the same job and is datasheet-pinned.
//   * "The A cell is 17.0 mm by 50.0 mm." SUPERSEDED by Saft LS17500, Doc
//     31029-2-0710: 17.13 by 50.90 mm. The to-scale size-ladder graphic is drawn
//     on the datasheet figure, so the old number would have put the screen and
//     the graphic in visible disagreement.
//   * "The B cell is 21.5 mm by 60 mm." WITHDRAWN. That figure traces to a
//     battery-equivalence site, the exact source class this research bans, and
//     no standalone B cell datasheet exists because nobody sells one. The
//     dimension is now stated as UNAVAILABLE rather than guessed, which is what
//     the ladder graphic draws too: an honestly empty labeled slot.
//
// The load-bearing correction the page exists to deliver: the round-cell code IS
// dimensional and the two-digit button-cell catalog number is NOT, and both
// conventions sit in the same IEC 60086-2:2021 Clause 7 block. Everyone teaches
// only the first half.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash or en dash;
// US spelling; "Wi-Fi" never "WiFi"; no marketing words.

/// Stable catalog tool id — backs the route, the help entry, the hero graphic
/// slot, and the tests. Permanent.
const String kBatteriesToolId = 'batteries';

// ─────────────────────────────── framing lead ───────────────────────────────

/// The lead. Conclusion first: the code on the cell tells you something, but
/// which something depends on which family you are holding.
const String kBatteryLead =
    'A cell name encodes its chemistry, and the chemistry sets the voltage. It '
    'sometimes encodes the size too, and sometimes it does not. The round-cell '
    'codes are dimensional, from a 3.2 mm coin to a 34.5 mm cylinder on one '
    'rule; the aqueous button numbers beside them in the same standard are '
    'catalog entries. Read both conventions before you trust a code to tell you '
    'what fits.';

// ────────────────────── 1. reading the coin / button code ───────────────────

/// The dimensional rule, datasheet-pinned. Four worked codes reproduce their
/// cans on it, and it is NOT a coin-cell rule: it reaches a 34.5 mm cylinder
/// without modification. Replaces the refuted "five digits split three plus
/// two" claim (see the retraction block at the head of this file).
const String kCoinCodeRule =
    'A round-cell code reads chemistry, then R for round, then a diameter code, '
    'then a height code. The diameter code is whole millimeters, TRUNCATED, so '
    'it is a floor and not the cell diameter. The height code is tenths of a '
    'millimeter, exact. Read the height from the right; everything to its left '
    'is the diameter. The letters carry the chemistry: C is lithium manganese '
    'dioxide, B is lithium carbon monofluoride, R means round.';

/// The asymmetry between the two halves of the code. This is the actual
/// teaching point, and it explains every apparent disagreement between a code
/// and a datasheet.
const String kCodeRoundsPartDoesNot =
    'The two halves of the code are not the same kind of number. The height IS '
    'the height, exactly: CR2032 reads 32 and the can measures 3.20 mm. The '
    'diameter is only a floor: LR1154 reads 11 and the can measures 11.60 mm. '
    'That same cell settles truncation against rounding, because 11.60 rounds '
    'to 12 under any convention and the code still says 11. The code truncates; '
    'the part does not. Where a code and a datasheet disagree on diameter, the '
    'datasheet is the measurement.';

/// The one line worth carrying out of the section. It holds on all seven codes
/// checked against a datasheet, and it escapes the circularity in "three digits
/// at 10 mm and over," which a reader cannot apply without already knowing the
/// height.
const String kHeightGroupRule =
    'A two-digit height group means you are holding a coin. A three-digit height '
    'group means you are holding a cylinder. CR2032 reads 32, so 3.2 mm high, a '
    'coin. CR17345, which is the CR123A, reads 345, so 34.5 mm high, a cylinder. '
    'The diameter is always whole millimeters, so CR17345 cannot be read as 173 '
    'plus 45. This holds on all seven codes checked against a datasheet.';

/// The half of the story that is normally left out.
const String kButtonCodeRule =
    'The aqueous button cells mostly do NOT work that way. Many LR, SR, and PR '
    'numbers are arbitrary catalog entries. LR44 is not 4 mm by 4.4 mm. It is '
    'catalog entry 44. Both conventions are listed in one block of IEC '
    '60086-2:2021 Clause 7, Category 4, which is why one cell can carry both '
    'kinds of name: LR1154 is the dimensional code for exactly the can LR44 '
    'names by catalog number. Which form a datasheet prints tracks registration '
    'history, not chemistry.';

/// One worked example of a cell code.
///
/// [meaning] and [datasheet] are two DIFFERENT quantities and the type keeps
/// them apart on purpose. A nominal designation is not a measurement: the code
/// truncates the diameter and the part does not. FINDINGS is explicit that any
/// surface printing both must say which is which, "because a reader who spots
/// the discrepancy and is given no explanation concludes the source is sloppy."
/// Collapsing these two fields back into one prose string is how the PR1154
/// error got in.
class CellCode {
  const CellCode({
    required this.code,
    required this.reads,
    required this.meaning,
    required this.datasheet,
    required this.dimensional,
  });

  /// The code printed on the cell, e.g. `CR2032`.
  final String code;

  /// How the digits split, e.g. `20 + 32`.
  final String reads;

  /// What the CODE says. For a dimensional code the diameter is a floor and the
  /// height is exact. For a catalog number it says nothing about size at all.
  final String meaning;

  /// What the PART measures, per a named datasheet. This is the measurement,
  /// and it is where the code and the object disagree.
  final String datasheet;

  /// True when the digits genuinely encode dimensions; false when the number is
  /// a catalog entry that only looks dimensional.
  final bool dimensional;
}

/// Worked code examples, dimensional first, then the catalog-number cases that
/// break the pattern. Every row is pinned on BOTH sides in FINDINGS: the split
/// the rule predicts, and a named datasheet for the can.
///
/// The set is chosen to make the rule falsifiable rather than illustrated:
///   * CR2032  — the coin everyone already knows; code and can agree exactly.
///   * CR2450  — four digits, read two and two. The old copy called this a
///               five-digit code and it is not.
///   * LR1154  — the truncation witness. 11.60 rounds to 12 under any
///               convention and the code says 11, so the rule is truncation,
///               not rounding. Also the same can as LR44, one row down.
///   * CR15H270 — the SECOND independent truncation witness (15.60 to 15), so
///               the rule is cross-verified rather than single-sourced. Also
///               shows an interior letter, which this page deliberately does
///               not decode.
///   * FR14505 — three-digit height group, so a cylinder. It is FR and not CR:
///               F is lithium iron disulfide. (An earlier draft of this file
///               wrote CR14505, which the Energizer datasheet does not.)
///   * CR17345 — the CR123A, a 34.5 mm cylinder read by the same rule with no
///               modification. This is why it is not a "coin cell code."
const List<CellCode> kCellCodes = <CellCode>[
  CellCode(
    code: 'CR2032',
    reads: '20 + 32',
    meaning: 'Diameter at least 20 mm, height 3.2 mm exactly. Lithium '
        'manganese dioxide, 3.0 V.',
    datasheet: 'Can measures 20.00 mm by 3.20 mm (Energizer, Form 2032NA0618).',
    dimensional: true,
  ),
  CellCode(
    code: 'CR2450',
    reads: '24 + 50',
    meaning: 'Diameter at least 24 mm, height 5.0 mm exactly. Four digits, '
        'read two and two.',
    datasheet: 'Can measures 24.50 mm by 5.00 mm (Energizer 2450NA0521; '
        'Panasonic).',
    dimensional: true,
  ),
  CellCode(
    code: 'LR1154',
    reads: '11 + 54',
    meaning: 'Diameter at least 11 mm, height 5.4 mm exactly. This is the same '
        'cell LR44 names by catalog number.',
    datasheet: 'Can measures 11.60 mm by 5.40 mm (Energizer A76, Form '
        'EBC-4407F). 11.60 rounds to 12 and the code says 11, so the rule is '
        'truncation.',
    dimensional: true,
  ),
  CellCode(
    code: 'CR15H270',
    reads: '15 + 270',
    meaning: 'Diameter at least 15 mm, height 27.0 mm exactly. This is the '
        'CR2. The interior H is part of the code and is not decoded here.',
    datasheet: 'Can measures 15.60 mm by 27.00 mm (Energizer 1CR2, Form '
        '1CR2GL1018). Second witness for truncation: 15.60 rounds to 16.',
    dimensional: true,
  ),
  CellCode(
    code: 'FR14505',
    reads: '14 + 505',
    // The chemistry letter is load-bearing and this page gets it right: the
    // Energizer datasheet reads FR14505 (FR6). An earlier draft of this file
    // wrote a C here, which names a chemistry this cell does not have. The
    // retraction guard bans that string from shipped copy, so the correction
    // is stated positively rather than by naming the wrong code.
    meaning: 'Diameter at least 14 mm, height 50.5 mm exactly. Three-digit '
        'height group, so a cylinder. F is the chemistry letter for lithium '
        'iron disulfide, which is what makes this the lithium AA.',
    datasheet: 'Can measures 14.50 mm by 50.50 mm (Energizer L91, Form '
        'L91GL1222).',
    dimensional: true,
  ),
  CellCode(
    code: 'CR17345',
    reads: '17 + 345',
    meaning: 'Diameter at least 17 mm, height 34.5 mm exactly. This is the '
        'CR123A, and the same rule reads it with no modification.',
    datasheet: 'Can measures 17.00 mm by 34.50 mm (Energizer 123, Form '
        '123GL1018; GP doc 20190912; Panasonic CR17345).',
    dimensional: true,
  ),
  CellCode(
    code: 'LR44',
    reads: 'entry 44',
    meaning: 'A catalog number, not a measurement. It says nothing about size. '
        'Alkaline, 1.5 V.',
    datasheet: 'Can measures 11.60 mm by 5.40 mm, the same can LR1154 names '
        'dimensionally (Energizer A76, Form EBC-4407F).',
    dimensional: false,
  ),
  CellCode(
    code: 'SR44',
    reads: 'entry 44',
    meaning: 'Same catalog entry, different chemistry. Silver oxide, 1.55 V.',
    datasheet: 'Can measures 11.60 mm by 5.40 mm, identical to LR44.',
    dimensional: false,
  ),
];

// ─────────────────────────── 2. the size ladder ─────────────────────────────

/// The counter-intuitive rule the section leads with.
const String kSizeLadderRule =
    'The doubled letter means smaller, not bigger. The ladder runs N, AAAA, AAA, '
    'AA, A, B, C, D, F, G from smallest to largest, so AA is SMALLER than A and '
    'AAA is smaller than AA. A and B are the two rungs that left the retail '
    'shelf, which is why the ladder looks like it has a hole in the middle.';

/// One rung of the ladder. [dimensions] is NULLABLE on purpose.
///
/// The B cell has no dimension that survives this research's sourcing rule: the
/// widely quoted 21.5 mm by 60 mm traces to a battery-equivalence site, which is
/// the exact source class FINDINGS bans, and no standalone B datasheet exists
/// because nobody sells one. A `null` here renders as an explicit "no datasheet"
/// state rather than a guess. The size-ladder graphic draws the same thing: an
/// honestly empty labeled slot, because the shelf gap IS the point.
///
/// Making this field non-nullable is what forced the invented figure last time.
/// A type that cannot express "unknown" will always be handed a number.
class BatterySizeRung {
  const BatterySizeRung({
    required this.size,
    required this.dimensions,
    required this.status,
    required this.pin,
  });

  /// Size letter, e.g. `AA`.
  final String size;

  /// Maximum diameter by maximum height, e.g. `14.50 mm x 50.50 mm`, or `null`
  /// when no datasheet gives one. Never a figure from an equivalence site.
  final String? dimensions;

  /// Where you actually meet it today.
  final String status;

  /// The datasheet the dimension came from, or the reason there is none.
  final String pin;
}

/// The three rungs the research covers, smallest to largest. All dimensions are
/// datasheet maxima. No dimension is invented for the rungs the brief does not
/// cover, and none is invented for B, which has no datasheet at all.
const List<BatterySizeRung> kBatterySizeRungs = <BatterySizeRung>[
  BatterySizeRung(
    size: 'AA',
    dimensions: '14.50 mm x 50.50 mm',
    status: 'On every shelf. The lithium AA also carries the dimensional code '
        'FR14505, whose 14 and 505 groups agree with the datasheet: at least 14 '
        'mm across, 50.5 mm tall.',
    pin: 'Energizer L91, Form L91GL1222.',
  ),
  BatterySizeRung(
    size: 'A',
    dimensions: '17.13 mm x 50.90 mm',
    status:
        'In current production, inside packs rather than on shelves. FDK HR-AUE '
        'is a 1.2 V NiMH A cell whose 2700 mAh is a nameplate rating: a '
        'datasheet headline, not a capacity measured at a stated load. Saft '
        'LS17500 is a 3.6 V lithium thionyl chloride A cell. LS17500 is a Saft '
        'house code and not an IEC dimensional code, so do not read a size out '
        'of it: it disagrees with the measured can.',
    pin: 'Saft LS17500, Doc 31029-2-0710.',
  ),
  // No dimension, on purpose. The figure in general circulation traces to a
  // battery-equivalence site, which is the source class this research bans, and
  // no standalone B datasheet exists because nobody sells one. The retracted
  // number is deliberately NOT quoted in shipped copy even to debunk it: a
  // reader takes a number off a screen far more readily than they take the
  // sentence around it, and the retraction guard in the test bans the digits
  // outright so no future edit can reintroduce them under any framing.
  BatterySizeRung(
    size: 'B',
    dimensions: null,
    status:
        'Survives only inside the 3R12 and 3LR12 flat 4.5 V battery. There is no '
        'retail single B cell, and no standalone B datasheet exists because '
        'nobody sells one.',
    pin: 'No datasheet found. The dimensions in general circulation trace to '
        'battery-equivalence sites, which is not a source this page prints '
        'from.',
  ),
];

/// What the table renders in the dimensions column when there is no datasheet.
/// A named constant so the "unknown" state is one string the tests can pin,
/// rather than a literal an edit could turn back into a number.
const String kNoDatasheetDimension = 'No datasheet';

/// The evidence from the standard: the round single-cell types IEC 60086-2:2021
/// Clause 7 (pp. 11-12) actually enumerates. Rendered verbatim as the reason to
/// believe the A and B claim.
const String kIecRoundSingleCellList =
    'R1, R03, R6P, R6S, R14P, R14S, R20P, R20S, LR8D425, LR1, LR03, LR6, LR14, '
    'LR20, FR10G445, FR14505';

/// What is missing from that list, and what it means.
const String kIecMissingSizes =
    'There is no R23 (size A) and no single-cell R12 (size B) anywhere in that '
    'list. The only R12 entries in the standard are the multi-cell 3R12P, 3R12S, '
    'and 3LR12: the 4.5 V flat battery, which is the last home of the B cell.';

/// The two senses of "B battery," kept apart. FINDINGS: the distinction is
/// solid; the folklore explanation for why B left the size ladder is not, and is
/// deliberately absent.
const String kTwoSensesOfB =
    'Two unrelated things are called a B battery. One is the size rung above A. '
    'The other is a circuit ROLE from valve-era radio, where the B supply ran the '
    'plate at 45 V to 90 V and was never a size at all. Keep them apart when you '
    'read old documentation.';

// ─────────────────────── 3. the two naming systems ──────────────────────────

/// One naming system and the shape of the code it produces.
class NamingSystem {
  const NamingSystem({
    required this.system,
    required this.shape,
    required this.aaAlkaline,
  });

  /// System name, e.g. `IEC 60086`.
  final String system;

  /// What the code is made of.
  final String shape;

  /// What an alkaline AA is called under this system.
  final String aaAlkaline;
}

/// The two systems, which disagree by design.
const List<NamingSystem> kNamingSystems = <NamingSystem>[
  NamingSystem(
    system: 'ANSI / NEDA',
    shape:
        'An arbitrary catalog number plus a chemistry suffix. Carries no '
        'dimensional information at all.',
    aaAlkaline: '15A',
  ),
  NamingSystem(
    system: 'IEC 60086',
    shape:
        'Chemistry letter, then shape letter, then size code. Systematic by '
        'design.',
    aaAlkaline: 'LR6',
  ),
];

/// The anti-pattern: one IEC code per size is wrong, because the code moves with
/// the chemistry for the same physical cell.
const String kOneCodePerSizeIsWrong =
    'Do not memorize one IEC code per size. The code changes with the chemistry '
    'for the SAME physical cell: an AA is LR6 in alkaline, R6 in zinc-carbon, '
    'FR6 or FR14505 in lithium iron disulfide, HR6 in NiMH, and KR6 in NiCd. A '
    'bare R6 is incomplete on top of that, because the standard lists R6P (zinc '
    'chloride) and R6S (Leclanche) as separate specifications.';

/// The small true thing about the 9 V battery. Both are on Energizer's own
/// datasheet.
const String kNineVoltNote =
    'The 9 V block reads cleanly once you know the letters. 6LR61 is six cells, '
    'alkaline, ROUND, size 61. 6LF22 is six cells, alkaline, FLAT, size 22. Same '
    '9 V battery, different internal construction, both on Energizer datasheets.';

// ──────────────────────── 4. chemistry letters ──────────────────────────────

/// One chemistry letter from IEC 60086-1:2021 section 4.1.4, Table 1, p. 13.
class ChemistryLetter {
  const ChemistryLetter({
    required this.letter,
    required this.system,
    required this.nominal,
    required this.maxOcv,
  });

  /// The IEC chemistry letter, or `(none)` for zinc-carbon.
  final String letter;

  /// The electrochemical system.
  final String system;

  /// Nominal voltage, e.g. `1.5 V`.
  final String nominal;

  /// Maximum open-circuit voltage, e.g. `1.83 V`. This is the number that
  /// surprises people on lithium primaries.
  final String maxOcv;
}

/// Primary chemistries, from IEC 60086-1:2021 Table 1. IEC 60086 is titled
/// Primary batteries, so rechargeables are NOT in it; they are listed
/// separately below.
const List<ChemistryLetter> kChemistryLetters = <ChemistryLetter>[
  ChemistryLetter(
    letter: '(none)',
    system: 'Zinc-carbon',
    nominal: '1.5 V',
    maxOcv: '1.73 V',
  ),
  ChemistryLetter(
    letter: 'L',
    system: 'Alkaline zinc / manganese dioxide',
    nominal: '1.5 V',
    maxOcv: '1.68 V',
  ),
  ChemistryLetter(
    letter: 'F',
    system: 'Lithium iron disulfide',
    nominal: '1.5 V',
    maxOcv: '1.83 V',
  ),
  ChemistryLetter(
    letter: 'C',
    system: 'Lithium manganese dioxide',
    nominal: '3.0 V',
    maxOcv: '3.7 V',
  ),
  ChemistryLetter(
    letter: 'B',
    system: 'Lithium carbon monofluoride',
    nominal: '3.0 V',
    maxOcv: '3.7 V',
  ),
  ChemistryLetter(
    letter: 'E',
    system: 'Lithium thionyl chloride',
    nominal: '3.6 V',
    maxOcv: '3.9 V',
  ),
  ChemistryLetter(
    letter: 'S',
    system: 'Silver oxide',
    nominal: '1.55 V',
    maxOcv: '1.63 V',
  ),
  ChemistryLetter(
    letter: 'P',
    system: 'Zinc-air',
    nominal: '1.4 V / 1.45 V',
    maxOcv: '1.59 V',
  ),
  ChemistryLetter(
    letter: 'Z',
    system: 'Zinc / nickel oxyhydroxide',
    nominal: '1.5 V',
    maxOcv: '1.78 V',
  ),
];

/// Rechargeable prefixes, which live under IEC 61951 / 61960 rather than 60086.
const List<ChemistryLetter> kRechargeableLetters = <ChemistryLetter>[
  ChemistryLetter(
    letter: 'HR',
    system: 'Nickel metal hydride (NiMH)',
    nominal: '1.2 V',
    maxOcv: 'Not in IEC 60086',
  ),
  ChemistryLetter(
    letter: 'KR',
    system: 'Nickel cadmium (NiCd)',
    nominal: '1.2 V',
    maxOcv: 'Not in IEC 60086',
  ),
  ChemistryLetter(
    letter: 'IFR',
    system: 'Lithium iron phosphate (LiFePO4)',
    nominal: '3.2 V',
    maxOcv: 'Not in IEC 60086',
  ),
];

/// Why the rechargeables sit in a separate table.
const String kRechargeableNote =
    'IEC 60086 is titled Primary batteries, so rechargeables are not in it. They '
    'sit under IEC 61951 and 61960 with their own prefixes.';

// ─────────────────── 5. LR44 vs SR44, the equivalence trap ──────────────────

/// One property compared across the alkaline and silver-oxide cell that share a
/// can.
class SubstitutionRow {
  const SubstitutionRow({
    required this.property,
    required this.alkaline,
    required this.silver,
  });

  /// What is being compared, e.g. `Nominal voltage`.
  final String property;

  /// The LR44 (alkaline) value.
  final String alkaline;

  /// The SR44 (silver oxide) value.
  final String silver;
}

/// LR44 against SR44: the same lump of metal, and a different battery.
const List<SubstitutionRow> kLr44VsSr44 = <SubstitutionRow>[
  SubstitutionRow(
    property: 'Chemistry',
    alkaline: 'Alkaline',
    silver: 'Silver oxide',
  ),
  SubstitutionRow(
    property: 'Can size',
    alkaline: '11.60 mm x 5.40 mm',
    silver: '11.60 mm x 5.40 mm',
  ),
  SubstitutionRow(
    property: 'Nominal voltage',
    alkaline: '1.5 V',
    silver: '1.55 V',
  ),
  SubstitutionRow(
    property: 'Discharge shape',
    alkaline: 'Sloping, 1.55 V down to 0.9 V',
    silver: 'Flat, holds near 1.55 V for ~600 h, then falls',
  ),
  SubstitutionRow(
    property: 'Substituting it',
    alkaline:
        'Alkaline into a silver-oxide slot drifts a precision instrument as the '
        'voltage sags',
    silver: 'Silver oxide into an alkaline slot is safe',
  ),
];

/// The alkaline cross-reference zoo. All of these name the same can.
const String kLr44CrossReference =
    'LR44, LR1154, A76, AG13, L1154, V13GA, 1166A';

/// The silver-oxide cross-reference zoo. Same can, different chemistry.
const String kSr44CrossReference =
    'SR44, SR1154, 357, 303, SR44W, SR44SW, 1131SO, V357, S76';

/// AG13 is trade shorthand, not a designation any body administers.
const String kAg13Caveat =
    'AG13 is not an IEC or an ANSI designation. It is an import-trade code that '
    'nobody administers. Treat it as a hint about the can, never as a '
    'specification.';

/// 357 vs 303: the whole distinction rides on a suffix retailers drop.
const String k357Vs303 =
    'The 357 and 303 numbers split on drain rate, and the suffix carries the '
    'entire distinction: 357 is SR1154W, the high-drain cell, and 303 is '
    'SR1154SW, the low-drain cell. Retailers routinely drop the W and SW, which '
    'is how the wrong one ends up in a meter.';

/// The mercury trap, for vintage gear.
const String kMercuryTrap =
    'Old gear specified for a PX625 or MR9 wanted 1.35 V from a mercury cell. '
    'Mercury cells are banned, and the alkaline sold as the replacement is 1.5 V '
    'with a sloping curve. It fits, it powers the meter, and it silently '
    'miscalibrates a vintage light meter across its life.';

// ─────────────── 6. the 1.5 V vs 1.2 V voltage gotcha ───────────────────────

/// The framing: the real problem is the gauge, not whether the device runs.
const String kVoltageGotchaLead =
    'The real problem with running NiMH in a 1.5 V slot is that a voltage-based '
    'fuel gauge cannot read a NiMH curve at all. Four alkaline cells give 6.0 V '
    'and four NiMH cells give 4.8 V, a 20 percent shortfall, and most devices '
    'run fine on it. The gauge is what breaks.';

/// One consequence of the alkaline / NiMH voltage difference.
class VoltageGotcha {
  const VoltageGotcha({required this.heading, required this.detail});

  /// Short heading, e.g. `The fuel gauge lies`.
  final String heading;

  /// The explanation.
  final String detail;
}

/// Where the 1.5 V versus 1.2 V difference actually bites.
const List<VoltageGotcha> kVoltageGotchas = <VoltageGotcha>[
  VoltageGotcha(
    heading: 'The fuel gauge cannot read it',
    detail:
        'Alkaline slides continuously from 1.5 V down to 0.8 V, so a voltage '
        'reading maps onto a state of charge. NiMH sits on a flat plateau just '
        'above 1.2 V and then falls off a cliff. A voltage-based gauge has '
        'nothing to resolve on a flat curve, so the meter reads full until it '
        'reads empty.',
  ),
  VoltageGotcha(
    heading: 'Low-voltage cutoff fires early',
    detail:
        'A device with a 5.0 V brownout threshold runs happily on four '
        'alkalines at 6.0 V and refuses to start on four fully charged NiMH '
        'cells at 4.8 V. Nothing is wrong with the pack.',
    ),
  VoltageGotcha(
    heading: 'The failure is abrupt',
    detail:
        'Alkaline warns you by fading. NiMH does not fade, so plan on a spare '
        'rather than on noticing.',
  ),
  VoltageGotcha(
    heading: 'Cameras invert it',
    detail:
        'At high drain the alkaline cell internal resistance pulls its terminal '
        'voltage below the NiMH cell voltage, so the chemistry with the lower '
        'nominal voltage runs longer. This is why NiMH won in cameras.',
  ),
];

/// The rarer gotcha in the other direction.
const String kLithiumOverVoltage =
    'The opposite trap is rarer and more surprising. A lithium primary AA is '
    'sold as a 1.5 V cell, but IEC gives its maximum open-circuit voltage as '
    '1.83 V and the Energizer L91 curve opens near 1.7 V to 1.8 V. A fresh '
    'four-cell lithium pack can present near 7 V where the design expected 6 V.';

// ────────────────────────────── 7. safety ───────────────────────────────────

/// The mechanism, stated correctly. This is a life-safety fact and the wording
/// is deliberate: it is electrolysis and hydroxide, not a leak and not choking.
const String kIngestionMechanism =
    'A swallowed button cell burns tissue with its own current. A cell lodged in '
    'the esophagus completes a circuit through moist tissue, electrolysis at the '
    'negative pole generates hydroxide, and the hydroxide causes liquefactive '
    'necrosis. The injury is electrochemical, so the cell does not need to leak, '
    'does not need to be old, and does not need to block the airway to do '
    'serious harm.';

/// The counter-intuitive corollary that changes how you handle a fresh cell.
const String kIngestionFreshCellIsWorst =
    'A brand new, fully charged cell is the MOST dangerous one, because the '
    'injury is driven by the current the cell can still deliver. A dead cell '
    'pulled out of a sensor is the safer object on the bench.';

/// Energizer's own datasheet language plus the size that lodges.
const String kIngestionTiming =
    'Energizer states on its own CR2032 datasheet that swallowing "may lead to '
    'serious injury or death in as little as 2 hours." The 20 mm lithium coin '
    'cell is the one most often implicated, because 20 mm is the diameter that '
    'lodges rather than passes.';

/// The US hotline, printed as a plain number.
const String kIngestionHotline =
    'US National Battery Ingestion Hotline: 800-498-8666.';

/// Why modern gear has a screwed-down coin-cell door.
const String kReesesLaw =
    'Reese\'s Law directed the CPSC to act. The rule was adopted 11 September '
    '2023, incorporating UL 4200A, and published in the Federal Register on 21 '
    'September 2023. It requires child-resistant battery compartments, which is '
    'why the coin-cell door on new gear is screwed down.';

// ───────────────────────────── 8. air travel ────────────────────────────────

/// The rule that matters for a kit bag, per FAA PackSafe.
const String kAirTravelRule =
    'Spare lithium cells of any size go in the cabin, never in checked baggage. '
    'Installed cells may be checked if the device is powered off. Consumer '
    'lithium primaries clear the lithium-content limits easily: Energizer rates '
    'the L91 AA at less than 1 gram and the CR2032 at 0.109 grams against a 2 g '
    'threshold.';

/// What the rule is actually protecting against.
const String kAirTravelTerminals =
    'The real hazard is a short circuit, so terminals must be protected. Loose '
    'AA lithium cells rattling in a tool bag against metal is the thing the rule '
    'exists to stop, not the gram count.';

// ──────────────────────── 9. field slant for Wi-Fi work ─────────────────────

/// One place a Wi-Fi engineer actually meets a cell, and why that cell is there.
class BatteryFieldUse {
  const BatteryFieldUse({
    required this.where,
    required this.cell,
    required this.why,
  });

  /// Where you meet it, e.g. `BLE tags, asset beacons, door and temp sensors`.
  final String where;

  /// The cell, e.g. `CR2032, CR2450, CR2477`.
  final String cell;

  /// Why that cell, in one sentence.
  final String why;
}

/// The field table.
const List<BatteryFieldUse> kBatteryFieldUses = <BatteryFieldUse>[
  BatteryFieldUse(
    where: 'BLE tags, asset beacons, door and temperature sensors',
    cell: 'CR2032, CR2450, CR2477',
    why:
        '3 V from a single cell and self-discharge near 1 percent per year. That '
        'is why a 5-year sensor life is a real claim and not marketing.',
  ),
  BatteryFieldUse(
    where: 'RTC and BIOS on a controller, switch, WLAN Pi, or server',
    cell: 'CR2032',
    why:
        'The cell that makes a device forget the date. Worth knowing which one '
        'before you are standing in the plant room.',
  ),
  BatteryFieldUse(
    where: 'Tone generators, toners, cable testers',
    cell: '9 V (6LR61)',
    why: 'Legacy designs that want a rail above 5 V.',
  ),
  BatteryFieldUse(
    where: 'Field testers on cold roofs',
    cell: 'AA lithium iron disulfide (FR6)',
    why:
        'Rated to -40 degrees C where alkaline is rated only to -18 degrees C. '
        'A real decision for winter work, not a preference.',
  ),
  BatteryFieldUse(
    where: 'Field packs powering an AP for a survey',
    cell: 'LiFePO4 (IFR)',
    why:
        '3.2 V per cell, so four cells give a usable 12.8 V rail. 2000+ cycles '
        'and a benign failure mode.',
  ),
];

// ──────────────────────── 10. the two standing cautions ─────────────────────

/// The USB-C rechargeable AA. FINDINGS is explicit: no standards designation and
/// no usable datasheet exists, so this carries NO numbers by design.
const String kUsbCRechargeableCaution =
    'The 1.5 V USB-C rechargeable lithium-ion AA has no standards-body '
    'designation and no datasheet of usable quality. It is a regulated cell in '
    'an AA shell, so it holds 1.5 V flat and then stops, which defeats a '
    'voltage-based fuel gauge the same way NiMH does. No capacity or runtime '
    'figure is printed here because there is no source worth printing.';

/// The capacity caution. FINDINGS: Energizer capacities are read off datasheet
/// bar charts, and capacity is load-dependent, so a single number is a defect.
const String kCapacityCaution =
    'Treat any single capacity figure as wrong. Cell capacity is load-dependent: '
    'the same alkaline AA delivers substantially more at a trickle than it does '
    'at a heavy drain, and manufacturers publish capacity as a family of curves '
    'rather than one number. Where a capacity appears on this page it is tied to '
    'a named cell and a named datasheet, and it is approximate.';
