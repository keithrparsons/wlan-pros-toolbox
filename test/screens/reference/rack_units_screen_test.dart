// Tests for the Rack Units & Mounting Hardware reference screen.
//
// Three layers, mirroring iec_connectors_screen_test / nema_connectors_screen_test:
//   1. Data fidelity (GL-005): the typed const datasets match Pax's verified
//      research brief (Deliverables/2026-06-08-rack-units-reference), with the
//      brief's load-bearing values pinned so a future edit cannot silently drift:
//      1U = 1.75 in = 44.45 mm exact; the 0.5/0.625/0.625 hole pattern; the
//      18.312-in / 17.72-in width facts; the three thread types. Plus the brief's
//      caveats (vendor mapping "commonly" not "always"; 42U reference, 45U a tall
//      variant) and the GL-004 glyph rules (no em dash, "Wi-Fi", no "router").
//   2. Widget render: the read-only screen renders title + every section heading
//      + key data values across phone/tablet widths with no RenderFlex overflow,
//      and the concept-graphic slots render exactly the bundled count (zero when
//      none built, two when both named SVGs are present) — proving graceful
//      degradation via debugSetBundled.
//
// Catalog + router + help registration are asserted by Larry's central tests at
// integration; this file does not import tool_catalog / app_router (Felix builds
// only NEW files and does not touch the central registration).

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/rack_diagrams.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/rack_units_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('U conversion — exact, matches the research brief (Section 1)', () {
    RackUnitRow rowFor(String u) =>
        RackUnitsScreen.conversions.firstWhere((RackUnitRow r) => r.u == u);

    test('1U = 1.75 in = 44.45 mm, by definition', () {
      final RackUnitRow r = rowFor('1U');
      expect(r.inches, '1.75');
      expect(r.mm, '44.45');
      expect(r.note.toLowerCase().contains('base'), isTrue);
    });

    test('values are exact multiples of the base (no rounding drift)', () {
      // Spot-check the load-bearing larger units against U x 1.75 / U x 44.45.
      expect(rowFor('42U').inches, '73.50');
      expect(rowFor('42U').mm, '1866.90');
      expect(rowFor('24U').inches, '42.00');
      expect(rowFor('48U').mm, '2133.60');
    });

    test('42U is the standard full rack; 45U is a taller variant (brief caveat)',
        () {
      // 42U is THE reference; 45U must not be framed as "common".
      expect(rowFor('42U').note.toLowerCase().contains('standard full'), isTrue);
      final String note45 = rowFor('45U').note.toLowerCase();
      expect(note45.contains('taller') || note45.contains('tall'), isTrue);
      expect(note45.contains('common'), isFalse,
          reason: '45U is a tall variant, not "common" (research-brief caveat)');
    });

    test('the conversion note states the exact live formula', () {
      expect(RackUnitsScreen.conversionNote.contains('U x 1.75'), isTrue);
      expect(RackUnitsScreen.conversionNote.contains('U x 44.45'), isTrue);
    });
  });

  group('Rack widths — "19-inch is only the front panel" (Section 2)', () {
    RackUnitRow widthFor(String label) =>
        RackUnitsScreen.widthFacts.firstWhere((RackUnitRow r) => r.u == label);

    test('headline states nothing inside the rack is 19 inches', () {
      expect(RackUnitsScreen.widthsHeadline.contains('front panel'), isTrue);
      expect(
        RackUnitsScreen.widthsHeadline.toLowerCase().contains('nothing inside'),
        isTrue,
      );
    });

    test('hole spacing = 18.312 in (465.1 mm), opening = 17.72 in (450 mm)', () {
      final RackUnitRow holes = widthFor('Hole spacing');
      expect(holes.inches, '18.312');
      expect(holes.mm, '465.1');
      final RackUnitRow opening = widthFor('Rack opening');
      expect(opening.inches, '17.72');
      expect(opening.mm, '450');
    });

    test('the front panel is the only 19-inch dimension', () {
      expect(widthFor('Front panel').inches, '19');
    });
  });

  group('EIA-310 hole pattern — the load-bearing one (Section 3)', () {
    test('headline pins the irregular 0.5 / 0.625 / 0.625 pattern', () {
      final String h = RackUnitsScreen.holePatternHeadline;
      expect(h.contains('0.5 / 0.625 / 0.625'), isTrue);
      expect(h.toLowerCase().contains('not evenly spaced') ||
          h.contains('NOT evenly spaced'), isTrue);
    });

    test('body explains the U boundary lands mid-gap and off-by-one binds', () {
      final String b = RackUnitsScreen.holePatternBody;
      expect(b.toLowerCase().contains('outer two holes'), isTrue);
      expect(b.toLowerCase().contains('bind'), isTrue);
      // mm equivalents carried verbatim from the brief.
      expect(b.contains('12.70 mm'), isTrue);
      expect(b.contains('15.88 mm'), isTrue);
    });
  });

  group('Mounting hardware — threads + rails + anti-patterns (Section 4/6)', () {
    RackThread threadFor(String t) =>
        RackUnitsScreen.threads.firstWhere((RackThread x) => x.thread == t);

    test('three thread types, each with its diameter and pitch', () {
      expect(RackUnitsScreen.threads.length, 3);
      expect(threadFor('10-32').diameter, '0.190 in');
      expect(threadFor('10-32').pitch, '32 TPI');
      expect(threadFor('12-24').diameter, '0.216 in');
      expect(threadFor('M6').pitch, '1.0 mm');
    });

    test('vendor mapping is "commonly", never "always" (brief caveat)', () {
      for (final RackThread t in RackUnitsScreen.threads) {
        expect(t.seenOn.toLowerCase().contains('commonly'), isTrue,
            reason: 'vendor mapping must hedge: "${t.seenOn}"');
        expect(t.seenOn.toLowerCase().contains('always'), isFalse,
            reason: 'never "always" for vendor mapping: "${t.seenOn}"');
      }
    });

    test('thread gotcha states the cross-thread / strip incompatibility', () {
      final String g = RackUnitsScreen.threadGotcha.toLowerCase();
      expect(g.contains('not interchangeable'), isTrue);
      expect(g.contains('cross-thread'), isTrue);
      expect(g.contains('strip'), isTrue);
    });

    test('three rail types incl. square-hole cage nut as the modern standard',
        () {
      expect(RackUnitsScreen.railTypes.length, 3);
      final RackRailType cage = RackUnitsScreen.railTypes.firstWhere(
        (RackRailType r) => r.type.toLowerCase().contains('cage nut'),
      );
      expect(cage.tradeoff.toLowerCase().contains('modern standard'), isTrue);
      expect(cage.tradeoff.toLowerCase().contains('strip-proof'), isTrue);
    });

    test('the two anti-patterns name the costliest assumptions', () {
      expect(RackUnitsScreen.antiPatterns.length, 2);
      // #1: assuming the rack is tapped.
      expect(
        RackUnitsScreen.antiPatterns[0].toLowerCase().contains('tapped'),
        isTrue,
      );
      // #2: mixing 10-32 and 12-24.
      final String mix = RackUnitsScreen.antiPatterns[1];
      expect(mix.contains('10-32'), isTrue);
      expect(mix.contains('12-24'), isTrue);
    });
  });

  group('GL-004 voice + glyph hygiene', () {
    test('no em dash, no "router", "Wi-Fi" not "WiFi" across all prose', () {
      final List<String> prose = <String>[
        RackUnitsScreen.conversionNote,
        RackUnitsScreen.widthsHeadline,
        RackUnitsScreen.widthsTelecomNote,
        RackUnitsScreen.holePatternHeadline,
        RackUnitsScreen.holePatternBody,
        RackUnitsScreen.threadGotcha,
        RackUnitsScreen.cageNutNote,
        RackUnitsScreen.depthFootnote,
        ...RackUnitsScreen.antiPatterns,
        for (final RackUnitRow r in RackUnitsScreen.conversions) ...<String>[
          r.u,
          r.inches,
          r.mm,
          r.note,
        ],
        for (final RackUnitRow r in RackUnitsScreen.widthFacts) ...<String>[
          r.u,
          r.inches,
          r.mm,
          r.note,
        ],
        for (final RackThread t in RackUnitsScreen.threads) ...<String>[
          t.thread,
          t.diameter,
          t.pitch,
          t.seenOn,
        ],
        for (final RackRailType rt in RackUnitsScreen.railTypes) ...<String>[
          rt.type,
          rt.mount,
          rt.tradeoff,
        ],
      ];
      for (final String s in prose) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.toLowerCase().contains('router'), isFalse,
            reason: 'never "router" in "$s"');
        expect(s.contains('WiFi'), isFalse,
            reason: '"Wi-Fi" never "WiFi" in "$s"');
      }
    });
  });

  group('RackDiagrams resolver', () {
    tearDown(() => RackDiagrams.debugReset());

    test('exposes the two named concept-graphic assets', () {
      expect(RackDiagrams.all,
          <String>['rack-1u-dimension', 'rack-cage-nut']);
      expect(RackDiagrams.rack1u, 'rack-1u-dimension');
      expect(RackDiagrams.cageNut, 'rack-cage-nut');
    });

    test('path() builds the conventional assets/tool-graphics path', () {
      expect(RackDiagrams.path(RackDiagrams.rack1u),
          'assets/tool-graphics/rack-1u-dimension.svg');
    });

    test('has() is false until bundled, true once set', () {
      RackDiagrams.debugSetBundled(const <String>{});
      expect(RackDiagrams.has(RackDiagrams.rack1u), isFalse);
      RackDiagrams.debugSetBundled(<String>{
        RackDiagrams.path(RackDiagrams.rack1u),
      });
      expect(RackDiagrams.has(RackDiagrams.rack1u), isTrue);
      expect(RackDiagrams.has(RackDiagrams.cageNut), isFalse);
    });
  });

  group('RackUnitsScreen widget', () {
    setUp(() {
      // No concept-graphic SVG bundled by default → the slots render nothing,
      // and the page must still ship fully working as tables + text.
      RackDiagrams.debugSetBundled(const <String>{});
    });
    tearDown(() {
      RackDiagrams.debugReset();
    });

    testWidgets('renders title, every section heading, and key data values',
        (tester) async {
      await _withViewport(tester, const Size(375, 3200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const RackUnitsScreen(),
          ),
        );

        // Title (app bar) — present at least once.
        expect(find.text('Rack Units'), findsWidgets);
        // Card + section headings across the page.
        expect(find.text('U conversion (exact)'), findsOneWidget);
        expect(find.text('Rack widths'), findsOneWidget);
        expect(find.text('EIA-310 vertical hole pattern'), findsOneWidget);
        expect(find.text('Mounting hardware'), findsOneWidget);
        expect(find.text('Thread types'), findsOneWidget);
        expect(find.text('Anti-patterns'), findsOneWidget);
        // Load-bearing data values render.
        expect(find.text('1U'), findsOneWidget);
        expect(find.text('44.45'), findsOneWidget);
        expect(find.text('18.312'), findsOneWidget);
        expect(find.text('10-32'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
        // No bundled graphic → no SvgPicture (graceful degradation).
        expect(find.byType(SvgPicture), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768]) {
        await _withViewport(tester, Size(width, 3200), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const RackUnitsScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });

    testWidgets('renders exactly the bundled concept-graphic count (dark)',
        (tester) async {
      // Both named graphics bundled → exactly two SvgPicture concept graphics
      // (dark path uses SvgPicture.asset): the 1U dimension diagram and the
      // cage-nut illustration. Proves the slot wiring + graceful degradation.
      RackDiagrams.debugSetBundled(<String>{
        for (final String name in RackDiagrams.all) RackDiagrams.path(name),
      });
      addTearDown(() => RackDiagrams.debugReset());

      await _withViewport(tester, const Size(375, 4200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const RackUnitsScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(SvgPicture), findsNWidgets(2));
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors iec_connectors_screen_test._withViewport so the read-only reference
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
