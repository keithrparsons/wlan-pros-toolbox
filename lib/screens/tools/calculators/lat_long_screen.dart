// Lat/Long Conversion tool.
//
// Enter a coordinate as decimal degrees (DD) and read it back in three formats
// for both latitude and longitude:
//   DD  — decimal degrees
//   DDM — degrees + decimal minutes
//   DMS — degrees + minutes + decimal seconds
//
// Behavior matches the RF Tools PWA reference exactly (app.js calcLatLong →
// fmtCoord → ddToDmsParts, lines 156-180):
//   DD  = dd.toFixed(6)
//   DDM = "{deg}° {(min + sec/60).toFixed(4)}' {dir}"
//   DMS = "{deg}° {min}' {sec.toFixed(2)}" {dir}"
// where {dir} is the hemisphere letter (N/S for latitude, E/W for longitude)
// chosen from the sign: dd >= 0 → N/E, dd < 0 → S/W. Degrees/minutes/seconds
// are computed from the ABSOLUTE value (PWA ddToDmsParts), so the sign lives
// only in the direction letter.
//
// Input is decimal degrees, matching the PWA's two number fields. Live
// recompute on every keystroke.
//
// Edge cases (PWA calcLatLong guards):
// - Empty / partial / non-numeric input → blank the outputs, no crash.
// - |latitude|  > 90  → out of range; outputs blank.
// - |longitude| > 180 → out of range; outputs blank.
//
// Conversion math is pure and lives in static methods on the public
// LatLongScreen class so it is unit-testable against the PWA.
//
// LIVE GPS (Batch 2): the screen also reads the device's current location via
// the `DeviceLocationService` seam (lib/services/location/device_location.dart,
// over `geolocator`). When Location permission is already granted, the live fix
// prefills the lat/long fields on entry; otherwise a NEUTRAL banner (GL-003
// §8.13 rule 6) offers a lime "Use my location" action that requests it.
// Altitude + horizontal accuracy surface as a read-only context readout so the
// GPS detail is always visible, not just consumed by the converter. All
// permission/no-fix states are explicit and honest (GL-005 / GL-008): a denied
// permission deep-links to Settings, a Mac without GPS labels its fix coarse,
// and a failed read shows "Location unavailable." — never a placeholder
// coordinate presented as real. Coordinates/altitude are IDENTIFIER values, so
// the readout uses Roboto Mono per §8.5 (NOT DM Mono).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/tool_assets.dart';
import '../../../services/location/device_location.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../utils/decimal_input.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/location_map.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Which axis a coordinate is on. Selects the hemisphere letters (N/S vs E/W)
/// and the valid range (±90 vs ±180), mirroring the PWA `isLat` flag.
enum CoordAxis { latitude, longitude }

/// One coordinate rendered in all three formats. Strings are PWA-exact.
class CoordFormats {
  const CoordFormats({required this.dd, required this.ddm, required this.dms});

  /// Decimal degrees, e.g. "40.712800".
  final String dd;

  /// Degrees decimal minutes, e.g. "40° 42.7680' N".
  final String ddm;

  /// Degrees minutes seconds, e.g. "40° 42' 46.08\" N".
  final String dms;
}

class LatLongScreen extends StatefulWidget {
  const LatLongScreen({super.key, this.location = const DeviceLocation()});

  /// The live-location seam. Defaults to the production `geolocator`-backed
  /// implementation; tests inject a fake to exercise every permission/fix state
  /// without touching real hardware.
  final DeviceLocationService location;

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: ddToDmsParts, fmtCoord.

  /// Hemisphere letter for a signed decimal degree on [axis].
  /// PWA fmtCoord: lat → N (>=0) / S; lon → E (>=0) / W.
  static String direction(double dd, CoordAxis axis) {
    switch (axis) {
      case CoordAxis.latitude:
        return dd >= 0 ? 'N' : 'S';
      case CoordAxis.longitude:
        return dd >= 0 ? 'E' : 'W';
    }
  }

