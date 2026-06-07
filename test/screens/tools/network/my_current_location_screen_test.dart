// Tests for the My Current Location tool (BF5-16).
//
// The screen reuses the DeviceLocationService seam. These tests script each
// sealed outcome and verify the screen auto-runs on open and renders the
// correct state (success / approximate / needs-permission / blocked /
// unavailable) — without touching real hardware.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/my_current_location_screen.dart';
import 'package:wlan_pros_toolbox/services/location/device_location.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

class _FakeLocation implements DeviceLocationService {
  _FakeLocation({
    this.permission = LocationPermissionState.granted,
    this.afterRequest,
    this.result = const LocationNeedsPermission(),
  });

  LocationPermissionState permission;
  LocationPermissionState? afterRequest;
  LocationResult result;
  int settingsOpened = 0;
  int reads = 0;

  @override
  Future<LocationPermissionState> permissionState() async => permission;

  @override
  Future<LocationPermissionState> requestPermission() async {
    final LocationPermissionState next = afterRequest ?? permission;
    permission = next;
    return next;
  }

  @override
  Future<LocationResult> currentLocation() async {
    reads++;
    return result;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

const LocationFix _gpsFix = LocationFix(
  latitude: 40.7128,
  longitude: -74.0060,
  altitudeMeters: 12.3,
  accuracyMeters: 5,
  altitudeAccuracyMeters: 3,
);

const LocationFix _ipApproxFix = LocationFix(
  latitude: 40.5,
  longitude: -111.9,
  altitudeMeters: null,
  accuracyMeters: null,
  altitudeAccuracyMeters: null,
  source: LocationSource.ipApproximate,
);

Future<void> _pump(WidgetTester tester, DeviceLocationService loc) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: MyCurrentLocationScreen(location: loc),
    ),
  );
  // First frame paints the loading state; the post-frame callback then runs the
  // auto-read and the screen settles.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('auto-runs the fix on open and shows lat/long/altitude/accuracy',
      (tester) async {
    final _FakeLocation loc = _FakeLocation(
      permission: LocationPermissionState.granted,
      result: const LocationSuccess(_gpsFix),
    );
    await _pump(tester, loc);

    expect(loc.reads, greaterThanOrEqualTo(1)); // auto-ran without a tap
    expect(find.text('Latitude'), findsOneWidget);
    expect(find.text('40.712800'), findsOneWidget);
    expect(find.text('-74.006000'), findsOneWidget);
    expect(find.text('12.3 m'), findsOneWidget); // altitude
    expect(find.text('±5 m'), findsOneWidget); // accuracy
    expect(find.text('Update'), findsOneWidget);
  });

  testWidgets('Update gives visible feedback: SnackBar + Last updated stamp',
      (tester) async {
    final _FakeLocation loc = _FakeLocation(
      permission: LocationPermissionState.granted,
      result: const LocationSuccess(_gpsFix),
    );
    await _pump(tester, loc);

    // The auto-open read stamps a "Last updated" line, but does not raise the
    // confirmation SnackBar (that is reserved for a user-initiated Update).
    expect(find.textContaining('Last updated'), findsOneWidget);
    expect(find.text('Location updated'), findsNothing);

    final int readsBeforeUpdate = loc.reads;
    await tester.tap(find.text('Update'));
    await tester.pump(); // start the async read (loading state)
    await tester.pumpAndSettle(); // settle the read + SnackBar entrance

    expect(loc.reads, greaterThan(readsBeforeUpdate)); // Update re-read
    // Visible confirmation: the SnackBar AND the timestamp line.
    expect(find.text('Location updated'), findsOneWidget);
    expect(find.textContaining('Last updated'), findsOneWidget);
  });

  testWidgets('an IP-approximate fix is labeled honestly (not GPS)',
      (tester) async {
    final _FakeLocation loc = _FakeLocation(
      permission: LocationPermissionState.granted,
      result: const LocationSuccess(_ipApproxFix),
    );
    await _pump(tester, loc);

    expect(find.textContaining('public IP'), findsOneWidget);
    // Altitude/accuracy not reported → the honest unavailable treatment.
    expect(find.text('Not available on this platform'), findsWidgets);
  });

  testWidgets('needs-permission shows the grant action and requests on tap',
      (tester) async {
    final _FakeLocation loc = _FakeLocation(
      permission: LocationPermissionState.needsPermission,
      result: const LocationNeedsPermission(),
      afterRequest: LocationPermissionState.granted,
    );
    await _pump(tester, loc);

    expect(find.text('Use my location'), findsOneWidget);
    // After granting, the read returns a fix.
    loc.result = const LocationSuccess(_gpsFix);
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();
    expect(find.text('40.712800'), findsOneWidget);
  });

  testWidgets('blocked shows the Settings deep-link', (tester) async {
    final _FakeLocation loc = _FakeLocation(
      permission: LocationPermissionState.blocked,
      result: const LocationBlocked(serviceDisabled: true),
    );
    await _pump(tester, loc);

    expect(find.text('Open Settings'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    expect(loc.settingsOpened, 1);
  });

  testWidgets('a genuine no-fix shows the honest unavailable state',
      (tester) async {
    final _FakeLocation loc = _FakeLocation(
      permission: LocationPermissionState.granted,
      result: const LocationUnavailable('Timed out waiting for a GPS fix.'),
    );
    await _pump(tester, loc);

    expect(find.text('Location unavailable'), findsOneWidget);
    expect(find.text('Timed out waiting for a GPS fix.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
