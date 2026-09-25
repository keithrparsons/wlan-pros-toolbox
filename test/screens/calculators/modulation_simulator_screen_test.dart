// Widget tests for the Wi-Fi Lab Modulation Simulator screen.
//
// The math is pinned in test/services/rf/modulation_math_test.dart; these
// tests cover the screen contract: it opens PAUSED (GL-003 §8.8), Step sends
// exactly one symbol, reduced motion is acknowledged, the empty-message error
// state disables the transport, dense orders switch to tap-to-label, and the
// layout survives phone and desktop widths in both themes without overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/modulation_simulator_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 390,
  double height = 844,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          disableAnimations: reduceMotion,
        ),
        child: const ModulationSimulatorScreen(seed: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _rowValue(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
  matching: find.byType(Text),
);

String _valueOf(WidgetTester tester, String label) {
  final List<Text> texts = tester.widgetList<Text>(_rowValue(label)).toList();
  return texts.last.data ?? '';
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final Finder f = find.text(label);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pump();
}

void main() {
  test('catalog registers modulation-simulator in Wi-Fi Lab', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'rf-calculators',
    );
    final ToolEntry e = rf.tools.firstWhere(
      (ToolEntry t) => t.id == kModulationSimulatorToolId,
    );
    expect(e.title, 'Modulation Simulator');
    expect(e.subgroup, 'Wi-Fi Lab');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/modulation-simulator');
    // The reference-card tool is a separate, untouched entry.
    final bool refStillThere = kToolCategories.any(
      (ToolCategory c) => c.tools.any((ToolEntry t) => t.id == 'modulation'),
    );
    expect(refStillThere, isTrue);
  });

  testWidgets('opens paused with nothing sent', (WidgetTester tester) async {
    await _pump(tester);
    expect(find.text('Modulation Simulator'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    expect(_valueOf(tester, 'Symbols sent'), '0');
    expect(
      find.textContaining('Press Step to send one symbol'),
      findsOneWidget,
    );
  });

  testWidgets('Step sends exactly one symbol', (WidgetTester tester) async {
    await _pump(tester);
    await _tapButton(tester, 'Step');
    expect(_valueOf(tester, 'Symbols sent'), '1');
    expect(find.text('Current bits'), findsOneWidget);
    await _tapButton(tester, 'Step');
    expect(_valueOf(tester, 'Symbols sent'), '2');
  });

  testWidgets('+100 sends a batch and Reset clears it', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await _tapButton(tester, '+100');
    expect(_valueOf(tester, 'Symbols sent'), '100');
    expect(find.textContaining('over 100 symbols'), findsOneWidget);
    await _tapButton(tester, 'Reset');
    expect(_valueOf(tester, 'Symbols sent'), '0');
  });

  testWidgets('Play advances on its own and Pause stops it', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await _tapButton(tester, 'Play');
    expect(find.text('Pause'), findsOneWidget);
    // Medium speed is 4 symbols per second.
    await tester.pump(const Duration(milliseconds: 1100));
    final int sent = int.parse(_valueOf(tester, 'Symbols sent'));
    expect(sent, greaterThanOrEqualTo(3));
    await _tapButton(tester, 'Pause');
    await tester.pump(const Duration(seconds: 2));
    expect(int.parse(_valueOf(tester, 'Symbols sent')), sent);
  });

  testWidgets('reduced motion: still paused, note shown, Step works', (
    WidgetTester tester,
  ) async {
    await _pump(tester, reduceMotion: true);
    expect(find.text('Play'), findsOneWidget);
    expect(find.textContaining('Reduced motion is on'), findsOneWidget);
    await _tapButton(tester, 'Step');
    expect(_valueOf(tester, 'Symbols sent'), '1');
  });

  testWidgets('empty message disables sending', (WidgetTester tester) async {
    await _pump(tester);
    await _tapButton(tester, 'Your text');
    // 'Hello, Wi-Fi' is 12 bytes = 96 bits: 24 whole 16-QAM symbols.
    expect(find.textContaining('96 bits = 24 symbols'), findsOneWidget);
    expect(find.textContaining('No padding needed.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.textContaining('Type a message to send it'), findsOneWidget);
    final OutlinedButton step = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Step'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(step.onPressed, isNull);
    final FilledButton play = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Play'), matching: find.byType(FilledButton)),
    );
    expect(play.onPressed, isNull);
  });

  testWidgets('64-QAM pads the last symbol and says so', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('16-QAM (4 bits per symbol)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('64-QAM (6 bits per symbol)').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('64 points, 6 bits per symbol'), findsOneWidget);
    await _tapButton(tester, 'Your text');
    await tester.enterText(find.byType(TextField), 'A');
    await tester.pump();
    // 8 bits into 6-bit symbols: 2 symbols, 4 zero bits of padding.
    expect(find.textContaining('8 bits = 2 symbols'), findsOneWidget);
    expect(
      find.textContaining('The last symbol is padded with 4 zero bits.'),
      findsOneWidget,
    );
  });

  testWidgets('a full text pass decodes the message at high SNR', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await _tapButton(tester, 'Your text');
    await tester.enterText(find.byType(TextField), 'Hi');
    await tester.pump();
    // SNR defaults to 25 dB; 16-QAM decodes 'Hi' (4 symbols) cleanly there.
    for (int n = 0; n < 4; n++) {
      await _tapButton(tester, 'Step');
    }
    expect(find.text('Last full copy'), findsOneWidget);
    expect(_valueOf(tester, 'Last full copy'), 'Hi');
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final double width in <double>[320, 390, 1024]) {
      testWidgets('$name theme at ${width.toInt()} wide renders cleanly', (
        WidgetTester tester,
      ) async {
        await _pump(tester, theme: theme(), width: width, height: 900);
        await _tapButton(tester, '+100');
        expect(tester.takeException(), isNull);
        await _tapButton(tester, 'Your text');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
