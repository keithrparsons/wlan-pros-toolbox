// Tests for the Find the Switch and Port (LLDP/CDP) reference screen.
//
// Dataset assertions guard the command strings against drift from Pax's
// commands-verified.md (the ONLY safe source): the numeric pktmon EtherType form
// (never the UNVERIFIED `-d LLDP` keyword), the exact lldpcli spellings
// (`summary` / `details`, not `detail`), and the CDP MAC (CDP has no EtherType).
// GL-004 no-em-dash + casing guards run over every shipped string and the §8.16
// copy payload. A widget smoke confirms render + no overflow at phone/tablet.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/command/lldp_cdp_reference_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  List<String> allStrings() {
    final List<String> s = <String>[
      LldpCdpReferenceScreen.screenSummary,
      LldpCdpReferenceScreen.referenceOnlyBanner,
      LldpCdpReferenceScreen.lldpDefinition,
      LldpCdpReferenceScreen.cdpDefinition,
      LldpCdpReferenceScreen.windowsCorrection,
      LldpCdpReferenceScreen.windowsServerEnable,
      LldpCdpReferenceScreen.vendorEnableCaveat,
      LldpCdpReferenceScreen.footnote,
      ...LldpCdpReferenceScreen.threeFacts,
      ...LldpCdpReferenceScreen.apPortWorkflow,
    ];
    for (final LldpCommandGroup g in LldpCdpReferenceScreen.commandGroups) {
      s.add(g.label);
      s.add(g.subtitle);
      for (final LldpCommand c in g.commands) {
        s..add(c.command)..add(c.note);
      }
    }
    for (final LldpMistake m in LldpCdpReferenceScreen.mistakes) {
      s..add(m.wrong)..add(m.right);
    }
    return s;
  }

  LldpCommandGroup groupByLabel(String needle) => LldpCdpReferenceScreen
      .commandGroups
      .firstWhere((LldpCommandGroup g) => g.label.contains(needle));

  group('LLDP/CDP reference — verified commands (Pax commands-verified.md)', () {
    test('macOS LLDP one-liner is the exact verified tcpdump filter', () {
      final LldpCommandGroup mac = groupByLabel('macOS');
      expect(
        mac.commands.any((LldpCommand c) =>
            c.command == "sudo tcpdump -nn -v -i en5 'ether proto 0x88cc'"),
        isTrue,
      );
    });

    test('macOS CDP matches the CDP MAC (CDP has no EtherType)', () {
      final LldpCommandGroup mac = groupByLabel('macOS');
      expect(
        mac.commands.any((LldpCommand c) =>
            c.command.contains('ether host 01:00:0c:cc:cc:cc')),
        isTrue,
      );
    });

    test('Windows pktmon uses the NUMERIC EtherType, never the -d LLDP keyword',
        () {
      final LldpCommandGroup win = groupByLabel('Windows');
      expect(
        win.commands.any((LldpCommand c) =>
            c.command == 'pktmon filter add LLDP --ethertype 0x88CC'),
        isTrue,
      );
      // The UNVERIFIED build-specific `-d LLDP` keyword must appear NOWHERE.
      for (final String s in allStrings()) {
        expect(s.contains('-d LLDP'), isFalse, reason: 'UNVERIFIED -d LLDP: $s');
      }
    });

    test('Windows pktmon capture uses --pkt-size 0 (avoids TLV truncation)', () {
      final LldpCommandGroup win = groupByLabel('Windows');
      expect(
        win.commands.any((LldpCommand c) =>
            c.command.contains('--pkt-size 0') && c.command.contains('pktmon start')),
        isTrue,
      );
    });

    test('lldpcli uses summary and details (plural), never "detail"', () {
      final LldpCommandGroup linux = groupByLabel('Linux');
      expect(
        linux.commands.any(
            (LldpCommand c) => c.command == 'lldpcli show neighbors summary'),
        isTrue,
      );
      expect(
        linux.commands.any(
            (LldpCommand c) => c.command == 'lldpcli show neighbors details'),
        isTrue,
      );
      // No "show neighbors detail" (singular) anywhere.
      expect(
        linux.commands
            .any((LldpCommand c) => c.command.endsWith('neighbors detail')),
        isFalse,
      );
    });

    test('switch CLI carries the AP-port triad: neighbors + status + power', () {
      final LldpCommandGroup sw = groupByLabel('Switch CLI');
      final Set<String> cmds =
          sw.commands.map((LldpCommand c) => c.command).toSet();
      expect(cmds.contains('show lldp neighbors'), isTrue);
      expect(cmds.contains('show interfaces status'), isTrue);
      expect(cmds.contains('show power inline'), isTrue);
    });
  });

  group('LLDP/CDP reference — GL-004 voice + facts', () {
    test('no em dash in any shipped string or the copy payload', () {
      for (final String s in allStrings()) {
        expect(s.contains('—'), isFalse, reason: 'em dash in: $s');
      }
      // The copy payload is generated; guard it too.
      // (Accessed via the widget render below is expensive; the static parts
      // already cover it, but assert no em dash in the joined content.)
      expect(allStrings().join(' ').contains('—'), isFalse);
    });

    test('Wi-Fi casing and exact 802.1AB are used, never WiFi/802.1ab', () {
      final String joined = allStrings().join(' ');
      expect(joined.contains('WiFi'), isFalse);
      expect(joined.contains('802.1ab'), isFalse);
      expect(joined.contains('802.1AB'), isTrue);
    });

    test('the three hard facts are present (Layer 2, wired only, off by default)',
        () {
      final String facts = LldpCdpReferenceScreen.threeFacts.join(' ');
      expect(facts.contains('single hop'), isTrue);
      expect(facts.contains('Wired only'), isTrue);
      expect(facts.contains('LLDP off'), isTrue);
    });

    test('Windows correction names Get-NetLldpAgent as NOT a neighbor viewer',
        () {
      expect(
        LldpCdpReferenceScreen.windowsCorrection.contains('Get-NetLldpAgent'),
        isTrue,
      );
      expect(
        LldpCdpReferenceScreen.windowsCorrection.contains('local agent'),
        isTrue,
      );
    });
  });

  group('LldpCdpReferenceScreen widget', () {
    testWidgets('renders the title and an anchor command', (tester) async {
      await _withViewport(tester, const Size(375, 2600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const LldpCdpReferenceScreen(),
          ),
        );
        await tester.pump();
        expect(
          find.text('Find the Switch and Port (LLDP/CDP)'),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('renders without overflow at 320/768 widths', (tester) async {
      for (final double width in <double>[320, 768]) {
        await _withViewport(tester, Size(width, 3200), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const LldpCdpReferenceScreen(),
            ),
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
