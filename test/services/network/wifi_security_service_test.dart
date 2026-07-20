// WifiSecurityService — Dart-side mapping of the iOS NEHotspotNetwork channel.
//
// Exercises the result mapping through an injected invoker, so no real platform
// channel is needed. Confirms the honest-unavailable behavior and the payload
// → WifiSecurityInfo mapping.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security_service.dart';

void main() {
  group('WifiSecurityService.fetch', () {
    test('maps an available payload into WifiSecurityInfo', () async {
      final WifiSecurityService svc = WifiSecurityService(
        invoke: (String method, [dynamic args]) async {
          expect(method, 'getSecurityInfo');
          return <String, Object?>{
            'available': true,
            'reason': null,
            'securityToken': 'personal',
            'bssid': 'a4:83:e7:00:11:22',
            'ssid': 'KeithNet',
            'locationAuthorized': true,
            'locationAuthStatus': 'authorized',
          };
        },
      );
      final WifiSecurityInfo info = await svc.fetch();
      expect(info.available, isTrue);
      expect(info.securityToken, 'personal');
      expect(info.bssid, 'a4:83:e7:00:11:22');
      expect(info.locationAuth, LocationAuthStatus.authorized);
      expect(info.reason, isNull);
    });

    test('maps an unavailable payload with an honest reason', () async {
      final WifiSecurityService svc = WifiSecurityService(
        invoke: (String method, [dynamic args]) async => <String, Object?>{
          'available': false,
          'reason': 'Location permission is needed.',
          'securityToken': null,
          'bssid': null,
          'ssid': null,
          'locationAuthorized': false,
        },
      );
      final WifiSecurityInfo info = await svc.fetch();
      expect(info.available, isFalse);
      expect(info.reason, 'Location permission is needed.');
      expect(info.securityToken, isNull);
      expect(info.bssid, isNull);
    });

    test('a MissingPluginException (off iOS) resolves to honest unavailable',
        () async {
      final WifiSecurityService svc = WifiSecurityService(
        invoke: (String method, [dynamic args]) async =>
            throw MissingPluginException('no handler'),
      );
      final WifiSecurityInfo info = await svc.fetch();
      expect(info.available, isFalse);
      expect(info.reason, contains('platform'));
    });

    test('a PlatformException resolves to unavailable (never throws)', () async {
      final WifiSecurityService svc = WifiSecurityService(
        invoke: (String method, [dynamic args]) async =>
            throw PlatformException(code: 'ERR', message: 'channel boom'),
      );
      final WifiSecurityInfo info = await svc.fetch();
      expect(info.available, isFalse);
      expect(info.reason, 'channel boom');
    });

    test('a null payload is honest-unavailable', () async {
      final WifiSecurityService svc = WifiSecurityService(
        invoke: (String method, [dynamic args]) async => null,
      );
      final WifiSecurityInfo info = await svc.fetch();
      expect(info.available, isFalse);
      expect(info.reason, isNotNull);
    });
  });

  group('WifiSecurityService permission passthroughs', () {
    test('isLocationAuthorized passes through the invoker', () async {
      final WifiSecurityService svc = WifiSecurityService(
        invoke: (String method, [dynamic args]) async {
          expect(method, 'isLocationAuthorized');
          return true;
        },
      );
      expect(await svc.isLocationAuthorized(), isTrue);
    });

    test('isLocationAuthorized returns false off iOS (no handler)', () async {
      final WifiSecurityService svc = WifiSecurityService(
        invoke: (String method, [dynamic args]) async =>
            throw MissingPluginException('no handler'),
      );
      expect(await svc.isLocationAuthorized(), isFalse);
    });

    test('requestLocationPermission passes through the invoker', () async {
      final WifiSecurityService svc = WifiSecurityService(
        invoke: (String method, [dynamic args]) async {
          expect(method, 'requestLocationPermission');
          return true;
        },
      );
      expect(await svc.requestLocationPermission(), isTrue);
    });

    test('openLocationSettings passes through the invoker', () async {
      final WifiSecurityService svc = WifiSecurityService(
        invoke: (String method, [dynamic args]) async {
          expect(method, 'openLocationSettings');
          return true;
        },
      );
      expect(await svc.openLocationSettings(), isTrue);
    });
  });
}
