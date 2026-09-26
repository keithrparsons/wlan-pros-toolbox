// Tests for the Roaming Walk engine (Wi-Fi Classroom spec 15, "Done means").
//
// Each group maps to one clause of the spec:
//   - with delta = 0 and two equal APs, ping-pong occurs; with delta = 8 dB
//     it does not;
//   - a client never roams while above its trigger;
//   - a lower trigger increases time spent below -70 dBm on the same walk;
//   - enabling 802.11k never increases scan time;
//   - FT authentication uses 4 frames and full 802.1X more;
//   - pure Dart and deterministic with a seed.
// Plus the path-loss arithmetic and the preset values from brief §3.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/roaming_walk_engine.dart';

/// Two APs mirrored across a straight walk, so at every sample they are the
/// same distance from the client and, with no shadowing, exactly as strong.
RoamWalkConfig _twinConfig({required double deltaDb}) => RoamWalkConfig(
  aps: const <FloorPoint>[(x: 30, y: 2), (x: 30, y: 18)],
  path: const <FloorPoint>[(x: 1, y: 10), (x: 59, y: 10)],
  shadowSigmaDb: 0,
  // Above every RSSI on this walk, so the client is always below it and the
  // only thing that stops a roam is delta.
  triggerDbm: -40,
  deltaDb: deltaDb,
);

