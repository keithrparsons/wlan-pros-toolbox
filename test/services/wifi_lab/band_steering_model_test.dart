// Unit tests for the Wi-Fi Classroom Band Steering engine
// (lib/services/wifi_lab/band_steering_model.dart), one group per line of
// spec 38's "Done means", plus the walk behaviors the screen relies on.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/band_steering_model.dart';

BsWalk _walk({
  ClientProfile profile = ClientProfile.a,
  SteeringMode mode = SteeringMode.off,
  WalkPath path = WalkPath.edgeToAp,
  bool random = false,
  double extra = kBsDefaultExtraLossDb,
  int tolerance = kBsDefaultTolerance,
  bool driver = true,
  int rescan = kBsDefaultRescanS,
  int retry = kBsDefaultRetryS,
}) => simulateWalk(
  BsConfig(
    profile: profile,
    mode: mode,
    path: path,
    randomScanAddress: random,
    extra5LossDb: extra,
    refusalTolerance: tolerance,
    driverSupportsBtm: driver,
    rescanS: rescan,
    retryS: retry,
  ),
);

/// The sample right after each deauthentication's outage: where the client
/// chose its band again.
List<BsStep> _rejoins(BsWalk w) => <BsStep>[
  for (int i = 1; i < w.steps.length; i++)
    if (w.steps[i - 1].inOutage && !w.steps[i].inOutage) w.steps[i],
];

