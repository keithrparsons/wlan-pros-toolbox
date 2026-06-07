// My Current Location (BF5-16) — auto-runs the GPS fix on open and shows the
// device's latitude, longitude, altitude, and horizontal accuracy directly.
//
// This is the consumer-findable front door to the same live fix the Lat / Long
// converter exposes: the converter buries it behind a "Use my location" action
// and a coordinate-format teaching panel, so people don't find it. This screen
// is the dedicated "where am I right now" answer.
//
// 100% backend reuse: it depends on the SAME DeviceLocationService seam
// (lib/services/location/device_location.dart) the Lat / Long tool uses — no new
// platform code, no new permission model. It switches over the sealed
// LocationResult so every state is handled explicitly and never fabricates a
// coordinate (GL-005 / GL-008):
//
// States (SOP-007 §5):
//  - loading        → a fix is in flight (auto on open, or after Update).
//  - success        → lat/long/altitude/accuracy render; coordinates are
//                     IDENTIFIER values (Roboto Mono per GL-003 §8.5).
//  - success (coarse / IP-approximate) → same readout, honestly labeled as
//                     approximate / not GPS-precise (never presented as a GPS
//                     reading).
//  - needs-permission → neutral banner + a lime "Use my location" action that
//                     requests permission (GL-003 §8.13 rule 6).
//  - blocked        → permission permanently denied or Location Services off →
//                     a Settings deep-link (in-app request would no-op).
//  - unavailable    → granted + enabled but no fix came back → honest
//                     "Location unavailable." with a reason; no stale coordinate.
//  - empty / error  → not separately reachable; the sealed states above cover
//                     every outcome of a single read.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/location/device_location.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'value_row.dart';

class MyCurrentLocationScreen extends StatefulWidget {
  const MyCurrentLocationScreen({super.key, this.location = const DeviceLocation()});

  /// The live-location seam. Defaults to the production geolocator-backed
  /// implementation; tests inject a fake.
  final DeviceLocationService location;

  @override
  State<MyCurrentLocationScreen> createState() =>
      _MyCurrentLocationScreenState();
}

class _MyCurrentLocationScreenState extends State<MyCurrentLocationScreen> {
  LocationFix? _fix;
  LocationPermissionState _permission = LocationPermissionState.granted;
  bool _serviceDisabled = false;
  bool _locating = false;
  String? _error;

