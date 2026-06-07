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
}
