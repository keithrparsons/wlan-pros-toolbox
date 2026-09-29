// Model tests for "Four ways to find a 6 GHz AP, timed" (Wi-Fi Classroom,
// join-ladder, spec 40): one test per item of the spec's "Done means"
// (myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/40-six-ghz-race.md).
// The existing Join generator stays in join_roam_test.dart, unchanged.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';

/// Every dwell extreme and default the sliders allow.
Iterable<JrConfig> _dwells() sync* {
  for (final double a in <double>[
    kMinActiveDwellMs,
    kDefaultActiveDwellMs,
    kMaxActiveDwellMs,
  ]) {
    for (final double p in <double>[
      kMinPassiveDwellMs,
      kDefaultPassiveDwellMs,
      kMaxPassiveDwellMs,
    ]) {
      yield JrConfig(activeDwellMs: a, passiveDwellMs: p);
    }
  }
}

void main() {
  test('a 6 GHz PSC probe waits dot11MinPSCProbeDelay (7 ms default, '
      '802.11-2024 26.17.2.3.3 and Annex C)', () {
    final JrScanPlan p = buildScan(
      const JrConfig(band: JrBand.g6, security: JrSecurity.sae),
    );
    final List<JrScanEvent> probes = p.events
        .where((JrScanEvent e) => e.kind == JrScanEventKind.probeRequest)
        .toList();
    expect(probes, hasLength(15));
    for (final JrScanEvent e in probes) {
      final JrScanChannel ch = p.channels.firstWhere(
        (JrScanChannel c) => c.number == e.channel,
      );
      expect(
        e.atMs - ch.startMs,
        greaterThanOrEqualTo(7),
        reason: '${ch.number}',
      );
    }
    expect(kMinPscProbeDelayMs, 7);
    // An RNR-directed probe is not held to the PSC idle rule, and 5 GHz
    // probes are unchanged.
    final JrScanPlan rnr = buildScan(
      const JrConfig(band: JrBand.g6, sixGhz: JrSixGhzDiscovery.rnr),
    );
    expect(
      rnr.events.first.atMs,
      kProbeAtMs,
      reason: 'the RNR probe goes out at once',
    );
    final JrScanPlan five = buildScan(const JrConfig());
    expect(
      five.events
          .firstWhere((JrScanEvent e) => e.kind == JrScanEventKind.probeRequest)
          .atMs,
      kProbeAtMs,
    );
  });

  test('four lanes, in order, each with its own scan', () {
    final SixGhzRace r = sixGhzRace(const JrConfig());
    expect(r.lanes.map((SixGhzRaceLane l) => l.method).toList(), <SixGhzMethod>[
      SixGhzMethod.passiveAll,
      SixGhzMethod.pscProbe,
      SixGhzMethod.rnr,
      SixGhzMethod.filsListen,
    ]);
    for (final SixGhzRaceLane l in r.lanes) {
      expect(l.plan.band, JrBand.g6, reason: '${l.method}');
      expect(l.plan.targetChannel, 37);
    }
    // The existing enum is untouched.
    expect(JrSixGhzDiscovery.values, <JrSixGhzDiscovery>[
      JrSixGhzDiscovery.psc,
      JrSixGhzDiscovery.rnr,
    ]);
    // The AP's channel is a PSC (802.11-2024 26.17.2.3.2: a 6 GHz-only AP
    // should put its primary channel on one).
    expect(k6Pscs.contains(r.targetChannel), isTrue);
  });

  test('passive, all 59: finds the AP only inside its channel\'s dwell', () {
    for (final JrConfig c in _dwells()) {
      final SixGhzRaceLane l = sixGhzRace(c).lane(SixGhzMethod.passiveAll);
      final JrScanPlan p = l.plan;
      expect(p.channels, hasLength(59));
      expect(p.probedCount, 0);
      final JrScanChannel t = p.target;
      for (final JrScanEvent e in p.events) {
        if (!e.heard) continue;
        expect(e.channel, 37);
        expect(e.atMs, inInclusiveRange(t.startMs, t.endMs));
      }
      expect(l.found, isTrue, reason: 'passive dwell ${c.passiveDwellMs}');
      expect(l.foundAtMs, inInclusiveRange(t.startMs, t.endMs));
    }
  });

  test('probe the PSCs: probes only on PSCs, never before 7 ms', () {
    for (final JrConfig c in _dwells()) {
      final JrScanPlan p = sixGhzRace(c).lane(SixGhzMethod.pscProbe).plan;
      expect(p.probedChannels.toSet().difference(k6Pscs), isEmpty);
      expect(p.probedChannels, hasLength(15));
      expect(p.channels.every((JrScanChannel ch) => ch.psc), isTrue);
      for (final JrScanEvent e in p.events) {
        if (e.kind != JrScanEventKind.probeRequest) continue;
        final JrScanChannel ch = p.channels.firstWhere(
          (JrScanChannel x) => x.number == e.channel,
        );
        expect(e.atMs - ch.startMs, greaterThanOrEqualTo(kMinPscProbeDelayMs));
      }
      // The AP answers inside the dwell, even at the shortest one.
      expect(p.firstHeard!.kind, JrScanEventKind.probeResponse);
    }
  });

  test('FILS listen: PSCs only, 20 TU or more each, always hears a frame', () {
    expect(kFilsListenDwellMs, greaterThanOrEqualTo(20.48));
    for (final JrConfig c in _dwells()) {
      final SixGhzRaceLane l = sixGhzRace(c).lane(SixGhzMethod.filsListen);
      final JrScanPlan p = l.plan;
      expect(p.channels, hasLength(15));
      expect(p.channels.every((JrScanChannel ch) => ch.psc), isTrue);
      expect(p.probedCount, 0, reason: 'it only listens');
      for (final JrScanChannel ch in p.channels) {
        expect(ch.dwellMs, greaterThanOrEqualTo(20.48));
      }
      expect(l.found, isTrue);
      expect(p.firstHeard!.kind, JrScanEventKind.fils);
      expect(p.firstHeard!.channel, 37);
    }
    // Whatever the phase of the AP's 20 TU frames, a 20 TU dwell holds one:
    // every heard FILS frame lies in the dwell, and the dwell is a whole
    // interval long.
    final JrScanPlan p = buildFilsListenScan(const JrConfig());
    expect(p.target.dwellMs, closeTo(kFilsIntervalMs, 1e-9));
  });

  test('at the defaults: FILS listen <= PSC probe < passive, all 59', () {
    final SixGhzRace r = sixGhzRace(const JrConfig());
    final double fils = r.lane(SixGhzMethod.filsListen).foundAtMs!;
    final double psc = r.lane(SixGhzMethod.pscProbe).foundAtMs!;
    final double passive = r.lane(SixGhzMethod.passiveAll).foundAtMs!;
    expect(fils, lessThanOrEqualTo(psc));
    expect(psc, lessThan(passive));
    // The worked numbers in spec 40.
    expect(fils, closeTo(2 * 20.48 + 10.24, 1e-9)); // 51.2 ms
    expect(psc, closeTo(2 * 30 + 7 + 2, 1e-9)); // 69 ms
    expect(passive, closeTo(9 * 111 + 10.24, 1e-9)); // 1009.24 ms
    expect(r.lane(SixGhzMethod.passiveAll).plan.totalMs, 59 * 111);
  });

  test('a short active dwell flips PSC probe ahead of FILS listen', () {
    final SixGhzRace r = sixGhzRace(
      const JrConfig(activeDwellMs: kMinActiveDwellMs),
    );
    expect(r.lane(SixGhzMethod.pscProbe).foundAtMs, closeTo(29, 1e-9));
    expect(
      r.lane(SixGhzMethod.pscProbe).foundAtMs!,
      lessThan(r.lane(SixGhzMethod.filsListen).foundAtMs!),
    );
  });

  test('RNR with and without the 5 GHz scan that heard it', () {
    for (final JrConfig c in _dwells()) {
      final SixGhzRaceLane on = sixGhzRace(c).lane(SixGhzMethod.rnr);
      final SixGhzRaceLane off = sixGhzRace(
        c,
        rnrCountsPriorScan: false,
      ).lane(SixGhzMethod.rnr);
      final JrScanPlan fiveGhz = buildScan(
        c.copyWith(band: JrBand.g5, scanType: JrScanType.active),
      );
      expect(on.prior, isNotNull);
      expect(on.prior!.band, JrBand.g5);
      expect(off.prior, isNull);
      expect(off.offsetMs, 0);
      expect(on.offsetMs, fiveGhz.totalMs);
      expect(on.foundAtMs! - off.foundAtMs!, closeTo(fiveGhz.totalMs, 1e-9));
      // One 6 GHz channel, one directed probe, at once.
      expect(on.plan.rnr, isTrue);
      expect(on.plan.probedChannels, <int>[37]);
      expect(off.foundAtMs, closeTo(kProbeResponseAtMs, 1e-9));
    }
    // At the defaults: 3 ms on its own, 2.05 s counting the 5 GHz scan
    // (9 probed channels x 30 ms + 16 DFS channels x 111 ms).
    final SixGhzRace on = sixGhzRace(const JrConfig());
    final SixGhzRace off = sixGhzRace(
      const JrConfig(),
      rnrCountsPriorScan: false,
    );
    expect(on.lane(SixGhzMethod.rnr).foundAtMs, closeTo(2046 + 3, 1e-9));
    expect(on.rnrCountsPriorScan, isTrue);
    // Counting the scan, RNR is the slowest; alone, the fastest.
    expect(on.winner!.method, SixGhzMethod.filsListen);
    expect(off.winner!.method, SixGhzMethod.rnr);
    expect(on.axisMs, on.lane(SixGhzMethod.rnr).foundAtMs);
    expect(off.axisMs, off.lane(SixGhzMethod.passiveAll).foundAtMs);
  });

  test('findings are sorted and distinct; the race ignores the band and '
      'scan type the ladder is set to', () {
    final SixGhzRace r = sixGhzRace(const JrConfig());
    final List<double> f = r.findings;
    expect(f, hasLength(4));
    for (int i = 1; i < f.length; i++) {
      expect(f[i], greaterThan(f[i - 1]));
    }
    for (final JrBand b in JrBand.values) {
      for (final JrScanType t in JrScanType.values) {
        final SixGhzRace other = sixGhzRace(
          JrConfig(band: b, scanType: t, security: JrSecurity.sae),
        );
        expect(other.findings, f, reason: '$b $t');
      }
    }
  });

  test('every lane finds the AP at every dwell setting (not found is '
      'unreachable while the AP sends FILS every 20 TU)', () {
    for (final JrConfig c in _dwells()) {
      for (final bool prior in <bool>[true, false]) {
        final SixGhzRace r = sixGhzRace(c, rnrCountsPriorScan: prior);
        for (final SixGhzRaceLane l in r.lanes) {
          expect(l.found, isTrue, reason: '${l.method} $c');
          expect(l.foundAtMs!, lessThanOrEqualTo(r.axisMs));
          expect(l.foundAtMs!, lessThanOrEqualTo(l.endMs));
        }
      }
    }
  });
}
