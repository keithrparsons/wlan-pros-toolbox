// =============================================================================
// Analyze Results, THE RULE LIBRARY (structured data, swappable).
// =============================================================================
//
// RATIFIED RESPONSE COPY, Keith ratified 2026-06-16 + Penn SOP-020 voice pass.
//
// Every `responseDraft` string below is the FINAL, Keith-ratified, Penn-voiced
// copy, dropped in VERBATIM from:
//   Deliverables/2026-06-16-website-connection-analyzer-research/
//     response-library-final.md  (33 rules, 9 categories)
//
// The copy is ship-ready. The two style rules baked into every line are
// non-negotiable on any future edit:
//   1. "Router/Access Point" is the device term throughout. Never bare "AP",
//      never bare "Access Point", never "Router" alone. "router/access point"
//      in a sentence is the intended form for this audience.
//   2. Zero em-dashes. Every pause is a comma, a period, a colon, or a fragment.
//
// WHY THIS IS A DATA FILE: the engine ([AnalyzeEngine]) NEVER hardcodes prose.
// It evaluates each rule's `condition` against an [AnalyzeInput] and renders the
// fired rules' `responseDraft` text. So updating the advice = editing THIS file
// ONLY (swap the string, swap the threshold the condition reads, add/remove a
// rule), no engine change, no UI change.
//
// THRESHOLDS ARE IMPORTED, NEVER DUPLICATED. Each condition reads the SAME
// ratified app constant the rest of the app uses (GL-005, domain-proof):
//   * RSSI / SNR bands, [WifiGradingBands]   (wifi_grading.dart)
//   * latency/jitter/loss/responsiveness/download bands, [QualityScoring]
//     (net_quality scoring.dart), read via the same grade functions
//   * verdict thresholds, [WifiVsInternetVerdict] (wifi_vs_internet.dart)
//   * security labels, [WifiSecurity] (wifi_security.dart)
// Two thresholds have no upstream app constant: the DNS resolution time
// (R-32, 200 ms) and the cloud-latency note (R-42, 250 ms). Both are the named
// [kDnsSlowMs] / [kCloudSlowMs] constants below, ratified by Keith 2026-06-16.
// =============================================================================

import 'package:net_quality/net_quality.dart' show QualityGrade, QualityScoring;

import '../wifi_grading.dart';
import '../wifi_security.dart';
import '../wifi_vs_internet.dart';
import 'analysis_finding.dart';
import 'analyze_input.dart';

/// DNS resolution time (ms) at/above which R-32 fires. Ratified Keith
/// 2026-06-16. The app has no upstream DNS band, so this is the source of truth.
const int kDnsSlowMs = 200;

/// Cloud-app reachability round-trip (ms) at/above which R-42 fires. Ratified
/// Keith 2026-06-16. No upstream app constant, so this is the source of truth.
const int kCloudSlowMs = 250;

/// The link-rate (Mbps) below which a link is treated as "low" for the SNR
/// context rules R-17/R-18. Ported VERBATIM from the app's `_snrContext`
/// `lowRateMbps = 200` in wifi_vs_internet.dart, kept in sync as one number.
const double kLowLinkRateMbps = 200;

/// One rule in the library: its id, category, priority, the [condition] that
/// fires it, and the response text. Editing this object = updating the advice;
/// the engine reads, it does not author.
class AnalyzeRule {
  /// Creates a rule.
  const AnalyzeRule({
    required this.id,
    required this.category,
    required this.severity,
    required this.condition,
    required this.responseDraft,
    this.contextOnly = false,
    this.pendingRatification = false,
  });

  /// Stable id matching response-library-final (e.g. "R-01").
  final String id;

  /// The finding category this rule produces.
  final FindingCategory category;

  /// The priority/severity of the produced finding (P1/P2/P3, critical/
  /// important/context).
  final FindingSeverity severity;

  /// Pure predicate over the input, true when the rule fires. Reads the
  /// imported thresholds; never duplicates a constant.
  final bool Function(AnalyzeInput input) condition;

