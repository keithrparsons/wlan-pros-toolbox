// Nearby AP Scan screen — widget tests (Android-only tool, H3).
//
// The screen reads APs through the Android `com.wlanpros.toolbox/ap_scan`
// method channel behind the [ApScanService] seam. The tests drive it with an
// [ApScanService] whose `invoke` is a fake and whose `platformOverride` selects
// the supported (android) or unsupported (ios) branch — no real channel.
//
// Covers the SOP-007 §5 state matrix plus the load-bearing honesty rules:
//   * list renders (SSID / BSSID / channel / band / RSSI).
//   * channel-occupancy bars render for 2.4 and 5 GHz.
//   * CLEAN fields only — no Noise / SNR / MCS column ever appears.
//   * off-Android (iOS) shows the honest "Android only" state and never scans.
//   * Location-gate and Wi-Fi-off empty states.
//   * sort control reorders the list.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ap_scan_screen.dart';
import 'package:wlan_pros_toolbox/services/network/ap_scan_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// Builds a native-shaped scan payload (the map the Kotlin channel returns).
Map<String, Object?> _payload({
  List<Map<String, Object?>>? aps,
  bool poweredOn = true,
  bool locationAuthorized = true,
  bool scanThrottled = false,
}) {
  return <String, Object?>{
    'poweredOn': poweredOn,
    'locationAuthorized': locationAuthorized,
    'scanThrottled': scanThrottled,
    'accessPoints': aps ??
        <Map<String, Object?>>[
          <String, Object?>{
            'ssid': 'KeithNet',
            'bssid': 'a4:83:e7:00:11:22',
            'rssiDbm': -42,
            'channel': 36,
            'band': '5 GHz',
            'frequencyMhz': 5180,
          },
          <String, Object?>{
            'ssid': 'Neighbor-2G',
            'bssid': 'b8:27:eb:aa:bb:cc',
            'rssiDbm': -71,
            'channel': 6,
            'band': '2.4 GHz',
            'frequencyMhz': 2437,
          },
          <String, Object?>{
            'ssid': null, // hidden network
            'bssid': 'c0:ff:ee:00:00:01',
            'rssiDbm': -80,
            'channel': 6,
            'band': '2.4 GHz',
            'frequencyMhz': 2437,
          },
        ],
  };
}

/// An [ApScanService] backed by a fake invoke that always returns [payload] for
/// scan/lastResults and reports Location granted. [platform] selects the
/// supported/unsupported branch.
ApScanService _service(
  Map<String, Object?> payload, {
  String platform = 'android',
}) {
  return ApScanService(
    platformOverride: platform,
    invoke: (String method, [dynamic args]) async {
      switch (method) {
        case 'scan':
        case 'lastResults':
          return payload;
        case 'isLocationAuthorized':
          return payload['locationAuthorized'];
        case 'requestLocationPermission':
          return true;
        case 'openLocationSettings':
          return true;
      }
      return null;
    },
  );
}

