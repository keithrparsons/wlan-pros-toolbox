// Tests for the Linux / WLAN Commands screen.
//
// Dataset assertions guard the grouped command set against drift from the Pax
// research deliverable (incl. the airmon-ng check kill + access_bpf additions).
// A widget smoke confirms render + the group-aware live filter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/command/linux_wlan_commands_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Linux / WLAN commands — dataset', () {
    List<String> groupLabels() =>
        LinuxWlanCommandsScreen.groups.map((g) => g.label).toList();

    bool hasCommand(String cmd) => LinuxWlanCommandsScreen.groups.any(
        (g) => g.commands.any((c) => c.command == cmd));

    test('seven groups in the expected order', () {
      expect(groupLabels(), <String>[
        'File',
        'Directory',
        'Process',
        'Network',
        'Wireless',
        'Monitor-mode',
        'macOS capture',
      ]);
    });

    test('modern iproute2 tools present in Network group', () {
      expect(hasCommand('ip addr'), isTrue);
      expect(hasCommand('ip route'), isTrue);
      expect(hasCommand('ip neigh'), isTrue);
      expect(hasCommand('ss -tulpn'), isTrue);
    });

    test('airmon-ng check kill present (Pax addition)', () {
      expect(hasCommand('sudo airmon-ng check kill'), isTrue);
    });

    test('macOS access_bpf capture setup present', () {
      expect(
        hasCommand('sudo dseditgroup -o edit -a USERNAME -t user access_bpf'),
        isTrue,
      );
      expect(hasCommand('sudo wdutil info'), isTrue);
    });

    test('HT40+ and HT40- channel-set sequences present', () {
      expect(hasCommand('sudo iw dev wlan0 set channel 36 HT40+'), isTrue);
      expect(hasCommand('sudo iw dev wlan0 set channel 40 HT40-'), isTrue);
    });
  });

  group('LinuxWlanCommandsScreen widget', () {
    testWidgets('renders title and group headings', (tester) async {
      await _withViewport(tester, const Size(375, 2000), () async {
        await tester.pumpWidget(
          MaterialApp(
              theme: AppTheme.dark(),
              home: const LinuxWlanCommandsScreen()),
        );
        expect(find.text('Linux / WLAN Commands'), findsWidgets);
        expect(find.text('Wireless'), findsOneWidget);
        expect(find.text('Monitor-mode'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
      });
    });

    testWidgets('filtering by a group label keeps the whole group',
        (tester) async {
      await _withViewport(tester, const Size(375, 2000), () async {
        await tester.pumpWidget(
          MaterialApp(
              theme: AppTheme.dark(),
              home: const LinuxWlanCommandsScreen()),
        );
        await tester.enterText(find.byType(TextField), 'monitor');
        await tester.pump();
        expect(find.text('Monitor-mode'), findsOneWidget);
        // A monitor-mode command that doesn't itself contain "monitor".
        expect(find.text('lsusb'), findsOneWidget);
        // A File-group command should be gone.
        expect(find.text('ls -la'), findsNothing);
      });
    });

    testWidgets('no-match query shows the empty card', (tester) async {
      await _withViewport(tester, const Size(375, 2000), () async {
        await tester.pumpWidget(
          MaterialApp(
              theme: AppTheme.dark(),
              home: const LinuxWlanCommandsScreen()),
        );
        await tester.enterText(find.byType(TextField), 'zzzzzz');
        await tester.pump();
        expect(find.text('No match'), findsOneWidget);
      });
    });

    testWidgets('renders without overflow at 320/768 widths', (tester) async {
      for (final double width in <double>[320, 768]) {
        await _withViewport(tester, Size(width, 2400), () async {
          await tester.pumpWidget(
            MaterialApp(
                theme: AppTheme.dark(),
                home: const LinuxWlanCommandsScreen()),
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
