// Wi-Fi vs Internet - the pure verdict engine.
//
// Answers one field question for a Wi-Fi engineer: "Is the problem my Wi-Fi
// LINK, or the internet UPSTREAM of it?" - and backs the answer with the actual
// numbers (Keith's "verdict + the numbers" style).
//
// CORE PRINCIPLE (Keith): the negotiated data RATE is the truth; RSSI/SNR are
// supporting context. The Tx/Rx rate is what the client can actually carry and
// it is in Mbps, directly comparable to internet throughput. RSSI/SNR only
// explain WHY the rate is what it is; they never override the rate for the
// headline verdict.
//
// PURE DART by design: no Flutter imports, no platform channels, no I/O. The
// caller (wifi_vs_internet_screen) supplies the already-measured inputs - a
// ConnectedAp's rates/SNR/RSSI plus the net_quality download/upload + dimension
// grades - and this engine turns them into a verdict. That keeps the whole
// matrix exhaustively unit-testable with plain values and no real network /
// radio. See SPEC: Deliverables/2026-06-01-wifi-vs-internet-spec/spec.md.
//
// THE METRIC (all disclosed in the screen footnote, verbatim from the spec):
//   1. Wi-Fi link rate = avg(Tx, Rx). Single-rate fallback when only one is
//      reported (macOS public CoreWLAN exposes Tx but not Rx) - [rateBasis]
//      records which path was taken.
//   2. Usable Wi-Fi capacity = 0.55 × link rate (real throughput runs ~50-60%
//      of the PHY rate).
//   3. Internet speed = the DOWNLOAD throughput (what a consumer means by
//      "internet speed"). Upload alone is NOT treated as internet speed.
//   4. Headroom ratio = internet download / usableWiFiCapacity.
//
// VERDICT LOGIC (grade gate first, then the ratio):
//   * Grade gate - if the internet is GOOD (throughput + latency + loss all
//     grade good/excellent) → bothHealthy, regardless of ratio. A fast link +
//     fast internet is never mislabeled a fault.
//   * Otherwise the ratio diagnoses the ceiling:
//       ratio ≥ 0.70 → wifiLimiter      (the air link is the bottleneck)
//       ratio < 0.40 → upstream         (unused link headroom; ISP/upstream)
//       0.40-0.70    → bothContributing
//   * Unknown Wi-Fi rate (wired, or iOS without the companion Shortcut) →
//     wifiUnknown: an internet-only read with an explicit caveat.

import 'dart:math' as math;

/// Real-world Wi-Fi throughput as a fraction of the negotiated PHY rate
/// (the spec's flat 0.55 - ~50-60% in practice). Exposed so a test reads the
/// same constant the engine uses rather than hard-coding 0.55 in two places.
const double kUsableWifiFactor = 0.55;

/// Headroom-ratio threshold at/above which the Wi-Fi LINK is the limiter.
const double kWifiLimiterRatio = 0.70;

/// Headroom-ratio threshold below which the bottleneck is UPSTREAM.
const double kUpstreamRatio = 0.40;

/// The five mutually-exclusive verdicts. The screen maps each to a §8.13 status
/// token AND renders the verdict WORD (never color-only - WCAG 2.2 SC 1.4.1).
enum WifiVsInternetVerdict {
  /// Internet is marginal/poor and within 70% of usable Wi-Fi capacity - the
  /// air link is the ceiling. "It's your Wi-Fi."
  wifiLimiter,

  /// Internet is marginal/poor and the link has unused headroom (ratio < 0.40),
  /// so the bottleneck is upstream. "It's upstream, not your Wi-Fi."
  upstream,

  /// Internet is marginal/poor and the ratio sits in the 0.40-0.70 middle -
  /// both the link and the upstream path are contributing.
  bothContributing,

  /// The internet graded good/excellent on throughput, latency, and loss - a
  /// healthy connection, no fault to localize. "Both healthy." (Grade gate.)
  bothHealthy,

  /// The Wi-Fi link rate could not be measured (wired, or iOS without the
  /// companion Shortcut) - an internet-only read with an explicit caveat.
  wifiUnknown,

