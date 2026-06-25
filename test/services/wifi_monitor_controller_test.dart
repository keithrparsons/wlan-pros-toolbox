// Unit tests for the Wi-Fi monitoring state machine (TICKET-03 A2/A4).
//
// Covers install-state branching (no data -> needsInstall; data -> idleWithData;
// relaunch-while-monitoring -> streaming), the start -> receive N -> stop loop,
// the monitoring-flag writes that gate the looping Shortcut, and the preserved
// one-shot path. No native channel is touched — a fake bridge stands in.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_monitor_controller.dart';

/// In-memory fake of [WiFiDetailsBridge] for state-machine tests.
class _FakeBridge extends WiFiDetailsBridge {
  _FakeBridge();

  final StreamController<WiFiDetails> _controller =
      StreamController<WiFiDetails>.broadcast();

  bool everReceived = false;
  bool monitoringFlag = false;
  WiFiDetails? latest;
  bool runShortcutResult = true;

  int setMonitoringActiveCalls = 0;
  bool? lastMonitoringValue;
  int runShortcutCalls = 0;
  String? lastRunShortcutName;

  @override
  Future<bool> hasEverReceivedPayload() async => everReceived;

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
}