  /// The final, ratified, conclusion-first response text. Swappable data.
  final String responseDraft;

  /// True for "no problem here" reassurance rules (R-12/R-22/R-30/R-42). The
  /// engine SUPPRESSES these unless at least one non-context finding also fired,
  /// so the report never narrates a non-issue (matches the app's `_snrContext`
  /// stay-quiet discipline).
  final bool contextOnly;

  /// True only while a rule's copy/threshold is not yet ratified. All rules are
  /// ratified as of 2026-06-16, so every rule ships this `false`. The flag and
  /// its rendering path are kept so a future not-yet-ratified rule can surface
  /// honestly, but nothing triggers it today.
  final bool pendingRatification;
}

// Small condition helpers (keep predicates one-liners + readable).

bool _present(num? v) => v != null;

/// RSSI grades to [grade] using the SAME ratified bands the live tool uses.
bool _rssiIs(AnalyzeInput i, QualityGrade grade) =>
    i.rssiDbm != null && WifiGrading.gradeRssi(i.rssiDbm) == grade;

/// SNR grades to [grade] using the SAME ratified bands.
bool _snrIs(AnalyzeInput i, QualityGrade grade) =>
    i.snrDb != null && WifiGrading.gradeSnr(i.snrDb) == grade;

// =============================================================================
// THE 35 RULES, ported from response-library-final.md, in its category order.
// =============================================================================

