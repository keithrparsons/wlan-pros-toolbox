// Tests for the 802.11 Frame Exchange reference screen.
//
//  1. Dataset assertions — the ported FX_SCENARIOS dataset matches the
//     rf-tools-pwa source: scenario keys/labels, and a known scenario's full
//     step sequence (numbers, directions, labels, types) is reproduced exactly.
//  2. Widget smoke in a phone viewport — the screen mounts, renders the default
//     scenario's heading and first frame, and the scenario selector is present.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/reference/frame_exchange_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('FrameExchangeScreen dataset (verbatim from rf-tools-pwa)', () {
    test('exposes the scenarios in tab order (4 PWA + OWE + Passpoint)', () {
      final List<String> keys = FrameExchangeScreen.scenarios
          .map((FxScenario s) => s.key)
          .toList();
      // The four ported PWA scenarios plus the two air-distinct adds (OWE,
      // Passpoint). eduroam / OpenRoaming are NOT separate scenarios — they are
      // backend federations that run an existing air exchange (asserted below).
      expect(keys, <String>[
        'open',
        'wpa3',
        'owe',
        'passpoint',
        'dot1x',
        'ft',
      ]);

      final List<String> labels = FrameExchangeScreen.scenarios
          .map((FxScenario s) => s.tabLabel)
          .toList();
      expect(labels, <String>[
        'Open / WPA2-PSK',
        'WPA3-SAE',
        'OWE / Enhanced Open',
        'Passpoint / Hotspot 2.0',
        'WPA2-Enterprise',
        '802.11r Roam',
      ]);
    });

    test('OWE carries the DH public keys in the Association frames', () {
      final FxScenario owe = FrameExchangeScreen.scenarios
          .firstWhere((FxScenario s) => s.key == 'owe');
      final List<FxFrame> frames =
          owe.phases.expand((FxPhase p) => p.frames).toList();

      // The two Association frames each carry the Diffie-Hellman Parameter
      // element — the technical crux of OWE.
      final List<FxFrame> assoc = frames
          .where((FxFrame f) => f.label.contains('Association'))
          .toList();
      expect(assoc.length, 2);
      expect(assoc[0].dir, 'STA → AP');
      expect(assoc[0].label, contains('DH Parameter element'));
      expect(assoc[1].dir, 'AP → STA');
      expect(assoc[1].label, contains('DH Parameter element'));
      // Ends in a standard 4-Way Handshake (EAPOL keys) using the OWE PMK.
      expect(frames.last.label, contains('Msg 4/4'));
      expect(frames.last.type, FxType.eap);
    });

    test('Passpoint shows the pre-association GAS/ANQP query', () {
      final FxScenario pp = FrameExchangeScreen.scenarios
          .firstWhere((FxScenario s) => s.key == 'passpoint');
      final List<FxFrame> frames =
          pp.phases.expand((FxPhase p) => p.frames).toList();

      // The distinct over-the-air part is GAS Initial Request/Response, sent
      // pre-association as Public Action management frames.
      expect(
        frames.any((FxFrame f) =>
            f.label.contains('GAS Initial Request') &&
            f.type == FxType.mgmt),
        isTrue,
      );
      // OpenRoaming is covered as a NOTE on the Passpoint EAP frame, not a
      // separate scenario.
      expect(
        frames.any((FxFrame f) =>
            f.note.toLowerCase().contains('openroaming')),
        isTrue,
      );
    });

    test('eduroam is a backend note on 802.1X, not its own scenario', () {
      // No scenario keyed 'eduroam'.
      expect(
        FrameExchangeScreen.scenarios.any((FxScenario s) => s.key == 'eduroam'),
        isFalse,
      );
      final FxScenario d = FrameExchangeScreen.scenarios
          .firstWhere((FxScenario s) => s.key == 'dot1x');
      final List<FxFrame> frames =
          d.phases.expand((FxPhase p) => p.frames).toList();
      expect(
        frames.any((FxFrame f) => f.note.toLowerCase().contains('eduroam')),
        isTrue,
      );
    });

    test('FT carries the over-the-DS Action-frame variant as a note', () {
      final FxScenario ft = FrameExchangeScreen.scenarios
          .firstWhere((FxScenario s) => s.key == 'ft');
      final List<FxFrame> frames =
          ft.phases.expand((FxPhase p) => p.frames).toList();
      expect(
        frames.any((FxFrame f) =>
            f.note.toLowerCase().contains('over-the-ds') &&
            f.note.contains('Action frames')),
        isTrue,
      );
    });

    test('open scenario reproduces the PWA step sequence exactly', () {
      final FxScenario open = FrameExchangeScreen.scenarios
          .firstWhere((FxScenario s) => s.key == 'open');

      expect(open.title, 'Open Network / WPA2-Personal Association');

      // Phase names, verbatim.
      expect(
        open.phases.map((FxPhase p) => p.name).toList(),
        <String>[
          '802.11 Probe & Auth',
          'Association',
          '4-Way Handshake (WPA2-PSK only — skip for Open networks)',
          'DHCP (via AP Relay)',
        ],
      );

      // Flatten the frames and assert the full numbered sequence.
      final List<FxFrame> frames =
          open.phases.expand((FxPhase p) => p.frames).toList();

      expect(frames.length, 15);
      expect(
        frames.map((FxFrame f) => f.n).toList(),
        List<int>.generate(15, (int i) => i + 1),
      );

      // Spot-check the (number, direction, label, type) tuples at the phase
      // boundaries — these are the load-bearing facts ported from FX_SCENARIOS.
      // Beacon comes FROM the AP (truth-audit fix 2026-06-02; the row's own
      // note says "AP broadcasts").
      expect(frames[0].dir, 'AP → STA');
      expect(frames[0].label, 'Beacon Frame');
      expect(frames[0].type, FxType.mgmt);

      expect(frames[7].n, 8);
      expect(frames[7].dir, 'AP → STA');
      expect(frames[7].label, 'EAPOL Key (Msg 1/4)');
      expect(frames[7].type, FxType.eap);

      expect(frames[11].n, 12);
      expect(frames[11].label, 'DHCP Discover');
      expect(frames[11].type, FxType.dhcp);

      expect(frames.last.n, 15);
      expect(frames.last.label, 'DHCP Ack');
      expect(frames.last.dir, 'AP → STA');
    });

    test('dot1x scenario carries the RADIUS (wired) frames', () {
      final FxScenario d = FrameExchangeScreen.scenarios
          .firstWhere((FxScenario s) => s.key == 'dot1x');
      final List<FxFrame> frames =
          d.phases.expand((FxPhase p) => p.frames).toList();

      expect(frames.length, 16);

      final List<FxFrame> wired =
          frames.where((FxFrame f) => f.type == FxType.wired).toList();
      expect(
        wired.map((FxFrame f) => f.label).toList(),
        <String>[
          'RADIUS Access-Request',
          'RADIUS Access-Challenge',
          'RADIUS Access-Accept',
        ],
      );
    });
  });

  testWidgets('renders default scenario in a 375x900 phone viewport', (
    tester,
  ) async {
    await _withViewport(tester, const Size(375, 900), () async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const FrameExchangeScreen(),
        ),
      );
      await tester.pump();

      // App-bar title (renamed to 'Association Sequence' 2026-06-12; id/route
      // stay 'frame-exchange'). JD's deep external Frame Exchange Reference now
      // lives in Educational Resources; our in-app tool is the quick reference.
      expect(find.text('Association Sequence'), findsOneWidget);
      // Default scenario heading + first frame label.
      expect(
        find.text('Open Network / WPA2-Personal Association'),
        findsOneWidget,
      );
      expect(find.text('Beacon Frame'), findsOneWidget);
      // Scenario selector is present (the default tab label).
      expect(find.text('Open / WPA2-PSK'), findsWidgets);
    });
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    for (final double width in <double>[320, 375, 768, 1280]) {
      await _withViewport(tester, Size(width, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const FrameExchangeScreen()),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      });
    }
  });
}

/// Local viewport helper — mirrors `_withViewport` in test/widget_test.dart.
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