  // BF (beta): the Update button gave no visible sign anything happened. We now
  // stamp the wall-clock time of every successful fix and render it as a
  // "Last updated HH:MM:SS" line that visibly changes on each read, and — for a
  // user-initiated Update — also surface a transient "Location updated"
  // SnackBar. Auto-open reads do not raise the SnackBar (it would be noise on a
  // screen the user just opened); they still stamp the timestamp.
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    // BF5-16: auto-run the fix on open. Deferred to the first frame so the
    // initial loading state paints before the async read.
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
  }

  // ─── Read one fix ──────────────────────────────────────────────────────────

  Future<void> _read({bool userInitiated = false}) async {
    setState(() {
      _locating = true;
      _error = null;
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
          _lastUpdated = DateTime.now();
        });
        // Beta fix: a user-initiated Update gets an explicit confirmation.
        if (userInitiated) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('Location updated')),
            );
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
          _error = reason;
          _locating = false;
        });
    }
  }

  Future<void> _requestThenRead() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    LocationPermissionState state;
    try {
      state = await widget.location.requestPermission();
    } catch (_) {
      state = LocationPermissionState.blocked;
    }
    if (!mounted) return;
    if (state == LocationPermissionState.granted) {
      await _read();
    } else {
      setState(() {
        _permission = state;
        _locating = false;
      });
    }
  }

  Future<void> _openSettings() async {
    await widget.location.openSettings();
  }

  // ─── Maps / copy ────────────────────────────────────────────────────────────

  ({double lat, double lon})? _coords() {
    final LocationFix? f = _fix;
    if (f == null) return null;
    if (!f.latitude.isFinite || !f.longitude.isFinite) return null;
    return (lat: f.latitude, lon: f.longitude);
  }

  Future<void> _openAppleMaps() async {
    final c = _coords();
    if (c == null) return;
    final String ll = '${c.lat.toStringAsFixed(6)},${c.lon.toStringAsFixed(6)}';
    await _launch(Uri.parse('https://maps.apple.com/?ll=$ll&q=$ll'));
  }

  Future<void> _openGoogleMaps() async {
    final c = _coords();
    if (c == null) return;
    final String q = '${c.lat.toStringAsFixed(6)},${c.lon.toStringAsFixed(6)}';
    await _launch(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'),
    );
  }

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

  /// §8.16 copy payload — the full readout as labeled text, or null when there is
  /// no fix yet (the copy affordance disables until there is something to copy).
  String? _buildCopyText() {
    final LocationFix? f = _fix;
    if (f == null) return null;
    final StringBuffer buf = StringBuffer()..writeln('Current Location');
    buf
      ..writeln('Latitude: ${f.latitude.toStringAsFixed(6)}')
      ..writeln('Longitude: ${f.longitude.toStringAsFixed(6)}');
    final String? alt = _formatAltitude(f);
    final String? acc = _formatAccuracy(f);
    buf.writeln('Altitude: ${alt ?? 'Not reported'}');
    buf.writeln('Horizontal accuracy: ${acc ?? 'Not reported'}');
    if (f.isApproximate) {
      buf.writeln('Source: approximate, from your public IP (city-level, not GPS)');
    }
    return buf.toString().trimRight();
  }

  static String? _formatAltitude(LocationFix fix) {
    final double? m = fix.altitudeMeters;
    if (m == null) return null;
    return '${m.toStringAsFixed(1)} m';
  }

  static String? _formatAccuracy(LocationFix fix) {
    final double? m = fix.accuracyMeters;
    if (m == null) return null;
    return '±${m.toStringAsFixed(0)} m';
  }

  static bool _isCoarse(LocationFix fix) {
    final double? m = fix.accuracyMeters;
    return m != null && m > 100;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Current Location'),
        toolbarHeight: 64,
        actions: <Widget>[
          // §8.16 — copy the readout. Disabled (null builder) until a fix exists.
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.contentMaxWidth,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _intro(context),
                  const SizedBox(height: AppSpacing.sm),
                  _stateCard(context),
                  ToolHelpFooter(toolId: 'my-current-location'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _intro(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      'Your device GPS fix, read on open: latitude, longitude, altitude, and '
      'how accurate the fix is. Tap Update to read it again.',
      style: text.labelMedium?.copyWith(color: colors.textTertiary),
    );
  }

  Widget _stateCard(BuildContext context) {
    if (_locating && _fix == null) return const _LoadingCard();
    if (_permission == LocationPermissionState.needsPermission) {
      return _PermissionCard(onGrant: _requestThenRead, locating: _locating);
    }
    if (_permission == LocationPermissionState.blocked) {
      return _BlockedCard(
        serviceDisabled: _serviceDisabled,
        onOpenSettings: _openSettings,
      );
    }
    final LocationFix? fix = _fix;
    if (fix != null) {
      return _ResultCard(
        fix: fix,
        coarse: _isCoarse(fix),
        altitude: _formatAltitude(fix),
        accuracy: _formatAccuracy(fix),
        locating: _locating,
        lastUpdated: _lastUpdated,
        onUpdate: () => _read(userInitiated: true),
        onAppleMaps: _openAppleMaps,
        onGoogleMaps: _openGoogleMaps,
      );
    }
    // Granted + enabled but no fix (or an unexpected read failure).
    return _UnavailableCard(
      reason: _error ?? 'Location unavailable.',
      locating: _locating,
      onRetry: _read,
    );
  }
}

// ─── State cards ───────────────────────────────────────────────────────────

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _CardShell(
      child: Semantics(
        liveRegion: true,
        label: 'Reading your location',
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Reading your location…',
              style: text.bodyLarge?.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.fix,
    required this.coarse,
    required this.altitude,
    required this.accuracy,
    required this.locating,
    required this.lastUpdated,
    required this.onUpdate,
    required this.onAppleMaps,
    required this.onGoogleMaps,
  });

  final LocationFix fix;
  final bool coarse;
  final String? altitude;
  final String? accuracy;
  final bool locating;
  final DateTime? lastUpdated;
  final VoidCallback onUpdate;
  final VoidCallback onAppleMaps;
  final VoidCallback onGoogleMaps;

  /// Local wall-clock as a zero-padded HH:MM:SS string (24-hour). No locale or
  /// intl dependency — this is a plain confirmation stamp, not a formatted date.
  static String _formatClock(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Coordinates are identifier values → Roboto Mono (GL-003 §8.5).
          ValueRow(
            label: 'Latitude',
            value: fix.latitude.toStringAsFixed(6),
            identifier: true,
            emphasize: true,
          ),
          ValueRow(
            label: 'Longitude',
            value: fix.longitude.toStringAsFixed(6),
            identifier: true,
            emphasize: true,
          ),
          // Altitude / accuracy are measured numerics → DM Mono. Null renders
          // the honest "Not available on this platform" treatment.
          ValueRow(label: 'Altitude', value: altitude, mono: true),
          ValueRow(label: 'Accuracy', value: accuracy, mono: true),
          if (fix.isApproximate || coarse) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _ApproxNote(approximate: fix.isApproximate),
          ],
          const SizedBox(height: AppSpacing.sm),
          // Update — primary action, re-reads the fix.
          FilledButton.icon(
            onPressed: locating ? null : onUpdate,
            icon: locating
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(colors.surface0),
                    ),
                  )
                : const Icon(Icons.my_location),
            label: Text(locating ? 'Updating…' : 'Update'),
          ),
          if (lastUpdated != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            // Beta fix: a visible, changing timestamp confirms the Update read.
            // liveRegion so a screen reader announces the new time on refresh.
            Semantics(
              liveRegion: true,
              child: Text(
                'Last updated ${_formatClock(lastUpdated!)}',
                textAlign: TextAlign.center,
                style: text.labelMedium?.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAppleMaps,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Apple Maps'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGoogleMaps,
                  icon: const Icon(Icons.public, size: 18),
                  label: const Text('Google Maps'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'WGS-84 decimal degrees. Negative latitude is south; negative '
            'longitude is west.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Honest note for a coarse or IP-approximate fix — never presents an
/// approximate location as GPS-precise (GL-005).
class _ApproxNote extends StatelessWidget {
  const _ApproxNote({required this.approximate});
  final bool approximate;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String msg = approximate
        ? 'Approximate, from your public IP (city-level, not a GPS reading).'
        : 'Coarse fix — likely Wi-Fi-derived rather than GPS (large accuracy '
            'radius).';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.info_outline, size: 16, color: colors.statusInfo),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            msg,
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.onGrant, required this.locating});
  final VoidCallback onGrant;
  final bool locating;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Location permission needed',
            style: text.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Allow location access to read your current GPS fix.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: locating ? null : onGrant,
            icon: const Icon(Icons.my_location),
            label: const Text('Use my location'),
          ),
        ],
      ),
    );
  }
}

class _BlockedCard extends StatelessWidget {
  const _BlockedCard({
    required this.serviceDisabled,
    required this.onOpenSettings,
  });
  final bool serviceDisabled;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String body = serviceDisabled
        ? 'Location Services are turned off for this device. Turn them on in '
            'Settings, then try again.'
        : 'Location permission is off for this app. Enable it in Settings, then '
            'try again.';
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            serviceDisabled
                ? 'Location Services are off'
                : 'Location permission is off',
            style: text.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({
    required this.reason,
    required this.locating,
    required this.onRetry,
  });
  final String reason;
  final bool locating;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Location unavailable',
            style: text.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            reason,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: locating ? null : onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(locating ? 'Trying…' : 'Try again'),
          ),
        ],
      ),
    );
  }
}
