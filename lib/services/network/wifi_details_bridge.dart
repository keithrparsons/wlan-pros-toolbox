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

import 'wifi_details.dart';

/// Bridges the native iOS Shortcuts Wi-Fi handoff to Dart, typed to
/// [WiFiDetails].
class WiFiDetailsBridge {
  WiFiDetailsBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method = methodChannel ??
            const MethodChannel('com.wlanpros.toolbox/shortcuts_bridge'),
        _events = eventChannel ??
            const EventChannel('com.wlanpros.toolbox/shortcuts_bridge/events');

  final MethodChannel _method;
  final EventChannel _events;

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

  /// Fires the combined Live Shortcut trigger: opens the PLAIN, fire-and-forget
  /// `shortcuts://run-shortcut?name=<enc>` URL for the Shortcut named [name]. The
  /// name is URL-encoded natively.
  ///
  /// This is deliberately NOT the `x-callback-url` form. The x-callback variant
  /// makes the app WAIT for the Shortcut to finish; the looping Live Shortcut
  /// never finishes, so the app would hang. The plain form hands the Shortcut off
  /// and returns immediately, after which the app passively consumes [updates].
  ///
  /// Returns false when the platform could not OPEN the URL (Shortcuts app
  /// missing, or off-iOS where the channel is absent) — the caller surfaces the
  /// honest error + install affordance. A true result means iOS opened the URL,
  /// not that the Shortcut finished (it never does, by design).
  Future<bool> runShortcut(String name) async {
    try {
      return await _method.invokeMethod<bool>(
            'runShortcut',
            <String, String>{'name': name},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.runShortcut failed: $e');
      return false;
    }
  }

  /// Fires the ONE-SHOT Live trigger: opens the `x-callback-url` form
  /// `shortcuts://x-callback-url/run-shortcut?name=<enc>&x-success=<scheme>://live-done`
  /// for the Shortcut named [name]. The name is URL-encoded natively.
  ///
  /// Unlike [runShortcut] (the plain STREAMING trigger), this asks iOS to return
  /// control to the app via the registered `wlanprostoolbox://live-done` scheme
  /// the moment the SINGLE run FINISHES. That auto-return is what stops a one-shot
  /// read (Get reading, auto-capture, the first read right after install) from
  /// stranding the user on the Shortcuts page. It is only safe for a NON-looping
  /// run: the app must NOT raise the monitoring flag before calling this, so the
  /// Shortcut's `ShouldContinueMonitoringIntent` reads false and the run finishes.
  ///
  /// Returns false when the platform could not OPEN the URL (Shortcuts app
  /// missing, or off-iOS where the channel is absent). A true result means iOS
  /// opened the URL, not that the Shortcut finished.
  Future<bool> runShortcutOneShot(String name) async {
    try {
      return await _method.invokeMethod<bool>(
            'runShortcutOneShot',
            <String, String>{'name': name},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.runShortcutOneShot failed: $e');
      return false;
    }
  }

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
