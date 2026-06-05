// Wi-Fi Authentication Glossary wiring + screen tests. The Authentication
// Glossary reuses WifiGlossaryScreen (parameterized by assetPath + title) and
// the shared GlossaryService, so these tests guard (a) the catalog/route wiring
// for the new `wifi-auth-glossary` id and (b) that the parameterized screen
// renders the auth title, groups, rows, search, and the honest empty state.
// A pre-built service is injected so the tests do not depend on the bundled
// asset load.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_glossary_screen.dart';
import 'package:wlan_pros_toolbox/services/glossary/glossary_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _fixture = '''
{
  "schema_version": 1,
  "title": "Wi-Fi Authentication Glossary",
  "source": "test fixture",
  "term_count": 3,
  "terms": [
    {
      "id": "radius", "term": "Remote Authentication Dial In User Service",
      "abbr": "RADIUS", "category": "Core Authentication",
      "definition": "Carries AAA messages to the authentication server."
    },
    {
      "id": "eap", "term": "Extensible Authentication Protocol",
      "abbr": "EAP", "category": "EAP & Key Exchange",
      "definition": "An authentication framework, not a single method."
    },
    {
      "id": "anqp", "term": "Access Network Query Protocol",
      "abbr": "ANQP", "category": "Roaming & Passpoint",
      "definition": "A client queries an access point before associating."
    }
  ]
}
''';

GlossaryService _svc() => GlossaryService.fromJson(_fixture);

Widget _harness(GlossaryService svc) => MaterialApp(
      theme: AppTheme.dark(),
      home: WifiGlossaryScreen(
        service: svc,
        assetPath: kWifiAuthGlossaryAsset,
        title: 'Wi-Fi Authentication Glossary',
      ),
    );

ToolEntry _authEntry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'wifi-auth-glossary');

void main() {
  group('catalog + route wiring', () {
    test('the tool id resolves to a live ToolEntry in Quick Reference', () {
      final ToolEntry entry = _authEntry();
      expect(entry.title, 'Wi-Fi Authentication Glossary');
      expect(entry.routeName, '/tools/wifi-auth-glossary');
      expect(entry.isLive, isTrue);
      expect(entry.subgroup, 'Wi-Fi & RF');

      // It lives in the same category as the Wi-Fi Glossary (Quick Reference).
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'wifi-auth-glossary'),
      );
      expect(
        cat.tools.any((ToolEntry t) => t.id == 'wifi-glossary'),
        isTrue,
        reason: 'auth glossary sits beside the wifi glossary',
      );
    });

    test('the route is registered and distinct from the wifi-glossary route',
        () {
      expect(AppRouter.routes.containsKey(AppRouter.wifiAuthGlossary), isTrue);
      expect(AppRouter.wifiAuthGlossary, '/tools/wifi-auth-glossary');
      expect(AppRouter.wifiAuthGlossary, isNot(AppRouter.wifiGlossary));
    });

    test('the bundled asset constant points at the sibling JSON', () {
      expect(kWifiAuthGlossaryAsset, 'assets/data/wifi_auth_glossary.json');
      expect(kWifiAuthGlossaryAsset, isNot(kWifiGlossaryAsset));
    });
  });

  group('screen', () {
    testWidgets('renders the auth title, a known term, and the search field', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();

      // AppBar carries the auth title.
      expect(find.text('Wi-Fi Authentication Glossary'), findsOneWidget);

      // A known term and its definition render.
      expect(
        find.text('Extensible Authentication Protocol'),
        findsOneWidget,
      );
      expect(
        find.text('An authentication framework, not a single method.'),
        findsOneWidget,
      );

      // Category section headers present.
      expect(find.text('Core Authentication'), findsOneWidget);
      expect(find.text('Roaming & Passpoint'), findsOneWidget);

      // The search field is present.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('typing a query filters the list', (tester) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'ANQP');
      await tester.pump();

      // Assert on each row's unique DEFINITION text (which never appears in the
      // search field) rather than the term/abbr word.
      expect(
        find.text('A client queries an access point before associating.'),
        findsOneWidget,
      );
      expect(
        find.text('Carries AAA messages to the authentication server.'),
        findsNothing,
      );
    });

    testWidgets('a no-match query shows the honest empty state', (tester) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'zzznotapresentword');
      await tester.pump();

      expect(find.textContaining('No terms match'), findsOneWidget);
      expect(find.text('Access Network Query Protocol'), findsNothing);
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths', (
      tester,
    ) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final GlossaryService svc = _svc();
      for (final double width in <double>[320, 375, 768, 1280]) {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(_harness(svc));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      }
    });
  });
}
