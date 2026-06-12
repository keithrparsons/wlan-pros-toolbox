// Tests for the International Morse model (lib/data/morse.dart).
//
// Pure logic — no widget pump, no audio. Covers: the ITU-R M.1677-1 table,
// text→Morse and Morse→text transforms, the round-trip lossless property,
// tolerant decoding (separators, unknown codes), the looksLikeMorse heuristic,
// and the dit-unit timing/segment model the audio player drives off.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/morse.dart';

void main() {
  group('International Morse table (ITU-R M.1677-1)', () {
    test('all 26 letters and 10 digits map', () {
      for (final int c in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.codeUnits) {
        final String ch = String.fromCharCode(c);
        expect(Morse.charToCode[ch], isNotNull, reason: 'missing $ch');
      }
    });

    test('canonical codes are correct', () {
      expect(Morse.charToCode['A'], '.-');
      expect(Morse.charToCode['E'], '.'); // shortest
      expect(Morse.charToCode['T'], '-');
      expect(Morse.charToCode['O'], '---');
      expect(Morse.charToCode['S'], '...');
      expect(Morse.charToCode['5'], '.....');
      expect(Morse.charToCode['0'], '-----');
      expect(Morse.charToCode['?'], '..--..');
    });

    test('the code→char inverse is consistent with char→code', () {
      Morse.charToCode.forEach((String ch, String code) {
        expect(Morse.codeToChar[code], ch,
            reason: 'inverse mismatch for $ch / $code');
      });
    });
  });

  group('encode (text → Morse)', () {
    test('SOS encodes letter-spaced', () {
      expect(Morse.encode('SOS'), '... --- ...');
    });

    test('case is folded to upper', () {
      expect(Morse.encode('sos'), Morse.encode('SOS'));
    });

    test('words are joined by a slash', () {
      expect(Morse.encode('HI YE'), '.... .. / -.-- .');
    });

    test('runs of whitespace collapse to one word gap', () {
      expect(Morse.encode('A   B'), '.- / -...');
    });

    test('unmappable characters are dropped (chars stay letter-spaced)', () {
      // The tilde has no Morse mapping; A and B remain, still within one word so
      // they keep the single-space letter gap.
      expect(Morse.encode('A~B'), '.- -...');
    });

    test('empty / whitespace input encodes to empty', () {
      expect(Morse.encode(''), '');
      expect(Morse.encode('   '), '');
    });
  });

  group('decode (Morse → text)', () {
    test('SOS decodes', () {
      expect(Morse.decode('... --- ...'), 'SOS');
    });

    test('slash and pipe and double-space all separate words', () {
      expect(Morse.decode('.... .. / -.-- .'), 'HI YE');
      expect(Morse.decode('.... .. | -.-- .'), 'HI YE');
      expect(Morse.decode('....  -.--'), 'H Y'); // double space = word gap
    });

    test('unknown codes decode to a question mark, not silence', () {
      // "......" is not a valid character; it surfaces as '?'.
      expect(Morse.decode('...... ...'), '?S');
    });

    test('stray surrounding whitespace is tolerated', () {
      expect(Morse.decode('   ... --- ...   '), 'SOS');
    });

    test('empty input decodes to empty', () {
      expect(Morse.decode(''), '');
      expect(Morse.decode('   '), '');
    });
  });

  group('round-trip (the lossless property)', () {
    test('text → Morse → text is lossless for encodable text (upper)', () {
      for (final String sample in <String>[
        'SOS',
        'HELLO WORLD',
        'WLAN PROS',
        'CWNE 3',
        'THE QUICK BROWN FOX 12345',
      ]) {
        final String there = Morse.encode(sample);
        final String back = Morse.decode(there);
        expect(back, sample.toUpperCase(), reason: 'round-trip on "$sample"');
      }
    });

    test('punctuation round-trips', () {
      const String sample = 'WHY?';
      expect(Morse.decode(Morse.encode(sample)), 'WHY?');
    });
  });

  group('looksLikeMorse', () {
    test('true for dot/dash/separator strings', () {
      expect(Morse.looksLikeMorse('... --- ...'), isTrue);
      expect(Morse.looksLikeMorse('.- / -...'), isTrue);
    });

    test('false for plain text and empty', () {
      expect(Morse.looksLikeMorse('SOS'), isFalse);
      expect(Morse.looksLikeMorse('hello'), isFalse);
      expect(Morse.looksLikeMorse(''), isFalse);
      expect(Morse.looksLikeMorse('   '), isFalse);
    });
  });

  group('prosigns', () {
    test('SOS prosign is the run-together form', () {
      final MorseEntry sos =
          Morse.prosigns.firstWhere((MorseEntry e) => e.character == '<SOS>');
      expect(sos.code, '...---...');
      expect(sos.isProsign, isTrue);
      expect(sos.name, isNotNull);
    });

    test('prosign tokens are not produced by ordinary encoding', () {
      // Encoding the letters S O S yields the SPACED form, never the prosign.
      expect(Morse.encode('SOS'), isNot('...---...'));
    });
  });

  group('timing / segment model', () {
    test('unitMs follows the PARIS standard (1200 / wpm)', () {
      expect(Morse.unitMs(20), 60);
      expect(Morse.unitMs(15), 80);
    });

    test('segments for "E" is a single 1-unit ON (one dot)', () {
      final List<MorseSegment> segs = Morse.segments('E');
      expect(segs, hasLength(1));
      expect(segs.single.on, isTrue);
      expect(segs.single.units, 1);
    });

    test('segments for "T" is a single 3-unit ON (one dash)', () {
      final List<MorseSegment> segs = Morse.segments('T');
      expect(segs, hasLength(1));
      expect(segs.single.on, isTrue);
      expect(segs.single.units, 3);
    });

    test('intra-character, letter, and word gaps are 1, 3, 7 units', () {
      // "EE" → dot, 3-unit letter gap, dot.
      final List<MorseSegment> ee = Morse.segments('EE');
      expect(ee.map((MorseSegment s) => '${s.on}:${s.units}').toList(),
          <String>['true:1', 'false:3', 'true:1']);

      // "E E" → dot, 7-unit word gap, dot.
      final List<MorseSegment> wordGap = Morse.segments('E E');
      expect(wordGap.map((MorseSegment s) => '${s.on}:${s.units}').toList(),
          <String>['true:1', 'false:7', 'true:1']);

      // "A" = dot dash → dot, 1-unit intra gap, dash.
      final List<MorseSegment> a = Morse.segments('A');
      expect(a.map((MorseSegment s) => '${s.on}:${s.units}').toList(),
          <String>['true:1', 'false:1', 'true:3']);
    });

    test('empty input yields no segments', () {
      expect(Morse.segments(''), isEmpty);
      expect(Morse.segments('   '), isEmpty);
    });
  });
}
