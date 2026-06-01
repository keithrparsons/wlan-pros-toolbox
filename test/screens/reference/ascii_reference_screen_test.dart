// Tests for the ASCII / Hex / Binary reference screen.
//
// Two layers, mirroring the other reference-screen tests (mcs_index,
// reason_codes):
//   1. Data assertions against the public static datasets — guard that the 128
//      ASCII rows and the supplementary tables match the team source of truth
//      (Deliverables/2026-05-31-ascii-hex-binary-reference/*.json) verbatim.
//      Anchors: NUL/0x00, 'A'/0x41/65, DEL/0x7F/127, the case bit, the
//      nibble→hex map, powers of two.
//   2. Widget tests in phone/tablet/desktop viewports — the screen pumps and
//      renders without a RenderFlex overflow at 320/375/768/1280, shows
//      representative rows, and the free-text filter narrows the table and
//      reaches the honest empty state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ascii_reference_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// Flatten control + printable into one lookup by decimal code point.
Map<int, AsciiEntry> _byDec() {
  final Map<int, AsciiEntry> m = <int, AsciiEntry>{};
  for (final AsciiEntry e in AsciiReferenceScreen.controlCodes) {
    m[e.dec] = e;
  }
  for (final AsciiEntry e in AsciiReferenceScreen.printableChars) {
    m[e.dec] = e;
  }
  return m;
}

