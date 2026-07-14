// Wi-Fi signal sampler — the shared live-RF sampling engine behind the
// "Wi-Fi signal" sparkline card.
//
// This factors out the per-platform live sampling that `wifi_info_screen`
// performs inline, so the merged Test My Connection screen can run the SAME
// continuous RF feed without copy-pasting the macOS poll loop and the iOS
// streaming controller into a second screen. It adds NO new measurement: it
// drives the already-shipped [MacWifiInfoAdapter] (macOS CoreWLAN) and
// [WifiMonitorController] / [WiFiDetailsBridge] (the iOS companion-Shortcut
// stream), folding each sample into a rolling [WifiTimeSeries].
//
// Platform behavior is identical to wifi-info (inherited, not re-invented):
//   * macOS — auto-polls CoreWLAN every [macPollInterval] while [start] is in
//     effect (CoreWLAN is local and cheap; there is no Start/Stop on macOS, the
//     screen just calls [start] when visible and [stop] on teardown).
//   * iOS — streams via the companion "WLAN Pros Live" Shortcut. [start] raises
//     the monitoring flag and fires the trigger once; [stop] clears it and
//     freezes the last values. When the companion Shortcut is absent, [start]
//     surfaces [triggerError] honestly (no fabricated trend) — exactly as
//     wifi-info degrades today.
//
// WINDOW (Keith, 2026-06-04): the sparklines roll over the last 30 SECONDS. The
// [WifiTimeSeries] capacity is a sample COUNT, so it is sized to 30s at the
// active platform cadence here (macOS: 30s / 2s poll ≈ 15 samples; iOS:
// ~1s stream ≈ 30 samples). This does NOT touch wifi-info's own window/cadence
// defaults — that screen keeps its 60-sample window; this sampler sets its own.
//
// HONESTY (GL-005): a field a sample omits is stored as null (the sparkline
// draws a gap, never a fabricated 0). A platform that cannot read the link (web,
// unsupported, iOS without the Shortcut) yields no samples and an honest
// unavailable surface — never invented data.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'connected_ap.dart';
import 'roam_detector.dart';
import 'wifi_connection_service.dart';
import 'wifi_details.dart';
import 'wifi_details_bridge.dart';
import 'wifi_info_adapter.dart';
import 'wifi_live_shortcuts_config.dart';
import 'wifi_monitor_controller.dart';
import 'wifi_time_series.dart';

