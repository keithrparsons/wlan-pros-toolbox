// Tests for the Subnetting / CIDR Table screen.
//
// The /0-/32 dataset is sourced verbatim from the verified addressing dataset
// (Deliverables/2026-06-08-reference-batch/addressing-data.md, Section 2). These
// tests assert the table is complete and arithmetically consistent (total =
// 2^(32-n)), pin the load-bearing anchor rows, and verify the /31 and /32
// exceptions are honored — a /31 carries 2 usable hosts (RFC 3021), a /32 carries
// 1 (single host), with their exception notes set. A phone-viewport widget test
// (mirrors the poe reference test) confirms the screen renders without a
// RenderFlex overflow at 320/375/768/1280 widths.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/cidr_table_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('CIDR table — completeness and arithmetic', () {
    CidrRow rowFor(int prefix) =>
        CidrTableScreen.rows.firstWhere((CidrRow r) => r.prefix == prefix);

    test('33 rows, one per prefix /0 to /32 in order', () {
      expect(CidrTableScreen.rows.length, 33);
      expect(
        CidrTableScreen.rows.map((CidrRow r) => r.prefix).toList(),
        List<int>.generate(33, (int i) => i),
      );
    });

    test('total addresses = 2^(32-n) for every row', () {
      for (final CidrRow r in CidrTableScreen.rows) {
        final int expected = math.pow(2, 32 - r.prefix).toInt();
        expect(r.total, expected, reason: '/${r.prefix} total');
      }
    });

    test('usable = total - 2 for /0 through /30', () {
      for (final CidrRow r in CidrTableScreen.rows) {
        if (r.prefix <= 30) {
          expect(r.usableHosts, r.total - 2, reason: '/${r.prefix} usable');
          expect(r.usableNote, isNull);
        }
      }
    });

    test('/24 = 256 total / 254 usable / 255.255.255.0', () {
      final CidrRow r = rowFor(24);
      expect(r.total, 256);
      expect(r.usableHosts, 254);
      expect(r.mask, '255.255.255.0');
      expect(r.wildcard, '0.0.0.255');
    });

    test('/0 = full IPv4 space', () {
      final CidrRow r = rowFor(0);
      expect(r.total, 4294967296);
      expect(r.usableHosts, 4294967294);
      expect(r.mask, '0.0.0.0');
    });
  });

  group('CIDR table — /31 and /32 exceptions honored', () {
    CidrRow rowFor(int prefix) =>
        CidrTableScreen.rows.firstWhere((CidrRow r) => r.prefix == prefix);

    test('/31 = 2 usable (point-to-point), NOT 0', () {
      final CidrRow r = rowFor(31);
      expect(r.total, 2);
      expect(r.usableHosts, 2, reason: 'RFC 3021 point-to-point');
      expect(r.usableNote, contains('point-to-point'));
      expect(r.usableNote, contains('RFC 3021'));
    });

    test('/32 = 1 host (single host), NOT -1', () {
      final CidrRow r = rowFor(32);
      expect(r.total, 1);
      expect(r.usableHosts, 1);
      expect(r.usableNote, contains('single host'));
    });

    test('cross-link names the IPv4 Subnet Calculator', () {
      expect(
        CidrTableScreen.calculatorCrossLink,
        contains('IPv4 Subnet Calculator'),
      );
    });
  });

  group('CidrTableScreen widget', () {
    testWidgets('renders title, table heading, and calculator cross-link in a '
        'phone viewport', (tester) async {
      await _withViewport(tester, const Size(375, 1400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const CidrTableScreen(),
          ),
        );

        expect(find.text('Subnetting / CIDR Table'), findsWidgets);
        expect(find.text('Prefix /0 to /32'), findsOneWidget);
        expect(find.textContaining('IPv4 Subnet Calculator'), findsWidgets);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1600), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const CidrTableScreen(),
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
