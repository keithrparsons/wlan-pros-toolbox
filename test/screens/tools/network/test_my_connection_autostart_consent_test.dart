// AUTO-START × CELLULAR CONSENT — the gate on the app's PRIMARY entry point.
//
// WHY THIS FILE EXISTS (round-4 P0, 2026-07-14). The cellular-data consent gate
// was built into the pre-run BUTTON. But the home screen's "Check My Connection"
// hero does not go through the button: it routes with `arguments == true`
// (app_router.dart:716) → `TestMyConnectionScreen(autoStart: true)` → a post-frame
// callback → `_run()`.
//
// `_run` took `{bool includeThroughput = true}`. It DEFAULTED TO TRUE and carried
// no consent check of its own — the decision lived only in the button. So the
// single most-travelled path in the app spent the user's cellular data with no
// warning, no decline path, and no consent.
//
// FOUR callers reached `_run()` on the default:
//   * :558  the auto-start post-frame callback   (the home hero — THE P0)
//   * :1573 `onRunAgain` on the RESULT screen    (re-run, also unconsented)
//   * :2658 `onInstalled` after Shortcut setup
//   * :1840 the pre-run button                   (the ONLY consenting one)
//
// AND THE WARNING COULD NOT HAVE SAVED IT, STRUCTURALLY. It is gated
// `if (_notOnWifi && !_running)`; `_run()` sets `_running = true` SYNCHRONOUSLY, and
// `_notOnWifi` reads the sampler, which settles a few hundred ms AFTER initState —
// while the post-frame callback fires on FRAME ONE. On frame one `_notOnWifi` is
// still `false`, so even a consent check placed inside `_run` would have read "on
// Wi-Fi" and waved the run through. The probe has to be AWAITED, not read.
//
// This was invisible to the suite: no test mounted `autoStart: true` together with
// a not-on-Wi-Fi probe. Every consent test mounts through `_pumpPreRun`, which
// never sets `autoStart`. This file is that missing test.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_data_cost.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/services/network/dns_probe_service.dart';
import 'package:wlan_pros_toolbox/services/network/ip_geo_service.dart';
import 'package:wlan_pros_toolbox/services/network/live_onboarding_service.dart';
import 'package:wlan_pros_toolbox/services/network/network_details_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// iOS reports NO Wi-Fi interface on the path: the cellular-only iPhone.
class _NoWifiPath implements WifiPathProbe {
  @override
  Future<WifiPathFacts?> read() async => const WifiPathFacts(
    usesWifi: false,
    wifiSatisfied: false,
    wifiInterfacePresent: false,
  );
}

/// iOS reports a Wi-Fi path: the device is associated. The CONTROL.
class _OnWifiPath implements WifiPathProbe {
  @override
  Future<WifiPathFacts?> read() async => const WifiPathFacts(
    usesWifi: true,
    wifiSatisfied: true,
    wifiInterfacePresent: true,
  );
}

class _NoAddresses implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => null;
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Bridge implements WiFiDetailsBridge {
  @override
  Future<bool> consumeShortcutMissing() async => false;
  @override
  Future<void> markSetupInitiated() async {}
  @override
  Future<bool> hasInitiatedSetup() async => false;
  @override
  Future<bool> isShortcutsAppInstalled() async => true;
  @override
  Future<void> setLiveOriginRoute(String route) async {}
  @override
  Future<String?> consumeLiveErrorNav() async => null;

  // Scene-teardown restore seam. Default = NO pending run, so every pre-existing
  // test keeps asserting the app does NOT drag the user into a tool. They are the
  // counterweight net for the restore.
  @override
  Future<void> armLiveRun(String route) async {}
  @override
  Future<PendingLiveRun?> pendingLiveRun() async => null;
  @override
  Future<void> clearLiveRun() async {}
  @override
  Future<bool> hasEverReceivedPayload() async => true;
  @override
  Future<DateTime?> payloadReceivedAt() async => null;
  @override
  Future<WiFiDetails?> readLatest() async => null;
  @override
  Future<bool> isMonitoringActive() async => false;
  @override
  Future<void> setMonitoringActive(bool active) async {}
  @override
  Future<void> resetMonitoringColdStart() async {}
  @override
  Future<bool> openUrl(String url) async => true;
  @override
  Future<bool> runShortcut(String name) async => true;
  @override
  Future<bool> runShortcutOneShot(String name) async => true;
  @override
  Stream<WiFiDetails> get updates => const Stream<WiFiDetails>.empty();
}

