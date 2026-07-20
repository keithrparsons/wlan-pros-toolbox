// Wi-Fi Information, the one cross-platform connected-AP tool (TICKET-04).
//
// Consolidates the former macOS-only "Wi-Fi Information" and iOS-only "Wi-Fi
// Details" tools into a SINGLE tool (id/route `wifi-info`, name "Wi-Fi
// Information"). The data source is selected per platform behind the
// [WifiInfoSourceResolver] seam, and every source maps into the normalized
// [ConnectedAp] model:
//
//   * macOS -> CoreWLAN snapshot ([MacWifiInfoAdapter]). Pull + Refresh, with the
//             Location-permission states (SSID/BSSID are gated by macOS Location
//             Services). No Shortcut, no trigger on macOS.
//   * iOS   -> LIVE streaming ONLY. The combined "WLAN Pros Live" companion
//             Shortcut feeds the App Group + Darwin stream each cycle; the screen
//             passively renders the live RF fields (sparklines + grading). Start
//             raises the monitoring flag and fires the PLAIN, fire-and-forget
//             run-shortcut trigger once; Stop clears the flag and FREEZES the last
//             values on screen (the snapshot). There is no separate one-tap "Get
//             Reading" snapshot on iOS, Live is the only iOS mode.
//   * Android -> snapshot via WifiManager (AndroidWifiInfoAdapter); pull to
//             refresh. No noise floor / SNR on this platform, so those render
//             the honest "Unavailable" row rather than a derived value.
//   * Windows -> snapshot via Native Wifi (WindowsWifiInfoAdapter); pull to
//             refresh. Same no-noise/SNR ceiling as Android.
//   * web -> download-the-app fallback.
//
// Both native bridges are retained (macOS WifiInfoChannel.swift + iOS
// ToolboxAppIntents/ShortcutsBridge.swift). Per GL-008/GL-005 a field a platform
// cannot expose renders an explicit "Unavailable" row with a precise reason --
// never a fabricated value, never a silent drop.
//
// THE LOCATION GATE IS TRI-STATE, NOT BOOLEAN (load-bearing). Neither gated
// platform will re-prompt once the authorization has left `notDetermined`:
// macOS TCC never asks twice, and Android stops asking after a permanent
// denial. A Location card that offers an in-app "Grant Location" button in
// every unauthorized state therefore renders a control that is GUARANTEED to do
// nothing under `denied` / `restricted` -- no prompt, no error, no navigation.
// Keith hit exactly that on the AP scan screen in a live deployment and clicked
// it repeatedly. This screen has held the tri-state `_nameAuth` since the
// permission read was added and simply never consulted it for this decision.
// It does now, and [_LocationCard] takes `promptable` as a REQUIRED parameter
// so a future call site cannot omit the state and quietly reintroduce the
// button: `notDetermined` renders the grant, `denied` / `restricted` render the
// System Settings deep-link as the SOLE and PRIMARY action. The copy moves with
// the control, because telling a denied user to grant Location in-app is the
// prose form of the same dead button. See
// [[feedback_ui_rendered_a_decision_it_lacked]]: the defect is the missing
// state, not the button. Tests: wifi_info_permission_flow_test.dart drives all
// four states, `denied` and `restricted` included, which no test on this screen
// had ever done.
//
// States (SOP-007 section 5):
//   * web / unsupported native -> NetworkUnavailableView / coming-soon.
//   * loading  -> macOS: labeled spinner (announced via liveRegion).
//   * empty/idle -> iOS: a clean "Tap Start to begin live readings" state.
//                macOS: covered by the location card or the error card.
//   * error    -> macOS: in-flow info/error card + retry. iOS: the Live trigger
//                error banner (Shortcut missing / cancelled).
//   * success  -> grouped metric cards (macOS) / live charts (iOS streaming).
//   * disabled -> macOS Grant button hides after a grant.
//   * interactive -> Refresh / Grant (macOS); Start / Stop (iOS).
//
// Layout matches interface_info_screen / net_quality_screen: SafeArea +
// LayoutBuilder + centered ConstrainedBox + scroll, surface1 cards with a
// hairline border, mono for addresses/numerics, the concept-graphic band
// degrades to nothing when the tool has no graphic asset.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:net_quality/net_quality.dart' show QualityGrade, QualityGradeLabel;

import '../../../data/tool_assets.dart';
import '../../../router/app_router.dart';
import '../../../services/network/connected_ap.dart';
import '../../../services/network/connected_ap_cache.dart';
import '../../../services/network/live_onboarding_service.dart';
import '../../../services/network/mac_oui_service.dart';
import '../../../services/network/mac_randomization.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/wifi_connection_service.dart';
import '../../../services/network/wifi_details.dart';
import '../../../services/network/wifi_details_bridge.dart';
import '../../../services/network/wifi_grading.dart';
import '../../../services/network/wifi_info_adapter.dart';
import '../../../services/network/wifi_info_service.dart';
import '../../../services/network/wifi_live_shortcuts_config.dart';
import '../../../services/network/wifi_monitor_controller.dart';
import '../../../services/network/wifi_security.dart';
import '../../../services/network/wifi_security_service.dart';
import '../../../services/network/wifi_time_series.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/sparkline.dart';
import '../concept_graphic_band.dart';
import 'install_shortcut_sheet.dart';
import 'setup_live_wifi_icon.dart';
import 'live_priming_card.dart';
import 'live_rf_locked_card.dart';
import 'live_setup_card.dart';
import 'not_on_wifi_card.dart';
import 'network_unavailable_view.dart';
import 'wifi_live_trend.dart';

/// The one Wi-Fi Information tool screen.
class WifiInfoScreen extends StatefulWidget {
  const WifiInfoScreen({
    super.key,
    this.sourceOverride,
    this.macAdapter,
    this.iosBridge,
    this.ouiService,
    this.securityService,
    this.connectedApCache,
    this.onboardingService,
    this.connectionService,
  });

  /// Forces a specific data source (tests). Defaults to the host platform.
  final WifiInfoSource? sourceOverride;

  /// Injectable shared connected-AP cache (tests). Defaults to the process-wide
  /// [ConnectedApCache.instance]. The Wi-Fi Information tool WRITES every
  /// reading it obtains here so the Interface Info tool can read the same
  /// identity without re-running the iOS Shortcut (Batch 8, item 1).
  final ConnectedApCache? connectedApCache;

  /// Injectable macOS adapter (tests). Defaults to the real CoreWLAN adapter.
  final WifiInfoAdapter? macAdapter;

  /// Injectable iOS bridge (tests). Defaults to the real Shortcuts bridge.
  final WiFiDetailsBridge? iosBridge;

  /// Injectable OUI vendor resolver (tests). When provided, the screen skips the
  /// asset load and uses this service for the AP-vendor row. Defaults to loading
  /// the bundled IEEE OUI table from `assets/oui/oui_table.tsv`.
  final MacOuiService? ouiService;

  /// Injectable iOS security service (tests). Defaults to the real
  /// NEHotspotNetwork channel. Only used on the iOS source.
  final WifiSecurityService? securityService;

  /// Injectable first-run onboarding gate (tests). Defaults to the real
  /// shared_preferences-backed service. iOS-only — drives the unmissable
  /// one-time "enable live Wi-Fi" sheet the first time a live tool is opened.
  final LiveOnboardingService? onboardingService;

  /// Injectable honest "is this device on Wi-Fi?" probe (tests). Defaults to the
  /// real [WifiConnectionService] (a native, permission-free `getWifiIP()`
  /// read). iOS-only — drives the [WifiMonitorController]'s notOnWifi phase so a
  /// cellular-only device sees the honest "connect to Wi-Fi" card. Tests inject a
  /// deterministic probe so the live flow runs against a known on-/off-Wi-Fi
  /// state without touching a platform channel.
  final WifiConnectionService? connectionService;

  /// Poll cadence for the macOS CoreWLAN re-read. Overridable in tests so the
  /// poll can be pumped deterministically.
  @visibleForTesting
  static Duration macPollInterval = const Duration(seconds: 2);

  /// When false, the macOS poll timer is never armed. Tests that exercise the
  /// one-shot snapshot path without a ticking timer set this to disable it.
  @visibleForTesting
  static bool macPollEnabled = true;

  @override
  State<WifiInfoScreen> createState() => _WifiInfoScreenState();
}

