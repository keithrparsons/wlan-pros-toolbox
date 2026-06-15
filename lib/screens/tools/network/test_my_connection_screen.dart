// Test My Connection — the ONE merged connection tool (Wave 4, 2026-06-04).
//
// Progressive disclosure: it leads with the plain consumer answer (is this my
// Wi-Fi or my internet?), tucks the full pro "Wi-Fi vs Internet" depth one tap
// away, and runs a live "Wi-Fi signal" sparkline card so the tool doubles as a
// walk-around instrument. It replaces BOTH former screens — the consumer
// `test-my-connection` and the pro `wifi-vs-internet` — so nothing the pro tool
// showed is lost; it moves into the expandable technical section.
//
// REUSE (zero new measurement / verdict / sampling code):
//   * the connected-AP link read — the SAME per-platform path wifi-info uses
//     (MacWifiInfoAdapter on macOS / WiFiDetailsBridge on iOS);
//   * a net_quality FULL run via the QualityClient seam;
//   * the duplicated engine glue, now in ONE shared [ConnectionCheck] service;
//   * [ConsumerVerdictMapper] as the consumer "brain" (untouched);
//   * the live RF feed + sparklines via the shared [WifiSignalSampler] (the same
//     MacWifiInfoAdapter poll / WifiMonitorController stream wifi-info ships),
//     windowed to 30s for this tool; rendered with the shared [Sparkline].
//
// HONESTY (GL-005 / GL-008): a Wi-Fi link the platform cannot read (wired, or
// iOS without the companion Shortcut) lands on the engine's honest internet-only
// path — Outcome D — with a soft optional Shortcut offer on iOS only. Any datum
// the platform never exposes (macOS public CoreWLAN never reports Rx rate)
// renders "Unavailable" on screen AND in the copy text, never fabricated.
//
// LAYOUT: SafeArea + centered ConstrainedBox(maxWidth 560) + scroll; surface1
// cards with a §8.1 hairline border; overflow-safe at 320px. Per-tool help is a
// bottom ToolHelpFooter (§8.16.1); copy stays the trailing AppBar action (§8.16).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:net_quality/net_quality.dart';

import '../../../services/network/connected_ap.dart';
import '../../../services/network/connection_check.dart';
import '../../../services/network/consumer_verdict.dart';
import '../../../services/network/dns_probe_service.dart';
import '../../../services/network/ip_geo_service.dart';
import '../../../services/network/network_details_service.dart';
import '../../../services/network/live_onboarding_service.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/wifi_details_bridge.dart';
import '../../../services/network/wifi_grading.dart';
import '../../../services/network/wifi_info_adapter.dart';
import '../../../services/network/wifi_security.dart';
import '../../../services/network/wifi_security_service.dart';
import '../../../services/network/wifi_signal_sampler.dart';
import '../../../services/network/wifi_time_series.dart';
import '../../../services/network/wifi_vs_internet.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/packet_flow_progress.dart';
import '../../../widgets/sparkline.dart';
import '../../../widgets/tool_help_footer.dart';
import 'cloud_apps_panel.dart';
import 'install_shortcut_sheet.dart';
import 'network_unavailable_view.dart';

/// The footnote method-disclosure, VERBATIM from the pro screen's spec. Kept as
/// a named constant so the test asserts the exact string and the technical
/// section renders it unchanged after the merge.
const String kWifiVsInternetFootnote =
    '* Usable Wi-Fi capacity is estimated at 55% of the average negotiated '
    'Tx/Rx data rate (real-world Wi-Fi throughput runs about 50 to 60 percent '
    'of the PHY rate). Internet throughput is the average of the measured '
    'download and upload speeds. The verdict compares the two: internet within '
    '70% of usable Wi-Fi capacity points to the Wi-Fi link as the limiter; '
    'below 40% points upstream to the internet. RSSI and SNR are shown as '
    'supporting context; the negotiated data rate drives the verdict.';

/// The merged "is it my Wi-Fi or my internet?" screen.
class TestMyConnectionScreen extends StatefulWidget {
  const TestMyConnectionScreen({
    super.key,
    this.sourceOverride,
    this.macAdapter,
    this.iosBridge,
    this.securityService,
    this.qualityClient,
    this.nowOverride,
    this.autoStart = false,
    this.startExpanded = false,
    this.sampler,
    this.enableLiveSampling = true,
    this.onboardingService,
    this.cloudAppsProbe,
    this.enableCloudApps,
    this.ipGeoService,
    this.dnsProbeService,
    this.networkDetailsService,
  });

  /// When true, the check runs automatically on first mount instead of waiting
  /// for the user to tap "Check My Connection". Used by the home consumer hero
  /// card so its one tap goes straight into the test.
  final bool autoStart;

  /// Retained no-op since v1.1 (2026-06-05). The "See the details" disclosure was
  /// removed and the full technical detail is now ALWAYS rendered, so there is no
  /// collapsed state to pre-expand. The old `/tools/wifi-vs-internet` deep link
  /// still passes `startExpanded: true`; it now lands on the same always-detailed
  /// view. Kept so existing call sites compile unchanged.
  final bool startExpanded;

  /// Forces a specific Wi-Fi data source (tests). Defaults to the host platform
  /// via [WifiInfoSourceResolver].
  final WifiInfoSource? sourceOverride;

  /// Injectable macOS CoreWLAN adapter (tests). Defaults to the real adapter.
  final WifiInfoAdapter? macAdapter;

  /// Injectable iOS Shortcuts bridge (tests + the optional install sheet).
  final WiFiDetailsBridge? iosBridge;

  /// Injectable iOS NEHotspotNetwork security/BSSID reader (tests pass a fake;
  /// production uses the real [WifiSecurityService]). iOS-only enrichment: the RF
  /// metrics arrive through the Shortcut bridge, but the connected network's
  /// security type and BSSID are app-readable natively via NEHotspotNetwork
  /// (Access Wi-Fi Information entitlement + Location), so they can populate even
  /// before — or without — a Shortcut RF capture. Off iOS the service resolves to
  /// an honest unavailable result and is never consulted.
  final WifiSecurityService? securityService;

  /// Injectable net_quality backend (tests use a [MockQualityClient]).
  final QualityClient? qualityClient;

  /// Injectable clock for the "Tested:" timestamp (tests).
  final DateTime Function()? nowOverride;

  /// Injectable live sampler (tests). Defaults to a real [WifiSignalSampler] on
  /// the resolved platform.
  final WifiSignalSampler? sampler;

  /// When false, the live sampler is never started (tests that do not exercise
  /// the live card disable it so no poll timer ticks). Production leaves it on.
  final bool enableLiveSampling;

  /// Injectable first-run onboarding gate (tests). Defaults to the real
  /// shared_preferences-backed service. iOS-only — the front door must lead the
  /// one-time "enable live Wi-Fi" setup so a user can never run the test first
  /// and never be told about the companion Shortcut.
  final LiveOnboardingService? onboardingService;

  /// Injectable reachability probe for the bottom Cloud Apps panel (tests pass a
  /// fake so no real socket is opened). Defaults to the real probe in production.
  final ReachabilityProbe? cloudAppsProbe;

  /// Whether to mount the bottom Cloud Apps panel. Null (production default)
  /// follows [enableLiveSampling], so the same flag the render/screenshot tests
  /// already set to silence the live-poll timer ALSO skips the cloud panel's
  /// real reachability socket — no per-test churn. A test exercising the panel
  /// passes an explicit true plus a fake [cloudAppsProbe].
  final bool? enableCloudApps;

  /// Injectable IP-info service (tests pass a fake; production uses the real
  /// keyless HTTPS [IpGeoService] — ipinfo.io primary, geojs.io fallback). Used
  /// to enrich the "Copy these details" payload with the public IP + ISP/org +
  /// ASN so a help desk has the ISP context (Keith ISP-ask + #6). Fetched once
  /// per run; fails open — if offline or both providers error, the ISP section
  /// is omitted cleanly and never blocks the check (GL-005, GL-008).
  final IpGeoService? ipGeoService;

  /// Injectable DNS resolution-time probe (tests pass a fake; production uses
  /// the real [DnsProbeService], which times `InternetAddress.lookup` through
  /// the device resolver — Keith #3). Runs once per check, in parallel with the
  /// measurement; a failed lookup marks DNS unavailable rather than blocking.
  final DnsProbeService? dnsProbeService;

  /// Injectable local-addressing reader (tests pass a fake; production uses the
  /// real [NetworkDetailsService] over `network_info_plus` + `NetworkInterface`
  /// — Keith #5). Reads local IP / subnet / gateway; DHCP server, DNS servers,
  /// and VLAN are honestly unavailable on these platforms (no sandbox-safe
  /// source) and the service reports them as such.
  final NetworkDetailsService? networkDetailsService;

  @override
  State<TestMyConnectionScreen> createState() => _TestMyConnectionScreenState();
}

