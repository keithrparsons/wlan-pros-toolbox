// Wi-Fi monitoring state machine (TICKET-03 A2).
//
// Drives the Wi-Fi Details screen over the [WiFiDetailsBridge]. It owns the
// honest install-state branch, the one-shot pull, and the live push stream, so
// the widget stays thin and the state machine is unit-testable without a widget
// tree. Exposed as a [ChangeNotifier].
//
// Phases:
//   loading      -> resolving install-state + latest payload on first load.
//   notOnWifi    -> the device is demonstrably NOT on Wi-Fi (e.g. cellular-only
//                   on iOS): show the honest "connect to Wi-Fi" message instead
//                   of silence or an endless "waiting" spinner. Checked BEFORE
//                   needsInstall, and only ever entered on a positive
//                   not-on-Wi-Fi signal (never from missing/ambiguous data).
//   needsInstall -> on Wi-Fi but no payload has ever arrived: show install/how-to.
//   idleWithData -> at least one payload exists, live monitoring not running.
//   streaming    -> live monitoring running; cards update on each pushed payload.
//
// The one-shot path (run the Shortcut once -> single update) stays first-class:
// a payload delivered while idle moves the screen to [idleWithData] with data.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'wifi_connection_service.dart';
import 'wifi_details.dart';
import 'wifi_details_bridge.dart';

