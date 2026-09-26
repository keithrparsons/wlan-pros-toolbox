// Unit tests for the Channel Planner model (Wi-Fi Classroom, channel-planner).
//
// Expected values are spec 16 "Done means" and brief §4 of
// myPKA Deliverables/2026-09-25-wifi-lab-wave3-research/brief.md. The channel
// counts are counted by the model from lib/data/channel_frequency_data.dart;
// the numbers below are the brief's, written down independently.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/channel_planner_model.dart';

const List<int> _widths = <int>[20, 40, 80, 160];

List<int> _counts(PlanRules r) => <int>[
  for (final int w in _widths) channelsAvailable(r, w),
];

ChannelOption _opt(PlanRules r, int width, int primary) =>
    channelOptions(r, width).firstWhere(
      (ChannelOption o) =>
          o.primary == primary && o.group.components.first <= primary,
    );

void main() {
  group('5 GHz channel counts at 20/40/80/160 MHz (brief §4)', () {
    const PlanRules us = PlanRules(region: PlannerRegion.us);
    const PlanRules eu = PlanRules(region: PlannerRegion.eu);

    test('US all channels: 25/12/6/2', () {
      expect(_counts(us.copyWith(dfs: true)), <int>[25, 12, 6, 2]);
    });
    test('US without DFS: 9/4/2/0', () {
      expect(_counts(us), <int>[9, 4, 2, 0]);
    });
    test('US with U-NII-4: 28/14/7/3 and 12/6/3/1 without DFS', () {
      expect(_counts(us.copyWith(dfs: true, unii4: true)), <int>[28, 14, 7, 3]);
      expect(_counts(us.copyWith(unii4: true)), <int>[12, 6, 3, 1]);
    });
    test('EU all channels: 19/9/4/2', () {
      expect(_counts(eu.copyWith(dfs: true)), <int>[19, 9, 4, 2]);
    });
    test('EU without DFS: 4/2/1/0', () {
      expect(_counts(eu), <int>[4, 2, 1, 0]);
    });
    test('EU drops 144 (5710-5730 MHz crosses the 5725 edge)', () {
      final List<int> ch = allowed20(eu.copyWith(dfs: true));
      expect(ch, contains(140));
      expect(ch, isNot(contains(144)));
      expect(ch, isNot(contains(149)));
    });
    test('U-NII-4 is ignored in the EU', () {
      expect(
        _counts(eu.copyWith(dfs: true, unii4: true)),
        _counts(eu.copyWith(dfs: true)),
      );
    });
  });

  group('2.4 GHz plan channels', () {
    const PlanRules us = PlanRules(band: PlannerBand.band24);
    test('US 20 MHz OFDM: 1, 6, 11', () {
      expect(
        planChannels(us, 20).map((ChannelGroup g) => g.components.first),
        <int>[1, 6, 11],
      );
    });
    test('EU 20 MHz OFDM: 1, 5, 9, 13', () {
      expect(
        planChannels(
          us.copyWith(region: PlannerRegion.eu),
          20,
        ).map((ChannelGroup g) => g.components.first),
        <int>[1, 5, 9, 13],
      );
    });
    test('DSSS is 22 MHz wide: 3 channels in the EU too, no 40 MHz', () {
      final PlanRules eu = us.copyWith(
        region: PlannerRegion.eu,
        mask: TxMask.dsss,
      );
      expect(channelsAvailable(eu, 20), 3);
      expect(channelsAvailable(eu, 40), 0);
    });
    test('40 MHz: one in the US, two in the EU', () {
      expect(channelsAvailable(us, 40), 1);
      expect(channelsAvailable(us.copyWith(region: PlannerRegion.eu), 40), 2);
    });
  });

  group('transmit masks (brief §4, tolerance 0.2 dB)', () {
    test('OFDM at 25 MHz = -34 dBr', () {
      expect(maskDbr(TxMask.ofdm, 25), closeTo(-34, 0.2));
    });
    test('OFDM at 15 MHz = -23.6 dBr', () {
      expect(maskDbr(TxMask.ofdm, 15), closeTo(-23.6, 0.2));
    });
    test('OFDM breakpoints: 0 to 9, -20 at 11, -28 at 20, -40 at 30+', () {
      expect(maskDbr(TxMask.ofdm, 9), 0);
      expect(maskDbr(TxMask.ofdm, 11), closeTo(-20, 1e-9));
      expect(maskDbr(TxMask.ofdm, 20), closeTo(-28, 1e-9));
      expect(maskDbr(TxMask.ofdm, 30), closeTo(-40, 1e-9));
      expect(maskDbr(TxMask.ofdm, 45), -40);
      expect(maskDbr(TxMask.ofdm, -25), closeTo(-34, 0.2));
    });
    test('DSSS: -30 dBr at 15 and 20 MHz, -50 at 25', () {
      expect(maskDbr(TxMask.dsss, 15), -30);
      expect(maskDbr(TxMask.dsss, 20), -30);
      expect(maskDbr(TxMask.dsss, 25), -50);
      expect(maskDbr(TxMask.dsss, 5), 0);
    });
    test('integrated leak: 0 dB co-channel, and above the mask value', () {
      expect(adjacentChannelDb(TxMask.ofdm, 0), closeTo(0, 0.01));
      // Integrating over the victim's 20 MHz picks up the near edge, so the
      // leak is larger than the mask value at the victim's center.
      final double at25 = adjacentChannelDb(TxMask.ofdm, 25);
      expect(at25, greaterThan(maskDbr(TxMask.ofdm, 25)));
      expect(at25, inInclusiveRange(-32, -28));
      expect(
        adjacentChannelDb(TxMask.ofdm, 15),
        greaterThan(adjacentChannelDb(TxMask.ofdm, 20)),
      );
    });
  });

  group('contention thresholds', () {
    const PlanRules r = PlanRules(dfs: true);

    test('two co-channel APs at -80 dBm contend; at -85 dBm they do not', () {
      final ChannelOption a = _opt(r, 20, 36);
      final Deferral hear = evaluateDeferral(
        observer: a,
        transmitter: a,
        rxTotalDbm: -80,
      );
      expect(hear.defers, isTrue);
      expect(hear.rule, CcaRule.preambleDetect);
      final Deferral quiet = evaluateDeferral(
        observer: a,
        transmitter: a,
        rxTotalDbm: -85,
      );
      expect(quiet.defers, isFalse);
      expect(quiet.overlaps, isTrue);

      final PlanAnalysis near = analyzePlan(
        aps: <PlannerAp>[
          PlannerAp(const FloorPoint(0, 0), a),
          PlannerAp(const FloorPoint(0, 0), a),
        ],
        walls: const <Wall>[],
        propagation: const PropagationSettings(eirpDbm: -80 + 47.26),
        rules: r,
      );
      expect(near.contending, hasLength(1));
    });

    test('two APs on non-overlapping channels never contend', () {
      for (final (PlanRules rr, int x, int y) in <(PlanRules, int, int)>[
        (r, 36, 40),
        (r, 36, 149),
        (const PlanRules(band: PlannerBand.band24), 1, 6),
        (const PlanRules(band: PlannerBand.band24), 6, 11),
      ]) {
        final ChannelOption a = _opt(rr, 20, x), b = _opt(rr, 20, y);
        for (final double rx in <double>[-90, -60, -30, 0, 20]) {
          expect(
            evaluateDeferral(
              observer: a,
              transmitter: b,
              rxTotalDbm: rx,
            ).defers,
            isFalse,
            reason: '$x vs $y at $rx dBm',
          );
        }
      }
    });

    test('secondary 20 MHz uses -72 dBm signal detect in 5 GHz', () {
      final ChannelOption wide = _opt(r, 40, 36); // 36 + 40
      final ChannelOption on40 = _opt(r, 20, 40);
      Deferral d(double rx) =>
          evaluateDeferral(observer: wide, transmitter: on40, rxTotalDbm: rx);
      expect(d(-70).rule, CcaRule.secondarySignal);
      expect(d(-74).defers, isFalse);
      // The 20 MHz AP on 40 hears the 40 MHz AP's duplicated preamble on its
      // own primary, at half the power per 20 MHz.
      final Deferral back = evaluateDeferral(
        observer: on40,
        transmitter: wide,
        rxTotalDbm: -78,
      );
      expect(back.rule, CcaRule.preambleDetect);
      expect(back.levelDbm, closeTo(-81.01, 0.01));
    });

    test('energy detect -62 dBm on a far secondary of an 80 MHz channel', () {
      final ChannelOption wide = _opt(r, 80, 36); // 36-48, secondary 40
      final ChannelOption on48 = _opt(r, 20, 48);
      expect(
        evaluateDeferral(
          observer: wide,
          transmitter: on48,
          rxTotalDbm: -61,
        ).rule,
        CcaRule.energyDetect,
      );
      expect(
        evaluateDeferral(
          observer: wide,
          transmitter: on48,
          rxTotalDbm: -64,
        ).defers,
        isFalse,
      );
    });

    test('2.4 GHz 1 vs 4 overlaps: energy only, from the mask', () {
      const PlanRules g = PlanRules(band: PlannerBand.band24);
      final ChannelOption one = _opt(g, 20, 1), four = _opt(g, 20, 4);
      final double leak = adjacentChannelDb(TxMask.ofdm, 15);
      final Deferral d = evaluateDeferral(
        observer: one,
        transmitter: four,
        rxTotalDbm: -62 - leak + 0.5,
      );
      expect(d.rule, CcaRule.energyDetect);
      expect(
        evaluateDeferral(
          observer: one,
          transmitter: four,
          rxTotalDbm: -62 - leak - 0.5,
        ).defers,
        isFalse,
      );
    });
  });

  group('floor', () {
    test('a wall between two APs costs its loss', () {
      const PropagationSettings p = PropagationSettings(wallLossDb: 12);
      final double open = receivedDbm(
        p: p,
        band: PlannerBand.band5,
        distanceM: 10,
        wallsCrossed: 0,
      );
      final double walled = receivedDbm(
        p: p,
        band: PlannerBand.band5,
        distanceM: 10,
        wallsCrossed: 1,
      );
      expect(open - walled, 12);
      // 20 dBm - (47.26 + 30 log10 10) = -57.26 dBm at 5500 MHz, n = 3.
      expect(open, closeTo(-57.26, 0.01));
      expect(
        crossesWall(
          const FloorPoint(0, 5),
          const FloorPoint(10, 5),
          const Wall(5, 0, 5, 10),
        ),
        isTrue,
      );
      expect(
        crossesWall(
          const FloorPoint(0, 5),
          const FloorPoint(4, 5),
          const Wall(5, 0, 5, 10),
        ),
        isFalse,
      );
    });

    test('largest domain is a clique of mutual deferral', () {
      final List<Set<int>> adj = <Set<int>>[
        <int>{1},
        <int>{0, 2},
        <int>{1},
      ];
      // A chain: 0-1 and 1-2 contend, 0 and 2 do not.
      expect(maximalCliques(adj).first, hasLength(2));
    });
  });

  group('auto-plan', () {
    const List<FloorPoint> spots = <FloorPoint>[
      FloorPoint(9, 8),
      FloorPoint(25, 8),
      FloorPoint(41, 8),
      FloorPoint(9, 22),
      FloorPoint(25, 22),
      FloorPoint(41, 22),
    ];

    int largest(PlanRules r, int width) {
      final List<ChannelOption?> plan = autoPlan(
        positions: spots,
        walls: const <Wall>[],
        propagation: const PropagationSettings(),
        rules: r,
        width: width,
      );
      return analyzePlan(
        aps: <PlannerAp>[
          for (int i = 0; i < spots.length; i++) PlannerAp(spots[i], plan[i]),
        ],
        walls: const <Wall>[],
        propagation: const PropagationSettings(),
        rules: r,
      ).largestDomain.length;
    }

    test('six APs on nine 20 MHz channels: nobody shares', () {
      expect(largest(const PlanRules(), 20), 1);
    });
    test('six APs on two 80 MHz channels: three share', () {
      expect(largest(const PlanRules(), 80), 3);
    });
    test('2.4 GHz uses only 1, 6 and 11', () {
      const PlanRules g = PlanRules(band: PlannerBand.band24);
      final List<ChannelOption?> plan = autoPlan(
        positions: spots,
        walls: const <Wall>[],
        propagation: const PropagationSettings(),
        rules: g,
        width: 20,
      );
      expect(
        plan.map((ChannelOption? c) => c!.primary).toSet(),
        everyElement(isIn(<int>[1, 6, 11])),
      );
      expect(largest(g, 20), 2);
    });
    test('no channel at this width: nothing assigned', () {
      expect(
        autoPlan(
          positions: spots,
          walls: const <Wall>[],
          propagation: const PropagationSettings(),
          rules: const PlanRules(),
          width: 160,
        ),
        everyElement(isNull),
      );
    });
  });
}