  /// Whole degrees from the absolute value (PWA ddToDmsParts.degrees).
  static int degreesPart(double dd) => dd.abs().floor();

  /// Whole minutes from the absolute value (PWA ddToDmsParts.minutes).
  static int minutesPart(double dd) {
    final double abs = dd.abs();
    final double minFull = (abs - abs.floorToDouble()) * 60;
    return minFull.floor();
  }

  /// Fractional seconds from the absolute value (PWA ddToDmsParts.seconds).
  static double secondsPart(double dd) {
    final double abs = dd.abs();
    final double minFull = (abs - abs.floorToDouble()) * 60;
    final int minutes = minFull.floor();
    return (minFull - minutes) * 60;
  }

  /// Decimal minutes for DDM = minutes + seconds/60 (PWA fmtCoord.dm value).
  static double decimalMinutesPart(double dd) {
    return minutesPart(dd) + secondsPart(dd) / 60;
  }

  /// All three PWA-exact format strings for [dd] on [axis]. Returns null when
  /// the value is non-finite or out of range (lat ±90, lon ±180) — the caller
  /// blanks the output, matching the PWA guard.
  static CoordFormats? format(double dd, CoordAxis axis) {
    if (!dd.isFinite) return null;
    final double limit = axis == CoordAxis.latitude ? 90 : 180;
    if (dd.abs() > limit) return null;

    final String dir = direction(dd, axis);
    final int deg = degreesPart(dd);
    final int min = minutesPart(dd);
    final double sec = secondsPart(dd);
    final double decMin = decimalMinutesPart(dd);

    return CoordFormats(
      dd: dd.toStringAsFixed(6),
      ddm: "$deg° ${decMin.toStringAsFixed(4)}' $dir",
      dms: "$deg° $min' ${sec.toStringAsFixed(2)}\" $dir",
    );
  }

  @override
  State<LatLongScreen> createState() => _LatLongScreenState();
}

class _LatLongScreenState extends State<LatLongScreen> {
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lonCtrl = TextEditingController();

  final FocusNode _latFocus = FocusNode();
  final FocusNode _lonFocus = FocusNode();

  // Computed format triples, or null when input is empty / invalid / range.
  CoordFormats? _lat;
  CoordFormats? _lon;

  // ─── Live-location state ──────────────────────────────────────────────────
  // The most recent live fix (drives the read-only altitude/accuracy readout),
  // or null before any successful read.
  LocationFix? _fix;

  // The current permission posture, resolved on entry (null = still checking).
  // Selects which banner the location card shows.
  LocationPermissionState? _permission;

  // A read in flight — disables the action + shows the spinner.
  bool _locating = false;

  // An honest, human reason when a read failed (no fix / blocked). Cleared on a
  // successful read. Never a stale coordinate.
  String? _locationError;

  // True once the device's Location Services master switch is reported off, so
  // the card words its deep-link toward Settings rather than an in-app prompt.
  bool _serviceDisabled = false;

  // Signed decimal: degrees can be negative for S/W. No scientific notation —
  // coordinates are typed by hand, not pasted from instruments.
  static final List<TextInputFormatter> _signedDecimal = signedDecimalFormatters;

  @override
  void initState() {
    super.initState();
    _resolvePermissionThenPrefill();
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _latFocus.dispose();
    _lonFocus.dispose();
    super.dispose();
  }

  // ─── Live-location handlers ─────────────────────────────────────────────────

  /// On entry: check the current permission without prompting. If it is already
  /// granted, read the live fix and prefill the fields straight away (Keith:
  /// current location is the default when permission exists). Otherwise leave
  /// the fields empty and let the neutral banner offer the request.
  Future<void> _resolvePermissionThenPrefill() async {
    LocationPermissionState state;
    try {
      state = await widget.location.permissionState();
    } catch (_) {
      // The platform plugin is unavailable (e.g. a headless test host, or a
      // platform without a location backend). Degrade to the honest
      // needs-permission banner rather than crashing entry.
      state = LocationPermissionState.needsPermission;
    }
    if (!mounted) return;
    setState(() {
      _permission = state;
      _serviceDisabled = false;
    });
    if (state == LocationPermissionState.granted) {
      await _readLocation(prefill: true);
    }
  }

