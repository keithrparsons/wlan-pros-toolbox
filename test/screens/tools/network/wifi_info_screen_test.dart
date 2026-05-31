// Widget tests for WifiInfoScreen.
//
// The service is the real WifiInfoService driven through its injectable seams:
// `platformOverride` forces the supported/unsupported path, and `invoke` is a
// fake method-channel function so no real CoreWLAN channel or network is hit.
//
// Coverage:
//  - full payload renders metric values; the Rx Rate row shows "Unavailable".
//  - location-denied shows the Grant card + button; tapping it requests
//    permission and re-fetches (a second getWifiInfo invoke).
//  - post-grant-pending shows the "may need an app relaunch" copy and hides
//    the Grant button.
//  - non-macOS renders NetworkUnavailableView and never calls the invoker.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_unavailable_view.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';

/// Builds a getWifiInfo payload map with sensible defaults; override per test.
Map<String, Object?> _payload({
  String? ssid = 'TestNet',
  String? bssid = 'aa:bb:cc:dd:ee:ff',
  int? rssiDbm = -52,
  int? noiseDbm = -95,
  int? snrDb = 43,
  double? txRateMbps = 866.7,
  String? phyMode = '802.11ac',
  int? channel = 44,
  int? channelWidthMhz = 80,
  String? band = '5 GHz',
  String? countryCode = 'US',
  String? interfaceName = 'en0',
  String? hardwareAddress = '11:22:33:44:55:66',
  bool poweredOn = true,
  bool locationAuthorized = true,
}) {
  return <String, Object?>{
    'interfaceName': interfaceName,
    'ssid': ssid,
    'bssid': bssid,
    'rssiDbm': rssiDbm,
    'noiseDbm': noiseDbm,
    'snrDb': snrDb,
    'txRateMbps': txRateMbps,
    'phyMode': phyMode,
    'channel': channel,
    'channelWidthMhz': channelWidthMhz,
    'band': band,
    'countryCode': countryCode,
    'hardwareAddress': hardwareAddress,
    'poweredOn': poweredOn,
    'locationAuthorized': locationAuthorized,
  };
}

void main() {
  group('WifiInfoScreen', () {
    testWidgets('full payload renders values; Rx Rate shows Unavailable',
        (tester) async {
      final service = WifiInfoService(
        platformOverride: 'macos',
        invoke: (String method, [dynamic args]) async {
          if (method == 'getWifiInfo') return _payload();
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(home: WifiInfoScreen(service: service)),
      );
      await tester.pumpAndSettle();

      // Representative live values from each section.
      expect(find.text('TestNet'), findsOneWidget); // SSID
      expect(find.text('-52'), findsOneWidget); // RSSI
      expect(find.text('43'), findsOneWidget); // SNR
      expect(find.text('44'), findsOneWidget); // Channel
      expect(find.text('5 GHz'), findsOneWidget); // Band
      expect(find.text('802.11ac'), findsOneWidget); // Standard

      // The Rx Rate row is hard-coded unavailable.
      expect(find.text('Rx Rate (Mbps)'), findsOneWidget);
      expect(find.text('Tx Power (dBm)'), findsOneWidget);
      // "Unavailable" appears for the two honesty rows.
      expect(find.text('Unavailable'), findsWidgets);
      expect(
        find.text('Not exposed by macOS CoreWLAN'),
        findsNWidgets(2),
      );

      // No Grant-Location card when the SSID is present.
      expect(find.text('Grant Location permission'), findsNothing);
    });

    testWidgets('location denied shows Grant card; tap re-fetches',
        (tester) async {
      var getWifiInfoCalls = 0;
      var requestPermissionCalls = 0;

      final service = WifiInfoService(
        platformOverride: 'macos',
        invoke: (String method, [dynamic args]) async {
          if (method == 'getWifiInfo') {
            getWifiInfoCalls++;
            return _payload(
              ssid: null,
              bssid: null,
              locationAuthorized: false,
            );
          }
          if (method == 'requestLocationPermission') {
            requestPermissionCalls++;
            return true;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(home: WifiInfoScreen(service: service)),
      );
      await tester.pumpAndSettle();

      expect(getWifiInfoCalls, 1);
      expect(
        find.textContaining('Network name needs Location permission'),
        findsOneWidget,
      );
      expect(find.text('Grant Location permission'), findsOneWidget);

      await tester.tap(find.text('Grant Location permission'));
      await tester.pumpAndSettle();

      expect(requestPermissionCalls, 1);
      // The grant triggers a second snapshot read.
      expect(getWifiInfoCalls, 2);
    });

    testWidgets('post-grant pending shows relaunch copy, hides Grant button',
        (tester) async {
      final service = WifiInfoService(
        platformOverride: 'macos',
        invoke: (String method, [dynamic args]) async {
          if (method == 'getWifiInfo') {
            // SSID stays null even though Location is now authorized — the
            // macOS post-grant relaunch quirk.
            return _payload(
              ssid: null,
              bssid: null,
              locationAuthorized: true,
            );
          }
          if (method == 'requestLocationPermission') return true;
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(home: WifiInfoScreen(service: service)),
      );
      await tester.pumpAndSettle();

      // Before any grant attempt, the original prompt + button show (state a):
      // not authorized OR name-missing → here name is missing.
      expect(find.text('Grant Location permission'), findsOneWidget);

      await tester.tap(find.text('Grant Location permission'));
      await tester.pumpAndSettle();

      // State (b): granted, ssid still null, attempt made.
      expect(
        find.textContaining('may need an app relaunch'),
        findsOneWidget,
      );
      expect(find.text('Grant Location permission'), findsNothing);
    });

    testWidgets('non-macOS renders unavailable view and never invokes',
        (tester) async {
      var invokeCalls = 0;
      final service = WifiInfoService(
        platformOverride: 'linux',
        invoke: (String method, [dynamic args]) async {
          invokeCalls++;
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(home: WifiInfoScreen(service: service)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NetworkUnavailableView), findsOneWidget);
      expect(invokeCalls, 0);
    });
  });
}