/// A continuous live-RF sampler exposing a rolling [WifiTimeSeries] plus the
/// latest [ConnectedAp]. A [ChangeNotifier] so the sparkline card rebuilds on
/// each new sample. Drives the correct platform feed for [source].
class WifiSignalSampler extends ChangeNotifier {
  WifiSignalSampler({
    required this.source,
    WifiInfoAdapter? macAdapter,
    WiFiDetailsBridge? iosBridge,
    WifiConnectionService? connectionService,
    Duration macPollInterval = const Duration(seconds: 2),
    Duration window = const Duration(seconds: 30),
  })  // The public params are named without the underscore (clean API); the
      // private fields mirror them, so the initializing-formal lint does not
      // apply here.
      // ignore_for_file: prefer_initializing_formals
      : _macPollInterval = macPollInterval,
        _window = window {
    switch (source) {
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.androidWifiManager:
      case WifiInfoSource.windowsNativeWifi:
        // All three snapshot sources poll a [WifiInfoAdapter]; pick the
        // platform's.
        _macAdapter = macAdapter ??
            switch (source) {
              WifiInfoSource.androidWifiManager => AndroidWifiInfoAdapter(),
              WifiInfoSource.windowsNativeWifi => WindowsWifiInfoAdapter(),
              _ => MacWifiInfoAdapter(),
            };
        // ANDROID ONLY: the honest "is this device on Wi-Fi?" probe for a SNAPSHOT
        // source. (Round-4 cold review, THE ANDROID GATE, 2026-07-14.)
        //
        // This is THE SECOND, INDEPENDENT COPY of the consent hole, and it had to
        // be closed separately from the one in [WifiConnectionService]. Test My
        // Connection's gate does NOT read the service — it reads
        // [WifiSignalSampler.notOnWifi], which read `_controller?.notOnWifi`, and
        // `_controller` is built ONLY under `case WifiInfoSource.iosShortcuts`
        // below. So on Android `notOnWifi` was hard-wired to `false` no matter what
        // the service learned, and [load] was a NO-OP. Fixing the service alone
        // would have left the app's PRIMARY ENTRY POINT (the home hero pushes this
        // screen with `autoStart: true`) still auto-spending 50-500 MB of a
        // cellular user's data on frame one.
        //
        // macOS AND WINDOWS GET NO PROBE, DELIBERATELY — and that is enforced HERE,
        // by construction, not by a runtime check that could drift. On those
        // platforms [WifiConnectionService] can only ever answer `unknown` (an
        // absent Wi-Fi IPv4 on a desktop is ambiguous, and "never nag a wired
        // desktop" genuinely applies), so building a probe for them would buy a
        // per-load platform-channel round-trip that CANNOT change any answer. They
        // keep the no-op [load] they have always had, byte for byte.
        _connectionService = source == WifiInfoSource.androidWifiManager
            ? (connectionService ?? WifiConnectionService())
            : null;
        // 30s window at a 2s poll → ~15 samples (ceil so the full window fits).
        _series = WifiTimeSeries(capacity: _capacityFor(_macPollInterval));
      case WifiInfoSource.iosShortcuts:
        _iosBridge = iosBridge ?? WiFiDetailsBridge();
        // [connectionService] is the honest "is this device on Wi-Fi?" probe
        // seam. Null in production (the controller builds the real one); a test
        // injects a fake so the not-on-Wi-Fi gate is exercised without a live
        // radio — mirroring [WifiMonitorController]'s own seam.
        _controller = WifiMonitorController(
          bridge: _iosBridge!,
          connectionService: connectionService,
        );
        // 30s window at the ~1s companion-Shortcut cadence → ~30 samples.
        _series =
            WifiTimeSeries(capacity: _capacityFor(const Duration(seconds: 1)));
        _controller!.addListener(_onControllerChanged);
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        // No live RF feed on these platforms; the series stays empty and the
        // card renders its honest unavailable state.
        _series = WifiTimeSeries(capacity: 1);
    }
  }

  /// The resolved platform source. Drives which feed [start] activates.
  final WifiInfoSource source;

  final Duration _macPollInterval;
  final Duration _window;

  // ---- macOS (CoreWLAN poll) ----
  WifiInfoAdapter? _macAdapter;
  Timer? _macPollTimer;
  ConnectedAp? _macLastCharted;
  ConnectedAp? _macInfo;

  // ---- Android (snapshot source) connection probe ----

  /// The honest Wi-Fi connection probe for the ANDROID snapshot source. Null on
  /// macOS / Windows (they have no honest negative to report — see the constructor)
  /// and on iOS (the [WifiMonitorController] owns the probe there).
  WifiConnectionService? _connectionService;

  /// The last SETTLED not-on-Wi-Fi verdict for the Android snapshot source, set by
  /// [load]. False until [load] resolves, and set ONLY on a POSITIVE `notOnWifi`
  /// (a MEASURED `TRANSPORT_CELLULAR`); an `unknown` or failed read leaves it false
  /// so a wired Android TV and a tablet on Wi-Fi are never nagged (GL-005).
  bool _snapshotNotOnWifi = false;

  // ---- iOS (companion-Shortcut stream) ----
  WiFiDetailsBridge? _iosBridge;
  WifiMonitorController? _controller;
  WiFiDetails? _lastCharted;
  bool _wasStreaming = false;
  bool _triggerError = false;

  late final WifiTimeSeries _series;

  /// Roam log for THIS session — records BSSID transitions within the same SSID
  /// as samples arrive (Feature 2, Felix 2026-06-13). Fed from the same per-
  /// platform sample path that feeds the sparkline series, so it rides the
  /// existing Shortcut bridge / CoreWLAN poll with no new permission or plugin.
  final RoamDetector _roamDetector = RoamDetector();

  bool _disposed = false;

