// RED-FIRST GUARDS for the cellular RPM decision (Keith, 2026-07-14).
//
// THE RULING: do not measure RPM on cellular at all. RPM is an ADJUNCT to what
// Test My Connection is for. A shortened load window would understate loaded
// latency and therefore FLATTER `rpm = 60000 / loadedAvg` — an optimistic number
// with a caveat is exactly the disease this codebase spent two days killing. Not
// measuring an adjunct is the honest answer, it is faster, and it spends less of
// the user's cellular data.
//
// WHAT THESE TESTS PIN, and why each one exists:
//   1. On cellular the RPM load generator NEVER RUNS — not a short one, none. The
//      load is a full-rate download; not running it is the data saving.
//   2. The skipped metric reads as a DELIBERATE CHOICE, never as a failure. A
//      deliberate skip presented as an error is the "Couldn't check" bug in a new
//      metric.
//   3. On Wi-Fi the FULL RPM still runs, unchanged.
//   4. THE BAR NEVER FREEZES. The old ticker interpolated the responsiveness band
//      against `throughputProbe.maxDuration` alone, so a stage that outran that
//      denominator pinned the bar at the top of its band and sat there. That is a
//      freeze, and a frozen bar reads as a hang.
//   5. The RPM load is BUDGET-BOUNDED, so one slow endpoint cannot cascade into a
//      walk of the whole pool (the ~36 s Keith measured on his phone).

import 'package:net_quality/net_quality.dart';
import 'package:test/test.dart';

/// A latency probe seam that always returns the same RTT.
Future<Duration> Function() _constSampler(int ms) =>
    () async => Duration(milliseconds: ms);

/// Builds a client whose stages have SHORT, KNOWN windows so the timing
/// assertions below run in milliseconds instead of the real 15 s.
///
/// [loadDuration] is how long the RPM load generator takes. Setting it LONGER
/// than [maxDuration] reproduces the real-world case: a throttled cellular
/// endpoint burning the whole window (and, before the budget fix, walking to the
/// next endpoint and burning another).
OwnEngineQualityClient _client({
  required Duration maxDuration,
  required Duration loadDuration,
  int idleSamples = 1,
  int loadedSamples = 1,
  void Function()? onLoadRun,
}) {
  final ThroughputProbe throughput = ThroughputProbe(
    downloadStreamCount: 1,
    warmUp: Duration.zero,
    maxDuration: maxDuration,
    downloadEndpoints: <Uri>[Uri.parse('https://a.test/down')],
    uploadEndpoints: <Uri>[Uri.parse('https://a.test/up')],
    downloader: (Uri uri, Duration max) async => 10 * 1000 * 1000,
    uploader: (Uri uri, int bytes, Duration max) async => bytes,
  );

  final ResponsivenessProbe responsiveness = ResponsivenessProbe(
    idleSamples: idleSamples,
    loadedSamples: loadedSamples,
    latencySampler: _constSampler(20),
    loadGenerator: () async {
      onLoadRun?.call();
      await Future<void>.delayed(loadDuration);
    },
  );

  return OwnEngineQualityClient(
    latencyProbe: LatencyProbe(
      host: 'h',
      samples: 1,
      connector: (String h, int p, Duration t) async =>
          const Duration(milliseconds: 10),
    ),
    throughputProbe: throughput,
    responsivenessProbe: responsiveness,
  );
}

