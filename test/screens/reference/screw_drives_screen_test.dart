// Tests for the Screw Drives & Driver Bits reference screen — a new
// installer-scoped reference page.
//
// Three layers, mirroring iec_connectors_screen_test:
//   1. Data fidelity (GL-005): the typed const datasets match Pax's verified
//      research brief, with the brief's honesty CORRECTIONS pinned so a future
//      edit cannot silently re-introduce the field errors — Torx is named by
//      T-number (never "star bit"), Robertson color coding is labeled a trade
//      convention (not ISO), the Phillips "designed to cam out" line is debunked
//      (never repeated as fact), and Phillips/Pozidriv are stated NOT
//      interchangeable. Plus the no-em-dash / no-"router" / Wi-Fi glyph rules.
//   2. Widget render: the read-only screen renders the title, both section
//      headings, the key drives, and "Pozidriv" across phone/tablet widths with
//      no RenderFlex overflow.
//   3. Graceful degradation: the concept-graphic slots render exactly the
//      bundled count (zero when none built, three when all named SVGs are
//      present), proving the manifest-gated resolver wiring.
//
// Catalog / router / help registration is wired centrally by Larry at
// integration (this build does NOT self-register), so this test deliberately
// does NOT assert on the catalog — it stays focused on the screen + data.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/screw_drives_diagrams.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/screw_drives_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Common drives — match the research brief (Part 1 / Part 3)', () {
    ScrewDrive driveFor(String name) => ScrewDrivesScreen.commonDrives
        .firstWhere((ScrewDrive d) => d.name == name);

    test('Phillips bit is PH1, PH2 (covers almost everything on gear)', () {
      final ScrewDrive d = driveFor('Phillips');
      expect(d.bit, 'PH1, PH2');
      expect(d.standard, 'ISO 8764');
    });

    test('Pozidriv bit is PZ1, PZ2 and the standard is ISO 8764 Type Z', () {
      final ScrewDrive d = driveFor('Pozidriv');
      expect(d.bit, 'PZ1, PZ2');
      expect(d.standard.contains('Type Z'), isTrue);
    });

    test('Torx is named by T-number, never "star bit"', () {
      final ScrewDrive d = driveFor('Torx');
      expect(d.standard, 'ISO 10664');
      expect(d.bit.contains('T10'), isTrue);
      // The lay term "star" must never appear in the Torx data (brief flag).
      for (final String s in <String>[d.name, d.code, d.bit, d.where]) {
        expect(s.toLowerCase().contains('star'), isFalse,
            reason: 'never "star bit" — use T-numbers (brief correction)');
      }
    });

    test('Robertson is labeled a trade convention, not an ISO standard', () {
      final ScrewDrive d = driveFor('Robertson (square)');
      expect(d.standard.toLowerCase().contains('not iso'), isTrue,
          reason: 'Robertson color coding is a trade convention, not ISO');
      // The color-coding convention reaches the bit (green #1, red #2).
      expect(d.bit.contains('green'), isTrue);
      expect(d.bit.contains('red'), isTrue);
    });

    test('seven common drives; both hex series (metric + imperial) present', () {
      expect(ScrewDrivesScreen.commonDrives.length, 7);
      final Iterable<ScrewDrive> hex = ScrewDrivesScreen.commonDrives
          .where((ScrewDrive d) => d.name.toLowerCase().contains('hex'));
      expect(hex.length, 2,
          reason: 'metric and imperial hex are not cross-compatible');
    });
  });

  group('Phillips vs Pozidriv distinguisher (the field-value rule)', () {
    test('states NOT interchangeable + the 45-degree tick-mark tell', () {
      final String s = ScrewDrivesScreen.distinguisher;
      expect(s.contains('NOT interchangeable'), isTrue);
      expect(s.contains('45 degrees'), isTrue,
          reason: 'the four 45-degree tick marks are the distinguishing mark');
      expect(s.toLowerCase().contains('cams out'), isTrue);
    });
  });

  group('Security / tamper drives — match the research brief (Part 2)', () {
    SecurityDrive secFor(String startsWith) => ScrewDrivesScreen.securityDrives
        .firstWhere((SecurityDrive s) => s.name.startsWith(startsWith));

    test('security Torx carries the pin + T10H-T40H clearance sizing', () {
      final SecurityDrive s = secFor('Security Torx');
      expect(s.looksLike.toLowerCase().contains('pin'), isTrue);
      expect(s.tool.contains('T10H-T40H'), isTrue);
    });

    test('five tamper drives incl. tri-wing, spanner, one-way, pin-hex', () {
      expect(ScrewDrivesScreen.securityDrives.length, 5);
      final List<String> names = ScrewDrivesScreen.securityDrives
          .map((SecurityDrive s) => s.name.toLowerCase())
          .toList();
      expect(names.any((String n) => n.contains('tri-wing')), isTrue);
      expect(names.any((String n) => n.contains('spanner')), isTrue);
      expect(names.any((String n) => n.contains('one-way')), isTrue);
      expect(names.any((String n) => n.contains('pin-in hex')), isTrue);
    });

    test('the "pack the tamper bits" takeaway is present', () {
      final String s = ScrewDrivesScreen.tamperTakeaway;
      expect(s.toLowerCase().contains('pack the tamper bits'), isTrue);
      expect(s.contains('T10H-T40H'), isTrue);
    });
  });

  group('Myth debunk (GL-005 + domain-proof-over-consensus)', () {
    test('debunks the Phillips cam-out myth, never repeats it as fact', () {
      final String s = ScrewDrivesScreen.mythDebunk;
      // The page must say Phillips was NOT designed to cam out.
      expect(s.contains('NOT designed to cam out'), isTrue);
      expect(s.contains('1933'), isTrue,
          reason: 'the patent text is the proof');
      // It must NOT assert the myth as true (no "designed to cam out" without
      // the negation directly before it).
      expect(s.contains('was designed to cam out'), isFalse);
    });
  });

  group('GL-004 voice + glyph hygiene', () {
    test('no em dash, no "router", Wi-Fi hyphenated where it appears', () {
      final List<String> prose = <String>[
        ScrewDrivesScreen.distinguisher,
        ScrewDrivesScreen.tamperTakeaway,
        ScrewDrivesScreen.mythDebunk,
        ScrewDrivesScreen.commonFootnote,
        for (final ScrewDrive d in ScrewDrivesScreen.commonDrives) ...<String>[
          d.name,
          d.code,
          d.bit,
          d.where,
          d.standard,
        ],
        for (final SecurityDrive s in ScrewDrivesScreen.securityDrives)
          ...<String>[s.name, s.looksLike, s.tool],
      ];
      for (final String s in prose) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.toLowerCase().contains('router'), isFalse,
            reason: 'never "router" in "$s"');
        // Never "WiFi" (must be "Wi-Fi" if present at all).
        expect(s.contains('WiFi'), isFalse,
            reason: '"WiFi" should be "Wi-Fi" in "$s"');
      }
    });
  });

  group('ScrewDrivesScreen widget', () {
    setUp(() {
      // No graphic SVG bundled by default → each slot renders nothing, and the
      // page must still ship fully working as tables.
      ScrewDrivesDiagrams.debugSetBundled(const <String>{});
    });
    tearDown(() {
      ScrewDrivesDiagrams.debugReset();
    });

    testWidgets('renders title, section headings, key drives, and "Pozidriv"',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 3200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const ScrewDrivesScreen(),
          ),
        );

        expect(find.text('Screw Drives'), findsWidgets);
        // The three section headings.
        expect(find.text('Common drives'), findsOneWidget);
        expect(find.text('Phillips vs Pozidriv'), findsOneWidget);
        expect(find.text('Security / tamper drives'), findsOneWidget);
        // Key drives render their names.
        expect(find.text('Phillips'), findsOneWidget);
        expect(find.text('Pozidriv'), findsOneWidget);
        expect(find.text('Torx'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
        // No bundled graphic → no SvgPicture (graceful degradation).
        expect(find.byType(SvgPicture), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768 widths',
        (WidgetTester tester) async {
      for (final double width in <double>[320, 375, 768]) {
        await _withViewport(tester, Size(width, 2000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const ScrewDrivesScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });

    testWidgets('renders exactly the bundled concept-graphic count (dark)',
        (WidgetTester tester) async {
      // All three named graphics bundled → exactly three SvgPicture renders
      // (dark path uses SvgPicture.asset): the faces chart, the Phillips-vs-
      // Pozidriv distinguisher, and the security faces. Proves the wiring.
      ScrewDrivesDiagrams.debugSetBundled(<String>{
        for (final String name in ScrewDrivesDiagrams.all)
          ScrewDrivesDiagrams.path(name),
      });
      addTearDown(ScrewDrivesDiagrams.debugReset);

      await _withViewport(tester, const Size(375, 5000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const ScrewDrivesScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(SvgPicture), findsNWidgets(3));
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors iec_connectors_screen_test _withViewport so the read-only reference
/// renders at phone width without a RenderFlex overflow.
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
