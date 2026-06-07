// Unit tests for [WifiSignalSampler] — the shared live-RF sampler behind the
// Test My Connection "Wi-Fi signal" card.
//
// FOCUS: the iOS first-run bug (2026-06-07). The underlying
// [WifiMonitorController.load] resumes its phase to `streaming` whenever the
// persisted App Group monitoring flag is still set — even when that flag is a
// STALE leftover from a prior session whose looping companion Shortcut was
// killed without a clean Stop (the flag is only cleared by stop, not dispose).
// On that resume the controller re-subscribes passively but never re-fires the
// recursive Shortcut, so no producer exists and no sample arrives. The sampler
// must NOT report that phantom as live: [isStreaming] is true only after a
// deliberate in-session [start], so the Test My Connection card falls back to
// the actionable Start control instead of a dead "LIVE" header.
//
// No native channel is touched — an in-memory fake bridge stands in.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';

/// In-memory fake of [WiFiDetailsBridge] modeling the App Group persisted state.
class _FakeBridge extends WiFiDetailsBridge {
  _FakeBridge({
    this.everReceived = true,
    this.monitoringFlag = false,
    this.latest,
  });

  final StreamController<WiFiDetails> _events =
      StreamController<WiFiDetails>.broadcast();

  bool everReceived;
  bool monitoringFlag;
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
  Stream<WiFiDetails> get updates => _events.stream;

  void push(WiFiDetails d) => _events.add(d);

  Future<void> close() => _events.close();
}

WiFiDetails _details({String ssid = 'KeithNet', int rssi = -55}) => WiFiDetails(
  ssid: ssid,
  bssid: 'a4:83:e7:00:11:22',
  rssi: rssi,
  noise: -90,
  channel: 36,
  standard: '802.11ax - Wi-Fi 6',
  rxRate: 780,
  txRate: 866,
);

void main() {
  group('iOS first-run stuck-LIVE fix', () {
    test(
      'a STALE persisted monitoring flag does NOT present as live on load — '
      'no in-session start means the card shows Start, not a dead LIVE',
      () async {
        // First-run condition: a prior session left the App Group flag set, and
        // a payload was received before, but no Shortcut is actually looping now.
        final bridge = _FakeBridge(
          everReceived: true,
          monitoringFlag: true,
          latest: _details(),
        );
        final sampler = WifiSignalSampler(
          source: WifiInfoSource.iosShortcuts,
          iosBridge: bridge,
        );

        await sampler.load();

        // The sampler must NOT claim to be streaming — nothing was started this
        // session, so there is no live producer behind a "LIVE" header.
        expect(sampler.isStreaming, isFalse);
        // It actively clears the stale flag so the loop cannot be misread as
        // alive on a later resume either.
        expect(bridge.lastMonitoringValue, isFalse);

        sampler.dispose();
        await bridge.close();
      },
    );

    test(
      'no auto-fire on load — the companion Shortcut is never run during load '
      '(the bounce gotcha stays avoided)',
      () async {
        final bridge = _FakeBridge(
          everReceived: true,
          monitoringFlag: true,
          latest: _details(),
        );
        final sampler = WifiSignalSampler(
          source: WifiInfoSource.iosShortcuts,
          iosBridge: bridge,
        );

        await sampler.load();

        // load() must never invoke the Shortcut — that auto-fire is exactly the
        // app-bounce regression GL-008 / the project memory warns against.
        expect(bridge.runShortcutCalls, 0);

        sampler.dispose();
        await bridge.close();
      },
    );

    test(
      'a deliberate in-session start DOES present as live and fires the '
      'Shortcut exactly once',
      () async {
        final bridge = _FakeBridge(everReceived: true, latest: _details());
        final sampler = WifiSignalSampler(
          source: WifiInfoSource.iosShortcuts,
          iosBridge: bridge,
        );
        await sampler.load();
        expect(sampler.isStreaming, isFalse); // idle before the tap

        await sampler.start();

        expect(sampler.isStreaming, isTrue);
        expect(bridge.runShortcutCalls, 1);
        expect(bridge.lastMonitoringValue, isTrue);

        sampler.dispose();
        await bridge.close();
      },
    );

    test('stop ends the live state and clears the in-session start', () async {
      final bridge = _FakeBridge(everReceived: true, latest: _details());
      final sampler = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
      );
      await sampler.load();
      await sampler.start();
      expect(sampler.isStreaming, isTrue);

      await sampler.stop();

      expect(sampler.isStreaming, isFalse);
      expect(bridge.lastMonitoringValue, isFalse);

      sampler.dispose();
      await bridge.close();
    });
  });
}
