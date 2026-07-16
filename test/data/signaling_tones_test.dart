// Tests for the Telephone Signaling History tone tables and synth
// (lib/data/signaling_tones.dart).
//
// Verifies the canonical ITU-T / Wikipedia Blue Box MF digit pairs (NOT the
// hobbyist ordering), the KP / ST / 2600 Hz framing tones, the US Red Box
// 1700 + 2200 Hz coin patterns and their exact burst timings, plus the PCM
// sample count / range and WAV header the playback engine consumes. Pure math —
// no audio engine, no widget pump.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/signaling_tones.dart';

void main() {
  group('Blue Box — R1 MF table (ITU-T / Wikipedia canonical)', () {
    SignalingTone byLabel(String label) =>
        SignalingTones.blueBox.firstWhere((SignalingTone t) => t.label == label);

    test('the six MF frequencies are 700/900/1100/1300/1500/1700', () {
      expect(
        SignalingTones.mfFrequencies,
        <double>[700, 900, 1100, 1300, 1500, 1700],
      );
    });

    test('canonical digit pairs (not the repo ordering)', () {
      // The discrepancy the brief flagged: canonical digit 1 = 700 + 900,
      // digit 2 = 700 + 1100. Assert the full canonical set.
      const Map<String, List<double>> expected = <String, List<double>>{
        '1': <double>[700, 900],
        '2': <double>[700, 1100],
        '3': <double>[900, 1100],
        '4': <double>[700, 1300],
        '5': <double>[900, 1300],
        '6': <double>[1100, 1300],
        '7': <double>[700, 1500],
        '8': <double>[900, 1500],
        '9': <double>[1100, 1500],
        '0': <double>[1300, 1500],
      };
      expected.forEach((String digit, List<double> pair) {
        final SignalingTone t = byLabel(digit);
        expect(t.lowHz, pair[0], reason: 'digit $digit low');
        expect(t.highHz, pair[1], reason: 'digit $digit high');
      });
    });

    test('KP = 1100 + 1700, ST = 1500 + 1700', () {
      final SignalingTone kp = byLabel('KP');
      expect(kp.lowHz, 1100);
      expect(kp.highHz, 1700);
      final SignalingTone st = byLabel('ST');
      expect(st.lowHz, 1500);
      expect(st.highHz, 1700);
    });

    test('2600 is a single-frequency supervisory tone', () {
      final SignalingTone t = byLabel('2600');
      expect(t.lowHz, 2600);
      expect(t.highHz, isNull);
      expect(t.isSingleFrequency, isTrue);
    });

    test('every MF digit pair is drawn from the six MF frequencies', () {
      for (final String d in <String>[
        '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', //
      ]) {
        final SignalingTone t = byLabel(d);
        expect(SignalingTones.mfFrequencies, contains(t.lowHz));
        expect(SignalingTones.mfFrequencies, contains(t.highHz));
      }
    });
  });

  group('Red Box: US coin tones (1700 + 2200 Hz)', () {
    SignalingTone coin(String label) =>
        SignalingTones.redBox.firstWhere((SignalingTone t) => t.label == label);

    test('all three coins are the 1700 + 2200 Hz dual tone', () {
      for (final String c in <String>['Nickel', 'Dime', 'Quarter']) {
        final SignalingTone t = coin(c);
        expect(t.lowHz, 1700, reason: '$c low');
        expect(t.highHz, 2200, reason: '$c high');
      }
    });

    test('nickel = one 66 ms burst', () {
      final SignalingTone t = coin('Nickel');
      expect(t.bursts, 1);
      expect(t.burstMs, 66);
    });

    test('dime = two 66 ms bursts, 66 ms apart', () {
      final SignalingTone t = coin('Dime');
      expect(t.bursts, 2);
      expect(t.burstMs, 66);
      expect(t.gapMs, 66);
    });

    test('quarter = five 33 ms bursts, 33 ms apart', () {
      final SignalingTone t = coin('Quarter');
      expect(t.bursts, 5);
      expect(t.burstMs, 33);
      expect(t.gapMs, 33);
    });

    test('highest component (2200 Hz) is under the 8000 Hz Nyquist limit', () {
      // 2200 < 4000, so 8000 Hz reproduces it cleanly — guard the sample rate.
      expect(SignalingTones.sampleRate, 8000);
      expect(2200, lessThan(SignalingTones.sampleRate / 2));
    });
  });

  group('PCM synthesis', () {
    test('single-burst sample count matches duration × sample rate', () {
      final SignalingTone nickel = SignalingTones.redBox
          .firstWhere((SignalingTone t) => t.label == 'Nickel');
      final Int16List s = SignalingTones.synthesize(nickel, sampleRate: 8000);
      // 66 ms × 8000 Hz = 528 samples, one burst, no gap.
      expect(s.length, (8000 * 66 / 1000).round());
    });

    test('multi-burst sample count includes the inter-burst gaps', () {
      final SignalingTone quarter = SignalingTones.redBox
          .firstWhere((SignalingTone t) => t.label == 'Quarter');
      final Int16List s = SignalingTones.synthesize(quarter, sampleRate: 8000);
      final int burst = (8000 * 33 / 1000).round();
      final int gap = (8000 * 33 / 1000).round();
      // 5 bursts + 4 gaps.
      expect(s.length, 5 * burst + 4 * gap);
    });

    test('all samples stay within the 16-bit signed range', () {
      for (final SignalingTone t in <SignalingTone>[
        ...SignalingTones.blueBox,
        ...SignalingTones.redBox,
      ]) {
        final Int16List s = SignalingTones.synthesize(t);
        for (final int v in s) {
          expect(v, inInclusiveRange(-32768, 32767),
              reason: 'tone ${t.label} sample out of range');
        }
      }
    });

    test('a tone has non-trivial amplitude in its first burst body', () {
      final SignalingTone t = SignalingTones.blueBox
          .firstWhere((SignalingTone t) => t.label == '5');
      final Int16List s = SignalingTones.synthesize(t);
      int peak = 0;
      for (int i = s.length ~/ 4; i < s.length * 3 ~/ 4; i++) {
        if (s[i].abs() > peak) peak = s[i].abs();
      }
      expect(peak, greaterThan(10000));
    });

    test('the single-tone 2600 burst is non-silent', () {
      final SignalingTone t = SignalingTones.blueBox
          .firstWhere((SignalingTone t) => t.label == '2600');
      final Int16List s = SignalingTones.synthesize(t);
      int peak = 0;
      for (int i = s.length ~/ 4; i < s.length * 3 ~/ 4; i++) {
        if (s[i].abs() > peak) peak = s[i].abs();
      }
      expect(peak, greaterThan(10000));
    });
  });

  group('WAV wrapping (reuses the DTMF WAV header)', () {
    test('produces a 44-byte header + PCM data of the right size', () {
      final SignalingTone t = SignalingTones.redBox
          .firstWhere((SignalingTone t) => t.label == 'Dime');
      final Int16List pcm = SignalingTones.synthesize(t, sampleRate: 8000);
      final Uint8List wav = SignalingTones.wavForTone(t, sampleRate: 8000);
      expect(wav.length, 44 + pcm.length * 2);
    });

    test('starts with the RIFF/WAVE/fmt/data chunk markers', () {
      final SignalingTone t = SignalingTones.blueBox
          .firstWhere((SignalingTone t) => t.label == 'KP');
      final Uint8List wav = SignalingTones.wavForTone(t);
      String at(int i, int n) => String.fromCharCodes(wav.sublist(i, i + n));
      expect(at(0, 4), 'RIFF');
      expect(at(8, 4), 'WAVE');
      expect(at(12, 4), 'fmt ');
      expect(at(36, 4), 'data');
    });
  });

  group('readout labels', () {
    test('frequency label renders one or two components', () {
      final SignalingTone two = SignalingTones.redBox.first;
      expect(two.frequencyLabel, '1700 Hz + 2200 Hz');
      final SignalingTone one = SignalingTones.blueBox
          .firstWhere((SignalingTone t) => t.label == '2600');
      expect(one.frequencyLabel, '2600 Hz');
    });

    test('timing label renders single vs multi-burst', () {
      final SignalingTone nickel = SignalingTones.redBox
          .firstWhere((SignalingTone t) => t.label == 'Nickel');
      expect(nickel.timingLabel, '66 ms');
      final SignalingTone quarter = SignalingTones.redBox
          .firstWhere((SignalingTone t) => t.label == 'Quarter');
      expect(quarter.timingLabel, '5 × 33 ms, 33 ms apart');
    });
  });
}
