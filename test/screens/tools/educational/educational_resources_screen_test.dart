// EducationalResourcesScreen widget tests — the directory renders a "Reference
// Cards" section at the top (from injected cards), then the online-resource
// topic groups; filter chips under the search switch between sections; free-text
// search collapses to matching online resources. A pre-built service and an
// explicit card list are injected so the tests do not depend on the bundled
// asset load or the live catalog. A tall viewport is used so all list rows are
// laid out (a ListView only builds on-screen children).

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/guides/guide_reader_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/educational/educational_resources_screen.dart';
import 'package:wlan_pros_toolbox/services/educational/educational_resources_service.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// WCAG 2.2 relative luminance (SC 1.4.3), same method as
/// pdf_letterbox_contrast_test.dart so the two agree by construction.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// WCAG contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The credit string inside [_fixture]. Named once so the fixture and the
/// assertions cannot drift apart, which is how F2 became able to pass vacuously.
const String _kFixtureCredit = 'Inspired by example.net by A Person';

const String _fixture = '''
{
  "_meta": {
    "title": "Educational Resources",
    "attribution": "Inspired by example.net by A Person",
    "topics": [
      "Tools and utilities",
      "Podcasts"
    ]
  },
  "resources": [
    {
      "id": "alpha-tool", "title": "Alpha Tool", "summary": "A handy tool.",
      "description": "Body.", "url": "https://example.com/tool",
      "topic": "Tools and utilities", "cost": "free", "level": "all",
      "tags": ["tool"], "approval": "pending_outreach"
    },
    {
      "id": "beta-pod", "title": "Beta Podcast", "summary": "A Wi-Fi podcast.",
      "description": "Body.", "url": "https://example.com/pod",
      "topic": "Podcasts", "cost": "free", "level": "all",
      "tags": ["destination", "podcast"], "approval": "pending_outreach"
    }
  ]
}
''';

const List<ToolEntry> _cards = <ToolEntry>[
  ToolEntry(
    id: 'bubble-diagram',
    title: 'WLAN Pros Bubble Diagram',
    description: 'Wi-Fi design decision bubble diagram',
    routeName: '/tools/bubble-diagram',
    isLive: true,
  ),
  ToolEntry(
    id: 'top-20-checklist',
    title: 'Top 20 Wi-Fi Checklist',
    description: 'The Top 20 Wi-Fi design checklist',
    routeName: '/tools/top-20-checklist',
    isLive: true,
  ),
];

EducationalResourcesService _svc() =>
    EducationalResourcesService.fromJson(_fixture);

