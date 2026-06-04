// Tests for the DTMF synthesis model (lib/data/dtmf.dart).
//
// Verifies the standard ITU-T Q.23 frequency grid (each key = a low-group row
// + a high-group column), the PCM sample count/range, and the WAV header the
// playback engine consumes. Pure math — no audio engine, no widget pump.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/dtmf.dart';

void main() {
  group('DTMF frequency grid (ITU-T Q.23)', () {
    test('all 16 keys are present', () {
      expect(Dtmf.keys.length, 16);
      for (final String label in <String>[
        '1', '2', '3', 'A', //
        '4', '5', '6', 'B', //
        '7', '8', '9', 'C', //
        '*', '0', '#', 'D', //
      ]) {
        expect(Dtmf.keyFor(label), isNotNull, reason: 'missing key $label');
      }
    });

    test('key 1 = 697 + 1209 Hz', () {
      final DtmfKey k = Dtmf.keyFor('1')!;
      expect(k.lowHz, 697);
      expect(k.highHz, 1209);
    });

    test('key 5 = 770 + 1336 Hz (center)', () {
      final DtmfKey k = Dtmf.keyFor('5')!;
      expect(k.lowHz, 770);
      expect(k.highHz, 1336);
    });

    test('key 0 = 941 + 1336 Hz', () {
      final DtmfKey k = Dtmf.keyFor('0')!;
      expect(k.lowHz, 941);
      expect(k.highHz, 1336);
    });

    test('key # = 941 + 1477 Hz', () {
      final DtmfKey k = Dtmf.keyFor('#')!;
      expect(k.lowHz, 941);
      expect(k.highHz, 1477);
    });

    test('key D = 941 + 1633 Hz (the fourth-column extension)', () {
      final DtmfKey k = Dtmf.keyFor('D')!;
      expect(k.lowHz, 941);
      expect(k.highHz, 1633);
    });

    test('low group is 697/770/852/941, high group 1209/1336/1477/1633', () {
      expect(Dtmf.lowGroup, <double>[697, 770, 852, 941]);
      expect(Dtmf.highGroup, <double>[1209, 1336, 1477, 1633]);
    });

    test('every key combines exactly one low-group + one high-group freq', () {
      for (final DtmfKey k in Dtmf.keys.values) {
        expect(Dtmf.lowGroup, contains(k.lowHz));
        expect(Dtmf.highGroup, contains(k.highHz));
      }
    });

    test('an unknown label returns null (not a DTMF key)', () {
      expect(Dtmf.keyFor('E'), isNull);
      expect(Dtmf.keyFor('+'), isNull);
    });
  });

  group('PCM synthesis', () {
    test('sample count matches duration × sample rate', () {
      final Int16List s = Dtmf.synthesize(
        Dtmf.keyFor('5')!,
        durationMs: 200,
        sampleRate: 8000,
      );
      expect(s.length, 1600); // 8000 * 0.2
    });

    test('all samples stay within the 16-bit signed range', () {
      final Int16List s = Dtmf.synthesize(Dtmf.keyFor('1')!);
      for (final int v in s) {
        expect(v, inInclusiveRange(-32768, 32767));
      }
    });

    test('the tone has non-trivial amplitude in its body (not silence)', () {
      final Int16List s = Dtmf.synthesize(Dtmf.keyFor('9')!);
      // Look at the peak across the body (past the fade ramps). A single sample
      // can land on a zero-crossing of the two-sine sum, so check the max, not
      // one point.
      int peak = 0;
      for (int i = s.length ~/ 4; i < s.length * 3 ~/ 4; i++) {
        if (s[i].abs() > peak) peak = s[i].abs();
      }
      expect(peak, greaterThan(10000));
    });

    test('fade-in starts near zero (click suppression)', () {
      final Int16List s = Dtmf.synthesize(Dtmf.keyFor('2')!);
      expect(s.first.abs(), lessThan(500));
    });
  });

  group('WAV wrapping', () {
    test('produces a 44-byte header + PCM data of the right size', () {
      final Int16List pcm = Dtmf.synthesize(
        Dtmf.keyFor('7')!,
        durationMs: 100,
        sampleRate: 8000,
      );
      final Uint8List wav = Dtmf.wavFromPcm(pcm, sampleRate: 8000);
      expect(wav.length, 44 + pcm.length * 2);
    });

    test('starts with the RIFF/WAVE/fmt/data chunk markers', () {
      final Uint8List wav = Dtmf.wavForKey(Dtmf.keyFor('5')!);
      String at(int i, int n) => String.fromCharCodes(wav.sublist(i, i + n));
      expect(at(0, 4), 'RIFF');
      expect(at(8, 4), 'WAVE');
      expect(at(12, 4), 'fmt ');
      expect(at(36, 4), 'data');
    });

    test('declares mono, 16-bit, 8000 Hz in the fmt chunk', () {
      final Uint8List wav = Dtmf.wavForKey(Dtmf.keyFor('5')!);
      final ByteData bd = ByteData.sublistView(wav);
      expect(bd.getUint16(20, Endian.little), 1); // PCM
      expect(bd.getUint16(22, Endian.little), 1); // channels = mono
      expect(bd.getUint32(24, Endian.little), 8000); // sample rate
      expect(bd.getUint16(34, Endian.little), 16); // bits per sample
    });
  });
}
