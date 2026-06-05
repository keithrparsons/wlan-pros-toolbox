// Convention-based per-connector photo resolution with graceful degradation,
// plus per-photo alt text and license/courtesy-credit metadata.
//
// The Antenna Connectors reference accepts a real, freely-licensed photo per
// connector WHERE WE ACTUALLY HAVE ONE. Pax vetted every license off the source
// File: page (Deliverables/2026-06-05-antenna-connector-photos/manifest.json):
// the shipped set is 9 photos covering 9 distinct connectors, ALL CC0 / Public
// Domain / "Copyrighted free use" — zero require mandatory attribution, so the
// app carries no legally-required credits section. Courtesy credits are recorded
// here as good practice and surfaced quietly beneath each photo.
//
// HONESTY (GL-005 / the truthfulness mandate): a connector gets a photo ONLY
// when a correctly-licensed, correctly-identified photo exists. The three
// priority connectors with no CC0/PD photo — N-Type, TNC, RP-TNC — get NO photo
// and NO placeholder; they keep their existing line diagram. We never substitute
// a wrongly-licensed (CC BY-SA / NC / ND) image to fill a gap, and never fake a
// photo.
//
// Resolution mirrors ConnectorDiagrams / ToolAssets: read the build-time
// AssetManifest once, cache the set of bundled photo files, answer has(id) with
// zero I/O thereafter. The screen gates on has(id) before handing Image.asset a
// path, so a missing file never throws and never shows a broken-image box.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// License + attribution + alt-text metadata for one bundled connector photo.
class ConnectorPhotoMeta {
  const ConnectorPhotoMeta({
    required this.alt,
    required this.license,
    required this.credit,
    required this.attributionRequired,
  });

  /// Screen-reader alt text describing what the photo shows. Image semantics are
  /// mandatory (GL-003 §8.13) — a photo is never an unlabeled node.
  final String alt;

  /// Human-readable license name (e.g. "CC0 1.0", "Public domain").
  final String license;

  /// Courtesy credit string (uploader / source). Shown quietly beneath the
  /// photo. For the shipped CC0/PD/free-use set this is courtesy-only.
  final String credit;

  /// `true` only when the license legally requires attribution. The shipped set
  /// is all-false (CC0/PD/free-use); the field exists so a future CC-BY photo
  /// can be added and rendered with a mandatory, not optional, credit line.
  final bool attributionRequired;
}

/// Resolves per-connector photos by connector id, gated on the build-time asset
/// manifest so missing files degrade silently, and carries the vetted per-photo
/// license/alt metadata.
class ConnectorPhotos {
  ConnectorPhotos._();

  static const String _dir = 'assets/connector-photos';

  /// Vetted metadata for every bundled photo, keyed by connector id. Source:
  /// Deliverables/2026-06-05-antenna-connector-photos/manifest.json (Pax,
  /// licenses read off each Wikimedia Commons File: page). Only ids present here
  /// AND in the bundle render a photo.
  static const Map<String, ConnectorPhotoMeta> _meta =
      <String, ConnectorPhotoMeta>{
    'rp-sma': ConnectorPhotoMeta(
      alt: 'Photo of an RP-SMA plug, a small threaded coaxial connector.',
      license: 'CC0 1.0',
      credit: 'Markus Bärlocher / Wikimedia Commons (CC0)',
      attributionRequired: false,
    ),
    'rpsma-bulkhead': ConnectorPhotoMeta(
      alt: 'Photo of an RP-SMA bulkhead/panel-mount jack.',
      license: 'CC0 1.0',
      credit: 'Markus Bärlocher / Wikimedia Commons (CC0)',
      attributionRequired: false,
    ),
    'sma': ConnectorPhotoMeta(
      alt: 'Photo comparing an SMA connector (right) with an RP-SMA (left).',
      license: 'Public domain',
      credit: 'Fckw kyle / Wikimedia Commons (public domain)',
      attributionRequired: false,
    ),
    'ufl': ConnectorPhotoMeta(
      alt: 'Photo of a U.FL / I-PEX MHF1 board-level coaxial connector beside a '
          'smaller MHF4.',
      license: 'CC0 1.0',
      credit: 'Mitja Stachowiak / Wikimedia Commons (CC0)',
      attributionRequired: false,
    ),
    'ipex-mhf1': ConnectorPhotoMeta(
      alt: 'Photo of an I-PEX MHF1 (U.FL-equivalent) board-level connector '
          'beside a smaller MHF4.',
      license: 'CC0 1.0',
      credit: 'Mitja Stachowiak / Wikimedia Commons (CC0)',
      attributionRequired: false,
    ),
    'ipex-mhf4': ConnectorPhotoMeta(
      alt: 'Photo of an I-PEX MHF4 (the smaller, left) connector beside a '
          'U.FL/MHF1.',
      license: 'CC0 1.0',
      credit: 'Mitja Stachowiak / Wikimedia Commons (CC0)',
      attributionRequired: false,
    ),
    'mmcx': ConnectorPhotoMeta(
      alt: 'Photo of an MMCX straight male PCB connector.',
      license: 'Public domain',
      credit: 'Cmpter / Wikimedia Commons (public domain)',
      attributionRequired: false,
    ),
    'mcx': ConnectorPhotoMeta(
      alt: 'Photo of an MCX coaxial connector.',
      license: 'Copyrighted free use',
      credit: 'Rainer Zenz / Wikimedia Commons (copyrighted free use)',
      attributionRequired: false,
    ),
    'bnc': ConnectorPhotoMeta(
      alt: 'Photo of a BNC connector, a bayonet-coupling coaxial connector.',
      license: 'Public domain',
      credit: 'Jonas Bergsten / Wikimedia Commons (public domain)',
      attributionRequired: false,
    ),
    '716-din': ConnectorPhotoMeta(
      alt: 'Photo of a 7/16 DIN male connector, a large threaded RF connector.',
      license: 'CC0 1.0',
      credit: 'Jensibua / Wikimedia Commons (CC0)',
      attributionRequired: false,
    ),
  };

  /// Built photo paths, populated once from the AssetManifest. `null` until the
  /// first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// Conventional photo path for [connectorId]. No existence guarantee — gate on
  /// [has] before handing this to `Image.asset`.
  static String path(String connectorId) => '$_dir/$connectorId.jpg';

  /// Vetted metadata for [connectorId], or `null` if we ship no photo for it.
  static ConnectorPhotoMeta? meta(String connectorId) => _meta[connectorId];

  /// `true` only when the build bundled this connector's photo AND we have
  /// vetted metadata (alt + license) for it. Both must hold — a bundled file
  /// with no metadata never renders (no unlabeled, un-licensed image).
  static bool has(String connectorId) =>
      _meta.containsKey(connectorId) &&
      (_bundled?.contains(path(connectorId)) ?? false);

  /// Load and cache the asset manifest once. Safe to call repeatedly. Call at
  /// app startup so the synchronous [has] checks have data; if it has not run
  /// yet, [has] returns `false` and the photo slot is omitted — a race only
  /// delays a photo, never crashes.
  static Future<void> ensureLoaded() async {
    if (_bundled != null) return;
    WidgetsFlutterBinding.ensureInitialized();
    final AssetManifest manifest =
        await AssetManifest.loadFromAssetBundle(rootBundle);
    _bundled = manifest
        .listAssets()
        .where((String p) => p.startsWith('$_dir/'))
        .toSet();
  }

  /// Test-only override so widget tests can assert the photo slot renders when
  /// present and is omitted when absent. Pass exact bundled paths (e.g.
  /// 'assets/connector-photos/rp-sma.jpg'); pass an empty set for "none".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
