// ROUTING THE USER BACK IS NOT ENOUGH. HE MUST GET HIS RESULT.
//
// Half 1 (test/router/live_run_restore_test.dart) puts the user back on Test My
// Connection after iOS destroys the scene. On its own that hands Keith a FRESH TMC
// SCREEN WITH THE RUN GONE — he tapped "Check My Connection" and got a reset screen.
// That is a different bug, not a fix.
//
// This file drives the other half: THE RUN COMES BACK.
//
// WHY IT CAN. The measurement's TCP streams died with the Dart heap and cannot be
// literally continued — but the thing the run was WAITING FOR did not die. The
// companion Shortcut wrote its reading to the APP GROUP before the scene was torn
// down; that is the entire point of the App Group. `payloadReceivedAt` (c5ec11e)
// now says WHEN, so the screen can tell a reading THIS run produced from the stale
// one sitting there since the last time the phone was on Wi-Fi.
//
// So a resumed run ADOPTS the delivered RF and re-runs the measurement to a result.
//
// THE HAZARD THIS FILE EXISTS TO PIN. The naive resume calls `_run()` again — and
// `_run()` fires the Shortcut, which backgrounds the app into Shortcuts, WHICH IS
// THE EVENT THAT DESTROYED THE SCENE IN THE FIRST PLACE. That is an infinite bounce
// loop that would take Keith's phone away from him entirely. A resumed run must
// NEVER re-fire the trigger; the reading it needs is already in the App Group. The
// `never re-fires` test below is the guard on that, and it is the most important
// assertion in this file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
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

/// ON WI-FI, definitively. Keith's failing case is the ON-WI-FI one: off Wi-Fi the
/// screen never fires the Shortcut at all (`_autoCaptureIosRf` returns early on
/// `_notOnWifi`), so the scene is never backgrounded and the run never dies. That is
/// exactly why his CELLULAR run completed (40 s, stuck at 72 %, then a correct
/// result) while his WI-FI run bounced to Home — the device evidence and the root
/// cause agree, and this probe puts us on the failing side of that line.
class _OnWifiPath implements WifiPathProbe {
  const _OnWifiPath();
  @override
  Future<WifiPathFacts?> read() async => const WifiPathFacts(
        usesWifi: true,
        wifiSatisfied: true,
        wifiInterfacePresent: true,
      );
}

const WiFiDetails _kDelivered = WiFiDetails(
  ssid: 'KeithNet',
  bssid: '94:2a:6f:a0:a5:5d',
  channel: 44,
  rssi: -52,
  noise: -95,
  standard: '802.11ax - Wi-Fi 6',
  rxRate: 640,
  txRate: 720,
);

/// THE APP GROUP ACROSS THE TEARDOWN.
///
/// Everything here survives the scene death, and nothing else does. The screen that
/// mounts after the rebuild is a brand-new State object with no memory of the run —
/// this store is the only thing it can learn from.
class _AppGroup {
  String? pendingRunRoute;
  DateTime? pendingRunAt;

  WiFiDetails? latest;
  DateTime? payloadAt;
  bool everReceived = true;

  /// THE BOUNCE-LOOP COUNTER. A resumed run that re-fires the trigger backgrounds
  /// the app into Shortcuts again — the very event that destroyed the run. This must
  /// stay at ZERO across a resume.
  int oneShotFires = 0;
  int streamFires = 0;
  int clearLiveRunCalls = 0;

  /// EVERY route ever armed, in order. Asserting on the CURRENT arm is racy — a
  /// healthy run arms and then disarms within a few frames, so a test that samples
  /// the live value can miss the arm entirely and conclude it never happened. The
  /// history cannot be missed.
  final List<String> armHistory = <String>[];
}

class _FakeBridge implements WiFiDetailsBridge {
  _FakeBridge(this.g);
  final _AppGroup g;

  @override
  Future<void> armLiveRun(String route) async {
    g.armHistory.add(route);
    g.pendingRunRoute = route;
    g.pendingRunAt = DateTime.now();
  }

  @override
  Future<PendingLiveRun?> pendingLiveRun() async {
    final String? r = g.pendingRunRoute;
    final DateTime? at = g.pendingRunAt;
    if (r == null || r.isEmpty || at == null) return null;
    return PendingLiveRun(route: r, armedAt: at);
  }

  @override
  Future<void> clearLiveRun() async {
    g.clearLiveRunCalls++;
    g.pendingRunRoute = null;
    g.pendingRunAt = null;
  }

