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
  // The named params are clean (no leading underscore); the private fields
  // mirror them, so the initializing-formal lint does not apply.
  // ignore_for_file: prefer_initializing_formals
  WifiMonitorController({
    required WiFiDetailsBridge bridge,
    Duration missingShortcutSettle = const Duration(seconds: 4),
  })  : _bridge = bridge,
        _missingShortcutSettle = missingShortcutSettle;

  final WiFiDetailsBridge _bridge;

  /// How long to wait after a successful trigger OPEN before concluding the
  /// companion Shortcut is missing/deleted. iOS reports `open` success when it
  /// merely launched the Shortcuts app — even for a Shortcut the user deleted —
  /// so the open boolean alone cannot detect a missing Shortcut. A real run
  /// delivers a payload within ~1s; this window gives the round-trip headroom
  /// before the missing-Shortcut verdict fires. Injectable so tests run fast.
  final Duration _missingShortcutSettle;

  StreamSubscription<WiFiDetails>? _sub;

  /// Transient subscription for a [getReadingOnce] read: captures exactly one
  /// streamed payload and tears itself down, so a one-shot read never leaves a
  /// persistent live stream (or the iOS banner) running.
  StreamSubscription<WiFiDetails>? _oneShotSub;

  /// Cancellable settle timer for the missing-Shortcut verdict. Cancelled on
  /// dispose and on a fresh attempt so a pending settle never outlives the
  /// screen or flips [shortcutMissing] after disposal.
  Timer? _missingTimer;

  WifiMonitorPhase _phase = WifiMonitorPhase.loading;
  WiFiDetails? _details;
  bool _hasEverReceived = false;
  DateTime? _lastUpdated;
  bool _disposed = false;
  bool _shortcutMissing = false;

  WifiMonitorPhase get phase => _phase;

  /// Most recent parsed details, or null when none has arrived yet.
  WiFiDetails? get details => _details;

  /// Whether any payload has ever arrived (honest install-state signal).
  bool get hasEverReceived => _hasEverReceived;

  /// True once a trigger OPENED successfully but delivered NO payload within the
  /// settle window on a first-ever run — i.e. the companion "WLAN Pros Live"
  /// Shortcut is missing/deleted (iOS only launched the Shortcuts app).
  ///
  /// Why a flag and not just the [getReadingOnce] / [startMonitoring] return:
  /// iOS reports the trigger `open` as a success even for a DELETED Shortcut, so
  /// the only honest missing-signal is "opened but nothing ever arrived." Waiting
  /// for that inside the call would stall the happy-path one-shot (where the
  /// stream delivers a beat later). Instead the call returns promptly on the
  /// open result and this flag flips asynchronously after the settle, so the
  /// screen's in-tool reinstall card fires WITHOUT delaying a working read.
  /// A delivered payload clears it. The screens OR this into their `triggerError`
  /// presentation, so the same reinstall card serves both the open-failed and the
  /// deleted-Shortcut cases.
  bool get shortcutMissing => _shortcutMissing;

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
  /// Returns false ONLY when iOS could not OPEN the trigger (Shortcuts app
  /// absent). When the trigger opens, the call returns true promptly; the
  /// SEPARATE deleted-Shortcut case (it opened but, on a first-ever run, no
  /// payload arrives within [_missingShortcutSettle]) flips [shortcutMissing]
  /// asynchronously so a working stream is never stalled. Either way the screen
  /// surfaces the honest reinstall card (it ORs [shortcutMissing] into its
  /// `triggerError`). Also returns true when no trigger was requested (a resume,
  /// where the recursion is already running).
  Future<bool> startMonitoring({String? triggerShortcutName}) async {
    final Future<void> write = _bridge.setMonitoringActive(true);
    _startListening();
    _safeNotify();
    await write;
    if (triggerShortcutName == null) return true;
    final bool opened = await _bridge.runShortcut(triggerShortcutName);
    if (!opened) return false;
    // Returned promptly; the missing-Shortcut verdict (deleted Shortcut that
    // opened but never delivered) flips [shortcutMissing] asynchronously so a
    // working stream is never stalled by the settle.
    _verifyShortcutDelivered();
    return true;
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
  /// Returns false ONLY when iOS could not OPEN the trigger (Shortcuts app
  /// absent). When the trigger opens, the call returns true promptly; the
  /// SEPARATE missing-Shortcut case (it opened but a deleted Shortcut delivered
  /// nothing) is surfaced asynchronously via [shortcutMissing] after the settle,
  /// so a working one-shot read is never stalled. Either way the caller's
  /// reinstall / setup card fires (the screen ORs [shortcutMissing] into its
  /// `triggerError`). Never enters a loop, never hangs.
  Future<bool> getReadingOnce({required String triggerShortcutName}) async {
    // Belt-and-suspenders: make sure no persistent loop flag survives. If a prior
    // crashed continuous session left the flag `true`, a fresh Shortcut run would
    // keep looping; clearing it first guarantees this read stays single-cycle.
    final Future<void> clearFlag = _bridge.setMonitoringActive(false);

    // A fresh attempt clears any prior missing verdict (and any in-flight settle)
    // so the card does not linger from a previous run.
    _missingTimer?.cancel();
    _missingTimer = null;
    if (_shortcutMissing) {
      _shortcutMissing = false;
      _safeNotify();
    }

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
    // ONE-SHOT uses the x-callback form so the SINGLE run AUTO-RETURNS to the app
    // (x-success=wlanprostoolbox://live-done) instead of stranding the user on the
    // Shortcuts page. Safe here because the monitoring flag was just cleared, so
    // the Shortcut's ShouldContinueMonitoringIntent reads false and the run
    // finishes (which is what fires the return). Streaming stays on the plain
    // fire-and-forget form (it never finishes).
    final bool opened = await _bridge.runShortcutOneShot(triggerShortcutName);
    if (!opened) {
      _oneShotSub?.cancel();
      _oneShotSub = null;
      return false;
    }
    // The trigger opened; verify a payload actually arrives WITHOUT blocking the
    // return (a deleted Shortcut opens "successfully" but delivers nothing).
    _verifyShortcutDelivered();
    return true;
  }

  /// After a trigger OPENED, arm a settle timer that flips [shortcutMissing] if
  /// no payload arrives. Returns immediately so it never stalls the caller.
  ///
  /// iOS reports `open` success when it merely surfaced the Shortcuts app, so a
  /// DELETED Shortcut opens "successfully" yet never delivers a payload — the
  /// silent failure that stranded users who removed "WLAN Pros Live" (the in-tool
  /// reinstall card never fired). This closes that gap: if the app has ALREADY
  /// received a payload at some point, the Shortcut demonstrably works, so a
  /// transient miss is not surfaced as a reinstall prompt (no nagging working
  /// users). Only on a FIRST-EVER run do we settle for [_missingShortcutSettle]
  /// and, if still nothing arrived, conclude the Shortcut is missing.
  void _verifyShortcutDelivered() {
    if (_hasEverReceived) return;
    // A cancellable timer (not a bare Future.delayed) so dispose / a fresh
    // attempt can tear it down — a pending settle must never outlive the screen
    // or flip the flag after disposal.
    _missingTimer?.cancel();
    _missingTimer = Timer(_missingShortcutSettle, () async {
      _missingTimer = null;
      if (_disposed) return;
      // A streamed sample or a persisted App Group payload landing during the
      // settle proves the Shortcut ran. Poll the App Group too, in case the
      // single delivery raced the app's foreground return (the Darwin
      // notification can fire while backgrounded).
      if (!_hasEverReceived) {
        final WiFiDetails? latest = await _bridge.readLatest();
        if (_disposed) return;
        if (latest != null && latest.hasAnyData) _onPayload(latest);
      }
      if (_hasEverReceived) return;
      // Nothing ever arrived on a first-ever run: the named Shortcut is missing.
      _oneShotSub?.cancel();
      _oneShotSub = null;
      _shortcutMissing = true;
      _safeNotify();
    });
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
    // A real payload disproves any pending missing-Shortcut verdict and makes the
    // settle moot — cancel it so no timer lingers.
    _missingTimer?.cancel();
    _missingTimer = null;
    _shortcutMissing = false;
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _missingTimer?.cancel();
    _sub?.cancel();
    _oneShotSub?.cancel();
    super.dispose();
  }
}
