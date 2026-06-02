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
  String? lastRunShortcutTool;

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
  Future<bool> runShortcut(String name, {required String tool}) async {
    runShortcutCalls++;
    lastRunShortcutName = name;
    lastRunShortcutTool = tool;
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

    test('start fires the recursive trigger once with the canonical name',
        () async {
      // TICKET-05: Start raises the flag AND fires the run-shortcut trigger once
      // to kick off the recursion. The app never loops itself.
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _details();
      final c = WifiMonitorController(bridge: bridge);
      await c.load();

      final bool opened = await c.startMonitoring(
        triggerShortcutName: 'WLAN Pros Wi-Fi',
        triggerTool: 'wifi-info',
      );

      expect(opened, isTrue);
      expect(c.isStreaming, isTrue);
      expect(bridge.lastMonitoringValue, isTrue);
      expect(bridge.runShortcutCalls, 1);
      expect(bridge.lastRunShortcutName, 'WLAN Pros Wi-Fi');
      expect(bridge.lastRunShortcutTool, 'wifi-info');
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
}
