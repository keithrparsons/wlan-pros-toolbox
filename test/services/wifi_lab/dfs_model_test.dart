// Model tests for the Wi-Fi Lab DFS and Radar simulator (dfs-simulator).
//
// Pins spec 25 "Done means" (myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/25-dfs.md) against the brief §2 values: CAC 60 s in the
// US; 60 s in the EU outside 5600-5650 MHz and 600 s on 120/124/128; 30 min
// of non-occupancy after radar and a move inside 10 s; 144 is DFS in the US
// and absent from the EU plan; a move to a non-DFS channel costs no CAC.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/dfs_model.dart';

BondedChannel _p(DfsRegion r, int ch, [int width = 20]) => dfsPlacements(
  r,
  width,
).firstWhere((BondedChannel b) => b.components.contains(ch));

void main() {
  group('channel availability check', () {
    test('US: 60 s on every DFS channel, including 120/124/128', () {
      for (final int ch in <int>[52, 64, 100, 120, 124, 128, 144]) {
        expect(
          cacSecondsFor(DfsRegion.us, _p(DfsRegion.us, ch)),
          60,
          reason: 'ch $ch',
        );
      }
      final DfsRun run = simulateDfs(const DfsConfig(startChannel: 52));
      expect(run.firstTxS, 60);
      expect(run.segments.first.phase, ApPhase.cac);
      expect(run.segments.first.endS, 60);
    });

    test('EU: 60 s outside 5600-5650 MHz, 600 s on 120, 124, 128', () {
      for (final int ch in <int>[
        52,
        64,
        100,
        104,
        108,
        112,
        116,
        132,
        136,
        140,
      ]) {
        expect(
          cacSecondsFor(DfsRegion.eu, _p(DfsRegion.eu, ch)),
          60,
          reason: 'ch $ch',
        );
      }
      for (final int ch in <int>[120, 124, 128]) {
        expect(
          cacSecondsFor(DfsRegion.eu, _p(DfsRegion.eu, ch)),
          600,
          reason: 'ch $ch',
        );
      }
      final DfsRun run = simulateDfs(
        const DfsConfig(region: DfsRegion.eu, startChannel: 124),
      );
      expect(run.firstTxS, 600);
    });

    test('EU: a wide channel partly in 5600-5650 takes 600 s', () {
      // 116+120 spans 5570-5610; 132+136 starts at 5650 (edge only).
      expect(cacSecondsFor(DfsRegion.eu, _p(DfsRegion.eu, 116, 40)), 600);
      expect(cacSecondsFor(DfsRegion.eu, _p(DfsRegion.eu, 132, 40)), 60);
      expect(cacSecondsFor(DfsRegion.eu, _p(DfsRegion.eu, 100, 160)), 600);
      expect(cacSecondsFor(DfsRegion.us, _p(DfsRegion.us, 100, 160)), 60);
    });

    test('non-DFS channels serve at once', () {
      expect(cacSecondsFor(DfsRegion.us, _p(DfsRegion.us, 36)), 0);
      expect(cacSecondsFor(DfsRegion.us, _p(DfsRegion.us, 149)), 0);
      final DfsRun run = simulateDfs(const DfsConfig(startChannel: 36));
      expect(run.firstTxS, 0);
      expect(run.segments.single.phase, ApPhase.service);
    });

    test('a 160 MHz channel that includes 52-64 is DFS', () {
      final BondedChannel wide = _p(DfsRegion.us, 36, 160);
      expect(placementIsDfs(DfsRegion.us, wide), isTrue);
      expect(cacSecondsFor(DfsRegion.us, wide), 60);
    });
  });

  group('channel plans', () {
    test('US 144 is DFS; the EU plan does not offer 144', () {
      expect(isDfsChannel(DfsRegion.us, 144), isTrue);
      expect(regionChannels(DfsRegion.eu), isNot(contains(144)));
      expect(isDfsChannel(DfsRegion.eu, 144), isFalse);
      expect(
        dfsPlacements(
          DfsRegion.eu,
          20,
        ).any((BondedChannel p) => p.components.contains(144)),
        isFalse,
      );
      // Nor at any width: 140+144 and 132-144 are gone too.
      for (final int w in kDfsWidths) {
        expect(
          dfsPlacements(
            DfsRegion.eu,
            w,
          ).any((BondedChannel p) => p.components.contains(144)),
          isFalse,
          reason: '$w MHz',
        );
      }
    });

    test('DFS sets: US 52-64 and 100-144; EU 52-64 and 100-140', () {
      List<int> dfs(DfsRegion r) => <int>[
        for (final int c in regionChannels(r))
          if (isDfsChannel(r, c)) c,
      ];
      expect(dfs(DfsRegion.us), <int>[
        52,
        56,
        60,
        64,
        100,
        104,
        108,
        112,
        116,
        120,
        124,
        128,
        132,
        136,
        140,
        144,
      ]);
      expect(dfs(DfsRegion.eu), <int>[
        52,
        56,
        60,
        64,
        100,
        104,
        108,
        112,
        116,
        120,
        124,
        128,
        132,
        136,
        140,
      ]);
    });
  });

  group('radar', () {
    test('while serving: blocked 30 min, move inside 10 s, closing times', () {
      final DfsRun run = simulateDfs(
        const DfsConfig(startChannel: 100, manualRadarS: <double>[300]),
      );
      final RadarHit h = run.hits.single;
      expect(h.duringCac, isFalse);
      expect(h.channel.components, <int>[100]);
      expect(h.stopTrafficS - h.timeS, closeTo(0.2, 1e-9));
      expect(h.moveS, lessThanOrEqualTo(10));
      final ChannelBlock b = run.blocks.single;
      expect(b.channels, <int>[100]);
      expect(b.untilS - b.fromS, 30 * 60);
      expect(run.statusOf(100, 300 + 29 * 60).use, ChannelUse.blocked);
      expect(run.statusOf(100, 300 + 30 * 60).use, ChannelUse.available);

      final DfsRun eu = simulateDfs(
        const DfsConfig(
          region: DfsRegion.eu,
          startChannel: 100,
          manualRadarS: <double>[300],
        ),
      );
      expect(eu.hits.single.stopTrafficS - 300, closeTo(1.0, 1e-9));
      expect(eu.hits.single.moveS, lessThanOrEqualTo(10));
    });

    test('move to a non-DFS channel has no CAC; clients follow', () {
      final DfsRun run = simulateDfs(
        const DfsConfig(startChannel: 100, manualRadarS: <double>[300]),
      );
      final RadarHit h = run.hits.single;
      expect(placementIsDfs(DfsRegion.us, h.next), isFalse);
      expect(h.nextCacS, 0);
      expect(h.resumeS, h.leaveS);
      expect(h.outageS, closeTo(kApSwitchS, 1e-9));
      expect(h.clientsDropped, isFalse);
      for (int i = 0; i < kClientRejoinS.length; i++) {
        expect(run.clientConnectedAt(i, h.resumeS!), isTrue);
      }
    });

    test('move to another DFS channel pays a new CAC; clients drop', () {
      final DfsRun run = simulateDfs(
        const DfsConfig(
          startChannel: 100,
          policy: NewChannelPolicy.anotherDfs,
          manualRadarS: <double>[300],
        ),
      );
      final RadarHit h = run.hits.single;
      expect(h.next.components, <int>[104]);
      expect(h.nextCacS, 60);
      expect(h.resumeS, closeTo(h.leaveS + 60, 1e-9));
      expect(h.clientsDropped, isTrue);
      expect(run.clientConnectedAt(0, h.resumeS!), isFalse);
      expect(run.clientConnectedAt(0, h.resumeS! + kClientRejoinS[0]), isTrue);
    });

    test('EU policy "another DFS" from 116 lands on 120 and waits 10 min', () {
      final DfsRun run = simulateDfs(
        const DfsConfig(
          region: DfsRegion.eu,
          startChannel: 116,
          policy: NewChannelPolicy.anotherDfs,
          manualRadarS: <double>[120],
        ),
      );
      final RadarHit h = run.hits.single;
      expect(h.next.components, <int>[120]);
      expect(h.nextCacS, 600);
      expect(h.outageS, closeTo(kApSwitchS + 600, 1e-9));
    });

    test('radar during a CAC: leaves at once, never transmitted', () {
      final DfsRun run = simulateDfs(
        const DfsConfig(startChannel: 52, manualRadarS: <double>[30]),
      );
      final RadarHit h = run.hits.single;
      expect(h.duringCac, isTrue);
      expect(h.leaveS, 30);
      expect(run.firstTxS, 30); // moved to 36, no CAC
      expect(run.blocks.single.channels, <int>[52]);
    });

    test('radar on a non-DFS channel is not acted on', () {
      final DfsRun run = simulateDfs(
        const DfsConfig(startChannel: 36, manualRadarS: <double>[300]),
      );
      expect(run.hits, isEmpty);
      expect(run.radarActionableAt(300), isFalse);
    });

    test('a wide channel blocks every 20 MHz channel it used', () {
      final DfsRun run = simulateDfs(
        const DfsConfig(
          widthMHz: 80,
          startChannel: 100,
          manualRadarS: <double>[200],
        ),
      );
      expect(run.blocks.single.channels, <int>[100, 104, 108, 112]);
      expect(run.hits.single.next.components, <int>[36, 40, 44, 48]);
    });

    test('160 MHz: no non-DFS 160 exists, then no free 160, so it narrows', () {
      final DfsRun run = simulateDfs(
        const DfsConfig(
          widthMHz: 160,
          startChannel: 100,
          manualRadarS: <double>[200, 400],
        ),
      );
      expect(run.hits, hasLength(2));
      final RadarHit first = run.hits[0];
      expect(first.noNonDfsAtWidth, isTrue);
      expect(first.next.components.first, 36);
      expect(first.next.widthMHz, 160);
      final RadarHit second = run.hits[1];
      expect(second.narrowedFromMHz, 160);
      expect(second.next.widthMHz, lessThan(160));
      expect(placementIsDfs(DfsRegion.us, second.next), isFalse);
    });

    test('random radar is seeded: same config, same run', () {
      const DfsConfig c = DfsConfig(startChannel: 100, radarPerHour: 12);
      final List<double> a = randomRadarTimes(12, 1);
      expect(a, randomRadarTimes(12, 1));
      expect(a, isNotEmpty);
      expect(
        simulateDfs(c).hits.map((RadarHit h) => h.timeS),
        simulateDfs(c).hits.map((RadarHit h) => h.timeS),
      );
      expect(randomRadarTimes(0, 1), isEmpty);
    });
  });

  group('detection threshold', () {
    test('FCC: -64 dBm at 200 mW and up, -62 dBm below', () {
      expect(detectionThresholdDbm(DfsRegion.us, 23, 20), -64);
      expect(detectionThresholdDbm(DfsRegion.us, 30, 80), -64);
      expect(detectionThresholdDbm(DfsRegion.us, 20, 20), -62);
    });

    test('ETSI: -62 + 10 - PSD, floor -64', () {
      // 23 dBm over 20 MHz is 10 dBm/MHz: -62 dBm.
      expect(detectionThresholdDbm(DfsRegion.eu, 23, 20), closeTo(-62, 0.02));
      // 30 dBm over 20 MHz is 17 dBm/MHz: formula -69, floored to -64.
      expect(detectionThresholdDbm(DfsRegion.eu, 30, 20), -64);
      // 20 dBm over 80 MHz is 0.97 dBm/MHz: about -53 dBm.
      expect(
        detectionThresholdDbm(DfsRegion.eu, 20, 80),
        closeTo(-52.97, 0.01),
      );
    });
  });

  group('help example (assets/help/tool_help.json, dfs-simulator)', () {
    // The help sheet prints these numbers; this pins them to the model.
    test('US 100, radar at 5:00; Another DFS; EU 116', () {
      final DfsRun us = simulateDfs(
        const DfsConfig(startChannel: 100, manualRadarS: <double>[300]),
      );
      expect(fmtClock(us.firstTxS!), '1:00');
      final RadarHit h = us.hits.single;
      expect(h.next.components, <int>[36]);
      expect(fmtSpan(h.outageS!), '1.0 s');
      expect(fmtClock(us.blocks.single.untilS), '35:00');

      final RadarHit dfs = simulateDfs(
        const DfsConfig(
          startChannel: 100,
          policy: NewChannelPolicy.anotherDfs,
          manualRadarS: <double>[300],
        ),
      ).hits.single;
      expect(dfs.next.components, <int>[104]);
      expect(fmtSpan(dfs.outageS!), '61.0 s');

      final RadarHit eu = simulateDfs(
        const DfsConfig(
          region: DfsRegion.eu,
          startChannel: 116,
          policy: NewChannelPolicy.anotherDfs,
          manualRadarS: <double>[300],
        ),
      ).hits.single;
      expect(eu.next.components, <int>[120]);
      expect(fmtSpan(eu.outageS!), '10 min 1 s');
    });
  });

  group('formatting', () {
    test('clock and spans', () {
      expect(fmtClock(0), '0:00');
      expect(fmtClock(605.7), '10:05');
      expect(fmtSpan(0.2), '200 ms');
      expect(fmtSpan(61), '61.0 s');
      expect(fmtSpan(600), '10 min');
      expect(fmtSpan(1801), '30 min 1 s');
    });
  });
}