class _WifiInfoScreenState extends State<WifiInfoScreen>
    with WidgetsBindingObserver {
  late final WifiInfoSource _source;

  /// Shared app-wide cache the tool WRITES every reading into (Batch 8, item 1),
  /// so Interface Info can show the same SSID/BSSID/etc. without re-bouncing to
  /// the iOS Shortcut. Resolved once in [initState] from the injected cache or
  /// the process-wide singleton.
  late final ConnectedApCache _apCache;

  // ---- macOS (CoreWLAN snapshot) state ----
  WifiInfoAdapter? _macAdapter;
  bool _macLoading = false;
  ConnectedAp? _macInfo;
  WifiInfoUnavailable? _macError;
  bool _locationGrantAttempted = false;

  /// The current name-gating (Location) authorization for the snapshot source,
  /// or null until the first no-prompt status read resolves. Only meaningful
  /// when the active adapter gates the network name behind an OS permission
  /// (macOS Location Services / Android ACCESS_FINE_LOCATION); it stays
  /// null/irrelevant for ungated sources (Windows Native Wifi). This is what
  /// lets the SSID/BSSID rows name the REAL cause: a not-authorized status makes
  /// them read the actionable "Needs Location permission" instead of a flat,
  /// misleading "Unavailable", while an authorized-but-empty read (a genuinely
  /// disconnected / hidden network — NOT a permission problem) falls back to the
  /// plain unavailable. Read via the adapter's [WifiInfoAdapter.nameAuthorizationStatus]
  /// no-prompt seam (never surfaces a system prompt). See [_nameGateNote].
  LocationAuthStatus? _nameAuth;

  /// Rolling window of CoreWLAN snapshots for the macOS sparklines. macOS reads
  /// the same RF fields as iOS (RSSI / SNR / Tx rate), so the SAME [_LiveCharts]
  /// surface renders from a series fed by automatic polling rather than a stream.
  WifiTimeSeries? _macSeries;

  /// The last snapshot folded into [_macSeries], so the poll appends one sample
  /// per CHANGED reading (an unchanged poll does not duplicate the window).
  ConnectedAp? _macLastCharted;

  /// Automatic CoreWLAN poll. macOS has no Start/Stop, it polls while the
  /// screen is mounted (CoreWLAN is local and cheap) and the timer is cancelled
  /// in [dispose]. Paused while the app is backgrounded (lifecycle observer).
  Timer? _macPollTimer;

  // ---- iOS (Live streaming) state ----
  WiFiDetailsBridge? _iosBridge;

  /// Live monitoring state machine, built lazily on the iOS path. Owns the
  /// stream subscription, the monitoring flag, and the recursion kickoff.
  WifiMonitorController? _liveController;

  /// Rolling window of streamed RF fields for the Live sparklines + grading.
  WifiTimeSeries? _series;

  /// The last details object folded into [_series], so the listener appends one
  /// sample per NEW payload (the controller notifies on phase changes too).
  WiFiDetails? _lastCharted;

  /// Whether the controller was streaming on the previous notification, so a
  /// Stop->Start transition clears the window (a new session does not chart the
  /// previous one's stale samples).
  bool _wasStreaming = false;

  /// Set when the last Live Start could not open the Live Shortcut (Shortcuts
  /// missing / not installed). Surfaced as the honest error in the Live bar.
  bool _liveTriggerError = false;

  /// True from the instant Live Start fires the companion Shortcut until the app
  /// has returned to the foreground after that Shortcut run completes.
  ///
  /// On iOS the Live trigger opens the Shortcuts app (`UIApplication.shared.open`
  /// in AppDelegate.runShortcut), which VISIBLY backgrounds the Toolbox and then
  /// foregrounds it again when the run returns. That background→foreground bounce
  /// is caused by the app itself, NOT by the user leaving and coming back. This
  /// flag lets [didChangeAppLifecycleState] tell the two apart: while it is set,
  /// the lifecycle transitions are the Shortcut round-trip and MUST NOT stop
  /// sampling or (critically) re-fire the Shortcut. Re-firing on that
  /// app-induced foreground was the runaway: fire → background → resume →
  /// fire → background → … an unbreakable loop the user had to force-kill. The
  /// foreground that clears this flag never re-arms anything; the stream simply
  /// keeps running off the already-recursing Shortcut.
  bool _shortcutBounceInFlight = false;

  /// Guards [_startLive] against re-entrancy. A Shortcut trigger may only be
  /// fired by an explicit user tap, never automatically, and never while a
  /// previous trigger's bounce is still resolving. Belt-and-suspenders on top of
  /// [_shortcutBounceInFlight]: even a stray programmatic call cannot chain one
  /// Shortcut run into the next.
  bool _startInFlight = false;

  // ---- AP-vendor (OUI) lookup state (both platforms) ----

  /// Bundled IEEE OUI resolver. Loaded once from the bundled asset (or injected
  /// in tests). Null until the load completes; the AP-vendor row shows a brief
  /// "loading the vendor database" note until then. The lookup is fully offline.
  MacOuiService? _ouiService;

  // ---- iOS native security + BSSID state (NEHotspotNetwork) ----

  /// iOS-only service that reads the coarse security token + BSSID directly via
  /// NEHotspotNetwork. The RF metrics still arrive via the Shortcut; this fills
  /// the two entitlement-gated fields the Shortcut path does not carry.
  WifiSecurityService? _securityService;

  /// The latest native iOS security read, or null before the first read. Carries
  /// the coarse security token, the BSSID, and the honest unavailable reason.
  WifiSecurityInfo? _iosSecurity;

  // ---- iOS first-run onboarding state ----

  /// iOS-only first-run gate. Decides whether the unmissable one-time "enable
  /// live Wi-Fi" sheet fires on the first open of a live tool.
  LiveOnboardingService? _onboardingService;

  /// Guards the first-run sheet so it fires at most once per screen mount even
  /// if [initState]'s async check overlaps a rebuild. Retained with
  /// [_maybeShowFirstRunOnboarding] for the inline opt-in path; the AUTO-FIRE was
  /// removed 2026-06-23 (native-first) but the gate logic stays intact.
  // ignore: unused_field
  bool _firstRunChecked = false;

  @override
  void initState() {
    super.initState();
    _source = widget.sourceOverride ?? WifiInfoSourceResolver.resolve();
    _apCache = widget.connectedApCache ?? ConnectedApCache.instance;
    _loadOuiTable();

    switch (_source) {
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.androidWifiManager:
      case WifiInfoSource.windowsNativeWifi:
        // The macOS CoreWLAN, Android WifiManager, and Windows Native Wifi
        // sources are all pull-only snapshot adapters behind the SAME
        // [WifiInfoAdapter] seam and render the SAME snapshot body; only the
        // per-field platform label differs (see [_snapshotPlatformLabel]). Pick
        // the right adapter for the source, then drive the shared snapshot flow.
        _macAdapter = widget.macAdapter ??
            switch (_source) {
              WifiInfoSource.androidWifiManager => AndroidWifiInfoAdapter(),
              WifiInfoSource.windowsNativeWifi => WindowsWifiInfoAdapter(),
              // macOS decodes the connected AP's advertised name from its beacon
              // IEs (best-effort, Location-gated, honest-null) so the Network card
              // can show it next to the BSSID.
              _ => MacWifiInfoAdapter(enrichApName: true),
            };
        _macSeries = WifiTimeSeries();
        WidgetsBinding.instance.addObserver(this);
        // Seed the first reading, then begin automatic polling so the
        // sparklines start filling without a Start button.
        _fetchMac().then((_) => _startMacPoll());
      case WifiInfoSource.iosShortcuts:
        _iosBridge = widget.iosBridge ?? WiFiDetailsBridge();
        // Record this as the origin tool so a missing-Shortcut x-error routes the
        // user back HERE (and the recovery card) instead of the home strand.
        _iosBridge!.setLiveOriginRoute(AppRouter.wifiInfo);
        _liveController = WifiMonitorController(
          bridge: _iosBridge!,
          connectionService: widget.connectionService,
        );
        _series = WifiTimeSeries();
        _liveController!.addListener(_captureSample);
        _securityService = widget.securityService ?? WifiSecurityService();
        _onboardingService = widget.onboardingService ?? LiveOnboardingService();
        WidgetsBinding.instance.addObserver(this);
        // Resolve install-state on entry. NO auto-fire (2026-06-26, Keith device
        // round 5): with Get reading removed, the single live action is the
        // explicit Start Live Monitoring tap, so the screen never bounces a
        // browsing user into Shortcuts on open.
        _liveController!.load(nativeSsid: _nativeSsid);
        // Read the native security type + BSSID once on open. Re-read on resume
        // (lifecycle) so a Location grant in Settings lands without a relaunch.
        _fetchIosSecurity();
        // NATIVE-FIRST (2026-06-23, Keith): opening Wi-Fi Information must NOT
        // auto-pop the companion-Shortcut setup sheet. The native identity
        // (SSID / BSSID / security via NEHotspotNetwork) renders immediately and
        // the rich RF fields are offered through the inline, non-modal
        // LiveRfLockedCard / LiveSetupCard (and the About-row recovery). The
        // former auto-fire of [_maybeShowFirstRunOnboarding] was the forced modal
        // gate; it is removed here. The gate method stays intact (reachable via
        // the inline opt-in) so the one-time semantics and the 1.5.5 double-prompt
        // fix are preserved — only the AUTO-FIRE is removed.
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        break;
    }
  }

  /// True for the pull-only snapshot sources (macOS CoreWLAN, Android
  /// WifiManager). Both share the `_macAdapter` snapshot machinery, the poll
  /// timer, the location-grant flow, and the `_macBody` rendering — only the
  /// per-field platform label differs (see [_snapshotPlatformLabel]).
  bool get _isSnapshotSource =>
      _source == WifiInfoSource.macosCoreWlan ||
      _source == WifiInfoSource.androidWifiManager ||
      _source == WifiInfoSource.windowsNativeWifi;

  /// The per-field platform label the snapshot cards use in honest
  /// "not exposed by `<platform>`" copy. Each snapshot platform exposes a
  /// different field subset (Android + Windows have no noise/SNR), so the reason
  /// text names the real source.
  String get _snapshotPlatformLabel => switch (_source) {
        WifiInfoSource.androidWifiManager => 'Android',
        WifiInfoSource.windowsNativeWifi => 'Windows',
        _ => 'macOS CoreWLAN',
      };

  /// The platform that owns an unreadable-MAC reason note, so the "MAC type"
  /// note names the RIGHT OS limit (the S24 bug was the iOS "Apple does not
  /// expose…" reason leaking onto Android). iOS / Android each name their own
  /// real limitation; macOS reads the burned-in MAC directly so it falls to the
  /// generic note in the rare unreadable case.
  MacAddressPlatform get _macPlatform {
    switch (_source) {
      case WifiInfoSource.iosShortcuts:
        return MacAddressPlatform.ios;
      case WifiInfoSource.androidWifiManager:
        return MacAddressPlatform.android;
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.windowsNativeWifi:
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        return MacAddressPlatform.other;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS: stop the live sampling loop when the app genuinely leaves the
    // foreground, but NEVER auto-re-fire the Shortcut on return.
    //
    // The hard constraint: firing the Live Shortcut itself backgrounds the app
    // (it opens the Shortcuts app) and then foregrounds it again when the run
    // returns. That app-induced bounce is indistinguishable, at the lifecycle
    // level, from the user switching away and back — EXCEPT for the
    // [_shortcutBounceInFlight] flag the Start path sets. So:
    //
    //   * A background that is part of the Shortcut bounce is ignored (the
    //     recursion is meant to keep going; stopping it here would also fight
    //     the resume).
    //   * A genuine background (user left the app) stops sampling — the original
    //     auto-stop goal — and the last reading stays frozen on screen.
    //   * A foreground NEVER re-fires the Shortcut. The recursion, if still
    //     armed, keeps streaming on its own; if it was stopped, the user taps
    //     Start to resume. This is what makes a runaway impossible: there is no
    //     code path where returning to the foreground triggers another run.
    if (_source == WifiInfoSource.iosShortcuts) {
      if (state == AppLifecycleState.resumed) {
        // The Shortcut bounce has completed (or the user returned). Either way,
        // re-resolve so a payload delivered while we were backgrounded lands and
        // the persisted monitoring flag re-attaches the stream WITHOUT firing
        // the Shortcut. load() reads cache + re-subscribes only; it never opens
        // a URL, so it cannot loop.
        _shortcutBounceInFlight = false;
        _liveController?.load(nativeSsid: _nativeSsid);
        // Re-read the native security + BSSID so a Location grant made in
        // Settings (while backgrounded) lands without an app relaunch. This also
        // re-resolves the native SSID, so a user who joined Wi-Fi while away
        // re-triggers an on-Wi-Fi re-check on the next load (e.g. from the
        // not-on-Wi-Fi "I'm on Wi-Fi now" retry).
        _fetchIosSecurity();
      } else if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        // Ignore the background half of the Shortcut bounce — that backgrounding
        // is the app opening Shortcuts, not the user leaving, and the recursion
        // is supposed to continue.
        if (_shortcutBounceInFlight) return;
        // A genuine background: ALWAYS clear the loop-gate flag so the recursive
        // Shortcut halts on its next check — unconditionally, not only when we
        // believe we're streaming. A stale or adopted flag (or a one-shot in
        // flight) must never keep the external loop alive after the user leaves.
        // The last values stay frozen on screen; the user re-taps Start to resume
        // — no auto-resume, no loop. (Option B defensive clear.)
        _liveController?.stopMonitoring();
      }
    }

    // Snapshot sources (macOS CoreWLAN / Android WifiManager): pause the poll
    // while backgrounded (no point re-reading a link the user cannot see),
    // resume + re-read on return to foreground.
    if (_isSnapshotSource) {
      if (state == AppLifecycleState.resumed) {
        _fetchMac().then((_) => _startMacPoll());
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        _stopMacPoll();
      }
    }
  }

  @override
  void dispose() {
    if (_isSnapshotSource) {
      WidgetsBinding.instance.removeObserver(this);
      _stopMacPoll();
    }
    if (_source == WifiInfoSource.iosShortcuts) {
      WidgetsBinding.instance.removeObserver(this);
      // Hygiene: leaving the screen clears the monitoring flag so the recursive
      // Shortcut stops on its next check and the other tool is never stranded as
      // "streaming".
      final WifiMonitorController? controller = _liveController;
      // Detach the listener FIRST so the stopMonitoring() notify below does not
      // re-enter _captureSample's setState on a defunct element.
      controller?.removeListener(_captureSample);
      // ALWAYS clear the flag on teardown (Option B defensive clear) — not only
      // when streaming — so leaving the screen can never strand the external loop
      // as "keep going". dispose is a permanent teardown, never a Shortcut bounce.
      controller?.stopMonitoring();
      controller?.dispose();
    }
    super.dispose();
  }

  /// Controller listener (iOS Live): appends a NEW payload to [_series] — whether
  /// it arrived from the continuous stream OR a single one-shot "Get reading".
  /// Guarded so the many non-sample notifications (phase changes, Start/Stop) do
  /// not duplicate the last reading into the window.
  void _captureSample() {
    final WifiMonitorController? c = _liveController;
    final WifiTimeSeries? series = _series;
    if (c == null || series == null) return;

    final bool streaming = c.isStreaming;
    // Fresh Stop->Start: drop the previous session's window.
    if (streaming && !_wasStreaming) {
      series.clear();
      _lastCharted = null;
    }
    _wasStreaming = streaming;

    if (mounted) setState(() {}); // reflect live indicator / timestamp ticks

    // Append any NEW LIVE payload regardless of streaming. A one-shot "Get
    // reading" lands the controller in idleWithData (NOT streaming); the earlier
    // `if (!streaming) return` silently DROPPED that single sample, so a normal
    // post-setup Get reading delivered a payload but the screen stayed on the
    // pre-payload card with no reading shown (Keith device round 4). Gate on
    // [deliveryCount] so the load-restored STALE stored reading is not charted on
    // open (only fresh one-shot / stream deliveries advance it). The
    // `d == _lastCharted` value dedup keeps a settle-poll re-delivery of the same
    // payload from duplicating the last reading.
    final WiFiDetails? d = c.details;
    if (c.deliveryCount == 0 || d == null || d == _lastCharted) return;
    _lastCharted = d;
    final ConnectedAp reading = ConnectedAp.fromWifiDetails(d);
    series.add(reading);
    // Share the security-enriched reading app-wide (item 1): Interface Info then
    // shows this SSID/BSSID without re-bouncing the user to the Shortcut.
    _apCache.update(_enrichIos(reading));
  }

  /// Live Start: raise the monitoring flag AND fire the recursive Shortcut once
  /// to kick off the stream. The app then passively consumes the bridge updates;
  /// it never loops itself.
  ///
  /// Re-entrancy guarded. Firing the Shortcut backgrounds the app and then
  /// foregrounds it on return; this must be the ONLY place a Shortcut run is
  /// triggered, and it must run only once per explicit user tap.
  /// [_startInFlight] rejects an overlapping call, and [_shortcutBounceInFlight]
  /// tells the lifecycle observer the following background→foreground is the
  /// Shortcut round-trip, not a user app-switch — so the observer neither stops
  /// the stream nor re-fires the trigger. Together they make a self-sustaining
  /// loop impossible: nothing automatic can chain one run into another.
  Future<void> _startLive() async {
    final WifiMonitorController? c = _liveController;
    if (c == null) return;
    if (_startInFlight) return; // re-entrancy guard: never chain a second run
    _startInFlight = true;
    // Mark the imminent Shortcut bounce BEFORE the trigger fires, so the
    // background it causes is recognized as the round-trip and ignored.
    _shortcutBounceInFlight = true;
    setState(() => _liveTriggerError = false);
    try {
      final bool opened = await c.startMonitoring(
        triggerShortcutName: WifiLiveShortcutsConfig.kLiveShortcutName,
      );
      if (!mounted) return;
      if (!opened) {
        // Could not open the Shortcut. There is no bounce coming, so clear the
        // in-flight marker now. Surface the honest error immediately, then clear
        // the monitoring flag (the recursion never started, so there is no
        // producer). Showing the error first means the banner does not wait on
        // the stop cleanup completing.
        _shortcutBounceInFlight = false;
        setState(() => _liveTriggerError = true);
        await c.stopMonitoring();
      }
    } finally {
      _startInFlight = false;
    }
  }

  /// Live Stop: clear the monitoring flag so the recursive Shortcut halts on its
  /// next `ShouldContinueMonitoringIntent` check. The last values stay frozen on
  /// screen (the snapshot).
  Future<void> _stopLive() async {
    await _liveController?.stopMonitoring();
    if (mounted) setState(() {});
  }

  /// iOS first-run: fires the unmissable one-time "enable live Wi-Fi" sheet on
  /// the first open of a live tool, gated by the honest composite signal —
  /// the app has NEVER received a Live payload AND the sheet has not been shown
  /// before. Marks the sheet seen the instant it is presented so it never nags
  /// (the persisted flag plus the App Group hasEverReceived signal make this
  /// truly one-time). No-op off the iOS source. Never throws.
  // ignore: unused_element
  Future<void> _maybeShowFirstRunOnboarding() async {
    if (_firstRunChecked) return;
    _firstRunChecked = true;
    final LiveOnboardingService? svc = _onboardingService;
    final WiFiDetailsBridge? bridge = _iosBridge;
    if (svc == null || bridge == null) return;
    final bool everReceived = await bridge.hasEverReceivedPayload();
    final bool show = await svc.shouldShowOnboarding(
      hasEverReceivedPayload: everReceived,
    );
    if (!show || !mounted) return;
    // Mark seen BEFORE awaiting the sheet so a rapid second open cannot queue a
    // second sheet, and so it is one-time even if the user dismisses it.
    await svc.markOnboardingSeen();
    if (!mounted) return;
    await _openInstallSheet();
  }

  /// iOS: re-checks the Wi-Fi connection state from the not-on-Wi-Fi card's
  /// "Check again" action. Re-reads the native NEHotspotNetwork identity first
  /// (a freshly joined SSID is a definitive on-Wi-Fi signal), then re-runs the
  /// controller's connection probe + install-state resolve so the screen advances
  /// out of the not-on-Wi-Fi state once Wi-Fi is back. Never fires the Shortcut.
  Future<void> _retryConnection() async {
    await _fetchIosSecurity();
    await _liveController?.load(nativeSsid: _nativeSsid);
  }

  /// iOS: opens the one-time companion-Shortcut install sheet. Surfaced by the
  /// [LiveSetupCard] prompts when the app has never received a live payload
  /// (the honest "not set up" signal). After the user adds the Shortcut and taps
  /// "I've added it", the controller re-resolves install-state and Start is
  /// kicked off so live readings begin without a second manual tap.
  Future<void> _openInstallSheet() async {
    final WiFiDetailsBridge? bridge = _iosBridge;
    if (bridge == null) return;
    await showInstallShortcutSheet(
      context: context,
      openUrl: bridge.openUrl,
      // Best-effort Shortcuts-app presence gate (Tom Hollingsworth): when absent,
      // the sheet leads with installing Apple's Shortcuts app first.
      isShortcutsAppInstalled: bridge.isShortcutsAppInstalled,
      // Mark the post-install priming flag when the user taps "Add the Shortcut",
      // so on return the live tools show the priming step ("tap Start Live
      // Monitoring to finish") rather than the cold setup prompt.
      onSetupInitiated: bridge.markSetupInitiated,
      // UX-2: reverse the button emphasis once setup has already been started.
      hasInitiatedSetup: bridge.hasInitiatedSetup,
      onInstalled: () async {
        // Persist the global onboarding-seen flag the moment the user completes
        // the install hand-off, so no OTHER live tool re-prompts in the window
        // before the first Live payload lands (null-safe; never throws).
        await _onboardingService?.markOnboardingSeen();
        // Re-resolve install-state. NO auto-fire (2026-06-26): the LivePrimingCard
        // now prompts "tap Start Live Monitoring to finish"; the user's explicit
        // Start delivers the first sample, flips hasEverReceived, and clears
        // priming. The Start-aware settle surfaces recovery if the Shortcut is
        // missing.
        await _liveController?.load(nativeSsid: _nativeSsid);
      },
    );
  }

  // ---- AP-vendor (OUI) lookup ----

  /// Loads the bundled IEEE OUI table once (or uses the injected service). The
  /// lookup is fully offline, no network. A load failure leaves [_ouiService]
  /// null; the AP-vendor row then shows an honest "vendor database unavailable"
  /// note rather than a wrong or blank value.
  Future<void> _loadOuiTable() async {
    final MacOuiService? injected = widget.ouiService;
    if (injected != null) {
      _ouiService = injected;
      return;
    }
    try {
      final String raw = await rootBundle.loadString('assets/oui/oui_table.tsv');
      final Map<String, String> table = MacOuiService.parseTable(raw);
      if (!mounted) return;
      setState(() => _ouiService = MacOuiService.fromTable(table));
    } on Object catch (e) {
      // Honest: the row will read "vendor database unavailable", never invented.
      debugPrint('WifiInfoScreen: OUI table load failed: $e');
    }
  }

  /// Resolves the AP vendor (manufacturer) from a BSSID via the bundled OUI
  /// registry. Returns null when the table is not loaded, the BSSID is absent,
  /// the BSSID is locally-administered / multicast (no IEEE vendor), OR the
  /// BSSID is globally administered but its OUI prefix is not in the bundled
  /// IEEE snapshot. A bare unregistered OUI hex prefix is NOT a resolved
  /// manufacturer, so we never present it as one here. This is the AP
  /// MANUFACTURER, never the configured AP name. The precise reason for a null
  /// rides in the row's note (see [_apVendorNote]).
  String? _apVendorLabel(String? bssid) {
    final MacOuiService? svc = _ouiService;
    if (svc == null || bssid == null || bssid.trim().isEmpty) return null;
    final OuiResult r = svc.lookup(bssid);
    // Only a real IEEE registry hit is a manufacturer. Invalid, local,
    // multicast, and unlisted-global all resolve to null (the note explains).
    return r.matched ? r.vendor : null;
  }

  // ---- iOS native security + BSSID (NEHotspotNetwork) ----

  /// Reads the iOS coarse security token + BSSID natively and stores it. No-op
  /// off the iOS source. Never throws, the service resolves to an honest
  /// unavailable result on any failure or permission gap.
  Future<void> _fetchIosSecurity() async {
    final WifiSecurityService? svc = _securityService;
    if (svc == null) return;
    final WifiSecurityInfo info = await svc.fetch();
    if (!mounted) return;
    setState(() => _iosSecurity = info);
    // The native NEHotspotNetwork read yields SSID/BSSID/security even before
    // the first Shortcut RF sample. Cache that identity so Interface Info shows
    // the network name without a Shortcut bounce (item 1). The current live
    // reading (if any) is enriched and re-cached, otherwise a minimal model
    // carrying just the native identity is cached.
    if (info.available) {
      final ConnectedAp? ap = _currentAp();
      if (ap != null) _apCache.update(ap);
    }
  }

  /// iOS: requests Location-When-In-Use (the NEHotspotNetwork gate), then
  /// re-reads the security + BSSID regardless of the result.
  Future<void> _grantIosSecurityLocation() async {
    final WifiSecurityService? svc = _securityService;
    if (svc == null) return;
    await svc.requestLocationPermission();
    await _fetchIosSecurity();
  }

  /// iOS: opens the app's Settings page so the user can enable Location manually.
  Future<void> _openIosSecuritySettings() async {
    await _securityService?.openLocationSettings();
  }

  /// Folds the native iOS security read (security token + BSSID) onto a
  /// Shortcut-derived [ConnectedAp]. The Shortcut path does not carry the
  /// security type, and the BSSID may be absent there too, so we enrich both
  /// from NEHotspotNetwork when available. macOS already carries both directly,
  /// so this is a no-op off the iOS source.
  ConnectedAp _enrichIos(ConnectedAp ap) {
    final WifiSecurityInfo? sec = _iosSecurity;
    if (sec == null || !sec.available) return ap;
    final WifiSecurity? security = WifiSecurityClassifier.classify(
      sec.securityToken,
    );
    final ConnectedAp withSec = ap.withSecurity(security);
    // Prefer a BSSID the Shortcut already supplied; fall back to the native one.
    if (withSec.bssid == null && sec.bssid != null) {
      return ConnectedAp(
        ssid: withSec.ssid,
        bssid: sec.bssid,
        rssiDbm: withSec.rssiDbm,
        noiseDbm: withSec.noiseDbm,
        snrDb: withSec.snrDb,
        txRateMbps: withSec.txRateMbps,
        rxRateMbps: withSec.rxRateMbps,
        channel: withSec.channel,
        channelWidthMhz: withSec.channelWidthMhz,
        band: withSec.band,
        standard: withSec.standard,
        countryCode: withSec.countryCode,
        interfaceName: withSec.interfaceName,
        hardwareAddress: withSec.hardwareAddress,
        securityType: withSec.securityType,
        poweredOn: withSec.poweredOn,
        rxRateAvailable: withSec.rxRateAvailable,
        channelWidthAvailable: withSec.channelWidthAvailable,
        bandDerived: withSec.bandDerived,
        snrDerived: withSec.snrDerived,
        securityAvailable: withSec.securityAvailable,
      );
    }
    return withSec;
  }

  // ---- macOS data flow ----

  /// Reads a fresh macOS snapshot. [manual] is true for the app-bar Refresh,
  /// which shows a brief confirmation so a refresh that returns identical values
  /// is never silent.
  ///
  /// WCAG 4.1.3 -- the loading state is announced by the liveRegion on
  /// [_LoadingCard]; no imperative announce here (the first read fires from
  /// initState and would race teardown).
  Future<void> _fetchMac({bool manual = false}) async {
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null) return;
    setState(() {
      _macLoading = true;
      _macError = null;
    });
    try {
      final ConnectedAp info = await adapter.fetch();
      if (!mounted) return;
      setState(() {
        _macInfo = info;
        _macLoading = false;
      });
      _appendMacSample(info);
      // Share the reading app-wide so Interface Info shows the same identity.
      _apCache.update(info);
      // Resolve WHY the name is (or is not) present so the SSID/BSSID rows can
      // name the actionable Location cause vs a genuine absence (no-prompt read).
      await _refreshNameAuth();
      if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wi-Fi information updated'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on WifiInfoUnavailable catch (e) {
      if (!mounted) return;
      setState(() {
        _macError = e;
        _macLoading = false;
      });
    } catch (e) {
      // Defensive: never sit on a spinner forever.
      if (!mounted) return;
      setState(() {
        _macError = WifiInfoUnavailable(
          WifiInfoUnavailableReason.channelError,
          e.toString(),
        );
        _macLoading = false;
      });
    }
  }

  /// Appends a CoreWLAN snapshot to [_macSeries] for the sparklines, but only
  /// when one of the four CHARTED RF fields (RSSI / SNR / Tx / Rx rate) differs
  /// from the last charted reading (an unchanged poll does not pad the window).
  /// [ConnectedAp] carries no value equality, so the comparison is field-wise on
  /// exactly what the sparklines draw. Mirrors [_captureSample] on the iOS path.
  void _appendMacSample(ConnectedAp info) {
    final WifiTimeSeries? series = _macSeries;
    if (series == null) return;
    final ConnectedAp? last = _macLastCharted;
    final bool unchanged = last != null &&
        info.rssiDbm == last.rssiDbm &&
        info.snrDb == last.snrDb &&
        info.txRateMbps == last.txRateMbps &&
        info.rxRateMbps == last.rxRateMbps;
    if (unchanged) return;
    _macLastCharted = info;
    series.add(info);
  }

  /// Arms the automatic CoreWLAN poll. Idempotent: cancels any existing timer
  /// first so a resume never double-arms. macOS needs no Start/Stop, the poll
  /// runs while the screen is foregrounded and is cancelled in [dispose].
  void _startMacPoll() {
    if (!WifiInfoScreen.macPollEnabled) return;
    if (!mounted) return;
    _macPollTimer?.cancel();
    _macPollTimer = Timer.periodic(
      WifiInfoScreen.macPollInterval,
      (_) => _pollMacSample(),
    );
  }

  /// Cancels the CoreWLAN poll (background / teardown).
  void _stopMacPoll() {
    _macPollTimer?.cancel();
    _macPollTimer = null;
  }

  /// One automatic CoreWLAN re-read. Reuses the same adapter read as the manual
  /// Refresh, but stays silent (no snackbar, no spinner): it updates [_macInfo]
  /// so the cards stay current and appends the reading to [_macSeries] so the
  /// sparklines advance. A failed poll is swallowed, the last good values and
  /// the existing card/error state stand; the next poll retries.
  Future<void> _pollMacSample() async {
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null || !mounted) return;
    try {
      final ConnectedAp info = await adapter.fetch();
      if (!mounted) return;
      setState(() {
        _macInfo = info;
        // A recovered poll clears a stale error so the cards return.
        _macError = null;
      });
      _appendMacSample(info);
      // Keep the shared cache current so Interface Info tracks the live link.
      _apCache.update(info);
      // Re-resolve the name-gate status each poll so a grant made in System
      // Settings while the screen is open flips the SSID/BSSID reason without a
      // relaunch.
      await _refreshNameAuth();
    } on WifiInfoUnavailable {
      // Transient read failure: keep the last good snapshot + series on screen.
    } catch (_) {
      // Defensive: a poll never tears down the screen.
    }
  }

  /// macOS: requests Location authorization, then re-reads regardless of result.
  Future<void> _grantLocation() async {
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null) return;
    await adapter.requestNamePermission();
    if (!mounted) return;
    _locationGrantAttempted = true;
    await _fetchMac();
  }

  /// Re-reads the CURRENT name-gating (Location) authorization for the snapshot
  /// source WITHOUT surfacing a prompt, and stores it so the SSID/BSSID rows can
  /// name the real cause (a Location permission gate vs a genuinely absent name).
  /// No-op for ungated sources (Windows Native Wifi) and off the snapshot path.
  /// Bounded by the adapter's own timeout; never throws — on a read failure it
  /// leaves the last known status, so the row degrades to a plain unavailable
  /// rather than asserting a cause it could not confirm.
  Future<void> _refreshNameAuth() async {
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null || !adapter.gatesNameBehindPermission) return;
    try {
      final LocationAuthStatus auth = await adapter.nameAuthorizationStatus();
      if (!mounted) return;
      setState(() => _nameAuth = auth);
    } on Object {
      // Honest fallback: keep the prior status; never fabricate a reason.
    }
  }

  /// macOS: deep-links to System Settings → Privacy & Security → Location
  /// Services so the user can enable this app manually. macOS cannot toggle its
  /// own Location permission in code, so this opens the exact pane; the user
  /// flips the toggle and returns to tap Refresh.
  Future<void> _openLocationSettings() async {
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null) return;
    await adapter.openNamePermissionSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Information'),
        toolbarHeight: 64,
        actions: _appBarActions(),
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  List<Widget> _appBarActions() {
    switch (_source) {
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.androidWifiManager:
      case WifiInfoSource.windowsNativeWifi:
        // §8.16 order: copy LEADS, the Refresh action trails. Copy is disabled
        // until a snapshot has resolved (textBuilder → null while loading or on
        // error with no info), enabled once link details exist.
        return [
          AppCopyAction(textBuilder: _buildCopyText),
          _macLoading
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      // Foreground accent → darkened-lime in light (§8.20.2).
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.textAccent,
                      ),
                    ),
                  ),
                )
              : Semantics(
                  button: true,
                  // This branch renders only when not mid-refresh, so the
                  // action is always available; `onPressed` is never null.
                  // Without this the node leaves isEnabled unset, which AT
                  // announces as a DISABLED button (see 68d9b93).
                  enabled: true,
                  label: 'Refresh Wi-Fi information',
                  child: IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                    onPressed: () => _fetchMac(manual: true),
                  ),
                ),
        ];
      case WifiInfoSource.iosShortcuts:
        // §8.16: copy is the only app-bar action on iOS. Disabled
        // (textBuilder → null) until at least one live reading exists.
        return <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ];
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        return const [];
    }
  }

  /// The connected-AP link currently shown, regardless of platform source:
  /// the macOS CoreWLAN snapshot, or the latest iOS streamed payload (which Stop
  /// freezes as the snapshot). Null when nothing is on screen yet.
  ConnectedAp? _currentAp() {
    switch (_source) {
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.androidWifiManager:
      case WifiInfoSource.windowsNativeWifi:
        return _macInfo;
      case WifiInfoSource.iosShortcuts:
        final WiFiDetails? d = _liveController?.details;
        // No live RF reading yet, but the native security read may have
        // resolved on open, surface it so Security / AP vendor show before the
        // first Shortcut sample. Build a near-empty model carrying just the
        // native security + BSSID so those rows render.
        if (d == null) {
          final WifiSecurityInfo? sec = _iosSecurity;
          if (sec == null || !sec.available) return null;
          return _enrichIos(const ConnectedAp(securityAvailable: true));
        }
        return _enrichIos(ConnectedAp.fromWifiDetails(d));
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        return null;
    }
  }

  /// §8.16 copy payload, the connected-AP link as a labeled plain-text block,
  /// mirroring the on-screen metric cards (Network / Signal / Rate / Channel /
  /// Radio / Status). Returns null (→ disabled affordance) until link details
  /// exist. On iOS this copies whatever the live stream currently shows; a tap
  /// re-serializes on demand, so a later sample copies its newer values.
  ///
  /// Honesty (GL-005): a field the platform cannot expose is written as
  /// "Unavailable" with a per-platform reason (e.g. Rx rate). Channel width is
  /// different — every snapshot platform derives it from the AP's advertised
  /// info, so when it is missing the note is per-network ("Not reported for this
  /// network"), never an OS-blaming claim. Never a blank, never a fabricated
  /// value.
  String? _buildCopyText() {
    final ConnectedAp? info = _currentAp();
    if (info == null) return null;

    final String platformLabel = _source == WifiInfoSource.iosShortcuts
        ? 'iOS'
        : _snapshotPlatformLabel;
    final StringBuffer buf = StringBuffer()..writeln('Wi-Fi Information');

    buf
      ..writeln()
      ..writeln('Network')
      ..writeln('  SSID: ${_copyVal(info.ssid, null)}');
    // AP name only when advertised — mirrors the on-screen row (what is on
    // screen is what is copied; no empty line when there is no name).
    if (info.apName != null && info.apName!.trim().isNotEmpty) {
      buf.writeln('  AP name: ${info.apName}');
    }
    buf
      ..writeln('  BSSID: ${_copyVal(info.bssid, null)}')
      ..writeln('  AP vendor: ${_copyVal(_apVendorValue(info.bssid), null)}');

    buf
      ..writeln()
      ..writeln('Security')
      ..writeln(
        '  Security type: ${info.securityAvailable ? _copyVal(info.securityType?.label, null) : 'Not exposed by $platformLabel'}'
        '${(info.securityType?.isPersonalCoarse ?? false) || (info.securityType?.isEnterpriseCoarse ?? false) ? ' (iOS coarse, WPA2/WPA3 not distinguished)' : ''}',
      );

    // Android exposes no noise floor, so Noise + SNR carry an explicit reason in
    // the copy text too (matches the on-screen notes; GL-005). macOS reports
    // both; iOS derives SNR.
    final bool isAndroid = _source == WifiInfoSource.androidWifiManager;
    final String noiseCopy = isAndroid && info.noiseDbm == null
        ? 'Not available on $platformLabel (no noise-floor API)'
        : _copyVal(info.noiseDbm?.toString(), 'dBm');
    final String snrCopy = isAndroid && info.snrDb == null
        ? 'Needs the noise floor, which $platformLabel does not expose'
        : '${_copyVal(info.snrDb?.toString(), 'dB')}'
            '${info.snrDerived ? ' (derived)' : ''}';
    buf
      ..writeln()
      ..writeln('Signal')
      ..writeln('  RSSI: ${_copyVal(info.rssiDbm?.toString(), 'dBm')}')
      ..writeln('  Noise: $noiseCopy')
      ..writeln('  SNR: $snrCopy');

    // Rx: a permanent platform limit (rxRateAvailable false → macOS) vs the
    // Android sentinel (-1) → an Android-specific note vs a present value.
    final String rxCopy = !info.rxRateAvailable
        ? 'Not exposed by $platformLabel'
        : (info.rxRateMbps == null
            ? (isAndroid
                ? "Not reported by this device's $platformLabel link"
                : 'Not in this reading')
            : _copyVal(_formatRate(info.rxRateMbps), 'Mbps'));
    buf
      ..writeln()
      ..writeln('Rate')
      ..writeln('  Tx Rate: ${_copyVal(_formatRate(info.txRateMbps), 'Mbps')}')
      ..writeln('  Rx Rate: $rxCopy');

    final bool isPsc = _isPscChannel(info.channel, info.band);
    buf
      ..writeln()
      ..writeln('Channel')
      ..writeln(
        '  Channel: ${_copyVal(info.channel?.toString(), null)}'
        '${isPsc ? ' (Preferred Scanning Channel)' : ''}',
      )
      ..writeln(
        '  Width: ${info.channelWidthAvailable ? _copyVal(_formatChannelWidth(info.channelWidthMhz), _channelWidthHasUnit(info.channelWidthMhz) ? 'MHz' : null) : 'Not reported for this network'}',
      )
      ..writeln(
        '  Band: ${_copyVal(info.band, null)}'
        '${info.bandDerived ? ' (derived)' : ''}',
      );

    buf
      ..writeln()
      ..writeln('Radio')
      ..writeln('  Wi-Fi Standard: ${_copyVal(info.standard, null)}')
      ..writeln('  Country: ${_copyVal(info.countryCode, null)}')
      ..writeln('  Interface: ${_copyVal(info.interfaceName, null)}')
      ..writeln('  Hardware Address: ${_copyVal(info.hardwareAddress, null)}')
      ..writeln('  MAC type: ${MacRandomizationClassifier.label(info.hardwareAddress, platform: _macPlatform)}');

    buf
      ..writeln()
      ..writeln('Status')
      ..writeln('  Wi-Fi Radio: ${info.poweredOn ? 'On' : 'Off'}');

    return buf.toString().trimRight();
  }

  /// Clipboard analog of `_MetricRow`: "value unit", or "Unavailable" when the
  /// value is missing (GL-005 honest blanks).
  static String _copyVal(String? value, String? unit) {
    if (value == null || value.trim().isEmpty) return 'Unavailable';
    return unit == null ? value : '$value $unit';
  }

  Widget _body() {
    switch (_source) {
      case WifiInfoSource.web:
        return const NetworkUnavailableView(
          toolName: 'Wi-Fi Information',
          reason: NetworkUnavailableReason.web,
        );
      case WifiInfoSource.unsupported:
        return const _PlatformComingSoon();
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.androidWifiManager:
      case WifiInfoSource.windowsNativeWifi:
        return _macBody();
      case WifiInfoSource.iosShortcuts:
        return _iosBody();
    }
  }

  // ---- macOS body ----

  Widget _macBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            edge,
            AppSpacing.sm,
            edge,
            edge + AppSpacing.sm,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _macContent(isDesktop),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _macContent(bool isDesktop) {
    final List<Widget> children = <Widget>[
      ConceptGraphicBand(toolId: 'wifi-info', isDesktop: isDesktop),
      if (ToolAssets.hasGraphic('wifi-info'))
        const SizedBox(height: AppSpacing.md),
    ];

    if (_macLoading && _macInfo == null && _macError == null) {
      children.add(const _LoadingCard());
      return children;
    }

    if (_macError != null && _macInfo == null) {
      children.add(
        _ErrorCard(error: _macError!, onRetry: _macLoading ? null : _fetchMac),
      );
      return children;
    }

    final ConnectedAp? info = _macInfo;
    if (info == null) {
      children.add(
        _ErrorCard(error: null, onRetry: _macLoading ? null : _fetchMac),
      );
      return children;
    }

    if (!info.poweredOn) {
      children
        ..add(const _WifiOffCard())
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    final Widget? locationCard = _buildLocationCard(info);
    if (locationCard != null) {
      children
        ..add(locationCard)
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    if (_macError != null) {
      children
        ..add(
          _ErrorCard(
            error: _macError!,
            onRetry: _macLoading ? null : _fetchMac,
          ),
        )
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    // Live RF sparklines on top (same surface as iOS), fed by the automatic
    // CoreWLAN poll. Shown once at least one sample is in the window; the cards
    // below carry the full per-field detail regardless.
    final WifiTimeSeries? series = _macSeries;
    if (series != null && !series.isEmpty) {
      children
        ..add(_LiveCharts(
          series: series,
          latest: info,
          platformLabel: _snapshotPlatformLabel,
        ))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    children.addAll(_metricCards(info, platformLabel: _snapshotPlatformLabel));
    return children;
  }

  /// Location card for the snapshot sources (macOS CoreWLAN / Android
  /// WifiManager), three states. Returns null when no card is needed.
  ///
  /// Both snapshot platforms gate the SSID/BSSID behind a Location permission;
  /// the copy and post-grant behavior differ (macOS Location Services + likely
  /// relaunch; Android ACCESS_FINE_LOCATION runtime grant that takes effect on
  /// the next read). Never built on iOS (that path reads the name through the
  /// Shortcut bridge and routes through [_iosBody]).
  Widget? _buildLocationCard(ConnectedAp info) {
    final bool nameMissing = info.ssid == null && info.bssid == null;
    if (info.ssid != null) return null;

    // Only sources that gate the name behind an OS permission (macOS Location
    // Services / Android ACCESS_FINE_LOCATION) get a Location card. Windows
    // Native Wifi returns SSID/BSSID with no grant, so a null name there is
    // simply absent from this reading — never a permission problem, no card.
    final WifiInfoAdapter? adapter = _macAdapter;
    if (!(adapter?.gatesNameBehindPermission ?? false)) return null;

    // When Location IS authorized yet the name is still missing, this is NOT a
    // permission problem (a genuinely disconnected / hidden network). Don't show
    // a card that blames a granted permission. A null (unresolved) or a
    // not-authorized status keeps the card, since a gated name is the dominant
    // cause of a missing name on these sources. The post-grant informational
    // path (below) still owns the just-granted case.
    if (_nameAuth == LocationAuthStatus.authorized && !_locationGrantAttempted) {
      return null;
    }

    final bool isAndroid = _source == WifiInfoSource.androidWifiManager;

    // THE TRI-STATE, consulted. This screen has held `_nameAuth` since the
    // permission read was added, and the Location card never asked it whether a
    // prompt was even possible: it offered "Grant Location" in every
    // unauthorized state. Under `denied` / `restricted` macOS will not re-prompt
    // and Android will not re-prompt after a permanent denial, so that button
    // was guaranteed to do nothing at all. Keith hit exactly this on the AP scan
    // screen in a live deployment and clicked it repeatedly with no prompt, no
    // error and no navigation. The defect is the unconsulted state, not the
    // button ([[feedback_ui_rendered_a_decision_it_lacked]]).
    //
    // A null `_nameAuth` means the status has not resolved yet, and resolves to
    // `notDetermined` to match [LocationAuthStatus.fromToken]'s documented
    // fallback: offer the harmless prompt rather than a dead deep-link when the
    // truth is not yet known.
    final LocationAuthStatus auth = _nameAuth ?? LocationAuthStatus.notDetermined;
    final bool promptable = auth.isPromptable;
    final String settingsName = isAndroid ? 'Settings' : 'System Settings';

    if (info.ssid == null && _locationGrantAttempted) {
      // Android: a granted runtime permission lands on the next poll (no
      // relaunch). macOS: the grant may need an app relaunch before the name
      // surfaces. A still-null name after granting on Android most often means
      // the user denied (or permanently denied) the dialog — the card keeps the
      // Open Settings affordance below for the permanently-denied case.
      // Same guard, same reason: after a grant attempt on Android the status is
      // no longer `notDetermined`, so a re-offered in-app grant here is the same
      // dead button. When the answer was a denial, say so and point at the only
      // switch that still works.
      return _LocationCard(
        message: isAndroid
            ? (promptable
                ? 'If you allowed Location, the network name appears on the '
                    'next refresh. If it is still blank, tap Grant Location '
                    'again. Signal, rate, and channel details work without it.'
                : 'The Location permission was denied, and this app cannot ask '
                    'again. Enable Location for this app in Settings, then tap '
                    'Refresh. Signal, rate, and channel details work without '
                    'it.')
            : 'Permission granted. macOS may need an app relaunch before the '
                'network name appears. The signal and channel details below are '
                'unaffected.',
        promptable: promptable,
        onGrant: isAndroid ? (_macLoading ? null : _grantLocation) : null,
        onOpenSettings: isAndroid ? _openLocationSettings : null,
        platformIsAndroid: isAndroid,
      );
    }

    if (nameMissing) {
      // The copy changes with the control. Telling a denied user that the name
      // "needs" Location, beside a Grant button the OS forbids from acting, is
      // the prose form of the same dead button: it instructs them to do
      // something that cannot be done from inside this app.
      final String why = isAndroid
          ? 'Android requires it to read the connected network name.'
          : 'macOS requires it to read the name.';
      final String needs = isAndroid
          ? 'The network name (SSID and BSSID) needs the Location permission '
              'on Android.'
          : 'The network name (SSID and BSSID) needs Location Services for '
              'this app.';
      const String unaffected =
          'Signal, rate, and channel details already work without it.';
      final String message;
      switch (auth) {
        case LocationAuthStatus.denied:
        case LocationAuthStatus.restricted:
          // NOT promptable. No in-app grant is offered and none is described.
          message = '$needs $why Location is turned off for this app, and this '
              'app cannot ask again. That switch only exists in $settingsName. '
              'Turn it on there, then tap Refresh. $unaffected';
        case LocationAuthStatus.notDetermined:
          message = '$needs $why $unaffected';
        case LocationAuthStatus.authorized:
          // Defensive: the authorized-and-not-yet-attempted case returns null
          // above, so this is not normally reachable. If it ever is, the card
          // must not claim a grant is missing when the app holds it.
          message = 'Location is granted for this app, but the network name '
              'still did not resolve in this reading. Tap Refresh to try '
              'again. $unaffected';
      }
      return _LocationCard(
        message: message,
        promptable: promptable,
        onGrant: _macLoading ? null : _grantLocation,
        onOpenSettings: _openLocationSettings,
        platformIsAndroid: isAndroid,
      );
    }

    return null;
  }

  /// The natively-readable connected-network identity on iOS (SSID / BSSID /
  /// security via NEHotspotNetwork), or null before the native read resolves or
  /// when it is unavailable (no network / permission). Used by [_LiveBody] to
  /// show the real network basics BEFORE the first Shortcut RF sample, so the
  /// tool never opens to a dead screen. Carries no RF values (those need the
  /// Shortcut) — only the identity the app can honestly read itself.
  /// The native NEHotspotNetwork SSID, when a real network has resolved — a
  /// definitive "on Wi-Fi" signal for the connection probe. Null before the
  /// native read resolves or when Location is ungranted; absence is never used to
  /// assert "not on Wi-Fi" (see [WifiConnectionService]).
  String? get _nativeSsid {
    final WifiSecurityInfo? sec = _iosSecurity;
    if (sec == null || !sec.available) return null;
    final String? ssid = sec.ssid?.trim();
    return (ssid == null || ssid.isEmpty) ? null : ssid;
  }

  ConnectedAp? _nativeIdentityAp() {
    final WifiSecurityInfo? sec = _iosSecurity;
    if (sec == null || !sec.available) return null;
    // Seed the SSID from the native NEHotspotNetwork read so the native-first
    // identity card shows the REAL network name (not just BSSID + security)
    // before the first Shortcut RF sample. _enrichIos then folds the coarse
    // security token and BSSID onto it.
    return _enrichIos(
      ConnectedAp(ssid: sec.ssid, securityAvailable: true),
    );
  }

  // ---- iOS body (Live streaming only) ----

  Widget _iosBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;

        return _LiveBody(
          controller: _liveController!,
          series: _series!,
          edge: edge,
          triggerError: _liveTriggerError,
          // The single live action: Start continuous monitoring (keeps the iOS
          // banner up while running; Stop ends it).
          onStart: _startLive,
          onStop: _stopLive,
          onSetUp: _openInstallSheet,
          // "Check again" from the not-on-Wi-Fi card: re-read the native identity
          // (a freshly joined SSID is a definitive on-Wi-Fi signal) THEN re-run
          // the connection probe + install-state resolve so the screen advances
          // out of the not-on-Wi-Fi state the moment Wi-Fi is back.
          onRetryConnection: _retryConnection,
          // Fold the native security token + BSSID onto each live reading so the
          // Security / AP-vendor rows render from the same enriched model the
          // rest of the cards use.
          enrich: _enrichIos,
          // Native-first: BEFORE any Shortcut payload, surface the connected
          // network basics the app CAN read natively (SSID / BSSID / security
          // via NEHotspotNetwork). Null until the native read resolves; the
          // Live body then shows the real identity immediately rather than a
          // dead start hint.
          nativeIdentity: _nativeIdentityAp(),
          nativeIdentityCardsBuilder: (ConnectedAp native) => <Widget>[
            _networkCard(native),
            const SizedBox(height: AppSpacing.sm),
            _securityCard(native, 'iOS'),
          ],
          // The grouped metric cards belong to the State (they read the shared
          // _metricCards builder), so they are passed in as a builder over the
          // SAME latest reading the charts use. Null until the first sample, so
          // the cards appear only once there is honest data to group.
          metricCardsBuilder: (ConnectedAp latest) =>
              _metricCards(latest, platformLabel: 'iOS Live'),
        );
      },
    );
  }

  // ---- Shared metric cards (render the normalized model) ----

  /// Builds the grouped metric cards from the normalized [ConnectedAp]. Used by
  /// BOTH platform bodies so the data presentation is identical regardless of
  /// source; only the per-field availability reasons differ ([platformLabel]).
  List<Widget> _metricCards(ConnectedAp info, {required String platformLabel}) {
    return <Widget>[
      _networkCard(info),
      const SizedBox(height: AppSpacing.sm),
      _securityCard(info, platformLabel),
      const SizedBox(height: AppSpacing.sm),
      _signalCard(info, platformLabel),
      const SizedBox(height: AppSpacing.sm),
      _rateCard(info, platformLabel),
      const SizedBox(height: AppSpacing.sm),
      _channelCard(info),
      const SizedBox(height: AppSpacing.sm),
      _radioCard(info),
      const SizedBox(height: AppSpacing.sm),
      _statusCard(info),
    ];
  }

  /// The actionable reason the network name is empty when a snapshot source
  /// gates it behind an OS Location permission that is not granted. Worded to
  /// agree with the Network-at-a-glance card's
  /// 'Network name needs Location permission' (network_glance_card.dart) so the
  /// two surfaces name the macOS/Android Location condition the same way
  /// (Phase 5.5 cross-surface consistency). Kept short here because the row's
  /// own label ('SSID' / 'BSSID') already supplies the "Network name" subject.
  static const String _kNeedsLocationPermission = 'Needs Location permission';

  /// The honest, ACTIONABLE reason an SSID/BSSID row is empty on a snapshot
  /// source that gates the network name behind an OS Location permission (macOS
  /// Location Services / Android ACCESS_FINE_LOCATION). Returns
  /// [_kNeedsLocationPermission] ONLY when the value is missing, the active
  /// adapter gates the name, and the current authorization is NOT granted — so
  /// the row names the true, fixable cause instead of a flat "Unavailable".
  ///
  /// Returns null (→ the row's plain "Unavailable") when the value is present,
  /// when the source has no name gate (Windows Native Wifi, or the iOS path
  /// where `_macAdapter` is null), or when Location IS authorized yet the name
  /// is still absent — a genuinely disconnected / hidden network, which is NOT a
  /// permission problem, so we never blame a granted permission (GL-005).
  String? _nameGateNote(String? value) {
    if (value != null && value.trim().isNotEmpty) return null;
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null || !adapter.gatesNameBehindPermission) return null;
    if (_nameAuth == LocationAuthStatus.authorized) return null;
    return _kNeedsLocationPermission;
  }

  Widget _networkCard(ConnectedAp info) => _Card(
    title: 'Network',
    child: Column(
      children: [
        _MetricRow(
          label: 'SSID',
          value: info.ssid,
          note: _nameGateNote(info.ssid),
        ),
        // AP name (vendor-advertised in the beacon, decoded from the IEs on
        // macOS). Shown ABOVE the BSSID so the human-readable name leads and the
        // MAC reads as secondary. Honest-null: when the AP advertises no name (or
        // the platform cannot read the IEs), this row is omitted entirely — no
        // empty label, no placeholder — and the card reads exactly as before.
        if (info.apName != null && info.apName!.trim().isNotEmpty)
          _MetricRow(label: 'AP name', value: info.apName),
        _MetricRow(
          label: 'BSSID',
          value: info.bssid,
          mono: true,
          note: _nameGateNote(info.bssid),
        ),
        // AP vendor (manufacturer) resolved offline from the BSSID's IEEE OUI.
        // This is the AP MANUFACTURER, distinct from the configured AP name
        // above: the name is what an admin typed and the AP advertises (macOS,
        // when enabled); the vendor is who built the radio. The note says so.
        _MetricRow(
          label: 'AP vendor',
          value: _apVendorValue(info.bssid),
          note: _apVendorNote(info.bssid),
        ),
      ],
    ),
  );

  /// The AP-vendor row value: the manufacturer resolved from the BSSID's OUI.
  /// When the BSSID is locally-administered (personal hotspots, MAC
  /// randomization) there is no IEEE vendor to resolve, so we surface the honest
  /// human label "Private address" rather than the generic "Unavailable". All
  /// other not-resolved states (absent BSSID, table not loaded, unregistered
  /// global OUI) still return null (→ "Unavailable"); the note explains each.
  String? _apVendorValue(String? bssid) {
    final String? vendor = _apVendorLabel(bssid);
    if (vendor != null) return vendor;
    if (_isLocallyAdministeredBssid(bssid)) return 'Private address';
    return null;
  }

  /// True when the BSSID is a locally-administered / multicast MAC (no
  /// IEEE-registered vendor exists to look up). Mirrors the branch in
  /// [_apVendorNote] exactly: reachable only when the OUI did not match a
  /// registry entry and the address is a readable MAC.
  bool _isLocallyAdministeredBssid(String? bssid) {
    final MacOuiService? svc = _ouiService;
    if (svc == null || bssid == null || bssid.trim().isEmpty) return false;
    final OuiResult r = svc.lookup(bssid);
    if (r.matched || !r.isValid) return false;
    return r.isLocal || r.isMulticast;
  }

  /// The honest note for the AP-vendor row: explains WHY it is unavailable
  /// (no BSSID / database loading / randomized BSSID / unregistered OUI), or
  /// clarifies that a present value is the manufacturer, not the configured AP
  /// name. Reads the structured [OuiResult] so each not-resolved state gets its
  /// own honest reason instead of one catch-all.
  String? _apVendorNote(String? bssid) {
    if (bssid == null || bssid.trim().isEmpty) {
      return 'Needs the BSSID (AP MAC) to look up';
    }
    final MacOuiService? svc = _ouiService;
    if (svc == null) {
      return 'Loading the offline vendor database…';
    }
    final OuiResult r = svc.lookup(bssid);
    if (r.matched) {
      return 'AP manufacturer (from the BSSID), not the configured AP name';
    }
    if (!r.isValid) {
      return 'BSSID is not a readable MAC address';
    }
    if (r.isLocal || r.isMulticast) {
      // Randomized / software-assigned address, not from an IEEE block.
      return "This BSSID is locally administered (normal for personal "
          "hotspots and MAC randomization), so there's no manufacturer to "
          "look up.";
    }
    // Globally administered but the OUI prefix is not in the bundled IEEE
    // snapshot. A bare hex prefix is not a manufacturer, so the value reads
    // "Unavailable" and we say exactly why, surfacing the raw prefix as such.
    final String prefix = _ouiPrefixLabel(r.oui);
    return 'Unregistered OUI prefix$prefix, no IEEE vendor name';
  }

  /// Formats a 24-bit OUI hex (e.g. `0011225` → `00:11:22`) for display inside
  /// the note, clearly labeled as a raw prefix rather than a vendor. Returns an
  /// empty string when there is no usable prefix.
  String _ouiPrefixLabel(String? oui) {
    if (oui == null || oui.length < 6) return '';
    final String p =
        '${oui.substring(0, 2)}:${oui.substring(2, 4)}:${oui.substring(4, 6)}';
    return ' ($p)';
  }

  /// The Security card. Renders the normalized security label, with the honest
  /// iOS-coarse footnote and the iOS Location-gate affordance when the native
  /// read is blocked by a missing permission.
  Widget _securityCard(ConnectedAp info, String platformLabel) {
    final WifiSecurity? security = info.securityType;
    final bool isIos = _source == WifiInfoSource.iosShortcuts;

    // iOS-only: when the native read is blocked by Location, offer the grant /
    // settings affordance (same shape as the macOS Location card).
    //
    // THE FIX (instance #7 of the dead-control family). This gate used to read
    // a BOOLEAN `locationAuthorized`, which collapses "never asked" and "asked
    // and refused" into one false — so under `denied` it rendered a Grant
    // button that iOS is guaranteed to ignore, because iOS never re-prompts
    // after a When-In-Use denial. `WifiSecurityInfo` now carries the platform's
    // own tri-state and the affordance is driven by it.
    // See [[feedback_ui_rendered_a_decision_it_lacked]].
    final WifiSecurityInfo? sec = isIos ? _iosSecurity : null;
    final bool iosNeedsLocation = sec != null &&
        !sec.available &&
        !sec.locationAuth.isAuthorized;
    final LocationAuthStatus securityAuth =
        sec?.locationAuth ?? LocationAuthStatus.notDetermined;

    // Honest note: the coarse-iOS caveat, or the per-platform unavailable reason.
    String? note;
    if (!info.securityAvailable) {
      note = 'Not exposed by $platformLabel';
    } else if (security == null) {
      // Available platform, no value this reading. On iOS surface the precise
      // native reason (permission / no network) when we have one.
      if (iosNeedsLocation && !securityAuth.isPromptable) {
        // NOT promptable. The native reason says "Location permission is
        // needed", which is true but reads as though this app could ask for it.
        // It cannot. Say so, and name where the switch actually lives — the
        // prose equivalent of not rendering a dead button.
        note = 'Location is turned off for this app, and this app cannot ask '
            'again. Turn it on in Settings > Privacy & Security > Location '
            'Services > WLAN Pros Toolbox, then tap Refresh';
      } else {
        // `sec` is null on every non-iOS source, so this stays a null-SAFE read
        // (the original guard's shape). A null-assert here would throw on the
        // whole macOS path.
        note = (sec != null && !sec.available && sec.reason != null)
            ? sec.reason
            : 'Not in this reading';
      }
    } else if (security.isPersonalCoarse || security.isEnterpriseCoarse) {
      note = 'iOS reports only Open / Personal / Enterprise. It cannot '
          'distinguish WPA2 from WPA3';
    }

    return _Card(
      title: 'Security',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _MetricRow(
            label: 'Security type',
            value: security?.label,
            note: note,
          ),
          if (iosNeedsLocation) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _SecurityLocationActions(
              status: securityAuth,
              onGrant: _grantIosSecurityLocation,
              onOpenSettings: _openIosSecuritySettings,
            ),
          ],
        ],
      ),
    );
  }

  Widget _signalCard(ConnectedAp info, String platformLabel) {
    // ANDROID NOISE/SNR (FIX 2, 2026-06-08): the public Android Wi-Fi API
    // exposes NO noise-floor reading, so SNR genuinely cannot be computed — it
    // is a true platform limit, not a transient miss (GL-005 / GL-008). macOS
    // CoreWLAN DOES report both, so it carries no note; iOS derives SNR
    // (snrDerived). On Android, the Noise and SNR rows therefore carry an
    // explicit "why" note naming the missing API, rather than a bare
    // "Unavailable" the user cannot interpret.
    // Android AND Windows expose NO noise-floor reading in their public Wi-Fi
    // APIs (Android's WifiManager, Windows' Native Wifi), so SNR genuinely
    // cannot be computed on either — a true platform limit, not a transient
    // miss (GL-005 / GL-008). macOS CoreWLAN DOES report both (no note); iOS
    // derives SNR (snrDerived). Both no-noise platforms therefore carry an
    // explicit "why" note naming the missing API rather than a bare
    // "Unavailable" the user cannot interpret.
    final bool isWindows = _source == WifiInfoSource.windowsNativeWifi;
    final bool noNoiseFloorApi =
        _source == WifiInfoSource.androidWifiManager || isWindows;
    final String? noiseNote = noNoiseFloorApi && info.noiseDbm == null
        ? 'Not available on $platformLabel (no noise-floor API)'
        : null;
    final String? snrNote = noNoiseFloorApi && info.snrDb == null
        ? 'Needs the noise floor, which $platformLabel does not expose'
        : null;
    return _Card(
      title: 'Signal',
      child: Column(
        children: [
          _MetricRow(
            label: 'RSSI',
            value: info.rssiDbm?.toString(),
            unit: 'dBm',
            mono: true,
          ),
          _MetricRow(
            label: 'Noise',
            value: info.noiseDbm?.toString(),
            unit: 'dBm',
            mono: true,
            note: noiseNote,
          ),
          _MetricRow(
            label: 'SNR',
            value: info.snrDb?.toString(),
            unit: 'dB',
            mono: true,
            derived: info.snrDerived,
            note: snrNote,
          ),
        ],
      ),
    );
  }

  Widget _rateCard(ConnectedAp info, String platformLabel) => _Card(
    title: 'Rate',
    child: Column(
      children: [
        _MetricRow(
          label: 'Tx Rate',
          value: _formatRate(info.txRateMbps),
          unit: 'Mbps',
          mono: true,
        ),
        _MetricRow(
          label: 'Rx Rate',
          value: _formatRate(info.rxRateMbps),
          unit: 'Mbps',
          mono: true,
          // Say WHY precisely (FIX 2, 2026-06-08):
          //   * rxRateAvailable false → the platform NEVER exposes Rx (macOS
          //     public CoreWLAN). Permanent platform limit.
          //   * Android, rxRateAvailable true but the value null → the device
          //     returned getRxLinkSpeedMbps()'s unknown sentinel (-1), common on
          //     the S24. Honest, Android-specific platform-limit wording that
          //     matches the SNR rows above, never a bare "Unavailable".
          //   * iOS, rxRateAvailable true but null → a per-reading miss; the
          //     Shortcut can carry Rx, this harvest just lacked it.
          note: !info.rxRateAvailable
              ? 'Not exposed by $platformLabel'
              : (info.rxRateMbps == null
                  ? (_source == WifiInfoSource.androidWifiManager
                      ? "Not reported by this device's $platformLabel link"
                      : 'Not in this reading')
                  : null),
        ),
      ],
    ),
  );

  Widget _channelCard(ConnectedAp info) {
    final bool isPsc = _isPscChannel(info.channel, info.band);
    return _Card(
      title: 'Channel',
      child: Column(
        children: [
          _MetricRow(
            label: 'Channel',
            value: info.channel?.toString(),
            mono: true,
            marker: isPsc ? '*' : null,
            note: isPsc ? 'Preferred Scanning Channel (PSC)' : null,
          ),
          _MetricRow(
            label: 'Width',
            value: _formatChannelWidth(info.channelWidthMhz),
            unit: _channelWidthHasUnit(info.channelWidthMhz) ? 'MHz' : null,
            mono: true,
            // Channel width nulls per-reading, never per-OS: Windows and Android
            // both derive it from the AP's advertised info (beacon IEs / matching
            // ScanResult), so it is absent only when THIS network's reading did
            // not carry it — not an OS-permanent ceiling. Honest per-network copy
            // (matches androidUnreadReason), not an OS-blaming "Not reported by
            // <platform>". (GL-005; pre-launch accuracy pass.)
            note: info.channelWidthAvailable
                ? null
                : 'Not reported for this network',
          ),
          _MetricRow(
            label: 'Band',
            value: info.band,
            derived: info.bandDerived,
          ),
        ],
      ),
    );
  }

  Widget _radioCard(ConnectedAp info) => _Card(
    title: 'Radio',
    child: Column(
      children: [
        _MetricRow(label: 'Wi-Fi Standard', value: info.standard),
        // Country: Android's WifiManager.getCountryCode() is restricted on
        // Android 11+ and often returns nothing to a non-privileged app. When it
        // does, the row carries the honest Android limit note rather than a bare
        // "Unavailable" (GL-005). When the platform DOES return it, the value
        // shows and no note is needed. iOS never carries country (no path), and
        // macOS reads it directly.
        _MetricRow(
          label: 'Country',
          value: info.countryCode,
          note: _countryNote(info.countryCode),
        ),
        _MetricRow(label: 'Interface', value: info.interfaceName, mono: true),
        // Hardware Address here is the DEVICE Wi-Fi MAC (this device's adapter),
        // NOT the AP BSSID (that lives in the Network card, and IS available on
        // Android with Location). The device MAC is hidden on both phones: iOS
        // never exposes it, Android returns the 02:00:00:00:00:00 randomized
        // placeholder (mapped to null by the native side). When absent, the row
        // carries the platform-correct reason rather than a bare "Unavailable".
        _MetricRow(
          label: 'Hardware Address',
          value: info.hardwareAddress,
          mono: true,
          note: _hardwareAddressNote(info.hardwareAddress),
        ),
        // Derived MAC type from the locally-administered bit. When the MAC is
        // unreadable, the value is "Unavailable" and the honest, PLATFORM-CORRECT
        // reason rides in the note rather than a meaningless computed flag
        // (GL-005). iOS blocks app reads of the device Wi-Fi MAC; Android returns
        // a randomized placeholder — each names its own real limit.
        _MetricRow(
          label: 'MAC type',
          value: _macTypeValue(info.hardwareAddress),
          note: _macTypeNote(info.hardwareAddress),
        ),
      ],
    ),
  );

  /// The honest note for an absent device Hardware Address (the DEVICE Wi-Fi
  /// MAC). Platform-correct: iOS does not expose it; Android returns a
  /// randomized placeholder. Null when the MAC is present (rare on phones) or on
  /// macOS, where the burned-in MAC reads directly.
  String? _hardwareAddressNote(String? mac) {
    if (mac != null && mac.trim().isNotEmpty) return null;
    switch (_source) {
      case WifiInfoSource.androidWifiManager:
        return 'This device MAC, not the AP. ${MacRandomizationClassifier.unreadableReason(MacAddressPlatform.android)}';
      case WifiInfoSource.iosShortcuts:
        return 'This device MAC, not the AP. ${MacRandomizationClassifier.unreadableReason(MacAddressPlatform.ios)}';
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.windowsNativeWifi:
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        return null;
    }
  }

  /// The MAC-type value for the Radio card: the Randomized/Universal label, or
  /// null (→ "Unavailable") when the MAC is unreadable, so the honest reason
  /// rides in the [_MetricRow.note] rather than masquerading as a value.
  static String? _macTypeValue(String? mac) {
    return switch (MacRandomizationClassifier.classify(mac)) {
      MacRandomization.randomized => 'Randomized (locally administered)',
      MacRandomization.universal => 'Universal (burned-in)',
      MacRandomization.unreadable => null,
    };
  }

  /// The honesty note for an unreadable MAC, PLATFORM-CORRECT, or null when the
  /// MAC parsed. iOS: Apple does not expose the device MAC. Android: the OS
  /// returns a randomized placeholder and hides the real device MAC. Never the
  /// wrong platform's wording (GL-005 / GL-008).
  String? _macTypeNote(String? mac) {
    return MacRandomizationClassifier.classify(mac) ==
            MacRandomization.unreadable
        ? MacRandomizationClassifier.unreadableReason(_macPlatform)
        : null;
  }

  /// The honest note for an absent Country code, platform-correct.
  ///
  /// Android: the regulatory country comes from WifiManager.getCountryCode(),
  /// restricted on Android 11+ and frequently empty to a normal app.
  /// Windows: the value is parsed from the AP's Country information element, so
  /// it is simply absent when the AP does not advertise one (common). Null on
  /// every other platform/state (a present value, or iOS/macOS which carry no
  /// such caveat).
  String? _countryNote(String? countryCode) {
    if (countryCode != null && countryCode.trim().isNotEmpty) return null;
    switch (_source) {
      case WifiInfoSource.androidWifiManager:
        return 'Restricted on Android 11+; the OS does not expose the '
            'regulatory country to this app';
      case WifiInfoSource.windowsNativeWifi:
        return 'Only present when the AP advertises a Country element';
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.iosShortcuts:
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        return null;
    }
  }

  Widget _statusCard(ConnectedAp info) => _Card(
    title: 'Status',
    child: Column(
      children: [
        _MetricRow(label: 'Wi-Fi Radio', value: info.poweredOn ? 'On' : 'Off'),
      ],
    ),
  );

  /// Whether [channel] is a 6 GHz Preferred Scanning Channel (PSC). PSC channels
  /// are 5, 21, 37, ... 229 -- (ch - 5) a multiple of 16 across 6 GHz. False for
  /// 2.4 and 5 GHz.
  static bool _isPscChannel(int? channel, String? band) {
    if (channel == null || band != '6 GHz') return false;
    if (channel < 5 || channel > 233) return false;
    return (channel - 5) % 16 == 0;
  }

  /// Formats a channel width in MHz, special-casing the 80+80 MHz sentinel
  /// (8080) the Android native side emits for two non-contiguous 80 MHz
  /// segments. Returns null so the row renders "Unavailable" when the width is
  /// absent. The "80+80" case carries its own unit, so the row drops the trailing
  /// "MHz" (see [_channelWidthHasUnit]).
  static String? _formatChannelWidth(int? mhz) {
    if (mhz == null) return null;
    if (mhz == 8080) return '80+80 MHz';
    return mhz.toString();
  }

  /// Whether the formatted channel-width value still needs a trailing "MHz"
  /// unit. The 80+80 sentinel already embeds its unit, so it does not.
  static bool _channelWidthHasUnit(int? mhz) => mhz != null && mhz != 8080;

  /// Formats a Mbps rate without a trailing ".0", or null so the row renders
  /// "Unavailable".
  static String? _formatRate(double? mbps) {
    if (mbps == null) return null;
    if (mbps == mbps.roundToDouble()) return mbps.toStringAsFixed(0);
    return mbps.toStringAsFixed(1);
  }
}

