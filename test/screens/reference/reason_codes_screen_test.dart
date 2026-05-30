// Tests for the 802.11 Reason & Status Codes reference screen.
//
// Two layers:
//   1. Data assertions against the public static dataset — guards that the
//      codes match the RF Tools PWA RC_DATA / RC_GROUPS / SC_DATA verbatim.
//      Known anchors: RC 1 = Unspecified reason, RC 7 = Class 3 frame from
//      non-assoc STA, RC 15 = 4-Way Handshake timeout, SC 0 = Successful.
//   2. One widget test in a phone viewport — pumps the screen, confirms it
//      renders a known code and meaning, and confirms the filter narrows the
//      list (and reaches the empty state on a no-match query).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/reason_codes_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// Flatten the reason-code groups into one lookup by code. Status codes are
/// asserted directly off statusGroup since their numbers overlap RC numbers.
Map<int, String> _reasonByCode() {
  final Map<int, String> m = <int, String>{};
  for (final CodeGroup g in ReasonCodesScreen.reasonGroups) {
    for (final CodeEntry e in g.entries) {
      m[e.code] = e.meaning;
    }
  }
  return m;
}

void main() {
  group('Reason code dataset', () {
    test('RC 1 is "Unspecified reason"', () {
      expect(_reasonByCode()[1], 'Unspecified reason');
    });

    test('RC 7 is the Class 3 non-assoc frame code', () {
      expect(_reasonByCode()[7], 'Class 3 frame received from non-assoc STA');
    });

    test('RC 15 is the 4-Way Handshake timeout', () {
      expect(_reasonByCode()[15], '4-Way Handshake timeout');
    });

    test('RC 23 is the 802.1X authentication failure', () {
      expect(_reasonByCode()[23], '802.1X authentication failed');
    });

    test('handshake-failure group holds exactly 15, 16, 23', () {
      final CodeGroup g = ReasonCodesScreen.reasonGroups.firstWhere(
        (CodeGroup g) => g.label == 'Security — handshake failures',
      );
      expect(g.entries.map((CodeEntry e) => e.code).toList(), <int>[15, 16, 23]);
    });

    test('reason groups mirror the six PWA RC_GROUPS labels in order', () {
      expect(
        ReasonCodesScreen.reasonGroups.map((CodeGroup g) => g.label).toList(),
        <String>[
          'Common (seen in most captures)',
          'Capability / Channel mismatch',
          'Security — frame / element errors',
          'Security — handshake failures',
          'QoS / load management',
          'Fast Roaming (802.11r)',
        ],
      );
    });
  });

  group('Association status dataset', () {
    test('SC 0 is "Successful"', () {
      final CodeEntry zero = ReasonCodesScreen.statusGroup.entries.firstWhere(
        (CodeEntry e) => e.code == 0,
      );
      expect(zero.meaning, 'Successful');
    });

    test('SC 104 is the HE-features code', () {
      final CodeEntry he = ReasonCodesScreen.statusGroup.entries.firstWhere(
        (CodeEntry e) => e.code == 104,
      );
      expect(he.meaning, 'Requesting STA does not support HE features');
    });
  });

  testWidgets('renders codes and filters in a phone viewport', (tester) async {
    await _withViewport(tester, const Size(375, 900), () async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const ReasonCodesScreen(),
        ),
      );
      await tester.pump();

      // Title + a known code/meaning render on first paint.
      expect(find.text('Reason & Status Codes'), findsOneWidget);
      expect(find.text('4-Way Handshake timeout'), findsOneWidget);

      // Filter to "handshake" — the two handshake-timeout meanings survive,
      // an unrelated code drops out.
      await tester.enterText(find.byType(TextField), 'handshake');
      await tester.pump();
      expect(find.text('4-Way Handshake timeout'), findsOneWidget);
      expect(find.text('Group Key Handshake timeout'), findsOneWidget);
      expect(find.text('Unspecified reason'), findsNothing);

      // A query that matches nothing reaches the honest empty state.
      await tester.enterText(find.byType(TextField), 'zzzznope');
      await tester.pump();
      expect(find.text('No match'), findsOneWidget);
    });
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    for (final double width in <double>[320, 375, 768, 1280]) {
      await _withViewport(tester, Size(width, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const ReasonCodesScreen()),
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
