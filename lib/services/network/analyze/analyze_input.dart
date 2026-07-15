// Analyze Results, the engine's typed INPUT.
//
// This is the SAME data the Test My Connection result already holds, normalized
// into one flat, pure-Dart value object the rule library evaluates against. We
// build it DIRECTLY from the in-memory models (ConnectedAp, the net_quality
// QualityResult, the WifiVsInternetResult verdict, the DNS probe, and the cloud
// reachability rows), NOT by re-parsing the copied report text. The data is
// already in memory; re-parsing our own copy format would add a brittle parser
// for no gain. (The web "paste a report" analyzer in the research brief is a
// separate, later surface; this in-app engine reads the live objects.)
//
// Every numeric threshold the rules compare against is imported from the
// ratified app constants, NOT duplicated here:
//   * RSSI / SNR bands → WifiGradingBands (wifi_grading.dart, Keith 2026-06-01)
//   * latency / jitter / loss / responsiveness / download bands → QualityScoring
//     (net_quality scoring.dart)
//   * verdict thresholds → WifiVsInternetEngine (wifi_vs_internet.dart)
//   * security labels → WifiSecurity (wifi_security.dart)
// See analyze_rules.dart for where each is read.
//
// NULL DISCIPLINE (mirrors the app + the response library): a field the platform did
// not measure stays null and fires NO rule. The honesty rules (R-30/R-31)
// explain the gap instead of guessing (GL-005).

import 'package:net_quality/net_quality.dart';

import '../connected_ap.dart';
import '../connection_check.dart';
import '../dns_probe_service.dart';
import '../wifi_security.dart';
import '../wifi_vs_internet.dart';

/// The flat, immutable snapshot the rule library sees. Pure data, no behavior
/// beyond the [fromConnectionState] builder that assembles it from the live
/// models. Any field may be null: each platform/run exposes a different subset.
class AnalyzeInput {
  /// Creates an input snapshot. Tests construct this directly with plain values;
  /// production uses [fromConnectionState].
  const AnalyzeInput({
    this.verdict,
    this.rssiDbm,
    this.snrDb,
    this.linkRateMbps,
    this.band,
    this.standard,
    this.channel,
    this.channelWidthMhz,
    this.channelWidthAvailable = false,
    this.security,
    this.downloadMbps,
    this.uploadMbps,
    this.latencyMs,
    this.jitterMs,
    this.lossPct,
    this.responsivenessRpm,
    this.dnsResolutionMs,
    this.cloudReachableCount,
    this.cloudTotalCount,
    this.internetMeasured = false,
    this.wifiSignalCaptured = true,
    this.platformIsIos = false,
    this.notOnWifi = false,
    this.speedTestSkipped = false,
  });

  /// The Wi-Fi-vs-Internet verdict, when one was produced. Drives R-01..R-05.
  final WifiVsInternetVerdict? verdict;

  /// Received signal strength, dBm (negative). Null when not read.
  final int? rssiDbm;

  /// Signal-to-noise ratio, dB. Null when not read.
  final int? snrDb;

  /// The negotiated link rate fed to the verdict, avg(Tx, Rx) or the single
  /// side reported, Mbps. Null when no rate was read.
  final double? linkRateMbps;

  /// Band label ("2.4 GHz" / "5 GHz" / "6 GHz"). Null when unknown.
  final String? band;

  /// PHY / standard label (e.g. "802.11ax (Wi-Fi 6)"). Null when unknown.
  final String? standard;

  /// Primary channel number. Null / 0 sentinel when unknown.
  final int? channel;

  /// Channel width, MHz (20/40/80/160). Null when not reported.
  final int? channelWidthMhz;

  /// Whether THIS platform can ever expose channel width (iOS cannot via the
  /// Shortcut). False → the width rules suppress and R-30 explains the gap.
  final bool channelWidthAvailable;

  /// The connected network's security classification. Null when not reported.
  final WifiSecurity? security;

  /// Measured download / upload throughput, Mbps. Null when not measured.
  final double? downloadMbps;
  final double? uploadMbps;

  /// Measured internet path quality. Null when not measured.
  final double? latencyMs;
  final double? jitterMs;
  final double? lossPct;
  final double? responsivenessRpm;

  /// Measured DNS resolution time, ms. Null when no probe host resolved.
  final int? dnsResolutionMs;

  /// Cloud-app reachability tally (N of M). Both null when the panel did not run.
  final int? cloudReachableCount;
  final int? cloudTotalCount;

  /// Whether the internet path was measured at all this run (any of down/up/
  /// latency/loss present). Gates the "none reachable" cloud rule R-40.
  final bool internetMeasured;

  /// iOS-only: whether the companion Shortcut captured the live RF block. False
  /// fires the honesty rule R-31 (signal details not captured) — but ONLY when
  /// there was a Wi-Fi link to capture; see [notOnWifi].
  final bool wifiSignalCaptured;

  /// True only on the iOS source. Drives the iOS-specific honesty wording.
  final bool platformIsIos;

  /// True when the check ran with the device demonstrably NOT on Wi-Fi.
  ///
  /// [wifiSignalCaptured] is false in TWO different situations and R-31's advice
  /// ("tap Capture Wi-Fi details, which uses the companion Shortcut") is only
  /// right in one of them. On a cellular-only phone there is no link to capture,
  /// so the Shortcut cannot help and the finding is false advice — the same
  /// wrong-kind-of-null the not-on-Wi-Fi work exists to remove (GL-005). This flag
  /// separates the two, and suppresses R-31 in the second.
  final bool notOnWifi;