void main() {
  group('cellular: RPM is not measured at all (Keith 2026-07-14)', () {
    test('the RPM load generator NEVER runs when responsiveness is excluded',
        () async {
      // THE DATA SAVING. The RPM load is a full-rate download, ADDITIONAL to the
      // throughput stage. "Skip RPM" only saves cellular data if the LOAD does
      // not run — a shortened load would still spend.
      var loadRuns = 0;
      final OwnEngineQualityClient client = _client(
        maxDuration: const Duration(milliseconds: 120),
        loadDuration: const Duration(milliseconds: 60),
        onLoadRun: () => loadRuns++,
      );

      await client
          .measure(includeThroughput: true, includeResponsiveness: false)
          .drain<void>();

      expect(loadRuns, 0,
          reason: 'the RPM load generator must not run on cellular at all');
    });

    test('the skipped RPM metric reads as a DELIBERATE CHOICE, not a failure',
        () async {
      final OwnEngineQualityClient client = _client(
        maxDuration: const Duration(milliseconds: 120),
        loadDuration: const Duration(milliseconds: 60),
      );

      await client
          .measure(includeThroughput: true, includeResponsiveness: false)
          .drain<void>();

      final QualityMetric rpm =
          client.lastResult!.metric(MetricIds.responsiveness)!;

      // It is a null — but it is the THIRD kind of null: "we did not try, on
      // purpose". The note is what tells the UI which (GL-005).
      expect(rpm.isAvailable, isFalse);
      expect(rpm.value, isNull);
      expect(rpm.note, OwnEngineQualityClient.kResponsivenessCellularNote);

      // It must NEVER read as a failure or a fabricated zero.
      final String note = rpm.note!;
      expect(note.toLowerCase(), isNot(contains('failed')));
      expect(note.toLowerCase(), isNot(contains('unavailable')));
      expect(note.toLowerCase(), isNot(contains("couldn't")));
      expect(note.toLowerCase(), isNot(contains('error')));

      // It must name the REASON in plain words: a choice, and why.
      expect(note.toLowerCase(), contains('cellular'));
      expect(note.toLowerCase(), contains('wi-fi'),
          reason: 'tell the user where they CAN get the number');
    });

    test('the DELIBERATE cellular skip is distinguishable from a FAILED probe',
        () async {
      // Two different nulls must not collapse to one string. A probe that threw
      // is "Measurement failed"; a probe we chose not to run is not.
      final OwnEngineQualityClient failing = _client(
        maxDuration: const Duration(milliseconds: 120),
        loadDuration: Duration.zero,
      );
      final OwnEngineQualityClient skipping = _client(
        maxDuration: const Duration(milliseconds: 120),
        loadDuration: Duration.zero,
      );

      // A real failure: the load generator throws.
      final OwnEngineQualityClient thrower = OwnEngineQualityClient(
        latencyProbe: failing.latencyProbe,
        throughputProbe: failing.throughputProbe,
        responsivenessProbe: ResponsivenessProbe(
          idleSamples: 1,
          loadedSamples: 1,
          latencySampler: _constSampler(20),
          loadGenerator: () async => throw StateError('load died'),
        ),
      );

      await thrower
          .measure(includeThroughput: true, includeResponsiveness: true)
          .drain<void>();
      await skipping
          .measure(includeThroughput: true, includeResponsiveness: false)
          .drain<void>();

      final String? failedNote =
          thrower.lastResult!.metric(MetricIds.responsiveness)!.note;
      final String? skippedNote =
          skipping.lastResult!.metric(MetricIds.responsiveness)!.note;

      expect(failedNote, isNotNull);
      expect(skippedNote, isNotNull);
      expect(skippedNote, isNot(failedNote),
          reason: 'a deliberate skip and a failure are DIFFERENT nulls');
    });

    test('Wi-Fi still runs the FULL RPM load, unchanged', () async {
      var loadRuns = 0;
      final OwnEngineQualityClient client = _client(
        maxDuration: const Duration(milliseconds: 120),
        loadDuration: const Duration(milliseconds: 60),
        onLoadRun: () => loadRuns++,
      );

      await client
          .measure(includeThroughput: true, includeResponsiveness: true)
          .drain<void>();

      expect(loadRuns, 1, reason: 'Wi-Fi behavior must be unchanged');

      final QualityMetric rpm =
          client.lastResult!.metric(MetricIds.responsiveness)!;
      expect(rpm.isAvailable, isTrue);
      expect(rpm.value, greaterThan(0));
    });
  });

  group('the progress bar must never freeze', () {
    test(
        'cellular (no RPM): the bar climbs to 1.0 through the throughput bands, '
        'with no dead 28% tail', () async {
      // If RPM does not run, the 0.72 -> 1.0 responsiveness band must not be
      // dead space or a sudden jump. The bands rebalance so the bar reflects the
      // work actually being done.
      final OwnEngineQualityClient client = _client(
        maxDuration: const Duration(milliseconds: 400),
        loadDuration: Duration.zero,
      );

      final List<QualityProgress> progress = await client
          .measure(includeThroughput: true, includeResponsiveness: false)
          .toList();

      // Monotonic and complete.
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i].fraction,
            greaterThanOrEqualTo(progress[i - 1].fraction));
      }
      expect(progress.last.fraction, 1.0);

      // No responsiveness phase is ever emitted — the stage did not run.
      expect(
        progress.any((QualityProgress p) =>
            p.phase == QualityPhase.responsiveness),
        isFalse,
        reason: 'no RPM stage on cellular means no RPM progress phase',
      );

      // THE ANTI-JUMP GUARD. Without rebalanced bands the upload stage would end
      // at 0.72 and the bar would leap 0.72 -> 1.0 in one frame. The upload band
      // must carry the bar deep into the old RPM territory instead.
      final List<QualityProgress> upload = progress
          .where((QualityProgress p) => p.phase == QualityPhase.upload)
          .toList();
      expect(upload, isNotEmpty);
      expect(upload.last.fraction, greaterThan(0.9),
          reason: 'upload must fill the bar on cellular, not stop at 0.72');
    });

    test(
        'Wi-Fi: the responsiveness band CLIMBS across the load window '
        '(it is not a single frozen emit)', () async {
      // The pre-existing test asserted the download and upload bands climb but
      // NEVER asserted the responsiveness band does — and its loadGenerator was
      // `() async {}`, so the RPM ticker was never exercised at all. This is that
      // missing guard.
      final OwnEngineQualityClient client = _client(
        maxDuration: const Duration(milliseconds: 600),
        loadDuration: const Duration(milliseconds: 500),
      );

      final List<QualityProgress> progress = await client
          .measure(includeThroughput: true, includeResponsiveness: true)
          .toList();

      final List<QualityProgress> rpmBand = progress
          .where((QualityProgress p) =>
              p.phase == QualityPhase.responsiveness && p.fraction < 1.0)
          .toList();

      final Set<double> distinct =
          rpmBand.map((QualityProgress p) => p.fraction).toSet();
      expect(distinct.length, greaterThanOrEqualTo(3),
          reason: 'the RPM band must climb in multiple steps, not sit at 0.72');
    });

    test(
        'THE FREEZE: a load that OUTRUNS its expected window must not pin the '
        'bar at a fixed number', () async {
      // THE REAL DEFECT, reproduced. The ticker interpolated elapsed/maxDuration.
      // A stage that ran LONGER than maxDuration clamped ratio to 1.0, so every
      // subsequent tick emitted the SAME fraction (the band ceiling) — a frozen
      // bar, for the entire overrun. On Keith's phone that overrun was ~21 s of a
      // ~36 s stage.
      //
      // The honest fix is NOT to invent a bigger denominator and keep guessing.
      // Once a stage outruns its known window, the remaining time is genuinely
      // UNKNOWN, and the bar must say so: indeterminate, never a number that
      // advances on a timer while nothing happens.
      final OwnEngineQualityClient client = _client(
        maxDuration: const Duration(milliseconds: 200),
        loadDuration: const Duration(milliseconds: 1200), // 6x the window
      );

      final List<QualityProgress> progress = await client
          .measure(includeThroughput: true, includeResponsiveness: true)
          .toList();

      final List<QualityProgress> rpmBand = progress
          .where((QualityProgress p) =>
              p.phase == QualityPhase.responsiveness && p.fraction < 1.0)
          .toList();
      expect(rpmBand, isNotEmpty);

      // Once the stage outran its window, the bar must have gone INDETERMINATE.
      // A determinate bar sitting on one number for a second is the hang the user
      // reads on screen.
      expect(
        rpmBand.any((QualityProgress p) => p.indeterminate),
        isTrue,
        reason: 'an overrunning stage must go indeterminate, not freeze',
      );

      // And it must never have been silent: no long run of identical DETERMINATE
      // fractions.
      final List<QualityProgress> determinate = rpmBand
          .where((QualityProgress p) => !p.indeterminate)
          .toList();
      final Set<double> distinct =
          determinate.map((QualityProgress p) => p.fraction).toSet();
      expect(distinct.length, greaterThanOrEqualTo(2),
          reason: 'the determinate portion must have climbed');
    });
  });

  group('runResilientRpmLoad is BUDGET-BOUNDED (the ~36 s cascade)', () {
    test(
        'a SLOW first endpoint does not cascade into a walk of the whole pool',
        () async {
      // KEITH'S 36 SECONDS. The old loop walked the endpoint list in order and
      // stopped at the first that WORKED. A throttling carrier made endpoint #0
      // burn its whole window and throw; the loop then handed endpoint #1 a FULL
      // FRESH window and burned it again. Two attempts ~= 36 s.
      //
      // Walking to the next endpoint is right when the first fails FAST (it costs
      // nothing and rescues RPM). It is wrong when the first was merely SLOW: the
      // budget is already spent and the walk buys nothing.
      final List<String> hit = <String>[];
      final ThroughputProbe probe = ThroughputProbe(
        maxDuration: const Duration(milliseconds: 300),
        downloadEndpoints: <Uri>[
          Uri.parse('https://slow.test/down'),
          Uri.parse('https://second.test/down'),
          Uri.parse('https://third.test/down'),
        ],
        downloader: (Uri uri, Duration max) async {
          hit.add(uri.host);
          if (uri.host == 'slow.test') {
            // Burns the ENTIRE budget, then fails — the throttled carrier.
            await Future<void>.delayed(const Duration(milliseconds: 300));
            throw const ThroughputUnmeasurable('throttled');
          }
          return 10 * 1000 * 1000;
        },
      );

      final Stopwatch sw = Stopwatch()..start();
      await expectLater(
        OwnEngineQualityClient.runResilientRpmLoad(probe),
        throwsA(isA<Object>()),
      );
      sw.stop();

      // It must NOT have walked on to burn a second full window.
      expect(hit, <String>['slow.test'],
          reason: 'a slow endpoint must not cascade into the next one');
      expect(sw.elapsed, lessThan(const Duration(milliseconds: 600)),
          reason: 'the whole load must stay inside ~one window, not two');
    });

    test('a FAST-FAILING first endpoint still falls back (resilience preserved)',
        () async {
      // The resilience commit (544cc3e) must not regress: an endpoint that dies
      // instantly costs no budget, so walking to the next one is free and RPM
      // still gets measured.
      final List<String> hit = <String>[];
      final ThroughputProbe probe = ThroughputProbe(
        maxDuration: const Duration(milliseconds: 300),
        downloadEndpoints: <Uri>[
          Uri.parse('https://speed.cloudflare.com/__down?bytes=1'),
          Uri.parse('https://proof.ovh.net/files/1Gb.dat'),
        ],
        downloader: (Uri uri, Duration max) async {
          hit.add(uri.host);
          if (uri.host == 'speed.cloudflare.com') {
            throw const ThroughputUnmeasurable('instant flake');
          }
          return 10 * 1000 * 1000;
        },
      );

      await OwnEngineQualityClient.runResilientRpmLoad(probe);

      expect(hit, <String>['speed.cloudflare.com', 'proof.ovh.net']);
    });
  });
}