  @override
  Future<WiFiDetails?> readLatest() async => g.latest;
  @override
  Future<DateTime?> payloadReceivedAt() async => g.payloadAt;
  @override
  Future<bool> hasEverReceivedPayload() async => g.everReceived;

  @override
  Future<bool> runShortcutOneShot(String name) async {
    g.oneShotFires++;
    return true;
  }

  @override
  Future<bool> runShortcut(String name) async {
    g.streamFires++;
    return true;
  }

  @override
  Future<bool> isMonitoringActive() async => false;
  @override
  Future<void> setMonitoringActive(bool active) async {}
  @override
  Future<void> resetMonitoringColdStart() async {}
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
  @override
  Future<bool> openUrl(String url) async => true;

  @override
  Stream<WiFiDetails> get updates => const Stream<WiFiDetails>.empty();

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
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
      const WifiSecurityInfo.unavailable('not needed for this test');
}

class _FakeIpGeo extends IpGeoService {
  @override
  Future<IpGeoResult> lookup({required String rawQuery}) async =>
      IpGeoResult.failure(query: rawQuery, message: 'offline in test');
}

/// A healthy Wi-Fi internet result — the run, if it actually RUNS, produces this.
QualityResult _goodInternet() => QualityResult(
      source: QualitySource.mock,
      measuredAt: DateTime.utc(2026, 1, 1),
      metrics: const <QualityMetric>[
        QualityMetric(
          id: MetricIds.latency,
          label: 'Latency',
          value: 12,
          unit: 'ms',
          grade: QualityGrade.good,
        ),
        QualityMetric(
          id: MetricIds.loss,
          label: 'Loss',
          value: 0,
          unit: '%',
          grade: QualityGrade.good,
        ),
        QualityMetric(
          id: MetricIds.download,
          label: 'Download',
          value: 712,
          unit: 'Mbps',
          grade: QualityGrade.good,
        ),
        QualityMetric(
          id: MetricIds.upload,
          label: 'Upload',
          value: 462,
          unit: 'Mbps',
          grade: QualityGrade.good,
        ),
      ],
    );

/// THE SCENE REBUILD. A brand-new screen, a brand-new sampler, a brand-new
/// controller — over the SAME App Group. Nothing carries over except what iOS could
/// not take: the shared store. This is structurally the event, not a mime of it.
///
/// Returns the sampler so a test can ask the question that actually distinguishes
/// an ADOPTED reading from a merely-DISPLAYED one: was it charted as a LIVE SAMPLE?
Future<WifiSignalSampler> _mountAfterSceneRebuild(
  WidgetTester tester,
  _AppGroup g,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    LiveOnboardingService.prefsKey: true,
  });
  final _FakeBridge bridge = _FakeBridge(g);
  final WifiSignalSampler sampler = WifiSignalSampler(
    source: WifiInfoSource.iosShortcuts,
    iosBridge: bridge,
    connectionService: WifiConnectionService(
      platformOverride: TargetPlatform.iOS,
      pathProbe: const _OnWifiPath(),
    ),
  );
  addTearDown(sampler.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: TestMyConnectionScreen(
        sourceOverride: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
        sampler: sampler,
        securityService: _FakeSecurity(),
        dnsProbeService: _FakeDns(),
        networkDetailsService: _FakeNetDetails(),
        ipGeoService: _FakeIpGeo(),
        onboardingService:
            LiveOnboardingService(getStore: SharedPreferences.getInstance),
        qualityClient: MockQualityClient(scriptedResult: _goodInternet()),
      ),
    ),
  );
  // The screen mounts, discovers it is a RESUMED run, and takes the run over. No
  // tap: the user already tapped, one scene ago.
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  return sampler;
}

