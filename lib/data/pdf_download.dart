// PDF share/download seam — one clean entry point, two platform bodies.
//
// Built to Pax's researched approach (Ticket 4):
//   * Native (iOS / macOS / Android): copy the bundled asset bytes to a temp
//     file in getTemporaryDirectory() under a clean human filename, then hand
//     it to the OS share sheet via Share.shareXFiles. Covers Save-to-Files /
//     AirDrop / Mail / Print. NO macOS entitlement change (share sheet, not
//     NSSavePanel). You cannot share a bundle asset path directly — the
//     temp-file copy is required.
//   * Web: a browser anchor download — fetch the asset bytes, make a blob URL,
//     click a download anchor with the clean filename.
//
// The web body lives in pdf_download_web.dart (uses package:web/dart:js_interop)
// and the native body in pdf_download_io.dart. A conditional import keeps the
// web-only symbols out of the native compile and vice versa, so neither target
// pulls code it cannot build. This file owns:
//   * the pure filename helper (unit-tested directly — no platform), and
//   * the `sharePdf` dispatch contract (delegated to the conditional body).

import 'pdf_download_io.dart'
    if (dart.library.js_interop) 'pdf_download_web.dart' as impl;

/// Builds a clean, human-readable download filename from a card title.
///
/// Rules (per Ticket 4 / the card titles): prefix `WLAN-Pros-`, slugify the
/// title to kebab-case, append `.pdf`. Parentheses are stripped, runs of
/// non-alphanumeric characters collapse to a single hyphen, and leading/trailing
/// hyphens are trimmed. Examples:
///   'Top 20 Wi-Fi Checklist'                  -> WLAN-Pros-Top-20-Wi-Fi-Checklist.pdf
///   'Extended Checklist (Non-Advertised Items)' -> WLAN-Pros-Extended-Checklist-Non-Advertised-Items.pdf
///   '2.4 GHz Channel Allocations'             -> WLAN-Pros-2-4-GHz-Channel-Allocations.pdf
///
/// The output contains only `[A-Za-z0-9-]` and the `.pdf` suffix, so it is safe
/// on every target filesystem and as a Content-Disposition filename.
String pdfDownloadFilename(String title) {
  // Strip parentheses entirely (keep their inner words), then replace every run
  // of non-alphanumeric characters with a single hyphen.
  final String withoutParens = title.replaceAll(RegExp(r'[()]'), ' ');
  final String slug = withoutParens
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return 'WLAN-Pros-$slug.pdf';
}

/// Shares (native) or downloads (web) the bundled PDF at [assetPath] under the
/// clean filename derived from [title]. On iPad/macOS the share popover anchors
/// to [shareOrigin] (the share button's global rect) to satisfy the platform's
/// popover-source requirement; pass `null` to let the platform pick a default.
///
/// Returns normally on success; throws on a load/share failure so the caller can
/// surface the honest error path.
Future<void> sharePdf({
  required String assetPath,
  required String title,
  ShareOrigin? shareOrigin,
}) {
  return impl.sharePdfImpl(
    assetPath: assetPath,
    filename: pdfDownloadFilename(title),
    title: title,
    shareOrigin: shareOrigin,
  );
}

/// A platform-agnostic rectangle for the iPad/macOS share-popover source.
/// Carried so the screen does not have to import `dart:ui` Rect into the seam.
class ShareOrigin {
  const ShareOrigin(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;
}
