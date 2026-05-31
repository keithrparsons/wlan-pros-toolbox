// Tests for the Network CLI Commands screen.
//
// Dataset assertions guard the command set against drift from the Pax research
// deliverable + Keith's decision (macOS shows ONLY `wdutil info`; `airport`
// removed). A widget smoke confirms render + the live filter narrows results.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/command/cli_commands_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('CLI commands — dataset', () {
    CliCommand byWin(String win) => CliCommandsScreen.commands
        .firstWhere((CliCommand c) => c.winCmd == win);

    test('ping pairs ping/ping with flags', () {
      final CliCommand c = byWin('ping host');
      expect(c.nixCmd, 'ping host');
      expect(c.options.any((o) => o.flag == '-t'), isTrue);
      expect(c.options.any((o) => o.flag == '-c count'), isTrue);
    });

    test('macOS Wi-Fi shows ONLY wdutil info, never airport (Keith #3)', () {
      final CliCommand c = byWin('netsh wlan show interfaces');
      expect(c.nixCmd, 'wdutil info');
      // airport must not appear anywhere in the dataset.
      for (final CliCommand cmd in CliCommandsScreen.commands) {
        expect((cmd.nixCmd ?? '').contains('airport'), isFalse);
        expect((cmd.winCmd ?? '').contains('airport'), isFalse);
        for (final CliOption o in cmd.options) {
          expect(o.flag.contains('airport'), isFalse);
          expect(o.meaning.contains('airport'), isFalse);
        }
      }
    });

    test('dig has no native Windows command (honest null)', () {
      final CliCommand dig = CliCommandsScreen.commands
          .firstWhere((CliCommand c) => c.nixCmd == 'dig name');
      expect(dig.winCmd, isNull);
    });

    test('nbtstat has no native nix command (honest null)', () {
      final CliCommand nb = CliCommandsScreen.commands
          .firstWhere((CliCommand c) => c.winCmd == 'nbtstat -A addr');
      expect(nb.nixCmd, isNull);
    });

    test('no em dash anywhere', () {
      for (final CliCommand c in CliCommandsScreen.commands) {
        expect(c.description.contains('—'), isFalse);
      }
    });
  });

  group('CliCommandsScreen widget', () {
    testWidgets('renders title and an anchor command', (tester) async {
      await _withViewport(tester, const Size(375, 1400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const CliCommandsScreen()),
        );
        expect(find.text('Network CLI Commands'), findsWidgets);
        expect(find.text('wdutil info'), findsWidgets);
        expect(find.byType(TextField), findsOneWidget); // the filter
      });
    });

    testWidgets('filter narrows to matching commands', (tester) async {
      await _withViewport(tester, const Size(375, 1400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const CliCommandsScreen()),
        );
        await tester.enterText(find.byType(TextField), 'nbtstat');
        await tester.pump();
        expect(find.text('nbtstat -A addr'), findsOneWidget);
        expect(find.text('ping host'), findsNothing);
      });
    });

    testWidgets('no-match query shows the empty card', (tester) async {
      await _withViewport(tester, const Size(375, 1400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const CliCommandsScreen()),
        );
        await tester.enterText(find.byType(TextField), 'zzzzzz');
        await tester.pump();
        expect(find.text('No match'), findsOneWidget);
      });
    });

    testWidgets('renders without overflow at 320/768 widths', (tester) async {
      for (final double width in <double>[320, 768]) {
        await _withViewport(tester, Size(width, 1600), () async {
          await tester.pumpWidget(
            MaterialApp(
                theme: AppTheme.dark(), home: const CliCommandsScreen()),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
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