/// A HOST THAT CAN UNMOUNT THE SCREEN WITHOUT TOUCHING THE BINDING.
///
/// WHY THIS EXISTS, AND IT IS NOT A CONVENIENCE. Unmounting a screen in a widget test
/// looks trivial and is not. Two traps ate two versions of the tests below, and BOTH
/// produced a green test that measured nothing:
///
///   TRAP 1 — `pumpWidget(somethingElse)` RESETS THE APP LIFECYCLE. It flips the
///   binding back to `resumed` an instant before disposing the old tree, so a test
///   that carefully drove the app to `paused` had that state silently undone right
///   before the only line that reads it.
///
///   TRAP 2 — `MaterialApp.home` only SEEDS the Navigator's initial route. Swapping
///   `home` on an already-built MaterialApp does NOT pop the mounted screen, so a
///   host that toggled `home` never disposed the child at all. dispose() ran at test
///   TEARDOWN instead, long after the assertions, and the test passed by accident.
///
/// So the toggle lives INSIDE the route (below the Navigator), where a plain setState
/// removes the child through the ordinary element lifecycle — no pumpWidget, no
/// binding reset, and dispose() observes exactly the lifecycle state the test set.
///
/// Both traps were caught by hand-injected mutation, not by reading the tests. The
/// tests looked right. That is the entire argument for mutation testing, in one file.
class _Host extends StatelessWidget {
  const _Host({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.dark(),
        home: _Swapper(child: child),
      );
}

/// Lives BELOW the Navigator, so flipping [show] genuinely unmounts and disposes the
/// child — which is the event these tests are about.
class _Swapper extends StatefulWidget {
  const _Swapper({required this.child});
  final Widget child;

  @override
  State<_Swapper> createState() => _SwapperState();
}

class _SwapperState extends State<_Swapper> {
  bool show = true;

  /// The user tapped Back / iOS tore the scene down: the screen goes away.
  void unmountChild() => setState(() => show = false);