/// The full, ordered rule library. The engine sorts FIRED rules by severity
/// then by this declaration order, so the order here is the within-priority
/// tiebreak (verdict, then security, then worst measured-quality).
const List<AnalyzeRule> kAnalyzeRules = <AnalyzeRule>[
  // A. Verdict (the headline, always leads).
  AnalyzeRule(
    id: 'R-01',
    category: FindingCategory.verdict,
    severity: FindingSeverity.critical,
    condition: _isVerdictWifiLimiter,
    responseDraft:
        "Your Wi-Fi is the limit here, not your internet. Your internet plan "
        "can carry more than your Wi-Fi is currently passing through the air. "
        "The slowdown is the wireless hop between your device and your "
        "router/access point. Try this first: get closer to the router/access "
        "point, and clear out what sits between you and it, like walls and "
        "floors. Then run the check again. If it stays low even up close, the "
        "channel, the channel width, or the router/access point itself is "
        "worth a look.",
  ),
  AnalyzeRule(
    id: 'R-02',
    category: FindingCategory.verdict,
    severity: FindingSeverity.critical,
    condition: _isVerdictUpstream,
    responseDraft:
        "This one is your internet service, not your Wi-Fi. Your Wi-Fi has "
        "plenty of room to spare. The limit is past your router/access point, "
        "out on the internet side. Changing Wi-Fi settings will not move this "
        "number. What helps: a faster plan, or a call to your internet "
        "provider to find out why you are not getting what you pay for.",
  ),
  AnalyzeRule(
    id: 'R-03',
    category: FindingCategory.verdict,
    severity: FindingSeverity.critical,
    condition: _isVerdictBothContributing,
    responseDraft:
        "Both your Wi-Fi and your internet are holding you back, and they are "
        "close enough that neither one is clearly the culprit. The good news: "
        "fixing either one helps, and fixing both helps most. Start with the "
        "easy win. Usually that means getting closer to your router/access "
        "point first, then taking a second look at your internet plan.",
  ),
  AnalyzeRule(
    id: 'R-04',
    category: FindingCategory.verdict,
    severity: FindingSeverity.important,
    condition: _isVerdictBothHealthy,
    responseDraft:
        "Nothing to fix. Your Wi-Fi and your internet are both performing "
        "well, and they are working together the way they should. If something "
        "still feels slow, the cause is almost certainly a specific app or a "
        "website you are reaching, not your connection at home.",
  ),
  AnalyzeRule(
    id: 'R-05',
    category: FindingCategory.verdict,
    severity: FindingSeverity.important,
    condition: _isVerdictUnknown,
    responseDraft:
        "This is a partial read. One side could not be measured, so the check "
        "cannot yet tell you whether your Wi-Fi or your internet is the limit. "
        "Run it again while you are connected over Wi-Fi with the internet "
        "live. On iPhone, install the companion Shortcut first so the app can "
        "read your Wi-Fi details.",
  ),
  // Honest "you're online" verdict (Keith 2026-06-17). Fires when the speed
  // test stalled (throughput unmeasurable even after the retry) but the device
  // is clearly online: DNS resolved, a public IP was obtained, and cloud apps
  // were reachable. Leads with the reachable truth, NOT "make sure you're on
  // Wi-Fi". Conclusion-first, calm. On macOS this is the right read even though
  // the Wi-Fi Rx rate is never exposed (so the full Wi-Fi-vs-internet
  // comparison cannot compute): strong reachability evidence outranks the
  // missing throughput number.
  AnalyzeRule(
    id: 'R-06',
    category: FindingCategory.verdict,
    severity: FindingSeverity.important,
    condition: _isVerdictOnlineUnmeasured,
    responseDraft:
        "You are online. Your internet is reachable, but the speed test did "
        "not complete, so its speed could not be measured. Names are "
        "resolving, you have a public IP, and the test services answered, so "
        "the connection itself is up. Try the check again in a moment.",
  ),

  // B. Signal, RSSI (coverage / distance).
  AnalyzeRule(
    id: 'R-10',
    category: FindingCategory.signal,
    severity: FindingSeverity.important,
    condition: _rssiPoor,
    // HEDGE (Keith, 2026-07-12): the RSSI bands are a useful convention, not
    // physics — Keith has held great connections at -75 dBm. So this copy
    // reports a weak READING and points at coverage without promising a hard
    // verdict. The old wording ("right at the edge of coverage… no faster plan
    // will touch it") stated a threshold convention as certainty; softened.
    responseDraft:
        "Your signal is weak, which usually means you are near the edge of "
        "solid coverage. When the signal gets this faint, your device often "
        "slows itself down on purpose just to hold the connection together, "
        "and that can cap your speed and cause those annoying stalls. Keep in "
        "mind a signal reading is a guideline: some connections still run fine "
        "at this level, and others struggle a little above it. If speed or "
        "stalls are the problem here, coverage is the first place to look. Two "
        "things help, in order: move closer to your router/access point, or "
        "move the router/access point closer to the area where you need better "
        "coverage. If you still need range in a far corner, adding a second "
        "access point or a mesh node out there is the real fix. A weak signal "
        "is usually a coverage problem rather than a plan problem, so a faster "
        "internet plan generally will not change this reading.",
  ),
  AnalyzeRule(
    id: 'R-11',
    category: FindingCategory.signal,
    severity: FindingSeverity.context,
    condition: _rssiFair,
    responseDraft:
        "Your signal is fair. Usable, but not strong. Farther from the "
        "router/access point you may notice slower speeds or a little "
        "hesitation before things load. If performance matters where you are "
        "sitting, moving a bit closer to the router/access point will help.",
  ),
  AnalyzeRule(
    id: 'R-12',
    category: FindingCategory.signal,
    severity: FindingSeverity.context,
    contextOnly: true,
    condition: _rssiExcellent,
    responseDraft:
        "Your signal strength is excellent, so weak coverage is not your "
        "problem. The cause is somewhere else in this report, noted above.",
  ),

  // C. Noise / SNR (interference, quality of signal).
  AnalyzeRule(
    id: 'R-15',
    category: FindingCategory.noise,
    severity: FindingSeverity.important,
    condition: _snrPoor,
    responseDraft:
        "There is too much noise around you compared to your signal. Even when "
        "the signal itself looks fine, a noisy airspace drowns it out, and "
        "your connection drops to slow, error-prone speeds to cope. Usually "
        "the band is just crowded, and 2.4 GHz is the worst offender, or there "
        "is a noise source nearby. Connecting to a 5 GHz or 6 GHz network "
        "where your gear supports it, or simply moving away from whatever is "
        "making the racket, usually clears it up.",
  ),
  AnalyzeRule(
    id: 'R-16',
    category: FindingCategory.noise,
    severity: FindingSeverity.context,
    condition: _snrFair,
    responseDraft:
        "Your signal-to-noise ratio is fair. Some interference or background "
        "noise is nibbling at your connection quality. If you are on 2.4 GHz, "
        "connecting to 5 GHz or 6 GHz where your gear supports it is the most "
        "dependable fix.",
  ),
  AnalyzeRule(
    id: 'R-17',
    category: FindingCategory.noise,
    severity: FindingSeverity.important,
    condition: _snrWeakLowRate,
    responseDraft:
        "A weak signal is holding your Wi-Fi speed down. That low "
        "signal-to-noise reading is the reason your link is capped. A closer "
        "or cleaner signal should raise it.",
  ),
  AnalyzeRule(
    id: 'R-18',
    category: FindingCategory.noise,
    severity: FindingSeverity.context,
    condition: _snrStrongLowRate,
    responseDraft:
        "Strong signal, but a low link rate, so something else is getting in "
        "the way. Your signal is healthy, which means the slow speed points to "
        "interference, retries, or your router/access point holding you to an "
        "older, slower data rate. The router/access point's channel and "
        "configuration are the place to look.",
  ),

  // D. Band / PHY / width (capability).
  AnalyzeRule(
    id: 'R-20',
    category: FindingCategory.capability,
    severity: FindingSeverity.important,
    // DOCTRINE GUARDRAIL, ratified Keith 2026-06-16. Must NOT tell users to
    // blanket-switch bands; 2.4 GHz is the right choice for range/IoT. The copy
    // keeps the honest trade-off caveat. The condition fires on 2.4 GHz only
    // when the PHY suggests 5/6 GHz is plausible (Wi-Fi 5+), so an honestly
    // 2.4-only device is not scolded.
    condition: _band24WithModernPhy,
    responseDraft:
        "You are connected on the 2.4 GHz band, the slow and crowded one. "
        "2.4 GHz reaches a long way, which is exactly why it gets shared with "
        "microwaves, Bluetooth, your neighbors, and nearly everything else in "
        "the building, so it runs slower and noisier. If your device and your "
        "router/access point both support it, connecting to the 5 GHz or 6 GHz "
        "network usually gives you a real jump in speed. One honest caveat: "
        "2.4 GHz is sometimes the right choice on purpose, for long range or "
        "for older smart-home gadgets. If that is what you are doing, you are "
        "fine. This note is for the case where a faster band is sitting right "
        "there unused.",
  ),
  AnalyzeRule(
    id: 'R-21',
    category: FindingCategory.capability,
    severity: FindingSeverity.important,
    condition: _legacyPhy,
    responseDraft:
        "Your device is connected using an older Wi-Fi standard, 802.11n or "
        "earlier. Older standards top out at much lower speeds no matter how "
        "strong your signal is or how fast your plan is. This is almost always "
        "the age of the device or the router/access point. A newer "
        "router/access point, or connecting a newer device, lifts the ceiling. "
        "If the device itself is old, this may simply be as fast as it goes.",
  ),
  AnalyzeRule(
    id: 'R-22',
    category: FindingCategory.capability,
    severity: FindingSeverity.context,
    contextOnly: true,
    condition: _wifi5Phy,
    responseDraft:
        "You are on 802.11ac, often labeled Wi-Fi 5. Solid, just not the "
        "newest. For most homes this is perfectly fine. The newer standards "
        "add capacity in busy, crowded places more than they add raw speed for "
        "a single device.",
  ),
  AnalyzeRule(
    id: 'R-23',
    category: FindingCategory.capability,
    severity: FindingSeverity.context,
    // DOCTRINE GUARDRAIL, ratified Keith 2026-06-16. The "wider is better"
    // anti-pattern. Must NEVER tell users to force 160 MHz. Per
    // domain-proof-over-consensus, wider is not better; a narrow channel is
    // often the more reliable choice in a busy area. The copy keeps the honest
    // trade-off.
    condition: _narrowWidthFastBand,
    responseDraft:
        "You are on a narrow 20 MHz channel on a fast band. A wider channel "
        "can carry more, but wider is not automatically better. In a busy "
        "area, a narrow channel is often the more reliable choice, and forcing "
        "it wide just invites more interference. If you control the "
        "router/access point and your area is genuinely quiet, a wider channel "
        "may raise your speed. In a crowded area, leave it where it is.",
  ),
  AnalyzeRule(
    id: 'R-24',
    category: FindingCategory.capability,
    severity: FindingSeverity.context,
    condition: _band24OverlappingChannel,
    responseDraft:
        "Your 2.4 GHz channel is overlapping with the networks around you. On "
        "2.4 GHz, only channels 1, 6, and 11 stay out of each other's way. Any "
        "other channel is guaranteed to step on a neighbor and pick up "
        "interference. If you control the router/access point, set it to "
        "channel 1, 6, or 11.",
  ),

  // E. Internet path quality (latency / jitter / loss / responsiveness).
  AnalyzeRule(
    id: 'R-25',
    category: FindingCategory.internetQuality,
    severity: FindingSeverity.critical,
    condition: _lossPoor,
    responseDraft:
        "You are losing packets, and that is exactly why calls and games "
        "stutter. Loss this high breaks up anything live, even when the raw "
        "speed number looks healthy. Packet loss usually comes from one of two "
        "places: a weak Wi-Fi link, which you can see in your signal reading "
        "above, or a problem upstream at your provider. If your signal is "
        "strong, the trouble is almost certainly upstream, so your internet "
        "provider is the call to make.",
  ),
  AnalyzeRule(
    id: 'R-26',
    category: FindingCategory.internetQuality,
    severity: FindingSeverity.important,
    condition: _latencyPoor,
    responseDraft:
        "High latency. Your connection is slow to respond, not slow to "
        "download. Pages and files may still finish just fine, but anything "
        "interactive, like calls, video chat, and gaming, feels laggy and "
        "behind. When latency is high but speed is otherwise fine, the cause "
        "is usually upstream: your provider's routing, a faraway server, or a "
        "congested link, not your Wi-Fi at home.",
  ),
  AnalyzeRule(
    id: 'R-27',
    category: FindingCategory.internetQuality,
    severity: FindingSeverity.important,
    condition: _jitterPoor,
    responseDraft:
        "Your latency is jumpy, which we call high jitter. Even when the "
        "average looks okay, the constant variation breaks up live audio and "
        "video. Jitter usually traces back to a congested link or a shaky "
        "Wi-Fi connection. Check your signal first. If it is strong, the cause "
        "is most likely upstream at your provider.",
  ),
  AnalyzeRule(
    id: 'R-28',
    category: FindingCategory.internetQuality,
    severity: FindingSeverity.context,
    condition: _responsivenessPoor,
    responseDraft:
        "Your connection bogs down the moment something else starts using it. "
        "That is low responsiveness, and it is the classic sign of "
        "bufferbloat. The good news: this is usually fixable right on the "
        "router with a setting called Smart Queue Management, sometimes listed "
        "as SQM or fq_codel, if your router offers it.",
  ),
  AnalyzeRule(
    id: 'R-29',
    category: FindingCategory.internetQuality,
    severity: FindingSeverity.important,
    condition: _goodSpeedBadQuality,
    responseDraft:
        "Your speed is fine. The quality of your connection is not. Speed "
        "tests come back looking great, yet live apps still struggle, because "
        "the real trouble is latency, jitter, or loss, not raw bandwidth. "
        "Chasing a faster plan will not fix this. The fix is the quality issue "
        "called out above, whether that is your signal, congestion, or "
        "something upstream.",
  ),

  // F. DNS.
  AnalyzeRule(
    id: 'R-32',
    category: FindingCategory.dns,
    severity: FindingSeverity.context,
    condition: _dnsSlow,
    responseDraft:
        "Names are resolving slowly, so websites feel slow just to start "
        "loading. DNS is the quick lookup that happens before any page opens, "
        "and when that lookup drags, every new site you visit picks up a "
        "delay, even on a fast connection. An easy win: point your device or "
        "your router at a faster public DNS resolver. Good ones to try are "
        "1.1.1.1, 8.8.8.8, and 9.9.9.9.",
  ),

  // G. Security (safety note).
  AnalyzeRule(
    id: 'R-35',
    category: FindingCategory.security,
    severity: FindingSeverity.critical,
    condition: _securityOpen,
    responseDraft:
        "Your Wi-Fi is wide open, which means anyone nearby can see what you "
        "send. There is no encryption protecting your traffic at all. If this "
        "is your own network, turn on WPA3, or WPA2 if that is all your gear "
        "offers, and set a strong password. If this is a public hotspot, steer "
        "clear of anything sensitive, like banking, or use a VPN you trust.",
  ),
  AnalyzeRule(
    id: 'R-36',
    category: FindingCategory.security,
    severity: FindingSeverity.critical,
    condition: _securityWep,
    responseDraft:
        "Your network is using WEP, and WEP is broken. Treat it as no "
        "protection at all. It can be cracked in minutes and has been retired "
        "for years. If you control this network, switch it to WPA3 or WPA2 "
        "today. In practice, WEP usually means the equipment is very old and "
        "is overdue to be replaced.",
  ),
  AnalyzeRule(
    id: 'R-37',
    category: FindingCategory.security,
    severity: FindingSeverity.context,
    condition: _securityWpa2OrOlder,
    responseDraft:
        "You are on WPA2, or an older flavor of WPA. It is still widely used "
        "and okay for now, so this is a gentle nudge, not an alarm. WPA3 is "
        "meaningfully more secure, and if your router/access point and your "
        "devices support it, turning it on, or using WPA2/WPA3 transition "
        "mode, is worth doing when you get the chance.",
  ),
  AnalyzeRule(
    id: 'R-38',
    category: FindingCategory.security,
    severity: FindingSeverity.context,
    condition: _securityOwe,
    responseDraft:
        "You are on Enhanced Open, also called OWE. Your traffic is encrypted "
        "even though the network looks open, which is genuinely good. The one "
        "gap: there is no password proving the network is the real one. For "
        "everyday public Wi-Fi this is fine. For anything sensitive, prefer a "
        "network you control, or use a VPN.",
  ),

  // H. Cloud-app reachability.
  AnalyzeRule(
    id: 'R-40',
    category: FindingCategory.cloudReachability,
    severity: FindingSeverity.critical,
    condition: _cloudNoneReachable,
    responseDraft:
        "None of the test services answered. Your link may look up, but you "
        "cannot actually reach the internet right now. The usual suspects are "
        "a sign-in page you have not gotten past yet, a DNS hiccup, or an "
        "outage upstream. Open a web browser first, since that often triggers "
        "a hidden sign-in screen. If no sign-in page appears, restart your "
        "router/access point, and if that does not bring it back, call your "
        "internet provider.",
  ),
  AnalyzeRule(
    id: 'R-41',
    category: FindingCategory.cloudReachability,
    severity: FindingSeverity.important,
    condition: _cloudMixed,
    responseDraft:
        "Some services are reachable and some are not. A mixed result like "
        "this usually means one specific service is down, or something is "
        "blocking certain destinations, like a firewall, a DNS issue, or your "
        "provider, not a general outage. Your connection is working. The "
        "services listed as unreachable below are the ones to look into.",
  ),

  // I. Honesty / not-captured (mirrors the app's GL-005 discipline).
  AnalyzeRule(
    id: 'R-30',
    category: FindingCategory.honesty,
    severity: FindingSeverity.context,
    contextOnly: true,
    condition: _widthNotCaptured,
    responseDraft:
        "Channel width was not captured on this device. On iPhone, Apple does "
        "not hand channel width to apps, so this is not an error. It simply "
        "cannot be read here.",
  ),
  AnalyzeRule(
    id: 'R-31',
    category: FindingCategory.honesty,
    severity: FindingSeverity.context,
    condition: _wifiNotCaptured,
    responseDraft:
        "Your Wi-Fi signal details were not captured. The check ran without "
        "the live Wi-Fi read, so the signal, channel, and band findings are "
        "missing. In the app, tap \"Capture Wi-Fi details,\" which uses the "
        "companion Shortcut, then run it again and paste the new report.",
  ),
  // R-42 (cloud-latency context) and R-50 (parser guard) from the response
  // library: R-42 is included as a context-only note (held false until per-
  // service cloud latency is threaded through); R-50 is a PARSER guard for the
  // future web "paste a report" surface and has no analogue in this in-app
  // engine (the engine reads live in-memory objects, never pasted text), so it
  // is intentionally omitted here and noted in the engine doc.
  AnalyzeRule(
    id: 'R-42',
    category: FindingCategory.cloudReachability,
    severity: FindingSeverity.context,
    contextOnly: true,
    condition: _alwaysFalse,
    responseDraft:
        "Some services answer, just slowly. They are reachable, but the "
        "round-trip is high, which lines up with the latency finding above.",
  ),
];

