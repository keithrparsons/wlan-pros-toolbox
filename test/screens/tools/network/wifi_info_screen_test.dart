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
import 'package:wlan_pros_toolbox/screens/tools/network/network_unavailable_view.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
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

/// A fake iOS Shortcuts bridge driving the controller without a channel.
class _FakeBridge implements WiFiDetailsBridge {
  _FakeBridge({
    this.everReceived = false,
    this.latest,
  });

  bool everReceived;
  WiFiDetails? latest;
  bool monitoringActive = false;
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

  group('WifiInfoScreen — iOS source', () {
    testWidgets('needs-install empty state offers Install Shortcut',
        (tester) async {
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(everReceived: false),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No Wi-Fi data yet'), findsOneWidget);
      expect(find.text('Install Shortcut'), findsOneWidget);
    });

    testWidgets('success shows the control bar + cards + honest width note',
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
      // Start control present (idle with data, not yet streaming).
      expect(find.text('Start'), findsOneWidget);
      // iOS does not report channel width — honest per-field note.
      expect(find.text('Not reported by iOS'), findsOneWidget);
    });

    testWidgets('Start begins streaming and swaps to Stop', (tester) async {
      final WiFiDetails sample =
          WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'});
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(everReceived: true, latest: sample),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      // Streaming: the Stop control and the "Live" status label both appear.
      expect(find.byIcon(Icons.stop), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
    });

    testWidgets(
        'streaming timestamp is excluded from the live region '
        '(Vera LOW: no per-tick re-announcement)', (tester) async {
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
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      // Push a streamed payload so the "Updated HH:MM:SS" timestamp renders.
      bridge.controller.add(
        WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'KeithNet'}),
      );
      await tester.pumpAndSettle();

      final Finder timestamp = find.textContaining('Updated ');
      expect(timestamp, findsOneWidget);

      // The state word stays inside the liveRegion so Start/Stop announce...
      final Finder liveRegion = find.ancestor(
        of: find.text('Live'),
        matching: find.byWidgetPredicate(
          (Widget w) => w is Semantics && w.properties.liveRegion == true,
        ),
      );
      expect(liveRegion, findsOneWidget);

      // ...but the ticking timestamp is wrapped in ExcludeSemantics, so it is
      // NOT re-announced on every ~1s tick (the Vera SOP-009 LOW finding).
      final Finder excludedTimestamp = find.ancestor(
        of: timestamp,
        matching: find.byType(ExcludeSemantics),
      );
      expect(excludedTimestamp, findsOneWidget);

      // The timestamp's own ExcludeSemantics wrapper sits inside the live
      // region subtree — so the timestamp is structurally present under the
      // liveRegion but excluded from what it announces. (Two ExcludeSemantics
      // descend from the live region: this one and the decorative live dot.)
      final Finder excludedTimestampInLiveRegion = find.descendant(
        of: liveRegion,
        matching: find.ancestor(
          of: timestamp,
          matching: find.byType(ExcludeSemantics),
        ),
      );
      expect(excludedTimestampInLiveRegion, findsOneWidget);
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