class _TestMyConnectionScreenState extends State<TestMyConnectionScreen>
    with WidgetsBindingObserver {
  late final WifiInfoSource _source;
  WifiInfoAdapter? _macAdapter;
  WiFiDetailsBridge? _iosBridge;

  /// iOS-only: reads the connected network's security type + BSSID natively via
  /// NEHotspotNetwork. Null off the iOS source.
  WifiSecurityService? _securityService;

  /// iOS-only: the latest native NEHotspotNetwork read, folded onto the
  /// Shortcut-derived [ConnectedAp] so security + BSSID populate even when no RF
  /// has been captured yet. Null off iOS / before the first read.
  WifiSecurityInfo? _iosSecurity;

  LiveOnboardingService? _onboardingService;
  late final QualityClient _quality;

  /// Fires the unmissable first-run onboarding at most once per mount.
  bool _firstRunChecked = false;

  /// The shared live-RF sampler that feeds the "Wi-Fi signal" sparkline card.
  /// Continuous while the screen is open (macOS auto-polls; iOS streams via the
  /// companion Shortcut). Null on web / unsupported.
  WifiSignalSampler? _sampler;

  bool _running = false;
  String? _error;

  // Internet progress.
  QualityPhase _phase = QualityPhase.idle;
  double _fraction = 0;

  // Results, populated when the run completes.
  ConnectedAp? _ap;

  /// macOS only: whether Location Services is authorized for this app. Since
  /// macOS 14, CoreWLAN withholds the SSID and BSSID unless the app holds
  /// Location authorization — every other RF field still resolves. Read WITHOUT
  /// a prompt during a run (a consumer check must never pop a TCC prompt
  /// mid-test) so the SSID/BSSID empty state can explain itself ("grant Location
  /// access to show the network name") instead of a bare "Unavailable". Null
  /// before the first read / off macOS.
  bool? _macLocationAuthorized;

  QualityResult? _internet;
  ConsumerVerdict? _verdict;
  WifiVsInternetResult? _engine;
  DateTime? _testedAt;

  /// The ISP / public-IP lookup for the comprehensive copy payload (Keith
  /// ISP-ask + #6). Fetched async during a run; null until it lands (or stays
  /// null if it failed / is offline, in which case the ISP copy section is
  /// omitted cleanly — never blocks the check or fabricates a value).
  late final IpGeoService _ipGeo;
  IpGeoResult? _ispInfo;

  /// The DNS resolution-time probe and its latest result (Keith #3). Fetched
  /// async during a run; null until it lands or if it failed (unavailable).
  late final DnsProbeService _dnsProbe;
  DnsProbeResult? _dnsResult;

  /// The local-addressing reader and its latest snapshot (Keith #5). Fetched
  /// async during a run; null until it lands (or stays null if the read failed,
  /// in which case the Network section shows the honest unavailable fields).
  late final NetworkDetailsService _netDetailsService;
  NetworkDetails? _networkDetails;

  /// The latest cloud-apps reachability rows, lifted from the bottom panel so
  /// the copy payload can summarize them. Empty until the panel's probe lands.
  List<SiteReachability> _cloudResults = const <SiteReachability>[];

  StreamSubscription<QualityProgress>? _sub;

  /// True only on iOS (the companion-Shortcut source).
  bool get _isIos => _source == WifiInfoSource.iosShortcuts;

  /// Whether to run the REAL DNS-probe + local-addressing reads on a check.
  /// Production always does (live sampling on). Tests that disable live sampling
  /// and inject no fake skip them, so no real resolver / interface call leaks a
  /// pending Timer into the test clock; a test that injects a fake DNS probe or
  /// network-details reader flips this on to exercise those report sections.
  bool get _runRealNetworkProbes =>
      widget.enableLiveSampling ||
      widget.dnsProbeService != null ||
      widget.networkDetailsService != null;

  /// Plain platform word for the "Tested … on `<platform>`" fact (GL-005).
  String get _platformLabel {
    switch (_source) {
      case WifiInfoSource.macosCoreWlan:
        return 'macOS';
      case WifiInfoSource.androidWifiManager:
        return 'Android';
      case WifiInfoSource.iosShortcuts:
        return 'iOS';
      case WifiInfoSource.unsupported:
        return 'this device';
      case WifiInfoSource.web:
        return 'this browser';
    }
  }

  @override
  void initState() {
    super.initState();
    _ipGeo = widget.ipGeoService ?? IpGeoService();
    _dnsProbe = widget.dnsProbeService ?? DnsProbeService();
    _netDetailsService =
        widget.networkDetailsService ?? NetworkDetailsService();
    _source = widget.sourceOverride ?? WifiInfoSourceResolver.resolve();
    switch (_source) {
      case WifiInfoSource.macosCoreWlan:
        _macAdapter = widget.macAdapter ?? MacWifiInfoAdapter();
      case WifiInfoSource.androidWifiManager:
        _macAdapter = widget.macAdapter ?? AndroidWifiInfoAdapter();
      case WifiInfoSource.iosShortcuts:
        _iosBridge = widget.iosBridge ?? WiFiDetailsBridge();
        // Native NEHotspotNetwork enrichment: security type + BSSID are
        // app-readable on iOS WITHOUT the Shortcut, so we read them and fold them
        // onto the Shortcut-derived link. This is why the pro Wi-Fi Information
        // tool shows the security/BSSID immediately; Test My Connection now does
        // the same instead of always listing Security as "Unavailable".
        _securityService = widget.securityService ?? WifiSecurityService();
        // The front door is the FIRST live surface most users hit. The mandatory
        // one-time "enable live Wi-Fi" onboarding must lead from HERE so a user
        // can never run the comparison check first and only afterward discover
        // the companion Shortcut exists (the exact beta confusion — Pax
        // 2026-06-07). iOS-only; the gate is honest and one-time.
        _onboardingService =
            widget.onboardingService ?? LiveOnboardingService();
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        break;
    }
    _quality =
        widget.qualityClient ??
        OwnEngineQualityClient.forHost('one.one.one.one');

    // Live "Wi-Fi signal" sampler — the same per-platform feed wifi-info uses,
    // windowed to 30s for this tool (the sampler sets its own capacity; it does
    // not touch wifi-info's defaults). Only built where a live feed exists.
    if (widget.enableLiveSampling &&
        (_source == WifiInfoSource.macosCoreWlan ||
            _source == WifiInfoSource.androidWifiManager ||
            _source == WifiInfoSource.iosShortcuts)) {
      _sampler = widget.sampler ??
          WifiSignalSampler(
            source: _source,
            macAdapter: _macAdapter,
            iosBridge: _iosBridge,
          );
      WidgetsBinding.instance.addObserver(this);
      _sampler!.load();
      // AUTO-START THE LIVE CAPTURE (item #8).
      //
      // macOS sources its live feed from NATIVE polling (CoreWLAN snapshots on a
      // timer, no app switch), so it auto-starts cleanly on screen entry — the
      // sparklines begin filling as soon as the first sample lands, with no tap.
      // This holds whether the screen was reached by tapping "Check My
      // Connection" or via the home hero's auto-run argument.
      //
      // iOS sources its live feed from the Shortcuts bridge: start() fires the
      // companion "WLAN Pros Live" Shortcut, which SWITCHES to the Shortcuts app.
      // Auto-firing that on screen entry would bounce the user straight out of
      // the app — a jarring auto-bounce. So iOS keeps the single explicit Start
      // kickoff in the live card; we do not auto-fire the bridge. The comparison
      // test still auto-runs on the home-hero path; only the iOS RF stream waits
      // for the one deliberate tap (GL-008: build to the platform, no fabricated
      // auto-behavior that the bridge cannot honor).
      // macOS and Android both source the live feed from NATIVE polling (no app
      // switch), so they auto-start cleanly on screen entry. iOS waits for the
      // single deliberate Start tap (firing the Shortcut would bounce the user
      // out of the app).
      if (_source == WifiInfoSource.macosCoreWlan ||
          _source == WifiInfoSource.androidWifiManager) {
        _sampler!.start();
      }
    }

    // Unmissable first-run onboarding (iOS only): the first time ANY live tool
    // is opened — including this front door — and the companion Shortcut is not
    // demonstrably working, present the one-time "enable live Wi-Fi" setup sheet
    // before the user can run a check and hit a wall. Scheduled post-frame so the
    // sheet has a built context to mount into.
    if (_source == WifiInfoSource.iosShortcuts) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeShowFirstRunOnboarding();
      });
    }

    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run();
      });
    }
  }

  /// iOS first-run: fires the unmissable one-time "enable live Wi-Fi" sheet on
  /// the first open of the front door, gated by the SAME honest composite signal
  /// wifi-info uses — the app has NEVER received a Live payload AND the sheet has
  /// not been shown before. Marks the sheet seen the instant it is presented so
  /// it never nags again (the persisted flag plus the App Group hasEverReceived
  /// signal make this truly one-time across every live tool). No-op off the iOS
  /// source. Never throws.
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
    // second sheet, and so it stays one-time even if the user dismisses it.
    await svc.markOnboardingSeen();
    if (!mounted) return;
    await _openShortcutSheet();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final WifiSignalSampler? sampler = _sampler;
    if (sampler == null) return;
    if (state == AppLifecycleState.resumed) {
      sampler.load();
      sampler.resumeMac();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      sampler.pauseMac();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_sampler != null) {
      WidgetsBinding.instance.removeObserver(this);
      // Only dispose a sampler we created; an injected one is the test's.
      if (widget.sampler == null) _sampler!.dispose();
    }
    super.dispose();
  }

  /// Reads the connected-AP link via the SAME per-platform path as wifi-info.
  /// Returns null when the link cannot be read — the engine then takes its
  /// honest wifiUnknown path (Outcome D). Never throws to the caller.
  Future<ConnectedAp?> _readLink() async {
    try {
      switch (_source) {
        case WifiInfoSource.androidWifiManager:
          final WifiInfoAdapter? adapter = _macAdapter;
          if (adapter == null) return null;
          // ANDROID LOCATION GATE (FIX 1, 2026-06-08): unlike macOS, Android
          // redacts not just the SSID/BSSID but the WHOLE WifiManager snapshot
          // (frequency, link rate, scan results) until ACCESS_FINE_LOCATION is
          // granted at runtime — so a user who opened Test My Connection FIRST
          // saw no Wi-Fi data at all and had to detour to Wi-Fi Information to
          // answer the prompt (Keith, Galaxy S24). Reuse the SAME permission
          // helper Wi-Fi Information uses: if Location is not already authorized,
          // surface the standard Android runtime dialog HERE so the data flows
          // without the detour. The Android runtime dialog is the platform's
          // normal prompt — it does NOT background the app — so prompting
          // mid-flow is correct on Android, distinct from macOS where the TCC
          // prompt is unreliable in notarized builds and is NOT popped here (see
          // the macOS branch). We never block on the choice: whatever the user
          // picks, we then read the snapshot and let the rate-derived verdict
          // proceed (only the NAME needs Location, never the verdict).
          if (adapter.gatesNameBehindPermission &&
              !await adapter.currentNameAuthorization()) {
            await adapter.requestNamePermission();
            if (!mounted) return null;
          }
          return await adapter.fetch().timeout(
            const Duration(seconds: 5),
            onTimeout: () =>
                throw TimeoutException('Wi-Fi link read timed out'),
          );
        case WifiInfoSource.macosCoreWlan:
          final WifiInfoAdapter? adapter = _macAdapter;
          if (adapter == null) return null;
          // A consumer check must never pop a Location prompt mid-test on macOS
          // (the link RATE — hence the verdict — resolves WITHOUT Location; only
          // the NAME needs it, and the macOS TCC prompt is unreliable in
          // notarized builds). Read the CURRENT authorization WITHOUT a prompt so
          // the SSID/BSSID empty state can explain itself ("grant Location
          // access") rather than read as a bare glitch. Then read the snapshot
          // directly, bounded so a stalled channel can never hang the check.
          _macLocationAuthorized = await adapter.currentNameAuthorization();
          return await adapter.fetch().timeout(
            const Duration(seconds: 5),
            onTimeout: () =>
                throw TimeoutException('Wi-Fi link read timed out'),
          );
        case WifiInfoSource.iosShortcuts:
          final WiFiDetailsBridge? bridge = _iosBridge;
          if (bridge == null) return null;
          // Read the native security/BSSID first (no Shortcut bounce) so the
          // enrichment below has it. Never blocks the verdict — a failed read
          // just leaves the enrichment empty.
          await _fetchIosSecurity();
          // The RF metrics (RSSI / noise / SNR / channel / width / band / PHY /
          // rate) come ONLY from the companion Shortcut's last harvest, read here
          // from the App Group. readLatest() returns null when the Shortcut has
          // never delivered a payload — in that case the RF block is genuinely
          // not captured, and the screen shows a "Tap to capture Wi-Fi details"
          // affordance rather than a silent grid of "Unavailable" (see
          // [_iosRfCaptured] + the capture card in build()).
          final details = await bridge.readLatest();
          final ConnectedAp? rf =
              details == null ? null : ConnectedAp.fromWifiDetails(details);
          // Fold the native NEHotspotNetwork security + BSSID onto whatever the
          // Shortcut gave us. When no RF was captured, this still yields a
          // minimal link carrying just the native identity (security/BSSID), so
          // those rows populate without a Shortcut bounce.
          return _enrichIosSecurity(rf);
        case WifiInfoSource.unsupported:
        case WifiInfoSource.web:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// iOS: reads the native NEHotspotNetwork security token + BSSID once at the
  /// start of a run so the enrichment is available when the link read resolves.
  /// No-op off the iOS source. Never throws (the service returns an honest
  /// unavailable result on any failure / permission gap).
  ///
  /// Gated so the real native channel is only touched in production (live
  /// sampling on) or when a test explicitly injects a fake [securityService].
  /// Unlike the DNS / addressing reads, this is NOT keyed off `_runRealNetwork
  /// Probes`: the NEHotspotNetwork channel is unrelated to DNS/addressing, so a
  /// copy test that injects DNS/addressing fakes must not also light up the real
  /// security channel and leak a pending async into the test clock. A test that
  /// wants the enrichment injects a fake [securityService], which flips this on.
  Future<void> _fetchIosSecurity() async {
    if (!widget.enableLiveSampling && widget.securityService == null) return;
    final WifiSecurityService? svc = _securityService;
    if (svc == null) return;
    final WifiSecurityInfo info = await svc.fetch();
    if (!mounted) return;
    _iosSecurity = info;
  }

  /// Folds the native iOS security read (security token + BSSID) onto a
  /// Shortcut-derived [ConnectedAp]. Mirrors the pro Wi-Fi Information tool's
  /// `_enrichIos`: the Shortcut path does not carry the security type, and the
  /// BSSID may be absent there too, so both are enriched from NEHotspotNetwork
  /// when available. When [rf] is null (no RF captured) but native security IS
  /// available, returns a minimal link carrying just the native identity so the
  /// Security/BSSID rows populate without a Shortcut bounce. Returns [rf]
  /// unchanged off iOS or when no native read landed.
  ConnectedAp? _enrichIosSecurity(ConnectedAp? rf) {
    final WifiSecurityInfo? sec = _iosSecurity;
    if (sec == null || !sec.available) return rf;
    final WifiSecurity? security =
        WifiSecurityClassifier.classify(sec.securityToken);
    if (rf == null) {
      // No RF captured yet — surface a minimal link from the native read alone
      // so security + BSSID + SSID are not falsely "Unavailable".
      return ConnectedAp(
        ssid: sec.ssid,
        bssid: sec.bssid,
        securityType: security,
        securityAvailable: true,
        rxRateAvailable: true,
        channelWidthAvailable: false,
      );
    }
    final ConnectedAp withSec = rf.withSecurity(security);
    // Prefer a BSSID the Shortcut already supplied; fall back to the native one.
    if (withSec.bssid == null && sec.bssid != null) {
      return ConnectedAp(
        ssid: withSec.ssid ?? sec.ssid,
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

  /// iOS: whether the companion Shortcut has captured the RF metrics for the
  /// current result. The native NEHotspotNetwork read supplies only SSID / BSSID
  /// / security; the rich RF block (RSSI / noise / SNR / channel / width / band /
  /// PHY / rate) comes ONLY from the Shortcut harvest. We treat "RF captured" as
  /// "at least one RF metric is present", so a link that carries only the native
  /// identity reads as NOT captured and the screen shows the capture affordance
  /// rather than a grid of "Unavailable". Always true off iOS (those platforms
  /// read RF natively, with no capture step).
  bool get _iosRfCaptured {
    if (!_isIos) return true;
    final ConnectedAp? ap = _ap;
    if (ap == null) return false;
    return ap.rssiDbm != null ||
        ap.noiseDbm != null ||
        ap.channel != null ||
        ap.txRateMbps != null ||
        ap.rxRateMbps != null ||
        ap.standard != null;
  }

  /// Runs the internet measurement and the link read from one tap, then computes
  /// the engine verdict (shared [ConnectionCheck]) and translates it for the
  /// consumer ([ConsumerVerdictMapper]).
  void _run() {
    setState(() {
      _error = null;
      _running = true;
      _phase = QualityPhase.idle;
      _fraction = 0;
      _ap = null;
      _macLocationAuthorized = null;
      _internet = null;
      _verdict = null;
      _engine = null;
      _testedAt = null;
      _ispInfo = null;
      _dnsResult = null;
      _networkDetails = null;
    });

    final Future<ConnectedAp?> linkFuture = _readLink();

    // ISP / public-IP lookup for the copy payload (Keith ISP-ask + #6). Runs in
    // parallel with the measurement and is purely additive — it never gates the
    // verdict, never blocks the run, and fails open (a thrown lookup is caught
    // and the ISP copy section is simply omitted; IpGeoService itself already
    // never throws and returns an honest failure result). HTTPS + keyless
    // (GL-008); never a fabricated address (GL-005).
    _fetchIspInfo();

    // DNS resolution-time probe (Keith #3) + local-addressing read (Keith #5).
    // Both run in parallel with the measurement, are purely additive (never gate
    // the verdict, never block the run), and fail open — a failed DNS lookup
    // marks DNS unavailable and a failed addressing read leaves the Network
    // fields on their honest unavailable state. Cross-platform + sandbox-safe:
    // InternetAddress.lookup and network_info_plus are native in-process calls,
    // not CLI spawns (GL-008).
    //
    // Real network I/O is gated by [_runRealNetworkProbes]: production always
    // runs them; render/copy tests that disable live sampling AND inject no fake
    // skip them so no real resolver/interface call (and its timeout Timer) leaks
    // into the test clock — the SAME seam pattern the cloud panel uses. A test
    // exercising these sections injects a fake service, which flips the gate on.
    if (_runRealNetworkProbes) {
      _fetchDnsProbe();
      _fetchNetworkDetails();
    }

    _sub = _quality.measure().listen(
      (QualityProgress p) {
        if (!mounted) return;
        setState(() {
          _phase = p.phase;
          _fraction = p.fraction;
        });
      },
      onDone: () async {
        final QualityResult? internet = _quality.lastResult;
        final ConnectedAp? ap = await linkFuture.timeout(
          const Duration(seconds: 8),
          onTimeout: () => null,
        );
        if (!mounted) return;
        final WifiVsInternetResult engine = ConnectionCheck.compute(
          ap,
          internet,
        );
        setState(() {
          _ap = ap;
          _internet = internet;
          _engine = engine;
          _verdict = ConsumerVerdictMapper.map(
            engine,
            internetHealthy:
                ConnectionCheck.internetHealth(internet) ==
                InternetHealth.good,
          );
          _testedAt = (widget.nowOverride ?? DateTime.now)();
          _running = false;
        });
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Connection check complete',
          TextDirection.ltr,
        );
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _error =
              "Something went wrong and we couldn't finish the check. "
              'Please try again.';
        });
      },
    );
  }

  /// Fetches the public IP + ISP/org + ASN for the copy payload. Never throws
  /// (IpGeoService returns an honest failure result, and we catch defensively),
  /// never blocks the run, and stores only a real, located/successful result —
  /// a failure or offline lookup leaves [_ispInfo] null so the ISP copy section
  /// is omitted cleanly (Keith ISP-ask + #6; GL-005 / GL-008).
  Future<void> _fetchIspInfo() async {
    try {
      final IpGeoResult result = await _ipGeo
          .lookup(rawQuery: '')
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      // Only keep a non-error result; a failure stays null (omitted from copy).
      if (!result.isError) {
        setState(() => _ispInfo = result);
      }
    } catch (_) {
      // Fail open — offline / timeout / transport error → no ISP section.
    }
  }

  /// Measures DNS resolution time for the report (Keith #3). Never throws
  /// (DnsProbeService swallows lookup errors and returns an honest unavailable
  /// result, and we catch defensively), never blocks the run. Stores whatever
  /// the probe returns — a successful timing OR the honest unavailable state —
  /// so the DNS row is always truthful (GL-005).
  Future<void> _fetchDnsProbe() async {
    try {
      final DnsProbeResult result = await _dnsProbe.measure();
      if (!mounted) return;
      setState(() => _dnsResult = result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _dnsResult = DnsProbeResult.unavailable());
    }
  }

  /// Reads the device's local addressing for the report (Keith #5). Never
  /// throws (NetworkDetailsService guards each sub-read and never throws, and we
  /// catch defensively), never blocks the run. A failed read leaves
  /// [_networkDetails] null so the Network section renders its honest
  /// unavailable fields rather than a fabricated address (GL-005 / GL-008).
  Future<void> _fetchNetworkDetails() async {
    try {
      final NetworkDetails details = await _netDetailsService
          .read()
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => _networkDetails = details);
    } catch (_) {
      // Fail open — leave _networkDetails null; the Network section then shows
      // the honest "Not available" fields.
    }
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // §8.5 `--text-h2` (28px) screen title. At every real iPhone width
        // (≥375pt) the full "Test My Connection" string renders at full size
        // beside the single §8.16 copy action (verified 375/430/768 — no
        // ellipsis). `BoxFit.scaleDown` is a no-op there; it engages ONLY below
        // 375pt (e.g. a 320px stress width), shrinking the title just enough to
        // keep the WHOLE name on one line rather than ellipsizing to
        // "Test My C…". The title never truncates and never wraps.
        title: const Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('Test My Connection'),
          ),
        ),
        toolbarHeight: 64,
        // §8.16: copy is the SINGLE trailing AppBar action. Help is the bottom
        // footer (§8.16.1), not an AppBar glyph.
        //
        // Vera title-truncation finding (2026-06-14): a SECOND trailing action
        // here — the old labeled "Run again" `TextButton.icon` — widened the
        // trailing block to ~198px and ellipsized the 28px (§8.5 `--text-h2`,
        // ~252px) "Test My Connection" title to "Test My C…" at iPhone widths
        // (320–430px). Even an icon-only second action still overran 320/375px
        // (252px title + 16px lead + two ≥48dp hit regions does not fit). §8.16
        // pins the copy action to the AppBar, so the re-run is the action that
        // moves: the unmistakable LABELED "Run again" control now lives on an
        // EXISTING line in the result body — the verdict-hero sentence row
        // (Keith explicitly OK'd "on the same line as something else", no new
        // vertical space). It carries `Icons.refresh`, the 'Run the test again'
        // Semantics label, and the §8.3 44pt target (see [_HeroRunAgainButton]).
        // With copy alone the full title clears at every iPhone width.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    // The internet measurement needs dart:io sockets the browser does not have;
    // route web (and any no-socket platform) to the shared fallback.
    if (!NetworkSupport.activeNetworkSupported) {
      return NetworkUnavailableView(
        toolName: 'Test My Connection',
        reason:
            NetworkSupport.unavailableReason ?? NetworkUnavailableReason.web,
      );
    }
    if (_source == WifiInfoSource.web) {
      return const NetworkUnavailableView(
        toolName: 'Test My Connection',
        reason: NetworkUnavailableReason.web,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        final ConsumerVerdict? verdict = _verdict;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.md,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (verdict == null && !_running) _introCard(context),
                  if (verdict == null) _actionCard(context),
                  if (_running) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _progressCard(context),
                  ],
                  if (verdict != null) ...[
                    // (A) VERDICT HERO — the H1/36px plain-language sentence +
                    //     the two axis status chips side by side (§2.A / §2.A2).
                    _HeroVerdict(
                      verdict: verdict,
                      heroSentence: _heroSentence(verdict),
                      // The unmistakable LABELED re-run lives HERE on the
                      // hero-sentence row (Keith: same line as something else,
                      // no new vertical space). Disabled while a run is in
                      // flight so a double-tap can't queue a second check.
                      onRunAgain: _running ? null : _run,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // VERDICT LINE — a plain, state-driven sentence that names the
                    // limiter, plus the direct % comparison answer. Both ALWAYS
                    // shown, prominent (no disclosure). The v1.1 "show more" pass
                    // walked back the over-simplified reshape (Keith, 2026-06-05).
                    _VerdictLine(
                      verdict: _verdictLine(verdict),
                      comparison: _comparisonLine(verdict),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // DETAILS — the Mbps / bars / live signal / pro readout, now
                    // ALWAYS rendered (the "See the details" disclosure was
                    // removed in v1.1 to return to showing more information).
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // Core comparison — usable Wi-Fi vs internet bars.
                        _ComparisonCard(result: _engine!),
                        const SizedBox(height: AppSpacing.sm),
                        // Live "Wi-Fi signal" sparkline card.
                        if (_sampler != null) ...[
                          _LiveSignalCard(sampler: _sampler!),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        // "What to tell support".
                        _HelpDeskCard(
                          facts: _facts(),
                          onCopy: _copyDetails,
                          copied: _detailsCopied,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        // NETWORK details (Keith #5): local IP / subnet / gateway
                        // (obtainable, sandbox-safe), plus the honest unavailable
                        // DHCP server / DNS server(s) / VLAN rows. Compact, grouped
                        // in one card so it adds little vertical space. Carries the
                        // measured DNS resolution time (Keith #3) as its first row.
                        _NetworkDetailsCard(
                          details: _networkDetails,
                          dns: _dnsResult,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        // The absorbed pro "Wi-Fi vs Internet" readout.
                        _TechnicalSection(
                          ap: _ap,
                          internet: _internet,
                          result: _engine!,
                          // iOS-only: when the companion Shortcut has not captured
                          // the RF metrics, the Wi-Fi link sub-card shows a "Tap to
                          // capture Wi-Fi details" affordance instead of a grid of
                          // "Unavailable", so the user knows it is a capture step,
                          // not a broken tool (GL-005 / GL-008).
                          needsWifiCapture: _isIos && !_iosRfCaptured,
                          onCaptureWifi: _isIos ? _openShortcutSheet : null,
                        ),
                      ],
                    ),
                    // iOS-only soft optional Shortcut offer on the D1 path only.
                    if (_isIos &&
                        verdict.outcome ==
                            ConsumerOutcome.couldntCheckWifi) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _ShortcutOfferCard(onOpen: _openShortcutSheet),
                    ],
                    // CLOUD APPS reachability panel (Feature 1, Felix 2026-06-13).
                    // Keith asked for the named-cloud-apps panel at the BOTTOM of
                    // this screen. It reuses the shared ReachabilityProbe over the
                    // recurated kCloudApps list and runs its own probe once the
                    // result content is shown — independent of the Wi-Fi/internet
                    // verdict above it.
                    if (widget.enableCloudApps ??
                        widget.enableLiveSampling) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      CloudAppsPanel(
                        probe: widget.cloudAppsProbe,
                        // Lift the reachability rows so the comprehensive copy
                        // payload can summarize them (Keith #6). Additive only —
                        // the panel still owns its own probe + scoped re-check.
                        onResults: (List<SiteReachability> rows) {
                          if (!mounted) return;
                          setState(() => _cloudResults = rows);
                        },
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    _poweredBy(context),
                  ],
                  ToolHelpFooter(toolId: 'test-my-connection'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- Idle ----

  Widget _introCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        "Not sure if it's your Wi-Fi or your internet? Tap below and find out "
        'in about a minute.',
        style: text.bodyLarge?.copyWith(color: colors.textSecondary),
      ),
    );
  }

  Widget _actionCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_error != null) ...[
          Container(
            decoration: BoxDecoration(
              color: colors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: colors.border,
                width: colors.isLight ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              _error!,
              style: text.bodyMedium?.copyWith(color: colors.statusDanger),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Semantics(
          button: true,
          enabled: !_running,
          label: _running
              ? 'Checking your connection'
              : 'Check my connection',
          child: FilledButton(
            onPressed: _running ? null : _run,
            child: Text(_running ? 'Checking…' : 'Check My Connection'),
          ),
        ),
      ],
    );
  }

  // ---- Running ----

  Widget _progressCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final int pct = (_fraction * 100).round();
    final String caption = _friendlyPhase(_phase);
    // PACKET-FLOW LOADING (2026-06-13, Keith-picked concept): the percentage bar
    // is replaced by an animated [You] → [AP] → [Internet] path whose nodes light
    // lime as each phase of the SAME live test completes (Wi-Fi link → gateway →
    // internet). It is a pure presentation layer over [_phase] / [_fraction] —
    // the data-gathering logic is untouched. Accessibility (the textual
    // phase + percentage, the live-region announcement, and the reduced-motion
    // fallback) lives inside [PacketFlowProgress].
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PacketFlowProgress(
            caption: caption,
            fraction: _fraction,
            stage: _packetFlowStage(_phase),
            semanticsLabelBuilder: () => '$caption, $pct percent complete',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Testing your Wi-Fi and your internet connection.',
            style: text.bodyMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          // Duration hint (Keith #9). HONEST figure (GL-005): the test is NOT a
          // fixed 10–15 s window. It runs three back-to-back ~10 s measurement
          // windows — download, then upload, then a loaded-responsiveness probe
          // — preceded by a sub-second latency burst. A typical healthy run is
          // ~25–35 s; a fast link finishes near the low end, a slow/stalled
          // endpoint near the high end. "About half a minute" is the truthful,
          // plain-language version of that range. See the timing constants in
          // own_engine_quality_client.dart + throughput_probe.maxDuration (10 s).
          Text(
            'This usually takes about half a minute.',
            style: text.bodyMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  /// Maps the live [QualityPhase] to how many hops of the packet-flow path have
  /// completed. The device ([PacketFlowNode.you]) lights the instant the test is
  /// underway; the AP/gateway hop lights once the latency round-trip is in
  /// (download/upload/responsiveness are running over a confirmed link); the
  /// internet node lights when the run completes. This is presentation-only — it
  /// reads the phase the engine already streams and adds no measurement.
  static PacketFlowStage _packetFlowStage(QualityPhase phase) {
    switch (phase) {
      case QualityPhase.idle:
        return PacketFlowStage.none;
      case QualityPhase.latency:
        // The first round-trip is in flight — [You] is lit, the dot travels to
        // the AP.
        return PacketFlowStage.you;
      case QualityPhase.download:
      case QualityPhase.upload:
      case QualityPhase.responsiveness:
        // Throughput is flowing over a confirmed link — [You] + [AP] lit, the
        // dot travels to the internet.
        return PacketFlowStage.ap;
      case QualityPhase.complete:
        return PacketFlowStage.all;
      case QualityPhase.failed:
        // Freeze the path where it was; the host surfaces the honest error card.
        return PacketFlowStage.ap;
    }
  }

  /// Friendly, jargon-free phase captions. The user never sees
  /// "latency / download / upload".
  static String _friendlyPhase(QualityPhase phase) {
    switch (phase) {
      case QualityPhase.idle:
        return 'Starting…';
      case QualityPhase.latency:
      case QualityPhase.download:
        return 'Testing your internet speed…';
      case QualityPhase.upload:
        return 'Checking your Wi-Fi…';
      case QualityPhase.responsiveness:
      case QualityPhase.complete:
        return 'Working out the answer…';
      case QualityPhase.failed:
        return 'Something went wrong…';
    }
  }

  // ---- v1.1 readability copy (§2–§4) ----
  //
  // Every string below is authored to Flesch-Kincaid grade ≤ 8.0 PER STRING
  // (§4). The hero sentence, the "what this means" line, the D1 number anchor,
  // and the self-help steps are all measured; the worst is 6.7. The D1 path is
  // the only one that surfaces a raw number — it carries a use-case ANCHOR (§3),
  // never a bare figure at the verdict level.

  /// (A) The plain-language VERDICT HERO sentence (§2.A), one per outcome. Short,
  /// active, second person, most-important-first — FK ≤ 8.0 each.
  ///
  /// SAME-TIER OVERRIDE (2026-06-07, Vera gate / Keith): the per-axis chips are
  /// now ABSOLUTE tiers (Strong / Moderate / Weak). When BOTH chips land on the
  /// SAME real tier (e.g. Moderate Wi-Fi + Moderate internet), naming a "slow
  /// part" or "limit" contradicts two equal chips for the non-technical reader.
  /// In that case word the hero by MARGIN instead — see [_sameTierHero]. The
  /// different-tier outcomes keep their existing "slow part / limit" wording.
  String _heroSentence(ConsumerVerdict verdict) {
    final String? sameTier = _sameTierHero(verdict);
    if (sameTier != null) return sameTier;

    switch (verdict.outcome) {
      case ConsumerOutcome.wifi:
        return 'Your Wi-Fi is the slow part.';
      case ConsumerOutcome.wifiLead:
        return 'Your Wi-Fi is mostly the slow part.';
      case ConsumerOutcome.internet:
        return 'Your internet is the slow part.';
      case ConsumerOutcome.bothFine:
        return 'Your Wi-Fi and internet both look fine.';
      case ConsumerOutcome.couldntCheckWifi:
        return 'We checked your internet, but not your Wi-Fi.';
      case ConsumerOutcome.couldntComplete:
        return 'We could not finish the check.';
    }
  }

  /// The same-tier hero sentence, or null when the two axes are NOT on the same
  /// real tier (the caller then falls through to the existing per-outcome wording).
  ///
  /// Fires only when [ConsumerVerdict.wifiStatus] equals
  /// [ConsumerVerdict.internetStatus] AND both are a real tier (Strong / Moderate
  /// / Weak — never [AxisStatus.unknown], so the couldn't-check rows are left
  /// alone). Margin reuses the SAME +/-10% band as [_comparisonLine]: within the
  /// band both sides read "about the same speed"; outside it, the side with the
  /// higher measured rate is "slightly ahead".
  ///
  /// Returns null (deferring to the outcome wording) when either rate is missing
  /// or the internet rate is ~0 — the same honest guard the comparison line uses,
  /// so the hero never asserts a margin from a figure it does not have (GL-005).
  String? _sameTierHero(ConsumerVerdict verdict) {
    final AxisStatus tier = verdict.wifiStatus;
    if (tier != verdict.internetStatus || tier == AxisStatus.unknown) {
      return null;
    }

    final double? usable = _engine?.usableWifiMbps;
    final double? internet = _engine?.internetAvgMbps;
    if (usable == null || internet == null || internet < 0.5) return null;

    final String tierWord = _lowerTierWord(tier);
    final double deltaPct = 100 * (usable - internet) / internet;
    if (deltaPct.abs() <= 10) {
      return 'Both sides are $tierWord. They’re about the same speed.';
    }
    // Name whichever side measured the higher rate as "slightly ahead".
    final String ahead = deltaPct > 0 ? 'Wi-Fi' : 'internet';
    return 'Both sides are $tierWord. Your $ahead is slightly ahead.';
  }

  /// The lowercase tier word for the same-tier hero sentence ("strong" /
  /// "moderate" / "weak"). [AxisStatus.unknown] never reaches here — the
  /// same-tier branch excludes it — so it defers to the chip word defensively.
  static String _lowerTierWord(AxisStatus tier) {
    switch (tier) {
      case AxisStatus.strong:
        return 'strong';
      case AxisStatus.moderate:
        return 'moderate';
      case AxisStatus.weak:
        return 'weak';
      case AxisStatus.unknown:
        return _TwoAxisChips.word(tier);
    }
  }

  /// The plain, state-driven VERDICT LINE that names the limiter (item #4). It
  /// maps off the SAME verdict classification the engine produced — the line and
  /// the comparison bars always agree. The "could not check one side" rows keep
  /// an honest neutral line and never assert a verdict we do not have (GL-005).
  ///
  /// SAME-TIER OVERRIDE (2026-06-07): when BOTH absolute axis chips land on the
  /// same real tier, naming one side "the weak link" / "the limit" contradicts
  /// two equal chips AND the hero's margin framing (the engine's comparative
  /// `wifiLimiter` verdict fires off the 0.70 headroom ratio, a DIFFERENT basis
  /// than the absolute usable-vs-internet comparison the chips/hero/% line use).
  /// In that case the line is worded by MARGIN to match — see [_sameTierVerdictLine].
  /// Different-tier outcomes keep their existing "weak link / limit" wording.
  String _verdictLine(ConsumerVerdict verdict) {
    final String? sameTier = _sameTierVerdictLine(verdict);
    if (sameTier != null) return sameTier;

    switch (verdict.outcome) {
      case ConsumerOutcome.wifi:
      case ConsumerOutcome.wifiLead:
        // Usable Wi-Fi is clearly below the measured internet — Wi-Fi limits.
        return 'Your Wi-Fi is the weak link right now.';
      case ConsumerOutcome.internet:
        // Usable Wi-Fi clearly exceeds the measured internet — internet limits.
        return 'Your internet is the limit right now, not your Wi-Fi.';
      case ConsumerOutcome.bothFine:
        // Both strong / about even.
        return 'Both your Wi-Fi and your internet are keeping up.';
      case ConsumerOutcome.couldntCheckWifi:
        // Internet measured, Wi-Fi not — honest, no verdict on the missing side.
        return 'We measured your internet, but could not read your Wi-Fi on '
            'this device.';
      case ConsumerOutcome.couldntComplete:
        // Neither side read — honest neutral line.
        return 'We could not read your Wi-Fi or your internet. Make sure you '
            'are on Wi-Fi, then try again.';
    }
  }

  /// The same-tier VERDICT LINE, or null when the two axes are NOT on the same
  /// real tier (the caller then falls through to the existing limiter wording).
  ///
  /// Mirrors [_sameTierHero] exactly — same equal-real-tier guard, same usable
  /// Wi-Fi vs internet basis, same +/-10% margin band — so the hero, this line,
  /// and the % comparison line never disagree. Within the band both sides read
  /// "about the same"; outside it the higher-rate side has "a little more
  /// headroom" (never naming the lower side "the weak link" / "the limit", which
  /// would contradict two equal chips and the % line). Returns null on a missing
  /// or ~0 internet figure so the line never asserts a margin it cannot back
  /// (GL-005).
  String? _sameTierVerdictLine(ConsumerVerdict verdict) {
    final AxisStatus tier = verdict.wifiStatus;
    if (tier != verdict.internetStatus || tier == AxisStatus.unknown) {
      return null;
    }

    final double? usable = _engine?.usableWifiMbps;
    final double? internet = _engine?.internetAvgMbps;
    if (usable == null || internet == null || internet < 0.5) return null;

    final String tierWord = _lowerTierWord(tier);
    final double deltaPct = 100 * (usable - internet) / internet;
    if (deltaPct.abs() <= 10) {
      return 'Both your Wi-Fi and your internet are $tierWord, and running at '
          'about the same speed.';
    }
    final String ahead = deltaPct > 0 ? 'Wi-Fi' : 'internet';
    return 'Both your Wi-Fi and your internet are $tierWord; your $ahead has a '
        'little more headroom right now.';
  }

  /// The DIRECT COMPARISON sentence (item #5): a single headline answer comparing
  /// the SAME two quantities the verdict already compares — the usable Wi-Fi data
  /// rate vs the measured internet rate. N = round(100 * (usableWifi - internet)
  /// / internet). Faster when usable > internet, slower when below, "about the
  /// same" within +/-10%. Returns null (the line is suppressed) when the internet
  /// side could not be measured or is ~0 — the honest neutral verdict line then
  /// carries the result on its own (GL-005: the % is only ever shown from real
  /// measured numbers, never fabricated).
  String? _comparisonLine(ConsumerVerdict verdict) {
    final double? usable = _engine?.usableWifiMbps;
    final double? internet = _engine?.internetAvgMbps;
    // Suppress when either side is missing or the internet rate is ~0 (no truthful
    // denominator). The verdict line already states the honest couldn't-check.
    if (usable == null || internet == null || internet < 0.5) return null;

    final double deltaPct = 100 * (usable - internet) / internet;
    final int n = deltaPct.abs().round();
    // Within +/-10% reads as "about the same speed" rather than a near-zero %.
    if (deltaPct.abs() <= 10) {
      return 'Your Wi-Fi link and your internet connection are running at about '
          'the same speed.';
    }
    final String direction = deltaPct > 0 ? 'faster' : 'slower';
    return 'Your Wi-Fi link is $n% $direction than your internet connection.';
  }

  // ---- Result: the plain help-desk facts ----

  /// The plain facts, as label/value rows. Any field not measured prints
  /// "Not measured" — never blank, never invented (GL-005).
  List<_Fact> _facts() {
    final QualityResult? net = _internet;
    final ConnectedAp? ap = _ap;

    final double? down = ConnectionCheck.metricValue(net, MetricIds.download);
    final double? up = ConnectionCheck.metricValue(net, MetricIds.upload);
    final double? latency =
        ConnectionCheck.metricValue(net, MetricIds.latency);
    final double? loss = ConnectionCheck.metricValue(net, MetricIds.loss);

    final String? wifiName = _consumerWifiName(ap);

    return <_Fact>[
      _Fact('Internet Down', _mbps(down)),
      _Fact('Internet Up', _mbps(up)),
      _Fact(
        'Delay / dropped data',
        '${latency != null ? '${latency.round()} ms' : 'Not measured'} · '
            '${loss != null ? '${loss.round()}%' : 'Not measured'}',
      ),
      if (wifiName != null) _Fact('Wi-Fi network', wifiName),
      _Fact('Tested', '${_formatTimestamp(_testedAt)} on $_platformLabel'),
    ];
  }

  /// The Wi-Fi network NAME for the consumer flow, or null when not available.
  String? _consumerWifiName(ConnectedAp? ap) {
    final String? ssid = ap?.ssid;
    if (ssid != null && ssid.trim().isNotEmpty) return ssid;
    return null;
  }

  /// A network-identity value (SSID or BSSID) for the copy report, or the honest
  /// empty state. On macOS, the SSID and BSSID are the ONLY two RF fields gated
  /// behind Location Services (since macOS 14, CoreWLAN withholds them without
  /// it). When they are absent specifically because Location is not authorized,
  /// the empty state names the fix ("Unavailable (grant Location access to show
  /// the network name)") instead of a bare "Unavailable" that reads like a
  /// glitch. Every other platform / cause falls back to the plain sentinel.
  String _nameOrLocationHint(String? value) {
    if (value != null && value.trim().isNotEmpty) return value;
    if (_source == WifiInfoSource.macosCoreWlan &&
        _macLocationAuthorized == false) {
      return 'Unavailable (grant Location access to show the network name)';
    }
    return 'Unavailable';
  }

  /// RSSI alone, for the copy line. "Unavailable" when the NIC omits it.
  static String _rssiOnly(ConnectedAp? ap) {
    final int? rssi = ap?.rssiDbm;
    return rssi != null ? '$rssi dBm' : 'Unavailable';
  }

  /// SNR alone, for the copy line. "Unavailable" when the NIC omits it.
  static String _snrOnly(ConnectedAp? ap) {
    final int? snr = ap?.snrDb;
    return snr != null ? '$snr dB' : 'Unavailable';
  }

  /// Wi-Fi Down — the NIC's average Rx data rate. When the platform never
  /// exposes Rx at all (macOS public CoreWLAN), the empty state is labelled as a
  /// KNOWN platform limit ("Unavailable (not exposed on macOS)") so a help-desk
  /// reader does not mistake it for a glitch. iOS supplies Rx via the Shortcut
  /// bridge, so its empty state is the plain "Unavailable" (GL-005).
  static String _rxRate(ConnectedAp? ap) {
    final double? rx = ap?.rxRateMbps;
    if (rx != null) return '${rx.round()} Mbps';
    if (ap != null && !ap.rxRateAvailable) {
      return 'Unavailable (not exposed on macOS)';
    }
    return 'Unavailable';
  }

  /// Wi-Fi Up — the NIC's average Tx data rate. "Unavailable" when omitted.
  static String _txRate(ConnectedAp? ap) {
    final double? tx = ap?.txRateMbps;
    return tx != null ? '${tx.round()} Mbps' : 'Unavailable';
  }

  /// Mbps rounded to a whole number for a consumer, or "Not measured".
  static String _mbps(double? v) =>
      v == null ? 'Not measured' : '${v.round()} Mbps';

  /// "Jun 1, 2:14 PM" — month-day + 12-hour clock, no intl dependency.
  static String _formatTimestamp(DateTime? at) {
    if (at == null) return 'Not measured';
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final String month = months[at.month - 1];
    final int hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final String minute = at.minute.toString().padLeft(2, '0');
    final String meridiem = at.hour < 12 ? 'AM' : 'PM';
    return '$month ${at.day}, $hour12:$minute $meridiem';
  }

  // ---- §8.16 copy payload (shared by toolbar + inline button) ----

  bool _detailsCopied = false;

  /// The COMPREHENSIVE help-desk clipboard payload (Keith #3 / #4 / #5 / #6). A
  /// polished, scannable plain-text report a help-desk tech will respect: a
  /// titled header with the test date/time, then clearly-labelled sections in a
  /// fixed order — Wi-Fi / Internet / DNS / Network / ISP / Cloud apps / Verdict
  /// — each an aligned `label: value` block under a hairline separator.
  ///
  /// Plain text only (it is clipboard text — no markdown, so no literal `*`),
  /// but visually organized: each section header sits under a rule of dashes,
  /// and within a section the values are left-aligned to a shared column so the
  /// block reads like a table when pasted into any monospaced or proportional
  /// help-desk field.
  ///
  /// HONESTY (GL-005): every field the platform did not expose prints
  /// "Unavailable" (Wi-Fi link facts) or "Not measured" (internet metrics) —
  /// never blank, never invented. The DNS row reports a REAL measured resolution
  /// time or an honest "Not available"; it is labelled "DNS resolution time" so
  /// it is never mistaken for anything the net_quality engine produces (the
  /// engine still measures no DNS). The Network section's DHCP server, DNS
  /// server(s), and VLAN rows carry the precise reason they are absent rather
  /// than a guessed value. ISP and Cloud-apps sections are omitted entirely when
  /// their data did not land (offline / failed / panel hidden).
  ///
  /// The verdict WORDS still lead (§8.16 / §8.13): the two-axis "Wi-Fi: … ·
  /// Internet: …" line is preserved verbatim near the top, and the exact
  /// "Internet Down / Internet Up" / "Wi-Fi Down / Wi-Fi Up" labels the
  /// help-desk + existing tests rely on are unchanged.
  String? _buildCopyText() {
    if (_running || _verdict == null) return null;
    final List<_Fact> facts = _facts();
    String fact(String label) =>
        facts.firstWhere((f) => f.label == label).value;

    final QualityResult? net = _internet;
    final double? down = ConnectionCheck.metricValue(net, MetricIds.download);
    final double? up = ConnectionCheck.metricValue(net, MetricIds.upload);
    final double? latency =
        ConnectionCheck.metricValue(net, MetricIds.latency);
    final double? jitter = ConnectionCheck.metricValue(net, MetricIds.jitter);
    final double? loss = ConnectionCheck.metricValue(net, MetricIds.loss);
    final double? rpm =
        ConnectionCheck.metricValue(net, MetricIds.responsiveness);

    final ConsumerVerdict? v = _verdict;
    final ConnectedAp? ap = _ap;

    final StringBuffer buf = StringBuffer();

    // ── Header ──────────────────────────────────────────────────────────────
    buf.writeln('WLAN Pros Toolbox — Connection Report');
    buf.writeln('Generated: ${fact('Tested')}');
    if (v != null) {
      buf.writeln(
        'Summary: Wi-Fi ${_TwoAxisChips.word(v.wifiStatus)} · '
        'Internet ${_TwoAxisChips.word(v.internetStatus)}',
      );
    }

    // ── Wi-Fi ─────────────────────────────────────────────────────────────
    final String? wifiName = _consumerWifiName(ap);
    _copySection(buf, 'WI-FI', <_CopyRow>[
      _CopyRow('Network (SSID)', _nameOrLocationHint(wifiName)),
      _CopyRow('BSSID', _nameOrLocationHint(ap?.bssid)),
      _CopyRow('RSSI', _rssiOnly(ap)),
      _CopyRow('Noise', _noiseOnly(ap)),
      _CopyRow('SNR', _snrOnly(ap)),
      // Keep the exact "Wi-Fi Down / Wi-Fi Up" labels the help-desk + existing
      // tests rely on (Rx = Down, Tx = Up).
      _CopyRow('Wi-Fi Down (Rx rate)', _rxRate(ap)),
      _CopyRow('Wi-Fi Up (Tx rate)', _txRate(ap)),
      _CopyRow('Channel', _channelCopy(ap?.channel)),
      _CopyRow('Channel width', _channelWidth(ap)),
      _CopyRow('Band', _orUnavailable(ap?.band)),
      _CopyRow('Standard (PHY)', _orUnavailable(ap?.standard)),
      _CopyRow('Security', _security(ap)),
      // iOS, no RF captured: the empty RF rows above are a CAPTURE step, not a
      // failure. Name that explicitly so a help-desk reader (and Keith) knows the
      // difference (GL-005).
      if (_isIos && !_iosRfCaptured)
        const _CopyRow(
          'Note',
          'Wi-Fi signal details not captured — tap "Capture Wi-Fi details" in '
              'the app to read them via the companion Shortcut.',
        ),
    ]);

    // ── Internet ────────────────────────────────────────────────────────────
    // The exact "Internet Down / Internet Up" lines + the "Not measured" wording
    // are preserved (help-desk + test contract). Jitter and responsiveness are
    // included; the DNS measurement lives in its OWN section below.
    _copySection(buf, 'INTERNET', <_CopyRow>[
      _CopyRow('Internet Down', _mbps(down)),
      _CopyRow('Internet Up', _mbps(up)),
      _CopyRow(
        'Latency',
        latency != null ? '${latency.round()} ms' : 'Not measured',
      ),
      _CopyRow(
        'Jitter',
        jitter != null ? '${jitter.round()} ms' : 'Not measured',
      ),
      _CopyRow('Loss', loss != null ? '${loss.round()}%' : 'Not measured'),
      _CopyRow(
        'Responsiveness',
        rpm != null ? '${rpm.round()} RPM' : 'Not measured',
      ),
    ]);

    // ── DNS ─────────────────────────────────────────────────────────────────
    // A REAL resolution-time measurement (Keith #3), labelled as exactly what it
    // is, or the honest "Not available" when no probed host resolved (GL-005).
    final DnsProbeResult? dns = _dnsResult;
    final String dnsValue = (dns != null && dns.isAvailable)
        ? '${dns.millis} ms'
            '${dns.host != null ? ' (resolved ${dns.host})' : ''}'
        : 'Not available';
    _copySection(buf, 'DNS', <_CopyRow>[
      _CopyRow('Resolution time', dnsValue),
    ]);

    // ── Network ───────────────────────────────────────────────────────────
    // Local addressing (Keith #5): IP / subnet / gateway are obtainable and
    // sandbox-safe; DHCP server, DNS server(s), and VLAN are honestly
    // unavailable on these platforms — each carries the precise reason, never a
    // guessed value (GL-005 / GL-008).
    final NetworkDetails nd = _networkDetails ?? NetworkDetails.empty;
    _copySection(buf, 'NETWORK', <_CopyRow>[
      _CopyRow('Local IP address', nd.localIp ?? 'Not available'),
      _CopyRow('Subnet mask', nd.subnetMask ?? 'Not available'),
      _CopyRow('Default gateway', nd.gateway ?? 'Not available'),
      _CopyRow('DHCP server', NetworkDetails.dhcpReason),
      _CopyRow('DNS server(s)', NetworkDetails.dnsReason),
      _CopyRow('VLAN tag', NetworkDetails.vlanReason),
    ]);

    // ── ISP ────────────────────────────────────────────────────────────────
    // Omitted entirely when the lookup did not land (offline / failed) — never a
    // placeholder section, never a fabricated address (GL-005 / GL-008).
    final IpGeoResult? isp = _ispInfo;
    if (isp != null && !isp.isError) {
      final String? ip = isp.ip;
      final String? org = isp.isp ?? isp.org;
      final String? asn = isp.asn;
      final String? loc = isp.locationLine;
      final List<_CopyRow> rows = <_CopyRow>[
        if (ip != null) _CopyRow('Public IP', ip),
        if (org != null) _CopyRow('ISP / org', org),
        if (asn != null) _CopyRow('ASN', asn),
        if (loc != null) _CopyRow('Approx. location', loc),
      ];
      if (rows.isNotEmpty) _copySection(buf, 'ISP', rows);
    }

    // ── Cloud apps ─────────────────────────────────────────────────────────
    // Omitted when the panel produced no rows yet (hidden / not run). A summary
    // header line plus a per-service "reachable / unreachable (+rtt)" list.
    final List<SiteReachability> cloud = _cloudResults;
    if (cloud.isNotEmpty) {
      final int reachable =
          cloud.where((SiteReachability s) => s.reachable).length;
      final List<_CopyRow> rows = <_CopyRow>[
        for (final SiteReachability s in cloud)
          _CopyRow(
            s.site.name,
            s.reachable
                ? 'reachable'
                    '${s.latencyMs != null ? ' (${s.latencyMs!.round()} ms)' : ''}'
                : 'unreachable',
          ),
      ];
      _copySection(
        buf,
        'CLOUD APPS REACHABLE ($reachable of ${cloud.length})',
        rows,
      );
    }

    // ── Verdict ────────────────────────────────────────────────────────────
    final List<_CopyRow> verdictRows = <_CopyRow>[
      _CopyRow('Result', _verdictLine(v!)),
    ];
    final String? cmp = _comparisonLine(v);
    if (cmp != null) verdictRows.add(_CopyRow('Comparison', cmp));
    _copySection(buf, 'VERDICT', verdictRows);

    return buf.toString().trimRight();
  }

  /// Writes one labelled section to the report [buf]: a blank line, a section
  /// header (`SECTION` over a rule of dashes), then each row as `  label: value`
  /// — a 2-space indent sets the block off from the flush-left header, and the
  /// `label: value` form keeps each datum self-describing when the report is
  /// pasted into any help-desk field (proportional or monospaced). Plain text
  /// only — no markdown that would render as literal asterisks.
  static void _copySection(
    StringBuffer buf,
    String title,
    List<_CopyRow> rows,
  ) {
    buf.writeln('');
    buf.writeln(title);
    buf.writeln('-' * (title.length < 48 ? title.length : 48));
    for (final _CopyRow r in rows) {
      buf.writeln('  ${r.label}: ${r.value}');
    }
  }

  /// A nullable string value or the honest "Unavailable" sentinel (GL-005).
  static String _orUnavailable(String? v) =>
      (v != null && v.trim().isNotEmpty) ? v : 'Unavailable';

  /// Channel for the copy line. Channel 0 is the "no/unknown channel" sentinel
  /// some stacks return — it is never a real Wi-Fi channel, so it prints the
  /// honest "Unavailable" rather than a misleading "0" (GL-005).
  static String _channelCopy(int? channel) {
    if (channel == null || channel == 0) return 'Unavailable';
    return channel.toString();
  }

  /// Noise floor for the copy line. "Unavailable" when the NIC omits it.
  static String _noiseOnly(ConnectedAp? ap) {
    final int? noise = ap?.noiseDbm;
    return noise != null ? '$noise dBm' : 'Unavailable';
  }

  /// Channel width for the copy line, honoring the platform-availability flag.
  static String _channelWidth(ConnectedAp? ap) {
    final int? w = ap?.channelWidthMhz;
    if (w != null) return '$w MHz';
    return 'Unavailable';
  }

  /// Security scheme label, or "Unavailable" when the platform did not report
  /// one. Never invents a scheme (GL-005).
  static String _security(ConnectedAp? ap) {
    final WifiSecurity? s = ap?.securityType;
    return s != null ? s.label : 'Unavailable';
  }

  Future<void> _copyDetails() async {
    final String? text = _buildCopyText();
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Details copied',
      TextDirection.ltr,
    );
    setState(() => _detailsCopied = true);
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _detailsCopied = false);
    });
  }

  // ---- iOS optional Shortcut offer (D1 path) ----

  Future<void> _openShortcutSheet() async {
    final WiFiDetailsBridge? bridge = _iosBridge;
    if (bridge == null) return;
    await showInstallShortcutSheet(
      context: context,
      openUrl: bridge.openUrl,
      onInstalled: () async {
        if (mounted) _run();
      },
    );
  }

  Widget _poweredBy(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Text(
        'Powered by the WLAN Pros Toolbox',
        style: text.labelSmall?.copyWith(color: context.colors.textTertiary),
      ),
    );
  }
}

