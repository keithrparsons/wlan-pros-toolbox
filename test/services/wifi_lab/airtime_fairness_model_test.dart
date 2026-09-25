// Unit tests for the Airtime Fairness model (Wi-Fi Lab spec 04, "Done means").

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_fairness_model.dart';

const ClientConfig _slow = ClientConfig(rateMbps: 6, legacy: true);
const ClientConfig _fast = ClientConfig(rateMbps: 54, legacy: true);

void main() {
  group('constants', () {
    test('overhead parts match spec 04', () {
      expect(AirtimeConstants.aifsUs, 43);
      expect(AirtimeConstants.avgBackoffUs, 67.5);
      expect(AirtimeConstants.preambleLegacyUs, 20);
      expect(AirtimeConstants.preambleHtUs, 40);
      expect(AirtimeConstants.sifsUs, 16);
      expect(AirtimeConstants.ackUs, 28);
      expect(AirtimeConstants.blockAckUs, 32);
      expect(AirtimeConstants.perFrameOverheadBytes, 26 + 4 + 4);
    });
  });

  group('T_i', () {
    test('1500 bytes at 54 Mbps, n = 1, equals the spec formula', () {
      const double expected =
          (43 + 67.5 + 20 + 16 + 28) + (8 * 1 * (1500 + 34)) / 54;
      expect(airtimeUs(_fast), closeTo(expected, 1e-9));
      expect(airtimeUs(_fast), closeTo(401.7593, 1e-4));
    });

    test('aggregated HT+ client uses the 40 us preamble and Block Ack', () {
      const ClientConfig c = ClientConfig(
        rateMbps: 867,
        legacy: false,
        aggregation: 32,
      );
      expect(overheadUs(c), 43 + 67.5 + 40 + 16 + 32);
      expect(airtimeUs(c), closeTo(198.5 + 8 * 32 * 1534 / 867, 1e-9));
    });

    test('non-legacy client with n = 1 takes a plain ACK', () {
      const ClientConfig c = ClientConfig(rateMbps: 150, legacy: false);
      expect(overheadUs(c), 43 + 67.5 + 40 + 16 + 28);
    });

    test('a legacy client cannot aggregate, whatever it is given', () {
      const ClientConfig c = ClientConfig(
        rateMbps: 54,
        legacy: true,
        aggregation: 32,
      );
      expect(c.frames, 1);
      expect(airtimeUs(c), airtimeUs(_fast));
    });

    test('payload size feeds the formula', () {
      expect(
        airtimeUs(_fast, payloadBytes: 64),
        closeTo(174.5 + 8 * (64 + 34) / 54, 1e-9),
      );
    });

    test('presets carry their family', () {
      expect(ClientConfig.preset(RatePreset.legacy6).legacy, isTrue);
      expect(ClientConfig.preset(RatePreset.he1201).legacy, isFalse);
      expect(RatePreset.vht867.label, '867 Mbps (VHT)');
    });
  });

  group('fairness', () {
    test('all clients at one rate: packet and airtime fairness agree', () {
      for (final ClientConfig c in <ClientConfig>[
        _fast,
        const ClientConfig(rateMbps: 867, legacy: false, aggregation: 32),
      ]) {
        final List<ClientConfig> cs = List<ClientConfig>.filled(4, c);
        final FairnessResult p = computeFairness(cs, FairnessMode.packet);
        final FairnessResult a = computeFairness(cs, FairnessMode.airtime);
        for (int i = 0; i < cs.length; i++) {
          expect(
            p.clients[i].throughputMbps,
            closeTo(a.clients[i].throughputMbps, 1e-9),
          );
          expect(p.clients[i].airtimeShare, closeTo(0.25, 1e-12));
        }
        expect(p.aggregateMbps, closeTo(a.aggregateMbps, 1e-9));
      }
    });

    test('6 and 54 Mbps: packet fairness gives both the same throughput', () {
      final FairnessResult p = computeFairness(<ClientConfig>[
        _slow,
        _fast,
      ], FairnessMode.packet);
      expect(
        p.clients[0].throughputMbps,
        closeTo(p.clients[1].throughputMbps, 1e-12),
      );
      final double round = airtimeUs(_slow) + airtimeUs(_fast);
      expect(p.clients[0].throughputMbps, closeTo(12000 / round, 1e-12));
      // The slow client holds most of the air.
      expect(p.clients[0].airtimeShare, greaterThan(0.8));
    });

    test('6 and 54 Mbps: airtime fairness ratio equals T_slow / T_fast', () {
      final FairnessResult a = computeFairness(<ClientConfig>[
        _slow,
        _fast,
      ], FairnessMode.airtime);
      final double ratio =
          a.clients[1].throughputMbps / a.clients[0].throughputMbps;
      expect(ratio, closeTo(airtimeUs(_slow) / airtimeUs(_fast), 1e-9));
      expect(a.clients[0].airtimeShare, 0.5);
      expect(a.clients[1].airtimeShare, 0.5);
    });

    test('airtime-fair aggregate >= packet-fair aggregate when rates differ '
        '(equal aggregation)', () {
      final math.Random rng = math.Random(42);
      const List<double> rates = <double>[6, 24, 54, 150, 300, 433, 600, 867];
      for (int trial = 0; trial < 500; trial++) {
        final int n = 2 + rng.nextInt(7);
        final bool legacy = rng.nextBool();
        final int agg = legacy ? 1 : 1 << rng.nextInt(7);
        final List<ClientConfig> cs = <ClientConfig>[
          for (int i = 0; i < n; i++)
            ClientConfig(
              rateMbps: rates[rng.nextInt(rates.length)],
              legacy: legacy,
              aggregation: agg,
            ),
        ];
        final FairnessResult p = computeFairness(cs, FairnessMode.packet);
        final FairnessResult a = computeFairness(cs, FairnessMode.airtime);
        expect(
          a.aggregateMbps,
          greaterThanOrEqualTo(p.aggregateMbps - 1e-9),
          reason: 'trial $trial',
        );
      }
      final FairnessResult p = computeFairness(<ClientConfig>[
        _slow,
        _fast,
      ], FairnessMode.packet);
      final FairnessResult a = computeFairness(<ClientConfig>[
        _slow,
        _fast,
      ], FairnessMode.airtime);
      expect(a.aggregateMbps, greaterThan(p.aggregateMbps));
    });

    test('shares sum to one in both modes', () {
      final List<ClientConfig> cs = <ClientConfig>[
        _slow,
        _fast,
        const ClientConfig(rateMbps: 867, legacy: false, aggregation: 32),
      ];
      for (final FairnessMode m in FairnessMode.values) {
        final double sum = computeFairness(
          cs,
          m,
        ).clients.fold(0, (double s, ClientResult c) => s + c.airtimeShare);
        expect(sum, closeTo(1, 1e-12));
      }
    });

    test('spec defaults: the 6 Mbps client holds over half the air', () {
      final List<ClientConfig> cs = <ClientConfig>[
        for (int i = 0; i < 3; i++)
          ClientConfig.preset(RatePreset.vht867, aggregation: 32),
        ClientConfig.preset(RatePreset.legacy6),
      ];
      final FairnessResult p = computeFairness(cs, FairnessMode.packet);
      final FairnessResult a = computeFairness(cs, FairnessMode.airtime);
      expect(p.clients[3].airtimeShare, closeTo(0.5318, 1e-3));
      expect(p.clients[0].throughputMbps, closeTo(92.0, 0.1));
      expect(a.clients[0].throughputMbps, closeTo(147.4, 0.1));
      expect(a.aggregateMbps, greaterThan(p.aggregateMbps));
    });

    test('rejects an empty cell and a zero rate', () {
      expect(
        () => computeFairness(const <ClientConfig>[], FairnessMode.packet),
        throwsArgumentError,
      );
      expect(
        () => computeFairness(const <ClientConfig>[
          ClientConfig(rateMbps: 0, legacy: true),
        ], FairnessMode.packet),
        throwsArgumentError,
      );
    });
  });

  group('schedule', () {
    test('packet fairness is round robin with blocks back to back', () {
      final List<ClientConfig> cs = <ClientConfig>[_slow, _fast, _fast];
      final List<ScheduledTx> s = buildSchedule(
        cs,
        FairnessMode.packet,
        windowUs: 3 * (airtimeUs(_slow) + 2 * airtimeUs(_fast)),
      );
      expect(s.take(6).map((ScheduledTx t) => t.client), <int>[
        0,
        1,
        2,
        0,
        1,
        2,
      ]);
      for (int i = 1; i < s.length; i++) {
        expect(s[i].startUs, closeTo(s[i - 1].endUs, 1e-9));
      }
    });

    test('airtime fairness evens out time used over the window', () {
      final List<ClientConfig> cs = <ClientConfig>[_slow, _fast];
      final double window = 20 * airtimeUs(_slow);
      final List<ScheduledTx> s = buildSchedule(
        cs,
        FairnessMode.airtime,
        windowUs: window,
      );
      final List<double> used = <double>[0, 0];
      for (final ScheduledTx t in s) {
        used[t.client] += t.durationUs;
      }
      // Within one slow block of each other.
      expect((used[0] - used[1]).abs(), lessThan(airtimeUs(_slow) + 1e-9));
      expect(s.last.endUs, greaterThanOrEqualTo(window));
    });

    test('round window fits a packet round and a full slow turn each', () {
      final List<ClientConfig> cs = <ClientConfig>[_slow, _fast, _fast];
      expect(roundWindowUs(cs), closeTo(3 * airtimeUs(_slow), 1e-9));
      expect(clientLetter(0), 'A');
      expect(clientLetter(7), 'H');
    });
  });
}
