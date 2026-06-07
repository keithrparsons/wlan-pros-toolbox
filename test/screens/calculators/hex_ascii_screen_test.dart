// Tests for the Hex / ASCII screen.
//
// Part A — the pure base-conversion math (dec <-> hex <-> bin), incl. the
// empty/invalid paths and a large BigInt-domain value.
// Part B — the printable-ASCII table: 95 rows (32-126), values derived (not
// hand-typed) so the char is always the real glyph — including the
// vertical-bar row (decimal 124), the Pax-flagged ingest hazard.
// A widget smoke confirms render + live converter mirroring.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/hex_ascii_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('HexAsciiConvert — base conversion math', () {
    test('decimal 65 -> hex 41 -> binary 1000001', () {
      final BigInt? v = HexAsciiConvert.parseDecimal('65');
      expect(v, isNotNull);
      expect(HexAsciiConvert.toHex(v!), '41');
      expect(HexAsciiConvert.toBinary(v), '1000001');
    });

    test('hex parses with and without 0x prefix', () {
      expect(HexAsciiConvert.parseHex('ff'), BigInt.from(255));
      expect(HexAsciiConvert.parseHex('0xFF'), BigInt.from(255));
    });

    test('binary parses with and without 0b prefix', () {
      expect(HexAsciiConvert.parseBinary('1010'), BigInt.from(10));
      expect(HexAsciiConvert.parseBinary('0b1010'), BigInt.from(10));
    });

    test('empty and invalid inputs return null (blank-mirror path)', () {
      expect(HexAsciiConvert.parseDecimal(''), isNull);
      expect(HexAsciiConvert.parseDecimal('  '), isNull);
      expect(HexAsciiConvert.parseHex('xyz'), isNull);
      expect(HexAsciiConvert.parseBinary('012'), isNull); // 2 not binary
      expect(HexAsciiConvert.parseHex('0x'), isNull); // prefix only
    });

    test('large values stay exact in the BigInt domain', () {
      final BigInt? v =
          HexAsciiConvert.parseHex('FFFFFFFFFFFFFFFFFF'); // 18 hex digits
      expect(v, isNotNull);
      expect(HexAsciiConvert.toDecimal(v!), '4722366482869645213695');
    });
  });

  group('HexAsciiConvert — ASCII conversion (BF5-17)', () {
    test('a single printable glyph parses to its code point', () {
      expect(HexAsciiConvert.parseAscii('A'), BigInt.from(65));
      expect(HexAsciiConvert.parseAscii(' '), BigInt.from(32));
      expect(HexAsciiConvert.parseAscii('~'), BigInt.from(126));
      expect(HexAsciiConvert.parseAscii('|'), BigInt.from(124));
    });

    test('non-single / non-printable input parses to null', () {
      expect(HexAsciiConvert.parseAscii(''), isNull);
      expect(HexAsciiConvert.parseAscii('AB'), isNull); // more than one char
      expect(HexAsciiConvert.parseAscii('\n'), isNull); // control code (10)
    });

    test('a code point in 32-126 renders its glyph; outside it is null', () {
      expect(HexAsciiConvert.toAscii(BigInt.from(65)), 'A');
      expect(HexAsciiConvert.toAscii(BigInt.from(32)), ' ');
      expect(HexAsciiConvert.toAscii(BigInt.from(126)), '~');
      // No single ASCII glyph for a control code or a multi-byte value.
      expect(HexAsciiConvert.toAscii(BigInt.from(10)), isNull);
      expect(HexAsciiConvert.toAscii(BigInt.from(255)), isNull);
      expect(HexAsciiConvert.toAscii(BigInt.from(31)), isNull);
    });

    test('round-trips a glyph through its code point', () {
      final BigInt? code = HexAsciiConvert.parseAscii('Z');
      expect(code, BigInt.from(90));
      expect(HexAsciiConvert.toAscii(code!), 'Z');
      expect(HexAsciiConvert.toHex(code), '5A');
    });
  });

  group('ASCII reference table — derived rows', () {
    AsciiRow rowFor(int dec) =>
        HexAsciiScreen.rows.firstWhere((AsciiRow r) => r.dec == dec);

    test('exactly 95 printable rows, 32 through 126', () {
      expect(HexAsciiScreen.rows.length, 95);
      expect(HexAsciiScreen.rows.first.dec, 32);
      expect(HexAsciiScreen.rows.last.dec, 126);
    });

    test('A (65) derives hex 41, binary 01000001, char A', () {
      final AsciiRow a = rowFor(65);
      expect(a.hex, '41');
      expect(a.bin, '01000001');
      expect(a.char, 'A');
    });

    test('the vertical-bar row (124) is a real "|" glyph (Pax ingest hazard)',
        () {
      final AsciiRow bar = rowFor(124);
      expect(bar.char, '|');
      expect(bar.hex, '7C');
      expect(bar.bin, '01111100');
      expect(bar.name, 'Vertical bar');
    });

    test('space (32) and tilde (126) endpoints', () {
      expect(rowFor(32).char, ' ');
      expect(rowFor(32).name, 'Space');
      expect(rowFor(126).char, '~');
      expect(rowFor(126).name, 'Tilde');
    });

    test('hyphen-minus (45) carries the ASCII-hyphen name', () {
      expect(rowFor(45).char, '-');
      expect(rowFor(45).name, 'Hyphen-minus');
    });

    test('binary is always 8-bit zero-padded', () {
      for (final AsciiRow r in HexAsciiScreen.rows) {
        expect(r.bin.length, 8);
      }
    });
  });

  group('HexAsciiScreen widget', () {
    testWidgets('typing decimal updates hex and binary live', (tester) async {
      await _withViewport(tester, const Size(375, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const HexAsciiScreen()),
        );
        // First field is Decimal.
        await tester.enterText(find.byType(TextField).first, '255');
        await tester.pump();
        // Hex field should now read FF, binary 11111111.
        expect(find.text('FF'), findsWidgets);
        expect(find.text('11111111'), findsWidgets);
      });
    });

    testWidgets('typing an ASCII glyph fills dec/hex/binary (BF5-17)',
        (tester) async {
      await _withViewport(tester, const Size(375, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const HexAsciiScreen()),
        );
        // The fourth converter field is "ASCII character".
        await tester.enterText(find.byType(TextField).at(3), 'A');
        await tester.pump();
        // 'A' is decimal 65 / hex 41 / binary 1000001.
        expect(find.text('65'), findsWidgets);
        expect(find.text('41'), findsWidgets);
        expect(find.text('1000001'), findsWidgets);
      });
    });

    testWidgets('typing decimal 65 shows the ASCII glyph A (BF5-17)',
        (tester) async {
      await _withViewport(tester, const Size(375, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const HexAsciiScreen()),
        );
        final Finder asciiField = find.byType(TextField).at(3);
        await tester.enterText(find.byType(TextField).first, '65');
        await tester.pump();
        expect(
          tester.widget<TextField>(asciiField).controller!.text,
          'A',
        );
      });
    });

    testWidgets('renders the table and an anchor row', (tester) async {
      await _withViewport(tester, const Size(375, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const HexAsciiScreen()),
        );
        expect(find.text('Hex / ASCII'), findsWidgets);
        expect(find.text('Printable ASCII (32-126)'), findsOneWidget);
      });
    });

    testWidgets('renders without overflow at 320/768 widths', (tester) async {
      for (final double width in <double>[320, 768]) {
        await _withViewport(tester, Size(width, 3000), () async {
          await tester.pumpWidget(
            MaterialApp(theme: AppTheme.dark(), home: const HexAsciiScreen()),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });
  });
}

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
