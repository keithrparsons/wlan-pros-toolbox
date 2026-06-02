// Wi-Fi Details bridge — Dart side of the iOS Shortcuts handoff (TICKET-02).
//
// Production replacement for the TICKET-01 throwaway `ShortcutsBridgeService`.
// Same device-verified plumbing, now typed to the normalized [WiFiDetails]
// model instead of a raw snapshot.
//
// The companion Shortcut harvests the connected AP's RF metrics via the stock
// "Get Network Details" action, assembles them into a JSON object, and hands
// that object to the native `ReceiveWiFiDetailsIntent`. The iOS runner persists
// the JSON to an App Group shared UserDefaults key and posts a Darwin
// notification (see ios/Runner/ShortcutsBridge.swift). This service is the Dart
// consumer of that handoff:
//
//   1. PULL  — [readLatest] reads the last JSON the native side stored and
//              parses it to a [WiFiDetails]. Used on first build and on resume,
//              since the Shortcut bounces the app to the foreground and the
//              receiver intent typically fired while we were backgrounded.
//   2. PUSH  — [updates] streams parsed [WiFiDetails] as the Darwin notification
//              fires while the app is already foregrounded.
//
// Both resolve the same App Group key, so they cannot disagree. Off-iOS the
// platform channels have no handler; [readLatest] returns null and [updates]
// stays empty, which the screen reports as the honest per-platform state.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'shortcut_trigger_result.dart';
import 'wifi_details.dart';