  /// Internet throughput could not be measured (the speed test stalled even
  /// after the retry), BUT independent evidence says the device is online: DNS
  /// resolved, a public IP was obtained, AND cloud-app reachability succeeded.
  /// The honest read is "you are online, the speed just could not be measured",
  /// NOT "could not read your Wi-Fi or your internet". See [OnlineEvidence].
  onlineUnmeasured,
}

/// Independent evidence that the device is genuinely on the internet, used to
/// distinguish a transient speed-test stall from a real "you are offline" read.
///
/// These three signals are gathered by the screen OUTSIDE the throughput
/// measurement (the DNS probe, the public-IP lookup, and the cloud-app
/// reachability panel), so they stay valid even when the speed test itself
/// stalls. When all three are present the engine produces
/// [WifiVsInternetVerdict.onlineUnmeasured] in place of the bleak "could not
/// read" verdict, in Keith's calm, conclusion-first voice. A pure value object.
class OnlineEvidence {
  /// Creates an evidence snapshot.
  const OnlineEvidence({
    this.dnsResolved = false,
    this.publicIpObtained = false,
    this.cloudReachable = false,
  });

  /// True when a DNS lookup resolved a host this run.
  final bool dnsResolved;

  /// True when the public-IP / ISP lookup returned an address.
  final bool publicIpObtained;

  /// True when at least one cloud-app reachability probe succeeded.
  final bool cloudReachable;

  /// All three signals present: the device is clearly online, so a missing
  /// throughput number is a stalled speed test, not an offline link.
  bool get isOnline => dnsResolved && publicIpObtained && cloudReachable;
}

/// Which negotiated rates fed the link-rate figure. Drives the honest "averaged
/// both / Tx only / Rx only" caption and the macOS Tx-only path.
enum WifiRateBasis {
  /// Both Tx and Rx were reported - link rate is their average.
  averaged,

  /// Only Tx was reported (the macOS public-CoreWLAN case) - link rate is Tx.
  txOnly,

  /// Only Rx was reported - link rate is Rx.
  rxOnly,

  /// Neither rate was reported - link rate is unknown (drives [wifiUnknown]).
  none,
}

/// The qualitative state of the internet path, derived from the net_quality
/// dimension grades. Kept as a tiny enum (rather than importing the package's
/// `QualityGrade`) so this engine stays pure Dart and Flutter-free: the screen
/// translates the three relevant grades into these flags at the boundary.
enum InternetHealth {
  /// Throughput + latency + loss all graded good/excellent - the grade gate
  /// fires and the verdict is [WifiVsInternetVerdict.bothHealthy].
  good,

  /// At least one of those three dimensions graded fair/poor (or could not be
  /// graded) - the ratio is allowed to diagnose where the ceiling is.
  marginal,
}

/// The immutable result of one Wi-Fi-vs-Internet evaluation: the verdict, the
/// display strings, and every derived number so the screen renders them without
/// recomputing. A value object - no behavior beyond carrying the answer.
class WifiVsInternetResult {
  /// Creates a result. All fields are set by [WifiVsInternetEngine.evaluate];
  /// the const constructor exists so tests can build expected values directly.
  const WifiVsInternetResult({
    required this.verdict,
    required this.headline,
    required this.explanation,
    required this.snrContext,
    required this.rateBasis,
    required this.usableWifiMbps,
    required this.internetMbps,
    required this.linkRateMbps,
    required this.ratio,
  });

  /// The localized verdict enum. The screen maps it to a §8.13 status color.
  final WifiVsInternetVerdict verdict;

  /// The short verdict WORD/phrase shown in the verdict card (e.g. "It's your
  /// Wi-Fi."). Always rendered alongside the status color - never color-only.
  final String headline;

  /// One-line plain explanation of WHY this verdict, in engineer-plain English.
  final String explanation;

  /// The supporting RSSI/SNR context line. Empty string when there is no
  /// signal context to add (no rate, or no SNR reading). Never the headline.
  final String snrContext;

  /// Which rates fed [linkRateMbps] - drives the honest "Tx only" caption.
  final WifiRateBasis rateBasis;

  /// Usable Wi-Fi capacity = 0.55 × link rate, Mbps. Null when the rate is
  /// unknown ([rateBasis] == none / [verdict] == wifiUnknown).
  final double? usableWifiMbps;