/// Pump the screen on a tall viewport so the whole list is laid out (cards +
/// both topic groups all build), and reset it on teardown.
///
/// [theme] defaults to dark, which is what every test here used when this
/// helper hardcoded `AppTheme.dark()`. It is a PARAMETER now because nothing
/// pumped this screen in light theme at all: Vera covered light by screenshot
/// once, by hand, on 2026-09-15, and a hand measurement guards nothing after
/// the session that made it. Pass `AppTheme.light()` to cover the other half.
Future<void> _pump(
  WidgetTester tester,
  EducationalResourcesService svc, {
  ThemeData? theme,
}) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: EducationalResourcesScreen(service: svc, cards: _cards),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders the _meta credit line under the intro', (tester) async {
    // The credit for wlan-talks.net was specified in the data on 2026-06-03 and
    // did not render for three months, because nothing read the key. This is
    // the assertion that would have caught it.
    await _pump(tester, _svc());
    expect(find.text(_kFixtureCredit), findsOneWidget);
  });

  testWidgets('renders no credit line when _meta carries none', (tester) async {
    // F2, Vera 2026-09-15. This was built by replaceAll surgery on the fixture
    // JSON, and she proved it could pass while testing nothing: change the
    // fixture's credit WORDING and the replace silently matches nothing, the
    // credit renders anyway, and the negative assertion still passes because it
    // was looking for the old wording. Green because the thing that would have
    // said otherwise was never reached.
    //
    // fromEntries takes no _meta at all, so "carries none" is structural rather
    // than the result of a string edit that may or may not have happened.
    final EducationalResourcesService bare =
        EducationalResourcesService.fromEntries(_svc().all);
    expect(bare.attribution, isEmpty,
        reason: 'the bare service must genuinely carry no credit, or the '
            'assertion below is vacuous');

    await _pump(tester, bare);
    expect(find.text(_kFixtureCredit), findsNothing);
    expect(find.textContaining('Inspired by'), findsNothing);
  });

  testWidgets('renders the Reference Cards section header + a card title',
      (tester) async {
    await _pump(tester, _svc());

    // The Reference Cards section renders above the topic groups, with at least
    // one card title visible.
    expect(find.text('WLAN Pros Bubble Diagram'), findsOneWidget);
    expect(find.text('Top 20 Wi-Fi Checklist'), findsOneWidget);
    // The "Reference Cards" string appears in the section header AND the chip,
    // so it is present at least twice.
    expect(find.text('Reference Cards'), findsWidgets);
  });

  testWidgets('renders the in-app Field Manual entry and opens the reader',
      (tester) async {
    // markdown_widget's VisibilityDetector leaves a pending timer otherwise.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await _pump(tester, _svc());

    // The "In-Depth Guide" section + the Field Manual row lead the directory.
    expect(find.text('In-Depth Guide'), findsOneWidget);
    expect(find.text('Field Manual'), findsOneWidget);

    // Tapping it opens the in-app reader on the field manual (not a URL).
    await tester.tap(find.text('Field Manual'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final Finder reader = find.byType(GuideReaderScreen);
    expect(reader, findsOneWidget);
    expect(
      tester.widget<GuideReaderScreen>(reader).assetPath,
      kFieldManualAsset,
    );
  });

  testWidgets('renders topic group headers and resource rows', (tester) async {
    await _pump(tester, _svc());

    // Resource rows: title + summary present.
    expect(find.text('Alpha Tool'), findsOneWidget);
    expect(find.text('A handy tool.'), findsOneWidget);
    expect(find.text('Beta Podcast'), findsOneWidget);
    expect(find.text('A Wi-Fi podcast.'), findsOneWidget);
    // Topic strings render as a header AND a filter chip, so >= 1 each.
    expect(find.text('Tools and utilities'), findsWidgets);
    expect(find.text('Podcasts'), findsWidgets);
  });

  testWidgets('filter chips are present (All + Reference Cards + topics)',
      (tester) async {
    await _pump(tester, _svc());

    expect(find.text('All'), findsOneWidget);
    // Reference Cards + two topics each appear at least as a chip.
    expect(find.text('Reference Cards'), findsWidgets);
    expect(find.text('Tools and utilities'), findsWidgets);
    expect(find.text('Podcasts'), findsWidgets);
  });

  testWidgets('selecting the Reference Cards chip hides the online topics',
      (tester) async {
    await _pump(tester, _svc());

    // The chip renders above the section header, so `.first` is the chip.
    await tester.tap(find.text('Reference Cards').first);
    await tester.pump();

    // Cards still show; online resources are filtered out.
    expect(find.text('WLAN Pros Bubble Diagram'), findsOneWidget);
    expect(find.text('Alpha Tool'), findsNothing);
    expect(find.text('Beta Podcast'), findsNothing);
  });

  testWidgets('selecting a topic chip shows only that topic and hides cards',
      (tester) async {
    await _pump(tester, _svc());

    await tester.tap(find.text('Podcasts').first);
    await tester.pump();

    expect(find.text('Beta Podcast'), findsOneWidget);
    expect(find.text('Alpha Tool'), findsNothing);
    // Reference cards are hidden when a topic filter is active.
    expect(find.text('WLAN Pros Bubble Diagram'), findsNothing);
  });

  testWidgets('live search filters rows, hides cards + chips, collapses groups',
      (tester) async {
    await _pump(tester, _svc());

    await tester.enterText(find.byType(TextField), 'podcast');
    await tester.pump();

    // Only the matching online resource survives; the tool, its group header,
    // the cards, and the chips are all gone.
    expect(find.text('Beta Podcast'), findsOneWidget);
    expect(find.text('Alpha Tool'), findsNothing);
    expect(find.text('WLAN Pros Bubble Diagram'), findsNothing);
    expect(find.text('All'), findsNothing); // chip row hidden while typing
    // "Podcasts" now only renders as the surviving group header.
    expect(find.text('Podcasts'), findsOneWidget);
  });

  testWidgets('shows the honest no-match state when nothing matches',
      (tester) async {
    await _pump(tester, _svc());

    await tester.enterText(find.byType(TextField), 'zzznotathing');
    await tester.pump();

    expect(find.textContaining('No resources match'), findsOneWidget);
    expect(find.text('Alpha Tool'), findsNothing);
    expect(find.text('Beta Podcast'), findsNothing);
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final EducationalResourcesService svc = _svc();
    for (final double width in <double>[320, 375, 768, 1280]) {
      tester.view.physicalSize = Size(width, 2000);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: EducationalResourcesScreen(service: svc, cards: _cards),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
    }
  });

  // RENDER PROOF FOR THE 2026-08-09 ADDITIONS. Every other test in this file
  // injects a fixture on purpose, so none of them would notice a real row that
  // parses but never reaches the screen. This one pumps the BUNDLED asset and
  // looks for the three new rows at mobile, tablet and desktop widths, because
  // "the parser accepted it" and "a user can see it" are different claims.
  testWidgets('the 2026-08-09 additions render from the bundled asset',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final EducationalResourcesService real =
        EducationalResourcesService.fromJson(
            File('assets/data/educational_resources.json').readAsStringSync());

    const List<String> titles = <String>[
      'Hamina Attenuation Object Library',
      'Hamina Attenuation Object Editor',
      'teigenRF Free Tools for Hamina and Ekahau',
      'Hamina Clipboard Tools (PotatoFi)',
    ];

    for (final double width in <double>[375, 768, 1280]) {
      tester.view.physicalSize = Size(width, 6000);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: EducationalResourcesScreen(service: real, cards: _cards),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');

      for (final String title in titles) {
        expect(find.text(title), findsWidgets,
            reason: '"$title" did not render at ${width}px');
      }

      // F1, Vera 2026-09-15. The fixture render test proves the WIDGET can show
      // a credit. It does not prove the SHIPPED credit reaches a user, and that
      // exact gap is this feature's own history: the line sat correct in the
      // data for three months while nothing rendered it. Vera reproduced it by
      // reverting one argument, and all four data/service guards still passed.
      // This is the assertion that goes red for that.
      expect(find.text('Inspired by wlan-talks.net by Victor Gatuna'),
          findsOneWidget,
          reason: 'the real credit from the real asset did not reach the real '
              'screen at ${width}px');
    }
  });

  testWidgets('search reaches the 2026-08-09 additions by name and by tag',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1.0;

    final EducationalResourcesService real =
        EducationalResourcesService.fromJson(
            File('assets/data/educational_resources.json').readAsStringSync());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: EducationalResourcesScreen(service: real, cards: _cards),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'attenuation object');
    await tester.pump();
    expect(find.text('Hamina Attenuation Object Library'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'clipboard');
    await tester.pump();
    expect(find.text('Hamina Clipboard Tools (PotatoFi)'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'teigenrf');
    await tester.pump();
    expect(find.text('teigenRF Free Tools for Hamina and Ekahau'), findsWidgets);

    // 'Hamina Attenuation Object Library' and 'Hamina Attenuation Object
    // Editor' share a 32-character prefix and both landed on 2026-08-09. A
    // search for the shared prefix must return BOTH, and find.text is exact, so
    // this also proves the two rows are distinct widgets rather than one row
    // matched twice.
    await tester.enterText(
        find.byType(TextField).first, 'hamina attenuation object');
    await tester.pump();
    expect(find.text('Hamina Attenuation Object Library'), findsWidgets);
    expect(find.text('Hamina Attenuation Object Editor'), findsWidgets);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // LIGHT THEME. Recorded as a gap on 2026-09-15 and fixed here.
  //
  // `_pump` hardcoded dark, so every assertion above this line had only ever
  // run against one of the two themes the app ships. Vera covered light once by
  // screenshot and measured the contrast by hand: 8.86:1 light and 12.63:1
  // dark. Both numbers are REPRODUCED below from the tokens themselves, which
  // is what makes them a guard rather than a note in a report.
  // ══════════════════════════════════════════════════════════════════════════
  group('light theme', () {
    testWidgets('the screen renders in light theme, not only dark',
        (tester) async {
      await _pump(tester, _svc(), theme: AppTheme.light());

      // The same assertions the dark tests make, against the other theme. The
      // point is not that light is special; it is that NOTHING pumped this
      // screen in light, so a light-only layout or colour failure could ship.
      expect(find.text(_kFixtureCredit), findsOneWidget);
      expect(find.text('Top 20 Wi-Fi Checklist'), findsWidgets);
    });

    testWidgets('search works in light theme too', (tester) async {
      // Searches the INJECTED fixture, so the title asserted here is one the
      // fixture defines. The dark sibling at 'search reaches the 2026-08-09
      // additions' builds a service from the real bundled JSON instead, which
      // is why it can look for a Hamina entry and this cannot.
      await _pump(tester, _svc(), theme: AppTheme.light());
      await tester.enterText(find.byType(TextField).first, 'alpha');
      await tester.pump();
      expect(find.text('Alpha Tool'), findsWidgets);
      expect(find.text('Beta Podcast'), findsNothing);
    });
  });

  group('contrast of the tokens this screen actually uses', () {
    // Every text token the screen paints, against every surface it paints them
    // on. Derived by counting the `colors.<token>` references in
    // educational_resources_screen.dart rather than guessed: textTertiary (12),
    // textAccent (7), textPrimary (6), textSecondary (4), on surface1 (5),
    // surface2 (2) and the surface0 canvas beneath them.
    //
    // SC 1.4.3 floor for body text is 4.5:1.
    const double kFloor = 4.5;

    List<(String, Color)> textTokens(AppColorScheme c) => <(String, Color)>[
          ('textPrimary', c.textPrimary),
          ('textSecondary', c.textSecondary),
          ('textTertiary', c.textTertiary),
          ('textAccent', c.textAccent),
        ];

    List<(String, Color)> surfaces(AppColorScheme c) => <(String, Color)>[
          ('surface0', c.surface0),
          ('surface1', c.surface1),
          ('surface2', c.surface2),
        ];

    for (final (String name, AppColorScheme scheme) in <(String, AppColorScheme)>[
      ('light', AppColorScheme.light()),
      ('dark', AppColorScheme.dark()),
    ]) {
      test('$name: every text token clears 4.5:1 on every surface', () {
        for (final (String tName, Color tColor) in textTokens(scheme)) {
          for (final (String sName, Color sColor) in surfaces(scheme)) {
            final double ratio = _contrast(tColor, sColor);
            expect(
              ratio,
              greaterThanOrEqualTo(kFloor),
              reason: '$name $tName on $sName is '
                  '${ratio.toStringAsFixed(2)}:1, below the $kFloor:1 floor',
            );
          }
        }
      });
    }

    test("Vera's two hand-measured numbers, reproduced from the tokens", () {
      // She measured the credit line, which paints in textSecondary, on a card,
      // which is surface1. Reproducing her exact figures is what proves this
      // guard measures the same thing her screenshot did.
      expect(
        _contrast(
          AppColorScheme.light().textSecondary,
          AppColorScheme.light().surface1,
        ),
        closeTo(8.86, 0.01),
      );
      expect(
        _contrast(
          AppColorScheme.dark().textSecondary,
          AppColorScheme.dark().surface1,
        ),
        closeTo(12.63, 0.01),
      );
    });

    test('the TIGHTEST pair is named, so a drift is visible before it fails',
        () {
      // Light textAccent on the light canvas is 4.60:1. It clears the floor by
      // 0.10, which is the smallest margin anywhere on this screen in either
      // theme, so it is the pair that breaks first if a token is nudged.
      // Asserting the VALUE rather than only the floor means a change that
      // still passes 4.5 does not pass silently.
      final AppColorScheme light = AppColorScheme.light();
      expect(
        _contrast(light.textAccent, light.surface0),
        closeTo(4.60, 0.01),
      );
    });
  });
}
