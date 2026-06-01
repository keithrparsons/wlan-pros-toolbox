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
    required this.headline,
    required this.body,
    required this.selfHelp,
  });

  /// The consumer outcome bucket. The screen maps it to a §8.13 status color.
  final ConsumerOutcome outcome;

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
  static ConsumerVerdict map(WifiVsInternetResult engineResult) {
    switch (engineResult.verdict) {
      // A — Wi-Fi link is the limiter.
      case WifiVsInternetVerdict.wifiLimiter:
        return const ConsumerVerdict(
          outcome: ConsumerOutcome.wifi,
          headline: 'Looks like your Wi-Fi',
          body:
              'Your internet can go faster than your Wi-Fi is carrying right '
              'now. The slow part is between your device and the router.',
          selfHelp: SelfHelpTopic.wifi,
        );

      // A (lead) — both contributing; point at the easy Wi-Fi fixes first.
      case WifiVsInternetVerdict.bothContributing:
        return const ConsumerVerdict(
          outcome: ConsumerOutcome.wifiLead,
          headline: 'Mostly your Wi-Fi',
          body:
              'Both your Wi-Fi and your internet are a little slow. Start with '
              "the Wi-Fi fixes below, they're the easiest.",
          selfHelp: SelfHelpTopic.wifi,
        );

      // B — the internet upstream is the slow part.
      case WifiVsInternetVerdict.upstream:
        return const ConsumerVerdict(
          outcome: ConsumerOutcome.internet,
          headline: 'Looks like your Internet',
          body:
              'Your Wi-Fi has room to spare, but the internet coming into your '
              'home is the slow part.',
          selfHelp: SelfHelpTopic.internet,
        );

      // C — both healthy; it is probably the app or website.
      case WifiVsInternetVerdict.bothHealthy:
        return const ConsumerVerdict(
          outcome: ConsumerOutcome.bothFine,
          headline: 'Both look fine',
          body:
              'Your Wi-Fi and internet are both working well. If something '
              "still feels slow, it's probably the website or app you're "
              'using, not your connection.',
          selfHelp: SelfHelpTopic.differentApp,
        );

      // D — the Wi-Fi link could not be read; split on whether internet ran.
      case WifiVsInternetVerdict.wifiUnknown:
        final bool internetMeasured = engineResult.internetAvgMbps != null;
        if (internetMeasured) {
          // D1 — internet measured, Wi-Fi not. The screen substitutes the live
          // [X]/[fine|slow] via [bodyForCouldntCheckWifi]; this is the template.
          return const ConsumerVerdict(
            outcome: ConsumerOutcome.couldntCheckWifi,
            headline: 'Couldn’t check everything',
            body:
                'Your internet measured about [X] Mbps, which looks '
                '[fine/slow]. We couldn’t read your Wi-Fi details on this '
                'device.',
            selfHelp: SelfHelpTopic.reconnect,
          );
        }
        // D2 — neither side measured.
        return const ConsumerVerdict(
          outcome: ConsumerOutcome.couldntComplete,
          headline: 'Couldn’t complete the check',
          body: "Make sure you're connected to Wi-Fi and try again.",
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