/// Bridges the native iOS Shortcuts Wi-Fi handoff to Dart, typed to
/// [WiFiDetails].
class WiFiDetailsBridge {
  WiFiDetailsBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    EventChannel? triggerResultChannel,
  })  : _method = methodChannel ??
            const MethodChannel('com.wlanpros.toolbox/shortcuts_bridge'),
        _events = eventChannel ??
            const EventChannel('com.wlanpros.toolbox/shortcuts_bridge/events'),
        _triggerResults = triggerResultChannel ??
            const EventChannel(
                'com.wlanpros.toolbox/shortcuts_bridge/trigger_result');

  final MethodChannel _method;
  final EventChannel _events;
  final EventChannel _triggerResults;

  /// Reads the most recent payload the native receiver intent stored and parses
  /// it to a [WiFiDetails], or null if nothing has been delivered yet (or the
  /// stored string is not a valid JSON object). Off-iOS returns null because the
  /// channel has no handler.
  Future<WiFiDetails?> readLatest() async {
    final String? json = await _readLatestJson();
    if (json == null || json.isEmpty) return null;
    return WiFiDetails.fromJsonString(json);
  }

  /// Whether the app has *ever* received a payload from the companion Shortcut
  /// (TICKET-03 A1). iOS cannot query whether a Shortcut is installed, so
  /// install-state is inferred honestly from this persisted App Group flag:
  /// `false` -> show the install / how-to onboarding; `true` -> the Shortcut
  /// demonstrably works, so show data. Off-iOS the channel has no handler and
  /// this returns false.
  Future<bool> hasEverReceivedPayload() async {
    try {
      return await _method.invokeMethod<bool>('hasEverReceivedPayload') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.hasEverReceivedPayload failed: $e');
      return false;
    }
  }

  /// Sets the App Group monitoring-active flag (TICKET-03 A2/A3). The native
  /// [ShouldContinueMonitoringIntent] returns this value to a looping companion
  /// Shortcut: `true` keeps the loop running, `false` stops it. The app writes
  /// `true` on Start and `false` on Stop. No-op off-iOS.
  Future<void> setMonitoringActive(bool active) async {
    try {
      await _method.invokeMethod<void>('setMonitoringActive', active);
    } on MissingPluginException {
      // Non-iOS: no loop to gate.
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.setMonitoringActive failed: $e');
    }
  }

  /// Reads the persisted monitoring-active flag (TICKET-03 A2/A3). Lets the
  /// screen resume the live state after a relaunch mid-loop. False off-iOS.
  Future<bool> isMonitoringActive() async {
    try {
      return await _method.invokeMethod<bool>('isMonitoringActive') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.isMonitoringActive failed: $e');
      return false;
    }
  }

  /// Opens an external URL (the iCloud companion-Shortcut link, TICKET-03 A1).
  /// Routed through the existing app-owned channel so the app keeps a single
  /// native surface and adds no URL-launcher plugin. Returns false when the
  /// platform could not open the URL (or off-iOS where the channel is absent).
  Future<bool> openUrl(String url) async {
    try {
      return await _method.invokeMethod<bool>('openUrl', url) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.openUrl failed: $e');
      return false;
    }
  }

  /// Fires the one-tap Shortcut trigger (TICKET-03): builds and opens the
  /// `shortcuts://x-callback-url/run-shortcut` URL for the Shortcut named
  /// [name], encoding the originating [tool] id so the return can deep-link back
  /// to that tool's screen. The name and callback targets are URL-encoded
  /// natively. iOS flicks to Shortcuts, runs the one-shot Shortcut (which stores
  /// JSON to the App Group via [ReceiveWiFiDetailsIntent]), then returns to
  /// `wlanprostoolbox://reading?tool=<tool>&status=ok|err`. The result of that
  /// return arrives on [triggerEvents] / [triggerResults]; the fresh data lands
  /// via [readLatest] on resume.
  ///
  /// Returns false when the platform could not open the URL (Shortcuts app
  /// missing, or off-iOS where the channel is absent) — the caller falls back to
  /// the install affordance.
  Future<bool> runShortcut(String name, {required String tool}) async {
    try {
      return await _method.invokeMethod<bool>(
            'runShortcut',
            <String, String>{'name': name, 'tool': tool},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.runShortcut failed: $e');
      return false;
    }
  }

  /// Broadcast stream of decoded one-tap trigger returns (TICKET-03), each
  /// carrying the originating tool id + outcome. The native SceneDelegate parses
  /// the `wlanprostoolbox://reading?tool=…&status=…` return URL and pushes the
  /// wire string `"<tool>|<ok|err>"`; on a cold relaunch the native side buffers
  /// it and replays it the instant this stream is listened to. The deep-link
  /// router consumes this to navigate to the originating tool. Off-iOS the
  /// channel has no handler and the stream stays empty.
  ///
  /// Broadcast so both the per-screen [triggerResults] view and the top-level
  /// deep-link router can subscribe to the one underlying native channel.
  Stream<ShortcutTriggerEvent> get triggerEvents =>
      _triggerEvents ??= _triggerResults
          .receiveBroadcastStream()
          .map<String>((dynamic e) => e?.toString() ?? '')
          .where((String s) => s.isNotEmpty)
          .map<ShortcutTriggerEvent>(ShortcutTriggerEvent.fromNative)
          .handleError((Object error) {
            debugPrint('WiFiDetailsBridge trigger-event stream error: $error');
          })
          .asBroadcastStream();
  Stream<ShortcutTriggerEvent>? _triggerEvents;

  /// Stream of x-callback results from the one-tap trigger (TICKET-03), reduced
  /// to the outcome only. Derived from [triggerEvents] so screens that only care
  /// whether the run succeeded keep their existing API.
  Stream<ShortcutTriggerResult> get triggerResults =>
      triggerEvents.map<ShortcutTriggerResult>((e) => e.result);

  /// Stream of parsed [WiFiDetails] pushed when the Darwin notification fires
  /// while the app is foregrounded. Unparseable payloads are dropped (never
  /// surfaced as an error) so the screen's StreamBuilder never tears down on a
  /// transient or malformed delivery.
  Stream<WiFiDetails> get updates => _events
      .receiveBroadcastStream()
      .map<String>((dynamic e) => e?.toString() ?? '')
      .where((String s) => s.isNotEmpty)
      .map<WiFiDetails?>(WiFiDetails.fromJsonString)
      .where((WiFiDetails? d) => d != null && d.hasAnyData)
      .cast<WiFiDetails>()
      .handleError((Object error) {
        debugPrint('WiFiDetailsBridge event stream error: $error');
      });

  Future<String?> _readLatestJson() async {
    try {
      return await _method.invokeMethod<String>('readLatest');
    } on MissingPluginException {
      // Channel not registered (non-iOS, or runner not yet built). Honest.
      return null;
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.readLatest failed: $e');
      return null;
    }
  }
}
