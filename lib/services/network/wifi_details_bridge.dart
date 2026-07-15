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

/// A live run that was IN FLIGHT when the app last lost its scene.
///
/// Firing the companion Shortcut backgrounds the app into the Shortcuts app, and
/// iOS may tear down and rebuild the UIScene while we are away. Flutter then
/// restarts at its initial (home) route, and the ENTIRE Dart heap goes with it —
/// the tool screen, its state, and the in-flight measurement. The user tapped
/// "Check My Connection" and landed on Home with nothing to show for it.
///
/// This is the record that survives that, because it is written to the App Group
/// (below the app's lifecycle) at the instant the trigger fires. [route] says which
/// tool to put the user back on; [armedAt] says when the run started, which both
/// BOUNDS the restore (a stale arm is ignored, never obeyed) and DATES the evidence
/// (a payload stamped after [armedAt] belongs to THIS run — a stale reading from
/// the last time the phone was on Wi-Fi does not).
@immutable
class PendingLiveRun {
  const PendingLiveRun({required this.route, required this.armedAt});

  /// The named route of the tool that fired the trigger (e.g. `/tools/test-my-connection`).
  final String route;

  /// When the run armed — i.e. when it fired the Shortcut.
  final DateTime armedAt;

  /// How long an armed run stays restorable.
  ///
  /// SIZED TO THE ROUND-TRIP IT PROTECTS, not by feel. The one-shot trigger uses
  /// the `x-callback-url` form, so iOS re-foregrounds the app the moment the single
  /// Shortcut run FINISHES — a few seconds. The window has to cover that, plus a
  /// full app relaunch if iOS killed the process outright, plus a user who glanced
  /// at a notification on the way back.
  ///
  /// TWO MINUTES. Long enough that no realistic return path expires mid-walk; short
  /// enough that an app iOS killed and the user reopened NEXT MORNING is never
  /// dragged into a tool they did not ask for. The failure it must not have is
  /// "restores something the user has forgotten about" — and 2 minutes cannot reach
  /// that, while 30 seconds could plausibly cut off a slow cold relaunch.
  static const Duration restoreWindow = Duration(minutes: 2);

  /// Whether this armed run is still young enough to restore. An arm older than
  /// [restoreWindow] is dead: the user has moved on, and yanking them back into a
  /// tool would be the app hijacking their navigation, not recovering their run.
  bool isFresh({DateTime? now}) {
    final DateTime t = now ?? DateTime.now();
    final Duration age = t.difference(armedAt);
    // A negative age (clock moved backwards, or a stamp from the future) is not
    // evidence of freshness — it is evidence we cannot trust the clock. Fail safe.
    return !age.isNegative && age <= restoreWindow;
  }

  @override
  bool operator ==(Object other) =>
      other is PendingLiveRun &&
      other.route == route &&
      other.armedAt == armedAt;

  @override
  int get hashCode => Object.hash(route, armedAt);