// ===========================================================================
// Shared presentation widgets
// ===========================================================================

/// Honest per-platform state for Android / Windows / desktop Linux (adapters are
/// later tickets).
class _PlatformComingSoon extends StatelessWidget {
  const _PlatformComingSoon();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_find_outlined,
                size: 48,
                color: colors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Coming in a later update',
                style: text.headlineSmall?.copyWith(
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'The native Wi-Fi data path for this platform is coming in a '
                "later update. On macOS, Wi-Fi Information reads the link "
                'directly through CoreWLAN; on iOS, it reads the connected '
                "access point's RF metrics through a companion Shortcut.",
                style: text.bodyLarge?.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// macOS loading card (before the first snapshot resolves).
class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            // Foreground accent → darkened-lime in light (§8.20.2).
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.textAccent,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Reading Wi-Fi link state…',
                style: text.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// ---- Snapshot-source location card (macOS Location Services / Android
// ACCESS_FINE_LOCATION) ----

/// The Grant / Open Settings affordance pair for the iOS Wi-Fi security gate.
///
/// Instance #7 of the dead-control family lived here as an unguarded
/// `FilledButton('Grant Location')`: it rendered whenever the native read was
/// blocked, including under `denied`, where iOS will never surface the system
/// prompt again. Tapping it did nothing, forever.
class _SecurityLocationActions extends StatelessWidget {
  const _SecurityLocationActions({
    required this.status,
    required this.onGrant,
    required this.onOpenSettings,
  });

  /// The platform's own authorization tri-state.
  ///
  /// THE load-bearing input. It is `required`, and it is the full enum rather
  /// than a pre-computed bool, for two reasons: a call site cannot forget to
  /// consult it (this widget will not compile without it), and the promptable
  /// question is answered HERE by [LocationAuthStatus.isPromptable] rather than
  /// re-derived at each call site, where the derivations drift apart.
  /// See [[feedback_ui_rendered_a_decision_it_lacked]].
  final LocationAuthStatus status;

  /// Fires the native permission prompt. Only ever rendered while a prompt can
  /// actually appear.
  final VoidCallback onGrant;

  /// Deep-links to the app's iOS Settings page — the only route that can work
  /// once the status leaves `notDetermined`.
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    // THE FIX. The in-app grant renders ONLY where iOS can still surface a
    // prompt. Under denied / restricted the deep-link is the only route that
    // can work, so it takes the primary weight instead of sitting as an
    // outlined afterthought beside a button that cannot act.
    final bool showGrant = status.isPromptable;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        if (showGrant)
          Semantics(
            button: true,
            label: 'Grant Location permission to read Wi-Fi security',
            child: FilledButton(
              onPressed: onGrant,
              child: const Text('Grant Location'),
            ),
          ),
        Semantics(
          button: true,
          label: 'Open Location settings',
          child: showGrant
              ? OutlinedButton(
                  onPressed: onOpenSettings,
                  child: const Text('Open Settings'),
                )
              : FilledButton(
                  onPressed: onOpenSettings,
                  child: const Text('Open Settings'),
                ),
        ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.message,
    required this.promptable,
    required this.onGrant,
    required this.onOpenSettings,
    this.platformIsAndroid = false,
  });

  final String message;

  /// Whether the OS can still surface an in-app permission prompt.
  ///
  /// THE load-bearing input, and the one this card used to lack. It is
  /// `required` on purpose: a call site cannot forget to consult the
  /// authorization state, because the card will not compile without it. Both
  /// gated platforms stop prompting once the status leaves `notDetermined`
  /// (macOS TCC never re-prompts; Android will not re-prompt after a permanent
  /// denial), so rendering an in-app grant outside that state produces a button
  /// guaranteed to do nothing at all. See [[feedback_ui_rendered_a_decision_it_lacked]].
  final bool promptable;

  /// When null, the card is informational (post-grant) and hides the Grant
  /// button to avoid an endless re-tap loop. A non-null callback is still only
  /// rendered when [promptable] is true.
  final VoidCallback? onGrant;

  /// Deep-links to the OS settings pane (macOS Location Services / Android app
  /// permissions). When null the settings affordance and the numbered steps are
  /// hidden.
  final VoidCallback? onOpenSettings;

  /// Whether the card is shown for the Android source (drives the button labels
  /// and the manual-enable steps wording).
  final bool platformIsAndroid;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    // THE FIX for the dead button. The in-app grant renders ONLY where the OS
    // can actually surface a prompt. Under denied / restricted the deep-link is
    // the only route that can work, so it takes the primary weight instead of
    // sitting as an outlined afterthought beside a button that cannot act.
    final bool showGrant = promptable && onGrant != null;
    final bool settingsIsPrimary = !showGrant;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 20,
                color: colors.textAccent, // foreground accent (§8.20.2)
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: text.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          // The Grant button tries the system prompt, and is therefore rendered
          // only while a prompt can still appear (notDetermined). The Open
          // Location Settings button deep-links to the exact pane for the
          // reliable manual path, and becomes the primary action once it is the
          // only one that can work. Both wrap on a narrow card.
          if (showGrant || onOpenSettings != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                if (showGrant)
                  Semantics(
                    button: true,
                    label: 'Grant Location permission',
                    child: FilledButton(
                      onPressed: onGrant,
                      child: const Text('Grant Location'),
                    ),
                  ),
                if (onOpenSettings != null)
                  Semantics(
                    button: true,
                    label: settingsIsPrimary
                        ? (platformIsAndroid
                            ? 'Open app Location settings to enable Location '
                                'for this app'
                            : 'Open macOS Location Services settings to enable '
                                'Location for this app')
                        : (platformIsAndroid
                            ? 'Open app Location settings'
                            : 'Open macOS Location Services settings'),
                    // Primary weight when it is the only action that can work,
                    // so the one usable route is not the quiet one.
                    child: settingsIsPrimary
                        ? FilledButton(
                            onPressed: onOpenSettings,
                            child: Text(
                              platformIsAndroid
                                  ? 'Open App Settings'
                                  : 'Open Location Settings',
                            ),
                          )
                        : OutlinedButton(
                            onPressed: onOpenSettings,
                            child: Text(
                              platformIsAndroid
                                  ? 'Open App Settings'
                                  : 'Open Location Settings',
                            ),
                          ),
                  ),
              ],
            ),
          ],
          if (onOpenSettings != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _LocationSteps(platformIsAndroid: platformIsAndroid),
          ],
        ],
      ),
    );
  }
}

