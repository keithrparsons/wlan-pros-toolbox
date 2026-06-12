// EmergencyPhrasesScreen smoke test.
//
// Covers (per SOP-007 §5 / the build brief's definition of done):
//  - renders the title, the draft-translation banner, and phrase rows;
//  - the language picker toggles one-language ↔ all-languages, and the target
//    select swaps the visible target column;
//  - search narrows in place across languages + the honest empty state;
//  - the AppBar copy action carries the draft caveat + a phrase;
//  - a per-phrase copy action copies just that phrase in the visible languages;
//  - light + dark themes both build (GL-003 §8.20).
//
// A small in-memory service is injected so the test never touches the bundled
// asset or the rootBundle, and so the data is deterministic.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/emergency_phrases_screen.dart';
import 'package:wlan_pros_toolbox/services/phrases/emergency_phrase_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

const String _fixture = '''
{
  "title": "Emergency Phrases",
  "translation_status": "draft-needs-review",
  "translation_note": "Draft machine translations, not yet reviewed.",
  "languages": [
    { "code": "en", "label": "English", "native": "English" },
    { "code": "es", "label": "Spanish", "native": "Español" },
    { "code": "fr", "label": "French", "native": "Français" },
    { "code": "it", "label": "Italian", "native": "Italiano" },
    { "code": "de", "label": "German", "native": "Deutsch" }
  ],
  "phrases": [
    { "id": "help", "category": "Medical & help", "en": "Help!", "es": "¡Ayuda!", "fr": "Au secours !", "it": "Aiuto!", "de": "Hilfe!" },
    { "id": "thanks", "category": "Basics & courtesy", "en": "Thank you.", "es": "Gracias.", "fr": "Merci.", "it": "Grazie.", "de": "Danke." },
    { "id": "toilet", "category": "Directions", "en": "Where is the toilet?", "es": "¿Dónde está el baño?", "fr": "Où sont les toilettes ?", "it": "Dov'è il bagno?", "de": "Wo ist die Toilette?" }
  ]
}
''';

EmergencyPhraseService _svc() => EmergencyPhraseService.fromJson(_fixture);

Widget _harness({ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: EmergencyPhrasesScreen(service: _svc()),
    );

void main() {
  // A tall surface so the whole list (banner + intro + picker + search + 3
  // rows) lays out without lazy-list culling — the per-row copy actions and
  // every phrase line are then all present without scrolling.
  Future<void> tallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  group('render', () {
    testWidgets('shows the title, draft banner, and phrases', (tester) async {
      await tallSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();

      expect(find.text('Emergency Phrases'), findsWidgets);
      // The draft-translation caveat is visibly on-screen, not just in data.
      expect(find.text('Draft translations. Review pending'), findsOneWidget);
      expect(find.textContaining('not yet reviewed'), findsOneWidget);

      // English source lines render for every phrase (default one-language mode
      // shows EN + Spanish).
      expect(find.text('Help!'), findsOneWidget);
      expect(find.text('Thank you.'), findsOneWidget);
      expect(find.text('¡Ayuda!'), findsOneWidget); // Spanish (default target)
      // German is NOT shown in one-language Spanish mode.
      expect(find.text('Hilfe!'), findsNothing);
    });
  });

  group('language picker', () {
    testWidgets('all-languages mode shows every target column', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      await tester.tap(find.text('All languages'));
      await tester.pump();

      // Now all four targets render for "Help!".
      expect(find.text('¡Ayuda!'), findsOneWidget);
      expect(find.text('Au secours !'), findsOneWidget);
      expect(find.text('Aiuto!'), findsOneWidget);
      expect(find.text('Hilfe!'), findsOneWidget);
    });

    testWidgets('switching the target swaps the shown column', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      // Default target is Spanish; German hidden.
      expect(find.text('Hilfe!'), findsNothing);

      // Open the target select and choose German.
      await tester.tap(find.text('Spanish (Español)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('German (Deutsch)').last);
      await tester.pumpAndSettle();

      expect(find.text('Hilfe!'), findsOneWidget); // German now shown
      expect(find.text('¡Ayuda!'), findsNothing); // Spanish gone
    });
  });

  group('search', () {
    testWidgets('narrows in place across languages', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      // Search in German even though Spanish is the shown column — search spans
      // all five languages.
      await tester.enterText(find.byType(TextField), 'Toilette');
      await tester.pump();
      expect(find.text('Where is the toilet?'), findsOneWidget);
      expect(find.text('Help!'), findsNothing);
    });

    testWidgets('no match shows the honest empty state', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'zzznotpresent');
      await tester.pump();
      expect(find.textContaining('No phrases match'), findsOneWidget);
      expect(find.text('Help!'), findsNothing);
    });
  });

  group('copy', () {
    testWidgets('AppBar copy carries the draft caveat and a phrase',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      // The AppBar action is the FIRST AppCopyAction (the per-row ones follow).
      final Finder appBarCopy = find.bySemanticsLabel('Copy all phrases');
      expect(appBarCopy, findsOneWidget);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      await tester.tap(appBarCopy);
      await tester.pump();

      expect(copied, isNotNull);
      expect(copied, contains('Emergency Phrases'));
      expect(copied, contains('DRAFT'));
      expect(copied, contains('Help!'));
      expect(copied, contains('¡Ayuda!'));

      await tester.pump(const Duration(milliseconds: 1600));
    });

    testWidgets('a per-phrase copy action is present on each row',
        (tester) async {
      await tallSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();

      // One AppBar copy + one per phrase row (3 phrases) = 4.
      expect(find.byType(AppCopyAction), findsNWidgets(4));
      expect(find.bySemanticsLabel('Copy this phrase'), findsNWidgets(3));
    });
  });

  group('themes', () {
    testWidgets('builds in dark theme', (tester) async {
      await tester.pumpWidget(_harness(theme: AppTheme.dark()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Emergency Phrases'), findsWidgets);
    });

    testWidgets('builds in light theme', (tester) async {
      await tester.pumpWidget(_harness(theme: AppTheme.light()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Draft translations. Review pending'), findsOneWidget);
    });
  });
}
