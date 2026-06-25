// Cellular monitoring state machine (TICKET-05).
//
// Mirrors [WifiMonitorController], typed to [CellularInfo], over the
// [CellularInfoBridge]. Drives the Cellular Information Live mode: the honest
// install-state branch, the one-shot pull, and the live push stream fed by the
// recursive companion Shortcut. Exposed as a [ChangeNotifier] so the widget
// stays thin and the state machine is unit-testable without a widget tree.
//
// Phases:
//   loading      -> resolving install-state + latest payload on first load.
//   needsInstall -> no payload has ever arrived: show install / how-to.
//   idleWithData -> at least one payload exists, live monitoring not running.
//   streaming    -> live monitoring running; the screen updates on each push.
//
// The app NEVER loops itself: the continuous stream comes from the recursive
// companion Shortcut, which delivers one cellular sample per cycle via the
// background Receive intent and checks the shared monitoring flag. The
// controller's only jobs are to set/clear the flag, fire the trigger once on
// Start to kick off the recursion, and passively consume the bridge updates.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cellular_info.dart';
import 'cellular_info_bridge.dart';

/// Lifecycle phases of the Cellular Information Live mode.
enum CellularMonitorPhase {
  loading,
  needsInstall,
  idleWithData,
  streaming,
}

/// State machine for the Cellular Information Live mode, over a
/// [CellularInfoBridge].
class CellularMonitorController extends ChangeNotifier {
  // The named params are clean (no leading underscore); the private fields
  // mirror them, so the initializing-formal lint does not apply.
  // ignore_for_file: prefer_initializing_formals
  CellularMonitorController({
    required CellularInfoBridge bridge,
    Duration missingShortcutSettle = const Duration(seconds: 4),
  })  : _bridge = bridge,
        _missingShortcutSettle = missingShortcutSettle;

  final CellularInfoBridge _bridge;

  /// How long to wait after a successful trigger OPEN before concluding the
  /// companion Shortcut is missing/deleted. iOS reports `open` success when it
  /// merely launched the Shortcuts app — even for a Shortcut the user deleted —
  /// so the open boolean alone cannot detect a missing Shortcut. A real run
  /// delivers a payload within ~1s; this window gives the round-trip headroom
  /// before the missing-Shortcut verdict fires. Injectable so tests run fast.
  final Duration _missingShortcutSettle;

  StreamSubscription<CellularInfo>? _sub;

  /// Transient subscription for a [getReadingOnce] read: captures exactly one
  /// streamed payload and tears itself down, so a one-shot read never leaves a
  /// persistent live stream (or the iOS banner) running.
  StreamSubscription<CellularInfo>? _oneShotSub;

  /// Cancellable settle timer for the missing-Shortcut verdict. Cancelled on
  /// dispose and on a fresh attempt so a pending settle never outlives the
  /// screen or flips [shortcutMissing] after disposal.
  Timer? _missingTimer;

  CellularMonitorPhase _phase = CellularMonitorPhase.loading;
  CellularInfo? _info;
  bool _hasEverReceived = false;
  DateTime? _lastUpdated;
  bool _disposed = false;
  bool _shortcutMissing = false;

  CellularMonitorPhase get phase => _phase;

  /// Most recent parsed cellular info, or null when none has arrived yet.
  CellularInfo? get info => _info;

  /// True once a trigger OPENED successfully but delivered NO payload within the
  /// settle window on a first-ever run — i.e. the combined "WLAN Pros Live"
  /// Shortcut is missing/deleted (iOS only launched the Shortcuts app). Set
  /// asynchronously after the settle so a working read is never stalled; a
  /// delivered payload clears it. The screen ORs this into its `triggerError`
  /// presentation so the same reinstall card serves the open-failed and the
  /// deleted-Shortcut cases. See [WifiMonitorController.shortcutMissing].
  bool get shortcutMissing => _shortcutMissing;

  /// Whether any payload has ever arrived (honest install-state signal).
  bool get hasEverReceived => _hasEverReceived;

  /// True while the live push stream is being consumed.
  bool get isStreaming => _phase == CellularMonitorPhase.streaming;

  /// Wall-clock time of the most recent payload, for the "last updated" label.
  DateTime? get lastUpdated => _lastUpdated;

  /// Resolves install-state, the shared monitoring flag, and the latest
  /// payload. Re-entrant: callable from the "I've installed it, run it" retry
  /// and from app-resume (the Shortcut bounces the app to the foreground).
  Future<void> load() async {
    if (_phase != CellularMonitorPhase.streaming) {
      _phase = CellularMonitorPhase.loading;
      _safeNotify();
    }

    final bool received = await _bridge.hasEverReceivedPayload();
    final CellularInfo? latest = await _bridge.readLatest();
    final bool wasMonitoring = await _bridge.isMonitoringActive();

    _hasEverReceived = received || (latest != null && latest.hasAnyData);
    if (latest != null && latest.hasAnyData) {
      _info = latest;
      _lastUpdated ??= DateTime.now();
    }

    if (_phase == CellularMonitorPhase.streaming) {
      _safeNotify();
      return;
    }

    if (!_hasEverReceived) {
      _phase = CellularMonitorPhase.needsInstall;
    } else if (wasMonitoring) {
      _startListening();
    } else {
      _phase = CellularMonitorPhase.idleWithData;
    }
    _safeNotify();
  }

