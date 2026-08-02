// SubnetCalcScreen — the two 2026-08-02 additions: Range mode and the
// Number forms block.
//
// The arithmetic is unit-tested in ip_block_math_test and ipv4_forms_test.
// This file asserts only what the SCREEN owes:
//
//   * Subnet mode still opens on its worked example and now carries the
//     integer / hex / binary rows, with the boundary drawn at the prefix;
//   * the binary row shows the address AS TYPED, not the network base, so a
//     host address teaches which bits are host bits;
//   * a /31 and a /32 still render, boundary and all, without a broadcast;
//   * Range mode converts two endpoints to the minimal block set, says how
//     many blocks and why, and converts back from a typed block;
//   * a last address before the first is an error, not a silent swap;
//   * the Copy payload changes with the mode;
//   * no overflow at phone, tablet and desktop widths, including the 35-char
//     binary lines on the narrowest phone.
//
// The device-IP prefill is stubbed out so the seeded worked example survives.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/subnet_calc_screen.dart';
import 'package:wlan_pros_toolbox/services/network/interface_info_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

/// An interface reader that reports nothing, so the screen keeps its seeded
/// worked example instead of prefilling from a real device.
class _NoInterfaceInfo extends InterfaceInfoService {
  @override
  Future<InterfaceInfoSnapshot> read() async =>
      throw StateError('no interface info in tests');
}

Widget _host({Size size = const Size(390, 844)}) => MaterialApp(
  theme: AppTheme.dark(),
  home: MediaQuery(
    data: MediaQueryData(size: size),
    child: SubnetCalcScreen(interfaceInfo: _NoInterfaceInfo()),
  ),
);

Finder _field(int index) => find.byType(TextField).at(index);

String? _copyPayload(WidgetTester tester) =>
    tester.widget<AppCopyAction>(find.byType(AppCopyAction)).textBuilder();

