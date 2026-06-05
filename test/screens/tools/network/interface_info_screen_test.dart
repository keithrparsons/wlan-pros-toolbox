// Interface Information screen — widget tests (Batch 8 truthfulness + a11y gate).
//
// Drives the real InterfaceInfoService behind injected seams (interface lister,
// connected-AP reader, shared cache, and a clock) so warm / stale / fresh cache
// paths are exercised deterministically — no platform channel is touched. The
// PublicIpService is injected with a fake fetcher so the Device card's public-IP
// row resolves offline.
//
// Coverage:
//   * Warm cache render → cached Wi-Fi identity shows WITH the "as of" line.
//   * Stale cache (past the threshold) → identity is bypassed, the iOS Refresh
//     Wi-Fi prompt shows instead of a stale identity, and NO "as of" line.
//   * Fresh (live) read → identity shows, NO "as of" line (the live path is
//     never labelled "as of").
//   * Refresh Wi-Fi button: semantics (single, un-doubled announcement),
//     disabled+pending while the bounce is in flight, and the failure path
//     (Shortcut could not open) dropping the pending state.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/interface_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap_cache.dart';
import 'package:wlan_pros_toolbox/services/network/interface_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/public_ip_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// The network_info_plus method channel — stubbed to return null for every call
/// so the snapshot's addressing reads (gateway/submask/IP/IPv6) resolve
/// in-process without a real platform handler, letting `read()` settle within a
/// pump. The addressing fields are not what these tests assert — identity /
/// cache behavior is.
const MethodChannel _networkInfoChannel =
    MethodChannel('dev.fluttercommunity.plus/network_info');

/// A bridge whose `runShortcut` is scripted: it never touches a method channel.
/// `opened` controls whether the one-shot bounce "succeeds" (true) or fails to
/// open (false → the screen drops the pending state).
class _FakeBridge extends WiFiDetailsBridge {
  _FakeBridge({required this.opened});

  final bool opened;
  int runCount = 0;

  @override
  Future<bool> runShortcut(String name) async {
    runCount++;
    return opened;
  }
}

