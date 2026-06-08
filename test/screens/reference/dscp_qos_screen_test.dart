// Tests for the DSCP / QoS Markings reference screen.
//
// The datasets are reproduced verbatim from the verified protocols dataset
// (Deliverables/2026-06-08-reference-batch/protocols-data.md, Page 4): the
// WMM AC <-> 802.11 UP <-> DSCP mapping per RFC 8325, and the DSCP class
// reference. These tests anchor the load-bearing facts — voice (EF) belongs in
// AC_VO via UP 6 per RFC 8325, EF = 46, the trap copy names the voice-into-video
// demotion — plus phone/tablet/desktop widget tests confirming the read-only
// screen renders without overflow and surfaces the warning callout.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/dscp_qos_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('WMM AC mapping — per RFC 8325', () {
    test('telephony/voice = UP 6, EF, AC_VO (RFC 8325 keeps voice in AC_VO)',
        () {
      final QosMapping voice = DscpQosScreen.mappings.firstWhere(
        (QosMapping m) => m.traffic == 'Telephony / voice',
      );
      expect(voice.accessCategory, 'AC_VO (Voice)');
      expect(voice.userPriority, '6');
      expect(voice.dscp.contains('EF'), isTrue);
      expect(voice.dscpDecimal.contains('46'), isTrue);
    });

    test('interactive/streaming video = UP 4, AF41/42/43, AC_VI', () {
      final QosMapping video = DscpQosScreen.mappings.firstWhere(
        (QosMapping m) => m.traffic == 'Interactive / streaming video',
      );
      expect(video.accessCategory, 'AC_VI (Video)');
      expect(video.userPriority, '4');
      expect(video.dscpDecimal, '34 / 36 / 38');
    });

    test('six mapping rows; no em dash in any field', () {
      expect(DscpQosScreen.mappings.length, 6);
      for (final QosMapping m in DscpQosScreen.mappings) {
        expect(m.traffic.contains('—'), isFalse, reason: 'no em dash');
        expect(m.dscp.contains('—'), isFalse, reason: 'no em dash');
      }
    });
  });

  group('DSCP class reference', () {
    DscpClass classFor(String name) => DscpQosScreen.dscpClasses
        .firstWhere((DscpClass c) => c.name == name);

    test('EF = 46, VA = 44', () {
      expect(classFor('EF').decimal, '46');
      expect(classFor('VA').decimal, '44');
    });

    test('DF (Default / CS0) = 0, CS7 = 56', () {
      expect(classFor('DF (Default / CS0)').decimal, '0');
      expect(classFor('CS7').decimal, '56');
    });
  });

  group('the voice-into-video trap is flagged', () {
    test('trap title names the demotion and trap body explains EF -> UP 5', () {
      expect(DscpQosScreen.trapTitle.toLowerCase().contains('voice'), isTrue);
      expect(DscpQosScreen.trapTitle.toLowerCase().contains('video'), isTrue);
      // The mechanism is spelled out: EF (46) top-three-bits land in AC_VI.
      expect(DscpQosScreen.trapBody.contains('EF is 46'), isTrue);
      expect(DscpQosScreen.trapBody.contains('AC_VI'), isTrue);
      expect(DscpQosScreen.trapBody.contains('RFC 8325'), isTrue);
    });
  });

  group('DscpQosScreen widget', () {
    testWidgets('renders title, both tables, and the trap callout (phone)',
        (tester) async {
      await _withViewport(tester, const Size(375, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DscpQosScreen(),
          ),
        );
        expect(find.text('DSCP / QoS Markings'), findsWidgets);
        expect(find.text('DSCP class reference'), findsOneWidget);
        expect(find.text(DscpQosScreen.trapTitle), findsOneWidget);
        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 2600), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const DscpQosScreen(),
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

/// Helper — run [body] with the test view sized to [size], then restore.
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