// =============================================================================
// CONDITIONS, pure predicates. Each reads the imported ratified thresholds.
// Top-level functions (not closures) so they are const-assignable to the rules.
// =============================================================================

// A. Verdict.
bool _isVerdictWifiLimiter(AnalyzeInput i) =>
    i.verdict == WifiVsInternetVerdict.wifiLimiter;
bool _isVerdictUpstream(AnalyzeInput i) =>
    i.verdict == WifiVsInternetVerdict.upstream;
bool _isVerdictBothContributing(AnalyzeInput i) =>
    i.verdict == WifiVsInternetVerdict.bothContributing;
bool _isVerdictBothHealthy(AnalyzeInput i) =>
    i.verdict == WifiVsInternetVerdict.bothHealthy;
bool _isVerdictUnknown(AnalyzeInput i) =>
    i.verdict == WifiVsInternetVerdict.wifiUnknown;
bool _isVerdictOnlineUnmeasured(AnalyzeInput i) =>
    i.verdict == WifiVsInternetVerdict.onlineUnmeasured;

// B. RSSI, graded with WifiGradingBands (the ratified app bands).
bool _rssiPoor(AnalyzeInput i) => _rssiIs(i, QualityGrade.poor);
bool _rssiFair(AnalyzeInput i) => _rssiIs(i, QualityGrade.fair);
bool _rssiExcellent(AnalyzeInput i) => _rssiIs(i, QualityGrade.excellent);

