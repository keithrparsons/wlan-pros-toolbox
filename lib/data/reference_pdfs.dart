// Convention-based resolution for the Field & Trade Reference PLATE PDFs, with
// graceful degradation.
//
// Each field-reference screen (enclosure-ratings, hazardous-locations, ... and
// the LED Decoder's master comparison plate) ships Vera's print-format plate as
// a bundled vector PDF at `assets/reference-pdf/<tool-id>.pdf`. The screen
// offers it as a "Download PDF" (save/share) via the same seam the PDF reference
// cards use (pdf_download.dart -> sharePdf), so the user can save or AirDrop the
// full-resolution plate for print.
//
// Mirrors [ReferenceImages] exactly (the proven per-asset resolver): read the
// AssetManifest once at startup, cache the set of files Flutter actually bundled,
// and answer `isBundled(id)` with zero I/O thereafter. The download control gates
// on `isBundled` before ever handing `sharePdf` a path, so a missing or unbundled
// PDF NEVER surfaces a broken control — the control is simply omitted and the
// screen's native text tables (and the on-screen plate) still read end-to-end.
//
// The PDF is the DOWNLOAD companion to the on-screen raster plate; the two are
// resolved independently (a screen can bundle one, both, or neither) so the
// download degrades separately from the inline image.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the Field & Trade Reference plate PDFs
/// (`assets/reference-pdf/<id>.pdf`), gated on the build-time asset manifest so a
/// missing file degrades silently (the download control self-omits).
class ReferencePdfs {
  ReferencePdfs._();

  static const String _dir = 'assets/reference-pdf';

  /// Conventional asset path for [id] (a catalog tool id, or the LED master
  /// comparison plate id). No existence guarantee — gate on [isBundled] before
  /// handing this to `sharePdf`.
  static String pathFor(String id) => '$_dir/$id.pdf';

  /// Built reference-PDF paths, populated once from the AssetManifest. `null`
  /// until the first [ensureLoaded] completes; treated as "nothing built".
  static Set<String>? _bundled;

  /// `true` only when the build actually bundled this id's PDF. Gate on this
  /// before rendering a download control that would hand [pathFor] to `sharePdf`.
  static bool isBundled(String id) => _bundled?.contains(pathFor(id)) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. Call
  /// during app startup so the synchronous [isBundled] check has data; if it has
  /// not run yet, [isBundled] returns `false` and the download control is simply
  /// omitted, so a race only delays a download affordance, never crashes.
  static Future<void> ensureLoaded() async {
    if (_bundled != null) return;
    WidgetsFlutterBinding.ensureInitialized();
    final AssetManifest manifest = await AssetManifest.loadFromAssetBundle(
      rootBundle,
    );
    _bundled = manifest
        .listAssets()
        .where((String p) => p.startsWith('$_dir/'))
        .toSet();
  }

  /// Test-only override so widget tests can assert the download control renders
  /// when the PDF is present and is omitted when absent. Pass the exact bundled
  /// paths, or an empty set for "nothing built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