  /// True when the internet speed test was NOT RUN because the user declined its
  /// cellular-data cost (Keith, 2026-07-13). Distinct from "the speed test failed":
  /// nothing failed, so no rule may tell this user the test "did not complete" or
  /// invite them to "try again in a moment" — that is an invitation to spend the
  /// data they just chose not to spend (GL-005).
  final bool speedTestSkipped;

  /// Builds the input from the live Test My Connection state. Pure: a total
  /// function of its arguments, so the assembly is unit-testable without any
  /// real radio or socket.
  ///
  /// [ap]: the unified ConnectedAp (one-shot read folded with the live sample),
  /// [internet]: the net_quality result, [engine]: the verdict result,
  /// [dns]: the DNS probe result, [cloudReachable]/[cloudTotal]: the cloud
  /// panel tally, [platformIsIos] / [wifiSignalCaptured]: the iOS honesty
  /// signals.
  factory AnalyzeInput.fromConnectionState({
    required ConnectedAp? ap,
    required QualityResult? internet,
    required WifiVsInternetResult? engine,
    DnsProbeResult? dns,
    int? cloudReachable,
    int? cloudTotal,
    bool platformIsIos = false,
    bool wifiSignalCaptured = true,
    bool notOnWifi = false,
    bool speedTestSkipped = false,
  }) {
    final double? down =
        ConnectionCheck.metricValue(internet, MetricIds.download);
    final double? up = ConnectionCheck.metricValue(internet, MetricIds.upload);
    final double? latency =
        ConnectionCheck.metricValue(internet, MetricIds.latency);
    final double? jitter =
        ConnectionCheck.metricValue(internet, MetricIds.jitter);
    final double? loss = ConnectionCheck.metricValue(internet, MetricIds.loss);
    final double? rpm =
        ConnectionCheck.metricValue(internet, MetricIds.responsiveness);

    final bool internetMeasured = down != null ||
        up != null ||
        latency != null ||
        loss != null ||
        jitter != null ||
        rpm != null;

    return AnalyzeInput(
      verdict: engine?.verdict,
      rssiDbm: ap?.rssiDbm,
      snrDb: ap?.snrDb,
      linkRateMbps: engine?.linkRateMbps,
      band: _clean(ap?.band),
      standard: _clean(ap?.standard),
      channel: ap?.channel,
      channelWidthMhz: ap?.channelWidthMhz,
      channelWidthAvailable: ap?.channelWidthAvailable ?? false,
      security: ap?.securityType,
      downloadMbps: down,
      uploadMbps: up,
      latencyMs: latency,
      jitterMs: jitter,
      lossPct: loss,
      responsivenessRpm: rpm,
      dnsResolutionMs: (dns != null && dns.isAvailable) ? dns.millis : null,
      cloudReachableCount: cloudReachable,
      cloudTotalCount: cloudTotal,
      internetMeasured: internetMeasured,
      wifiSignalCaptured: wifiSignalCaptured,
      platformIsIos: platformIsIos,
      notOnWifi: notOnWifi,
      speedTestSkipped: speedTestSkipped,
    );
  }

  /// A non-empty trimmed string, or null. Keeps the rules from firing on a
  /// blank/whitespace value (treated as "not reported").
  static String? _clean(String? v) {
    if (v == null) return null;
    final String t = v.trim();
    return t.isEmpty ? null : t;
  }

  // ── Derived helpers the rules read (kept on the input so the rule predicates
  //    stay one-liners and the band/2.4-GHz logic lives in one place). ──

  /// True when the band is the 2.4 GHz band.
  bool get isBand24 => band == '2.4 GHz';

  /// True when the band is a "fast" band (5 or 6 GHz), where a narrow width is
  /// the meaningful R-23 case.
  bool get isFastBand => band == '5 GHz' || band == '6 GHz';

  /// True when the channel is a real, usable channel number (not null / the 0
  /// sentinel some stacks return for "unknown").
  bool get hasRealChannel => channel != null && channel != 0;

  /// Whether the PHY/standard string names Wi-Fi 4 or older (802.11 a/b/g/n),
  /// the legacy-ceiling case for R-21. Case-insensitive substring match on the
  /// labels the app produces ("802.11n (Wi-Fi 4)", "802.11g", …).
  bool get isLegacyPhy {
    final String? s = standard?.toLowerCase();
    if (s == null) return false;
    return s.contains('wi-fi 4') ||
        s.contains('802.11n') ||
        s.contains('802.11g') ||
        // Match real 802.11b but NOT 802.11be (Wi-Fi 7): a bare "802.11b" is
        // only legacy when not immediately followed by another letter. The
        // lookahead excludes "802.11be …" (and any future 802.11b-prefixed
        // token) while still catching every label the app produces — the macOS
        // bare "802.11b", the iOS dash form "802.11b - Wi-Fi 1", and a
        // parenthesized "802.11b (…)".
        RegExp(r'802\.11b(?![a-z])').hasMatch(s) ||
        s.contains('802.11a)') || // "802.11a (…)", avoid matching 802.11ac/ax
        s == '802.11a';
  }

  /// Whether the PHY/standard string names Wi-Fi 5 (802.11ac), the R-22 case.
  bool get isWifi5Phy {
    final String? s = standard?.toLowerCase();
    if (s == null) return false;
    return s.contains('wi-fi 5') || s.contains('802.11ac');
  }
}
