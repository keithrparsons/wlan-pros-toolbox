// Wi-Fi Information screen — widget tests (TICKET-04, consolidated tool).
//
// The one Wi-Fi tool selects its data source per platform behind a seam, so the
// tests drive each source explicitly via [WifiInfoScreen.sourceOverride] plus an
// injected fake adapter/bridge — no real platform channel is touched.
//
// Covers the state matrix from SOP-007 §5 across BOTH platform paths:
//   * macOS source: loading → success cards, Wi-Fi-off, location-permission
//     card, channel-error card + retry.
//   * iOS source: needs-install empty state, success cards with the monitoring
//     control bar, Start/Stop, the honest per-field "not reported by iOS" note.
//   * web source: download-the-app fallback.
//   * unsupported native: honest "coming in a later update" state.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/shortcut_deep_link_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_unavailable_view.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/shortcut_trigger_result.dart';
import 'package:wlan_pros_toolbox/services/network/shortcuts_config.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
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

/// A fake iOS Shortcuts bridge driving the one-shot trigger flow without a
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

  /// Records the exact name + tool passed to [runShortcut] for assertions.
  String? lastRunShortcutName;
  String? lastRunShortcutTool;
  int runShortcutCalls = 0;

  final StreamController<WiFiDetails> controller =
      StreamController<WiFiDetails>.broadcast();
  final StreamController<ShortcutTriggerResult> triggerController =
      StreamController<ShortcutTriggerResult>.broadcast();

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
  Future<bool> runShortcut(String name, {required String tool}) async {
    runShortcutCalls++;
    lastRunShortcutName = name;
    lastRunShortcutTool = tool;
    return runShortcutResult;
  }

  @override
  Stream<ShortcutTriggerEvent> get triggerEvents =>
      triggerController.stream.map(
        (r) => ShortcutTriggerEvent(tool: 'wifi-info', result: r),
      );

  @override
  Stream<ShortcutTriggerResult> get triggerResults => triggerController.stream;

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

  group('WifiInfoScreen — iOS source (one-tap trigger, TICKET-03)', () {
    testWidgets('needs-install empty state offers Get Reading + Install',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(everReceived: false),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No Wi-Fi data yet'), findsOneWidget);
      // "Get Reading" is the primary trigger; "Install Shortcut" is secondary.
      expect(find.text('Get Reading'), findsOneWidget);
      expect(find.text('Install Shortcut'), findsOneWidget);
    });

    testWidgets('success shows Get Reading + cards + honest width note',
        (tester) async {
      final WiFiDetails sample = WiFiDetails.fromMap(const <String, dynamic>{
        'SSID': 'KeithNet',
        'BSSID': 'a4:83:e7:00:11:22',
        'Channel': 36,
        'RSSI': -50,
        'Noise': -95,
        'Standard': '802.11ax - Wi-Fi 6',
        'RX Rate': 780,
        'TX Rate': 866,
      });
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(everReceived: true, latest: sample),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('KeithNet'), findsOneWidget);
      // The one-tap trigger is present on the success screen.
      expect(find.text('Get Reading'), findsOneWidget);
      // iOS does not report channel width — honest per-field note.
      expect(find.text('Not reported by iOS'), findsOneWidget);
    });

    testWidgets('Get Reading fires runShortcut with the canonical name',
        (tester) async {
      final _FakeBridge bridge = _FakeBridge(
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
      await tester.tap(find.text('Get Reading'));
      await tester.pump(); // start the async trigger
      expect(bridge.runShortcutCalls, 1);
      // The trigger uses the EXACT canonical Shortcut name the published
      // Shortcut must match (the native side URL-encodes it into the
      // run-shortcut x-callback URL).
      expect(bridge.lastRunShortcutName, ShortcutsConfig.kCompanionShortcutName);
      expect(bridge.lastRunShortcutName, 'WLAN Pros Wi-Fi');
      // The originating tool id is carried so the x-callback return can
      // deep-link back to THIS screen on a cold relaunch (TICKET-03 UX fix).
      expect(bridge.lastRunShortcutTool, 'wifi-info');
    });

    testWidgets('x-success return refreshes from the App Group payload',
        (tester) async {
      // Start with one reading; the trigger return delivers a newer payload via
      // readLatest (mirrors the native re-read on resume).
      final _FakeBridge bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'OldNet'}),
      );
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('OldNet'), findsOneWidget);

      // Fire the trigger; the App Group payload updates while the app is in
      // Shortcuts, then the x-success callback arrives. The success handler
      // re-reads the App Group (readLatest now returns the fresh payload).
      await tester.tap(find.text('Get Reading'));
      await tester.pump();
      bridge.latest =
          WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'FreshNet'});
      bridge.triggerController.add(ShortcutTriggerResult.success);
      await tester.pumpAndSettle();

      // The fresh reading rendered, the stale one is gone, and no error banner.
      expect(find.text('FreshNet'), findsOneWidget);
      expect(find.text('OldNet'), findsNothing);
      expect(find.textContaining('Could not get a reading'), findsNothing);
    });

    testWidgets('x-error return shows the honest error + install fallback',
        (tester) async {
      final _FakeBridge bridge = _FakeBridge(
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

      await tester.tap(find.text('Get Reading'));
      await tester.pump();
      // The Shortcut errored / the user cancelled.
      bridge.triggerController.add(ShortcutTriggerResult.error);
      await tester.pumpAndSettle();

      // Honest error message + the install affordance as the fallback.
      expect(find.textContaining('Could not get a reading'), findsOneWidget);
      expect(find.text('Install the Shortcut'), findsOneWidget);
    });

    testWidgets('runShortcut failing to open shows the error immediately',
        (tester) async {
      final _FakeBridge bridge = _FakeBridge(
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
      await tester.tap(find.text('Get Reading'));
      await tester.pumpAndSettle();
      // No x-callback will ever arrive when the open failed; the error shows now.
      expect(find.textContaining('Could not get a reading'), findsOneWidget);
    });

    testWidgets(
        'app resume with no callback unsticks the triggering state',
        (tester) async {
      // Regression (Vera priority-1): the user taps Get Reading, lands in
      // Shortcuts, then back-swipes out WITHOUT the x-callback ever firing. On
      // resume the screen must clear _triggering so the button re-enables and
      // the spinner never sticks.
      final _FakeBridge bridge = _FakeBridge(
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

      // Tap Get Reading -> the screen enters the triggering state (spinner +
      // "Getting reading…"; the idle "Get Reading" label is gone).
      await tester.tap(find.text('Get Reading'));
      await tester.pump();
      expect(find.text('Getting reading…'), findsOneWidget);
      expect(find.text('Get Reading'), findsNothing);

      // Simulate the back-swipe return: an app RESUME with NO trigger callback.
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Triggering cleared: the idle button is back, the spinner is gone, and
      // no error banner was raised (the user simply backed out).
      expect(find.text('Get Reading'), findsOneWidget);
      expect(find.text('Getting reading…'), findsNothing);
      expect(find.textContaining('Could not get a reading'), findsNothing);
    });
  });

  group('WifiInfoScreen — iOS Live mode (TICKET-05)', () {
    Future<void> pumpLive(WidgetTester tester, _FakeBridge bridge) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      // Flip to Live via the segmented toggle.
      await tester.tap(find.text('Live'));
      await tester.pumpAndSettle();
    }

    testWidgets('Start sets the monitoring flag and fires the recursive trigger',
        (tester) async {
      final bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
      );
      await pumpLive(tester, bridge);

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      // The shared monitoring flag is raised so the Shortcut keeps recursing.
      expect(bridge.monitoringActive, isTrue);
      // Start fires the run-shortcut trigger ONCE to kick off the recursion.
      expect(bridge.runShortcutCalls, 1);
      expect(bridge.lastRunShortcutName, ShortcutsConfig.kCompanionShortcutName);
      expect(bridge.lastRunShortcutTool, 'wifi-info');
      // The Stop control is now showing (streaming).
      expect(find.text('Stop'), findsOneWidget);
    });

    testWidgets('stream consumption appends samples + renders the live charts',
        (tester) async {
      final bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
      );
      await pumpLive(tester, bridge);
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

      // The live charts rendered (graded RSSI/SNR + trend Tx/Rx cards).
      expect(find.text('RSSI'), findsOneWidget);
      expect(find.text('SNR'), findsOneWidget);
      expect(find.text('Tx Rate'), findsOneWidget);
      // The latest RSSI value (-60) is shown in the readout.
      expect(find.textContaining('-60'), findsWidgets);
    });

    testWidgets('Stop clears the monitoring flag', (tester) async {
      final bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
      );
      await pumpLive(tester, bridge);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(bridge.monitoringActive, isTrue);

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      expect(bridge.monitoringActive, isFalse);
      expect(find.text('Start'), findsOneWidget);
    });
  });

  group('WifiInfoScreen — cold-launch deep-link args (TICKET-03)', () {
    testWidgets(
        'reached via a status=err deep link shows the error banner here',
        (tester) async {
      // The cold-launch router pushes this screen with
      // ShortcutTriggerArgs(initialError: true) when the x-callback returned
      // status=err. The screen must show its honest error banner on THIS tool
      // screen rather than leaving the user on home.
      final _FakeBridge bridge = _FakeBridge(
        everReceived: true,
        latest: WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
      );
      // Push the screen via a route that carries the deep-link args, exactly as
      // the cold-launch router does (Navigator.pushNamed(route, arguments: …)).
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(
                  arguments: ShortcutTriggerArgs(initialError: true),
                ),
                builder: (_) => WifiInfoScreen(
                  sourceOverride: WifiInfoSource.iosShortcuts,
                  iosBridge: bridge,
                ),
              ),
            ),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // The honest error banner is shown on the tool screen.
      expect(find.textContaining('Could not get a reading'), findsOneWidget);
      expect(find.text('Install the Shortcut'), findsOneWidget);
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
