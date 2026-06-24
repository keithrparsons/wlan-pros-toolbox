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
        // 30s window at a 2s poll → ~15 samples (ceil so the full window fits).
        _series = WifiTimeSeries(capacity: _capacityFor(_macPollInterval));
      case WifiInfoSource.iosShortcuts:
        _iosBridge = iosBridge ?? WiFiDetailsBridge();
        _controller = WifiMonitorController(bridge: _iosBridge!);
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

  /// Whether this platform can ever produce a live feed (macOS + Android + iOS).
  /// web / unsupported render the honest unavailable state instead of the card.
  bool get isSupported =>
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

  /// Set when the last iOS [start] could not open the companion Shortcut
  /// (Shortcuts missing / not installed). Surfaced as the honest live error.
  bool get triggerError => _triggerError;

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
  /// payload delivered while backgrounded lands and an active loop resumes).
  /// No-op on macOS. Call on first build and on app resume.
  Future<void> load() async {
    if (source == WifiInfoSource.iosShortcuts) {
      final WifiMonitorController? c = _controller;
      if (c == null) return;
      await c.load();
      // If load() resumed the controller to `streaming` purely from a stale
      // persisted monitoring flag (no deliberate in-session start, so no live
      // producer), tear that phantom stream down and clear the flag. This is
      // the iOS first-run fix: without it the card would read `isStreaming` and
      // render a dead "LIVE" header with no data behind it. We do NOT auto-fire
      // the Shortcut here — we drop back to the honest idle state so the card
      // shows the actionable Start control, which the user taps to begin.
      if (!_startedThisSession && c.isStreaming) {
        await c.stopMonitoring();
        _safeNotify();
      }
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

  /// Controller listener: folds each NEW streamed payload into the series, and
  /// clears the window on a fresh Stop→Start so a new session does not chart the
  /// previous one's stale samples. Mirrors wifi-info's `_captureSample`.
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

    if (streaming) {
      final WiFiDetails? d = c.details;
      if (d != null && d != _lastCharted) {
        _lastCharted = d;
        final ConnectedAp sample = ConnectedAp.fromWifiDetails(d);
        _roamDetector.observe(sample);
        _series.add(sample);
      }
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
    if (c != null && c.isStreaming) {
      c.stopMonitoring();
    }
    c?.dispose();
    super.dispose();
  }
}
