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
//   * Android / Windows -> honest "coming in a later update" state (clean seam).
//   * web -> download-the-app fallback.
//
// Both native bridges are retained (macOS WifiInfoChannel.swift + iOS
// ToolboxAppIntents/ShortcutsBridge.swift). Per GL-008/GL-005 a field a platform
// cannot expose renders an explicit "Unavailable" row with a precise reason --
// never a fabricated value, never a silent drop.
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
import '../../../services/network/connected_ap.dart';
import '../../../services/network/connected_ap_cache.dart';
import '../../../services/network/live_onboarding_service.dart';
import '../../../services/network/mac_oui_service.dart';
import '../../../services/network/mac_randomization.dart';
import '../../../services/network/network_support.dart';
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
import 'live_rf_locked_card.dart';
import 'live_setup_card.dart';
import 'network_unavailable_view.dart';

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
  /// if [initState]'s async check overlaps a rebuild.
  bool _firstRunChecked = false;

  @override
  void initState() {
    super.initState();
    _source = widget.sourceOverride ?? WifiInfoSourceResolver.resolve();
    _apCache = widget.connectedApCache ?? ConnectedApCache.instance;
    _loadOuiTable();

    switch (_source) {
      case WifiInfoSource.macosCoreWlan:
        _macAdapter = widget.macAdapter ?? MacWifiInfoAdapter();
        _macSeries = WifiTimeSeries();
        WidgetsBinding.instance.addObserver(this);
        // Seed the first reading, then begin automatic polling so the
        // sparklines start filling without a Start button.
        _fetchMac().then((_) => _startMacPoll());
      case WifiInfoSource.iosShortcuts:
        _iosBridge = widget.iosBridge ?? WiFiDetailsBridge();
        _liveController = WifiMonitorController(bridge: _iosBridge!);
        _series = WifiTimeSeries();
        _liveController!.addListener(_captureSample);
        _securityService = widget.securityService ?? WifiSecurityService();
        _onboardingService = widget.onboardingService ?? LiveOnboardingService();
        WidgetsBinding.instance.addObserver(this);
        _liveController!.load();
        // Read the native security type + BSSID once on open. Re-read on resume
        // (lifecycle) so a Location grant in Settings lands without a relaunch.
        _fetchIosSecurity();
        // Unmissable first-run onboarding: the first time ANY live tool is
        // opened (and the Shortcut is not demonstrably working), present the
        // one-time "enable live Wi-Fi" sheet so a brand-new user is never left
        // to discover the dependency by hitting a wall.
        _maybeShowFirstRunOnboarding();
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        break;
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
        _liveController?.load();
        // Re-read the native security + BSSID so a Location grant made in
        // Settings (while backgrounded) lands without an app relaunch.
        _fetchIosSecurity();
      } else if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        // Ignore the background half of the Shortcut bounce — that backgrounding
        // is the app opening Shortcuts, not the user leaving, and the recursion
        // is supposed to continue.
        if (_shortcutBounceInFlight) return;
        // A genuine background: stop sampling (clears the loop-gate flag so the
        // recursive Shortcut halts on its next check). The last values stay on
        // screen. The user re-taps Start to resume — no auto-resume, no loop.
        final WifiMonitorController? c = _liveController;
        if (c != null && c.isStreaming) {
          c.stopMonitoring();
        }
      }
    }

    // macOS: pause the CoreWLAN poll while backgrounded (no point re-reading a
    // link the user cannot see), resume + re-read on return to foreground.
    if (_source == WifiInfoSource.macosCoreWlan) {
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
    if (_source == WifiInfoSource.macosCoreWlan) {
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
      if (controller != null && controller.isStreaming) {
        controller.stopMonitoring();
      }
      controller?.dispose();
    }
    super.dispose();
  }

  /// Controller listener (iOS Live): appends a sample to [_series] each time a
  /// NEW streamed payload lands while monitoring is running. Guarded so the
  /// many non-sample notifications (phase changes, Start/Stop) do not duplicate
  /// the last reading into the window.
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

    if (!streaming) return;
    final WiFiDetails? d = c.details;
    if (d == null || d == _lastCharted) return;
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
      onInstalled: () async {
        await _liveController?.load();
        if (!mounted) return;
        await _startLive();
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
  /// "Unavailable", and the two per-platform reasons the cards surface
  /// (Rx rate, Channel width) travel as an explicit "Not reported on this
  /// platform" note, never a blank, never a fabricated value.
  String? _buildCopyText() {
    final ConnectedAp? info = _currentAp();
    if (info == null) return null;

    final String platformLabel = _source == WifiInfoSource.iosShortcuts
        ? 'iOS'
        : 'macOS CoreWLAN';
    final StringBuffer buf = StringBuffer()..writeln('Wi-Fi Information');

    buf
      ..writeln()
      ..writeln('Network')
      ..writeln('  SSID: ${_copyVal(info.ssid, null)}')
      ..writeln('  BSSID: ${_copyVal(info.bssid, null)}')
      ..writeln('  AP vendor: ${_copyVal(_apVendorLabel(info.bssid), null)}');

    buf
      ..writeln()
      ..writeln('Security')
      ..writeln(
        '  Security type: ${info.securityAvailable ? _copyVal(info.securityType?.label, null) : 'Not exposed by $platformLabel'}'
        '${(info.securityType?.isPersonalCoarse ?? false) || (info.securityType?.isEnterpriseCoarse ?? false) ? ' (iOS coarse, WPA2/WPA3 not distinguished)' : ''}',
      );

    buf
      ..writeln()
      ..writeln('Signal')
      ..writeln('  RSSI: ${_copyVal(info.rssiDbm?.toString(), 'dBm')}')
      ..writeln('  Noise: ${_copyVal(info.noiseDbm?.toString(), 'dBm')}')
      ..writeln(
        '  SNR: ${_copyVal(info.snrDb?.toString(), 'dB')}'
        '${info.snrDerived ? ' (derived)' : ''}',
      );

    buf
      ..writeln()
      ..writeln('Rate')
      ..writeln('  Tx Rate: ${_copyVal(_formatRate(info.txRateMbps), 'Mbps')}')
      ..writeln(
        '  Rx Rate: ${info.rxRateAvailable ? _copyVal(_formatRate(info.rxRateMbps), 'Mbps') : 'Not exposed by $platformLabel'}',
      );

    final bool isPsc = _isPscChannel(info.channel, info.band);
    buf
      ..writeln()
      ..writeln('Channel')
      ..writeln(
        '  Channel: ${_copyVal(info.channel?.toString(), null)}'
        '${isPsc ? ' (Preferred Scanning Channel)' : ''}',
      )
      ..writeln(
        '  Width: ${info.channelWidthAvailable ? _copyVal(info.channelWidthMhz?.toString(), 'MHz') : 'Not reported by $platformLabel'}',
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
      ..writeln('  MAC type: ${MacRandomizationClassifier.label(info.hardwareAddress)}');

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
          platformLabel: 'macOS CoreWLAN',
        ))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    children.addAll(_metricCards(info, platformLabel: 'macOS CoreWLAN'));
    return children;
  }

  /// macOS location card (three states). Returns null when no card is needed.
  ///
  /// macOS-only, the card and its deep-link are never built on iOS (the iOS
  /// path reads the network name through the Shortcut bridge and has no Location
  /// gate, so it routes through [_iosBody], not here).
  Widget? _buildLocationCard(ConnectedAp info) {
    final bool nameMissing = info.ssid == null && info.bssid == null;
    if (info.ssid != null) return null;

    if (info.ssid == null && _locationGrantAttempted) {
      return const _LocationCard(
        message:
            'Permission granted. macOS may need an app relaunch before the '
            'network name appears. The signal and channel details below are '
            'unaffected.',
        onGrant: null,
        onOpenSettings: null,
      );
    }

    if (nameMissing) {
      return _LocationCard(
        message:
            'The network name (SSID and BSSID) needs Location Services for this '
            'app. macOS requires it to read the name. Signal, rate, and channel '
            'details already work without it.',
        onGrant: _macLoading ? null : _grantLocation,
        onOpenSettings: _openLocationSettings,
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
  ConnectedAp? _nativeIdentityAp() {
    final WifiSecurityInfo? sec = _iosSecurity;
    if (sec == null || !sec.available) return null;
    return _enrichIos(const ConnectedAp(securityAvailable: true));
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
          onStart: _startLive,
          onStop: _stopLive,
          onSetUp: _openInstallSheet,
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
      _signalCard(info),
      const SizedBox(height: AppSpacing.sm),
      _rateCard(info, platformLabel),
      const SizedBox(height: AppSpacing.sm),
      _channelCard(info, platformLabel),
      const SizedBox(height: AppSpacing.sm),
      _radioCard(info),
      const SizedBox(height: AppSpacing.sm),
      _statusCard(info),
    ];
  }

  Widget _networkCard(ConnectedAp info) => _Card(
    title: 'Network',
    child: Column(
      children: [
        _MetricRow(label: 'SSID', value: info.ssid),
        _MetricRow(label: 'BSSID', value: info.bssid, mono: true),
        // AP vendor (manufacturer) resolved offline from the BSSID's IEEE OUI.
        // This is the AP MANUFACTURER, not the configured AP name (which is not
        // readable on iOS/macOS), the note says so.
        _MetricRow(
          label: 'AP vendor',
          value: _apVendorValue(info.bssid),
          note: _apVendorNote(info.bssid),
        ),
      ],
    ),
  );

  /// The AP-vendor row value: the manufacturer resolved from the BSSID's OUI,
  /// or null (→ "Unavailable") when the BSSID is absent, the table has not
  /// loaded, or the BSSID is locally-administered (no IEEE vendor).
  String? _apVendorValue(String? bssid) => _apVendorLabel(bssid);

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
      return 'BSSID is locally administered, no registered vendor';
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

    // Honest note: the coarse-iOS caveat, or the per-platform unavailable reason.
    String? note;
    if (!info.securityAvailable) {
      note = 'Not exposed by $platformLabel';
    } else if (security == null) {
      // Available platform, no value this reading. On iOS surface the precise
      // native reason (permission / no network) when we have one.
      final WifiSecurityInfo? sec = isIos ? _iosSecurity : null;
      note = (sec != null && !sec.available && sec.reason != null)
          ? sec.reason
          : 'Not in this reading';
    } else if (security.isPersonalCoarse || security.isEnterpriseCoarse) {
      note = 'iOS reports only Open / Personal / Enterprise. It cannot '
          'distinguish WPA2 from WPA3';
    }

    // iOS-only: when the native read is blocked by Location, offer the grant /
    // settings affordance (same shape as the macOS Location card).
    final bool iosNeedsLocation = isIos &&
        _iosSecurity != null &&
        !_iosSecurity!.available &&
        !_iosSecurity!.locationAuthorized;

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
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                Semantics(
                  button: true,
                  label: 'Grant Location permission to read Wi-Fi security',
                  child: FilledButton(
                    onPressed: _grantIosSecurityLocation,
                    child: const Text('Grant Location'),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Open Location settings',
                  child: OutlinedButton(
                    onPressed: _openIosSecuritySettings,
                    child: const Text('Open Settings'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _signalCard(ConnectedAp info) => _Card(
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
        ),
        _MetricRow(
          label: 'SNR',
          value: info.snrDb?.toString(),
          unit: 'dB',
          mono: true,
          derived: info.snrDerived,
        ),
      ],
    ),
  );

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
          // Say WHY precisely: a permanent platform limit (macOS never exposes
          // Rx) vs a per-sample miss (iOS can, but this reading lacked it).
          note: !info.rxRateAvailable
              ? 'Not exposed by $platformLabel'
              : (info.rxRateMbps == null ? 'Not in this reading' : null),
        ),
      ],
    ),
  );

  Widget _channelCard(ConnectedAp info, String platformLabel) {
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
            value: info.channelWidthMhz?.toString(),
            unit: 'MHz',
            mono: true,
            note: info.channelWidthAvailable
                ? null
                : 'Not reported by $platformLabel',
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
        _MetricRow(label: 'Country', value: info.countryCode),
        _MetricRow(label: 'Interface', value: info.interfaceName, mono: true),
        _MetricRow(
          label: 'Hardware Address',
          value: info.hardwareAddress,
          mono: true,
        ),
        // Derived MAC type from the locally-administered bit. When the MAC is
        // unreadable (iOS blocks app reads of the device Wi-Fi MAC), the value
        // is "Unavailable" and the honest reason rides in the note rather than
        // a meaningless computed flag (GL-005).
        _MetricRow(
          label: 'MAC type',
          value: _macTypeValue(info.hardwareAddress),
          note: _macTypeNote(info.hardwareAddress),
        ),
      ],
    ),
  );

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

  /// The honesty note for an unreadable MAC (iOS), or null when the MAC parsed.
  static String? _macTypeNote(String? mac) {
    return MacRandomizationClassifier.classify(mac) ==
            MacRandomization.unreadable
        ? "Apple does not expose this device's Wi-Fi MAC to apps"
        : null;
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


// ---- macOS location card ----

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.message,
    required this.onGrant,
    required this.onOpenSettings,
  });

  final String message;

  /// When null, the card is informational (post-grant) and hides the Grant
  /// button to avoid an endless re-tap loop.
  final VoidCallback? onGrant;

  /// Deep-links to System Settings → Privacy & Security → Location Services.
  /// When null (the post-grant informational state) the settings affordance and
  /// the numbered steps are hidden.
  final VoidCallback? onOpenSettings;

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
          // The Grant button tries the system prompt (still helps first-time
          // users). The Open Location Settings button deep-links to the exact
          // pane for the reliable manual path. Both are shown side by side and
          // wrap on a narrow card.
          if (onGrant != null || onOpenSettings != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                if (onGrant != null)
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
                    label: 'Open macOS Location Services settings',
                    child: OutlinedButton(
                      onPressed: onOpenSettings,
                      child: const Text('Open Location Settings'),
                    ),
                  ),
              ],
            ),
          ],
          if (onOpenSettings != null) ...[
            const SizedBox(height: AppSpacing.sm),
            const _LocationSteps(),
          ],
        ],
      ),
    );
  }
}