// C. SNR, graded with WifiGradingBands; rate-context reuses the app's 200 Mbps.
bool _snrPoor(AnalyzeInput i) => _snrIs(i, QualityGrade.poor);
bool _snrFair(AnalyzeInput i) => _snrIs(i, QualityGrade.fair);
bool _snrWeakLowRate(AnalyzeInput i) =>
    i.snrDb != null &&
    i.snrDb! < WifiGradingBands.snrGoodDb &&
    _present(i.linkRateMbps) &&
    i.linkRateMbps! < kLowLinkRateMbps;
bool _snrStrongLowRate(AnalyzeInput i) =>
    i.snrDb != null &&
    i.snrDb! >= WifiGradingBands.snrGoodDb &&
    _present(i.linkRateMbps) &&
    i.linkRateMbps! < kLowLinkRateMbps;

// D. Band / PHY / width.
bool _band24WithModernPhy(AnalyzeInput i) =>
    i.isBand24 && (i.isWifi5Phy || _isWifi6Plus(i));
bool _legacyPhy(AnalyzeInput i) => i.isLegacyPhy;
bool _wifi5Phy(AnalyzeInput i) => i.isWifi5Phy && !i.isBand24;
bool _narrowWidthFastBand(AnalyzeInput i) =>
    i.channelWidthAvailable && i.channelWidthMhz == 20 && i.isFastBand;