  @override
  String toString() => 'PendingLiveRun($route, armed $armedAt)';
}

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

  /// Wall-clock time the native receiver intent STORED the most recent payload,
  /// or null when none has ever been stored (or off-iOS, where the channel has no
  /// handler).
  ///
  /// WHY THIS EXISTS (2026-07-14, Keith device — the live-feed regression).
  /// [WiFiDetails] carries no timestamp, so a payload read back from the App Group
  /// is indistinguishable from the STALE one stored months ago. That is why the
  /// Start-aware missing-Shortcut settle refused to poll the App Group at all: any
  /// stored reading would have "proved" the Shortcut ran and masked a real miss.
  ///
  /// But refusing to look made the check unsatisfiable. Firing the streaming
  /// trigger BACKGROUNDS the app into the Shortcuts app, and a backgrounded
  /// Flutter engine cannot receive the Darwin push — so the only evidence the
  /// settle would accept (a payload on the live [updates] stream) is evidence that
  /// by construction cannot arrive during the settle window. The settle therefore
  /// concluded "the Shortcut is missing" on a perfectly healthy Shortcut, and tore
  /// down the very loop it was checking on.
  ///
  /// A timestamp resolves the dilemma honestly: the settle can now ask the RIGHT
  /// question — "did a payload land AFTER this Start?" — which a stale reading can
  /// never answer yes to, and which a working Shortcut answers yes to even when it
  /// delivered while we were backgrounded. Neither blind nor credulous.
  Future<DateTime?> payloadReceivedAt() async {
    try {
      final int? ms = await _method.invokeMethod<int>('payloadReceivedAt');
      if (ms == null || ms <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.payloadReceivedAt failed: $e');
      return null;
    }
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

  /// Reads and CLEARS the transient "companion Shortcut not found on the last
  /// one-shot fire" marker (one-shot consume).
  ///
  /// The native side sets it when iOS invokes the one-shot `x-error` callback
  /// (`wlanprostoolbox://live-error`) — the reliable missing-Shortcut signal,
  /// fired when "WLAN Pros Live" was renamed/deleted — and at the same time
  /// resets the durable install-state. The controller calls this on each
  /// foreground load: a `true` drives the honest "Shortcut not found — re-run
  /// setup" recovery once, after which the marker is cleared and the tool returns
  /// to the normal one-time setup prompt. False off-iOS (no handler).
  Future<bool> consumeShortcutMissing() async {
    try {
      return await _method.invokeMethod<bool>('consumeShortcutMissing') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.consumeShortcutMissing failed: $e');
      return false;
    }
  }

  /// Records that the user has STARTED setup (tapped "Add the Shortcut"). Drives
  /// the post-install PRIMING step: until the first payload completes the
  /// round-trip, the live tools show "come back and tap Get reading; iOS asks
  /// permission the first time" instead of the cold "Set up live Wi-Fi" prompt.
  /// The native side clears it automatically when a payload arrives. No-op
  /// off-iOS.
  Future<void> markSetupInitiated() async {
    try {
      await _method.invokeMethod<void>('markSetupInitiated');
    } on MissingPluginException {
      // Non-iOS: no priming step.
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.markSetupInitiated failed: $e');
    }
  }

  /// Whether the user has started setup but no payload has completed the
  /// round-trip yet — drives the priming step ("tap Get reading to finish")
  /// instead of the cold setup prompt. False off-iOS / once a payload arrives.
  Future<bool> hasInitiatedSetup() async {
    try {
      return await _method.invokeMethod<bool>('hasInitiatedSetup') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.hasInitiatedSetup failed: $e');
      return false;
    }
  }

  /// Best-effort check of whether Apple's Shortcuts app is installed (Tom
  /// Hollingsworth: many users do not have it, so they fail before step one). Uses
  /// `canOpenURL("shortcuts://")` natively (`shortcuts` is whitelisted in
  /// LSApplicationQueriesSchemes). Returns true off-iOS / when the channel is
  /// absent so non-iOS onboarding is never falsely blocked — the gate is an iOS-
  /// only nudge, applied only where this returns an explicit false.
  Future<bool> isShortcutsAppInstalled() async {
    try {
      return await _method.invokeMethod<bool>('isShortcutsAppInstalled') ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.isShortcutsAppInstalled failed: $e');
      return true;
    }
  }

  /// Records the route name of the live tool that fired a one-shot trigger, so an
  /// x-error can route the user back to it (and its recovery card) rather than the
  /// home page iOS may rebuild the scene at. No-op off-iOS.
  Future<void> setLiveOriginRoute(String route) async {
    try {
      await _method.invokeMethod<void>('setLiveOriginRoute', route);
    } on MissingPluginException {
      // Non-iOS: no scene-rebuild strand to recover from.
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.setLiveOriginRoute failed: $e');
    }
  }

  /// One-shot consume of the pending x-error navigation. Returns the origin tool
  /// route to navigate to (empty string when none was recorded) when an x-error
  /// nav is pending, or null when none is — so the navigation gate no-ops on a
  /// normal foreground. Null off-iOS (no handler).
  Future<String?> consumeLiveErrorNav() async {
    try {
      return await _method.invokeMethod<String?>('consumeLiveErrorNav');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.consumeLiveErrorNav failed: $e');
      return null;
    }
  }

  /// ARMS the "a live run is in flight on [route]" marker in the App Group, at the
  /// moment the run fires its trigger. Until [clearLiveRun], a UIScene teardown is a
  /// RECOVERABLE event: the nav gate can route the user back and the tool can resume
  /// the run. No-op off-iOS (no scene teardown to survive).
  Future<void> armLiveRun(String route) async {
    try {
      await _method.invokeMethod<void>('armLiveRun', route);
    } on MissingPluginException {
      // Non-iOS: firing a tool never backgrounds the app, so no run is ever lost.
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.armLiveRun failed: $e');
    }
  }

  /// Reads the in-flight live run, or null when none is armed. NON-DESTRUCTIVE —
  /// the nav gate and then the tool each need it, in that order, so the read cannot
  /// consume it. The tool calls [clearLiveRun] once it has taken the run over.
  ///
  /// Null off-iOS (no handler), and null when the native side cannot DATE the arm —
  /// an arm we cannot bound is one we refuse to act on rather than one we trust.
  Future<PendingLiveRun?> pendingLiveRun() async {
    try {
      final Map<Object?, Object?>? raw =
          await _method.invokeMethod<Map<Object?, Object?>>('pendingLiveRun');
      if (raw == null) return null;
      final Object? route = raw['route'];
      final Object? atMs = raw['atMs'];
      if (route is! String || route.isEmpty) return null;
      if (atMs is! int || atMs <= 0) return null;
      return PendingLiveRun(
        route: route,
        armedAt: DateTime.fromMillisecondsSinceEpoch(atMs),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.pendingLiveRun failed: $e');
      return null;
    }
  }

  /// DISARMS the in-flight-run marker. Called on every CLEAN ending: the run
  /// completed, the run errored, or the user deliberately left the tool. After this,
  /// nothing drags the user back — which is exactly right, because there is no run
  /// to come back to. This is the call that makes "the marker is still set" MEAN
  /// "we did not exit cleanly". No-op off-iOS.
  Future<void> clearLiveRun() async {
    try {
      await _method.invokeMethod<void>('clearLiveRun');
    } on MissingPluginException {
      // Non-iOS: nothing was ever armed.
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.clearLiveRun failed: $e');
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

  /// Cold-start reset of the persisted Live monitoring loop state (Option B).
  /// Clears the monitoring-active flag AND its hard-cap start stamp. Called once
  /// from `main()` before any live screen can run, so a stale `true` left by a
  /// prior force-quit/crash mid-stream can neither keep an orphaned loop trusted
  /// nor suppress a legitimate new Start (the app-wide single-flight would
  /// otherwise ADOPT the phantom flag instead of firing the trigger). No-op
  /// off-iOS (no persisted loop state) and never throws.
  Future<void> resetMonitoringColdStart() async {
    try {
      await _method.invokeMethod<void>('resetMonitoringColdStart');
    } on MissingPluginException {
      // Non-iOS: no persisted loop state to reset.
    } on PlatformException catch (e) {
      debugPrint('WiFiDetailsBridge.resetMonitoringColdStart failed: $e');
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
