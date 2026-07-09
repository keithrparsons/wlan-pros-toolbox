// PiBackendQualityClient — adapts the Pi's `conntest` into the net_quality
// QualityClient seam used by the Network Quality (net-quality) screen.
//
// The Network Quality screen depends only on the QualityClient interface, never
// on a concrete probe, so on Pi-hosted web we swap in this client instead of the
// `dart:io`-socket OwnEngineQualityClient. It maps the Pi's connection test into
// the SAME graded QualityResult model the screen already renders.
//
// HONESTY (GL-005 / GL-008): the Pi's conntest measures gateway + internet
// latency/loss, internet-target jitter (`internet.jitter_ms`, when computable),
// and DNS-resolution time; a separate throughput probe measures the Pi's own
// uplink (Pi -> internet) download/upload. The Pi does NOT measure the end-user's
// own Wi-Fi RF or a loaded-responsiveness figure, and jitter/throughput can each
// come back null when the Pi could not compute them. Every dimension the Pi
// cannot back is returned as a first-class `QualityGrade.unavailable` metric with
// a plain "Not measured by the Pi sensor" note — never faked, never zero-filled.
// The raw hops (gateway/internet/DNS) are also exposed via [lastConntest] so the
// screen can show them as reachability rows.

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
  PiThroughputResult? _lastThroughput;

  @override
  QualityResult? get lastResult => _last;

  /// The raw hops from the most recent successful run, so the screen can render
  /// gateway / internet / DNS reachability rows. Null before the first run.
  PiConntestResult? get lastConntest => _lastConntest;

  /// The Pi's own uplink throughput (Pi → internet) from the most recent run, so
  /// the screen can attribute the download/upload rows to the Pi's uplink and
  /// keep them distinct from the browser↔Pi Wi-Fi-hop figure. Null before the
  /// first run, or when the throughput probe failed.
  PiThroughputResult? get lastThroughput => _lastThroughput;

  @override
  bool get isAvailable => kIsWeb && PiBackend.available;

  @override
  Stream<QualityProgress> measure() async* {
    yield const QualityProgress(QualityPhase.idle, 0);
    // The Pi conntest backs latency/loss/DNS; report the latency phase while it
    // runs so the progress bar reads honestly. A failure here (non-200 / timeout
    // / malformed) propagates as a stream error, which the screen surfaces
    // through its existing onError state.
    yield const QualityProgress(QualityPhase.latency, 0.25);
    final PiConntestResult ct = await _client.conntest();
    _lastConntest = ct;
    // The Pi's own uplink throughput (Pi → internet) is a SEPARATE round-trip.
    // It is best-effort: a failure leaves [_lastThroughput] null and the
    // download/upload rows fall back to their honest "not measured" note rather
    // than failing the whole run.
    yield const QualityProgress(QualityPhase.download, 0.6);
    PiThroughputResult? tp;
    try {
      tp = await _client.throughput();
    } on Object {
      tp = null;
    }
    _lastThroughput = tp;
    _last = _resultFrom(ct, tp);
    yield const QualityProgress(QualityPhase.complete, 1.0);
  }

  static const String _notMeasured = 'Not measured by the Pi sensor.';

  QualityResult _resultFrom(PiConntestResult ct, PiThroughputResult? tp) {
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

    // Jitter — the Pi's internet-target jitter (JSON `internet.jitter_ms`),
    // graded on the same bands as the native engine. The Pi now computes this
    // from its ICMP series, so it is a real value when present; when the Pi
    // could not compute one (null), it stays a first-class unavailable metric
    // with the honest note, never faked or zero-filled (GL-005).
    final double? jitter = ct.internet.jitterMs;
    if (jitter != null) {
      metrics.add(QualityMetric(
        id: MetricIds.jitter,
        label: 'Jitter',
        value: jitter,
        unit: 'ms',
        grade: QualityScoring.gradeJitterMs(jitter),
      ));
    } else {
      metrics.add(const QualityMetric.unavailable(
        id: MetricIds.jitter,
        label: 'Jitter',
        unit: 'ms',
        note: _notMeasured,
      ));
    }
    // Download / Upload — the Pi's OWN uplink to the internet (Pi → internet),
    // measured by the Pi against a vendor-neutral public endpoint. This is
    // distinct from the browser↔Pi Wi-Fi-hop figure the screen shows in its own
    // card; the two are never conflated. A leg that failed on the Pi stays
    // honest-null with the Pi's own error note, never a fabricated 0 (GL-005).
    final double? down = tp?.downloadMbps;
    if (down != null) {
      metrics.add(QualityMetric(
        id: MetricIds.download,
        label: 'Download',
        value: down,
        unit: 'Mbps',
        grade: QualityScoring.gradeDownloadMbps(down),
      ));
    } else {
      metrics.add(QualityMetric.unavailable(
        id: MetricIds.download,
        label: 'Download',
        unit: 'Mbps',
        note: _blank(tp?.downloadError) ?? _notMeasured,
      ));
    }
    final double? up = tp?.uploadMbps;
    if (up != null) {
      metrics.add(QualityMetric(
        id: MetricIds.upload,
        label: 'Upload',
        value: up,
        unit: 'Mbps',
        grade: QualityScoring.gradeUploadMbps(up),
      ));
    } else {
      metrics.add(QualityMetric.unavailable(
        id: MetricIds.upload,
        label: 'Upload',
        unit: 'Mbps',
        note: _blank(tp?.uploadError) ?? _notMeasured,
      ));
    }
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

  static String? _blank(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}
