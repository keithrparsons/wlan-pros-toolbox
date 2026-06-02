// Unit tests for the Cellular monitoring state machine (TICKET-05).
//
// Covers install-state branching, the start -> receive N -> stop loop, the
// shared monitoring-flag writes that gate the recursive Shortcut, the trigger
// kickoff on Start, and the preserved one-shot path. No native channel is
// touched — a fake bridge stands in.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_info.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_info_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_monitor_controller.dart';
import 'package:wlan_pros_toolbox/services/network/shortcut_trigger_result.dart';

/// In-memory fake of [CellularInfoBridge] for state-machine tests.
class _FakeBridge implements CellularInfoBridge {
  _FakeBridge();

  final StreamController<CellularInfo> _controller =
      StreamController<CellularInfo>.broadcast();

  bool everReceived = false;
  bool monitoringFlag = false;
  CellularInfo? latest;
  bool runShortcutResult = true;

  int setMonitoringActiveCalls = 0;
  bool? lastMonitoringValue;
  int runShortcutCalls = 0;
  String? lastRunShortcutName;
  String? lastRunShortcutTool;

  @override
  Future<bool> hasEverReceivedPayload() async => everReceived;

  @override
  Future<CellularInfo?> readLatest() async => latest;

  @override
  Future<bool> isMonitoringActive() async => monitoringFlag;

  @override
  Future<void> setMonitoringActive(bool active) async {
    setMonitoringActiveCalls++;
    lastMonitoringValue = active;
    monitoringFlag = active;
  }

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
  Stream<ShortcutTriggerEvent> get triggerEvents => const Stream.empty();

  @override
  Stream<ShortcutTriggerResult> get triggerResults => const Stream.empty();

  @override
  Stream<CellularInfo> get updates => _controller.stream;

  void push(CellularInfo d) => _controller.add(d);

  Future<void> close() => _controller.close();
}

CellularInfo _info({String carrier = 'Verizon', int bars = 3}) {
  return CellularInfo(
    carrier: carrier,
    radioTechnology: '5G NR',
    signalBars: bars,
    countryCode: 'US',
    roaming: false,
  );
}

void main() {
  group('load — install-state branching', () {
    test('no payload ever -> needsInstall', () async {
      final bridge = _FakeBridge()..everReceived = false;
      final c = CellularMonitorController(bridge: bridge);

      await c.load();

      expect(c.phase, CellularMonitorPhase.needsInstall);
      expect(c.hasEverReceived, isFalse);
      expect(c.info, isNull);
      c.dispose();
      await bridge.close();
    });

    test('payload received before, not monitoring -> idleWithData', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _info()
        ..monitoringFlag = false;
      final c = CellularMonitorController(bridge: bridge);

      await c.load();

      expect(c.phase, CellularMonitorPhase.idleWithData);
      expect(c.info, isNotNull);
      expect(c.info!.carrier, 'Verizon');
      expect(c.lastUpdated, isNotNull);
      c.dispose();
      await bridge.close();
    });

    test('relaunch with monitoring flag set -> resumes streaming', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _info()
        ..monitoringFlag = true;
      final c = CellularMonitorController(bridge: bridge);

      await c.load();

      expect(c.phase, CellularMonitorPhase.streaming);
      expect(c.isStreaming, isTrue);
      c.dispose();
      await bridge.close();
    });
  });

  group('streaming state machine (start -> receive N -> stop)', () {
    test('start sets the flag, fires the trigger, and enters streaming',
        () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _info();
      final c = CellularMonitorController(bridge: bridge);
      await c.load();

      final bool opened = await c.startMonitoring(
        triggerShortcutName: 'WLAN Pros Cellular',
        triggerTool: 'cellular-info',
      );

      expect(opened, isTrue);
      expect(c.isStreaming, isTrue);
      expect(bridge.lastMonitoringValue, isTrue);
      // Start fires the recursive Shortcut once to kick off the stream.
      expect(bridge.runShortcutCalls, 1);
      expect(bridge.lastRunShortcutName, 'WLAN Pros Cellular');
      expect(bridge.lastRunShortcutTool, 'cellular-info');
      c.dispose();
      await bridge.close();
    });

    test('start without a trigger name skips the trigger (resume case)',
        () async {
      final bridge = _FakeBridge()..everReceived = true;
      final c = CellularMonitorController(bridge: bridge);
      await c.load();

      final bool ok = await c.startMonitoring();

      expect(ok, isTrue);
      expect(c.isStreaming, isTrue);
      expect(bridge.runShortcutCalls, 0);
      c.dispose();
      await bridge.close();
    });

    test('receives N pushed payloads; updates info + timestamp', () async {
      final bridge = _FakeBridge()..everReceived = true;
      final c = CellularMonitorController(bridge: bridge);
      await c.load();
      await c.startMonitoring();

      var notifications = 0;
      c.addListener(() => notifications++);

      bridge.push(_info(carrier: 'A', bars: 1));
      await Future<void>.delayed(Duration.zero);
      bridge.push(_info(carrier: 'B', bars: 4));
      await Future<void>.delayed(Duration.zero);

      expect(c.info!.carrier, 'B');
      expect(c.info!.signalBars, 4);
      expect(c.hasEverReceived, isTrue);
      expect(c.lastUpdated, isNotNull);
      expect(notifications, greaterThanOrEqualTo(2));
      c.dispose();
      await bridge.close();
    });

    test('stop clears the flag, leaves streaming, retains the last payload',
        () async {
      final bridge = _FakeBridge()..everReceived = true;
      final c = CellularMonitorController(bridge: bridge);
      await c.load();
      await c.startMonitoring();
      bridge.push(_info(carrier: 'Last'));
      await Future<void>.delayed(Duration.zero);

      await c.stopMonitoring();

      expect(c.isStreaming, isFalse);
      expect(c.phase, CellularMonitorPhase.idleWithData);
      expect(bridge.lastMonitoringValue, isFalse);
      expect(c.info!.carrier, 'Last');
      c.dispose();
      await bridge.close();
    });

    test('payloads pushed after stop are ignored', () async {
      final bridge = _FakeBridge()..everReceived = true;
      final c = CellularMonitorController(bridge: bridge);
      await c.load();
      await c.startMonitoring();
      bridge.push(_info(carrier: 'Before'));
      await Future<void>.delayed(Duration.zero);
      await c.stopMonitoring();

      bridge.push(_info(carrier: 'After'));
      await Future<void>.delayed(Duration.zero);

      expect(c.info!.carrier, 'Before');
      c.dispose();
      await bridge.close();
    });

    test('an all-null payload on the stream is ignored', () async {
      final bridge = _FakeBridge()..everReceived = true;
      final c = CellularMonitorController(bridge: bridge);
      await c.load();
      await c.startMonitoring();
      bridge.push(_info(carrier: 'Real'));
      await Future<void>.delayed(Duration.zero);

      bridge.push(const CellularInfo()); // hasAnyData == false
      await Future<void>.delayed(Duration.zero);

      expect(c.info!.carrier, 'Real');
      c.dispose();
      await bridge.close();
    });

    test('start failing to open the trigger returns false', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..runShortcutResult = false;
      final c = CellularMonitorController(bridge: bridge);
      await c.load();

      final bool opened = await c.startMonitoring(
        triggerShortcutName: 'WLAN Pros Cellular',
      );

      expect(opened, isFalse);
      // The flag was still raised synchronously; the screen clears it on the
      // false return (its _startLive calls stopMonitoring).
      expect(bridge.runShortcutCalls, 1);
      c.dispose();
      await bridge.close();
    });
  });
}
