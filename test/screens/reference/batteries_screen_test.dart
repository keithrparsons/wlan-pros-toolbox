// Tests for the Batteries reference screen.
//
// Three layers, mirroring screw_drives_screen_test:
//   1. DATA FIDELITY (GL-005). The typed const datasets match Pax's clean-room
//      brief (Deliverables/2026-07-25-battery-sd-reference/FINDINGS.md, Part 1),
//      with the brief's DO-NOT-PRINT list pinned as negative assertions so a
//      future edit cannot silently reintroduce an unverified claim:
//        * the AA 1907 / AAA 1911 introduction dates (UNVERIFIED),
//        * the "B was skipped to avoid the radio B battery" story (FOLKLORE),
//        * any number attached to the 1.5 V USB-C rechargeable AA (no source),
//        * any capacity without its load or an explicit nameplate label,
//        * FOUR CLAIMS RETRACTED 2026-07-25 (see the group at the bottom of
//          this file): the "five digits split three plus two" CR2450 rule, the
//          designation PR1154, the A cell at 17.0 x 50.0 mm, and any B cell
//          dimension at all.
//      Plus the positive claims the page exists to deliver: CR2032 decodes,
//      LR44 does not, the diameter truncates and the height is exact, two
//      digits of height is a coin and three is a cylinder, the doubled letter
//      means smaller, and LR44 against SR44.
//
//      ON THE SHAPE OF THE RETRACTION TESTS. Four of the tests in this file
//      used to assert the refuted claims were PRESENT - `expect(c.reads, '245 +
//      0')`, `expect(a.dimensions, '17.0 mm x 50.0 mm')`. They were green the
//      whole time. A test that pins a wrong number does not catch the bug, it
//      enshrines it, and it makes the fix look like a regression to the next
//      reader. Each of those four is now inverted: the old string is asserted
//      ABSENT from every shipped surface, with the arithmetic that refuted it
//      in the failure message, so a future edit that restores the claim fails
//      with the reason rather than with a diff.
//
//      THE SWEEP COVERS TWO SURFACES, NOT ONE. `_allProse()` is the screen's
//      Dart data; `shippedHelpProse(kBatteriesToolId)` is the help sheet in
//      assets/help/tool_help.json. Until 2026-07-25 the sweep saw only the
//      first, and the folklore sentence was shipping in the second (Vera, M-01)
//      while a test three files away asserted it was absent. Any new negative
//      assertion goes over BOTH lists.
//   2. SAFETY WORDING. The ingestion mechanism is electrolysis generating
//      hydroxide and causing liquefactive necrosis, and a NEW cell is the most
//      dangerous. It must NOT be described as a leak or as choking. This is the
//      one string on the page where being wrong is a real-world defect, so it is
//      asserted by mechanism word, not by vibe.
//   3. WIDGET RENDER + graceful degradation: the screen renders at 320 / 375 /
//      768 with no RenderFlex overflow, and the concept-graphic slots render
//      exactly the bundled count (zero when none built, three when all named
//      SVGs are present), proving the manifest-gated resolver wiring.
//
// The catalog / router / help registration is asserted centrally by
// tool_help_loader_test (count guard) and the router tests; this file stays on
// the screen and its data.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/battery_diagrams.dart';
import 'package:wlan_pros_toolbox/data/battery_reference_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/batteries_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/tool_help_footer.dart';

import '../../support/shipped_help_copy.dart';

/// The OTHER shipped surface: every string in this tool's entry in
/// assets/help/tool_help.json, rendered by the help sheet. Lazily initialized
/// (Dart top-level finals are), and `shippedHelpProse` throws rather than
/// returning empty if the id ever goes missing, so the sweeps below cannot
/// silently degrade into assertions over nothing.
final List<String> _helpProse = shippedHelpProse(kBatteriesToolId);

/// Both shipped surfaces in one list: the screen's data constants and the help
/// sheet. Every DO-NOT-PRINT and glyph-hygiene assertion runs over this.
List<String> _allShippedCopy() => <String>[..._allProse(), ..._helpProse];

/// The ONE permitted appearance of the B-size folklore in shipped copy: the
/// help sheet's exclusion note, which names the story in order to tell the
/// reader it has no primary source. Pinned verbatim because the framing is the
/// only thing that makes printing it acceptable, and framing is exactly what
/// drifts when someone tightens a sentence a year from now.
const String kFolkloreExclusionNote =
    'Two things are deliberately NOT on this screen because no primary source '
    'was found for them: the AA and AAA introduction dates, and the story that '
    'the B size was skipped to avoid clashing with the radio B battery. The '
    'distinction between the two senses of B battery is real and is shown; the '
    'explanation for it is not.';

