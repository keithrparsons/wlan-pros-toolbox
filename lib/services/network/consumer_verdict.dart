// Consumer verdict translator — the plain-English "brain" of Test My Connection.
//
// A pure-Dart function with NO Flutter, NO platform channels, NO I/O. It takes
// the result the shared [WifiVsInternetEngine] already produced (the SAME engine
// the pro `wifi-vs-internet` tool drives, untouched) and re-skins its five
// engineer-facing verdict enums as the four consumer outcomes the
// `test_my_connection_screen` renders.
//
// REUSE, not reinvention: this layer adds ZERO measurement and ZERO new math. It
// maps verdicts to copy. Keeping it pure keeps the whole mapping exhaustively
// unit-testable with plain values and no real network/radio — one test per
// mapping row, including the D1/D2 split (see test/services/consumer_verdict_test.dart).
//
// All copy here is VERBATIM from the build spec
// (Deliverables/2026-06-01-consumer-wifi-internet-tool/SPEC-for-felix.md
//  §"Verdict translation"). The hedge stays in the verb ("Looks like" /
// "Likely cause"), never "your Wi-Fi is broken" — Keith's locked decision.
//
// HONESTY (GL-005): the D outcomes are the engine's honest "couldn't read the
// Wi-Fi link" path (wired, or iOS without the companion Shortcut). D1 keeps the
// real internet figure it DID measure; D2 admits neither side was read. Nothing
// is fabricated to paper over a platform limit.

import 'wifi_vs_internet.dart';

/// The four consumer outcomes the screen renders, collapsed from the engine's
/// five [WifiVsInternetVerdict] values. The D path splits into [couldntCheckWifi]
/// (D1 — internet measured) and [couldntComplete] (D2 — neither measured).
///
/// The screen maps each to a §8.13 status token AND renders the headline WORD,
/// so the verdict never relies on color alone (WCAG 2.2 SC 1.4.1). The
/// [selfHelpTopic] picks which vetted self-help list the screen shows.
enum ConsumerOutcome {
  /// A — the Wi-Fi link is the bottleneck (engine `wifiLimiter`). Also the
  /// LEADING half of [wifiLead], pointing at the easy, in-their-control fixes.
  wifi,

  /// A (lead) — both sides are a little slow (engine `bothContributing`), but
  /// the consumer is pointed at the Wi-Fi fixes first because they are the
  /// easiest and free. The body still names both honestly.
  wifiLead,

  /// B — the internet upstream is the slow part (engine `upstream`).
  internet,

  /// C — both sides are healthy (engine `bothHealthy`). The single most useful
  /// consumer message: it is probably the app or website, not your connection.
  bothFine,

  /// D1 — the Wi-Fi link could not be read but the internet WAS measured
  /// (engine `wifiUnknown` with an internet figure). Honest degraded read.
  couldntCheckWifi,

  /// D2 — neither side could be measured (engine `wifiUnknown`, no internet
  /// figure). "Make sure you're on Wi-Fi and try again."
  couldntComplete,

  /// E — the speed test stalled (throughput unmeasurable even after the retry)
  /// but the device is clearly online: DNS resolved, a public IP was obtained,
  /// and cloud apps were reachable (engine `onlineUnmeasured`). Leads with the
  /// reachable truth, not "make sure you're on Wi-Fi". (Keith 2026-06-17.)
  online,
}

/// The status of ONE axis — Wi-Fi or Internet — on the two-chip result header
/// (R1-A). Each axis gets its OWN explicit word so a non-technical person learns
/// that Wi-Fi and Internet are two separate things, and a missing read reads as
/// "Couldn't check" rather than a silent/ambiguous gap.
///
/// REVISION 2 (2026-06-07, Keith family-dinner feedback): a 3-TIER absolute
/// scale — Strong / Moderate / Weak — bucketed from the ABSOLUTE data rate in
/// Mbps, the SAME thresholds on both axes (see [AxisStatusThresholds]). This
/// replaces the prior 2-tier {fine, slow} verdict, which was COMPARATIVE
/// (derived from the engine's "which side is the limiter" verdict). The chips
/// now answer "how good is THIS side, on its own" — the comparative "is it your
/// Wi-Fi or your internet" answer still lives in the engine verdict / hero
/// sentence on the screen, so the two are complementary, not redundant.
///
/// The screen renders each as icon + WORD + a §8.13 color token: [strong] →
/// status-success (green), [moderate] → status-warning (amber), [weak] →
/// status-danger (red), [unknown] → a neutral/muted token. The WORD always
/// carries meaning so the chip never relies on color alone (WCAG 2.2 SC 1.4.1).
enum AxisStatus {
  /// "Strong" — this side measured a high data rate (> 250 Mbps).
  /// §8.13 `--app-status-success` (green).
  strong,

