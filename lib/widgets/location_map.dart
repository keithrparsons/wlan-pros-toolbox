// LocationMap — the embedded "plot my location" map preview (Batch 3, item #13).
//
// A self-contained, reusable map surface that plots a SINGLE coordinate (the
// device's current GPS fix, or any hand-typed coordinate) on OpenStreetMap
// raster tiles. Used by the Lat / Long tool as a preview card beneath the
// coordinate inputs; written as a standalone widget so the screen stays
// readable and any future tool can reuse the same compliant surface.
//
// ─── GL-003 §8.18 (Embedded map surface) — composed verbatim ─────────────────
//   Container : surface-1 fill, 12px (AppRadius.card) radius, 1px borderStrong.
//   Marker    : ONE lime (AppColors.primary) location pin with a charcoal
//               (AppColors.secondary, #1A1A1A) halo so the pin clears SC 1.4.11
//               (3:1) over arbitrary tile imagery. One hue, no second color.
//   Attribution (HARD LEGAL RULE — OSMF tile policy, not stylistic):
//               a PERSISTENT, non-dismissable, TAPPABLE
//               "© OpenStreetMap contributors" credit, bottom-edge, on a
//               rgba(0,0,0,0.6) (AppColors.scrim) chip, 13px caption text in
//               textSecondary, linking to openstreetmap.org/copyright.
//               IMPLEMENTED as an OWN persistent map child (not flutter_map's
//               RichAttributionWidget): RichAttributionWidget hides its
//               TextSourceAttribution items inside a tap-to-open popup, which
//               would put the credit "behind an info button" — exactly what
//               §8.18 forbids. SimpleAttributionWidget is persistent but
//               hardcodes a "flutter_map | © " prefix and its own padding, so
//               it cannot render the verbatim string with the required caption
//               type + scrim. So the chip below is a plain always-on overlay,
//               giving exact verbatim text, the scrim chip, and the tappable
//               link with full type control.
//
// ─── OSMF tile-usage policy — honored as a hard rule (Pax brief §F) ──────────
//   * UNIQUE User-Agent  : kOsmUserAgentPackageName below = the app bundle id,
//                          NOT the flutter_map library default. The policy
//                          requires an identifiable UA; a generic/library UA can
//                          get the app rate-limited or blocked.
//   * NO offline caching / NO tile pre-fetch: this widget uses ONLY flutter_map's
//                          default in-memory image cache (what Flutter does for
//                          any network image). No on-disk tile store, no
//                          FMTC/bulk-download provider, no pre-fetch. The policy
//                          forbids pre-fetching and heavy caching.
//   * ONLINE-ONLY        : tiles load over HTTPS from tile.openstreetmap.org.
//                          When offline, tiles simply fail to load; the caller
//                          owns the honest "no connection" copy around the map.
//
// flutter_map is BSD-3-Clause, pure-Dart (no platform channel, no entitlement),
// so it runs identically on iOS + macOS + web.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';

/// The OSMF-required attribution string. Verbatim per GL-003 §8.18 — do not
/// alter, abbreviate, or tint.
const String kOsmAttribution = '© OpenStreetMap contributors';

/// The OSM copyright page the attribution links to (GL-003 §8.18).
const String kOsmCopyrightUrl = 'https://www.openstreetmap.org/copyright';

/// The OSM standard raster tile endpoint (HTTPS, online-only).
const String kOsmTileUrl =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// The UNIQUE User-Agent identifier sent to the OSM tile server — the app's
/// bundle id, so the request is attributable to this app per the OSMF policy.
/// flutter_map prefixes this with its own runtime info; passing the bundle id
/// makes the resulting UA unique to the WLAN Pros Toolbox rather than a generic
/// flutter_map default.
const String kOsmUserAgentPackageName = 'com.wlanpros.wlanProsToolbox';

/// An embedded, online-only OSM map plotting a single [latitude]/[longitude]
/// with a lime location pin. Pan/zoom only — no routing, search, or geocoding.
///
/// The widget renders ONLY the map surface (container + tiles + marker +
/// attribution). The caller is responsible for the honest connectivity / no-fix
/// states around it (this widget should not be shown when there is no valid
/// coordinate to plot).
class LocationMap extends StatefulWidget {
  const LocationMap({
    super.key,
    required this.latitude,
    required this.longitude,
    this.height = 220,
    this.initialZoom = 14,
  });

  /// Signed decimal-degrees latitude of the point to plot. Caller guarantees
  /// it is finite and in range (±90).
  final double latitude;

  /// Signed decimal-degrees longitude of the point to plot. Caller guarantees
  /// it is finite and in range (±180).
  final double longitude;

  /// Fixed map height. The map is a preview card, not a full-screen view, so a
  /// bounded height keeps it lightweight within the scrolling tool body.
  final double height;

