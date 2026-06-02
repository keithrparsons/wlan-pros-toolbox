// Cellular Information screen — widget tests (TICKET-02).
//
// The tool selects its data source per platform behind a seam, so the tests
// drive each source explicitly via [CellularInfoScreen.sourceOverride] plus an
// injected fake bridge — no real platform channel is touched.
//
// Covers the state matrix from SOP-007 §5:
//   * iOS source: needs-install empty state, one-shot success cards (the five
//     fields), and the honest signal-bars footnote.
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
import 'package:wlan_pros_toolbox/services/network/cellular_shortcuts_config.dart';
import 'package:wlan_pros_toolbox/services/network/shortcut_trigger_result.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A fake iOS Shortcuts bridge: returns a queued reading + install flag without
/// a platform channel, and records the one-tap trigger call (TICKET-03).
class _FakeBridge implements CellularInfoBridge {
  _FakeBridge({
    this.everReceived = false,
    this.latest,
    this.runShortcutResult = true,
  });

  bool everReceived;
  CellularInfo? latest;

  /// What [runShortcut] returns (false => could not open Shortcuts).
  bool runShortcutResult;
  String? lastRunShortcutName;
  String? lastRunShortcutTool;
  int runShortcutCalls = 0;

  final StreamController<ShortcutTriggerResult> triggerController =
      StreamController<ShortcutTriggerResult>.broadcast();

  @override
  Future<bool> hasEverReceivedPayload() async => everReceived;

  @override
  Future<CellularInfo?> readLatest() async => latest;

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
        (r) => ShortcutTriggerEvent(tool: 'cellular-info', result: r),
      );

  @override
  Stream<ShortcutTriggerResult> get triggerResults => triggerController.stream;
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

  group('CellularInfoScreen — iOS source', () {
    testWidgets('needs-install empty state offers Get Reading + Install',
        (tester) async {
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(everReceived: false),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No cellular data yet'), findsOneWidget);
      // "Get Reading" is the primary trigger; "Install Shortcut" is secondary.
      expect(find.text('Get Reading'), findsOneWidget);
      expect(find.text('Install Shortcut'), findsOneWidget);
    });

    testWidgets('success shows the five fields and the signal footnote',
        (tester) async {
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(everReceived: true, latest: _sample()),
        ),
      ));
      await tester.pumpAndSettle();

      // The four card titles.
      expect(find.text('Carrier'), findsWidgets);
      expect(find.text('Radio'), findsOneWidget);
      expect(find.text('Signal'), findsOneWidget);
      expect(find.text('Network'), findsOneWidget);

      // The values.
      expect(find.text('Verizon'), findsOneWidget);
      expect(find.text('5G NR'), findsOneWidget);
      expect(find.text('US'), findsOneWidget);
      expect(find.text('No'), findsOneWidget); // roaming = false

      // Signal bars render as "N of 4" — NEVER a dBm/RSRP value. The bar value
      // text must be exactly "3 of 4"; no bar value carries a dBm/RSRP unit.
      expect(find.text('3 of 4'), findsOneWidget);
      expect(find.text('3 dBm'), findsNothing);
      expect(find.text('-3 dBm'), findsNothing);
      expect(find.textContaining('RSRP: '), findsNothing);

      // The honest footnote stating bars are the only signal indicator.
      expect(
        find.textContaining('Apple does not expose a raw signal reading'),
        findsOneWidget,
      );
    });

    testWidgets('missing fields render an honest Unavailable', (tester) async {
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(
            everReceived: true,
            latest: const CellularInfo(carrier: 'AT&T'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('AT&T'), findsOneWidget);
      // Radio Technology / Country Code / Roaming all absent -> Unavailable.
      expect(find.text('Unavailable'), findsWidgets);
    });

    testWidgets('Get Reading fires runShortcut with the canonical name',
        (tester) async {
      final _FakeBridge bridge =
          _FakeBridge(everReceived: true, latest: _sample());
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get Reading'));
      await tester.pump();
      expect(bridge.runShortcutCalls, 1);
      // The EXACT canonical Shortcut name the published Shortcut must match.
      expect(
        bridge.lastRunShortcutName,
        CellularShortcutsConfig.kCompanionShortcutName,
      );
      expect(bridge.lastRunShortcutName, 'WLAN Pros Cellular');
      // The originating tool id is carried so the x-callback return can
      // deep-link back to THIS screen on a cold relaunch (TICKET-03 UX fix).
      expect(bridge.lastRunShortcutTool, 'cellular-info');
    });

    testWidgets('x-error return shows the honest error + install fallback',
        (tester) async {
      final _FakeBridge bridge =
          _FakeBridge(everReceived: true, latest: _sample());
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get Reading'));
      await tester.pump();
      bridge.triggerController.add(ShortcutTriggerResult.error);
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not get a reading'), findsOneWidget);
      expect(find.text('Install the Shortcut'), findsOneWidget);
    });

    testWidgets('x-success return refreshes from the App Group payload',
        (tester) async {
      final _FakeBridge bridge =
          _FakeBridge(everReceived: true, latest: _sample());
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Verizon'), findsOneWidget);

      await tester.tap(find.text('Get Reading'));
      await tester.pump();
      // The App Group payload updates while in Shortcuts; x-success re-reads it.
      bridge.latest = const CellularInfo(carrier: 'T-Mobile');
      bridge.triggerController.add(ShortcutTriggerResult.success);
      await tester.pumpAndSettle();

      expect(find.text('T-Mobile'), findsOneWidget);
      expect(find.text('Verizon'), findsNothing);
      expect(find.textContaining('Could not get a reading'), findsNothing);
    });

    testWidgets('runShortcut failing to open shows the error immediately',
        (tester) async {
      final _FakeBridge bridge = _FakeBridge(
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
      await tester.tap(find.text('Get Reading'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not get a reading'), findsOneWidget);
    });

    testWidgets(
        'app resume with no callback unsticks the triggering state',
        (tester) async {
      // Regression (Vera priority-1): the user taps Get Reading, lands in
      // Shortcuts, then back-swipes out WITHOUT the x-callback ever firing. On
      // resume the screen must clear _triggering so the button re-enables and
      // the spinner never sticks.
      final _FakeBridge bridge =
          _FakeBridge(everReceived: true, latest: _sample());
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
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
