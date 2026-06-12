// DTMF Generator widget tests — focus on the BF6-1 sequence mode UI.
//
// Audio playback (just_audio) has no headless test backend, so these tests cover
// the UI contract: the sequence field renders, the Play button enables only when
// the field holds at least one valid DTMF character, and the parsed count is
// shown. Tapping Play is not asserted (it would reach the audio plugin).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dtmf_generator_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.dark(), home: const DtmfGeneratorScreen()),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders the sequence card with its label and field',
      (tester) async {
    await _pump(tester);
    expect(find.text('Play a sequence'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    // With no digits typed, the button reads the generic label.
    expect(find.text('Play sequence'), findsOneWidget);
  });

  testWidgets('typing digits shows the parsed count on the Play button',
      (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '8675309');
    await tester.pump();
    // 7 valid DTMF characters → "Play sequence (7)".
    expect(find.text('Play sequence (7)'), findsOneWidget);
  });

  testWidgets('non-DTMF characters in a pasted number are not counted',
      (tester) async {
    await _pump(tester);
    // Spaces/dashes are filtered by the input formatter; only digits count.
    await tester.enterText(find.byType(TextField), '1-800-555');
    await tester.pump();
    // 7 digits remain after the formatter strips the dashes.
    expect(find.text('Play sequence (7)'), findsOneWidget);
  });

  testWidgets('defaults to DTMF mode (sequence card present, no history note)',
      (tester) async {
    await _pump(tester);
    expect(find.text('DTMF'), findsOneWidget);
    expect(find.text('Play a sequence'), findsOneWidget);
    expect(find.text('Telephone signaling history'), findsNothing);
  });

  testWidgets('Blue Box mode shows the honesty note and the MF pad',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Blue Box'));
    await tester.pumpAndSettle();
    // The honest "does nothing on a modern network" note is on screen.
    expect(find.text('Telephone signaling history'), findsOneWidget);
    expect(
      find.textContaining('do nothing on any modern phone network'),
      findsOneWidget,
    );
    // KP / ST / 2600 signals render as pad keys.
    expect(find.text('KP'), findsOneWidget);
    expect(find.text('ST'), findsOneWidget);
    expect(find.text('2600'), findsOneWidget);
    // The DTMF-only sequence card is gone in this mode.
    expect(find.text('Play a sequence'), findsNothing);
  });

  testWidgets('Red Box mode shows the three coin keys and the honesty note',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Red Box'));
    await tester.pumpAndSettle();
    expect(find.text('Telephone signaling history'), findsOneWidget);
    expect(find.text('Nickel'), findsOneWidget);
    expect(find.text('Dime'), findsOneWidget);
    expect(find.text('Quarter'), findsOneWidget);
  });

  testWidgets('no "phreaking" or "hacking" wording appears in any mode',
      (tester) async {
    await _pump(tester);
    for (final String mode in <String>['Blue Box', 'Red Box', 'DTMF']) {
      await tester.tap(find.text(mode));
      await tester.pumpAndSettle();
      expect(find.textContaining('phreak', skipOffstage: false), findsNothing);
      expect(find.textContaining('hack', skipOffstage: false), findsNothing);
    }
  });
}
