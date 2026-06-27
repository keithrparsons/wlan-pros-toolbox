// Tests for WavTempFile — the Windows audio playback temp-file sink. Runs on
// the macOS test host (dart:io available), exercising the native impl that
// Windows uses: write WAV bytes to a temp file, replace-and-delete on rewrite,
// and clean up on dispose. No audio engine is involved (pure filesystem logic).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/audio/wav_temp_file.dart';

void main() {
  group('WavTempFile', () {
    test('write() creates a file holding exactly the given bytes', () async {
      final WavTempFile sink = WavTempFile('dtmf');
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);

      final Uri uri = await sink.write(bytes);
      final File file = File.fromUri(uri);

      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), equals(bytes));
      expect(sink.hasFile, isTrue);

      await sink.cleanup();
    });

    test('filename carries the tag and the .wav extension', () async {
      final WavTempFile sink = WavTempFile('morse');
      final Uri uri = await sink.write(Uint8List.fromList(<int>[0]));

      final String name = uri.pathSegments.last;
      expect(name, contains('morse'));
      expect(name, endsWith('.wav'));

      await sink.cleanup();
    });

    test('write() replaces and deletes the previous temp file', () async {
      final WavTempFile sink = WavTempFile('dtmf');

      final Uri first = await sink.write(Uint8List.fromList(<int>[9, 9]));
      final File firstFile = File.fromUri(first);
      expect(await firstFile.exists(), isTrue);

      final Uri second = await sink.write(Uint8List.fromList(<int>[7]));
      final File secondFile = File.fromUri(second);

      // A fresh, distinct file...
      expect(second, isNot(equals(first)));
      expect(await secondFile.exists(), isTrue);
      // ...and the old one is gone (no pile-up across rapid taps / sequences).
      expect(await firstFile.exists(), isFalse);

      await sink.cleanup();
    });

    test('cleanup() deletes the file and is safe to call twice', () async {
      final WavTempFile sink = WavTempFile('dtmf');
      final Uri uri = await sink.write(Uint8List.fromList(<int>[1]));
      final File file = File.fromUri(uri);

      await sink.cleanup();
      expect(await file.exists(), isFalse);
      expect(sink.hasFile, isFalse);

      // Idempotent: a second cleanup (e.g. dispose after stop) must not throw.
      await sink.cleanup();
      expect(sink.hasFile, isFalse);
    });

    test('cleanup() with no prior write is a no-op', () async {
      final WavTempFile sink = WavTempFile('morse');
      expect(sink.hasFile, isFalse);
      await sink.cleanup(); // must not throw
      expect(sink.hasFile, isFalse);
    });
  });
}