  /// True only after [start] was deliberately invoked in THIS screen session.
  ///
  /// Why this exists (iOS first-run bug, 2026-06-07): the underlying
  /// [WifiMonitorController.load] resumes its phase to `streaming` whenever the
  /// persisted App Group monitoring flag is still set — a flag that can be left
  /// stale `true` when a prior session's looping companion Shortcut was killed
  /// without a clean Stop (the flag is only cleared by [stop], not by dispose).
  /// On that resume the controller merely re-subscribes passively; it does NOT
  /// re-fire the recursive Shortcut, so no producer exists and no sample ever
  /// arrives. The Test My Connection live card read `isStreaming` alone and so
  /// rendered a "LIVE" header with nothing behind it — the dead/stuck first-run
  /// state Keith hit. Gating the live presentation on a real in-session [start]
  /// (this flag) makes the card show the actionable Start control instead, with
  /// no auto-fire (the Shortcut still only runs on the user's deliberate tap).
  bool _startedThisSession = false;

  /// The rolling 30s window of RF samples that feeds the sparklines.
  WifiTimeSeries get series => _series;

  /// The roam log for this session — BSSID transitions within the same SSID,
  /// oldest→newest. Feature 2 (Felix 2026-06-13). Foreground-session scope on
  /// iOS (no background Wi-Fi callbacks exist); macOS polls continuously while
  /// the screen is open.
  List<RoamEvent> get roamEvents => _roamDetector.events;

  /// Number of roams recorded this session.
  int get roamCount => _roamDetector.count;

  /// True only on iOS (the companion-Shortcut source). macOS auto-polls and
  /// never shows Start/Stop.
  bool get isIos => source == WifiInfoSource.iosShortcuts;

  /// Whether this platform can ever produce a live feed (macOS + Android +
  /// Windows + iOS). web / unsupported render the honest unavailable state
  /// instead of the card. Delegates to the static [isSupportedSource] so the
  /// instance answer and the pre-construction answer a screen gates on can never
  /// diverge.
  bool get isSupported => isSupportedSource(source);

  /// The SSOT for "can this [WifiInfoSource] ever back a live RF feed?" — the
  /// single predicate every live-signal consumer (the Roaming Log, Test My
  /// Connection, the Wi-Fi-signal sparkline card) must gate on instead of
  /// carrying its own inline platform list. That inline-list drift is exactly
  /// what darkened Windows on the roaming log (bug C3): the screen enumerated
  /// {macOS, Android, iOS} itself and forgot Windows, while this sampler polls
  /// Windows just like macOS/Android.
  ///
  /// macOS/Android/Windows poll a snapshot [WifiInfoAdapter]; iOS streams the
  /// companion Shortcut. A NEW native adapter wired into the constructor switch
  /// above (e.g. a future desktop-Linux source) MUST be added here in the same
  /// change — the consistency harness
  /// (test/consistency/platform_capability_invariant_test.dart) asserts this
  /// predicate stays in lock-step with the constructor's live-feed branches, so
  /// an omission fails a test rather than silently shipping a false "monitoring
  /// is off on this device".
  static bool isSupportedSource(WifiInfoSource source) =>
      source == WifiInfoSource.macosCoreWlan ||
      source == WifiInfoSource.androidWifiManager ||
      source == WifiInfoSource.windowsNativeWifi ||
      source == WifiInfoSource.iosShortcuts;

  /// The latest connected-AP reading from whichever feed is active. Null until
  /// the first sample lands (or on an unsupported platform).
  ConnectedAp? get latest {
    switch (source) {
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.androidWifiManager:
      case WifiInfoSource.windowsNativeWifi:
        return _macInfo;
      case WifiInfoSource.iosShortcuts:
        final WiFiDetails? d = _controller?.details;
        return d == null ? null : ConnectedAp.fromWifiDetails(d);
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        return null;
    }
  }

  /// True while the iOS live stream is running AS A RESULT OF A DELIBERATE,
  /// IN-SESSION [start]. Always false on macOS (which auto-polls with no
  /// Start/Stop) and on unsupported platforms.
  ///
  /// This is intentionally NOT a bare passthrough of the controller phase. A
  /// stale persisted monitoring flag can resume the controller to its
  /// `streaming` phase on [load] with no live producer behind it (see
  /// [_startedThisSession]); reporting that as "streaming" is what produced the
  /// dead "LIVE" first-run card. We only report streaming once the user has
  /// actually started the feed this session, so the card falls back to the
  /// actionable Start control whenever the feed is not genuinely live.
  bool get isStreaming =>
      _startedThisSession && (_controller?.isStreaming ?? false);

