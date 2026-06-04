// Device location — a thin, typed seam over `geolocator` so the Lat / Long tool
// (and any future map tool) consumes ONE package-agnostic contract instead of
// touching the plugin directly.
//
// The screen never imports `geolocator`; it imports this file and switches on
// the sealed [LocationResult]. That keeps the platform truth in one place and
// lets the result carry an honest, per-case reason (GL-008 + GL-005 +
// Truthfulness Audit): a denied permission, a disabled Location Service, or a
// genuine no-fix are three different states the UI must distinguish, never a
// blank coordinate presented as real.
//
// Permission model mirrors the wifi-info Location gate (GL-003 §8.13 rule 6):
//   * needs-permission  → the UI shows a NEUTRAL banner + a lime "Use my
//                          location" / "Grant Location" action that requests it.
//   * deniedForever     → in-app request is a no-op; the UI offers the Settings
//                          deep-link (openAppSettings) instead.
//   * granted           → the UI may prefill the live fix on entry.
//
// macOS without GPS hardware: Core Location returns a Wi-Fi-derived (coarse)
// fix. We do not try to detect "is this GPS or Wi-Fi" (the OS does not tell
// us); instead the result always carries [accuracyMeters], and the UI labels a
// coarse fix honestly from that value rather than claiming GPS precision.

import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Where the permission currently stands. A flattened view of geolocator's
/// [LocationPermission] + the Location-services master switch, so the screen
/// reasons about three UI states, not five enum cases.
enum LocationPermissionState {
  /// Not yet asked, or denied once (re-askable). UI: neutral banner + request.
  needsPermission,

  /// Permanently denied / restricted, OR the device's Location Services master
  /// switch is off. An in-app request will not prompt — the UI must deep-link
  /// to Settings.
  blocked,

  /// While-in-use or always. The UI may read and prefill the live fix.
  granted,
}

/// A single immutable location reading the UI renders. Coordinates are
/// IDENTIFIER values (GL-003 §8.5) → rendered in Roboto Mono, not DM Mono.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.altitudeMeters,
    required this.accuracyMeters,
    required this.altitudeAccuracyMeters,
  });

  /// Signed decimal degrees. Feeds the Lat / Long converter's latitude field.
  final double latitude;

  /// Signed decimal degrees. Feeds the longitude field.
  final double longitude;

  /// Meters above the WGS-84 reference ellipsoid. `null` when the platform did
  /// not supply altitude (e.g. a coarse Wi-Fi fix on a Mac without GPS).
  final double? altitudeMeters;

  /// Horizontal accuracy radius in meters (smaller is better). `null` when not
  /// reported. A large value is the honest signal of a coarse/derived fix.
  final double? accuracyMeters;

  /// Vertical (altitude) accuracy in meters. `null` when not reported. iOS/
  /// macOS report a non-positive sentinel when altitude is not measured.
  final double? altitudeAccuracyMeters;
}

/// The sealed outcome of a location request. The UI switches over the runtime
/// type so every state is handled explicitly (no implicit blank/placeholder).
sealed class LocationResult {
  const LocationResult();
}

/// A real fix was obtained.
class LocationSuccess extends LocationResult {
  const LocationSuccess(this.fix);
  final LocationFix fix;
}

/// Permission is needed and is re-askable in-app. UI shows the neutral banner
/// with the lime request action.
class LocationNeedsPermission extends LocationResult {
  const LocationNeedsPermission();
}

/// Permission is permanently denied/restricted, or Location Services is off.
/// In-app request will not prompt; UI offers the Settings deep-link.
/// [serviceDisabled] distinguishes the master-switch-off case so the UI can
/// word the deep-link correctly.
class LocationBlocked extends LocationResult {
  const LocationBlocked({required this.serviceDisabled});
  final bool serviceDisabled;
}

/// Permission/services are fine but no fix came back (timeout, no signal). UI
/// shows "Location unavailable." — never a stale coordinate.
class LocationUnavailable extends LocationResult {
  const LocationUnavailable(this.reason);

  /// Short, human reason for the failure. Surfaced as honest helper text.
  final String reason;
}

/// The seam the screen depends on. The default [DeviceLocation] talks to
/// geolocator; tests inject a fake implementing this interface.
abstract interface class DeviceLocationService {
  /// Current permission state without prompting (safe to call on entry).
  Future<LocationPermissionState> permissionState();

  /// Requests permission (system prompt) and returns the resulting state.
  Future<LocationPermissionState> requestPermission();

  /// Reads one fix. Resolves permission/services first and returns the matching
  /// sealed state; never throws to the caller.
  Future<LocationResult> currentLocation();

  /// Opens the OS app-settings page so a [LocationBlocked] user can grant
  /// permission manually. Returns whether the page opened.
  Future<bool> openSettings();
}

/// Production implementation over `geolocator`.
class DeviceLocation implements DeviceLocationService {
  const DeviceLocation();

  @override
  Future<LocationPermissionState> permissionState() async {
    final bool serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) return LocationPermissionState.blocked;
    final LocationPermission p = await Geolocator.checkPermission();
    return _map(p);
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    final bool serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) return LocationPermissionState.blocked;
    final LocationPermission p = await Geolocator.requestPermission();
    return _map(p);
  }

  @override
  Future<LocationResult> currentLocation() async {
    final bool serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      return const LocationBlocked(serviceDisabled: true);
    }

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    switch (_map(p)) {
      case LocationPermissionState.needsPermission:
        return const LocationNeedsPermission();
      case LocationPermissionState.blocked:
        return const LocationBlocked(serviceDisabled: false);
      case LocationPermissionState.granted:
        break;
    }

    try {
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          // A real GPS lock can take a few seconds; cap it so the UI never
          // hangs on a request that will not resolve (honest timeout state).
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationSuccess(_fromPosition(pos));
    } catch (e) {
      return LocationUnavailable(_describe(e));
    }
  }

  @override
  Future<bool> openSettings() => Geolocator.openAppSettings();

  // ─── Mapping ────────────────────────────────────────────────────────────

  static LocationPermissionState _map(LocationPermission p) {
    switch (p) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionState.granted;
      case LocationPermission.deniedForever:
        return LocationPermissionState.blocked;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionState.needsPermission;
    }
  }

  /// Converts a geolocator [Position] to our model. iOS/macOS report a
  /// non-positive sentinel for an unmeasured altitude/accuracy, and geolocator
  /// uses a negative accuracy to mean "invalid" — both collapse to `null` so
  /// the UI shows an honest "not reported" rather than a meaningless 0 or
  /// negative meters.
  static LocationFix _fromPosition(Position pos) {
    double? clean(double v) => v.isFinite && v > 0 ? v : null;
    return LocationFix(
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitudeMeters: pos.altitude.isFinite ? pos.altitude : null,
      accuracyMeters: clean(pos.accuracy),
      altitudeAccuracyMeters: clean(pos.altitudeAccuracy),
    );
  }

  static String _describe(Object e) {
    if (e is TimeoutException) {
      return 'Timed out waiting for a GPS fix.';
    }
    if (e is LocationServiceDisabledException) {
      return 'Location Services are turned off.';
    }
    if (e is PermissionDeniedException) {
      return 'Location permission was denied.';
    }
    if (e is PositionUpdateException) {
      return 'The device could not determine a location.';
    }
    return 'Location unavailable.';
  }
}