// ===========================================================================
// A single help-desk fact (label → value).
// ===========================================================================

class _Fact {
  const _Fact(this.label, this.value);
  final String label;
  final String value;
}

/// One `label: value` pair in the copied connection report. Used only by
/// [_buildCopyText] / [_copySection] to lay each section out as an aligned,
/// scannable block of plain text (Keith #4).
class _CopyRow {
  const _CopyRow(this.label, this.value);
  final String label;
  final String value;
}

// ===========================================================================
// (A) VERDICT HERO — the H1/36px plain-language sentence (the visual climax)
// + the two axis status chips SIDE BY SIDE (§2.A / §2.A2).
// ===========================================================================

/// The verdict hero: a single result card holding the plain-language verdict
/// SENTENCE at `headlineLarge` (H1/36px, §8.5.2 scope extension), then the two
/// labeled axis status chips on one row. The sentence is the comprehension
/// climax — the screen opens on the answer, not the numbers (§2.A). The chips
/// teach the two-things model; each carries WORD + GLYPH + color (§1.3), never
/// color alone. In light, the card takes the §8.20.3-C status accent treatment.
class _HeroVerdict extends StatelessWidget {
  const _HeroVerdict({
    required this.verdict,
    required this.heroSentence,
    this.onRunAgain,
  });

