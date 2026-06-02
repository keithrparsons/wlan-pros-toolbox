// Cellular Information bridge — Dart side of the iOS Shortcuts handoff
// (TICKET-02).
//
// Mirrors [WiFiDetailsBridge], scoped to the cellular payload and to a SINGLE
// one-shot read (streaming is a separate ticket). The companion Shortcut
// harvests the cellular branch of the stock "Get Network Details" action,
// assembles it into a JSON object, and hands that object to the native
// `ReceiveCellularDetailsIntent`. The iOS runner persists the JSON to a
// dedicated App Group key (separate from the Wi-Fi key) and the Dart side reads
// it back here.
//
// Two operations, both over the existing app-owned method channel
// `com.wlanpros.toolbox/shortcuts_bridge`:
//   1. PULL — [readLatest] reads the last cellular JSON the native side stored
//             and parses it to a [CellularInfo]. Used on first build and on
//             resume, since the Shortcut bounces the app to the foreground and
//             the receiver intent typically fired while we were backgrounded.
//   2. install-state — [hasEverReceivedPayload] reflects whether any cellular
//             payload has ever arrived, so the screen shows the install /
//             how-to onboarding before the first reading and data after.
//
// Off-iOS the channel has no handler; both calls degrade honestly (null /
// false), which the screen reports as the per-platform unavailable state. The
// install link is opened via [openUrl], shared with the Wi-Fi bridge's channel
// so the app keeps a single native surface and adds no URL-launcher plugin.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cellular_info.dart';

/// Bridges the native iOS Shortcuts cellular handoff to Dart, typed to
/// [CellularInfo].
class CellularInfoBridge {
  CellularInfoBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method = methodChannel ??
            const MethodChannel('com.wlanpros.toolbox/shortcuts_bridge'),
        _events = eventChannel ??
            const EventChannel(
                'com.wlanpros.toolbox/shortcuts_bridge/cellular_events');

  final MethodChannel _method;
  final EventChannel _events;

  /// Reads the most recent cellular payload the native receiver intent stored
  /// and parses it to a [CellularInfo], or null if nothing has been delivered
  /// yet (or the stored string is not a valid JSON object). Off-iOS returns null
  /// because the channel has no handler.
  Future<CellularInfo?> readLatest() async {
    final String? json = await _readLatestJson();
    if (json == null || json.isEmpty) return null;
    return CellularInfo.fromJsonString(json);
  }

  /// Whether the app has *ever* received a cellular payload from the companion
  /// Shortcut. iOS cannot query whether a Shortcut is installed, so install
  /// state is inferred honestly from this persisted App Group flag: `false` ->
  /// show the install / how-to onboarding; `true` -> the Shortcut demonstrably
  /// works, so show data. Off-iOS the channel has no handler and this returns
  /// false.
  Future<bool> hasEverReceivedPayload() async {
    try {
      return await _method
              .invokeMethod<bool>('hasEverReceivedCellularPayload') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('CellularInfoBridge.hasEverReceivedPayload failed: $e');
      return false;
    }
  }

  /// Sets the shared App Group monitoring-active flag (TICKET-05). The native
  /// [ShouldContinueMonitoringIntent] returns this value to the recursive
  /// companion Shortcut: `true` keeps the recursion running, `false` stops it.
  /// The flag is SHARED with the Wi-Fi bridge (only one tool streams at a time),
  /// so the same `setMonitoringActive` method channel call is used. No-op
  /// off-iOS.
  Future<void> setMonitoringActive(bool active) async {
    try {
      await _method.invokeMethod<void>('setMonitoringActive', active);
    } on MissingPluginException {
      // Non-iOS: no recursion to gate.
    } on PlatformException catch (e) {
      debugPrint('CellularInfoBridge.setMonitoringActive failed: $e');
    }
  }

  /// Reads the persisted shared monitoring-active flag (TICKET-05). Lets the
  /// screen resume the live state after a relaunch mid-stream. False off-iOS.
  Future<bool> isMonitoringActive() async {
    try {
      return await _method.invokeMethod<bool>('isMonitoringActive') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('CellularInfoBridge.isMonitoringActive failed: $e');
      return false;
    }
  }

  /// Opens an external URL (the iCloud companion-Shortcut link). Routed through
  /// the existing app-owned channel so the app keeps a single native surface and
  /// adds no URL-launcher plugin. Returns false when the platform could not open
  /// the URL (or off-iOS where the channel is absent).
  Future<bool> openUrl(String url) async {
    try {
      return await _method.invokeMethod<bool>('openUrl', url) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('CellularInfoBridge.openUrl failed: $e');
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
  /// missing, or off-iOS where the channel is absent). A true result means iOS
  /// opened the URL, not that the Shortcut finished (it never does, by design).
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
      debugPrint('CellularInfoBridge.runShortcut failed: $e');
      return false;
    }
  }

  /// Stream of parsed [CellularInfo] pushed when a Darwin notification fires
  /// while the app is foregrounded (TICKET-05). The recursive companion
  /// Shortcut delivers one cellular sample per cycle via the background
  /// [ReceiveCellularDetailsIntent], which stores the JSON to the App Group
  /// cellular key and posts the shared Darwin notification; the native cellular
  /// event channel re-reads that cellular key and pushes the JSON here.
  /// Unparseable / empty payloads are dropped (never surfaced as an error) so
  /// the screen's stream never tears down on a transient delivery. Off-iOS the
  /// channel has no handler and the stream stays empty.
  Stream<CellularInfo> get updates => _events
      .receiveBroadcastStream()
      .map<String>((dynamic e) => e?.toString() ?? '')
      .where((String s) => s.isNotEmpty)
      .map<CellularInfo?>(CellularInfo.fromJsonString)
      .where((CellularInfo? d) => d != null && d.hasAnyData)
      .cast<CellularInfo>()
      .handleError((Object error) {
        debugPrint('CellularInfoBridge event stream error: $error');
      });

  Future<String?> _readLatestJson() async {
    try {
      return await _method.invokeMethod<String>('readLatestCellular');
    } on MissingPluginException {
      // Channel not registered (non-iOS, or runner not yet built). Honest.
      return null;
    } on PlatformException catch (e) {
      debugPrint('CellularInfoBridge.readLatest failed: $e');
      return null;
    }
  }
}