void main() {
  group('signal', () {
    test('at equal distance, 5 GHz is 7.1 dB (+-0.1) weaker in free space '
        '(5.5 vs 2.437 GHz)', () {
      for (final double d in <double>[1, 2, 7.5, 20, 55]) {
        final double gap =
            bsRssiDbm(BsBand.ghz24, d) - bsRssiDbm(BsBand.ghz5, d);
        expect(gap, closeTo(7.1, 0.1), reason: '$d m');
      }
      expect(bsFreeSpaceGapDb, closeTo(7.07, 0.01));
    });

    test(
      'the extra 5 GHz wall loss adds to the gap and touches 5 GHz only',
      () {
        expect(
          bsRssiDbm(BsBand.ghz5, 20) -
              bsRssiDbm(BsBand.ghz5, 20, extra5LossDb: 3),
          closeTo(3, 1e-9),
        );
        expect(
          bsRssiDbm(BsBand.ghz24, 20, extra5LossDb: 3),
          bsRssiDbm(BsBand.ghz24, 20),
        );
      },
    );

    test('the 2.4 GHz ring is larger than the 5 GHz ring', () {
      final BsWalk w = _walk();
      expect(w.ringM(BsBand.ghz24), greaterThan(w.ringM(BsBand.ghz5)));
      expect(
        bsRssiDbm(BsBand.ghz24, w.ringM(BsBand.ghz24)),
        closeTo(kBsHearFloorDbm, 1e-9),
      );
    });
  });

  group('the AP can hide, refuse or suggest; beacons never stop', () {
    test('under probe suppression the client still receives 2.4 GHz '
        'beacons', () {
      for (final SteeringMode m in SteeringMode.values) {
        expect(apSendsBeacon(m, BsBand.ghz24), isTrue, reason: m.name);
        expect(apSendsBeacon(m, BsBand.ghz5), isTrue, reason: m.name);
      }
      // And the walk: every sample on 2.4 GHz range still ends with the client
      // knowing 2.4 GHz, so it can join it even with its probe unanswered.
      final BsWalk w = _walk(
        profile: ClientProfile.c,
        mode: SteeringMode.probeSuppression,
        path: WalkPath.apToEdge,
      );
      final BsStep first = w.steps.first;
      expect(
        first.frames.any(
          (BsFrame f) =>
              f.kind == BsFrameKind.probeBroadcast &&
              f.band == BsBand.ghz24 &&
              f.outcome == BsOutcome.ignored,
        ),
        isTrue,
      );
      expect(first.band, BsBand.ghz24);
    });

    test('directed probes are answered under probe suppression', () {
      expect(
        apAnswersProbe(
          mode: SteeringMode.probeSuppression,
          band: BsBand.ghz24,
          directed: true,
          trackedOn5: true,
        ),
        isTrue,
      );
      expect(
        apAnswersProbe(
          mode: SteeringMode.probeSuppression,
          band: BsBand.ghz24,
          directed: false,
          trackedOn5: true,
        ),
        isFalse,
      );
      // Untracked clients and 5 GHz probes are always answered.
      expect(
        apAnswersProbe(
          mode: SteeringMode.probeSuppression,
          band: BsBand.ghz24,
          directed: false,
          trackedOn5: false,
        ),
        isTrue,
      );
      expect(
        apAnswersProbe(
          mode: SteeringMode.probeSuppression,
          band: BsBand.ghz5,
          directed: false,
          trackedOn5: true,
        ),
        isTrue,
      );
    });
  });

  group('clients are sticky by their own published rules', () {
    test('Client B on 2.4 GHz at -65 dBm does not re-run selection', () {
      expect(looksForAnother(ClientProfile.b, BsBand.ghz24, -65), isFalse);
      expect(looksForAnother(ClientProfile.b, BsBand.ghz24, -73), isTrue);
      expect(looksForAnother(ClientProfile.b, BsBand.ghz5, -69), isFalse);
      expect(looksForAnother(ClientProfile.b, BsBand.ghz5, -71), isTrue);
    });

    test('Client A on 2.4 GHz at -65 dBm does not scan', () {
      expect(looksForAnother(ClientProfile.a, BsBand.ghz24, -65), isFalse);
      expect(looksForAnother(ClientProfile.a, BsBand.ghz24, -71), isTrue);
    });

    test('Client B discards a 5 GHz network at -78 dBm (below -77) while '
        'accepting 2.4 GHz at -71', () {
      expect(passesEntry(ClientProfile.b, BsBand.ghz5, -78), isFalse);
      expect(passesEntry(ClientProfile.b, BsBand.ghz24, -71), isTrue);
      expect(joinPreference(ClientProfile.b, rssi24: -71, rssi5: -78), <BsBand>[
        BsBand.ghz24,
      ]);
      // At -77 it passes, and the wider channel's estimate wins.
      expect(
        joinPreference(ClientProfile.b, rssi24: -71, rssi5: -77).first,
        BsBand.ghz5,
      );
    });

    test('walking from edge to AP with steering off leaves Client A and '
        'Client B on 2.4 GHz', () {
      for (final ClientProfile p in <ClientProfile>[
        ClientProfile.a,
        ClientProfile.b,
      ]) {
        for (final double extra in <double>[0, 3, 10]) {
          final BsWalk w = _walk(profile: p, extra: extra);
          expect(w.steps.first.band, BsBand.ghz24, reason: '${p.name} $extra');
          expect(
            w.steps.every((BsStep s) => s.band == BsBand.ghz24),
            isTrue,
            reason: '${p.name} $extra',
          );
          expect(w.last.distanceM, kBsNearM);
        }
      }
    });

    test('the why sentence for a sticky Client B names the -73 dBm rule', () {
      final BsWalk w = _walk(profile: ClientProfile.b);
      expect(
        w.last.why,
        contains(
          'above -73 dBm, so this client does not look for another '
          'network',
        ),
      );
    });
  });

  group('authentication refusal', () {
    test('with the random-address toggle on, authentication refusal never '
        'fires', () {
      for (final ClientProfile p in ClientProfile.values) {
        for (final WalkPath path in WalkPath.values) {
          final BsWalk w = _walk(
            profile: p,
            mode: SteeringMode.authRefusal,
            path: path,
            random: true,
          );
          expect(w.last.refusalsTotal, 0, reason: '${p.name} ${path.name}');
          expect(
            w.steps
                .expand((BsStep s) => s.frames)
                .any((BsFrame f) => f.outcome == BsOutcome.refused),
            isFalse,
          );
          expect(w.steps.any((BsStep s) => s.trackedOn5), isFalse);
        }
      }
    });

    test('after the refusal tolerance is reached the client associates on '
        '2.4 GHz', () {
      for (final int tol in <int>[1, 3, 10]) {
        // Client A on 5 GHz walks out; below -70 dBm it tries 2.4 GHz, which
        // the AP refuses until the tolerance is reached.
        final BsWalk w = _walk(
          path: WalkPath.apToEdge,
          mode: SteeringMode.authRefusal,
          tolerance: tol,
        );
        expect(w.steps.first.band, BsBand.ghz5);
        final int firstRefusal = w.steps.indexWhere(
          (BsStep s) => s.refusalsTotal > 0,
        );
        expect(firstRefusal, greaterThan(0));
        final int on24 = w.steps.indexWhere(
          (BsStep s) => s.band == BsBand.ghz24,
        );
        expect(on24, firstRefusal + tol, reason: 'tolerance $tol');
        expect(w.steps[on24 - 1].refusalsInRow, tol);
        expect(w.steps[on24].refusalsTotal, tol);
        expect(w.steps[on24].why, contains('let the client in'));
      }
    });

    test('a refused client that can use 5 GHz joins 5 GHz instead', () {
      final BsWalk w = _walk(
        profile: ClientProfile.c,
        mode: SteeringMode.authRefusal,
        path: WalkPath.apToEdge,
      );
      expect(w.steps.first.band, BsBand.ghz5);
      expect(w.steps.first.refusalsTotal, 1);
    });

    test('an AP that never heard the client on 5 GHz does not refuse', () {
      final BsWalk w = _walk(
        profile: ClientProfile.b,
        mode: SteeringMode.authRefusal,
      );
      expect(w.steps.first.trackedOn5, isFalse);
      expect(w.steps.first.band, BsBand.ghz24);
      expect(w.steps.first.refusalsTotal, 0);
    });
  });

  group('transition request (802.11v)', () {
    test('declined with "no suitable candidates" when 5 GHz is below the '
        "client's entry threshold", () {
      final BtmAnswer a = answerTransitionRequest(ClientProfile.b, -78);
      expect(a.answered, isTrue);
      expect(a.status, kBtmStatusNoSuitableCandidates);
      expect(a.label, contains('no suitable candidates'));
      expect(answerTransitionRequest(ClientProfile.b, -77).accepted, isTrue);

      final BsWalk w = _walk(
        profile: ClientProfile.b,
        mode: SteeringMode.transitionRequest,
      );
      expect(w.steps.first.band, BsBand.ghz24);
      expect(w.steps.first.btm!.status, kBtmStatusNoSuitableCandidates);
      expect(w.steps.first.why, contains('no suitable candidates'));
    });

    test('the strongest tool: an accepted request moves Client B to 5 GHz '
        'once 5 GHz passes -77 dBm', () {
      final BsWalk w = _walk(
        profile: ClientProfile.b,
        mode: SteeringMode.transitionRequest,
      );
      expect(w.last.band, BsBand.ghz5);
      final BsStep moved = w.steps.firstWhere(
        (BsStep s) => s.band == BsBand.ghz5,
      );
      expect(moved.rssi5, greaterThanOrEqualTo(-77));
      expect(moved.btm!.accepted, isTrue);
    });

    test('a driver without support does not answer', () {
      final BtmAnswer a = answerTransitionRequest(
        ClientProfile.c,
        -60,
        driverSupportsBtm: false,
      );
      expect(a.answered, isFalse);
      final BsWalk w = _walk(
        profile: ClientProfile.c,
        mode: SteeringMode.transitionRequest,
        driver: false,
      );
      expect(w.steps.every((BsStep s) => s.band != BsBand.ghz5), isTrue);
    });
  });

  group('deauthentication (Keith, 2026-09-27: the 4th method)', () {
    test('a client whose 5 GHz level is below its entry threshold returns '
        'to 2.4 GHz, and the loop counter increments', () {
      // Client B, published 5 GHz entry -77 dBm. Walking out from the AP it
      // reaches 2.4 GHz, is matched on 5 GHz, and is deauthenticated.
      final BsWalk w = _walk(
        profile: ClientProfile.b,
        mode: SteeringMode.deauthentication,
        path: WalkPath.apToEdge,
      );
      final List<BsStep> back = _rejoins(w);
      expect(back, isNotEmpty);
      final BsStep first = back.first;
      expect(first.rssi5, lessThan(clientBEntryDbm(BsBand.ghz5)));
      expect(first.band, BsBand.ghz24);
      expect(first.returnsTo24, 1);
      expect(first.why, contains('entry threshold'));
      expect(first.why, contains('the AP will deauthenticate it again'));
      // The AP deauthenticates it again: the loop, counted.
      expect(w.last.deauthsTotal, greaterThan(1));
      expect(w.last.returnsTo24, back.length);
      int prev = 0;
      for (final BsStep s in back) {
        expect(s.returnsTo24, prev + 1);
        prev = s.returnsTo24;
      }

      // Client A the same way, against its -70 dBm model-choice level.
      final BsWalk a = _walk(mode: SteeringMode.deauthentication);
      final BsStep aBack = _rejoins(a).first;
      expect(aBack.rssi5, lessThan(kClientALookDbm));
      expect(aBack.band, BsBand.ghz24);
      expect(aBack.returnsTo24, 1);
    });

    test('a client that hears 5 GHz above its threshold ends on 5 GHz after '
        'one deauthentication', () {
      final BsWalk w = _walk(
        profile: ClientProfile.b,
        mode: SteeringMode.deauthentication,
        extra: 0,
        retry: 25,
      );
      expect(w.last.deauthsTotal, 1);
      expect(w.last.returnsTo24, 0);
      expect(w.last.band, BsBand.ghz5);
      final BsStep rejoin = _rejoins(w).single;
      expect(rejoin.rssi5, greaterThanOrEqualTo(clientBEntryDbm(BsBand.ghz5)));
      expect(rejoin.band, BsBand.ghz5);
      expect(rejoin.why, contains('Steered, after 1 deauthentication'));
      // Once on 5 GHz it is never deauthenticated again.
      final int at = w.steps.indexOf(rejoin);
      for (final BsStep s in w.steps.skip(at)) {
        expect(s.band, BsBand.ghz5);
        expect(
          s.frames.any((BsFrame f) => f.kind == BsFrameKind.deauthentication),
          isFalse,
        );
      }
    });

    test('at every rejoin the client takes 5 GHz exactly when its own join '
        'rule prefers 5 GHz there', () {
      for (final ClientProfile p in ClientProfile.values) {
        for (final WalkPath path in WalkPath.values) {
          final BsWalk w = _walk(
            profile: p,
            mode: SteeringMode.deauthentication,
            path: path,
          );
          for (final BsStep s in _rejoins(w)) {
            final List<BsBand> pref = joinPreference(
              p,
              rssi24: s.rssi24,
              rssi5: s.rssi5,
            );
            expect(
              s.band,
              pref.isEmpty ? isNull : pref.first,
              reason: '${p.label} ${path.label} at ${s.distanceM} m',
            );
          }
        }
      }
    });

    test('client traffic is zero during the outage, which lasts the rescan '
        'time', () {
      for (final int rescan in <int>[1, 3, 7]) {
        final BsWalk w = _walk(
          profile: ClientProfile.c,
          mode: SteeringMode.deauthentication,
          path: WalkPath.apToEdge,
          rescan: rescan,
        );
        final List<BsStep> out = w.steps
            .where((BsStep s) => s.inOutage)
            .toList();
        expect(out, isNotEmpty);
        for (final BsStep s in out) {
          expect(s.trafficFlowing, isFalse);
          expect(s.band, isNull);
          expect(s.outageSecond, inInclusiveRange(1, rescan));
        }
        // Every deauthentication costs exactly the rescan time, one sample
        // (1 s, illustrative) each, unless the walk ends first.
        expect(w.last.outageS, out.length * kBsSecondsPerStep);
        final int complete = _rejoins(w).length;
        expect(out.length, greaterThanOrEqualTo(complete * rescan));
        expect(out.length, lessThanOrEqualTo(w.last.deauthsTotal * rescan));
        // Outside an outage an associated client passes traffic.
        for (final BsStep s in w.steps.where((BsStep s) => !s.inOutage)) {
          expect(s.trafficFlowing, s.band != null);
        }
      }
    });

    test('the AP waits the retry interval on 2.4 GHz before each '
        'deauthentication', () {
      for (final int retry in <int>[1, 5, 9]) {
        final BsWalk w = _walk(
          profile: ClientProfile.c,
          mode: SteeringMode.deauthentication,
          path: WalkPath.apToEdge,
          retry: retry,
        );
        for (int i = 0; i < w.steps.length; i++) {
          final bool sent = w.steps[i].frames.any(
            (BsFrame f) => f.kind == BsFrameKind.deauthentication,
          );
          if (!sent) continue;
          // The samples before it, back to the association, are all on
          // 2.4 GHz and number at least the retry interval.
          int on24 = 0;
          for (int j = i - 1; j >= 0 && w.steps[j].band == BsBand.ghz24; j--) {
            on24++;
          }
          expect(on24 * kBsSecondsPerStep, greaterThanOrEqualTo(retry));
        }
      }
    });

    test('a client the AP never matched on 5 GHz is never deauthenticated', () {
      for (final ClientProfile p in ClientProfile.values) {
        final BsWalk w = _walk(
          profile: p,
          mode: SteeringMode.deauthentication,
          path: WalkPath.apToEdge,
          random: true,
        );
        expect(w.last.deauthsTotal, 0, reason: p.label);
      }
      // Walking in, Client C never scans after joining, so it is never
      // matched.
      expect(
        _walk(
          profile: ClientProfile.c,
          mode: SteeringMode.deauthentication,
        ).last.deauthsTotal,
        0,
      );
    });

    test('beacons still go out under deauthentication', () {
      expect(
        apSendsBeacon(SteeringMode.deauthentication, BsBand.ghz24),
        isTrue,
      );
    });
  });

  test('deterministic: the same config gives the same walk', () {
    final BsWalk a = _walk(
      profile: ClientProfile.b,
      mode: SteeringMode.authRefusal,
      path: WalkPath.apToEdge,
    );
    final BsWalk b = _walk(
      profile: ClientProfile.b,
      mode: SteeringMode.authRefusal,
      path: WalkPath.apToEdge,
    );
    expect(a.steps.length, b.steps.length);
    for (int i = 0; i < a.steps.length; i++) {
      expect(a.steps[i].band, b.steps[i].band);
      expect(a.steps[i].why, b.steps[i].why);
    }
  });
}
