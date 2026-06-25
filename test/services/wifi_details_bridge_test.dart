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

  group('runShortcut (PLAIN fire-and-forget Live trigger)', () {
    test('invokes runShortcut with ONLY the name — no x-callback, no tool',
        () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return true;
      });
      final ok = await WiFiDetailsBridge().runShortcut('WLAN Pros Live');

      expect(ok, isTrue);
      expect(seen!.method, 'runShortcut');
      // ONLY the name is passed; the native side builds the PLAIN
      // `shortcuts://run-shortcut?name=…` URL (NOT the x-callback form, which
      // would make the app wait for the never-finishing Live Shortcut).
      final args = seen!.arguments as Map;
      expect(args['name'], 'WLAN Pros Live');
      // No tool / x-callback / x-success plumbing rides along anymore.
      expect(args.containsKey('tool'), isFalse);
      expect(args.keys.length, 1);
      // Defensive: nothing in the call mentions x-callback.
      expect(args.toString().contains('x-callback'), isFalse);
    });

    test('returns false when the platform could not open Shortcuts', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      expect(await WiFiDetailsBridge().runShortcut('X'), isFalse);
    });

    test('returns false when the plugin is missing (off-iOS)', () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(await WiFiDetailsBridge().runShortcut('X'), isFalse);
    });
  });

  group('runShortcutOneShot (x-callback ONE-SHOT trigger, auto-return)', () {
    test('invokes the distinct runShortcutOneShot method with the name',
        () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return true;
      });
      final ok =
          await WiFiDetailsBridge().runShortcutOneShot('WLAN Pros Live');

      expect(ok, isTrue);
      // The ONE-SHOT path uses a SEPARATE method from the plain streaming
      // trigger; the native side builds the x-callback form
      // (shortcuts://x-callback-url/run-shortcut?name=…&x-success=wlanprostoolbox://live-done)
      // so the single run AUTO-RETURNS to the app instead of stranding the user.
      expect(seen!.method, 'runShortcutOneShot');
      final args = seen!.arguments as Map;
      expect(args['name'], 'WLAN Pros Live');
      expect(args.keys.length, 1);
    });

    test('returns false when the platform could not open Shortcuts', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      expect(await WiFiDetailsBridge().runShortcutOneShot('X'), isFalse);
    });

    test('returns false when the plugin is missing (off-iOS)', () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(await WiFiDetailsBridge().runShortcutOneShot('X'), isFalse);
    });
  });
}