  /// "Moderate" — this side measured a mid data rate (100–250 Mbps inclusive).
  /// §8.13 `--app-status-warning` (amber).
  moderate,

  /// "Weak" — this side measured a low data rate (< 100 Mbps).
  /// §8.13 `--app-status-danger` (red).
  weak,

  /// "Couldn't check" — this side could not be measured/read on this device
  /// (neutral/muted token, NOT a fault color; GL-005 — never force a tier onto
  /// missing data).
  unknown,
}

/// The absolute data-rate thresholds (Mbps) that bucket a measured rate into an
/// [AxisStatus] tier. The SAME thresholds apply to both axes (Keith, 2026-06-07).
///
/// Boundaries (inclusive at the top of the Moderate band):
///   * rate > 250            → [AxisStatus.strong]
///   * 100 ≤ rate ≤ 250      → [AxisStatus.moderate]
///   * rate < 100            → [AxisStatus.weak]
///   * rate == null          → [AxisStatus.unknown] (unmeasured; GL-005)
///
/// Exposed as named constants so tests assert against the same numbers the
/// derivation uses, and so a future threshold change has one home.
class AxisStatusThresholds {
  const AxisStatusThresholds._();

  /// Above this rate (Mbps), exclusive, the axis is [AxisStatus.strong].
  static const double strongAboveMbps = 250;

  /// At/above this rate (Mbps), inclusive, the axis is at least
  /// [AxisStatus.moderate]; below it the axis is [AxisStatus.weak].
  static const double moderateAtOrAboveMbps = 100;

  /// Buckets an absolute data [rateMbps] into its tier. A null rate is an
  /// honest [AxisStatus.unknown] — no tier is forced onto missing data
  /// (GL-005). A non-positive rate (≤ 0) is also treated as unmeasured rather
  /// than as a real "Weak" reading, mirroring the engine's "treat ≤ 0 as
  /// absent" convention.
  static AxisStatus tierFor(double? rateMbps) {
    if (rateMbps == null || rateMbps <= 0) return AxisStatus.unknown;
    if (rateMbps > strongAboveMbps) return AxisStatus.strong;
    if (rateMbps >= moderateAtOrAboveMbps) return AxisStatus.moderate;
    return AxisStatus.weak;
  }
}

/// Which vetted self-help list the screen surfaces for an outcome. Drives the
/// "A few things to try" card — Wi-Fi fixes, internet fixes, the single
/// different-app line, or the reconnect-and-retry line. (FCC-sourced; the copy
/// itself lives in the screen, not here, so this stays a pure mapping.)
enum SelfHelpTopic {
  /// Move closer / restart router / pause competing traffic. Outcomes A and A(lead).
  wifi,

  /// Check for an outage / restart modem then router / contact provider. Outcome B.
  internet,

  /// The single "try a different app or website" line. Outcome C.
  differentApp,

  /// "Make sure you're on Wi-Fi and try again." Outcomes D1 and D2.
  reconnect,
}

/// The immutable plain-English translation of one engine verdict: the outcome
/// bucket, the consumer headline + body, and which self-help list to show. A
/// value object — no behavior beyond carrying the consumer answer.
class ConsumerVerdict {
  /// Creates a consumer verdict. All fields are set by [ConsumerVerdictMapper];
  /// the const constructor lets tests build expected values directly.
  const ConsumerVerdict({
    required this.outcome,
    required this.wifiStatus,
    required this.internetStatus,
    required this.headline,
    required this.body,
    required this.selfHelp,
  });

  /// The consumer outcome bucket. The screen maps it to a §8.13 status color.
  final ConsumerOutcome outcome;

  /// The Wi-Fi axis status for the top "Wi-Fi:" chip (R1-A). REVISION 2: an
  /// ABSOLUTE 3-tier read bucketed from the engine's usable Wi-Fi data rate
  /// ([WifiVsInternetResult.usableWifiMbps]) via [AxisStatusThresholds.tierFor]
  /// — > 250 Mbps → [AxisStatus.strong], 100–250 → [AxisStatus.moderate],
  /// < 100 → [AxisStatus.weak], unmeasured → [AxisStatus.unknown]. Independent
  /// of the comparative engine verdict; the chip reports how good the Wi-Fi side
  /// is on its own.
  final AxisStatus wifiStatus;

