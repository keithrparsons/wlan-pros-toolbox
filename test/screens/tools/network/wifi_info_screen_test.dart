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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_unavailable_view.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap_cache.dart';
import 'package:wlan_pros_toolbox/services/network/live_onboarding_service.dart';
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
      phyMode: '802.11ax (Wi-Fi 6)',
      channel: 36,
      channelWidthMhz: null,
      band: '5 GHz',
      countryCode: null,
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
  _FakeMacAdapter({this.snapshot, this.error, this.snapshotAfterGrant});

  final ConnectedAp? snapshot;
  final WifiInfoUnavailable? error;

  /// When set, models the real grant flow: [fetch] returns [snapshot] until the
  /// interactive [requestNamePermission] resolves authorized, then returns this
  /// post-grant snapshot (SSID/BSSID now populated). Lets a test prove the
  /// grant → re-read → name-appears path.
  final ConnectedAp? snapshotAfterGrant;

  int grantCalls = 0;
  int openSettingsCalls = 0;
  bool _granted = false;

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
  Future<bool> openNamePermissionSettings() async => true;
}

/// A fake iOS Shortcuts bridge driving the Live streaming flow without a
/// platform channel.
class _FakeBridge implements WiFiDetailsBridge {
  _FakeBridge({
    this.everReceived = false,
    this.latest,
    this.runShortcutResult = true,
  });

  bool everReceived;
  WiFiDetails? latest;
  bool monitoringActive = false;

  /// What [runShortcut] returns (false => could not open Shortcuts).
  bool runShortcutResult;

  /// Records the exact name passed to [runShortcut] for assertions. The PLAIN
  /// trigger carries ONLY the name (no tool / no x-callback).
  String? lastRunShortcutName;
  int runShortcutCalls = 0;

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
  Future<bool> openUrl(String url) async => true;

  @override
  Future<bool> runShortcut(String name) async {
    runShortcutCalls++;
    lastRunShortcutName = name;
    return runShortcutResult;
  }

  @override
  Stream<WiFiDetails> get updates => controller.stream;
}

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
    testWidgets('idle state offers Start and the begin-live hint',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(everReceived: false),
        ),
      ));
      await tester.pumpAndSettle();
      // The only iOS mode is Live: a clean idle "Tap Start" state, no Snapshot
      // toggle and no Get Reading button.
      expect(find.text('Start'), findsOneWidget);
      expect(find.textContaining('Tap Start to begin live readings'),
          findsOneWidget);
      expect(find.text('Snapshot'), findsNothing);
      expect(find.text('Get Reading'), findsNothing);
    });

    testWidgets(
        'first-time setup (never received a payload) shows the LiveRfLockedCard '
        'with the RF fields by NAME and the single Enable CTA — never zeroed RF '
        'and never a redundant second setup prompt',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
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
      // The locked card carries the SINGLE enable CTA (no native identity yet →
      // "Enable live Wi-Fi"); the redundant LiveSetupCard prompt is suppressed.
      expect(find.text('Enable live Wi-Fi'), findsOneWidget);
      expect(find.text('Set up live Wi-Fi (one-time)'), findsNothing);
    });

    testWidgets(
        "the locked card's Enable button opens the install sheet (3 steps)",
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(everReceived: false),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enable live Wi-Fi'));
      await tester.pumpAndSettle();

      // The one-time onboarding sheet opens with the crystal-clear steps, deep-
      // linking to install the "WLAN Pros Live" companion Shortcut.
      expect(find.text('Set up live Wi-Fi'), findsOneWidget);
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
        // With the native identity already on screen, the locked card's CTA
        // starts live readings rather than re-opening the install sheet.
        expect(find.text('Start live readings'), findsOneWidget);
      },
    );

    testWidgets(
      'mandatory first-run onboarding sheet auto-fires once on first open '
      '(never-received payload), then is one-time',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final onboarding =
            LiveOnboardingService(getStore: SharedPreferences.getInstance);
        await tester.pumpWidget(host(
          WifiInfoScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _FakeBridge(everReceived: false),
            onboardingService: onboarding,
          ),
        ));
        await tester.pumpAndSettle();

        // The unmissable one-time setup sheet auto-presents on first open.
        expect(find.text('Set up live Wi-Fi'), findsOneWidget);
        expect(find.textContaining('No Location permission'), findsOneWidget);

        // It marked itself seen the instant it presented — re-mounting a fresh
        // screen against the SAME persisted store does NOT re-fire it.
        Navigator.of(tester.element(find.text('Set up live Wi-Fi'))).pop();
        await tester.pumpAndSettle();
        await tester.pumpWidget(host(
          WifiInfoScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _FakeBridge(everReceived: false),
            onboardingService:
                LiveOnboardingService(getStore: SharedPreferences.getInstance),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Set up live Wi-Fi'), findsNothing);
      },
    );

    testWidgets(
        'install/setup hint HIDDEN once the app has ever received a payload',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
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
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start'));
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
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
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
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(bridge.monitoringActive, isTrue);

      bridge.controller.add(WiFiDetails.fromMap(const <String, dynamic>{
        'SSID': 'KeithNet',
        'RSSI': -55,
        'Noise': -95,
      }));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      // Flag cleared; the idle Start control is back; the last reading is frozen
      // on screen (still charted + still in the metric cards). 'RSSI' now
      // appears as both the chart title and the Signal-card row label, so
      // findsWidgets, not findsOneWidget.
      expect(bridge.monitoringActive, isFalse);
      expect(find.text('Start'), findsOneWidget);
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
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      // The flag is cleared (no producer) and the honest, ACTIONABLE setup card
      // shows: the "could not start" message plus the one-time setup button.
      expect(bridge.monitoringActive, isFalse);
      expect(find.textContaining('Live readings could not start'),
          findsOneWidget);
      expect(find.text('Set up live Wi-Fi (one-time)'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
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
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
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
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();

      // User taps Start: the Shortcut fires exactly once.
      await tester.tap(find.text('Start'));
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
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
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
          iosBridge: bridge,
          connectedApCache: cache,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
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
      expect(find.text('Start'), findsOneWidget);
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
      // Android cannot read channel width via the public API → honest note that
      // names the real platform (not "macOS").
      expect(find.textContaining('Not reported by Android'), findsWidgets);
      // No macOS wording leaks onto the Android path.
      expect(find.textContaining('macOS'), findsNothing);
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
