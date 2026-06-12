// Morse Code screen widget smoke tests.
//
// Audio playback (just_audio) has no headless backend, so these cover the UI
// contract: the screen renders, the two fields convert live, the direction
// toggle swaps the result back into the input, the empty-state copy shows, and
// the prosign reference expands. Tapping Play is not asserted (it reaches the
// audio plugin).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/morse_code_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.dark(), home: const MorseCodeScreen()),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders the title, both direction buttons, and empty state',
      (tester) async {
    await _pump(tester);
    expect(find.text('Morse Code'), findsOneWidget);
    expect(find.text('Text → Morse'), findsOneWidget);
    expect(find.text('Morse → Text'), findsOneWidget);
    // Empty state: result card prompts the user to type.
    expect(find.text('Type text above to see its Morse code.'), findsOneWidget);
  });

  testWidgets('typing text shows its live Morse encoding', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'SOS');
    await tester.pump();
    expect(find.text('... --- ...'), findsOneWidget);
  });

  testWidgets('Morse → Text direction decodes a pasted code', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Morse → Text'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '... --- ...');
    await tester.pump();
    // The decoded text appears as a SelectableText result.
    expect(find.text('SOS'), findsOneWidget);
  });

  testWidgets('switching direction swaps the prior result into the input',
      (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'SOS');
    await tester.pump();
    expect(find.text('... --- ...'), findsOneWidget);

    // Swap to Morse → Text: the encoded Morse becomes the new input, and it
    // decodes back to SOS.
    await tester.tap(find.text('Morse → Text'));
    await tester.pump();
    final TextField field = tester.widget(find.byType(TextField));
    expect(field.controller!.text, '... --- ...');
    expect(find.text('SOS'), findsOneWidget);
  });

  testWidgets('prosign reference expands to list SOS', (tester) async {
    await _pump(tester);
    expect(find.text('<SOS>'), findsNothing);
    await tester.tap(find.text('Prosigns (procedural signals)'));
    await tester.pumpAndSettle();
    expect(find.text('<SOS>'), findsOneWidget);
    expect(find.text('...---...'), findsOneWidget);
  });
}
