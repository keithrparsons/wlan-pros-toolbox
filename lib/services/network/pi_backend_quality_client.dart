// PiBackendQualityClient — adapts the Pi's `conntest` into the net_quality
// QualityClient seam used by the Network Quality (net-quality) screen.
//
// The Network Quality screen depends only on the QualityClient interface, never
// on a concrete probe, so on Pi-hosted web we swap in this client instead of the
// `dart:io`-socket OwnEngineQualityClient. It maps the Pi's connection test into
// the SAME graded QualityResult model the screen already renders.
//
// HONESTY (GL-005 / GL-008): the Pi's conntest measures gateway + internet
// latency/loss and DNS-resolution time. It does NOT measure jitter, throughput
// (download/upload), the end-user's own Wi-Fi RF, or a loaded-responsiveness
// figure. Those dimensions are returned as first-class `QualityGrade.unavailable`
// metrics with a plain "Not measured by the Pi sensor" note — never faked, never
// zero-filled. The raw hops (gateway/internet/DNS) are also exposed via
// [lastConntest] so the screen can show them as reachability rows.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:net_quality/net_quality.dart';

import 'pi_backend.dart';
import 'pi_backend_client.dart';

class PiBackendQualityClient implements QualityClient {
  PiBackendQualityClient({PiBackendClient? client})
      : _client = client ?? PiBackendClient();

  final PiBackendClient _client;

  QualityResult? _last;
  PiConntestResult? _lastConntest;

  @override
  QualityResult? get lastResult => _last;

  /// The raw hops from the most recent successful run, so the screen can render
  /// gateway / internet / DNS reachability rows. Null before the first run.
  PiConntestResult? get lastConntest => _lastConntest;

  @override
  bool get isAvailable => kIsWeb && PiBackend.available;

  @override
  Stream<QualityProgress> measure() async* {
    yield const QualityProgress(QualityPhase.idle, 0);
    // A single Pi round-trip backs the whole measurement; report the latency
    // phase while it runs so the progress bar reads honestly.
    yield const QualityProgress(QualityPhase.latency, 0.3);
    // A failure here (non-200 / timeout / malformed) propagates as a stream
    // error, which the screen surfaces through its existing onError state.
    final PiConntestResult ct = await _client.conntest();
    _lastConntest = ct;
    _last = _resultFrom(ct);
    yield const QualityProgress(QualityPhase.complete, 1.0);
  }

  static const String _notMeasured = 'Not measured by the Pi sensor.';

  QualityResult _resultFrom(PiConntestResult ct) {
    final List<QualityMetric> metrics = <QualityMetric>[];

    // Latency — the Pi's internet-target average RTT, graded on the same bands
    // as the native engine.
    final double? avg = ct.internet.avgMs;
    if (ct.internet.reachable && avg != null) {
      metrics.add(QualityMetric(
        id: MetricIds.latency,
        label: 'Latency',
        value: avg,
        unit: 'ms',
        grade: QualityScoring.gradeLatencyMs(avg),
      ));
    } else {
      metrics.add(const QualityMetric.unavailable(
        id: MetricIds.latency,
        label: 'Latency',
        unit: 'ms',
        note: 'The Pi could not reach the internet target.',
      ));
    }

    // Loss — the Pi's internet-target loss percentage.
    final double? loss = ct.internet.lossPct;
    if (loss != null) {
      metrics.add(QualityMetric(
        id: MetricIds.loss,
        label: 'Loss',
        value: loss,
        unit: '%',
        grade: QualityScoring.gradeLossPct(loss),
      ));
    } else {
      metrics.add(const QualityMetric.unavailable(
        id: MetricIds.loss,
        label: 'Loss',
        unit: '%',
        note: _notMeasured,
      ));
    }

    // Dimensions the Pi sensor does not measure — first-class unavailable, never
    // faked (GL-005). The screen already renders the unavailable state honestly.
    metrics.add(const QualityMetric.unavailable(
      id: MetricIds.jitter,
      label: 'Jitter',
      unit: 'ms',
      note: _notMeasured,
    ));
    metrics.add(const QualityMetric.unavailable(
      id: MetricIds.download,
      label: 'Download',
      unit: 'Mbps',
      note: _notMeasured,
    ));
    metrics.add(const QualityMetric.unavailable(
      id: MetricIds.upload,
      label: 'Upload',
      unit: 'Mbps',
      note: _notMeasured,
    ));
    metrics.add(const QualityMetric.unavailable(
      id: MetricIds.responsiveness,
      label: 'Responsiveness',
      unit: 'RPM',
      note: _notMeasured,
    ));

    return QualityResult(
      metrics: metrics,
      // The engine that produced this is the app's own (running on the Pi), not
      // a mock; ownEngine is the honest source tag.
      source: QualitySource.ownEngine,
      measuredAt: DateTime.now(),
    );
  }
}
