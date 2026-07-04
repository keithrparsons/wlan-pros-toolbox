// Wi-Fi Information screen — widget tests (consolidated tool; iOS Live-only).
//
// The one Wi-Fi tool selects its data source per platform behind a seam, so the
// tests drive each source explicitly via [WifiInfoScreen.sourceOverride] plus an
// injected fake adapter/bridge — no real platform channel is touched.
//
// Covers the state matrix from SOP-007 §5 across BOTH platform paths:
//   * macOS source: loading → success cards, Wi-Fi-off, location-permission
//     card, channel-error card + retry. (Unchanged — macOS uses CoreWLAN.)
//   * iOS source (LIVE ONLY): the idle "Tap Start" state; Start sets the
//     monitoring flag + fires the PLAIN combined-Live trigger; stream
//     consumption renders the live charts; Stop clears the flag and freezes the
//     last values; dispose clears the flag (Vera regression).
//   * web source: download-the-app fallback.
//   * unsupported native: honest "coming in a later update" state.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_unavailable_view.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/not_on_wifi_card.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap_cache.dart';
import 'package:wlan_pros_toolbox/services/network/live_onboarding_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/mac_oui_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_live_shortcuts_config.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/sparkline.dart';

ConnectedAp _macSample({
  String? ssid = 'KeithNet',
  String? bssid = 'a4:83:e7:00:11:22',
  bool poweredOn = true,
}) {
  return ConnectedAp.fromWifiInfo(
    WifiInfo(
      interfaceName: 'en0',
      ssid: ssid,
      bssid: bssid,
      rssiDbm: -50,
      noiseDbm: -95,
      snrDb: 45,
      txRateMbps: 866,
      phyMode: '802.11ax',
      channel: 36,
      channelWidthMhz: 80,
      band: '5 GHz',
      countryCode: 'US',
      hardwareAddress: 'a4:83:e7:aa:bb:cc',
      poweredOn: poweredOn,
      locationAuthorized: true,
    ),
  );
}

/// An Android WifiManager sample: SSID/BSSID present, RF fields populated, and
/// noise/SNR honestly null (Android exposes neither).
ConnectedAp _androidSample({
  String? ssid = 'KeithNet',
  String? bssid = 'a4:83:e7:00:11:22',
  bool poweredOn = true,
  double? rxRateMbps,
  int? channelWidthMhz,
  String? countryCode,
}) {
  return ConnectedAp.fromAndroidWifiInfo(
    WifiInfo(
      interfaceName: 'wlan0',
      ssid: ssid,
      bssid: bssid,
      rssiDbm: -48,
      noiseDbm: null,
      snrDb: null,
      txRateMbps: 866,
      rxRateMbps: rxRateMbps,
      phyMode: '802.11ax (Wi-Fi 6)',
      channel: 36,
      channelWidthMhz: channelWidthMhz,
      band: '5 GHz',
      countryCode: countryCode,
      hardwareAddress: null,
      securityToken: 'wpa3Personal',
      poweredOn: poweredOn,
      locationAuthorized: ssid != null,
    ),
  );
}

/// A macOS sample with a specific RSSI, so successive polls produce distinct
/// charted samples.
ConnectedAp _macSampleRssi(int rssi) {
  return ConnectedAp.fromWifiInfo(
    WifiInfo(
      interfaceName: 'en0',
      ssid: 'KeithNet',
      bssid: 'a4:83:e7:00:11:22',
      rssiDbm: rssi,
      noiseDbm: -95,
      snrDb: 95 + rssi, // varies with RSSI
      txRateMbps: 866,
      phyMode: '802.11ax',
      channel: 36,
      channelWidthMhz: 80,
      band: '5 GHz',
      countryCode: 'US',
      hardwareAddress: 'a4:83:e7:aa:bb:cc',
      poweredOn: true,
      locationAuthorized: true,
    ),
  );
}

/// A fake macOS adapter: returns a queued snapshot or throws a queued error.
class _FakeMacAdapter implements WifiInfoAdapter {
  _FakeMacAdapter({
    this.snapshot,
    this.error,
    this.snapshotAfterGrant,
    bool authorized = false,
  }) : _granted = authorized;

  final ConnectedAp? snapshot;
  final WifiInfoUnavailable? error;

  /// When set, models the real grant flow: [fetch] returns [snapshot] until the
  /// interactive [requestNamePermission] resolves authorized, then returns this
  /// post-grant snapshot (SSID/BSSID now populated). Lets a test prove the
  /// grant → re-read → name-appears path.
  final ConnectedAp? snapshotAfterGrant;

  int grantCalls = 0;
  int openSettingsCalls = 0;

  /// Seeded from the constructor's `authorized` flag so a test can model a
  /// source where Location is ALREADY granted (the name is missing for a
  /// genuine reason, not a permission gate) without going through the grant
  /// flow. Flipped true by [requestNamePermission] to model an in-app grant.
  bool _granted;

  @override
  String get platformLabel => 'macOS CoreWLAN';

  @override
  bool get gatesNameBehindPermission => true;

  @override
  Future<ConnectedAp> fetch() async {
    if (error != null) throw error!;
    if (_granted && snapshotAfterGrant != null) return snapshotAfterGrant!;
    return snapshot ?? _macSample();
  }

  @override
  Future<bool> requestNamePermission() async {
    grantCalls++;
    _granted = true;
    return true;
  }

  @override
  Future<bool> currentNameAuthorization() async => _granted;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => _granted ? LocationAuthStatus.authorized : LocationAuthStatus.notDetermined;

  @override
  Future<bool> openNamePermissionSettings() async {
    openSettingsCalls++;
    return true;
  }
}

/// A macOS adapter that walks a sequence of snapshots, one per [fetch] call
/// (clamping on the last). Lets the poll test assert successive reads return
/// distinct values that advance the sparkline series and update the cards.
class _SequenceMacAdapter implements WifiInfoAdapter {
  _SequenceMacAdapter({required this.samples})
      : assert(samples.isNotEmpty, 'need at least one sample');

  final List<ConnectedAp> samples;
  int fetchCalls = 0;

  @override
  String get platformLabel => 'macOS CoreWLAN';

  @override
  bool get gatesNameBehindPermission => true;

  @override
  Future<ConnectedAp> fetch() async {
    final int i = fetchCalls < samples.length ? fetchCalls : samples.length - 1;
    fetchCalls++;
    return samples[i];
  }

  @override
  Future<bool> requestNamePermission() async => true;

  @override
  Future<bool> currentNameAuthorization() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => LocationAuthStatus.authorized;

  @override
  Future<bool> openNamePermissionSettings() async => true;
}

/// A fake Windows Native Wifi adapter: like the real [WindowsWifiInfoAdapter],
/// it does NOT gate the network name behind a permission
/// (`gatesNameBehindPermission => false`) and always reports authorized. Returns
/// a queued snapshot. Used to pin the leak-guard: a null name on an ungated
/// source must NOT show a Location card or a permission note — plain
/// "Unavailable" only.
class _FakeWindowsAdapter implements WifiInfoAdapter {
  _FakeWindowsAdapter({required this.snapshot});

  final ConnectedAp snapshot;
  int grantCalls = 0;
  int openSettingsCalls = 0;

  @override
  String get platformLabel => 'Windows';

  @override
  bool get gatesNameBehindPermission => false;

  @override
  Future<ConnectedAp> fetch() async => snapshot;

  @override
  Future<bool> requestNamePermission() async {
    grantCalls++;
    return true;
  }

  @override
  Future<bool> currentNameAuthorization() async => true;

  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;

  @override
  Future<bool> openNamePermissionSettings() async {
    openSettingsCalls++;
    return false;
  }
}

