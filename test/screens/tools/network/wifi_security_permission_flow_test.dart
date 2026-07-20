// Wi-Fi Information, SECURITY card — the iOS Location gate, driven across ALL
// FOUR authorization states.
//
// WHY THIS FILE EXISTS. This is instance #7 of the dead-control family
// ([[feedback_ui_rendered_a_decision_it_lacked]]), and it is a DIFFERENT SHAPE
// from #3 and #6. Those two screens already held a tri-state and simply failed
// to consult it. Here the tri-state did not exist anywhere in the stack: the
// iOS channel computed the CLAuthorizationStatus and then collapsed it to a
// bool (`isAuthorized`) BEFORE it crossed the method channel, so
// `WifiSecurityInfo` carried only `locationAuthorized`. A bool cannot
// distinguish "never asked" from "asked and refused", and iOS re-prompts only
// in the former: after a When-In-Use denial `requestWhenInUseAuthorization`
// returns without showing anything, forever. The Security card therefore
// rendered an unguarded `FilledButton('Grant Location')` in every unauthorized
// state, and under `denied` it was a button that could not act.
//
// WHY IT SURVIVED. Every fixture in the tree fed this path
// `locationAuthorized: true` (available network) or `false` (unavailable), and
// `false` was rendered identically whether the user had never been asked or had
// refused. `denied` and `restricted` had no name in the stack, so no test could
// name them, and the suite stayed green precisely BECAUSE the bit was missing.
//
// WHAT THIS FILE PINS. All four states, at the two layers the fix spans: the
// service-level token mapping (the bit that used to be destroyed in Swift) and
// the screen-level affordance driven by it. Each guard is asserted
// independently so that no single test carries two claims.
//
// EVIDENCE BOUNDARY (stated for the record): these are widget and unit tests.
// The Swift half of this change — that `authorizationStatusToken` emits the
// token this file feeds in, and that iOS genuinely does not re-prompt after a
// When-In-Use denial — is NOT executed here and rests on code reading plus
// Apple's documented CoreLocation behavior. No device run was available.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// An iOS bridge holding one live reading, so the screen has a [ConnectedAp]
/// and renders the Security card. The SSID comes from the Shortcut payload; the
/// security type does NOT (that is exactly what the native read supplies), so
/// the Security card is present and its value is missing — the shape that
/// exposes the Location gate.
class _LiveBridge implements WiFiDetailsBridge {
  @override
  Future<bool> consumeShortcutMissing() async => false;
  @override
  Future<void> markSetupInitiated() async {}
  @override
  Future<bool> hasInitiatedSetup() async => true;
  @override
  Future<bool> isShortcutsAppInstalled() async => true;
  @override
  Future<void> setLiveOriginRoute(String route) async {}
  @override
  Future<String?> consumeLiveErrorNav() async => null;
  @override
  Future<void> armLiveRun(String route) async {}
  @override
  Future<PendingLiveRun?> pendingLiveRun() async => null;
  @override
  Future<void> clearLiveRun() async {}
  @override
  Future<bool> hasEverReceivedPayload() async => true;
  @override
  Future<DateTime?> payloadReceivedAt() async => null;
  @override
  Future<WiFiDetails?> readLatest() async => WiFiDetails.fromMap(
        const <String, dynamic>{
          'SSID': 'KeithNet',
          'RSSI': -50,
          'Channel': 36,
        },
      );
  bool monitoringActive = false;

  /// Feeds live Shortcut samples, so the screen reaches the FULL metric-card
  /// body (where the Security card lives) rather than the pre-sample locked
  /// card. This is the realistic journey for this defect: the Shortcut is
  /// working and the RF fields are fine, while the NATIVE security read is
  /// blocked by Location.
  final StreamController<WiFiDetails> controller =
      StreamController<WiFiDetails>.broadcast();

  @override
  Future<bool> isMonitoringActive() async => monitoringActive;
  @override
  Future<void> setMonitoringActive(bool active) async {
    monitoringActive = active;
  }
  @override
  Future<void> resetMonitoringColdStart() async {}
  @override
  Future<bool> openUrl(String url) async => true;
  @override
  Future<bool> runShortcut(String name) async => true;
  @override
  Future<bool> runShortcutOneShot(String name) async => true;
  @override
  Stream<WiFiDetails> get updates => controller.stream;
}

