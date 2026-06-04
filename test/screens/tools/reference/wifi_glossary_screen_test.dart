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
  "terms": [
    {
      "id": "ssid", "term": "SSID", "abbr": "Service Set Identifier",
      "category": "Access Points, Networks & Roaming",
      "definition": "The human-readable name of a Wi-Fi network."
    },
    {
      "id": "ofdma", "term": "OFDMA", "abbr": "Orthogonal Frequency Division Multiple Access",
      "category": "Speed, Modulation & Capacity",
      "definition": "Lets one transmission serve several devices at once."
    },
    {
      "id": "cci", "term": "Co-Channel Interference", "abbr": "CCI",
      "category": "Bands & Spectrum",
      "definition": "Access points sharing a channel take turns."
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

    // Category section headers present.
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
