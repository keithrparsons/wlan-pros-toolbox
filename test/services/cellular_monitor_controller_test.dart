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

/// In-memory fake of [CellularInfoBridge] for state-machine tests.
class _FakeBridge implements CellularInfoBridge {
  _FakeBridge();

  final StreamController<CellularInfo> _controller =
      StreamController<CellularInfo>.broadcast();

  bool everReceived = false;
  bool monitoringFlag = false;
  CellularInfo? latest;
  bool runShortcutResult = true;

  /// Mirrors the native App Group missing-Shortcut marker (set on an x-error,
  /// consumed-once by the controller load).
  bool shortcutMissingFlag = false;
  int consumeShortcutMissingCalls = 0;

  /// Mirrors the native App Group post-install priming flag.
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
  Future<bool> runShortcut(String name) async {
    runShortcutCalls++;
    lastRunShortcutName = name;
    return runShortcutResult;
  }

  // ONE-SHOT (x-callback) trigger: getReadingOnce now fires via this form so the
  // single run auto-returns to the app. Routed through the same counter/result
  // as the plain trigger so the existing one-shot tests behave identically —
  // only the URL form changed.
  @override
  Future<bool> runShortcutOneShot(String name) async {
    runShortcutCalls++;
    lastRunShortcutName = name;
    return runShortcutResult;
  }

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

