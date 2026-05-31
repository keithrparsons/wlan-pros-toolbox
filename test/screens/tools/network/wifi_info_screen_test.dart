import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';

/// A fake invoker that scripts channel responses for the screen tests.
///
/// Records how many times getWifiInfo is called so the location regrant flow
/// can be verified without a real platform channel.
class _FakeInvoker {
  _FakeInvoker(this.responses);

  final Map<String, Object?> responses;
  int getWifiInfoCalls = 0;
  int requestPermissionCalls = 0;

  Future<Object?> call(String method, [dynamic args]) async {
    switch (method) {
      case 'getWifiInfo':
        getWifiInfoCalls++;
        return responses['getWifiInfo'];
      case 'requestLocationPermission':
        requestPermissionCalls++;
        return responses['requestLocationPermission'];
      case 'isLocationAuthorized':
        return responses['isLocationAuthorized'];
    }
    return null;
  }
}

/// A complete payload: connected on a 6 GHz Wi-Fi 6E link with all fields.
Map<String, Object?> _fullPayload() => <String, Object?>{
      'interfaceName': 'en0',
      'poweredOn': true,
      'ssid': 'WLAN Pros 6E',
      'bssid': 'a4:83:e7:9a:bc:de',
      'rssiDbm': -47,
      'noiseDbm': -92,
      'snrDb': 45,
      'txRateMbps': 2401.0,
      'phyMode': '802.11ax',
      'channel': 37,
      'channelWidthMhz': 160,
      'band': '6 GHz',
      'countryCode': 'US',
      'hardwareAddress': 'a4:83:e7:11:22:33',
      'locationAuthorized': true,
    };

/// Location denied: RF metrics resolve, but SSID/BSSID are null.
Map<String, Object?> _denied() => <String, Object?>{
      'interfaceName': 'en0',
      'poweredOn': true,
      'ssid': null,
      'bssid': null,
      'rssiDbm': -47,
      'noiseDbm': -92,
      'snrDb': 45,
      'txRateMbps': 2401.0,
      'phyMode': '802.11ax',
      'channel': 37,
      'channelWidthMhz': 160,
      'band': '6 GHz',
      'countryCode': 'US',
      'hardwareAddress': 'a4:83:e7:11:22:33',
      'locationAuthorized': false,
    };

/// After granting: location reads authorized, but SSID is still null (the
/// documented macOS relaunch quirk).
Map<String, Object?> _grantedButPending() => <String, Object?>{
      ..._denied(),
      'locationAuthorized': true,
    };

void main() {
  Future<void> pump(WidgetTester tester, WifiInfoService service) async {
    await tester.pumpWidget(
      MaterialApp(home: WifiInfoScreen(service: service)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'full payload renders values with units; Wi-Fi 6E label; Rx Rate Unavailable',
    (WidgetTester tester) async {
      final _FakeInvoker invoker = _FakeInvoker(<String, Object?>{
        'getWifiInfo': _fullPayload(),
      });
      final WifiInfoService service = WifiInfoService(
        invoke: invoker.call,
        platformOverride: 'macos',
      );
      await pump(tester, service);

      expect(find.text('WLAN Pros 6E'), findsOneWidget);
      // Units are tied to the value, not the label.
      expect(find.text('-47 dBm'), findsOneWidget);
      expect(find.text('45 dB'), findsOneWidget);
      expect(find.text('2401 Mbps'), findsOneWidget);
      expect(find.text('160 MHz'), findsOneWidget);
      // 802.11ax on 6 GHz is Wi-Fi 6E, shown with both vocabularies.
      expect(find.text('802.11ax (Wi-Fi 6E)'), findsOneWidget);
      expect(find.text('37'), findsOneWidget);
      expect(find.text('6 GHz'), findsOneWidget);
      // Rx Rate and Tx Power are always-unavailable rows.
      expect(find.text('Unavailable'), findsNWidgets(2));
      expect(find.textContaining('Not exposed'), findsNWidgets(2));
    },
  );

  testWidgets(
    'location denied shows Grant card; tap re-fetches',
    (WidgetTester tester) async {
      final _FakeInvoker invoker = _FakeInvoker(<String, Object?>{
        'getWifiInfo': _denied(),
        'requestLocationPermission': true,
      });
      final WifiInfoService service = WifiInfoService(
        invoke: invoker.call,
        platformOverride: 'macos',
      );
      await pump(tester, service);

      expect(find.textContaining('Location'), findsWidgets);
      expect(find.text('Grant Location permission'), findsOneWidget);

      await tester.tap(find.text('Grant Location permission'));
      await tester.pumpAndSettle();
      expect(invoker.getWifiInfoCalls, 2);
    },
  );

  testWidgets(
    'post-grant pending shows relaunch copy, hides Grant button',
    (WidgetTester tester) async {
      final _FakeInvoker invoker = _FakeInvoker(<String, Object?>{
        'getWifiInfo': _denied(),
        'requestLocationPermission': true,
      });
      final WifiInfoService service = WifiInfoService(
        invoke: invoker.call,
        platformOverride: 'macos',
      );
      await pump(tester, service);
      // The refetch returns authorized + still-null SSID (relaunch quirk).
      invoker.responses['getWifiInfo'] = _grantedButPending();
      await tester.tap(find.text('Grant Location permission'));
      await tester.pumpAndSettle();

      expect(find.textContaining('relaunch'), findsOneWidget);
      expect(find.text('Grant Location permission'), findsNothing);
    },
  );

  testWidgets(
    'non-macOS renders unavailable view and never invokes',
    (WidgetTester tester) async {
      final _FakeInvoker invoker = _FakeInvoker(<String, Object?>{
        'getWifiInfo': _fullPayload(),
      });
      final WifiInfoService service = WifiInfoService(
        invoke: invoker.call,
        platformOverride: 'linux',
      );
      await pump(tester, service);

      // The unavailable view shows, and the channel is never touched.
      expect(invoker.getWifiInfoCalls, 0);
      // No live metric rows render off macOS.
      expect(find.text('802.11ax (Wi-Fi 6E)'), findsNothing);
    },
  );

  testWidgets(
    'app-bar refresh re-reads and confirms with a snackbar',
    (WidgetTester tester) async {
      final _FakeInvoker invoker = _FakeInvoker(<String, Object?>{
        'getWifiInfo': _fullPayload(),
      });
      final WifiInfoService service = WifiInfoService(
        invoke: invoker.call,
        platformOverride: 'macos',
      );
      await pump(tester, service);
      expect(invoker.getWifiInfoCalls, 1); // initial load

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      // The refresh actually re-reads, and confirms visibly so it is never
      // silent even when the values are unchanged.
      expect(invoker.getWifiInfoCalls, 2);
      expect(find.text('Wi-Fi information updated'), findsOneWidget);
    },
  );
}
