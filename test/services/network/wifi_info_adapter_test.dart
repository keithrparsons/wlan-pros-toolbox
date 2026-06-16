// MacWifiInfoAdapter — the Location-permission timeout guard (fix/tmc-macos-hang).
//
// macOS gates the network NAME behind a CLLocationManager authorization request.
// In notarized non-App-Store builds the system prompt can fail to surface, or
// the delegate callback never fires, so the native `requestLocationPermission`
// call never resolves. Before the fix, EVERY caller (Test My Connection and the
// pro Wi-Fi Information tool) awaited that call unbounded and hung forever.
//
// These tests prove the adapter bounds the wait: a never-completing native
// channel resolves to `false` (treated as "not authorized") within the
// timeout instead of hanging, and a normally-resolving channel is unaffected.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security.dart';

void main() {
  // A WifiInfoService whose native channel NEVER answers — models the stalled
  // CLLocationManager prompt. platformOverride 'macos' keeps the service on its
  // supported path so it actually reaches the (hanging) invoke.
  WifiInfoService neverResolvingService() => WifiInfoService(
        invoke: (String method, [dynamic args]) => Completer<Object?>().future,
        platformOverride: 'macos',
      );

  test(
    'requestNamePermission() returns false (does not hang) when the native '
    'channel never resolves',
    () async {
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(
        service: neverResolvingService(),
        permissionTimeout: const Duration(milliseconds: 50),
      );

      // Without the timeout this await would never complete. The test's own
      // timeout is the backstop proving the bound is the adapter's, not flutter
      // _test's: the call resolves well inside it.
      final bool authorized = await adapter
          .requestNamePermission()
          .timeout(const Duration(seconds: 2));

      // A stalled prompt degrades honestly to "not authorized" — never a hang,
      // never a fabricated "true".
      expect(authorized, isFalse);
    },
  );

  test(
    'requestNamePermission() passes through a real answer when the channel '
    'resolves in time',
    () async {
      final WifiInfoService service = WifiInfoService(
        invoke: (String method, [dynamic args]) async => true,
        platformOverride: 'macos',
      );
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(
        service: service,
        permissionTimeout: const Duration(seconds: 3),
      );

      expect(await adapter.requestNamePermission(), isTrue);
    },
  );

  test(
    'requestNamePermission() default ceiling is GENEROUS (30s) — long enough '
    'for the interactive grant to wait for the user, still a hang-safety',
    () async {
      // The interactive grant must not time out before a user can click Allow
      // (~4s). A real delegate response that lands shortly after the prompt
      // resolves authorized within the default ceiling. We model that response
      // arriving after a small delay and assert it passes through (it is NOT
      // cut off to false by a too-tight 3s bound). Uses the DEFAULT ceiling.
      final WifiInfoService service = WifiInfoService(
        invoke: (String method, [dynamic args]) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return true;
        },
        platformOverride: 'macos',
      );
      // No permissionTimeout override → exercises the 30s default ceiling.
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(service: service);

      expect(await adapter.requestNamePermission(), isTrue);
    },
  );

  // The no-prompt current-authorization path used by a connection check: it
  // reports the CURRENT status without surfacing a prompt, and is bounded so it
  // can never hang either.
  test(
    'currentNameAuthorization() reports the current status without prompting',
    () async {
      final WifiInfoService service = WifiInfoService(
        invoke: (String method, [dynamic args]) async {
          // The no-prompt path hits isLocationAuthorized, never the prompt.
          expect(method, 'isLocationAuthorized');
          return true;
        },
        platformOverride: 'macos',
      );
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(service: service);

      expect(await adapter.currentNameAuthorization(), isTrue);
    },
  );

  test(
    'currentNameAuthorization() returns false (does not hang) when the native '
    'status channel never resolves',
    () async {
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(
        service: neverResolvingService(),
        fetchTimeout: const Duration(milliseconds: 50),
      );

      final bool authorized = await adapter
          .currentNameAuthorization()
          .timeout(const Duration(seconds: 2));

      expect(authorized, isFalse);
    },
  );

  // The TRI-STATE no-prompt status path that drives the auto-prompt vs deep-link
  // decision on screen. It hits the native `locationAuthorizationStatus` token
  // channel (never the prompt) and maps the token to the enum.
  test(
    'nameAuthorizationStatus() maps the native token to the tri-state enum, no '
    'prompt',
    () async {
      for (final ({String token, LocationAuthStatus expected}) c
          in <({String token, LocationAuthStatus expected})>[
        (token: 'authorized', expected: LocationAuthStatus.authorized),
        (token: 'notDetermined', expected: LocationAuthStatus.notDetermined),
        (token: 'denied', expected: LocationAuthStatus.denied),
        (token: 'restricted', expected: LocationAuthStatus.restricted),
      ]) {
        final WifiInfoService service = WifiInfoService(
          invoke: (String method, [dynamic args]) async {
            // The tri-state path hits the status token, never the prompt.
            expect(method, 'locationAuthorizationStatus');
            return c.token;
          },
          platformOverride: 'macos',
        );
        final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(service: service);
        expect(await adapter.nameAuthorizationStatus(), c.expected);
      }
    },
  );

  test(
    'nameAuthorizationStatus() defaults to notDetermined (the promptable, safe '
    'default) when the native status channel never resolves',
    () async {
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(
        service: neverResolvingService(),
        fetchTimeout: const Duration(milliseconds: 50),
      );

      final LocationAuthStatus status = await adapter
          .nameAuthorizationStatus()
          .timeout(const Duration(seconds: 2));

      expect(status, LocationAuthStatus.notDetermined);
    },
  );

  // The same hang class on the SNAPSHOT read: a CoreWLAN read that never
  // returns must not hang any caller. The adapter bounds fetch() and degrades
  // to a typed channelError, which every caller already handles.
  test(
    'fetch() throws WifiInfoUnavailable (does not hang) when the native '
    'channel never resolves',
    () async {
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(
        service: neverResolvingService(),
        fetchTimeout: const Duration(milliseconds: 50),
      );

      // Without the bound this await would never complete. The outer 2s test
      // timeout is the backstop: the call must resolve (by throwing) well
      // inside it, proving the bound is the adapter's.
      await expectLater(
        adapter.fetch().timeout(const Duration(seconds: 2)),
        throwsA(
          isA<WifiInfoUnavailable>().having(
            (WifiInfoUnavailable e) => e.reason,
            'reason',
            WifiInfoUnavailableReason.channelError,
          ),
        ),
      );
    },
  );

  test(
    'fetch() returns the snapshot when the channel resolves in time',
    () async {
      final WifiInfoService service = WifiInfoService(
        invoke: (String method, [dynamic args]) async =>
            <String, Object?>{'poweredOn': true, 'ssid': 'TestNet'},
        platformOverride: 'macos',
      );
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(
        service: service,
        fetchTimeout: const Duration(seconds: 3),
      );

      final ConnectedAp ap = await adapter.fetch();
      expect(ap.ssid, 'TestNet');
      expect(ap.poweredOn, isTrue);
    },
  );

  // ---- AndroidWifiInfoAdapter (Phase 2) --------------------------------

  // A WifiInfoService on the Android supported path with an injectable invoke.
  WifiInfoService androidService(
    Future<Object?> Function(String method, [dynamic args]) invoke,
  ) =>
      WifiInfoService(invoke: invoke, platformOverride: 'android');

  group('AndroidWifiInfoAdapter', () {
    test('platformLabel is "Android" and it gates the name behind a permission',
        () {
      final adapter = AndroidWifiInfoAdapter(
        service: androidService((m, [a]) async => null),
      );
      expect(adapter.platformLabel, 'Android');
      expect(adapter.gatesNameBehindPermission, isTrue);
    });

    test('fetch() maps a connected WifiManager snapshot, noise/SNR honest-null',
        () async {
      final adapter = AndroidWifiInfoAdapter(
        service: androidService((method, [args]) async {
          expect(method, 'getWifiInfo');
          return <String, Object?>{
            'poweredOn': true,
            'ssid': 'WLANPros',
            'bssid': 'aa:bb:cc:dd:ee:ff',
            'rssiDbm': -52,
            'noiseDbm': null,
            'snrDb': null,
            'txRateMbps': 1200,
            'phyMode': '802.11ax (Wi-Fi 6)',
            'channel': 36,
            'band': '5 GHz',
            'securityToken': 'wpa2Personal',
            'locationAuthorized': true,
          };
        }),
      );

      final ConnectedAp ap = await adapter.fetch();
      expect(ap.ssid, 'WLANPros');
      expect(ap.bssid, 'aa:bb:cc:dd:ee:ff');
      expect(ap.rssiDbm, -52);
      expect(ap.txRateMbps, 1200.0);
      expect(ap.standard, '802.11ax (Wi-Fi 6)');
      expect(ap.band, '5 GHz');
      expect(ap.securityType, WifiSecurity.wpa2Personal);
      // GL-005: Android exposes neither, so they are never estimated.
      expect(ap.noiseDbm, isNull);
      expect(ap.snrDb, isNull);
      expect(ap.snrDerived, isFalse);
      // Android CAN expose Rx (so the row is shown when present, "not in this
      // reading" otherwise) — never "not on this platform".
      expect(ap.rxRateAvailable, isTrue);
      // No channel width in this reading → the row says "Not reported".
      expect(ap.channelWidthAvailable, isFalse);
      expect(ap.securityAvailable, isTrue);
    });

    test('fetch() maps a Location-denied snapshot to null SSID/BSSID', () async {
      final adapter = AndroidWifiInfoAdapter(
        service: androidService((method, [args]) async => <String, Object?>{
              'poweredOn': true,
              'ssid': null,
              'bssid': null,
              'rssiDbm': -60,
              'txRateMbps': 200,
              'channel': 6,
              'band': '2.4 GHz',
              'securityToken': null,
              'locationAuthorized': false,
            }),
      );

      final ConnectedAp ap = await adapter.fetch();
      // The RF fields resolve without Location; only the NAME is gated.
      expect(ap.ssid, isNull);
      expect(ap.bssid, isNull);
      expect(ap.rssiDbm, -60);
      expect(ap.txRateMbps, 200.0);
      expect(ap.band, '2.4 GHz');
    });

    test('fetch() throws channelError (does not hang) on a stalled channel',
        () async {
      final adapter = AndroidWifiInfoAdapter(
        service: WifiInfoService(
          invoke: (m, [a]) => Completer<Object?>().future,
          platformOverride: 'android',
        ),
        fetchTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        adapter.fetch().timeout(const Duration(seconds: 2)),
        throwsA(
          isA<WifiInfoUnavailable>().having(
            (e) => e.reason,
            'reason',
            WifiInfoUnavailableReason.channelError,
          ),
        ),
      );
    });

    test('requestNamePermission() passes through the runtime grant result',
        () async {
      var seen = '';
      final adapter = AndroidWifiInfoAdapter(
        service: androidService((method, [args]) async {
          seen = method;
          return true;
        }),
      );
      expect(await adapter.requestNamePermission(), isTrue);
      expect(seen, 'requestLocationPermission');
    });

    test('requestNamePermission() degrades to false (no hang) on a stalled '
        'permission dialog callback', () async {
      final adapter = AndroidWifiInfoAdapter(
        service: WifiInfoService(
          invoke: (m, [a]) => Completer<Object?>().future,
          platformOverride: 'android',
        ),
        permissionTimeout: const Duration(milliseconds: 50),
      );
      final bool granted =
          await adapter.requestNamePermission().timeout(const Duration(seconds: 2));
      expect(granted, isFalse);
    });

    test('currentNameAuthorization() reports status without a prompt', () async {
      var seen = '';
      final adapter = AndroidWifiInfoAdapter(
        service: androidService((method, [args]) async {
          seen = method;
          return false;
        }),
      );
      expect(await adapter.currentNameAuthorization(), isFalse);
      expect(seen, 'isLocationAuthorized');
    });
  });

  // ---- ConnectedAp.fromAndroidWifiInfo mapping -------------------------

  group('ConnectedAp.fromAndroidWifiInfo', () {
    test('classifies the Android security token and never derives SNR', () {
      final ConnectedAp ap = ConnectedAp.fromAndroidWifiInfo(
        const WifiInfo(
          interfaceName: 'wlan0',
          ssid: 'Net',
          bssid: 'aa:bb:cc:dd:ee:ff',
          rssiDbm: -50,
          noiseDbm: null,
          snrDb: null,
          txRateMbps: 540,
          phyMode: '802.11ac (Wi-Fi 5)',
          channel: 149,
          channelWidthMhz: null,
          band: '5 GHz',
          countryCode: null,
          hardwareAddress: null,
          securityToken: 'wpa3Personal',
          poweredOn: true,
          locationAuthorized: true,
        ),
      );

      expect(ap.securityType, WifiSecurity.wpa3Personal);
      expect(ap.securityAvailable, isTrue);
      expect(ap.standard, '802.11ac (Wi-Fi 5)');
      expect(ap.snrDb, isNull);
      expect(ap.snrDerived, isFalse);
      expect(ap.bandDerived, isFalse);
    });
  });
}
