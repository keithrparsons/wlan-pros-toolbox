// Unit tests for the Wi-Fi monitoring state machine (TICKET-03 A2/A4).
//
// Covers install-state branching (no data -> needsInstall; data -> idleWithData;
// relaunch-while-monitoring -> streaming), the start -> receive N -> stop loop,
// the monitoring-flag writes that gate the looping Shortcut, and the preserved
// one-shot path. No native channel is touched — a fake bridge stands in.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_monitor_controller.dart';

/// A [NetworkInfo] fake feeding [WifiConnectionService]: a canned Wi-Fi IP drives
/// the on/not-on-Wi-Fi verdict deterministically in the controller tests.
class _FakeNetworkInfo implements NetworkInfo {
  _FakeNetworkInfo({this.wifiIp});

  String? wifiIp;

  @override
  Future<String?> getWifiIP() async => wifiIp;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Builds a [WifiConnectionService] pinned to iOS with a canned Wi-Fi IP — a
/// non-null IP => onWifi, a null IP => notOnWifi (the controller's not-on-Wi-Fi
/// branch under test).
WifiConnectionService _conn({String? wifiIp}) {
  return WifiConnectionService(
    networkInfo: _FakeNetworkInfo(wifiIp: wifiIp),
    platformOverride: TargetPlatform.iOS,
  );
}

/// In-memory fake of [WiFiDetailsBridge] for state-machine tests.
class _FakeBridge extends WiFiDetailsBridge {
  _FakeBridge();

  final StreamController<WiFiDetails> _controller =
      StreamController<WiFiDetails>.broadcast();

  bool everReceived = false;
  bool monitoringFlag = false;
  WiFiDetails? latest;
  bool runShortcutResult = true;

  /// Mirrors the native App Group missing-Shortcut marker (set by
  /// markShortcutMissing on an x-error, consumed-once by the controller load).
  bool shortcutMissingFlag = false;
  int consumeShortcutMissingCalls = 0;

  /// Mirrors the native App Group post-install priming flag (set by
  /// markSetupInitiated, cleared when a payload arrives).
  bool setupInitiatedFlag = false;
  int markSetupInitiatedCalls = 0;

  int setMonitoringActiveCalls = 0;
  bool? lastMonitoringValue;
  int runShortcutCalls = 0;
  String? lastRunShortcutName;

  @override
  Future<bool> hasEverReceivedPayload() async => everReceived;

  @override
  Future<bool> consumeShortcutMissing() async {
    consumeShortcutMissingCalls++;
    final bool v = shortcutMissingFlag;
    shortcutMissingFlag = false; // native consume-once semantics
    return v;
  }

  @override
  Future<void> markSetupInitiated() async {
    markSetupInitiatedCalls++;
    setupInitiatedFlag = true;
  }

  @override
  Future<bool> hasInitiatedSetup() async => setupInitiatedFlag;

  @override
  Future<bool> isShortcutsAppInstalled() async => true;

  @override
  Future<WiFiDetails?> readLatest() async => latest;

  @override
  Future<bool> isMonitoringActive() async => monitoringFlag;

  @override
  Future<void> setMonitoringActive(bool active) async {
    setMonitoringActiveCalls++;
    lastMonitoringValue = active;
    monitoringFlag = active;
  }

  @override
  Future<bool> runShortcut(String name) async {
    runShortcutCalls++;
    lastRunShortcutName = name;
    return runShortcutResult;
  }

  // ONE-SHOT (x-callback) trigger: getReadingOnce now fires via this form so the
  // single run auto-returns to the app. Routed through the same counter/result
  // as the plain trigger so the existing one-shot tests (missing-verdict settle,
  // payload-lands-not-missing) behave identically — only the URL form changed.
  @override
  Future<bool> runShortcutOneShot(String name) async {
    runShortcutCalls++;
    lastRunShortcutName = name;
    return runShortcutResult;
  }

  @override
  Stream<WiFiDetails> get updates => _controller.stream;

