// Native (iOS / macOS / Android) body for the PDF share seam.
//
// Reads the bundled asset bytes, writes them to a temp file under the clean
// human filename, and hands the temp file to the OS share sheet. The native
// share sheet covers Save-to-Files / AirDrop / Mail / Print. No macOS
// entitlement change is needed (share sheet, not NSSavePanel).
//
// This file is selected by the conditional import in pdf_download.dart on every
// target that has dart:io (iOS/macOS/Android/Windows/Linux). It is never
// compiled on web, so importing share_plus + path_provider here does not pull
// their platform channels into the web build.

import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'pdf_download.dart' show ShareOrigin;

/// Generic native body: copies the bundled [assetPath] bytes to a temp file
/// under the clean human [filename], then hands it to the OS share sheet typed
/// as [mimeType]. Same macOS-sandbox-safe temp-dir handling as the PDF path
/// (the per-bundle Caches dir must be created before writing). Throws on a
/// load/write failure so the caller surfaces the honest error path.
Future<void> shareAssetImpl({
  required String assetPath,
  required String filename,
  required String mimeType,
  ShareOrigin? shareOrigin,
}) async {
  // 1. Read the bundled bytes (throws on a missing/corrupt asset).
  final bytes = await rootBundle.load(assetPath);

  // 2. Write them to a temp file under the clean human filename. iOS/macOS show
  //    this filename in the share sheet, so it must be the friendly one.
  //    On the macOS App Sandbox the per-bundle Caches dir that
  //    getTemporaryDirectory() points at does not exist until something creates
  //    it, so writing straight into it throws PathNotFoundException (the share
  //    button appeared to "do nothing"). Ensure the directory exists first.
  final Directory tmpDir = await getTemporaryDirectory();
  await tmpDir.create(recursive: true);
  final File tmpFile = File('${tmpDir.path}/$filename');
  await tmpFile.writeAsBytes(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    flush: true,
  );

  // 3. Hand the temp file to the OS share sheet. On iPad/macOS the popover must
  //    anchor to a source rect or the platform throws; pass the button's rect.
  await Share.shareXFiles(
    <XFile>[XFile(tmpFile.path, mimeType: mimeType)],
    sharePositionOrigin: shareOrigin == null
        ? null
        : Rect.fromLTWH(
            shareOrigin.left,
            shareOrigin.top,
            shareOrigin.width,
            shareOrigin.height,
          ),
  );
}