/// A PublicIpService that resolves offline to a fixed IP (no network).
PublicIpService _fakePublicIp() =>
    PublicIpService(fetcher: (String url, Duration t) async => '203.0.113.7');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Stub the network_info_plus channel to null so addressing reads settle
  // in-process and the snapshot future completes within a pump.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_networkInfoChannel, (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_networkInfoChannel, null);
  });

  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.dark(), home: child);

  // Builds the screen wired to the real service behind seams. [cachedAp] (with
  // [cacheAgeMinutes]) seeds the shared cache; [readerAp] is what the cold/fresh
  // per-platform reader returns when the cache is bypassed.
  Widget buildScreen({
    ConnectedAp? cachedAp,
    int cacheAgeMinutes = 0,
    ConnectedAp? readerAp,
    WiFiDetailsBridge? bridge,
  }) {
    final cache = ConnectedApCache();
    if (cachedAp != null) cache.update(cachedAp);
    final DateTime cachedMoment = cache.updatedAt ?? DateTime.now();

    final service = InterfaceInfoService(
      interfaceLister: () async => const [],
      connectedApReader: () async => (ap: readerAp, authorized: true),
      connectedApCache: cache,
      // Advance the clock so a seeded cache reads as `cacheAgeMinutes` old.
      now: () => cachedMoment.add(Duration(minutes: cacheAgeMinutes)),
    );

    return host(
      InterfaceInfoScreen(
        service: service,
        publicIpService: _fakePublicIp(),
        // Force the iOS Shortcut path so the on-demand Refresh Wi-Fi affordance
        // is reachable in the stale/cold case.
        wifiSourceOverride: WifiInfoSource.iosShortcuts,
        iosBridge: bridge ?? _FakeBridge(opened: true),
      ),
    );
  }

  testWidgets('warm cache renders cached Wi-Fi identity with an "as of" line',
      (tester) async {
    await tester.pumpWidget(buildScreen(
      cachedAp: const ConnectedAp(
        ssid: 'KeithNet',
        bssid: 'a4:83:e7:00:11:22',
      ),
      cacheAgeMinutes: 1, // well within the 5-minute threshold
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The cached identity is shown...
    expect(find.text('KeithNet'), findsOneWidget);
    expect(find.text('a4:83:e7:00:11:22'), findsOneWidget);
    // ...with an honest remembered-reading "as of" line (not presented as live).
    expect(
      find.textContaining('Remembered reading, as of'),
      findsOneWidget,
    );
    // A warm reading does NOT show the Refresh prompt (identity is present).
    expect(find.text('Refresh Wi-Fi'), findsNothing);
  });

  testWidgets(
      'stale cache is bypassed: Refresh prompt shows, no stale identity, no "as of"',
      (tester) async {
    await tester.pumpWidget(buildScreen(
      // The cache holds the PREVIOUS network, set 6 minutes ago (> threshold)...
      cachedAp: const ConnectedAp(ssid: 'OldNetwork'),
      cacheAgeMinutes: 6,
      // ...and the fresh per-platform read returns nothing (iOS, no live payload).
      readerAp: null,
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The stale identity is NOT presented as current.
    expect(find.text('OldNetwork'), findsNothing);
    // No "as of" line (nothing cache-sourced is being shown).
    expect(find.textContaining('Remembered reading, as of'), findsNothing);
    // Instead the user is offered the explicit on-demand Refresh.
    expect(find.text('Refresh Wi-Fi'), findsOneWidget);
  });

  testWidgets('a fresh (live) read shows identity with NO "as of" line',
      (tester) async {
    await tester.pumpWidget(buildScreen(
      // Cold cache → the reader's live payload is used directly.
      readerAp: const ConnectedAp(
        ssid: 'LiveNet',
        bssid: 'aa:bb:cc:11:22:33',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('LiveNet'), findsOneWidget);
    // The live path is never labelled "as of".
    expect(find.textContaining('Remembered reading, as of'), findsNothing);
  });

  group('Refresh Wi-Fi button', () {
    testWidgets('exposes a single button semantics (no doubled announcement)',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(buildScreen(readerAp: null)); // cold → prompt shows
      await tester.pump();
    await tester.pump(const Duration(seconds: 1));

      expect(find.text('Refresh Wi-Fi'), findsOneWidget);
      // The custom Semantics wrapper carries the explicit label AND excludes the
      // child's semantics, so the action announces exactly once. The button's
      // own visible label text is therefore NOT also exposed as a semantics node.
      expect(
        find.bySemanticsLabel(
          'Refresh Wi-Fi by running the WLAN Pros Wi-Fi Shortcut',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('tapping fires the Shortcut and shows the pending state',
        (tester) async {
      final bridge = _FakeBridge(opened: true);
      await tester.pumpWidget(buildScreen(readerAp: null, bridge: bridge));
      await tester.pump();
    await tester.pump(const Duration(seconds: 1));

      await tester.ensureVisible(find.byType(OutlinedButton));
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump(); // let setState(_refreshingWifi = true) apply

      expect(bridge.runCount, 1);
      // Pending: label folds to "Reading…" and the button is disabled.
      expect(find.text('Reading…'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('a failed Shortcut open drops the pending state honestly',
        (tester) async {
      final bridge = _FakeBridge(opened: false); // could not open the Shortcut
      await tester.pumpWidget(buildScreen(readerAp: null, bridge: bridge));
      await tester.pump();
    await tester.pump(const Duration(seconds: 1));

      await tester.ensureVisible(find.byType(OutlinedButton));
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();
    await tester.pump(const Duration(seconds: 1));

      expect(bridge.runCount, 1);
      // Pending cleared: the button returns to its enabled "Refresh Wi-Fi" rest
      // state — no fabricated value, no stuck spinner.
      expect(find.text('Reading…'), findsNothing);
      expect(find.text('Refresh Wi-Fi'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNotNull);
    });
  });
}
