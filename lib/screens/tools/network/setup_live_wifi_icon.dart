// SetupLiveWifiIcon — the custom Tier-2 glyph for the "Set up Live Wi-Fi" action.
//
// Replaces the generic `Icons.download_outlined` tray-arrow on the
// install-the-companion buttons ("Set up live Wi-Fi" / "Set up live readings" /
// "Add the Shortcut") with Charta's Vera-approved custom mark. See GL-003
// §8.6.1 (Tier-2 custom-icon authoring), §8.6.3 (the install-companion gap this
// fills), and the team note [[feedback_custom_icons]] (prominent actions get
// custom icons; a generic Material placeholder on a feature button is a flag a
// custom icon was missed).
//
// The asset is the single monochrome `assets/tool-icons/setup-live-wifi.svg`
// (currentColor strokes), resolved through the existing [ToolAssets] convention
// (GL-003 §8.6 — assets/tool-icons/<id>.svg). It renders via `flutter_svg` like
// every other Tier-2 icon.
//
// TINT STAYS RUNTIME: the SVG uses `currentColor`, so this widget tints it to the
// AMBIENT IconTheme color — exactly what an `Icon` does inside a `FilledButton`
// (which sets IconTheme to the button's onPrimary foreground). So swapping
// `Icon(Icons.download_outlined)` → `SetupLiveWifiIcon()` keeps the lime/
// onPrimary/disabled tinting unchanged across light and dark modes, with no
// per-call-site color wiring.
//
// DECORATIVE: every call site sits inside a labeled button ("Set up live Wi-Fi"
// / "Add the Shortcut"), so the glyph is excluded from semantics — the button's
// own Semantics label is the accessible name (no duplicate announcement).

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/tool_assets.dart';

/// The custom "Set up Live Wi-Fi" glyph. Drop-in replacement for
/// `Icon(Icons.download_outlined)` on the install-the-companion buttons: same
/// default icon size, same runtime tint (follows the ambient [IconTheme]).
class SetupLiveWifiIcon extends StatelessWidget {
  const SetupLiveWifiIcon({super.key, this.size});

  /// The catalog id the asset is registered under (GL-003 §8.6).
  static const String _assetId = 'setup-live-wifi';

  /// Render size in logical pixels. Defaults to the ambient [IconTheme] size
  /// (the standard 24 inside a [FilledButton.icon]), so it matches the `Icon` it
  /// replaces without hardcoding a size.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final IconThemeData iconTheme = IconTheme.of(context);
    final double dim = size ?? iconTheme.size ?? 24;
    // Follow the ambient icon color (a button sets this to its foreground), with
    // the theme icon color as the fallback — identical behaviour to `Icon`.
    final Color color =
        iconTheme.color ?? Theme.of(context).iconTheme.color ?? Colors.white;

    // The asset ships bundled, but gate on the manifest so a stripped build never
    // hands flutter_svg a missing path — fall back to the prior download glyph
    // rather than render a broken box (graceful degradation, mirrors ToolAssets
    // policy).
    if (!ToolAssets.hasIcon(_assetId)) {
      return Icon(Icons.download_outlined, size: dim, color: color);
    }

    return SvgPicture.asset(
      ToolAssets.iconPath(_assetId),
      width: dim,
      height: dim,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      // Decorative: the enclosing button's Semantics carries the accessible name.
      excludeFromSemantics: true,
      placeholderBuilder: (_) => SizedBox(width: dim, height: dim),
    );
  }
}
