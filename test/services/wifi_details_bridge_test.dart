// Unit tests for the TICKET-03 additions to WiFiDetailsBridge.
//
// Exercises the new method-channel calls (hasEverReceivedPayload,
// setMonitoringActive, isMonitoringActive, openUrl) and their honest
// MissingPluginException fallbacks. No real native side is involved — the
// platform channel is mocked.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel =
      MethodChannel('com.wlanpros.toolbox/shortcuts_bridge');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('hasEverReceivedPayload', () {
    test('reflects the native flag', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return call.method == 'hasEverReceivedPayload' ? true : null;
      });
      expect(await WiFiDetailsBridge().hasEverReceivedPayload(), isTrue);
    });

    test('defaults to false on null', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await WiFiDetailsBridge().hasEverReceivedPayload(), isFalse);
    });

    test('returns false when the plugin is missing (off-iOS)', () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(await WiFiDetailsBridge().hasEverReceivedPayload(), isFalse);
    });
  });

  group('monitoring flag', () {
    test('setMonitoringActive forwards the bool argument', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final bridge = WiFiDetailsBridge();
      await bridge.setMonitoringActive(true);
      await bridge.setMonitoringActive(false);

      expect(calls.map((c) => c.method),
          everyElement('setMonitoringActive'));
      expect(calls[0].arguments, true);
      expect(calls[1].arguments, false);
    });

    test('isMonitoringActive reflects the native flag', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return call.method == 'isMonitoringActive' ? true : null;
      });
      expect(await WiFiDetailsBridge().isMonitoringActive(), isTrue);
    });

    test('isMonitoringActive returns false when plugin missing', () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(await WiFiDetailsBridge().isMonitoringActive(), isFalse);
    });
  });

  group('openUrl', () {
    test('forwards the url and returns success', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return true;
      });
      final ok = await WiFiDetailsBridge().openUrl('https://example.com/x');

      expect(ok, isTrue);
      expect(seen!.method, 'openUrl');
      expect(seen!.arguments, 'https://example.com/x');
    });

    test('returns false when the platform could not open it', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      expect(await WiFiDetailsBridge().openUrl('bad://x'), isFalse);
    });

    test('returns false when the plugin is missing (off-iOS)', () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(await WiFiDetailsBridge().openUrl('https://x'), isFalse);
    });
  });

  group('runShortcut (one-tap trigger, TICKET-03)', () {
    test('invokes runShortcut with the Shortcut name AND originating tool',
        () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return true;
      });
      final ok = await WiFiDetailsBridge()
          .runShortcut('WLAN Pros Wi-Fi', tool: 'wifi-info');

      expect(ok, isTrue);
      expect(seen!.method, 'runShortcut');
      // The name + tool are passed as a map; the native side URL-encodes them
      // into the run-shortcut x-callback URL, encoding the tool into the
      // x-success / x-error callback targets so the return deep-links back to
      // the originating tool screen (TICKET-03 UX fix).
      expect(seen!.arguments, <String, String>{
        'name': 'WLAN Pros Wi-Fi',
        'tool': 'wifi-info',
      });
    });

    test('returns false when the platform could not open Shortcuts', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      expect(
        await WiFiDetailsBridge().runShortcut('X', tool: 'wifi-info'),
        isFalse,
      );
    });

    test('returns false when the plugin is missing (off-iOS)', () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(
        await WiFiDetailsBridge().runShortcut('X', tool: 'wifi-info'),
        isFalse,
      );
    });
  });
}
