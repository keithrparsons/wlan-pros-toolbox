// Live smoke run of the net_quality engine against the REAL network.
//
// This is NOT a unit test (those use injected fakes). It runs the actual
// OwnEngineQualityClient and ReachabilityProbe over real sockets/HTTP on this
// machine, so we can confirm the engine produces sane numbers end to end.
//
// Run from the package root:
//   dart run tool/live_run.dart
//
// Pure Dart, no Flutter. Uses dart:io directly, so it is NOT sandboxed the way
// the macOS app is; it validates the measurement logic and real connectivity.

import 'package:net_quality/net_quality.dart';

Future<void> main() async {
  // ignore: avoid_print
  print('net_quality live run against the real network\n');

  final client = OwnEngineQualityClient.forHost('one.one.one.one');

  // ignore: avoid_print
  print('Measuring (latency -> throughput -> responsiveness)...');
  await for (final p in client.measure()) {
    // ignore: avoid_print
    print('  ${p.phase.name.padRight(14)} ${(p.fraction * 100).toStringAsFixed(0)}%');
  }

  final result = client.lastResult!;
  // ignore: avoid_print
  print('\nTransport metrics (source: ${result.source.name}):');
  for (final m in result.metrics) {
    final value = m.isAvailable
        ? '${m.value!.toStringAsFixed(1)} ${m.unit}'
        : 'unavailable${m.note != null ? ' (${m.note})' : ''}';
    // ignore: avoid_print
    print('  ${m.label.padRight(16)} ${value.padRight(22)} [${m.grade.label}]');
  }

  // ignore: avoid_print
  print('\nPopular-site reachability:');
  final sites = await ReachabilityProbe().measure();
  for (final s in sites) {
    final status = s.reachable
        ? '${s.latencyMs!.toStringAsFixed(0)} ms'.padRight(10)
        : 'unreachable'.padRight(10);
    // ignore: avoid_print
    print('  ${s.site.name.padRight(14)} $status ${s.reachable ? 'reachable' : 'UNREACHABLE'}');
  }

  // ignore: avoid_print
  print('\nDone.');
}