  final ConsumerVerdict verdict;
  final String heroSentence;

  /// Re-runs the whole check. Rendered as the unmistakable LABELED "Run again"
  /// control on the hero-sentence row (the AppBar carries only a compact
  /// icon-only refresh so the title never truncates — Vera 2026-06-14). Null
  /// while a run is in flight; the control is then omitted.
  final VoidCallback? onRunAgain;

  /// §8.20.3-C #2 — the status tone that colors the result card's accent bar.
  /// "Both fine" reads as success; any slow side is a warning; an unreadable
  /// side is neutral info. The headline + chips carry the precise verdict; the
  /// bar is a projector-visible reinforcement of the overall tone.
  StatusTone get _tone {
    switch (verdict.outcome) {
      case ConsumerOutcome.bothFine:
        return StatusTone.success;
      case ConsumerOutcome.wifi:
      case ConsumerOutcome.wifiLead:
      case ConsumerOutcome.internet:
        return StatusTone.warning;
      case ConsumerOutcome.couldntCheckWifi:
      case ConsumerOutcome.couldntComplete:
        return StatusTone.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final String semanticsLabel =
        '$heroSentence '
        'Wi-Fi ${_TwoAxisChips.word(verdict.wifiStatus)}. '
        'Internet ${_TwoAxisChips.word(verdict.internetStatus)}.';

    final Widget card = Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // §2.A — the plain-language verdict SENTENCE at H1/36px
          // (`headlineLarge`, §8.5.2 scope extension). The largest in-app
          // headline; the comprehension climax. Wraps (never clips) under
          // dynamic type, §8.9. The unmistakable LABELED "Run again" control
          // shares this row (Keith: same line as something else, no new
          // vertical space) — the sentence flexes, the button trails,
          // top-aligned so it sits beside the first line of a wrapped headline.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                // The verdict sentence is part of the card's single merged SR
                // summary, so its own node is excluded here (the outer Semantics
                // below speaks it). The Run again button, by contrast, is an
                // interactive control and MUST keep its own live semantics — so
                // it is NOT inside this ExcludeSemantics (the blanket card-level
                // exclusion was dropped for exactly this reason).
                child: ExcludeSemantics(
                  child: Text(
                    heroSentence,
                    style:
                        text.headlineLarge?.copyWith(color: colors.textPrimary),
                  ),
                ),
              ),
              if (onRunAgain != null) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                _HeroRunAgainButton(onRunAgain: onRunAgain!),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // §2.A2 — the two axis chips, side by side, teaching the two-things
          // model. Excluded from SR (the merged summary speaks the tiers).
          ExcludeSemantics(
            child: _TwoAxisChips(
              wifiStatus: verdict.wifiStatus,
              internetStatus: verdict.internetStatus,
            ),
          ),
        ],
      ),
    );

    // The card carries a single merged SR summary (sentence + both axis tiers)
    // via this Semantics label; the verdict text and chips above are
    // individually ExcludeSemantics'd so they don't double-speak. The Run again
    // button is deliberately OUTSIDE any exclusion so it stays a focusable,
    // labelled control in the SR tree.
    return Semantics(
      container: true,
      // explicitChildNodes keeps the Run again button as its OWN focusable,
      // labelled child node rather than collapsing it into this container's
      // merged summary (the verdict text + chips are ExcludeSemantics'd above,
      // so the only surviving descendant node is the button).
      explicitChildNodes: true,
      label: semanticsLabel,
      // §8.20.3-C #2 — in light, the status-bearing result card carries a 6px
      // full-saturation status-hue left-accent bar plus a 4px top strip in the
      // same hue (a small AREA, not a thin line, so full saturation). No bars
      // in dark.
      child: colors.isLight
          ? _StatusAccentFrame(tone: _tone, child: card)
          : card,
    );
  }
}