  /// The Internet axis status for the top "Internet:" chip (R1-A). REVISION 2:
  /// an ABSOLUTE 3-tier read bucketed from the engine's measured internet rate
  /// ([WifiVsInternetResult.internetAvgMbps]) via the SAME
  /// [AxisStatusThresholds.tierFor] thresholds as the Wi-Fi axis. Unmeasured
  /// internet → [AxisStatus.unknown] (GL-005 — no tier forced onto missing data).
  final AxisStatus internetStatus;

  /// The plain-English headline WORD/phrase (e.g. "Looks like your Wi-Fi").
  /// Always rendered alongside the status color — never color-only.
  final String headline;

  /// The one-line plain body explaining the headline in second person.
  /// For D1 the screen substitutes the measured-internet figures (see the
  /// [bodyForCouldntCheckWifi] builder); this carries the non-substituted form.
  final String body;

  /// Which vetted self-help list the screen surfaces for this outcome.
  final SelfHelpTopic selfHelp;
}

/// The pure consumer translator. Stateless: [map] is a total function of the
/// engine result, so every mapping row is unit-testable with plain values.
class ConsumerVerdictMapper {
  const ConsumerVerdictMapper._();

  /// Translates an engine [WifiVsInternetResult] into its [ConsumerVerdict].
  ///
  /// The D1/D2 split keys off whether the engine measured an internet figure:
  /// `wifiUnknown` with a non-null [WifiVsInternetResult.internetAvgMbps] is D1
  /// (we have a real internet result to report); without one it is D2.
  ///
  /// REVISION 2 (2026-06-07): the two axis chips are now ABSOLUTE 3-tier reads
  /// bucketed from the engine's rate figures via [AxisStatusThresholds.tierFor]
  /// — [WifiVsInternetResult.usableWifiMbps] drives [wifiStatus] and
  /// [WifiVsInternetResult.internetAvgMbps] drives [internetStatus], with the
  /// SAME > 250 / 100–250 / < 100 Mbps thresholds on both. The chips therefore
  /// depend ONLY on the measured rates, not on which `verdict` branch fires; the
  /// branch below still chooses the consumer OUTCOME (the comparative "is it your
  /// Wi-Fi or your internet" answer) and the copy, but no longer hard-codes the
  /// chip tiers.
  ///
  /// [internetHealthy] is the grade-gate result the screen already computes
  /// (`_internetHealth(...) == InternetHealth.good`). It is read ONLY on the D1
  /// path now, to word the "which looks [fine/slow]" body line — it no longer
  /// selects a chip tier (the chip comes from the absolute rate). Defaults to
  /// false so a caller that omits it never over-promises a healthy internet.
  static ConsumerVerdict map(
    WifiVsInternetResult engineResult, {
    bool internetHealthy = false,
  }) {
    // The two chips are absolute, rate-driven, and verdict-independent. Compute
    // both tiers once from the engine's measured rates; null rates (unmeasured
    // Wi-Fi link or unmeasured internet) honestly bucket to `unknown` (GL-005).
    final AxisStatus wifiTier =
        AxisStatusThresholds.tierFor(engineResult.usableWifiMbps);
    final AxisStatus internetTier =
        AxisStatusThresholds.tierFor(engineResult.internetAvgMbps);

    switch (engineResult.verdict) {
      // A — Wi-Fi link is the limiter.
      case WifiVsInternetVerdict.wifiLimiter:
        return ConsumerVerdict(
          outcome: ConsumerOutcome.wifi,
          wifiStatus: wifiTier,
          internetStatus: internetTier,
          headline: 'Looks like your Wi-Fi',
          body:
              'Your internet can go faster than your Wi-Fi is carrying right '
              'now. The slow part is between your device and the router.',
          selfHelp: SelfHelpTopic.wifi,
        );

      // A (lead) — both contributing; point at the easy Wi-Fi fixes first.
      case WifiVsInternetVerdict.bothContributing:
        return ConsumerVerdict(
          outcome: ConsumerOutcome.wifiLead,
          wifiStatus: wifiTier,
          internetStatus: internetTier,
          headline: 'Mostly your Wi-Fi',
          body:
              'Both your Wi-Fi and your internet are a little slow. Start with '
              "the Wi-Fi fixes below, they're the easiest.",
          selfHelp: SelfHelpTopic.wifi,
        );

      // B — the internet upstream is the slow part.
      case WifiVsInternetVerdict.upstream:
        return ConsumerVerdict(
          outcome: ConsumerOutcome.internet,
          wifiStatus: wifiTier,
          internetStatus: internetTier,
          headline: 'Looks like your Internet',
          body:
              'Your Wi-Fi has room to spare, but the internet coming into your '
              'home is the slow part.',
          selfHelp: SelfHelpTopic.internet,
        );

      // C — both healthy; it is probably the app or website.
      case WifiVsInternetVerdict.bothHealthy:
        return ConsumerVerdict(
          outcome: ConsumerOutcome.bothFine,
          wifiStatus: wifiTier,
          internetStatus: internetTier,
          headline: 'Both look fine',
          body:
              'Your Wi-Fi and internet are both working well. If something '
              "still feels slow, it's probably the website or app you're "
              'using, not your connection.',
          selfHelp: SelfHelpTopic.differentApp,
        );

      // D — the Wi-Fi link could not be read; split on whether internet ran.
      // The Wi-Fi chip is `unknown` here BY THE RATE (usableWifiMbps is null on
      // this path), so `wifiTier` already resolves to unknown — no override.
      case WifiVsInternetVerdict.wifiUnknown:
        final bool internetMeasured = engineResult.internetAvgMbps != null;
        if (internetMeasured) {
          // D1 — internet measured, Wi-Fi not. Wi-Fi chip is `unknown` (no
          // rate); the Internet chip is its absolute tier. The screen
          // substitutes the live [X]/[fine|slow] via [bodyForCouldntCheckWifi].
          return ConsumerVerdict(
            outcome: ConsumerOutcome.couldntCheckWifi,
            wifiStatus: wifiTier,
            internetStatus: internetTier,
            headline: 'Couldn’t check everything',
            body:
                'Your internet measured about [X] Mbps, which looks '
                '[fine/slow]. We couldn’t read your Wi-Fi details on this '
                'device.',
            selfHelp: SelfHelpTopic.reconnect,
          );
        }
        // D2 — neither side measured. Both chips `unknown` by the rates.
        return ConsumerVerdict(
          outcome: ConsumerOutcome.couldntComplete,
          wifiStatus: wifiTier,
          internetStatus: internetTier,
          headline: 'Couldn’t complete the check',
          body: "Make sure you're connected to Wi-Fi and try again.",
          selfHelp: SelfHelpTopic.reconnect,
        );

      // E — the speed test stalled but the device is clearly online. The
      // internet chip is `unknown` (no throughput rate), but the message leads
      // with the reachable truth instead of "make sure you're on Wi-Fi".
      case WifiVsInternetVerdict.onlineUnmeasured:
        return ConsumerVerdict(
          outcome: ConsumerOutcome.online,
          wifiStatus: wifiTier,
          internetStatus: internetTier,
          headline: 'You are online',
          body:
              'Your internet is reachable, but the speed test did not '
              'complete, so its speed could not be measured. Try again in a '
              'moment.',
          selfHelp: SelfHelpTopic.reconnect,
        );
    }
  }

  /// Builds the D1 body with the measured-internet figure substituted in, per
  /// the spec row: "Your internet measured about [X] Mbps, which looks
  /// [fine/slow]." [internetAvgMbps] is the engine's averaged figure; [healthy]
  /// is whether the internet graded good (→ "fine") or not (→ "slow"). Rounds
  /// the figure to a whole number — a consumer does not need decimals.
  ///
  /// Returns the non-substituted template when [internetAvgMbps] is null (a
  /// defensive guard: the D1 path only fires with a non-null figure).
  static String bodyForCouldntCheckWifi({
    required double? internetAvgMbps,
    required bool healthy,
  }) {
    if (internetAvgMbps == null) {
      return 'Your internet measured, but we couldn’t read your Wi-Fi '
          'details on this device.';
    }
    final int mbps = internetAvgMbps.round();
    final String quality = healthy ? 'fine' : 'slow';
    return 'Your internet measured about $mbps Mbps, which looks $quality. '
        'We couldn’t read your Wi-Fi details on this device.';
  }
}
