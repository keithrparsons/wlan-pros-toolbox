// QR PNG share seam — one entry point, two platform bodies.
//
// Mirrors the pdf_download.dart pattern: a conditional import keeps the
// web-only symbols out of the native compile and vice versa. The QR screen
// rasterizes its white tile to PNG bytes (so the shared image is the SAME
// dark-on-white QR the user sees, GL-003 §8.19), then hands those bytes here.
//   * Native (iOS / macOS / Android): write the bytes to a temp file under a
//     clean filename, hand it to the OS share sheet via share_plus. NO macOS
//     entitlement change (share sheet, not NSSavePanel) — same as the PDF cards.
//   * Web: a browser anchor download of the PNG blob.

import 'dart:typed_data';

import 'qr_share_io.dart'
    if (dart.library.js_interop) 'qr_share_web.dart' as impl;

/// Shares (native) or downloads (web) the rendered QR [png] bytes. [label] is
/// the encoded text — used only to derive a stable, human filename. Returns
/// normally on success; throws on a write/share failure so the caller can
/// surface the honest error path.
Future<void> shareQrPng({
  required Uint8List png,
  required String label,
}) {
  return impl.shareQrPngImpl(png: png, filename: 'WLAN-Pros-QR-Code.png');
}