/// The unmistakable LABELED "Run again" control on the verdict-hero sentence
/// row — the primary re-run affordance (the AppBar now carries only the §8.16
/// copy action so the full "Test My Connection" title clears at every iPhone
/// width). Visible "Run again" text + the `Icons.refresh` glyph; re-runs the
/// WHOLE check. Carries the 'Run the test again' Semantics label and the §8.3
/// 44pt touch target. Lime accent (theme-aware: brand lime in dark,
/// darkened-lime via textAccent in light so it stays legible on the white card).
class _HeroRunAgainButton extends StatelessWidget {
  const _HeroRunAgainButton({required this.onRunAgain});

  final VoidCallback onRunAgain;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final Color accent = colors.isLight ? colors.textAccent : colors.primary;
    // The label overrides the visible "Run again" text for AT with the explicit
    // 'Run the test again' action phrase (matching the former AppBar action's
    // label, so existing finders resolve). Same pattern as AppCopyAction /
    // _RetryButton: ExcludeSemantics drops the inner button's own label so the
    // parent Semantics owns the single labelled button node, while the
    // TextButton remains the real focusable, activatable control.
    return Semantics(
      button: true,
      label: 'Run the test again',
      child: ExcludeSemantics(
        child: TextButton.icon(
          onPressed: onRunAgain,
          icon: Icon(Icons.refresh, size: 20, color: accent),
          label: Text(
            'Run again',
            style: TextStyle(color: accent, fontWeight: FontWeight.w600),
          ),
          style: TextButton.styleFrom(
            foregroundColor: accent,
            // §8.3 44pt hit region; the label adds width, not height.
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}

/// Wraps a result card with the §8.20.3-C #2 status accent treatment (light
/// only): a 6px full-saturation status-hue bar down the left edge and a 4px
/// strip across the top, both in the relevant status hue. The bars are small
/// AREAS (≥3:1 vs the white card), so they carry the hue at full saturation; the
/// card's headline + chips carry the precise meaning.
class _StatusAccentFrame extends StatelessWidget {
  const _StatusAccentFrame({required this.tone, required this.child});

  final StatusTone tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final Color hue = colors.statusToneColor(tone);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Stack(
        children: <Widget>[
          child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(height: 4, color: hue), // top strip
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: Container(width: 6, color: hue), // left accent bar
          ),
        ],
      ),
    );
  }
}

/// The two labeled axis chips, laid out side by side (Item B) and wrapping to a
/// second row at the smallest width. Each carries an aligned plain label + a
/// status chip; the WORD always carries the verdict (never color alone).
class _TwoAxisChips extends StatelessWidget {
  const _TwoAxisChips({
    required this.wifiStatus,
    required this.internetStatus,
  });

