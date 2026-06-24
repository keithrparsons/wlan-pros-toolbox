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
  CellularMonitorController({required CellularInfoBridge bridge})
      // ignore: prefer_initializing_formals
      : _bridge = bridge;

  final CellularInfoBridge _bridge;

  StreamSubscription<CellularInfo>? _sub;

  /// Transient subscription for a [getReadingOnce] read: captures exactly one
  /// streamed payload and tears itself down, so a one-shot read never leaves a
  /// persistent live stream (or the iOS banner) running.
  StreamSubscription<CellularInfo>? _oneShotSub;

  CellularMonitorPhase _phase = CellularMonitorPhase.loading;
  CellularInfo? _info;
  bool _hasEverReceived = false;
  DateTime? _lastUpdated;
  bool _disposed = false;

  CellularMonitorPhase get phase => _phase;

  /// Most recent parsed cellular info, or null when none has arrived yet.
  CellularInfo? get info => _info;

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
  /// Returns false when the trigger could not be OPENED (Shortcuts missing / the
  /// Live Shortcut not installed). Returns true when no trigger was requested or
  /// iOS opened the trigger URL.
  Future<bool> startMonitoring({String? triggerShortcutName}) async {
    final Future<void> write = _bridge.setMonitoringActive(true);
    _startListening();
    _safeNotify();
    await write;
    if (triggerShortcutName == null) return true;
    return _bridge.runShortcut(triggerShortcutName);
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
  /// Returns false when the trigger could not be OPENED (Shortcut missing) so the
  /// caller surfaces the honest setup card. Never loops, never hangs.
  Future<bool> getReadingOnce({required String triggerShortcutName}) async {
    final Future<void> clearFlag = _bridge.setMonitoringActive(false);

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
    }
    return opened;
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