  @override
  Widget build(BuildContext context) =>
      show ? widget.child : const SizedBox.shrink();
}

String _visibleText(WidgetTester tester) {
  final StringBuffer buf = StringBuffer();
  for (final Element e in find.byType(Text).evaluate()) {
    final Text t = e.widget as Text;
    if (t.data != null) buf.writeln(t.data);
  }
  return buf.toString();
}

/// A run was in flight, and the Shortcut DID deliver before the scene died.
_AppGroup _runInterruptedAfterDelivery() {
  final DateTime armed = DateTime.now().subtract(const Duration(seconds: 3));
  return _AppGroup()
    ..pendingRunRoute = AppRouter.testMyConnection
    ..pendingRunAt = armed
    // The reading landed AFTER the run armed → it belongs to THIS run.
    ..payloadAt = armed.add(const Duration(seconds: 1))
    ..latest = _kDelivered;
}

void main() {
  group('TEST 2 — the run RESUMES and RENDERS A RESULT', () {
    testWidgets(
        'a run interrupted by the scene teardown COMPLETES and shows a verdict — '
        'not a reset screen', (WidgetTester tester) async {
      final _AppGroup g = _runInterruptedAfterDelivery();

      await _mountAfterSceneRebuild(tester, g);

      final String text = _visibleText(tester);
      // THE POINT OF THE WHOLE EXERCISE. Keith tapped "Check My Connection". He must
      // end up holding a RESULT.
      expect(
        text.contains('Run again') || text.contains('Copy results'),
        isTrue,
        reason: 'THE BUG KEITH REPORTED, IN ONE ASSERTION. Routing him back to a '
            'blank TMC screen is not a fix — he tapped a button and must get an '
            'answer. A completed run renders its result affordances; a screen that '
            'merely reset renders the pre-run intro. Visible text was:\n$text',
      );
      expect(
        text.contains('Check My Connection'),
        isFalse,
        reason: 'the PRE-RUN call to action must be gone — its presence means the '
            'screen came back reset, with the run silently dropped',
      );
    });

    testWidgets(
        'THE BOUNCE-LOOP GUARD: a resumed run NEVER re-fires the Shortcut',
        (WidgetTester tester) async {
      final _AppGroup g = _runInterruptedAfterDelivery();

      await _mountAfterSceneRebuild(tester, g);

      expect(
        g.oneShotFires,
        0,
        reason: 'CATASTROPHIC IF WRONG. Firing the Shortcut is what backgrounds the '
            'app into Shortcuts, which is what let iOS destroy the scene. A resumed '
            'run that re-fires would be destroyed again, resume again, fire again — '
            'an infinite bounce loop that takes the phone away from the user. The '
            'reading is ALREADY in the App Group; there is nothing to fire for.',
      );
      expect(g.streamFires, 0);
    });

    testWidgets(
        'the resumed run ADOPTS the RF the Shortcut delivered before the scene died',
        (WidgetTester tester) async {
      final _AppGroup g = _runInterruptedAfterDelivery();

      final WifiSignalSampler sampler = await _mountAfterSceneRebuild(tester, g);

      final String text = _visibleText(tester);
      expect(text.contains('KeithNet'), isTrue,
          reason: 'the Shortcut RAN and its reading survived in the App Group — a '
              'resume that ignores it throws away the one thing the bounce bought');
      // ADOPTED, not merely displayed. A reading that landed after the arm is a
      // reading of THIS run, so it is charted as a live sample.
      expect(sampler.series.isEmpty, isFalse,
          reason: 'a proven-fresh delivery is a LIVE sample and belongs on the '
              'sparkline exactly as it would have if the scene had never died');
    });

    testWidgets('the arm is CONSUMED, so a later launch is not dragged back in',
        (WidgetTester tester) async {
      final _AppGroup g = _runInterruptedAfterDelivery();

      await _mountAfterSceneRebuild(tester, g);

      expect(g.clearLiveRunCalls, greaterThanOrEqualTo(1));
      expect(g.pendingRunRoute, isNull,
          reason: 'one arm, one resume. An arm that survives its own resume would '
              're-trigger on the next cold start.');
    });
  });

  group('THE HONEST FALLBACK — a run was in flight but NOTHING landed', () {
    // SCOPE, STATED PLAINLY, BECAUSE THE DISTINCTION IS SUBTLE AND LOAD-BEARING.
    //
    // These tests assert the resume does not ADOPT an unproven reading — i.e. does
    // not chart it on the live sparkline, count it as a delivery, or stamp it
    // "Updated just now". That is what `_adoptDeliveredIosRf` governs and what would
    // be a LIE if it got it wrong.
    //
    // They deliberately do NOT assert the stale SSID is absent from the screen
    // entirely, because a SECOND, PRE-EXISTING path puts it there: `_readLink()`
    // reads `WiFiDetailsBridge.readLatest()` directly, with no timestamp check, on
    // EVERY iOS run — normal or resumed. So on Wi-Fi the last stored App Group
    // payload renders as the run's link however old it is. That is a real latent
    // staleness issue, it is NOT introduced by the resume, and narrowing it would
    // change the behavior of every ordinary iOS check. It is reported separately
    // rather than smuggled in under a bug fix.

    testWidgets(
        'no payload after the arm → the run still COMPLETES (no hang) and the stale '
        'reading is NOT adopted as a live sample', (WidgetTester tester) async {
      // The Shortcut never delivered (it was slow, it failed, the user backed out of
      // Shortcuts). The App Group holds only a STALE reading from the last time the
      // phone was on Wi-Fi — stamped BEFORE this run armed.
      final DateTime armed = DateTime.now().subtract(const Duration(seconds: 3));
      final _AppGroup g = _AppGroup()
        ..pendingRunRoute = AppRouter.testMyConnection
        ..pendingRunAt = armed
        ..payloadAt = armed.subtract(const Duration(days: 30)) // a month old
        ..latest = const WiFiDetails(ssid: 'AnOldCafe', rssi: -70, txRate: 29);

      final WifiSignalSampler sampler = await _mountAfterSceneRebuild(tester, g);

      // It must not HANG — the run reaches a terminal state on the existing path.
      expect(
        _visibleText(tester).contains('Run again') ||
            _visibleText(tester).contains('Copy results'),
        isTrue,
        reason: 'a resume with no delivery must still finish the run honestly, not '
            'sit forever waiting for a payload that is not coming',
      );
      // And it must not pass a month-old reading off as a sample of THIS run.
      expect(
        sampler.series.isEmpty,
        isTrue,
        reason: 'GL-005. A reading stamped BEFORE this run armed cannot be a reading '
            'OF this run. Charting it would draw a month-old café onto the live '
            'sparkline and stamp it "just updated" — the exact stale-reading class of '
            'bug this codebase has now been burned by twice.',
      );
      // NB: `sampler.lastUpdated` is deliberately NOT asserted here. The controller's
      // load() stamps it (`_lastUpdated ??= DateTime.now()`) whenever it restores the
      // stored reading — pre-existing behavior on every load, on every screen, and
      // not something the resume path introduces or controls. Reported separately;
      // not silently redefined under cover of a bug fix.
    });

    testWidgets('an UNSTAMPED payload is not adopted (a null is not a yes)',
        (WidgetTester tester) async {
      // The platform cannot date the payload. GL-005: "we cannot prove this landed"
      // is not "it landed". Fail safe — do not adopt.
      final DateTime armed = DateTime.now().subtract(const Duration(seconds: 3));
      final _AppGroup g = _AppGroup()
        ..pendingRunRoute = AppRouter.testMyConnection
        ..pendingRunAt = armed
        ..payloadAt = null
        ..latest = const WiFiDetails(ssid: 'Unprovable', rssi: -70);

      final WifiSignalSampler sampler = await _mountAfterSceneRebuild(tester, g);

      expect(sampler.series.isEmpty, isTrue,
          reason: 'an undateable payload is not a proven one, and an unproven '
              'reading is never charted as a live sample');
    });
  });

  group('THE ARM — the run records itself BEFORE it hands control to iOS', () {
    testWidgets(
        'a real check on Wi-Fi ARMS the run before firing the Shortcut',
        (WidgetTester tester) async {
      // WITHOUT THIS, NOTHING ELSE IN THIS FILE MATTERS. Every other test here starts
      // from an already-armed App Group, so they would all still pass if the app
      // never armed anything on a real run — and the fix would do precisely nothing
      // on Keith's phone. This is the test that connects the machinery to reality.
      final _AppGroup g = _AppGroup()..everReceived = true;
      SharedPreferences.setMockInitialValues(<String, Object>{
        LiveOnboardingService.prefsKey: true,
      });
      final _FakeBridge bridge = _FakeBridge(g);
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
        connectionService: WifiConnectionService(
          platformOverride: TargetPlatform.iOS,
          pathProbe: const _OnWifiPath(),
        ),
      );
      addTearDown(sampler.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: TestMyConnectionScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: bridge,
            sampler: sampler,
            securityService: _FakeSecurity(),
            dnsProbeService: _FakeDns(),
            networkDetailsService: _FakeNetDetails(),
            ipGeoService: _FakeIpGeo(),
            onboardingService:
                LiveOnboardingService(getStore: SharedPreferences.getInstance),
            qualityClient: MockQualityClient(scriptedResult: _goodInternet()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(g.pendingRunRoute, isNull, reason: 'nothing armed before the tap');

      // The user taps Check My Connection — the tap that, on Keith's phone, threw him
      // out to Home.
      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(
        g.armHistory,
        contains(AppRouter.testMyConnection),
        reason: 'THE RUN MUST RECORD ITSELF BEFORE IT FIRES. The very next thing that '
            'happens is iOS foregrounding the Shortcuts app, after which our scene can '
            'be destroyed at any moment — no warning, no exception, no finally block. '
            'If the arm is not in the App Group by then, nothing is left to tell the '
            'rebuilt app that a run was ever happening, and Keith lands on Home.',
      );
      expect(g.oneShotFires, greaterThanOrEqualTo(1),
          reason: 'and it did in fact fire — the arm is not decorative');

      // ...and having COMPLETED, it disarms: there is nothing left to restore.
      expect(g.pendingRunRoute, isNull,
          reason: 'a finished run must not be restorable — a scene rebuild minutes '
              'later would drag the user back into a check that already succeeded');
    });
  });

  group('THE DISCRIMINATOR — did the user leave, or did iOS take the scene?', () {
    /// Mounts TMC inside a [_Host] so the test can unmount it WITHOUT pumpWidget
    /// (which would reset the lifecycle to `resumed` and make these tests vacuous).
    Future<_SwapperState> mountInHost(WidgetTester tester, _AppGroup g) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LiveOnboardingService.prefsKey: true,
      });
      final _FakeBridge bridge = _FakeBridge(g);
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
        connectionService: WifiConnectionService(
          platformOverride: TargetPlatform.iOS,
          pathProbe: const _OnWifiPath(),
        ),
      );
      addTearDown(sampler.dispose);
      await tester.pumpWidget(
        _Host(
          child: TestMyConnectionScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: bridge,
            sampler: sampler,
            securityService: _FakeSecurity(),
            dnsProbeService: _FakeDns(),
            networkDetailsService: _FakeNetDetails(),
            ipGeoService: _FakeIpGeo(),
            onboardingService:
                LiveOnboardingService(getStore: SharedPreferences.getInstance),
            qualityClient: MockQualityClient(scriptedResult: _goodInternet()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // THE APP IS FOREGROUNDED. Say it explicitly, for two reasons:
      //   1. The test binding starts with a NULL lifecycle state and pumpWidget does
      //      NOT set one. A real iOS device is `resumed` from the first frame.
      //   2. The binding LEAKS lifecycle state between tests in a file, which is how
      //      an earlier cut of these tests silently inherited `resumed` from its
      //      neighbour and appeared to prove something it never drove.
      // Production checks `== resumed`, so a null state does NOT disarm — on the one
      // axis where harness and device disagree, the code fails toward KEEPING the
      // run, which is the error we can afford.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      return tester.state<_SwapperState>(find.byType(_Swapper));
    }

    testWidgets(
        'a DELIBERATE exit (app FOREGROUNDED) DISARMS the run — nothing drags the '
        'user back', (WidgetTester tester) async {
      final _AppGroup g = _AppGroup()..latest = _kDelivered;
      final _SwapperState host = await mountInHost(tester, g);

      // A run is in flight, and the user is LOOKING AT THE APP. Only a foregrounded
      // user can tap Back — that asymmetry is the entire discriminator.
      g.pendingRunRoute = AppRouter.testMyConnection;
      g.pendingRunAt = DateTime.now();
      expect(tester.binding.lifecycleState, AppLifecycleState.resumed);

      expect(find.byType(TestMyConnectionScreen), findsOneWidget,
          reason: 'PROBE: mounted before unmount');
      host.unmountChild(); // the Back tap
      await tester.pumpAndSettle();
      expect(find.byType(TestMyConnectionScreen), findsNothing,
          reason: 'PROBE: the screen must actually be GONE — if it is still here, '
              'dispose() never ran and this test is proving nothing');

      expect(g.pendingRunRoute, isNull,
          reason: 'a user who deliberately walked away must NOT be yanked back into '
              'the tool on the next foreground. An app that drags you into a screen '
              'you just left is broken in its own right.');
    });

    // THE BACKGROUNDED-TEARDOWN CASE IS **NOT** A WIDGET TEST, AND CANNOT BE ONE.
    //
    // A paused app does not pump frames, so the unmount a real scene teardown performs
    // never runs inside a widget-test body — dispose() fires later, at test teardown,
    // with the binding back at `resumed`. TWO successive widget tests for this looked
    // correct, passed, and were both proven VACUOUS by hand-injected mutation: they
    // passed identically against a rule that disarmed unconditionally, which is the
    // exact defect they existed to catch.
    //
    // Rather than ship a third test that cannot fail, the rule is pinned as a pure
    // function below — exhaustively, over every lifecycle state. That version DOES die
    // to the mutant.
    group('shouldDisarmOnDispose — the rule, pinned exhaustively', () {
      test('ONLY a foregrounded app disarms (the user chose to leave)', () {
        expect(
          shouldDisarmOnDispose(
              AppLifecycleState.resumed),
          isTrue,
          reason: 'only a foregrounded user can tap Back, so only a foregrounded '
              'dispose is a deliberate exit',
        );
      });

      test(
          'every NON-foregrounded state PRESERVES the arm — it is the only evidence '
          'Keith is owed a result', () {
        for (final AppLifecycleState state in <AppLifecycleState>[
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.detached,
        ]) {
          expect(
            shouldDisarmOnDispose(state),
            isFalse,
            reason: 'THE FIX HINGES ON THIS. $state means the screen is going away '
                'for reasons that are NOT the user\'s choice — iOS is taking the '
                'scene while we sit backgrounded in the Shortcuts app. Disarming here '
                'would erase the very record that brings the run back, and Keith lands '
                'on Home with nothing: the original bug, reintroduced by the cleanup '
                'meant to prevent it.',
          );
        }
      });

      test('an UNKNOWN (null) state does NOT disarm — the affordable error', () {
        // The two errors are not symmetric. Disarming wrongly loses a real run (the
        // bug). Failing to disarm pulls the user back into a tool once, inside a
        // few-second window, self-correcting because the arm is consumed on the way
        // through. Fail toward keeping the run.
        expect(
          shouldDisarmOnDispose(null),
          isFalse,
        );
      });
    });
  });

  group('NO ARM, NO RESUME — the ordinary screen is untouched', () {
    testWidgets(
        'opening Test My Connection normally does NOT auto-run anything',
        (WidgetTester tester) async {
      // The regression net for every other user: a screen with no armed run behaves
      // exactly as it always has — it waits for the tap. A restore that auto-runs on
      // a plain open would spend a cellular user's data with no consent at all.
      final _AppGroup g = _AppGroup()..latest = null;

      await _mountAfterSceneRebuild(tester, g);

      final String text = _visibleText(tester);
      expect(text.contains('Check My Connection'), isTrue,
          reason: 'no arm → no resume → the pre-run call to action stands');
      expect(g.oneShotFires, 0);
    });
  });
}