  /// Wall-clock time of the most recent iOS payload, for the "Updated" stamp.
  DateTime? get lastUpdated => _controller?.lastUpdated;

  /// Whether the iOS companion Shortcut has ever delivered a payload — drives
  /// the honest "install the Shortcut" hint exactly as wifi-info does.
  bool get hasEverReceived => _controller?.hasEverReceived ?? false;

  /// True in the post-install PRIMING window: the user started setup but no
  /// payload has completed the round-trip yet. Drives the "tap Get reading to
  /// finish; iOS asks permission the first time" priming step instead of the cold
  /// "Set up live Wi-Fi" prompt. Forwarded from [WifiMonitorController]. False off
  /// iOS / once a payload arrives.
  bool get setupInitiated => _controller?.setupInitiated ?? false;

  /// True when the last connection probe found the device is demonstrably NOT on
  /// Wi-Fi — drives the honest "connect to Wi-Fi" surface in the Wi-Fi-signal
  /// section instead of a stale reading under a LIVE badge, AND the cellular-data
  /// consent gate in Test My Connection. Honest: only ever set on a POSITIVE
  /// not-on-Wi-Fi signal, never from missing/ambiguous data.
  ///
  /// TWO SOURCES, ONE ANSWER:
  ///   * iOS     — [WifiMonitorController]'s probe flag (`_controller`).
  ///   * Android — [_snapshotNotOnWifi], settled by [load] from
  ///               [WifiConnectionService]'s MEASURED `TRANSPORT_CELLULAR` read.
  /// Always false on macOS / Windows / web / unsupported, where no honest negative
  /// exists to report.
  ///
  /// THE `?? false` USED TO BE THE WHOLE ANDROID BUG (round-4 cold review,
  /// 2026-07-14). `_controller` is constructed ONLY for
  /// `WifiInfoSource.iosShortcuts`, so on Android this getter was hard-wired to
  /// `false` — and Test My Connection's consent gate reads EXACTLY this. `notOnWifi`
  /// was therefore unreachable, `spendData` was unconditionally true, and the home
  /// hero's `autoStart: true` push auto-ran a full throughput measurement plus the
  /// RPM load generator (50-500 MB) on a cellular Android phone with ZERO TAPS. The
  /// fallback is no longer a constant: it is the Android probe's settled verdict.
  ///
  /// THE `&& !hasEverReceived` GATE IS GONE (2026-07-13, Keith on-device, v1.7.2).
  /// It was a SECOND copy of the same suppression that hid the honest state in
  /// [WifiMonitorController] — and it was NOT downstream of it: this getter reads
  /// the controller's RAW probe flag, so fixing the controller alone would have
  /// left Test My Connection still showing "Wi-Fi data rate 29 Mbps" under a
  /// green LIVE badge on a cellular-only phone. Any user who had EVER captured a
  /// Wi-Fi reading permanently satisfied `hasEverReceived`, so the honest card
  /// never fired for anyone real. There is no Wi-Fi link; there is no reading.
  bool get notOnWifi => _controller?.notOnWifi ?? _snapshotNotOnWifi;

  /// Set when the last iOS [start] could not open the companion Shortcut
  /// (Shortcuts missing / not installed). Surfaced as the honest live error.
  bool get triggerError => _triggerError;

  /// True once a trigger OPENED but a deleted "WLAN Pros Live" Shortcut delivered
  /// no payload within the settle window on a first-ever run (iOS reports the
  /// open as a success even for a deleted Shortcut, so this is the only honest
  /// missing-signal). Forwarded from [WifiMonitorController.shortcutMissing] and
  /// flips asynchronously after the settle, so the screen ORs it with
  /// [triggerError] to fire the in-tool reinstall card. False off iOS.
  bool get shortcutMissing => _controller?.shortcutMissing ?? false;