/// Short numbered steps for enabling the Location permission manually (macOS
/// Location Services / Android app permissions). Shown under the Location card's
/// buttons. Each step is plain text; the whole block reads as one list to a
/// screen reader.
class _LocationSteps extends StatelessWidget {
  const _LocationSteps({this.platformIsAndroid = false});

  final bool platformIsAndroid;

  static const List<String> _macSteps = <String>[
    'Open Location Settings (button above).',
    'Turn on WLAN Pros Toolbox.',
    'Come back and tap Refresh.',
  ];

  static const List<String> _androidSteps = <String>[
    'Open App Settings (button above).',
    'Tap Permissions, then Location, and allow it.',
    'Come back and tap Refresh.',
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? style = text.bodySmall?.copyWith(
      color: colors.textTertiary,
    );
    final List<String> steps =
        platformIsAndroid ? _androidSteps : _macSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : AppSpacing.xxs,
            ),
            child: Text('${i + 1}. ${steps[i]}', style: style),
          ),
      ],
    );
  }
}

// ---- macOS Wi-Fi off card ----

class _WifiOffCard extends StatelessWidget {
  const _WifiOffCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wifi_off, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wi-Fi is off',
                  style: text.titleMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Turn Wi-Fi on to read live link details. Any values still '
                  'reported by the system are shown below.',
                  style: text.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- macOS error card ----

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final WifiInfoUnavailable? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String? detail = error?.detail;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: colors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No Wi-Fi reading available',
                      style: text.titleMedium?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detail != null && detail.trim().isNotEmpty
                          ? detail
                          : 'The system did not return a Wi-Fi snapshot. '
                                'There may be no active Wi-Fi interface.',
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label: 'Retry reading Wi-Fi information',
                child: FilledButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- Reusable card shell (matches interface_info_screen._Card) ----

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.child,
    this.verticalPadding = AppSpacing.sm,
  });

  final String title;
  final Widget child;

  /// Top/bottom inset for the card. Defaults to `sm` (16px) for the macOS
  /// snapshot / idle / error cards. The Live charts pass a tighter `xs` (8px)
  /// so the dense per-metric sparkline stack fits a phone screen without
  /// clipping, horizontal inset stays `sm` so content edges still align.
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: verticalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