/// A fake iOS Shortcuts bridge driving the Live streaming flow without a
/// platform channel.
class _FakeBridge implements WiFiDetailsBridge {
  _FakeBridge({
    this.everReceived = false,
    this.latest,
    this.runShortcutResult = true,
    this.initiatedSetup = false,
  });

  /// Drives the post-install priming window (setupInitiated && !hasEverReceived).
  bool initiatedSetup;

  @override
  Future<bool> consumeShortcutMissing() async => false;
  @override
  Future<void> markSetupInitiated() async {}
  @override
  Future<bool> hasInitiatedSetup() async => initiatedSetup;
  @override
  Future<bool> isShortcutsAppInstalled() async => true;
  @override
  Future<void> setLiveOriginRoute(String route) async {}
  @override
  Future<String?> consumeLiveErrorNav() async => null;

  bool everReceived;
  WiFiDetails? latest;
  bool monitoringActive = false;

  /// What [runShortcut] returns (false => could not open Shortcuts).
  bool runShortcutResult;

  /// Records the exact name passed to [runShortcut] for assertions. The PLAIN
  /// trigger carries ONLY the name (no tool / no x-callback).
  String? lastRunShortcutName;
  int runShortcutCalls = 0;

  /// Records the ONE-SHOT (x-callback) trigger. Separate from the plain trigger
  /// so a test can assert which form fired.
  String? lastOneShotName;
  int runShortcutOneShotCalls = 0;

  final StreamController<WiFiDetails> controller =
      StreamController<WiFiDetails>.broadcast();

  @override
  Future<bool> hasEverReceivedPayload() async => everReceived;

  @override
  Future<WiFiDetails?> readLatest() async => latest;

  @override
  Future<bool> isMonitoringActive() async => monitoringActive;

  @override
  Future<void> setMonitoringActive(bool active) async {
    monitoringActive = active;
  }

  @override
  Future<void> resetMonitoringColdStart() async {
    monitoringActive = false;
  }

  @override
  Future<bool> openUrl(String url) async => true;

  @override
  Future<bool> runShortcut(String name) async {
    runShortcutCalls++;
    lastRunShortcutName = name;
    return runShortcutResult;
  }

  @override
  Future<bool> runShortcutOneShot(String name) async {
    runShortcutOneShotCalls++;
    lastOneShotName = name;
    return runShortcutResult;
  }

  @override
  Stream<WiFiDetails> get updates => controller.stream;
}

/// A fake [NetworkInfo] for the honest Wi-Fi-connection probe: returns a queued
/// Wi-Fi IPv4 (or null) without touching a platform channel. The real
/// [NetworkInfo] is a method-channel plugin with no handler in the test harness,
/// so the live flow needs this seam to resolve to a deterministic on-/off-Wi-Fi
/// verdict instead of stalling the controller's load().
class _FakeNetworkInfo implements NetworkInfo {
  _FakeNetworkInfo({this.wifiIp});

  /// The Wi-Fi adapter IPv4 to report. Non-empty => the device is on Wi-Fi; null
  /// => no Wi-Fi link (cellular-only on iOS).
  final String? wifiIp;

  @override
  Future<String?> getWifiIP() async => wifiIp;

