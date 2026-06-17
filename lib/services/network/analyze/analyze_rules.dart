// =============================================================================
// Analyze Results — THE RULE LIBRARY (structured data, swappable).
// =============================================================================
//
// ▓▓▓ DRAFT RESPONSE COPY — PENDING KEITH RATIFICATION + PENN SOP-020 VOICE ▓▓▓
//
// Every `responseDraft` string below is Pax's v1 DRAFT, ported VERBATIM from:
//   Deliverables/2026-06-16-website-connection-analyzer-research/
//     response-library-v1.md  (35 rules, 9 categories)
//
// The copy is STRUCTURE + CORRECT PHYSICS ONLY — NOT finished Keith-voice copy.
// It is NOT ship-ready. Before this feature ships:
//   1. Keith ratifies the rules (especially the doctrine guardrails — see the
//      `pendingRatification: true` rules R-20 and R-23, plus the others Pax
//      flagged `[NEEDS KEITH]`: R-24, R-32, R-38, R-42).
//   2. Penn runs a formal SOP-020 voice pass (no "So," starters, no marketing
//      words, "Wi-Fi" / "802.1X" spelling, conclusion-first, NO em dashes —
//      the drafts below still carry some em dashes Penn will convert).
//
// WHY THIS IS A DATA FILE: the engine ([AnalyzeEngine]) NEVER hardcodes prose.
// It evaluates each rule's `condition` against an [AnalyzeInput] and renders the
// fired rules' `responseDraft` text. So updating the advice = editing THIS file
// ONLY (swap the string, swap the threshold the condition reads, add/remove a
// rule) — no engine change, no UI change. When Keith's ratified + Penn-voiced
// copy lands, it replaces these strings in place and the feature is ship-ready.
//
// THRESHOLDS ARE IMPORTED, NEVER DUPLICATED. Each condition reads the SAME
// ratified app constant the rest of the app uses (GL-005, domain-proof):
//   * RSSI / SNR bands → [WifiGradingBands]   (wifi_grading.dart)
//   * latency/jitter/loss/responsiveness/download bands → [QualityScoring]
//     (net_quality scoring.dart) — read via the same grade functions
//   * verdict thresholds → [WifiVsInternetVerdict] (wifi_vs_internet.dart)
//   * security labels → [WifiSecurity] (wifi_security.dart)
// Two thresholds Pax proposed have NO ratified app constant yet — the DNS
// resolution time (R-32, 200 ms) and the cloud-latency note (R-42, 250 ms).
// They live as the named [kDnsSlowMs] / [kCloudSlowMs] constants below, stamped
// PENDING so Keith ratifies or replaces them exactly like the others.
// =============================================================================

import 'package:net_quality/net_quality.dart' show QualityGrade, QualityScoring;

import '../wifi_grading.dart';
import '../wifi_security.dart';
import '../wifi_vs_internet.dart';
import 'analysis_finding.dart';
import 'analyze_input.dart';

/// DNS resolution time (ms) at/above which R-32 fires. **PENDING KEITH** — Pax-
/// proposed starting value; the app has NO ratified DNS band. Ratify or replace,
/// then stamp a reviewed-date like the wifi_grading.dart bands.
const int kDnsSlowMs = 200;

/// Cloud-app reachability round-trip (ms) at/above which R-42 fires. **PENDING
/// KEITH** — Pax-proposed; no app constant. Ratify or replace.
const int kCloudSlowMs = 250;

/// The link-rate (Mbps) below which a link is treated as "low" for the SNR
/// context rules R-17/R-18. Ported VERBATIM from the app's `_snrContext`
/// `lowRateMbps = 200` in wifi_vs_internet.dart — kept in sync as one number.
const double kLowLinkRateMbps = 200;

