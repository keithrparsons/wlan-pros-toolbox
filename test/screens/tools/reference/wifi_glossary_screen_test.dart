// WifiGlossaryScreen widget tests — the glossary groups by category, renders
// term rows (term + definition), exposes a search field, filters live on typing,
// and lays out without RenderFlex overflow at 320/375/768/1280 widths. A
// pre-built service is injected so the tests do not depend on the bundled asset
// load (WifiGlossaryScreen.service hook).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_glossary_screen.dart';
import 'package:wlan_pros_toolbox/services/glossary/glossary_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _fixture = '''
{
  "schema_version": 1,
  "title": "Wi-Fi Glossary",
  "source": "test fixture",
  "term_count": 3,
  "languages": ["en", "es", "fr", "it", "de"],
  "translation_status": "draft-needs-review",
  "terms": [
    {
      "id": "ssid", "term": "SSID", "abbr": "Service Set Identifier",
      "category": "Access Points, Networks & Roaming",
      "definition": "The human-readable name of a Wi-Fi network.",
      "definitions": {
        "es": "El nombre legible de una red Wi-Fi.",
        "fr": "Le nom lisible d'un réseau Wi-Fi.",
        "it": "Il nome leggibile di una rete Wi-Fi.",
        "de": "Der lesbare Name eines WLAN-Netzwerks."
      },
      "translation_status": "draft-needs-review"
    },
    {
      "id": "ofdma", "term": "OFDMA", "abbr": "Orthogonal Frequency Division Multiple Access",
      "category": "Speed, Modulation & Capacity",
      "definition": "Lets one transmission serve several devices at once.",
      "definitions": {
        "es": "Permite que una transmisión atienda a varios dispositivos a la vez.",
        "fr": "Permet à une transmission de servir plusieurs appareils à la fois.",
        "it": "Consente a una trasmissione di servire più dispositivi alla volta.",
        "de": "Lässt eine Übertragung mehrere Geräte gleichzeitig bedienen."
      },
      "translation_status": "draft-needs-review"
    },
    {
      "id": "cci", "term": "Co-Channel Interference", "abbr": "CCI",
      "category": "Bands & Spectrum",
      "definition": "Access points sharing a channel take turns.",
      "definitions": {
        "es": "Los puntos de acceso que comparten canal se turnan.",
        "fr": "Les points d'accès partageant un canal se relaient.",
        "it": "Gli access point che condividono un canale si alternano.",
        "de": "Access Points, die sich einen Kanal teilen, wechseln sich ab."
      },
      "translation_status": "draft-needs-review"
    }
  ]
}
''';

GlossaryService _svc() => GlossaryService.fromJson(_fixture);

Widget _harness(GlossaryService svc) => MaterialApp(
      theme: AppTheme.dark(),
      home: WifiGlossaryScreen(service: svc),
    );

void main() {
  testWidgets('mounts, renders a known term and the search field', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_svc()));
    await tester.pump();

    // A known term and its definition render.
    expect(find.text('OFDMA'), findsOneWidget);
    expect(find.text('SSID'), findsOneWidget);
    expect(
      find.text('The human-readable name of a Wi-Fi network.'),
      findsOneWidget,
    );

    // Category section headers present. The CCI group sits below the fold in
    // the default test viewport now that the language picker occupies space at
    // the top, so scroll it into view before asserting (ListView builds lazily).
    await tester.scrollUntilVisible(
      find.text('Bands & Spectrum'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Bands & Spectrum'), findsOneWidget);

    // The search field is present.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('typing a query filters the list', (tester) async {
    await tester.pumpWidget(_harness(_svc()));
    await tester.pump();

    // Before filtering, all three terms are present.
    expect(find.text('OFDMA'), findsOneWidget);
    expect(find.text('SSID'), findsOneWidget);

    // Filter to OFDMA. The query string itself also lives in the search field's
    // EditableText, so assert on each row's unique DEFINITION text (which never
    // appears in the field) rather than the term word.
    await tester.enterText(find.byType(TextField), 'OFDMA');
    await tester.pump();

    expect(
      find.text('Lets one transmission serve several devices at once.'),
      findsOneWidget,
    );
    expect(
      find.text('The human-readable name of a Wi-Fi network.'),
      findsNothing,
    );
    expect(find.text('Co-Channel Interference'), findsNothing);
  });

  testWidgets('a no-match query shows the honest empty state', (tester) async {
    await tester.pumpWidget(_harness(_svc()));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'zzznotapresentword');
    await tester.pump();

    expect(find.textContaining('No terms match'), findsOneWidget);
    expect(find.text('OFDMA'), findsNothing);
  });

  testWidgets('defaults to English: shows English definition and no beta note', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_svc()));
    await tester.pump();

    // English definition renders by default.
    expect(
      find.text('The human-readable name of a Wi-Fi network.'),
      findsOneWidget,
    );
    // The Spanish draft is NOT shown until the language switches.
    expect(find.text('El nombre legible de una red Wi-Fi.'), findsNothing);
    // No beta note while English is active.
    expect(find.textContaining('translations are in beta'), findsNothing);
    // The picker shows English as its current value.
    expect(find.text('English'), findsWidgets);
  });

  testWidgets(
    'switching to Spanish swaps definitions and reveals the beta draft note',
    (tester) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();

      // Open the language picker (AppSelect) and choose Español.
      await tester.tap(find.text('English').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Español').last);
      await tester.pumpAndSettle();

      // Definitions now render in Spanish; the English versions are gone.
      expect(find.text('El nombre legible de una red Wi-Fi.'), findsOneWidget);
      expect(
        find.text('The human-readable name of a Wi-Fi network.'),
        findsNothing,
      );

      // The honest draft-review flag is visible.
      expect(
        find.textContaining('translations are in beta'),
        findsOneWidget,
      );
      expect(find.textContaining('pending professional review'), findsOneWidget);

      // The term itself stays English even in Spanish mode.
      expect(find.text('SSID'), findsOneWidget);
    },
  );

  testWidgets('search filters the active-language definitions', (tester) async {
    await tester.pumpWidget(_harness(_svc()));
    await tester.pump();

    // Switch to Spanish.
    await tester.tap(find.text('English').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Español').last);
    await tester.pumpAndSettle();

    // A Spanish word present only in the OFDMA Spanish definition filters to it.
    await tester.enterText(find.byType(TextField), 'atienda');
    await tester.pump();

    expect(
      find.text(
        'Permite que una transmisión atienda a varios dispositivos a la vez.',
      ),
      findsOneWidget,
    );
    expect(find.text('El nombre legible de una red Wi-Fi.'), findsNothing);
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
}
