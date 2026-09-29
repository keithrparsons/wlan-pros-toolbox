// OFDMA vs MU-MIMO model (spec 47, "Done means"): co-located clients are not
// separable; orthogonal steering (M = 2, half-wave, +-30 deg) loses nothing;
// sounding grows with the client count; the OFDMA side is computeOfdma to
// the tenth of a microsecond. Plus the zero-forcing identities and the four
// scenarios' verdicts, so a change to the model cannot flip a lesson quietly.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/complex.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/mu_mimo_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/ofdma_model.dart';

MuScenario _two(double a, double b, {int m = 2, bool reflection = false}) =>
    MuScenario(
      antennas: m,
      clients: <MuClient>[
        MuClient(angleDeg: a, distanceM: 8),
        MuClient(angleDeg: b, distanceM: 8),
      ],
      reflection: reflection,
    );

MuScenario _spread(int k, {int m = 4, int n = 1, int payload = 1500}) =>
    MuScenario(
      antennas: m,
      clients: <MuClient>[
        for (int i = 0; i < k; i++)
          MuClient(angleDeg: -60 + i * 120 / math.max(1, k - 1), distanceM: 8),
      ],
      payloadBytes: payload,
      exchangesPerSounding: n,
    );

void main() {
  group('zero-forcing', () {
    test('co-located clients (rho = 1) are not separable', () {
      final MuResult r = computeMuVsOfdma(_two(20, 20, m: 4));
      final MuPair p = r.precoding.pairs.single;
      expect(p.correlation, closeTo(1, 1e-9));
      expect(p.separable, isFalse);
      expect(p.lossDb, double.infinity);
      expect(r.precoding.possible, isFalse);
      expect(r.block, MuBlock.singular);
      expect(r.mu, isNull);
      expect(r.winner, MuWinner.muUnavailable);
      // OFDMA still runs.
      expect(r.ofdma, isNotNull);
    });

    test('orthogonal steering, M = 2 at half-wave, +-30 deg: zero loss', () {
      final MuResult r = computeMuVsOfdma(_two(-30, 30));
      final MuPair p = r.precoding.pairs.single;
      expect(p.correlation, closeTo(0, 1e-12));
      expect(p.separable, isTrue);
      for (final double f in r.precoding.factors) {
        expect(f, closeTo(1, 1e-12));
      }
      for (final double l in r.precoding.lossesDb) {
        expect(l, closeTo(0, 1e-9));
      }
      // Array gain 2 exactly repays the split over 2 streams.
      for (final MuClientLink l in r.links) {
        expect(l.muSnrChangeDb, closeTo(0, 1e-9));
        expect(l.muMcs, l.ofdmaMcs);
      }
    });

    test('two clients: the ZF factor is 1 - |rho|^2', () {
      for (final (double, double, int) c in <(double, double, int)>[
        (-10, 25, 2),
        (5, 12, 4),
        (-70, 40, 8),
        (0, 3, 3),
      ]) {
        final MuPrecoding zf = zeroForcing(_two(c.$1, c.$2, m: c.$3));
        final double rho = zf.pairs.single.correlation;
        for (final double f in zf.factors) {
          expect(f, closeTo(1 - rho * rho, 1e-9), reason: '$c');
        }
      }
    });

    test('each ZF beam puts a null on every other client', () {
      for (final bool refl in <bool>[false, true]) {
        final MuScenario s = _spread(4, m: 6);
        final MuScenario sr = MuScenario(
          antennas: s.antennas,
          clients: s.clients,
          reflection: refl,
        );
        final MuPrecoding zf = zeroForcing(sr);
        expect(zf.possible, isTrue);
        for (int i = 0; i < 4; i++) {
          for (int j = 0; j < 4; j++) {
            final double leak = innerH(zf.channels[i], zf.weights![j]).abs;
            if (i == j) {
              expect(leak, greaterThan(0.1));
            } else {
              expect(leak, closeTo(0, 1e-9), reason: 'h$i . w$j refl=$refl');
            }
          }
        }
        // Line of sight: the beam toward another client's angle is a null.
        if (!refl) {
          expect(zf.beamGain(0, s.clients[1].angleDeg), closeTo(0, 1e-12));
          expect(zf.beamGain(0, s.clients[0].angleDeg), greaterThan(0.5));
        }
      }
    });

    test('more clients than antennas: no zero-forcing', () {
      final MuResult r = computeMuVsOfdma(_spread(4, m: 3));
      expect(r.block, MuBlock.tooManyClients);
      expect(r.precoding.possible, isFalse);
      expect(r.mu, isNull);
    });

    test('bunched clients lose more than spread ones', () {
      final double bunched = zeroForcing(_two(10, 16, m: 4)).factors.first;
      final double spread = zeroForcing(_two(-40, 30, m: 4)).factors.first;
      expect(bunched, lessThan(spread));
    });

    test('the reflection changes the channel but ZF still nulls', () {
      final MuPrecoding a = zeroForcing(_two(-20, 25, m: 4));
      final MuPrecoding b = zeroForcing(_two(-20, 25, m: 4, reflection: true));
      expect(
        b.pairs.single.correlation,
        isNot(closeTo(a.pairs.single.correlation, 1e-6)),
      );
      expect(b.possible, isTrue);
    });
  });

  group('complex inverse', () {
    test('A times its inverse is I; a singular matrix returns null', () {
      final List<List<Complex>> a = <List<Complex>>[
        <Complex>[const Complex(2, 1), const Complex(0, -1), const Complex(1)],
        <Complex>[const Complex(0, 1), const Complex(3), const Complex(1, 1)],
        <Complex>[const Complex(1), const Complex(1, -1), const Complex(4, 2)],
      ];
      final List<List<Complex>> inv = invertComplex(a)!;
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          Complex s = Complex.zero;
          for (int k = 0; k < 3; k++) {
            s = s + a[i][k] * inv[k][j];
          }
          expect(s.re, closeTo(i == j ? 1 : 0, 1e-12));
          expect(s.im, closeTo(0, 1e-12));
        }
      }
      expect(
        invertComplex(<List<Complex>>[
          <Complex>[Complex.one, const Complex(2)],
          <Complex>[const Complex(2), const Complex(4)],
        ]),
        isNull,
      );
    });
  });

  group('sounding', () {
    test('grows with the client count', () {
      int prev = 0;
      for (int k = 2; k <= 4; k++) {
        final MuResult r = computeMuVsOfdma(_spread(k));
        expect(r.block, isNull, reason: 'k=$k');
        expect(r.soundingTenths, greaterThan(prev), reason: 'k=$k');
        prev = r.soundingTenths;
        expect(MuSounding.ndpaBytes(k), 21 + 4 * k);
      }
    });

    test('the sounding sequence is NDPA, NDP, BFRP, reports, SIFS apart', () {
      final MuResult r = computeMuVsOfdma(_spread(3));
      final List<String> names = r.mu!.segments
          .map((OfdmaSegment s) => s.shortLabel)
          .take(11)
          .toList();
      expect(names, <String>[
        'AIFS',
        'Backoff',
        'NDPA',
        'SIFS',
        'NDP',
        'SIFS',
        'BFRP',
        'SIFS',
        'Reports',
        'SIFS',
        'Preamble',
      ]);
    });

    test('MU report: MU codebook plus delta SNR, bigger than the SU one', () {
      final MuReportEstimate e = MuReportEstimate(antennas: 4, widthMhz: 80);
      // 996 / 4 + 1 = 250 groups; 4x1 has 6 angles: 3 x (9 + 7) + 4 = 52.
      expect(e.subcarrierGroups, 250);
      expect(e.angles, 6);
      expect(e.bodyBits, 8 + 250 * 52);
      expect(e.bytes, 1626 + 35);
      expect(e.bytes, greaterThan(e.suBytes));
    });

    test('more antennas sound longer (more HE-LTFs in the NDP)', () {
      final int m2 = computeMuVsOfdma(_spread(2, m: 2)).soundingTenths;
      final int m8 = computeMuVsOfdma(_spread(2, m: 8)).soundingTenths;
      expect(m8, greaterThan(m2));
    });

    test('the MU preamble carries one HE-LTF per stream (1, 2, 4, 4)', () {
      const List<int> ltfs = <int>[1, 2, 4, 4];
      for (int k = 1; k <= 4; k++) {
        expect(
          muPreambleTenths(80, k),
          (32 + 4) * 10 + sigBLength(80, k).tenths + ltfs[k - 1] * 72,
          reason: 'k=$k',
        );
      }
    });
  });

  group('the OFDMA side is computeOfdma', () {
    test('one exchange equals computeOfdma to the tenth', () {
      for (final int w in MuLimits.widthsMhz) {
        for (int k = 2; k <= 4; k++) {
          for (final int payload in MuLimits.payloadChoices) {
            final MuScenario s = MuScenario(
              antennas: 4,
              clients: _spread(k).clients,
              widthMhz: w,
              payloadBytes: payload,
              exchangesPerSounding: 1,
            );
            final MuResult r = computeMuVsOfdma(s);
            final OfdmaResult direct = computeOfdma(
              OfdmaScenario(
                widthMhz: w,
                ruSizes: List<RuSize>.filled(k, r.ofdmaRu),
                payloadBytes: payload,
                mcs: r.ofdmaMcs!,
              ),
            );
            expect(r.ofdmaRu, OfdmaTonePlan.largestEqualFit(w, k));
            expect(r.ofdma!.totalTenths, direct.dl!.totalTenths);
            expect(
              r.ofdma!.segments.map((OfdmaSegment x) => x.tenths).toList(),
              direct.dl!.segments.map((OfdmaSegment x) => x.tenths).toList(),
            );
          }
        }
      }
    });

    test('n exchanges are n copies on one clock', () {
      final MuResult one = computeMuVsOfdma(_spread(3));
      final MuResult eight = computeMuVsOfdma(_spread(3, n: 8));
      expect(eight.ofdma!.totalTenths, 8 * one.ofdma!.totalTenths);
      final List<OfdmaSegment> segs = eight.ofdma!.segments;
      for (int i = 1; i < segs.length; i++) {
        expect(segs[i].startTenths, segs[i - 1].endTenths);
      }
    });

    test('MU-MIMO shares the wait, SIFS and block-ack times', () {
      final MuResult r = computeMuVsOfdma(_spread(4));
      int of(OfdmaTimeline t, OfdmaSegmentKind k) =>
          t.segments.firstWhere((OfdmaSegment s) => s.kind == k).tenths;
      for (final OfdmaSegmentKind k in <OfdmaSegmentKind>[
        OfdmaSegmentKind.aifs,
        OfdmaSegmentKind.backoff,
        OfdmaSegmentKind.sifs,
      ]) {
        expect(of(r.mu!, k), of(r.ofdma!, k), reason: '$k');
      }
      expect(
        r.mu!.segments.last.tenths,
        r.ofdma!.segments.last.tenths,
        reason: 'block acks',
      );
    });

    test(
      'the difference is exchanges x (data + preamble saved) - sounding',
      () {
        for (final MuPreset p in MuPreset.values) {
          final MuResult r = computeMuVsOfdma(p.scenario);
          if (r.mu == null) continue;
          expect(
            r.savedTenths,
            r.exchanges *
                    (r.ofdmaDataTenths -
                        r.muDataTenths +
                        r.ofdmaPreambleTenths -
                        r.muPreambleTenthsEach) -
                r.soundingTenths,
            reason: p.label,
          );
          expect(
            r.mu!.segments
                .firstWhere((OfdmaSegment s) => s.shortLabel == 'NDPA')
                .startTenths,
            r.soundingStartTenths,
          );
        }
      },
    );

    test('MU data: every client on the whole channel', () {
      final MuResult r = computeMuVsOfdma(_spread(4));
      expect(r.muDataTenths, lessThan(r.ofdmaDataTenths));
    });
  });

  group('links', () {
    test('a client beyond MCS 0 stops both schemes', () {
      final MuResult r = computeMuVsOfdma(
        MuScenario(
          antennas: 4,
          clients: const <MuClient>[
            MuClient(angleDeg: -30, distanceM: 8),
            MuClient(angleDeg: 30, distanceM: 400),
          ],
        ),
      );
      expect(r.block, MuBlock.outOfRange);
      expect(r.ofdma, isNull);
      expect(r.winner, MuWinner.outOfRange);
    });

    test('MU-MIMO change = 10 log10(M/K) - ZF loss', () {
      final MuResult r = computeMuVsOfdma(_spread(3, m: 8));
      for (int i = 0; i < 3; i++) {
        expect(
          r.links[i].muSnrChangeDb,
          closeTo(10 * math.log(8 / 3) / math.ln10 - r.links[i].zfLossDb, 1e-9),
        );
      }
    });

    test('fromXy clamps to the allowed ring and the front half-plane', () {
      expect(MuClient.fromXy(0, 0.1).distanceM, MuLimits.minDistanceM);
      expect(MuClient.fromXy(100, 100).distanceM, MuLimits.maxDistanceM);
      final MuClient c = MuClient.fromXy(5, -3);
      expect(c.angleDeg, 90);
      const MuClient d = MuClient(angleDeg: 30, distanceM: 10);
      final (double x, double y) = d.xy;
      final MuClient back = MuClient.fromXy(x, y);
      expect(back.angleDeg, closeTo(30, 1e-9));
      expect(back.distanceM, closeTo(10, 1e-9));
    });
  });

  group("Keith's four scenarios", () {
    test('spread out, big frames: MU-MIMO wins', () {
      final MuResult r = computeMuVsOfdma(MuPreset.spreadBig.scenario);
      expect(r.precoding.allSeparable, isTrue);
      expect(r.winner, MuWinner.muMimo);
    });

    test('bunched together: not separable, MU-MIMO cannot decode', () {
      final MuResult r = computeMuVsOfdma(MuPreset.bunched.scenario);
      expect(r.precoding.pairs.where((MuPair p) => !p.separable), isNotEmpty);
      expect(r.block, MuBlock.lossTooHigh);
      expect(r.winner, MuWinner.muUnavailable);
    });

    test('many tiny frames: OFDMA wins; sounding outweighs the data saved', () {
      final MuResult r = computeMuVsOfdma(MuPreset.tinyFrames.scenario);
      expect(r.precoding.allSeparable, isTrue);
      expect(r.winner, MuWinner.ofdma);
      final int saved = (r.ofdmaDataTenths - r.muDataTenths) * r.exchanges;
      expect(r.soundingTenths, greaterThan(saved));
    });

    test('one far client: the far client sets both PPDU lengths', () {
      final MuResult r = computeMuVsOfdma(MuPreset.oneFar.scenario);
      final int far = r.links.indexWhere(
        (MuClientLink l) => l.ofdmaMcs == r.ofdmaMcs,
      );
      expect(r.scenario.clients[far].distanceM, 20);
      expect(r.muDataSymbols.indexOf(r.muDataSymbols.reduce(math.max)), far);
      expect(r.winner, MuWinner.muMimo);
    });

    test('one sounding per exchange hands every scenario to OFDMA', () {
      for (final MuPreset p in MuPreset.values) {
        final MuScenario s = p.scenario;
        final MuResult r = computeMuVsOfdma(
          MuScenario(
            antennas: s.antennas,
            clients: s.clients,
            widthMhz: s.widthMhz,
            payloadBytes: s.payloadBytes,
            exchangesPerSounding: 1,
          ),
        );
        expect(
          r.winner,
          anyOf(MuWinner.ofdma, MuWinner.muUnavailable),
          reason: p.label,
        );
      }
    });
  });
}