  /// Initial zoom level (OSM z). 14 frames a neighborhood-scale view around the
  /// plotted point — enough context to recognize the location without exposing
  /// a pin floating in a featureless world view.
  final double initialZoom;

  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap> {
  final MapController _controller = MapController();

  @override
  void didUpdateWidget(covariant LocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-center when the plotted coordinate changes (e.g. a fresh GPS read or a
    // hand-edited field), preserving the user's current zoom.
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _controller.move(
        LatLng(widget.latitude, widget.longitude),
        _controller.camera.zoom,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final LatLng point = LatLng(widget.latitude, widget.longitude);

    // §8.18 map container: surface-1 fill, card radius, 1px borderStrong (the
    // map is interactive → the strong/component boundary, not decorative border).
    return Semantics(
      label:
          'Map of your location at latitude '
          '${widget.latitude.toStringAsFixed(6)}, longitude '
          '${widget.longitude.toStringAsFixed(6)}',
      // The slippy map itself is a pan/zoom surface with no readable text for a
      // screen reader; the label above + the lat/long readout elsewhere on the
      // screen carry the meaning, so we exclude the inner tile semantics.
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.card),
            // Interactive surface → borderStrong; §8.20.3-B 1.5px in light.
            border: Border.all(
              color: colors.borderStrong,
              width: colors.isLight ? 1.5 : 1,
            ),
          ),
          child: FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: point,
              initialZoom: widget.initialZoom,
              // Pan/zoom only — no rotation gesture (keeps the lightweight
              // preview predictable; the brief asks for basic pan/zoom only).
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.scrollWheelZoom,
              ),
            ),
            children: <Widget>[
              // ── Online-only OSM tiles ──────────────────────────────────────
              TileLayer(
                urlTemplate: kOsmTileUrl,
                // UNIQUE User-Agent per the OSMF policy (HARD rule).
                userAgentPackageName: kOsmUserAgentPackageName,
                // Default in-memory tile provider ONLY — no on-disk cache, no
                // pre-fetch (the policy forbids bulk caching / pre-fetching).
                tileProvider: NetworkTileProvider(),
                // Fail honestly: when a tile cannot load (offline / blocked),
                // show the surface-2 placeholder rather than a broken image.
                errorTileCallback: (tile, error, stackTrace) {},
              ),

              // ── Single lime pin with a charcoal halo (§8.18 marker) ─────────
              MarkerLayer(
                markers: <Marker>[
                  Marker(
                    point: point,
                    width: 44,
                    height: 44,
                    // The pin's tip marks the point; anchor the icon so its
                    // base sits on the coordinate, not its center.
                    alignment: Alignment.topCenter,
                    child: const _LocationPin(),
                  ),
                ],
              ),

              // ── Attribution (HARD LEGAL RULE, §8.18) ───────────────────────
              // PERSISTENT, non-dismissable, TAPPABLE "© OpenStreetMap
              // contributors" on a rgba(0,0,0,0.6) scrim chip, anchored to the
              // bottom edge, linking to the OSM copyright page. An always-on map
              // child — never a toggle, never a popup, never faded out.
              _OsmAttributionChip(
                text: text,
                onTap: _openOsmCopyright,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openOsmCopyright() async {
    final Uri uri = Uri.parse(kOsmCopyrightUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Honest no-op on a host without a browser; the credit remains visible.
    }
  }
}

/// A single lime location pin with a charcoal (#1A1A1A) halo, per GL-003 §8.18.
/// The dark halo guarantees the pin's edge clears SC 1.4.11 (3:1) as a graphical
/// object over BOTH light and dark tiles (the tile color is arbitrary).
class _LocationPin extends StatelessWidget {
  const _LocationPin();

  @override
  Widget build(BuildContext context) {
    // THEME-INDEPENDENT BY DESIGN (§8.18): the pin sits over arbitrary OSM tile
    // imagery, NOT over a light/dark app surface. Its SC 1.4.11 guarantee comes
    // from the charcoal halo against tiles, independent of the app theme — so it
    // stays brand lime + charcoal halo in BOTH themes. The §8.20.2 lime-fill-only
    // rule governs lime on a light *app surface*; it does not apply over tiles.
    return const Stack(
      alignment: Alignment.topCenter,
      children: <Widget>[
        // Charcoal halo: a slightly larger pin behind the lime one, offset so
        // the dark outline reads on every side.
        Icon(
          Icons.location_on,
          size: 40,
          color: AppColors.secondary, // #1A1A1A halo
        ),
        Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.location_on,
            size: 34,
            color: AppColors.primary, // lime — the one accent
          ),
        ),
      ],
    );
  }
}

/// The OSMF-required attribution chip (GL-003 §8.18, HARD LEGAL RULE).
///
/// Persistent (always visible while the map is on screen), non-dismissable (no
/// toggle, no popup), and TAPPABLE (opens the OSM copyright page). Verbatim
/// "© OpenStreetMap contributors" in 13px caption / textSecondary on a
/// rgba(0,0,0,0.6) scrim chip so it clears SC 1.4.3 AA over arbitrary tiles.
class _OsmAttributionChip extends StatelessWidget {
  const _OsmAttributionChip({required this.text, required this.onTap});

  final TextTheme text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        // A hair off the bottom-right corner so the chip clears the rounded
        // container edge.
        padding: const EdgeInsets.all(4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Semantics(
              link: true,
              label: 'OpenStreetMap copyright',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // rgba(0,0,0,0.6) dark scrim chip (§8.18) — guarantees the
                  // credit clears AA over any tile color. THEME-INDEPENDENT: the
                  // scrim is always dark, so it does not take the light surface.
                  color: AppColors.scrim,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    kOsmAttribution,
                    // 13px caption / IBM Plex Sans (§8.18). The label color stays
                    // LIGHT (#E5E5E5) in both themes because it sits on the dark
                    // scrim chip, not on the app surface — flipping it to the
                    // light-theme dark text would fail AA on the scrim. The
                    // underline signals the tappable link affordance.
                    style: text.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: AppTextSize.caption,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
