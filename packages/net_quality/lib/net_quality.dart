/// Backend-agnostic network-quality measurement for the WLAN Pros Toolbox.
///
/// Pure Dart, no Flutter. Exposes the [QualityClient] seam, a graded
/// [QualityResult] model, a deterministic mock, and a real probe engine.
library;

export 'src/mock_quality_client.dart';
export 'src/own_engine_quality_client.dart';
export 'src/popular_sites.dart';
export 'src/probes/latency_probe.dart';
export 'src/probes/reachability_probe.dart';
export 'src/probes/responsiveness_probe.dart';
export 'src/probes/throughput_probe.dart';
export 'src/quality_client.dart';
export 'src/quality_grade.dart';
export 'src/quality_metric.dart';
export 'src/quality_result.dart';
export 'src/scoring.dart';
