import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';

void main() {
  group('WifiInfoService', () {
    test('maps a full payload including SNR and int/double rate coercion',
        () async {
      var calls = 0;
      Future<Object?> fakeInvoke(String method, [dynamic args]) async {
        calls++;
        expect(method, 'getWifiInfo');
        return <dynamic, dynamic>{
          'interfaceName': 'en0',
          'poweredOn': true,
          'ssid': 'WLANPros',
          'bssid': 'aa:bb:cc:dd:ee:ff',
          'rssiDbm': -52,
          'noiseDbm': -91,
          'snrDb': 39,
          // Arrives as an int here; must coerce to double.
          'txRateMbps': 1200,
          'phyMode': '802.11ax',
          'channel': 36,
          'channelWidthMhz': 80,
          'band': '5 GHz',
          'countryCode': 'US',
          'hardwareAddress': '11:22:33:44:55:66',
          'locationAuthorized': true,
        };
      }

      final service = WifiInfoService(
        invoke: fakeInvoke,
        platformOverride: 'macos',
      );
      final info = await service.fetch();

      expect(calls, 1);
      expect(info.interfaceName, 'en0');
      expect(info.poweredOn, isTrue);
      expect(info.ssid, 'WLANPros');
      expect(info.bssid, 'aa:bb:cc:dd:ee:ff');
      expect(info.rssiDbm, -52);
      expect(info.noiseDbm, -91);
      expect(info.snrDb, 39);
      expect(info.txRateMbps, 1200.0);
      expect(info.txRateMbps, isA<double>());
      expect(info.phyMode, '802.11ax');
      expect(info.channel, 36);
      expect(info.channelWidthMhz, 80);
      expect(info.band, '5 GHz');
      expect(info.countryCode, 'US');
      expect(info.hardwareAddress, '11:22:33:44:55:66');
      expect(info.locationAuthorized, isTrue);
    });

    test('coerces a double-valued txRateMbps', () async {
      Future<Object?> fakeInvoke(String method, [dynamic args]) async {
        return <dynamic, dynamic>{
          'poweredOn': true,
          'txRateMbps': 866.7,
          'locationAuthorized': true,
        };
      }

      final service = WifiInfoService(
        invoke: fakeInvoke,
        platformOverride: 'macos',
      );
      final info = await service.fetch();
      expect(info.txRateMbps, 866.7);
    });

    test('maps a partial payload with null SSID/BSSID and no location',
        () async {
      Future<Object?> fakeInvoke(String method, [dynamic args]) async {
        return <dynamic, dynamic>{
          'interfaceName': 'en0',
          'poweredOn': true,
          'ssid': null,
          'bssid': null,
          'rssiDbm': -60,
          'noiseDbm': null,
          'snrDb': null,
          'txRateMbps': null,
          'phyMode': null,
          'channel': null,
          'channelWidthMhz': null,
          'band': null,
          'countryCode': null,
          'hardwareAddress': null,
          'locationAuthorized': false,
        };
      }

      final service = WifiInfoService(
        invoke: fakeInvoke,
        platformOverride: 'macos',
      );
      final info = await service.fetch();

      expect(info.ssid, isNull);
      expect(info.bssid, isNull);
      expect(info.snrDb, isNull);
      expect(info.txRateMbps, isNull);
      expect(info.poweredOn, isTrue);
      expect(info.locationAuthorized, isFalse);
    });

    test('throws unsupportedPlatform off macOS without calling invoke',
        () async {
      var calls = 0;
      Future<Object?> fakeInvoke(String method, [dynamic args]) async {
        calls++;
        return null;
      }

      final service = WifiInfoService(
        invoke: fakeInvoke,
        platformOverride: 'linux',
      );

      await expectLater(
        service.fetch(),
        throwsA(
          isA<WifiInfoUnavailable>().having(
            (e) => e.reason,
            'reason',
            WifiInfoUnavailableReason.unsupportedPlatform,
          ),
        ),
      );
      expect(calls, 0);
    });

    test('wraps a PlatformException as channelError', () async {
      Future<Object?> fakeInvoke(String method, [dynamic args]) async {
        throw PlatformException(code: 'boom', message: 'no interface');
      }

      final service = WifiInfoService(
        invoke: fakeInvoke,
        platformOverride: 'macos',
      );

      await expectLater(
        service.fetch(),
        throwsA(
          isA<WifiInfoUnavailable>().having(
            (e) => e.reason,
            'reason',
            WifiInfoUnavailableReason.channelError,
          ),
        ),
      );
    });

    test('requestLocationPermission passes through the invoker', () async {
      var seen = '';
      Future<Object?> fakeInvoke(String method, [dynamic args]) async {
        seen = method;
        return true;
      }

      final service = WifiInfoService(
        invoke: fakeInvoke,
        platformOverride: 'macos',
      );
      final granted = await service.requestLocationPermission();
      expect(seen, 'requestLocationPermission');
      expect(granted, isTrue);
    });

    test('isLocationAuthorized passes through the invoker', () async {
      var seen = '';
      Future<Object?> fakeInvoke(String method, [dynamic args]) async {
        seen = method;
        return false;
      }

      final service = WifiInfoService(
        invoke: fakeInvoke,
        platformOverride: 'macos',
      );
      final authorized = await service.isLocationAuthorized();
      expect(seen, 'isLocationAuthorized');
      expect(authorized, isFalse);
    });

    test('openLocationSettings invokes the deep-link channel method', () async {
      var seen = '';
      var calls = 0;
      Future<Object?> fakeInvoke(String method, [dynamic args]) async {
        seen = method;
        calls++;
        return true;
      }

      final service = WifiInfoService(
        invoke: fakeInvoke,
        platformOverride: 'macos',
      );
      final opened = await service.openLocationSettings();
      expect(seen, 'openLocationSettings');
      expect(calls, 1);
      expect(opened, isTrue);
    });

    // ---- Android platform gate (Phase 2) -------------------------------

    test('isSupportedPlatform is true on Android (Phase 2 native bridge)', () {
      final service = WifiInfoService(
        invoke: (m, [a]) async => null,
        platformOverride: 'android',
      );
      expect(service.isSupportedPlatform, isTrue);
    });

    test('isSupportedPlatform stays true on macOS', () {
      final service = WifiInfoService(
        invoke: (m, [a]) async => null,
        platformOverride: 'macos',
      );
      expect(service.isSupportedPlatform, isTrue);
    });

    test('isSupportedPlatform is false on an unsupported native platform', () {
      final service = WifiInfoService(
        invoke: (m, [a]) async => null,
        platformOverride: 'linux',
      );
      expect(service.isSupportedPlatform, isFalse);
    });

    test('fetch() reaches the channel on Android and maps the payload',
        () async {
      var calls = 0;
      Future<Object?> fakeInvoke(String method, [dynamic args]) async {
        calls++;
        expect(method, 'getWifiInfo');
        return <dynamic, dynamic>{
          'interfaceName': 'wlan0',
          'poweredOn': true,
          'ssid': 'WLANPros',
          'bssid': 'aa:bb:cc:dd:ee:ff',
          'rssiDbm': -47,
          // Android exposes no noise floor → SNR cannot be computed.
          'noiseDbm': null,
          'snrDb': null,
          'txRateMbps': 866,
          'rxRateMbps': 780,
          'phyMode': '802.11ax (Wi-Fi 6)',
          'channel': 36,
          'channelWidthMhz': null,
          'band': '5 GHz',
          'countryCode': null,
          'hardwareAddress': null,
          'securityToken': 'wpa3Personal',
          'locationAuthorized': true,
        };
      }

      final service = WifiInfoService(
        invoke: fakeInvoke,
        platformOverride: 'android',
      );
      final info = await service.fetch();

      expect(calls, 1);
      expect(info.ssid, 'WLANPros');
      expect(info.bssid, 'aa:bb:cc:dd:ee:ff');
      expect(info.rssiDbm, -47);
      // Honest nulls: Android cannot read noise / SNR.
      expect(info.noiseDbm, isNull);
      expect(info.snrDb, isNull);
      expect(info.txRateMbps, 866.0);
      expect(info.channel, 36);
      expect(info.band, '5 GHz');
      expect(info.securityToken, 'wpa3Personal');
      expect(info.locationAuthorized, isTrue);
    });
  });
}