  /// Begins live monitoring: raises the shared monitoring-active flag so the
  /// Shortcut's `ShouldContinueMonitoringIntent` returns "keep going", then fires
  /// the PLAIN, fire-and-forget run-shortcut trigger ONCE to kick off the
  /// recursion. The combined "WLAN Pros Live" Shortcut delivers both Wi-Fi and
  /// cellular each cycle; this controller consumes only the cellular side of the
  /// stream. The app then passively consumes [CellularInfoBridge.updates]; it
  /// never loops itself. When [triggerShortcutName] is null the trigger is
  /// skipped (the recursion is assumed already running, e.g. a relaunch-resumed
  /// loop).
  ///
  /// Returns false ONLY when iOS could not OPEN the trigger (Shortcuts app
  /// absent). When the trigger opens, the call returns true promptly; the
  /// SEPARATE deleted-Shortcut case (it opened but, on a first-ever run, no
  /// payload arrives within [_missingShortcutSettle]) flips [shortcutMissing]
  /// asynchronously so a working stream is never stalled. Either way the screen
  /// surfaces the honest reinstall card. Also returns true when no trigger was
  /// requested (a resume).
  Future<bool> startMonitoring({String? triggerShortcutName}) async {
    final Future<void> write = _bridge.setMonitoringActive(true);
    _startListening();
    _safeNotify();
    await write;
    if (triggerShortcutName == null) return true;
    final bool opened = await _bridge.runShortcut(triggerShortcutName);
    if (!opened) return false;
    // Returned promptly; the deleted-Shortcut case (opened but delivered nothing)
    // flips [shortcutMissing] asynchronously so a working stream is never stalled.
    _verifyShortcutDelivered();
    return true;
  }

  /// ONE-SHOT live read (2026-06-23, Keith): fire the companion Shortcut ONCE,
  /// capture a single cellular payload, and leave NO persistent monitoring loop
  /// behind — so the iOS status banner flashes for the one run and then clears on
  /// its own. This is the new DEFAULT live read; the continuous loop
  /// ([startMonitoring]) is demoted to an explicit opt-in.
  ///
  /// Like [WifiMonitorController.getReadingOnce] it does NOT raise the monitoring
  /// flag — it CLEARS it first (defence against a stale `true`), so the single
  /// Shortcut cycle reads `false` from `ShouldContinueMonitoringIntent` and stops.
  /// The phase never enters [streaming]; a delivered payload lands the screen on
  /// [idleWithData]. The single payload is captured via a transient stream
  /// subscription and a settle-then-poll fallback ([pollLatestAfterOneShot]).
  ///
  /// Returns false ONLY when iOS could not OPEN the trigger (Shortcuts app
  /// absent). When the trigger opens, the call returns true promptly; the
  /// deleted-Shortcut case (it opened but delivered nothing) is surfaced
  /// asynchronously via [shortcutMissing] after the settle so a working read is
  /// never stalled. Either way the caller's reinstall / setup card fires (the
  /// screen ORs [shortcutMissing] into its `triggerError`). Never loops, never
  /// hangs.
  Future<bool> getReadingOnce({required String triggerShortcutName}) async {
    final Future<void> clearFlag = _bridge.setMonitoringActive(false);

    // A fresh attempt clears any prior missing verdict (and any in-flight settle)
    // so the card does not linger from a previous run.
    _missingTimer?.cancel();
    _missingTimer = null;
    if (_shortcutMissing) {
      _shortcutMissing = false;
      _safeNotify();
    }

    _oneShotSub?.cancel();
    _oneShotSub = _bridge.updates.listen((CellularInfo d) {
      _onPayload(d);
      _oneShotSub?.cancel();
      _oneShotSub = null;
    });

    await clearFlag;
    final bool opened = await _bridge.runShortcut(triggerShortcutName);
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
  /// received a payload, the Shortcut demonstrably works, so a transient miss is
  /// not surfaced as a reinstall prompt (no nagging working users). Only on a
  /// FIRST-EVER run do we settle for [_missingShortcutSettle] and, if still
  /// nothing arrived, conclude the Shortcut is missing.
  void _verifyShortcutDelivered() {
    if (_hasEverReceived) return;
    // A cancellable timer (not a bare Future.delayed) so dispose / a fresh
    // attempt can tear it down — a pending settle must never outlive the screen
    // or flip the flag after disposal.
    _missingTimer?.cancel();
    _missingTimer = Timer(_missingShortcutSettle, () async {
      _missingTimer = null;
      if (_disposed) return;
      if (!_hasEverReceived) {
        final CellularInfo? latest = await _bridge.readLatest();
        if (_disposed) return;
        if (latest != null && latest.hasAnyData) _onPayload(latest);
      }
      if (_hasEverReceived) return;
      _oneShotSub?.cancel();
      _oneShotSub = null;
      _shortcutMissing = true;
      _safeNotify();
    });
  }

  /// Polls the persisted App Group payload after a one-shot fire settles, in case
  /// the single streamed sample raced the app's foreground return. Records it via
  /// the same [_onPayload] path. Never throws; off-iOS [readLatest] returns null.
  Future<void> pollLatestAfterOneShot() async {
    final CellularInfo? latest = await _bridge.readLatest();
    if (latest != null && latest.hasAnyData) _onPayload(latest);
  }

  /// Stops live monitoring: clears the shared monitoring flag (the recursive
  /// Shortcut halts on its next check), flips the phase, and tears down the
  /// subscription. The last payload stays on screen.
  Future<void> stopMonitoring() async {
    final Future<void> write = _bridge.setMonitoringActive(false);
    final StreamSubscription<CellularInfo>? sub = _sub;
    _sub = null;
    _phase = _hasEverReceived
        ? CellularMonitorPhase.idleWithData
        : CellularMonitorPhase.needsInstall;
    _safeNotify();
    await sub?.cancel();
    await write;
  }

  void _startListening() {
    _sub?.cancel();
    _phase = CellularMonitorPhase.streaming;
    _sub = _bridge.updates.listen(_onPayload);
  }

  void _onPayload(CellularInfo d) {
    if (!d.hasAnyData) return;
    _info = d;
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