  /// The consumer-facing internet speed = the DOWNLOAD throughput, Mbps (what a
  /// user means by "internet speed"). Null when download was not measured —
  /// upload alone is deliberately NOT treated as internet speed (Keith 2026-07).
  final double? internetMbps;

  /// The negotiated link rate that fed the capacity figure, Mbps. Null when
  /// unknown. Exposed so the screen can show the basis without re-averaging.
  final double? linkRateMbps;

  /// Headroom ratio = internet download / usableWifi. Null when either input is
  /// unknown (so no ratio-based verdict was possible).
  final double? ratio;
}

/// The pure verdict engine. Stateless: [evaluate] is a total function of its
/// inputs, so the full matrix is unit-testable with plain numbers.
class WifiVsInternetEngine {
  const WifiVsInternetEngine._();

  /// Evaluates the verdict from the measured inputs.
  ///
  /// Wi-Fi link (any may be null - each platform exposes a different subset):
  ///   * [txRateMbps] / [rxRateMbps] - negotiated rates, Mbps.
  ///   * [rxRateAvailable] - whether THIS platform can ever expose Rx (macOS
  ///     public CoreWLAN cannot). Carried through for the caller; the rate math
  ///     keys off whether [rxRateMbps] is non-null, not this flag.
  ///   * [snrDb] / [rssiDbm] - supporting signal context only.
  ///
  /// Internet (from net_quality, translated at the boundary):
  ///   * [internetDownMbps] / [internetUpMbps] - measured throughput, Mbps.
  ///   * [internetHealth] - the grade-gate input: [InternetHealth.good] when
  ///     throughput + latency + loss all grade good/excellent.
  static WifiVsInternetResult evaluate({
    double? txRateMbps,
    double? rxRateMbps,
    bool rxRateAvailable = false,
    int? snrDb,
    int? rssiDbm,
    double? internetDownMbps,
    double? internetUpMbps,
    required InternetHealth internetHealth,
    OnlineEvidence onlineEvidence = const OnlineEvidence(),
  }) {
    // --- Link rate: avg(Tx, Rx) with single-rate fallback. ---
    final bool hasTx = txRateMbps != null && txRateMbps > 0;
    final bool hasRx = rxRateMbps != null && rxRateMbps > 0;

    final WifiRateBasis basis;
    final double? linkRate;
    if (hasTx && hasRx) {
      basis = WifiRateBasis.averaged;
      linkRate = (txRateMbps + rxRateMbps) / 2;
    } else if (hasTx) {
      basis = WifiRateBasis.txOnly;
      linkRate = txRateMbps;
    } else if (hasRx) {
      basis = WifiRateBasis.rxOnly;
      linkRate = rxRateMbps;
    } else {
      basis = WifiRateBasis.none;
      linkRate = null;
    }

    final double? usableWifi = linkRate == null
        ? null
        : kUsableWifiFactor * linkRate;

    // --- Consumer internet speed: DOWNLOAD only (what a user means by
    //     "internet speed"); upload alone is NOT internet speed. A null download
    //     falls through to the online-evidence / unmeasured paths below. ---
    final double? internet = _downloadInternet(internetDownMbps);

    // --- Headroom ratio (only when both sides are known and capacity > 0). ---
    final double? ratio =
        (usableWifi != null && usableWifi > 0 && internet != null)
        ? internet / usableWifi
        : null;

    // The signal context line is the same regardless of verdict; compute once.
    final String snrContext = _snrContext(
      linkRate: linkRate,
      snrDb: snrDb,
      basis: basis,
    );

    // --- Honest "you're online" path: throughput is unmeasurable (the speed
    //     test stalled even after the retry) but the device is clearly online
    //     (DNS resolved + public IP obtained + cloud reachability succeeded).
    //     Lead with the reachable truth instead of the bleak "could not read"
    //     verdict. This covers BOTH the no-rate case (wired) and the macOS
    //     Tx-only case (Rx never exposed, so the ratio can't fully compute) -
    //     in either case, strong reachability evidence outranks the missing
    //     throughput number (Keith 2026-06-17). ---
    if (internet == null && onlineEvidence.isOnline) {
      return WifiVsInternetResult(
        verdict: WifiVsInternetVerdict.onlineUnmeasured,
        headline: 'You are online',
        explanation:
            'Your internet is reachable, but the speed test did not complete, '
            'so its speed could not be measured. Try again in a moment.',
        snrContext: basis == WifiRateBasis.none ? '' : snrContext,
        rateBasis: basis,
        usableWifiMbps: usableWifi,
        internetMbps: null,
        linkRateMbps: linkRate,
        ratio: null,
      );
    }

    // --- Unknown-rate path: internet-only read with a caveat. ---
    if (basis == WifiRateBasis.none) {
      return WifiVsInternetResult(
        verdict: WifiVsInternetVerdict.wifiUnknown,
        headline: 'Wi-Fi link not measured',
        explanation: internet == null
            ? 'The Wi-Fi link rate could not be read, so the verdict cannot '
                  'localize the bottleneck. Connect over Wi-Fi (on iOS, install '
                  'the companion Shortcut) for the full read.'
            : 'The Wi-Fi link rate could not be read, so this is an '
                  'internet-only result. Measured internet throughput is '
                  '${_mbps(internet)}. Connect over Wi-Fi (on iOS, install '
                  'the companion Shortcut) to compare it against the link.',
        snrContext: '',
        rateBasis: basis,
        usableWifiMbps: null,
        internetMbps: internet,
        linkRateMbps: null,
        ratio: null,
      );
    }

    // --- Grade gate: good internet → both healthy, regardless of ratio. ---
    if (internetHealth == InternetHealth.good) {
      final bool highRatio = ratio != null && ratio >= kWifiLimiterRatio;
      final String explanation = highRatio
          ? 'Internet and Wi-Fi are both performing well. You are using most '
                'of your Wi-Fi link capacity, which is expected with fast '
                'internet, not a fault.'
          : 'Internet and Wi-Fi are both performing well, with link capacity '
                'to spare. No bottleneck to chase here.';
      return WifiVsInternetResult(
        verdict: WifiVsInternetVerdict.bothHealthy,
        headline: 'Both healthy',
        explanation: explanation,
        snrContext: snrContext,
        rateBasis: basis,
        usableWifiMbps: usableWifi,
        internetMbps: internet,
        linkRateMbps: linkRate,
        ratio: ratio,
      );
    }

    // --- Marginal/poor internet: the ratio diagnoses the ceiling. ---
    // If we could not form a ratio (no internet figure), fall back to the
    // unknown-internet caveat rather than guessing a side.
    if (ratio == null) {
      return WifiVsInternetResult(
        verdict: WifiVsInternetVerdict.wifiUnknown,
        headline: 'Internet not measured',
        explanation:
            'The internet throughput could not be measured, so the verdict '
            'cannot compare it against the Wi-Fi link. Re-run the check on a '
            'live connection.',
        snrContext: snrContext,
        rateBasis: basis,
        usableWifiMbps: usableWifi,
        internetMbps: null,
        linkRateMbps: linkRate,
        ratio: null,
      );
    }

    // Round the ratio for the band decision so float noise at an exact cut
    // point (e.g. 0.55 * 200 = 110.000…1, making 44/that = 0.3999…96) does not
    // flip the verdict. The true [ratio] is still reported on the result.
    final double bandRatio = (ratio * 1e6).roundToDouble() / 1e6;

    if (bandRatio >= kWifiLimiterRatio) {
      return WifiVsInternetResult(
        verdict: WifiVsInternetVerdict.wifiLimiter,
        headline: "It's your Wi-Fi",
        explanation:
            'The internet path can carry more than your Wi-Fi link is passing '
            '(${_mbps(internet)} internet vs ${_mbps(usableWifi)} usable '
            'Wi-Fi). The air link is the limiter: get closer to the AP, or '
            'check the channel, width, and AP, then re-test.',
        snrContext: snrContext,
        rateBasis: basis,
        usableWifiMbps: usableWifi,
        internetMbps: internet,
        linkRateMbps: linkRate,
        ratio: ratio,
      );
    }

    if (bandRatio < kUpstreamRatio) {
      return WifiVsInternetResult(
        verdict: WifiVsInternetVerdict.upstream,
        headline: "It's upstream, not your Wi-Fi",
        explanation:
            'Your Wi-Fi link has unused headroom (${_mbps(usableWifi)} usable '
            'vs ${_mbps(internet)} internet). The bottleneck is upstream: '
            'the ISP, modem, or the path beyond your access point.',
        snrContext: snrContext,
        rateBasis: basis,
        usableWifiMbps: usableWifi,
        internetMbps: internet,
        linkRateMbps: linkRate,
        ratio: ratio,
      );
    }

    // 0.40 ≤ ratio < 0.70 → both contributing.
    return WifiVsInternetResult(
      verdict: WifiVsInternetVerdict.bothContributing,
      headline: 'Both contributing',
      explanation:
          'The internet and the Wi-Fi link are in the same range '
          '(${_mbps(internet)} internet vs ${_mbps(usableWifi)} usable '
          'Wi-Fi), so both are limiting throughput. Improving either one will '
          'help; improving both will help most.',
      snrContext: snrContext,
      rateBasis: basis,
      usableWifiMbps: usableWifi,
      internetMbps: internet,
      linkRateMbps: linkRate,
      ratio: ratio,
    );
  }