void main() {
  group('path loss', () {
    test('FSPL at 1 m is 20 log10(4 pi f / c)', () {
      for (final RoamBand b in RoamBand.values) {
        final double expected =
            20 *
            (math.log(4 * math.pi * b.freqMHz * 1e6 / 299792458.0) / math.ln10);
        expect(b.fspl1mDb, closeTo(expected, 1e-9));
      }
      // 5500 MHz: 47.26 dB.
      expect(RoamBand.b5.fspl1mDb, closeTo(47.255, 0.001));
    });

    test('log-distance: n = 3 costs 30 dB per decade', () {
      final RoamWalkConfig c = RoamWalkConfig(shadowSigmaDb: 0);
      expect(
        c.meanRssiAtDistance(1) - c.meanRssiAtDistance(10),
        closeTo(30, 1e-9),
      );
      expect(
        c.meanRssiAtDistance(1),
        closeTo(c.eirpDbm - RoamBand.b5.fspl1mDb, 1e-9),
      );
    });

    test('contour radius is where the mean RSSI equals the level', () {
      final RoamWalkConfig c = RoamWalkConfig();
      for (final double level in <double>[-67, -70, -85]) {
        expect(
          c.meanRssiAtDistance(c.contourRadiusM(level)),
          closeTo(level, 1e-9),
        );
      }
    });

    test('shadowing off: every sample is the mean', () {
      final RoamWalkConfig c = RoamWalkConfig(shadowSigmaDb: 0);
      final RoamWalkResult r = simulateRoamWalk(c);
      for (int k = 0; k < r.sampleCount; k += 37) {
        expect(r.rssi[1][k], closeTo(c.meanRssiDbm(1, r.positions[k]), 1e-9));
      }
    });

    test('shadowing: smooth along the path, spread near sigma', () {
      // Long walk, one AP's shadow sequence: sample-to-sample steps are far
      // smaller than sigma (correlated over meters), and the spread over the
      // walk is of the order of sigma.
      final RoamWalkConfig c = RoamWalkConfig(
        shadowSigmaDb: 6,
        path: kThereAndBackPath,
      );
      final RoamWalkResult r = simulateRoamWalk(c);
      double maxStep = 0;
      final List<double> x = <double>[];
      for (int k = 0; k < r.sampleCount; k++) {
        x.add(r.rssi[0][k] - c.meanRssiDbm(0, r.positions[k]));
        if (k > 0) maxStep = math.max(maxStep, (x[k] - x[k - 1]).abs());
      }
      expect(maxStep, lessThan(6));
      final double mean = x.reduce((double a, double b) => a + b) / x.length;
      final double sd = math.sqrt(
        x.map((double v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            x.length,
      );
      expect(sd, inInclusiveRange(2, 10));
    });
  });

  group('ping-pong', () {
    test('delta = 0 with two equal APs: ping-pong occurs', () {
      final RoamWalkResult r = simulateRoamWalk(_twinConfig(deltaDb: 0));
      expect(r.totals.roams, greaterThan(2));
      expect(r.totals.pingPongs, greaterThan(0));
      // Every ping-pong goes back to the AP it just left, within 5 s.
      for (int i = 1; i < r.events.length; i++) {
        final RoamEvent e = r.events[i];
        if (!e.pingPong) continue;
        final RoamEvent prev = r.events[i - 1];
        expect(e.toAp, prev.fromAp);
        expect(e.timeS - prev.timeS, lessThanOrEqualTo(5));
      }
    });

    test('delta = 8 dB with the same two APs: no ping-pong', () {
      final RoamWalkResult r = simulateRoamWalk(_twinConfig(deltaDb: 8));
      expect(r.totals.pingPongs, 0);
      expect(r.totals.roams, 0);
    });

    test('a roam back after more than 5 s is not a ping-pong', () {
      // Down the corridor and back, iPhone values: the client returns to
      // AP 1 far later than 5 s after leaving it.
      final RoamWalkResult r = simulateRoamWalk(
        RoamWalkConfig(
          path: const <FloorPoint>[
            (x: 1, y: 16),
            (x: 59, y: 16),
            (x: 1, y: 16),
          ],
          shadowSigmaDb: 0,
        ),
      );
      expect(r.events.map((RoamEvent e) => e.toAp), contains(0));
      expect(r.totals.pingPongs, 0);
    });
  });

  group('roam rule', () {
    test('a client never roams while above its trigger', () {
      for (final ClientPreset p in ClientPreset.values) {
        for (final WalkPathPreset path in WalkPathPreset.values) {
          final List<FloorPoint>? pts = path.points;
          if (pts == null) continue;
          for (final int seed in <int>[1, 2, 3]) {
            final RoamWalkResult r = simulateRoamWalk(
              RoamWalkConfig(
                path: pts,
                seed: seed,
                shadowSigmaDb: 4,
                triggerDbm: p.triggerDbm,
                deltaDb: p.deltaDb,
              ),
            );
            for (final RoamEvent e in r.events) {
              expect(e.fromRssiDbm, lessThan(p.triggerDbm));
              expect(
                e.toRssiDbm,
                greaterThanOrEqualTo(e.fromRssiDbm + p.deltaDb),
              );
              expect(r.rssi[e.fromAp][e.sample], e.fromRssiDbm);
            }
          }
        }
      }
    });

    test('the client is between APs for exactly the roam gap', () {
      final RoamWalkResult r = simulateRoamWalk(RoamWalkConfig());
      expect(r.events, isNotEmpty);
      final RoamEvent e = r.events.first;
      expect(r.servingAt(e.sample), e.fromAp);
      final int back = e.sample + (e.gapMs / 100).ceil();
      for (int k = e.sample + 1; k < back; k++) {
        expect(r.servingAt(k), isNull);
      }
      expect(r.servingAt(back), e.toAp);
    });

    test('a lower trigger increases time below -70 dBm on the same walk', () {
      double below(double trigger) => simulateRoamWalk(
        RoamWalkConfig(triggerDbm: trigger, deltaDb: 12),
      ).totals.secondsBelowWeak;
      final double iphone = below(-70);
      final double mac = below(-75);
      final double sticky = below(-85);
      expect(mac, greaterThan(iphone));
      expect(sticky, greaterThan(mac));
    });

    test('the default iPhone walk roams twice, the sticky one never', () {
      final RoamWalkResult iphone = simulateRoamWalk(
        RoamWalkConfig(shadowSigmaDb: 0),
      );
      expect(iphone.totals.roams, 2);
      expect(
        iphone.events.map((RoamEvent e) => (e.fromAp, e.toAp)).toList(),
        <(int, int)>[(0, 1), (1, 2)],
      );
      final RoamWalkResult sticky = simulateRoamWalk(
        RoamWalkConfig(shadowSigmaDb: 0, triggerDbm: -85, deltaDb: 12),
      );
      expect(sticky.totals.roams, 0);
      expect(sticky.totals.secondsBelowWeak, greaterThan(20));
    });
  });

  group('roam cost', () {
    test('enabling 802.11k never increases scan time', () {
      for (int aps = kMinAps; aps <= kMaxAps; aps++) {
        for (int ch = 1; ch <= 60; ch++) {
          for (final double dwell in <double>[5, 10, 40, 100]) {
            final RoamTiming t = RoamTiming(dwellMs: dwell, channelCount: ch);
            final double off = scanTimeMs(
              use11k: false,
              apCount: aps,
              timing: t,
            );
            final double on = scanTimeMs(use11k: true, apCount: aps, timing: t);
            expect(on, lessThanOrEqualTo(off));
          }
        }
      }
    });

    test('802.11k scans the neighbor channels, at most six', () {
      expect(scanChannels(use11k: true, apCount: 3, channelCount: 25), 2);
      expect(scanChannels(use11k: true, apCount: 6, channelCount: 25), 5);
      // Six is the cap even if a longer list existed.
      expect(kMaxNeighborChannels, 6);
      expect(scanChannels(use11k: false, apCount: 3, channelCount: 25), 25);
      expect(scanChannels(use11k: true, apCount: 6, channelCount: 3), 3);
    });

    test('FT uses 4 frames; full 802.1X uses more; PMK caching between', () {
      final int ft = authFrames(AuthMethod.ftOverTheAir).length;
      final int pmk = authFrames(AuthMethod.pmkCaching).length;
      final int full = authFrames(AuthMethod.full8021x).length;
      expect(ft, 4);
      expect(full, greaterThan(ft));
      expect(pmk, greaterThan(ft));
      expect(full, greaterThan(pmk));
      // Full 802.1X carries EAP and the 4-way handshake; FT folds the
      // handshake into its four frames.
      expect(
        authFrames(
          AuthMethod.full8021x,
        ).where((String f) => f.startsWith('EAPOL-Key')),
        hasLength(4),
      );
      expect(
        authFrames(
          AuthMethod.ftOverTheAir,
        ).where((String f) => f.startsWith('EAP')),
        isEmpty,
      );
      // Even with no EAP method frames, full 802.1X is longer than FT.
      expect(
        authFrames(AuthMethod.full8021x, eapMethodFrames: 0).length,
        greaterThan(ft),
      );
    });

    test('FT is never slower to authenticate than full 802.1X', () {
      for (final double frame in <double>[1, 3, 10]) {
        for (final double server in <double>[0, 50, 200]) {
          final RoamTiming t = RoamTiming(frameMs: frame, serverMs: server);
          expect(
            authTimeMs(AuthMethod.ftOverTheAir, t),
            lessThan(authTimeMs(AuthMethod.full8021x, t)),
          );
        }
      }
    });

    test('PMK caching applies only to an AP already joined; FT always', () {
      final RoamWalkConfig pmk = RoamWalkConfig(usePmkCaching: true);
      expect(pmk.authMethodFor(joinedBefore: false), AuthMethod.full8021x);
      expect(pmk.authMethodFor(joinedBefore: true), AuthMethod.pmkCaching);
      final RoamWalkConfig ft = RoamWalkConfig(
        useFt: true,
        usePmkCaching: true,
      );
      expect(ft.authMethodFor(joinedBefore: false), AuthMethod.ftOverTheAir);
    });

    test('gap = scan + authentication, and totals add the gaps', () {
      final RoamWalkResult r = simulateRoamWalk(
        RoamWalkConfig(use11k: true, useFt: true),
      );
      double sum = 0;
      for (final RoamEvent e in r.events) {
        expect(e.gapMs, closeTo(e.cost.scanMs + e.cost.authMs, 1e-9));
        expect(e.cost.method, AuthMethod.ftOverTheAir);
        sum += e.gapMs;
      }
      expect(r.totals.gapMs, closeTo(sum, 1e-9));
    });
  });

  group('help example (assets/help/tool_help.json, roaming-walk)', () {
    // The help sheet prints these numbers; this pins them to the engine.
    test('default floor, shadowing off', () {
      RoamWalkResult walk(ClientPreset p, {bool k = false, bool ft = false}) =>
          simulateRoamWalk(
            RoamWalkConfig(
              shadowSigmaDb: 0,
              triggerDbm: p.triggerDbm,
              deltaDb: p.deltaDb,
              use11k: k,
              useFt: ft,
            ),
          );
      final RoamWalkResult iphone = walk(ClientPreset.iphoneTx);
      expect(
        iphone.events.map((RoamEvent e) => e.timeS.toStringAsFixed(1)),
        <String>['17.7', '32.0'],
      );
      expect(iphone.totals.secondsBelowWeak.toStringAsFixed(1), '0.2');
      expect(
        walk(ClientPreset.mac).totals.secondsBelowWeak.toStringAsFixed(1),
        '11.8',
      );
      final RoamWalkResult sticky = walk(ClientPreset.sticky);
      expect(sticky.totals.roams, 0);
      expect(sticky.totals.secondsBelowWeak.toStringAsFixed(1), '23.7');
      final RoamEvent e = iphone.events.first;
      expect(e.cost.scanMs, 250);
      expect(e.cost.authMs, 101);
      expect(e.cost.frames, 17);
      final RoamEvent fast = walk(
        ClientPreset.iphoneTx,
        k: true,
        ft: true,
      ).events.first;
      expect(fast.gapMs, 32);
      expect(authFrames(AuthMethod.pmkCaching), hasLength(8));
    });
  });

  group('determinism and presets', () {
    test('same config and seed, same walk; another seed differs', () {
      final RoamWalkResult a = simulateRoamWalk(RoamWalkConfig(seed: 7));
      final RoamWalkResult b = simulateRoamWalk(RoamWalkConfig(seed: 7));
      final RoamWalkResult c = simulateRoamWalk(RoamWalkConfig(seed: 8));
      expect(a.rssi[0], b.rssi[0]);
      expect(a.events.length, b.events.length);
      expect(a.rssi[0], isNot(equals(c.rssi[0])));
    });

    test('presets carry the brief §3 values', () {
      expect(ClientPreset.iphoneTx.triggerDbm, -70);
      expect(ClientPreset.iphoneTx.deltaDb, 8);
      expect(ClientPreset.iphoneIdle.deltaDb, 12);
      expect(ClientPreset.mac.triggerDbm, -75);
      expect(ClientPreset.mac.deltaDb, 12);
      expect(ClientPreset.sticky.published, isFalse);
      expect(ClientPreset.jumpy.published, isFalse);
      expect(ClientPreset.matching(-65, 2), ClientPreset.jumpy);
      expect(ClientPreset.matching(-66, 2), isNull);
    });

    test('path helpers', () {
      expect(pathLengthM(kCorridorPath), closeTo(58, 1e-9));
      final FloorPoint mid = pointAlong(kThereAndBackPath, 58 + 6);
      expect(mid.x, closeTo(59, 1e-9));
      expect(mid.y, closeTo(10, 1e-9));
      expect(WalkPathPreset.matching(kDiagonalPath), WalkPathPreset.diagonal);
      expect(
        WalkPathPreset.matching(const <FloorPoint>[(x: 0, y: 0), (x: 1, y: 1)]),
        WalkPathPreset.custom,
      );
    });
  });
}