  // The remaining reads are unused by [WifiConnectionService]; report null.
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

/// An iOS connection probe that reports the device is ON Wi-Fi (a non-empty
/// Wi-Fi IP). This is the default state for the iOS Live tests: the live controls
/// (Get reading / Start live monitoring / streaming) only render on Wi-Fi, so the
/// probe must resolve to [WifiConnectionStatus.onWifi] for those assertions to
/// hold. Without it the controller's load() would stall on the real
/// platform-channel read and the screen would never leave its pre-load gate.
WifiConnectionService _onWifiProbe() => WifiConnectionService(
      networkInfo: _FakeNetworkInfo(wifiIp: '192.168.1.20'),
      platformOverride: TargetPlatform.iOS,
    );

/// An iOS connection probe that reports the device is demonstrably NOT on Wi-Fi
/// (a null Wi-Fi IP on iOS => cellular-only / offline). Drives the honest
/// [NotOnWifiCard] state.
WifiConnectionService _offWifiProbe() => WifiConnectionService(
      networkInfo: _FakeNetworkInfo(),
      platformOverride: TargetPlatform.iOS,
    );

/// Builds a [WifiSecurityService] whose native channel returns an AVAILABLE
/// NEHotspotNetwork read (SSID / BSSID / coarse security token) — the real
/// connected-network identity the app reads itself on iOS, no Shortcut needed.
WifiSecurityService _availableSecurity({
  String ssid = 'KeithNet',
  String bssid = 'a4:83:e7:00:11:22',
  String token = 'personal',
}) {
  return WifiSecurityService(
    invoke: (String method, [dynamic args]) async {
      switch (method) {
        case 'getSecurityInfo':
          return <String, dynamic>{
            'available': true,
            'securityToken': token,
            'bssid': bssid,
            'ssid': ssid,
            'locationAuthorized': true,
          };
        case 'isLocationAuthorized':
          return true;
        default:
          return null;
      }
    },
  );
}

void main() {
  Widget host(Widget child) => MaterialApp(theme: AppTheme.dark(), home: child);

  // The macOS path arms an automatic CoreWLAN poll (Timer.periodic). A live
  // periodic timer never lets pumpAndSettle settle, so the default for the suite
  // is OFF; the dedicated polling group below re-enables it and pumps the
  // interval deterministically. Always restored in tearDown.
  setUp(() {
    WifiInfoScreen.macPollEnabled = false;
    WifiInfoScreen.macPollInterval = const Duration(seconds: 2);
  });
  tearDown(() {
    WifiInfoScreen.macPollEnabled = true;
    WifiInfoScreen.macPollInterval = const Duration(seconds: 2);
  });

  group('WifiInfoScreen — macOS source', () {
    testWidgets('loading then success cards', (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: _FakeMacAdapter(snapshot: _macSample()),
        ),
      ));
      await tester.pump(); // loading frame
      await tester.pumpAndSettle(); // resolve fetch
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('KeithNet'), findsOneWidget);
      // macOS cannot expose Rx rate — honest per-field note. Now stated on BOTH
      // the Rx sparkline and the Rate card with the same permanent wording.
      expect(find.text('Not exposed by macOS CoreWLAN'), findsWidgets);
      // macOS DOES expose channel width — no "not reported" note for it.
      expect(find.textContaining('Not reported by macOS'), findsNothing);
    });

    testWidgets('renders BOTH the live sparklines AND the metric cards',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: _FakeMacAdapter(snapshot: _macSample()),
        ),
      ));
      await tester.pumpAndSettle();

      // Sparklines on top: the seed CoreWLAN read fed one sample into the macOS
      // series, so the shared _LiveCharts surface renders (graded RSSI/SNR +
      // Tx/Rx trend cards). At least one Sparkline is painted.
      expect(find.byType(Sparkline), findsWidgets);
      // The graded RSSI sparkline card carries a grade chip — proof the live
      // surface (not just the metric cards) is on macOS now.
      expect(find.text('RSSI'), findsWidgets);

      // Metric cards on the bottom: the grouped Network/Signal/Rate/Channel/
      // Radio/Status cards still render below.
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Signal'), findsOneWidget);
      expect(find.text('KeithNet'), findsOneWidget);
      // macOS-honest per-field note present on BOTH surfaces (the Rx sparkline
      // and the Rate card), with the same permanent "Not exposed by macOS
      // CoreWLAN" wording — no misleading "in this reading" on the chart.
      expect(find.text('Not exposed by macOS CoreWLAN'), findsNWidgets(2));
    });

    testWidgets(
        'automatic poll advances the series and refreshes the cards (no Start '
        'button needed)', (tester) async {
      WifiInfoScreen.macPollEnabled = true;
      WifiInfoScreen.macPollInterval = const Duration(seconds: 2);

      // The adapter returns a CHANGING RSSI each fetch so successive polls add
      // distinct samples and the latest card value updates.
      final adapter = _SequenceMacAdapter(
        samples: <ConnectedAp>[
          _macSample(),
          _macSampleRssi(-60),
          _macSampleRssi(-70),
        ],
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: adapter,
        ),
      ));
      // Seed read resolves.
      await tester.pump();
      await tester.pump();

      // There is no Start control on macOS — the poll is automatic.
      expect(find.text('Start'), findsNothing);
      expect(find.text('Stop'), findsNothing);

      // Advance one poll interval: the timer fires, re-reads (-60), updates.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(adapter.fetchCalls, greaterThanOrEqualTo(2));

      // Advance another interval: re-reads (-70).
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(adapter.fetchCalls, greaterThanOrEqualTo(3));

      // The latest RSSI (-70) is reflected in the Signal card.
      expect(find.textContaining('-70'), findsWidgets);

      // Tear down cleanly so the periodic timer is cancelled (no pending-timer
      // failure).
      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pump();
    });

    testWidgets('Wi-Fi off leads with the off card', (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: _FakeMacAdapter(snapshot: _macSample(poweredOn: false)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Wi-Fi is off'), findsOneWidget);
    });

    testWidgets('location card shows when the name is gated', (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: _FakeMacAdapter(
            snapshot: _macSample(ssid: null, bssid: null),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // Name is gated (both SSID and BSSID null) -> the Grant card shows, with
      // both the system-prompt button and the deep-link to Location Settings.
      expect(find.text('Grant Location'), findsWidgets);
      expect(find.text('Open Location Settings'), findsOneWidget);
      // The consumer-friendly numbered steps render under the buttons.
      expect(find.textContaining('Turn on WLAN Pros Toolbox'), findsOneWidget);
    });

    testWidgets(
        'tapping "Open Location Settings" invokes the deep-link channel method',
        (tester) async {
      final adapter = _FakeMacAdapter(
        snapshot: _macSample(ssid: null, bssid: null),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: adapter,
        ),
      ));
      await tester.pumpAndSettle();

      expect(adapter.openSettingsCalls, 0);
      await tester.tap(find.text('Open Location Settings'));
      await tester.pumpAndSettle();

      // The button routes to the adapter, which (on the real macOS adapter)
      // calls the `openLocationSettings` channel method — the deep-link.
      expect(adapter.openSettingsCalls, 1);
    });

    testWidgets(
        'grant Location -> permission resolves authorized -> re-read populates '
        'SSID/BSSID (the interactive grant waits for the user)', (tester) async {
      final adapter = _FakeMacAdapter(
        // Before grant: name gated off (Location not yet authorized).
        snapshot: _macSample(ssid: null, bssid: null),
        // After grant: the same network, now with the name exposed.
        snapshotAfterGrant: _macSample(),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: adapter,
        ),
      ));
      await tester.pumpAndSettle();

      // Pre-grant: the name is gated, the Grant card is visible, no SSID value.
      expect(find.text('Grant Location'), findsWidgets);
      expect(find.text('KeithNet'), findsNothing);

      // Tap Grant: requestNamePermission resolves authorized (the 30s ceiling
      // means the interactive grant waits for the user), then _fetchMac re-reads
      // WITH authorization and the name appears.
      await tester.tap(find.text('Grant Location').first);
      await tester.pumpAndSettle();

      expect(adapter.grantCalls, 1);
      expect(find.text('KeithNet'), findsOneWidget);
      expect(find.text('a4:83:e7:00:11:22'), findsOneWidget);
    });

    testWidgets(
        'Location denied → the SSID and BSSID rows name the actionable '
        '"Needs Location permission" reason, NOT a bare "Unavailable", and the '
        'grant affordance is present', (tester) async {
      // The reported bug: with macOS Location NOT granted, SSID/BSSID rendered a
      // flat "Unavailable" (implying the data does not exist) even though the
      // real, fixable cause is the missing Location permission. Model that state
      // with a not-authorized adapter returning a name-gated snapshot.
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: _FakeMacAdapter(
            snapshot: _macSample(ssid: null, bssid: null),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // The SSID/BSSID rows carry the actionable Location reason (worded to
      // agree with the glance card's "Network name needs Location permission").
      // The row label supplies the "Network name" subject, so the note reads
      // "Needs Location permission" — one per gated row (SSID + BSSID).
      expect(find.textContaining('Needs Location permission'), findsWidgets);
      // The grant affordance is present so the user can act on the reason.
      expect(find.text('Grant Location'), findsWidgets);
      expect(find.text('Open Location Settings'), findsOneWidget);
    });

    testWidgets(
        'Location AUTHORIZED but name absent (disconnected/hidden) → the rows '
        'fall back to a plain unavailable, NOT the Location reason, and no '
        'Location card is shown (the permission is granted)', (tester) async {
      // Distinguish "Location not authorized" (actionable) from a genuine
      // absence: when Location IS granted yet the name is still missing, the
      // cause is a disconnected / hidden network, NOT a permission gate. We must
      // never blame a permission that is actually granted (GL-005).
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: _FakeMacAdapter(
            authorized: true,
            snapshot: _macSample(ssid: null, bssid: null),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // The Location reason must NOT appear — the permission is granted.
      expect(find.textContaining('Needs Location permission'), findsNothing);
      // And no Location card / grant affordance is shown for a granted permission.
      expect(find.text('Grant Location'), findsNothing);
      expect(find.text('Open Location Settings'), findsNothing);
    });

    testWidgets(
        'Location authorized WITH a name → the real SSID/BSSID render and no '
        'Location reason note appears', (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: _FakeMacAdapter(
            authorized: true,
            snapshot: _macSample(),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('KeithNet'), findsOneWidget);
      expect(find.text('a4:83:e7:00:11:22'), findsOneWidget);
      expect(find.textContaining('Needs Location permission'), findsNothing);
      expect(find.text('Grant Location'), findsNothing);
    });

    testWidgets(
        'LEAK GUARD (Windows, ungated source): a null name shows NO Location '
        'card and NO permission note — plain "Unavailable" only, since Windows '
        'Native Wifi has no name gate', (tester) async {
      // Regression pin: the macOS-worded Location card / "Needs Location
      // permission" note must never leak onto a source that does not gate the
      // name behind a permission. Windows returns SSID/BSSID with no grant, so a
      // null name is a genuine absence, not a permission problem.
      final adapter = _FakeWindowsAdapter(
        // RF present, name absent — the ungated null-name case.
        snapshot: const ConnectedAp(
          rssiDbm: -55,
          channel: 36,
          band: '5 GHz',
          txRateMbps: 866,
          poweredOn: true,
          rxRateAvailable: true,
        ),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.windowsNativeWifi,
          macAdapter: adapter,
        ),
      ));
      await tester.pumpAndSettle();

      // No Location card / grant affordance and no permission note.
      expect(find.text('Grant Location'), findsNothing);
      expect(find.textContaining('Needs Location permission'), findsNothing);
      expect(find.textContaining('Location Services'), findsNothing);
      // The name rows fall back to the plain, honest "Unavailable".
      expect(find.text('Unavailable'), findsWidgets);
      // And the grant path was never even offered (no settings deep-link fired).
      expect(adapter.openSettingsCalls, 0);
    });

    testWidgets('channel error shows an error card with retry', (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: _FakeMacAdapter(
            error: const WifiInfoUnavailable(
              WifiInfoUnavailableReason.channelError,
              'No interface',
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No Wi-Fi reading available'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets(
        'a STALLED fetch (native channel never returns) does not hang — the '
        'screen leaves loading and shows the error card', (tester) async {
      // Drive the REAL adapter against a never-resolving native channel with a
      // tiny fetchTimeout. This exercises the full chain end-to-end: the
      // adapter bounds fetch(), throws the typed channelError, and the screen's
      // catch leaves the spinner and renders the honest error card. Before the
      // adapter bound, _fetchMac's `await adapter.fetch()` would hang forever
      // and the loading spinner would never clear.
      final adapter = MacWifiInfoAdapter(
        service: WifiInfoService(
          invoke: (String method, [dynamic args]) =>
              Completer<Object?>().future, // never resolves
          platformOverride: 'macos',
        ),
        fetchTimeout: const Duration(milliseconds: 50),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: adapter,
        ),
      ));
      await tester.pump(); // loading frame
      // Spinner is up while the bounded fetch is in flight.
      expect(find.text('Reading Wi-Fi link state…'), findsOneWidget);

      // Let the adapter's fetchTimeout fire and the screen settle. If the read
      // were unbounded, this would never settle.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // The screen left loading and degraded to the honest error card.
      expect(find.text('Reading Wi-Fi link state…'), findsNothing);
      expect(find.text('No Wi-Fi reading available'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('WifiInfoScreen — iOS source (Live only)', () {
    testWidgets(
        'INSTALL GATE: a not-set-up idle screen offers SET UP (never a blind '
        'Get reading / Start that would fire the missing Shortcut)',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: _FakeBridge(everReceived: false),
        ),
      ));
      await tester.pumpAndSettle();
      // 2026-06-25 install gate: when the companion Shortcut is NOT demonstrably
      // installed (hasEverReceived == false), the control bar's primary action is
      // "Set up live Wi-Fi" — it opens the install sheet, it never blind-fires the
      // run-shortcut URL (which errored "the file doesn't exist" and stranded the
      // user). The opt-in continuous-streaming row is hidden until setup completes.
      expect(find.text('Set up live Wi-Fi'), findsWidgets);
      expect(find.text('Get reading'), findsNothing);
      expect(find.text('Start live monitoring'), findsNothing);
      expect(find.text('Start'), findsNothing);
      expect(find.text('Snapshot'), findsNothing);
      // Vera H1 (device round 5): the cold-state hint must name the button that
      // IS on screen (Set up live Wi-Fi), NOT a Start control that does not exist
      // yet (GL-005). The wording references Set up and never tells the user to
      // "Tap Start Live Monitoring above".
      expect(find.textContaining('Tap Set up live Wi-Fi to add it'), findsOneWidget);
      expect(find.textContaining('Tap Start Live Monitoring above'), findsNothing);
    });

    testWidgets(
        'PRIMING-state hint references Start (matches the priming card), never '
        'Set up (Vera H2)', (tester) async {
      // setupInitiated == true && hasEverReceived == false: the screen shows the
      // LivePrimingCard ("Tap Start Live Monitoring to finish...") and the control
      // bar is suppressed. The hint must agree with that card — reference Start,
      // NOT "Set up live Wi-Fi" (a button absent during priming).
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: _FakeBridge(everReceived: false, initiatedSetup: true),
        ),
      ));
      await tester.pumpAndSettle();
      // The priming card is the single Start CTA.
      expect(find.textContaining('Start Live Monitoring to finish'),
          findsOneWidget);
      // The hint references Start, never the cold "Set up live Wi-Fi" copy.
      expect(find.textContaining('Tap Start Live Monitoring above'),
          findsOneWidget);
      expect(find.textContaining('Tap Set up live Wi-Fi to add it'), findsNothing);
    });

    testWidgets(
        'PRIMING + Start-open-failure: only the error card guides; no hint that '
        'names an absent button (Vera M3)', (tester) async {
      // Compound state: priming (setupInitiated) AND the Start could not open the
      // Shortcut (showSetupError). The control bar is suppressed and the priming
      // card is replaced by LiveSetupCard.error, so the error card is the SINGLE
      // source of guidance. The _LiveStartHint must NOT render (it would name a
      // Start/Set up button that is not on screen).
      final bridge = _FakeBridge(
        everReceived: false,
        initiatedSetup: true,
        runShortcutResult: false, // Shortcuts could not be opened
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      // Fire the priming card's Start; it fails to open the Shortcut.
      await tester.tap(find.text('Start live monitoring'));
      await tester.pumpAndSettle();

      // The error card is showing and is the single guidance.
      expect(find.textContaining('Live readings could not start'), findsOneWidget);
      expect(find.text('Set up live Wi-Fi (one-time)'), findsOneWidget);
      // No contradictory hint naming an absent button, and the priming card is
      // suppressed in this state.
      expect(find.textContaining('Tap Start Live Monitoring above'), findsNothing);
      expect(find.textContaining('Tap Set up live Wi-Fi to add it'), findsNothing);
      expect(
          find.textContaining('Start Live Monitoring to finish'), findsNothing);
    });

    testWidgets(
        'idle state for a SET-UP user offers the single green Start Live '
        'Monitoring action with the honest banner note',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          // hasEverReceived == true, but no live payload yet (latest carries the
          // identity only) so the screen stays idle (not streaming) and shows the
          // single Start control rather than the setup gate.
          iosBridge: _FakeBridge(
            everReceived: true,
            latest: WiFiDetails.fromMap(
                const <String, dynamic>{'SSID': 'KeithNet'}),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // 2026-06-26 (Keith device round 5): Get reading is GONE; the one live
      // action is the green Start Live Monitoring (control bar), with one honest
      // note. The locked card is a button-less field list (no second CTA).
      expect(find.text('Get reading'), findsNothing);
      expect(find.text('Start live monitoring'), findsOneWidget);
      expect(find.textContaining('takes one snapshot now'), findsNothing);
      expect(
          find.textContaining('keeps a status banner up while running'),
          findsOneWidget);
      expect(find.text('Start'), findsNothing);
      expect(find.text('Snapshot'), findsNothing);
    });

    testWidgets(
        'first-time setup (never received a payload) shows the LiveRfLockedCard '
        'with the RF fields by NAME and the single Enable CTA — never zeroed RF '
        'and never a redundant second setup prompt',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: _FakeBridge(everReceived: false),
        ),
      ));
      await tester.pumpAndSettle();
      // Pax anti-pattern #1 fix: the rich RF fields render as the locked card —
      // listed BY NAME with the honest "available once you enable live Wi-Fi"
      // framing, never as zeroed / blank values.
      expect(find.text('Live signal details'), findsOneWidget);
      expect(find.text('Signal (RSSI) and SNR'), findsOneWidget);
      expect(find.text('Channel, width, and band'), findsOneWidget);
      expect(find.text('Tx / Rx rate'), findsOneWidget);
      expect(find.text('Wi-Fi standard (PHY)'), findsOneWidget);
      // The no-Location trust signal is led, per the brief.
      expect(find.textContaining('no Location permission'), findsOneWidget);
      // The locked card carries the SINGLE enable CTA. With the install gate
      // (2026-06-25) and no demonstrably-installed Shortcut, that CTA reads
      // "Set up live Wi-Fi" and opens the install sheet (it never blind-fires the
      // missing Shortcut). The redundant LiveSetupCard prompt is suppressed.
      expect(find.text('Set up live Wi-Fi'), findsWidgets);
      expect(find.text('Enable live Wi-Fi'), findsNothing);
      expect(find.text('Set up live Wi-Fi (one-time)'), findsNothing);
    });

    testWidgets(
        "the locked card's Enable button opens the install sheet (3 steps)",
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: _FakeBridge(everReceived: false),
        ),
      ));
      await tester.pumpAndSettle();

      // With the install gate, the locked card's CTA reads "Set up live Wi-Fi".
      // Scroll it into view before tapping in the 600px test viewport. (The
      // control bar also shows a "Set up live Wi-Fi" primary; both open the same
      // sheet — tap the locked card's via its last occurrence to be specific.)
      final Finder lockedCta = find.text('Set up live Wi-Fi').last;
      await tester.ensureVisible(lockedCta);
      await tester.pumpAndSettle();
      await tester.tap(lockedCta);
      await tester.pumpAndSettle();

      // The one-time onboarding sheet opens with the crystal-clear steps, deep-
      // linking to install the "WLAN Pros Live" companion Shortcut. The sheet's
      // own title is also "Set up live Wi-Fi".
      expect(find.textContaining('WLAN Pros Live'), findsWidgets);
      expect(find.text('Tap Add the Shortcut below.'), findsOneWidget);
      expect(find.text('Add the Shortcut'), findsOneWidget);
    });

    testWidgets(
      'NATIVE-FIRST: shows the real connected-network identity (SSID / BSSID / '
      'security read via NEHotspotNetwork) immediately, with the rich RF fields '
      'as the locked card — never a dead screen, before any Shortcut payload',
      (tester) async {
        await tester.pumpWidget(host(
          WifiInfoScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
            iosBridge: _FakeBridge(everReceived: false),
            securityService: _availableSecurity(),
          ),
        ));
        await tester.pumpAndSettle();

        // The native identity cards render the REAL basics the app reads itself
        // — no Shortcut required for SSID / BSSID / security (brief req A).
        expect(find.text('Network'), findsOneWidget);
        expect(find.text('KeithNet'), findsOneWidget);
        expect(find.text('a4:83:e7:00:11:22'), findsOneWidget);
        expect(find.text('Security'), findsOneWidget);
        expect(find.text('Personal (WPA/WPA2/WPA3-PSK)'), findsOneWidget);

        // The rich RF fields render as the locked card, by NAME, never zeroed.
        expect(find.text('Live signal details'), findsOneWidget);
        expect(find.text('Signal (RSSI) and SNR'), findsOneWidget);
        // INSTALL GATE (2026-06-25): the native identity (SSID/BSSID/security via
        // NEHotspotNetwork) resolves with NO Shortcut, so it does NOT prove the
        // Shortcut is installed. With hasEverReceived == false the locked card's
        // CTA must be "Set up live Wi-Fi" (opens the install sheet), NOT a
        // "Get reading" that would blind-fire the missing Shortcut and strand the
        // user. This is the exact clean-install bug being fixed.
        expect(find.text('Set up live Wi-Fi'), findsWidgets);
        expect(find.text('Get reading'), findsNothing);
      },
    );

    testWidgets(
      'NATIVE-FIRST (2026-06-23): opening Wi-Fi Information does NOT auto-present '
      'the setup modal; the inline non-modal opt-in is offered instead',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final onboarding =
            LiveOnboardingService(getStore: SharedPreferences.getInstance);
        await tester.pumpWidget(host(
          WifiInfoScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
            iosBridge: _FakeBridge(everReceived: false),
            onboardingService: onboarding,
          ),
        ));
        await tester.pumpAndSettle();

        // The forced modal setup sheet must NOT auto-fire on open (the friends-
        // at-dinner friction Keith hit). No modal bottom sheet is presented — its
        // unique step copy ("Tap Add the Shortcut below.") is absent.
        expect(find.text('Tap Add the Shortcut below.'), findsNothing);
        // Instead the non-modal opt-in path is on screen: the inline locked card
        // lists the RF fields by name with the single Set-up CTA (install-gated,
        // since hasEverReceived == false).
        expect(find.text('Live signal details'), findsOneWidget);
        expect(find.text('Set up live Wi-Fi'), findsWidgets);
      },
    );

    testWidgets(
        'install/setup hint HIDDEN once the app has ever received a payload',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: _FakeBridge(
            everReceived: true,
            latest:
                WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // The user clearly has the Shortcut working (hasEverReceived = true), so
      // the install/setup note is noise and is gone permanently.
      expect(find.textContaining('WLAN Pros Live'), findsNothing);
    });

    testWidgets('Start sets the flag and fires the PLAIN combined-Live trigger',
        (tester) async {
      final bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();

      // 2026-06-23: continuous streaming is the opt-in "Start live monitoring"
      // toggle (one-shot "Get reading" is the default). This test exercises the
      // continuous path, so it taps the opt-in control.
      await tester.ensureVisible(find.text('Start live monitoring'));
      await tester.tap(find.text('Start live monitoring'));
      await tester.pumpAndSettle();

      // The shared monitoring flag is raised so the Shortcut keeps recursing.
      expect(bridge.monitoringActive, isTrue);
      // Start fires the run-shortcut trigger ONCE to kick off the recursion,
      // with the ONE canonical combined-Live name (the bridge-level test asserts
      // the URL is the plain, non-x-callback form).
      expect(bridge.runShortcutCalls, 1);
      expect(bridge.lastRunShortcutName,
          WifiLiveShortcutsConfig.kLiveShortcutName);
      expect(bridge.lastRunShortcutName, 'WLAN Pros Live');
      // The Stop control is now showing (streaming).
      expect(find.text('Stop'), findsOneWidget);
    });

    testWidgets('stream consumption appends samples + renders the live charts',
        (tester) async {
      final bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start live monitoring'));
      await tester.tap(find.text('Start live monitoring'));
      await tester.pumpAndSettle();

      // Push two streamed samples through the bridge updates stream.
      bridge.controller.add(WiFiDetails.fromMap(const <String, dynamic>{
        'SSID': 'KeithNet',
        'RSSI': -50,
        'Noise': -95,
        'TX Rate': 866,
      }));
      await tester.pump();
      bridge.controller.add(WiFiDetails.fromMap(const <String, dynamic>{
        'SSID': 'KeithNet',
        'RSSI': -60,
        'Noise': -95,
        'TX Rate': 700,
      }));
      await tester.pumpAndSettle();

      // The live charts rendered (graded RSSI/SNR + Tx/Rx rate cards) — the
      // chart 'RSSI' label co-exists with the metric Signal card, so the chart
      // RSSI title appears with the metric-card RSSI row label.
      expect(find.text('RSSI'), findsWidgets);
      expect(find.text('SNR'), findsWidgets);
      // The latest RSSI value (-60) is shown in the readout.
      expect(find.textContaining('-60'), findsWidgets);

      // AND the grouped metric cards render BELOW the charts (the unified
      // layout): Network / Signal / Channel / Radio / Status group titles.
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Signal'), findsOneWidget);
      // 'Channel' is both the card title and a row label inside it.
      expect(find.text('Channel'), findsWidgets);
      expect(find.text('Radio'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('KeithNet'), findsWidgets);
    });

    testWidgets('Stop clears the monitoring flag and freezes the last values',
        (tester) async {
      final bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start live monitoring'));
      await tester.tap(find.text('Start live monitoring'));
      await tester.pumpAndSettle();
      expect(bridge.monitoringActive, isTrue);

      bridge.controller.add(WiFiDetails.fromMap(const <String, dynamic>{
        'SSID': 'KeithNet',
        'RSSI': -55,
        'Noise': -95,
      }));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Stop'));
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      // Flag cleared; the idle controls are back (the opt-in Start live
      // monitoring toggle); the last reading is frozen on screen (still charted +
      // still in the metric cards). 'RSSI' now appears as both the chart title
      // and the Signal-card row label, so findsWidgets, not findsOneWidget.
      expect(bridge.monitoringActive, isFalse);
      expect(find.text('Start live monitoring'), findsOneWidget);
      expect(find.text('RSSI'), findsWidgets);
      // The grouped cards are still on screen after Stop (frozen snapshot).
      expect(find.text('Network'), findsOneWidget);
    });

    testWidgets('Start failing to open the Shortcut clears the flag + errors',
        (tester) async {
      final bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
        runShortcutResult: false, // Shortcuts app could not be opened
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start live monitoring'));
      await tester.tap(find.text('Start live monitoring'));
      await tester.pumpAndSettle();

      // The flag is cleared (no producer) and the honest, ACTIONABLE setup card
      // shows: the "could not start" message plus the one-time setup button.
      expect(bridge.monitoringActive, isFalse);
      expect(find.textContaining('Live readings could not start'),
          findsOneWidget);
      expect(find.text('Set up live Wi-Fi (one-time)'), findsOneWidget);
      expect(find.text('Start live monitoring'), findsOneWidget);
    });

    testWidgets('dispose clears the monitoring flag (Vera regression)',
        (tester) async {
      final bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start live monitoring'));
      await tester.tap(find.text('Start live monitoring'));
      await tester.pumpAndSettle();
      expect(bridge.monitoringActive, isTrue);

      // Tear the screen down (navigate away). Dispose must clear the flag so the
      // recursive Shortcut stops and the cellular tool is never stranded as
      // "streaming".
      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(bridge.monitoringActive, isFalse);
    });

    // REGRESSION — beta-blocker runaway loop (force-kill required).
    //
    // On iOS, Live Start fires the "WLAN Pros Live" Shortcut, which opens the
    // Shortcuts app. That VISIBLY backgrounds the Toolbox (inactive/paused) and
    // then foregrounds it again (resumed) when the run returns. The earlier
    // "pause-and-resume" code auto-re-fired the Shortcut on that resume, so:
    //   fire -> background -> resume -> fire -> background -> resume -> ...
    // an unbreakable loop the user had to force-kill. This test reproduces the
    // exact Start -> background -> foreground sequence the Shortcut bounce
    // produces and proves the Shortcut is fired EXACTLY ONCE — the resume does
    // NOT re-fire it — so the app can never ping-pong to Shortcuts on its own.
    testWidgets(
        'a Shortcut-run-induced foreground does NOT auto-re-fire the Shortcut '
        '(no runaway loop)', (tester) async {
      final bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();

      // User opts into continuous streaming: the Shortcut fires exactly once.
      await tester.ensureVisible(find.text('Start live monitoring'));
      await tester.tap(find.text('Start live monitoring'));
      await tester.pumpAndSettle();
      expect(bridge.runShortcutCalls, 1);
      expect(bridge.monitoringActive, isTrue);

      // The bounce: opening Shortcuts backgrounds the Toolbox...
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      // ...and the Shortcut run returns, foregrounding the Toolbox again.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // THE FIX: the app-induced foreground did NOT fire the Shortcut again.
      // Still exactly one run; the recursion (modeled by the live bridge stream)
      // carries the streaming, not a re-trigger from the app.
      expect(bridge.runShortcutCalls, 1,
          reason: 'resume after a Shortcut bounce must never re-fire the '
              'Shortcut — that is the runaway loop');

      // Hammer the bounce a few more times: a real loop would multiply the run
      // count without bound. The count must stay pinned at 1.
      for (int i = 0; i < 5; i++) {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
      }
      expect(bridge.runShortcutCalls, 1,
          reason: 'repeated foreground transitions must never accumulate '
              'Shortcut runs');
    });

    testWidgets(
        'a genuine background (not a Shortcut bounce) stops sampling and the '
        'foreground does not auto-restart it', (tester) async {
      final bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start live monitoring'));
      await tester.tap(find.text('Start live monitoring'));
      await tester.pumpAndSettle();
      expect(bridge.monitoringActive, isTrue);
      expect(bridge.runShortcutCalls, 1);

      // Simulate the Start's Shortcut bounce fully completing first (resume
      // clears the in-flight marker), so the NEXT background is a genuine
      // user-driven app switch, not the Start trigger's own bounce.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // User genuinely leaves the app: sampling stops (the auto-stop goal — the
      // loop-gate flag is cleared so the recursive Shortcut halts).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(bridge.monitoringActive, isFalse);

      // User returns: the Shortcut is NOT auto-re-fired. Still one run; the user
      // re-taps Start to resume (no auto-resume → no loop).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(bridge.runShortcutCalls, 1);
      expect(bridge.monitoringActive, isFalse);
    });

    testWidgets('a streamed reading is written to the shared cache (item 1)',
        (tester) async {
      final cache = ConnectedApCache();
      final bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: bridge,
          connectedApCache: cache,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start live monitoring'));
      await tester.tap(find.text('Start live monitoring'));
      await tester.pumpAndSettle();

      bridge.controller.add(WiFiDetails.fromMap(const <String, dynamic>{
        'SSID': 'KeithNet',
        'BSSID': 'a4:83:e7:00:11:22',
        'RSSI': -55,
      }));
      await tester.pumpAndSettle();

      // The Wi-Fi tool wrote its reading into the shared cache, so Interface Info
      // can now show the same SSID/BSSID without re-running the iOS Shortcut.
      expect(cache.hasReading, isTrue);
      expect(cache.latest?.ssid, 'KeithNet');
      expect(cache.latest?.bssid, 'a4:83:e7:00:11:22');
    });

    testWidgets('an idle (not-streaming) screen is not paused on background',
        (tester) async {
      final bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiProbe(),
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      // Never started streaming. Backgrounding must be a no-op, and foreground
      // must NOT auto-start a stream the user never asked for.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(bridge.monitoringActive, isFalse);
      expect(bridge.runShortcutCalls, 0);
      expect(find.text('Start live monitoring'), findsOneWidget);
    });

    // LAUNCH-CRITICAL regression (2026-06-25): when the device is demonstrably
    // OFF Wi-Fi (cellular-only on iOS → a null Wi-Fi IP) and no live reading has
    // ever arrived, the screen must render the honest [NotOnWifiCard] INSTEAD of
    // the live controls or an endless "waiting" — the exact silent dead-end a
    // tester hit. The notOnWifi gate is only entered on a POSITIVE off-Wi-Fi
    // signal AND no prior payload (GL-005: never from missing/ambiguous data).
    testWidgets(
        'OFF-WIFI: a cellular-only iOS device with no prior reading shows the '
        'honest NotOnWifiCard, not the live controls', (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          // Demonstrably off Wi-Fi: a null Wi-Fi IP on iOS is a positive
          // not-on-Wi-Fi signal (cellular-only / offline).
          connectionService: _offWifiProbe(),
          iosBridge: _FakeBridge(everReceived: false),
        ),
      ));
      await tester.pumpAndSettle();

      // The honest off-Wi-Fi card is shown with its plain explanation and the
      // "Check again" retry.
      expect(find.byType(NotOnWifiCard), findsOneWidget);
      expect(find.text("You're not connected to Wi-Fi"), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);

      // And the live controls / setup gate are NOT competing with it — the
      // off-Wi-Fi state takes precedence over the install gate when there is no
      // data to show (the Shortcut cannot read Wi-Fi RF that does not exist).
      expect(find.text('Get reading'), findsNothing);
      expect(find.text('Start live monitoring'), findsNothing);
      expect(find.text('Set up live Wi-Fi'), findsNothing);
    });

    // The OFF-WIFI gate is honest: a device that already has a reading this
    // session keeps showing it (the last known values) even if the probe drops
    // to cellular — a transient drop never blanks data the user already has.
    testWidgets(
        'OFF-WIFI is suppressed once a reading exists: a prior payload keeps the '
        'live data on screen even when the probe reports off-Wi-Fi',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          connectionService: _offWifiProbe(),
          // hasEverReceived == true: the Shortcut has delivered before, so the
          // last reading stays visible rather than the off-Wi-Fi card.
          iosBridge: _FakeBridge(
            everReceived: true,
            latest:
                WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // No off-Wi-Fi dead-end: the screen shows the live controls, not the
      // off-Wi-Fi card (hasEverReceived suppresses the not-on-Wi-Fi phase).
      expect(find.byType(NotOnWifiCard), findsNothing);
      expect(find.text('Start live monitoring'), findsOneWidget);
    });
  });

  group('WifiInfoScreen — macOS Location card narrow-width reflow', () {
    // The not-authorized Location card carries two action buttons (Grant
    // Location + Open Location Settings) side by side in a Wrap, plus the
    // numbered manual steps. On a narrow phone the two buttons cannot sit on one
    // line, so the Wrap must reflow them rather than throw a RenderFlex
    // overflow. These tests pin the viewport narrow and assert no overflow while
    // the full not-authorized content still renders.
    for (final double width in <double>[280, 320]) {
      testWidgets('renders the gated Location card without overflow at '
          '${width.toInt()}px', (tester) async {
        await _withViewport(tester, Size(width, 900), () async {
          await tester.pumpWidget(host(
            WifiInfoScreen(
              sourceOverride: WifiInfoSource.macosCoreWlan,
              macAdapter: _FakeMacAdapter(
                // Name gated off (both SSID and BSSID null) → the not-authorized
                // Location card with both buttons + the numbered steps.
                snapshot: _macSample(ssid: null, bssid: null),
              ),
            ),
          ));
          await tester.pumpAndSettle();

          // The full not-authorized content is present: both action buttons and
          // the numbered manual steps.
          expect(find.text('Grant Location'), findsWidgets);
          expect(find.text('Open Location Settings'), findsOneWidget);
          expect(
            find.textContaining('Turn on WLAN Pros Toolbox'),
            findsOneWidget,
          );
          // The buttons live in a Wrap so they reflow on a narrow card.
          expect(find.byType(Wrap), findsWidgets);
          // No RenderFlex overflow at this width.
          expect(
            tester.takeException(),
            isNull,
            reason: 'Location card overflowed at ${width.toInt()}px',
          );
        });
      });
    }
  });

  group('WifiInfoScreen — Android source (Phase 2)', () {
    testWidgets('loading then success cards with Android-honest field notes',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.androidWifiManager,
          macAdapter: _FakeMacAdapter(snapshot: _androidSample()),
        ),
      ));
      await tester.pump(); // loading frame
      await tester.pumpAndSettle(); // resolve fetch
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('KeithNet'), findsOneWidget);
      // Channel width is absent for this reading → honest per-network note
      // ("Not reported for this network"), never an OS-blaming "Not reported by
      // Android" (width is derived per-network, not blocked by the OS).
      expect(
        find.textContaining('Not reported for this network'),
        findsWidgets,
      );
      expect(find.textContaining('Not reported by Android'), findsNothing);
      // FIX 2: Android exposes no noise floor, so the Noise + SNR rows carry an
      // explicit reason note instead of a bare "Unavailable".
      expect(
        find.textContaining('Not available on Android (no noise-floor API)'),
        findsWidgets,
      );
      expect(
        find.textContaining(
          'Needs the noise floor, which Android does not expose',
        ),
        findsWidgets,
      );
      // FIX 2: with no Rx value (the -1 sentinel), the Rx row reads as an
      // Android device-link limit, not a bare "Unavailable". The note appears on
      // the static Rate card and may also appear on the live-charts surface.
      expect(
        find.textContaining("Not reported by this device's Android link"),
        findsWidgets,
      );
      // No macOS wording leaks onto the Android path.
      expect(find.textContaining('macOS'), findsNothing);
    });

    testWidgets('FIX 2: a real Android Rx value renders as Mbps, no limit note',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.androidWifiManager,
          macAdapter: _FakeMacAdapter(
            snapshot: _androidSample(rxRateMbps: 650),
          ),
        ),
      ));
      await tester.pump();
      await tester.pumpAndSettle();
      // The wired-through Rx value shows on the Rate card (and may also appear
      // on the live-charts surface), so at least one render is present.
      expect(find.text('650 Mbps'), findsWidgets);
      // And the device-link limit note is absent because Rx WAS reported.
      expect(
        find.textContaining("Not reported by this device's Android link"),
        findsNothing,
      );
    });

    testWidgets(
        'name gated without Location → the Android-worded Location card with '
        'the runtime-permission Grant + Open App Settings affordances',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.androidWifiManager,
          macAdapter: _FakeMacAdapter(
            // Both SSID and BSSID null models an ungranted ACCESS_FINE_LOCATION.
            snapshot: _androidSample(ssid: null, bssid: null),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // The gated card surfaces the runtime-permission request and the manual
      // settings fallback, with Android wording (not macOS Location Services).
      expect(find.text('Grant Location'), findsWidgets);
      expect(find.text('Open App Settings'), findsOneWidget);
      expect(find.textContaining('on Android'), findsWidgets);
      expect(find.textContaining('macOS'), findsNothing);
    });

    testWidgets(
        'tapping Grant Location drives the runtime request, then the name '
        'appears on the re-read', (tester) async {
      final adapter = _FakeMacAdapter(
        snapshot: _androidSample(ssid: null, bssid: null),
        snapshotAfterGrant: _androidSample(),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.androidWifiManager,
          macAdapter: adapter,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant Location').first);
      await tester.pumpAndSettle();

      // The runtime permission was requested exactly once, and the granted
      // re-read populated the network name.
      expect(adapter.grantCalls, 1);
      expect(find.text('KeithNet'), findsOneWidget);
      expect(find.text('a4:83:e7:00:11:22'), findsOneWidget);
    });

    testWidgets('channel error shows an error card with retry', (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.androidWifiManager,
          macAdapter: _FakeMacAdapter(
            error: const WifiInfoUnavailable(
              WifiInfoUnavailableReason.channelError,
              'No interface',
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No Wi-Fi reading available'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets(
        'S24 LEAK FIX: the MAC-type note names the ANDROID limit, never the iOS '
        '"Apple does not expose" wording', (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.androidWifiManager,
          // hardwareAddress is null on Android (the device MAC is hidden), so
          // the MAC-type row is unreadable and carries the platform note.
          macAdapter: _FakeMacAdapter(snapshot: _androidSample()),
        ),
      ));
      await tester.pumpAndSettle();
      // The Android-correct reason is present...
      expect(
        find.textContaining('Android returns a randomized placeholder MAC'),
        findsWidgets,
      );
      // ...and the iOS wording does NOT leak onto Android anywhere on screen.
      expect(find.textContaining('Apple does not expose'), findsNothing);
    });

    testWidgets(
        'ADD 1: channel width from the matching ScanResult renders on Android',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.androidWifiManager,
          macAdapter:
              _FakeMacAdapter(snapshot: _androidSample(channelWidthMhz: 160)),
        ),
      ));
      await tester.pumpAndSettle();
      // The width shows as a real value and the "Not reported" note disappears.
      expect(find.text('160 MHz'), findsWidgets);
      expect(
        find.textContaining('Not reported for this network'),
        findsNothing,
      );
      expect(find.textContaining('Not reported by Android'), findsNothing);
    });

    testWidgets('ADD 1: 80+80 MHz sentinel renders as "80+80 MHz"',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.androidWifiManager,
          macAdapter:
              _FakeMacAdapter(snapshot: _androidSample(channelWidthMhz: 8080)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('80+80 MHz'), findsWidgets);
    });

    testWidgets(
        'ADD 2: country code, when the platform returns it, shows with no note',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.androidWifiManager,
          macAdapter:
              _FakeMacAdapter(snapshot: _androidSample(countryCode: 'US')),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('US'), findsWidgets);
      expect(find.textContaining('Restricted on Android 11+'), findsNothing);
    });

    testWidgets(
        'ADD 2: country code absent → the honest Android restriction note, not '
        'a bare Unavailable', (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.androidWifiManager,
          macAdapter: _FakeMacAdapter(snapshot: _androidSample()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Restricted on Android 11+'),
        findsOneWidget,
      );
    });

    testWidgets(
        'ADD 4: Hardware Address (device MAC) absent → platform-correct note '
        'that it is the device MAC, not the AP', (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.androidWifiManager,
          macAdapter: _FakeMacAdapter(snapshot: _androidSample()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This device MAC, not the AP'),
        findsWidgets,
      );
      // The AP BSSID, by contrast, IS available on Android and shows in Network.
      expect(find.text('a4:83:e7:00:11:22'), findsOneWidget);
    });
  });

  group('WifiInfoScreen — platform fallbacks', () {
    testWidgets('web shows the download-the-app fallback', (tester) async {
      await tester.pumpWidget(host(
        const WifiInfoScreen(sourceOverride: WifiInfoSource.web),
      ));
      await tester.pumpAndSettle();
      // The download-the-app fallback view renders for the web source.
      expect(find.byType(NetworkUnavailableView), findsOneWidget);
    });

    testWidgets('unsupported native shows the coming-soon state',
        (tester) async {
      await tester.pumpWidget(host(
        const WifiInfoScreen(sourceOverride: WifiInfoSource.unsupported),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Coming in a later update'), findsOneWidget);
    });
  });

  // Batch 7 — Security type + AP vendor (entitlement-gated enrichment).
  group('WifiInfoScreen — Batch 7 Security + AP vendor', () {
    // A small OUI table standing in for the bundled asset, so the AP-vendor row
    // resolves a real manufacturer without loading the 50k-line file.
    MacOuiService ouiStub() => MacOuiService.fromTable(<String, String>{
          'A483E7': 'Apple, Inc.',
        });

    // A macOS sample carrying a fine-grained security token + the test BSSID.
    ConnectedAp macSecuritySample(String token) => ConnectedAp.fromWifiInfo(
          WifiInfo(
            interfaceName: 'en0',
            ssid: 'KeithNet',
            bssid: 'a4:83:e7:00:11:22',
            rssiDbm: -50,
            noiseDbm: -95,
            snrDb: 45,
            txRateMbps: 866,
            phyMode: '802.11ax',
            channel: 36,
            channelWidthMhz: 80,
            band: '5 GHz',
            countryCode: 'US',
            hardwareAddress: 'a4:83:e7:aa:bb:cc',
            securityToken: token,
            poweredOn: true,
            locationAuthorized: true,
          ),
        );

    testWidgets('macOS renders the fine WPA3 security label + AP vendor',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter:
              _FakeMacAdapter(snapshot: macSecuritySample('wpa3Transition')),
          ouiService: ouiStub(),
        ),
      ));
      await tester.pumpAndSettle();

      // Security card with the FINE macOS truth.
      expect(find.text('Security'), findsOneWidget);
      expect(find.text('WPA2/WPA3 Transition'), findsOneWidget);
      // No iOS-coarse caveat on macOS (it gives the real WPA generation).
      expect(find.textContaining('cannot distinguish WPA2 from WPA3'),
          findsNothing);

      // AP-vendor row resolves the manufacturer from the BSSID's OUI.
      expect(find.text('AP vendor'), findsOneWidget);
      expect(find.text('Apple, Inc.'), findsOneWidget);
      // Honest clarification: manufacturer, not the configured AP name.
      expect(
        find.textContaining('not the configured AP name'),
        findsOneWidget,
      );
    });

    testWidgets(
        'macOS WPA2 Personal renders the fine label, no coarse caveat',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter:
              _FakeMacAdapter(snapshot: macSecuritySample('wpa2Personal')),
          ouiService: ouiStub(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('WPA2 Personal'), findsOneWidget);
    });

    testWidgets(
        'a locally-administered BSSID shows the honest no-vendor reason',
        (tester) async {
      // Flip the U/L bit on the first octet → randomized BSSID, no IEEE vendor.
      final ConnectedAp randomized = ConnectedAp.fromWifiInfo(
        WifiInfo(
          interfaceName: 'en0',
          ssid: 'KeithNet',
          bssid: 'a6:83:e7:00:11:22', // a6 = a4 with the 0x02 bit set
          rssiDbm: -50,
          noiseDbm: -95,
          snrDb: 45,
          txRateMbps: 866,
          phyMode: '802.11ax',
          channel: 36,
          channelWidthMhz: 80,
          band: '5 GHz',
          countryCode: 'US',
          hardwareAddress: 'a4:83:e7:aa:bb:cc',
          securityToken: 'wpa2Personal',
          poweredOn: true,
          locationAuthorized: true,
        ),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: _FakeMacAdapter(snapshot: randomized),
          ouiService: ouiStub(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('locally administered, no registered vendor'),
        findsOneWidget,
      );
    });

    testWidgets(
        'a globally-administered BSSID with an unlisted OUI reads Unavailable '
        'with the unregistered-prefix reason (no raw hex as a manufacturer)',
        (tester) async {
      // Globally administered (U/L bit clear on 0x00), unicast (I/G bit clear),
      // but its OUI prefix 00:11:22 is NOT in the bundled IEEE table. The old
      // behavior leaked the raw hex "00:11:22" into the value as if it were a
      // resolved manufacturer. The honest behavior: value "Unavailable" + a
      // note that names the unregistered prefix, never presenting it as a vendor.
      final ConnectedAp unlisted = ConnectedAp.fromWifiInfo(
        WifiInfo(
          interfaceName: 'en0',
          ssid: 'KeithNet',
          bssid: '00:11:22:33:44:55', // global + unicast, OUI not in the table
          rssiDbm: -50,
          noiseDbm: -95,
          snrDb: 45,
          txRateMbps: 866,
          phyMode: '802.11ax',
          channel: 36,
          channelWidthMhz: 80,
          band: '5 GHz',
          countryCode: 'US',
          hardwareAddress: 'a4:83:e7:aa:bb:cc',
          securityToken: 'wpa2Personal',
          poweredOn: true,
          locationAuthorized: true,
        ),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: _FakeMacAdapter(snapshot: unlisted),
          ouiService: ouiStub(),
        ),
      ));
      await tester.pumpAndSettle();

      // The AP-vendor row still renders.
      expect(find.text('AP vendor'), findsOneWidget);
      // The honest note names the unregistered prefix and surfaces the raw OUI
      // clearly labeled as such, not as a vendor name.
      expect(
        find.textContaining('Unregistered OUI prefix (00:11:22)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('no IEEE vendor name'),
        findsOneWidget,
      );
      // The bare hex prefix must NEVER appear as the row VALUE (the overclaim).
      // It appears only inside the parenthetical note above, never standalone.
      expect(find.text('00:11:22'), findsNothing);
      // And the matched-manufacturer note must be absent for an unlisted OUI.
      expect(
        find.textContaining('not the configured AP name'),
        findsNothing,
      );
    });
  });
}

/// Run [body] with the test view sized to [size], then restore. Mirrors the
/// `_withViewport` helper in test/widget_test.dart so narrow-width overflow
/// checks layout at a real phone width.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
