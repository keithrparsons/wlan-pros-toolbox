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
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';

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

        // THE THREE ANCHORS THE COPY STATES — AND IT NOW STATES THESE EXACT NUMBERS.
        //
        // These three assertions were ALREADY HERE, already computing 29 / 198 / 573,
        // while the trailing comments read `// stated as "about 30 MB"`. The test
        // knew the true values and cheerfully documented the copy stating different
        // ones. The rounding to "30 / 200 / 570" is the only reason the sentence
        // needed the word "about" — so stating the derived figures makes the copy
        // MORE PRECISE AND MORE HONEST AT THE SAME TIME, and the hedge evaporates.
        expect(totalAt(10).round(), 29);
        expect(totalAt(100).round(), 198);
        expect(totalAt(300).round(), 573);

        // And the sentence really does say them.
        expect(kCellularDataWarning, contains('15 seconds'));
        expect(kCellularDataWarning, contains('10 MB'));
        expect(kCellularDataWarning, contains('29 MB at 10 Mbps'));
        expect(kCellularDataWarning, contains('198 MB at 100 Mbps'));
        expect(kCellularDataWarning, contains('573 MB at 300 Mbps'));

        // AND SO DOES THE UNKNOWN-LINK SENTENCE. Two warnings now exist, and the
        // second one is the one a user on an AMBIGUOUS link sees — so it must carry
        // the same derived figures. A guard that checked only the cellular string
        // would let the new one drift, which is exactly the class of hole this file
        // was written to close.
        expect(kUnknownLinkDataWarning, contains('15 seconds'));
        expect(kUnknownLinkDataWarning, contains('10 MB'));
        expect(kUnknownLinkDataWarning, contains('29 MB at 10 Mbps'));
        expect(kUnknownLinkDataWarning, contains('198 MB at 100 Mbps'));
        expect(kUnknownLinkDataWarning, contains('573 MB at 300 Mbps'));
      },
    );

    test('EVERY stated figure is an UPPER bound on the true cost', () {
      // The file header claims the method "keeps every figure below an UPPER bound".
      // It did not. 570 UNDERSTATED 572.5 — only 0.4%, and in the one direction that
      // matters: it spent more of the user's money than the sentence promised, on the
      // screen whose entire job is to say what a tap will cost. Round UP, always.
      final ThroughputProbe probe = ThroughputProbe();
      final double perMbps = probe.maxDuration.inSeconds / 8;
      final double upload = probe.uploadBytes / 1000000;
      double totalAt(double mbps) => perMbps * mbps + upload;

      final Map<double, int> stated = <double, int>{
        10: 29,
        100: 198,
        300: 573,
      };
      stated.forEach((double mbps, int claim) {
        expect(
          claim,
          greaterThanOrEqualTo(totalAt(mbps)),
          reason:
              'the copy claims $claim MB at $mbps Mbps but the run really costs '
              '${totalAt(mbps)} MB — a consent dialog may never understate the '
              'spend it is asking permission for',
        );
      });
    });

    test('the warning carries NO hedge words (it is a consent dialog)', () {
      // "roughly X or more" is what you write when you have no source. Every
      // figure here has one, so none of these should be needed.
      //
      // ─────────────────────────────────────────────────────────────────────────
      // THIS TEST WAS GREEN WHILE THE STRING IT GUARDS SAID "about 30 MB".
      //
      // Its hedge list enumerated SIX words the string did not contain and OMITTED
      // THE ONE IT DID. A test named after banning the hedge was DEFENDING it, and
      // `voice-lint.py` — whose `hedged quantity` rule is literally `\b(about|...)\s+
      // [\d,]` — failed the same string this test passed. The sixth enshrined test in
      // a week ([[feedback_tests_that_enshrine_the_bug]]).
      //
      // So: `about` is now first in the list, and the list is checked against
      // BOTH warnings. Read the test NAMES before you trust them — and then read
      // what the test actually asserts, because the name was right and the body
      // was not.
      // ─────────────────────────────────────────────────────────────────────────
      const List<String> hedges = <String>[
        'about', // <- THE ONE THAT WAS MISSING, AND THE ONE THAT WAS THERE
        'roughly',
        'or more',
        'approximately',
        'up to',
        'may use',
        'could use',
        'around',
        'nearly',
        'almost',
        'some ',
      ];
      for (final String warning in <String>[
        kCellularDataWarning,
        kUnknownLinkDataWarning,
      ]) {
        final String lower = warning.toLowerCase();
        for (final String hedge in hedges) {
          expect(
            lower,
            isNot(contains(hedge)),
            reason:
                'a hedged quantity on a consent dialog has no source — found '
                '"$hedge" in: $warning',
          );
        }
      }
    });

    test(
      'the UNKNOWN-LINK warning never CLAIMS the user is on cellular',
      () {
        // THE PROMPT MUST NOT LIE ABOUT CERTAINTY, IN EITHER DIRECTION.
        //
        // The round-5 fix makes the gate fire on an AMBIGUOUS link. If that prompt
        // opened with "You're on cellular", we would have closed a silent-spend bug
        // by shipping a fabricated fact — asserting a link we cannot read, to a user
        // we are about to charge for it. That is the same disease from the other
        // side, and it would be a much easier one to miss.
        expect(
          kUnknownLinkDataWarning,
          isNot(contains("You're on cellular")),
          reason: 'we do not know that, and we must not say it',
        );
        expect(
          kUnknownLinkDataWarning.toLowerCase(),
          contains("can't tell"),
          reason: 'say the true thing: we cannot tell what link this is',
        );
        // ...and the CONFIRMED string still does assert it, because there it is a
        // MEASUREMENT and the user deserves to be told plainly.
        expect(kCellularDataWarning, contains("You're on cellular."));
      },
    );

    test('the right sentence is chosen for each risk', () {
      // The SSOT selector. Neither screen may branch on the risk itself — that is
      // how one of them would eventually pick the wrong sentence.
      expect(dataCostWarningFor(MeteredRisk.metered), kCellularDataWarning);
      expect(dataCostWarningFor(MeteredRisk.unknown), kUnknownLinkDataWarning);
      expect(
        dataCostWarningFor(MeteredRisk.none),
        isNull,
        reason: 'a Wi-Fi user must not be warned about a spend that is not '
            'happening — noise trains people to ignore the warning that matters',
      );
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
