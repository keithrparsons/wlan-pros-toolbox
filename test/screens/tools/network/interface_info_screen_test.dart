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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/interface_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/ap_name_cache.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap_cache.dart';
import 'package:wlan_pros_toolbox/services/network/interface_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/public_ip_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

/// One non-extended IE element: [id][len][...data].
List<int> _ie(int id, List<int> data) => <int>[id, data.length, ...data];

/// A synthetic UniFi (Ubiquiti) Tag 221 AP-name IE: OUI 00:15:6D, type 0x01.
List<int> _unifiNameBlob(String name) =>
    _ie(221, <int>[0x00, 0x15, 0x6D, 0x01, ...name.codeUnits]);

/// A fake macOS WifiInfoService for the persistent-adapter tests: it serves the
/// connected BSSID, a UniFi name IE blob, and a granted Location, and touches no
/// platform channel. When [gate] is supplied, the beacon-IE scan blocks on it —
/// so a test can hold the fire-and-forget scan open, assert the honest first-read
/// null, then release it and assert the auto-re-read surfaces the name.
WifiInfoService _macService({
  required String bssid,
  required String apName,
  Future<void>? gate,
}) =>
    WifiInfoService(
      platformOverride: 'macos',
      invoke: (String method, [dynamic args]) async {
        switch (method) {
          case 'getWifiInfo':
            return <String, Object?>{
              'ssid': 'KeithNet',
              'bssid': bssid,
              'poweredOn': true,
              'locationAuthorized': true,
            };
          case 'connectedApIeBlob':
            if (gate != null) await gate; // hold the scan open until released
            return <String, Object?>{
              'ieBytes': Uint8List.fromList(_unifiNameBlob(apName)),
              'bssid': bssid,
              'locationAuthorized': true,
            };
          case 'isLocationAuthorized':
            return true;
          default:
            return null;
        }
      },
    );

/// The network_info_plus method channel — stubbed to return null for every call
/// so the snapshot's addressing reads (gateway/submask/IP/IPv6) resolve
/// in-process without a real platform handler, letting `read()` settle within a
/// pump. The addressing fields are not what these tests assert — identity /
/// cache behavior is.
const MethodChannel _networkInfoChannel =
    MethodChannel('dev.fluttercommunity.plus/network_info');

/// The ANDROID TRANSPORT channel (round-4b, 2026-07-14) — stubbed for the SAME
/// reason as the one above, and it must be stubbed for these tests to settle.
///
/// WHY IT LANDS HERE, IN A TEST ABOUT WI-FI IDENTITY CACHING. `InterfaceInfoService`
/// resolves its `notOnWifi` flag through `WifiConnectionService.status()`
/// (interface_info_service.dart:328), which builds its own service with NO
/// `platformOverride` — so it runs as `defaultTargetPlatform`, and IN A FLUTTER
/// WIDGET TEST THAT IS `TargetPlatform.android`. The new Android transport probe
/// therefore fires here, hits an unstubbed channel, and the resulting async round
/// trip does NOT settle inside the fixed `pump()` count these tests use — so the
/// snapshot future never completes and the cached identity never renders.
///
/// `available: false` is the HONEST "we could not read the transport" payload. It
/// resolves to `WifiConnectionStatus.unknown`, which is EXACTLY what this service
/// got on Android before round 4b — so these tests assert the same behavior they
/// always did, and the stub is a fidelity fix, not a workaround.
const MethodChannel _networkTransportChannel =
    MethodChannel('com.wlanpros.toolbox/network_transport');

/// A bridge whose `runShortcut` is scripted: it never touches a method channel.
/// `opened` controls whether the one-shot bounce "succeeds" (true) or fails to
/// open (false → the screen drops the pending state).
class _FakeBridge extends WiFiDetailsBridge {
  _FakeBridge({required this.opened, this.extras});

  final bool opened;

  /// The Wi-Fi-Shortcut payload [readLatest] returns (Orb-parity local
  /// addresses). Null by default so the standard tests touch no channel and see
  /// no new rows (the current-Shortcut, absent state).
  final WiFiDetails? extras;

  int runCount = 0;

  @override
  Future<bool> runShortcut(String name) async {
    runCount++;
    return opened;
  }

  @override
  Future<WiFiDetails?> readLatest() async => extras;
}