// ---- Single metric row ----
//
// One label -> value row. A null/empty value renders "Unavailable" in
// textSecondary (muted but clears WCAG 4.5:1 -- never textTertiary for value
// text, never a dash, never a fake 0). Live values render in textPrimary. Each
// row is a single semantic node so a screen reader speaks "label, value" (or
// "label, Unavailable", with any honesty note appended) as one unit.

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.note,
    this.unit,
    this.marker,
    this.derived = false,
  });

  final String label;
  final String? value;
  final bool mono;

  /// Optional note under the value. For an Unavailable value it explains why
  /// (e.g. "Not exposed by macOS CoreWLAN"); for a present value it is a
  /// footnote tied to [marker] (e.g. the PSC explanation).
  final String? note;

  /// Unit appended to the value (e.g. "dBm"), tied to the number so it scans as
  /// "-50 dBm". Omitted when unavailable.
  final String? unit;

  /// Optional marker glyph (e.g. "*") appended to the value and prefixing
  /// [note]. Shown only for a present value; excluded from the spoken value.
  final String? marker;

  /// Appends a quiet "derived" caption -- the value is app-computed (e.g. SNR or
  /// Band on the iOS path), not source-reported. Honest labeling.
  final bool derived;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasValue = value != null && value!.trim().isNotEmpty;
    final String shown = hasValue
        ? (unit == null ? value! : '${value!} $unit')
        : 'Unavailable';
    final String displayValue = (hasValue && marker != null)
        ? '$shown $marker'
        : shown;
    final bool showNote = note != null;
    final String footnote = note == null
        ? ''
        : (marker != null ? '$marker $note' : note!);

    final String labelSpoken = derived ? '$label, derived' : label;
    final String semanticLabel = showNote
        ? '$labelSpoken, $shown, $note'
        : '$labelSpoken, $shown';

    final AppMonoText monoText =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final Color valueColor = hasValue
        ? colors.textPrimary
        : colors.textSecondary;
    final TextStyle? valueStyle = (mono && hasValue)
        ? monoText.robotoMono.copyWith(color: valueColor)
        : text.bodyMedium?.copyWith(color: valueColor);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Semantics(
        container: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: text.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      if (derived)
                        Text(
                          'derived',
                          style: text.labelSmall?.copyWith(
                            color: colors.textTertiary,
                            letterSpacing: 0.4,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 3,
                  child: Text(
                    displayValue,
                    textAlign: TextAlign.end,
                    style: valueStyle,
                  ),
                ),
              ],
            ),
            if (showNote) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                footnote,
                textAlign: TextAlign.end,
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// iOS Live mode, continuous streaming surface (the only iOS mode)
// ===========================================================================

