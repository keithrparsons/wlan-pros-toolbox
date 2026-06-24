// Wi-Fi monitoring state machine (TICKET-03 A2).
//
// Drives the Wi-Fi Details screen over the [WiFiDetailsBridge]. It owns the
// honest install-state branch, the one-shot pull, and the live push stream, so
// the widget stays thin and the state machine is unit-testable without a widget
// tree. Exposed as a [ChangeNotifier].
//
// Phases:
//   loading      -> resolving install-state + latest payload on first load.
//   needsInstall -> no payload has ever arrived: show install / how-to.
//   idleWithData -> at least one payload exists, live monitoring not running.
//   streaming    -> live monitoring running; cards update on each pushed payload.
//
// The one-shot path (run the Shortcut once -> single update) stays first-class:
// a payload delivered while idle moves the screen to [idleWithData] with data.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'wifi_details.dart';
import 'wifi_details_bridge.dart';

/// Lifecycle phases of the Wi-Fi Details screen.
enum WifiMonitorPhase {
  loading,
  needsInstall,
  idleWithData,
  streaming,
}

/// State machine for the Wi-Fi Details screen, over a [WiFiDetailsBridge].
class WifiMonitorController extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  WifiMonitorController({required WiFiDetailsBridge bridge}) : _bridge = bridge;

  final WiFiDetailsBridge _bridge;

  StreamSubscription<WiFiDetails>? _sub;

  /// Transient subscription for a [getReadingOnce] read: captures exactly one
  /// streamed payload and tears itself down, so a one-shot read never leaves a
  /// persistent live stream (or the iOS banner) running.
  StreamSubscription<WiFiDetails>? _oneShotSub;

  WifiMonitorPhase _phase = WifiMonitorPhase.loading;
  WiFiDetails? _details;
  bool _hasEverReceived = false;
  DateTime? _lastUpdated;
  bool _disposed = false;

  WifiMonitorPhase get phase => _phase;

  /// Most recent parsed details, or null when none has arrived yet.
  WiFiDetails? get details => _details;

  /// Whether any payload has ever arrived (honest install-state signal).
  bool get hasEverReceived => _hasEverReceived;

  /// True while the live push stream is being consumed.
  bool get isStreaming => _phase == WifiMonitorPhase.streaming;

  /// Wall-clock time of the most recent payload, for the "last updated" label.
  DateTime? get lastUpdated => _lastUpdated;

  /// Resolves install-state, the persisted monitoring flag, and the latest
  /// payload. Re-entrant: callable from the "I've installed it, run it" retry
  /// and from app-resume (the Shortcut bounces the app to the foreground).
  Future<void> load() async {
    if (_phase != WifiMonitorPhase.streaming) {
      _phase = WifiMonitorPhase.loading;
      _safeNotify();
    }

    final bool received = await _bridge.hasEverReceivedPayload();
    final WiFiDetails? latest = await _bridge.readLatest();
    final bool wasMonitoring = await _bridge.isMonitoringActive();

    _hasEverReceived = received || (latest != null && latest.hasAnyData);
    if (latest != null && latest.hasAnyData) {
      _details = latest;
      _lastUpdated ??= DateTime.now();
    }

    if (_phase == WifiMonitorPhase.streaming) {
      // A resume arrived mid-stream; keep streaming, data already refreshed.
      _safeNotify();
      return;
    }

    if (!_hasEverReceived) {
      _phase = WifiMonitorPhase.needsInstall;
    } else if (wasMonitoring) {
      // App relaunched while a loop was active -> resume listening.
      _startListening();
    } else {
      _phase = WifiMonitorPhase.idleWithData;
    }
    _safeNotify();
  }

  /// Begins live monitoring. The app never loops itself: the continuous stream
  /// comes from the RECURSIVE combined companion Shortcut. Start does two things,
  /// in order:
  ///   1. raises the App Group monitoring-active flag so the Shortcut's
  ///      `ShouldContinueMonitoringIntent` returns "keep going", and
  ///   2. fires the PLAIN, fire-and-forget run-shortcut trigger ONCE to kick off
  ///      the recursion ([triggerShortcutName]); each cycle the Shortcut delivers
  ///      a sample via the background `ReceiveLiveDetailsIntent`, posts a Darwin
  ///      notification, checks the flag, waits, and runs itself again. The plain
  ///      trigger does NOT make the app wait for the Shortcut to finish, so a
  ///      looping Shortcut never hangs the app.
  /// The app's only job from here is to passively consume [WiFiDetailsBridge.updates].
  ///
  /// The flag write and the stream subscription are kicked off synchronously
  /// (before the first `await`) so a tap-driven rebuild does not wait on a later
  /// microtask. When [triggerShortcutName] is null the trigger is skipped (the
  /// recursion is assumed already running, e.g. a relaunch-resumed loop).
  ///
  /// Returns false when the trigger could not be OPENED (Shortcuts missing / the
  /// Live Shortcut not installed); the caller surfaces the honest error and the
  /// install affordance. Returns true when no trigger was requested or iOS opened
  /// the trigger URL.
  Future<bool> startMonitoring({String? triggerShortcutName}) async {
    final Future<void> write = _bridge.setMonitoringActive(true);
    _startListening();
    _safeNotify();
    await write;
    if (triggerShortcutName == null) return true;
    return _bridge.runShortcut(triggerShortcutName);
  }

  /// ONE-SHOT live read (2026-06-23, Keith): fire the companion Shortcut ONCE,
  /// capture a single payload, and leave NO persistent monitoring loop behind —
  /// so the iOS status banner ("WLAN Pros" logo at the top) flashes for the one
  /// run and then clears on its own. This is the new DEFAULT live read; the
  /// continuous loop ([startMonitoring]) is demoted to an explicit opt-in.
  ///
  /// How it stays one-shot: unlike [startMonitoring] it does NOT raise the App
  /// Group monitoring-active flag. We CLEAR it first (defence against a stale
  /// `true` left by a prior crashed loop), so when the companion Shortcut runs
  /// its single cycle and consults `ShouldContinueMonitoringIntent`, it reads
  /// `false` and stops — no recursion, no persistent banner. The phase never
  /// enters [streaming]; a delivered payload lands the screen on [idleWithData].
  ///
  /// The single delivered payload is consumed two ways, whichever lands first:
  ///   * the live [updates] stream (the Darwin notification while foregrounded),
  ///     via a transient subscription that captures one payload and tears down;
  ///   * a [WiFiDetailsBridge.readLatest] poll after a short settle, in case the
  ///     stream sample raced the app's foreground return.
  /// Either way [_onPayload] records it and the screen rebuilds with real data.
  ///
  /// Returns false when the trigger could not be OPENED (Shortcuts missing / the
  /// Live Shortcut not installed) so the caller surfaces the honest setup card,
  /// exactly as [startMonitoring] does. Never enters a loop, never hangs.
  Future<bool> getReadingOnce({required String triggerShortcutName}) async {
    // Belt-and-suspenders: make sure no persistent loop flag survives. If a prior
    // crashed continuous session left the flag `true`, a fresh Shortcut run would
    // keep looping; clearing it first guarantees this read stays single-cycle.
    final Future<void> clearFlag = _bridge.setMonitoringActive(false);

    // Capture exactly one streamed payload without entering the streaming phase.
    // The transient subscription auto-cancels after the first sample so we never
    // hold an open live stream (that is the opt-in path's job).
    _oneShotSub?.cancel();
    _oneShotSub = _bridge.updates.listen((WiFiDetails d) {
      _onPayload(d);
      _oneShotSub?.cancel();
      _oneShotSub = null;
    });

    await clearFlag;
    final bool opened = await _bridge.runShortcut(triggerShortcutName);
    if (!opened) {
      _oneShotSub?.cancel();
      _oneShotSub = null;
    }
    return opened;
  }

  /// Polls the persisted App Group payload after a one-shot fire settles, in case
  /// the single streamed sample raced the app's foreground return (the Shortcut
  /// bounces the app, so the Darwin notification can fire while backgrounded).
  /// Records the payload via the same [_onPayload] path. No-op if a stream sample
  /// already landed (the read just refreshes to the same/newer value). Never
  /// throws; off-iOS [readLatest] returns null and this is a no-op.
  Future<void> pollLatestAfterOneShot() async {
    final WiFiDetails? latest = await _bridge.readLatest();
    if (latest != null && latest.hasAnyData) _onPayload(latest);
  }

  /// Stops live monitoring: fires the App Group flag clear, flips the phase, and
  /// tears down the subscription synchronously (all before the first `await`),
  /// then awaits. Clearing the flag first means the looping Shortcut halts on its
  /// next check; the last payload stays on screen.
  Future<void> stopMonitoring() async {
    final Future<void> write = _bridge.setMonitoringActive(false);
    final StreamSubscription<WiFiDetails>? sub = _sub;
    _sub = null;
    _phase = _hasEverReceived
        ? WifiMonitorPhase.idleWithData
        : WifiMonitorPhase.needsInstall;
    _safeNotify();
    await sub?.cancel();
    await write;
  }

  void _startListening() {
    _sub?.cancel();
    _phase = WifiMonitorPhase.streaming;
    _sub = _bridge.updates.listen(_onPayload);
  }

  void _onPayload(WiFiDetails d) {
    if (!d.hasAnyData) return;
    _details = d;
    _hasEverReceived = true;
    _lastUpdated = DateTime.now();
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _oneShotSub?.cancel();
    super.dispose();
  }
}
