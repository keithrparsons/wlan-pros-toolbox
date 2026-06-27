// Native (dart:io) implementation of [WavTempFile] — the Windows playback path.
// See wav_temp_file.dart for why this exists.

import 'dart:io';
import 'dart:typed_data';

/// Writes generated WAV bytes to a single reusable temp file and hands back a
/// `file:` URI just_audio_windows can play. Each [write] replaces (and deletes)
/// the previous file, so a rapid run of taps or a tone sequence never piles up
/// temp files; [cleanup] removes the last one on dispose.
class WavTempFile {
  WavTempFile(this.tag);

  /// A short label baked into the filename so DTMF and Morse temp files are
  /// distinguishable on disk (e.g. `wlanpros_dtmf_...wav`).
  final String tag;

  File? _file;

  /// Whether a temp file is currently on disk (exposed for tests).
  bool get hasFile => _file != null;

  /// Write [wav] to a fresh temp file (deleting any prior one) and return its
  /// `file:` URI. The filename is unique per call so a player that is mid-read
  /// on the old file is never racing the new write.
  Future<Uri> write(Uint8List wav) async {
    await cleanup();
    final String name =
        'wlanpros_${tag}_${DateTime.now().microsecondsSinceEpoch}.wav';
    final File file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$name',
    );
    await file.writeAsBytes(wav, flush: true);
    _file = file;
    return file.uri;
  }

  /// Delete the current temp file, if any. Safe to call repeatedly; swallows a
  /// missing-file error so dispose never throws.
  Future<void> cleanup() async {
    final File? f = _file;
    _file = null;
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Best-effort: a temp file the OS already reclaimed is not an error.
    }
  }
}
