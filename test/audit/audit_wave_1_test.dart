// Audit wave 1 — regression guards for the confirmed defects.
//
// Every test in this file failed RED against the shipped code before its fix
// landed. Grouped by defect so a failure names the bug it protects against.
//
// Deliberately NOT in this file: any monotonicity assertion on the ITU rain
// coefficients. k_H is genuinely non-monotonic below 6 GHz (1.390e-4 @ 3 GHz →
// 1.071e-4 @ 4 GHz → back up). That dip is real ITU-R P.838-3 data. A "loss
// must rise with frequency" guard would flag valid coefficients as broken and
// invite someone to "fix" them into being wrong. See rain_fade_screen_test.dart.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/adjacent_radio_systems_data.dart';
import 'package:wlan_pros_toolbox/data/ham_reference_data.dart';
import 'package:wlan_pros_toolbox/data/vendor_model_decode_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/poe_budget_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/command/linux_wlan_commands_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/dbm_watt_converter.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/icmp_ping_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/adjacent_radio_systems_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ascii_reference_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/optical_transceivers_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/poe_reference_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/signal_thresholds_screen.dart';
import 'package:wlan_pros_toolbox/services/network/icmp_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─────────────────────────────────────────────────────────────────────────
  // P0 — PoE: the PSE column was silently dropped.
  //
  // `_standardsCard` held [standard, name, PSE W, PD W] and rendered
  // row[0], row[1], row[3]. row[2] — PSE — never reached the screen.
  //
  // A switch budget is spent in PSE watts. Twelve Class-4 APs read 306 W of PD
  // against a 370 W switch and look fine; the switch actually delivers 360 W.
  // ─────────────────────────────────────────────────────────────────────────
  group('PoE standards card renders BOTH PSE and PD', () {
    testWidgets('the PSE watts for af / at / bt Type 3 are on screen',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(414, 2200), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );
        await tester.pumpAndSettle();

        // PSE — the column that feeds a switch budget. Previously invisible.
        expect(find.text('15.4 W'), findsWidgets, reason: '802.3af PSE');
        expect(find.text('30.0 W'), findsWidgets, reason: '802.3at PSE');
        expect(find.text('60.0 W'), findsWidgets, reason: '802.3bt Type 3 PSE');

        // PD — still rendered, but no longer the only number.
        expect(find.text('12.95 W'), findsWidgets, reason: '802.3af PD');
        expect(find.text('25.5 W'), findsWidgets, reason: '802.3at PD');
        expect(find.text('51.0 W'), findsWidgets, reason: '802.3bt Type 3 PD');
      });
    });

    testWidgets('the card says which column a switch budget is spent in',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(414, 2200), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );
        await tester.pumpAndSettle();

        expect(find.text('PSE'), findsWidgets);
        expect(find.text('PD'), findsWidgets);
        expect(
          find.textContaining('switch budget', findRichText: true),
          findsWidgets,
          reason: 'The user must be told PSE is the number a switch spends.',
        );
      });
    });

    testWidgets('Type 4 PSE is 90.0 W per IEEE 802.3-2022 Table 145-11',
        (WidgetTester tester) async {
      // SETTLED from the standard, not guessed.
      //
      // IEEE Std 802.3-2022, Table 145-11 — Class 8 P_Class (the PSE's minimum
      // output power per class) = 90 W. poe_reference_screen was right all
      // along; the calculator's hidden 100.0 W was wrong.
      //
      // WHERE THE 100 CAME FROM (so it does not come back): Table 145-16 item 13
      // gives P_Type for a Type 4 PSE as min 75 W / MAX 99.9 W. That is the
      // PSE's power-RATING BAND, not its per-class output power. Someone read
      // 99.9 and rounded it to 100. Different quantity, different table. This
      // test exists so that "correction" fails loudly.
      await _withViewport(tester, const Size(414, 2200), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );
        await tester.pumpAndSettle();

        expect(find.text('90.0 W'), findsWidgets, reason: 'Type 4 PSE');
        expect(
          find.text('100.0 W'),
          findsNothing,
          reason: 'That is P_Type max (99.9 W, Table 145-16 item 13) rounded up '
              '— the PSE rating band, NOT the Class 8 P_Class output power.',
        );
      });
    });

    test('the on-screen IEEE citation is pinned to the value it cites', () {
      // Larry's rule, learned the hard way today: a source line that is not
      // checked against the source is worse than no source line. The app's only
      // properly-cited reference table was also its most wrong one.
      //
      // So: the citation string and the number it justifies are asserted
      // together. You cannot change one without the other failing.
      expect(PoeBudgetScreen.typeFourPseWatts, 90.0);
      expect(
        PoeBudgetScreen.typeFourPseCitation,
        'IEEE 802.3-2022, Table 145-11 (P_Class)',
      );
    });

    test('poe_budget and poe_reference agree on Type 4 PSE', () {
      // The contradiction that started this. Both screens, one number.
      final PoeStandard typeFour = PoeReferenceScreen.standards.firstWhere(
        (PoeStandard s) => s.standard.contains('Type 4'),
      );
      expect(typeFour.pseWatts, 90.0);
      expect(
        PoeBudgetScreen.typeFourPseWatts,
        typeFour.pseWatts,
        reason: 'The calculator and the reference screen must not disagree.',
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Signal thresholds — the help shipped the thresholds Keith OVERRULED.
  //
  // Help said:   Excellent > -50 / Good -50..-67 / Fair -67..-70
  // Screen says: Excellent > -55 / Good -55..-65 / Fair -65..-75
  //
  // The app told the user one scale and showed them another, one tap apart.
  // ─────────────────────────────────────────────────────────────────────────
  group('signal thresholds — help matches the screen', () {
    test('the help carries Keith\'s bands, not the overruled vendor bands',
        () async {
      final String help =
          await rootBundle.loadString('assets/help/tool_help.json');
      final Map<String, dynamic> tools =
          (jsonDecode(help) as Map<String, dynamic>)['tools']
              as Map<String, dynamic>;
      final String notes =
          jsonEncode(tools['signal-thresholds'] as Map<String, dynamic>);

      // The overruled vendor/internet numbers must be gone.
      for (final String stale in <String>['-50', '-67', '-70']) {
        expect(
          notes,
          isNot(contains('($stale')),
          reason: 'Overruled threshold $stale still in the help.',
        );
      }
      expect(notes, isNot(contains('better than -50')));

      // Keith's bands, as rendered by the screen.
      expect(notes, contains('-55'));
      expect(notes, contains('-65'));
      expect(notes, contains('-75'));
    });

    test('every band the screen renders is named in the help', () async {
      final String help =
          await rootBundle.loadString('assets/help/tool_help.json');
      for (final SignalBand b in SignalThresholdsScreen.kSignalBands) {
        expect(
          help,
          contains(b.range),
          reason: 'The help must quote the screen\'s "${b.label}" band '
              '(${b.range}) verbatim, not a different scale.',
        );
      }
    });

    test('the help says these are recommendations, not a standard', () async {
      // Keith's framing, confirmed today. IEEE 802.11 defines no "good" or
      // "poor" signal level; presenting these as if a standard blessed them
      // would be a fabricated authority.
      final String help =
          await rootBundle.loadString('assets/help/tool_help.json');
      expect(help, contains('not an industry standard'));
      expect(help, contains('IEEE 802.11 does not define'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Adjacent radio systems — the card heading contradicted every row in it.
  // ─────────────────────────────────────────────────────────────────────────
  group('adjacent radio systems — heading matches its contents', () {
    test('Zigbee, Thread and BLE do share 2.4 GHz (the rows are right)', () {
      for (final String s in <String>['Zigbee', 'Thread', 'BLE']) {
        final RadioSystemRow row =
            kRadioSystems.firstWhere((RadioSystemRow r) => r.system == s);
        expect(row.sharesTwoFour, 'Yes', reason: s);
      }
    });

    testWidgets('no card claims these systems do not touch your air',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(414, 4000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const AdjacentRadioSystemsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('What does not touch your air'),
          findsNothing,
          reason: 'That card contains Zigbee, Thread and BLE, each of which '
              'renders "Shares 2.4 GHz: Yes" directly beneath the heading.',
        );
      });
    });

    test('the envelope caution does not promise a battery column', () {
      // The caution told users to read every "range, rate, and battery figure"
      // as an envelope. There is no battery field on RadioSystemRow and no
      // battery column on screen. Pointing at a column that does not exist is
      // the same phantom-promise class as the model-decode caveat.
      expect(
        kEnvelopeWarning,
        isNot(contains('battery')),
        reason: 'RadioSystemRow has no battery field and the table renders no '
            'battery column.',
      );
      // The columns it DOES point at must actually be there.
      expect(kEnvelopeWarning, contains('range'));
      expect(kEnvelopeWarning, contains('rate'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // HIGH — dBm↔W converter fabricated "0.0000" mW for non-positive input.
  //
  // The dBm field correctly showed "—", but the mW mirror wrote "0.0000".
  // The guard is `w <= 0` and the field accepts a sign, so typing −5 made the
  // app assert 0.0000 mW. A broken honesty promise, on screen.
  // ─────────────────────────────────────────────────────────────────────────
  group('dBm/W converter is honest about non-positive input', () {
    testWidgets('a negative watts input renders a dash, never 0.0000',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(414, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DbmWattConverterScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Field order: dBm, Watts, mW.
        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(1), '-5');
        await tester.pump();

        expect(
          find.text('0.0000'),
          findsNothing,
          reason: '-5 W is not 0.0000 mW. It has no dBm value at all.',
        );
      });
    });

    testWidgets('a negative mW input renders a dash, never 0.0000',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(414, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DbmWattConverterScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(2), '-5');
        await tester.pump();

        expect(find.text('0.0000'), findsNothing);
      });
    });

    testWidgets('zero is likewise honest — 0 W has no dBm', (tester) async {
      await _withViewport(tester, const Size(414, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DbmWattConverterScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(1), '0');
        await tester.pump();

        expect(find.text('0.0000'), findsNothing);
      });
    });

    testWidgets('a valid positive input still converts (no false honesty)',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(414, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DbmWattConverterScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(1), '1'); // 1 W = 30 dBm = 1000 mW
        await tester.pump();

        expect(find.text('30.00'), findsWidgets);
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // HIGH — Ping (ICMP) told a WINDOWS user the macOS App Sandbox blocked them.
  // ─────────────────────────────────────────────────────────────────────────
  group('ICMP unavailable message is platform-correct', () {
    testWidgets('a Windows user is never told about the macOS App Sandbox',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(900, 1000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: IcmpPingScreen(
              service: IcmpService(
                platformOverride: 'windows',
                isWebOverride: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('macOS App Sandbox', findRichText: true),
          findsNothing,
          reason: 'There is no macOS App Sandbox on Windows.',
        );
        expect(
          find.textContaining('macOS', findRichText: true),
          findsNothing,
          reason: 'A Windows user should read nothing about macOS.',
        );
      });
    });

    testWidgets('a Linux user is never told about the macOS App Sandbox',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(900, 1000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: IcmpPingScreen(
              service: IcmpService(
                platformOverride: 'linux',
                isWebOverride: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('macOS', findRichText: true),
          findsNothing,
        );
      });
    });

    testWidgets('a macOS user IS still told about the App Sandbox (it is true)',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(900, 1000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: IcmpPingScreen(
              service: IcmpService(
                platformOverride: 'macos',
                isWebOverride: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('App Sandbox', findRichText: true),
          findsWidgets,
        );
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // HIGH — three inverted guards. Each comment promised the OPPOSITE of the
  // behavior directly beneath it.
  // ─────────────────────────────────────────────────────────────────────────
  group('inverted guard 1 — optical form-factor table really is always shown',
      () {
    testWidgets('a no-match search still leaves the form-factor ladder up',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(414, 1600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const OpticalTransceiversScreen(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField).first,
          'zzz-no-such-transceiver',
        );
        await tester.pumpAndSettle();

        expect(find.text('No match'), findsOneWidget);
        expect(
          find.text('Form factors · SFP → OSFP'),
          findsOneWidget,
          reason: 'The comment says "always shown in full" — the code hid it.',
        );
      });
    });
  });

  group('inverted guard 2 — Linux WLAN group-label search', () {
    test('searching a group name returns that group, not "No match"', () {
      // The screen HAS a group named Monitor-mode. Searching for it returned
      // "No match" because `if (kept.isEmpty) return null;` ran BEFORE the
      // label check.
      final List<String> labels = LinuxWlanCommandsScreen.groups
          .map((WlanCommandGroup g) => g.label)
          .toList();

      for (final String label in labels) {
        final String q = label.toLowerCase();
        final int matched = LinuxWlanCommandsScreen.groups
            .map((WlanCommandGroup g) =>
                LinuxWlanCommandsScreen.filterGroup(g, q))
            .whereType<WlanCommandGroup>()
            .fold<int>(0, (int n, WlanCommandGroup g) => n + g.commands.length);

        expect(
          matched,
          greaterThan(0),
          reason: 'Searching the group label "$label" must surface that '
              'group\'s commands, not "No match".',
        );
      }
    });

    test('searching "monitor" surfaces the Monitor-mode group in full', () {
      // The exact case from the audit.
      final WlanCommandGroup monitor = LinuxWlanCommandsScreen.groups
          .firstWhere((WlanCommandGroup g) =>
              g.label.toLowerCase().contains('monitor'));

      final WlanCommandGroup? filtered =
          LinuxWlanCommandsScreen.filterGroup(monitor, 'monitor');

      expect(filtered, isNotNull);
      expect(
        filtered!.commands.length,
        monitor.commands.length,
        reason: 'A label match keeps the WHOLE group.',
      );
    });

    test('a genuinely absent term still reports no matches', () {
      final int matched = LinuxWlanCommandsScreen.groups
          .map((WlanCommandGroup g) =>
              LinuxWlanCommandsScreen.filterGroup(g, 'zzz-not-a-command'))
          .whereType<WlanCommandGroup>()
          .fold<int>(0, (int n, WlanCommandGroup g) => n + g.commands.length);
      expect(matched, 0);
    });
  });

  group('inverted guard 3 — ASCII "tables below are unaffected"', () {
    testWidgets('the CR/LF note survives a no-match search',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(414, 3000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const AsciiReferenceScreen(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'zzzz');
        await tester.pumpAndSettle();

        expect(find.text('No match'), findsOneWidget);
        // The no-match card promises the quick-reference tables below are
        // unaffected. The CR/LF note is one of them, and it was being hidden.
        expect(
          find.textContaining('CR', findRichText: true),
          findsWidgets,
          reason: 'The card promises the reference tables below are unaffected.',
        );
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // MEDIUM — self-contradictions shipping inside the app.
  // ─────────────────────────────────────────────────────────────────────────
  group('the app does not contradict its own help', () {
    test('tool_help says exactly as many ports as the data file holds', () async {
      final String helpRaw =
          await rootBundle.loadString('assets/help/tool_help.json');
      final String portsRaw =
          await rootBundle.loadString('assets/ports/well_known_ports.json');

      final Map<String, dynamic> ports =
          jsonDecode(portsRaw) as Map<String, dynamic>;
      final int actual = (ports['ports'] as List<dynamic>).length;

      // The screen renders this count dynamically, so a stale help string means
      // the app is on screen contradicting its own help text.
      expect(
        helpRaw,
        contains('all $actual ports'),
        reason: 'tool_help.json must state the real port count ($actual).',
      );
      expect(
        helpRaw,
        isNot(contains('all 86 ports')),
        reason: 'The stale count. The data file holds $actual.',
      );
    });

    test('the 60 m ham band does not say 5 channels and 4 channels at once', () {
      final HamBand band =
          kHamBandPlan.firstWhere((HamBand b) => b.band == '60 m');

      // The record's own `general` field says "4 channels". The freqRange said
      // "5 channels area". The ARRL manual says the 5-channel version is wrong.
      expect(
        band.freqRange,
        isNot(contains('5 channels')),
        reason: 'Contradicts this same record\'s general field one line below.',
      );
      expect(band.general, contains('4 channels'));
    });

    test('the model-decode screen makes no promise about a parser it lacks', () {
      // The screen has zero text inputs and no parser. It cannot read "a
      // segment" and report it "unrecognized" — there is nothing to read.
      expect(
        kDecodeStandingCaveat,
        isNot(contains('unrecognized segment')),
        reason: 'A phantom promise: the screen has no input and no parser.',
      );
      expect(
        kDecodeStandingCaveat,
        contains('heuristic'),
        reason: 'The honest part of the caveat stays.',
      );
    });
  });
}

/// Run [body] with the test view sized to [size], then restore.
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