  // Post-install PRIMING window (2026-06-26). Mirrors the Wi-Fi controller: the
  // one combined Shortcut drives both tools, so the priming flag surfaces the
  // "tap Get reading to finish" step here too.
  group('post-install priming window', () {
    test('setup started, no payload yet -> setupInitiated true, needsInstall',
        () async {
      final bridge = _FakeBridge()
        ..everReceived = false
        ..setupInitiatedFlag = true;
      final c = CellularMonitorController(bridge: bridge);

      await c.load();

      expect(c.setupInitiated, isTrue);
      expect(c.hasEverReceived, isFalse);
      expect(c.phase, CellularMonitorPhase.needsInstall);
      c.dispose();
      await bridge.close();
    });

    test('a delivered payload ends priming', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _info()
        ..setupInitiatedFlag = true;
      final c = CellularMonitorController(bridge: bridge);

      await c.load();

      expect(c.setupInitiated, isFalse);
      expect(c.phase, CellularMonitorPhase.idleWithData);
      c.dispose();
      await bridge.close();
    });
  });

  // x-error recovery for a RENAMED/DELETED Shortcut (2026-06-25). The one combined
  // "WLAN Pros Live" Shortcut feeds the cellular tool too, so a missing-Shortcut
  // x-error resets it and surfaces the honest setup recovery. Mirrors the Wi-Fi
  // controller.
  group('x-error recovery (renamed/deleted "WLAN Pros Live")', () {
    test('missing marker -> needsInstall + shortcutMissing, gate reset', () async {
      final bridge = _FakeBridge()
        ..everReceived = false
        ..latest = null
        ..shortcutMissingFlag = true;
      final c = CellularMonitorController(bridge: bridge);

      await c.load();

      expect(bridge.consumeShortcutMissingCalls, 1);
      expect(c.shortcutMissing, isTrue);
      expect(c.hasEverReceived, isFalse);
      expect(c.phase, CellularMonitorPhase.needsInstall);
      c.dispose();
      await bridge.close();
    });

    test('marker is consumed once: a fresh controller reload clears recovery',
        () async {
      final bridge = _FakeBridge()..shortcutMissingFlag = true;
      final c1 = CellularMonitorController(bridge: bridge);
      await c1.load();
      expect(c1.shortcutMissing, isTrue);

      final c2 = CellularMonitorController(bridge: bridge);
      await c2.load();
      expect(c2.shortcutMissing, isFalse);
      expect(c2.phase, CellularMonitorPhase.needsInstall);
      c1.dispose();
      c2.dispose();
      await bridge.close();
    });

    test('no marker -> normal load is unaffected', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _info();
      final c = CellularMonitorController(bridge: bridge);

      await c.load();

      expect(bridge.consumeShortcutMissingCalls, 1);
      expect(c.shortcutMissing, isFalse);
      expect(c.phase, CellularMonitorPhase.idleWithData);
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
        triggerShortcutName: 'WLAN Pros Live',
      );

      expect(opened, isTrue);
      expect(c.isStreaming, isTrue);
      expect(bridge.lastMonitoringValue, isTrue);
      // Start fires the recursive combined Shortcut once to kick off the stream.
      expect(bridge.runShortcutCalls, 1);
      expect(bridge.lastRunShortcutName, 'WLAN Pros Live');
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
        triggerShortcutName: 'WLAN Pros Live',
      );

      expect(opened, isFalse);
      // The flag was still raised synchronously; the screen clears it on the
      // false return (its _startLive calls stopMonitoring).
      expect(bridge.runShortcutCalls, 1);
      c.dispose();
      await bridge.close();
    });
  });

  // Missing / deleted companion Shortcut detection (onboarding recovery).
  //
  // The combined "WLAN Pros Live" Shortcut feeds the cellular live tool too, so
  // a user who deleted it strands the cellular tool the same way. iOS reports
  // `runShortcut` as a SUCCESS whenever it could surface the Shortcuts app —
  // even for a deleted Shortcut — so the open boolean alone cannot tell working
  // from missing. The controller now settles after a successful open and, on a
  // FIRST-EVER run with no payload, returns false so the reinstall card fires.
  group('missing-Shortcut detection (deleted "WLAN Pros Live")', () {
    const Duration fastSettle = Duration(milliseconds: 10);

    test(
        'getReadingOnce: open succeeds but NO payload ever -> shortcutMissing fires',
        () async {
      // The call returns true on the OPEN; the missing verdict surfaces async via
      // [shortcutMissing] after the settle so a working read is never stalled.
      final bridge = _FakeBridge()
        ..everReceived = false
        ..latest = null
        ..runShortcutResult = true;
      final c = CellularMonitorController(
        bridge: bridge,
        missingShortcutSettle: fastSettle,
      );
      await c.load();

      final bool opened =
          await c.getReadingOnce(triggerShortcutName: 'WLAN Pros Live');
      expect(opened, isTrue);
      expect(c.shortcutMissing, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(c.shortcutMissing, isTrue,
          reason: 'a deleted Shortcut that delivers no cellular payload must '
              'flag missing so the reinstall card fires');
      expect(bridge.runShortcutCalls, 1);
      expect(c.hasEverReceived, isFalse);
      c.dispose();
      await bridge.close();
    });

    test('getReadingOnce: open succeeds AND a payload lands -> not missing',
        () async {
      final bridge = _FakeBridge()
        ..everReceived = false
        ..runShortcutResult = true;
      final c = CellularMonitorController(
        bridge: bridge,
        missingShortcutSettle: const Duration(milliseconds: 50),
      );
      await c.load();

      final bool opened =
          await c.getReadingOnce(triggerShortcutName: 'WLAN Pros Live');
      expect(opened, isTrue);
      bridge.push(_info(carrier: 'Delivered'));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(c.shortcutMissing, isFalse);
      expect(c.hasEverReceived, isTrue);
      expect(c.info!.carrier, 'Delivered');
      c.dispose();
      await bridge.close();
    });

    test('getReadingOnce: a previously-working Shortcut is NOT flagged missing',
        () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _info()
        ..runShortcutResult = true;
      final c = CellularMonitorController(
        bridge: bridge,
        missingShortcutSettle: const Duration(seconds: 30),
      );
      await c.load();

      final bool opened =
          await c.getReadingOnce(triggerShortcutName: 'WLAN Pros Live');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(opened, isTrue);
      expect(c.shortcutMissing, isFalse);
      c.dispose();
      await bridge.close();
    });

    test('startMonitoring (continuous): deleted Shortcut -> shortcutMissing fires',
        () async {
      final bridge = _FakeBridge()
        ..everReceived = false
        ..latest = null
        ..runShortcutResult = true;
      final c = CellularMonitorController(
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
