import 'dart:async';

/// Takes one latency sample and returns its RTT. The injectable sampling seam.
typedef LatencySampler = Future<Duration> Function();

/// Generates network load while responsiveness is sampled. The injectable load
/// seam (the real engine uses a throughput download).
typedef LoadGenerator = Future<void> Function();

/// Responsiveness statistics under load.
class ResponsivenessStats {
  /// Responsiveness in round-trips per minute, derived from loaded latency.
  final double rpm;

  /// Mean RTT measured while load was running, milliseconds.
  final double loadedAvgRttMs;

  /// Mean RTT measured while idle, milliseconds.
  final double idleAvgRttMs;

  /// Number of loaded samples taken.
  final int samples;

  /// Creates responsiveness statistics.
  const ResponsivenessStats({
    required this.rpm,
    required this.loadedAvgRttMs,
    required this.idleAvgRttMs,
    required this.samples,
  });

  @override
  String toString() =>
      'ResponsivenessStats(${rpm.toStringAsFixed(0)} RPM, '
      'loaded ${loadedAvgRttMs.toStringAsFixed(1)}ms, '
      'idle ${idleAvgRttMs.toStringAsFixed(1)}ms, $samples samples)';
}

/// Measures responsiveness under load.
///
/// IMPORTANT: this is a SIMPLIFIED, single-flow loaded-latency RPM. It is
/// INSPIRED BY RFC 9097 and Apple's networkQuality tool, but it is NOT the full
/// multi-flow RPM standard. The standard ramps up many parallel flows until the
/// link saturates and measures latency across multiple protocol layers. We run
/// a single load flow and one latency stream, so the RPM here is a directional
/// indicator, not a standards-conformant RPM value. Do not present it as one.
class ResponsivenessProbe {
  /// Latency sampling seam.
  final LatencySampler latencySampler;

  /// Load generation seam.
  final LoadGenerator loadGenerator;

  /// Number of idle samples to establish a baseline.
  final int idleSamples;

  /// Number of samples to take while load runs.
  final int loadedSamples;

  /// Creates a responsiveness probe.
  const ResponsivenessProbe({
    required this.latencySampler,
    required this.loadGenerator,
    this.idleSamples = 3,
    this.loadedSamples = 5,
  });

  /// Runs the probe: idle baseline, then load with concurrent sampling.
  Future<ResponsivenessStats> measure() async {
    final idleAvg = await _averageSamples(idleSamples);

    // Start the load WITHOUT awaiting, so sampling overlaps with it.
    final loadFuture = loadGenerator();
    final loadedAvg = await _averageSamples(loadedSamples);
    await loadFuture;

    final rpm = loadedAvg <= 0 ? 0.0 : 60000.0 / loadedAvg;

    return ResponsivenessStats(
      rpm: rpm,
      loadedAvgRttMs: loadedAvg,
      idleAvgRttMs: idleAvg,
      samples: loadedSamples,
    );
  }

  /// Averages [count] latency samples, in milliseconds. Returns 0 for a
  /// non-positive count.
  Future<double> _averageSamples(int count) async {
    if (count <= 0) return 0.0;
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      final d = await latencySampler();
      sum += d.inMicroseconds / 1000.0;
    }
    return sum / count;
  }
}
