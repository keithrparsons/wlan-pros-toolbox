// Tests for the Credentials & Licenses reference screen, a Field & Trade
// Reference set entry (2026-07-05). Three layers: data fidelity (the
// six-credential lead-time table, the two GROL facts, the three FCC concepts,
// plus the no-em-dash / "Wi-Fi" guards), registration (a live "Codes & Safety"
// Quick Reference tile, route, keywords), and widget render (dark + light, no
// overflow at 320/375/768/1280, plate omitted when unbundled and shown once
// when bundled).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/credentials_licenses_data.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/credentials_licenses_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

List<String> _allProse() => <String>[
      kCredentialsLead,
      kFccConceptsIntro,
      ...kFccConcepts,
      kGrolFactsIntro,
      ...kGrolFacts,
      kGrolException,
      kCredentialsTableIntro,
      ...kCredentialNotes,
      ...kLeadTimeClusters,
      kCredentialsWlanCares,
      kCredentialsDeferNote,
      for (final CredentialRow c in kCredentials) ...<String>[
        c.credential,
        c.authority,
        c.gatesYou,
        c.leadTime,
        c.validity,
      ],
    ];

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('credentials table: exactly 6; TWIC and its validity anchored', () {
      expect(kCredentials.length, 6);
      final CredentialRow twic =
          kCredentials.firstWhere((CredentialRow c) => c.credential == 'TWIC');
      expect(twic.authority, 'TSA / USCG');
      expect(twic.validity, '5 years');
    });

    test('two GROL facts, and the Part 101 microwave exception', () {
      expect(kGrolFacts.length, 2);
      expect(kFccConcepts.length, 3);
      expect(kGrolFacts[1].contains('Part 101 Fixed Microwave Services'),
          isTrue);
      expect(kGrolFacts[1].contains('does not, by itself, require a GROL'),
          isTrue);
    });

    test('five per-credential notes and three lead-time clusters', () {
      expect(kCredentialNotes.length, 5);
      expect(kLeadTimeClusters.length, 3);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      for (final String s in _allProse()) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('WiFi'), isFalse, reason: 'must be "Wi-Fi" in "$s"');
      }
    });
  });

  group('registration (catalog + subgroup + router + keywords)', () {
    test('live Quick Reference tile in "Codes & Safety"', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final ToolEntry t = qr.tools.firstWhere(
        (ToolEntry e) => e.id == 'credentials-licenses',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/credentials-licenses');
      expect(t.title, 'Credentials & Licenses');
      expect(t.subgroup, 'Codes & Safety');
    });

    test('grouping places the tool under "Codes & Safety", not "Other"', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final List<ToolSection> sections = groupedCategoryTools(qr);
      for (final ToolSection s
          in sections.where((ToolSection s) => s.header == 'Other')) {
        expect(
          s.tools.any((ToolEntry e) => e.id == 'credentials-licenses'),
          isFalse,
          reason: 'credentials-licenses orphaned into Other',
        );
      }
      final ToolSection codes = sections.firstWhere(
        (ToolSection s) => s.header == 'Codes & Safety',
      );
      expect(
        codes.tools.any((ToolEntry e) => e.id == 'credentials-licenses'),
        isTrue,
      );
    });

    test('route resolves to a registered builder', () {
      expect(
        AppRouter.routes.containsKey('/tools/credentials-licenses'),
        isTrue,
      );
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('credentials-licenses'), isTrue);
      expect(kToolKeywords['credentials-licenses']!, isNotEmpty);
      expect(kToolKeywords['credentials-licenses']!.contains('twic'), isTrue);
    });
  });

  group('widget render (dark + light, no overflow)', () {
    setUp(() {
      ReferenceImages.debugSetBundled(const <String>{});
    });
    tearDown(ReferenceImages.debugReset);

    testWidgets('renders title + key content in dark + light, plate omitted',
        (tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
      ]) {
        await _withViewport(tester, const Size(375, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(theme: theme, home: const CredentialsLicensesScreen()),
          );
          await tester.pump();
          expect(find.text('Credentials & Licenses'), findsWidgets);
          expect(
            find.text('The credentials that gate the site'),
            findsOneWidget,
          );
          expect(find.text('Why a WLAN pro cares'), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(DarkRasterDiagramCard), findsNothing);
        });
      }
    });

    testWidgets('shows exactly one plate card when the PNG is bundled',
        (tester) async {
      ReferenceImages.debugSetBundled(<String>{
        ReferenceImages.pathFor('credentials-licenses'),
      });
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const CredentialsLicensesScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(DarkRasterDiagramCard), findsOneWidget);
      });
    });

    testWidgets('no overflow at 320/375/768/1280 widths', (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const CredentialsLicensesScreen(),
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow at ${width}px',
          );
        });
      }
    });
  });
}

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