/// Every user-facing string the page can render, for the sweep-style checks.
List<String> _allProse() => <String>[
      kBatteryLead,
      kCoinCodeRule,
      kCodeRoundsPartDoesNot,
      kHeightGroupRule,
      kButtonCodeRule,
      kNoDatasheetDimension,
      kSizeLadderRule,
      kIecRoundSingleCellList,
      kIecMissingSizes,
      kTwoSensesOfB,
      kOneCodePerSizeIsWrong,
      kNineVoltNote,
      kRechargeableNote,
      kLr44CrossReference,
      kSr44CrossReference,
      kAg13Caveat,
      k357Vs303,
      kMercuryTrap,
      kVoltageGotchaLead,
      kLithiumOverVoltage,
      kIngestionMechanism,
      kIngestionFreshCellIsWorst,
      kIngestionTiming,
      kIngestionHotline,
      kReesesLaw,
      kAirTravelRule,
      kAirTravelTerminals,
      kUsbCRechargeableCaution,
      kCapacityCaution,
      for (final CellCode c in kCellCodes) ...<String>[
        c.code,
        c.reads,
        c.meaning,
        c.datasheet,
      ],
      for (final BatterySizeRung r in kBatterySizeRungs) ...<String>[
        r.size,
        // A null dimension renders as kNoDatasheetDimension, which is already
        // in the list above. `?? ''` here would put an empty string into the
        // sweep and silently satisfy nothing; skip it instead.
        if (r.dimensions != null) r.dimensions!,
        r.status,
        r.pin,
      ],
      for (final NamingSystem n in kNamingSystems) ...<String>[
        n.system,
        n.shape,
        n.aaAlkaline,
      ],
      for (final ChemistryLetter c in <ChemistryLetter>[
        ...kChemistryLetters,
        ...kRechargeableLetters,
      ]) ...<String>[c.letter, c.system, c.nominal, c.maxOcv],
      for (final SubstitutionRow s in kLr44VsSr44) ...<String>[
        s.property,
        s.alkaline,
        s.silver,
      ],
      for (final VoltageGotcha g in kVoltageGotchas) ...<String>[
        g.heading,
        g.detail,
      ],
      for (final BatteryFieldUse f in kBatteryFieldUses) ...<String>[
        f.where,
        f.cell,
        f.why,
      ],
    ];

