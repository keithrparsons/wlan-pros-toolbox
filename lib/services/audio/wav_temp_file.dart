// Temp-file WAV sink for the Windows audio playback path.
//
// just_audio's first-party backends (iOS / macOS / Android / web) play the
// generated tones straight from an in-memory StreamAudioSource. The community
// Windows federated implementation (just_audio_windows, Media Foundation) does
// NOT support StreamAudioSource — it only plays file / asset / URL sources. So
// on Windows the generated WAV bytes are written to a temp file and played via
// AudioSource.uri(Uri.file(...)). This helper owns that single temp file and
// its lifecycle (write-replaces-previous, plus cleanup on dispose) so neither
// player leaks files.
//
// Web safety: dart:io File / Directory do not exist on the web target, so the
// real implementation lives in wav_temp_file_io.dart behind a conditional
// export. The web build gets wav_temp_file_stub.dart instead (it is never
// reached at runtime — the platform branch in the players only takes the
// temp-file path on Windows, which is never web).
//
// GL-008: local filesystem only — no subprocess, no network.
export 'wav_temp_file_stub.dart' if (dart.library.io) 'wav_temp_file_io.dart';
