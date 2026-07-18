// Tests for the Network CLI Commands screen.
//
// Dataset assertions guard the command set against drift from the consolidated
// reference + Keith's decision (macOS shows ONLY `wdutil info`; `airport`
// removed). 3-column model (2026-06-12, Silas flag): each task carries a
// separate winCmd / macCmd / linCmd so a diverged macOS-vs-Linux command is
// never collapsed. A widget smoke confirms render + the live filter narrows
// results.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/command/cli_commands_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('CLI commands — dataset', () {
    CliCommand byWin(String win) => CliCommandsScreen.commands
        .firstWhere((CliCommand c) => c.winCmd == win);

    test('ping is ping/ping/ping across all three columns with flags', () {
      final CliCommand c = byWin('ping host');
      expect(c.macCmd, 'ping host');
      expect(c.linCmd, 'ping host');
      expect(c.options.any((o) => o.flag == '-t'), isTrue);
      expect(c.options.any((o) => o.flag == '-c count'), isTrue);
    });

    test('macOS Wi-Fi shows ONLY wdutil info, never airport (Keith #3)', () {
      final CliCommand c = byWin('netsh wlan show interfaces');
      expect(c.macCmd, 'wdutil info');
      // airport must not appear anywhere in the dataset (any column or flag).
      for (final CliCommand cmd in CliCommandsScreen.commands) {
        expect((cmd.winCmd ?? '').contains('airport'), isFalse);
        expect((cmd.macCmd ?? '').contains('airport'), isFalse);
        expect((cmd.linCmd ?? '').contains('airport'), isFalse);
        for (final CliOption o in cmd.options) {
          expect(o.flag.contains('airport'), isFalse);
          expect(o.meaning.contains('airport'), isFalse);
        }
      }
      for (final LinuxShellCommand cmd in CliCommandsScreen.linuxShell) {
        expect(cmd.command.contains('airport'), isFalse);
      }
    });

    test('macOS and Linux diverge on a real row (3-column split is load-bearing)',
        () {
      // netstat connections: macOS netstat -an vs Linux ss -tunap.
      final CliCommand c = byWin('netstat -ano');
      expect(c.macCmd, 'netstat -an');
      expect(c.linCmd, 'ss -tunap');
      expect(c.macCmd == c.linCmd, isFalse);
    });

    test('dig has no native Windows command (honest null)', () {
      final CliCommand dig = CliCommandsScreen.commands
          .firstWhere((CliCommand c) => c.macCmd == 'dig name');
      expect(dig.winCmd, isNull);
      expect(dig.linCmd, 'dig name');
    });

    test('nbtstat is Windows-only (honest nulls on macOS and Linux)', () {
      final CliCommand nb = CliCommandsScreen.commands
          .firstWhere((CliCommand c) => c.winCmd == 'nbtstat -A addr');
      expect(nb.macCmd, isNull);
      expect(nb.linCmd, isNull);
    });

    test('Linux shell essentials render as a Linux-only group', () {
      expect(CliCommandsScreen.linuxShell, isNotEmpty);
      expect(
        CliCommandsScreen.linuxShell.any((c) => c.command == 'tail -f file'),
        isTrue,
      );
    });

    test('capture/scan/throughput tools are present with example invocations',
        () {
      CliCommand toolByMac(String mac) => CliCommandsScreen.commands
          .firstWhere((CliCommand c) => c.macCmd == mac);

      // nmap: cross-platform, with two example invocations.
      final CliCommand nmap = toolByMac('nmap host');
      expect(nmap.winCmd, 'nmap host');
      expect(nmap.linCmd, 'nmap host');
      expect(
        nmap.options.any((o) => o.flag == 'nmap -sn 192.168.1.0/24'),
        isTrue,
      );
      expect(
        nmap.options.any((o) => o.flag == 'nmap -sV -p 1-1000 host'),
        isTrue,
      );

      // iperf3: server + client example invocations.
      final CliCommand iperf = toolByMac('iperf3 -c host');
      expect(iperf.options.any((o) => o.flag == 'iperf3 -s'), isTrue);
      expect(
        iperf.options.any((o) => o.flag == 'iperf3 -c host -u -b 100M'),
        isTrue,
      );

      // tcpdump: honest null on Windows (no native tcpdump).
      final CliCommand tcpdump = toolByMac('sudo tcpdump -i en0');
      expect(tcpdump.winCmd, isNull);
      expect(tcpdump.linCmd, 'sudo tcpdump -i wlan0');
      expect(
        tcpdump.options.any((o) => o.flag == 'sudo tcpdump -i en0 -n port 53'),
        isTrue,
      );

      // tshark: cross-platform CLI Wireshark.
      final CliCommand tshark = toolByMac('tshark -i en0');
      expect(tshark.winCmd, 'tshark -i 1');
      expect(
        tshark.options.any((o) => o.flag == 'tshark -r cap.pcap -Y "http.request"'),
        isTrue,
      );
    });

    test('no em dash anywhere', () {
      for (final CliCommand c in CliCommandsScreen.commands) {
        expect(c.description.contains('—'), isFalse);
      }
      for (final LinuxShellCommand c in CliCommandsScreen.linuxShell) {
        expect(c.note.contains('—'), isFalse);
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
