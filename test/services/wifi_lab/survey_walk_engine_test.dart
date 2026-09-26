// Survey Walk engine tests: every item in spec 26's "Done means" that the
// engine owns, plus determinism and the brief's worked numbers.
//
// Spec: myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 26-survey-walk.md. Numbers: wave 4 research brief §5.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/survey_walk_engine.dart';

ScanSchedule _sched(ScannerConfig s) => ScanSchedule.build(s);

double _meanRevisit(ScanSchedule s, bool Function(SurveyChannel c) where) {
  final List<double> r = <double>[
    for (int i = 0; i < s.channels.length; i++)
      if (where(s.channels[i])) s.revisit[i].meanS,
  ];
  return r.reduce((double a, double b) => a + b) / r.length;
}

void main() {
  group('channel sets', () {
    test('preset counts: 3, 28, 43, 95, 59', () {
      expect(channelsFor(ChannelSetPreset.g24), hasLength(3));
      expect(channelsFor(ChannelSetPreset.g24g5), hasLength(28));
      expect(channelsFor(ChannelSetPreset.g24g5psc), hasLength(43));
      expect(channelsFor(ChannelSetPreset.all), hasLength(95));
      expect(channelsFor(ChannelSetPreset.g6), hasLength(59));
      expect(
        channelsFor(ChannelSetPreset.custom, customCount: 12),
        hasLength(12),
      );
    });

    test('6 GHz PSCs are 5, 21, ..., 229', () {
      expect(k6PscChannels.first.number, 5);
      expect(k6PscChannels.last.number, 229);
      expect(k6AllChannels.last.number, 233);
    });
  });

  group('spacing and revisit', () {
    test('spacing = pace x revisit time', () {
      expect(sampleSpacingM(1.4, 7.0), closeTo(9.8, 1e-9));
      expect(sampleSpacingM(1.0, 3.108), closeTo(3.108, 1e-9));
      // And on a real walk: a channel's placed samples sit pace x revisit
      // apart (straight corridor, continuous, per-channel stamps).
      final SurveyWalkResult r = simulateSurveyWalk(SurveyWalkConfig());
      final int ch = r.indexOf(const SurveyChannel(RoamBand.b5, 36));
      final List<double> pos = <double>[
        for (final SurveySample s in r.samplesOf(ch)) s.placedS,
      ];
      expect(pos.length, greaterThan(3));
      for (int i = 1; i < pos.length; i++) {
        expect(pos[i] - pos[i - 1], closeTo(1.4 * 7.0, 1e-6));
      }
      expect(r.stats[ch].spacingM, closeTo(9.8, 1e-9));
    });

    test('the 28-channel, 250 ms, one-radio preset: 7.0 s and 9.8 m at '
        '1.4 m/s', () {
      final ScanSchedule s = _sched(ScannerConfig.nics(1));
      expect(s.channels, hasLength(28));
      for (final RevisitStats r in s.revisit) {
        expect(r.meanS, closeTo(7.0, 1e-9));
        expect(r.maxS, closeTo(7.0, 1e-9));
      }
      expect(sampleSpacingM(1.4, s.worstRevisitS), closeTo(9.8, 1e-9));
    });

    test('doubling radios on a shared sequential list roughly halves the '
        'revisit time', () {
      for (final int n in <int>[1, 2]) {
        final double one = _sched(ScannerConfig(radios: n)).worstRevisitS;
        final double two = _sched(ScannerConfig(radios: 2 * n)).worstRevisitS;
        expect(two / one, closeTo(0.5, 0.05), reason: '$n to ${2 * n}');
      }
      // ceil(28 / 3) = 10 slots.
      expect(
        _sched(const ScannerConfig(radios: 3)).worstRevisitS,
        closeTo(2.5, 1e-9),
      );
    });

    test('band per radio gives each band its own revisit time', () {
      final ScanSchedule s = _sched(
        const ScannerConfig(
          channelSet: ChannelSetPreset.g24g5psc,
          radios: 3,
          algorithm: HoppingAlgorithm.bandPerRadio,
        ),
      );
      final Map<RoamBand, double> b = s.bandRevisitS;
      expect(b[RoamBand.b24], closeTo(3 * 0.25, 1e-9));
      expect(b[RoamBand.b5], closeTo(25 * 0.25, 1e-9));
      expect(b[RoamBand.b6], closeTo(15 * 0.25, 1e-9));
      expect(b.values.toSet(), hasLength(3));
      // A fourth radio joins the slowest band (5 GHz) and halves it.
      final ScanSchedule s4 = _sched(
        const ScannerConfig(
          channelSet: ChannelSetPreset.g24g5psc,
          radios: 4,
          algorithm: HoppingAlgorithm.bandPerRadio,
        ),
      );
      expect(s4.bandRevisitS[RoamBand.b5], closeTo(13 * 0.25, 1e-9));
    });

    test('priority channels get shorter spacing than the rest on the same '
        'walk', () {
      final SurveyWalkResult r = simulateSurveyWalk(
        SurveyWalkConfig(
          scanner: const ScannerConfig(algorithm: HoppingAlgorithm.priority),
        ),
      );
      final ScanSchedule s = r.schedule!;
      final double pri = _meanRevisit(s, kDefaultPriorityChannels.contains);
      final double rest = _meanRevisit(
        s,
        (SurveyChannel c) => !kDefaultPriorityChannels.contains(c),
      );
      // k = 3, 5 priority channels: every 15 slots = 3.75 s. The other 23
      // share 2 of every 3 slots: 34.5 slots = 8.6 s.
      expect(pri, closeTo(3.75, 0.01));
      expect(rest, closeTo(8.625, 0.1));
      double spacing(bool priority) {
        final List<double> v = <double>[
          for (final ChannelStats st in r.stats)
            if (kDefaultPriorityChannels.contains(st.channel) == priority)
              st.spacingM,
        ];
        return v.reduce((double a, double b) => a + b) / v.length;
      }

      expect(spacing(true), lessThan(spacing(false)));
      // And the real samples agree: channel 36 gets more samples than 40.
      final int c36 = r.indexOf(const SurveyChannel(RoamBand.b5, 36));
      final int c40 = r.indexOf(const SurveyChannel(RoamBand.b5, 40));
      expect(r.stats[c36].samples, greaterThan(r.stats[c40].samples));
    });
  });

  group('Rule 4: longest allowed revisit = guess range / pace', () {
    test('5 m at 1.4 m/s is 3.6 s', () {
      expect(maxAllowedRevisitS(5, 1.4), closeTo(3.57, 0.01));
    });

    test('the four device presets: 7.0, 3.5, 2.5 and 1.75 s; at 5 m and '
        '1.4 m/s 1 NIC fails and 2, 3 and 4 NICs pass', () {
      SurveyWalkResult run(int n) =>
          simulateSurveyWalk(SurveyWalkConfig(scanner: ScannerConfig.nics(n)));
      const List<double> revisit = <double>[7.0, 3.5, 2.5, 1.75];
      for (int n = 1; n <= 4; n++) {
        final SurveyWalkResult r = run(n);
        expect(r.ruleRevisitS, closeTo(revisit[n - 1], 1e-9), reason: '$n');
        expect(r.rule4Pass, n > 1, reason: '$n NICs');
      }
      // 2 NICs only just passes: 3.5 s against 5 / 1.4 = 3.57 s.
      expect(run(2).maxAllowedRevisit - 3.5, lessThan(0.1));
      // A preset keeps the channel set and dwell the student chose.
      const ScannerConfig mine = ScannerConfig(
        channelSet: ChannelSetPreset.g24,
        dwellMs: 100,
      );
      final ScannerConfig three = ScannerConfig.nics(3, base: mine);
      expect(three.channelSet, ChannelSetPreset.g24);
      expect(three.dwellMs, 100);
      expect(three.radios, 3);
      expect(nicPresetLabel(1), "1 NIC (a laptop's built-in radio)");
      expect(nicPresetLabel(4), '4 NICs');
    });
  });

  group('survey types', () {
    test('hybrid is not available with one radio, and says why', () {
      final ({bool available, String? reason}) h = hybridAvailability(
        const ScannerConfig(),
      );
      expect(h.available, isFalse);
      expect(h.reason, contains('one radio for the active connection'));
      expect(
        hybridAvailability(const ScannerConfig(radios: 2)).available,
        isTrue,
      );
      // Asking for it anyway runs a passive survey.
      final SurveyWalkConfig c = SurveyWalkConfig(
        surveyType: SurveyType.hybrid,
      );
      expect(c.effectiveType, SurveyType.passive);
    });

    test('hybrid takes one radio for the active connection', () {
      final SurveyWalkResult r = simulateSurveyWalk(
        SurveyWalkConfig(
          surveyType: SurveyType.hybrid,
          scanner: const ScannerConfig(radios: 3),
        ),
      );
      expect(r.schedule!.radios, 2);
      expect(r.samples.any((SurveySample s) => s.active), isTrue);
      expect(r.samples.any((SurveySample s) => !s.active), isTrue);
    });

    test('passive hears the neighbor; active does not', () {
      bool hearsNeighbor(SurveyType t) =>
          simulateSurveyWalk(SurveyWalkConfig(surveyType: t)).samples.any(
            (SurveySample s) =>
                s.heard.any((HeardAp h) => kSurveyAps[h.ap].neighbor),
          );
      expect(hearsNeighbor(SurveyType.passive), isTrue);
      expect(hearsNeighbor(SurveyType.active), isFalse);
    });
  });

  group('capture method and position error', () {
    test('a 3 s pause in continuous mode moves samples; stop and go does '
        'not', () {
      SurveyWalkResult run(CaptureMethod m, {required bool pause}) =>
          simulateSurveyWalk(
            SurveyWalkConfig(capture: m, doorPause: pause, doorPauseS: 3),
          );
      expect(
        run(CaptureMethod.continuous, pause: false).maxErrorM,
        lessThan(1e-6),
      );
      final double moved = run(CaptureMethod.continuous, pause: true).maxErrorM;
      // Corridor 58 m at 1.4 m/s, pause at 29 m: the app assumes
      // 58 / 44.4 s = 1.31 m/s, so a sample at the door is placed
      // 29 - 20.7 x 1.31 = 2.0 m short.
      expect(moved, greaterThan(1.5));
      expect(moved, lessThan(2.1));
      expect(run(CaptureMethod.stopAndGo, pause: true).maxErrorM, 0);
      expect(run(CaptureMethod.stopAndGo, pause: false).maxErrorM, 0);
    });

    test("the brief's worked case: 20 m at 1.4 m/s, 3 s pause mid-way, "
        'about 1.7 m', () {
      final SurveyWalkResult r = simulateSurveyWalk(
        SurveyWalkConfig(
          path: const <FloorPoint>[(x: 10, y: 10), (x: 30, y: 10)],
          doorPause: true,
          doorPauseS: 3,
          scanner: const ScannerConfig(dwellMs: 50),
        ),
      );
      expect(r.maxErrorM, closeTo(1.73, 0.05));
    });

    test(
      'per-cycle stamping gives a larger position error than per-channel',
      () {
        double err(TimestampMode m) =>
            simulateSurveyWalk(SurveyWalkConfig(timestamp: m)).maxErrorM;
        expect(err(TimestampMode.perChannel), lessThan(1e-6));
        // Up to one revisit distance (9.8 m) for the first channel of a cycle.
        expect(err(TimestampMode.perCycle), greaterThan(9));
        expect(err(TimestampMode.perCycle), lessThanOrEqualTo(9.8 + 1e-6));
      },
    );

    test('stop and go stacks samples at points, two full cycles each', () {
      final SurveyWalkResult r = simulateSurveyWalk(
        SurveyWalkConfig(capture: CaptureMethod.stopAndGo),
      );
      expect(r.stopDurationS, closeTo(14.0, 1e-9));
      final int ch = r.indexOf(const SurveyChannel(RoamBand.b5, 36));
      final List<SurveySample> s = r.samplesOf(ch).toList();
      // Stops at 0, 5, ..., 55 and 58 m: 13 stops, 2 samples each.
      expect(s, hasLength(26));
      expect(s[0].placedS, s[1].placedS);
      // Standing still repeats one fade; walking does not.
      expect(s[0].heard.single.fadeDb, s[1].heard.single.fadeDb);
      final List<SurveySample> moving = simulateSurveyWalk(
        SurveyWalkConfig(),
      ).samplesOf(ch).toList();
      expect(
        moving[0].heard.single.fadeDb,
        isNot(moving[1].heard.single.fadeDb),
      );
    });

    test('line mode does not record between segments', () {
      final SurveyWalkResult r = simulateSurveyWalk(
        SurveyWalkConfig(capture: CaptureMethod.line, path: kSurveyLoopPath),
      );
      for (final SurveySample s in r.samples) {
        expect(r.plan.phaseAt(s.measuredAtS).recording, isTrue);
      }
      expect(r.plan.clicks, hasLength(2 * (kSurveyLoopPath.length - 1)));
    });
  });

  group('no data (white) gaps', () {
    test('gaps wider than the guess range are uncovered', () {
      final List<(double, double)> gaps = noDataIntervals(
        <double>[0, 9.8, 19.6],
        5,
        20,
      );
      expect(gaps, hasLength(2));
      expect(gaps[0].$1, closeTo(2.5, 1e-9));
      expect(gaps[0].$2, closeTo(7.3, 1e-9));
      expect(gaps[1].$1, closeTo(12.3, 1e-9));
      expect(gaps[1].$2, closeTo(17.1, 1e-9));
      expect(noDataIntervals(<double>[0, 4, 8, 12, 16, 20], 5, 20), isEmpty);
    });

    test('1 NIC at 5 m leaves white gaps; 4 NICs do not', () {
      int gaps(int n) {
        final SurveyWalkResult r = simulateSurveyWalk(
          SurveyWalkConfig(scanner: ScannerConfig.nics(n)),
        );
        final int ch = r.indexOf(const SurveyChannel(RoamBand.b5, 36));
        return r.stats[ch].noData
            .where(((double, double) g) => g.$1 > 0 && g.$2 < 58)
            .length;
      }

      expect(gaps(1), greaterThan(0));
      expect(gaps(4), 0);
    });
  });

  test('deterministic with a seed', () {
    final SurveyWalkResult a = simulateSurveyWalk(SurveyWalkConfig(seed: 7));
    final SurveyWalkResult b = simulateSurveyWalk(SurveyWalkConfig(seed: 7));
    expect(a.samples.length, b.samples.length);
    for (int i = 0; i < a.samples.length; i++) {
      expect(a.samples[i].placedS, b.samples[i].placedS);
      for (int k = 0; k < a.samples[i].heard.length; k++) {
        expect(a.samples[i].heard[k].rssiDbm, b.samples[i].heard[k].rssiDbm);
      }
    }
    final SurveyWalkResult c = simulateSurveyWalk(SurveyWalkConfig(seed: 8));
    final int i = a.samples.indexWhere((SurveySample s) => s.heard.isNotEmpty);
    expect(
      a.samples[i].heard.first.fadeDb,
      isNot(c.samples[i].heard.first.fadeDb),
    );
  });

  test('walking physics for the reveal: 14 to 37 ms coherence, 5.484 ms '
      'frame', () {
    expect(coherenceTimeMs(RoamBand.b24, 1.4), closeTo(37, 0.5));
    expect(coherenceTimeMs(RoamBand.b6, 1.4), closeTo(13.9, 0.2));
    expect(kLongestPpduMs, lessThan(coherenceTimeMs(RoamBand.b6, 1.4)));
  });
}