  /// Begins the platform feed. On macOS this seeds the first reading and arms
  /// the auto-poll; on iOS it raises the monitoring flag and fires the trigger
  /// once. Idempotent on macOS (re-arming cancels any prior timer first).
  Future<void> start() async {
    _startedThisSession = true;
    switch (source) {
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.androidWifiManager:
      case WifiInfoSource.windowsNativeWifi:
        await _pollMac(); // seed
        _startMacPoll();
      case WifiInfoSource.iosShortcuts:
        final WifiMonitorController? c = _controller;
        if (c == null) return;
        _triggerError = false;
        _safeNotify();
        final bool opened = await c.startMonitoring(
          triggerShortcutName: WifiLiveShortcutsConfig.kLiveShortcutName,
        );
        if (!opened) {
          // The recursion never started (no producer) — surface the honest
          // error and clear the flag, mirroring wifi-info.
          _triggerError = true;
          _safeNotify();
          await c.stopMonitoring();
        }
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        break;
    }
  }

  /// ONE-SHOT live read (2026-06-23, Keith): fire the companion Shortcut ONCE and
  /// capture a single payload WITHOUT raising the persistent monitoring flag, so
  /// the iOS status banner flashes for the one run and then clears on its own (no
  /// continuous loop). This is the DEFAULT live read; [start] (continuous) is the
  /// opt-in. The single payload still flows into [latest] and the sparkline
  /// series via the controller's transient capture, so a one-shot reading appears
  /// on screen and in any copy exactly like a streamed sample — just one of them.
  ///
  /// iOS-only behavior. On macOS / Android / Windows the snapshot poll already
  /// reads natively with no Shortcut, so this delegates to a single [_pollMac]
  /// seed and returns true. Returns false on iOS only when the trigger could not
  /// be opened (Shortcut missing) so the caller surfaces the honest setup hint.
  Future<bool> getReadingOnce() async {
    switch (source) {
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.androidWifiManager:
      case WifiInfoSource.windowsNativeWifi:
        await _pollMac();
        return true;
      case WifiInfoSource.iosShortcuts:
        final WifiMonitorController? c = _controller;
        if (c == null) return false;
        _triggerError = false;
        _safeNotify();
        final bool opened = await c.getReadingOnce(
          triggerShortcutName: WifiLiveShortcutsConfig.kLiveShortcutName,
        );
        if (!opened) {
          _triggerError = true;
          _safeNotify();
        }
        return opened;
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        return false;
    }
  }

  /// Polls the persisted iOS payload after a one-shot fire settles, in case the
  /// single streamed sample raced the app's foreground return. No-op off iOS.
  Future<void> pollLatestAfterOneShot() async {
    if (source == WifiInfoSource.iosShortcuts) {
      await _controller?.pollLatestAfterOneShot();
    }
  }