/// Reports the device is ON Wi-Fi. The iOS live surfaces (and therefore the
/// Security card) only render once the connection probe resolves to onWifi;
/// without it the screen never leaves its pre-load gate.
class _OnWifiPath implements WifiPathProbe {
  @override
  Future<WifiPathFacts?> read() async => const WifiPathFacts(
        usesWifi: true,
        wifiSatisfied: true,
        wifiInterfacePresent: true,
      );
}

class _FakeNetworkInfo implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => '192.168.1.20';
  @override
  Future<String?> getWifiName() async => null;
  @override
  Future<String?> getWifiBSSID() async => null;
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  Future<String?> getWifiSubmask() async => null;
  @override
  Future<String?> getWifiGatewayIP() async => null;
  @override
  Future<String?> getWifiBroadcast() async => null;
}

WifiConnectionService _onWifiProbe() => WifiConnectionService(
      networkInfo: _FakeNetworkInfo(),
      platformOverride: TargetPlatform.iOS,
      pathProbe: _OnWifiPath(),
    );

/// A security service whose Location authorization is an explicit TRI-STATE.
///
/// It answers over the NATIVE PAYLOAD, not by constructing a [WifiSecurityInfo]
/// directly, so the token→enum mapping under test is the same code the real
/// channel drives. A fake that built the model directly would skip the very
/// conversion this fix added.
WifiSecurityService _securityAt(
  LocationAuthStatus status, {
  List<String>? methodLog,
}) {
  final String token = switch (status) {
    LocationAuthStatus.authorized => 'authorized',
    LocationAuthStatus.denied => 'denied',
    LocationAuthStatus.restricted => 'restricted',
    LocationAuthStatus.notDetermined => 'notDetermined',
  };
  return WifiSecurityService(
    invoke: (String method, [dynamic args]) async {
      methodLog?.add(method);
      switch (method) {
        case 'getSecurityInfo':
          // Unauthorized => the native read genuinely fails. This is the state
          // that renders the gate.
          return <String, dynamic>{
            'available': false,
            'reason': 'Location permission is needed to read the Wi-Fi '
                'security type and AP vendor on iOS.',
            'securityToken': null,
            'bssid': null,
            'ssid': null,
            'locationAuthorized': status == LocationAuthStatus.authorized,
            'locationAuthStatus': token,
          };
        case 'isLocationAuthorized':
          return status == LocationAuthStatus.authorized;
        case 'locationAuthorizationStatus':
          return token;
        case 'requestLocationPermission':
          // Models the real OS behavior under a non-promptable status: the
          // request returns immediately, nothing is shown, the answer does not
          // change. This is what made the button dead.
          return status == LocationAuthStatus.authorized;
        case 'openLocationSettings':
          return true;
        default:
          return null;
      }
    },
  );
}

