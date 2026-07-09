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
//   * off-Android shows the honest per-platform unavailable state and never
//     scans; Windows copy says the path isn't wired yet (not an Apple block).
//   * Location-gate and Wi-Fi-off empty states.
//   * sort control reorders the list.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ap_scan_screen.dart';
import 'package:wlan_pros_toolbox/services/network/ap_scan_service.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart';
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
    testWidgets('iOS shows the honest OS-block copy, not a Windows-style note',
        (tester) async {
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(_payload(), platform: 'ios'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Runs on Android'), findsOneWidget);
      expect(
        find.textContaining('iOS and macOS block nearby-AP scanning'),
        findsOneWidget,
      );
      // No list, no AP names off-Android.
      expect(find.text('KeithNet'), findsNothing);
    });

    testWidgets('Windows says the scan path is not wired yet (never an Apple '
        'block, never "can\'t")', (tester) async {
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(_payload(), platform: 'windows'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not wired for Windows yet'), findsOneWidget);
      expect(
        find.textContaining('Windows can list nearby access points'),
        findsOneWidget,
      );
      // Must NOT blame Apple or claim Windows fundamentally can't scan.
      expect(find.textContaining('Apple'), findsNothing);
      expect(find.textContaining('block'), findsNothing);
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
      expect(find.text('Runs on Android'), findsOneWidget);
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

  group('ApScanScreen — Pi-hosted scan-radio picker', () {
    http.Response jsonResp(Object body, {int status = 200}) =>
        http.Response(jsonEncode(body), status,
            headers: <String, String>{'content-type': 'application/json'});

    // One Pi BSS (the `/toolboxapi/scan` wire shape).
    Map<String, dynamic> nets() => <String, dynamic>{
          'nets': <dynamic>[
            <String, dynamic>{
              'ssid': 'KeithNet',
              'bssid': 'a4:83:e7:00:11:22',
              'signal': -42,
              'freq': 5180,
              'key_mgmt': 'wpa2',
            },
          ],
        };

    /// A Pi-backed [ApScanService] whose MockClient serves the interface list
    /// and the scan, capturing the `interface` query the scan was run with.
    ApScanService piService({
      required List<Map<String, dynamic>> interfaces,
      int interfacesStatus = 200,
      List<String>? interfaceCalls,
      List<String?>? scanInterfaceCalls,
    }) {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/toolboxapi/scan-interfaces') {
          interfaceCalls?.add(req.url.path);
          if (interfacesStatus != 200) {
            return jsonResp(<String, dynamic>{'error': 'boom'},
                status: interfacesStatus);
          }
          return jsonResp(<String, dynamic>{'interfaces': interfaces});
        }
        if (req.url.path == '/toolboxapi/scan') {
          scanInterfaceCalls?.add(req.url.queryParameters['interface']);
          return jsonResp(nets());
        }
        return jsonResp(<String, dynamic>{}, status: 404);
      });
      return ApScanService(
        piBackedOverride: true,
        piClient:
            PiBackendClient(httpClient: mock, base: Uri.parse('http://pi.local/')),
      );
    }

    testWidgets('two radios render the picker and default to wlan0',
        (tester) async {
      await tester.pumpWidget(host(ApScanScreen(
        service: piService(interfaces: <Map<String, dynamic>>[
          <String, dynamic>{'name': 'wlan0', 'driver': 'mt7921u'},
          <String, dynamic>{'name': 'wlan1', 'driver': 'iwlwifi'},
        ]),
      )));
      await tester.pumpAndSettle();

      // Picker label + the default (wlan0) selection shown in the closed control.
      expect(find.text('Scan radio'), findsOneWidget);
      expect(find.text('wlan0 (mt7921u)'), findsWidgets);
      // The scan still renders on the Pi path.
      expect(find.text('KeithNet'), findsOneWidget);
    });

    testWidgets('choosing wlan1 re-scans on the chosen interface',
        (tester) async {
      final List<String?> scanCalls = <String?>[];
      await tester.pumpWidget(host(ApScanScreen(
        service: piService(
          interfaces: <Map<String, dynamic>>[
            <String, dynamic>{'name': 'wlan0', 'driver': 'mt7921u'},
            <String, dynamic>{'name': 'wlan1', 'driver': 'iwlwifi'},
          ],
          scanInterfaceCalls: scanCalls,
        ),
      )));
      await tester.pumpAndSettle();

      // The seed + fresh initial scans ran on the wlan0 default.
      expect(scanCalls, everyElement('wlan0'));

      // Open the select (tap its closed-state value) and pick wlan1.
      await tester.tap(find.text('wlan0 (mt7921u)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('wlan1 (iwlwifi)').last);
      await tester.pumpAndSettle();

      // The most recent scan was threaded onto wlan1.
      expect(scanCalls.last, 'wlan1');
    });

    testWidgets('a single radio shows no picker (no clutter)', (tester) async {
      await tester.pumpWidget(host(ApScanScreen(
        service: piService(interfaces: <Map<String, dynamic>>[
          <String, dynamic>{'name': 'wlan0', 'driver': 'mt7921u'},
        ]),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Scan radio'), findsNothing);
      // The scan still runs and renders.
      expect(find.text('KeithNet'), findsOneWidget);
    });

    testWidgets('scan-interfaces failure falls back to wlan0 with no picker',
        (tester) async {
      final List<String?> scanCalls = <String?>[];
      await tester.pumpWidget(host(ApScanScreen(
        service: piService(
          interfaces: const <Map<String, dynamic>>[],
          interfacesStatus: 500,
          scanInterfaceCalls: scanCalls,
        ),
      )));
      await tester.pumpAndSettle();

      // Graceful: no picker, no crash, and the scan defaulted to wlan0.
      expect(find.text('Scan radio'), findsNothing);
      expect(find.text('KeithNet'), findsOneWidget);
      expect(scanCalls, everyElement('wlan0'));
    });
  });

  group('ApScanService.platformStatus — honest per-platform mapping', () {
    ApScanService svc(String os) => ApScanService(
          platformOverride: os,
          invoke: (String method, [dynamic args]) async => _payload(),
        );

    test('android is the supported (wired) status', () {
      expect(svc('android').platformStatus, ApScanPlatformStatus.supported);
    });

    test('ios and macOS map to an OS-level Apple restriction', () {
      expect(svc('ios').platformStatus, ApScanPlatformStatus.appleRestricted);
      expect(svc('macos').platformStatus, ApScanPlatformStatus.appleRestricted);
    });

    test('windows maps to not-wired-yet, NOT an OS block', () {
      expect(
        svc('windows').platformStatus,
        ApScanPlatformStatus.windowsNotWired,
      );
    });

    test('other native platforms map to generic unavailable', () {
      expect(svc('linux').platformStatus, ApScanPlatformStatus.unavailable);
    });
  });
}