/// The Live body: the Start/Stop monitor bar, and either the idle start hint,
/// the waiting state, or the live charts. Rebuilds on each streamed payload via
/// an [AnimatedBuilder] over the [WifiMonitorController]. Stop freezes the last
/// values on screen (the snapshot); there is no separate snapshot mode.
class _LiveBody extends StatelessWidget {
  const _LiveBody({
    required this.controller,
    required this.series,
    required this.edge,
    required this.triggerError,
    required this.onStart,
    required this.onStop,
    required this.onSetUp,
    required this.onRetryConnection,
    required this.enrich,
    required this.metricCardsBuilder,
    required this.nativeIdentity,
    required this.nativeIdentityCardsBuilder,
  });

  final WifiMonitorController controller;
  final WifiTimeSeries series;
  final double edge;
  final bool triggerError;

  /// The single live action: Start continuous monitoring (Keith device round 5 —
  /// Get reading removed). Keeps the iOS banner up while running; [onStop] ends it.
  final VoidCallback onStart;
  final VoidCallback onStop;

  /// Opens the one-time companion-Shortcut install sheet. Wired to both the
  /// first-run setup prompt and the post-failure setup card.
  final VoidCallback onSetUp;

  /// Re-runs the connection probe + install-state resolve. Wired to the
  /// not-on-Wi-Fi card's "Check again" action so a user who has just joined Wi-Fi
  /// can re-check without leaving the screen.
  final VoidCallback onRetryConnection;

