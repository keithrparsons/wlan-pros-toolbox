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
}) => simulateWalk(
  BsConfig(
    profile: profile,
    mode: mode,
    path: path,
    randomScanAddress: random,
    extra5LossDb: extra,
    refusalTolerance: tolerance,
    driverSupportsBtm: driver,
  ),
);

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