/// One rule in the library: its id, category, priority, the [condition] that
/// fires it, and the DRAFT response text. Editing this object = updating the
/// advice; the engine reads, it does not author.
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

  /// Stable id matching response-library-v1 (e.g. "R-01").
  final String id;

  /// The finding category this rule produces.
  final FindingCategory category;

  /// The priority/severity of the produced finding (P1/P2/P3 → critical/
  /// important/context).
  final FindingSeverity severity;

  /// Pure predicate over the input — true when the rule fires. Reads the
  /// imported thresholds; never duplicates a constant.
  final bool Function(AnalyzeInput input) condition;

  /// The DRAFT, conclusion-first response text (Pax v1). Swappable data.
  final String responseDraft;

  /// True for "no problem here" reassurance rules (R-12/R-22/R-30/R-42). The
  /// engine SUPPRESSES these unless at least one non-context finding also fired,
  /// so the report never narrates a non-issue (matches the app's `_snrContext`
  /// stay-quiet discipline; Pax open-question #4).
  final bool contextOnly;

  /// True when Pax flagged the rule `[NEEDS KEITH]` — copy/threshold not yet
  /// ratified. Surfaced honestly by the UI/findings.
  final bool pendingRatification;
}

// ── Small condition helpers (keep predicates one-liners + readable). ─────────

bool _present(num? v) => v != null;

/// RSSI grades to [grade] using the SAME ratified bands the live tool uses.
bool _rssiIs(AnalyzeInput i, QualityGrade grade) =>
    i.rssiDbm != null && WifiGrading.gradeRssi(i.rssiDbm) == grade;

/// SNR grades to [grade] using the SAME ratified bands.
bool _snrIs(AnalyzeInput i, QualityGrade grade) =>
    i.snrDb != null && WifiGrading.gradeSnr(i.snrDb) == grade;

// =============================================================================
// THE 35 RULES — ported from response-library-v1.md, in its category order.
// =============================================================================

