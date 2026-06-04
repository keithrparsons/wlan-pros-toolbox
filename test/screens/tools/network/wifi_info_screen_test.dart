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
      // macOS cannot expose Rx rate — honest per-field note.
      expect(find.text('Not exposed by macOS CoreWLAN'), findsOneWidget);
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
      // macOS-honest per-field note still present (cards path).
      expect(find.text('Not exposed by macOS CoreWLAN'), findsOneWidget);
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