/// A PublicIpService that resolves offline to a fixed IP (no network).
PublicIpService _fakePublicIp() =>
    PublicIpService(fetcher: (String url, Duration t) async => '203.0.113.7');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> clipboardWrites;
  // Stub the network_info_plus channel to null so addressing reads settle
  // in-process and the snapshot future completes within a pump.
  setUp(() {
    // The AP-name cache is the app-wide singleton now; reset it so the
    // auto-re-read test genuinely starts with the name UNdecoded (its first-read
    // assertion depends on a cold cache).
    ApNameCache.instance.clear();
    clipboardWrites = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_networkInfoChannel, (call) async => null);
    // Honest "the transport could not be read" → `unknown`, which is what this
    // service resolved to on Android before the transport probe existed. Same
    // behavior, now stated instead of inherited.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _networkTransportChannel,
      (MethodCall call) async => <String, Object?>{'available': false},
    );
    // Capture the §8.16 copy report at the Clipboard channel boundary so the
    // AP-name copy-row present/absent paths can be asserted (MEDIUM-2).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final Map<Object?, Object?> args =
            call.arguments as Map<Object?, Object?>;
        clipboardWrites.add(args['text'] as String);
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_networkInfoChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_networkTransportChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Taps the copy affordance and returns the copied §8.16 report text.
  Future<String> copyReport(WidgetTester tester) async {
    final Finder copyBtn = find.byType(AppCopyAction);
    await tester.ensureVisible(copyBtn);
    await tester.pumpAndSettle();
    await tester.tap(copyBtn);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2)); // drain the "Copied" timer
    expect(clipboardWrites, isNotEmpty,
        reason: 'the copy report must have been produced');
    return clipboardWrites.last;
  }

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

  testWidgets(
    'the Refresh action exposes an accessible NAME, not just a tooltip '
    '(WCAG 2.2 AA SC 4.1.2)',
    (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(buildScreen(
        cachedAp: const ConnectedAp(
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
        ),
        cacheAgeMinutes: 1,
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // `tooltip: 'Refresh'` maps to AXHelp, not AXTitle; the explicit Semantics
      // label is the accessible name. Removing it (the mutation) → red.
      expect(find.bySemanticsLabel('Refresh interface info'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Refresh interface info')),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          label: 'Refresh interface info',
        ),
        reason: 'the Refresh action must read as a named, enabled button to AT',
      );

      handle.dispose();
    },
  );

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

  group('AP name (vendor-advertised, beside the BSSID)', () {
    testWidgets(
        'present: the AP name row shows and the FULL BSSID still renders',
        (tester) async {
      await tester.pumpWidget(buildScreen(
        readerAp: const ConnectedAp(
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
          apName: 'AP-Lobby-3',
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // The vendor-advertised name gets its own labelled row...
      expect(find.text('AP name'), findsOneWidget);
      expect(find.text('AP-Lobby-3'), findsOneWidget);
      // ...and the full BSSID is preserved as the precise identifier (not a tail).
      expect(find.text('a4:83:e7:00:11:22'), findsOneWidget);
    });

    testWidgets(
        'absent: no AP-name row and no fabricated name — the BSSID stands alone',
        (tester) async {
      await tester.pumpWidget(buildScreen(
        readerAp: const ConnectedAp(
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
          // No apName advertised (iOS platform ceiling, or the AP names none).
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Honest-null: the row is omitted entirely, never a placeholder or guess.
      expect(find.text('AP name'), findsNothing);
      expect(find.text('a4:83:e7:00:11:22'), findsOneWidget);
    });

    // MEDIUM-2: the copy report's `line('AP name', w.apName)` path.
    testWidgets('copy report: present → an "AP name" line above the BSSID',
        (tester) async {
      await tester.pumpWidget(buildScreen(
        readerAp: const ConnectedAp(
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
          apName: 'AP-Lobby-3',
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final String report = await copyReport(tester);
      expect(report, contains('AP name: AP-Lobby-3'));
      expect(report, contains('BSSID: a4:83:e7:00:11:22'));
      // Name leads the BSSID in the report.
      expect(report.indexOf('AP name:'), lessThan(report.indexOf('BSSID:')));
    });

    testWidgets('copy report: absent → no "AP name" line, BSSID still present',
        (tester) async {
      await tester.pumpWidget(buildScreen(
        readerAp: const ConnectedAp(
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final String report = await copyReport(tester);
      // Honest-null: no AP-name line at all, never a placeholder.
      expect(report, isNot(contains('AP name:')));
      expect(report, contains('BSSID: a4:83:e7:00:11:22'));
    });

    // HIGH-1: the fire-and-forget name is null on the first read and must appear
    // WITHOUT a manual refresh — the screen holds the adapter (per-BSSID cache
    // survives) and auto-re-reads when the pending scan resolves.
    testWidgets(
        'auto re-read: name is absent on the first read, then appears once the '
        'background scan resolves (persistent adapter, no manual Refresh)',
        (tester) async {
      const String bssid = 'a4:83:e7:00:11:22';
      // Hold the beacon-IE scan open so the first read genuinely resolves BEFORE
      // the name does — the real production ordering, made deterministic.
      final Completer<void> releaseScan = Completer<void>();
      final InterfaceInfoService service = InterfaceInfoService(
        interfaceLister: () async => const [],
        // A HELD, enriching macOS adapter (real MacWifiInfoAdapter over a fake
        // service) — NOT an injected model — so the fire-and-forget cache path
        // is exercised end to end.
        wifiInfoAdapter: MacWifiInfoAdapter(
          service: _macService(
            bssid: bssid,
            apName: 'UAP-Lobby',
            gate: releaseScan.future,
          ),
          enrichApName: true,
        ),
        connectedApCache: ConnectedApCache(),
      );

      await tester.pumpWidget(host(
        InterfaceInfoScreen(
          service: service,
          publicIpService: _fakePublicIp(),
          wifiSourceOverride: WifiInfoSource.macosCoreWlan,
        ),
      ));
      await tester.pump(); // read 1 resolves
      await tester.pump(const Duration(seconds: 1));

      // First read: the BSSID is up but the scan is still blocked, so the name
      // has honestly not resolved yet — no row, no placeholder.
      expect(find.text(bssid), findsOneWidget);
      expect(find.text('AP name'), findsNothing);

      // Release the scan; the cached name resolves and the screen auto-re-reads.
      releaseScan.complete();
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // The name now appears — no manual Refresh was tapped.
      expect(find.text('AP name'), findsOneWidget);
      expect(find.text('UAP-Lobby'), findsOneWidget);
      expect(find.text(bssid), findsOneWidget);
    });
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

  group('Orb-parity Wi-Fi-Shortcut local addresses', () {
    testWidgets(
        'PRESENT: a Shortcut-derived local IPv4/IPv6 renders alongside the '
        'native addresses, attributed to the Wi-Fi Shortcut', (tester) async {
      final bridge = _FakeBridge(
        opened: true,
        extras: const WiFiDetails(
          ipv4Local: '192.168.1.42',
          ipv6Local: 'fe80::1c2d',
        ),
      );
      await tester.pumpWidget(buildScreen(
        readerAp: const ConnectedAp(
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
        ),
        bridge: bridge,
      ));
      await tester.pumpAndSettle();

      // Native wifiIPv4/IPv6 are null in these hermetic tests, so the Shortcut
      // rows surface an address the native read did not — clearly attributed.
      expect(find.text('IPv4 (Wi-Fi Shortcut)'), findsOneWidget);
      expect(find.text('192.168.1.42'), findsOneWidget);
      expect(find.text('IPv6 (Wi-Fi Shortcut)'), findsOneWidget);
      expect(find.text('fe80::1c2d'), findsOneWidget);
    });

    testWidgets(
        'ABSENT: with no Shortcut payload the card reads exactly as today — no '
        'Wi-Fi Shortcut address rows', (tester) async {
      final bridge = _FakeBridge(opened: true); // extras == null (current Shortcut)
      await tester.pumpWidget(buildScreen(
        readerAp: const ConnectedAp(
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
        ),
        bridge: bridge,
      ));
      await tester.pumpAndSettle();

      expect(find.text('IPv4 (Wi-Fi Shortcut)'), findsNothing);
      expect(find.text('IPv6 (Wi-Fi Shortcut)'), findsNothing);
    });

    test(
        'shortcutLocalAddress: shows a differing address, hides a duplicate or '
        'a blank (no double-show, honest floor)', () {
      // PRESENT and different from the native row -> surface it.
      expect(shortcutLocalAddress('192.168.1.42', null), '192.168.1.42');
      expect(shortcutLocalAddress('192.168.1.42', '10.0.0.1'), '192.168.1.42');
      // DUPLICATE of the native row (after trimming) -> hide it.
      expect(shortcutLocalAddress('192.168.1.42', '192.168.1.42'), isNull);
      expect(shortcutLocalAddress('  192.168.1.42 ', '192.168.1.42'), isNull);
      // ABSENT / blank Shortcut value -> hide it (identical to today).
      expect(shortcutLocalAddress(null, '192.168.1.42'), isNull);
      expect(shortcutLocalAddress('   ', null), isNull);
    });
  });
}
