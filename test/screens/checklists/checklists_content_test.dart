// Tests for the two real checklist content consts (data/checklists.dart),
// rendered by the already-gated ChecklistScreen type.
//
// Guards Keith's decisions: the AP-install "After Installing" list is a clean
// 1-12 (13 + 1 + 11 = 25 total items across 3 phases), "Install Access Point"
// is its own one-item phase, and the client-test list is a single flat 12-item
// phase. Plus a widget smoke per checklist via the real ChecklistScreen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/checklists.dart';
import 'package:wlan_pros_toolbox/screens/tools/checklists/checklist_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('How to NOT Have a Wireless Problem (checklist-ap-install)', () {
    test('three phases in card order', () {
      expect(
        kApInstallChecklist.phases.map((p) => p.label).toList(),
        <String?>[
          'Before Installing Access Point',
          'Install Access Point',
          'After Installing Access Point',
        ],
      );
    });

    test('phase item counts: 13 + 1 + 11 = 25 total', () {
      expect(kApInstallChecklist.phases[0].items.length, 13);
      expect(kApInstallChecklist.phases[1].items.length, 1); // own phase
      expect(kApInstallChecklist.phases[2].items.length, 11); // clean 1-12 -> 11
      expect(kApInstallChecklist.totalItems, 25);
    });

    test('typos fixed: Confirm DNS reachable, reachable spelling', () {
      final List<String> after =
          kApInstallChecklist.phases[2].items.map((i) => i.text).toList();
      final List<String> before =
          kApInstallChecklist.phases[0].items.map((i) => i.text).toList();
      expect(before.contains('Confirm DNS reachable'), isTrue);
      expect(before.contains('Confirm target IP addresses reachable'), isTrue);
      // No "Cornfirm" / "Reachhable" survives.
      for (final String t in <String>[...before, ...after]) {
        expect(t.contains('Cornfirm'), isFalse);
        expect(t.contains('Reachhable'), isFalse);
      }
    });

    test('802.3 casing, no em dash', () {
      for (final ChecklistPhase p in kApInstallChecklist.phases) {
        for (final ChecklistItem i in p.items) {
          expect(i.text.contains('—'), isFalse);
        }
      }
      expect(
        kApInstallChecklist.phases[0].items.any((i) => i.text.contains('802.3')),
        isTrue,
      );
    });
  });

  group('Wi-Fi Client Testing Checklist (checklist-client-test)', () {
    test('single flat 12-item phase (no heading)', () {
      expect(kClientTestChecklist.phases.length, 1);
      expect(kClientTestChecklist.phases.single.label, isNull);
      expect(kClientTestChecklist.totalItems, 12);
    });

    test('first and last steps verbatim', () {
      final List<String> items =
          kClientTestChecklist.phases.single.items.map((i) => i.text).toList();
      expect(items.first, 'Can see all SSIDs being broadcast');
      expect(items.last, 'Complete network speed test');
      // Typos fixed: Associate (not Associatte), client (not Cilent).
      expect(items.contains('Associate to target SSID'), isTrue);
      expect(items.contains('Check client Tx data rate'), isTrue);
    });
  });

  group('Checklist screens render', () {
    testWidgets('AP-install checklist renders title, phases, progress',
        (tester) async {
      await _withViewport(tester, const Size(375, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const ChecklistScreen(
              checklist: kApInstallChecklist,
              toolId: 'checklist-ap-install',
            ),
          ),
        );
        expect(find.text('How to NOT Have a Wireless Problem'), findsWidgets);
        expect(find.text('Before Installing Access Point'), findsOneWidget);
        expect(find.text('0 / 25 done'), findsOneWidget);
      });
    });

    testWidgets('client-test checklist renders a flat 12-item list',
        (tester) async {
      await _withViewport(tester, const Size(375, 2000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const ChecklistScreen(
              checklist: kClientTestChecklist,
              toolId: 'checklist-client-test',
            ),
          ),
        );
        expect(find.text('Wi-Fi Client Testing Checklist'), findsWidgets);
        expect(find.text('0 / 12 done'), findsOneWidget);
        expect(find.text('Associate to target SSID'), findsOneWidget);
      });
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
