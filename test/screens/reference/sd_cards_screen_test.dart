// Tests for the SD & microSD Cards reference screen.
//
// Three layers, mirroring screw_drives_screen_test:
//   1. DATA FIDELITY (GL-005). The typed const datasets match Pax's clean-room
//      brief (Deliverables/2026-07-25-battery-sd-reference/FINDINGS.md, Part 2),
//      which pulled every figure from the SD Physical Layer Simplified
//      Specification v6.00 with section and page cited. The claims the page
//      exists to deliver are pinned so a future edit cannot soften them:
//        * the two axes are orthogonal (C/U/V = sustained sequential write,
//          A1/A2 = random 4 KB IOPS),
//        * A2 requires host Command Queuing and falls back to A1 by design,
//        * A1 and A2 cap sustained write at 10 MB/s,
//        * the capacity mark is a FILESYSTEM contract,
//        * V60 and V90 require UHS-II.
//   2. The brief's DO-NOT-PRINT item, pinned as a negative assertion: no single
//      SD Express maximum. The SD Association's own two publications disagree
//      (3940 against 3938 MB/s), so the page prints ~3.9 GB/s and neither exact
//      figure may appear. The sweep runs over BOTH shipped surfaces: the
//      screen's Dart data (`_allProse()`) and the help sheet in
//      assets/help/tool_help.json (`shippedHelpProse`). Scanning only the first
//      is how the Batteries folklore sentence shipped past an identical guard
//      (Vera, 2026-07-25, M-01).
//   3. WIDGET RENDER + graceful degradation: the screen renders at 320 / 375 /
//      768 with no RenderFlex overflow, and the concept-graphic slots render
//      exactly the bundled count.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/sd_card_diagrams.dart';
import 'package:wlan_pros_toolbox/data/sd_card_reference_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/sd_cards_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/tool_help_footer.dart';

import '../../support/shipped_help_copy.dart';

/// The OTHER shipped surface: every string in this tool's entry in
/// assets/help/tool_help.json, rendered by the help sheet. `shippedHelpProse`
/// throws rather than returning empty if the id goes missing, so the absence
/// sweeps below cannot degrade into assertions over nothing.
final List<String> _helpProse = shippedHelpProse(kSdCardsToolId);

/// Both shipped surfaces in one list: the screen's data constants and the help
/// sheet. Every DO-NOT-PRINT and glyph-hygiene assertion runs over this.
List<String> _allShippedCopy() => <String>[..._allProse(), ..._helpProse];

/// Every user-facing string the page can render, for the sweep-style checks.
List<String> _allProse() => <String>[
      kSdLead,
      kMarketingReadCaution,
      kFilesystemContract,
      kSdExpressCaution,
      kSecondPinRow,
      kUhsIiInUhsISlot,
      kV60RequiresUhsIi,
      kVNumberReadsDirectly,
      kRedundantMarks,
      kClassesAreOptional,
      kA2NeedsCommandQueuing,
      kA2IsNotAVideoCard,
      kEnduranceProblem,
      kEnduranceTbw,
      kCounterfeitMechanism,
      kCounterfeitAntiPattern,
      kCounterfeitTest,
      kWriteProtectNotch,
      for (final SdCardMark m in kSdCardMarks) ...<String>[m.mark, m.measures],
      for (final SdCapacityStandard c in kSdCapacityStandards) ...<String>[
        c.mark,
        c.capacity,
        c.filesystem,
      ],
      for (final SdBusInterface b in kSdBusInterfaces) ...<String>[
        b.mark,
        b.name,
        b.ceiling,
      ],
      for (final SdSpeedClass s in kSdSpeedClasses) ...<String>[
        s.mark,
        s.floor,
        s.note,
      ],
      for (final SdAppPerformanceClass a in kSdAppClasses) ...<String>[
        a.mark,
        a.randomRead,
        a.randomWrite,
        a.sustainedWrite,
      ],
      for (final SdReadingStep s in kSdReadingOrder) ...<String>[s.step, s.what],
      for (final SdJobSelection j in kSdJobSelections) ...<String>[
        j.job,
        j.governs,
        j.read,
        j.ignore,
      ],
      for (final CounterfeitBehavior c in kCounterfeitBehaviors) ...<String>[
        c.name,
        c.what,
      ],
    ];