  /// User tapped "Use my location" / "Grant Location": request permission (this
  /// shows the system prompt) then, if granted, read + prefill. A blocked
  /// result keeps the card on its Settings deep-link branch.
  Future<void> _requestThenRead() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    LocationPermissionState state;
    try {
      state = await widget.location.requestPermission();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationError = 'Location unavailable.';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _permission = state);
    if (state == LocationPermissionState.granted) {
      await _readLocation(prefill: true);
    } else {
      // Request returned non-granted: either still needs-permission (user
      // dismissed) or blocked. requestPermission() reports the master-switch-off
      // case as blocked; surface the Settings branch via _serviceDisabled.
      setState(() {
        _locating = false;
        if (state == LocationPermissionState.blocked) _serviceDisabled = true;
      });
    }
  }

  /// Reads one fix and (optionally) writes it into the lat/long fields. Updates
  /// the permission posture and error state from the sealed result so the card
  /// always reflects the true cause.
  Future<void> _readLocation({required bool prefill}) async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    LocationResult result;
    try {
      result = await widget.location.currentLocation();
    } catch (_) {
      result = const LocationUnavailable('Location unavailable.');
    }
    if (!mounted) return;

    switch (result) {
      case LocationSuccess(:final fix):
        setState(() {
          _fix = fix;
          _permission = LocationPermissionState.granted;
          _serviceDisabled = false;
          _locating = false;
        });
        if (prefill) {
          // Six decimals matches the DD format the converter emits.
          _latCtrl.text = fix.latitude.toStringAsFixed(6);
          _lonCtrl.text = fix.longitude.toStringAsFixed(6);
          _recompute();
        }
      case LocationNeedsPermission():
        setState(() {
          _permission = LocationPermissionState.needsPermission;
          _serviceDisabled = false;
          _locating = false;
        });
      case LocationBlocked(:final serviceDisabled):
        setState(() {
          _permission = LocationPermissionState.blocked;
          _serviceDisabled = serviceDisabled;
          _locating = false;
        });
      case LocationUnavailable(:final reason):
        setState(() {
          _locationError = reason;
          _locating = false;
        });
    }
  }

  /// Deep-links to the OS settings page so a blocked user can grant permission
  /// manually (macOS cannot toggle its own Location permission in code; iOS
  /// "Allow Once / Never" likewise routes through Settings on a hard denial).
  Future<void> _openLocationSettings() async {
    await widget.location.openSettings();
  }

  // ─── Map actions ────────────────────────────────────────────────────────────
  //
  // The currently entered coordinate (GPS-prefilled or hand-typed), as a signed
  // (lat, lon) pair, or null when either field is empty / non-numeric / out of
  // range. Drives the "Open in … Maps" + "Copy map link" actions, which are
  // shown only when there is a real coordinate to point at (honest affordance —
  // never a button that opens a map of 0,0).
  ({double lat, double lon})? _mapCoords() {
    final double? lat = tryParseFlexibleDouble(_latCtrl.text);
    final double? lon = tryParseFlexibleDouble(_lonCtrl.text);
    if (lat == null || lon == null) return null;
    if (!lat.isFinite || !lon.isFinite) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    return (lat: lat, lon: lon);
  }

  /// Opens the platform Apple Maps at the current coordinate. The
  /// `maps.apple.com` universal link resolves to the native Maps app on iOS and
  /// macOS and to the web map elsewhere. Six decimals matches the DD format.
  Future<void> _openAppleMaps() async {
    final c = _mapCoords();
    if (c == null) return;
    final String ll = '${c.lat.toStringAsFixed(6)},${c.lon.toStringAsFixed(6)}';
    await _launch(Uri.parse('https://maps.apple.com/?ll=$ll&q=$ll'));
  }

  /// Opens Google Maps at the current coordinate via the documented universal
  /// Maps URL, which hands off to the Google Maps app when installed and falls
  /// back to the browser otherwise.
  Future<void> _openGoogleMaps() async {
    final c = _mapCoords();
    if (c == null) return;
    final String q = '${c.lat.toStringAsFixed(6)},${c.lon.toStringAsFixed(6)}';
    await _launch(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'),
    );
  }

  /// Copies a shareable Google Maps link to the clipboard (works in any
  /// browser, on any platform, for the person you send it to).
  Future<void> _copyMapLink() async {
    final c = _mapCoords();
    if (c == null) return;
    final String q = '${c.lat.toStringAsFixed(6)},${c.lon.toStringAsFixed(6)}';
    final String link = 'https://www.google.com/maps/search/?api=1&query=$q';
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Map link copied')),
    );
  }

  /// Shared launcher with an honest failure path: if no app/browser can open
  /// the URL, tell the user rather than failing silently.
  Future<void> _launch(Uri uri) async {
    bool ok;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open a maps app.')),
    );
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? lat = tryParseFlexibleDouble(_latCtrl.text);
    final double? lon = tryParseFlexibleDouble(_lonCtrl.text);
    setState(() {
      _lat = lat == null ? null : LatLongScreen.format(lat, CoordAxis.latitude);
      _lon = lon == null
          ? null
          : LatLongScreen.format(lon, CoordAxis.longitude);
    });
  }

  /// §8.16 copy payload — the coordinate conversions as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) when neither coordinate is valid:
  /// before any entry, or when both are empty / non-numeric / out of range. A
  /// present coordinate copies all three formats (DD / DDM / DMS); a coordinate
  /// that is absent or out of range is simply omitted (honest blank, GL-005).
  String? _buildCopyText() {
    final CoordFormats? lat = _lat;
    final CoordFormats? lon = _lon;
    if (lat == null && lon == null) return null;

    final StringBuffer buf = StringBuffer()..writeln('Lat / Long');
    if (lat != null) {
      buf
        ..writeln('Latitude DD: ${lat.dd}')
        ..writeln('Latitude DDM: ${lat.ddm}')
        ..writeln('Latitude DMS: ${lat.dms}');
    }
    if (lon != null) {
      buf
        ..writeln('Longitude DD: ${lon.dd}')
        ..writeln('Longitude DDM: ${lon.ddm}')
        ..writeln('Longitude DMS: ${lon.dms}');
    }
    // Append the live-GPS context when a fix is present so a copy carries the
    // altitude/accuracy a coordinate copy alone would drop.
    final LocationFix? fix = _fix;
    if (fix != null) {
      final String? alt = _formatAltitude(fix);
      final String? acc = _formatAccuracy(fix);
      if (alt != null) buf.writeln('Altitude: $alt');
      if (acc != null) buf.writeln('Horizontal accuracy: $acc');
    }
    return buf.toString().trimRight();
  }

  // ─── Live-location formatting (honest; null = "not reported") ───────────────

  /// Altitude as "123.4 m", or null when the platform did not report it.
  static String? _formatAltitude(LocationFix fix) {
    final double? m = fix.altitudeMeters;
    if (m == null) return null;
    return '${m.toStringAsFixed(1)} m';
  }

  /// Horizontal accuracy as "±5 m", or null when not reported.
  static String? _formatAccuracy(LocationFix fix) {
    final double? m = fix.accuracyMeters;
    if (m == null) return null;
    return '±${m.toStringAsFixed(0)} m';
  }

  /// Whether the current fix reads as coarse (likely Wi-Fi-derived rather than
  /// GPS) so the readout can flag it honestly. A horizontal accuracy worse than
  /// ~100 m is the practical signal of a non-GPS fix (a Mac without GPS).
  static bool _isCoarse(LocationFix fix) {
    final double? m = fix.accuracyMeters;
    return m != null && m > 100;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lat / Long'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until at least one
        // coordinate is valid and in range; copies each present coordinate in
        // all three formats (DD / DDM / DMS) as a labeled text block.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            return Align(
              alignment: AppSpacing.calculatorVerticalAlignment(constraints),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.calculatorMaxWidth,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    edge,
                    AppSpacing.sm,
                    edge,
                    edge + AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // §8.6.2 concept-graphic header band — first child, above
                      // the input card. Self-collapses when no graphic is
                      // bundled, so the 24px gap below it disappears too.
                      ConceptGraphicBand(
                        toolId: 'lat-long',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('lat-long'))
                        const SizedBox(height: AppSpacing.md),
                      _locationCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _resultCard(text, mono),
                      if (_mapCoords() case final c?) ...[
                        const SizedBox(height: AppSpacing.md),
                        _mapCard(text, c),
                        const SizedBox(height: AppSpacing.md),
                        _mapActionsCard(text),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      _formatCard(text, mono),
                      ToolHelpFooter(toolId: 'lat-long'),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── Live-location card ─────────────────────────────────────────────────
  //
  // One card, four states (mirrors the wifi-info `_LocationCard` permission
  // pattern, GL-003 §8.13 rule 6 — NEUTRAL copy, the action in lime, never a
  // status-blue/green verdict because a permission prompt is not a verdict):
  //   1. needs-permission → neutral banner + lime "Use my location" action.
  //   2. blocked          → neutral banner explaining the denial + a Settings
  //                          deep-link (and a master-switch note if applicable).
  //   3. granted, no fix yet → "Use my location" action (re-read).
  //   4. granted, with fix → the read-only altitude + accuracy readout, plus a
  //                          quiet "Update" re-read action.
  Widget _locationCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _locationCardChildren(text, mono),
      ),
    );
  }

  List<Widget> _locationCardChildren(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final LocationPermissionState? perm = _permission;
    final LocationFix? fix = _fix;
    final bool blocked = perm == LocationPermissionState.blocked;

    // Header: neutral icon + neutral copy. The §8.13 rule-6 rule — the banner
    // text is neutral (textSecondary), the lime is reserved for the ACTION, not
    // a status verdict. The location pin is tinted lime as a brand glyph, the
    // app's single accent, consistent with the wifi-info location card.
    final String headerCopy;
    if (perm == null) {
      headerCopy = 'Checking Location permission…';
    } else if (blocked) {
      headerCopy = _serviceDisabled
          ? 'Location Services are turned off. Turn them on in Settings to fill '
                'these fields with your current position.'
          : 'Location permission is off. Allow it in Settings to fill these '
                'fields with your current position.';
    } else if (fix != null) {
      headerCopy = fix.isApproximate
          ? 'Your approximate location'
          : 'Your current location';
    } else {
      headerCopy = 'Fill the fields with your current latitude and longitude.';
    }

    return <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.location_on_outlined,
            size: 20,
            color: colors.textAccent,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              headerCopy,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),

      // The read-only altitude + accuracy readout, shown whenever a fix exists.
      // Coordinates/altitude are IDENTIFIER values → Roboto Mono (§8.5).
      if (fix != null) ...[
        const SizedBox(height: AppSpacing.sm),
        _fixReadout(fix, text, mono),
      ],

      // Honest no-fix message (granted, but the read failed). Neutral tertiary
      // text, never a fabricated coordinate.
      if (_locationError != null && !blocked) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          _locationError!,
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],

      // Action row. While checking permission (perm == null) show nothing yet.
      if (perm != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: _locationActions(blocked, fix),
        ),
      ],

      // IP-approximate honesty note: Core Location returned no fix, so this came
      // from the public IP. City-level, not GPS — say so plainly (GL-005).
      if (fix != null && fix.isApproximate) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Approximate location from your public IP (city-level, not GPS). '
          'Your device could not get a GPS or Wi-Fi position fix.',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ]
      // macOS coarse-fix honesty note: a Mac without GPS returns a Wi-Fi-derived
      // fix. Flag it from the accuracy value rather than claiming GPS precision.
      // (Skipped for an IP-approximate fix, which has its own note above.)
      else if (fix != null && _isCoarse(fix)) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          'This looks like a coarse, Wi-Fi-derived fix (no GPS hardware). '
          'Altitude and accuracy are approximate.',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    ];
  }

  List<Widget> _locationActions(bool blocked, LocationFix? fix) {
    final AppColorScheme colors = context.colors;
    if (_locating) {
      return <Widget>[
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.textAccent,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Semantics(
          liveRegion: true,
          child: Text(
            'Reading your location…',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ];
    }

    if (blocked) {
      // No in-app prompt will help — deep-link to the OS settings page.
      return <Widget>[
        Semantics(
          button: true,
          label: 'Open Location settings',
          child: OutlinedButton(
            onPressed: _openLocationSettings,
            child: const Text('Open Settings'),
          ),
        ),
      ];
    }

    // needs-permission OR granted: a single lime action. The label reads
    // "Use my location" before a fix and "Update location" once one exists, so
    // the affordance is honest about what it does in each state.
    return <Widget>[
      Semantics(
        button: true,
        label: fix == null ? 'Use my location' : 'Update location',
        child: FilledButton.icon(
          onPressed: () {
            if (_permission == LocationPermissionState.granted) {
              _readLocation(prefill: true);
            } else {
              _requestThenRead();
            }
          },
          icon: const Icon(Icons.my_location, size: 18),
          label: Text(fix == null ? 'Use my location' : 'Update location'),
        ),
      ),
    ];
  }

  /// Read-only altitude + horizontal-accuracy readout. The two identifier-style
  /// values sit in Roboto Mono (§8.5); each is omitted with an honest "Not
  /// reported" rather than a fabricated number when the platform did not supply
  /// it. The live lat/long themselves live in the editable fields below, so the
  /// readout focuses on the context Keith asked to keep visible.
  Widget _fixReadout(LocationFix fix, TextTheme text, AppMonoText mono) {
    final String? alt = _formatAltitude(fix);
    final String? acc = _formatAccuracy(fix);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _readoutRow('Altitude', alt, text, mono),
        const SizedBox(height: AppSpacing.xxs),
        _readoutRow('Accuracy', acc, text, mono),
      ],
    );
  }

  Widget _readoutRow(
    String label,
    String? value,
    TextTheme text,
    AppMonoText mono,
  ) {
    final AppColorScheme colors = context.colors;
    final bool reported = value != null;
    return Semantics(
      label: label,
      value: reported ? value : 'not reported',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: text.labelMedium?.copyWith(
                color: colors.textTertiary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              reported ? value : 'Not reported',
              // Identifier values → Roboto Mono per §8.5 (NOT DM Mono).
              style: mono.robotoMono.copyWith(
                color: reported
                    ? colors.textPrimary
                    : colors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: 'Latitude',
            hint: '(decimal degrees)',
            semanticLabel: 'Latitude in decimal degrees',
            field: _ddField(
              controller: _latCtrl,
              focusNode: _latFocus,
              hintText: '40.7128',
              monoStyle: mono.outputLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Longitude',
            hint: '(decimal degrees)',
            semanticLabel: 'Longitude in decimal degrees',
            field: _ddField(
              controller: _lonCtrl,
              focusNode: _lonFocus,
              hintText: '-74.0060',
              monoStyle: mono.outputLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ddField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required TextStyle monoStyle,
  }) {
    final AppColorScheme colors = context.colors;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: _signedDecimal,
      onChanged: (_) => _recompute(),
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      style: monoStyle.copyWith(fontSize: AppTextSize.fieldNumeric),
      cursorColor: colors.textAccent,
      decoration: InputDecoration(hintText: hintText),
    );
  }

  Widget _resultCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Coordinates',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _resultBlock('Latitude', _lat, text, mono),
          const SizedBox(height: AppSpacing.md),
          _resultBlock('Longitude', _lon, text, mono),
        ],
      ),
    );
  }

  // ─── Map-preview card ───────────────────────────────────────────────────────
  //
  // Shown only when a valid coordinate exists (same gate as the map-actions
  // card). An embedded, ONLINE-ONLY OpenStreetMap surface (GL-003 §8.18) that
  // plots the entered/GPS coordinate with a single lime pin. The map is the
  // §8.18 container itself (surface-1 / 12px / borderStrong), so this card adds
  // only the heading above it and the honest "needs internet" note below — the
  // tiles are online-only (OSMF policy: no offline caching), so when the device
  // is offline the tiles simply fail to load and this note explains why.
  Widget _mapCard(TextTheme text, ({double lat, double lon}) c) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(
            'Map',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
        ),
        LocationMap(latitude: c.lat, longitude: c.lon),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'The map needs an internet connection. Tiles © OpenStreetMap '
          'contributors; loaded live, never stored offline.',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }

  // ─── Map-actions card ───────────────────────────────────────────────────────
  //
  // Shown only when a valid coordinate exists. Three secondary actions
  // (OutlinedButton, not the lime primary which the location card owns):
  // open the point in Apple Maps, open it in Google Maps, or copy a shareable
  // map link. Wrap so the row reflows on a narrow phone width.
  Widget _mapActionsCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Open this location',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              Semantics(
                button: true,
                label: 'Open in Apple Maps',
                child: OutlinedButton.icon(
                  onPressed: _openAppleMaps,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Apple Maps'),
                ),
              ),
              Semantics(
                button: true,
                label: 'Open in Google Maps',
                child: OutlinedButton.icon(
                  onPressed: _openGoogleMaps,
                  icon: const Icon(Icons.public, size: 18),
                  label: const Text('Google Maps'),
                ),
              ),
              Semantics(
                button: true,
                label: 'Copy map link',
                child: OutlinedButton.icon(
                  onPressed: _copyMapLink,
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Copy map link'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultBlock(
    String heading,
    CoordFormats? f,
    TextTheme text,
    AppMonoText mono,
  ) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: text.labelMedium?.copyWith(
            color: colors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _formatRow(heading, 'DD', f?.dd, mono),
        const SizedBox(height: 4),
        _formatRow(heading, 'DDM', f?.ddm, mono),
        const SizedBox(height: 4),
        _formatRow(heading, 'DMS', f?.dms, mono),
      ],
    );
  }

  Widget _formatRow(
    String heading,
    String tag,
    String? value,
    AppMonoText mono,
  ) {
    final AppColorScheme colors = context.colors;
    final bool blank = value == null;
    // One SR node per row: "Latitude DD: 40.712800" (or "not calculated"),
    // instead of tag and value as separate fragments (Vera finding #6). The
    // heading rides along so the format is unambiguous when read aloud.
    return Semantics(
      label: '$heading $tag',
      value: blank ? 'not calculated' : value,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tag column snaps to the 8px base unit (GL-003 §4); 56px holds "DDM".
          SizedBox(
            width: 56,
            child: Text(
              tag,
              style: mono.inlineCode.copyWith(color: colors.textTertiary),
            ),
          ),
          Expanded(
            child: SelectableText(
              blank ? '—' : value,
              style: mono.inlineCode.copyWith(
                color: blank ? colors.textTertiary : colors.textAccent,
                fontWeight: blank ? FontWeight.w400 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    // Legend examples use a reference coordinate (London, 51.5074°) that is
    // deliberately distinct from any coordinate the result card is likely to
    // be showing. The earlier examples reused the New York anchor (40.7128°),
    // so the static legend value rendered the SAME string as a live result —
    // two widgets carrying identical text. The reference coordinate keeps the
    // legend illustrative without colliding with computed output.
    final List<List<String>> rows = const [
      ['DD', 'Decimal degrees', '51.507400'],
      ['DDM', 'Degrees decimal minutes', "51° 30.4440' N"],
      ['DMS', 'Degrees minutes seconds', "51° 30' 26.64\" N"],
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Formats',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...rows.map((row) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: colors.textAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      row[1],
                      style: text.labelMedium?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      row[2],
                      style: mono.inlineCode.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
