// Connection-check glue — the ONE shared bridge between the two measurement
// engines (the connected-AP link read + net_quality) and the pure
// [WifiVsInternetEngine].
//
// This is the de-duplication Keith flagged: `_compute()`, `_internetHealth()`,
// and `_metricValue()` were copy-pasted VERBATIM between the old
// `wifi_vs_internet_screen` (pro) and `test_my_connection_screen` (consumer).
// Both screens collapsed into the one merged Test My Connection screen, and that
// screen now calls these shared functions instead of carrying its own copy.
//
// PURE glue, NO new logic: every line here moved out of the screens unchanged.
// It adds zero measurement, zero verdict math (that all lives in
// [WifiVsInternetEngine] and [ConsumerVerdictMapper], both untouched). Keeping
// it in one place means a future change to the grade gate or the rate forwarding
// is a single edit, not two that can drift.

import 'package:net_quality/net_quality.dart';

import 'connected_ap.dart';
import 'wifi_vs_internet.dart';

/// Stateless glue between the measured inputs and the pure verdict engine.
class ConnectionCheck {
  const ConnectionCheck._();

  /// Bridges the two engines into the pure [WifiVsInternetEngine]: translates
  /// the net_quality grades into the engine's [InternetHealth] flag at the
  /// boundary (keeping the engine Flutter-free) and forwards the link rates.
  /// Lifted verbatim from both source screens' `_compute()`.
  ///
  /// [onlineEvidence] carries the out-of-band "you're online" signals (DNS
  /// resolved + public IP + cloud reachability) so the engine can produce the
  /// honest [WifiVsInternetVerdict.onlineUnmeasured] verdict when the speed test
  /// stalled but the device is clearly online. It defaults to no evidence, so a
  /// caller that has not gathered it yet gets the prior behavior unchanged.
  ///
  /// [notOnWifi] is the caller's POSITIVE not-on-Wi-Fi probe result. It lets the
  /// engine tell "we could not read the Wi-Fi link" apart from "there IS no
  /// Wi-Fi link" (GL-005, two kinds of null) — the distinction that stopped Test
  /// My Connection telling a cellular-only user to "boost the Wi-Fi signal".
  /// Defaults to false, so a caller that has not probed gets the prior behavior.
  static WifiVsInternetResult compute(
    ConnectedAp? ap,
    QualityResult? internet, {
    OnlineEvidence onlineEvidence = const OnlineEvidence(),
    bool notOnWifi = false,
    bool speedTestSkipped = false,
  }) {
    final double? down = metricValue(internet, MetricIds.download);
    final double? up = metricValue(internet, MetricIds.upload);

    return WifiVsInternetEngine.evaluate(
      txRateMbps: ap?.txRateMbps,
      rxRateMbps: ap?.rxRateMbps,
      rxRateAvailable: ap?.rxRateAvailable ?? false,
      snrDb: ap?.snrDb,
      rssiDbm: ap?.rssiDbm,
      internetDownMbps: down,
      internetUpMbps: up,
      internetHealth: internetHealth(internet),
      onlineEvidence: onlineEvidence,
      notOnWifi: notOnWifi,
      speedTestSkipped: speedTestSkipped,
    );
  }

  /// Grade gate input: GOOD only when throughput (download AND upload),
  /// latency, and loss ALL grade good/excellent. A missing/unavailable grade on
  /// any of the gating dimensions counts as NOT good, so the ratio gets to
  /// diagnose. Lifted verbatim from both source screens' `_internetHealth()`.
  static InternetHealth internetHealth(QualityResult? r) {
    if (r == null) return InternetHealth.marginal;
    bool ok(String id) {
      final QualityMetric? m = r.metric(id);
      return m != null &&
          (m.grade == QualityGrade.good || m.grade == QualityGrade.excellent);
    }

    final bool throughputGood = ok(MetricIds.download) && ok(MetricIds.upload);
    final bool latencyGood = ok(MetricIds.latency);
    final bool lossGood = ok(MetricIds.loss);
    return (throughputGood && latencyGood && lossGood)
        ? InternetHealth.good
        : InternetHealth.marginal;
  }

  /// A dimension's measured value, or null when the metric is absent or the run
  /// could not measure it. Lifted verbatim from both source screens'
  /// `_metricValue()`.
  static double? metricValue(QualityResult? r, String id) {
    final QualityMetric? m = r?.metric(id);
    return (m != null && m.isAvailable) ? m.value : null;
  }
}