  /// Resolves the iOS install-state + any persisted monitoring flag (so a
  /// payload delivered while backgrounded lands and an active loop resumes), and
  /// the honest Wi-Fi connection state (so a cellular user gets the "connect to
  /// Wi-Fi" surface instead of a dead waiting state, and the cellular-data consent
  /// gate fires BEFORE any data is spent). Call on first build and on app resume.
  ///
  /// AWAITING THIS IS LOAD-BEARING ON ANDROID, NOT HOUSEKEEPING. Test My
  /// Connection's `_autoStart` awaits `_retryConnection()` → this method → and only
  /// THEN reads [notOnWifi] to decide whether to run. Before round 4b this was a
  /// NO-OP off iOS, so the await returned instantly, [notOnWifi] was still the
  /// hard-wired `false`, and the app's primary entry point auto-spent a cellular
  /// Android user's data on frame one. The probe must SETTLE inside this await.
  ///
  /// macOS / Windows: STILL A NO-OP, deliberately. `_connectionService` is null
  /// there by construction (see the constructor), so this returns without a
  /// platform-channel round-trip that could not change any answer.
  ///
  /// [nativeSsid] is the optional native SSID the screen reads (NEHotspotNetwork on
  /// iOS); a non-empty value is a definitive "on Wi-Fi" signal (its absence is
  /// never used to assert "not on Wi-Fi"). See [WifiConnectionService].
  Future<void> load({String? nativeSsid}) async {
    switch (source) {
      case WifiInfoSource.iosShortcuts:
        final WifiMonitorController? c = _controller;
        if (c == null) return;
        await c.load(nativeSsid: nativeSsid);
        // ====================================================================
        // ADOPT A LIVE LOOP INHERITED ACROSS A SCENE REBUILD.
        // (2026-07-14, Keith device — the ~5-second death.)
        //
        // THIS BLOCK USED TO BE THE KILLER:
        //
        //     if (!_startedThisSession && c.isStreaming) {
        //       await c.stopMonitoring();   // <- destroyed a HEALTHY loop
        //     }
        //
        // Starting the feed BACKGROUNDS THE APP INTO SHORTCUTS BY DESIGN — that is
        // how the recursion is kicked off. Returning can REBUILD THE SCENE, which
        // constructs a FRESH sampler whose `_startedThisSession` is false, over a
        // monitoring flag that is still true BECAUSE THE LOOP IS GENUINELY RUNNING.
        // This guard read that as "a stale leftover from a previous session" and
        // cleared the flag — killing the recursion the user had just started. It
        // survived exactly as long as it took Keith to walk back from the Shortcuts
        // app: about five seconds, twice, on his phone.
        //
        // `_startedThisSession` is a fact about THE WIDGET. Whether a loop is
        // running is a fact about THE LOOP. Using the first to decide the second is
        // the entire bug, and no amount of tuning this flag can fix a category
        // error.
        //
        // THE DECISION HAS MOVED TO [WifiMonitorController.load], where it belongs:
        // it adopts the stream only when the APP GROUP'S PAYLOAD STAMP proves a
        // recent delivery, and tears the flag down otherwise. That witness lives
        // BELOW the app's lifecycle, so it survives the very rebuild that broke
        // this — and Wi-Fi Information, which drives the controller DIRECTLY and
        // never had this guard at all, now inherits the same protection from the
        // same place.
        //
        // So by the time we get here the controller has already settled it. If it
        // is streaming, there is a REAL PRODUCER behind the flag, and this session
        // has a live feed — whether this widget started it or inherited it. Record
        // that, so [isStreaming] reports the truth and the card renders LIVE
        // instead of an actionable Start control over a running stream.
        // ====================================================================
        if (c.isStreaming) {
          _startedThisSession = true;
          _safeNotify();
        }
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.androidWifiManager:
      case WifiInfoSource.windowsNativeWifi:
        // Android only — `_connectionService` is null on macOS / Windows, so this
        // is still the no-op it has always been there.
        final WifiConnectionService? svc = _connectionService;
        if (svc == null) return;
        final WifiConnectionStatus status =
            await svc.status(nativeSsid: nativeSsid);
        if (_disposed) return;
        // ONLY a POSITIVE verdict raises the flag. `unknown` (a wired Android TV, a
        // VPN that hides its underlying transport, a read that failed) LOWERS it —
        // it does not latch — because the device genuinely may have moved back onto
        // Wi-Fi and a stale `true` would nag a user who is no longer paying per
        // byte. Never inferred, never defaulted, in either direction (GL-005).
        final bool next = status == WifiConnectionStatus.notOnWifi;
        if (next != _snapshotNotOnWifi) {
          _snapshotNotOnWifi = next;
          _safeNotify();
        }
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        break;
    }
  }

  /// Stops the platform feed. On macOS this cancels the auto-poll (the last
  /// values stay on screen); on iOS it clears the monitoring flag so the
  /// looping Shortcut halts and freezes the last values.
  Future<void> stop() async {
    _startedThisSession = false;
    switch (source) {
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.androidWifiManager:
      case WifiInfoSource.windowsNativeWifi:
        _stopMacPoll();
      case WifiInfoSource.iosShortcuts:
        await _controller?.stopMonitoring();
        _safeNotify();
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        break;
    }
  }

  /// Re-arms the snapshot poll (macOS / Android / Windows) after an app-resume
  /// (no-op on the iOS stream / unsupported platforms).
  void resumeMac() {
    if (source == WifiInfoSource.macosCoreWlan ||
        source == WifiInfoSource.androidWifiManager ||
        source == WifiInfoSource.windowsNativeWifi) {
      _pollMac().then((_) => _startMacPoll());
    }
  }