void main() {
  group('Cell codes — the split convention (FINDINGS Part 1)', () {
    CellCode codeFor(String code) =>
        kCellCodes.firstWhere((CellCode c) => c.code == code);

    test('the rule states diameter TRUNCATED and height EXACT', () {
      // The asymmetry is the whole teaching point and the thing that resolves
      // every code-against-datasheet discrepancy on this page.
      expect(kCoinCodeRule.contains('TRUNCATED'), isTrue);
      expect(kCoinCodeRule.contains('floor'), isTrue,
          reason: 'the diameter group is a floor, not the cell diameter');
      expect(kCoinCodeRule.contains('tenths of a millimeter'), isTrue);
      expect(kCoinCodeRule.contains('exact'), isTrue);
      expect(kCoinCodeRule.contains('height from the right'), isTrue);
    });

    test('every worked code splits with the height read from the RIGHT', () {
      // Mechanical, not eyeballed: recompute each split from the code string
      // and require the data to agree. This is what would have failed red on
      // "CR2450 reads 245 + 0" and on "PR1154 reads 115 + 4", both of which
      // shipped past a hand-written assertion that simply restated them.
      for (final CellCode c in kCellCodes.where((CellCode c) => c.dimensional)) {
        final List<String> parts = c.reads.split(' + ');
        expect(parts.length, 2, reason: '${c.code} must split in two');
        final String dia = parts[0];
        final String height = parts[1];

        // Concatenating the two groups must reproduce the digits of the code,
        // in order. An interior letter (CR15H270) is dropped first; it sits on
        // the boundary and this page does not decode it.
        final String digits = c.code.replaceAll(RegExp('[^0-9]'), '');
        expect(dia + height, digits,
            reason: '${c.code}: "${c.reads}" does not reconstruct "$digits". '
                'This is the check PR1154 failed: 1,1,5,4 cannot yield both '
                '"11.5" and "5.4" without the 5 doing double duty.');

        // The height group is 2 or 3 digits. Never 1: a one-digit height group
        // is the "245 + 0" shape, and 0 tenths of a millimeter is 0.0 mm.
        expect(height.length, anyOf(2, 3),
            reason: '${c.code}: a ${height.length}-digit height group. Two '
                'digits is a coin, three is a cylinder, and one is the '
                'refuted CR2450 split.');

        // The height in the copy must equal the group read as tenths of a mm.
        final String expectedHeight =
            (int.parse(height) / 10).toStringAsFixed(1);
        expect(c.meaning.contains('height $expectedHeight mm'), isTrue,
            reason: '${c.code}: group "$height" is $expectedHeight mm. '
                'Copy reads: "${c.meaning}"');

        // The diameter is stated as a FLOOR, never as a measurement.
        expect(c.meaning.contains('Diameter at least $dia mm'), isTrue,
            reason: '${c.code}: the diameter group is truncated, so the copy '
                'must say "at least", not assert a measured diameter.');
      }
    });

    test('CR2032 code and can agree exactly: 20.00 mm by 3.20 mm', () {
      final CellCode c = codeFor('CR2032');
      expect(c.dimensional, isTrue);
      expect(c.reads, '20 + 32');
      expect(c.datasheet.contains('20.00 mm'), isTrue);
      expect(c.datasheet.contains('3.20 mm'), isTrue);
    });

    test('CR2450 is FOUR digits and reads 24 + 50', () {
      final CellCode c = codeFor('CR2450');
      expect(c.dimensional, isTrue);
      expect(c.reads, '24 + 50');
      expect(c.meaning.contains('Four digits'), isTrue,
          reason: 'the copy previously called CR2450 a five-digit code');
      expect(c.datasheet.contains('24.50 mm'), isTrue,
          reason: 'the 24.50 is the DATASHEET can, not what the code encodes');
    });

    test('LR1154 is the truncation witness: code 11, can 11.60', () {
      final CellCode c = codeFor('LR1154');
      expect(c.dimensional, isTrue);
      expect(c.reads, '11 + 54');
      expect(c.datasheet.contains('11.60 mm'), isTrue);
      // 11.60 truncates to 11 and rounds to 12 under any convention, so this
      // single cell settles truncation against rounding. Say so.
      expect(c.datasheet.contains('truncation'), isTrue);
      expect(kCodeRoundsPartDoesNot.contains('11.60'), isTrue);
      expect(kCodeRoundsPartDoesNot.contains('truncates'), isTrue);
    });

    test('truncation has a SECOND independent witness, CR15H270', () {
      // One witness is a coincidence away from being an artifact. FINDINGS
      // cross-verifies on CR15H270: 15.60 truncates to 15 and rounds to 16.
      final CellCode c = codeFor('CR15H270');
      expect(c.reads, '15 + 270');
      expect(c.datasheet.contains('15.60 mm'), isTrue);
      expect(c.datasheet.contains('27.00 mm'), isTrue);
    });

    test('the AA lithium code is FR14505, never CR14505', () {
      final CellCode c = codeFor('FR14505');
      expect(c.reads, '14 + 505');
      expect(c.datasheet.contains('14.50 mm'), isTrue);
      expect(c.datasheet.contains('50.50 mm'), isTrue);
      expect(c.meaning.contains('lithium iron disulfide'), isTrue,
          reason: 'F is the chemistry letter and is why it is not CR14505');
    });

    test('the rule reaches a CYLINDER unmodified: CR17345 is the CR123A', () {
      final CellCode c = codeFor('CR17345');
      expect(c.reads, '17 + 345');
      expect(c.datasheet.contains('17.00 mm'), isTrue);
      expect(c.datasheet.contains('34.50 mm'), isTrue);
      // The teaching line, which holds on all seven verified codes.
      expect(kHeightGroupRule.contains('two-digit height group'), isTrue);
      expect(kHeightGroupRule.contains('coin'), isTrue);
      expect(kHeightGroupRule.contains('cylinder'), isTrue);
      expect(kHeightGroupRule.contains('173'), isTrue,
          reason: 'the copy must rule out the 173 + 45 misreading');
    });

    test('LR44 is a CATALOG NUMBER, not 4 mm by 4.4 mm', () {
      final CellCode c = codeFor('LR44');
      expect(c.dimensional, isFalse,
          reason: 'LR44 is catalog entry 44, not a measurement');
      expect(c.datasheet.contains('11.60 mm'), isTrue,
          reason: 'the real can size must be given');
      // The rule text must say so in words, because this is the half everyone
      // leaves out.
      expect(kButtonCodeRule.contains('LR44 is not 4 mm by 4.4 mm'), isTrue);
      expect(kButtonCodeRule.contains('catalog entry 44'), isTrue);
    });

    test('both conventions are named to the same IEC clause', () {
      expect(kButtonCodeRule.contains('IEC 60086-2:2021'), isTrue);
      expect(kButtonCodeRule.contains('Clause 7'), isTrue);
      // LR1154 is the dimensional code for the same can LR44 names by catalog
      // number: the proof that both conventions coexist. It replaces PR1154,
      // which is not a designation any manufacturer or standard carries.
      expect(kButtonCodeRule.contains('LR1154'), isTrue);
      final CellCode lr1154 = codeFor('LR1154');
      final CellCode lr44 = codeFor('LR44');
      expect(lr1154.datasheet.contains('11.60 mm by 5.40 mm'), isTrue);
      expect(lr44.datasheet.contains('11.60 mm by 5.40 mm'), isTrue,
          reason: 'one can, two kinds of name, is the whole point');
    });

    test('the code and the part are kept apart as different quantities', () {
      // FINDINGS: "Any screen using both must say which is which, because a
      // reader who spots the discrepancy and is given no explanation concludes
      // the source is sloppy." The type enforces the separation; this asserts
      // the copy honors it.
      for (final CellCode c in kCellCodes) {
        expect(c.datasheet.contains('measures'), isTrue,
            reason: '${c.code}: the datasheet field must read as a '
                'measurement, so the reader can tell it from the code');
        expect(c.datasheet.isNotEmpty, isTrue);
      }
    });
  });

  group('The size ladder', () {
    test('states the doubled letter means SMALLER', () {
      expect(kSizeLadderRule.contains('doubled letter means smaller'), isTrue);
      expect(kSizeLadderRule.contains('AA is SMALLER than A'), isTrue);
    });

    test('the ladder order runs N, AAAA, AAA, AA, A, B, C, D', () {
      final int n = kSizeLadderRule.indexOf('N, AAAA, AAA, AA, A, B, C, D');
      expect(n, greaterThan(-1), reason: 'the ladder order is the fact');
    });

    test('A carries the Saft datasheet dimension, 17.13 x 50.90', () {
      final BatterySizeRung a =
          kBatterySizeRungs.firstWhere((BatterySizeRung r) => r.size == 'A');
      expect(a.dimensions, '17.13 mm x 50.90 mm',
          reason: 'Saft LS17500 Doc 31029-2-0710. The to-scale size-ladder '
              'graphic is drawn on this figure, so a different number here '
              'puts the screen and the graphic in visible disagreement.');
      expect(a.pin.contains('Saft LS17500'), isTrue);
      expect(a.status.contains('FDK HR-AUE'), isTrue);
      expect(a.status.contains('2700 mAh'), isTrue);
      // The figure is a datasheet rating with no load behind it, and the copy
      // has to say so: this page's whole argument is that a capacity without
      // its load is meaningless.
      expect(a.status.contains('nameplate rating'), isTrue,
          reason: 'a bare 2700 mAh contradicts the page it sits on');
      // LS17500 is a Saft house code, not an IEC dimensional code, and it
      // NEARLY decodes: 500 predicts 50.0 mm against a measured 50.90. A code
      // that nearly decodes is more dangerous than one that obviously does
      // not, because it survives a careless self-test. Printing it on a page
      // that teaches code decoding is only safe if the page says so.
      expect(a.status.contains('house code'), isTrue,
          reason: 'LS17500 appears on this page and must be marked undecodable');
      expect(a.status.contains('do not read a size out of it'), isTrue);
    });

    test('B has NO dimension, and says so rather than guessing', () {
      final BatterySizeRung b =
          kBatterySizeRungs.firstWhere((BatterySizeRung r) => r.size == 'B');
      expect(b.dimensions, isNull,
          reason: 'no standalone B cell datasheet exists because nobody sells '
              'one. The 21.5 x 60 mm figure in circulation traces to a '
              'battery-equivalence site, the exact source class this research '
              'bans. An unavailable dimension is stated, never estimated.');
      expect(b.pin.contains('No datasheet found'), isTrue);
      expect(b.status.contains('3LR12'), isTrue);
      expect(b.status.contains('nobody sells one'), isTrue);
    });

    test('every non-null dimension names a datasheet in its pin', () {
      // A dimension with no source is the shape both retracted figures had.
      for (final BatterySizeRung r in kBatterySizeRungs) {
        expect(r.pin.trim(), isNotEmpty,
            reason: '${r.size} has no pin at all');
        if (r.dimensions == null) continue;
        expect(
          RegExp(r'Saft|Energizer|FDK|Panasonic|Renata|GP|Form|Doc')
              .hasMatch(r.pin),
          isTrue,
          reason: '${r.size}: "${r.dimensions}" is pinned to "${r.pin}", which '
              'names no manufacturer or document. Equivalence sites are not a '
              'source this page prints from.',
        );
      }
    });

    test('the standard list is quoted, and the missing sizes are named', () {
      expect(kIecRoundSingleCellList.contains('LR6'), isTrue);
      expect(kIecRoundSingleCellList.contains('FR14505'), isTrue);
      expect(kIecMissingSizes.contains('R23'), isTrue);
      expect(kIecMissingSizes.contains('3LR12'), isTrue);
    });
  });

  group('Naming systems and chemistry letters', () {
    test('ANSI gives 15A and IEC gives LR6 for the same alkaline AA', () {
      final NamingSystem ansi = kNamingSystems
          .firstWhere((NamingSystem n) => n.system.startsWith('ANSI'));
      final NamingSystem iec = kNamingSystems
          .firstWhere((NamingSystem n) => n.system.startsWith('IEC'));
      expect(ansi.aaAlkaline, '15A');
      expect(iec.aaAlkaline, 'LR6');
    });

    test('one code per size is called out as wrong, with the chemistry set', () {
      for (final String code in <String>['LR6', 'R6', 'FR6', 'HR6', 'KR6']) {
        expect(kOneCodePerSizeIsWrong.contains(code), isTrue,
            reason: '$code belongs in the same-size, different-code list');
      }
      expect(kOneCodePerSizeIsWrong.contains('R6P'), isTrue);
      expect(kOneCodePerSizeIsWrong.contains('R6S'), isTrue);
    });

    test('9 V: 6LR61 is round, 6LF22 is flat', () {
      expect(kNineVoltNote.contains('6LR61'), isTrue);
      expect(kNineVoltNote.contains('6LF22'), isTrue);
      expect(kNineVoltNote.contains('ROUND'), isTrue);
      expect(kNineVoltNote.contains('FLAT'), isTrue);
    });

    test('lithium iron disulfide max OCV is 1.83 V, silver oxide is 1.55 V', () {
      final ChemistryLetter f =
          kChemistryLetters.firstWhere((ChemistryLetter c) => c.letter == 'F');
      expect(f.maxOcv, '1.83 V');
      expect(f.nominal, '1.5 V');
      final ChemistryLetter s =
          kChemistryLetters.firstWhere((ChemistryLetter c) => c.letter == 'S');
      expect(s.nominal, '1.55 V');
    });

    test('rechargeables are separated out of IEC 60086', () {
      expect(kRechargeableNote.contains('Primary batteries'), isTrue);
      final ChemistryLetter ifr = kRechargeableLetters
          .firstWhere((ChemistryLetter c) => c.letter == 'IFR');
      expect(ifr.nominal, '3.2 V');
    });
  });

  group('LR44 against SR44 — the equivalence trap', () {
    SubstitutionRow rowFor(String property) =>
        kLr44VsSr44.firstWhere((SubstitutionRow r) => r.property == property);

    test('same can, different nominal voltage', () {
      final SubstitutionRow can = rowFor('Can size');
      expect(can.alkaline, '11.60 mm x 5.40 mm');
      expect(can.silver, can.alkaline, reason: 'identical can is the whole trap');
      final SubstitutionRow v = rowFor('Nominal voltage');
      expect(v.alkaline, '1.5 V');
      expect(v.silver, '1.55 V');
    });

    test('sloping against flat, and the safe direction of substitution', () {
      final SubstitutionRow d = rowFor('Discharge shape');
      expect(d.alkaline.contains('Sloping'), isTrue);
      expect(d.silver.contains('Flat'), isTrue);
      final SubstitutionRow s = rowFor('Substituting it');
      expect(s.silver.contains('safe'), isTrue,
          reason: 'silver oxide into an alkaline slot is the safe direction');
      expect(s.alkaline.contains('drifts a precision instrument'), isTrue);
    });

    test('AG13 is flagged as an unadministered trade code', () {
      expect(kAg13Caveat.contains('not an IEC or an ANSI designation'), isTrue);
      expect(kLr44CrossReference.contains('AG13'), isTrue);
    });

    test('357 and 303 split on the drain-rate suffix', () {
      expect(k357Vs303.contains('SR1154W'), isTrue);
      expect(k357Vs303.contains('SR1154SW'), isTrue);
      expect(k357Vs303.contains('high-drain'), isTrue);
      expect(k357Vs303.contains('low-drain'), isTrue);
    });

    test('the mercury trap keeps the 1.35 V figure', () {
      expect(kMercuryTrap.contains('1.35 V'), isTrue);
      expect(kMercuryTrap.contains('PX625'), isTrue);
    });
  });

  group('The 1.5 V against 1.2 V gotcha, framed correctly', () {
    test('leads with the FUEL GAUGE, not with "it will not run"', () {
      // The brief is explicit: the real problem is that a voltage-based gauge
      // cannot read a flat NiMH curve. That claim must come FIRST.
      final int gauge = kVoltageGotchaLead.indexOf('fuel gauge');
      final int shortfall = kVoltageGotchaLead.indexOf('shortfall');
      expect(gauge, greaterThan(-1));
      expect(shortfall, greaterThan(gauge),
          reason: 'the gauge is the lead, the 20 percent is the supporting fact');
      expect(kVoltageGotchaLead.contains('6.0 V'), isTrue);
      expect(kVoltageGotchaLead.contains('4.8 V'), isTrue);
    });

    test('the flat-plateau explanation is present', () {
      final VoltageGotcha g = kVoltageGotchas.first;
      expect(g.detail.contains('flat plateau'), isTrue);
      expect(g.detail.contains('1.2 V'), isTrue);
      expect(g.detail.contains('0.8 V'), isTrue);
    });

    test('the opposite trap keeps the 1.83 V maximum open-circuit figure', () {
      expect(kLithiumOverVoltage.contains('1.83 V'), isTrue);
      expect(kLithiumOverVoltage.contains('L91'), isTrue);
    });
  });

  group('Button-cell safety — the mechanism must be right', () {
    test('states electrolysis, hydroxide, and liquefactive necrosis', () {
      final String m = kIngestionMechanism.toLowerCase();
      expect(m.contains('electrolysis'), isTrue);
      expect(m.contains('hydroxide'), isTrue);
      expect(m.contains('liquefactive necrosis'), isTrue);
      expect(m.contains('esophagus'), isTrue,
          reason: 'US spelling; the site of the injury is load-bearing');
    });

    test('does NOT describe the injury as a leak or as choking', () {
      final String m = kIngestionMechanism.toLowerCase();
      // The only permitted uses of "leak" and "airway" are the explicit
      // negations ("does not need to leak", "does not need to block the
      // airway"). Assert the negation is present rather than the word absent.
      expect(m.contains('does not need to leak'), isTrue);
      expect(m.contains('does not need to block the airway'), isTrue);
      // The word "choking" must not appear at all: it names the wrong
      // mechanism and is the single most common way this fact is told wrong.
      expect(m.contains('chok'), isFalse);
    });

    test('a NEW fully charged cell is called out as the most dangerous', () {
      final String s = kIngestionFreshCellIsWorst.toLowerCase();
      expect(s.contains('most dangerous'), isTrue);
      expect(s.contains('fully charged'), isTrue);
    });

    test('keeps the 2-hour datasheet quote, the 20 mm size, and the hotline',
        () {
      expect(kIngestionTiming.contains('2 hours'), isTrue);
      expect(kIngestionTiming.contains('20 mm'), isTrue);
      expect(kIngestionHotline.contains('800-498-8666'), isTrue);
    });

    test('Reeses Law is dated to the adopted rule, with UL 4200A', () {
      expect(kReesesLaw.contains('11 September'), isTrue);
      expect(kReesesLaw.contains('2023'), isTrue);
      expect(kReesesLaw.contains('UL 4200A'), isTrue);
    });
  });

  group('Air travel', () {
    test('spare cells go in the cabin; installed may be checked', () {
      expect(kAirTravelRule.contains('never in checked baggage'), isTrue);
      expect(kAirTravelRule.contains('powered off'), isTrue);
      expect(kAirTravelRule.contains('0.109 grams'), isTrue);
    });

    test('names the short circuit as the real hazard', () {
      expect(kAirTravelTerminals.contains('short circuit'), isTrue);
    });
  });

  group('DO-NOT-PRINT list from the brief stays absent', () {
    // ---- The guard on the guard. ----
    // Every test below asserts an ABSENCE. An absence assertion over an empty
    // or wrong list passes for free, so pin that both surfaces are really in
    // the sweep before trusting anything the sweep reports.
    test('the sweep covers BOTH shipped surfaces, not just the Dart data', () {
      expect(_allProse().length, greaterThan(60),
          reason: 'the screen data surface must be in the sweep');
      expect(_helpProse.length, greaterThan(10),
          reason: 'the help-sheet surface must be in the sweep');
      // Sentinels: one string only the screen carries, one only the help
      // sheet carries. If either surface silently drops out, this goes red.
      expect(_allShippedCopy().any((String s) => s.contains('800-498-8666')),
          isTrue);
      expect(
          _allShippedCopy().any((String s) =>
              s.contains('Use the copy button in the toolbar')),
          isTrue,
          reason: 'a help-sheet-only string must appear in the sweep');
    });

    test('no AA / AAA introduction dates (UNVERIFIED in the brief)', () {
      for (final String s in _allShippedCopy()) {
        expect(s.contains('1907'), isFalse,
            reason: 'the AA introduction date is UNVERIFIED: "$s"');
        expect(s.contains('1911'), isFalse,
            reason: 'the AAA introduction date is UNVERIFIED: "$s"');
        expect(s.contains('1947'), isFalse);
        expect(s.contains('1959'), isFalse);
      }
    });

    test('no "B was skipped because of the radio B battery" folklore', () {
      for (final String s in _allProse()) {
        final String l = s.toLowerCase();
        expect(l.contains('skipped'), isFalse,
            reason: 'the skipped-B story is FOLKLORE with no primary source');
        expect(l.contains('to avoid clashing'), isFalse);
      }
      // The DISTINCTION between the two senses of B battery is solid and must
      // survive, without the causal story.
      expect(kTwoSensesOfB.contains('45 V to 90 V'), isTrue);
      expect(kTwoSensesOfB.toLowerCase().contains('circuit role'), isTrue);
    });

    test('the folklore appears ONLY as the help sheet exclusion note', () {
      // Naming an excluded claim and saying why it was excluded is what GL-005
      // asks for, so the help sheet keeps the debunk. What it cannot do is
      // drift: the framing words are the only thing separating "here is a story
      // with no source" from an assertion of the story. So the framing is
      // pinned, not trusted.
      final List<String> hits = _helpProse
          .where((String s) => s.toLowerCase().contains('skipped'))
          .toList();
      expect(hits.length, 1,
          reason: 'the folklore may appear exactly once in shipped help copy, '
              'as the exclusion note. Found ${hits.length}: $hits');

      final String note = hits.single;
      // The framing, asserted before the verbatim pin so a drifted note fails
      // with the reason that matters rather than a wall of diff.
      expect(note.contains('deliberately NOT on this screen'), isTrue,
          reason: 'the note must read as an exclusion, not as a claim');
      expect(note.contains('no primary source was found'), isTrue,
          reason: 'the reason for the exclusion is the load-bearing half');
      expect(note.indexOf('deliberately NOT'),
          lessThan(note.indexOf('skipped to avoid clashing')),
          reason: 'the negation must come BEFORE the story it negates');

      // And the whole sentence, verbatim. Editing the note is allowed; editing
      // it without a reviewer seeing this constant change is not.
      expect(note, kFolkloreExclusionNote,
          reason: 'the help-sheet exclusion note changed. If that was '
              'deliberate, re-read it as a reader would, confirm it still '
              'DEBUNKS the story rather than repeating it, then update '
              'kFolkloreExclusionNote in this file.');

      // "to avoid clashing" rides along in the same one sentence, nowhere else.
      expect(
        _allShippedCopy()
            .where((String s) => s.contains('to avoid clashing'))
            .length,
        1,
      );
    });

    test('the USB-C rechargeable AA caution carries NO numbers', () {
      expect(
        kUsbCRechargeableCaution.contains('no standards-body'),
        isTrue,
      );
      // No digit may appear in the caution except the "1.5 V" naming of the
      // product category itself, which is the product's own label, not a
      // performance claim.
      final String stripped = kUsbCRechargeableCaution.replaceAll('1.5 V', '');
      expect(RegExp(r'\d').hasMatch(stripped), isFalse,
          reason: 'no capacity or runtime figure has a usable source');
      // Same rule on the help sheet: no performance figure may attach itself
      // to the USB-C product there either.
      for (final String s in _helpProse) {
        if (!s.contains('USB-C')) continue;
        expect(RegExp(r'\d+\s*(mAh|Wh|cycles|hours)').hasMatch(s), isFalse,
            reason: 'no sourced performance figure exists for it: "$s"');
      }
    });

    // ── THE FOUR RETRACTIONS, 2026-07-25 ───────────────────────────────────
    // Each of these shipped. Each had a green test asserting it was PRESENT.
    // The reason for the retraction lives in the failure message, not in a
    // comment, because the person who trips this guard will be reading the
    // failure and not this file.

    test('RETRACTED: no "five digits split three plus two" CR2450 rule', () {
      for (final String s in _allShippedCopy()) {
        final String l = s.toLowerCase();
        expect(l.contains('five-digit') || l.contains('five digit'), isFalse,
            reason: 'The five-digit rule is REFUTED on its own arithmetic. '
                'CR2450 has FOUR digits, so a rule scoped to five-digit codes '
                'never reached its own headline example. Offending copy: "$s"');
        expect(s.contains('245 + 0'), isFalse,
            reason: 'REFUTED: the height group is tenths of a millimeter (that '
                'is how 32 becomes 3.2 mm), so a height group of "0" is 0.0 '
                'mm, not 5.0 mm. The split refutes the rule it was offered as '
                'an exception to. CR2450 reads 24 + 50. Offending copy: "$s"');
        expect(s.contains('145 + 05'), isFalse,
            reason: 'REFUTED: three-plus-two on 14505 gives "05", which is 0.5 '
                'mm, against the 50.5 mm the same sentence asserted. Two of '
                'two examples did not compute. Offending copy: "$s"');
        expect(s.contains('CR14505'), isFalse,
            reason: 'The Energizer datasheet reads FR14505 (FR6). F is lithium '
                'iron disulfide, not C. Offending copy: "$s"');
      }
      // And the code table must not contain either retracted entry.
      final Iterable<String> codes = kCellCodes.map((CellCode c) => c.code);
      expect(codes.contains('CR14505'), isFalse);
    });

    test('RETRACTED: PR1154 is not a designation and does not appear', () {
      for (final String s in _allShippedCopy()) {
        expect(s.contains('PR1154'), isFalse,
            reason: 'PR1154 was SEARCHED AND NOT FOUND. No manufacturer '
                'datasheet and no standards document carries it; Energizer, '
                'Renata, GP, Ansmann and Power One all designate that 675 '
                'zinc-air cell PR44. It survives only on retail '
                'cross-reference pages. Its arithmetic does not parse either: '
                'digits 1,1,5,4 cannot yield both "11.5" and "5.4" without the '
                '5 doing double duty. Arithmetic consistency would not have '
                'been evidence of existence in any case. Use LR1154, which is '
                'datasheet-pinned and names the same can as LR44. Offending '
                'copy: "$s"');
        expect(s.contains('11.5 mm by 5.4 mm'), isFalse,
            reason: 'the nominal figure that came with PR1154. The can is '
                '11.60 by 5.40 mm and the code reads 11 + 54. Copy: "$s"');
      }
      expect(kCellCodes.map((CellCode c) => c.code).contains('PR1154'), isFalse);
    });

    test('RETRACTED: the A cell is not 17.0 x 50.0 mm', () {
      for (final String s in _allShippedCopy()) {
        expect(s.contains('17.0 mm x 50.0 mm'), isFalse,
            reason: 'SUPERSEDED by Saft LS17500, Doc 31029-2-0710: 17.13 by '
                '50.90 mm. The to-scale size-ladder graphic is drawn on the '
                'datasheet figure, so restoring this puts the screen and the '
                'graphic in visible disagreement. Offending copy: "$s"');
        expect(s.contains('17.0 by 50.0'), isFalse);
      }
    });

    test('RETRACTED: no B cell dimension anywhere on either surface', () {
      // The strongest form available: not "the old figure is absent" but "no
      // dimension is asserted for B at all", because the finding is that none
      // exists. A substituted guess would pass a string-equality check.
      for (final String s in _allShippedCopy()) {
        expect(s.contains('21.5'), isFalse,
            reason: 'WITHDRAWN. The 21.5 x 60 mm B cell figure traces to a '
                'battery-equivalence site, the exact source class this '
                'research bans, and no standalone B datasheet exists because '
                'nobody sells one. Offending copy: "$s"');
      }
      final BatterySizeRung b =
          kBatterySizeRungs.firstWhere((BatterySizeRung r) => r.size == 'B');
      expect(b.dimensions, isNull);
      // Nor may a dimension sneak into B's prose. Any "<number> mm" in the B
      // row that is not the 3R12 pack voltage or the pack name is suspect, so
      // require that no millimeter figure appears in the row at all.
      for (final String s in <String>[b.status, b.pin]) {
        expect(RegExp(r'\d+(\.\d+)?\s*mm').hasMatch(s), isFalse,
            reason: 'a millimeter figure appeared in the B row, which has no '
                'datasheet to take one from: "$s"');
      }
    });

    test('capacity is labeled load-dependent and approximate', () {
      expect(kCapacityCaution.contains('load-dependent'), isTrue);
      expect(kCapacityCaution.contains('approximate'), isTrue);
    });

    test('every mAh figure carries its load, or is labeled a nameplate rating',
        () {
      // FINDINGS line 58: "Every capacity is approximate and load-stated; none
      // may appear without its load." A nameplate rating is the one permitted
      // alternative, because it is a different KIND of number and the copy has
      // to say so where it appears (FINDINGS line 56, corrected 2026-07-25
      // after Vera found the FDK 2700 mAh shipping bare).
      final RegExp qualified = RegExp(
        r'nameplate|at \d|@\s*\d|\d\s*mA\b',
        caseSensitive: false,
      );
      for (final String s in _allShippedCopy()) {
        if (!s.contains('mAh')) continue;
        expect(qualified.hasMatch(s), isTrue,
            reason: 'a capacity with no load and no nameplate label is exactly '
                'the number this page argues is meaningless: "$s"');
      }
    });
  });

  group('GL-004 voice and glyph hygiene', () {
    test('no em dash, no en dash, no "WiFi", no "router"', () {
      for (final String s in _allShippedCopy()) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('–'), isFalse, reason: 'en dash in "$s"');
        expect(s.contains('WiFi'), isFalse, reason: '"WiFi" in "$s"');
        expect(s.toLowerCase().contains('router'), isFalse,
            reason: 'never "router" in "$s"');
      }
    });

    test('US spelling on the words this page could get wrong', () {
      for (final String s in _allShippedCopy()) {
        final String l = s.toLowerCase();
        for (final String british in <String>[
          'oesophagus',
          'catalogue',
          'behaviour',
          'grey',
          'labelled',
          'normalise',
        ]) {
          expect(l.contains(british), isFalse,
              reason: 'British spelling "$british" in "$s"');
        }
      }
    });
  });

  group('BatteriesScreen widget', () {
    setUp(() {
      // No graphic SVG bundled by default: each slot renders nothing, and the
      // page must still ship fully working as tables.
      BatteryDiagrams.debugSetBundled(const <String>{});
    });
    tearDown(BatteryDiagrams.debugReset);

    testWidgets('renders the title and every section heading',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 8000), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const BatteriesScreen()),
        );

        expect(find.text('Batteries'), findsWidgets);
        for (final String heading in <String>[
          'Reading the code',
          'The size ladder',
          'Naming systems',
          'Chemistry letters',
          'LR44 against SR44',
          '1.5 V against 1.2 V',
          'Button cell safety',
          'Air travel',
          'Where a Wi-Fi engineer meets these',
        ]) {
          expect(find.text(heading), findsOneWidget,
              reason: 'missing section heading "$heading"');
        }
        // The per-tool help affordance is wired (the help ENTRY itself is
        // asserted centrally by tool_help_loader_test's count guard).
        expect(find.byType(ToolHelpFooter), findsOneWidget);
        // Read-only reference: no inputs anywhere.
        expect(find.byType(TextField), findsNothing);
        // No bundled graphic, so no SvgPicture (graceful degradation).
        expect(find.byType(SvgPicture), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320 / 375 / 768 widths',
        (WidgetTester tester) async {
      for (final double width in <double>[320, 375, 768]) {
        await _withViewport(tester, Size(width, 3000), () async {
          await tester.pumpWidget(
            MaterialApp(theme: AppTheme.dark(), home: const BatteriesScreen()),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });

    testWidgets('renders in light App Mode without exception',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 3000), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.light(), home: const BatteriesScreen()),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('renders exactly the bundled concept-graphic count (dark)',
        (WidgetTester tester) async {
      BatteryDiagrams.debugSetBundled(<String>{
        for (final String name in BatteryDiagrams.all)
          BatteryDiagrams.path(name),
      });
      addTearDown(BatteryDiagrams.debugReset);

      await _withViewport(tester, const Size(375, 12000), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const BatteriesScreen()),
        );
        await tester.pump();
        expect(find.byType(SvgPicture), findsNWidgets(BatteryDiagrams.all.length));
      });
    });

    test('the copy payload carries every section', () {
      final String tsv = BatteriesScreen.buildCopyText();
      for (final String marker in <String>[
        'Batteries (field reference)',
        'Reading the code',
        'The size ladder',
        'The two naming systems',
        'Chemistry letters',
        'LR44 against SR44',
        '1.5 V against 1.2 V',
        'Button cell ingestion',
        'Air travel',
        'Where a Wi-Fi engineer meets these',
      ]) {
        expect(tsv.contains(marker), isTrue, reason: 'copy missing "$marker"');
      }
      expect(tsv.contains('\t'), isTrue, reason: 'tables copy as TSV');
      expect(tsv.contains('—'), isFalse, reason: 'no em dash in the copy');
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