void main() {
  // CORRECTED 2026-07-27. This group asserted that the A-class measures a
  // DIFFERENT axis and required the word 'orthogonal' to be present. Both were
  // wrong, and because the test faithfully encoded the wrong claim it stayed
  // green while the screen shipped it. Pinned: SD Part 1 Physical Layer
  // Simplified Specification v6.00, Sec 4.16.1.1 and 4.16.1.2, p.150 - A1 and
  // A2 each specify random IOPS AND a 10 MB/s sustained sequential write floor,
  // in identical wording. The A-class shares the axis and adds one.
  group('The lead: the A-class shares the axis and adds one', () {
    test('names sequential write and random IOPS, and does not call them separate axes', () {
      expect(kSdLead.contains('SEQUENTIAL write'), isTrue);
      expect(kSdLead.contains('RANDOM 4 KB IOPS'), isTrue);
      // The refuted claim must NOT come back. This is the guard that was missing.
      expect(kSdLead.contains('orthogonal'), isFalse);
      expect(kSdLead.contains('10 MB/s'), isTrue);
      // Both directions of the consequence must be stated, not just one.
      expect(kSdLead.contains('V90 card can be slower'), isTrue);
      expect(kSdLead.contains('A2 card can drop frames'), isTrue);
    });

    test('exactly seven marks, numbered 1 to 7 for the hero graphic', () {
      expect(kSdCardMarks.length, 7);
      expect(
        kSdCardMarks.map((SdCardMark m) => m.number).toList(),
        <int>[1, 2, 3, 4, 5, 6, 7],
      );
    });

    test('the headline MB/s is flagged as an unregulated READ, not a class', () {
      expect(kMarketingReadCaution.contains('sequential READ'), isTrue);
      expect(kMarketingReadCaution.contains('No class regulates it'), isTrue);
    });
  });

  group('Capacity standard is a filesystem contract', () {
    SdCapacityStandard capFor(String mark) =>
        kSdCapacityStandards.firstWhere((SdCapacityStandard c) => c.mark == mark);

    test('SDHC means FAT32; SDXC and SDUC mean exFAT', () {
      expect(capFor('SDHC').filesystem, 'FAT32');
      expect(capFor('SDXC').filesystem, 'exFAT');
      expect(capFor('SDUC').filesystem, 'exFAT');
    });

    test('capacity bands match the spec', () {
      expect(capFor('SDHC').capacity, '2 GB to 32 GB');
      expect(capFor('SDXC').capacity, '32 GB to 2 TB');
      expect(capFor('SDUC').capacity, '2 TB to 128 TB');
    });

    test('states that the host fails on exFAT, not on capacity', () {
      expect(kFilesystemContract.contains('It fails'), isTrue);
      expect(kFilesystemContract.contains('exFAT'), isTrue);
      expect(kFilesystemContract.contains('outside the specification'), isTrue);
    });
  });

  group('Bus interface', () {
    SdBusInterface busFor(String name) =>
        kSdBusInterfaces.firstWhere((SdBusInterface b) => b.name == name);

    test('UHS-I 104, UHS-II 312, UHS-III 624 MB/s', () {
      expect(busFor('UHS-I').ceiling, '104 MB/s');
      expect(busFor('UHS-II').ceiling, '312 MB/s');
      expect(busFor('UHS-III').ceiling, '624 MB/s');
    });

    test('SD Express is rounded to ~3.9 GB/s and NEITHER exact figure appears',
        () {
      expect(busFor('SD Express').ceiling.contains('~3.9 GB/s'), isTrue);
      // Guard on the guard: this is an ABSENCE assertion, and an absence
      // assertion over an empty list passes for free. Pin that both shipped
      // surfaces are actually in the sweep first.
      expect(_allProse().length, greaterThan(60),
          reason: 'the screen data surface must be in the sweep');
      expect(_helpProse.length, greaterThan(10),
          reason: 'the help-sheet surface must be in the sweep');
      expect(
          _allShippedCopy().any(
              (String s) => s.contains('Use the copy button in the toolbar')),
          isTrue,
          reason: 'a help-sheet-only string must appear in the sweep');

      // The SD Association contradicts itself (3940 against 3938 MB/s). The
      // brief is explicit: do not pick a side. Screen data AND help sheet.
      for (final String s in _allShippedCopy()) {
        expect(s.contains('3940'), isFalse,
            reason: 'the SDA contradicts itself; do not print an exact figure');
        expect(s.contains('3938'), isFalse,
            reason: 'the SDA contradicts itself; do not print an exact figure');
      }
      expect(kSdExpressCaution.contains('two different'), isTrue);
      // The help sheet must carry the reason it is rounded, not just the
      // rounded number, or a reader meets a vague figure with no explanation.
      expect(
          _helpProse.any((String s) =>
              s.contains('~3.9 GB/s') && s.contains('two different')),
          isTrue,
          reason: 'the help sheet must name the SDA self-contradiction');
    });

    test('the second pin row: pins 10 to 17, and 7 and 8 become RCLK', () {
      expect(kSecondPinRow.contains('9 contacts'), isTrue);
      expect(kSecondPinRow.contains('pins 10 through'), isTrue);
      expect(kSecondPinRow.contains('17'), isTrue);
      expect(kSecondPinRow.contains('RCLK+'), isTrue);
      expect(kSecondPinRow.contains('1.70 V to 1.95 V'), isTrue);
    });

    test('a UHS-II card in a UHS-I slot runs UHS-I', () {
      expect(kUhsIiInUhsISlot.contains('simply runs UHS-I'), isTrue);
    });

    test('V60 and V90 require UHS-II, and the mis-mark is named', () {
      expect(kV60RequiresUhsIi.contains('require UHS-II'), isTrue);
      expect(kV60RequiresUhsIi.contains('Roman I'), isTrue);
      expect(kV60RequiresUhsIi.contains('marked wrongly'), isTrue);
      // The class table row must carry the same requirement.
      final SdSpeedClass v =
          kSdSpeedClasses.firstWhere((SdSpeedClass s) => s.mark == 'V60 / V90');
      expect(v.note.contains('Requires UHS-II'), isTrue);
      expect(v.floor, '60 / 90 MB/s');
    });
  });

  group('Sustained-write classes', () {
    SdSpeedClass classFor(String mark) =>
        kSdSpeedClasses.firstWhere((SdSpeedClass s) => s.mark == mark);

    test('C, U, and V floors match the spec', () {
      expect(classFor('C2 / C4 / C6 / C10').floor, '2 / 4 / 6 / 10 MB/s');
      expect(classFor('U1 / U3').floor, '10 / 30 MB/s');
      expect(classFor('V6 / V10 / V30').floor, '6 / 10 / 30 MB/s');
    });

    test('there is no U2, and the V number reads directly', () {
      expect(classFor('U1 / U3').note.contains('no U2'), isTrue);
      expect(kVNumberReadsDirectly.contains('V number IS the MB/s floor'),
          isTrue);
    });

    // CORRECTED 2026-07-27. The old test required the string 'v4.20'. The
    // Physical Layer Simplified Specification's revision history has no 4.20
    // (1.10, 2.00, 3.01, 4.10, 5.00, 6.00); that version belongs to the Host
    // Controller spec. The substance is separately pinnable at Sec 4.13.1.6
    // p.117, Table 4-52 p.109 and Table 4-54 p.109, so the claim stays and the
    // unverifiable version number goes.
    test('all three families are flagged OPTIONAL, with no unverified spec version', () {
      expect(kClassesAreOptional.contains('OPTIONAL'), isTrue);
      expect(kClassesAreOptional.contains('v4.20'), isFalse);
      expect(classFor('C2 / C4 / C6 / C10').note.contains('Legacy'), isTrue);
    });
  });

  group('Application Performance Class — the two caveats', () {
    SdAppPerformanceClass appFor(String mark) =>
        kSdAppClasses.firstWhere((SdAppPerformanceClass a) => a.mark == mark);

    test('A1 and A2 IOPS figures match the spec', () {
      expect(appFor('A1').randomRead, '1500 IOPS');
      expect(appFor('A1').randomWrite, '500 IOPS');
      expect(appFor('A2').randomRead, '4000 IOPS');
      expect(appFor('A2').randomWrite, '2000 IOPS');
    });

    test('BOTH cap sustained write at 10 MB/s', () {
      expect(appFor('A1').sustainedWrite, '10 MB/s');
      expect(appFor('A2').sustainedWrite, '10 MB/s');
    });

    test('A2 needs host Command Queuing, and the fallback is by design', () {
      expect(kA2NeedsCommandQueuing.contains('Command Queuing'), isTrue);
      expect(kA2NeedsCommandQueuing.contains('fall back to A1'), isTrue);
      expect(kA2NeedsCommandQueuing.contains('by design'), isTrue);
      // The Pi-benchmark consequence is the reason this caveat is on the page.
      expect(kA2NeedsCommandQueuing.contains('Raspberry Pi'), isTrue);
    });

    test('an A2 card is no better than V10 without a V mark; V90 says nothing '
        'about IOPS', () {
      expect(kA2IsNotAVideoCard.contains('no better than V10'), isTrue);
      expect(kA2IsNotAVideoCard.contains('is not a 4K video card'), isTrue);
      expect(kA2IsNotAVideoCard.contains('V90 says nothing'), isTrue);
    });
  });

  group('Reading order and selection by job', () {
    test('the read order is capacity, bus, class, then ignore the headline', () {
      expect(kSdReadingOrder.length, 4);
      expect(kSdReadingOrder[0].step.contains('Capacity standard'), isTrue);
      expect(kSdReadingOrder[1].step.contains('Bus interface'), isTrue);
      expect(kSdReadingOrder[3].step.contains('Ignore the headline'), isTrue);
    });

    test('Pi boot reads the A class and ignores V; capture is the reverse', () {
      final SdJobSelection pi = kSdJobSelections
          .firstWhere((SdJobSelection j) => j.job.contains('Pi'));
      expect(pi.governs.contains('Random IOPS'), isTrue);
      expect(pi.read.contains('A1 as the safe default'), isTrue);
      expect(pi.ignore.contains('V class'), isTrue);

      final SdJobSelection cap = kSdJobSelections
          .firstWhere((SdJobSelection j) => j.job.contains('packet capture'));
      expect(cap.governs.contains('sequential write'), isTrue);
      expect(cap.read.contains('V30 minimum'), isTrue);
      expect(cap.ignore.contains('A class'), isTrue);
    });
  });

  group('Endurance and counterfeits', () {
    test('endurance hours are flagged as an unstated-bitrate figure', () {
      expect(kEnduranceProblem.contains('unstated bitrate'), isTrue);
      expect(kEnduranceProblem.contains('2,500 h'), isTrue);
      expect(kEnduranceProblem.contains('40,000 h'), isTrue);
      expect(kEnduranceProblem.contains('4K'), isTrue);
      expect(kEnduranceTbw.contains('TBW'), isTrue);
    });

    test('limbo is named as the dangerous silent failure', () {
      final CounterfeitBehavior limbo = kCounterfeitBehaviors
          .firstWhere((CounterfeitBehavior c) => c.name == 'Limbo');
      expect(limbo.what.contains('silently discarded'), isTrue);
      expect(limbo.what.contains('read back as zeros'), isTrue);
      expect(kCounterfeitBehaviors.length, 2);
    });

    test('the only working test is a full fill and read-back, with the tools',
        () {
      expect(kCounterfeitTest.contains('read every byte back'), isTrue);
      for (final String tool in <String>['h2testw', 'f3write', 'f3read']) {
        expect(kCounterfeitTest.contains(tool), isTrue);
      }
      expect(kCounterfeitAntiPattern.contains('passes every quick test'), isTrue);
    });
  });

  group('The write-protect notch', () {
    test('the switch lives in the host and the card cannot see it', () {
      expect(kWriteProtectNotch.contains('microswitch in the HOST'), isTrue);
      expect(kWriteProtectNotch.contains('cannot see the switch'), isTrue);
      expect(kWriteProtectNotch.contains('microSD has no notch'), isTrue);
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
          'behaviour',
          'normalise',
          'catalogue',
          'labelled',
          'grey',
        ]) {
          expect(l.contains(british), isFalse,
              reason: 'British spelling "$british" in "$s"');
        }
      }
    });
  });

  group('SdCardsScreen widget', () {
    setUp(() {
      SdCardDiagrams.debugSetBundled(const <String>{});
    });
    tearDown(SdCardDiagrams.debugReset);

    testWidgets('renders the title and every section heading',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 8000), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const SdCardsScreen()),
        );

        expect(find.text('SD & microSD Cards'), findsWidgets);
        for (final String heading in <String>[
          'The seven marks',
          'Capacity standard',
          'Bus interface',
          'Sustained write classes',
          'Application Performance Class',
          'Reading order for a buyer',
          'Endurance',
          'Counterfeits',
        ]) {
          expect(find.text(heading), findsOneWidget,
              reason: 'missing section heading "$heading"');
        }
        // The per-tool help affordance is wired (the help ENTRY itself is
        // asserted centrally by tool_help_loader_test's count guard).
        expect(find.byType(ToolHelpFooter), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(SvgPicture), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320 / 375 / 768 widths',
        (WidgetTester tester) async {
      for (final double width in <double>[320, 375, 768]) {
        await _withViewport(tester, Size(width, 3000), () async {
          await tester.pumpWidget(
            MaterialApp(theme: AppTheme.dark(), home: const SdCardsScreen()),
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
          MaterialApp(theme: AppTheme.light(), home: const SdCardsScreen()),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('renders exactly the bundled concept-graphic count (dark)',
        (WidgetTester tester) async {
      SdCardDiagrams.debugSetBundled(<String>{
        for (final String name in SdCardDiagrams.all) SdCardDiagrams.path(name),
      });
      addTearDown(SdCardDiagrams.debugReset);

      await _withViewport(tester, const Size(375, 12000), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const SdCardsScreen()),
        );
        await tester.pump();
        expect(
          find.byType(SvgPicture),
          findsNWidgets(SdCardDiagrams.all.length),
        );
      });
    });

    test('the copy payload carries every section', () {
      final String tsv = SdCardsScreen.buildCopyText();
      for (final String marker in <String>[
        'SD & microSD Cards (field reference)',
        'The seven marks',
        'Capacity standard and the filesystem it specifies',
        'Bus interface',
        'Sustained sequential write classes',
        'Application Performance Class (random 4 KB IOPS)',
        'Reading order for a buyer',
        'Selection by job',
        'Endurance',
        'Counterfeits',
        'The write-protect notch',
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