  /// The consumer-facing internet speed: the DOWNLOAD throughput, or null when
  /// download was not measured. Upload alone is deliberately NOT treated as
  /// "internet speed" (Keith 2026-07) — a consumer's "internet speed" is the
  /// download number. Treats a non-positive figure as absent.
  static double? _downloadInternet(double? down) {
    if (down != null && down > 0) return down;
    return null;
  }

  /// The supporting RSSI/SNR context line (spec): explains the link RATE, never
  /// the headline. Returns '' when there is no rate or no SNR to reason about.
  ///
  /// A "low" link rate is judged relative to a modern expectation: rates under
  /// ~200 Mbps on a single link suggest a problem worth a context note. SNR
  /// under ~25 dB is "weak signal"; at/above that the signal is healthy, so a
  /// low rate with good SNR is the genuinely useful engineer flag (interference,
  /// retries, or a legacy-rate lock).
  static String _snrContext({
    required double? linkRate,
    required int? snrDb,
    required WifiRateBasis basis,
  }) {
    if (linkRate == null || snrDb == null) return '';

    const double lowRateMbps = 200;
    const int weakSnrDb = 25;

    final bool lowRate = linkRate < lowRateMbps;
    if (!lowRate) {
      // Healthy rate - no problem flag to raise; stay quiet rather than
      // narrate a non-issue.
      return '';
    }

    if (snrDb < weakSnrDb) {
      return 'Weak signal (SNR ${snrDb}dB) is holding the link rate down. '
          'A closer or stronger signal should raise it.';
    }
    return 'Strong signal (SNR ${snrDb}dB) but a low link rate. Check for '
        'interference, retries, or a legacy-rate lock.';
  }