void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.dark(), home: child);

  group('ApScanScreen — Android (supported)', () {
    testWidgets('renders the AP list with SSID / BSSID / channel / band / RSSI',
        (tester) async {
      await tester.pumpWidget(host(ApScanScreen(service: _service(_payload()))));
      await tester.pumpAndSettle();

      expect(find.text('KeithNet'), findsOneWidget);
      expect(find.text('a4:83:e7:00:11:22'), findsOneWidget);
      expect(find.text('-42 dBm'), findsOneWidget);
      expect(find.text('ch 36 · 5 GHz'), findsOneWidget);
      // Hidden network renders an honest label, never a blank.
      expect(find.text('(hidden network)'), findsOneWidget);
    });

    testWidgets('renders channel-occupancy bars for 2.4 and 5 GHz',
        (tester) async {
      await tester.pumpWidget(host(ApScanScreen(service: _service(_payload()))));
      await tester.pumpAndSettle();

      expect(find.text('2.4 GHz channel occupancy'), findsOneWidget);
      expect(find.text('5 GHz channel occupancy'), findsOneWidget);
      // Channel 6 has two APs (Neighbor-2G + hidden) → "2 APs".
      expect(find.text('2 APs'), findsOneWidget);
      // Channel 36 has one AP → "1 AP".
      expect(find.text('1 AP'), findsWidgets);
    });

    testWidgets('CLEAN fields only — no Noise / SNR / MCS anywhere',
        (tester) async {
      await tester.pumpWidget(host(ApScanScreen(service: _service(_payload()))));
      await tester.pumpAndSettle();

      expect(find.textContaining('Noise'), findsNothing);
      expect(find.textContaining('SNR'), findsNothing);
      expect(find.textContaining('MCS'), findsNothing);
    });

    testWidgets('sort control reorders the list (Channel asc)',
        (tester) async {
      await tester.pumpWidget(host(ApScanScreen(service: _service(_payload()))));
      await tester.pumpAndSettle();

      // Tap the "Channel" sort segment.
      await tester.tap(find.text('Channel'));
      await tester.pumpAndSettle();

      // Channel-asc puts the ch-6 APs above the ch-36 AP. Find their row
      // vertical positions and assert the order.
      final double neighborY =
          tester.getTopLeft(find.text('Neighbor-2G')).dy;
      final double keithY = tester.getTopLeft(find.text('KeithNet')).dy;
      expect(neighborY, lessThan(keithY));
    });

    testWidgets('Wi-Fi off shows the off card and no list', (tester) async {
      final Map<String, Object?> off = _payload(
        aps: const <Map<String, Object?>>[],
        poweredOn: false,
      );
      await tester.pumpWidget(host(ApScanScreen(service: _service(off))));
      await tester.pumpAndSettle();

      expect(find.textContaining('Wi-Fi is off'), findsOneWidget);
    });

    testWidgets('Location not granted shows the Location-gate card',
        (tester) async {
      final Map<String, Object?> gated = _payload(
        aps: const <Map<String, Object?>>[],
        locationAuthorized: false,
      );
      await tester.pumpWidget(host(ApScanScreen(service: _service(gated))));
      await tester.pumpAndSettle();

      expect(find.text('Grant Location'), findsOneWidget);
      expect(
        find.textContaining('Location permission to read Wi-Fi scan'),
        findsOneWidget,
      );
    });

    testWidgets('throttled fresh scan surfaces the "last scan" note',
        (tester) async {
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(_payload(scanThrottled: true)))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Android throttled'), findsOneWidget);
      // The list still renders from the cached scan.
      expect(find.text('KeithNet'), findsOneWidget);
    });
  });

  group('ApScanScreen — off-Android (unsupported)', () {
    testWidgets('iOS shows the honest "Android only" state', (tester) async {
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(_payload(), platform: 'ios'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Android only'), findsOneWidget);
      // No list, no AP names off-Android.
      expect(find.text('KeithNet'), findsNothing);
    });

    testWidgets('off-Android never touches the scan channel', (tester) async {
      bool touched = false;
      final ApScanService svc = ApScanService(
        platformOverride: 'macos',
        invoke: (String method, [dynamic args]) async {
          if (method == 'scan' || method == 'lastResults') touched = true;
          return _payload();
        },
      );
      await tester.pumpWidget(host(ApScanScreen(service: svc)));
      await tester.pumpAndSettle();

      expect(touched, isFalse);
      expect(find.text('Android only'), findsOneWidget);
    });
  });

  group('ApScanScreen — channel error', () {
    testWidgets('channel error shows the error card + Retry', (tester) async {
      final ApScanService svc = ApScanService(
        platformOverride: 'android',
        invoke: (String method, [dynamic args]) async {
          if (method == 'scan' || method == 'lastResults') {
            throw PlatformException(code: 'ERR', message: 'scan failed');
          }
          return true;
        },
      );
      await tester.pumpWidget(host(ApScanScreen(service: svc)));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('scan failed'), findsOneWidget);
    });
  });
}