class _FakeDns extends DnsProbeService {
  @override
  Future<DnsProbeResult> measure() async =>
      DnsProbeResult.success(host: 'cloudflare.com', millis: 12);
}

class _FakeNetDetails extends NetworkDetailsService {
  @override
  Future<NetworkDetails> read() async => const NetworkDetails();
}

class _FakeSecurity extends WifiSecurityService {
  @override
  Future<WifiSecurityInfo> fetch() async =>
      const WifiSecurityInfo.unavailable('cellular: no Wi-Fi');
}

class _FakeIpGeo extends IpGeoService {
  @override
  Future<IpGeoResult> lookup({required String rawQuery}) async =>
      IpGeoResult.failure(query: rawQuery, message: 'offline in test');
}

QualityResult _internet() => QualityResult(
  source: QualitySource.mock,
  measuredAt: DateTime.utc(2026, 1, 1),
  metrics: const <QualityMetric>[
    QualityMetric(
      id: MetricIds.latency,
      label: 'Latency',
      value: 60,
      unit: 'ms',
      grade: QualityGrade.fair,
    ),
    QualityMetric(
      id: MetricIds.download,
      label: 'Download',
      value: 60,
      unit: 'Mbps',
      grade: QualityGrade.fair,
    ),
  ],
);

/// Mounts the screen exactly as the HOME SCREEN HERO does — `autoStart: true` —
/// over a scripted Wi-Fi path.
Future<MockQualityClient> _pumpAutoStart(
  WidgetTester tester,
  WifiPathProbe path,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    LiveOnboardingService.prefsKey: true,
  });
  final _Bridge bridge = _Bridge();
  final MockQualityClient quality = MockQualityClient(
    scriptedResult: _internet(),
  );
  final WifiSignalSampler sampler = WifiSignalSampler(
    source: WifiInfoSource.iosShortcuts,
    iosBridge: bridge,
    connectionService: WifiConnectionService(
      networkInfo: _NoAddresses(),
      platformOverride: TargetPlatform.iOS,
      pathProbe: path,
    ),
  );
  addTearDown(sampler.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: TestMyConnectionScreen(
        // THE ONE LINE THIS FILE EXISTS FOR. The home hero sets it.
        autoStart: true,
        sourceOverride: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
        sampler: sampler,
        securityService: _FakeSecurity(),
        dnsProbeService: _FakeDns(),
        networkDetailsService: _FakeNetDetails(),
        ipGeoService: _FakeIpGeo(),
        enableCloudApps: false,
        onboardingService: LiveOnboardingService(
          getStore: SharedPreferences.getInstance,
        ),
        qualityClient: quality,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  return quality;
}

void main() {
  group('AUTO-START on a cellular-only iPhone (the home screen hero)', () {
    testWidgets('THE P0: auto-start must NOT spend cellular data without consent', (
      WidgetTester tester,
    ) async {
      final MockQualityClient quality = await _pumpAutoStart(
        tester,
        _NoWifiPath(),
      );

      // THE PROPERTY: no throughput bytes were requested. Either the run never
      // started, or it started without the data-hungry stages. Both are honest;
      // spending the data is the only thing that is not.
      //
      // NOTE the shape of this assertion. `lastIncludeThroughput` alone is a TRAP:
      // it initializes to `true`, so `expect(lastIncludeThroughput, isFalse)`
      // fails even for a screen that correctly never ran at all. The counter is
      // what makes "did not spend" expressible apart from "did not run".
      final bool spentCellularData =
          quality.measureCalls > 0 && quality.lastIncludeThroughput;

      expect(
        spentCellularData,
        isFalse,
        reason:
            'the auto-start path spent the user\'s cellular data on the '
            'speed test without ever asking: ~30 seconds of full-rate download, '
            'hundreds of MB to ~1 GB, from one tap on the home screen with no '
            'warning and no way out. Consent must live where the bytes are '
            'spent, not where the button is.',
      );
    });

    testWidgets('auto-start renders the data-cost warning and BOTH choices', (
      WidgetTester tester,
    ) async {
      final MockQualityClient quality = await _pumpAutoStart(
        tester,
        _NoWifiPath(),
      );

      // Zero bytes move until the user decides. The run does not start at all.
      expect(
        quality.measureCalls,
        0,
        reason: 'nothing may run before the user has seen the cost and chosen',
      );

      // The warning states the mechanism and the cost. The figure is now derived
      // from the probe constants (kCellularDataWarning), not a hedged range.
      expect(find.textContaining("You're on cellular"), findsOneWidget);
      expect(find.textContaining(kCellularDataWarning), findsOneWidget);
      expect(find.textContaining('29 MB at 10 Mbps'), findsOneWidget);

      // And BOTH paths are offered — consent is a choice, not a dead end.
      expect(find.text('Check My Connection (uses data)'), findsOneWidget);
      expect(find.text('Check without the speed test'), findsOneWidget);
    });

    testWidgets(
      'consenting from the auto-start screen DOES run the speed test',
      (WidgetTester tester) async {
        // The gate must not be a wall: a user who reads the cost and accepts it
        // gets the full check. Otherwise "safe" would just mean "broken".
        final MockQualityClient quality = await _pumpAutoStart(
          tester,
          _NoWifiPath(),
        );

        await tester.tap(find.text('Check My Connection (uses data)'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        expect(quality.measureCalls, 1);
        expect(
          quality.lastIncludeThroughput,
          isTrue,
          reason:
              'the tap IS the consent — the label above it carries the cost',
        );
      },
    );

    testWidgets(
      'declining from the auto-start screen still produces a result',
      (WidgetTester tester) async {
        final MockQualityClient quality = await _pumpAutoStart(
          tester,
          _NoWifiPath(),
        );

        await tester.tap(find.text('Check without the speed test'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        expect(quality.measureCalls, 1);
        expect(quality.lastIncludeThroughput, isFalse);

        // The withheld metric reads "Not measured" — nothing FAILED.
        expect(
          find.textContaining("Couldn't check"),
          findsNothing,
          reason:
              'a metric we chose not to take is not a metric we failed to '
              'take (GL-005, the two kinds of null)',
        );
      },
    );
  });

  // ========================================================================
  // THE CHOKEPOINT, exercised through the OTHER callers.
  //
  // Stopping auto-start fixes auto-start. It does NOT fix "Run again" on the
  // result screen, which was `onRunAgain: _run` — a tear-off riding the same
  // default-true parameter. A user who declined the speed test, got their result,
  // and then tapped "Run again" would have had their cellular data spent anyway.
  //
  // This is why the fix is not one line. `_run` now REQUIRES the caller to state a
  // spend decision, and then withholds the data-hungry stages anyway unless the
  // user has actually consented on this screen. These tests are the guard on that
  // second layer: without them, mutating the chokepoint away leaves the suite green
  // (it did — the mutation harness caught exactly that).
  // ========================================================================
  group('the consent chokepoint: "Run again" on a cellular result', () {
    /// Declines the speed test from the auto-start consent screen, lands on a
    /// result, then taps the result screen's "Run again".
    Future<MockQualityClient> declineThenRunAgain(WidgetTester tester) async {
      final MockQualityClient quality = await _pumpAutoStart(
        tester,
        _NoWifiPath(),
      );

      await tester.tap(find.text('Check without the speed test'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final Finder runAgain = find.text('Run again');
      expect(
        runAgain,
        findsOneWidget,
        reason:
            'sanity: the result screen must offer "Run again", or this '
            'test proves nothing about it',
      );
      await tester.ensureVisible(runAgain);
      await tester.pumpAndSettle();
      await tester.tap(runAgain);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      return quality;
    }

    testWidgets('"Run again" after DECLINING does not spend cellular data', (
      WidgetTester tester,
    ) async {
      final MockQualityClient quality = await declineThenRunAgain(tester);

      expect(
        quality.measureCalls,
        2,
        reason: 'sanity: "Run again" must actually re-run the check',
      );
      expect(
        quality.lastIncludeThroughput,
        isFalse,
        reason:
            'the user declined the data cost and never took it back. '
            '"Run again" must honor that decision, not quietly re-spend their '
            'data because a different caller reached _run().',
      );
    });

    testWidgets('"Run again" after CONSENTING still runs the full check', (
      WidgetTester tester,
    ) async {
      // The other half: consent is remembered for the screen, so a user who DID
      // accept the cost is not re-interrogated on every re-run. Without this, the
      // test above would pass against a chokepoint that simply never allows
      // throughput on cellular — a "gate" that is really a wall.
      final MockQualityClient quality = await _pumpAutoStart(
        tester,
        _NoWifiPath(),
      );

      await tester.tap(find.text('Check My Connection (uses data)'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // THE BUTTON'S LABEL CHANGED, AND THAT IS THE POINT (round-4b, 2026-07-14).
      //
      // This finder was `find.text('Run again')`. It passed — while the button it
      // tapped spent ANOTHER 50-500 MB of cellular data behind a label that said
      // nothing about cost, on a result screen where the warning and the
      // cost-labelled button had both been replaced by the result. Consent latches
      // for the MOUNT, so this test proved the SPEND was honored; nothing proved
      // the user could still SEE what it cost. Warned once, charged N times.
      //
      // Consent is still per-mount (no re-interrogation — that is what this test
      // defends, and it still does). But every button that can spend cellular data
      // now carries the cost in its own label, so every spend remains a
      // cost-labelled tap. The DECLINED path above still finds a bare "Run again",
      // correctly: with no consent on file the chokepoint downgrades that run and
      // it spends nothing, so it must not claim a cost it will not incur.
      final Finder runAgain = find.text('Run again (uses data)');
      expect(
        runAgain,
        findsOneWidget,
        reason:
            'after consenting, the re-run button SPENDS cellular data and '
            'must say so',
      );
      expect(
        find.text('Run again'),
        findsNothing,
        reason: 'the bare, cost-silent label must not survive a consent',
      );
      await tester.ensureVisible(runAgain);
      await tester.pumpAndSettle();
      await tester.tap(runAgain);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(quality.measureCalls, 2);
      expect(
        quality.lastIncludeThroughput,
        isTrue,
        reason: 'the user consented on this screen; re-running honors it',
      );
    });
  });

  group('AUTO-START on Wi-Fi (the control)', () {
    testWidgets('on Wi-Fi, auto-start runs the FULL check immediately', (
      WidgetTester tester,
    ) async {
      // The other half of the gate. Without this, the P0 test above would also
      // pass against a screen that simply never auto-runs anything — a fix that
      // "works" by breaking the feature. On an unmetered link nothing changes:
      // one tap on the home hero still gives a full result with no extra prompt.
      final MockQualityClient quality = await _pumpAutoStart(
        tester,
        _OnWifiPath(),
      );

      expect(
        quality.measureCalls,
        1,
        reason: 'auto-start must still auto-start on Wi-Fi',
      );
      expect(
        quality.lastIncludeThroughput,
        isTrue,
        reason: 'Wi-Fi is unmetered: the speed test runs, as it always has',
      );
      expect(find.textContaining("You're on cellular"), findsNothing);
    });
  });
}
