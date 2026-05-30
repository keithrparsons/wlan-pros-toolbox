// Unit + widget tests for RoamingScreen.
//
// The datasets are ported VERBATIM from the rf-tools-pwa `roaming` tool
// (ROAMING_PROTOCOLS / ROAMING_THRESHOLDS in www/app.js). These tests pin the
// load-bearing facts so a future edit that drifts from the PWA fails loudly:
//  - 802.11r is Fast BSS Transition (FT) — and is spelled "802.11r", not
//    "802.11R".
//  - the VoIP/standard roam-trigger RSSI design targets (−67 / −70 dBm).
//  - the §8.13 grade→status-color mapping.
// Plus one phone-viewport widget smoke test.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/reference/roaming_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/theme/app_tokens.dart';

void main() {
  group('RoamingScreen dataset (verbatim from rf-tools-pwa)', () {
    test('defines exactly the three PWA protocols: 802.11r, 802.11k, 802.11v',
        () {
      final List<String> protos =
          RoamingScreen.kProtocols.map((RoamingProtocol p) => p.proto).toList();
      expect(protos, <String>['802.11r', '802.11k', '802.11v']);
    });

    test('802.11r is Fast BSS Transition (FT), spelled lowercase r', () {
      final RoamingProtocol ft = RoamingScreen.kProtocols.firstWhere(
        (RoamingProtocol p) => p.proto == '802.11r',
      );
      expect(ft.name, 'Fast BSS Transition (FT)');
      // Guard the casing rule explicitly: never "802.11R".
      expect(ft.proto, '802.11r');
      expect(ft.proto.contains('R'), isFalse);
    });

    test('802.11k is the Neighbor Report; 802.11v is BSS Transition Management',
        () {
      final RoamingProtocol k = RoamingScreen.kProtocols.firstWhere(
        (RoamingProtocol p) => p.proto == '802.11k',
      );
      final RoamingProtocol v = RoamingScreen.kProtocols.firstWhere(
        (RoamingProtocol p) => p.proto == '802.11v',
      );
      expect(k.name, 'Neighbor Report');
      expect(v.name, 'BSS Transition Management');
    });

    test('roam-trigger RSSI design targets match the PWA thresholds', () {
      final RoamingThreshold voip = RoamingScreen.kThresholds.firstWhere(
        (RoamingThreshold r) => r.scenario == 'VoIP / UC design target',
      );
      final RoamingThreshold data = RoamingScreen.kThresholds.firstWhere(
        (RoamingThreshold r) => r.scenario == 'Standard data design target',
      );
      // VoIP target: ≥ −67 dBm / ≥ 25 dB / < 50 ms with 802.11r.
      expect(voip.minRssi, '≥ −67 dBm');
      expect(voip.minSnr, '≥ 25 dB');
      expect(voip.roamLatency, '< 50 ms (with 802.11r)');
      expect(voip.grade, RoamGrade.good);
      // Standard data target: ≥ −70 dBm / ≥ 20 dB / < 150 ms.
      expect(data.minRssi, '≥ −70 dBm');
      expect(data.minSnr, '≥ 20 dB');
    });

    test('sticky-client and unusable rows grade as bad', () {
      final RoamingThreshold sticky = RoamingScreen.kThresholds.firstWhere(
        (RoamingThreshold r) =>
            r.scenario == 'Sticky client trigger (typical)',
      );
      final RoamingThreshold unusable = RoamingScreen.kThresholds.firstWhere(
        (RoamingThreshold r) => r.scenario == 'Unusable - roam immediately',
      );
      expect(sticky.minRssi, '−75 to −80 dBm');
      expect(sticky.grade, RoamGrade.bad);
      expect(unusable.minRssi, '< −80 dBm');
      expect(unusable.grade, RoamGrade.bad);
    });

    test('grade maps to the §8.13 status palette', () {
      expect(RoamingScreen.gradeColor(RoamGrade.good), AppColors.statusSuccess);
      expect(
        RoamingScreen.gradeColor(RoamGrade.marginal),
        AppColors.statusWarning,
      );
      expect(RoamingScreen.gradeColor(RoamGrade.bad), AppColors.statusDanger);
    });
  });

  testWidgets(
    'RoamingScreen renders in a 375x900 phone viewport without overflow',
    (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        final List<Object> overflow = <Object>[];
        final FlutterExceptionHandler? previous = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          if (details.exception.toString().contains('overflowed')) {
            overflow.add(details.exception);
          }
        };
        addTearDown(() => FlutterError.onError = previous);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const RoamingScreen(),
          ),
        );
        await tester.pump();

        // Title and both section headings render.
        expect(find.text('Roaming Parameters'), findsOneWidget);
        expect(find.text('Protocols'), findsOneWidget);
        expect(find.text('Thresholds'), findsOneWidget);

        // The wide 5-column threshold table scrolls horizontally, so it must
        // not log a RenderFlex overflow at phone width.
        expect(
          overflow,
          isEmpty,
          reason: 'RoamingScreen must not overflow at 375x900 — '
              'got: ${overflow.map((Object e) => e.toString()).join("; ")}',
        );
      });
    },
  );

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    for (final double width in <double>[320, 375, 768, 1280]) {
      await _withViewport(tester, Size(width, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const RoamingScreen()),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      });
    }
  });
}

/// Run [body] with the test view sized to [size], then restore. Mirrors the
/// `_withViewport` helper in test/widget_test.dart.
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