  /// Folds the native iOS security token + BSSID onto a Shortcut-derived reading
  /// so the Security / AP-vendor rows render from the same model as every other
  /// card. Identity off the iOS path.
  final ConnectedAp Function(ConnectedAp) enrich;

  /// Builds the grouped metric cards (Network / Signal / Rate / Channel / Radio
  /// / Status) for the latest reading. Owned by the State so iOS and macOS share
  /// the identical card presentation; rendered BELOW the live charts.
  final List<Widget> Function(ConnectedAp latest) metricCardsBuilder;

  /// The natively-readable connected-network identity (SSID / BSSID / security),
  /// or null before the native read resolves. When present and no Shortcut RF
  /// sample has arrived yet, the body shows these real basics immediately
  /// (native-first) instead of a dead start hint.
  final ConnectedAp? nativeIdentity;

  /// Builds the native-first identity cards (Network + Security) for the
  /// pre-payload state. Owned by the State so the card presentation matches the
  /// post-payload cards exactly.
  final List<Widget> Function(ConnectedAp native) nativeIdentityCardsBuilder;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final ConnectedAp? ap = controller.details == null
                ? null
                : enrich(ConnectedAp.fromWifiDetails(controller.details!));
            // Surface the reinstall card for BOTH error cases: the trigger could
            // not open (open-failed, [triggerError]) OR it opened but a deleted
            // "WLAN Pros Live" Shortcut delivered nothing ([controller.shortcutMissing],
            // set asynchronously after the settle). This is the in-context recovery
            // for users who removed the Shortcut.
            //
            // CONTRADICTION GUARD (2026-06-26, device round 2): never show "could
            // not start" while the feed is genuinely LIVE with data. The earlier
            // build could show "LIVE" + "could not start" + "set up" at once when a
            // stale error flag lingered behind a streaming session. Suppressing the
            // error card whenever we are actually streaming with samples keeps the
            // live state to ONE coherent reading.
            final bool liveWithData =
                controller.isStreaming && !series.isEmpty;
            final bool showSetupError =
                (triggerError || controller.shortcutMissing) && !liveWithData;

