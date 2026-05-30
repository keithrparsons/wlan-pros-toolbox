// EXPERIMENTAL / SPIKE harness — runs an iperf3 client test through Dart FFI and
// prints the real JSON throughput summary it gets back from libiperf.
//
// Usage (from repo root, after running third_party/iperf3/fetch_and_build.sh):
//   dart run tool/iperf_spike_harness.dart <host> [port] [duration] [reverse]
//
// Examples:
//   dart run tool/iperf_spike_harness.dart 127.0.0.1 5201 5
//   dart run tool/iperf_spike_harness.dart speedtest.serverius.net 5002 5 true
//
// macOS only. The blocking iperf_run_client call is run inside Isolate.run to
// model the off-main-isolate execution a real integration would need.

import 'dart:convert';
import 'dart:isolate';

import 'package:wlan_pros_toolbox/services/network/iperf_ffi_spike.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run tool/iperf_spike_harness.dart <host> [port] '
        '[duration] [reverse]');
    return;
  }
  final host = args[0];
  final port = args.length > 1 ? int.parse(args[1]) : 5201;
  final duration = args.length > 2 ? int.parse(args[2]) : 5;
  final reverse = args.length > 3 ? args[3].toLowerCase() == 'true' : false;

  final dylib = resolveSpikeDylibPath();
  print('== iperf3 FFI spike ==');
  print('dylib   : $dylib');
  print('target  : $host:$port  duration=${duration}s  reverse=$reverse');
  print('running blocking iperf_run_client inside Isolate.run ...\n');

  final result = await Isolate.run(() {
    final spike = IperfFfiSpike(dylib);
    return spike.runClientTest(
      host: host,
      port: port,
      durationSeconds: duration,
      reverse: reverse,
    );
  });

  print('runCode : ${result.runCode}');
  if (result.errorText != null) print('error   : ${result.errorText}');

  if (result.json == null || result.json!.isEmpty) {
    print('No JSON returned.');
    return;
  }

  // Pretty-print + pull the throughput numbers out of the real summary.
  final decoded = jsonDecode(result.json!) as Map<String, dynamic>;
  final end = decoded['end'] as Map<String, dynamic>?;

  print('\n--- parsed throughput (from real FFI JSON) ---');
  if (end != null) {
    final sumSent = end['sum_sent'] as Map<String, dynamic>?;
    final sumRecv = end['sum_received'] as Map<String, dynamic>?;
    if (sumSent != null) {
      final bps = (sumSent['bits_per_second'] as num).toDouble();
      print('sum_sent     : ${(bps / 1e6).toStringAsFixed(2)} Mbit/s '
          '(${sumSent['bytes']} bytes over ${sumSent['seconds']}s)');
    }
    if (sumRecv != null) {
      final bps = (sumRecv['bits_per_second'] as num).toDouble();
      print('sum_received : ${(bps / 1e6).toStringAsFixed(2)} Mbit/s '
          '(${sumRecv['bytes']} bytes over ${sumRecv['seconds']}s)');
    }
  }

  print('\n--- raw JSON (truncated to first 1200 chars) ---');
  final raw = const JsonEncoder.withIndent('  ').convert(decoded);
  print(raw.length > 1200 ? '${raw.substring(0, 1200)}\n...[truncated]' : raw);
}
