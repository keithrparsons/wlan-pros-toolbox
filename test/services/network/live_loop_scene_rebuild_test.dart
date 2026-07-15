// THE SCENE-REBUILD PATH. NO TEST HAS EVER DRIVEN IT.
//
// That is why six cold reviews, 4,238 tests and three rounds of mutation proofs
// sailed past this, and Keith's phone found it twice in 30 seconds.
//
// DEVICE EVIDENCE (build 202607141030 = c5ec11e, real iPhone, on Wi-Fi):
//   TEST 1 (Test My Connection): "I started live and the first couple seconds it
//   worked, then it stopped and returned to the screen asking me to start again."
//   TEST 2 (Wi-Fi Information): the Start pill "pretended to start, but returned
//   immediately" with "live readings could not start, iOS needs WLAN Pros Live
//   companion shortcut." Re-adding the Shortcut did not help.
//
// THE SYMPTOM CHANGED, AND THE CHANGE IS THE DIAGNOSIS. Before c5ec11e it died
// INSTANTLY. Now it RUNS, THEN DIES. The start works. Something is KILLING A
// HEALTHY, RUNNING LOOP.
//
// Starting the feed BACKGROUNDS THE APP INTO SHORTCUTS BY DESIGN. Returning can
// REBUILD THE SCENE — which constructs a FRESH sampler / FRESH controller over an
// App Group flag that is STILL TRUE, because the loop is genuinely running.
//
// This file drives exactly that, on BOTH live surfaces, because they do NOT share
// a code path (verified, against the brief's claim that they do):
//   * Test My Connection -> WifiSignalSampler -> WifiMonitorController
//   * Wi-Fi Information  -> WifiMonitorController DIRECTLY (no sampler)
//
// A fix that only touches the sampler cannot fix Wi-Fi Information. A fix that
// only touches the controller must not reopen the dead-"LIVE"-card hazard.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_monitor_controller.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';

/// THE APP GROUP, faked — the ONLY thing that survives a scene rebuild. The
/// monitoring flag and the payload stamp live here, exactly as they do in the real
/// App Group, so a fresh sampler/controller sees precisely what iOS would hand it.
class _AppGroup {
  /// The loop-gate flag the recursive "WLAN Pros Live" Shortcut consults on every
  /// cycle. TRUE = "keep going". Clearing it KILLS the loop.
  bool monitoringActive = false;
  bool everReceived = false;
  WiFiDetails? latest;

  /// The instant the native receiver STORED the most recent payload. This is the
  /// evidence a running loop leaves behind, and it is the ONLY thing that can tell
  /// a live loop from a stale flag.
  DateTime? payloadAt;

  final StreamController<WiFiDetails> updates =
      StreamController<WiFiDetails>.broadcast();
}

class _FakeBridge implements WiFiDetailsBridge {
  _FakeBridge(this.g);
  final _AppGroup g;

  @override
  Future<bool> hasEverReceivedPayload() async => g.everReceived;
  @override
  Future<WiFiDetails?> readLatest() async => g.latest;
  @override
  Future<DateTime?> payloadReceivedAt() async => g.payloadAt;
  @override
  Future<bool> isMonitoringActive() async => g.monitoringActive;
  @override
  Future<void> setMonitoringActive(bool active) async {
    g.monitoringActive = active;
  }

  @override
  Stream<WiFiDetails> get updates => g.updates.stream;

  @override
  Future<bool> runShortcut(String name) async => true;
  @override
  Future<bool> runShortcutOneShot(String name) async => true;
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

