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
    Duration notOnWifiConfirmSettle = const Duration(milliseconds: 1200),
  })  : _bridge = bridge,
        _connection = connectionService ?? WifiConnectionService(),
        _missingShortcutSettle = missingShortcutSettle,
        _notOnWifiConfirmSettle = notOnWifiConfirmSettle;

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

  /// How long to wait before RE-PROBING a not-on-Wi-Fi verdict that would tear
  /// down a LIVE session. See [_confirmedNotOnWifi]. Injectable so tests run fast.
  final Duration _notOnWifiConfirmSettle;

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

  /// Wall-clock instant of the most recent [startMonitoring]. Null before the
  /// first Start. Paired with [WiFiDetailsBridge.payloadReceivedAt] so the
  /// missing-Shortcut settle can tell a payload THIS Start produced from the
  /// stale one sitting in the App Group since the last time the phone was on
  /// Wi-Fi.
  DateTime? _startedAt;

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
    bool notOnWifi = connStatus == WifiConnectionStatus.notOnWifi;
    // A verdict that would tear down a LIVE session must be SETTLED, not a single
    // read taken across the Shortcuts app-switch this very screen just made. Only
    // the streaming path pays the confirmation cost; an idle screen acts on the
    // positive probe immediately. See [_confirmedNotOnWifi].
    if (notOnWifi && _phase == WifiMonitorPhase.streaming) {
      notOnWifi = await _confirmedNotOnWifi(nativeSsid: nativeSsid);
      if (_disposed) return;
    }
    _notOnWifi = notOnWifi;

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
      // ======================================================================
      // ADOPT A LIVE LOOP, TEAR DOWN A DEAD ONE. (2026-07-14, Keith device.)
      //
      // This branch used to be a bare `_startListening()` — resume streaming from
      // the persisted flag ALONE, with NO check that anything is still producing.
      // The flag says "a loop was started". It does NOT say "a loop is running".
      // Those are different facts, and every bug in this area is a confusion of
      // the two:
      //
      //   * Believe the flag too readily and you paint a "LIVE" header over a
      //     dead session with no producer behind it — the dead-LIVE-card hazard
      //     Keith hit on a first run.
      //   * Distrust it and you TEAR DOWN THE LOOP THE USER JUST STARTED. That is
      //     the regression Keith's phone found twice: start the feed, get bounced
      //     into Shortcuts (BY DESIGN — that is how the recursion is kicked off),
      //     come back, and the app kills the healthy recursion it was waiting for.
      //     It survived exactly as long as it took him to walk back: ~5 seconds.
      //
      // The old defense against the first hazard lived in `WifiSignalSampler`
      // (`if (!_startedThisSession && c.isStreaming) stopMonitoring()`), and it was
      // wrong in two ways at once. It asked a question about THE WIDGET
      // (`_startedThisSession`) to answer a question about THE LOOP. And it lived in
      // the sampler — which Wi-Fi Information DOES NOT USE (it drives this
      // controller directly), so that screen had no protection from hazard one at
      // all, while Test My Connection got killed by hazard two.
      //
      // THE ONLY HONEST WITNESS TO A RUNNING LOOP IS A RECENT PAYLOAD. Ask the
      // App Group stamp, not a session flag. It lives BELOW the app's lifecycle, so
      // it survives the scene rebuild that started this whole mess, and a loop that
      // is genuinely delivering leaves it fresh every cycle. Both screens now
      // inherit one rule from one place.
      // ======================================================================
      if (await _loopIsAlive()) {
        if (_disposed) return;
        // A payload landed inside the liveness window: there is a real producer on
        // the other end of that flag. ADOPT the stream. Do NOT re-fire the
        // Shortcut — the recursion is already running, and a second fire would
        // stack a competing loop.
        _startListening();
      } else {
        if (_disposed) return;
        // The flag is up but NOTHING is delivering: a crashed or abandoned session
        // left it behind. Clear it so the (non-existent) recursion cannot be
        // resurrected, and rest in the honest idle state with the actionable Start
        // control — never a "LIVE" badge with no data behind it.
        await stopMonitoring();
        _safeNotify();
        return;
      }
    } else {
      _phase = WifiMonitorPhase.idleWithData;
    }
    _safeNotify();
  }

  /// How long after the last delivered payload a monitoring loop is still presumed
  /// ALIVE.
  ///
  /// PICKED FROM THE ACTUAL DELIVERY CADENCE IN THIS CODEBASE, not by feel:
  ///   * The companion Shortcut's live cadence is ~1 SECOND. `WifiSignalSampler`
  ///     sizes its 30-second sparkline window to "~30 samples" at "the ~1s
  ///     companion-Shortcut cadence", so a healthy loop stamps the App Group about
  ///     once a second.
  ///   * [_missingShortcutSettle] is 4 SECONDS — this code already treats 4 seconds
  ///     of silence on a FRESH start as grounds for suspicion.
  ///
  /// 10 seconds is therefore ~10 missed delivery cycles: far outside any plausible
  /// iOS scheduling jitter or Shortcuts-app hand-off delay (the window that must
  /// NOT be misread as death — it is exactly the window the user spends walking
  /// back from the Shortcuts app), and far inside a genuinely abandoned session
  /// (a flag left by a previous app run is minutes or hours stale, not seconds).
  ///
  /// ERRING DIRECTION, STATED: this window errs toward ADOPTING. A loop that died
  /// less than 10 seconds ago is briefly presumed alive, and the screen shows LIVE
  /// for up to 10 seconds with no new samples arriving. That is a transient
  /// cosmetic wrong. The opposite error — presuming a LIVE loop dead — CLEARS THE
  /// FLAG and destroys a working session the user explicitly started, which is the
  /// bug this exists to remove. Between a stale badge for a few seconds and killing
  /// the user's feed, the badge is not close.
  static const Duration _loopLivenessWindow = Duration(seconds: 10);

  /// Is the monitoring loop behind the persisted flag GENUINELY RUNNING?
  ///
  /// Evidence, in order of strength:
  ///   1. A payload arrived on the live stream THIS session ([_sampleSinceStart]) —
  ///      we watched it happen; nothing beats that.
  ///   2. The App Group's payload stamp is inside [_loopLivenessWindow]. This is the
  ///      witness that SURVIVES A SCENE REBUILD, because it lives below the app.
  ///
  /// FAIL-SAFE DIRECTION. When the platform cannot answer — [payloadReceivedAt]
  /// returns null off-iOS, or on an App Group written by a build that predates the
  /// stamp — this returns FALSE, i.e. "tear down". That is deliberate: a null stamp
  /// is "I cannot prove this loop is alive", and adopting an unprovable loop is what
  /// paints a dead LIVE card. It degrades to the pre-existing conservative behavior
  /// rather than inventing a liveness it cannot demonstrate (GL-005).
  Future<bool> _loopIsAlive() async {
    if (_sampleSinceStart) return true;
    final DateTime? deliveredAt = await _bridge.payloadReceivedAt();
    if (deliveredAt == null) return false;
    return DateTime.now().difference(deliveredAt) <= _loopLivenessWindow;
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
    // The instant this Start fired. The missing-Shortcut settle compares the App
    // Group's payload stamp against it to ask the only honest question available
    // once the app has been backgrounded into Shortcuts: "did a payload land
    // AFTER this Start?" See [_verifyShortcutDelivered].
    _startedAt = DateTime.now();
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
  /// nothing means the recursion never started (missing Shortcut).
  ///
  /// ============================================================================
  /// THE REGRESSION THIS BLOCK CAUSED, AND WHY (2026-07-14, Keith device).
  /// ============================================================================
  /// The Start path FIRES A SHORTCUT, which means iOS foregrounds the Shortcuts
  /// app and BACKGROUNDS the Toolbox. The companion Shortcut then delivers its
  /// sample by writing the APP GROUP and posting a Darwin notification — and a
  /// backgrounded (soon suspended) Flutter engine CANNOT RECEIVE THAT PUSH.
  ///
  /// So [_sampleSinceStart], which is set only from a payload arriving on the live
  /// [WiFiDetailsBridge.updates] stream, is evidence that BY CONSTRUCTION cannot
  /// arrive during the settle window — because the app spends that entire window
  /// backgrounded in the app this very method just sent it to. The settle asked
  /// for the one proof the Start path makes impossible, and then, on not getting
  /// it, declared the user's Shortcut missing and CLEARED THE APP GROUP LOOP FLAG
  /// — halting the healthy recursion it was waiting on. Keith reinstalled the
  /// Shortcut several times; of course it never helped. The Shortcut was fine.
  /// We killed it, and then blamed it.
  ///
  /// The old code refused to poll the App Group for a good reason — "that would
  /// return a STALE stored reading and mask the miss" — and that reason was real:
  /// [WiFiDetails] carries no timestamp, so a stored payload could not be told
  /// from one stored a month ago. The answer is not to go blind; it is to get the
  /// timestamp. [WiFiDetailsBridge.payloadReceivedAt] now returns the instant the
  /// native receiver STORED the payload, so this settle can ask the honest
  /// question — "did a payload land AFTER this Start?" — which:
  ///   * a STALE reading can never answer yes to (its stamp predates the Start),
  ///     so a real miss is still caught; and
  ///   * a WORKING Shortcut answers yes to even when it delivered while we were
  ///     backgrounded, so a healthy session is never torn down.
  /// Neither blind nor credulous.
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
        // A sample already reached us on the live stream (the user came back to
        // the foreground fast enough): the recursion is demonstrably running.
        if (_sampleSinceStart) return;
        // Nothing on the stream — which proves nothing, because we were
        // backgrounded in the Shortcuts app. Ask the App Group whether the
        // Shortcut delivered while we could not listen.
        if (await _deliveredSinceStart()) {
          if (_disposed) return;
          // It ran. Land the payload it delivered so the reading and the
          // sparkline reflect it, and leave the live session ALONE.
          final WiFiDetails? latest = await _bridge.readLatest();
          if (_disposed) return;
          if (latest != null && latest.hasAnyData) {
            _onPayload(latest); // clears _shortcutMissing, sets _sampleSinceStart
            return;
          }
        }
        if (_disposed) return;
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

  /// Did the companion Shortcut store a payload AFTER the current [startMonitoring]?
  ///
  /// The honest "the Shortcut ran" signal for a Start that has backgrounded the
  /// app. A payload whose stored-at stamp is at or after [_startedAt] can only
  /// have been produced by THIS Start's trigger; a stale reading from the last
  /// time the phone was on Wi-Fi is stamped earlier and is correctly rejected, so
  /// this cannot mask a genuinely missing Shortcut.
  ///
  /// False when the platform cannot answer (off-iOS, or no stamp stored — an App
  /// Group written by a build that predates the stamp). That is the FAIL-SAFE
  /// direction for a NEW check: it degrades to the old stream-only behavior rather
  /// than inventing a delivery that may not have happened.
  Future<bool> _deliveredSinceStart() async {
    final DateTime? started = _startedAt;
    if (started == null) return false;
    final DateTime? deliveredAt = await _bridge.payloadReceivedAt();
    if (deliveredAt == null) return false;
    return !deliveredAt.isBefore(started);
  }

  /// Re-probes the Wi-Fi connection and returns whether it STILL reports
  /// not-on-Wi-Fi.
  ///
  /// NOT-ON-WIFI MUST BE A SETTLED STATE, NEVER A TRANSIENT. The verdict is
  /// load-bearing — it blanks the reading and tears down a live session — and
  /// [load] runs on every app RESUME, which on the live tools means it runs
  /// immediately after the app has been bounced through the Shortcuts app. A path
  /// probe taken across that app-switch is exactly the read least entitled to be
  /// trusted: a backgrounded/just-resumed app can see an unsatisfied path or an
  /// empty interface list for a Wi-Fi link that is perfectly healthy, and a single
  /// such read would kill the session the user just started.
  ///
  /// So a not-on-Wi-Fi verdict that would tear down a LIVE session must be
  /// CONFIRMED by a second, settled read. A device that genuinely dropped to
  /// cellular still confirms (it is not on Wi-Fi a moment later either) and still
  /// gets the honest state — the suppression is not weakened, only made to prove
  /// itself. The IDLE path does not pay this cost: with no live session at risk, a
  /// positive probe is acted on immediately, so a cellular-only user still gets
  /// "You're not connected to Wi-Fi" the instant the screen opens.
  Future<bool> _confirmedNotOnWifi({String? nativeSsid}) async {
    await Future<void>.delayed(_notOnWifiConfirmSettle);
    if (_disposed) return false;
    final WifiConnectionStatus again =
        await _connection.status(nativeSsid: nativeSsid);
    return again == WifiConnectionStatus.notOnWifi;
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
