// Unit tests for the Wi-Fi Classroom Multi-Link Operation model (mlo-simulator).
//
// The spec's "Done means" (myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/
// specs/22-mlo.md): one link makes every mode the single link; two
// identical links make STR no slower than a single link; EMLSR is no faster
// than STR on the same traffic; one much busier link shrinks the win; a seed
// gives the same run every time. Plus the model's own contract: frames never
// overlap other traffic or each other, NSTR ends align, EMLSR pays its
// lead-in and transition delay, the driver fallback, overload, the kernel
// delay values, the lessons, and the numbers the help entry prints.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_state.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_anatomy.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/mlo_model.dart';

const List<MloMode> _mlo = <MloMode>[MloMode.str, MloMode.nstr, MloMode.emlsr];

MloConfig _two(double f5, double f6, {int seed = 1, double rate = 1000}) =>
    MloConfig(
      links: <MloLinkConfig>[
        MloLinkConfig(band: MloBand.ghz5, busyFraction: f5),
        MloLinkConfig(band: MloBand.ghz6, busyFraction: f6),
      ],
      arrivalsPerSecond: rate,
      seed: seed,
    );

void main() {
  group('spec: Done means', () {
    test('with one link, every mode equals single link', () {
      for (final MloBand b in MloBand.values) {
        final MloRun r = simulateMlo(
          MloConfig(
            links: <MloLinkConfig>[MloLinkConfig(band: b, busyFraction: 0.4)],
            airtimeSource: MloAirtimeSource.anatomy,
          ),
        );
        final MloModeResult single = r.singles.single;
        for (final MloMode m in _mlo) {
          final MloModeResult x = r.result(m);
          expect(x.fellBackToSingle, isTrue);
          expect(x.txs.length, single.txs.length);
          for (int i = 0; i < x.txs.length; i++) {
            expect(x.txs[i].startUs, single.txs[i].startUs);
            expect(x.txs[i].endUs, single.txs[i].endUs);
            expect(x.txs[i].leadInUs, 0);
          }
          expect(x.meanUs, single.meanUs);
          expect(x.p99Us, single.p99Us);
          expect(r.worseThanBestSingle(m), isFalse);
        }
      }
    });

    test('two identical links: STR mean <= single-link mean (seeds 1-10)', () {
      for (int seed = 1; seed <= 10; seed++) {
        final MloRun r = simulateMlo(_two(0.5, 0.5, seed: seed));
        final double str = r.result(MloMode.str).meanUs;
        for (final MloModeResult s in r.singles) {
          expect(str, lessThanOrEqualTo(s.meanUs), reason: 'seed $seed');
        }
      }
    });

    test('EMLSR latency >= STR latency on the same traffic', () {
      final List<MloConfig> configs = <MloConfig>[
        _two(0.5, 0.5),
        _two(0.9, 0.3),
        _two(0.1, 0.1, rate: 300),
        _two(0.3, 0.3).copyWith(paddingDelayUs: 0, transitionDelayUs: 0),
        for (final MloPreset p in MloPreset.values) p.config,
        const MloConfig(
          links: <MloLinkConfig>[
            MloLinkConfig(band: MloBand.ghz24),
            MloLinkConfig(band: MloBand.ghz5),
            MloLinkConfig(band: MloBand.ghz6),
          ],
          airtimeSource: MloAirtimeSource.anatomy,
        ),
      ];
      for (final MloConfig c in configs) {
        for (int seed = 1; seed <= 5; seed++) {
          final MloRun r = simulateMlo(c.copyWith(seed: seed));
          expect(
            r.result(MloMode.emlsr).meanUs,
            greaterThanOrEqualTo(r.result(MloMode.str).meanUs),
          );
          expect(
            r.result(MloMode.emlsr).p99Us,
            greaterThanOrEqualTo(r.result(MloMode.str).p99Us),
          );
        }
      }
    });

    test('one link far busier: the win over the best single link shrinks', () {
      for (int seed = 1; seed <= 10; seed++) {
        final MloRun even = simulateMlo(_two(0.3, 0.3, seed: seed));
        final MloRun uneven = simulateMlo(_two(0.9, 0.3, seed: seed));
        final double winEven = 1 - even.ratioToBestSingle(MloMode.str);
        final double winUneven = 1 - uneven.ratioToBestSingle(MloMode.str);
        expect(winUneven, lessThan(winEven), reason: 'seed $seed');
        // And in absolute terms.
        expect(
          uneven.bestSingle.meanUs - uneven.result(MloMode.str).meanUs,
          lessThan(even.bestSingle.meanUs - even.result(MloMode.str).meanUs),
          reason: 'seed $seed',
        );
      }
    });

    test('results are deterministic for a seed', () {
      final MloConfig c = MloPreset.slowLink.config;
      final MloRun a = simulateMlo(c);
      final MloRun b = simulateMlo(c);
      expect(a.arrivalsUs, b.arrivalsUs);
      for (final MloMode m in <MloMode>[MloMode.single, ..._mlo]) {
        expect(a.result(m).sortedLatenciesUs, b.result(m).sortedLatenciesUs);
        expect(a.result(m).linkCounts, b.result(m).linkCounts);
      }
      final MloRun other = simulateMlo(c.copyWith(seed: 2));
      expect(
        other.result(MloMode.str).meanUs,
        isNot(a.result(MloMode.str).meanUs),
      );
    });

    test('a band carries the same traffic whatever else is enabled', () {
      final MloRun one = simulateMlo(
        const MloConfig(
          links: <MloLinkConfig>[MloLinkConfig(band: MloBand.ghz6)],
        ),
      );
      final MloRun two = simulateMlo(const MloConfig());
      // 6 GHz single link is index 0 in one, index 1 in two.
      expect(
        two.singles[1].sortedLatenciesUs,
        one.singles[0].sortedLatenciesUs,
      );
    });
  });

  group('the model', () {
    test('frames never overlap other traffic or each other on a link', () {
      for (final MloPreset p in MloPreset.values) {
        final MloRun r = simulateMlo(p.config);
        for (final MloMode m in <MloMode>[MloMode.single, ..._mlo]) {
          final MloModeResult x = r.result(m);
          for (int k = 0; k < r.linkCount; k++) {
            final List<MloTx> on =
                x.txs.where((MloTx t) => t.link == k).toList()
                  ..sort((MloTx a, MloTx b) => a.startUs.compareTo(b.startUs));
            for (int i = 1; i < on.length; i++) {
              expect(on[i].startUs, greaterThanOrEqualTo(on[i - 1].endUs));
            }
            final List<(double, double)> busy = x.timelines[k].busyIn(
              0,
              r.arrivalsUs.last,
            );
            int j = 0;
            for (final MloTx t in on) {
              while (j < busy.length && busy[j].$2 <= t.startUs) {
                j++;
              }
              if (j < busy.length) {
                // The next busy period starts at or after this frame ends.
                expect(
                  busy[j].$1,
                  greaterThanOrEqualTo(t.endUs - 1e-6),
                  reason: '${p.name} ${m.name} link $k frame ${t.frame}',
                );
              }
            }
          }
        }
      }
    });

    test('no frame is sent before it arrives, and all are sent once', () {
      final MloRun r = simulateMlo(MloPreset.equal.config);
      for (final MloMode m in <MloMode>[MloMode.single, ..._mlo]) {
        final MloModeResult x = r.result(m);
        expect(x.txs.length, r.config.frameCount);
        expect(
          x.txs.map((MloTx t) => t.frame).toSet().length,
          r.config.frameCount,
        );
        for (final MloTx t in x.txs) {
          expect(t.startUs, greaterThanOrEqualTo(t.arrivalUs));
          expect(t.latencyUs, greaterThanOrEqualTo(t.airtimeUs));
        }
      }
    });

    test('NSTR frames sent together start together and end together', () {
      final MloRun r = simulateMlo(MloPreset.slowLink.config);
      final MloModeResult x = r.result(MloMode.nstr);
      final Map<double, List<MloTx>> byStart = <double, List<MloTx>>{};
      for (final MloTx t in x.txs) {
        (byStart[t.startUs] ??= <MloTx>[]).add(t);
      }
      final List<List<MloTx>> pairs = byStart.values
          .where((List<MloTx> g) => g.length > 1)
          .toList();
      expect(pairs, isNotEmpty);
      for (final List<MloTx> g in pairs) {
        expect(g.map((MloTx t) => t.endUs).toSet().length, 1);
        expect(g.map((MloTx t) => t.link).toSet().length, g.length);
        // The shorter one is padded out to the longer.
        final double longest = g
            .map((MloTx t) => t.airtimeUs)
            .reduce((double a, double b) => a > b ? a : b);
        for (final MloTx t in g) {
          expect(t.paddingUs, closeTo(longest - t.airtimeUs, 1e-9));
        }
      }
      // Exchanges never overlap in time.
      final List<double> starts = byStart.keys.toList()..sort();
      for (int i = 1; i < starts.length; i++) {
        expect(
          starts[i],
          greaterThanOrEqualTo(byStart[starts[i - 1]]!.first.endUs),
        );
      }
    });

    test('EMLSR lead-in: RTS + padding + SIFS + CTS + SIFS at 24 Mbps', () {
      // 5 GHz: RTS 20 B and CTS 14 B are 2 OFDM symbols each at 24 Mbps,
      // 20 + 8 = 28 us; SIFS 16 us.
      expect(mloEmlsrLeadInUs(MloBand.ghz5, 0), 28 + 16 + 28 + 16);
      expect(mloEmlsrLeadInUs(MloBand.ghz6, 256), 28 + 256 + 16 + 28 + 16);
      // 2.4 GHz: SIFS 10 us and a 6 us signal extension on each frame.
      expect(mloEmlsrLeadInUs(MloBand.ghz24, 64), 34 + 64 + 10 + 34 + 10);
    });

    test('EMLSR: one exchange at a time, each after the transition delay', () {
      final MloConfig c = MloPreset.equal.config.copyWith(
        paddingDelayUs: 128,
        transitionDelayUs: 256,
      );
      final MloRun r = simulateMlo(c);
      final MloModeResult x = r.result(MloMode.emlsr);
      expect(x.fellBackToSingle, isFalse);
      for (int i = 0; i < x.txs.length; i++) {
        final MloTx t = x.txs[i];
        expect(t.leadInUs, mloEmlsrLeadInUs(c.links[t.link].band, 128));
        if (i > 0) {
          expect(t.startUs, greaterThanOrEqualTo(x.txs[i - 1].endUs + 256));
        }
      }
      expect(x.linkCounts.every((int n) => n > 0), isTrue);
    });

    test('EMLSR disabled by driver: single link on the least busy link', () {
      final MloConfig c = _two(0.6, 0.2).copyWith(emlsrDisabledByDriver: true);
      final MloRun r = simulateMlo(c);
      final MloModeResult x = r.result(MloMode.emlsr);
      expect(mloFallbackLink(c), 1);
      expect(x.fellBackToSingle, isTrue);
      expect(x.singleLink, 1);
      expect(x.sortedLatenciesUs, r.singles[1].sortedLatenciesUs);
      // STR and NSTR are unaffected by the switch.
      final MloRun on = simulateMlo(c.copyWith(emlsrDisabledByDriver: false));
      expect(r.result(MloMode.str).meanUs, on.result(MloMode.str).meanUs);
    });

    test('a load the link cannot carry is flagged as overloaded', () {
      final MloRun r = simulateMlo(
        const MloConfig(
          links: <MloLinkConfig>[
            MloLinkConfig(
              band: MloBand.ghz5,
              busyFraction: 0.95,
              meanBusyUs: 200,
            ),
          ],
          arrivalsPerSecond: 200,
        ),
      );
      expect(r.singles.single.overloaded, isTrue);
      expect(simulateMlo(const MloConfig()).bestSingle.overloaded, isFalse);
    });

    test('a quiet link sends every frame the moment it arrives', () {
      final MloRun r = simulateMlo(
        const MloConfig(
          links: <MloLinkConfig>[
            MloLinkConfig(band: MloBand.ghz6, busyFraction: 0),
          ],
          arrivalsPerSecond: 100,
        ),
      );
      final MloModeResult s = r.singles.single;
      // At 100 frames/s, 300 us frames almost never queue.
      expect(s.percentileUs(50), 300);
      expect(s.timelines.single.busyIn(0, 1e9), isEmpty);
    });

    test('EMLSR delay values are the kernel lists', () {
      expect(kEmlsrPaddingDelaysUs, <int>[0, 32, 64, 128, 256]);
      expect(kEmlsrTransitionDelaysUs, <int>[0, 16, 32, 64, 128, 256]);
    });

    test('Airtime Anatomy airtime follows the band width', () {
      const MloConfig c = MloConfig(
        airtimeSource: MloAirtimeSource.anatomy,
        aggregation: 8,
      );
      final double a24 = mloFrameAirtimeUs(c, MloBand.ghz24);
      final double a5 = mloFrameAirtimeUs(c, MloBand.ghz5);
      final double a6 = mloFrameAirtimeUs(c, MloBand.ghz6);
      expect(a24, greaterThan(a5));
      expect(a5, greaterThan(a6));
      for (final MloBand b in MloBand.values) {
        expect(
          computeAirtime(mloAirtimeScenario(b, 7, 8)).check,
          AirtimeCheck.ok,
        );
      }
    });

    test('histogram counts every value, on a whole-decade range', () {
      final MloRun r = simulateMlo(const MloConfig());
      final List<double> v = r.bestSingle.sortedLatenciesUs;
      final (double lo, double hi) = mloHistogramRange(<List<double>>[v]);
      expect(lo, lessThanOrEqualTo(v.first));
      expect(hi, greaterThanOrEqualTo(v.last));
      final List<int> h = mloLogHistogram(v, lo, hi, 30);
      expect(h.fold<int>(0, (int a, int b) => a + b), v.length);
    });

    test('formatting', () {
      expect(mloFmtUs(240), '240 µs');
      expect(mloFmtUs(1350), '1.35 ms');
      expect(mloFmtUs(12400), '12.4 ms');
      expect(mloFmtUs(1200000), '1.20 s');
      expect(mloFmtTick(100), '100 µs');
      expect(mloFmtTick(1000), '1 ms');
      expect(mloFmtTick(20500), '20.5 ms');
      expect(mloFmtTick(100000), '100 ms');
      expect(mloFmtTick(1e6), '1 s');
    });
  });

  group('lessons', () {
    test('each lesson shows its point on seeds 1-5', () {
      for (int seed = 1; seed <= 5; seed++) {
        MloRun run(MloPreset p) => simulateMlo(p.config.copyWith(seed: seed));
        final MloRun equal = run(MloPreset.equal);
        for (final MloMode m in _mlo) {
          expect(equal.worseThanBestSingle(m), isFalse);
        }
        expect(equal.ratioToBestSingle(MloMode.str), lessThan(0.5));
        final MloRun busy = run(MloPreset.oneBusy);
        expect(
          busy.ratioToBestSingle(MloMode.str),
          greaterThan(equal.ratioToBestSingle(MloMode.str)),
        );
        expect(busy.worseThanBestSingle(MloMode.emlsr), isTrue);
        final MloRun slow = run(MloPreset.slowLink);
        expect(slow.worseThanBestSingle(MloMode.str), isTrue);
        final MloRun cost = run(MloPreset.switchCost);
        expect(cost.worseThanBestSingle(MloMode.emlsr), isTrue);
        expect(cost.worseThanBestSingle(MloMode.str), isFalse);
        for (final MloRun r in <MloRun>[equal, busy, slow, cost]) {
          for (final MloMode m in <MloMode>[MloMode.single, ..._mlo]) {
            expect(r.result(m).overloaded, isFalse);
          }
        }
      }
    });

    test('the numbers the help example prints', () {
      final MloRun eq = simulateMlo(MloPreset.equal.config);
      expect(mloFmtUs(eq.singles[0].meanUs), '2.01 ms');
      expect(mloFmtUs(eq.singles[1].meanUs), '1.74 ms');
      expect(mloFmtUs(eq.result(MloMode.str).meanUs), '583 µs');
      expect(mloFmtUs(eq.result(MloMode.nstr).meanUs), '621 µs');
      expect(mloFmtUs(eq.result(MloMode.emlsr).meanUs), '1.49 ms');
      final MloRun slow = simulateMlo(MloPreset.slowLink.config);
      expect(mloFmtUs(slow.airtimeUs[0]), '794 µs');
      expect(mloFmtUs(slow.airtimeUs[1]), '291 µs');
      expect(mloFmtUs(slow.result(MloMode.str).meanUs), '462 µs');
      expect(mloFmtUs(slow.bestSingle.meanUs), '428 µs');
      expect(slow.bestSingle.singleLink, 1);
    });
  });
}
