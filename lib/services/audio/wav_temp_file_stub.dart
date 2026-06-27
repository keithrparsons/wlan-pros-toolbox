// Web stub for [WavTempFile]. The web target has no dart:io filesystem, but it
// also never takes the temp-file playback path (that branch is Windows-only and
// Windows is never web), so these methods are unreachable at runtime and exist
// only to satisfy the conditional export in wav_temp_file.dart.

import 'dart:typed_data';

/// Web stand-in matching the native [WavTempFile] shape. Never reached at
/// runtime — the web build plays tones via just_audio's in-memory
/// StreamAudioSource, not a temp file.
class WavTempFile {
  WavTempFile(this.tag);

  final String tag;

  bool get hasFile => false;

  Future<Uri> write(Uint8List wav) async => throw UnsupportedError(
        'WavTempFile is native-only; the web build uses StreamAudioSource.',
      );

  Future<void> cleanup() async {}
}
