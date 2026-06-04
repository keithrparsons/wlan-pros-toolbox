// DTMF tone synthesis — pure Dart, no Flutter, no audio engine.
//
// Batch 4c. DTMF (Dual-Tone Multi-Frequency, "Touch-Tone") encodes each key as
// the SUM of two sine waves: one from the LOW group (the key's row) and one
// from the HIGH group (the key's column). The standard grid (ITU-T Q.23):
//
//                1209 Hz  1336 Hz  1477 Hz  1633 Hz
//        697 Hz    1        2        3        A
//        770 Hz    4        5        6        B
//        852 Hz    7        8        9        C
//        941 Hz    *        0        #        D
//
// This module owns the frequency table and a pure PCM synthesizer that returns
// the raw 16-bit signed mono samples for a key. The audio engine (just_audio,
// behind a seam) plays those bytes; the synthesis here is unit-testable with no
// platform dependency.

import 'dart:math' as math;
import 'dart:typed_data';

/// A DTMF key and its two component frequencies (low group + high group, Hz).
class DtmfKey {
  const DtmfKey({
    required this.label,
    required this.lowHz,
    required this.highHz,
  });

  /// The key glyph as shown on the keypad ("1".."9", "0", "*", "#", "A".."D").
  final String label;

  /// Low-group frequency (the row): 697 / 770 / 852 / 941 Hz.
  final double lowHz;

  /// High-group frequency (the column): 1209 / 1336 / 1477 / 1633 Hz.
  final double highHz;
}

/// The DTMF standard. Low-group rows and high-group columns, then the 16-key
/// grid built from their intersection.
class Dtmf {
  Dtmf._();

  /// Low-group frequencies (rows), top to bottom.
  static const List<double> lowGroup = <double>[697, 770, 852, 941];

  /// High-group frequencies (columns), left to right.
  static const List<double> highGroup = <double>[1209, 1336, 1477, 1633];

  /// The 16-key grid in row-major order (the labels in each keypad row).
  static const List<List<String>> grid = <List<String>>[
    <String>['1', '2', '3', 'A'],
    <String>['4', '5', '6', 'B'],
    <String>['7', '8', '9', 'C'],
    <String>['*', '0', '#', 'D'],
  ];

  /// Standard sample rate for telephony-band audio (Hz).
  static const int sampleRate = 8000;

  /// Default tone duration when a key is tapped (ms).
  static const int defaultDurationMs = 200;

  /// All 16 keys, keyed by label, with their low/high frequencies resolved from
  /// the grid position.
  static final Map<String, DtmfKey> keys = _buildKeys();

  static Map<String, DtmfKey> _buildKeys() {
    final Map<String, DtmfKey> out = <String, DtmfKey>{};
    for (int r = 0; r < grid.length; r++) {
      for (int c = 0; c < grid[r].length; c++) {
        final String label = grid[r][c];
        out[label] = DtmfKey(
          label: label,
          lowHz: lowGroup[r],
          highHz: highGroup[c],
        );
      }
    }
    return out;
  }

  /// Look up a key by its label, or null if not a DTMF key.
  static DtmfKey? keyFor(String label) => keys[label];

  /// Synthesize the raw 16-bit signed little-endian mono PCM samples for [key],
  /// [durationMs] long at [sampleRate], as the SUM of the two group sines.
  ///
  /// Each component is at half amplitude (0.5) so their sum never clips the
  /// 16-bit range. A short linear fade-in / fade-out (5 ms) suppresses the
  /// click that an abrupt start/stop of a tone produces.
  static Int16List synthesize(
    DtmfKey key, {
    int durationMs = defaultDurationMs,
    int sampleRate = Dtmf.sampleRate,
  }) {
    final int sampleCount = (sampleRate * durationMs / 1000).round();
    final Int16List samples = Int16List(sampleCount);

    final double twoPiLow = 2 * math.pi * key.lowHz / sampleRate;
    final double twoPiHigh = 2 * math.pi * key.highHz / sampleRate;

    // 5 ms cosine-ish linear ramp on each end to kill the click.
    final int rampSamples = math.min(
      (sampleRate * 5 / 1000).round(),
      sampleCount ~/ 2,
    );

    for (int i = 0; i < sampleCount; i++) {
      final double sample =
          0.5 * math.sin(twoPiLow * i) + 0.5 * math.sin(twoPiHigh * i);

      double gain = 1.0;
      if (rampSamples > 0) {
        if (i < rampSamples) {
          gain = i / rampSamples;
        } else if (i >= sampleCount - rampSamples) {
          gain = (sampleCount - 1 - i) / rampSamples;
        }
      }

      // Scale to 16-bit signed range with a hair of headroom (0.95).
      final int value = (sample * gain * 0.95 * 32767).round();
      samples[i] = value.clamp(-32768, 32767);
    }
    return samples;
  }

  /// Wrap raw 16-bit signed mono PCM [samples] in a 44-byte canonical WAV
  /// header so a generic audio player (just_audio) can decode them without a
  /// codec. Mono, [sampleRate] Hz, 16-bit. Returns the full WAV byte stream.
  static Uint8List wavFromPcm(
    Int16List samples, {
    int sampleRate = Dtmf.sampleRate,
  }) {
    const int channels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final int blockAlign = channels * bitsPerSample ~/ 8;
    final int dataBytes = samples.length * 2;
    final int fileSize = 44 + dataBytes;

    final BytesBuilder b = BytesBuilder();
    void writeString(String s) => b.add(s.codeUnits);
    void writeUint32(int v) => b.add(<int>[
          v & 0xFF,
          (v >> 8) & 0xFF,
          (v >> 16) & 0xFF,
          (v >> 24) & 0xFF,
        ]);
    void writeUint16(int v) => b.add(<int>[v & 0xFF, (v >> 8) & 0xFF]);

    // RIFF header.
    writeString('RIFF');
    writeUint32(fileSize - 8);
    writeString('WAVE');
    // fmt chunk.
    writeString('fmt ');
    writeUint32(16); // PCM fmt chunk size
    writeUint16(1); // audio format = PCM
    writeUint16(channels);
    writeUint32(sampleRate);
    writeUint32(byteRate);
    writeUint16(blockAlign);
    writeUint16(bitsPerSample);
    // data chunk.
    writeString('data');
    writeUint32(dataBytes);
    // Samples, little-endian.
    final ByteData pcm = ByteData(dataBytes);
    for (int i = 0; i < samples.length; i++) {
      pcm.setInt16(i * 2, samples[i], Endian.little);
    }
    b.add(pcm.buffer.asUint8List());

    return b.toBytes();
  }

  /// Convenience: the playable WAV bytes for [key] at [durationMs].
  static Uint8List wavForKey(
    DtmfKey key, {
    int durationMs = defaultDurationMs,
    int sampleRate = Dtmf.sampleRate,
  }) {
    final Int16List pcm = synthesize(
      key,
      durationMs: durationMs,
      sampleRate: sampleRate,
    );
    return wavFromPcm(pcm, sampleRate: sampleRate);
  }
}
