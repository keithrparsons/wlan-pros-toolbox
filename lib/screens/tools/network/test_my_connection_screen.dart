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

import '../../../router/app_router.dart';
import '../../guides/guide_reader_screen.dart';
import '../../../services/network/cellular_data_cost.dart';
import '../../../services/network/wifi_connection_service.dart';
import '../../../services/network/analyze/analyze_engine.dart';
import '../../../services/network/analyze/analyze_input.dart';
import '../../../services/network/analyze/analyze_report_text.dart';
import '../../../services/network/analyze/analysis_finding.dart';
import '../../../services/network/connected_ap.dart';
import '../../../services/network/connection_check.dart';
import '../../../services/network/connection_comparison.dart';
import '../../../services/network/consumer_verdict.dart';
import '../../../services/network/dns_probe_service.dart';
import '../../../services/network/ip_geo_service.dart';
import '../../../services/network/network_details_service.dart';
import '../../../services/network/live_onboarding_service.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/wifi_details_bridge.dart';
import '../../../services/network/wifi_grading.dart';
import '../../../services/network/wifi_info_adapter.dart';
import '../../../services/network/wifi_info_service.dart' show LocationAuthStatus;
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
import 'analyze_results_screen.dart';
import 'cloud_apps_panel.dart';
import 'get_reading_icon.dart';
import 'setup_live_wifi_icon.dart';
import 'install_shortcut_sheet.dart';
import 'live_setup_card.dart';
import 'network_unavailable_view.dart';
import 'not_on_wifi_card.dart';

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
/// THE DISARM DECISION, AS A PURE FUNCTION — because it cannot be driven any other
/// way, and an undriveable rule is an unguarded one.
///
/// A widget test CANNOT reproduce "dispose() while backgrounded". A paused app does
/// not pump frames, so the unmount a real scene teardown performs never runs inside a
/// test body; dispose() fires later, at teardown, with the binding back at `resumed`.
/// Two successive widget-level attempts at this LOOKED right, passed, and were both
/// proven vacuous by hand-injected mutation — they passed identically against a rule
/// that disarmed unconditionally, i.e. against the exact defect they existed to catch.
///
/// So the rule is lifted out of the widget and pinned here, where it can be stated
/// exactly and tested exhaustively over every lifecycle state.
///
/// THE RULE. Disarm ONLY when we are demonstrably FOREGROUNDED, because only a
/// foregrounded user can choose to leave. Every other state — inactive, hidden,
/// paused, detached, or UNKNOWN — is a screen going away for reasons that are not the
/// user's choice, and in those cases the arm is the only surviving evidence that a run
/// was ever in flight.
///
/// A NULL STATE DELIBERATELY DOES NOT DISARM. Null means "we do not know", and the two
/// errors are not symmetric:
///   * disarm when we should not have → the user's destroyed run is NOT restored. That
///     is Keith's bug, unfixed.
///   * fail to disarm when we should have → the user is pulled back into a tool once,
///     inside the few seconds a run is armed. Annoying, self-correcting (the arm is
///     consumed on the way through), and bounded by the restore window.
/// The second is the error we can afford. On a real device the state is `resumed` from
/// the first frame, so this guards the unknown rather than a routine path.
@visibleForTesting
bool shouldDisarmOnDispose(AppLifecycleState? state) =>
    state == AppLifecycleState.resumed;

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
    this.connectionService,
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

  /// Injectable Wi-Fi connection probe for the MONEY question, used ONLY when no
  /// live sampler exists (live sampling off) so a render/copy test can honestly
  /// declare the link it is modelling. When a sampler is present it owns the probe
  /// (it also updates live as the user walks in/out of range). Production always
  /// has a sampler, so this seam is never consulted there.
  final WifiConnectionService? connectionService;

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

  /// Guards the first-run onboarding gate so it presents at most once per mount.
  /// Retained with [_maybeShowFirstRunOnboarding] for the inline opt-in path; the
  /// AUTO-FIRE was removed 2026-06-23 (native-first), but the gate logic stays so
  /// the one-time semantics are preserved if re-wired to a non-modal trigger.
  // ignore: unused_field
  bool _firstRunChecked = false;

  /// The shared live-RF sampler that feeds the "Wi-Fi signal" sparkline card.
  /// Continuous while the screen is open (macOS auto-polls; iOS streams via the
  /// companion Shortcut). Null on web / unsupported.
  WifiSignalSampler? _sampler;

  bool _running = false;
  String? _error;

  /// SET WHEN THIS SCREEN WAS MOUNTED TO TAKE OVER A RUN iOS DESTROYED.
  ///
  /// Holds the instant that run ARMED (fired its Shortcut). Two jobs, and both are
  /// load-bearing:
  ///
  ///   1. It tells [_run] this is a RESUME, so it must NOT fire the Shortcut again.
  ///      Firing is what backgrounds the app into Shortcuts, which is what let iOS
  ///      destroy the run in the first place. A resume that re-fires would be
  ///      destroyed again, resume again, fire again — AN INFINITE BOUNCE LOOP that
  ///      takes the phone away from the user entirely. This is the single most
  ///      dangerous thing in this change and [_adoptDeliveredIosRf] is its guard.
  ///
  ///   2. It DATES the evidence. The Shortcut's reading is sitting in the App Group,
  ///      but so is the stale one from the last time the phone was on Wi-Fi. Only a
  ///      payload stamped at or after this instant is a reading OF this run.
  ///
  /// Null on every ordinary open, which is why an ordinary open behaves exactly as
  /// it always has: it waits for the tap.
  DateTime? _resumedRunArmedAt;

  // Internet progress.
  QualityPhase _phase = QualityPhase.idle;
  double _fraction = 0;

  /// True when the engine has told us it no longer knows how long the current
  /// stage will take. The bar must then stop showing a percentage — a number that
  /// sits still for tens of seconds reads as a HANG, which is exactly how Keith
  /// read the frozen 0.99 the old ticker emitted. See [QualityProgress
  /// .indeterminate].
  bool _indeterminate = false;

  /// The measurement stream has CLOSED, and we are waiting on the Wi-Fi link read
  /// before the result can render (MEDIUM-2, round 5, 2026-07-14).
  ///
  /// `onDone` does `await linkFuture.timeout(8s)` BEFORE it flips [_running] false,
  /// and the progress card is gated on [_running] — so for up to EIGHT SECONDS after
  /// the run has actually finished, the user watched a bar frozen at 100%. The work
  /// is real (the link read has not landed), so the honest fix is to SAY so, not to
  /// tear the card down early and flash the idle screen at them.
  ///
  /// This is the most likely explanation for Keith's "still working" sighting, and I
  /// am NOT claiming it as the confirmed cause — Vera could not reproduce that, her
  /// hypothesis died to her own test, and inventing a culprit for an unreproduced
  /// report is how a fake fix gets shipped. This is a real defect I can see in the
  /// code and reproduce in a test; whether it is HIS defect is unproven.
  bool _finishing = false;

  // Results, populated when the run completes.

  /// The raw one-shot link read taken at test completion ([_readLink]). Off Wi-Fi
  /// this is the App Group's LAST STORED payload, which survives the phone leaving
  /// Wi-Fi — so it is NEVER rendered directly. The result body reads
  /// [_effectiveAp] / [_resultAp], which is gated on the run's own probe verdict.
  ConnectedAp? _ap;

  /// The RF snapshot THIS RESULT was computed from: [_ap] folded with the live
  /// sampler's reading, stamped in the run's `onDone` and enriched (never blanked)
  /// by late-arriving live RF. The SINGLE source the verdict, the technical
  /// section, the help-desk facts, the copy report, and Analyze all read, via
  /// [_effectiveAp]. Null when the check ran with no Wi-Fi link.
  ConnectedAp? _resultAp;

  /// macOS only: whether Location Services is authorized for this app. Since
  /// macOS 14, CoreWLAN withholds the SSID and BSSID unless the app holds
  /// Location authorization — every other RF field still resolves. So the
  /// SSID/BSSID empty state (in the copy report and the on-screen hint) can
  /// explain itself ("Location access needed") instead of a bare "Unavailable".
  /// Null before the first read / off macOS.
  bool? _macLocationAuthorized;

  /// macOS only: the TRI-STATE Location authorization, read WITHOUT a prompt at
  /// the start of a run. Drives whether the on-screen hint's button PROMPTS
  /// (notDetermined) or DEEP-LINKS to System Settings (denied / restricted), and
  /// whether the auto-prompt fires this run. Null before the first read / off
  /// macOS.
  LocationAuthStatus? _macNameAuth;

  /// macOS only: set once the proactive native Location prompt has been fired
  /// this screen-mount, so a run never spams the prompt on every check. macOS
  /// remembers the user's first response, so re-prompting is both pointless and
  /// jarring; after the first fire this stays true and subsequent runs read the
  /// remembered status without re-prompting (Keith: "One request only").
  bool _macLocationPromptFired = false;

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

  /// Whether the public-IP / ISP lookup OBTAINED a public IP this run — the ONLINE
  /// EVIDENCE the offline / captive-portal verdicts turn on. TRI-STATE, and that is
  /// the whole fix (round 5 CRITICAL, 2026-07-14):
  ///
  ///   * null  — the lookup has NOT ANSWERED yet (pending, or never fired). Assert
  ///             nothing: a healthy run mid-flight must not read as offline.
  ///   * true  — the lookup answered and returned a public IP.
  ///   * false — the lookup answered and NO public IP came back (a reported failure
  ///             OR a thrown timeout/transport error). This is the value the whole
  ///             engine was missing: a dead internet fails the lookup, and until now
  ///             that failure was DISCARDED and this stayed null forever, so
  ///             [OnlineEvidence.isOffline] (which needs `publicIpObtained == false`)
  ///             could never fire from the screen.
  ///
  /// [_ispInfo] is UNCHANGED — it is still populated ONLY on success, so the copy
  /// report's ISP section behaves exactly as before. This flag carries the NEGATIVE
  /// that [_ispInfo]'s null could not: "we asked and got no public IP" (`false`) vs
  /// "we have not asked yet" (`null`). The two-kinds-of-null distinction, one layer
  /// down. See [feedback_unsourced_is_not_invalid].
  bool? _publicIpObtained;

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

  /// iOS install-state: whether the companion "WLAN Pros Live" Shortcut has ever
  /// delivered a payload (so it is demonstrably installed). Read from the live
  /// sampler's honest App Group signal. Drives whether the couldn't-check Wi-Fi
  /// offer is the PROMINENT "Set up Live Wi-Fi" CTA (not yet set up) or the soft
  /// optional offer (set up, but this run could not read the link). False off
  /// iOS / before the sampler resolves.
  bool get _iosHasEverReceived => _sampler?.hasEverReceived ?? false;

  /// The LIVE "this device is demonstrably NOT on Wi-Fi" probe result, read from
  /// the live sampler. True only on a POSITIVE not-on-Wi-Fi verdict from
  /// [WifiConnectionService] (read its KNOWN LIMITS before relying on it); an
  /// ambiguous or failed read leaves it false, so a wired desktop and a
  /// Location-gated read are never falsely told they have no Wi-Fi (GL-005).
  /// False before the sampler resolves, and on every non-iOS source.
  ///
  /// This tracks the device RIGHT NOW, so it moves when the user joins or leaves
  /// Wi-Fi. The RESULT body must not read it directly — see [_resultNotOnWifi].
  bool get _notOnWifi => _sampler?.notOnWifi ?? false;

  /// THE MONEY ANSWER, AND THE ONLY THING THE CONSENT GATE READS (round 5).
  ///
  /// Separate from [_notOnWifi] and it FAILS THE OTHER WAY. [_notOnWifi] refuses to
  /// CLAIM a link it cannot prove (so it defaults false); this refuses to SPEND on a
  /// link it cannot prove (so it defaults [MeteredRisk.unknown], which ASKS).
  ///
  /// THE NO-SAMPLER FALLBACK IS PLATFORM-AWARE, AND IT HAS TO BE.
  ///
  /// A null sampler (live sampling off, `web`, `unsupported`) means we have measured
  /// NOTHING — and the round-4 gate's fatal habit was to read "nothing measured" as
  /// "safe to spend". So the fallback must NOT be `MeteredRisk.none`.
  ///
  /// But it must not be a blanket `unknown` either: that would prompt a WEB user, and
  /// a desktop with sampling disabled, about cellular data they have no radio to
  /// spend. "Fail closed" is a rule about PHONES; on a machine with no cellular
  /// modem there is no meter to trip, and a warning there is noise that teaches
  /// people to dismiss the one that matters.
  ///
  /// So it falls back to the PLATFORM fact — the same rule [WifiSignalSampler
  /// .meteredRisk] and [WifiConnectionService.isMeteredCapable] use. Every source is
  /// listed rather than defaulted, so a new one cannot silently inherit "free to
  /// spend" from a `default:` clause.
  /// The money answer, or NULL when the probe has not reported yet.
  ///
  /// THE GATE AND THE RENDER READ THIS DIFFERENTLY, AND THEY MUST.
  ///   * [_meteredRisk] collapses null to `unknown` — FAIL CLOSED. Nothing spends.
  ///   * [_showCostUi] collapses null to "say nothing" — because before the first
  ///     probe returns, EVERY device reads `unknown`, and a card driven off that
  ///     would flash a cellular-data warning at every user on their home Wi-Fi.
  ///
  /// A tap made during that window is still safe: [_run] AWAITS the probe and the
  /// `spendData` chokepoint downgrades it. That is exactly the "walked out of Wi-Fi
  /// range" case, and it is proven in `spend_chokepoint_test.dart`.
  /// The money answer resolved by the SCREEN'S OWN probe, used when there is no live
  /// sampler to own it (live sampling off). Null until [_resolveScreenRisk] returns.
  MeteredRisk? _screenRisk;

  MeteredRisk? get _resolvedRisk {
    final WifiSignalSampler? s = _sampler;
    if (s != null) return s.meteredRiskResolved ? s.meteredRisk : null;
    // NO LIVE SAMPLER. The money question does not belong to the live-RF feed, so
    // the screen resolves it itself (see [_resolveScreenRisk], kicked off in
    // initState). Null until that probe returns — the gate reads that as `unknown`
    // (fail closed) and the card stays hidden until we actually know. On a desktop /
    // web source the probe is skipped and this is `none` from frame one.
    switch (_source) {
      case WifiInfoSource.iosShortcuts:
      case WifiInfoSource.androidWifiManager:
        return _screenRisk;
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.windowsNativeWifi:
      case WifiInfoSource.web:
      case WifiInfoSource.unsupported:
        // No cellular radio this app can detect. `none` is the final answer and it
        // needs no probe, so it is RESOLVED from frame one.
        return MeteredRisk.none;
    }
  }

  /// Probes the money question ONCE from the screen's own connection service, for
  /// the no-sampler configuration. Never runs in production (a sampler always
  /// exists there); a render/copy test injects a [connectionService] to declare the
  /// link it models. A failed read resolves to `unknown` (fail closed), never free.
  Future<void> _resolveScreenRisk() async {
    if (_sampler != null) return;
    final bool phone = _source == WifiInfoSource.iosShortcuts ||
        _source == WifiInfoSource.androidWifiManager;
    if (!phone) return;
    final WifiConnectionService svc =
        widget.connectionService ?? WifiConnectionService();
    final LinkVerdict v = await svc.read();
    if (!mounted) return;
    setState(() => _screenRisk = v.meteredRisk);
  }

  /// THE GATE'S view: an unprobed link is [MeteredRisk.unknown], which ASKS.
  MeteredRisk get _meteredRisk => _resolvedRisk ?? MeteredRisk.unknown;

  /// Whether the app must ASK before it spends a byte. FAIL CLOSED: true unless the
  /// link is PROVEN free (confirmed Wi-Fi, a confirmed wired link, or a platform
  /// with no cellular radio to bill).
  ///
  /// Read by [_run]'s chokepoint and by [_autoStart] — BOTH of which await the probe
  /// first, so neither ever evaluates this in the unresolved window.
  bool get _needsConsent => _meteredRisk.requiresConsent;

  /// THE RENDER'S view: show the cost UI only once we actually KNOW.
  ///
  /// An unresolved link shows NOTHING — no warning, no decline path, no "(may use
  /// data)" label — and the consent tap is not recorded either, because the user has
  /// not been shown a cost to consent to. A warning that fires on every launch is not
  /// a safety feature; it teaches people to dismiss the one that matters.
  bool get _showCostUi => (_resolvedRisk ?? MeteredRisk.none).requiresConsent;

  /// The risk the pre-run card was last BUILT with — including the null that means
  /// "not probed yet". Lets [_onSamplerChanged] rebuild whenever the answer moves,
  /// in EITHER direction: null → none (stand down), null → unknown (raise the card),
  /// unknown → none (a user walking back into Wi-Fi range).
  MeteredRisk? _renderedRisk;

  /// The not-on-Wi-Fi state AS OF THE COMPLETED CHECK — the flag every part of
  /// the RESULT body reads (the verdict, the technical section, the help-desk
  /// facts, the copy report, the capture affordances).
  ///
  /// WHY THE RESULT NEEDS ITS OWN FLAG (cold-eyes F4, 2026-07-13). [_notOnWifi] is
  /// live. Run a check at home on Wi-Fi, walk to the car, let the app resume: the
  /// resume re-probes, the live flag flips true, and a body wired to it would blank
  /// every Wi-Fi row of a reading that was LEGITIMATELY TAKEN on Wi-Fi — while the
  /// verdict card, which is not recomputed on resume, still read "It's your Wi-Fi".
  /// The screen contradicted itself and threw away a true measurement.
  ///
  /// A completed check is a TIMESTAMPED REPORT ("Tested: <time>"), not a live
  /// readout. So the report is FROZEN against the probe state of its own run:
  /// stamped once in the run's `onDone` and never moved by a later resume.
  /// Recomputing it instead would replace a true finding ("your Wi-Fi link was the
  /// limiter at 14:32") with a false one ("there was no Wi-Fi to check"), which is
  /// the same class of lie this whole fix exists to remove. The LIVE Wi-Fi-signal
  /// card keeps reading [_notOnWifi] and honestly says "You're not connected to
  /// Wi-Fi" right now, so the two coexist without contradicting each other: one is
  /// dated, one is live. "Run again" re-stamps the report.
  ///
  /// False until the first check completes.
  bool _resultNotOnWifi = false;

  /// EXPLICIT consent to spend cellular data on the speed test, for this screen.
  ///
  /// Set ONLY by the user tapping the primary button while off Wi-Fi — the button
  /// whose own label carries the cost ("Check My Connection (uses data)"), directly
  /// beneath the warning that states it. Never inferred, never defaulted, never set
  /// by a caller. [_run]'s chokepoint reads it, so a run that was never consented to
  /// cannot include the data-hungry stages no matter who started it.
  bool _throughputConsented = false;

  /// Whether THIS result's run skipped the data-hungry speed test because the
  /// user declined the cellular-data cost. Stamped once in the run's `onDone`,
  /// exactly like [_resultNotOnWifi] and for the same reason (cold-eyes F4): the
  /// report is dated to its own run, and no later recompute may re-derive it.
  bool _resultSpeedTestSkipped = false;

  /// The cellular data the speed test will consume.
  ///
  /// THE SENTENCE AND ITS DERIVATION NOW LIVE IN ONE PLACE:
  /// [kCellularDataWarning] (`services/network/cellular_data_cost.dart`), which
  /// derives every figure from the named `ThroughputProbe` constants and is
  /// re-derivation-guarded by a test. Network Quality shows the same sentence.
  ///
  /// The old hedged range ("roughly 50 MB ... 500 MB or more") is gone. It was
  /// BOTH stale — its "about 30 seconds" was two 15 s download windows, and the
  /// RPM window no longer runs on cellular — AND unsourceable, which on a consent
  /// dialog is the real fault: a user is approving a spend and a fuzzy number
  /// cannot be checked.
  ///
  /// THE CONSENT TAP IS UNCHANGED. Less cost is not no cost: download and upload
  /// still spend real money, so the warning, the decline path and the awaited
  /// `spendData` chokepoint all stay exactly as they were. Only the NUMBER moved.
  ///
  /// The historical derivation notes below are kept because they record WHY an
  /// earlier revision's "300 Mbps -> ~1.1 GB" was unreachable:
  ///   * `ThroughputProbe.maxDuration` = 15 s. `downloadStreamCount` (default 5)
  ///     concurrent download streams LOOP sized requests back-to-back until that
  ///     window closes (`_downloadOnce`'s do/while), so this stage can transfer
  ///     roughly `link rate x 15 s` — several summed flows are what fill a fast
  ///     link.
  ///   * The responsiveness (RPM) probe's load generator is ANOTHER full-window
  ///     download (`runResilientRpmLoad`) — a second ~15 s window. It is
  ///     SINGLE-FLOW ("one healthy single-flow load for the whole RPM window").
  ///   * Upload is the only capped one: `uploadBytes` = 10 MB.
  ///
  /// SO THE APP DOWNLOADS FOR ABOUT 30 SECONDS, BUT ONLY THE FIRST ~15 s CAN RUN AT
  /// THE FULL LINK RATE. A previous revision of this comment multiplied the WHOLE
  /// 30 s by the link rate and printed `300 Mbps -> ~1.1 GB`. That figure is
  /// UNREACHABLE, and this codebase says why in its own words: a single TCP stream
  /// "is bandwidth-delay-product limited and cannot fill a fast link, so several
  /// summed concurrent flows are required to measure true capacity"
  /// (`throughput_probe.dart`, `downloadStreamCount`). The RPM stage is exactly
  /// that single stream, so it transfers materially LESS than the parallel stage on
  /// a fast link — and by an amount this code cannot know in advance.
  ///
  /// The honest bound is therefore: at least `rate x 15 s / 8` from the parallel
  /// stage, plus an unknown-but-smaller single-flow contribution, plus 10 MB up.
  ///   10 Mbps  -> at least ~19 MB, and comfortably under 50 MB
  ///   300 Mbps -> at least ~560 MB
  ///
  /// SCOPE (updated 2026-07-14 — the previous note here is now OUT OF DATE and
  /// said the opposite). It used to read "THIS GATE IS iOS-ONLY ... a cellular
  /// Android phone gets NO warning". That hole was CLOSED in commit 4306b75:
  /// `WifiConnectionStatus.notOnWifi` is now a real MEASURED verdict on Android
  /// too (`ConnectivityManager` naming TRANSPORT_CELLULAR on the active network),
  /// not an iOS-only inference. macOS and Windows remain deliberately unreachable
  /// — there, an absent Wi-Fi address is genuinely ambiguous (a wired desktop),
  /// so no honest negative exists to assert.
  ///
  /// ROUND 5: the `_kCellularDataWarning` alias that used to sit here is GONE. There
  /// is no longer ONE warning to alias — the screen must choose between the
  /// confirmed-cellular sentence and the honest "we can't tell" sentence, and that
  /// choice belongs to [dataCostWarningFor] so neither screen can pick wrong.

  /// Whether offering the iOS companion-Shortcut capture path is HONEST for the
  /// result on screen.
  ///
  /// THE SECOND WRONG NULL (cold-eyes F2, 2026-07-13). Gating the RF DATA at
  /// [_effectiveAp] was not enough: [_iosRfCaptured] is DERIVED from it, so a null
  /// [_effectiveAp] made "RF captured" false — and false there does not mean
  /// "there is no Wi-Fi", it means "tap Capture Wi-Fi details and we'll read it
  /// through the companion Shortcut". A cellular-only iPhone was shown that button
  /// (:_WifiLinkSection), that note in the copy report, that offer card, and that
  /// Analyze finding (R-31). No Shortcut can read a Wi-Fi link that does not
  /// exist — it is the SAME wrong-kind-of-null failure in a new costume.
  ///
  /// So the data has one chokepoint ([_effectiveAp]) and the ADVICE has this one.
  /// Every capture/Shortcut affordance in the result body reads THIS getter, so a
  /// new one cannot be added without passing the gate. Off Wi-Fi there is nothing
  /// to capture, and the honest "You're not connected to Wi-Fi" verdict already
  /// tells the user what to do instead: join a network.
  bool get _canOfferWifiCapture => _isIos && !_resultNotOnWifi;

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
      case WifiInfoSource.windowsNativeWifi:
        return 'Windows';
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
    _source = widget.sourceOverride ?? WifiInfoSourceResolver.resolve();

    // WEB GATE (launch-critical, 2026-07-06). The browser has no dart:io, and
    // several of the native services constructed below touch it at CONSTRUCTION
    // time — NetworkDetailsService's field initializer reads `Platform.isAndroid`,
    // which throws `Unsupported operation: Platform._operatingSystem` on web and
    // blanks the whole screen before build() ever runs. build() -> _body()
    // already returns NetworkUnavailableView on web (the same gate every other
    // network tool uses), and NONE of the late-final services below are ever read
    // on that path (_run / the fetch helpers are the only readers, and they never
    // fire without a Check button, which the web body never shows). So we bail out
    // HERE, before constructing them. Native platforms are byte-for-byte
    // unaffected: kIsWeb is false, so the full setup runs exactly as before.
    if (!NetworkSupport.activeNetworkSupported ||
        _source == WifiInfoSource.web) {
      return;
    }

    _ipGeo = widget.ipGeoService ?? IpGeoService();
    _dnsProbe = widget.dnsProbeService ?? DnsProbeService();
    _netDetailsService =
        widget.networkDetailsService ?? NetworkDetailsService();
    switch (_source) {
      case WifiInfoSource.macosCoreWlan:
        _macAdapter = widget.macAdapter ?? MacWifiInfoAdapter();
      case WifiInfoSource.androidWifiManager:
        _macAdapter = widget.macAdapter ?? AndroidWifiInfoAdapter();
      case WifiInfoSource.windowsNativeWifi:
        _macAdapter = widget.macAdapter ?? WindowsWifiInfoAdapter();
      case WifiInfoSource.iosShortcuts:
        _iosBridge = widget.iosBridge ?? WiFiDetailsBridge();
        // Record this as the origin tool so a missing-Shortcut x-error routes the
        // user back HERE (and the recovery card) instead of the home strand.
        _iosBridge!.setLiveOriginRoute(AppRouter.testMyConnection);
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
            _source == WifiInfoSource.windowsNativeWifi ||
            _source == WifiInfoSource.iosShortcuts)) {
      _sampler = widget.sampler ??
          WifiSignalSampler(
            source: _source,
            macAdapter: _macAdapter,
            iosBridge: _iosBridge,
          );
      WidgetsBinding.instance.addObserver(this);
      // Resolve the native identity first, then load — so a known SSID is a
      // definitive "on Wi-Fi" signal on the first connection probe (absence is
      // never read as "not on Wi-Fi"). The fetch is async; the load passes
      // whatever has resolved, and the resume path re-passes it later.
      _fetchIosSecurity().then(
        (_) => _sampler?.load(nativeSsid: _nativeSsid),
      );
      // Keep the screen's own copy/technical/capture-affordance state in sync
      // with the live stream: [_effectiveAp] and [_iosRfCaptured] read the
      // sampler's latest reading, so when a late live sample lands AFTER the run
      // completed, this lightweight rebuild flows that RF into the technical
      // Wi-Fi sub-card and clears the "not captured" note. The live sparkline
      // card has its own AnimatedBuilder; this is for the rest of the screen.
      _sampler!.addListener(_onSamplerChanged);
      // AUTO-START THE LIVE CAPTURE (item #8).
      //
      // macOS / Android source their live feed from NATIVE polling (CoreWLAN /
      // WifiManager snapshots on a timer, no app switch), so they auto-start
      // cleanly on screen entry — the sparklines begin filling as soon as the
      // first sample lands, with no tap. This holds whether the screen was
      // reached by tapping "Check My Connection" or via the home hero's auto-run.
      //
      // iOS sources its live feed from the Shortcuts bridge: start() fires the
      // companion "WLAN Pros Live" Shortcut, which SWITCHES to the Shortcuts app.
      // Firing that on MERE SCREEN ENTRY would bounce a user who is only browsing
      // straight out of the app, so we do NOT fire it here. Instead the auto-fire
      // is tied to RUNNING THE TEST (Keith's "no tap" request): [_run] calls
      // [_autoCaptureIosRf], which fires the Shortcut once at test start, settles,
      // and retries once if empty — so a normal Check My Connection captures RF
      // automatically and it appears both on screen and in the copy, while a user
      // who never starts a test is never bounced. The manual Start / "Capture
      // Wi-Fi details" affordance remains the fallback (GL-008: build to the
      // platform; the single deliberate kickoff is what the bridge can honor).
      //
      // macOS, Android, and Windows all source the live feed from NATIVE polling
      // (CoreWLAN / WifiManager / wlanapi.dll snapshots on a timer, no app
      // switch), so they auto-start cleanly on screen entry; only iOS waits for
      // the deliberate kickoff above.
      // TODO(windows-verify): confirm the wlanapi.dll poll loop ticks against a
      // real radio on the June-26 device pass (mapping logic is unit-tested; the
      // FFI read itself only executes on Windows).
      if (_source == WifiInfoSource.macosCoreWlan ||
          _source == WifiInfoSource.androidWifiManager ||
          _source == WifiInfoSource.windowsNativeWifi) {
        _sampler!.start();
      }
    }

    // NATIVE-FIRST (2026-06-23, Keith): opening the front door must NOT auto-pop
    // the companion-Shortcut setup sheet. A casual user gets an immediate, useful
    // native result (network name, BSSID, security, internet speed) with zero
    // modal prompts; the path to live RF is the inline, non-modal affordance only
    // (the LiveSetupCard / LiveRfLockedCard, and the About-screen "Set up live
    // Wi-Fi" row). The former auto-fire of [_maybeShowFirstRunOnboarding] (a modal
    // bottom sheet, scheduled post-frame) was the forced gate that bounced casual
    // users before they saw any result. The method and the one-time gate are kept
    // intact and stay reachable via the inline opt-in card (see
    // [_openShortcutSheet]), so the recovery path and the 1.5.5 double-prompt fix
    // continue to work — only the AUTO-FIRE is removed.

    // Resolve the MONEY question when no live sampler owns it (live sampling off).
    // No-op in production and on desktop sources; see [_resolveScreenRisk].
    unawaited(_resolveScreenRisk());

    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoStart();
      });
    }

    // THE SCENE-TEARDOWN RESUME (2026-07-14, Keith device round 6).
    //
    // This screen may have been mounted NOT by a user tap, but by the navigation
    // gate putting the user back after iOS destroyed the scene out from under a run
    // that was already going. The user tapped "Check My Connection" one scene ago;
    // they are owed a RESULT, not a reset screen. See [_maybeResumeInterruptedRun].
    //
    // Post-frame so the sampler's construction above has completed and the resume can
    // drive a fully-built screen.
    if (_isIos) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeResumeInterruptedRun();
      });
    }
  }

  /// TAKES OVER A RUN THAT iOS DESTROYED MID-FLIGHT.
  ///
  /// Keith: "Click on Check My Connection, and it opens the Shortcut for a second,
  /// then RETURNS TO THE HOME SCREEN. Doesn't finish Test My Connection at all."
  ///
  /// Firing the companion Shortcut backgrounds the app into the Shortcuts app, and
  /// iOS may tear down and rebuild the UIScene while we are gone. Flutter restarts at
  /// its initial (home) route and the whole Dart heap dies with it — this screen, its
  /// state, and the in-flight measurement. The navigation gate
  /// ([LiveErrorNavGate._restoreInterruptedRun]) puts the user back HERE; this method
  /// gives them back their RUN.
  ///
  /// WHAT "RESUME" CAN AND CANNOT MEAN, STATED HONESTLY. The throughput measurement's
  /// TCP streams died with the heap. They cannot be continued, and this does not
  /// pretend to: it RE-RUNS the measurement. What genuinely survives is the thing the
  /// run had gone to Shortcuts FOR — the RF reading, written to the App Group before
  /// the scene died. So the resumed run adopts that reading (never re-firing to get
  /// it) and re-measures the internet, and the user ends up holding the result they
  /// asked for.
  ///
  /// If the reading did NOT land, the run still completes — with no RF, no fabricated
  /// value, and no hang (GL-005). An honest partial result beats a spinner.
  Future<void> _maybeResumeInterruptedRun() async {
    final WiFiDetailsBridge? bridge = _iosBridge;
    // A run already in flight on this fresh screen (autoStart) needs no resuming.
    if (bridge == null || _running) return;

    final PendingLiveRun? pending = await bridge.pendingLiveRun();
    if (pending == null || !mounted) return;
    // Someone else's run (Wi-Fi Information, Cellular). Not ours to take over.
    if (pending.route != AppRouter.testMyConnection) return;

    // An arm older than the restore window is not a run any more — iOS killed the
    // app and the user reopened it later. Reap it and behave like a normal open.
    if (!pending.isFresh()) {
      await bridge.clearLiveRun();
      return;
    }

    // ONE ARM, ONE RESUME — AND THE ARM IS CONSUMED *BEFORE* THE RUN STARTS.
    //
    // This ordering is the second half of the anti-bounce-loop guard. Even if the
    // resumed run were somehow interrupted again, there is no arm left to restore
    // from, so the app cannot ping-pong. It degrades to the honest old behavior (the
    // user lands on Home and taps again) rather than to an infinite loop. A resume
    // that re-armed itself would be a machine for taking someone's phone away.
    await bridge.clearLiveRun();
    if (!mounted) return;

    _resumedRunArmedAt = pending.armedAt;
    // The SAME chokepoint every other caller passes through — it awaits the
    // connection probe and then decides `spendData` for itself. A resumed run gets
    // NO special dispensation to spend cellular data: `_throughputConsented` died
    // with the scene, so on a metered link this re-asks rather than assuming a
    // consent it cannot prove was given. Consent is a fact about a session, never a
    // durable grant. (In practice an armed run implies we were ON WI-FI when it
    // fired — off Wi-Fi the Shortcut is never fired at all — so this is a belt on
    // top of braces, which is exactly where a consent check belongs.)
    await _run(includeThroughput: true);
  }

  /// The AUTO-START entry: the home screen's "Check My Connection" hero
  /// (home_screen.dart → app_router.dart:716 → `autoStart: true`).
  ///
  /// IT CANNOT JUST CALL [_run] (round-4 P0, 2026-07-14). It used to, and that
  /// made the app's single most-travelled path spend a cellular user's data on a
  /// ~30-second full-rate download with no warning, no decline path, and no
  /// consent — the same screen and the same tap that produced Keith's original
  /// bug report.
  ///
  /// AND FRAME ONE IS TOO EARLY TO KNOW. [_notOnWifi] reads the sampler, which
  /// settles a few hundred ms after `initState`, while this post-frame callback
  /// fires on FRAME ONE. So on frame one [_notOnWifi] is still `false`, and a
  /// consent check merely PLACED inside [_run] would read "on Wi-Fi" and wave the
  /// run through. The probe has to be AWAITED, not read.
  ///
  /// OFF WI-FI WE DO NOT RUN AT ALL, rather than running without throughput. Both
  /// spend zero data, but stopping renders the pre-run screen with the cost and
  /// BOTH choices, so the user can still opt INTO the speed test. Silently
  /// downgrading the run would withhold a feature and give them no way to ask for
  /// it. On Wi-Fi nothing changes: the full check fires immediately, as always.
  ///
  /// THE RESIDUAL NAMED HERE WAS THE EXPLOIT (round 5, 2026-07-14). This doc used
  /// to end: "only a POSITIVE not-on-Wi-Fi verdict stops the run. An `unknown` probe
  /// (a wired Mac, an ambiguous read) auto-runs exactly as before — the alternative
  /// would stop and interrogate every desktop user about cellular data they are not
  /// spending."
  ///
  /// The stated worry was RIGHT, and the conclusion drawn from it was WRONG. A wired
  /// desktop must indeed never be interrogated — but "an ambiguous read" is not a
  /// desktop. It is also a cellular iPhone whose `en0` holds a link-local, and a
  /// cellular Android phone behind a VPN, and this is the app's PRIMARY ENTRY POINT
  /// running with `autoStart: true`. Opening the app spent their money, with zero
  /// taps and nothing to consent to.
  ///
  /// The desktop is protected WHERE THAT FACT IS ACTUALLY KNOWN — in
  /// [WifiConnectionService.isMeteredCapable], which resolves every desktop to
  /// [MeteredRisk.none] BY PLATFORM, not by hoping an ambiguous probe means "safe".
  /// So the run now stops on anything not PROVEN free, and the desktop still never
  /// sees a prompt.
  Future<void> _autoStart() async {
    await _retryConnection();
    if (!mounted) return;
    if (_needsConsent) {
      // Zero bytes move. Rebuild so the pre-run screen shows the data-cost
      // warning and both choices; the user decides.
      setState(() {});
      return;
    }
    _run(includeThroughput: true);
  }

  /// Re-runs the whole check from the RESULT screen's "Run again" control.
  ///
  /// This was `onRunAgain: _run` — a tear-off that rode the old default-true
  /// parameter, so "Run again" on a cellular result re-spent the user's data
  /// without consent too. It now states its request explicitly, and [_run]'s
  /// chokepoint downgrades it when the user has not consented on this screen.
  void _rerun() => _run(includeThroughput: true);

  /// iOS first-run: fires the unmissable one-time "enable live Wi-Fi" sheet on
  /// the first open of the front door, gated by the SAME honest composite signal
  /// wifi-info uses — the app has NEVER received a Live payload AND the sheet has
  /// not been shown before. Marks the sheet seen the instant it is presented so
  /// it never nags again (the persisted flag plus the App Group hasEverReceived
  /// signal make this truly one-time across every live tool). No-op off the iOS
  /// source. Never throws.
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
    // second sheet, and so it stays one-time even if the user dismisses it.
    await svc.markOnboardingSeen();
    if (!mounted) return;
    await _openShortcutSheet();
  }

  /// Rebuilds the screen when the live sampler reports a new reading, so the
  /// parts of the result body that read [_effectiveAp] / [_iosRfCaptured] (the
  /// technical Wi-Fi sub-card, the capture affordance, and any copy taken right
  /// after) reflect late-arriving live RF — keeping "what's on screen is what's
  /// copied" true even when the stream's first sample lands after the run
  /// completes. Cheap: only fires while results are shown, and only flips
  /// already-rebuilt-on-stream state. No-op when unmounted or while idle (no
  /// verdict yet means nothing reads the RF).
  void _onSamplerChanged() {
    if (!mounted) return;
    // Rebuild for live RF updates while results are shown (verdict != null), AND
    // whenever the missing-Shortcut recovery state is set — so the recovery card
    // surfaces on the "Check My Connection" hero path even before/without a verdict
    // (Keith device round 5: the hero Check produced no verdict, so the recovery,
    // which had only lived in the verdict-gated live-signal card, never showed).
    final WifiSignalSampler? s = _sampler;
    final bool recovery = (s?.shortcutMissing ?? false) || (s?.triggerError ?? false);
    // ...AND whenever the connection probe says we are off Wi-Fi, even with no
    // verdict yet (Keith, 2026-07-13). The PRE-RUN action card now depends on
    // [_notOnWifi]: it carries the cellular-data warning and the "check without
    // the speed test" decline path. The probe settles a few hundred ms AFTER
    // initState, so without this the card would build once with `notOnWifi: false`
    // and never rebuild — and the warning would silently never appear, which is
    // exactly the failure the warning exists to prevent. Caught by pumping the
    // real screen and reading the pre-run text, not by reasoning about it.
    // ...AND WHENEVER THE MONEY ANSWER CHANGES AT ALL — IN EITHER DIRECTION.
    //
    // THIS LINE IS A BUG I INTRODUCED AND MY OWN CONTROL TEST CAUGHT (round 5).
    //
    // The first cut read `if (_verdict == null && !recovery && !needsConsent) return;`
    // — a straight port of the old `!notOnWifi` version. It rebuilt when the card
    // needed to APPEAR and never when it needed to DISAPPEAR, which was harmless
    // while the flag started at `false` (nothing shown) and only ever rose.
    //
    // [_meteredRisk] starts at `unknown`, WHICH MEANS THE CARD IS SHOWN FROM FRAME
    // ONE. When the probe settles a few hundred ms later and says "Wi-Fi, free", the
    // early-return fired — `needsConsent` was now false — and the screen NEVER
    // REBUILT. So a Wi-Fi user who opened Test My Connection from the tool list
    // (no `autoStart`, so no other rebuild) sat looking at a cellular-data warning
    // and a "may use data" button, forever, on their home Wi-Fi.
    //
    // A fail-closed default is only honest if the screen can also STAND DOWN. Track
    // the risk we actually RENDERED and rebuild on any change, both ways.
    final MeteredRisk? risk = _resolvedRisk;
    final bool riskChanged = risk != _renderedRisk;
    _renderedRisk = risk;
    if (_verdict == null && !recovery && !riskChanged) return;

    // ENRICH THE RESULT SNAPSHOT, NEVER BLANK IT (cold-eyes F4).
    //
    // The sampler's first sample can land AFTER the run completes, and the copy
    // report must serialize exactly the RF the sparklines show — so late live RF
    // is folded into the result snapshot here. But the fold is one-way: when the
    // sampler's reading goes NULL (the phone left Wi-Fi after the check, so the
    // controller stops handing out its stored payload), we KEEP the snapshot the
    // completed check produced. A reading taken on Wi-Fi stays a true, timestamped
    // reading; it is not retroactively deleted because the user walked to the car.
    //
    // A check that ran with NO Wi-Fi ([_resultNotOnWifi]) is never enriched: there
    // was no link, so there is nothing a late sample could be a sample OF.
    if (_verdict != null && !_resultNotOnWifi && s?.latest != null) {
      _resultAp = _mergeWithLive(_ap);
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final WifiSignalSampler? sampler = _sampler;
    if (sampler == null) return;
    if (state == AppLifecycleState.resumed) {
      // Re-read the native identity then re-run the connection probe + load, so a
      // user who joined Wi-Fi while away advances out of the not-on-Wi-Fi state.
      _fetchIosSecurity().then((_) => sampler.load(nativeSsid: _nativeSsid));
      sampler.resumeMac();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      sampler.pauseMac();
    }
  }

  /// THE DISARM DECISION, AS A PURE FUNCTION — because it cannot be driven any other
  /// way, and an undriveable rule is an unguarded one.
  ///
  /// A widget test CANNOT reproduce "dispose() while backgrounded". A paused app does
  /// not pump frames, so the unmount that a real scene teardown performs never runs
  /// inside the test body; `dispose()` fires later, at teardown, with the binding back
  /// at `resumed`. Two successive attempts at a widget-level test for this LOOKED
  /// right, passed, and were both proven vacuous by hand-injected mutation — they
  /// passed identically against a version of this rule that disarmed unconditionally,
  /// i.e. against the exact defect they existed to catch.
  ///
  /// So the rule is lifted out of the widget and pinned here, where it can be stated
  /// exactly and tested exhaustively over every lifecycle state (see
  /// test/screens/tools/network/test_my_connection_scene_rebuild_resume_test.dart).
  ///
  /// THE RULE. Disarm ONLY when we are demonstrably FOREGROUNDED, because only a
  /// foregrounded user can choose to leave. Every other state — paused, inactive,
  /// hidden, detached, or UNKNOWN — is a screen going away for reasons that are not
  /// the user's choice, and in those cases the arm is the only evidence that a run was
  /// in flight.
  ///
  /// A NULL STATE DELIBERATELY DOES NOT DISARM. Null means "we do not know", and the
  /// two errors are not symmetric:
  ///   * disarm when we should not have → the user's destroyed run is NOT restored.
  ///     That is Keith's bug, unfixed.
  ///   * fail to disarm when we should have → the user is pulled back into a tool once,
  ///     during the few seconds a run is armed. Mildly annoying, self-correcting (the
  ///     arm is consumed on the way through), and bounded by the restore window.
  /// The second is the error we can afford. On a real device the state is `resumed`
  /// from the first frame, so this is a guard against the unknown, not a routine path.
  @override
  void dispose() {
    // ========================================================================
    // THE DISCRIMINATOR: DID THE USER LEAVE, OR DID iOS TAKE THE SCENE?
    //
    // Both look identical from inside dispose(). The screen is going away either
    // way. But the correct response is opposite:
    //   * user tapped Back / switched tools → DISARM. Dragging someone back into a
    //     screen they deliberately left is the app hijacking their navigation.
    //   * iOS tore down the UIScene mid-run → LEAVE IT ARMED. That arm is the only
    //     surviving evidence that Keith is owed a result.
    //
    // The APP'S LIFECYCLE STATE separates them cleanly. A user can only tap Back
    // while looking at the app, so a deliberate exit disposes with the app RESUMED.
    // A scene teardown happens while we are backgrounded in the Shortcuts app, so it
    // disposes (if it disposes at all) with the app paused / inactive / hidden /
    // detached — never resumed.
    //
    // It also fails in the SAFE direction on the ambiguous case. If iOS kills the
    // isolate outright, dispose never runs at all, and the arm survives — which is
    // exactly what we want. The only way to lose a real run here is for iOS to
    // destroy a foregrounded scene, which is not a thing it does.
    // ========================================================================
    if (shouldDisarmOnDispose(WidgetsBinding.instance.lifecycleState)) {
      _iosBridge?.clearLiveRun();
    }
    _sub?.cancel();
    if (_sampler != null) {
      WidgetsBinding.instance.removeObserver(this);
      _sampler!.removeListener(_onSamplerChanged);
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
          // macOS LOCATION AUTO-PROMPT (2026-06-15, Keith reversal): macOS 14+
          // withholds the SSID/BSSID until the app holds Location authorization.
          // The prior round deliberately never prompted (only the NAME needs
          // Location, never the rate-derived verdict); Keith now wants the app to
          // proactively surface the native "Allow Location" prompt so he need not
          // dig into System Settings. RUNNING the test is the contextual moment
          // of clear intent, so we fire the prompt HERE — but ONLY when:
          //   1. the source gates the name behind a permission, AND
          //   2. the status is `notDetermined` (PROMPTABLE — a denied/restricted
          //      status cannot raise a dialog; the on-screen hint deep-links to
          //      System Settings instead), AND
          //   3. we have not already fired the prompt this screen-mount
          //      (`_macLocationPromptFired`) — macOS remembers the first answer,
          //      so re-prompting every run would be both pointless and jarring.
          // The prompt is fired BEFORE the snapshot read (request at/just-before
          // the run starts, not mid-results). We never BLOCK the verdict on the
          // choice: whatever the user picks, we then read the snapshot and the
          // rate-derived verdict proceeds; only the NAME depends on the grant.
          LocationAuthStatus auth = await adapter.nameAuthorizationStatus();
          if (adapter.gatesNameBehindPermission &&
              auth.isPromptable &&
              !_macLocationPromptFired) {
            _macLocationPromptFired = true;
            await adapter.requestNamePermission();
            if (!mounted) return null;
            // Re-read the (now-resolved) status so the on-screen hint + copy
            // report reflect the user's choice without waiting for the next run.
            auth = await adapter.nameAuthorizationStatus();
          }
          _macNameAuth = auth;
          _macLocationAuthorized = auth.isAuthorized;
          return await adapter.fetch().timeout(
            const Duration(seconds: 5),
            onTimeout: () =>
                throw TimeoutException('Wi-Fi link read timed out'),
          );
        case WifiInfoSource.windowsNativeWifi:
          // Windows Native Wifi (wlanapi.dll via Dart FFI) returns SSID/BSSID/
          // rate with NO Location grant, so — unlike macOS/Android — there is no
          // permission gate to consider mid-test. Read the snapshot directly,
          // bounded so a stalled FFI read can never hang the check. The
          // WindowsWifiInfoAdapter applies its own 5s fetch ceiling too; this
          // outer bound mirrors the macOS branch for a uniform call site.
          // TODO(windows-verify): the wlanapi.dll FFI read executes only on a
          // real Windows host — exercise this branch against a live radio on the
          // June-26 device pass.
          final WifiInfoAdapter? winAdapter = _macAdapter;
          if (winAdapter == null) return null;
          return await winAdapter.fetch().timeout(
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

  /// "Check again" from the not-on-Wi-Fi state: re-read the native identity (a
  /// freshly joined SSID is a definitive on-Wi-Fi signal) then re-run the
  /// sampler's connection probe + install-state resolve, so the section advances
  /// out of the not-on-Wi-Fi state once Wi-Fi is back. Never fires the Shortcut.
  Future<void> _retryConnection() async {
    await _fetchIosSecurity();
    if (_sampler != null) {
      await _sampler!.load(nativeSsid: _nativeSsid);
    } else {
      // No live sampler: settle the SCREEN'S own money probe before any caller
      // reads the gate, exactly as the sampler path settles its own. A run that
      // decided `spendData` from an unresolved risk is the F-2 bypass.
      await _resolveScreenRisk();
    }
  }

  /// The native NEHotspotNetwork SSID when a real network has resolved — a
  /// definitive "on Wi-Fi" signal for the sampler's connection probe. Null before
  /// the native read resolves or when Location is ungranted; absence is never
  /// used to assert "not on Wi-Fi" (see [WifiConnectionService]).
  String? get _nativeSsid {
    final WifiSecurityInfo? sec = _iosSecurity;
    if (sec == null || !sec.available) return null;
    final String? ssid = sec.ssid?.trim();
    return (ssid == null || ssid.isEmpty) ? null : ssid;
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

  /// The SINGLE RF source the result body, the technical section, the help-desk
  /// facts, and the COPY report all read — the one-shot link read taken at
  /// test-completion ([_ap]) UNIFIED with the live sampler's most recent reading
  /// (the same [WifiSignalSampler.latest] the on-screen sparkline card binds to).
  ///
  /// THE BUG THIS FIXES (Keith, on-device 2026-06-15): the live "Wi-Fi signal"
  /// card binds to `sampler.latest` — on iOS, the continuously-streamed companion-
  /// Shortcut payload — so the sparklines (RSSI / SNR / rate) showed live RF on
  /// screen. But the copy report and technical section read ONLY [_ap], a single
  /// `WiFiDetailsBridge.readLatest()` taken once when the test finished. That
  /// one-shot read can resolve before — or independently of — the live stream, so
  /// it carried no RF and the copied report listed SSID/RSSI/channel/etc. as
  /// "Unavailable" even though they were live on screen. Reading both off the SAME
  /// merged source makes "what's on screen is what's copied".
  ///
  /// The merge is non-destructive (see [ConnectedAp.mergedWith]): [_ap]'s own
  /// values win, so the native NEHotspotNetwork security/BSSID enrichment already
  /// folded onto it is preserved; the live sampler only FILLS RF gaps it has and
  /// the one-shot read lacked. When [_ap] is null (no one-shot read landed at
  /// all) but the live sampler has a reading, the live reading stands on its own,
  /// so the copy still reflects exactly what the sparklines show. Off iOS the
  /// macOS/Android poll and the one-shot read draw from the same CoreWLAN/
  /// WifiManager snapshot, so this still resolves to a complete reading without
  /// changing established behavior.
  /// NOT ON WI-FI -> THERE IS NO LINK READING (2026-07-13, Keith on-device, v1.7.2).
  ///
  /// [_readLink]'s iOS branch calls `WiFiDetailsBridge.readLatest()`, which returns
  /// the App Group's LAST STORED payload — and that payload survives the phone
  /// leaving Wi-Fi. On a cellular-only iPhone the stale reading (Tx 29 / Rx 13
  /// Mbps, captured the last time it WAS on Wi-Fi) flowed into [_ap] -> here ->
  /// `ConnectionCheck.compute` -> a `wifiLimiter` verdict, and the screen told a
  /// user with NO Wi-Fi to "Boost the Wi-Fi signal to raise the ceiling." The
  /// advice was derived from a Wi-Fi link that does not exist.
  ///
  /// THE READING IS STAMPED WITH THE RUN, NOT RECOMPUTED LIVE (cold-eyes F4).
  /// [_resultAp] is assembled ONCE in the run's `onDone` — gated there by the
  /// run's own [_resultNotOnWifi] — and thereafter only ENRICHED by late-arriving
  /// live RF ([_onSamplerChanged]), never blanked by a probe that moved after the
  /// check finished. That keeps a legitimately-taken on-Wi-Fi reading intact when
  /// the phone later drops to cellular, and keeps the whole result body (verdict,
  /// technical section, help-desk facts, copy report, Analyze) reading ONE
  /// consistent snapshot instead of a mix of dated and live state.
  ///
  /// Null until the first check completes, and null for a check that ran with no
  /// Wi-Fi link at all.
  ConnectedAp? get _effectiveAp => _resultAp;

  /// The one-shot link read folded with whatever the live sampler has RIGHT NOW.
  /// Non-destructive (see [ConnectedAp.mergedWith]): [oneShot]'s own values win,
  /// so the native NEHotspotNetwork security/BSSID enrichment already folded onto
  /// it is preserved and the live sampler only FILLS RF gaps the one-shot read
  /// lacked. When [oneShot] is null but the sampler has a reading, the live
  /// reading stands on its own.
  ConnectedAp? _mergeWithLive(ConnectedAp? oneShot) {
    final ConnectedAp? live = _sampler?.latest;
    if (oneShot == null) return live;
    return oneShot.mergedWith(live);
  }

  /// iOS: whether the companion Shortcut has captured the RF metrics for the
  /// current result. The native NEHotspotNetwork read supplies only SSID / BSSID
  /// / security; the rich RF block (RSSI / noise / SNR / channel / width / band /
  /// PHY / rate) comes ONLY from the Shortcut harvest — via either the one-shot
  /// `readLatest()` OR the live stream, now unified in [_effectiveAp]. We treat
  /// "RF captured" as "at least one RF metric is present" on the MERGED reading,
  /// so a result whose RF arrived only on the live stream reads as captured (the
  /// sparklines are already showing it) and the screen does NOT fall back to the
  /// capture affordance / "not captured" copy note. Always true off iOS (those
  /// platforms read RF natively, with no capture step).
  bool get _iosRfCaptured {
    if (!_isIos) return true;
    final ConnectedAp? ap = _effectiveAp;
    if (ap == null) return false;
    return ap.rssiDbm != null ||
        ap.noiseDbm != null ||
        ap.channel != null ||
        ap.txRateMbps != null ||
        ap.rxRateMbps != null ||
        ap.standard != null;
  }

  /// macOS-only: the on-screen Location hint for the Wi-Fi link card, or null
  /// when no hint is warranted.
  ///
  /// A hint is shown only on the macOS source, only when the name is genuinely
  /// gated (we have read the authorization and it is NOT authorized). The hint
  /// carries the right CALL TO ACTION for the state: when the status is
  /// promptable (`notDetermined`) the button re-fires the native prompt; when it
  /// is `denied` / `restricted` (no dialog can appear) the button deep-links to
  /// the macOS Location Services settings pane. Null off macOS, before the first
  /// read, or once authorized (SSID/BSSID then populate — no hint needed).
  _MacLocationHint? get _macLocationHint {
    if (_source != WifiInfoSource.macosCoreWlan) return null;
    final LocationAuthStatus? auth = _macNameAuth;
    if (auth == null || auth.isAuthorized) return null;
    return _MacLocationHint(
      promptable: auth.isPromptable,
      onAction: auth.isPromptable ? _promptMacLocation : _openMacLocationSettings,
    );
  }

  /// Fires the native macOS Location prompt from the on-screen hint button, then
  /// re-reads the authorization so the hint and the network-name rows update in
  /// place. Used only when the status is promptable (`notDetermined`); a denied
  /// status routes to [_openMacLocationSettings] instead (no dialog can appear).
  /// Never throws to the caller. Sets [_macLocationPromptFired] so the run-time
  /// auto-prompt does not also fire (one request only).
  Future<void> _promptMacLocation() async {
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null) return;
    _macLocationPromptFired = true;
    try {
      await adapter.requestNamePermission();
    } catch (_) {
      // A failed/absent prompt leaves the hint as-is; never crash the screen.
    }
    if (!mounted) return;
    final LocationAuthStatus auth = await adapter.nameAuthorizationStatus();
    if (!mounted) return;
    setState(() {
      _macNameAuth = auth;
      _macLocationAuthorized = auth.isAuthorized;
    });
    // If the grant just landed, re-read the snapshot so SSID/BSSID populate now
    // rather than only on the next run.
    if (auth.isAuthorized) await _refreshMacLinkAfterGrant();
  }

  /// Deep-links to the macOS Location Services settings pane (the honest path
  /// when the status is `denied` / `restricted` and no in-app dialog can
  /// appear). The user enables Location there, returns, and re-runs the check.
  /// Never throws to the caller.
  Future<void> _openMacLocationSettings() async {
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null) return;
    try {
      await adapter.openNamePermissionSettings();
    } catch (_) {
      // Best-effort deep-link; a failure leaves the user on the hint, which
      // still names the fix in its body copy.
    }
  }

  /// Re-reads the macOS CoreWLAN snapshot after a just-granted Location prompt so
  /// the SSID/BSSID rows and copy report populate immediately, without waiting
  /// for the next full run. Merges onto the existing result so the rest of the
  /// reading (RF, internet, verdict) is untouched. Never throws.
  Future<void> _refreshMacLinkAfterGrant() async {
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null) return;
    try {
      final ConnectedAp fresh = await adapter.fetch();
      if (!mounted) return;
      setState(() {
        final ConnectedAp? prior = _ap;
        _ap = prior == null ? fresh : fresh.mergedWith(prior);
        // Keep the RESULT snapshot in step: [_effectiveAp] reads [_resultAp], not
        // [_ap], so a refresh that only touched [_ap] would never reach the screen.
        // macOS is never `notOnWifi` (the probe only asserts it on iOS), but the
        // guard keeps this from resurrecting a suppressed reading if that changes.
        if (!_resultNotOnWifi && _verdict != null) {
          _resultAp = _mergeWithLive(_ap);
        }
      });
    } catch (_) {
      // A failed re-read leaves the prior result intact; the user can re-run.
    }
  }

  /// Runs the internet measurement and the link read from one tap, then computes
  /// the engine verdict (shared [ConnectionCheck]) and translates it for the
  /// consumer ([ConsumerVerdictMapper]).
  ///
  /// [includeThroughput] carries the user's CELLULAR-DATA CONSENT (Keith,
  /// 2026-07-13). The speed test is not byte-bounded — it downloads at full rate
  /// for a fixed window, so it costs roughly 50 MB on a slow cellular link and
  /// 500 MB or more on fast 5G. On Wi-Fi this is always true and nothing changes.
  /// Off Wi-Fi the user chooses, and choosing "no" still runs the whole rest of
  /// the check (latency, loss, DNS, reachability, ISP, the honest not-on-Wi-Fi
  /// state) — only the data-hungry stages are withheld.
  Future<void> _run({required bool includeThroughput}) async {
    // ========================================================================
    // SETTLE THE PROBE BEFORE THE CONSENT DECISION READS IT (round-4 F-2 fix,
    // 2026-07-14). THIS AWAIT IS THE FIX. Do not turn it back into a
    // fire-and-forget.
    //
    // The consent decision below reads [_notOnWifi]. Until now the only thing
    // that refreshed [_notOnWifi] inside a run was a FIRE-AND-FORGET
    // `_sampler?.load()` fired AFTER this decision had already been made. That
    // was defended in a comment as safe because the probe "resolves in
    // milliseconds, far inside the ~25-35s measurement, so [_notOnWifi] is
    // settled long before `onDone` reads it." True — and irrelevant. `onDone`
    // is not the only reader. `spendData` is, and it runs FIRST.
    //
    // THE BYPASS THAT LET THROUGH (REPRODUCED): mount the screen on Wi-Fi, then
    // walk out of Wi-Fi range with it open — an entirely ordinary thing to do.
    // Nothing re-probes while mounted, so [_notOnWifi] is still false: the
    // cellular warning never renders, the button keeps its on-Wi-Fi label, the
    // consent tap at [_throughputConsented] never fires — and `spendData`
    // reads that same stale false and evaluates TRUE. The app spent up to
    // 500 MB of the user's cellular data, and then rendered "you're not
    // connected to Wi-Fi" in the result, because the fire-and-forget probe had
    // landed by the time `onDone` ran. It spent the data AND THEN TOLD YOU IT
    // KNEW.
    //
    // [_autoStart] already awaited the probe (that is why the auto-run path was
    // safe and only the auto-run path was tested). The BUTTON and "Run again"
    // did not. The fix belongs HERE, at the one chokepoint every caller passes
    // through, not bolted onto each caller — a fourth caller added tomorrow
    // must not be able to reintroduce this by forgetting a line.
    // ========================================================================
    await _retryConnection();
    if (!mounted) return;

    // ========================================================================
    // THE CONSENT CHOKEPOINT (round-4 P0, 2026-07-14).
    //
    // Consent must live where the BYTES ARE SPENT, not where the button is. This
    // parameter used to default to `true`, and FOUR callers reached _run() on that
    // default — the auto-start post-frame callback (the home hero), the result
    // screen's "Run again" tear-off, the post-Shortcut-install callback, and the
    // pre-run button. Only the button had seen the user's consent. The other three
    // spent cellular data without asking.
    //
    // Two changes make that impossible rather than merely fixed:
    //   1. `includeThroughput` is now REQUIRED. A caller cannot spend the user's
    //      data by simply not knowing the parameter exists; the compiler makes
    //      every caller state a decision.
    //   2. This line. `includeThroughput` is what the CALLER ASKED FOR;
    //      `spendData` is what the USER HAS AGREED TO PAY FOR. On a metered link
    //      the two are the same only after an explicit consent tap. A future
    //      caller that passes `true` still cannot spend a cellular user's data.
    //
    // On Wi-Fi (`!_notOnWifi`) this is a no-op and the check behaves as it always
    // has.
    // ========================================================================
    //
    // ROUND 5: IT NOW FAILS CLOSED. The line above used to read
    //     includeThroughput && (!_notOnWifi || _throughputConsented)
    // which closed ONLY on a definitive `notOnWifi`. Every ambiguous / errored /
    // timed-out / unsupported read resolves to `unknown` — and `unknown` SPENT. The
    // consent card only rendered on `notOnWifi`, so `_throughputConsented` was still
    // false: THE USER WAS NEVER ASKED AND COULD NOT HAVE BEEN. Vera got five
    // exploits through it (Android VPN over cellular; the OS merging both transport
    // bits; an Android channel that threw or timed out; an iPhone on cellular whose
    // `en0` holds a link-local `fe80::`, twice over).
    //
    // The two shapes that HELD were the two Keith happened to have tested on his own
    // phone. Every shape he did not test, spent.
    //
    // ASSERTING A FACT and AUTHORIZING A SPEND are different acts. GL-005 forbids the
    // first from ambiguity; it never required the second. We ask WITHOUT claiming —
    // see [kUnknownLinkDataWarning].
    final bool spendData =
        includeThroughput && (!_needsConsent || _throughputConsented);

    setState(() {
      _error = null;
      _running = true;
      _finishing = false;
      _phase = QualityPhase.idle;
      _fraction = 0;
      _indeterminate = false;
      _ap = null;
      // A new run re-stamps the report from scratch: drop the previous run's RF
      // snapshot and its probe verdict so nothing from it can bleed into this one.
      _resultAp = null;
      _resultNotOnWifi = false;
      _resultSpeedTestSkipped = false;
      _macLocationAuthorized = null;
      // NB: _macNameAuth resets with the result but _macLocationPromptFired does
      // NOT — the one-shot prompt guard must survive a re-run so the native
      // prompt fires at most once per screen-mount (Keith: "One request only").
      _macNameAuth = null;
      _internet = null;
      _verdict = null;
      _engine = null;
      _testedAt = null;
      _ispInfo = null;
      // Back to UNANSWERED for the fresh run — never carry a prior run's answered-no
      // into the next, or the first recompute could fire an offline verdict off
      // stale evidence before this run's own probes have reported.
      _publicIpObtained = null;
      _dnsResult = null;
      _networkDetails = null;
    });

    // (The not-on-Wi-Fi probe used to be fired here, unawaited, AFTER the consent
    // decision above had already read its stale result. It is now AWAITED at the
    // top of this method — see the F-2 note there. Firing it again here would be a
    // redundant platform-channel round trip.)

    final Future<ConnectedAp?> linkFuture = _readLink();

    // AUTO-CAPTURE iOS Wi-Fi RF (item #8 — Keith's explicit "no tap" request).
    //
    // On iOS the RF block (RSSI / noise / SNR / channel / width / band / PHY /
    // rate) only arrives through the companion "WLAN Pros Live" Shortcut. Before
    // this, the user had to tap "Start" / "Capture Wi-Fi details" by hand, so a
    // normal run captured no RF and both the sparklines and the copy report came
    // up empty. We now fire the companion Shortcut automatically AT TEST START so
    // the live stream is already delivering by the time the ~25–35 s internet
    // measurement completes — RF then appears on screen AND in the copy with zero
    // taps. macOS/Android auto-poll natively (no Shortcut, no bounce) and already
    // capture without a tap, so this is iOS-only. Fire-and-forget: it never gates
    // or blocks the verdict, and a failure falls back to the manual capture tap
    // (the Start button + "Capture Wi-Fi details" affordance stay as the
    // fallback). See [_autoCaptureIosRf] for the auto-fire-bounce handling.
    //
    // ...UNLESS THIS RUN IS A RESUME, IN WHICH CASE FIRING WOULD BE CATASTROPHIC.
    //
    // A resumed run is one iOS already destroyed once, BY BACKGROUNDING US INTO
    // SHORTCUTS — which is exactly what firing does. Fire again and the scene is
    // destroyed again, the gate restores again, the resume fires again: an infinite
    // bounce loop the user cannot escape without force-quitting. There is also
    // nothing to fire FOR — the Shortcut already ran, and its reading is sitting in
    // the App Group waiting to be picked up.
    //
    // The flag is CONSUMED here, so a subsequent "Run again" on this same screen
    // fires normally. One resume per arm.
    if (_isIos) {
      final DateTime? resumedFrom = _resumedRunArmedAt;
      _resumedRunArmedAt = null;
      if (resumedFrom != null) {
        _adoptDeliveredIosRf(resumedFrom);
      } else {
        _autoCaptureIosRf();
      }
    }

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

    // THE RPM DECISION (Keith, 2026-07-14). On cellular the responsiveness stage
    // does not run AT ALL. Its load generator is a second full-rate download, and
    // shortening it would not have been "less accurate" — it would have been
    // BIASED TOWARD FLATTERY (a link that never saturates understates loaded
    // latency, and rpm = 60000/loadedAvg then comes out too HIGH). RPM is an
    // adjunct here; declining to measure an adjunct is the honest answer, and it
    // is the fast one.
    //
    // ROUND 5 — IT FAILED OPEN ON THE SAME FLAG, AND THAT DOUBLED THE DAMAGE. This
    // rode `!_notOnWifi`, the very flag the broken chokepoint rode, so on all five
    // exploited shapes it ALSO evaluated true: the user got the download PLUS the
    // RPM load generator (a SECOND full-rate download) PLUS the upload — roughly
    // DOUBLE the cost the consent sentence describes, having never seen the sentence.
    // Fixing `spendData` and leaving this line alone would have closed the front door
    // and left the side door open, which is exactly how the round-4 fix failed.
    //
    // It now fails closed on the SAME rule: RPM runs only when the link is PROVEN
    // free. Never on a confirmed metered link (Keith's decision, unchanged), and
    // never on a link we could not identify — because the consent sentence quotes the
    // download+upload cost, and adding RPM on top would make that sentence false even
    // for a user who DID tap.
    _sub = _quality
        .measure(
      includeThroughput: spendData,
      includeResponsiveness: !_needsConsent,
    )
        .listen(
      (QualityProgress p) {
        if (!mounted) return;
        setState(() {
          _phase = p.phase;
          _fraction = p.fraction;
          _indeterminate = p.indeterminate;
        });
      },
      onDone: () async {
        final QualityResult? internet = _quality.lastResult;
        // MEDIUM-2: the measurement is DONE and the link read may not be. Say that,
        // rather than holding a dead 100% bar for up to 8 seconds. The card is gated
        // on `_running`, which does not drop until after the await below — so
        // WITHOUT this the last thing the user sees is a full bar and a stale phase
        // caption, for longer than the upload stage took.
        if (mounted) setState(() => _finishing = true);
        final ConnectedAp? ap = await linkFuture.timeout(
          const Duration(seconds: 8),
          onTimeout: () => null,
        );
        if (!mounted) return;
        // ==================================================================
        // THE GATE. Everything the result body says about Wi-Fi hangs off this
        // one line (2026-07-13).
        //
        // `ap` above is the App Group's LAST STORED payload, which survives the
        // phone leaving Wi-Fi. Feeding it in is what produced "It's your Wi-Fi" /
        // "your Wi-Fi link 29 Mbps" / "boost the Wi-Fi signal" on a cellular-only
        // iPhone. The probe was refreshed at run start and settles in ms, far
        // inside the ~25-35s measurement, so it is authoritative by now.
        //
        // Read the probe ONCE, here, and STAMP it onto the result
        // ([_resultNotOnWifi]) so the whole report is dated to its own run and a
        // later resume cannot half-rewrite it (cold-eyes F4). Deleting this line
        // renders the original bug in full — which is what
        // test/screens/tools/network/test_my_connection_offwifi_e2e_test.dart is
        // there to catch.
        // ==================================================================
        final bool notOnWifi = _notOnWifi;
        // Stamp the consent decision onto the RESULT for the same reason the probe
        // verdict is stamped: the report must be dated to its own run, and a later
        // recompute must not re-derive it from whatever the screen looks like now.
        final bool skipped = !spendData;
        final ConnectedAp? linkAp = notOnWifi ? null : ap;
        final WifiVsInternetResult engine = ConnectionCheck.compute(
          linkAp,
          internet,
          // Fold in whatever evidence already landed; late-arriving evidence
          // re-derives the verdict via [_recomputeVerdict] as it lands.
          onlineEvidence: _onlineEvidence,
          // The honest not-on-Wi-Fi probe, so the engine says "there is no Wi-Fi
          // link" rather than "the Wi-Fi link could not be read" (GL-005).
          notOnWifi: notOnWifi,
          // ...and the honest "we never ran it" so the engine never says the speed
          // test "did not complete" about a test that was never started.
          speedTestSkipped: skipped,
        );
        setState(() {
          _ap = ap;
          _resultNotOnWifi = notOnWifi;
          _resultSpeedTestSkipped = skipped;
          // The RF snapshot for THIS result: the gated one-shot read folded with
          // whatever the live stream has already delivered. Off Wi-Fi there is no
          // link, so there is no reading (GL-005 — the second kind of null).
          _resultAp = notOnWifi ? null : _mergeWithLive(ap);
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
          _finishing = false;
        });
        // THE RUN IS DONE — DISARM IT. The user has their result on screen; there is
        // nothing left to restore. Leaving the arm standing would let a scene rebuild
        // minutes later drag them back into a run that already finished.
        _iosBridge?.clearLiveRun();
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
          _finishing = false;
          _error =
              "Something went wrong and we couldn't finish the check. "
              'Please try again.';
        });
        // A FAILED run is still a FINISHED run. The screen is showing the honest
        // error and the actionable retry; restoring this later would replay a
        // failure the user has already seen and dismissed.
        _iosBridge?.clearLiveRun();
      },
    );
  }

  /// The out-of-band "you're online" evidence, read from the latest fetched
  /// state. These three signals are gathered OUTSIDE the throughput measurement
  /// (the DNS probe, the public-IP lookup, and the cloud-app reachability
  /// panel), so they stay valid even when the speed test stalls. When all three
  /// are present the engine produces [WifiVsInternetVerdict.onlineUnmeasured]
  /// instead of the bleak "could not read" verdict (Keith 2026-06-17).
  /// ROUND 5: EVERY SIGNAL IS NOW TRI-STATE, AND THAT IS THE WHOLE FIX.
  ///
  /// Each of these used to collapse to `false` when the probe HAD NOT COME BACK YET
  /// — `_dnsResult?.isAvailable ?? false`, an empty `_cloudResults` list, a null
  /// `_ispInfo`. All three probes land ASYNCHRONOUSLY, and this getter is read in
  /// `onDone` (which is exactly why [_recomputeVerdict] exists to re-run it as they
  /// arrive). So at first read a PENDING probe and a FAILED probe were the same
  /// value, and "all three false" was the NORMAL mid-flight state of a perfectly
  /// healthy connection.
  ///
  /// Reading the negative off THAT would have told half the app's users their
  /// internet was down, every single run. `null` now means UNANSWERED, `false` means
  /// ANSWERED NO, and [OnlineEvidence.isOffline] requires all three to be an actual
  /// `false`. The verdict simply does not fire until the evidence is in — and when a
  /// late probe lands, [_recomputeVerdict] re-derives it, which is the machinery
  /// that makes waiting free.
  OnlineEvidence get _onlineEvidence => OnlineEvidence(
        // null until the DNS probe reports. `isAvailable` is its settled answer.
        // (`?.` is doing the tri-state work here: null result → null evidence.)
        dnsResolved: _dnsResult?.isAvailable,
        // The tri-state answered/answered-no/unanswered flag, set by [_fetchIspInfo]
        // on BOTH a reported failure and a thrown error. Derived from [_publicIpObtained]
        // rather than from [_ispInfo], because [_ispInfo] is stored ONLY on success —
        // so a null there could not tell "the lookup failed" (answered-no → false)
        // from "the lookup has not landed" (unanswered → null). That collapse was the
        // whole bug: on a dead internet the lookup fails, `_ispInfo` stayed null, and
        // `publicIpObtained` could never resolve to `false`, so `isOffline` never
        // fired from the screen. See [_publicIpObtained].
        publicIpObtained: _publicIpObtained,
        // null until the cloud panel returns ANY row. An empty list is "the probe has
        // not answered"; a full list where nothing is reachable is a definitive NO.
        // The screen's own AnalyzeInput already drew exactly this line
        // (`cloud.isEmpty ? null : …`) — the information was always here.
        cloudReachable: _cloudResults.isEmpty
            ? null
            : _cloudResults.any((SiteReachability s) => s.reachable),
      );

  /// Re-derives the engine verdict and the consumer verdict from the stored
  /// measurement plus the CURRENT online evidence, then rebuilds the UI.
  ///
  /// The evidence signals (DNS / public IP / cloud reachability) land async,
  /// often AFTER the measurement completes, so the verdict is recomputed each
  /// time one arrives. This is the seam that lets a stalled-throughput run flip
  /// from "could not read" to the honest "you are online" the moment the
  /// reachability evidence confirms the device is genuinely online. It is a
  /// no-op until a measurement has produced an [_internet] result (the run is
  /// what seeds [_internet] / [_engine]); evidence that lands before then is
  /// folded in when the run's own `onDone` calls this.
  void _recomputeVerdict() {
    if (!mounted || _internet == null) return;
    final WifiVsInternetResult engine = ConnectionCheck.compute(
      _effectiveAp,
      _internet,
      onlineEvidence: _onlineEvidence,
      // The RUN's probe verdict, not the live one: a late DNS/ISP/cloud signal
      // must re-derive the verdict for the check that was TAKEN, and must never
      // rewrite a completed on-Wi-Fi result into "you're not on Wi-Fi" just
      // because the phone has since left the network (cold-eyes F4).
      notOnWifi: _resultNotOnWifi,
      // The RUN's consent decision, for the same reason as notOnWifi above: late
      // evidence re-derives the verdict for the check that was TAKEN.
      speedTestSkipped: _resultSpeedTestSkipped,
    );
    setState(() {
      _engine = engine;
      _verdict = ConsumerVerdictMapper.map(
        engine,
        internetHealthy:
            ConnectionCheck.internetHealth(_internet) == InternetHealth.good,
      );
    });
  }

  /// Fetches the public IP + ISP/org + ASN for the copy payload, AND records the
  /// public-IP-obtained ONLINE EVIDENCE (round 5 CRITICAL, 2026-07-14).
  ///
  /// TWO OUTPUTS, KEPT DISTINCT:
  ///   * [_ispInfo] — the COPY payload. Stored ONLY on a successful, located result,
  ///     exactly as before, so the report's ISP section is omitted cleanly on failure
  ///     (never a placeholder, never a fabricated address — GL-005 / GL-008).
  ///   * [_publicIpObtained] — the EVIDENCE. Set on EVERY answer, success or failure,
  ///     so [OnlineEvidence.publicIpObtained] can resolve to `false` (answered-no) on
  ///     a dead internet instead of sitting at `null` (unanswered) forever. That null
  ///     is what defeated both the offline and captive-portal verdicts before now.
  ///
  /// Never blocks the run. IpGeoService returns an honest failure result rather than
  /// throwing; the `catch` is the defensive backstop for a timeout / transport error,
  /// and it too is an ANSWER for the evidence axis (we asked, no public IP came back).
  Future<void> _fetchIspInfo() async {
    try {
      final IpGeoResult result = await _ipGeo
          .lookup(rawQuery: '')
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      final bool gotPublicIp = !result.isError && result.ip != null;
      setState(() {
        // ANSWERED. Record the evidence in BOTH directions.
        _publicIpObtained = gotPublicIp;
        // Keep the COPY payload only on success — unchanged behavior.
        if (gotPublicIp) _ispInfo = result;
      });
      // A public IP is one of the three online-evidence signals; a definitive NO is
      // just as load-bearing (it feeds the offline / captive-portal verdicts). Either
      // way, re-derive the verdict in case the speed test stalled (Keith 2026-06-17).
      _recomputeVerdict();
    } catch (_) {
      // Fail open for the COPY (no _ispInfo, no ISP section), but the EVIDENCE still
      // answers: a thrown timeout / transport error is "we asked and got no public
      // IP" — the ONLY path a truly dead internet takes — so it must resolve to
      // `false`, not leave the evidence unanswered.
      if (!mounted) return;
      setState(() => _publicIpObtained = false);
      _recomputeVerdict();
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
      // A resolved DNS lookup is one of the three "you're online" signals;
      // re-derive the verdict in case the speed test stalled (Keith 2026-06-17).
      if (result.isAvailable) _recomputeVerdict();
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

  /// Auto-fires the iOS companion "WLAN Pros Live" Shortcut so the Wi-Fi RF is
  /// captured automatically as part of running the test — no user tap (item #8,
  /// Keith). iOS-only and no-op without a live sampler (tests that disable live
  /// sampling, or a platform with none); the macOS/Android native poll already
  /// auto-captures with no Shortcut.
  ///
  /// AUTO-FIRE-BOUNCE HANDLING. Firing the companion Shortcut switches to the
  /// Shortcuts app briefly (the known auto-fire bounce). We MUST NOT re-fire it
  /// on top of an already-live stream, and MUST NOT fire it at all when the
  /// Shortcut is not demonstrably installed — that would bounce the user into the
  /// Shortcuts app with a "shortcut not found" error and starve the concurrent
  /// internet measurement. So:
  ///   0. If the app has NEVER received a Live payload
  ///      ([WiFiDetailsBridge.hasEverReceivedPayload] == false), the Shortcut is
  ///      not demonstrably installed → do nothing. The inline LiveSetupCard /
  ///      LiveRfLockedCard surfaces the non-modal install path instead.
  ///   1. If the live stream is ALREADY running this session (the user pressed
  ///      Start earlier, or a prior auto-fire is live), do nothing — the existing
  ///      stream already feeds the sparklines and [_effectiveAp].
  ///   2. Otherwise fire it ONCE via the sampler's [start]. The single explicit
  ///      kickoff is what the platform can honor; the recursive Shortcut then
  ///      streams back into the app on its own.
  ///   3. RETRY ONCE if, after a short settle, the stream produced no reading
  ///      (the bounce was cancelled, or the first fire raced the app switch).
  ///      A second settle without a reading falls back silently to the manual
  ///      "Start" / "Capture Wi-Fi details" affordance — never a fabricated value
  ///      (GL-005), never an endless re-fire loop.
  /// The internet measurement (~25–35 s) overlaps the settle, so in the normal
  /// case the stream is delivering well before the run completes and the RF is
  /// already on screen and in the copy with zero taps.
  /// The RESUME counterpart of [_autoCaptureIosRf]: take the reading the Shortcut
  /// ALREADY delivered, and do not fire anything.
  ///
  /// THE READING IS NOT LOST. That is the whole reason the App Group exists. The
  /// companion Shortcut ran, wrote its payload, and posted its Darwin notification —
  /// all while we were backgrounded and, moments later, destroyed. The payload
  /// outlived us, because it lives below our lifecycle. So a resumed run does not
  /// need to bounce the user into Shortcuts a second time to learn something it
  /// already knows.
  ///
  /// [armedAt] is when the destroyed run fired. Only a payload stamped AT OR AFTER
  /// that instant can be a reading OF that run; anything earlier is the stale
  /// reading from the last time the phone was on Wi-Fi, and adopting it would chart
  /// a months-old café as the current link. That is the exact stale-reading failure
  /// this codebase has now been burned by twice, so the check is on the STAMP, not
  /// on the payload's mere existence.
  ///
  /// A null stamp is NOT a yes (GL-005). If the platform cannot date the payload we
  /// decline to adopt it, and the run completes honestly with no RF rather than with
  /// RF we cannot prove is ours.
  Future<void> _adoptDeliveredIosRf(DateTime armedAt) async {
    final WifiSignalSampler? sampler = _sampler;
    final WiFiDetailsBridge? bridge = _iosBridge;
    if (sampler == null || bridge == null || !sampler.isIos) return;
    // Off Wi-Fi there is no link, so there is no reading of it (the second kind of
    // null). An armed run implies we were on Wi-Fi when it fired, but the phone can
    // have walked out of range during the bounce.
    if (_notOnWifi) return;

    final DateTime? deliveredAt = await bridge.payloadReceivedAt();
    if (!mounted) return;
    if (deliveredAt == null || deliveredAt.isBefore(armedAt)) return;

    // Land the payload through the same path a live sample takes, so the reading,
    // the sparkline and the copy report all see it exactly as they would have if the
    // scene had never died.
    await sampler.pollLatestAfterOneShot();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _autoCaptureIosRf() async {
    final WifiSignalSampler? sampler = _sampler;
    if (sampler == null || !sampler.isIos) return;

    // NOT ON WI-FI → DO NOT FIRE THE SHORTCUT (cold-eyes F5, 2026-07-13).
    //
    // The consumer of the one-shot ([WifiMonitorController.pollLatestAfterOneShot])
    // was gated but the PRODUCER was not, so a cellular-only check still fired the
    // companion Shortcut — measured at TWO fires per check (the initial fire plus
    // the no-reading retry below). Each fire is an app-switch to Shortcuts for a
    // read that CANNOT succeed (there is no Wi-Fi link to harvest), and each
    // app-switch starves the concurrent throughput measurement — the same
    // regression documented in the install gate below (118/94 vs a real 712/462
    // Mbps). Two bounces, zero data, and a slower internet number for the trouble.
    //
    // This reads the LAST SETTLED probe, not this run's in-flight one: the run
    // fires a refresh but never awaits it (a platform-channel await here would
    // couple the RF capture to a channel that can stall). initState and every
    // resume refresh it, so a cellular-only phone is already flagged by the time
    // any check is tapped. RESIDUAL, stated rather than hidden: a phone that drops
    // Wi-Fi while sitting on this screen, with no resume in between, can still fire
    // ONE Shortcut on the next check (never the retry — `onDone` re-reads the probe
    // and the result is gated). That is one bounce in a narrow window, versus a
    // capture path that silently dies whenever the probe hangs.
    if (_notOnWifi) return;

    // Already live this session → the stream is feeding both the sparklines and
    // [_effectiveAp]; do not re-fire (avoids a redundant Shortcuts-app bounce).
    if (sampler.isStreaming) return;

    // INSTALL GATE (2026-06-25, Keith — clean-install bounce bug). iOS cannot
    // query whether the companion "WLAN Pros Live" Shortcut is installed, so we
    // infer install-state from the SAME honest App Group signal the onboarding
    // uses: [WiFiDetailsBridge.hasEverReceivedPayload]. If the app has NEVER
    // received a Live payload, the Shortcut is not demonstrably installed — so
    // firing it would bounce the user into the Shortcuts app with a "shortcut not
    // found" error (iOS does not reliably report that failure back, so
    // [triggerError] stays false and the retry below fires a SECOND bounce), and
    // each app-switch starves the concurrent internet throughput measurement
    // (the 118/94 vs real 712/462 Mbps regression). So we DO NOT fire at all when
    // the Shortcut is not demonstrably working — the internet test then runs
    // uninterrupted in the foreground, and the inline LiveSetupCard /
    // LiveRfLockedCard still surfaces the non-modal "set up live Wi-Fi" path so
    // the user gets a clear install affordance without a bounce. Users who HAVE
    // the Shortcut working (hasEverReceivedPayload == true) auto-capture exactly
    // as before. Off-iOS the bridge has no handler and returns false, but the
    // [isIos] guard above already excludes those sources.
    final WiFiDetailsBridge? bridge = _iosBridge;
    if (bridge == null) return;
    final bool everReceived = await bridge.hasEverReceivedPayload();
    if (!everReceived || !mounted) return;

    // ONE-SHOT (2026-06-23, Keith): fire the companion Shortcut ONCE without
    // raising the persistent monitoring flag, so a normal Check My Connection
    // captures the RF automatically but leaves NO persistent iOS banner — the
    // banner flashes for the single run and clears on its own. Continuous
    // streaming (the looping Shortcut + banner) is now an explicit opt-in the
    // user starts from the technical Wi-Fi sub-card, not something a check
    // silently turns on. On a missing Shortcut getReadingOnce() sets triggerError
    // and the manual "Capture Wi-Fi details" affordance remains the fallback.
    // ========================================================================
    // ARM THE RUN — THE LAST LINE BEFORE WE HAND CONTROL TO iOS.
    //
    // The very next statement fires the Shortcut, which foregrounds the Shortcuts
    // app and backgrounds us. From that instant iOS may tear down and rebuild our
    // UIScene at any moment, and if it does, EVERYTHING BELOW THIS LINE CEASES TO
    // EXIST — this method, this screen, the measurement running concurrently, the
    // whole Dart heap. There is no `finally` that can save it and no exception to
    // catch; the process simply comes back as a different one, on the home route.
    //
    // So the fact that a run is in flight has to be written somewhere that is not
    // us. This is that write. It is the only thing that will survive to tell the
    // rebuilt app that Keith is owed a result.
    //
    // It is disarmed on every clean ending — the run completes (`onDone`), the run
    // errors (`onError`), the trigger never opened (just below), or the user
    // deliberately leaves the screen (`dispose`). Which is what makes an arm that is
    // STILL STANDING mean "iOS took this from us", and not "the user walked away".
    // ========================================================================
    await bridge.armLiveRun(AppRouter.testMyConnection);

    final bool opened = await sampler.getReadingOnce();
    if (!opened) {
      // iOS could not even open the trigger, so we were never backgrounded and the
      // scene was never at risk. There is no interrupted run to come back to —
      // disarm, or a later launch would restore a run that never started.
      await bridge.clearLiveRun();
      return;
    }

    // Settle, then poll the App Group payload in case the single streamed sample
    // raced the app's foreground return. The long internet measurement runs
    // concurrently, so this never extends the run.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final bool gotReading = sampler.latest?.hasAnyData ?? false;
    // Do NOT retry when the Shortcut is confirmed missing (Keith device round 5):
    // a missing-Shortcut x-error already fired markShortcutMissing, so re-firing
    // would bounce the user to Shortcuts a SECOND time. The recovery card now
    // surfaces from [shortcutMissing] instead.
    if (gotReading || sampler.triggerError || sampler.shortcutMissing) return;

    // RETRY ONCE: the first fire produced nothing (the launch bounce was
    // cancelled, or the first fire raced the app switch). Re-fire the one-shot
    // read once more — still without raising the persistent flag, so this never
    // becomes a loop. A second miss falls back silently (GL-005 — never a
    // fabricated value, never an endless re-fire).
    await sampler.getReadingOnce();
    await sampler.pollLatestAfterOneShot();
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
        // moves: the unmistakable LABELED "Run again" control lives in the result
        // body on its OWN row directly beneath the verdict-hero sentence
        // (trailing-aligned). It started on the sentence row itself, but at iPhone
        // widths the trailing button squeezed the verdict text into a narrow left
        // column, so it was moved to a dedicated row beneath; the sentence now
        // reads full-width (Keith, 2026-06-15). It carries `Icons.refresh`, the
        // 'Run the test again' Semantics label, and the §8.3 44pt target (see
        // [_HeroRunAgainButton]). With copy alone the full title clears at every
        // iPhone width.
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
                  // MISSING-SHORTCUT RECOVERY (Keith device round 5): surface the
                  // honest "Shortcut not found — re-run setup" card at the TOP of
                  // the body, independent of the verdict. The "Check My Connection"
                  // hero path can x-error a missing Shortcut without producing a
                  // verdict, and the recovery had only lived in the verdict-gated
                  // live-signal card, so nothing showed (the silent flicker). Once
                  // a verdict exists the live-signal card carries the recovery, so
                  // this top card is shown only pre-verdict to avoid duplication.
                  if (_isIos &&
                      verdict == null &&
                      ((_sampler?.shortcutMissing ?? false) ||
                          (_sampler?.triggerError ?? false))) ...<Widget>[
                    LiveSetupCard.error(
                      label: 'Set up live Wi-Fi (one-time)',
                      onSetUp: _openShortcutSheet,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
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
                      onRunAgain: _running ? null : _rerun,
                      // THE BUTTON MUST TELL THE TRUTH ABOUT WHAT IT SPENDS.
                      // "Run again" calls _run(includeThroughput: true), and the
                      // chokepoint now spends iff `!_needsConsent ||
                      // _throughputConsented`. So it costs data in exactly one
                      // shape: a link that is NOT proven free, with consent already
                      // latched for this mount. Tracks the chokepoint's own rule
                      // rather than restating it in terms of `_notOnWifi` — which is
                      // how this label came to promise "free" on the five shapes
                      // that spent. Reads the LIVE probe, not the frozen result
                      // flag: the label must describe what the NEXT tap will do, and
                      // _run re-settles the probe before spending.
                      runAgainUsesData: _needsConsent && _throughputConsented,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // THE OPT-IN THE RESULT SCREEN NEVER HAD (round-4b, 2026-07-14).
                    //
                    // A declined cellular run renders "Not measured: the speed test
                    // was skipped to save cellular data" — a sentence that invites
                    // "but I want it" and offered NO BUTTON. The pre-run card is
                    // gone by now (`if (verdict == null) _actionCard(...)`), so the
                    // user was PERMANENTLY DENIED the headline feature for this
                    // mount with no way back short of leaving and re-entering.
                    //
                    // It bites hardest on 5G fixed-wireless home users, who read as
                    // "cellular" and are UNLIMITED.
                    //
                    // This is not a new consent surface: it is the SAME cost-labelled
                    // tap the pre-run screen already treats as sufficient consent.
                    // There is no principled reason that tap is safe BEFORE a run and
                    // unsafe AFTER one. Same words, same cost, same one tap.
                    // BOTH flags, not just the first. `_resultSpeedTestSkipped`
                    // alone would render the words "(uses data)" to a user who is
                    // NOT on cellular if any future caller ever passes
                    // `includeThroughput: false` on Wi-Fi. Today no such caller
                    // exists (the decline path is itself gated on `_notOnWifi`), so
                    // this is belt-and-braces — but the offer's own copy makes a
                    // COST CLAIM, and a cost claim must never outrun the probe that
                    // licenses it. Both flags are frozen to the same completed run,
                    // so they cannot disagree.
                    if (_resultSpeedTestSkipped &&
                        _resultNotOnWifi &&
                        !_running) ...<Widget>[
                      Semantics(
                        button: true,
                        label: 'Run the speed test anyway, which uses cellular '
                            'data',
                        child: TextButton(
                          onPressed: () {
                            // THE TAP IS THE CONSENT — identical to the pre-run
                            // button, whose label carries the identical cost.
                            _throughputConsented = true;
                            _run(includeThroughput: true);
                          },
                          child: const Text(
                            'Run the speed test anyway (uses data)',
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    // VERDICT LINE — a plain, state-driven sentence that names the
                    // limiter, plus the direct % comparison answer. Both ALWAYS
                    // shown, prominent (no disclosure). The v1.1 "show more" pass
                    // walked back the over-simplified reshape (Keith, 2026-06-05).
                    _VerdictLine(
                      verdict: _verdictLine(verdict),
                      comparison: _comparisonLine(verdict),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // ANALYZE — opens the in-app, local, plain-language report
                    // (the [AnalyzeEngine] over the same result data). It sits
                    // ALONGSIDE the AppBar's Copy action: Copy saves the raw
                    // report for support; Analyze explains it. Local-only; no
                    // network, nothing stored (GL-005 / GL-008).
                    _AnalyzeButton(onAnalyze: _openAnalyze),
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
                          _LiveSignalCard(
                            sampler: _sampler!,
                            onSetUp: _openShortcutSheet,
                            onRetryConnection: _retryConnection,
                          ),
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
                        // The absorbed pro "Wi-Fi vs Internet" readout. Reads the
                        // UNIFIED RF source so the pro Wi-Fi link sub-card matches
                        // the live sparklines and the copy report.
                        _TechnicalSection(
                          ap: _effectiveAp,
                          internet: _internet,
                          result: _engine!,
                          // iOS-only: when the companion Shortcut has not captured
                          // the RF metrics, the Wi-Fi link sub-card shows a "Tap to
                          // capture Wi-Fi details" affordance instead of a grid of
                          // "Unavailable", so the user knows it is a capture step,
                          // not a broken tool (GL-005 / GL-008). [_canOfferWifiCapture]
                          // keeps that offer away from a phone with no Wi-Fi link —
                          // no Shortcut can capture a link that does not exist (F2).
                          needsWifiCapture: _canOfferWifiCapture && !_iosRfCaptured,
                          onCaptureWifi: _canOfferWifiCapture
                              ? _openShortcutSheet
                              : null,
                          // macOS-only: when Location is not granted, the SSID and
                          // BSSID are withheld by the OS, so the Wi-Fi link card
                          // shows an inline "network name hidden" hint with an
                          // action — PROMPT when promptable, OPEN SETTINGS when
                          // denied/restricted. Null off macOS / when authorized.
                          locationHint: _macLocationHint,
                        ),
                      ],
                    ),
                    // iOS-only Shortcut offer. PROMINENCE depends on the install
                    // gate (item #4): when the companion Shortcut is NOT
                    // demonstrably installed (the clean-install case Keith hit —
                    // the check came back "Wi-Fi: Couldn't Check" with no way to
                    // fix it), surface the PROMINENT lime-primary "Set up Live
                    // Wi-Fi" CTA right under the verdict so the path forward is
                    // unmissable. When the Shortcut IS set up but this particular
                    // run just could not read the link, keep the soft optional
                    // offer. Off the couldn't-check path the card is not shown.
                    //
                    // OFF WI-FI THE OFFER IS SUPPRESSED ENTIRELY (F2). The
                    // couldnt-check-Wi-Fi outcome ALSO fires for a cellular-only
                    // phone (there was no link to read), and there the card's
                    // "Add the companion Shortcut to let this app read your Wi-Fi
                    // details" is false advice: the Shortcut is not the missing
                    // piece, a Wi-Fi network is. [_canOfferWifiCapture] is the one
                    // gate every Shortcut affordance on this screen passes through.
                    if (_canOfferWifiCapture &&
                        verdict.outcome ==
                            ConsumerOutcome.couldntCheckWifi) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _ShortcutOfferCard(
                        onOpen: _openShortcutSheet,
                        prominent: !_iosHasEverReceived,
                      ),
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
                          // Reachable cloud apps are one of the three "you're
                          // online" signals; re-derive the verdict in case the
                          // speed test stalled (Keith 2026-06-17).
                          _recomputeVerdict();
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            "Not sure if it's your Wi-Fi or your internet? Tap below and find "
            'out in about a minute.',
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
          ),
          // Low-key aside for the first-timer who reads that sentence and
          // realizes they aren't sure Wi-Fi and internet are even different
          // things. Opens the user guide's plain-language explainer, deep-linked
          // straight to that chapter. Kept text-weight (not a second filled
          // button) so it reads as a helpful link beneath the intro line and
          // never competes with the primary "Check My Connection" action below.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openWifiVsInternetExplainer(context),
              icon: const Icon(Icons.help_outline, size: 18),
              label: const Text("What's the difference?"),
              style: TextButton.styleFrom(
                foregroundColor: colors.textAccent,
                textStyle: text.bodyMedium,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                // §8.3 / WCAG 2.2: hold the 44pt minimum touch target even at
                // this compact text-link weight.
                minimumSize: const Size(0, 44),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the user guide scrolled to its "Wi-Fi vs Cellular vs Internet"
  /// explainer chapter (the [kWifiCellularInternetChapter] deep-link anchor),
  /// answering the confused-first-timer question in plain language without
  /// leaving the app. Falls back to the top of the guide if the anchor ever
  /// stops matching a heading (the reader treats a missing anchor as a no-op).
  void _openWifiVsInternetExplainer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const GuideReaderScreen(
          assetPath: kUserGuideAsset,
          title: 'How this app works',
          initialHeadingAnchor: kWifiCellularInternetChapter,
        ),
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
        // THE DATA-COST WARNING (Keith, 2026-07-13; fail-closed round 5, 2026-07-14).
        //
        // IT USED TO BE GATED ON THE POSITIVE not-on-Wi-Fi PROBE ONLY, and the
        // comment here defended that: "`unknown` (an ambiguous read, a wired Mac,
        // any non-iOS platform) must NEVER reach here". Half of that was right and
        // the other half was the bug. A wired Mac must never be nagged — and it is
        // not, because [MeteredRisk.none] is decided BY PLATFORM. But an "ambiguous
        // read" is ALSO a cellular iPhone whose `en0` carries only a link-local, and
        // that user saw no warning, was never asked, and was charged for up to
        // 573 MB. The card that exists to prevent the spend was hidden on precisely
        // the shapes that spent.
        //
        // [dataCostWarningFor] now picks the sentence that is TRUE for this link:
        // "You're on cellular" only when the OS MEASURED cellular, and "We can't tell
        // whether this device is on Wi-Fi or cellular" when we could not read it.
        // Asserting cellular to a user whose link we never identified would be the
        // same false claim, told from the other side.
        if (_showCostUi && !_running) ...<Widget>[
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
              dataCostWarningFor(_resolvedRisk ?? MeteredRisk.none)!,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Semantics(
          button: true,
          enabled: !_running,
          label: _running
              ? 'Checking your connection'
              // The label IS the consent: a user who taps this has read the data
              // cost directly above it. One tap, no dialog.
              : switch (_resolvedRisk ?? MeteredRisk.none) {
                  MeteredRisk.metered =>
                    'Run the full check including the speed test, which uses '
                        'cellular data',
                  MeteredRisk.unknown =>
                    'Run the full check including the speed test, which may use '
                        'cellular data',
                  MeteredRisk.none => 'Check my connection',
                },
          child: FilledButton(
            onPressed: _running
                ? null
                : () {
                    // THE TAP IS THE CONSENT. When the link is not proven free this
                    // button's own label states the data cost, directly under the
                    // warning that explains it, so tapping it IS the informed
                    // decision. Record it before the run so the chokepoint in [_run]
                    // can honor it.
                    // CONSENT IS ONLY RECORDED IF THE COST WAS ACTUALLY SHOWN.
                    // Keying this off `_needsConsent` would latch consent during the
                    // unresolved window — when the card is deliberately hidden — and
                    // "consent" the user gave to a warning they never saw is not
                    // consent. If the link turns out to be metered, the chokepoint
                    // declines the spend and the card then appears so they can opt in
                    // for real.
                    if (_showCostUi) _throughputConsented = true;
                    _run(includeThroughput: true);
                  },
            child: Text(
              _running
                  ? 'Checking…'
                  : switch (_resolvedRisk ?? MeteredRisk.none) {
                      // "uses" ASSERTS the cellular link and is earned only by a
                      // MEASURED one. "may use" is the honest word when we cannot
                      // tell — hedging a fact we genuinely lack is the opposite sin
                      // from hedging a number we could have derived.
                      MeteredRisk.metered => 'Check My Connection (uses data)',
                      MeteredRisk.unknown =>
                        'Check My Connection (may use data)',
                      MeteredRisk.none => 'Check My Connection',
                    },
            ),
          ),
        ),
        // THE DECLINE PATH. It is not a dead end: everything that does not cost
        // cellular data still runs (latency, loss, DNS, reachability, ISP, and the
        // honest not-on-Wi-Fi state). Only the two data-hungry stages are withheld,
        // and the result says "Not measured" for them rather than "Couldn't check"
        // — nothing failed.
        if (_showCostUi && !_running) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            button: true,
            label: 'Check without the speed test, using no cellular data',
            child: TextButton(
              onPressed: () => _run(includeThroughput: false),
              child: const Text('Check without the speed test'),
            ),
          ),
        ],
      ],
    );
  }

  // ---- Running ----

  Widget _progressCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final int pct = (_fraction * 100).round();
    // MEDIUM-2: once the measurement stream closes we are waiting on the Wi-Fi link
    // read, and the bar has nothing left to fill. Name the work instead of freezing
    // a full bar and a stale phase caption on screen for up to 8 seconds. It is
    // INDETERMINATE, because it genuinely is: we are waiting on a read that may take
    // a moment or may time out.
    final bool stillWorking = _indeterminate || _finishing;
    final String caption =
        _finishing ? 'Reading your Wi-Fi link' : _friendlyPhase(_phase);
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
            indeterminate: stillWorking,
            semanticsLabelBuilder: () => stillWorking
                ? '$caption, still working'
                : '$caption, $pct percent complete',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Testing your Wi-Fi and your internet connection.',
            style: text.bodyMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          // Duration hint (Keith #9). HONEST figure (GL-005), and it now depends
          // on the link, because the run itself does.
          //
          // ON WI-FI: a download window (ThroughputProbe.maxDuration = 15 s), an
          // upload (byte-capped at uploadBytes = 10 MB, so seconds on a decent
          // link and at most one 15 s window on a slow one), then the loaded-
          // responsiveness probe (another ~15 s load window). Roughly half a
          // minute on a healthy link.
          //
          // ON CELLULAR: the responsiveness stage does not run at all, so a whole
          // ~15 s load window comes off the total — download plus a small upload,
          // about 20 seconds.
          //
          // (The previous comment here pinned `throughput_probe.maxDuration` at
          // 10 s. It is 15 s — throughput_probe.dart:490. Fixed 2026-07-14.)
          // Tracks the SAME rule the RPM stage is gated on (`!_needsConsent`), not
          // `_notOnWifi` — otherwise the caption promises a responsiveness test the
          // run will not perform on an ambiguous link. And it must not ASSERT
          // cellular on a link we could not read: the reason is the skip, not the
          // radio.
          Text(
            _showCostUi
                ? 'This usually takes about 20 seconds. The responsiveness '
                    'test is skipped to save data.'
                : 'This usually takes about half a minute.',
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
        // TWO KINDS OF NULL (GL-005). "We could not check it" implies a read that
        // might work next time. Off Wi-Fi there is nothing to check.
        return (_engine?.notOnWifi ?? false)
            ? 'You are not on Wi-Fi right now.'
            : 'We checked your internet, but not your Wi-Fi.';
      case ConsumerOutcome.couldntComplete:
        return (_engine?.notOnWifi ?? false)
            ? 'You are not on Wi-Fi right now.'
            : 'We could not finish the check.';
      case ConsumerOutcome.online:
        return 'You are online.';
      // ROUND 5. THIS IS THE SENTENCE KEITH'S PHONE COULD NOT PRINT. On a conference
      // SSID with a healthy 97/77 Mbps link and a dead internet, the hero said "We
      // could not finish the check." — the `couldntComplete` row above — because no
      // other row existed. It had checked the internet three ways and got a
      // definitive NO.
      case ConsumerOutcome.internetDown:
        return 'Your Wi-Fi is fine. The internet is not reachable.';
      case ConsumerOutcome.signInRequired:
        return 'This network wants you to sign in.';
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
    // Only a REAL measured tier (Strong/Moderate/Weak) may produce the "both
    // sides are X" hero: comparing a side that does not exist is meaningless, and
    // a cellular-only phone must never read "Both sides are …". The guard is
    // shared with [_sameTierVerdictLine] via [ConsumerVerdict.sameRealTier] so the
    // two sentences cannot drift apart (they already had).
    final AxisStatus? tier = verdict.sameRealTier();
    if (tier == null) return null;

    final double? usable = _engine?.usableWifiMbps;
    final double? internet = _engine?.internetMbps;
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

  /// The lowercase tier word for the same-tier sentences ("strong" / "moderate" /
  /// "weak"). Both callers gate on [ConsumerVerdict.sameRealTier], which returns
  /// ONLY those three, so no other member reaches here. The remaining cases defer
  /// to the chip word defensively rather than inventing one.
  static String _lowerTierWord(AxisStatus tier) {
    switch (tier) {
      case AxisStatus.strong:
        return 'strong';
      case AxisStatus.moderate:
        return 'moderate';
      case AxisStatus.weak:
        return 'weak';
      case AxisStatus.unknown:
      case AxisStatus.notApplicable:
      case AxisStatus.notMeasured:
      case AxisStatus.reachableUnmeasured:
      case AxisStatus.unreachable:
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
        // Off Wi-Fi, say WHY there is no Wi-Fi side rather than implying a failed
        // read the user could retry into success (GL-005, two kinds of null).
        return (_engine?.notOnWifi ?? false)
            ? 'We measured your internet. You are not connected to Wi-Fi, so '
                'there was no Wi-Fi link to measure.'
            : 'We measured your internet, but could not read your Wi-Fi on '
                'this device.';
      case ConsumerOutcome.couldntComplete:
        // Neither side read — honest neutral line.
        return (_engine?.notOnWifi ?? false)
            ? 'You are not connected to Wi-Fi, and your internet could not be '
                'measured. Join a Wi-Fi network, then try again.'
            : 'We could not read your Wi-Fi or your internet. Make sure you '
                'are on Wi-Fi, then try again.';
      case ConsumerOutcome.online:
        // The speed test stalled but the device is clearly online (DNS + public
        // IP + cloud reachability) — lead with the reachable truth (Keith's
        // ratified Copy-report VERDICT wording, 2026-06-17).
        return 'You are online. Your internet is reachable, but the speed test '
            'did not complete, so its speed could not be measured. Try again '
            'in a moment.';
      // ROUND 5. The `couldntComplete` row above used to catch this and say: "We
      // could not read your Wi-Fi or your internet. Make sure you are on Wi-Fi, then
      // try again." — printed on a phone that was ASSOCIATED TO A NAMED AP, in the
      // same frame as its own 48 Mbps Wi-Fi capacity bar. Four contradictions in one
      // card, and every one of them came from having no way to name a dead internet.
      case ConsumerOutcome.internetDown:
        return 'Your Wi-Fi link is working. Nothing beyond it is answering, so '
            'the problem is past your Wi-Fi, not in it. Check your router’s '
            'internet connection, or your provider.';
      case ConsumerOutcome.signInRequired:
        return 'Your Wi-Fi is working, but this network has not let you onto '
            'the internet yet. Open your browser and a sign-in page should '
            'appear.';
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
    // The SAME guard as [_sameTierHero], and now literally the same code — this
    // method used to carry its own copy, which had already drifted (it omitted the
    // `notApplicable` exclusion the hero had). See [ConsumerVerdict.sameRealTier].
    final AxisStatus? tier = verdict.sameRealTier();
    if (tier == null) return null;

    final double? usable = _engine?.usableWifiMbps;
    final double? internet = _engine?.internetMbps;
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
  /// rate vs the measured internet rate. Faster when usable > internet, slower
  /// when below, "about the same" within +/-10%. Returns null (the line is
  /// suppressed) when the internet side could not be measured or is ~0 — the
  /// honest neutral verdict line then carries the result on its own (GL-005: the
  /// figure is only ever shown from real measured numbers, never fabricated).
  String? _comparisonLine(ConsumerVerdict verdict) {
    final double? usable = _engine?.usableWifiMbps;
    final double? internet = _engine?.internetMbps;
    // Suppress when either side is missing or the internet rate is ~0 (no truthful
    // denominator). The verdict line already states the honest couldn't-check.
    if (usable == null || internet == null || internet < 0.5) return null;
    return ConnectionComparison.phrase(usable, internet);
  }

  // ---- Result: the plain help-desk facts ----

  /// The plain facts, as label/value rows. Any field not measured prints
  /// "Not measured" — never blank, never invented (GL-005).
  List<_Fact> _facts() {
    final QualityResult? net = _internet;
    // Read the UNIFIED RF source so the consumer Wi-Fi name (and every fact
    // derived from the link) matches what the live card shows on screen.
    final ConnectedAp? ap = _effectiveAp;

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

  /// The Responsiveness copy row — the ONLY place TMC shows RPM to a user.
  ///
  /// THE THREE NULLS, TOLD APART (Keith, 2026-07-14). This row used to read
  /// `rpm != null ? '$rpm RPM' : 'Not measured'`, built from
  /// `ConnectionCheck.metricValue`, which returns a bare `double?` and THROWS THE
  /// NOTE AWAY. So three completely different outcomes printed the same six
  /// characters:
  ///   * the probe ran and FAILED               ("Measurement failed")
  ///   * the user DECLINED the speed test        (kSkippedNote)
  ///   * we CHOSE not to measure it on cellular  (kResponsivenessCellularNote)
  /// A user reading "Not measured" could not tell which, and neither could a
  /// help-desk engineer reading their pasted results. The engine knew — it stamps
  /// the reason on the metric — and the UI discarded it. So read the METRIC, not
  /// the value, and print what the engine actually said.
  ///
  /// It also carries the RFC 9097 caveat onto the MEASURED value. The probe's own
  /// docstring says this is "a directional indicator, not a standards-conformant
  /// RPM value. Do not present it as one." — and this row was presenting a bare
  /// "1234 RPM", which is exactly presenting it as one.
  static String _responsivenessCopy(QualityResult? net) {
    final QualityMetric? m = net?.metric(MetricIds.responsiveness);
    if (m == null) return 'Not measured';
    if (m.isAvailable) {
      return '${m.value!.round()} RPM (simplified single-flow estimate, '
          'not a standards RPM)';
    }
    // The engine's own words for WHY there is no number. Never a bare null.
    return m.note ?? 'Not measured';
  }

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
    // NOTE: Responsiveness deliberately does NOT go through metricValue(). That
    // helper returns a bare double and discards the metric's note — which is the
    // whole reason three different nulls used to print as one "Not measured".
    // See [_responsivenessCopy].

    final ConsumerVerdict? v = _verdict;
    // The UNIFIED RF source: the one-shot link read folded with the live
    // sampler's latest reading (the same source the on-screen sparklines bind
    // to). This is the fix for the copy-vs-live mismatch — the copy now
    // serializes exactly the RF the user sees live, never a stale/empty
    // one-shot read while the sparklines show data (GL-005).
    final ConnectedAp? ap = _effectiveAp;

    final StringBuffer buf = StringBuffer();

    // ── Header ──────────────────────────────────────────────────────────────
    buf.writeln('WLAN Pros Toolbox: Connection Report');
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
      // THE TWO KINDS OF NULL, NAMED (GL-005). The empty rows above mean one of
      // two completely different things, and the help-desk reader must not have to
      // guess which:
      //   * NOT ON WI-FI — there was no Wi-Fi link to read. Nothing to capture, no
      //     Shortcut to install. Telling this reader to tap "Capture Wi-Fi details"
      //     sends them chasing a read that cannot exist (cold-eyes F2).
      //   * ON WI-FI, RF NOT CAPTURED — a real link, but the companion Shortcut has
      //     not harvested its RF yet. That IS a capture step, and the note says so.
      if (_resultNotOnWifi)
        const _CopyRow(
          'Note',
          'This device was not connected to Wi-Fi when the check ran, so there '
              'was no Wi-Fi link to measure. The internet figures below came over '
              'cellular or a wired connection.',
        )
      else if (_canOfferWifiCapture && !_iosRfCaptured)
        const _CopyRow(
          'Note',
          'Wi-Fi signal details not captured. Tap "Capture Wi-Fi details" in '
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
      _CopyRow('Responsiveness', _responsivenessCopy(net)),
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
    // sandbox-safe. DHCP server + DNS server(s) are REAL on Android (the OS
    // exposes them) and honestly unavailable on iOS/macOS; when a value is
    // null/empty its precise per-platform reason is shown, never a guess. VLAN
    // is a true platform fact on every OS (GL-005 / GL-008).
    final NetworkDetails nd = _networkDetails ?? NetworkDetails.empty;
    _copySection(buf, 'NETWORK', <_CopyRow>[
      _CopyRow('Local IP address', nd.localIp ?? 'Not available'),
      _CopyRow('Subnet mask', nd.subnetMask ?? 'Not available'),
      _CopyRow('Default gateway', nd.gateway ?? 'Not available'),
      _CopyRow('DHCP server', nd.dhcpServer ?? nd.dhcpReason),
      _CopyRow(
        'DNS server(s)',
        nd.dnsServers.isNotEmpty ? nd.dnsServers.join(', ') : nd.dnsReason,
      ),
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

    // ── How to read this report ──────────────────────────────────────────────
    // A single plain-text pointer to the published guide, the very last line of
    // the report so a help-desk reader knows where to learn what each datum
    // means. The page resolves once it is published at wlanprofessionals.com.
    buf.writeln('');
    buf.writeln(
      'How to read this report: '
      'https://wlanprofessionals.com/toolbox/connection-report-guide',
    );

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

  // ---- Analyze Results (local, in-app report) ----

  /// Builds the [AnalyzeInput] from the SAME live result state the report and
  /// copy text already read — directly from the in-memory models, never by
  /// re-parsing the copy text. Pure local evaluation; no network, nothing
  /// stored (GL-005 / GL-008).
  AnalysisReport _buildAnalysisReport() {
    final List<SiteReachability> cloud = _cloudResults;
    return AnalyzeEngine.analyze(
      AnalyzeInput.fromConnectionState(
        ap: _effectiveAp,
        internet: _internet,
        engine: _engine,
        dns: _dnsResult,
        cloudReachable: cloud.isEmpty
            ? null
            : cloud.where((SiteReachability s) => s.reachable).length,
        cloudTotal: cloud.isEmpty ? null : cloud.length,
        platformIsIos: _isIos,
        wifiSignalCaptured: _iosRfCaptured,
        // Separates "the Shortcut has not captured the RF yet" (R-31: tap Capture)
        // from "there was no Wi-Fi link at all" (R-31 must stay silent — cold-eyes
        // F2). Both arrive here as `wifiSignalCaptured: false`.
        notOnWifi: _resultNotOnWifi,
        speedTestSkipped: _resultSpeedTestSkipped,
      ),
    );
  }

  /// The plain-text payload for the Analyze report's own Copy action: a titled
  /// header, then each finding as `Category: Verdict-WORD` + its explanation, in
  /// the same order shown on screen. Plain text only (no markdown). Returns null
  /// when there is nothing to analyze (empty report) so Copy renders disabled.
  ///
  /// §7 CONTENT CONTRACT (GL-003 §8.16, load-bearing): every on-screen verdict
  /// the report carries with a §8.13 status hue MUST appear here as its WORD,
  /// using the SAME [AnalysisFinding.verdictWord] the on-screen [StatusChip]
  /// shows, so no verdict survives as color-only on the clipboard. Zero
  /// em-dashes: the category-and-verdict line uses a colon, not a dash.
  String? _buildAnalysisCopyText(AnalysisReport report) {
    if (!report.hasFindings) return null;
    final StringBuffer buf = StringBuffer();
    buf.writeln('WLAN Pros Toolbox: Connection Analysis');
    buf.writeln('Generated: ${_formatTimestamp(_testedAt)} on $_platformLabel');
    buf.writeln('');
    // The §7 body, every verdict carried as its WORD, lives in the pure,
    // unit-tested [analysisReportToPlainText] so the on-screen chip word and
    // the clipboard word can never drift.
    buf.writeln(analysisReportToPlainText(report));
    buf.writeln('');
    buf.writeln('Analyzed on your device. Nothing is sent or stored.');
    return buf.toString().trimRight();
  }

  /// Opens the in-app Analyze Results report for the current result. No-op while
  /// a run is in flight or before a verdict exists (the button is hidden then).
  void _openAnalyze() {
    if (_running || _verdict == null) return;
    final AnalysisReport report = _buildAnalysisReport();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnalyzeResultsScreen(
          report: report,
          copyTextBuilder: () => _buildAnalysisCopyText(report),
        ),
      ),
    );
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
      // Shortcuts-app presence gate + post-install priming flag (mirrors the
      // Wi-Fi Information tool; the one combined Shortcut drives both).
      isShortcutsAppInstalled: bridge.isShortcutsAppInstalled,
      onSetupInitiated: bridge.markSetupInitiated,
      // UX-2: reverse the button emphasis once setup has already been started.
      hasInitiatedSetup: bridge.hasInitiatedSetup,
      onInstalled: () async {
        // Persist the global onboarding-seen flag the moment the user completes
        // the install hand-off, so no OTHER live tool re-prompts in the window
        // before the first Live payload lands (null-safe; never throws).
        await _onboardingService?.markOnboardingSeen();
        // _run() auto-captures iOS RF (the priming one-shot) as part of the check.
        // It asks for throughput; the chokepoint withholds it on an unconsented
        // metered link, so finishing Shortcut setup can never spend cellular data.
        if (mounted) _run(includeThroughput: true);
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
// ANALYZE button — opens the local, in-app plain-language report.
// ===========================================================================

/// The "Analyze my results" affordance: a full-width §8.3 secondary (outline)
/// button beneath the verdict. It opens the [AnalyzeResultsScreen] report,
/// computed locally from the same result data. It sits ALONGSIDE the AppBar's
/// Copy action — Copy saves the raw report; Analyze explains it.
class _AnalyzeButton extends StatelessWidget {
  const _AnalyzeButton({required this.onAnalyze});

  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Analyze my results',
      child: ExcludeSemantics(
        child: OutlinedButton.icon(
          onPressed: onAnalyze,
          icon: const Icon(Icons.insights_outlined, size: 20),
          label: const Text('Analyze my results'),
        ),
      ),
    );
  }
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
    this.runAgainUsesData = false,
  });

  final ConsumerVerdict verdict;
  final String heroSentence;

  /// Re-runs the whole check. Rendered as the unmistakable LABELED "Run again"
  /// control on the hero-sentence row (the AppBar carries only a compact
  /// icon-only refresh so the title never truncates — Vera 2026-06-14). Null
  /// while a run is in flight; the control is then omitted.
  final VoidCallback? onRunAgain;

  /// Whether that re-run will spend CELLULAR data, so the button's own label can
  /// say so. See [_HeroRunAgainButton.usesData] for the consent-scope decision.
  final bool runAgainUsesData;

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
      // "You are online" is a calm, reachable-but-unmeasured read: neutral info
      // tone, not success (no speed was verified) and not warning (nothing is
      // wrong with the link).
      case ConsumerOutcome.online:
      // A captive portal is not a FAULT — the Wi-Fi works and the fix is one tap in
      // a browser. Info, not warning: nothing is broken, something is asked of you.
      case ConsumerOutcome.signInRequired:
        return StatusTone.info;
      // A DEAD INTERNET IS A REAL FAULT AND IT GETS THE WARNING TONE. Every other
      // "no number" row above is neutral because nothing is wrong; here something is
      // very wrong, and it is the one thing on the card the user must act on.
      case ConsumerOutcome.internetDown:
        return StatusTone.warning;
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
          // dynamic type, §8.9.
          //
          // FULL-WIDTH RULE (Keith, iPhone 2026-06-15): the verdict sentence
          // owns the ENTIRE card width and wraps across the whole screen — it
          // is NO LONGER in a Row that shares horizontal space with the re-run
          // control. A prior round put a trailing "Run again" on this row; at
          // iPhone widths (375–430) that button stole the right portion of the
          // line and squeezed the sentence into a narrow left column that
          // wrapped awkwardly. The button now lives on its OWN row directly
          // beneath the sentence (see below), so the sentence reads full-width.
          //
          // The sentence is part of the card's single merged SR summary, so its
          // own node is excluded here (the outer Semantics below speaks it).
          ExcludeSemantics(
            child: Text(
              heroSentence,
              style: text.headlineLarge?.copyWith(color: colors.textPrimary),
            ),
          ),
          // The unmistakable LABELED "Run again" control on its OWN row directly
          // beneath the verdict sentence — clearly visible (Keith's hard
          // requirement) but NOT competing with the sentence for horizontal
          // space. Trailing-aligned so it reads as a discrete secondary action.
          // It is an interactive control and MUST keep its own live semantics —
          // so it is NOT wrapped in ExcludeSemantics (the blanket card-level
          // exclusion was dropped for exactly this reason).
          if (onRunAgain != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: _HeroRunAgainButton(
                onRunAgain: onRunAgain!,
                usesData: runAgainUsesData,
              ),
            ),
          ],
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

/// The unmistakable LABELED "Run again" control on its OWN row directly beneath
/// the verdict-hero sentence — the primary re-run affordance (the AppBar carries
/// only the §8.16 copy action so the full "Test My Connection" title clears at
/// every iPhone width). It sits on a dedicated row (trailing-aligned) rather than
/// sharing the sentence row, so the verdict sentence reads full-width on a narrow
/// iPhone instead of being squeezed into a left column (Keith, 2026-06-15).
/// Visible "Run again" text + the `Icons.refresh` glyph; re-runs the WHOLE check.
/// Carries the 'Run the test again' Semantics label and the §8.3 44pt touch
/// target. Lime accent (theme-aware: brand lime in dark, darkened-lime via
/// textAccent in light so it stays legible on the white card).
class _HeroRunAgainButton extends StatelessWidget {
  const _HeroRunAgainButton({
    required this.onRunAgain,
    this.usesData = false,
  });

  final VoidCallback onRunAgain;

  /// Whether tapping this button will spend CELLULAR data (round-4b, 2026-07-14).
  ///
  /// THE CONSENT LATCH, AND WHY THE LABEL IS THE FIX. `_throughputConsented` is
  /// scoped to the MOUNT: it is set once, by the cost-labelled tap on the pre-run
  /// screen, and never reset. That is deliberate — re-interrogating a user who has
  /// already said yes, on every single re-run, is nagging — but it left this button
  /// LYING. Once the result screen replaced the pre-run card (`if (verdict == null)
  /// _actionCard(...)`), the ONLY re-run control was a bare "Run again" with NO cost
  /// label, sitting above a warning the user could no longer see. Consent once on
  /// cellular, and every subsequent tap silently spent ANOTHER 50-500 MB. Warned
  /// once, charged N times.
  ///
  /// THE SCOPE OF CONSENT, DECIDED AND DOCUMENTED: consent is PER-MOUNT for the
  /// FLAG, but EVERY BUTTON THAT CAN SPEND CELLULAR DATA CARRIES THE COST IN ITS
  /// OWN LABEL. So every spend is still preceded by a cost-labelled tap — which is
  /// per-run consent in substance, and is exactly the standard the pre-run button
  /// already meets ("the tap IS the consent... the button's own label carries the
  /// cost"). The user is never re-interrogated, and never uninformed.
  final bool usesData;

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
    //
    // Off Wi-Fi WITH consent already given, the SR label states the cost too — a
    // screen-reader user must not be the only one who cannot see what the tap
    // spends.
    return Semantics(
      button: true,
      label: usesData
          ? 'Run the test again, which uses cellular data'
          : 'Run the test again',
      child: ExcludeSemantics(
        child: TextButton.icon(
          onPressed: onRunAgain,
          icon: Icon(Icons.refresh, size: 20, color: accent),
          label: Text(
            usesData ? 'Run again (uses data)' : 'Run again',
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
      case AxisStatus.notApplicable:
        // NOT "Couldn't check" (Keith, 2026-07-13, cellular-only iPhone). The app
        // KNOWS there is no Wi-Fi — it is not a read that failed, it is a link
        // that is not there. Saying "Couldn't check" here claims a failure that
        // did not happen and sends the user hunting for it. See
        // [AxisStatus.notApplicable].
        return 'Not connected';
      case AxisStatus.notMeasured:
        // Also NOT "Couldn't check": the user declined the cellular-data cost, so
        // the speed test never ran. Nothing failed. See [AxisStatus.notMeasured].
        return 'Not measured';
      case AxisStatus.reachableUnmeasured:
        // Also NOT "Couldn't check" (Keith, 2026-07-14, cellular). We reached the
        // internet — DNS, public IP and cloud apps all answered — and only the
        // SPEED test failed. The old word claimed a failed check about a check
        // that succeeded, one line above the body text saying "Your internet is
        // reachable". Name what we actually do not know: the speed.
        return 'Speed unknown';
      case AxisStatus.unreachable:
        // AND ALSO NOT "Couldn't check" — from the OTHER direction (Keith, conference
        // SSID, 2026-07-14). We checked the internet THREE WAYS and every one came
        // back NO. "Couldn't check" claims a failed read about a read that SUCCEEDED
        // and returned a definitive negative. That word, on this state, is what put
        // "Internet: Couldn't check" next to a red "Wi-Fi: Weak" and sent a man to
        // fix a Wi-Fi link that was doing 97/77 Mbps. Say what we measured.
        return 'Not reachable';
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
      // THE ONE "NO NUMBER" STATE THAT IS GENUINELY A FAULT, AND THE ONLY ONE THAT
      // MAY WEAR RED. Every neutral state below it means "there is no number here,
      // and that is fine". This one means the user's internet is DOWN. §8.13 rule 2
      // forbids forcing a fault color onto an ABSENT value — it does not forbid
      // naming an actual fault, and dressing a dead internet in the same calm gray as
      // "we chose not to measure" would be its own small lie. The WORD ("Not
      // reachable") still carries it without the color (WCAG 2.2 SC 1.4.1).
      case AxisStatus.unreachable:
        return colors.statusDanger;
      case AxisStatus.unknown:
      case AxisStatus.notApplicable:
      case AxisStatus.notMeasured:
      case AxisStatus.reachableUnmeasured:
        // Light: neutral textSecondary #4A4A4A fill, matching the _GradeChip
        // no-hue fills across TMC / wifi_info / net_quality. Dark stays on
        // textTertiary so the dark render is byte-identical.
        //
        // `notApplicable` shares the NEUTRAL treatment on purpose: "there is no
        // Wi-Fi here" is not a fault and must not wear a danger hue (§8.13 rule
        // 2 — never force a fault color onto an absent value, GL-005). The WORD
        // ("Not connected") carries the meaning, so the two neutral states stay
        // distinguishable without color (WCAG 2.2 SC 1.4.1).
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
      case AxisStatus.notApplicable:
        // A DIFFERENT glyph from `unknown` on purpose: these are two different
        // truths and the chip must not blur them. `help_outline` ("we don't
        // know") would be as wrong as the "Couldn't check" word it replaces — we
        // DO know. `link_off` reads "not connected" without the fault load that
        // §1.1 rules out for error / cancel / block / remove. Axis-agnostic, so it
        // stays correct if a future axis is ever legitimately absent.
        return light ? Icons.link_off : Icons.link_off_outlined;
      case AxisStatus.notMeasured:
        // A THIRD distinct glyph. `help_outline` ("we don't know") and `link_off`
        // ("there is nothing there") are both wrong: the internet is there, and we
        // know we did not measure it. `pending` reads "not done", carries no fault
        // (§1.1 rules out error / cancel / block / remove), and keeps the three
        // neutral states separable without color (WCAG 2.2 SC 1.4.1).
        return light ? Icons.pending : Icons.pending_outlined;
      case AxisStatus.reachableUnmeasured:
        // A FOURTH distinct glyph, for the same reason the other three are
        // distinct: these are four different truths and the chip must not blur
        // them. `help_outline` ("we don't know") is wrong — we DO know the
        // internet is reachable. `link_off` ("nothing there") is wrong — it is
        // there. `pending` ("not done") is wrong — the test ran, it failed.
        // `speed` names the one thing we could not obtain, carries no fault glyph
        // (§1.1 rules out error / cancel / block / remove), and keeps all four
        // neutral states separable WITHOUT color (WCAG 2.2 SC 1.4.1).
        return light ? Icons.speed : Icons.speed_outlined;
      case AxisStatus.unreachable:
        // A FIFTH distinct glyph, and the ONLY one of the five allowed to read as a
        // fault — because it IS one. `cloud_off` says exactly what happened: the
        // internet is not there. It is the mirror of `reachableUnmeasured`'s `speed`
        // (we got there, could not time it) and the opposite of `unknown`'s
        // `help_outline` (we do not know) — here we know, and the answer is no.
        return light ? Icons.cloud_off : Icons.cloud_off_outlined;
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
        // TWO KINDS OF NULL (GL-005, 2026-07-13). "We could not read your Wi-Fi"
        // implies a read that might succeed on a retry. Off Wi-Fi there is
        // nothing to read at all — say that, and never imply a fix that cannot
        // work. The could-not-read wording stands for every ambiguous case
        // (wired, Location-gated, iOS without the companion Shortcut).
        if (result.notOnWifi) {
          return result.internetMbps == null
              ? 'You are not connected to Wi-Fi, so there is no Wi-Fi link to '
                  'measure. Join a Wi-Fi network and check again.'
              : 'You are not connected to Wi-Fi, so there is no Wi-Fi link to '
                  'compare against. Only the internet side is shown.';
        }
        return result.internetMbps == null
            ? 'We could not read your Wi-Fi link, so there is nothing to '
                'compare the internet against yet.'
            : 'We could not read your Wi-Fi link, so only the internet side is '
                'shown.';
      case WifiVsInternetVerdict.onlineUnmeasured:
        // The speed test stalled but reachability confirms the link is up;
        // lead with the reachable truth, never "could not read".
        return 'Your internet is reachable, but the speed test did not '
            'complete, so there is no speed to compare yet. Try again in a '
            'moment.';
      // ROUND 5. THERE IS NOTHING TO COMPARE, AND SAYING SO IS THE POINT. Note what
      // this row does NOT do: it does not reach for "Boost the Wi-Fi signal", which
      // is what the two rows at the top of this switch say and what this shape used
      // to fall through toward. The Wi-Fi is not the story. There is no internet bar
      // to draw because there is no internet.
      case WifiVsInternetVerdict.internetUnreachable:
        return result.usableWifiMbps == null
            ? 'The internet is not reachable, so there is no internet speed to '
                  'compare against.'
            : 'Your Wi-Fi link is carrying '
                  '${_fmtMbps(result.usableWifiMbps)} of usable capacity. There '
                  'is no internet speed to compare it against, because the '
                  'internet is not reachable.';
      case WifiVsInternetVerdict.captivePortal:
        return result.usableWifiMbps == null
            ? 'This network has not let you onto the internet yet, so there is '
                  'no internet speed to compare against.'
            : 'Your Wi-Fi link is carrying '
                  '${_fmtMbps(result.usableWifiMbps)} of usable capacity. There '
                  'is no internet speed to compare it against until you sign in '
                  'to this network.';
    }
  }

  /// Formats a Mbps figure for the reading lines. Whole numbers drop the decimal.
  static String _fmtMbps(double? v) {
    if (v == null) return 'n/a';
    final double r = (v * 10).round() / 10;
    return r == r.roundToDouble()
        ? '${r.toStringAsFixed(0)} Mbps'
        : '${r.toStringAsFixed(1)} Mbps';
  }

  /// The same-tier reading line, or null when the two rates are NOT on the same
  /// real tier (the caller then falls through to the engine-verdict wording).
  ///
  /// Buckets the SAME two rates the bars draw — [WifiVsInternetResult.usableWifiMbps]
  /// and [WifiVsInternetResult.internetMbps] — into Strong / Moderate / Weak via
  /// [AxisStatusThresholds.tierFor], the EXACT source the consumer chips use, so
  /// "same tier" here means the same thing the chips show. Fires only when both
  /// rates are real (non-null, internet not ~0) and land on the same real tier;
  /// then it words the line by the +/-10% margin band (matching the hero, the
  /// secondary line, and the % comparison line) and never names either side "the
  /// weak link" / "boost the Wi-Fi" / "the slower part". Null otherwise (GL-005).
  String? _sameTierReadingLine() {
    final double? usable = result.usableWifiMbps;
    final double? internet = result.internetMbps;
    if (usable == null || internet == null || internet < 0.5) return null;

    final AxisStatus wifiTier = AxisStatusThresholds.tierFor(usable);
    final AxisStatus internetTier = AxisStatusThresholds.tierFor(internet);
    // THE THIRD SAME-TIER GUARD (round-4 F1 review). It cannot call
    // [ConsumerVerdict.sameRealTier] — it derives its tiers from the RATES, not from
    // a verdict's axis statuses — but it must not keep its own blacklist either.
    // `isRealTier` is the shared WHITELIST all three guards now agree on, so a new
    // AxisStatus cannot start producing "both sides are <new state>" through the one
    // guard someone forgot to update. (That is precisely how `notMeasured` slipped
    // past the other two.)
    if (wifiTier != internetTier || !wifiTier.isRealTier) return null;

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
    final double? internet = result.internetMbps;

    // Shared scale: the larger of the two figures is full width, so the bars are
    // directly comparable. When one side is unknown, the other still draws.
    final double scaleMax = <double>[
      usable ?? 0,
      internet ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final double safeMax = scaleMax <= 0 ? 1 : scaleMax;

    // "Unavailable" is the right word for a figure we FAILED to obtain. It is the
    // wrong word for a link that does not exist — that is the same two-kinds-of-null
    // error as the `Wi-Fi: Couldn't check` chip (Keith, 2026-07-13). When the probe
    // positively says there is no Wi-Fi, the Wi-Fi side of this comparison is NOT
    // APPLICABLE, and there is nothing to compare against. Read it off the model's
    // own flag, not off a null rate — the null cannot tell the two apart.
    final String wifiValue = result.notOnWifi
        ? 'Not connected'
        : (usable != null ? '${usable.round()} Mbps' : 'Unavailable');
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
  const _LiveSignalCard({
    required this.sampler,
    required this.onSetUp,
    required this.onRetryConnection,
  });

  final WifiSignalSampler sampler;

  /// Opens the one-time companion-Shortcut install sheet. The header CTA shows
  /// "Set up" only when the Shortcut is not set up AND setup has not been started;
  /// otherwise the single live action is Start (sampler.start). Set up never
  /// blind-fires the Shortcut, so a clean install never strands the user.
  final VoidCallback onSetUp;

  /// Re-runs the connection probe + install-state resolve. Wired to the
  /// not-on-Wi-Fi state's "Check again" action so a user who has just joined
  /// Wi-Fi can re-check in place.
  final VoidCallback onRetryConnection;

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
                  if (sampler.notOnWifi)
                    // NOT-ON-WIFI (2026-06-25): the device is demonstrably off
                    // Wi-Fi (e.g. cellular). No Start / Set up CTA — there is no
                    // Wi-Fi link to read; the body carries the honest "connect to
                    // Wi-Fi" state with its own "Check again" action.
                    const SizedBox.shrink()
                  else if (sampler.isIos &&
                      !sampler.isStreaming &&
                      !sampler.hasEverReceived &&
                      !sampler.setupInitiated)
                    // COLD (not set up, setup not started): Set up opens the
                    // install sheet — never a Start that would blind-fire a
                    // not-yet-installed Shortcut.
                    Semantics(
                      button: true,
                      label: 'Set up live Wi-Fi',
                      child: OutlinedButton.icon(
                        onPressed: onSetUp,
                        icon: const SetupLiveWifiIcon(size: 18),
                        label: const Text('Set up'),
                      ),
                    )
                  else if (sampler.isIos && !sampler.isStreaming)
                    // SET UP OR PRIMING (2026-06-26, Option A): the ONE live action
                    // is Start Live Monitoring. In priming the first delivered
                    // sample flips hasEverReceived and clears priming; the
                    // Start-aware settle surfaces recovery if the Shortcut is gone.
                    Semantics(
                      button: true,
                      label: 'Start live monitoring',
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
              if (sampler.notOnWifi) ...<Widget>[
                // NOT-ON-WIFI (2026-06-25): the device is demonstrably off Wi-Fi
                // (e.g. cellular-only). Replace the walk-around tip + waiting/
                // setup states with the honest "connect to Wi-Fi" surface, scoped
                // to this section, with its own "Check again" retry. The
                // walk-around tip is meaningless with no Wi-Fi link, so it is
                // suppressed here.
                NotOnWifiCard(
                  onRetry: onRetryConnection,
                  title: "You're not connected to Wi-Fi",
                  message:
                      'Connect to a Wi-Fi network to see your live Wi-Fi signal. '
                      'On cellular or a partly-joined network, there is no Wi-Fi '
                      'link to read.',
                ),
              ] else ...<Widget>[
              // Walk-around tip (item #6) — invites the user to move while the
              // live feed runs so they see the signal change spot to spot.
              Text(
                'Walk around while this runs to see how your Wi-Fi signal '
                'changes from spot to spot.',
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (sampler.isIos &&
                  (sampler.triggerError || sampler.shortcutMissing) &&
                  !(sampler.isStreaming && !series.isEmpty)) ...<Widget>[
                // BOTH error cases surface the same recovery note: the trigger
                // could not open ([triggerError]) OR it opened but a deleted
                // "WLAN Pros Live" Shortcut delivered nothing ([shortcutMissing],
                // set asynchronously after the settle). In-context recovery for
                // users who removed the Shortcut. CONTRADICTION GUARD (2026-06-26):
                // suppressed while genuinely live with data, so the card never
                // reads "could not start" and "LIVE" at once.
                _LiveUnavailableNote(
                  message:
                      'Could not start the live Wi-Fi feed. The companion '
                      '"WLAN Pros Live" Shortcut may not be installed. Install '
                      'it, then tap Start Live Monitoring.',
                ),
              ] else if (series.isEmpty) ...<Widget>[
                _LiveUnavailableNote(
                  // iOS, NOT set up → the honest "set it up first" message paired
                  //   with the header "Set up" button.
                  // iOS, setup started but no payload yet (PRIMING) → the honest
                  //   "tap Start Live Monitoring to finish; iOS asks permission the
                  //   first time" step paired with the header "Start" button.
                  // iOS, set up but not yet started → invite the deliberate Start.
                  // iOS, started but the first sample has not landed yet → an
                  //   HONEST "waiting" indicator (the Shortcut WAS fired; we are
                  //   genuinely waiting on it, never a fake "LIVE" with nothing
                  //   behind it). macOS auto-polls, so it is simply reading.
                  message: sampler.isIos
                      ? (!sampler.hasEverReceived
                          ? (sampler.setupInitiated
                              ? 'Almost set up. Tap Start Live Monitoring to '
                                  'finish. The first time it runs, iOS asks to '
                                  'allow the "WLAN Pros Live" Shortcut to share '
                                  'your network details, so tap Always Allow. If '
                                  'that first tap is interrupted, tap Start Live '
                                  'Monitoring once more.'
                              : 'Live Wi-Fi signal needs the one-time "WLAN Pros '
                                  'Live" companion Shortcut. Tap Set up to add it, '
                                  'then this card streams your signal.')
                          : sampler.isStreaming
                              ? 'Starting the live Wi-Fi feed from the companion '
                                  'Shortcut. The first reading should arrive in a '
                                  'moment…'
                              : 'Tap Start to begin live Wi-Fi signal readings '
                                  'from the companion Shortcut.')
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
              ], // close the `else` (on-Wi-Fi) branch of the notOnWifi gate
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
          // Muted helper line directly under the copy button: tells the user
          // what the copied report is FOR. Quiet textTertiary (GL-003 §8.2,
          // 6.3:1 dark / 5.7:1 light, both pass SC 1.4.3 AA normal text), the
          // §4 half-step gap above so it reads as attached to the button, not a
          // new block. Plain language, no em-dashes, never a bare "AP".
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Paste this into an email or text to your IT or support team.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
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
        // DHCP server / DNS server(s) — REAL on Android (WifiManager.getDhcpInfo
        // + ConnectivityManager link properties), structurally unavailable on
        // iOS/macOS (no sandbox-safe source). When the value is present it shows;
        // when it is null/empty the row shows the design system's muted
        // "Unavailable" value with the precise per-platform reason beneath, so it
        // reads as an honest fact, not a fabricated address (GL-005).
        _DataRow(
          label: 'DHCP server',
          value: d?.dhcpServer,
          mono: true,
          note: (d?.dhcpServer == null)
              ? (d?.dhcpReason ?? NetworkDetails.defaultUnavailableReason)
              : null,
        ),
        // DNS server(s) — rendered ONE RESOLVER PER LINE (valueLines), each
        // wrapping with no ellipsis, so a long IPv6 resolver never truncates or
        // overflows the narrow value column (Vera 2026-06-26). Native already
        // emits canonical compressed IPv6; the per-line wrap covers the case
        // where even a compressed address exceeds the column on a small phone.
        _DataRow(
          label: 'DNS server(s)',
          value: null,
          valueLines: (d != null && d.dnsServers.isNotEmpty)
              ? d.dnsServers
              : null,
          mono: true,
          note: (d == null || d.dnsServers.isEmpty)
              ? (d?.dnsReason ?? NetworkDetails.defaultUnavailableReason)
              : null,
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
    this.locationHint,
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

  /// macOS-only: the on-screen Location hint (network name hidden + action), or
  /// null off macOS / when Location is authorized.
  final _MacLocationHint? locationHint;

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
          locationHint: locationHint,
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
      case WifiVsInternetVerdict.onlineUnmeasured:
      // A sign-in page is not a fault: informational, and one tap from fixed.
      case WifiVsInternetVerdict.captivePortal:
        return colors.statusInfo;
      // A dead internet IS a fault. It is the one thing on this card that is
      // genuinely broken, and it is not the Wi-Fi.
      case WifiVsInternetVerdict.internetUnreachable:
        return colors.statusDanger;
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
      case WifiVsInternetVerdict.onlineUnmeasured:
        // Reachable-but-unmeasured: the "you're online" cloud-done glyph, not a
        // question mark (that side is not unknown, just unmeasured for speed).
        return Icons.cloud_done_outlined;
      case WifiVsInternetVerdict.internetUnreachable:
        // The mirror of `cloud_done`. NOT `help_outline` — we are not confused, the
        // internet is not there. (`upstream` also uses `cloud_off`, and that is
        // right: both are "the problem is past your Wi-Fi". One is slow, one is
        // absent, and the WORD distinguishes them.)
        return Icons.cloud_off_outlined;
      case WifiVsInternetVerdict.captivePortal:
        // Not a cloud glyph at all: nothing is broken and nothing is missing. You
        // are being asked for a key.
        return Icons.login_outlined;
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

/// The data the on-screen macOS Location hint needs: whether the state is
/// PROMPTABLE (drives the button label + action) and the action callback.
@immutable
class _MacLocationHint {
  const _MacLocationHint({required this.promptable, required this.onAction});

  /// True when the status is `notDetermined` — the button fires the native
  /// prompt ("Allow Location access"). False when `denied` / `restricted` — the
  /// button deep-links to System Settings ("Open Location settings").
  final bool promptable;

  /// The hint's button action: fire the prompt (promptable) or open settings.
  final Future<void> Function() onAction;
}

/// A compact, single inline note shown where the Wi-Fi network name would sit
/// when macOS withholds the SSID/BSSID for lack of Location authorization.
///
/// Tasteful and low-profile per GL-003: a §8.13 info-toned hairline-outlined
/// row (icon + one line of copy + a tertiary text button), NOT a full callout
/// card — it adds one row of height, not a block. The meaning is carried by the
/// TEXT, never color alone (§8.13 rule 2). The button is a §8.3 tertiary text
/// button (lime label) inheriting the global focus ring; its 44pt touch target
/// is met by the FilledButton/TextButton min-size theme.
class _LocationNameHint extends StatelessWidget {
  const _LocationNameHint({required this.hint});

  final _MacLocationHint hint;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    // PROMPTABLE → the native prompt can appear; DENIED/RESTRICTED → only the
    // System Settings deep-link will help. The button copy names which it is.
    final String action =
        hint.promptable ? 'Allow Location' : 'Open settings';
    const String message = 'Wi-Fi network name hidden. Location access needed.';

    return Semantics(
      container: true,
      // The full hint reads as one node: the fact + the action it offers.
      label: '$message. Button: $action.',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        // §8.13 rule 6: a Location-permission hint is an active call-to-action,
        // NOT a computed verdict, so it must use NEUTRAL surface + border, never
        // a status* token. Neutral surface1 fill + neutral hairline border; the
        // location_off icon is quiet textTertiary; the only active accent is the
        // button's lime textAccent label (the §8.3 interactive role).
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colors.border, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.location_off_outlined,
              size: 16,
              color: colors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                message,
                style: text.bodySmall?.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            // §8.3 tertiary (text) button: lime label, no fill/border. Carries
            // the global icon/text focus ring; 44pt min target from the theme.
            TextButton(
              onPressed: () {
                // Fire-and-forget: the action re-reads auth + setState itself.
                hint.onAction();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xxs,
                ),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: Text(
                action,
                style: text.labelLarge?.copyWith(
                  color: colors.textAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
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
    this.locationHint,
  });

  final ConnectedAp? ap;
  final WifiVsInternetResult result;

  /// iOS-only: true when the companion Shortcut has not captured the RF metrics.
  /// The card then leads with a "Tap to capture Wi-Fi details" affordance so the
  /// empty RF block reads as a capture step, not a broken tool (GL-005 / GL-008).
  final bool needsCapture;

  /// Opens the one-time companion-Shortcut setup/capture sheet. Null off iOS.
  final VoidCallback? onCapture;

  /// macOS-only: the on-screen Location hint (network name hidden + action),
  /// shown at the TOP of the card where the network name would sit. Null off
  /// macOS / when Location is authorized (the name then populates normally).
  final _MacLocationHint? locationHint;

  @override
  Widget build(BuildContext context) {
    final ConnectedAp? a = ap;
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;

    // NO WI-FI LINK AT ALL (Keith, 2026-07-13, cellular-only iPhone). Before this,
    // a card headed "Your Wi-Fi link" rendered SEVEN "Unavailable" rows — Tx rate,
    // Rx rate, Usable capacity, SNR, RSSI, Channel, Standard — plus the caption
    // "55% of no rate reported", which is not a sentence a person should ever be
    // shown. Every one of those rows says "we tried to read this and could not".
    // None of them is true: there was nothing to read.
    //
    // This is the SAME two-kinds-of-null error as the `Wi-Fi: Couldn't check` chip
    // and the stale-rate bug before it (GL-005). Name the real state once, and
    // render no rows — a row with no possible value is not an honest row.
    if (result.notOnWifi) {
      return _SectionCard(
        title: 'Your Wi-Fi link',
        children: <Widget>[
          Text(
            'This device is not connected to Wi-Fi, so there is no Wi-Fi link '
            'to report. The internet figures below were measured over your '
            'cellular or wired connection.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      );
    }

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
            'companion Shortcut, no Location permission needed.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            button: true,
            label: 'Capture Wi-Fi details',
            child: FilledButton.icon(
              onPressed: onCapture,
              icon: const GetReadingIcon(),
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
    final _MacLocationHint? hint = locationHint;
    return _SectionCard(
      title: 'Your Wi-Fi link',
      children: <Widget>[
        // macOS-only: the SSID/BSSID are the ONLY two fields macOS 14+ withholds
        // without Location authorization. When they are gated, show a compact
        // inline hint where the network name would sit — with a one-tap action —
        // so the user sees the fix ON SCREEN rather than only in the copied
        // report. Off macOS / when authorized, [hint] is null and nothing shows.
        if (hint != null) ...<Widget>[
          _LocationNameHint(hint: hint),
          const SizedBox(height: AppSpacing.xs),
        ],
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
    this.valueLines,
  });

  final String label;
  final String? value;
  final String? unit;
  final bool mono;
  final String? note;
  final bool derived;
  final Widget? trailing;

  /// When non-null and non-empty, the value column renders each entry on its
  /// OWN line, wrapping (softWrap, NO ellipsis) instead of the single
  /// ellipsized [value] Text. Used for multi-value address rows (DNS resolvers)
  /// so a long IPv6 literal wraps rather than truncating. The a11y semantic
  /// label folds the entries comma-joined, matching the copy-report form.
  final List<String>? valueLines;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText monoText =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final AppColorScheme colors = context.colors;

    final List<String>? lines = valueLines;
    final bool useLines = lines != null && lines.isNotEmpty;
    final bool hasValue =
        useLines || (value != null && value!.trim().isNotEmpty);
    final String shown = useLines
        ? lines.join(', ')
        : (hasValue
            ? (unit == null ? value! : '${value!} $unit')
            : 'Unavailable');
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
                        // Multi-value rows (DNS) render one entry per line and
                        // WRAP (no ellipsis) so a long IPv6 literal is never
                        // clipped; single-value rows keep the ellipsized Text.
                        child: useLines
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: <Widget>[
                                  for (final String line in lines)
                                    Text(
                                      line,
                                      textAlign: TextAlign.end,
                                      softWrap: true,
                                      style: valueStyle,
                                    ),
                                ],
                              )
                            : Text(
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
  const _ShortcutOfferCard({required this.onOpen, this.prominent = false});

  final VoidCallback onOpen;

  /// When true, the companion Shortcut is NOT yet installed, so this is the
  /// PRIMARY path forward for a clean-install user whose check came back
  /// "Couldn't Check" for Wi-Fi (item #4). It renders the prominent lime
  /// FilledButton with "Set up Live Wi-Fi" copy so the fix is unmissable. When
  /// false the Shortcut IS set up but this run could not read the link, so it
  /// stays the soft optional outline offer.
  final bool prominent;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            prominent
                ? 'Set up live Wi-Fi to read your signal'
                : 'Want a deeper Wi-Fi check?',
            style: text.titleSmall?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            prominent
                ? 'This check could not read your Wi-Fi signal because the '
                    'one-time "WLAN Pros Live" companion Shortcut is not added '
                    'yet. Set it up once and every live tool works. It takes '
                    'about a minute.'
                : 'Add the companion Shortcut to let this app read your Wi-Fi '
                    'details next time. Optional, and it only takes a minute.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (prominent)
            Semantics(
              button: true,
              label: 'Set up live Wi-Fi',
              child: FilledButton.icon(
                onPressed: onOpen,
                icon: const SetupLiveWifiIcon(),
                label: const Text('Set up live Wi-Fi'),
              ),
            )
          else
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
