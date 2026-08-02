// TransferTimeScreen — widget tests.
//
// The arithmetic is unit-tested in test/services/transfer_math_test. This file
// asserts what the SCREEN owes, and most of it is about the bits-versus-bytes
// trap the tool exists to close:
//
//   * the bits-and-bytes rule is ON the form, not in the help sheet;
//   * the result restates BOTH operands in bits, so the factor of 8 is shown
//     rather than hidden inside the answer;
//   * picking a binary size unit raises the GB/GiB warning, and only then;
//   * each of the three solves shows the two fields it needs and hides the one
//     it is computing;
//   * a divisor of zero is an inline error, not an infinity, and Copy goes
//     null so nothing wrong can be pasted into a change ticket;
//   * an empty field is idle, not an error;
//   * no overflow at phone, tablet and desktop widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/transfer_time_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';

Widget _host() => const MaterialApp(home: TransferTimeScreen());

/// Drive the REAL test viewport, not just a MediaQuery wrapper.
///
/// This matters, and it is easy to get wrong: wrapping a screen in
/// `MediaQuery(data: MediaQueryData(size: ...))` changes what the widget is
/// TOLD about the window while the render surface stays at the 800x600 default,
/// so a "renders at 320 wide" assertion written that way never rendered at 320
/// and could not fail. `tester.view.physicalSize` is what actually resizes the
/// surface. Same helper as test/widget_test.dart and test/screens/home_screen_test.dart.
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

String? _copyPayload(WidgetTester tester) =>
    tester.widget<AppCopyAction>(find.byType(AppCopyAction)).textBuilder();

void main() {
  testWidgets('opens on the worked example: 1 GB at 100 Mbps is 1 min 20 s', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('1 min 20 s'), findsOneWidget);
    expect(find.text('1 GB = 8,000,000,000 bits'), findsOneWidget);
    expect(find.text('100 Mbps = 100,000,000 bits per second'), findsOneWidget);
  });

  testWidgets('the bits-and-bytes rule is on the form, not in the help sheet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('1 byte = 8 bits, so a 100 Mbps link moves 12.5 MB'),
      findsOneWidget,
    );
  });

  testWidgets('the decimal-versus-binary warning appears only when a binary '
      'unit is picked, and the bit count shows the 1024', (
    WidgetTester tester,
  ) async {
    await _withViewport(tester, const Size(390, 900), () async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      expect(find.textContaining('You picked a binary unit'), findsNothing);

      // Open the size-unit select (the first AppSelect on the screen). The
      // menu is capped at five rows by GL-003 §8.14 sizing, so the binary
      // units sit below the fold and the menu has to be scrolled before KiB
      // exists in the tree at all.
      await tester.tap(find.byType(AppSelect<String>).first);
      await tester.pumpAndSettle();
      final Finder menu = find.byType(ListView).last;
      await tester.drag(menu, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: menu, matching: find.text('KiB')));
      await tester.pumpAndSettle();

      expect(find.textContaining('You picked a binary unit'), findsOneWidget);
      // 1 KiB is 1024 bytes, so 8,192 bits. A KB would have been 8,000.
      expect(find.text('1 KiB = 8,192 bits'), findsOneWidget);
    });
  });

  testWidgets('solving for Speed hides the speed field and shows the answer '
      'in a bit unit', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Speed').first);
    await tester.pumpAndSettle();

    expect(find.text('Speed needed'), findsOneWidget);
    // 1 GB in 10 minutes: 8e9 bits / 600 s = 13,333,333.33 bps.
    expect(
      find.textContaining('13.33 Mbps (13,333,333.33 bits per second)'),
      findsOneWidget,
    );
    expect(find.text('10 min = 10 min 0 s'), findsOneWidget);
  });

  testWidgets('solving for Size reports bytes AND bits', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Size').first);
    await tester.pumpAndSettle();

    // 100 Mbps for 10 minutes = 6e10 bits = 7.5 GB.
    expect(find.text('Data moved'), findsOneWidget);
    expect(
      find.textContaining('7.50 GB (60,000,000,000 bits)'),
      findsOneWidget,
    );
  });

  testWidgets('a speed of zero is an inline error, not an infinity, and Copy '
      'goes null', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), '0');
    await tester.pumpAndSettle();

    expect(find.text('Check your input'), findsOneWidget);
    expect(find.textContaining('A rate of zero moves nothing'), findsOneWidget);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(_copyPayload(tester), isNull);
  });

  testWidgets('an empty field is idle, not an error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();

    expect(find.text('Check your input'), findsNothing);
    expect(find.text('Result'), findsNothing);
    expect(_copyPayload(tester), isNull);
  });

  testWidgets('the Copy payload carries the answer, both operands in bits, and '
      'the overhead caveat', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final String p = _copyPayload(tester)!;
    expect(p, contains('Transfer time: 1 min 20 s'));
    expect(p, contains('1 GB = 8,000,000,000 bits'));
    expect(p, contains('100 Mbps = 100,000,000 bits per second'));
    expect(p, contains('Real transfers run slower'));
  });

  testWidgets('no overflow at phone, tablet or desktop width', (
    WidgetTester tester,
  ) async {
    for (final Size size in <Size>[
      const Size(320, 720),
      const Size(768, 1024),
      const Size(1280, 900),
    ]) {
      await _withViewport(tester, size, () async {
        await tester.pumpWidget(_host());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size');
      });
    }
  });
}
