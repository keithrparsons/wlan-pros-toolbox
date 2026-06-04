// Native (iOS / macOS / Android) body for the QR PNG share seam.
//
// Writes the rendered QR PNG bytes to a temp file under a clean filename and
// hands it to the OS share sheet via share_plus. No macOS entitlement change
// (share sheet, not NSSavePanel) — identical to the PDF-card share path. The
// per-bundle Caches dir getTemporaryDirectory() points at may not exist yet
// under the macOS App Sandbox, so we create it before writing (the same
// PathNotFoundException fix the PDF share carries).

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes [png] to a temp file named [filename], then shares it.
Future<void> shareQrPngImpl({
  required Uint8List png,
  required String filename,
}) async {
  final Directory tmpDir = await getTemporaryDirectory();
  await tmpDir.create(recursive: true);
  final File tmpFile = File('${tmpDir.path}/$filename');
  await tmpFile.writeAsBytes(png, flush: true);

  await Share.shareXFiles(
    <XFile>[XFile(tmpFile.path, mimeType: 'image/png')],
  );
}