/// Lifecycle phases of the Wi-Fi Details screen.
enum WifiMonitorPhase {
  loading,
  notOnWifi,
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
    WifiConnectionService? connectionService,
    Duration missingShortcutSettle = const Duration(seconds: 4),
  })  : _bridge = bridge,
        _connection = connectionService ?? WifiConnectionService(),
        _missingShortcutSettle = missingShortcutSettle;

  final WiFiDetailsBridge _bridge;

  /// Honest "is the device on Wi-Fi?" probe (2026-06-25). Drives the [notOnWifi]
  /// phase so a cellular-only / half-joined-captive user sees a clear "connect to
  /// Wi-Fi" message instead of silence or an endless "waiting" spinner. Returns
  /// [WifiConnectionStatus.unknown] on any ambiguous read, which leaves the prior
  /// behaviour untouched (never a false "not on Wi-Fi").
  final WifiConnectionService _connection;

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
  bool _notOnWifi = false;
  bool _setupInitiated = false;
  int _deliveryCount = 0;

  /// True once a payload has arrived since the most recent [startMonitoring].
  /// Reset to false at each Start and set true on the first delivered payload, so
  /// the Start-aware missing-Shortcut settle can tell a working stream (a first
  /// sample arrived) from a missing one (a fresh Start that produced nothing) —
  /// even for an already-set-up user (Keith device round 5: streaming is now the
  /// only live action, so its missing case must self-recover).
  bool _sampleSinceStart = false;

  WifiMonitorPhase get phase => _phase;

  /// How many LIVE payloads have been delivered this session (one-shot + stream).
  /// [load] restoring the stored last reading does NOT advance this, so a screen
  /// can chart fresh deliveries while leaving a stale stored reading off the chart
  /// on open (Keith device round 4). Zero until the first live delivery.
  int get deliveryCount => _deliveryCount;

  /// True between "the user started setup (tapped Add the Shortcut)" and "the
  /// first payload completes the round-trip" — the PRIMING window. iOS cannot
  /// report whether a Shortcut is installed, so right after install the app would
  /// otherwise keep showing the cold "Set up live Wi-Fi" prompt (the post-install
  /// confusion Keith hit). While this is true and [hasEverReceived] is still
  /// false, the screen shows the priming step ("come back and tap Get reading; iOS
  /// asks permission the first time, tap Allow") and routes the enable action to a
  /// one-shot prime instead of re-opening setup. Read from the App Group, so it
  /// survives the install app-bounce; the native side clears it the moment a
  /// payload arrives. False once [hasEverReceived] is true.
  bool get setupInitiated => _setupInitiated && !_hasEverReceived;

  /// True when the most recent connection probe found the device is demonstrably
  /// NOT on Wi-Fi (e.g. cellular-only). Honest: only ever set on a positive
  /// not-on-Wi-Fi signal, never from missing/ambiguous data. The screen ORs this
  /// nowhere — it is surfaced via the [WifiMonitorPhase.notOnWifi] phase.
  bool get notOnWifi => _notOnWifi;

  /// Most recent parsed details, or null when none has arrived yet — AND null
  /// whenever the probe positively reports the device is NOT on Wi-Fi.
  ///
  /// THE STALE-READING BUG (2026-07-13, Keith on-device, v1.7.2). A cellular-only
  /// iPhone showed Tx 29 / Rx 13 Mbps as current/min/avg/max under a LIVE badge,
  /// and Test My Connection told him to "boost the Wi-Fi signal" — from a reading
  /// captured the last time the phone was actually on Wi-Fi. The stored payload
  /// outranked a positive not-on-Wi-Fi probe, so a value the device did not have
  /// was rendered as if it were current, and fed into advice.
  ///
  /// GL-005: there are two kinds of null. "We could not read this" is one; "this
  /// does not exist" is the other. Off Wi-Fi is the SECOND — there is no Wi-Fi
  /// link, so there is no Wi-Fi reading, stale or otherwise. We return null while
  /// [_notOnWifi] rather than clearing [_details], so a rejoin restores the last
  /// known reading without a re-fetch.
  ///
  /// SUPPRESSION IS LOAD-BEARING, SO ITS INPUT MUST BE RIGHT. [_notOnWifi] is set
  /// only when [WifiConnectionService] returns a POSITIVE not-on-Wi-Fi verdict;
  /// an ambiguous read (a wired desktop, a Location-gated SSID, a failed/denied
  /// read) resolves to [WifiConnectionStatus.unknown] and leaves it false. That
  /// structure is necessary but NOT sufficient: an earlier round called it
  /// "can never over-suppress" and shipped a probe that asserted not-on-Wi-Fi for
  /// an iPhone on an IPv6-only SSID (`getWifiIP()` is IPv4-only), which blanked a
  /// LIVE link. The exact conditions under which the probe may assert the
  /// negative — and the limits of that assertion — are documented in
  /// [WifiConnectionService]; read them before widening what this gate hides.
  WiFiDetails? get details => _notOnWifi ? null : _details;

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

  /// Resolves install-state, the persisted monitoring flag, the latest payload,
  /// and the honest Wi-Fi connection state. Re-entrant: callable from the "I've
  /// installed it, run it" retry and from app-resume (the Shortcut bounces the
  /// app to the foreground, and the user may have joined/left Wi-Fi meanwhile).
  ///
  /// [nativeSsid] is the optional native NEHotspotNetwork/CoreWLAN SSID the
  /// screen already reads. A non-empty value is a definitive "on Wi-Fi" signal;
  /// its absence is NOT used to assert "not on Wi-Fi" (it can be null because
  /// Location is ungranted). See [WifiConnectionService.status].
  Future<void> load({String? nativeSsid}) async {
    if (_phase != WifiMonitorPhase.streaming) {
      _phase = WifiMonitorPhase.loading;
      _safeNotify();
    }

    final bool received = await _bridge.hasEverReceivedPayload();
    final WiFiDetails? latest = await _bridge.readLatest();
    final bool wasMonitoring = await _bridge.isMonitoringActive();
    final WifiConnectionStatus connStatus =
        await _connection.status(nativeSsid: nativeSsid);
    // x-error recovery (2026-06-25, Keith — build 41 strand). The one-shot
    // trigger now carries an `x-error` return URL, so a renamed/deleted "WLAN
    // Pros Live" Shortcut bounces the app back via `wlanprostoolbox://live-error`
    // instead of stranding the user on the Shortcuts page. The native handler
    // RESET the durable install-state (cleared the trust flag + stale reading)
    // and raised this consumed-once marker; we read it on the resume-driven load
    // and force the honest "Shortcut not found — re-run setup" recovery. This
    // closes the gap the settle-timer [_verifyShortcutDelivered] leaves open for
    // a PREVIOUSLY-WORKING Shortcut: that path short-circuits on hasEverReceived,
    // so it never fired for Keith, who had received payloads before deleting it.
    final bool shortcutMissing = await _bridge.consumeShortcutMissing();
    // Post-install priming window: the user started setup but no payload has
    // completed the round-trip yet. Read here so a resume-driven load right after
    // install surfaces the priming step instead of the cold setup prompt.
    _setupInitiated = await _bridge.hasInitiatedSetup();

    _hasEverReceived = received || (latest != null && latest.hasAnyData);
    if (latest != null && latest.hasAnyData) {
      _details = latest;
      _lastUpdated ??= DateTime.now();
    }
    // Honest connection flag: true ONLY on a positive not-on-Wi-Fi signal; an
    // `unknown` (ambiguous / wired desktop / read failed) leaves it false so the
    // prior behaviour is untouched (GL-005 — no false "not on Wi-Fi").
    _notOnWifi = connStatus == WifiConnectionStatus.notOnWifi;

    if (shortcutMissing) {
      // The Shortcut is gone: present the setup recovery deterministically and
      // never the not-on-Wi-Fi card (re-running setup is the actionable fix, on
      // or off Wi-Fi). The native reset already dropped the trust flag + stored
      // reading, so hasEverReceived is false here; force it defensively in case a
      // racing stale signal slipped through.
      _shortcutMissing = true;
      _hasEverReceived = false;
      _notOnWifi = false;
    }

    // NOT-ON-WIFI WINS — unconditionally, and BEFORE the mid-stream early-return.
    //
    // THE FIX (2026-07-13). This branch used to read `_notOnWifi && !_hasEverReceived`,
    // so the honest state only ever showed to a user who had NEVER captured a
    // Wi-Fi reading. For everyone else — i.e. every real user — a stale stored
    // payload outranked a positive not-on-Wi-Fi probe and kept rendering as if it
    // were current. The old comment called that "never blanks data the user
    // already has." What it actually did was present a Wi-Fi rate for a Wi-Fi
    // link that does not exist, and feed it into the Wi-Fi-vs-internet advice.
    //
    // There is no Wi-Fi link, so there is no Wi-Fi reading. The probe is the
    // authority, and it is a POSITIVE-only signal ([WifiConnectionStatus.unknown]
    // on any ambiguous/failed read), so a wired desktop or a Location-gated read
    // can never land here.
    //
    // Checked before the streaming early-return because a device that dropped to
    // cellular WHILE streaming has no producer behind the stream: leaving it in
    // `streaming` is what painted the LIVE badge over the stale rate. Tear the
    // stream down and clear the App Group loop flag — a looping Shortcut has
    // nothing to read either.
    if (_notOnWifi) {
      await stopMonitoring(); // resolves _phase via _idlePhase -> notOnWifi
      _safeNotify();
      return;
    }

    if (_phase == WifiMonitorPhase.streaming) {
      // A resume arrived mid-stream; keep streaming, data already refreshed.
      _safeNotify();
      return;
    }

    if (shortcutMissing) {
      // Missing-Shortcut recovery takes priority: the live tools return to the
      // setup CTA, and the screen ORs [shortcutMissing] into its `triggerError`
      // presentation to show the honest "not found — re-run setup" note.
      // (The shortcutMissing block above already forced _notOnWifi false, so the
      // not-on-Wi-Fi branch cannot steal this case.)
      _phase = WifiMonitorPhase.needsInstall;
    } else if (!_hasEverReceived) {
      _phase = WifiMonitorPhase.needsInstall;
    } else if (wasMonitoring) {
      // App relaunched while a loop was active -> resume listening.
      _startListening();
    } else {
      _phase = WifiMonitorPhase.idleWithData;
    }
    _safeNotify();
  }

  /// The phase to rest in when no live stream is running.
  ///
  /// The honest not-on-Wi-Fi state outranks BOTH `idleWithData` (there is no
  /// reading to be idle with) and `needsInstall` (installing a Shortcut cannot
  /// conjure a Wi-Fi link). Positive-probe-only, so it never fires on an
  /// ambiguous read. Shared by [load] and [stopMonitoring] so the two can never
  /// disagree about where the machine rests.
  WifiMonitorPhase get _idlePhase {
    if (_notOnWifi) return WifiMonitorPhase.notOnWifi;
    return _hasEverReceived
        ? WifiMonitorPhase.idleWithData
        : WifiMonitorPhase.needsInstall;
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
  /// The stream subscription is kicked off synchronously (before the first
  /// `await`) so a tap-driven rebuild does not wait on a later microtask; the
  /// flag write + trigger fire happen after an app-wide single-flight check so a
  /// second concurrent Start ADOPTS the running loop instead of stacking a second
  /// one. When [triggerShortcutName] is null the trigger is skipped (the
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
    // Fresh Start: a working stream delivers a first sample within the settle.
    _sampleSinceStart = false;
    // A fresh Start clears any lingering missing verdict from a prior attempt.
    if (_shortcutMissing) _shortcutMissing = false;

    // Enter streaming optimistically and synchronously (before the first await)
    // so a tap-driven rebuild does not wait on a microtask — unchanged intent.
    _startListening();
    _safeNotify();

    // APP-WIDE SINGLE-FLIGHT (Option B). Fire the trigger and (re)stamp the flag
    // ONLY on a genuine false→true transition. If a monitoring loop is ALREADY
    // active — another scene/surface started it, or a relaunch resumed it — ADOPT
    // the existing stream instead of firing a SECOND run-shortcut: two concurrent
    // fires stack independent Shortcut loops that never supersede each other (the
    // multi-run stacking symptom). We also do NOT re-write the flag on adopt, so
    // the existing session's hard-cap start stamp is left intact (re-stamping
    // would silently extend the 5-minute cap on every surface that adopts).
    final bool alreadyActive = await _bridge.isMonitoringActive();
    if (alreadyActive) {
      // Adopted a live loop: the settle-based missing verdict is the starting
      // surface's job (it fired the trigger); here we just consume the stream.
      return true;
    }

    await _bridge.setMonitoringActive(true);
    if (triggerShortcutName == null) return true;
    final bool opened = await _bridge.runShortcut(triggerShortcutName);
    if (!opened) return false;
    // Returned promptly; the missing-Shortcut verdict flips [shortcutMissing]
    // asynchronously so a working stream is never stalled by the settle. On a
    // STREAM Start we surface it whenever this Start delivers no first sample —
    // a fresh kickoff that produces nothing means the recursion never started
    // (Shortcut missing), even for an already-set-up user.
    _verifyShortcutDelivered(forStart: true);
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
  ///
  /// For a STREAM START ([forStart]) we settle whenever this Start delivered no
  /// first sample, even for an already-set-up user: a fresh kickoff that produces
  /// nothing means the recursion never started (missing Shortcut). The stream
  /// Start does NOT poll the App Group (that would return a STALE stored reading
  /// and mask the miss); the only honest "the stream started" signal is a sample
  /// delivered THIS Start ([_sampleSinceStart]).
  void _verifyShortcutDelivered({bool forStart = false}) {
    if (!forStart && _hasEverReceived) return;
    // A cancellable timer (not a bare Future.delayed) so dispose / a fresh
    // attempt can tear it down so a pending settle never outlives the screen or
    // flips the flag after disposal.
    _missingTimer?.cancel();
    _missingTimer = Timer(_missingShortcutSettle, () async {
      _missingTimer = null;
      if (_disposed) return;
      if (forStart) {
        // Stream Start: a missing Shortcut delivers no first sample this Start.
        if (_sampleSinceStart) return;
        _shortcutMissing = true;
        // Tear down the phantom stream (no producer) so the screen does not show
        // a dead "LIVE" header alongside the recovery card.
        await stopMonitoring();
        _safeNotify();
        return;
      }
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
    // OFF WI-FI: never re-deliver the STORED reading as if it were a fresh live
    // sample (2026-07-13). This poll exists for a race — the Shortcut delivered
    // while we were backgrounded — but off Wi-Fi the Shortcut delivered NOTHING,
    // and the App Group still holds the last on-Wi-Fi reading. Feeding that
    // through [_onPayload] would stamp `lastUpdated = now`, advance
    // [deliveryCount], and chart a months-old rate as a live sample. There is no
    // Wi-Fi link, so a one-shot read has no result to settle for.
    if (_notOnWifi) return;
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
    _phase = _idlePhase;
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
    // A payload arrived since the last Start: the stream is alive, so the
    // Start-aware missing settle must not fire.
    _sampleSinceStart = true;
    // Count only LIVE deliveries this session (one-shot + stream). load() restores
    // the last stored payload by setting `_details` DIRECTLY (not through here), so
    // it never advances this — letting the screens chart fresh deliveries while NOT
    // charting a stale stored reading on open.
    _deliveryCount++;
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