  final AxisStatus wifiStatus;
  final AxisStatus internetStatus;

  /// Plain status WORD — the single source the card, chip, and SR label share.
  /// REVISION 2 (2026-06-07): the 3-tier absolute scale — Strong / Moderate /
  /// Weak — plus the honest "Couldn't check" for an unmeasured side (GL-005).
  static String word(AxisStatus s) {
    switch (s) {
      case AxisStatus.strong:
        return 'Strong';
      case AxisStatus.moderate:
        return 'Moderate';
      case AxisStatus.weak:
        return 'Weak';
      case AxisStatus.unknown:
        return "Couldn't check";
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wrap, not Row: the two labeled chips sit side by side on a wide card and
    // reflow to two rows on a narrow one (320px / large type) without clipping.
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        _AxisRow(label: 'Wi-Fi', status: wifiStatus),
        _AxisRow(label: 'Internet', status: internetStatus),
      ],
    );
  }
}

/// One axis: an aligned plain label + a status chip.
class _AxisRow extends StatelessWidget {
  const _AxisRow({required this.label, required this.status});

  final String label;
  final AxisStatus status;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          '$label:',
          style: text.bodyLarge?.copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(width: AppSpacing.xs),
        _StatusChip(status: status),
      ],
    );
  }
}

/// A single status chip: icon + WORD + §8.13/§8.20.4 color. The WORD always
/// carries meaning (WCAG 2.2 SC 1.4.1).
///
/// LIGHT (§8.20.4 Style A) renders the SOLID-FILL pill — the full-strength
/// status hue as a solid fill carrying a WHITE 700 label and a WHITE Material
/// status glyph (white-on-fill 5.4–5.9:1). DARK keeps the §8.13 outline chip
/// (surface2 fill + thin colored border + colored label/glyph). The "couldn't
/// check" neutral state has no status hue, so light fills it with the neutral
/// textSecondary #4A4A4A (white-on-fill 8.86:1) for the same solid + white
/// look, matching the _GradeChip no-hue fills.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final AxisStatus status;

  /// The full-strength status hue, theme-aware. In dark this colors the label,
  /// glyph and border; in light it is the §8.20.4 solid pill fill.
  Color _color(AppColorScheme colors) {
    switch (status) {
      // REVISION 2 (2026-06-07) — §8.13 verdict hues, one per tier:
      // Strong → success (green), Moderate → warning (amber), Weak → danger
      // (red). The WORD carries the meaning; the hue reinforces it (never
      // color-only, §8.13 rule 2 / WCAG 2.2 SC 1.4.1).
      case AxisStatus.strong:
        return colors.statusSuccess;
      case AxisStatus.moderate:
        return colors.statusWarning;
      case AxisStatus.weak:
        return colors.statusDanger;
      case AxisStatus.unknown:
        // Light: neutral textSecondary #4A4A4A fill, matching the _GradeChip
        // no-hue fills across TMC / wifi_info / net_quality. Dark stays on
        // textTertiary so the dark render is byte-identical.
        return colors.isLight ? colors.textSecondary : colors.textTertiary;
    }
  }

  /// The Material status glyph. Light uses the FILLED variant (a solid white
  /// knockout on the solid pill, §8.20.4); dark keeps the original OUTLINED
  /// variant so the dark render is byte-identical.
  IconData _icon(bool light) {
    switch (status) {
      // REVISION 2 (2026-06-07) — the §8.13 status glyph per tier. Light uses
      // the FILLED variant (white knockout on the solid pill, §8.20.4); dark
      // keeps the OUTLINED variant so the dark render stays byte-stable.
      case AxisStatus.strong:
        return light ? Icons.check_circle : Icons.check_circle_outline;
      case AxisStatus.moderate:
        return light ? Icons.warning_amber : Icons.warning_amber_outlined;
      case AxisStatus.weak:
        // `error` is the §8.13 danger glyph (rule 2). Filled in light, outlined
        // in dark — a failing-rate verdict, not a "fault we can't read".
        return light ? Icons.error : Icons.error_outline;
      case AxisStatus.unknown:
        // §1.1 — the "couldn't check" glyph is `help_outline`, NOT error /
        // cancel / block / remove. Those carry "fault"; this reads "unknown /
        // not determined", which is the truth. Same outlined glyph the footer
        // uses, so it reads familiar and non-threatening.
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final Color hue = _color(colors);

    // §8.20.4 Style A (light): solid hue fill, white label + white glyph, no
    // border. §8.13 (dark): surface2 fill, thin colored border, colored content.
    final Color fill = colors.isLight ? hue : colors.surface2;
    final Color content = colors.isLight ? const Color(0xFFFFFFFF) : hue;
    final BoxBorder? border =
        colors.isLight ? null : Border.all(color: hue, width: 1);

    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: border,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_icon(colors.isLight), size: 18, color: content),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            _TwoAxisChips.word(status),
            style: text.labelLarge?.copyWith(
              color: content,
              fontWeight: FontWeight.w700, // §8.20.4 / §8.20.3-A verdict word
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// VERDICT LINE — the plain, state-driven verdict that names the limiter, plus
// the direct % comparison answer. ALWAYS visible (no disclosure), prominent.
// Added in the v1.1 "show more" pass (Keith, 2026-06-05) walking back the
// over-simplified reshape toward MORE information.
// ===========================================================================

/// The verdict block beneath the hero: a plain sentence naming the limiter
/// ([verdict], item #4) and the single direct-comparison sentence ([comparison],
/// item #5). The verdict line sits at `bodyLarge`/textPrimary; the comparison
/// sentence is the headline answer, bumped to `titleMedium` weight so it reads
/// as the prominent takeaway. The comparison line is omitted entirely when null
/// (internet not measured / ~0) — the honest verdict line then stands alone
/// (GL-005). The two lines read as one container for screen readers.
class _VerdictLine extends StatelessWidget {
  const _VerdictLine({required this.verdict, required this.comparison});

  final String verdict;

  /// The direct % comparison sentence, or null when it must be suppressed
  /// (internet side unmeasured / ~0). Never fabricated.
  final String? comparison;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final String? cmp = comparison;
    return Semantics(
      container: true,
      label: cmp == null ? verdict : '$verdict $cmp',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              verdict,
              style: text.bodyLarge?.copyWith(color: colors.textPrimary),
            ),
            if (cmp != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                cmp,
                style: text.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 2. Core comparison — usable Wi-Fi capacity vs internet throughput on a
// shared scale. Wi-Fi is the lime accent bar; internet is a NEUTRAL bar
// (surface3 fill + borderStrong outline, NOT a status hue, per Vera §8.13).
// Always rendered in the result detail (the "See the details" disclosure was
// removed in v1.1; the detail no longer collapses).
// ===========================================================================

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.result});

  final WifiVsInternetResult result;

  /// The plain reading line beneath the bars, derived from the engine verdict so
  /// the words and the bar heights agree. No new verdict math — it reads the
  /// already-computed verdict and reuses the engine's usable-capacity figure.
  ///
  /// SAME-TIER OVERRIDE (2026-06-07): the bars compare ABSOLUTE usable Wi-Fi vs
  /// internet, and the chips/hero/% line bucket those same two rates into Strong
  /// / Moderate / Weak tiers. When both rates land on the SAME real tier, the
  /// "Boost the Wi-Fi signal" / "internet can carry more" wording (which keys off
  /// the engine's 0.70 headroom-ratio `wifiLimiter`/`bothContributing` verdict, a
  /// DIFFERENT basis) contradicts two equal chips and a "Wi-Fi N% faster" line.
  /// In that case the reading line is worded by MARGIN to match — see
  /// [_sameTierReadingLine]. Different-tier verdicts keep their existing wording.
  String _readingLine() {
    final String? sameTier = _sameTierReadingLine();
    if (sameTier != null) return sameTier;

    switch (result.verdict) {
      case WifiVsInternetVerdict.wifiLimiter:
        return 'Your internet can carry more than your Wi-Fi link is passing. '
            'Boost the Wi-Fi signal to raise the ceiling.';
      case WifiVsInternetVerdict.bothContributing:
        return 'Your internet is using almost all the headroom your Wi-Fi link '
            'can carry. Boost the Wi-Fi signal to raise the ceiling.';
      case WifiVsInternetVerdict.upstream:
        return 'Your Wi-Fi link has room to spare. The internet coming into '
            'your home is the slower part right now.';
      case WifiVsInternetVerdict.bothHealthy:
        return 'Both your Wi-Fi and your internet are keeping up. Neither side '
            'is holding you back right now.';
      case WifiVsInternetVerdict.wifiUnknown:
        return result.internetAvgMbps == null
            ? 'We could not read your Wi-Fi link, so there is nothing to '
                'compare the internet against yet.'
            : 'We could not read your Wi-Fi link, so only the internet side is '
                'shown.';
    }
  }

  /// The same-tier reading line, or null when the two rates are NOT on the same
  /// real tier (the caller then falls through to the engine-verdict wording).
  ///
  /// Buckets the SAME two rates the bars draw — [WifiVsInternetResult.usableWifiMbps]
  /// and [WifiVsInternetResult.internetAvgMbps] — into Strong / Moderate / Weak via
  /// [AxisStatusThresholds.tierFor], the EXACT source the consumer chips use, so
  /// "same tier" here means the same thing the chips show. Fires only when both
  /// rates are real (non-null, internet not ~0) and land on the same real tier;
  /// then it words the line by the +/-10% margin band (matching the hero, the
  /// secondary line, and the % comparison line) and never names either side "the
  /// weak link" / "boost the Wi-Fi" / "the slower part". Null otherwise (GL-005).
  String? _sameTierReadingLine() {
    final double? usable = result.usableWifiMbps;
    final double? internet = result.internetAvgMbps;
    if (usable == null || internet == null || internet < 0.5) return null;

    final AxisStatus wifiTier = AxisStatusThresholds.tierFor(usable);
    final AxisStatus internetTier = AxisStatusThresholds.tierFor(internet);
    if (wifiTier != internetTier || wifiTier == AxisStatus.unknown) return null;

    final double deltaPct = 100 * (usable - internet) / internet;
    if (deltaPct.abs() <= 10) {
      return 'Your Wi-Fi link and your internet are carrying about the same. '
          'Neither side is clearly holding you back right now.';
    }
    final String ahead = deltaPct > 0 ? 'Wi-Fi link' : 'internet';
    return 'Your $ahead has a little more headroom, but both sides are in the '
        'same range right now.';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double? usable = result.usableWifiMbps;
    final double? internet = result.internetAvgMbps;

    // Shared scale: the larger of the two figures is full width, so the bars are
    // directly comparable. When one side is unknown, the other still draws.
    final double scaleMax = <double>[
      usable ?? 0,
      internet ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final double safeMax = scaleMax <= 0 ? 1 : scaleMax;

    final String wifiValue =
        usable != null ? '${usable.round()} Mbps' : 'Unavailable';
    final String internetValue =
        internet != null ? '${internet.round()} Mbps' : 'Unavailable';

    final AppColorScheme colors = context.colors;
    return Semantics(
      container: true,
      // §1.3.1 — mark the comparison card as an SR heading node so heading-rotor
      // navigation can land on it (previously the card carried no heading
      // semantic at all). SR-only: the visible bar label "Wi-Fi usable capacity"
      // is the de-facto card title and is unchanged. No layout shift.
      header: true,
      label:
          'Wi-Fi usable capacity $wifiValue. Internet throughput '
          '$internetValue. ${_readingLine()}',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: colors.border,
              width: colors.isLight ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CompareBar(
                label: 'Wi-Fi usable capacity',
                value: wifiValue,
                fraction: usable == null ? null : (usable / safeMax),
                accent: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              _CompareBar(
                label: 'Internet throughput',
                value: internetValue,
                fraction: internet == null ? null : (internet / safeMax),
                accent: false,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _readingLine(),
                style: text.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One labeled bar in the comparison. The lime [accent] bar is the Wi-Fi usable
/// capacity (the single semantic accent); the non-accent bar is the NEUTRAL
/// internet bar (surface3 fill + borderStrong outline, never a status hue).
class _CompareBar extends StatelessWidget {
  const _CompareBar({
    required this.label,
    required this.value,
    required this.fraction,
    required this.accent,
  });

  final String label;
  final String value;

  /// 0..1 of the shared scale, or null when the figure is unavailable (the bar
  /// track shows empty and the value reads "Unavailable").
  final double? fraction;
  final bool accent;

  static const double _barHeight = 10;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final AppColorScheme colors = context.colors;
    final double f = (fraction ?? 0).clamp(0.0, 1.0);

    // On light, surface2/surface3 are both white and would vanish against the
    // white card: the empty track uses the gray canvas, and the neutral
    // (internet) fill uses the gray canvas + borderStrong so it reads as a
    // bordered neutral bar, not an invisible one.
    final Color trackColor = colors.isLight ? colors.surface0 : colors.surface2;
    final Color neutralFill = colors.isLight ? colors.surface0 : colors.surface3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: text.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              value,
              style: mono.robotoMono.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        // The shared-scale track. §8.20.3-B/C — the Wi-Fi capacity fill is a bar
        // AREA, not a thin foreground, so it carries FULL-saturation brand lime
        // #A1CC3A in both themes (a vivid fill reads at distance; the olive
        // substitute is only for thin foregrounds, §8.20.2). The internet bar is
        // the neutral fill + borderStrong outline.
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: SizedBox(
            height: _barHeight,
            child: Stack(
              children: <Widget>[
                Container(color: trackColor),
                FractionallySizedBox(
                  widthFactor: f == 0 ? 0.0 : f,
                  child: accent
                      ? Container(color: colors.primary)
                      : Container(
                          decoration: BoxDecoration(
                            color: neutralFill,
                            border: Border.all(
                              color: colors.borderStrong,
                              width: 1,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// 3. Live "Wi-Fi signal" sparkline card — REUSES the shared WifiSignalSampler
// and the shared Sparkline. Three rows: Wi-Fi data rate, SNR, RSSI, each with a
// current value (mono), a trend arrow, and an inline sparkline. macOS auto-polls
// continuously; iOS streams via the companion Shortcut (Start/Stop), degrading
// honestly when the Shortcut is absent.
// ===========================================================================

class _LiveSignalCard extends StatelessWidget {
  const _LiveSignalCard({required this.sampler});

  final WifiSignalSampler sampler;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sampler,
      builder: (context, _) {
        final ConnectedAp? latest = sampler.latest;
        final WifiTimeSeries series = sampler.series;
        final TextTheme text = Theme.of(context).textTheme;
        final AppColorScheme colors = context.colors;
        // LIVE label is a thin foreground → darkened-lime in light, lime in dark.
        final Color liveColor =
            colors.isLight ? colors.textAccent : colors.primary;

        return Container(
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: colors.border,
              width: colors.isLight ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Header: title + LIVE indicator (lime dot — NOT a status hue),
              // or, on iOS while paused, a Start affordance.
              Row(
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Wi-Fi signal',
                        style: text.titleSmall?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (sampler.isIos && !sampler.isStreaming)
                    Semantics(
                      button: true,
                      label: 'Start live Wi-Fi signal',
                      child: OutlinedButton.icon(
                        onPressed: sampler.start,
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Start'),
                      ),
                    )
                  else if (sampler.isIos && sampler.isStreaming)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _LiveDot(color: liveColor),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          'LIVE',
                          style: text.labelMedium?.copyWith(
                            color: liveColor,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Semantics(
                          button: true,
                          label: 'Stop live Wi-Fi signal',
                          child: IconButton(
                            icon: const Icon(Icons.stop, size: 20),
                            tooltip: 'Stop',
                            visualDensity: VisualDensity.compact,
                            onPressed: sampler.stop,
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _LiveDot(color: liveColor),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          'LIVE',
                          style: text.labelMedium?.copyWith(
                            color: liveColor,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              // Walk-around tip (item #6) — invites the user to move while the
              // live feed runs so they see the signal change spot to spot.
              Text(
                'Walk around while this runs to see how your Wi-Fi signal '
                'changes from spot to spot.',
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (sampler.isIos &&
                  sampler.triggerError) ...<Widget>[
                _LiveUnavailableNote(
                  message:
                      'Could not start the live Wi-Fi feed. The companion '
                      '"WLAN Pros Live" Shortcut may not be installed. Install '
                      'it, then tap Start.',
                ),
              ] else if (series.isEmpty) ...<Widget>[
                _LiveUnavailableNote(
                  // iOS, not yet started → invite the deliberate Start tap.
                  // iOS, started but the first sample has not landed yet →
                  // an HONEST "waiting" indicator (the Shortcut WAS fired; we
                  // are genuinely waiting on it, never a fake "LIVE" with
                  // nothing behind it). macOS auto-polls, so it is simply
                  // reading the link.
                  message: sampler.isIos
                      ? (sampler.isStreaming
                          ? 'Starting the live Wi-Fi feed from the companion '
                              'Shortcut. The first reading should arrive in a '
                              'moment…'
                          : 'Tap Start to begin live Wi-Fi signal readings from '
                              'the companion Shortcut.')
                      : 'Reading the Wi-Fi link…',
                ),
              ] else ...<Widget>[
                // Wi-Fi data rate (Tx — the rate macOS reliably exposes; iOS
                // carries both). Trend arrow + lime sparkline (not graded).
                _SignalRow(
                  label: 'Wi-Fi data rate',
                  unit: 'Mbps',
                  value: _rate(latest?.txRateMbps),
                  window: series.txRate,
                  // Thin sparkline line → darkened-lime in light, lime in dark.
                  lineColor: liveColor,
                ),
                const SizedBox(height: AppSpacing.xs),
                // SNR — graded line color reinforces the trend (word still leads
                // via the value; the line tint is reinforcement only).
                _SignalRow(
                  label: 'SNR',
                  unit: 'dB',
                  value: latest?.snrDb?.toString(),
                  window: series.snr,
                  lineColor: _gradeColor(
                    colors,
                    WifiGrading.gradeSnr(latest?.snrDb),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // RSSI.
                _SignalRow(
                  label: 'RSSI',
                  unit: 'dBm',
                  value: latest?.rssiDbm?.toString(),
                  window: series.rssi,
                  lineColor: _gradeColor(
                    colors,
                    WifiGrading.gradeRssi(latest?.rssiDbm),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String? _rate(double? mbps) {
    if (mbps == null) return null;
    if (mbps == mbps.roundToDouble()) return mbps.toStringAsFixed(0);
    return mbps.toStringAsFixed(1);
  }

  /// Tints a sparkline to its grade (reinforcement only; the unavailable case
  /// stays neutral so it never reads as a verdict). Theme-aware — status hues
  /// re-derive darker in light (§8.20.1).
  static Color _gradeColor(AppColorScheme colors, QualityGrade grade) {
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

/// One live-signal row: label, current value (mono), a trend arrow derived from
/// the window's last two PRESENT samples, and an inline sparkline.
class _SignalRow extends StatelessWidget {
  const _SignalRow({
    required this.label,
    required this.unit,
    required this.value,
    required this.window,
    required this.lineColor,
  });

  final String label;
  final String unit;
  final String? value;
  final List<double?> window;
  final Color lineColor;

  static const double _sparklineHeight = 28;

  /// −1 falling, 0 steady, +1 rising — from the last two present samples.
  int get _trend {
    double? prev;
    double? last;
    for (final double? v in window) {
      if (v == null) continue;
      prev = last;
      last = v;
    }
    if (prev == null || last == null) return 0;
    if (last > prev) return 1;
    if (last < prev) return -1;
    return 0;
  }

  IconData get _trendIcon {
    switch (_trend) {
      case 1:
        return Icons.trending_up;
      case -1:
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  String get _trendWord {
    switch (_trend) {
      case 1:
        return 'rising';
      case -1:
        return 'falling';
      default:
        return 'steady';
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final AppColorScheme colors = context.colors;
    final bool hasValue = value != null && value!.trim().isNotEmpty;
    final String shown = hasValue ? '$value $unit' : 'Unavailable';

    return Semantics(
      container: true,
      label: '$label, $shown, $_trendWord',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // Label + value stack (left).
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          shown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: hasValue
                              ? mono.robotoMono.copyWith(
                                  color: colors.textPrimary,
                                )
                              : text.bodyMedium?.copyWith(
                                  color: colors.textSecondary,
                                ),
                        ),
                      ),
                      if (hasValue) ...<Widget>[
                        const SizedBox(width: AppSpacing.xxs),
                        Icon(
                          _trendIcon,
                          size: 16,
                          color: colors.textTertiary,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Sparkline (right, fills).
            Expanded(
              child: Sparkline(
                values: window,
                lineColor: lineColor,
                semanticLabel: '$label trend',
                height: _sparklineHeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "LIVE" dot. Lime is the §8.3 active-state accent, not a verdict, so it is
/// off-limits for status color (§8.13). [color] is the foreground-accent (lime
/// in dark, darkened-lime in light) resolved by the parent so a small dot stays
/// visible on white (§8.20.2 — lime as a thin foreground fails on light).
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Honest note inside the live card when no samples exist yet or the iOS feed
/// could not start (GL-005 — no fabricated trend).
class _LiveUnavailableNote extends StatelessWidget {
  const _LiveUnavailableNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      message,
      style: text.bodyMedium?.copyWith(color: context.colors.textSecondary),
    );
  }
}

// ===========================================================================
// 4. "What to tell support" — plain measured facts + inline copy button.
// ===========================================================================

class _HelpDeskCard extends StatelessWidget {
  const _HelpDeskCard({
    required this.facts,
    required this.onCopy,
    required this.copied,
  });

  final List<_Fact> facts;
  final Future<void> Function() onCopy;
  final bool copied;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              'What to tell support',
              style: text.titleSmall?.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...facts.map((f) => _FactRow(fact: f)),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            button: true,
            label: copied ? 'Details copied' : 'Copy these details',
            child: OutlinedButton.icon(
              onPressed: onCopy,
              icon: Icon(
                copied ? Icons.check : Icons.copy_outlined,
                size: 20,
                color: copied ? colors.statusSuccess : colors.textSecondary,
              ),
              label: Text(copied ? 'Copied' : 'Copy these details'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One help-desk fact as a label → value row. The whole row is one semantic
/// node. Value wraps before overflowing at 320px.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact});

  final _Fact fact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding / 2),
      child: Semantics(
        container: true,
        label: '${fact.label}, ${fact.value}',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 2,
              child: Text(
                fact.label,
                style: text.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 3,
              child: Text(
                fact.value,
                textAlign: TextAlign.end,
                style: text.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// NETWORK details card (Keith #5 + #3). A compact, grouped readout of the
// device's local addressing — DNS resolution time, local IP, subnet mask,
// default gateway — plus the honestly-unavailable DHCP server, DNS server(s),
// and VLAN rows. Every row is truthful (GL-005): an obtainable field that came
// back null renders "Not available"; the three structurally-unavailable rows
// carry the precise reason the data is absent (sandbox / platform / 802.1Q
// stripping), never a guessed value.
// ===========================================================================

class _NetworkDetailsCard extends StatelessWidget {
  const _NetworkDetailsCard({required this.details, required this.dns});

  /// The local-addressing snapshot, or null while the read is in flight / after
  /// it failed (the obtainable rows then show "Not available").
  final NetworkDetails? details;

  /// The DNS resolution-time probe result, or null while it is in flight (the
  /// row then shows a neutral "Measuring…"); an unavailable result shows the
  /// honest "Not available".
  final DnsProbeResult? dns;

  /// The DNS resolution-time row value: the measured time + the host that
  /// resolved when available, a neutral in-flight string while still probing,
  /// or the honest "Not available" when no host resolved. Never fabricated.
  String _dnsValue() {
    final DnsProbeResult? r = dns;
    if (r == null) return 'Measuring…';
    if (r.isAvailable) {
      final String host = r.host != null ? ' (${r.host})' : '';
      return '${r.millis} ms$host';
    }
    return 'Not available';
  }

  @override
  Widget build(BuildContext context) {
    final NetworkDetails? d = details;
    return _SectionCard(
      title: 'Network',
      children: <Widget>[
        // DNS RESOLUTION TIME (Keith #3) — a real timed lookup through the
        // device resolver, labelled exactly as what it is.
        _DataRow(
          label: 'DNS resolution time',
          value: _dnsValue(),
          mono: true,
        ),
        // Local IP / subnet / gateway — obtainable, sandbox-safe. A null shows
        // the _DataRow "Unavailable" treatment (honest, not fabricated).
        _DataRow(label: 'Local IP address', value: d?.localIp, mono: true),
        _DataRow(label: 'Subnet mask', value: d?.subnetMask, mono: true),
        _DataRow(label: 'Default gateway', value: d?.gateway, mono: true),
        // DHCP server / DNS server(s) — structurally unavailable on these
        // platforms (no sandbox-safe source). Rendered as the design system's
        // muted "Unavailable" value with the precise reason beneath, so the row
        // reads as an honest platform fact, not a missing read (GL-005).
        const _DataRow(
          label: 'DHCP server',
          value: null,
          note: NetworkDetails.dhcpReason,
        ),
        const _DataRow(
          label: 'DNS server(s)',
          value: null,
          note: NetworkDetails.dnsReason,
        ),
        // VLAN tag — a true platform fact: 802.1Q tags are stripped before the
        // endpoint OS sees the frame, so no endpoint app can observe one.
        const _DataRow(
          label: 'VLAN tag',
          value: null,
          note: NetworkDetails.vlanReason,
        ),
      ],
    );
  }
}

// ===========================================================================
// The absorbed pro "Wi-Fi vs Internet" readout — the technical layer, now
// ALWAYS rendered in the result detail (the "See the details" disclosure was
// removed in v1.1; this section no longer collapses).
// Nothing the pro tool showed is lost; it just no longer leads the screen.
// ===========================================================================

class _TechnicalSection extends StatelessWidget {
  const _TechnicalSection({
    required this.ap,
    required this.internet,
    required this.result,
    this.needsWifiCapture = false,
    this.onCaptureWifi,
  });

  final ConnectedAp? ap;
  final QualityResult? internet;
  final WifiVsInternetResult result;

  /// iOS-only: true when the companion Shortcut has not captured the RF metrics,
  /// so the Wi-Fi link sub-card shows a capture affordance instead of an empty
  /// "Unavailable" grid.
  final bool needsWifiCapture;

  /// Opens the one-time companion-Shortcut setup/capture sheet. Null off iOS.
  final VoidCallback? onCaptureWifi;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Section heading — the named concept "Wi-Fi vs Internet" survives.
        // Marked as an SR heading so heading-rotor navigation can land on it.
        Semantics(
          header: true,
          child: Text(
            'Wi-Fi vs Internet',
            style: text.titleMedium?.copyWith(color: colors.textPrimary),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ProVerdictCard(result: result),
        const SizedBox(height: AppSpacing.sm),
        _WifiLinkSection(
          ap: ap,
          result: result,
          needsCapture: needsWifiCapture,
          onCapture: onCaptureWifi,
        ),
        const SizedBox(height: AppSpacing.sm),
        _InternetSection(result: internet),
        const SizedBox(height: AppSpacing.sm),
        Text(
          kWifiVsInternetFootnote,
          style: text.labelMedium?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// The pro verdict card (absorbed from wifi_vs_internet_screen): the engineer
/// verdict word + explanation + supporting SNR context, in the §8.13 status hue.
class _ProVerdictCard extends StatelessWidget {
  const _ProVerdictCard({required this.result});

  final WifiVsInternetResult result;

  static Color _statusColor(AppColorScheme colors, WifiVsInternetVerdict v) {
    switch (v) {
      case WifiVsInternetVerdict.bothHealthy:
        return colors.statusSuccess;
      case WifiVsInternetVerdict.wifiLimiter:
      case WifiVsInternetVerdict.upstream:
      case WifiVsInternetVerdict.bothContributing:
        return colors.statusWarning;
      case WifiVsInternetVerdict.wifiUnknown:
        return colors.statusInfo;
    }
  }

  static IconData _icon(WifiVsInternetVerdict v) {
    switch (v) {
      case WifiVsInternetVerdict.bothHealthy:
        return Icons.check_circle_outline;
      case WifiVsInternetVerdict.wifiLimiter:
        return Icons.wifi_outlined;
      case WifiVsInternetVerdict.upstream:
        return Icons.cloud_off_outlined;
      case WifiVsInternetVerdict.bothContributing:
        return Icons.compare_arrows;
      case WifiVsInternetVerdict.wifiUnknown:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final Color status = _statusColor(colors, result.verdict);

    final Widget card = Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      // §8.20.3-C #1 — pad the left edge in light so the 4px accent bar (added
      // below) clears the content.
      padding: EdgeInsets.fromLTRB(
        colors.isLight ? AppSpacing.sm + 4 : AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(_icon(result.verdict), size: 24, color: status),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  result.headline,
                  style: text.titleMedium?.copyWith(
                    color: status,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            result.explanation,
            style: text.bodyLarge?.copyWith(color: colors.textPrimary),
          ),
          if (result.snrContext.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              result.snrContext,
              style: text.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      container: true,
      label:
          'Verdict: ${result.headline}. ${result.explanation}'
          '${result.snrContext.isNotEmpty ? ' ${result.snrContext}' : ''}',
      child: ExcludeSemantics(
        // §8.20.3-C #1 — a status-bearing result card gets a 4px colored
        // left-accent bar in light (clears the 3:1 SC 1.4.11 floor). Dark keeps
        // the plain card (no accent bar in §8.13).
        child: colors.isLight
            ? ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Stack(
                  children: <Widget>[
                    card,
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 0,
                      child: Container(width: 4, color: status),
                    ),
                  ],
                ),
              )
            : card,
      ),
    );
  }
}

/// "Your Wi-Fi link" sub-card (absorbed verbatim from wifi_vs_internet_screen).
class _WifiLinkSection extends StatelessWidget {
  const _WifiLinkSection({
    required this.ap,
    required this.result,
    this.needsCapture = false,
    this.onCapture,
  });

  final ConnectedAp? ap;
  final WifiVsInternetResult result;

  /// iOS-only: true when the companion Shortcut has not captured the RF metrics.
  /// The card then leads with a "Tap to capture Wi-Fi details" affordance so the
  /// empty RF block reads as a capture step, not a broken tool (GL-005 / GL-008).
  final bool needsCapture;

  /// Opens the one-time companion-Shortcut setup/capture sheet. Null off iOS.
  final VoidCallback? onCapture;

  @override
  Widget build(BuildContext context) {
    final ConnectedAp? a = ap;
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    // iOS, no RF captured: lead the section with the honest capture affordance
    // instead of a grid of "Unavailable". The native identity rows (SSID/BSSID/
    // Security, read via NEHotspotNetwork) still render below when available, so
    // the user sees what IS known and exactly how to fill in the rest.
    if (needsCapture) {
      return _SectionCard(
        title: 'Your Wi-Fi link',
        children: <Widget>[
          Text(
            'Wi-Fi signal details (RSSI, channel, rate, and PHY) need a quick '
            'capture on iOS. Tap below to read them through the one-time '
            'companion Shortcut — no Location permission needed.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            button: true,
            label: 'Capture Wi-Fi details',
            child: FilledButton.icon(
              onPressed: onCapture,
              icon: const Icon(Icons.bolt_outlined),
              label: const Text('Capture Wi-Fi details'),
            ),
          ),
          // Show the natively-known identity rows when we have them, so the card
          // is never empty and the user sees what the app already read.
          if (a?.ssid != null || a?.bssid != null || a?.securityType != null)
            ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              if (a?.bssid != null)
                _DataRow(label: 'BSSID', value: a?.bssid, mono: true),
              if (a?.securityType != null)
                _DataRow(label: 'Security', value: a?.securityType?.label),
            ],
        ],
      );
    }
    return _SectionCard(
      title: 'Your Wi-Fi link',
      children: <Widget>[
        _DataRow(
          label: 'Tx rate',
          value: _rate(a?.txRateMbps),
          unit: 'Mbps',
          mono: true,
        ),
        _DataRow(
          label: 'Rx rate',
          value: _rate(a?.rxRateMbps),
          unit: 'Mbps',
          mono: true,
          // macOS public CoreWLAN never exposes the Rx rate (the Tx rate is the
          // only negotiated rate it returns). Label the empty state as a KNOWN
          // platform limit, not a glitch, so a reader does not chase a missing
          // reading. iOS supplies both Rx and Tx via the Shortcut bridge.
          note: (a != null && !a.rxRateAvailable && a.rxRateMbps == null)
              ? 'Not exposed on macOS'
              : null,
        ),
        _DataRow(
          label: 'Usable capacity',
          value: _rate(result.usableWifiMbps),
          unit: 'Mbps',
          mono: true,
          note:
              '55% of ${WifiVsInternetEngine.rateBasisCaption(result.rateBasis)}',
        ),
        _DataRow(
          label: 'SNR',
          value: a?.snrDb?.toString(),
          unit: 'dB',
          mono: true,
          derived: a?.snrDerived ?? false,
        ),
        _DataRow(
          label: 'RSSI',
          value: a?.rssiDbm?.toString(),
          unit: 'dBm',
          mono: true,
        ),
        _DataRow(label: 'Channel', value: _channelValue(a?.channel), mono: true),
        _DataRow(label: 'Standard', value: a?.standard),
      ],
    );
  }

  /// Channel as a display string, or null when the channel is unknown. Channel
  /// 0 is the "no/unknown channel" sentinel several stacks return; it is NEVER a
  /// real Wi-Fi channel, so it renders as the honest "Unavailable" treatment via
  /// the null path rather than a misleading "0" (GL-005).
  static String? _channelValue(int? channel) {
    if (channel == null || channel == 0) return null;
    return channel.toString();
  }

  static String? _rate(double? mbps) {
    if (mbps == null) return null;
    final double r = (mbps * 10).round() / 10;
    return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  }
}

/// "Your internet" sub-card (absorbed verbatim from wifi_vs_internet_screen).
class _InternetSection extends StatelessWidget {
  const _InternetSection({required this.result});

  final QualityResult? result;

  @override
  Widget build(BuildContext context) {
    final QualityResult? r = result;
    final double? down = _value(r, MetricIds.download);
    final double? up = _value(r, MetricIds.upload);
    final double? avg = (down != null && up != null)
        ? (down + up) / 2
        : (down ?? up);

    return _SectionCard(
      title: 'Your internet',
      children: <Widget>[
        _DataRow(
          label: 'Download',
          value: _fmt(down),
          unit: 'Mbps',
          mono: true,
          trailing: _GradeChip(grade: _grade(r, MetricIds.download)),
        ),
        _DataRow(
          label: 'Upload',
          value: _fmt(up),
          unit: 'Mbps',
          mono: true,
          trailing: _GradeChip(grade: _grade(r, MetricIds.upload)),
        ),
        _DataRow(
          label: 'Averaged',
          value: _fmt(avg),
          unit: 'Mbps',
          mono: true,
          note: 'average of download and upload',
        ),
        _DataRow(
          label: 'Latency',
          value: _fmtMs(_value(r, MetricIds.latency)),
          unit: 'ms',
          mono: true,
          trailing: _GradeChip(grade: _grade(r, MetricIds.latency)),
        ),
        _DataRow(
          label: 'Jitter',
          value: _fmtMs(_value(r, MetricIds.jitter)),
          unit: 'ms',
          mono: true,
          trailing: _GradeChip(grade: _grade(r, MetricIds.jitter)),
        ),
        _DataRow(
          label: 'Loss',
          value: _fmtMs(_value(r, MetricIds.loss)),
          unit: '%',
          mono: true,
          trailing: _GradeChip(grade: _grade(r, MetricIds.loss)),
        ),
      ],
    );
  }

  static double? _value(QualityResult? r, String id) {
    final QualityMetric? m = r?.metric(id);
    return (m != null && m.isAvailable) ? m.value : null;
  }

  static QualityGrade _grade(QualityResult? r, String id) =>
      r?.metric(id)?.grade ?? QualityGrade.unavailable;

  static String? _fmt(double? mbps) => mbps?.toStringAsFixed(1);

  static String? _fmtMs(double? v) => v?.round().toString();
}

/// The §8.13 grade chip (absorbed from wifi_vs_internet_screen).
class _GradeChip extends StatelessWidget {
  const _GradeChip({required this.grade});

  final QualityGrade grade;

  /// DARK (§8.13): solid status fill + dark text. LIGHT (§8.20.4 Style A): the
  /// SOLID full-strength status hue fill + WHITE 700 label + WHITE glyph, no
  /// border. Returns (fill, border, label) per theme. The "unavailable" grade
  /// has no status hue, so it stays neutral in both themes.
  static (Color, Color?, Color) _colors(AppColorScheme c, QualityGrade grade) {
    if (c.isLight) {
      const Color white = Color(0xFFFFFFFF);
      switch (grade) {
        case QualityGrade.excellent:
        case QualityGrade.good:
          return (c.statusSuccess, null, white);
        case QualityGrade.fair:
          return (c.statusWarning, null, white);
        case QualityGrade.poor:
          return (c.statusDanger, null, white);
        case QualityGrade.unavailable:
          // Neutral solid fill (textSecondary #4A4A4A, white-on-fill 9.0:1).
          return (c.textSecondary, null, white);
      }
    }
    switch (grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return (c.statusSuccess, null, c.onPrimary);
      case QualityGrade.fair:
        return (c.statusWarning, null, c.onPrimary);
      case QualityGrade.poor:
        return (c.statusDanger, null, c.onPrimary);
      case QualityGrade.unavailable:
        return (c.surface2, c.borderStrong, c.textSecondary);
    }
  }

  /// §8.20.4 — the Material status glyph that reinforces the verdict word
  /// (so meaning is never carried by color alone).
  static IconData _glyph(QualityGrade grade) {
    switch (grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return Icons.check_circle;
      case QualityGrade.fair:
        return Icons.warning_amber_rounded;
      case QualityGrade.poor:
        return Icons.error;
      case QualityGrade.unavailable:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final (Color bg, Color? borderColor, Color fg) =
        _colors(colors, grade);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        // §8.20.4 Style A — light is a borderless solid-fill PILL; dark keeps its
        // control-radius solid fill (only dark "unavailable" carries a 1px
        // boundary off borderColor).
        borderRadius: BorderRadius.circular(
          colors.isLight ? AppRadius.pill : AppRadius.control,
        ),
        border:
            borderColor == null ? null : Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // §8.20.4 Style A — the solid-fill light pill carries a 16px WHITE
          // Material status glyph, so the verdict is reinforced by shape + word,
          // not color alone. Dark keeps its solid-fill chip with no glyph.
          if (colors.isLight) ...<Widget>[
            Icon(_glyph(grade), size: 16, color: fg),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Flexible(
            child: Text(
              grade.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(
                color: fg,
                // §8.20.4 / §8.20.3-A verdict word bumps to 700 in light.
                fontWeight: colors.isLight ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled surface1 card with a §8.1 hairline border (absorbed shell).
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // §1.3.1 — the section heading is marked as an SR heading so VoiceOver
          // / TalkBack heading-rotor navigation can land on it. SR-only; no
          // layout change. Applied once here so every _SectionCard ("Your Wi-Fi
          // link", "Your internet") inherits the heading semantic.
          Semantics(
            header: true,
            child: Text(
              title,
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
                fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          // §8.20.3-C #3 — a 4px vivid lime #A1CC3A FILL underline bar under the
          // section heading, on the white card surface. Decorative brand area
          // (the bold label above carries the meaning); the bar reads vivid as a
          // fill. Light only — no underline in dark (lime is the dark accent
          // already and the section label needs no extra bar there).
          if (colors.isLight) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          ...children,
        ],
      ),
    );
  }
}

/// One label → value data row (absorbed verbatim from wifi_vs_internet_screen):
/// a null value renders "Unavailable", each row is one semantic node, mono for
/// numerics, an optional trailing grade chip ellipsizes before overflow.
class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.label,
    required this.value,
    this.unit,
    this.mono = false,
    this.note,
    this.derived = false,
    this.trailing,
  });

  final String label;
  final String? value;
  final String? unit;
  final bool mono;
  final String? note;
  final bool derived;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText monoText =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final AppColorScheme colors = context.colors;

    final bool hasValue = value != null && value!.trim().isNotEmpty;
    final String shown = hasValue
        ? (unit == null ? value! : '${value!} $unit')
        : 'Unavailable';
    final Color valueColor =
        hasValue ? colors.textPrimary : colors.textSecondary;
    final TextStyle? valueStyle = (mono && hasValue)
        ? monoText.robotoMono.copyWith(color: valueColor)
        : text.bodyMedium?.copyWith(color: valueColor);

    final String labelSpoken = derived ? '$label, derived' : label;
    final String semanticLabel = note == null
        ? '$labelSpoken, $shown'
        : '$labelSpoken, $shown, $note';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Semantics(
        container: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          shown,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: valueStyle,
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: AppSpacing.xs),
                        trailing!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                note!,
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
// iOS-only optional Shortcut offer (D1 path) — soft, secondary, post-answer.
// ===========================================================================

class _ShortcutOfferCard extends StatelessWidget {
  const _ShortcutOfferCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Want a deeper Wi-Fi check?',
            style: text.titleSmall?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Add the companion Shortcut to let this app read your Wi-Fi '
            'details next time. Optional, and it only takes a minute.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: onOpen,
              child: const Text('Add the companion Shortcut'),
            ),
          ),
        ],
      ),
    );
  }
}
