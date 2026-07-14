// THE ENGINE'S CELLULAR-DATA CONSENT GATE — certified by the ROOT suite.
//
// WHY THIS FILE LIVES IN `test/` AND NOT IN `packages/net_quality/test/`
// (round-4 P2, 2026-07-14).
//
// `OwnEngineQualityClient.measure` has ONE line deciding whether a gigabyte of a
// user's cellular data moves:
//
//     if (includeThroughput) {          // own_engine_quality_client.dart:270
//       ...download + upload + the RPM load generator...
//     } else {
//       ...honestly-unavailable metrics with the "not measured" reason...
//     }
//
// MEASURED, NOT ASSUMED: mutating that to `if (true)` left the ROOT `flutter test`
// run GREEN at 4,186 tests. The line is only exercised by
// `packages/net_quality/test/`, which the root run does not include — and which,
// as of today, does not even COMPILE (those files import `package:test/test.dart`,
// which is not resolvable in this workspace: "Error: Couldn't resolve the package
// 'test'"). So the single most expensive decision in the app was covered by a test
// that never ran, in a suite we do not certify releases with.
//
// A test that exists but never runs is not a test. This one runs.
//
// It drives the REAL `OwnEngineQualityClient` — not a mock — over injected probe
// seams, so nothing touches the network, and asserts the property that actually
// matters: WHEN CONSENT IS WITHHELD, THE BYTES DO NOT MOVE. The download, the
// upload, and the RPM load generator (the expensive stage nobody thinks about) are
// each proven never to have been invoked.

import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';

/// Records every call, performs no I/O. If the gate leaks, these counters rise.
class _Spy {
  int downloads = 0;
  int uploads = 0;
  int rpmLoads = 0;
  int latencySamples = 0;
}

/// The real engine, wired to probes that cannot reach the network.
OwnEngineQualityClient _engine(_Spy spy) {
  final ThroughputProbe throughput = ThroughputProbe(
    // Both data-hungry seams are counted. A byte moved is a byte spent.
    downloader: (Uri uri, Duration maxDuration) async {
      spy.downloads++;
      return 1000000;
    },
    uploader: (Uri uri, int bytes, Duration maxDuration) async {
      spy.uploads++;
      return bytes;
    },
  );

  final LatencyProbe latency = LatencyProbe(
    host: 'example.invalid',
    samples: 2,
    connector: (String host, int port, Duration timeout) async {
      spy.latencySamples++;
      return const Duration(milliseconds: 20);
    },
  );

  final ResponsivenessProbe responsiveness = ResponsivenessProbe(
    latencySampler: () async => const Duration(milliseconds: 20),
    // THE STAGE NOBODY THINKS ABOUT. The RPM probe's load generator is another
    // full-window download. Skipping the "speed test" while leaving RPM running
    // would still burn ~15 s of data at full rate — which is exactly why the
    // engine gates the two as ONE unit. This counter is the proof that it does.
    loadGenerator: () async => spy.rpmLoads++,
  );

  return OwnEngineQualityClient(
    latencyProbe: latency,
    throughputProbe: throughput,
    responsivenessProbe: responsiveness,
    clock: () => DateTime.utc(2026, 1, 1),
  );
}

Future<QualityResult?> _run(
  OwnEngineQualityClient engine, {
  required bool includeThroughput,
  // These cases certify the CONSENT gate (do bytes move at all?), which is a
  // separate question from the cellular RPM decision. Default to the Wi-Fi path
  // so this file keeps testing exactly what it always tested.
  bool includeResponsiveness = true,
}) async {
  await engine
      .measure(
        includeThroughput: includeThroughput,
        includeResponsiveness: includeResponsiveness,
      )
      .drain<void>();
  return engine.lastResult;
}

void main() {
  group("the engine's cellular-data consent gate (root-certified)", () {
    test('consent WITHHELD: not one byte of throughput moves', () async {
      final _Spy spy = _Spy();
      final OwnEngineQualityClient engine = _engine(spy);

      await _run(engine, includeThroughput: false);

      expect(spy.downloads, 0,
          reason: 'the download stage transfers rate x window. It must not run '
              'when the user declined the data cost.');
      expect(spy.uploads, 0, reason: 'nor the upload stage');
      expect(spy.rpmLoads, 0,
          reason: 'NOR THE RPM LOAD GENERATOR — a second full-window download, '
              'and the one that is easy to forget. Gating "the speed test" while '
              'leaving this running would still burn ~15 s of data at full rate.');

      // And the run is still USEFUL: latency/jitter/loss are cheap TCP-connect
      // samples and must still be taken. A consent gate that produces nothing is
      // not a gate, it is a broken feature.
      expect(spy.latencySamples, greaterThan(0),
          reason: 'declining the data cost must still give the user a result');
    });

    test('consent WITHHELD: the skipped metrics are "not measured", not failed',
        () async {
      // GL-005, the two kinds of null. A metric we CHOSE not to take is not a
      // metric we TRIED and FAILED to take, and the note is what lets the UI say
      // which. This is what drives AxisStatus.notMeasured instead of "Couldn't
      // check" on the screen.
      final QualityResult? result =
          await _run(_engine(_Spy()), includeThroughput: false);

      expect(result, isNotNull);
      for (final String id in <String>[
        MetricIds.download,
        MetricIds.upload,
        MetricIds.responsiveness,
      ]) {
        final QualityMetric m =
            result!.metrics.firstWhere((QualityMetric e) => e.id == id);
        expect(m.value, isNull,
            reason: '$id must not be fabricated as a zero');
        expect(m.note, OwnEngineQualityClient.kSkippedNote,
            reason: '$id must carry the "we did not try" reason, so the UI can '
                'say "Not measured" and never "Couldn\'t check"');
      }
    });

    test('consent GIVEN: the throughput stages DO run', () async {
      // THE OTHER HALF. Without this, every assertion above would also pass
      // against an engine that never runs throughput under ANY condition — a
      // "gate" that works by breaking the product. This is the test that makes
      // the mutation `if (includeThroughput)` -> `if (true)` detectable AND the
      // mutation -> `if (false)` detectable.
      final _Spy spy = _Spy();
      await _run(_engine(spy), includeThroughput: true);

      expect(spy.downloads, greaterThan(0),
          reason: 'a consented run must actually measure throughput');
      expect(spy.rpmLoads, greaterThan(0),
          reason: 'and must run the responsiveness load');
    });
  });
}
