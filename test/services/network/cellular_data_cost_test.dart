// THE RE-DERIVATION GUARD.
//
// The cellular cost sentence went stale once already: it said "about 30 seconds"
// because that was two 15 s download windows, and it kept saying it after the RPM
// stage stopped running on cellular. A number copied into a string is a number
// that drifts silently.
//
// So these tests recompute the figures from the LIVE `ThroughputProbe` defaults.
// Move `maxDuration` or `uploadBytes` and this fails — loudly, before ship —
// instead of the app quietly lying to a user about what a tap will cost them.

import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_data_cost.dart';

void main() {
  group('the cellular cost sentence is DERIVED from the probe constants', () {
    test('MB-per-Mbps matches the live download window', () {
      final ThroughputProbe probe = ThroughputProbe();
      // bytes = rate x window / 8  ->  MB per Mbps = window_seconds / 8
      final double derived = probe.maxDuration.inSeconds / 8;
      expect(
        kMegabytesPerMbps,
        closeTo(derived, 0.0001),
        reason: 'ThroughputProbe.maxDuration changed — the sentence is stale',
      );
    });

    test('the upload figure matches the live uploadBytes cap', () {
      final ThroughputProbe probe = ThroughputProbe();
      final double derived = probe.uploadBytes / 1000000;
      expect(
        kUploadMegabytes,
        closeTo(derived, 0.0001),
        reason: 'ThroughputProbe.uploadBytes changed — the sentence is stale',
      );
    });

    test(
      'every figure QUOTED in the warning re-derives from the constants',
      () {
        final ThroughputProbe probe = ThroughputProbe();
        final double perMbps = probe.maxDuration.inSeconds / 8;
        final double upload = probe.uploadBytes / 1000000;

        double totalAt(double mbps) => perMbps * mbps + upload;

        // The three anchors the copy states, to two significant figures.
        expect(totalAt(10).round(), 29); // stated as "about 30 MB"
        expect(totalAt(100).round(), 198); // stated as "200 MB"
        expect(totalAt(300).round(), 573); // stated as "570 MB"

        // And the sentence really does say them.
        expect(kCellularDataWarning, contains('15 seconds'));
        expect(kCellularDataWarning, contains('10 MB'));
        expect(kCellularDataWarning, contains('30 MB at 10 Mbps'));
        expect(kCellularDataWarning, contains('200 MB at 100 Mbps'));
        expect(kCellularDataWarning, contains('570 MB at 300 Mbps'));
      },
    );

    test('the warning carries NO hedge words (it is a consent dialog)', () {
      // "roughly X or more" is what you write when you have no source. Every
      // figure here has one, so none of these should be needed.
      final String lower = kCellularDataWarning.toLowerCase();
      for (final String hedge in <String>[
        'roughly',
        'or more',
        'approximately',
        'up to',
        'may use',
        'could use',
      ]) {
        expect(
          lower,
          isNot(contains(hedge)),
          reason: 'a hedged quantity on a consent dialog has no source',
        );
      }
    });

    test(
      'the STALE claim is gone: the app no longer downloads for 30 seconds',
      () {
        // The RPM load generator does not run on cellular, so the old "about 30
        // seconds" (two 15 s download windows) is no longer true of this app.
        expect(kCellularDataWarning, isNot(contains('30 seconds')));
        final ThroughputProbe probe = ThroughputProbe();
        expect(
          probe.maxDuration,
          const Duration(seconds: 15),
          reason: 'the copy says 15 seconds; the probe must agree',
        );
      },
    );
  });
}
