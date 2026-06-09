// Tests for the country-search feature on the International Power Plugs page.
//
// Two layers:
//   1. Data + search (GL-005): searchCountryPlugs resolves a country name (and
//      its common aliases: USA/US/United States, UK/United Kingdom/Britain,
//      Holland/Netherlands, UAE/Emirates) to the right plug type letters and
//      voltage/Hz, lists ALL letters for a multi-type country, and returns an
//      empty list for a no-match query. GL-004 voice (no em dash) is guarded.
//   2. Widget render: the search field sits at the top of the page; typing a
//      country shows its match with the type letters and voltage/Hz; a no-match
//      query shows an honest empty state; and the page renders with no
//      RenderFlex overflow at 320 and 768.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/country_plug_data.dart';
import 'package:wlan_pros_toolbox/data/international_plugs_diagrams.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/international_plugs_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('searchCountryPlugs — name + alias resolution', () {
    CountryPlug only(String query) {
      final List<CountryPlug> r = searchCountryPlugs(query);
      expect(r, isNotEmpty, reason: 'expected a match for "$query"');
      return r.first;
    }

    test('"Germany" returns Type C and F', () {
      final CountryPlug g = only('Germany');
      expect(g.country, 'Germany');
      expect(g.types, containsAll(<String>['C', 'F']));
      expect(g.types, <String>['C', 'F']);
      expect(g.powerLabel, '230V/50Hz');
      expect(g.typeLabel, 'Type C, F');
    });

    test('partial "germ" still finds Germany', () {
      expect(only('germ').country, 'Germany');
    });

    test('USA / US / United States all resolve to the United States (A, B)', () {
      for (final String q in <String>['USA', 'US', 'United States', 'America']) {
        final CountryPlug u = only(q);
        expect(u.country, 'United States', reason: 'query "$q"');
        expect(u.types, <String>['A', 'B']);
        expect(u.powerLabel, '120V/60Hz');
      }
    });

    test('UK / United Kingdom / Britain all resolve to the United Kingdom (G)',
        () {
      for (final String q in <String>['UK', 'United Kingdom', 'Britain']) {
        final CountryPlug u = only(q);
        expect(u.country, 'United Kingdom', reason: 'query "$q"');
        expect(u.types, <String>['G']);
        expect(u.powerLabel, '230V/50Hz');
      }
    });

    test('Holland resolves to the Netherlands (C, F)', () {
      final CountryPlug n = only('Holland');
      expect(n.country, 'Netherlands');
      expect(n.types, <String>['C', 'F']);
    });

    test('UAE / Emirates resolve to the United Arab Emirates (G)', () {
      for (final String q in <String>['UAE', 'Emirates']) {
        final CountryPlug u = only(q);
        expect(u.country, 'United Arab Emirates', reason: 'query "$q"');
        expect(u.types, <String>['G']);
      }
    });

    test('a multi-type country lists ALL its letters', () {
      // India is C, D, M; Italy is C, F, L; Maldives is D, G, J, K, L.
      expect(only('India').types, <String>['C', 'D', 'M']);
      expect(only('Italy').types, <String>['C', 'F', 'L']);
      expect(only('Maldives').types, <String>['D', 'G', 'J', 'K', 'L']);
    });

    test('search is case-insensitive', () {
      expect(only('GERMANY').country, 'Germany');
      expect(only('germany').country, 'Germany');
      expect(only('uSa').country, 'United States');
    });

    test('an exact country name ranks ahead of incidental substring matches',
        () {
      // "us" is a substring of Belarus, Cyprus, Mauritius, etc., but the US
      // alias is an EXACT match and must sort first.
      expect(searchCountryPlugs('us').first.country, 'United States');
    });

    test('a no-match query returns an empty list', () {
      expect(searchCountryPlugs('Atlantis'), isEmpty);
      expect(searchCountryPlugs('zzzz'), isEmpty);
    });

    test('an empty or whitespace query returns an empty list', () {
      expect(searchCountryPlugs(''), isEmpty);
      expect(searchCountryPlugs('   '), isEmpty);
    });

    test('the dataset carries roughly the full ~205-country roster', () {
      expect(kCountryPlugs.length, greaterThan(195));
      // Every entry has at least one type letter and non-empty power labels.
      for (final CountryPlug c in kCountryPlugs) {
        expect(c.types, isNotEmpty, reason: c.country);
        expect(c.voltage, isNotEmpty, reason: c.country);
        expect(c.frequency, isNotEmpty, reason: c.country);
      }
    });

    test('no em dash anywhere in the country data (GL-004)', () {
      for (final CountryPlug c in kCountryPlugs) {
        for (final String s in <String>[
          c.country,
          c.voltage,
          c.frequency,
          ...c.aliases,
        ]) {
          expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        }
      }
    });
  });

  group('InternationalPlugsScreen country search widget', () {
    setUp(() {
      // No face SVG bundled → each face card renders no graphic; the page must
      // still ship fully working.
      InternationalPlugsDiagrams.debugSetBundled(const <String>{});
    });
    tearDown(() {
      InternationalPlugsDiagrams.debugReset();
    });

    testWidgets('search field sits at the top and shows an idle prompt',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const InternationalPlugsScreen(),
          ),
        );
        await tester.pump();

        // The search field is present (the page is no longer input-free).
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Search by country'), findsOneWidget);
        // The idle prompt invites a lookup before anything is typed.
        expect(find.text('Look up a country'), findsOneWidget);
      });
    });

    testWidgets('typing "Germany" shows Type C, F and 230V/50Hz',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const InternationalPlugsScreen(),
          ),
        );
        await tester.pump();

        // Type a partial query so the field text ("germ") differs from the
        // result label ("Germany"), keeping the finders unambiguous (the
        // EditableText inside the field also carries the typed string).
        await tester.enterText(find.byType(TextField), 'germ');
        await tester.pump();

        expect(find.text('Germany'), findsOneWidget);
        expect(find.text('Type C, F'), findsOneWidget);
        expect(find.text('230V/50Hz'), findsOneWidget);
        // The idle prompt is gone once a query matches.
        expect(find.text('Look up a country'), findsNothing);
      });
    });

    testWidgets('a multi-type country shows all its letters (Italy → C, F, L)',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const InternationalPlugsScreen(),
          ),
        );
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'ital');
        await tester.pump();

        expect(find.text('Italy'), findsOneWidget);
        expect(find.text('Type C, F, L'), findsOneWidget);
      });
    });

    testWidgets('an alias query (Holland) resolves to the Netherlands',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const InternationalPlugsScreen(),
          ),
        );
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'Holland');
        await tester.pump();

        expect(find.text('Netherlands'), findsOneWidget);
        expect(find.text('Type C, F'), findsWidgets);
      });
    });

    testWidgets('a no-match query shows an honest empty state',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const InternationalPlugsScreen(),
          ),
        );
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'zzland');
        await tester.pump();

        expect(find.text('No match'), findsOneWidget);
        // The honest empty-state copy renders (not a fabricated country row).
        expect(find.textContaining('No country matches'), findsOneWidget);
        // The idle prompt is gone, replaced by the empty state.
        expect(find.text('Look up a country'), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320 and 768, query typed',
        (WidgetTester tester) async {
      for (final double width in <double>[320, 768]) {
        await _withViewport(tester, Size(width, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const InternationalPlugsScreen(),
            ),
          );
          await tester.pump();
          // Type a long multi-type country so the mono line is at its widest.
          await tester.enterText(find.byType(TextField), 'United Arab Emirates');
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
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