            // NOT-ON-WIFI (2026-06-25): the device is demonstrably off Wi-Fi
            // (e.g. cellular-only) and no live reading has ever arrived. Show the
            // honest "connect to Wi-Fi" message instead of the setup CTA or an
            // endless "waiting" spinner — the companion Shortcut cannot read
            // Wi-Fi RF that does not exist. Once a Wi-Fi network is joined and the
            // user taps "Check again" (or the app resumes), the probe clears this
            // and the normal setup / live flow resumes.
            if (controller.phase == WifiMonitorPhase.notOnWifi) {
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  edge,
                  AppSpacing.sm,
                  edge,
                  edge + AppSpacing.sm,
                ),
                child: NotOnWifiCard(onRetry: onRetryConnection),
              );
            }

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // SINGLE ACTION = Start Live Monitoring (2026-06-26, Keith device
                  // round 5: Get reading removed; streaming is the one live action).
                  // The control bar is SUPPRESSED during priming so the
                  // LivePrimingCard below is the single Start CTA (no stacked
                  // buttons, SOP-009 §7). When set up, Start fires the stream (the
                  // Start-aware settle surfaces recovery if the Shortcut is missing);
                  // when not set up, Start routes to the SETUP sheet.
                  if (!controller.setupInitiated)
                    _MonitorControlBar(
                      streaming: controller.isStreaming,
                      lastUpdated: controller.lastUpdated,
                      onStart:
                          controller.hasEverReceived ? onStart : onSetUp,
                      onStop: onStop,
                      setUpMode: !controller.hasEverReceived,
                    ),
                  if (controller.setupInitiated && !showSetupError) ...[
                    const SizedBox(height: AppSpacing.sm),
                    // POST-INSTALL PRIMING (2026-06-26): the user started setup but
                    // no payload has completed the round-trip yet (iOS cannot report
                    // install-state). Show the honest "tap Start Live Monitoring to
                    // finish; iOS asks permission the first time" step instead of
                    // the cold setup prompt. The first stream sample flips
                    // hasEverReceived and clears priming.
                    LivePrimingCard(onStart: onStart),
                  ],
                  if (showSetupError) ...[
                    const SizedBox(height: AppSpacing.sm),
                    // A failed Start (or a deleted Shortcut) leads with the
                    // actionable setup card — the honest "could not start" message
                    // PLUS the one-time "Set up live Wi-Fi" button — instead of a
                    // dead-end error or a silent no-op.
                    LiveSetupCard.error(
                      label: 'Set up live Wi-Fi (one-time)',
                      onSetUp: onSetUp,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  // When the recovery/error card is showing it is the SINGLE source
                  // of guidance, so with no data yet the pre-payload locked card +
                  // hint AND the "waiting" state are suppressed — otherwise the hint
                  // would name a "Start Live Monitoring" button that is not on
                  // screen and softly contradict the error card (Vera M3, same
                  // defect class as H1/H2). Charts still render if data exists.
                  if (showSetupError && series.isEmpty)
                    const SizedBox.shrink()
                  else if (!controller.isStreaming && series.isEmpty) ...<Widget>[
                    // NATIVE-FIRST pre-payload state (Pax anti-pattern #1 fix):
                    // never open to dead/zeroed RF fields. Show the real
                    // connected-network basics the app reads natively
                    // (SSID / BSSID / security) the instant they resolve, then
                    // the rich RF fields listed by NAME as "available once you
                    // enable live Wi-Fi" — never fabricated zeros.
                    if (nativeIdentity != null) ...<Widget>[
                      ...nativeIdentityCardsBuilder(nativeIdentity!),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    LiveRfLockedCard(
                      // SINGLE ACTION (2026-06-26): the native identity (SSID /
                      // BSSID / security via NEHotspotNetwork) resolves with NO
                      // Shortcut, so its presence does NOT prove the Shortcut is
                      // installed. Start Live Monitoring ONLY when set up
                      // (hasEverReceived) OR priming (setupInitiated); otherwise
                      // open the setup sheet first so a clean install never trips
                      // "the file doesn't exist".
                      // The control bar / priming card / setup card already carry
                      // the single live CTA, so this card is a button-less field
                      // LIST — no stacked Start/Set up actions (SOP-009 §7).
                      onEnable: onStart,
                      showAction: false,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // Cold-aware ONLY in the true cold state. `!hasEverReceived` is
                    // true in BOTH cold AND priming; gating also on
                    // `!setupInitiated` keeps the priming hint on the Start copy so
                    // it matches the LivePrimingCard above (Vera H2) instead of
                    // naming a "Set up" button not on screen during priming.
                    _LiveStartHint(
                      setUpMode: !controller.hasEverReceived &&
                          !controller.setupInitiated,
                    ),
                  ] else if (series.isEmpty)
                    _WaitingForFirstPayload(streaming: controller.isStreaming)
                  else ...<Widget>[
                    _LiveCharts(
                      series: series,
                      latest: ap,
                      platformLabel: 'iOS Live',
                    ),
                    // Grouped metric cards BELOW the sparklines (same surface as
                    // macOS). Rendered once a sample exists; fields the iOS
                    // stream does not carry render an honest "Unavailable" row.
                    if (ap != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      ...metricCardsBuilder(ap),
                    ],
                  ],
                  // First-time SETUP prompt only. Once the app has EVER received
                  // a Live payload (hasEverReceived, mirrors the App Group
                  // shortcuts_bridge.has_received_payload flag), the user clearly
                  // has the companion Shortcut working, so the setup prompt is
                  // noise and is hidden permanently — it never nags. While a
                  // Start error is showing, the error card above already carries
                  // the setup button, so this neutral prompt is suppressed to
                  // avoid two setup cards at once.
                  //
                  // The pre-payload state ALWAYS renders the LiveRfLockedCard,
                  // whose own "Enable live Wi-Fi" button is the single enable CTA
                  // (it routes to the install sheet via onSetUp when there is no
                  // native identity yet, or starts live readings when the native
                  // identity is already on screen). So this neutral prompt is
                  // suppressed whenever that pre-payload card is showing — with OR
                  // without a native identity — to avoid two competing setup CTAs,
                  // one of which lands below the fold (the prior double-CTA bug).
                  if (!controller.hasEverReceived &&
                      !controller.setupInitiated &&
                      !showSetupError &&
                      // ignore: prefer_is_not_empty
                      (controller.isStreaming || !series.isEmpty)) ...[
                    const SizedBox(height: AppSpacing.sm),
                    LiveSetupCard.prompt(
                      label: 'Set up live Wi-Fi (one-time)',
                      onSetUp: onSetUp,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Live-mode prompt before any sample has been captured and monitoring is not
/// running. Cold-aware (GL-005): when the Shortcut is not set up yet the only
/// button on screen is "Set up live Wi-Fi" (the control bar is in setUpMode), so
/// the hint must name THAT action — not a "Start Live Monitoring" control that
/// does not exist yet (Vera H1, device round 5). Once set up, it names Start.
class _LiveStartHint extends StatelessWidget {
  const _LiveStartHint({this.setUpMode = false});

  final bool setUpMode;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Text(
        setUpMode
            ? 'Live Wi-Fi signal comes from the one-time "WLAN Pros Live" '
                'companion Shortcut. Tap Set up live Wi-Fi to add it, then your '
                'live signal streams here.'
            : 'Tap Start Live Monitoring above to begin your live Wi-Fi signal. '
                'The companion Shortcut streams readings and the values fill in; '
                'tap Stop to end.',
        style: text.bodyLarge?.copyWith(color: colors.textSecondary),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Live sparkline chart height. A denser glyph metric than the [Sparkline]
/// default (40) so the four-metric Live stack (RSSI / SNR / Tx / Rx) fits a
/// phone screen without the bottom card clipping; still tall enough to read the
/// trend. Live-mode only, the macOS snapshot cards carry no sparkline.
const double _liveSparklineHeight = 32;

/// The Live charting + grading surface. RSSI and SNR each carry a graded chip +
/// sparkline; Tx and Rx rate each carry a trend label + sparkline (rates are
/// NOT hard-graded, a "good" rate is relative to band/width/MCS, so the value +
/// direction is the honest signal). Congestion / CCA is intentionally absent;
/// iOS does not expose channel utilization and we do not fabricate it (GL-005).
class _LiveCharts extends StatelessWidget {
  const _LiveCharts({
    required this.series,
    required this.latest,
    required this.platformLabel,
  });

  /// Platform label for the honest "unavailable" reasons on the charts, e.g.
  /// 'macOS CoreWLAN' or 'iOS Live'. Matches the metric cards' wording.
  final String platformLabel;

  final WifiTimeSeries series;

  /// The latest connected-AP reading, for the current-value readout. May be
  /// null briefly between Start and the first streamed payload.
  final ConnectedAp? latest;

  @override
  Widget build(BuildContext context) {
    final int? rssi = latest?.rssiDbm;
    final int? snr = latest?.snrDb;
    final double? tx = latest?.txRateMbps;
    final double? rx = latest?.rxRateMbps;
    final bool rxAvail = latest?.rxRateAvailable ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // H2 — the full charted RSSI + Tx-rate trend over the rolling window,
        // each with a current/min/avg/max readout. The genuine competitor gap:
        // the graded sparklines below read the DIRECTION; this section reads the
        // SHAPE (axes + stats). Same rolling [series] the screen already fills;
        // no new measurement. Rx degrades gracefully (see [WifiLiveTrend]).
        WifiLiveTrend(
          series: series,
          latest: latest,
          platformLabel: platformLabel,
        ),
        const SizedBox(height: AppSpacing.sm),
        _GradedMetricChart(
          label: 'RSSI',
          unit: 'dBm',
          currentValue: rssi?.toString(),
          grade: WifiGrading.gradeRssi(rssi),
          window: series.rssi,
        ),
        const SizedBox(height: AppSpacing.xs),
        _GradedMetricChart(
          label: 'SNR',
          unit: 'dB',
          currentValue: snr?.toString(),
          grade: WifiGrading.gradeSnr(snr),
          window: series.snr,
          derived: latest?.snrDerived ?? false,
        ),
        const SizedBox(height: AppSpacing.xs),
        _TrendMetricChart(
          label: 'Tx Rate',
          unit: 'Mbps',
          currentValue: _WifiInfoScreenState._formatRate(tx),
          window: series.txRate,
        ),
        const SizedBox(height: AppSpacing.xs),
        _TrendMetricChart(
          label: 'Rx Rate',
          unit: 'Mbps',
          currentValue:
              rxAvail ? _WifiInfoScreenState._formatRate(rx) : null,
          window: series.rxRate,
          // Distinguish a permanent platform limit (macOS never exposes Rx →
          // rxRateAvailable false) from the Android device-link sentinel and a
          // per-sample iOS miss (FIX 2: Android wording matches the static
          // Rate card so the live and detail surfaces never disagree).
          unavailableNote: latest == null
              ? null
              : !rxAvail
                  ? 'Not exposed by $platformLabel'
                  : (rx == null
                      ? (platformLabel == 'Android'
                          ? "Not reported by this device's Android link"
                          : 'Not in this reading')
                      : null),
        ),
      ],
    );
  }
}

/// A hard-graded dimension card: label, current value, grade chip, and a
/// sparkline tinted to the grade. The grade WORD carries the meaning; the tint
/// only reinforces it (SC 1.4.1). A null current value renders "Unavailable"
/// and the grade is [QualityGrade.unavailable].
class _GradedMetricChart extends StatelessWidget {
  const _GradedMetricChart({
    required this.label,
    required this.unit,
    required this.currentValue,
    required this.grade,
    required this.window,
    this.derived = false,
  });

  final String label;
  final String unit;
  final String? currentValue;
  final QualityGrade grade;
  final List<double?> window;
  final bool derived;

  @override
  Widget build(BuildContext context) {
    final bool hasValue =
        currentValue != null && currentValue!.trim().isNotEmpty;
    final String shown = hasValue ? '$currentValue $unit' : 'Unavailable';
    final String semantic =
        '$label${derived ? ', derived' : ''}, $shown, ${grade.label}';
    final AppColorScheme colors = context.colors;
    final Color lineColor = _gradeLineColor(grade, colors);

    return _Card(
      title: label,
      verticalPadding: AppSpacing.xs,
      child: Semantics(
        container: true,
        label: semantic,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: _CurrentReadout(value: shown, hasValue: hasValue),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _GradeChip(grade: grade),
                ],
              ),
              if (derived) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'derived',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textTertiary,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xxs),
              Sparkline(
                values: window,
                lineColor: lineColor,
                semanticLabel: '$label trend',
                height: _liveSparklineHeight,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tints the sparkline to match the grade chip (reinforcement only). The
  /// unavailable case stays neutral tertiary so it does not read as a verdict.
  static Color _gradeLineColor(QualityGrade grade, AppColorScheme colors) {
    switch (grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return colors.statusSuccess;
      case QualityGrade.fair:
        return colors.statusWarning;
      case QualityGrade.poor:
        return colors.statusDanger;
      case QualityGrade.unavailable:
        return colors.textTertiary;
    }
  }
}

/// A trend dimension card (rates): label, current value, and a lime sparkline.
/// Rates are not hard-graded, so the line stays the §8.3 lime accent (no verdict
/// tint) and the sparkline alone carries the rising/falling/steady signal, the
/// redundant trend word was dropped 2026-06-02 (Keith). When the platform does
/// not expose the rate, an honest [unavailableNote] explains why.
class _TrendMetricChart extends StatelessWidget {
  const _TrendMetricChart({
    required this.label,
    required this.unit,
    required this.currentValue,
    required this.window,
    this.unavailableNote,
  });

  final String label;
  final String unit;
  final String? currentValue;
  final List<double?> window;
  final String? unavailableNote;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasValue =
        currentValue != null && currentValue!.trim().isNotEmpty;
    final String shown = hasValue ? '$currentValue $unit' : 'Unavailable';
    final String semantic = unavailableNote != null
        ? '$label, $shown, $unavailableNote'
        : '$label, $shown';

    return _Card(
      title: label,
      verticalPadding: AppSpacing.xs,
      child: Semantics(
        container: true,
        label: semantic,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _CurrentReadout(value: shown, hasValue: hasValue),
              if (unavailableNote != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  unavailableNote!,
                  style: text.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xxs),
              Sparkline(
                values: window,
                semanticLabel: '$label trend',
                height: _liveSparklineHeight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The large mono current-value readout for a Live chart card.
class _CurrentReadout extends StatelessWidget {
  const _CurrentReadout({required this.value, required this.hasValue});

  final String value;
  final bool hasValue;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextTheme text = Theme.of(context).textTheme;
    return hasValue
        ? Text(
            value,
            style: mono.outputMedium.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : Text(
            value,
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
          );
  }
}

/// The §8.13 grade chip, matching net_quality_screen / wifi_vs_internet_screen
/// so every graded surface reads identically. The grade WORD carries the
/// meaning; the color only reinforces it (SC 1.4.1).
class _GradeChip extends StatelessWidget {
  const _GradeChip({required this.grade});

  final QualityGrade grade;

  /// Dark grade chip: solid status fill + dark (onPrimary) text. Unavailable is
  /// a neutral surface2 chip with a borderStrong outline.
  static (Color, Color) _darkColors(QualityGrade grade, AppColorScheme c) {
    switch (grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return (c.statusSuccess, c.onPrimary);
      case QualityGrade.fair:
        return (c.statusWarning, c.onPrimary);
      case QualityGrade.poor:
        return (c.statusDanger, c.onPrimary);
      case QualityGrade.unavailable:
        return (c.surface2, c.textSecondary);
    }
  }

  /// Light Style A parts (§8.20.4): the SOLID full-strength status hue fill and
  /// its Material glyph. The label + glyph render in WHITE on the fill.
  /// Unavailable has no status hue, so it fills with neutral textSecondary.
  static (Color fill, IconData? glyph) _lightParts(
      QualityGrade grade, AppColorScheme c) {
    switch (grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return (c.statusSuccess, Icons.check_circle);
      case QualityGrade.fair:
        return (c.statusWarning, Icons.warning_amber);
      case QualityGrade.poor:
        return (c.statusDanger, Icons.error);
      case QualityGrade.unavailable:
        // Neutral solid fill (textSecondary #4A4A4A, white-on-fill 9.0:1).
        return (c.textSecondary, Icons.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;

    // §8.20.4 Style A — light renders status as a SOLID-FILL PILL: the
    // full-strength status hue fill carrying a WHITE 700 label + WHITE Material
    // glyph, no border (white-on-fill 5.4–5.9:1). Dark keeps its solid-fill chip
    // unchanged.
    if (colors.isLight) {
      const Color white = Color(0xFFFFFFFF);
      final (Color fill, IconData? glyph) = _lightParts(grade, colors);
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (glyph != null) ...<Widget>[
              Icon(glyph, size: 16, color: white),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Flexible(
              child: Text(
                grade.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(
                  color: white,
                  fontWeight: FontWeight.w700, // §8.20.3-A verdict words
                ),
              ),
            ),
          ],
        ),
      );
    }

    final (Color bg, Color fg) = _darkColors(grade, colors);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: grade == QualityGrade.unavailable
            ? Border.all(color: colors.borderStrong, width: 1)
            : null,
      ),
      child: Text(
        grade.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}


/// iOS control bar (2026-06-23): the DEFAULT one-shot "Get reading" plus the
/// opt-in "Start live monitoring", with a live indicator + last-updated stamp.
/// While streaming it shows the single "Stop" control.
class _MonitorControlBar extends StatelessWidget {
  const _MonitorControlBar({
    required this.streaming,
    required this.lastUpdated,
    required this.onStart,
    required this.onStop,
    this.setUpMode = false,
  });

  final bool streaming;
  final DateTime? lastUpdated;

  /// The single live action: Start continuous monitoring (Keith device round 5 —
  /// Get reading removed). In [setUpMode] the caller routes this to the install
  /// sheet instead of firing the Shortcut.
  final VoidCallback onStart;
  final VoidCallback onStop;

  /// True when the companion Shortcut is NOT demonstrably installed
  /// (hasEverReceived == false). The primary action then reads "Set up live
  /// Wi-Fi" and installs the Shortcut (the caller routes [onStart] to setup),
  /// stopping a clean install from blind-firing the missing Shortcut.
  final bool setUpMode;

  static String _formatTimestamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// Below this width the status and action stack vertically (reflow, not clip)
  /// so the bar survives 320px at 200% type. GL-003 §8.9.
  static const double _reflowThreshold = 280;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool narrow = constraints.maxWidth < _reflowThreshold;
          final Widget status = _StatusBlock(
            streaming: streaming,
            lastUpdated: lastUpdated,
          );
          // SINGLE ACTION (2026-06-26): while streaming the bar shows Stop;
          // otherwise the ONE green primary is Start Live Monitoring (or, when the
          // Shortcut is not set up, the Set up CTA the caller routes [onStart] to).
          final Widget primaryAction = streaming
              ? _StopButton(onStop: onStop)
              : setUpMode
                  ? _SetUpLiveButton(onSetUp: onStart)
                  : _StartMonitoringButton(onStart: onStart);

          final Widget header = narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    status,
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: primaryAction,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: status),
                    const SizedBox(width: AppSpacing.xs),
                    primaryAction,
                  ],
                );

          if (streaming || setUpMode) return header;

          // Set up + idle: the one green Start, with an honest one-line note on
          // what it does. GL-004: no marketing words.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              header,
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Streams your live Wi-Fi signal continuously and keeps a status '
                'banner up while running; tap Stop to end.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Status block: state icon + "Live"/"Paused" + "Updated HH:MM:SS". The block
/// is one live region keyed only on the "Live"/"Paused" state word, so a Start
/// or Stop transition announces once (WCAG 2.2 SC 4.1.3). The "Updated" stamp
/// ticks ~1×/s while streaming, so it is wrapped in [ExcludeSemantics] to avoid
/// re-announcing the whole line every tick.
class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.streaming, required this.lastUpdated});

  final bool streaming;
  final DateTime? lastUpdated;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String label = streaming ? 'Live' : 'Paused';

    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (streaming)
            const _LiveIndicator()
          else
            Icon(
              Icons.pause_circle_outline,
              size: 20,
              color: colors.textTertiary,
            ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: text.labelLarge?.copyWith(
                    // "Live" label is a foreground accent → darkened-lime in
                    // light (§8.20.2); the word carries the meaning regardless.
                    color: streaming
                        ? colors.textAccent
                        : colors.textSecondary,
                  ),
                ),
                if (lastUpdated != null)
                  ExcludeSemantics(
                    child: Text(
                      'Updated ${_MonitorControlBar._formatTimestamp(lastUpdated!)}',
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Install CTA shown in the control bar when the companion Shortcut is not
/// demonstrably installed (hasEverReceived == false). Opens the one-time setup
/// sheet instead of firing the run-shortcut URL, so a clean install never trips
/// the "the file doesn't exist" Shortcuts error. Same lime-primary prominence as
/// "Get reading" so the action a new user needs is the obvious one.
class _SetUpLiveButton extends StatelessWidget {
  const _SetUpLiveButton({required this.onSetUp});

  final VoidCallback onSetUp;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Set up live Wi-Fi',
      child: FilledButton.icon(
        onPressed: onSetUp,
        icon: const SetupLiveWifiIcon(),
        label: const Text('Set up live Wi-Fi'),
      ),
    );
  }
}

/// The single prominent lime-primary live action: Start continuous monitoring
/// (Keith device round 5 — Get reading removed, so this is now the green primary).
class _StartMonitoringButton extends StatelessWidget {
  const _StartMonitoringButton({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Start live monitoring',
      child: FilledButton.icon(
        onPressed: onStart,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start live monitoring'),
      ),
    );
  }
}

/// The Stop control shown while continuous streaming is running.
class _StopButton extends StatelessWidget {
  const _StopButton({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Stop live monitoring',
      child: OutlinedButton.icon(
        onPressed: onStop,
        icon: const Icon(Icons.stop),
        label: const Text('Stop'),
      ),
    );
  }
}

/// Decorative lime "live" dot. The live region + changing label live on
/// [_StatusBlock]; this dot is excluded from the a11y tree. Lime is the §8.3
/// active-state accent, not a verdict.
class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator();

  @override
  Widget build(BuildContext context) {
    // Small lime dot is information-bearing (paired with the "Live" word). On a
    // white surface a 12px brand-lime dot is ~1.65:1 and vanishes, so light uses
    // the darkened-lime textAccent (§8.20.2); the word still carries the state.
    return ExcludeSemantics(
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: context.colors.textAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _WaitingForFirstPayload extends StatelessWidget {
  const _WaitingForFirstPayload({required this.streaming});

  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Text(
        streaming
            ? 'Listening. The recursive Shortcut is sending Wi-Fi details.'
            : 'Press Start to begin streaming Wi-Fi details.',
        style: text.bodyLarge?.copyWith(color: colors.textSecondary),
        textAlign: TextAlign.center,
      ),
    );
  }
}