  void push(WiFiDetails d) => _controller.add(d);

  Future<void> close() => _controller.close();
}

WiFiDetails _details({String ssid = 'Keith', int rssi = -45, int channel = 197}) {
  return WiFiDetails(
    ssid: ssid,
    bssid: '94:2a:6f:a0:a5:5d',
    rssi: rssi,
    noise: -95,
    channel: channel,
    standard: '802.11be - Wi-Fi 7',
    rxRate: 864,
    txRate: 1297,
  );
}

void main() {
  group('load — install-state branching', () {
    test('no payload ever -> needsInstall', () async {
      final bridge = _FakeBridge()..everReceived = false;
      final c = WifiMonitorController(bridge: bridge);

      await c.load();

      expect(c.phase, WifiMonitorPhase.needsInstall);
      expect(c.hasEverReceived, isFalse);
      expect(c.details, isNull);
      c.dispose();
      await bridge.close();
    });

    test('payload received before, not monitoring -> idleWithData', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details()
        ..monitoringFlag = false;
      final c = WifiMonitorController(bridge: bridge);

      await c.load();

      expect(c.phase, WifiMonitorPhase.idleWithData);
      expect(c.details, isNotNull);
      expect(c.details!.ssid, 'Keith');
      expect(c.lastUpdated, isNotNull);
      c.dispose();
      await bridge.close();
    });

    test('a stored payload alone implies install-state even without the flag',
        () async {
      // hasEverReceived is false but a real payload sits in the App Group.
      final bridge = _FakeBridge()
        ..everReceived = false
        ..latest = _details();
      final c = WifiMonitorController(bridge: bridge);

      await c.load();

      expect(c.hasEverReceived, isTrue);
      expect(c.phase, WifiMonitorPhase.idleWithData);
      c.dispose();
      await bridge.close();
    });

    test('relaunch with monitoring flag set -> resumes streaming', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details()
        ..monitoringFlag = true;
      final c = WifiMonitorController(bridge: bridge);

      await c.load();

      expect(c.phase, WifiMonitorPhase.streaming);
      expect(c.isStreaming, isTrue);
      c.dispose();
      await bridge.close();
    });
  });

  group('streaming state machine (start -> receive N -> stop)', () {
    test('start sets the monitoring flag and enters streaming', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details();
      final c = WifiMonitorController(bridge: bridge);
      await c.load();

      await c.startMonitoring();

      expect(c.isStreaming, isTrue);
      expect(bridge.lastMonitoringValue, isTrue);
      c.dispose();
      await bridge.close();
    });

    test('start fires the PLAIN recursive trigger once with the Live name',
        () async {
      // Start raises the flag AND fires the PLAIN run-shortcut trigger once to
      // kick off the recursion. The app never loops itself.
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details();
      final c = WifiMonitorController(bridge: bridge);
      await c.load();

      final bool opened = await c.startMonitoring(
        triggerShortcutName: 'WLAN Pros Live',
      );

      expect(opened, isTrue);
      expect(c.isStreaming, isTrue);
      expect(bridge.lastMonitoringValue, isTrue);
      expect(bridge.runShortcutCalls, 1);
      expect(bridge.lastRunShortcutName, 'WLAN Pros Live');
      c.dispose();
      await bridge.close();
    });

    test('start without a trigger name skips the trigger (resume case)',
        () async {
      final bridge = _FakeBridge()..everReceived = true;
      final c = WifiMonitorController(bridge: bridge);
      await c.load();

      final bool ok = await c.startMonitoring();

      expect(ok, isTrue);
      expect(c.isStreaming, isTrue);
      expect(bridge.runShortcutCalls, 0);
      c.dispose();
      await bridge.close();
    });

    test('receives N pushed payloads; updates data + timestamp', () async {
      final bridge = _FakeBridge()..everReceived = true;
      final c = WifiMonitorController(bridge: bridge);
      await c.load();
      await c.startMonitoring();

      var notifications = 0;
      c.addListener(() => notifications++);

      bridge.push(_details(ssid: 'Net-1', rssi: -40));
      await Future<void>.delayed(Duration.zero);
      bridge.push(_details(ssid: 'Net-2', rssi: -60));
      await Future<void>.delayed(Duration.zero);
      bridge.push(_details(ssid: 'Net-3', rssi: -55));
      await Future<void>.delayed(Duration.zero);

      expect(c.details!.ssid, 'Net-3');
      expect(c.details!.rssi, -55);
      expect(c.hasEverReceived, isTrue);
      expect(c.lastUpdated, isNotNull);
      expect(notifications, greaterThanOrEqualTo(3));
      c.dispose();
      await bridge.close();
    });

    test('stop clears the flag, leaves streaming, retains the last payload',
        () async {
      final bridge = _FakeBridge()..everReceived = true;
      final c = WifiMonitorController(bridge: bridge);
      await c.load();
      await c.startMonitoring();
      bridge.push(_details(ssid: 'Last'));
      await Future<void>.delayed(Duration.zero);

      await c.stopMonitoring();

      expect(c.isStreaming, isFalse);
      expect(c.phase, WifiMonitorPhase.idleWithData);
      expect(bridge.lastMonitoringValue, isFalse);
      expect(c.details!.ssid, 'Last');
      c.dispose();
      await bridge.close();
    });

    test('payloads pushed after stop are ignored', () async {
      final bridge = _FakeBridge()..everReceived = true;
      final c = WifiMonitorController(bridge: bridge);
      await c.load();
      await c.startMonitoring();
      bridge.push(_details(ssid: 'Before'));
      await Future<void>.delayed(Duration.zero);
      await c.stopMonitoring();

      bridge.push(_details(ssid: 'After'));
      await Future<void>.delayed(Duration.zero);

      expect(c.details!.ssid, 'Before');
      c.dispose();
      await bridge.close();
    });

    test('an all-null payload on the stream is ignored', () async {
      final bridge = _FakeBridge()..everReceived = true;
      final c = WifiMonitorController(bridge: bridge);
      await c.load();
      await c.startMonitoring();
      bridge.push(_details(ssid: 'Real'));
      await Future<void>.delayed(Duration.zero);

      bridge.push(const WiFiDetails()); // hasAnyData == false
      await Future<void>.delayed(Duration.zero);

      expect(c.details!.ssid, 'Real');
      c.dispose();
      await bridge.close();
    });

    test('one-shot path: load with data, no streaming', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details(ssid: 'OneShot');
      final c = WifiMonitorController(bridge: bridge);

      await c.load();

      expect(c.phase, WifiMonitorPhase.idleWithData);
      expect(c.isStreaming, isFalse);
      expect(c.details!.ssid, 'OneShot');
      c.dispose();
      await bridge.close();
    });
  });

  // Post-install PRIMING window (2026-06-26, Keith device round 2). iOS cannot
  // report whether a Shortcut is installed; the only proof is a delivered payload.
  // Right after install, no payload has arrived, so the controller reads the
  // App Group priming flag to surface the "tap Get reading to finish" step instead
  // of the cold "Set up live Wi-Fi" prompt.
  group('post-install priming window', () {
    test('setup started, no payload yet -> setupInitiated true, needsInstall',
        () async {
      final bridge = _FakeBridge()
        ..everReceived = false
        ..setupInitiatedFlag = true;
      final c = WifiMonitorController(bridge: bridge);

      await c.load();

      expect(c.setupInitiated, isTrue,
          reason: 'drives the priming step + Get-reading routing');
      expect(c.hasEverReceived, isFalse);
      expect(c.phase, WifiMonitorPhase.needsInstall);
      c.dispose();
      await bridge.close();
    });

    test('a delivered payload ends priming (setupInitiated false once received)',
        () async {
      // hasEverReceived wins: even if the flag is still set, priming is over.
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details()
        ..setupInitiatedFlag = true;
      final c = WifiMonitorController(bridge: bridge);

      await c.load();

      expect(c.setupInitiated, isFalse,
          reason: 'a real payload completes priming');
      expect(c.phase, WifiMonitorPhase.idleWithData);
      c.dispose();
      await bridge.close();
    });

    test('no setup started -> setupInitiated false (cold setup prompt)', () async {
      final bridge = _FakeBridge()..everReceived = false;
      final c = WifiMonitorController(bridge: bridge);

      await c.load();

      expect(c.setupInitiated, isFalse);
      expect(c.phase, WifiMonitorPhase.needsInstall);
      c.dispose();
      await bridge.close();
    });
  });

  // Missing / deleted companion Shortcut detection (onboarding recovery).
  //
  // iOS reports `runShortcut` (UIApplication.open of `shortcuts://run-shortcut?
  // name=…`) as a SUCCESS whenever it could surface the Shortcuts app — even
  // when the named Shortcut was DELETED. So `opened == true` alone cannot tell a
  // working Shortcut from a missing one; the missing case used to fail silently
  // (no payload ever arrived) and the in-tool reinstall card never fired. The
  // controller now settles after a successful open and, on a FIRST-EVER run with
  // no payload delivered, returns false so the caller raises the reinstall card.
  group('missing-Shortcut detection (deleted "WLAN Pros Live")', () {
    // A short settle keeps these unit tests fast while still exercising the
    // settle-then-verify path.
    const Duration fastSettle = Duration(milliseconds: 10);

    test(
        'getReadingOnce: open succeeds but NO payload ever -> shortcutMissing fires',
        () async {
      // The deleted-Shortcut scenario: iOS "opened" the trigger (launched the
      // Shortcuts app), nothing ran, no payload arrives, none ever has. The call
      // returns true on the OPEN (so the happy path is not stalled); the missing
      // verdict surfaces asynchronously via [shortcutMissing] after the settle.
      final bridge = _FakeBridge()
        ..everReceived = false
        ..latest = null
        ..runShortcutResult = true;
      final c = WifiMonitorController(
        bridge: bridge,
        missingShortcutSettle: fastSettle,
      );
      await c.load();

      var notified = false;
      c.addListener(() => notified = true);

      final bool opened =
          await c.getReadingOnce(triggerShortcutName: 'WLAN Pros Live');

      expect(opened, isTrue, reason: 'the trigger opened; the open is honored');
      expect(c.shortcutMissing, isFalse,
          reason: 'verdict is async — not yet decided immediately after open');

      // Let the settle elapse and the verify run.
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(c.shortcutMissing, isTrue,
          reason: 'a deleted Shortcut that delivers no payload must flag missing '
              'so the in-tool reinstall card fires');
      expect(notified, isTrue, reason: 'the flag flip notifies the screen');
      expect(bridge.runShortcutCalls, 1);
      expect(c.hasEverReceived, isFalse);
      c.dispose();
      await bridge.close();
    });

    test('getReadingOnce: open succeeds AND a payload lands -> not missing',
        () async {
      // The working Shortcut: it opened and delivered a sample during settle.
      final bridge = _FakeBridge()
        ..everReceived = false
        ..runShortcutResult = true;
      final c = WifiMonitorController(
        bridge: bridge,
        missingShortcutSettle: const Duration(milliseconds: 50),
      );
      await c.load();

      final bool opened =
          await c.getReadingOnce(triggerShortcutName: 'WLAN Pros Live');
      expect(opened, isTrue);
      // The companion Shortcut delivers within the settle window.
      bridge.push(_details(ssid: 'Delivered'));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(c.shortcutMissing, isFalse,
          reason: 'a delivered payload proves the Shortcut ran');
      expect(c.hasEverReceived, isTrue);
      expect(c.details!.ssid, 'Delivered');
      c.dispose();
      await bridge.close();
    });

    test('getReadingOnce: settle reads a persisted App Group payload -> not missing',
        () async {
      // The streamed sample raced the foreground return, but the native side
      // persisted it; the settle poll picks it up and the run reads as working.
      final bridge = _FakeBridge()
        ..everReceived = false
        ..runShortcutResult = true
        ..latest = _details(ssid: 'Persisted');
      final c = WifiMonitorController(
        bridge: bridge,
        missingShortcutSettle: fastSettle,
      );
      await c.load();
      // load() seeded details from `latest`; keep `latest` set so the in-settle
      // App Group poll proves the Shortcut delivered.
      bridge.latest = _details(ssid: 'Persisted');

      final bool opened =
          await c.getReadingOnce(triggerShortcutName: 'WLAN Pros Live');
      expect(opened, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(c.shortcutMissing, isFalse);
      expect(c.details!.ssid, 'Persisted');
      c.dispose();
      await bridge.close();
    });

    test('getReadingOnce: a previously-working Shortcut is NOT flagged missing',
        () async {
      // hasEverReceived is true (the Shortcut delivered before), so a transient
      // miss must NOT surface the reinstall card — no nagging working users. The
      // verify returns instantly without burning the (long) settle window.
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details()
        ..runShortcutResult = true;
      final c = WifiMonitorController(
        bridge: bridge,
        missingShortcutSettle: const Duration(seconds: 30),
      );
      await c.load();

      final bool opened =
          await c.getReadingOnce(triggerShortcutName: 'WLAN Pros Live');
      // Even after well beyond a real settle, no missing verdict — the verify
      // short-circuits on hasEverReceived.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(opened, isTrue);
      expect(c.shortcutMissing, isFalse);
      c.dispose();
      await bridge.close();
    });

    test('getReadingOnce: open FAILS outright -> returns false, no settle',
        () async {
      // Shortcuts app itself absent: open returns false; the screen surfaces the
      // setup card on the false return (no settle needed), preserving the
      // original fast-fail behavior.
      final bridge = _FakeBridge()
        ..everReceived = false
        ..runShortcutResult = false;
      final c = WifiMonitorController(
        bridge: bridge,
        missingShortcutSettle: const Duration(seconds: 30),
      );
      await c.load();

      final bool opened = await c
          .getReadingOnce(triggerShortcutName: 'WLAN Pros Live')
          .timeout(const Duration(seconds: 1));

      expect(opened, isFalse);
      c.dispose();
      await bridge.close();
    });

    test('getReadingOnce: a fresh attempt clears a prior missing verdict',
        () async {
      // After a missing verdict, re-running clears the stale card immediately so
      // the user is not shown a reinstall prompt while the retry is in flight.
      final bridge = _FakeBridge()
        ..everReceived = false
        ..latest = null
        ..runShortcutResult = true;
      final c = WifiMonitorController(
        bridge: bridge,
        missingShortcutSettle: fastSettle,
      );
      await c.load();

      await c.getReadingOnce(triggerShortcutName: 'WLAN Pros Live');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(c.shortcutMissing, isTrue);

      // Retry: the stale verdict clears synchronously at the start of the call.
      final Future<bool> retry =
          c.getReadingOnce(triggerShortcutName: 'WLAN Pros Live');
      expect(c.shortcutMissing, isFalse);
      await retry;
      c.dispose();
      await bridge.close();
    });

    test('startMonitoring (continuous): deleted Shortcut -> shortcutMissing fires',
        () async {
      // The continuous opt-in path mirrors the one-shot: a successful open with
      // no first-ever payload flags missing after the settle, so the screen shows
      // the reinstall card and stops the phantom stream.
      final bridge = _FakeBridge()
        ..everReceived = false
        ..latest = null
        ..runShortcutResult = true;
      final c = WifiMonitorController(
        bridge: bridge,
        missingShortcutSettle: fastSettle,
      );
      await c.load();

      final bool opened =
          await c.startMonitoring(triggerShortcutName: 'WLAN Pros Live');
      expect(opened, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(c.shortcutMissing, isTrue);
      expect(bridge.runShortcutCalls, 1);
      c.dispose();
      await bridge.close();
    });
  });

  // x-error recovery for a RENAMED/DELETED Shortcut (2026-06-25, Keith build 41).
  //
  // The one-shot trigger now carries an `x-error` return URL, so a missing
  // Shortcut bounces the app back via `wlanprostoolbox://live-error` instead of
  // stranding the user on the Shortcuts page. The native handler resets the
  // durable install-state and raises a consumed-once marker; the controller reads
  // it on the resume-driven load and forces the honest setup recovery. This is
  // the path the settle-timer could NOT cover, because it short-circuits on
  // hasEverReceived (Keith had received payloads before deleting the Shortcut).
  group('x-error recovery (renamed/deleted "WLAN Pros Live")', () {
    test('a previously-working Shortcut, now missing -> needsInstall + shortcutMissing',
        () async {
      // Native markShortcutMissing has already cleared the trust flag + stored
      // reading (so everReceived=false, latest=null here) and set the marker.
      final bridge = _FakeBridge()
        ..everReceived = false
        ..latest = null
        ..shortcutMissingFlag = true;
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: _conn(wifiIp: '192.168.0.10'),
      );

      await c.load();

      expect(bridge.consumeShortcutMissingCalls, 1);
      expect(c.shortcutMissing, isTrue,
          reason: 'the x-error marker drives the in-tool "not found" recovery');
      expect(c.hasEverReceived, isFalse, reason: 'the trust gate is reset');
      expect(c.phase, WifiMonitorPhase.needsInstall,
          reason: 'the tool returns to "Set up live Wi-Fi" mode');
      c.dispose();
      await bridge.close();
    });

    test('missing marker forces setup recovery OVER the not-on-Wi-Fi card',
        () async {
      // Even off Wi-Fi, the actionable fix for a deleted Shortcut is re-running
      // setup, so the missing recovery wins over the not-on-Wi-Fi state.
      final bridge = _FakeBridge()..shortcutMissingFlag = true;
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: _conn(wifiIp: null), // would otherwise be notOnWifi
      );

      await c.load();

      expect(c.shortcutMissing, isTrue);
      expect(c.notOnWifi, isFalse);
      expect(c.phase, WifiMonitorPhase.needsInstall);
      c.dispose();
      await bridge.close();
    });

    test('the marker is consumed ONCE: a fresh controller reload clears recovery',
        () async {
      // The native flag is one-shot; after the first load consumes it a fresh
      // controller (new screen mount) reads false and shows the neutral setup
      // prompt rather than the "not found" copy.
      final bridge = _FakeBridge()..shortcutMissingFlag = true;
      final c1 = WifiMonitorController(bridge: bridge);
      await c1.load();
      expect(c1.shortcutMissing, isTrue);

      final c2 = WifiMonitorController(bridge: bridge);
      await c2.load();
      expect(c2.shortcutMissing, isFalse,
          reason: 'consumed-once — the second load no longer flags missing');
      expect(c2.phase, WifiMonitorPhase.needsInstall,
          reason: 'install-state stays reset until a real payload arrives');
      c1.dispose();
      c2.dispose();
      await bridge.close();
    });

    test('no marker -> normal load is unaffected (no false recovery)', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details();
      final c = WifiMonitorController(bridge: bridge);

      await c.load();

      expect(bridge.consumeShortcutMissingCalls, 1);
      expect(c.shortcutMissing, isFalse);
      expect(c.phase, WifiMonitorPhase.idleWithData);
      c.dispose();
      await bridge.close();
    });
  });

  // The honest "you're not connected to Wi-Fi" state (2026-06-25). The three
  // states the live Wi-Fi surfaces must distinguish:
  //   1. NOT on Wi-Fi (cellular-only)        -> notOnWifi phase (NEW).
  //   2. ON Wi-Fi but Shortcut not set up     -> needsInstall (existing CTA).
  //   3. ON Wi-Fi + has data                  -> idleWithData / streaming.
  group('not-on-Wi-Fi state (honest connection probe)', () {
    test('STATE 1: not on Wi-Fi + no payload ever -> notOnWifi (not needsInstall)',
        () async {
      // A cellular-only user with the Shortcut never run: the honest state is
      // "connect to Wi-Fi", NOT "set up the Shortcut" — the Shortcut cannot read
      // Wi-Fi RF that does not exist.
      final bridge = _FakeBridge()..everReceived = false;
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: _conn(wifiIp: null), // null IP on iOS => notOnWifi
      );

      await c.load();

      expect(c.phase, WifiMonitorPhase.notOnWifi);
      expect(c.notOnWifi, isTrue);
      c.dispose();
      await bridge.close();
    });

    test('STATE 2: ON Wi-Fi but no payload ever -> needsInstall (the setup CTA)',
        () async {
      // On Wi-Fi (real Wi-Fi IP) but the Shortcut has never delivered: the setup
      // CTA is correct, and the not-on-Wi-Fi state must NOT appear.
      final bridge = _FakeBridge()..everReceived = false;
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: _conn(wifiIp: '192.168.0.10'),
      );

      await c.load();

      expect(c.phase, WifiMonitorPhase.needsInstall);
      expect(c.notOnWifi, isFalse);
      c.dispose();
      await bridge.close();
    });

    test('STATE 3: ON Wi-Fi + data -> idleWithData (live flow, not notOnWifi)',
        () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details();
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: _conn(wifiIp: '192.168.0.10'),
      );

      await c.load();

      expect(c.phase, WifiMonitorPhase.idleWithData);
      expect(c.notOnWifi, isFalse);
      c.dispose();
      await bridge.close();
    });

    test('a resolved native SSID overrides a null Wi-Fi IP -> NOT notOnWifi',
        () async {
      // Even with a null Wi-Fi IP, a known native SSID proves an active join, so
      // the user is on Wi-Fi and falls to the setup CTA, never the not-on-Wi-Fi
      // state (GL-005 — no false negative).
      final bridge = _FakeBridge()..everReceived = false;
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: _conn(wifiIp: null),
      );

      await c.load(nativeSsid: 'KeithNet');

      expect(c.phase, WifiMonitorPhase.needsInstall);
      expect(c.notOnWifi, isFalse);
      c.dispose();
      await bridge.close();
    });

    test('not-on-Wi-Fi NEVER blanks data the user already has', () async {
      // A transient drop to cellular while a reading is already on screen must
      // keep showing the last reading — the not-on-Wi-Fi phase is gated on
      // !hasEverReceived, so existing data is preserved.
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details(ssid: 'LastKnown');
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: _conn(wifiIp: null), // dropped to cellular
      );

      await c.load();

      expect(c.phase, WifiMonitorPhase.idleWithData);
      expect(c.notOnWifi, isTrue, reason: 'the probe still reports off-Wi-Fi');
      expect(c.details!.ssid, 'LastKnown',
          reason: 'the last reading is retained, never blanked');
      c.dispose();
      await bridge.close();
    });

    test('rejoining Wi-Fi on a reload clears the not-on-Wi-Fi state', () async {
      // First load: cellular -> notOnWifi. Then the user joins Wi-Fi and the
      // "Check again" retry reloads with a Wi-Fi IP -> the state clears to the
      // setup CTA.
      final fakeNet = _FakeNetworkInfo(wifiIp: null);
      final bridge = _FakeBridge()..everReceived = false;
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: WifiConnectionService(
          networkInfo: fakeNet,
          platformOverride: TargetPlatform.iOS,
        ),
      );

      await c.load();
      expect(c.phase, WifiMonitorPhase.notOnWifi);

      // User joins Wi-Fi; "Check again" reloads.
      fakeNet.wifiIp = '192.168.5.20';
      await c.load();

      expect(c.phase, WifiMonitorPhase.needsInstall);
      expect(c.notOnWifi, isFalse);
      c.dispose();
      await bridge.close();
    });
  });
}
