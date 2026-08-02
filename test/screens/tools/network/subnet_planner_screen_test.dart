// SubnetPlannerScreen — widget tests for the two-mode VLSM / summarize tile.
//
// The arithmetic is unit-tested in test/services/ip_block_math_test. This file
// asserts only what the SCREEN owes:
//
//   * it opens on a worked example rather than a blank panel, in Split mode;
//   * the mode toggle actually swaps the form AND the results;
//   * an allocation that cannot be met renders as a named "not allocated" card
//     with its reason, and never as a silent omission;
//   * the over-coverage number and the named gap blocks render in Summarize,
//     because that number is the reason the mode exists;
//   * a bad line renders with its line number while the good lines still
//     compute (per-line errors are not a whole-form error);
//   * a malformed parent block IS a whole-form error, and the Copy affordance
//     goes null so nothing wrong can be pasted into a change ticket;
//   * no overflow at phone, tablet and desktop widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/subnet_planner_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

Widget _host({Size size = const Size(390, 844)}) => MaterialApp(
  theme: AppTheme.dark(),
  home: MediaQuery(
    data: MediaQueryData(size: size),
    child: const SubnetPlannerScreen(),
  ),
);

/// The multi-line requirements box is the second TextField in Split mode.
Finder _field(int index) => find.byType(TextField).at(index);

String? _copyPayload(WidgetTester tester) =>
    tester.widget<AppCopyAction>(find.byType(AppCopyAction)).textBuilder();

void main() {
  testWidgets('opens in Split on a worked example, not a blank panel', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('10.20.0.0/22'), findsWidgets);
    // The four seeded VLANs, largest first.
    expect(find.text('Staff'), findsOneWidget);
    expect(find.text('10.20.0.0/23'), findsOneWidget);
    expect(find.text('10.20.2.0/24'), findsOneWidget);
    expect(find.text('10.20.3.0/25'), findsOneWidget);
    expect(find.text('10.20.3.128/30'), findsOneWidget);
    // And the leftover is named, not swallowed.
    expect(find.text('Still free'), findsOneWidget);
    expect(find.text('10.20.3.132/30'), findsOneWidget);
  });

  testWidgets('the 2-host line raises the RFC 3021 note', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.textContaining('RFC 3021'), findsOneWidget);
  });

  testWidgets('a requirement that does not fit is named, with its reason, and '
      'the rest still allocate', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(_field(0), '192.168.1.0/24');
    await tester.enterText(_field(1), 'Campus 500\nOffice 100');
    await tester.pumpAndSettle();

    expect(find.text('Campus: not allocated'), findsOneWidget);
    expect(find.textContaining('needs a /23'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget);
    expect(find.text('192.168.1.0/25'), findsOneWidget);
  });

  testWidgets('a bad requirement line is reported by line number and does not '
      'sink the good ones', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(_field(1), 'Staff 500\nnope\nGuest 200');
    await tester.pumpAndSettle();

    expect(find.text('Lines that were skipped'), findsOneWidget);
    expect(find.textContaining('Line 2, "nope"'), findsOneWidget);
    expect(find.text('Staff'), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);
  });

  testWidgets('a malformed parent block is a whole-form error and disables '
      'Copy', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(_field(0), '10.0.0.999/24');
    await tester.pumpAndSettle();

    expect(find.text('Check your input'), findsOneWidget);
    expect(find.text('Plan'), findsNothing);
    expect(_copyPayload(tester), isNull);
  });

  testWidgets('switching to Summarize swaps the form and the results', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Summarize'));
    await tester.pumpAndSettle();

    expect(find.text('Plan'), findsNothing);
    expect(find.text('Covering supernet'), findsOneWidget);
    // The four seeded /24s are contiguous, so they cover the /22 exactly.
    expect(find.text('10.0.0.0/22'), findsWidgets);
    expect(find.textContaining('fill this block exactly'), findsOneWidget);
  });

  testWidgets('Summarize names the over-coverage AND the gap blocks', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Summarize'));
    await tester.pumpAndSettle();

    await tester.enterText(_field(0), '10.0.0.0/24\n10.0.3.0/24');
    await tester.pumpAndSettle();

    expect(find.text('512'), findsWidgets); // covered, and extra
    expect(
      find.text('Inside the supernet, not in your list'),
      findsOneWidget,
    );
    expect(find.text('10.0.1.0/24'), findsOneWidget);
    expect(find.text('10.0.2.0/24'), findsOneWidget);
    expect(
      find.textContaining('addresses that are not in your list'),
      findsOneWidget,
    );
  });

  testWidgets('Summarize says out loud when it masked host bits off', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Summarize'));
    await tester.pumpAndSettle();

    await tester.enterText(_field(0), '10.0.0.37/24\n10.0.1.0/24');
    await tester.pumpAndSettle();

    expect(find.text('Read as their network address'), findsOneWidget);
    expect(find.textContaining('was read as 10.0.0.0/24'), findsOneWidget);
  });

  testWidgets('the Copy payload carries the plan, then the summary', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final String split = _copyPayload(tester)!;
    expect(split, contains('Subnet Planner: split 10.20.0.0/22'));
    expect(split, contains('Staff: 10.20.0.0/23'));
    expect(split, contains('510 usable, asked for 500'));
    expect(split, contains('Free blocks: 10.20.3.132/30'));

    await tester.tap(find.text('Summarize'));
    await tester.pumpAndSettle();
    final String sum = _copyPayload(tester)!;
    expect(sum, contains('Covering supernet: 10.0.0.0/22'));
    expect(sum, contains('Extra addresses the supernet would advertise: 0'));
  });

  testWidgets('no overflow at phone, tablet, or desktop width', (
    WidgetTester tester,
  ) async {
    for (final Size size in <Size>[
      const Size(320, 720),
      const Size(768, 1024),
      const Size(1280, 900),
    ]) {
      await tester.pumpWidget(_host(size: size));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });
}
