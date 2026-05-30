// Tests for the WPA Security reference screen.
//
// Two layers:
//   1. Data assertions over the public-static datasets — guard the verbatim
//      PWA facts (counts, key security claims) against silent drift.
//   2. One widget smoke in a phone viewport — the screen pumps and renders its
//      mode/feature content without overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wpa_security_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('WPA modes dataset', () {
    test('ports all seven modes in PWA order', () {
      expect(WpaSecurityScreen.modes.length, 7);
      expect(
        WpaSecurityScreen.modes.map((WpaMode m) => m.mode).toList(),
        <String>[
          'WEP',
          'WPA (WPA1)',
          'WPA2-Personal',
          'WPA3-Personal',
          'Enhanced Open',
          'WPA2-Enterprise',
          'WPA3-Enterprise',
        ],
      );
    });

    test('WPA3-Personal uses SAE with PMF required', () {
      final WpaMode m = WpaSecurityScreen.modes.firstWhere(
        (WpaMode e) => e.mode == 'WPA3-Personal',
      );
      expect(m.keyMethod, 'SAE');
      expect(m.pmf, 'Req');
      expect(m.encryption, 'AES-CCMP (128-bit)');
      expect(m.status, 'Recommended');
    });

    test('WPA3-Enterprise uses GCMP-256 (192-bit) with PMF required', () {
      final WpaMode m = WpaSecurityScreen.modes.firstWhere(
        (WpaMode e) => e.mode == 'WPA3-Enterprise',
      );
      expect(m.encryption, 'GCMP-256 (192-bit)');
      expect(m.keyMethod, '802.1X + EAP');
      expect(m.pmf, 'Req');
    });

    test('WEP is RC4 (broken) and flagged do-not-deploy', () {
      final WpaMode m =
          WpaSecurityScreen.modes.firstWhere((WpaMode e) => e.mode == 'WEP');
      expect(m.encryption, 'RC4 (broken)');
      expect(m.pmf, 'No');
      expect(m.status, 'Do not deploy');
    });

    test('Enhanced Open uses OWE with no authentication', () {
      final WpaMode m = WpaSecurityScreen.modes.firstWhere(
        (WpaMode e) => e.mode == 'Enhanced Open',
      );
      expect(m.encryption, 'OWE (AES-CCMP)');
      expect(m.keyMethod, 'None (auto)');
      expect(m.pmf, 'Req');
    });
  });

  group('WPA features dataset', () {
    test('ports all seven features in PWA order', () {
      expect(WpaSecurityScreen.features.length, 7);
      expect(
        WpaSecurityScreen.features.first.feature,
        'SAE (Simultaneous Authentication of Equals)',
      );
    });

    test('WPA3 is mandatory on 6 GHz', () {
      final WpaFeature f = WpaSecurityScreen.features.firstWhere(
        (WpaFeature e) => e.feature == 'WPA3 mandatory on 6 GHz',
      );
      expect(f.appliesTo, 'All Wi-Fi 6E / Wi-Fi 7');
      expect(f.description, contains('6 GHz band requires WPA3 or OWE'));
    });

    test('PMF applies optional to WPA2, required to WPA3', () {
      final WpaFeature f = WpaSecurityScreen.features.firstWhere(
        (WpaFeature e) => e.feature.startsWith('PMF'),
      );
      expect(f.appliesTo, 'Optional: WPA2 · Required: WPA3');
    });
  });

  testWidgets('renders modes and features in a phone viewport', (tester) async {
    await _withViewport(tester, const Size(375, 900), () async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const WpaSecurityScreen(),
        ),
      );
      await tester.pump();

      // Screen title and both section headers present.
      expect(find.text('WPA Security'), findsOneWidget);
      expect(find.text('Security modes'), findsOneWidget);
      expect(find.text('Advanced features'), findsOneWidget);

      // "WPA3-Personal" legitimately renders more than once: as a mode row in
      // the Security modes table and as the SAE feature's "applies to" value.
      // "Recommended" is the verdict on TWO mode rows (WPA3-Personal and
      // WPA3-Enterprise), so it occurs exactly twice. Assert both as
      // multi-occurrence proofs that the modes section rendered its rows.
      expect(find.text('WPA3-Personal'), findsWidgets);
      expect(find.text('Recommended'), findsNWidgets(2));
      // "Enhanced Open" the mode name occurs once (the OWE feature's
      // "Enhanced Open only" is a distinct string), anchoring an Open-row.
      expect(find.text('Enhanced Open'), findsOneWidget);
      // Genuinely unique strings prove the features section rendered: the full
      // SAE feature name (the "SAE" key-method cell is a different string).
      expect(
        find.text('SAE (Simultaneous Authentication of Equals)'),
        findsOneWidget,
      );
      expect(find.text('OWE — Opportunistic Wireless Encryption'), findsOneWidget);
    });
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    // F-04 regression: WPA Security must not RenderFlex-overflow at any common
    // breakpoint width: 320 (small phone, Vera's named gate width), 375
    // (phone), 768 (tablet), 1280 (desktop). Tall height so vertical scroll
    // content never false-triggers; width is what drives horizontal overflow.
    for (final double width in <double>[320, 375, 768, 1280]) {
      await _withViewport(tester, Size(width, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const WpaSecurityScreen()),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      });
    }
  });
}

/// Run [body] with the test view sized to [size], then restore — mirrors the
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