void main() {
  group('Number forms', () {
    testWidgets('the worked example carries integer, hex and both binary '
        'lines with the boundary at /22', (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Number forms'), findsOneWidget);
      expect(find.text('169,082,880'), findsOneWidget);
      expect(find.text('0x0A140000'), findsOneWidget);
      expect(find.text('0A.14.00.00'), findsOneWidget);
      expect(find.text('00001010.00010100.000000/00.00000000'), findsOneWidget);
      expect(find.text('11111111.11111111.111111/00.00000000'), findsOneWidget);
      expect(find.textContaining('left of it is the network'), findsOneWidget);
    });

    testWidgets('the binary line shows the address AS TYPED, not the network '
        'base', (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.enterText(_field(0), '10.20.0.37');
      await tester.pumpAndSettle();

      // .37 is 00100101, and the /22 boundary still cuts inside octet 3.
      expect(find.text('00001010.00010100.000000/00.00100101'), findsOneWidget);
      // The subnet rows still report the network, which is the whole point of
      // showing both.
      expect(find.text('10.20.0.0/22'), findsOneWidget);
    });

    testWidgets('a /32 puts the boundary at the very end and still has no '
        'broadcast', (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.enterText(_field(0), '10.0.0.5');
      await tester.enterText(_field(1), '32');
      await tester.pumpAndSettle();

      expect(find.text('00001010.00000000.00000000.00000101/'), findsOneWidget);
      expect(find.textContaining('Single-host route'), findsOneWidget);
    });

    testWidgets('a /31 renders the RFC 3021 case with its boundary', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.enterText(_field(0), '10.0.0.4');
      await tester.enterText(_field(1), '31');
      await tester.pumpAndSettle();

      expect(find.text('00001010.00000000.00000000.0000010/0'), findsOneWidget);
      expect(find.textContaining('RFC 3021'), findsOneWidget);
    });

    testWidgets('a /0 puts the boundary before the first bit', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.enterText(_field(0), '0.0.0.0');
      await tester.enterText(_field(1), '0');
      await tester.pumpAndSettle();

      // TWO matches, and that is correct: with 0.0.0.0 under a /0 the
      // address bits and the mask bits are both all-zero, so the two binary
      // lines are identical. Asserting one would have been asserting a bug.
      expect(
        find.text('/00000000.00000000.00000000.00000000'),
        findsNWidgets(2),
      );
    });

    testWidgets('the Copy payload carries the number forms', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      final String p = _copyPayload(tester)!;
      expect(p, contains('Integer: 169082880'));
      expect(p, contains('Hex: 0x0A140000'));
      expect(
        p,
        contains('Address in binary: 00001010.00010100.000000/00.00000000'),
      );
      expect(
        p,
        contains('Netmask in binary: 11111111.11111111.111111/00.00000000'),
      );
    });
  });

  group('Range mode', () {
    Future<void> toRange(WidgetTester tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Range'));
      await tester.pumpAndSettle();
    }

    testWidgets('an exactly-aligned range collapses to one block, and says '
        'so', (WidgetTester tester) async {
      await toRange(tester);
      expect(find.text('Covered by 1 block'), findsOneWidget);
      expect(find.text('10.4.16.0/20'), findsOneWidget);
      expect(find.text('4,096'), findsWidgets);
      expect(
        find.textContaining('lands exactly on one CIDR boundary'),
        findsOneWidget,
      );
      // The subnet-mode result is gone; one mode at a time.
      expect(find.text('Number forms'), findsNothing);
    });

    testWidgets('a range that is NOT aligned takes several blocks, and the '
        'screen says how many and why', (WidgetTester tester) async {
      await toRange(tester);
      await tester.enterText(_field(0), '192.168.1.1');
      await tester.enterText(_field(1), '192.168.1.6');
      await tester.pumpAndSettle();

      expect(find.text('Covered by 4 blocks'), findsOneWidget);
      expect(find.text('192.168.1.1/32'), findsOneWidget);
      expect(find.text('192.168.1.2/31'), findsOneWidget);
      expect(find.text('192.168.1.4/31'), findsOneWidget);
      expect(find.text('192.168.1.6/32'), findsOneWidget);
      expect(
        find.textContaining('takes 4 blocks to cover it exactly'),
        findsOneWidget,
      );
    });

    testWidgets('typing a whole block runs the conversion the other way and '
        'disables the second field', (WidgetTester tester) async {
      await toRange(tester);
      await tester.enterText(_field(0), '10.4.16.0/20');
      await tester.pumpAndSettle();

      expect(find.text('10.4.16.0'), findsWidgets); // the derived first
      expect(find.text('10.4.31.255'), findsWidgets); // the derived last
      expect(find.text('Covered by 1 block'), findsOneWidget);
      expect(find.textContaining('this field is ignored'), findsOneWidget);
      expect(tester.widget<TextField>(_field(1)).enabled, isFalse);
    });

    testWidgets('a last address before the first is an error, not a silent '
        'swap', (WidgetTester tester) async {
      await toRange(tester);
      await tester.enterText(_field(0), '10.0.0.10');
      await tester.enterText(_field(1), '10.0.0.1');
      await tester.pumpAndSettle();

      expect(find.text('Check your input'), findsOneWidget);
      expect(find.textContaining('comes before the first'), findsOneWidget);
      expect(_copyPayload(tester), isNull);
    });

    testWidgets('a malformed endpoint is an error with a specific message', (
      WidgetTester tester,
    ) async {
      await toRange(tester);
      await tester.enterText(_field(0), '10.0.0.999');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('first address is not valid IPv4'),
        findsOneWidget,
      );
    });

    testWidgets('the Copy payload is the range, not the subnet', (
      WidgetTester tester,
    ) async {
      await toRange(tester);
      final String p = _copyPayload(tester)!;
      expect(p, contains('IPv4 Range'));
      expect(p, contains('First: 10.4.16.0'));
      expect(p, contains('Last: 10.4.31.255'));
      expect(p, contains('Total IPs: 4,096'));
      expect(p, contains('Blocks (1): 10.4.16.0/20'));
      expect(p, isNot(contains('Wildcard')));
    });
  });

  testWidgets('no overflow at phone, tablet or desktop width, in either mode', (
    WidgetTester tester,
  ) async {
    for (final Size size in <Size>[
      const Size(320, 720),
      const Size(768, 1024),
      const Size(1280, 900),
    ]) {
      await tester.pumpWidget(_host(size: size));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'subnet at $size');

      await tester.tap(find.text('Range'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'range at $size');
    }
  });
}
