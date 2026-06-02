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
import 'package:wlan_pros_toolbox/screens/tools/network/network_unavailable_view.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_live_shortcuts_config.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

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

/// A fake macOS adapter: returns a queued snapshot or throws a queued error.
class _FakeMacAdapter implements WifiInfoAdapter {
  _FakeMacAdapter({this.snapshot, this.error});

  final ConnectedAp? snapshot;
  final WifiInfoUnavailable? error;
  int grantCalls = 0;

  @override
  String get platformLabel => 'macOS CoreWLAN';

  @override
  bool get gatesNameBehindPermission => true;

  @override
  Future<ConnectedAp> fetch() async {
    if (error != null) throw error!;
    return snapshot ?? _macSample();
  }

  @override
  Future<bool> requestNamePermission() async {
    grantCalls++;
    return true;
  }
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

void main() {
  Widget host(Widget child) => MaterialApp(theme: AppTheme.dark(), home: child);

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
      // macOS cannot expose Rx rate — honest per-field note.
      expect(find.text('Not exposed by macOS CoreWLAN'), findsOneWidget);
      // macOS DOES expose channel width — no "not reported" note for it.
      expect(find.textContaining('Not reported by macOS'), findsNothing);
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
      // Name is gated (both SSID and BSSID null) -> the Grant card shows.
      expect(find.text('Grant Location permission'), findsWidgets);
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
        'install/setup hint SHOWS on first-time setup (never received a payload)',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(everReceived: false),
        ),
      ));
      await tester.pumpAndSettle();
      // Genuine first-time setup: the companion-Shortcut install/how-to note is
      // shown so new users know to install it and tap Start.
      expect(find.textContaining('WLAN Pros Live'), findsOneWidget);
    });

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

      // The live charts rendered (graded RSSI/SNR + Tx/Rx rate cards).
      expect(find.text('RSSI'), findsOneWidget);
      expect(find.text('SNR'), findsOneWidget);
      expect(find.text('Tx Rate'), findsOneWidget);
      // The latest RSSI value (-60) is shown in the readout.
      expect(find.textContaining('-60'), findsWidgets);
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
      // on screen (still charted).
      expect(bridge.monitoringActive, isFalse);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('RSSI'), findsOneWidget);
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

      // The flag is cleared (no producer) and the honest Live error shows.
      expect(bridge.monitoringActive, isFalse);
      expect(find.textContaining('Could not start live streaming'),
          findsOneWidget);
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
}