void main() {
  group('ASCII dataset — completeness and verbatim values', () {
    test('33 control codes and 95 printable characters = 128 rows', () {
      expect(AsciiReferenceScreen.controlCodes.length, 33);
      expect(AsciiReferenceScreen.printableChars.length, 95);
      expect(AsciiReferenceScreen.allByCodePoint.length, 128);
    });

    test('every code point 0–127 is present exactly once', () {
      final Map<int, AsciiEntry> byDec = _byDec();
      for (int i = 0; i <= 127; i++) {
        expect(byDec.containsKey(i), isTrue, reason: 'missing code point $i');
      }
      expect(byDec.length, 128);
    });

    test('NUL is dec 0 / 0x00 / 000 / 00000000, control mnemonic NUL', () {
      final AsciiEntry nul = _byDec()[0]!;
      expect(nul.category, AsciiCategory.control);
      expect(nul.hex, '00');
      expect(nul.oct, '000');
      expect(nul.bin, '00000000');
      expect(nul.mnemonic, 'NUL');
      expect(nul.glyph, isNull);
      expect(nul.charToken, 'NUL');
    });

    test("'A' is dec 65 / 0x41 / 101 / 01000001, printable glyph A", () {
      final AsciiEntry a = _byDec()[65]!;
      expect(a.category, AsciiCategory.printable);
      expect(a.hex, '41');
      expect(a.oct, '101');
      expect(a.bin, '01000001');
      expect(a.glyph, 'A');
      expect(a.mnemonic, isNull);
      expect(a.charToken, 'A');
    });

    test('DEL is dec 127 / 0x7F / 177 / 01111111, control mnemonic DEL', () {
      final AsciiEntry del = _byDec()[127]!;
      expect(del.category, AsciiCategory.control);
      expect(del.hex, '7F');
      expect(del.oct, '177');
      expect(del.bin, '01111111');
      expect(del.mnemonic, 'DEL');
      expect(del.charToken, 'DEL');
    });

    test('space (dec 32) renders the explicit SP token', () {
      final AsciiEntry sp = _byDec()[32]!;
      expect(sp.glyph, ' ');
      expect(sp.charToken, 'SP');
    });

    test('lowercase a is dec 97 / 0x61 (case bit 0x20 above uppercase A)', () {
      final AsciiEntry lower = _byDec()[97]!;
      expect(lower.glyph, 'a');
      expect(lower.hex, '61');
      // The single-bit case relationship the source highlights.
      expect(_byDec()[65]!.dec + 0x20, lower.dec);
    });

    test('every bin column is 8 bits with the high bit clear', () {
      for (final AsciiEntry e in AsciiReferenceScreen.allByCodePoint) {
        expect(e.bin.length, 8, reason: 'dec ${e.dec}');
        expect(e.bin[0], '0', reason: 'high bit set on dec ${e.dec}');
        // bin parsed as base-2 equals the decimal value.
        expect(int.parse(e.bin, radix: 2), e.dec, reason: 'dec ${e.dec}');
      }
    });

    test('every hex column is the two-digit value of dec', () {
      for (final AsciiEntry e in AsciiReferenceScreen.allByCodePoint) {
        expect(int.parse(e.hex, radix: 16), e.dec, reason: 'dec ${e.dec}');
      }
    });
  });

  group('Supplementary tables — verbatim port', () {
    test('range boundaries cover digits, A–Z, a–z, space', () {
      expect(
        AsciiReferenceScreen.rangeBoundaries.map((RangeBoundary b) => b.block),
        <String>['Digits 0–9', 'Uppercase A–Z', 'Lowercase a–z', 'Space'],
      );
    });

    test('nibble→hex map has 16 rows, 0000→0 and 1111→F', () {
      expect(AsciiReferenceScreen.nibbleToHex.length, 16);
      expect(AsciiReferenceScreen.nibbleToHex.first.bin, '0000');
      expect(AsciiReferenceScreen.nibbleToHex.first.hex, '0');
      expect(AsciiReferenceScreen.nibbleToHex.last.bin, '1111');
      expect(AsciiReferenceScreen.nibbleToHex.last.hex, 'F');
    });

    test('powers of two include 2^8 = 256 and 2^32 = 4,294,967,296', () {
      final Map<int, String> byExp = <int, String>{
        for (final PowerOfTwo p in AsciiReferenceScreen.powersOfTwo)
          p.exp: p.value,
      };
      expect(byExp[8], '256');
      expect(byExp[32], '4,294,967,296');
    });

    test('hex place values run 16^0..16^4', () {
      expect(
        AsciiReferenceScreen.hexPlaceValues
            .map((HexPlaceValue h) => h.position),
        <String>['16^0', '16^1', '16^2', '16^3', '16^4'],
      );
    });

    test('high range names UTF-8, ISO-8859-1, Windows-1252', () {
      expect(
        AsciiReferenceScreen.highRangeEncodings
            .map((HighRangeEncoding e) => e.name),
        <String>['UTF-8', 'ISO-8859-1 (Latin-1)', 'Windows-1252'],
      );
    });
  });

  group('Filter matching', () {
    test('decimal, hex (with/without 0x), mnemonic, and keyword all match', () {
      final AsciiEntry lf = _byDec()[10]!;
      expect(lf.matches('10'), isTrue);
      expect(lf.matches('0a'), isTrue);
      expect(lf.matches('0x0a'), isTrue);
      expect(lf.matches('lf'), isTrue);
      expect(lf.matches('newline'), isTrue);
      expect(lf.matches('zzz'), isFalse);
    });

    test('empty query matches everything', () {
      expect(_byDec()[65]!.matches(''), isTrue);
    });
  });

  testWidgets('renders representative rows in a phone viewport', (
    tester,
  ) async {
    await _withViewport(tester, const Size(375, 1400), () async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const AsciiReferenceScreen(),
        ),
      );
      await tester.pump();

      // Title + both section headings render on first paint.
      expect(find.text('ASCII / Hex / Binary'), findsOneWidget);
      expect(find.text('Control codes (0–31, plus 127)'), findsOneWidget);
      expect(find.text('Printable characters (32–126)'), findsOneWidget);

      // Representative rows: NUL (0x00), 'A' (0x41/65), DEL (0x7F).
      expect(find.text('NUL'), findsWidgets);
      expect(find.text('00'), findsWidgets);
      expect(find.text('41'), findsWidgets);
      expect(find.text('65'), findsWidgets);
      expect(find.text('DEL'), findsWidgets);
      expect(find.text('7F'), findsWidgets);
    });
  });

  testWidgets('filter narrows to one row and reaches the empty state', (
    tester,
  ) async {
    await _withViewport(tester, const Size(375, 1400), () async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const AsciiReferenceScreen(),
        ),
      );
      await tester.pump();

      // Filter to the LF control code — its mnemonic survives, an unrelated
      // glyph drops out of the visible tables.
      await tester.enterText(find.byType(TextField), 'newline');
      await tester.pump();
      expect(find.text('LF'), findsWidgets);
      // The control-section count line reflects the single match.
      expect(
        find.textContaining('of 33', findRichText: false),
        findsOneWidget,
      );

      // A query that matches no character reaches the honest empty state, while
      // the quick-reference tables below stay visible.
      await tester.enterText(find.byType(TextField), 'zzzznope');
      await tester.pump();
      expect(find.text('No match'), findsOneWidget);
      expect(find.text('Nibble → hex map'), findsOneWidget);
    });
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    for (final double width in <double>[320, 375, 768, 1280]) {
      await _withViewport(tester, Size(width, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const AsciiReferenceScreen(),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      });
    }
  });
}

/// Run [body] with the test view sized to [size], then restore. Mirrors the
/// `_withViewport` helper in the other reference-screen tests.
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