bool _band24OverlappingChannel(AnalyzeInput i) =>
    i.isBand24 &&
    i.hasRealChannel &&
    !(i.channel == 1 || i.channel == 6 || i.channel == 11);

/// Whether the PHY names Wi-Fi 6/6E/7 (so 5/6 GHz is plausible, gates R-20).
bool _isWifi6Plus(AnalyzeInput i) {
  final String? s = i.standard?.toLowerCase();
  if (s == null) return false;
  return s.contains('wi-fi 6') ||
      s.contains('wi-fi 7') ||
      s.contains('802.11ax') ||
      s.contains('802.11be');
}

// E. Internet path quality, graded with QualityScoring (the ratified bands).
bool _lossPoor(AnalyzeInput i) =>
    i.lossPct != null &&
    QualityScoring.gradeLossPct(i.lossPct!) == QualityGrade.poor;
bool _latencyPoor(AnalyzeInput i) =>
    i.latencyMs != null &&
    QualityScoring.gradeLatencyMs(i.latencyMs!) == QualityGrade.poor;
bool _jitterPoor(AnalyzeInput i) =>
    i.jitterMs != null &&
    QualityScoring.gradeJitterMs(i.jitterMs!) == QualityGrade.poor;
bool _responsivenessPoor(AnalyzeInput i) =>
    i.responsivenessRpm != null &&
    QualityScoring.gradeResponsivenessRpm(i.responsivenessRpm!) ==
        QualityGrade.poor;