void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.dark(), home: child);

  setUp(() {
    WifiInfoScreen.macPollEnabled = false;
  });
  tearDown(() {
    WifiInfoScreen.macPollEnabled = true;
  });

  Future<List<String>> pumpAt(
    WidgetTester tester,
    LocationAuthStatus status,
  ) async {
    final List<String> log = <String>[];
    final _LiveBridge bridge = _LiveBridge();
    await tester.pumpWidget(host(
      WifiInfoScreen(
        sourceOverride: WifiInfoSource.iosShortcuts,
        connectionService: _onWifiProbe(),
        iosBridge: bridge,
        securityService: _securityAt(status, methodLog: log),
      ),
    ));
    await tester.pumpAndSettle();

    // Reach the FULL metric-card body, where the Security card lives. Before a
    // sample the screen shows the pre-payload locked card and NO Security card
    // at all — a state in which every "the dead button is gone" assertion would
    // pass for the wrong reason. See the mutation note in the group below.
    await tester.ensureVisible(find.text('Start live monitoring'));
    await tester.tap(find.text('Start live monitoring'));
    await tester.pumpAndSettle();
    bridge.controller.add(WiFiDetails.fromMap(const <String, dynamic>{
      'SSID': 'KeithNet',
      'RSSI': -50,
      'Noise': -95,
      'TX Rate': 866,
    }));
    await tester.pumpAndSettle();
    return log;
  }

  group('the harness reaches the control under test', () {
    // THE COUNTERWEIGHT. Every "Grant Location is absent" assertion in this file
    // is only meaningful if the Security card is actually on screen. A previous
    // fix in this family shipped a test that started in a state where the
    // control did not exist, so it never entered the branch it was named for and
    // passed against the unfixed code. This test fails loudly if the harness
    // ever stops rendering the gate.
    //
    // MEASURED, 2026-07-20. Deleting the live-sample push from `pumpAt` (so the
    // Security card never renders) leaves "DENIED: the dead button is GONE"
    // PASSING — it finds no 'Grant Location' because it finds no card. Nine
    // tests fail under that sabotage and this one is the first. Without it the
    // absence-assertions in this file would be unfalsifiable.
    testWidgets('the Security card and its Location gate are rendered',
        (WidgetTester tester) async {
      await pumpAt(tester, LocationAuthStatus.denied);

      expect(find.text('Security'), findsOneWidget);
      // The gate itself is present — an action is offered, just not a dead one.
      expect(find.text('Open Settings'), findsOneWidget);
    });
  });


  group('iOS Security card Location gate — the four platform states', () {
    // ---------------------------------------------------------------- state 1
    testWidgets(
        'notDetermined (PROMPTABLE): the in-app Grant Location button renders, '
        'because this is the one state where iOS can still show a prompt',
        (WidgetTester tester) async {
      await pumpAt(tester, LocationAuthStatus.notDetermined);

      expect(find.text('Grant Location'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
    });

    testWidgets(
        'notDetermined: Settings stays the SECONDARY (outlined) action, because '
        'the in-app grant is the faster route when it can work',
        (WidgetTester tester) async {
      await pumpAt(tester, LocationAuthStatus.notDetermined);

      expect(
        find.widgetWithText(OutlinedButton, 'Open Settings'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Open Settings'),
        findsNothing,
      );
    });

    testWidgets(
        'notDetermined: the copy does NOT claim the app cannot ask, because it '
        'can', (WidgetTester tester) async {
      await pumpAt(tester, LocationAuthStatus.notDetermined);

      expect(find.textContaining('cannot ask again'), findsNothing);
    });

    // ---------------------------------------------------------------- state 2
    testWidgets(
        'DENIED: the dead button is GONE. No in-app grant is offered, because '
        'iOS will not re-prompt and the request would do nothing',
        (WidgetTester tester) async {
      await pumpAt(tester, LocationAuthStatus.denied);

      expect(find.text('Grant Location'), findsNothing);
    });

    testWidgets(
        'DENIED: Open Settings is the SOLE action and is PRIMARY (filled), '
        'because it is the only route that can work',
        (WidgetTester tester) async {
      await pumpAt(tester, LocationAuthStatus.denied);

      expect(
        find.widgetWithText(FilledButton, 'Open Settings'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Open Settings'),
        findsNothing,
      );
    });

    testWidgets(
        'DENIED: the copy states the app cannot ask again AND names where the '
        'switch lives, so the user is not left hunting',
        (WidgetTester tester) async {
      await pumpAt(tester, LocationAuthStatus.denied);

      // The prose form of the same dead button would be an instruction to do
      // something that cannot be done from inside this app.
      expect(find.textContaining('cannot ask again'), findsOneWidget);
      expect(
        find.textContaining('Settings > Privacy & Security > Location Services'),
        findsOneWidget,
      );
    });

    testWidgets(
        'DENIED: the native "Location permission is needed" reason is REPLACED, '
        'because on its own it reads as though this app could ask for it',
        (WidgetTester tester) async {
      await pumpAt(tester, LocationAuthStatus.denied);

      expect(
        find.textContaining('Location permission is needed'),
        findsNothing,
      );
    });

    // ---------------------------------------------------------------- state 3
    testWidgets(
        'RESTRICTED (MDM / Screen Time): treated exactly like denied — no '
        'in-app grant, because the restriction is not the user\'s to lift from '
        'a prompt', (WidgetTester tester) async {
      await pumpAt(tester, LocationAuthStatus.restricted);

      expect(find.text('Grant Location'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Open Settings'),
        findsOneWidget,
      );
    });

    testWidgets(
        'RESTRICTED: carries the same cannot-ask-again copy as denied',
        (WidgetTester tester) async {
      await pumpAt(tester, LocationAuthStatus.restricted);

      expect(find.textContaining('cannot ask again'), findsOneWidget);
    });

    // ---------------------------------------------------------------- state 4
    testWidgets(
        'AUTHORIZED: no Location gate at all — neither button renders, because '
        'there is nothing to grant', (WidgetTester tester) async {
      await pumpAt(tester, LocationAuthStatus.authorized);

      expect(find.text('Grant Location'), findsNothing);
      expect(find.text('Open Settings'), findsNothing);
      expect(find.textContaining('cannot ask again'), findsNothing);
    });
  });

  group('the grant control actually reaches the platform when it renders', () {
    testWidgets(
        'notDetermined: tapping Grant Location invokes requestLocationPermission '
        '— the button that renders is a button that acts',
        (WidgetTester tester) async {
      final List<String> log = await pumpAt(
        tester,
        LocationAuthStatus.notDetermined,
      );
      log.clear();

      await tester.ensureVisible(find.text('Grant Location'));
      await tester.tap(find.text('Grant Location'));
      await tester.pumpAndSettle();

      expect(log, contains('requestLocationPermission'));
    });

    testWidgets(
        'denied: tapping Open Settings invokes openLocationSettings — the sole '
        'route offered is the sole route that works',
        (WidgetTester tester) async {
      final List<String> log = await pumpAt(tester, LocationAuthStatus.denied);
      log.clear();

      await tester.ensureVisible(find.text('Open Settings'));
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(log, contains('openLocationSettings'));
      // And it never tried to prompt, because a prompt cannot appear.
      expect(log, isNot(contains('requestLocationPermission')));
    });
  });

  group('WifiSecurityInfo carries the platform tri-state, not a bool', () {
    // The layer where the bit used to be destroyed. Each token maps to its own
    // state; nothing collapses.
    for (final (String token, LocationAuthStatus expected) in <(
      String,
      LocationAuthStatus
    )>[
      ('authorized', LocationAuthStatus.authorized),
      ('denied', LocationAuthStatus.denied),
      ('restricted', LocationAuthStatus.restricted),
      ('notDetermined', LocationAuthStatus.notDetermined),
    ]) {
      test('the native token "$token" maps to $expected', () async {
        final WifiSecurityService svc = WifiSecurityService(
          invoke: (String method, [dynamic args]) async => <String, dynamic>{
            'available': false,
            'reason': 'gated',
            'locationAuthorized': token == 'authorized',
            'locationAuthStatus': token,
          },
        );
        final WifiSecurityInfo info = await svc.fetch();
        expect(info.locationAuth, expected);
      });
    }

    test(
        'denied and notDetermined are DISTINGUISHABLE — the whole point. Both '
        'are unauthorized, only one is promptable', () async {
      Future<WifiSecurityInfo> at(String token) async {
        final WifiSecurityService svc = WifiSecurityService(
          invoke: (String method, [dynamic args]) async => <String, dynamic>{
            'available': false,
            'locationAuthorized': false,
            'locationAuthStatus': token,
          },
        );
        return svc.fetch();
      }

      final WifiSecurityInfo denied = await at('denied');
      final WifiSecurityInfo fresh = await at('notDetermined');

      // The bool the old model carried is identical for both...
      expect(denied.locationAuth.isAuthorized, isFalse);
      expect(fresh.locationAuth.isAuthorized, isFalse);
      // ...and the bit that was missing separates them.
      expect(denied.locationAuth.isPromptable, isFalse);
      expect(fresh.locationAuth.isPromptable, isTrue);
    });

    test(
        'an ABSENT locationAuthStatus falls back to notDetermined (the safe '
        'default: offer the harmless prompt, never a dead deep-link)',
        () async {
      final WifiSecurityService svc = WifiSecurityService(
        invoke: (String method, [dynamic args]) async => <String, dynamic>{
          'available': false,
          'locationAuthorized': false,
        },
      );
      final WifiSecurityInfo info = await svc.fetch();
      expect(info.locationAuth, LocationAuthStatus.notDetermined);
    });

    test('locationAuthorizationStatus() resolves the tri-state token',
        () async {
      final WifiSecurityService svc = WifiSecurityService(
        invoke: (String method, [dynamic args]) async {
          expect(method, 'locationAuthorizationStatus');
          return 'restricted';
        },
      );
      expect(
        await svc.locationAuthorizationStatus(),
        LocationAuthStatus.restricted,
      );
    });
  });
}
