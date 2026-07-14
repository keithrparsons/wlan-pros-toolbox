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

/// A [NetworkInfo] fake feeding [WifiConnectionService]: canned Wi-Fi addresses
/// drive the on/not-on-Wi-Fi verdict deterministically in the controller tests.
///
/// BOTH ADDRESS FAMILIES (2026-07-13). The probe now requires IPv4 AND routable
/// IPv6 to be absent before it asserts `notOnWifi`, because `getWifiIP()` is
/// IPv4-only and an iPhone on an IPv6-only SSID reads null there while fully
/// associated (cold-eyes F3). A fake that answers only IPv4 no longer models the
/// plugin: its IPv6 read would throw, the probe would honestly resolve to
/// `unknown`, and these tests would be asserting against a device state that
/// cannot occur. Default: no IPv6 either → the cellular-only case.
class _FakeNetworkInfo implements NetworkInfo {
  _FakeNetworkInfo({this.wifiIp, this.wifiIpv6});

  String? wifiIp;
  String? wifiIpv6;

  @override
  Future<String?> getWifiIP() async => wifiIp;

  @override
  Future<String?> getWifiIPv6() async => wifiIpv6;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [NetworkInfo] fake whose read THROWS — the denied-permission / unsupported-
/// platform case. It must resolve to [WifiConnectionStatus.unknown], never to a
/// false `notOnWifi` (GL-005), so a Location-gated read never blanks real data.
class _ThrowingNetworkInfo implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => throw Exception('permission denied');

