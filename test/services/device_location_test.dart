// DeviceLocation tests — focused on the IP-approximate fallback added for the
// Core-Location-no-fix case (the macOS-no-GPS / iOS-indoors state Keith hit).
//
// We mock GeolocatorPlatform so `getCurrentPosition` throws a no-fix error
// while services are on and permission is granted, then assert that
// `currentLocation()` returns a LocationSuccess flagged
// LocationSource.ipApproximate with the IP-derived coordinate, no altitude, and
// no fabricated accuracy. We also assert the fallback does NOT fire for the
// user-fixable states (permission-denied / services-disabled), which must stay
// LocationBlocked so the UI keeps routing the user to Settings.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// geolocator re-exports the full platform interface (GeolocatorPlatform,
// Position, PositionUpdateException), so we mock it through the public package.
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:wlan_pros_toolbox/services/location/device_location.dart';
import 'package:wlan_pros_toolbox/services/network/ip_geo_service.dart';
import 'package:wlan_pros_toolbox/services/network/json_http_client.dart';

/// A scriptable GeolocatorPlatform stand-in. Each test sets the service/
/// permission posture and whether `getCurrentPosition` should throw a no-fix.
class _MockGeolocator extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  _MockGeolocator({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    this.throwOnFix,
  });

  bool serviceEnabled;
  LocationPermission permission;

  /// When non-null, `getCurrentPosition` throws this (the no-fix case).
  Object? throwOnFix;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    final Object? err = throwOnFix;
    if (err != null) throw err;
    return Position(
      latitude: 1,
      longitude: 2,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      accuracy: 5,
      altitude: 10,
      altitudeAccuracy: 3,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

/// An IpGeoService backed by a scripted fetcher (no network). Returns an
/// ipinfo-shaped body so the fallback resolves a real coordinate.
IpGeoService _ipGeoReturning({double lat = 40.5, double lon = -111.9}) {
  return IpGeoService(
    client: JsonHttpClient(
      fetcher: (Uri url, Duration timeout) async => <String, dynamic>{
        'ip': '203.0.113.5',
        'city': 'Salt Lake City',
        'region': 'Utah',
        'country': 'US',
        'loc': '$lat,$lon',
        'org': 'AS396325 Fusion Networks',
      },
    ),
  );
}

/// An IpGeoService whose lookup fails (transport error on both providers).
IpGeoService _ipGeoFailing() {
  return IpGeoService(
    client: JsonHttpClient(
      fetcher: (Uri url, Duration timeout) async => throw const JsonHttpException(
        JsonHttpErrorKind.transport,
        'unreachable',
      ),
    ),
  );
}

void main() {
  late GeolocatorPlatform original;

  setUp(() {
    original = GeolocatorPlatform.instance;
  });

  tearDown(() {
    GeolocatorPlatform.instance = original;
  });

  test('no GPS fix + granted → IP-approximate fix, flagged, no altitude',
      () async {
    GeolocatorPlatform.instance = _MockGeolocator(
      serviceEnabled: true,
      permission: LocationPermission.whileInUse,
      throwOnFix: PositionUpdateException('no fix'),
    );

    final DeviceLocation loc = DeviceLocation(ipGeo: _ipGeoReturning());
    final LocationResult result = await loc.currentLocation();

    expect(result, isA<LocationSuccess>());
    final LocationFix fix = (result as LocationSuccess).fix;
    expect(fix.source, LocationSource.ipApproximate);
    expect(fix.isApproximate, isTrue);
    expect(fix.latitude, closeTo(40.5, 1e-9));
    expect(fix.longitude, closeTo(-111.9, 1e-9));
    // IP fixes carry no altitude and no fabricated accuracy.
    expect(fix.altitudeMeters, isNull);
    expect(fix.accuracyMeters, isNull);
  });

  test('a timeout no-fix also triggers the IP fallback', () async {
    GeolocatorPlatform.instance = _MockGeolocator(
      throwOnFix: TimeoutException('GPS timed out'),
    );
    final DeviceLocation loc = DeviceLocation(ipGeo: _ipGeoReturning());
    final LocationResult result = await loc.currentLocation();
    expect(result, isA<LocationSuccess>());
    expect((result as LocationSuccess).fix.isApproximate, isTrue);
  });

  test('no fix AND IP lookup fails → honest LocationUnavailable, no point',
      () async {
    GeolocatorPlatform.instance = _MockGeolocator(
      throwOnFix: PositionUpdateException('no fix'),
    );
    final DeviceLocation loc = DeviceLocation(ipGeo: _ipGeoFailing());
    final LocationResult result = await loc.currentLocation();
    expect(result, isA<LocationUnavailable>());
  });

  test('a real GPS fix is returned as coreLocation (no fallback)', () async {
    GeolocatorPlatform.instance = _MockGeolocator(); // resolves a fix
    final DeviceLocation loc = DeviceLocation(ipGeo: _ipGeoReturning());
    final LocationResult result = await loc.currentLocation();
    expect(result, isA<LocationSuccess>());
    final LocationFix fix = (result as LocationSuccess).fix;
    expect(fix.source, LocationSource.coreLocation);
    expect(fix.isApproximate, isFalse);
    expect(fix.latitude, 1);
  });

  test('services disabled → LocationBlocked, IP fallback never fires',
      () async {
    GeolocatorPlatform.instance = _MockGeolocator(serviceEnabled: false);
    // A failing IP service would still not matter — the fallback must not run
    // for a user-fixable state.
    final DeviceLocation loc = DeviceLocation(ipGeo: _ipGeoReturning());
    final LocationResult result = await loc.currentLocation();
    expect(result, isA<LocationBlocked>());
    expect((result as LocationBlocked).serviceDisabled, isTrue);
  });

  test('permission denied-forever → LocationBlocked, no IP fallback', () async {
    GeolocatorPlatform.instance = _MockGeolocator(
      permission: LocationPermission.deniedForever,
    );
    final DeviceLocation loc = DeviceLocation(ipGeo: _ipGeoReturning());
    final LocationResult result = await loc.currentLocation();
    expect(result, isA<LocationBlocked>());
    expect((result as LocationBlocked).serviceDisabled, isFalse);
  });

  test(
      'PermissionDeniedException thrown from getCurrentPosition → '
      'LocationBlocked (Settings), never the IP fallback', () async {
    // The race case: services on + permission whileInUse at check time, but the
    // OS revokes permission and getCurrentPosition throws. This is user-fixable
    // and must route to Settings, NOT get swapped for an IP lookup. The IP
    // service here RETURNS a coordinate — if the fallback wrongly fired we would
    // see a LocationSuccess, so this asserts the narrowed catch.
    GeolocatorPlatform.instance = _MockGeolocator(
      serviceEnabled: true,
      permission: LocationPermission.whileInUse,
      throwOnFix: const PermissionDeniedException('revoked mid-read'),
    );
    final DeviceLocation loc = DeviceLocation(ipGeo: _ipGeoReturning());
    final LocationResult result = await loc.currentLocation();
    expect(result, isA<LocationBlocked>());
    expect((result as LocationBlocked).serviceDisabled, isFalse);
  });

  test(
      'LocationServiceDisabledException thrown from getCurrentPosition → '
      'LocationBlocked(serviceDisabled), no IP fallback', () async {
    // Location Services switched off between the check and the read. Also
    // user-fixable → Settings, never the IP fallback.
    GeolocatorPlatform.instance = _MockGeolocator(
      serviceEnabled: true,
      permission: LocationPermission.whileInUse,
      throwOnFix: const LocationServiceDisabledException(),
    );
    final DeviceLocation loc = DeviceLocation(ipGeo: _ipGeoReturning());
    final LocationResult result = await loc.currentLocation();
    expect(result, isA<LocationBlocked>());
    expect((result as LocationBlocked).serviceDisabled, isTrue);
  });
}