  /// Formats a Mbps figure for the explanation strings: integers drop the
  /// decimal, otherwise one decimal place. Rounds half-up via [num.round].
  static String _mbps(double? v) {
    if (v == null) return 'n/a';
    final double rounded = (v * 10).round() / 10;
    final String n = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
    return '$n Mbps';
  }

  /// Convenience for callers/tests: a human caption for [WifiRateBasis], used by
  /// the screen's "Your Wi-Fi link" section to disclose which rates were used.
  static String rateBasisCaption(WifiRateBasis basis) {
    switch (basis) {
      case WifiRateBasis.averaged:
        return 'averaged Tx and Rx';
      case WifiRateBasis.txOnly:
        return 'Tx only (Rx not reported on this platform)';
      case WifiRateBasis.rxOnly:
        return 'Rx only (Tx not reported on this platform)';
      case WifiRateBasis.none:
        return 'no rate reported';
    }
  }

  /// Clamp helper kept for symmetry with the screen's ratio display; the engine
  /// itself never clamps the stored ratio (a >1.0 ratio is meaningful - the
  /// internet exceeds usable capacity, which IS the wifiLimiter signal).
  static double clampRatioForDisplay(double ratio) =>
      math.min(ratio, 9.99).clamp(0.0, 9.99);
}