  @override
  Future<String?> getWifiIPv6() async => throw Exception('permission denied');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Builds a [WifiConnectionService] pinned to iOS with a canned Wi-Fi IP — a
/// non-null IP => onWifi, a null IP => notOnWifi (the controller's not-on-Wi-Fi
/// branch under test).
WifiConnectionService _conn({String? wifiIp, String? wifiIpv6}) {
  return WifiConnectionService(
    networkInfo: _FakeNetworkInfo(wifiIp: wifiIp, wifiIpv6: wifiIpv6),
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
  Future<void> setLiveOriginRoute(String route) async {}
  @override
  Future<String?> consumeLiveErrorNav() async => null;

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

  /// Mirrors the native cold-start reset (Option B): clears the shared
  /// monitoring flag (and, natively, its start stamp) so a stale force-quit flag
  /// does not suppress a legitimate new Start via the app-wide single-flight.
  int resetColdStartCalls = 0;

  @override
  Future<void> resetMonitoringColdStart() async {
    resetColdStartCalls++;
    monitoringFlag = false;
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

    test(
        'START-AWARE recovery: a PREVIOUSLY-WORKING Shortcut, now missing, that '
        'delivers no first sample on a Start -> shortcutMissing + stream torn down',
        () async {
      // Keith device round 5: streaming is the only live action, so a missing
      // Shortcut on a Start must self-surface the recovery EVEN for a set-up user
      // (hasEverReceived true). The Start-aware settle keys on "no first sample
      // THIS Start", not on hasEverReceived, and does NOT poll the App Group (a
      // stale stored reading would mask the miss). It tears down the phantom
      // stream so no dead "LIVE" shows.
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details() // a stale stored reading is present
        ..runShortcutResult = true;
      final c = WifiMonitorController(
        bridge: bridge,
        missingShortcutSettle: fastSettle,
      );
      await c.load();
      expect(c.shortcutMissing, isFalse);

      final bool opened =
          await c.startMonitoring(triggerShortcutName: 'WLAN Pros Live');
      expect(opened, isTrue);
      expect(c.isStreaming, isTrue, reason: 'streaming starts optimistically');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(c.shortcutMissing, isTrue,
          reason: 'no first sample this Start => the Shortcut is missing');
      expect(c.isStreaming, isFalse,
          reason: 'the phantom stream is torn down (no producer)');
      c.dispose();
      await bridge.close();
    });

    test(
        'START-AWARE recovery: a WORKING Shortcut that delivers a first sample is '
        'NOT flagged missing',
        () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details()
        ..runShortcutResult = true;
      final c = WifiMonitorController(
        bridge: bridge,
        missingShortcutSettle: fastSettle,
      );
      await c.load();

      await c.startMonitoring(triggerShortcutName: 'WLAN Pros Live');
      // The recursive Shortcut delivers a first sample before the settle.
      bridge.push(_details(ssid: 'Live-1', rssi: -42));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(c.shortcutMissing, isFalse,
          reason: 'a delivered first sample proves the stream started');
      expect(c.isStreaming, isTrue);
      expect(c.details!.ssid, 'Live-1');
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

  // App-wide single-flight + cold-start reset (Option B, launch-safe mitigation
  // for the live-monitoring runaway). Two symptoms this guards:
  //   (2) multiple scenes/surfaces each fired their own run and none superseded
  //       each other — no app-wide single-flight, only per-screen re-entrancy.
  //   (1)+(3) a stale force-quit flag survived process death; on relaunch it must
  //       neither keep an orphaned loop trusted nor SUPPRESS a legitimate new
  //       Start (which the single-flight would otherwise adopt).
  group('app-wide single-flight (Option B)', () {
    test(
        'a Start while the loop is ALREADY active ADOPTS it and does NOT fire a '
        'second run-shortcut', () async {
      // RED on the pre-fix code: startMonitoring always fired the trigger, so a
      // second surface Start stacked a second independent Shortcut loop.
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details()
        ..monitoringFlag = true; // another scene already started the loop
      final c = WifiMonitorController(bridge: bridge);
      await c.load(); // resumes streaming from the active flag

      final bool ok =
          await c.startMonitoring(triggerShortcutName: 'WLAN Pros Live');

      expect(ok, isTrue);
      expect(c.isStreaming, isTrue, reason: 'adopts the running stream');
      expect(bridge.runShortcutCalls, 0,
          reason: 'an already-active loop is adopted, never re-fired (no stacking)');
      c.dispose();
      await bridge.close();
    });

    test('a Start from a clean (inactive) state fires exactly ONE run-shortcut',
        () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details()
        ..monitoringFlag = false; // clean slate (cold-start reset ran)
      final c = WifiMonitorController(bridge: bridge);
      await c.load();

      await c.startMonitoring(triggerShortcutName: 'WLAN Pros Live');

      expect(bridge.runShortcutCalls, 1,
          reason: 'a genuine false→true transition fires the trigger once');
      expect(bridge.lastMonitoringValue, isTrue);
      c.dispose();
      await bridge.close();
    });
  });

  group('cold-start reset (Option B)', () {
    test(
        'WITHOUT reset: a stale force-quit flag makes single-flight ADOPT and NOT '
        'fire — the bug the reset guards', () async {
      // A prior force-quit left the flag stale-true but the external loop is dead.
      // Single-flight adopts the phantom flag and fires nothing → the user\'s Start
      // silently no-ops. This test documents WHY the cold-start reset is required.
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details()
        ..monitoringFlag = true; // stale from a force-quit
      final c = WifiMonitorController(bridge: bridge);
      await c.load();

      await c.startMonitoring(triggerShortcutName: 'WLAN Pros Live');

      expect(bridge.runShortcutCalls, 0,
          reason: 'a stale flag is adopted, so a legit Start fires nothing');
      c.dispose();
      await bridge.close();
    });

    test('WITH reset: clearing the stale flag lets the next Start fire the trigger',
        () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details()
        ..monitoringFlag = true; // stale from a force-quit

      // Cold start: main() calls resetMonitoringColdStart before any screen runs.
      await bridge.resetMonitoringColdStart();
      expect(bridge.resetColdStartCalls, 1);
      expect(bridge.monitoringFlag, isFalse,
          reason: 'the reset cleared the stale flag');

      final c = WifiMonitorController(bridge: bridge);
      await c.load();

      await c.startMonitoring(triggerShortcutName: 'WLAN Pros Live');

      expect(bridge.runShortcutCalls, 1,
          reason: 'a clean slate makes the Start a genuine false→true transition');
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

    // ======================================================================
    // OVER-SUPPRESSION — the dangerous direction (cold-eyes F3, 2026-07-13).
    //
    // The not-on-Wi-Fi suppression is LOAD-BEARING here: it nulls [details], tears
    // down a LIVE stream, and clears the App Group loop flag. So a FALSE positive
    // from the probe does real damage to a working device — and `getWifiIP()` is
    // IPv4-only, so an iPhone on an IPv6-only SSID (NAT64/DNS64: carrier and
    // CONFERENCE networks) hit exactly that. Keith runs conference Wi-Fi.
    // ======================================================================
    test('IPv6-ONLY Wi-Fi is NOT blanked: a live reading survives, no notOnWifi',
        () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details();
      final c = WifiMonitorController(
        bridge: bridge,
        // No Wi-Fi IPv4 (the plugin cannot see one) but a routable IPv6: the phone
        // is ASSOCIATED and working.
        connectionService: _conn(wifiIp: null, wifiIpv6: '2606:4700:4700::1111'),
      );

      await c.load();

      expect(c.notOnWifi, isFalse,
          reason: 'an IPv6-only Wi-Fi network is still Wi-Fi');
      expect(c.phase, isNot(WifiMonitorPhase.notOnWifi));
      expect(c.details, isNotNull,
          reason: 'the live reading of a CONNECTED device must not be blanked');
      c.dispose();
      await bridge.close();
    });

    test('IPv6-ONLY Wi-Fi does not tear down a live stream mid-flight', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details();
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: _conn(wifiIp: null, wifiIpv6: 'fd12:3456:789a::1'),
      );
      await c.load();
      await c.startMonitoring(triggerShortcutName: 'WLAN Pros Live');
      expect(c.isStreaming, isTrue, reason: 'sanity: the stream started');

      // A resume-driven reload on the same IPv6-only network must leave the live
      // stream alone. Pre-fix this called stopMonitoring() and cleared the App
      // Group flag, killing a working feed on a working network.
      await c.load();

      expect(c.isStreaming, isTrue,
          reason: 'a working stream on a working network must not be torn down');
      expect(c.notOnWifi, isFalse);
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

    // ─────────────────────────────────────────────────────────────────────────
    // THE STALE-READING REGRESSION (2026-07-13, Keith on-device, iOS v1.7.2).
    //
    // This block REPLACES a prior test titled "not-on-Wi-Fi NEVER blanks data
    // the user already has", which asserted phase == idleWithData and
    // details!.ssid == 'LastKnown' while the probe reported off-Wi-Fi. That test
    // PASSED, and it was WRONG: it codified the bug as the spec. On a cellular-
    // only iPhone the app showed Tx 29 / Rx 13 Mbps as current/min/avg/max under
    // a LIVE badge, and Test My Connection told Keith to "boost the Wi-Fi signal"
    // — from a link that did not exist. The suite was green the whole time.
    //
    // The honest rule: a POSITIVE not-on-Wi-Fi probe outranks any stored reading.
    // There is no Wi-Fi link, so there is no Wi-Fi reading (GL-005 — the
    // "this does not exist" null, not the "we could not read it" null).
    // ─────────────────────────────────────────────────────────────────────────
    test(
        'REGRESSION: a stale stored reading NEVER outranks a positive '
        'not-on-Wi-Fi probe', () async {
      // The exact device shape: the user HAS captured Wi-Fi readings before
      // (everReceived), the App Group still holds the last one, and the phone is
      // now on cellular only. Pre-fix this landed on idleWithData and rendered
      // the stale 29/13 Mbps rates as current.
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details(ssid: 'LastKnown');
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: _conn(wifiIp: null), // cellular-only iPhone
      );

      await c.load();

      expect(c.notOnWifi, isTrue, reason: 'the probe positively reports off-Wi-Fi');
      expect(c.phase, WifiMonitorPhase.notOnWifi,
          reason: 'the honest not-on-Wi-Fi state must win over a stale reading, '
              'no matter how many payloads have arrived in the past');
      expect(c.details, isNull,
          reason: 'THE BUG: there is no Wi-Fi link, so there is no Wi-Fi '
              'reading. A stored rate must never render as a current one.');
      c.dispose();
      await bridge.close();
    });

    test(
        'REGRESSION: dropping to cellular WHILE STREAMING tears the stream down '
        '(no LIVE badge over a stale rate)', () async {
      // Keith saw a green LIVE badge on a phone with no Wi-Fi. A stream whose
      // producer is gone must not keep the screen in the streaming phase: there
      // is no companion Shortcut delivering anything over a link that does not
      // exist.
      final fakeNet = _FakeNetworkInfo(wifiIp: '192.168.0.10');
      final bridge = _FakeBridge()..everReceived = true;
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: WifiConnectionService(
          networkInfo: fakeNet,
          platformOverride: TargetPlatform.iOS,
        ),
      );

      await c.load();
      await c.startMonitoring();
      bridge.push(_details(ssid: 'RealLive', rssi: -50));
      await Future<void>.delayed(Duration.zero);
      expect(c.isStreaming, isTrue);
      expect(c.details!.ssid, 'RealLive');

      // Wi-Fi drops. The app resumes / re-probes.
      fakeNet.wifiIp = null;
      await c.load();

      expect(c.phase, WifiMonitorPhase.notOnWifi);
      expect(c.isStreaming, isFalse,
          reason: 'no producer, no link — the LIVE state must not survive');
      expect(c.details, isNull,
          reason: 'the last live reading is not a current reading once the '
              'link is gone');
      expect(bridge.lastMonitoringValue, isFalse,
          reason: 'the App Group loop flag is cleared so the looping Shortcut '
              'halts');
      c.dispose();
      await bridge.close();
    });

    test(
        'REGRESSION: pollLatestAfterOneShot does NOT re-deliver the stored '
        'reading as a live payload while off Wi-Fi', () async {
      // The settle-poll exists for a race (the Shortcut delivered while we were
      // backgrounded). Off Wi-Fi the Shortcut delivered NOTHING, and the App
      // Group still holds the last on-Wi-Fi payload. Feeding that through the
      // live-payload path stamps `lastUpdated = now`, advances deliveryCount, and
      // charts a months-old rate as a fresh sample — which is how the sparkline
      // and its min/avg/max got populated on a cellular-only phone.
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details(ssid: 'Stale');
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: _conn(wifiIp: null),
      );
      await c.load();
      expect(c.deliveryCount, 0);

      await c.pollLatestAfterOneShot();

      expect(c.deliveryCount, 0,
          reason: 'a STORED reading is not a LIVE delivery — never chart it as '
              'one while the device has no Wi-Fi link');
      expect(c.details, isNull);
      expect(c.phase, WifiMonitorPhase.notOnWifi);
      c.dispose();
      await bridge.close();
    });

    // ── ANTI-OVER-SUPPRESSION ────────────────────────────────────────────────
    // The fix must not suppress MORE than is true. There is prior art of an
    // over-suppressing "honest null" fix on this codebase that was rejected. An
    // AMBIGUOUS probe (a wired desktop, a Location-gated read, a failed read) is
    // NOT a not-on-Wi-Fi signal and must leave the existing behavior untouched.
    test(
        'ANTI-OVER-SUPPRESSION: an AMBIGUOUS probe (wired desktop) never blanks '
        'data and never claims "not on Wi-Fi"', () async {
      // A wired Mac has no Wi-Fi IP — but that is UNKNOWN, not "not on Wi-Fi"
      // (WifiConnectionService only asserts notOnWifi on iOS). The stored reading
      // must still render, exactly as before the fix.
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details(ssid: 'WiredMacLastKnown');
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: WifiConnectionService(
          networkInfo: _FakeNetworkInfo(wifiIp: null), // no Wi-Fi IP
          platformOverride: TargetPlatform.macOS, // …but ambiguous, not iOS
        ),
      );

      await c.load();

      expect(c.notOnWifi, isFalse,
          reason: 'an ambiguous read is never a positive not-on-Wi-Fi verdict');
      expect(c.phase, WifiMonitorPhase.idleWithData,
          reason: 'a wired desktop must NOT be told to connect to Wi-Fi');
      expect(c.details!.ssid, 'WiredMacLastKnown',
          reason: 'ambiguity must not blank data the user already has');
      c.dispose();
      await bridge.close();
    });

    test(
        'ANTI-OVER-SUPPRESSION: a FAILED/denied probe read never claims "not on '
        'Wi-Fi"', () async {
      // A throwing getWifiIP (permission denied / unsupported) resolves to
      // `unknown`, never `notOnWifi` — so a Location-gated read keeps its data.
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details(ssid: 'GatedButReal');
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: WifiConnectionService(
          networkInfo: _ThrowingNetworkInfo(),
          platformOverride: TargetPlatform.iOS, // even on iOS
        ),
      );

      await c.load();

      expect(c.notOnWifi, isFalse);
      expect(c.phase, WifiMonitorPhase.idleWithData);
      expect(c.details!.ssid, 'GatedButReal');
      c.dispose();
      await bridge.close();
    });

    test('rejoining Wi-Fi restores the last known reading (nothing destroyed)',
        () async {
      // Suppression is a VIEW decision, not a deletion: once the probe clears,
      // the stored reading is available again with no re-fetch.
      final fakeNet = _FakeNetworkInfo(wifiIp: null);
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details(ssid: 'LastKnown');
      final c = WifiMonitorController(
        bridge: bridge,
        connectionService: WifiConnectionService(
          networkInfo: fakeNet,
          platformOverride: TargetPlatform.iOS,
        ),
      );

      await c.load();
      expect(c.phase, WifiMonitorPhase.notOnWifi);
      expect(c.details, isNull);

      // The user joins Wi-Fi and taps "Check again".
      fakeNet.wifiIp = '192.168.5.20';
      await c.load();

      expect(c.notOnWifi, isFalse);
      expect(c.phase, WifiMonitorPhase.idleWithData);
      expect(c.details!.ssid, 'LastKnown',
          reason: 'the reading was hidden, not deleted');
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