/// Download grades good/excellent BUT a quality dimension grades poor.
bool _goodSpeedBadQuality(AnalyzeInput i) {
  final double? d = i.downloadMbps;
  if (d == null) return false;
  final QualityGrade dg = QualityScoring.gradeDownloadMbps(d);
  final bool speedOk =
      dg == QualityGrade.good || dg == QualityGrade.excellent;
  return speedOk && (_lossPoor(i) || _latencyPoor(i) || _jitterPoor(i));
}

// F. DNS, ratified threshold [kDnsSlowMs].
bool _dnsSlow(AnalyzeInput i) =>
    i.dnsResolutionMs != null && i.dnsResolutionMs! >= kDnsSlowMs;

// G. Security, read off the WifiSecurity classification.
bool _securityOpen(AnalyzeInput i) => i.security == WifiSecurity.open;
bool _securityWep(AnalyzeInput i) => i.security == WifiSecurity.wep;
bool _securityWpa2OrOlder(AnalyzeInput i) =>
    i.security == WifiSecurity.wpaPersonal ||
    i.security == WifiSecurity.wpa2Personal;
bool _securityOwe(AnalyzeInput i) => i.security == WifiSecurity.owe;

// H. Cloud reachability.
bool _cloudNoneReachable(AnalyzeInput i) =>
    i.cloudTotalCount != null &&
    i.cloudTotalCount! > 0 &&
    i.cloudReachableCount == 0 &&
    i.internetMeasured;
bool _cloudMixed(AnalyzeInput i) =>
    i.cloudTotalCount != null &&
    i.cloudReachableCount != null &&
    i.cloudReachableCount! > 0 &&
    i.cloudReachableCount! < i.cloudTotalCount!;

// I. Honesty.
bool _widthNotCaptured(AnalyzeInput i) =>
    !i.channelWidthAvailable &&
    (i.band != null || i.standard != null);
bool _wifiNotCaptured(AnalyzeInput i) =>
    i.platformIsIos && !i.wifiSignalCaptured;

/// R-42 fires off per-service cloud latency, which the in-app engine does not
/// currently surface as a tally; held false until that datum is threaded
/// through (ratified threshold [kCloudSlowMs]). Never fires today.
bool _alwaysFalse(AnalyzeInput i) => false;