  // Scene-teardown restore seam. Default = NO pending run, so this fake keeps
  // asserting the app does NOT drag the user into a tool.
  @override
  Future<void> armLiveRun(String route) async {}
  @override
  Future<PendingLiveRun?> pendingLiveRun() async => null;
  @override
  Future<void> clearLiveRun() async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// On Wi-Fi, definitively. The connection probe must never be the thing that kills
/// these loops — we are isolating the rebuild path.
class _OnWifiPath implements WifiPathProbe {
  const _OnWifiPath();
  @override
  Future<WifiPathFacts?> read() async => const WifiPathFacts(
        usesWifi: true,
        wifiSatisfied: true,
        wifiInterfacePresent: true,
      );
}

WifiConnectionService _onWifi() => WifiConnectionService(
      platformOverride: TargetPlatform.iOS,
      pathProbe: const _OnWifiPath(),
    );

const WiFiDetails _sample = WiFiDetails(ssid: 'KeithNet', rssi: -50);

/// A loop that is GENUINELY RUNNING: the flag is up, a payload has landed, and the
/// stamp is RECENT. This is the state the App Group is in at the exact moment the
/// user gets back from the Shortcuts app.
_AppGroup _runningLoop() => _AppGroup()
  ..monitoringActive = true
  ..everReceived = true
  ..latest = _sample
  ..payloadAt = DateTime.now();

/// A loop that is DEAD: the flag was left up by a crashed session, but NOTHING has
/// delivered in a long time. This is the dead-"LIVE"-card hazard Keith already hit
/// once, and it MUST still be torn down.
_AppGroup _staleFlag() => _AppGroup()
  ..monitoringActive = true
  ..everReceived = true
  ..latest = _sample
  ..payloadAt = DateTime.now().subtract(const Duration(minutes: 5));

void main() {
  // =========================================================================
  // SURFACE 1 — TEST MY CONNECTION (WifiSignalSampler -> WifiMonitorController)
  // =========================================================================
  group('Test My Connection: a scene rebuild must not kill a running loop', () {
    test(
        'RED-FIRST: a FRESH sampler over a STILL-RUNNING loop must ADOPT it, not '
        'tear it down', () async {
      final _AppGroup g = _runningLoop();

      // The scene rebuilds: a brand-new sampler is constructed over the SAME App
      // Group. `_startedThisSession` is false — but that is a fact about THE
      // WIDGET, not about THE LOOP. The loop is running. Confusing the two IS the
      // bug.
      final WifiSignalSampler fresh = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: _FakeBridge(g),
        connectionService: _onWifi(),
      );
      addTearDown(fresh.dispose);

      await fresh.load();

      expect(g.monitoringActive, isTrue,
          reason: 'THE BUG: a fresh sampler saw `!_startedThisSession && '
              'c.isStreaming`, concluded "stale leftover", and CLEARED THE LOOP '
              'FLAG — killing the recursion the user just started. It survives '
              'exactly as long as it takes to walk back from the Shortcuts app: '
              '~5 seconds.');
      expect(fresh.isStreaming || fresh.notOnWifi == false, isTrue);
    });

    test(
        'COUNTERWEIGHT: a STALE flag with NO recent payload is STILL torn down '
        '(no dead "LIVE" card)', () async {
      final _AppGroup g = _staleFlag();

      final WifiSignalSampler fresh = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: _FakeBridge(g),
        connectionService: _onWifi(),
      );
      addTearDown(fresh.dispose);

      await fresh.load();

      expect(g.monitoringActive, isFalse,
          reason: 'A flag with no producer behind it is the dead-"LIVE"-card '
              'hazard Keith hit once. It MUST still be cleared. Adoption is '
              'earned by a RECENT PAYLOAD, never by the flag alone.');
      expect(fresh.isStreaming, isFalse);
    });
  });

  // =========================================================================
  // SURFACE 2 — WI-FI INFORMATION (WifiMonitorController DIRECTLY — NO SAMPLER)
  //
  // The brief asserted both screens "share the sampler". They do NOT:
  // wifi_info_screen.dart constructs WifiMonitorController directly (:305). So a
  // sampler-only fix leaves Wi-Fi Information broken. These cases pin the
  // controller's own behavior.
  // =========================================================================
  group('Wi-Fi Information: the controller alone, on a scene rebuild', () {
    test('a FRESH controller over a STILL-RUNNING loop keeps it alive', () async {
      final _AppGroup g = _runningLoop();
      final WifiMonitorController c = WifiMonitorController(
        bridge: _FakeBridge(g),
        connectionService: _onWifi(),
      );
      addTearDown(c.dispose);

      await c.load();

      expect(g.monitoringActive, isTrue,
          reason: 'the controller resumes a live loop from the persisted flag');
      expect(c.isStreaming, isTrue);
    });

    test(
        'a FRESH controller over a STALE flag TEARS IT DOWN — the protection '
        'Wi-Fi Information never had', () async {
      // THIS TEST WAS WRITTEN RED, TO EXPOSE THE REAL DEFECT, AND IT FOUND ONE.
      //
      // Before the fix, `load()` resumed streaming from `wasMonitoring` ALONE —
      // no liveness check of any kind. Both of this group's cases passed, which
      // proved two things at once:
      //   1. the controller was NOT the ~5-second killer (so the brief's
      //      scene-rebuild hypothesis could not explain Wi-Fi Information), and
      //   2. the ONLY dead-"LIVE"-card protection in the codebase lived in the
      //      SAMPLER — which Wi-Fi Information DOES NOT USE.
      //
      // So Wi-Fi Information could paint a LIVE badge over a flag left behind by a
      // crashed session with no producer at all, and nothing anywhere would stop
      // it. Test My Connection had the protection and was killed by it; Wi-Fi
      // Information lacked it entirely. One rule, in the wrong place, doing harm on
      // one screen and nothing on the other.
      //
      // The liveness decision now lives in the controller, so BOTH screens inherit
      // it, and this asserts the half Wi-Fi Information never had.
      final _AppGroup g = _staleFlag();
      final WifiMonitorController c = WifiMonitorController(
        bridge: _FakeBridge(g),
        connectionService: _onWifi(),
      );
      addTearDown(c.dispose);

      await c.load();

      expect(g.monitoringActive, isFalse,
          reason: 'a flag with no producer behind it must be cleared, not adopted');
      expect(c.isStreaming, isFalse,
          reason: 'NO DEAD "LIVE" CARD: the screen must rest on the actionable '
              'Start control, never a LIVE badge with nothing arriving');
      expect(c.phase, WifiMonitorPhase.idleWithData,
          reason: 'it has data (a stored reading), it just is not live');
    });

    test('an UNPROVABLE loop (no stamp at all) is torn down, not adopted',
        () async {
      // FAIL-SAFE DIRECTION. A null stamp — an App Group written by a build that
      // predates the stamp, or a platform that cannot answer — means "I cannot
      // prove this loop is alive". Adopting an unprovable loop is exactly what
      // paints a dead LIVE card, so an unprovable loop is torn down (GL-005: a
      // null is not a yes).
      final _AppGroup g = _AppGroup()
        ..monitoringActive = true
        ..everReceived = true
        ..latest = _sample
        ..payloadAt = null; // the platform cannot answer

      final WifiMonitorController c = WifiMonitorController(
        bridge: _FakeBridge(g),
        connectionService: _onWifi(),
      );
      addTearDown(c.dispose);

      await c.load();

      expect(g.monitoringActive, isFalse);
      expect(c.isStreaming, isFalse);
    });
  });
}
