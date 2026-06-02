// Cellular Information screen — widget tests (iOS Live-only).
//
// The tool selects its data source per platform behind a seam, so the tests
// drive each source explicitly via [CellularInfoScreen.sourceOverride] plus an
// injected fake bridge — no real platform channel is touched.
//
// Covers the state matrix from SOP-007 §5:
//   * iOS source (LIVE ONLY): the idle "Tap Start" state; Start sets the shared
//     monitoring flag + fires the PLAIN combined-Live trigger; stream
//     consumption renders live carrier / bars updates (bars stay 0..4, never
//     dBm; no fabricated grade); Stop clears the flag and freezes the last
//     values; dispose clears the flag (Vera regression).
//   * macOS / unsupported native: the explicit "not available on this platform"
//     state (hard requirement — never a silent empty).
//   * web source: download-the-app fallback.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/cellular_info_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_unavailable_view.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_info.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_info_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_live_shortcuts_config.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A fake iOS Shortcuts bridge: feeds the Live streaming flow without a platform
/// channel, and records the PLAIN combined-Live trigger call.
class _FakeBridge implements CellularInfoBridge {
  _FakeBridge({
    this.everReceived = false,
    this.latest,
    this.runShortcutResult = true,
  });

  bool everReceived;
  CellularInfo? latest;
  bool monitoringActive = false;

  /// What [runShortcut] returns (false => could not open Shortcuts).
  bool runShortcutResult;

  /// Records the exact name passed to [runShortcut] for assertions. The PLAIN
  /// trigger carries ONLY the name (no tool / no x-callback).
  String? lastRunShortcutName;
  int runShortcutCalls = 0;

  final StreamController<CellularInfo> updatesController =
      StreamController<CellularInfo>.broadcast();

  @override
  Future<bool> hasEverReceivedPayload() async => everReceived;

  @override
  Future<CellularInfo?> readLatest() async => latest;

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
  Stream<CellularInfo> get updates => updatesController.stream;
}

CellularInfo _sample() => const CellularInfo(
      carrier: 'Verizon',
      radioTechnology: '5G NR',
      signalBars: 3,
      countryCode: 'US',
      roaming: false,
    );

void main() {
  Widget host(Widget child) => MaterialApp(theme: AppTheme.dark(), home: child);

  group('CellularInfoScreen — iOS source (Live only)', () {
    testWidgets('idle state offers Start and the begin-live hint',
        (tester) async {
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(everReceived: false),
        ),
      ));
      await tester.pumpAndSettle();
      // Live is the only iOS mode: a clean idle "Tap Start" state, no Snapshot
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
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
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
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(everReceived: true, latest: _sample()),
        ),
      ));
      await tester.pumpAndSettle();
      // The user clearly has the Shortcut working (hasEverReceived = true), so
      // the install/setup note is noise and is gone permanently.
      expect(find.textContaining('WLAN Pros Live'), findsNothing);
    });

    testWidgets('Start sets the flag and fires the PLAIN combined-Live trigger',
        (tester) async {
      final bridge = _FakeBridge(everReceived: true, latest: _sample());
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(bridge.monitoringActive, isTrue);
      // Start fires the run-shortcut trigger ONCE, with the ONE canonical
      // combined-Live name shared with the Wi-Fi tool (the bridge-level test
      // asserts the URL is the plain, non-x-callback form).
      expect(bridge.runShortcutCalls, 1);
      expect(bridge.lastRunShortcutName,
          WifiLiveShortcutsConfig.kLiveShortcutName);
      expect(bridge.lastRunShortcutName, 'WLAN Pros Live');
      expect(find.text('Stop'), findsOneWidget);
    });

    testWidgets('stream consumption renders live carrier / bars updates',
        (tester) async {
      final bridge = _FakeBridge(everReceived: true, latest: _sample());
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      bridge.updatesController.add(const CellularInfo(
        carrier: 'T-Mobile',
        radioTechnology: 'LTE',
        signalBars: 2,
        countryCode: 'US',
        roaming: false,
      ));
      await tester.pumpAndSettle();

      // The live value updated from the streamed payload; bars stay 0..4 and are
      // NEVER a dBm/RSRP value. Cellular is never graded.
      expect(find.text('T-Mobile'), findsOneWidget);
      expect(find.text('2 of 4'), findsOneWidget);
      expect(find.text('2 dBm'), findsNothing);
      // The honest signal footnote is present in the live surface.
      expect(
        find.textContaining('Apple does not expose a raw signal reading'),
        findsOneWidget,
      );
    });

    testWidgets('Stop clears the monitoring flag and freezes the last values',
        (tester) async {
      final bridge = _FakeBridge(everReceived: true, latest: _sample());
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(bridge.monitoringActive, isTrue);

      bridge.updatesController.add(const CellularInfo(carrier: 'T-Mobile'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      // Flag cleared; the idle Start control is back; the last value stays frozen
      // on screen (the snapshot).
      expect(bridge.monitoringActive, isFalse);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('T-Mobile'), findsOneWidget);
    });

    testWidgets('Start failing to open the Shortcut clears the flag + errors',
        (tester) async {
      final bridge = _FakeBridge(
        everReceived: true,
        latest: _sample(),
        runShortcutResult: false,
      );
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(bridge.monitoringActive, isFalse);
      expect(find.textContaining('Could not start live streaming'),
          findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('dispose clears the monitoring flag (Vera regression)',
        (tester) async {
      final bridge = _FakeBridge(everReceived: true, latest: _sample());
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(bridge.monitoringActive, isTrue);

      // Tear the screen down. Dispose must clear the shared flag so the recursive
      // Shortcut stops and the Wi-Fi tool is never stranded as "streaming".
      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(bridge.monitoringActive, isFalse);
    });
  });

  group('CellularInfoScreen — platform fallbacks', () {
    testWidgets(
        'macOS / unsupported native shows the explicit not-available state',
        (tester) async {
      await tester.pumpWidget(host(
        const CellularInfoScreen(
          sourceOverride: CellularInfoSource.unsupported,
        ),
      ));
      await tester.pumpAndSettle();
      // Hard requirement: an unmistakable warning, not a silent empty.
      expect(find.byType(NetworkUnavailableView), findsOneWidget);
      expect(find.text('Cellular is not available here'), findsOneWidget);
      expect(
        find.textContaining('requires an iPhone with a cellular connection'),
        findsOneWidget,
      );
    });

    testWidgets('web shows the download-the-app fallback', (tester) async {
      await tester.pumpWidget(host(
        const CellularInfoScreen(sourceOverride: CellularInfoSource.web),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(NetworkUnavailableView), findsOneWidget);
    });
  });

  group('CellularInfoSourceResolver', () {
    test('iOS resolves to the Shortcuts source', () {
      expect(
        CellularInfoSourceResolver.resolve(platformOverride: TargetPlatform.iOS),
        CellularInfoSource.iosShortcuts,
      );
    });

    test('macOS resolves to unsupported (no cellular radio)', () {
      expect(
        CellularInfoSourceResolver.resolve(
          platformOverride: TargetPlatform.macOS,
        ),
        CellularInfoSource.unsupported,
      );
    });

    test('Android and Windows resolve to unsupported', () {
      expect(
        CellularInfoSourceResolver.resolve(
          platformOverride: TargetPlatform.android,
        ),
        CellularInfoSource.unsupported,
      );
      expect(
        CellularInfoSourceResolver.resolve(
          platformOverride: TargetPlatform.windows,
        ),
        CellularInfoSource.unsupported,
      );
    });
  });
}
