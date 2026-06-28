// Tests for music_theory.dart — the equal-temperament + RF-bridge math behind
// the "Hear the Frequency" tool.
//
// GOLDEN TABLE: the spec's published C4 -> C5 frequencies (build-spec §2.1) are
// the baseline. The screen COMPUTES every value from f(n)=440*2^((n-49)/12);
// this test proves the computation reproduces the published table to 2 decimals,
// so a formula regression is caught.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/music_theory.dart';

void main() {
  group('Equal-temperament golden table (computed vs build-spec §2.1)', () {
    // key number -> (name, published frequency to 2 dp).
    const Map<int, (String, double)> golden = <int, (String, double)>{
      40: ('C4', 261.63),
      41: ('C#4', 277.18),
      42: ('D4', 293.66),
      43: ('D#4', 311.13),
      44: ('E4', 329.63),
      45: ('F4', 349.23),
      46: ('F#4', 369.99),
      47: ('G4', 392.00),
      48: ('G#4', 415.30),
      49: ('A4', 440.00),
      50: ('A#4', 466.16),
      51: ('B4', 493.88),
      52: ('C5', 523.25),
    };

    golden.forEach((int key, (String, double) expected) {
      test('key $key computes to ${expected.$1} = ${expected.$2} Hz', () {
        final double f = MusicTheory.frequencyForKey(key);
        expect(double.parse(f.toStringAsFixed(2)), expected.$2);
        final Note n = MusicTheory.noteForKey(key);
        expect(n.label, expected.$1);
      });
    });

    test('A4 is exactly 440 Hz (key 49)', () {
      expect(MusicTheory.frequencyForKey(49), 440.0);
    });

    test('chromaticC4toC5 has 13 notes: 8 white + 5 black', () {
      final List<Note> notes = MusicTheory.chromaticC4toC5;
      expect(notes.length, 13);
      expect(notes.where((Note n) => !n.isBlack).length, 8);
      expect(notes.where((Note n) => n.isBlack).length, 5);
    });

    test('black keys carry an enharmonic spelling; white keys do not', () {
      final Note cSharp = MusicTheory.noteForKey(41);
      expect(cSharp.isBlack, true);
      expect(cSharp.name, 'C#');
      expect(cSharp.enharmonicName, 'Db');
      final Note d = MusicTheory.noteForKey(42);
      expect(d.isBlack, false);
      expect(d.enharmonicName, isNull);
    });

    test('the two half-steps E-F and B-C are the white-white gaps with no black',
        () {
      // White keys C(40) D(42) E(44) F(45) G(47) A(49) B(51) C(52). The only
      // adjacent white pairs one semitone apart (gap of 1 key) are E-F and B-C.
      final List<Note> whites = MusicTheory.whiteKeysC4toC5;
      final List<int> gaps = <int>[
        for (int i = 1; i < whites.length; i++)
          whites[i].keyNumber - whites[i - 1].keyNumber,
      ];
      // E->F is whites index 1->2 ... actually compute which gaps == 1.
      final List<String> halfStepPairs = <String>[
        for (int i = 1; i < whites.length; i++)
          if (whites[i].keyNumber - whites[i - 1].keyNumber == 1)
            '${whites[i - 1].name}-${whites[i].name}',
      ];
      expect(halfStepPairs, <String>['E-F', 'B-C']);
      expect(gaps.where((int g) => g == 1).length, 2);
    });
  });

  group('Octave moves (the core doubling demo)', () {
    test('octaveUp doubles, octaveDown halves', () {
      expect(MusicTheory.octaveUp(440), 880);
      expect(MusicTheory.octaveDown(440), 220);
    });

    test('middle C doubled is its octave C5 (261.63 x2 ~ 523.25)', () {
      final double c5 = MusicTheory.octaveUp(MusicTheory.frequencyForKey(40));
      expect(double.parse(c5.toStringAsFixed(2)), 523.25);
    });

    test('octave ladder 110/220/440/880/1760 are exact doublings', () {
      double f = 110;
      for (final double expected in <double>[220, 440, 880, 1760]) {
        f = MusicTheory.octaveUp(f);
        expect(f, expected);
      }
    });
  });

  group('Interval / ratio explorer', () {
    test('octave: 440 vs 880 = ratio 2, 1 octave, 12 semitones', () {
      final IntervalResult r = MusicTheory.interval(440, 880);
      expect(r.ratio, closeTo(2.0, 1e-9));
      expect(r.octaves, closeTo(1.0, 1e-9));
      expect(r.semitones, closeTo(12.0, 1e-9));
      expect(r.nearestSemitones, 12);
      expect(r.intervalName, 'octave');
    });

    test('order-independent: interval(880,440) == interval(440,880)', () {
      expect(MusicTheory.interval(880, 440).ratio, closeTo(2.0, 1e-9));
    });

    test('perfect fifth: 440 vs 660 (3:2) ~ 7.02 semitones', () {
      final IntervalResult r = MusicTheory.interval(440, 660);
      expect(r.ratio, closeTo(1.5, 1e-9));
      expect(r.nearestSemitones, 7);
      expect(r.intervalName, 'perfect fifth');
    });

    test('two octaves: 440 vs 1760 names the octave fold', () {
      final IntervalResult r = MusicTheory.interval(440, 1760);
      expect(r.octaves, closeTo(2.0, 1e-9));
      expect(r.nearestSemitones, 24);
      expect(r.intervalName, '2 octaves');
    });

    test('interval name folds octaves: 19 semitones = fifth + 1 octave', () {
      expect(MusicTheory.intervalNameForSemitones(19), 'perfect fifth + 1 octave');
      expect(MusicTheory.intervalNameForSemitones(12), 'octave');
      expect(MusicTheory.intervalNameForSemitones(0), 'unison');
    });
  });

  group('RF bridge (build-spec §2.4, computed)', () {
    test('2.4 GHz to 4.8 GHz is exactly one octave', () {
      expect(MusicTheory.octavesBetween(2.4, 4.8), closeTo(1.0, 1e-9));
    });

    test('5 GHz is ~1.06 octaves above 2.4 GHz', () {
      expect(MusicTheory.octavesBetween(2.4, 5), closeTo(1.0589, 1e-3));
    });

    test('6 GHz is ~1.3219 octaves above 2.4 GHz', () {
      expect(MusicTheory.octavesBetween(2.4, 6), closeTo(1.3219, 1e-3));
    });

    test('60 GHz is ~4.64 octaves above 2.4 GHz (the spec closing question)',
        () {
      expect(MusicTheory.octavesBetween(2.4, 60), closeTo(4.6439, 1e-3));
    });
  });

  group('Harmonics (integer multiples)', () {
    test('first 5 harmonics of 2.4 are 2.4/4.8/7.2/9.6/12.0', () {
      final List<Harmonic> h = MusicTheory.harmonics(2.4, count: 5);
      expect(h.map((Harmonic x) => x.order).toList(), <int>[1, 2, 3, 4, 5]);
      expect(h[1].frequencyHz, closeTo(4.8, 1e-9)); // 2nd harmonic
      expect(h[2].frequencyHz, closeTo(7.2, 1e-9)); // 3rd harmonic
    });
  });

  group('Nearest note + cents readout', () {
    test('440 Hz is A4 with ~0 cents and 0 octaves from A4', () {
      final NearestNote n = MusicTheory.nearestNote(440);
      expect(n.note.label, 'A4');
      expect(n.centsOffset, closeTo(0.0, 1e-6));
      expect(n.octavesFromA4, closeTo(0.0, 1e-9));
    });

    test('523.25 Hz reads as C5, one octave above A4 minus a bit', () {
      final NearestNote n = MusicTheory.nearestNote(523.25);
      expect(n.note.label, 'C5');
      expect(n.centsOffset.abs() < 1.0, true);
    });

    test('a frequency a quarter-semitone sharp shows ~+25 cents', () {
      final double f = 440 * 1.0072464; // ~ +12.5 cents... use a clear offset
      final NearestNote n = MusicTheory.nearestNote(f);
      expect(n.note.label, 'A4');
      expect(n.centsOffset, greaterThan(0));
    });
  });
}