/// The full, ordered rule library. The engine sorts FIRED rules by severity
/// then by this declaration order, so the order here is the within-priority
/// tiebreak (verdict → security → worst measured-quality, per Pax's proposal).
const List<AnalyzeRule> kAnalyzeRules = <AnalyzeRule>[
  // ── A. Verdict (the headline — always leads) ──────────────────────────────
  AnalyzeRule(
    id: 'R-01',
    category: FindingCategory.verdict,
    severity: FindingSeverity.critical,
    condition: _isVerdictWifiLimiter,
    responseDraft:
        "Your Wi-Fi link is the limit, not your internet. Your internet plan "
        "can carry more than your Wi-Fi connection is currently passing. The "
        "bottleneck is the air link between your device and the access point. "
        "Do: move closer to the AP, reduce what's between you and it (walls, "
        "floors), and re-test. If it stays low close-up, the channel, channel "
        "width, or the AP itself is worth a look.",
  ),
  AnalyzeRule(
    id: 'R-02',
    category: FindingCategory.verdict,
    severity: FindingSeverity.critical,
    condition: _isVerdictUpstream,
    responseDraft:
        "This is your internet service, not your Wi-Fi. Your Wi-Fi link has "
        "plenty of unused capacity; the limit is upstream of your access "
        "point: the ISP, the modem, or the path beyond it. Do: a faster plan, "
        "an ISP support call, or checking the modem/ONT will help. Changing "
        "Wi-Fi settings will not.",
  ),
  AnalyzeRule(
    id: 'R-03',
    category: FindingCategory.verdict,
    severity: FindingSeverity.critical,
    condition: _isVerdictBothContributing,
    responseDraft:
        "Both your Wi-Fi link and your internet are limiting you. They are in "
        "the same range, so neither is clearly the culprit. Do: improving "
        "either helps; improving both helps most. Start with whichever is "
        "easier — usually getting closer to the AP first, then revisiting the "
        "internet plan.",
  ),
  AnalyzeRule(
    id: 'R-04',
    category: FindingCategory.verdict,
    severity: FindingSeverity.important,
    condition: _isVerdictBothHealthy,
    responseDraft:
        "Nothing to fix — both your Wi-Fi and internet are performing well. "
        "You're using your connection the way it's meant to work. If something "
        "still feels slow, the issue is likely a specific app or a server "
        "you're reaching, not your local connection.",
  ),
  AnalyzeRule(
    id: 'R-05',
    category: FindingCategory.verdict,
    severity: FindingSeverity.important,
    condition: _isVerdictUnknown,
    responseDraft:
        "This is a partial read. One side couldn't be measured, so the report "
        "can't tell you whether your Wi-Fi or your internet is the limit. Do: "
        "re-run the check while connected over Wi-Fi on a live internet "
        "connection. On iPhone, install the companion Shortcut so the app can "
        "read your Wi-Fi link details.",
  ),

  // ── B. Signal — RSSI (coverage / distance) ────────────────────────────────
  AnalyzeRule(
    id: 'R-10',
    category: FindingCategory.signal,
    severity: FindingSeverity.important,
    condition: _rssiPoor,
    responseDraft:
        "Your signal is weak — you're at the edge of coverage. At this "
        "strength the connection drops its data rate to stay alive, which caps "
        "speed and causes stalls. Do: move closer to the access point, or add "
        "an AP/mesh node nearer to where you use Wi-Fi. A weak signal is a "
        "coverage problem, not a plan problem.",
  ),
  AnalyzeRule(
    id: 'R-11',
    category: FindingCategory.signal,
    severity: FindingSeverity.context,
    condition: _rssiFair,
    responseDraft:
        "Your signal is fair — usable, but not strong. You may notice slower "
        "speeds or hesitation farther from the AP. Do: if performance matters "
        "where you are, moving a bit closer to the AP will help.",
  ),
  AnalyzeRule(
    id: 'R-12',
    category: FindingCategory.signal,
    severity: FindingSeverity.context,
    contextOnly: true,
    condition: _rssiExcellent,
    responseDraft:
        "Your signal strength is excellent, so weak coverage is not your "
        "problem — the cause is elsewhere in this report.",
  ),

  // ── C. Noise / SNR (interference, quality of signal) ──────────────────────
  AnalyzeRule(
    id: 'R-15',
    category: FindingCategory.noise,
    severity: FindingSeverity.important,
    condition: _snrPoor,
    responseDraft:
        "Too much noise relative to your signal. Even if signal strength looks "
        "OK, a low signal-to-noise ratio means interference or background RF "
        "is drowning out your connection, forcing slow, error-prone data "
        "rates. Do: the band may be crowded (especially 2.4 GHz) or there's a "
        "noise source nearby. Moving to 5 GHz / 6 GHz, or away from the "
        "interference, usually helps.",
  ),
  AnalyzeRule(
    id: 'R-16',
    category: FindingCategory.noise,
    severity: FindingSeverity.context,
    condition: _snrFair,
    responseDraft:
        "Your signal-to-noise ratio is fair. There's some interference or "
        "noise eating into your connection quality. Do: if this is on 2.4 GHz, "
        "switching to 5 GHz or 6 GHz where supported is the most reliable fix.",
  ),
  AnalyzeRule(
    id: 'R-17',
    category: FindingCategory.noise,
    severity: FindingSeverity.important,
    condition: _snrWeakLowRate,
    responseDraft:
        "A weak signal is holding your link rate down. The low SNR is the "
        "reason your Wi-Fi speed is capped — a closer or cleaner signal should "
        "raise it.",
  ),
  AnalyzeRule(
    id: 'R-18',
    category: FindingCategory.noise,
    severity: FindingSeverity.context,
    condition: _snrStrongLowRate,
    responseDraft:
        "Strong signal, but a low link rate — something else is in the way. "
        "Your signal is healthy, so the low speed points to interference, "
        "retries, or the AP locking you to an older, slower data rate. Do: "
        "check the AP's channel and configuration.",
  ),

  // ── D. Band / PHY / width (capability) ────────────────────────────────────
  AnalyzeRule(
    id: 'R-20',
    category: FindingCategory.capability,
    severity: FindingSeverity.important,
    // ▓ DOCTRINE GUARDRAIL — PENDING KEITH. Must NOT tell users to blanket-
    //   switch bands; 2.4 GHz is the right choice for range/IoT. Wording carries
    //   the honest trade-off (Pax open-question #1 + #6). The condition fires on
    //   2.4 GHz only when the PHY suggests 5/6 GHz is plausible (Wi-Fi 5+), so an
    //   honestly-2.4-only device is not scolded.
    pendingRatification: true,
    condition: _band24WithModernPhy,
    responseDraft:
        "You're on the 2.4 GHz band — the slow, crowded one. 2.4 GHz reaches "
        "farther but is shared with microwaves, Bluetooth, neighbors, and "
        "almost everything else, so it's slower and noisier. Do: if your "
        "device and AP support it, connecting to the 5 GHz or 6 GHz network "
        "usually gives a big speed and reliability jump. (Trade-off: 2.4 GHz is "
        "the right choice when you need range or for IoT devices — this is not "
        "a blanket \"always switch\" recommendation.)",
  ),
  AnalyzeRule(
    id: 'R-21',
    category: FindingCategory.capability,
    severity: FindingSeverity.important,
    condition: _legacyPhy,
    responseDraft:
        "Your device is connected with an older Wi-Fi standard (Wi-Fi 4 or "
        "earlier). Older standards top out at much lower speeds regardless of "
        "signal or plan. Do: this is usually the device's or the AP's age. A "
        "newer AP, or connecting a newer device, lifts the ceiling. If the "
        "device is old, this may simply be its limit.",
  ),
  AnalyzeRule(
    id: 'R-22',
    category: FindingCategory.capability,
    severity: FindingSeverity.context,
    contextOnly: true,
    condition: _wifi5Phy,
    responseDraft:
        "You're on Wi-Fi 5 — solid, but not the newest. This is fine for most "
        "uses. Wi-Fi 6/6E/7 add capacity in busy environments, not raw "
        "single-device speed for most homes.",
  ),
  AnalyzeRule(
    id: 'R-23',
    category: FindingCategory.capability,
    severity: FindingSeverity.context,
    // ▓ DOCTRINE GUARDRAIL — PENDING KEITH. The "wider is better" anti-pattern.
    //   Must NEVER tell users to force 160 MHz. Per domain-proof-over-consensus,
    //   wider ≠ better; a narrow channel is often the more reliable choice in a
    //   busy area (Pax open-question #1).
    pendingRatification: true,
    condition: _narrowWidthFastBand,
    responseDraft:
        "You're on a narrow 20 MHz channel on a fast band. Wider channels can "
        "carry more, but wider is not automatically better — in a busy area a "
        "narrow channel is often the more reliable choice. Do: if you control "
        "the AP and the area is quiet, a wider channel may raise speed; in a "
        "crowded area, leave it. (We do not recommend forcing 160 MHz — wider "
        "is a trade-off, not an upgrade.)",
  ),
  AnalyzeRule(
    id: 'R-24',
    category: FindingCategory.capability,
    severity: FindingSeverity.context,
    pendingRatification: true,
    condition: _band24OverlappingChannel,
    responseDraft:
        "Your 2.4 GHz channel overlaps with neighbors. On 2.4 GHz only "
        "channels 1, 6, and 11 don't overlap; any other channel guarantees "
        "interference with adjacent networks. Do: if you control the AP, set "
        "it to 1, 6, or 11.",
  ),

  // ── E. Internet path quality (latency / jitter / loss / responsiveness) ───
  AnalyzeRule(
    id: 'R-25',
    category: FindingCategory.internetQuality,
    severity: FindingSeverity.critical,
    condition: _lossPoor,
    responseDraft:
        "You're losing packets — that's why calls and games stutter. Packet "
        "loss this high disrupts anything real-time even when raw speed looks "
        "fine. Do: loss usually comes from a weak Wi-Fi link (see your signal "
        "above) or an upstream/ISP problem. If your signal is strong, it's "
        "likely upstream — contact your ISP.",
  ),
  AnalyzeRule(
    id: 'R-26',
    category: FindingCategory.internetQuality,
    severity: FindingSeverity.important,
    condition: _latencyPoor,
    responseDraft:
        "High latency — your connection is responsive-slow, not "
        "throughput-slow. Pages and downloads may finish fine, but anything "
        "interactive (calls, gaming, video chat) feels laggy. Do: high latency "
        "with otherwise fine speed usually points upstream (ISP routing, a "
        "distant server, or a congested link), not your local Wi-Fi.",
  ),
  AnalyzeRule(
    id: 'R-27',
    category: FindingCategory.internetQuality,
    severity: FindingSeverity.important,
    condition: _jitterPoor,
    responseDraft:
        "Your latency is unstable (high jitter). Even if average latency is "
        "OK, the variation breaks up real-time audio and video. Do: jitter "
        "often comes from a congested link or a marginal Wi-Fi connection. "
        "Check your signal first; if it's strong, the cause is likely upstream.",
  ),
  AnalyzeRule(
    id: 'R-28',
    category: FindingCategory.internetQuality,
    severity: FindingSeverity.context,
    condition: _responsivenessPoor,
    responseDraft:
        "Your connection bogs down under load (low responsiveness). When "
        "something else is using the connection, everything else gets sluggish "
        "— a sign of bufferbloat. Do: this is usually fixable on the router "
        "with Smart Queue Management (SQM/fq_codel) if it's available.",
  ),
  AnalyzeRule(
    id: 'R-29',
    category: FindingCategory.internetQuality,
    severity: FindingSeverity.important,
    condition: _goodSpeedBadQuality,
    responseDraft:
        "Your speed is fine — but your connection's quality isn't. Speed tests "
        "look good, yet real-time apps still struggle, because the problem is "
        "latency/jitter/loss, not raw bandwidth. Do: chasing a faster plan "
        "won't fix this. Address the quality issue above (signal, congestion, "
        "or upstream).",
  ),

  // ── F. DNS ────────────────────────────────────────────────────────────────
  AnalyzeRule(
    id: 'R-32',
    category: FindingCategory.dns,
    severity: FindingSeverity.context,
    pendingRatification: true,
    condition: _dnsSlow,
    responseDraft:
        "Names resolve slowly — websites feel slow to start loading. DNS is "
        "the lookup that happens before a page loads; a slow lookup adds a "
        "delay to every new site even when the connection itself is fast. Do: "
        "try a faster public DNS resolver (e.g. 1.1.1.1 or 8.8.8.8) on your "
        "device or router.",
  ),

  // ── G. Security (safety note) ─────────────────────────────────────────────
  AnalyzeRule(
    id: 'R-35',
    category: FindingCategory.security,
    severity: FindingSeverity.critical,
    condition: _securityOpen,
    responseDraft:
        "Your Wi-Fi is open — anyone nearby can see your traffic. There's no "
        "encryption protecting what you send. Do: if it's your network, turn "
        "on WPA3 (or WPA2) with a strong password. If it's a public hotspot, "
        "avoid sensitive activity or use a trusted VPN.",
  ),
  AnalyzeRule(
    id: 'R-36',
    category: FindingCategory.security,
    severity: FindingSeverity.critical,
    condition: _securityWep,
    responseDraft:
        "WEP is broken security — treat it as no protection. WEP can be "
        "cracked in minutes; it's been deprecated for years. Do: if you "
        "control this network, switch to WPA3 or WPA2 immediately. WEP usually "
        "means very old equipment that should be replaced.",
  ),
  AnalyzeRule(
    id: 'R-37',
    category: FindingCategory.security,
    severity: FindingSeverity.context,
    condition: _securityWpa2OrOlder,
    responseDraft:
        "You're on WPA2 (or older WPA). It's still widely used and OK for now, "
        "but WPA3 is meaningfully more secure. Do: if your AP and devices "
        "support WPA3, enabling it (or WPA2/WPA3 transition mode) is worth "
        "doing.",
  ),
  AnalyzeRule(
    id: 'R-38',
    category: FindingCategory.security,
    severity: FindingSeverity.context,
    pendingRatification: true,
    condition: _securityOwe,
    responseDraft:
        "You're on Enhanced Open (OWE) — encrypted, but unauthenticated. Your "
        "traffic is encrypted even on an open-style network, which is good, "
        "but there's no password proving the network is legitimate. Do: fine "
        "for public Wi-Fi; for sensitive work, prefer a network you control or "
        "a VPN.",
  ),

  // ── H. Cloud-app reachability ─────────────────────────────────────────────
  AnalyzeRule(
    id: 'R-40',
    category: FindingCategory.cloudReachability,
    severity: FindingSeverity.critical,
    condition: _cloudNoneReachable,
    responseDraft:
        "None of the test cloud services responded. Your link may be up but "
        "you can't actually reach the internet — a captive portal you haven't "
        "signed into, a DNS failure, or an upstream outage. Do: open a browser "
        "to trigger any sign-in page; if there isn't one, restart the "
        "modem/router or contact your ISP.",
  ),
  AnalyzeRule(
    id: 'R-41',
    category: FindingCategory.cloudReachability,
    severity: FindingSeverity.important,
    condition: _cloudMixed,
    responseDraft:
        "Some cloud services are reachable, some aren't. A partial result "
        "usually means a specific service is down, or something (a firewall, "
        "DNS, or your provider) is blocking certain destinations — not a "
        "general connection failure. Do: the unreachable services listed below "
        "are the ones to investigate; the connection itself is working.",
  ),

  // ── I. Honesty / not-captured (mirrors the app's GL-005 discipline) ───────
  AnalyzeRule(
    id: 'R-30',
    category: FindingCategory.honesty,
    severity: FindingSeverity.context,
    contextOnly: true,
    condition: _widthNotCaptured,
    responseDraft:
        "Channel width wasn't captured on this device. On iPhone, Apple "
        "doesn't expose channel width to apps, so this isn't an error — it just "
        "can't be read here.",
  ),
  AnalyzeRule(
    id: 'R-31',
    category: FindingCategory.honesty,
    severity: FindingSeverity.context,
    condition: _wifiNotCaptured,
    responseDraft:
        "Your Wi-Fi signal details weren't captured. The report ran without "
        "the live Wi-Fi read, so signal, channel, and band findings are "
        "missing. Do: in the app, tap \"Capture Wi-Fi details\" (installs/uses "
        "the companion Shortcut), then re-run and re-paste.",
  ),
  // R-42 (cloud-latency context) and R-50 (parser guard) from Pax's library:
  // R-42 is included as a context-only note; R-50 is a PARSER guard for the
  // future web "paste a report" surface and has no analogue in this in-app
  // engine (the engine reads live in-memory objects, never pasted text), so it
  // is intentionally omitted here and noted in the engine doc.
  AnalyzeRule(
    id: 'R-42',
    category: FindingCategory.cloudReachability,
    severity: FindingSeverity.context,
    contextOnly: true,
    pendingRatification: true,
    condition: _alwaysFalse,
    responseDraft:
        "Some services respond, but slowly. The named services are reachable "
        "but the round-trip is high, which lines up with the latency finding "
        "above.",
  ),
];

