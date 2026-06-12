// Morse audio playback — generates one WAV for a whole message and plays it
// once via just_audio. Reuses the in-memory StreamAudioSource pattern proven by
// the DTMF player (lib/services/audio/dtmf_player.dart): no temp file, no asset.
//
// Why one buffer for the whole message instead of per-symbol sequencing: a
// Morse transmission is a single continuous on/off keying of ONE tone, so
// synthesizing the entire envelope to one WAV and playing it once is both
// simpler and gives a smoother, gap-accurate result than scheduling N tiny
// clips. The pure timing model (Morse.segments) and the PCM synthesis below are
// unit-testable; this service only streams the bytes.
//
// GL-008: no subprocess, no network, no cleartext HTTP — local audio only.

// StreamAudioSource is just_audio's documented public API for serving audio
// from in-memory bytes, but the maintainer marks it @experimental. We use it
// deliberately (same call the DTMF player makes) and accept the API-stability
// risk; the alternative (a temp WAV per play) adds a filesystem touch we do not
// want. Suppress the file-wide experimental warning rather than per-line.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import '../../data/morse.dart';

/// An in-memory [StreamAudioSource] that serves a fixed WAV byte buffer, so
/// just_audio can decode generated Morse audio without a temp file or asset.
class _BytesAudioSource extends StreamAudioSource {
  _BytesAudioSource(this._bytes) : super(tag: 'morse');

  final Uint8List _bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final int s = start ?? 0;
    final int e = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: e - s,
      offset: s,
      stream: Stream<List<int>>.value(_bytes.sublist(s, e)),
      contentType: 'audio/wav',
    );
  }
}

/// Synthesizes Morse audio (pure Dart) and plays it through one reused
/// [AudioPlayer]. [dispose] releases the player.
class MorsePlayer {
  MorsePlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  bool _disposed = false;

  /// Telephony-band sample rate (Hz) — plenty for a single sine tone.
  static const int sampleRate = 8000;

  /// Sidetone frequency (Hz). 600 Hz is a common Morse sidetone pitch.
  static const double toneHz = 600;

  /// Whether playback is currently active.
  bool get isPlaying => _player.playing;

  /// Synthesize [text] as Morse audio at [wordsPerMinute] and play it once.
  /// A no-op if [text] has no encodable characters. Stops any in-flight
  /// playback first so a re-tap restarts cleanly.
  Future<void> play(String text, {int wordsPerMinute = 15}) async {
    if (_disposed) return;
    final Uint8List? wav = wavForText(text, wordsPerMinute: wordsPerMinute);
    if (wav == null) return;
    await _player.stop();
    await _player.setLoopMode(LoopMode.off);
    await _player.setAudioSource(_BytesAudioSource(wav));
    await _player.play();
  }

  /// Stop playback.
  Future<void> stop() async {
    if (_disposed) return;
    await _player.stop();
  }

  /// Release the underlying player. Call from the screen's dispose().
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _player.dispose();
  }

  // ── Pure synthesis (no audio engine — unit-testable) ──────────────────────

  /// The full playable WAV bytes for [text] at [wordsPerMinute], or null when
  /// the text has no encodable characters (so callers can early-out).
  static Uint8List? wavForText(String text, {int wordsPerMinute = 15}) {
    final Int16List? pcm = synthesize(text, wordsPerMinute: wordsPerMinute);
    if (pcm == null) return null;
    return wavFromPcm(pcm);
  }

  /// Synthesize the raw 16-bit signed mono PCM for [text]'s Morse envelope, or
  /// null if there is nothing to play. ON segments are a [toneHz] sine; OFF
  /// segments are silence. A short (5 ms) linear ramp on each ON edge kills the
  /// key click.
  static Int16List? synthesize(String text, {int wordsPerMinute = 15}) {
    final List<MorseSegment> segs = Morse.segments(text);
    if (segs.isEmpty) return null;

    final int unitMs = Morse.unitMs(wordsPerMinute);
    final int unitSamples = (sampleRate * unitMs / 1000).round();
    if (unitSamples <= 0) return null;

    final int total =
        segs.fold<int>(0, (int sum, MorseSegment s) => sum + s.units) *
            unitSamples;
    final Int16List out = Int16List(total);

    final double twoPiF = 2 * math.pi * toneHz / sampleRate;
    final int ramp = math.min((sampleRate * 5 / 1000).round(), unitSamples ~/ 2);

    int cursor = 0;
    for (final MorseSegment seg in segs) {
      final int len = seg.units * unitSamples;
      if (seg.on) {
        for (int i = 0; i < len; i++) {
          double gain = 1.0;
          if (ramp > 0) {
            if (i < ramp) {
              gain = i / ramp;
            } else if (i >= len - ramp) {
              gain = (len - 1 - i) / ramp;
            }
          }
          final double sample = math.sin(twoPiF * i) * gain * 0.9;
          out[cursor + i] = (sample * 32767).round().clamp(-32768, 32767);
        }
      }
      // OFF segments stay zero (silence) from Int16List's default fill.
      cursor += len;
    }
    return out;
  }

  /// Wrap raw 16-bit signed mono PCM [samples] in a 44-byte canonical WAV
  /// header so just_audio can decode them without a codec. Mono, [sampleRate]
  /// Hz, 16-bit.
  static Uint8List wavFromPcm(Int16List samples) {
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

    writeString('RIFF');
    writeUint32(fileSize - 8);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16);
    writeUint16(1); // PCM
    writeUint16(channels);
    writeUint32(sampleRate);
    writeUint32(byteRate);
    writeUint16(blockAlign);
    writeUint16(bitsPerSample);
    writeString('data');
    writeUint32(dataBytes);

    final ByteData pcm = ByteData(dataBytes);
    for (int i = 0; i < samples.length; i++) {
      pcm.setInt16(i * 2, samples[i], Endian.little);
    }
    b.add(pcm.buffer.asUint8List());

    return b.toBytes();
  }
}