  /// Pauses the snapshot poll (macOS / Android / Windows) while backgrounded
  /// (no-op elsewhere).
  void pauseMac() {
    if (source == WifiInfoSource.macosCoreWlan ||
        source == WifiInfoSource.androidWifiManager ||
        source == WifiInfoSource.windowsNativeWifi) {
      _stopMacPoll();
    }
  }

  // ---- macOS poll ----

  void _startMacPoll() {
    if (_disposed) return;
    _macPollTimer?.cancel();
    _macPollTimer = Timer.periodic(_macPollInterval, (_) => _pollMac());
  }

  void _stopMacPoll() {
    _macPollTimer?.cancel();
    _macPollTimer = null;
  }

  /// One CoreWLAN re-read. Silent on failure: the last good values and series
  /// stand; the next tick retries. Appends a sample only on a CHANGED reading
  /// so an unchanged poll does not pad the window (mirrors wifi-info).
  Future<void> _pollMac() async {
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null || _disposed) return;
    try {
      final ConnectedAp info = await adapter.fetch();
      if (_disposed) return;
      _macInfo = info;
      // Feed the roam detector EVERY fresh read — before the sparkline's
      // unchanged-RF guard — because a roam can land with identical RSSI/SNR/
      // rate (a new AP at the same signal), which the guard would otherwise drop.
      _roamDetector.observe(info);
      _appendMacSample(info);
      _safeNotify();
    } catch (_) {
      // Transient read failure: keep the last good snapshot + series.
    }
  }

  void _appendMacSample(ConnectedAp info) {
    final ConnectedAp? last = _macLastCharted;
    final bool unchanged = last != null &&
        info.rssiDbm == last.rssiDbm &&
        info.snrDb == last.snrDb &&
        info.txRateMbps == last.txRateMbps &&
        info.rxRateMbps == last.rxRateMbps;
    if (unchanged) return;
    _macLastCharted = info;
    _series.add(info);
  }

  // ---- iOS stream ----

  /// Controller listener: folds each NEW payload into the series, and clears the
  /// window on a fresh Stop→Start so a new session does not chart the previous
  /// one's stale samples. Mirrors wifi-info's `_captureSample`.
  void _onControllerChanged() {
    final WifiMonitorController? c = _controller;
    if (c == null) return;

    final bool streaming = c.isStreaming;
    if (streaming && !_wasStreaming) {
      _series.clear();
      _lastCharted = null;
      // A fresh Stop→Start is a new walk: drop the prior session's roam log so
      // it does not inherit stale BSSID transitions.
      _roamDetector.reset();
    }
    _wasStreaming = streaming;

    // Append any NEW LIVE payload regardless of streaming. A single one-shot
    // "Get reading" lands the controller in idleWithData (NOT streaming); the
    // earlier `if (streaming)` gate DROPPED that sample, so Test My Connection's
    // live-signal sparkline never rendered a one-shot reading (Keith device round
    // 4). Gate on [deliveryCount] so the load-restored STALE stored reading is not
    // charted on open; the `d != _lastCharted` value dedup keeps a settle-poll
    // re-delivery of the same payload from duplicating the last reading.
    final WiFiDetails? d = c.details;
    if (c.deliveryCount > 0 && d != null && d != _lastCharted) {
      _lastCharted = d;
      final ConnectedAp sample = ConnectedAp.fromWifiDetails(d);
      _roamDetector.observe(sample);
      _series.add(sample);
    }
    _safeNotify();
  }

  /// Samples held per field for a [_window] at [cadence].
  int _capacityFor(Duration cadence) {
    final int n = (_window.inMilliseconds / cadence.inMilliseconds).ceil();
    return n < 1 ? 1 : n;
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopMacPoll();
    final WifiMonitorController? c = _controller;
    c?.removeListener(_onControllerChanged);
    // ALWAYS clear the iOS loop-gate flag on teardown (Option B defensive clear)
    // — not only when streaming — so leaving Test My Connection can never strand
    // the external "WLAN Pros Live" loop as "keep going". dispose is a permanent
    // teardown, never a Shortcut bounce; a stale/adopted flag must be cleared.
    // No-op off iOS (stopMonitoring writes a flag no non-iOS Shortcut reads).
    c?.stopMonitoring();
    c?.dispose();
    super.dispose();
  }
}