// =============================================================================
// CONDITIONS — pure predicates. Each reads the imported ratified thresholds.
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

// B. RSSI — graded with WifiGradingBands (the ratified app bands).
bool _rssiPoor(AnalyzeInput i) => _rssiIs(i, QualityGrade.poor);
bool _rssiFair(AnalyzeInput i) => _rssiIs(i, QualityGrade.fair);
bool _rssiExcellent(AnalyzeInput i) => _rssiIs(i, QualityGrade.excellent);

// C. SNR — graded with WifiGradingBands; rate-context reuses the app's 200 Mbps.
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

/// Whether the PHY names Wi-Fi 6/6E/7 (so 5/6 GHz is plausible — gates R-20).
bool _isWifi6Plus(AnalyzeInput i) {
  final String? s = i.standard?.toLowerCase();
  if (s == null) return false;
  return s.contains('wi-fi 6') ||
      s.contains('wi-fi 7') ||
      s.contains('802.11ax') ||
      s.contains('802.11be');
}

// E. Internet path quality — graded with QualityScoring (the ratified bands).
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

// F. DNS — PENDING-KEITH threshold.
bool _dnsSlow(AnalyzeInput i) =>
    i.dnsResolutionMs != null && i.dnsResolutionMs! >= kDnsSlowMs;

// G. Security — read off the WifiSecurity classification.
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
/// through (Pax PENDING threshold [kCloudSlowMs]). Never fires today.
bool _alwaysFalse(AnalyzeInput i) => false;
