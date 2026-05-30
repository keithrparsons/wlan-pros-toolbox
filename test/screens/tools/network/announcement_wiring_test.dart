// Screen-reader announcement wiring for two network tools, covering the WCAG
// 4.1.3 (Status Messages) gate findings Vera raised:
//
//   - F-01 (SubnetCalcScreen): the calculator live-recomputes on every keystroke
//     and swaps a results card / error card without moving focus. The
//     results/error subtree must be wrapped in Semantics(liveRegion: true) so the
//     framework announces (and debounces) the change.
//   - F-02 (PacketSenderScreen): synchronous validation failures (bad port, bad
//     hex payload) return before the async send announcement, so the inline
//     _inputError text must carry its own Semantics(liveRegion: true).
//
// These assert the live-region wiring structurally (the liveRegion flag is set
// on the right subtree) rather than pinning exact SR announcement strings, so
// they stay green if copy is reworded.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/packet_sender_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/subnet_calc_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// Matches a Semantics widget whose explicit properties set liveRegion = true.
Finder _liveRegions() => find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.liveRegion == true,
    );

void main() {
  group('SubnetCalcScreen — F-01 live region', () {
    testWidgets('valid recompute wraps the results card in a live region',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const SubnetCalcScreen(),
        ),
      );
      // The screen seeds 10.20.0.0/22 post-frame, so a valid result is present.
      await tester.pumpAndSettle();

      expect(find.text('Network'), findsOneWidget); // results card is showing
      expect(_liveRegions(), findsOneWidget);
    });

    testWidgets('invalid input swaps to an error card still in a live region',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const SubnetCalcScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Force an invalid prefix; the error card replaces the results card.
      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(1), '99');
      await tester.pumpAndSettle();

      expect(find.text('Check your input'), findsOneWidget);
      expect(_liveRegions(), findsOneWidget);
    });
  });

  group('PacketSenderScreen — F-02 validation live region', () {
    testWidgets('an out-of-range port surfaces the error in a live region',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const PacketSenderScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Before submit there is no _inputError, so no validation live region.
      expect(_liveRegions(), findsNothing);

      final Finder fields = find.byType(TextField);
      // Host enables the Send button; the bad port trips synchronous validation.
      await tester.enterText(fields.at(0), '192.168.1.1');
      await tester.enterText(fields.at(1), '70000');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pumpAndSettle();

      // The validation message renders and is announced via its live region.
      expect(
        find.textContaining('between 1 and 65535'),
        findsOneWidget,
      );
      expect(_liveRegions(), findsOneWidget);
    });
  });
}