/// Short numbered steps for enabling Location Services manually on macOS. Shown
/// under the Location card's buttons. Each step is plain text; the whole block
/// reads as one list to a screen reader.
class _LocationSteps extends StatelessWidget {
  const _LocationSteps();

  static const List<String> _steps = <String>[
    'Open Location Settings (button above).',
    'Turn on WLAN Pros Toolbox.',
    'Come back and tap Refresh.',
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? style = text.bodySmall?.copyWith(
      color: colors.textTertiary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < _steps.length; i++)
          Padding(
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : AppSpacing.xxs,
            ),
            child: Text('${i + 1}. ${_steps[i]}', style: style),
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
    required this.enrich,
    required this.metricCardsBuilder,
    required this.nativeIdentity,
    required this.nativeIdentityCardsBuilder,
  });

  final WifiMonitorController controller;
  final WifiTimeSeries series;
  final double edge;
  final bool triggerError;
  final VoidCallback onStart;
  final VoidCallback onStop;

  /// Opens the one-time companion-Shortcut install sheet. Wired to both the
  /// first-run setup prompt and the post-failure setup card.
  final VoidCallback onSetUp;

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
                  _MonitorControlBar(
                    streaming: controller.isStreaming,
                    lastUpdated: controller.lastUpdated,
                    onStart: onStart,
                    onStop: onStop,
                  ),
                  if (triggerError) ...[
                    const SizedBox(height: AppSpacing.sm),
                    // A failed Start now leads with the actionable setup card —
                    // the honest "could not start" message PLUS the one-time
                    // "Set up live Wi-Fi" button — instead of a dead-end error.
                    LiveSetupCard.error(
                      label: 'Set up live Wi-Fi (one-time)',
                      onSetUp: onSetUp,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  if (!controller.isStreaming && series.isEmpty) ...<Widget>[
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
                      onEnable: nativeIdentity != null ? onStart : onSetUp,
                      enableLabel: nativeIdentity != null
                          ? 'Start live readings'
                          : 'Enable live Wi-Fi',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const _LiveStartHint(),
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
                      !triggerError &&
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
/// running.
class _LiveStartHint extends StatelessWidget {
  const _LiveStartHint();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Text(
        'Tap Start to begin live readings. The companion Shortcut sends a sample '
        'each cycle; each one charts here and the signal dimensions are graded as '
        'they arrive. Stop freezes the last values on screen.',
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
          // rxRateAvailable false) from a per-sample miss (iOS can, but this
          // reading lacked it).
          unavailableNote: latest == null
              ? null
              : !rxAvail
                  ? 'Not exposed by $platformLabel'
                  : (rx == null ? 'Not in this reading' : null),
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


/// iOS Start/Stop control + live indicator + last-updated timestamp.
class _MonitorControlBar extends StatelessWidget {
  const _MonitorControlBar({
    required this.streaming,
    required this.lastUpdated,
    required this.onStart,
    required this.onStop,
  });

  final bool streaming;
  final DateTime? lastUpdated;
  final VoidCallback onStart;
  final VoidCallback onStop;

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
          final Widget action = _ActionButton(
            streaming: streaming,
            onStart: onStart,
            onStop: onStop,
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                status,
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerLeft, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: AppSpacing.xs),
              action,
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.streaming,
    required this.onStart,
    required this.onStop,
  });

  final bool streaming;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return streaming
        ? Semantics(
            button: true,
            label: 'Stop live monitoring',
            child: OutlinedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          )
        : Semantics(
            button: true,
            label: 'Start live monitoring',
            child: FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start'),
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
