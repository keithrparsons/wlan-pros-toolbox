// Pins the Wi-Fi Classroom Body Loss model (spec 34, "Done means"):
// deterministic with a seed; facing the AP applies near-zero holder loss and
// facing away the full value; crowd loss = per-person loss x people crossing
// the line; empty vs occupied changes only crowd loss; band multipliers
// apply; every loss parameter is labeled illustrative in its UI string.
// Path loss and MCS are pinned against RateVsRangeMath, which the model
// reuses rather than re-derives.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/body_loss_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fspl_math.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_vs_range_math.dart';

/// A config with an explicit crowd, for exact crossing counts.
BlConfig _scene({
  required List<BlPoint> crowd,
  WifiBand band = WifiBand.band24,
  double perPerson = 4,
  bool occupied = true,
}) {
  final List<BlPoint> pool = <BlPoint>[
    ...crowd,
    // Pad to the full pool with people well off the line.
    for (int i = crowd.length; i < BlConfig.maxCrowd; i++)
      BlPoint(3 + (i % 10) * 1.5, 0.6),
  ];
  return BlConfig(
    band: band,
    perPersonLossDb: perPerson,
    crowdSize: crowd.length,
    occupied: occupied,
    holder: const BlPoint(16, 6),
    facingDeg: 270,
    people: pool,
  );
}

void main() {
  group('determinism', () {
    test('the same seed gives the same crowd, a different seed a different '
        'one', () {
      expect(BlConfig(seed: 7).people, BlConfig(seed: 7).people);
      expect(BlConfig(seed: 7).people, isNot(BlConfig(seed: 8).people));
      expect(BlConfig.scatterPeople(11), BlConfig.scatterPeople(11));
    });

    test('scatter moves to the next seed and is repeatable', () {
      final BlConfig a = BlConfig().scatter();
      final BlConfig b = BlConfig().scatter();
      expect(a.seed, BlConfig.defaultSeed + 1);
      expect(a.people, b.people);
      expect(a.people, isNot(BlConfig().people));
    });

    test('every scattered person is on the floor, spaced, and clear of the '
        'AP and the holder', () {
      for (final int seed in <int>[1, 2, 3, 42, 999]) {
        final List<BlPoint> p = BlConfig.scatterPeople(seed);
        expect(p, hasLength(BlConfig.maxCrowd));
        for (int i = 0; i < p.length; i++) {
          expect(p[i].x, inInclusiveRange(0, BlConfig.floorWidthM));
          expect(p[i].y, inInclusiveRange(0, BlConfig.floorDepthM));
          expect(
            p[i].distanceTo(BlConfig.ap),
            greaterThanOrEqualTo(BlConfig.clearanceM),
          );
          expect(
            p[i].distanceTo(BlConfig.defaultHolder),
            greaterThanOrEqualTo(BlConfig.clearanceM),
          );
          for (int j = 0; j < i; j++) {
            expect(
              p[i].distanceTo(p[j]),
              greaterThanOrEqualTo(BlConfig.minSpacingM),
              reason: 'seed $seed, $i vs $j',
            );
          }
        }
      }
    });

    test('the default scene has people on the line (2 of 30, 3 of 50)', () {
      final BlConfig c = BlConfig();
      expect(c.crossingCount, 2);
      expect(c.withCrowdSize(50).crossingCount, 3);
    });
  });

  group('the holder', () {
    test('facing the AP applies zero holder loss; back to it applies the '
        'full value', () {
      for (final WifiBand b in WifiBand.values) {
        final BlConfig c = BlConfig(band: b);
        expect(c.facingAp().holderShare, 0);
        expect(c.facingAp().holderLossAppliedDb, 0);
        expect(c.backToAp().holderShare, closeTo(1, 1e-12));
        expect(
          c.backToAp().holderLossAppliedDb,
          closeTo(c.holderLossDb * c.multiplierFor(b), 1e-9),
        );
      }
    });

    test('near-zero within a few degrees of facing the AP, and exactly zero '
        'side-on', () {
      final BlConfig c = BlConfig().facingAp();
      expect(c.rotatedBy(10).holderLossAppliedDb, 0);
      expect(c.rotatedBy(-10).holderLossAppliedDb, 0);
      expect(c.rotatedBy(90).holderLossAppliedDb, 0);
      expect(c.rotatedBy(-90).holderLossAppliedDb, 0);
    });

    test('the raised-cosine ramp over 60 degrees either side of back-on', () {
      final BlConfig back = BlConfig(band: WifiBand.band24).backToAp();
      for (final double beta in <double>[0, 15, 30, 45, 59, 60, 75]) {
        final double expected = beta >= 60
            ? 0
            : 0.5 * (1 + math.cos(math.pi * beta / 60));
        expect(
          back.rotatedBy(beta).holderShare,
          closeTo(expected, 1e-9),
          reason: 'beta $beta',
        );
        expect(
          back.rotatedBy(-beta).holderShare,
          closeTo(expected, 1e-9),
          reason: 'beta -$beta',
        );
      }
      expect(back.rotatedBy(30).holderLossAppliedDb, closeTo(4, 1e-9));
    });

    test('off-axis angle is 0 facing the AP and 180 back to it', () {
      expect(BlConfig().facingAp().offAxisDeg, closeTo(0, 1e-9));
      expect(BlConfig().backToAp().offAxisDeg, closeTo(180, 1e-9));
      expect(
        BlConfig().facingAp().rotatedBy(-100).offAxisDeg,
        closeTo(100, 1e-9),
      );
    });

    test('bearings are compass: 0 up, 90 right', () {
      const BlPoint o = BlPoint(5, 5);
      expect(BlConfig.bearingDeg(o, const BlPoint(5, 1)), closeTo(0, 1e-9));
      expect(BlConfig.bearingDeg(o, const BlPoint(9, 5)), closeTo(90, 1e-9));
      expect(BlConfig.bearingDeg(o, const BlPoint(5, 9)), closeTo(180, 1e-9));
      expect(BlConfig.bearingDeg(o, const BlPoint(1, 5)), closeTo(270, 1e-9));
    });

    test('the device is held 0.3 m in front of the body', () {
      final BlConfig c = BlConfig(holder: const BlPoint(10, 6), facingDeg: 90);
      expect(c.device.x, closeTo(10.3, 1e-9));
      expect(c.device.y, closeTo(6, 1e-9));
    });
  });

  group('the crowd', () {
    test('crowd loss = per-person loss x people crossing the line', () {
      // The line runs from the AP (1.5, 6) to the device (15.7, 6).
      final BlConfig c = _scene(
        crowd: const <BlPoint>[
          BlPoint(5, 6), // on the line
          BlPoint(9, 6.2), // on the line (0.2 m off, inside 0.25)
          BlPoint(12, 5.8), // on the line
          BlPoint(7, 7.5), // off
          BlPoint(10, 4), // off
        ],
      );
      expect(c.crossingCount, 3);
      expect(c.crossingIndexes, <int>[0, 1, 2]);
      expect(c.crowdLossDb, closeTo(4 * 3, 1e-9));
      for (final double pp in <double>[0, 2.5, 10]) {
        final BlConfig d = c.withPerPersonLoss(pp);
        expect(d.crowdLossDb, closeTo(pp * d.crossingCount, 1e-9));
      }
    });

    test('a body just beyond half its width misses the line; people past '
        'the device do not count', () {
      final BlConfig c = _scene(
        crowd: const <BlPoint>[
          BlPoint(8, 6.26), // 0.26 m off: misses
          BlPoint(8, 6.24), // 0.24 m off: crosses
          BlPoint(18, 6), // beyond the device, on the extended line
          BlPoint(0.6, 6), // behind the AP
        ],
      );
      expect(c.crossingIndexes, <int>[1]);
    });

    test('only the first crowdSize people are in the room', () {
      final BlConfig c = _scene(
        crowd: const <BlPoint>[BlPoint(5, 6), BlPoint(9, 6)],
      );
      expect(c.withCrowdSize(1).crossingCount, 1);
      expect(c.withCrowdSize(0).crossingCount, 0);
      expect(c.withCrowdSize(0).crowdLossDb, 0);
    });

    test('empty vs occupied changes only the crowd loss', () {
      final BlConfig occ = BlConfig().backToAp().rotatedBy(20);
      final BlConfig emp = occ.withOccupied(false);
      expect(occ.crowdLossDb, greaterThan(0));
      expect(emp.crowdLossDb, 0);
      expect(emp.holderLossAppliedDb, occ.holderLossAppliedDb);
      expect(emp.clearDbm, occ.clearDbm);
      expect(emp.pathLossDb, occ.pathLossDb);
      expect(emp.distanceM, occ.distanceM);
      expect(emp.people, occ.people);
      expect(emp.crossingCount, occ.crossingCount);
      expect(emp.receivedDbm - occ.receivedDbm, closeTo(occ.crowdLossDb, 1e-9));
      expect(occ.emptyVsOccupiedDb, closeTo(occ.crowdLossDb, 1e-9));
      expect(emp.emptyVsOccupiedDb, closeTo(occ.crowdLossDb, 1e-9));
      expect(occ.toggleOccupied().occupied, isFalse);
    });

    test('moving one person moves only that person, clamped to the floor', () {
      final BlConfig c = BlConfig();
      final BlConfig d = c.withPerson(4, const BlPoint(100, -3));
      expect(d.people[4].x, closeTo(BlConfig.floorWidthM - 0.3, 1e-9));
      expect(d.people[4].y, closeTo(0.3, 1e-9));
      for (int i = 0; i < c.people.length; i++) {
        if (i != 4) expect(d.people[i], c.people[i]);
      }
      expect(c.withPerson(99, const BlPoint(1, 1)).people, c.people);
    });
  });

  group('the band', () {
    test('band multipliers apply to the holder and the crowd', () {
      final BlConfig base = _scene(
        crowd: const <BlPoint>[BlPoint(5, 6), BlPoint(9, 6)],
      ).withHolderLoss(10).backToAp();
      final Map<WifiBand, double> mult = <WifiBand, double>{
        WifiBand.band24: 1.0,
        WifiBand.band5: 1.2,
        WifiBand.band6: 1.3,
      };
      for (final MapEntry<WifiBand, double> e in mult.entries) {
        final BlConfig c = base.withBand(e.key);
        expect(c.multiplier, e.value);
        expect(c.holderLossAppliedDb, closeTo(10 * e.value, 1e-9));
        expect(c.crowdLossDb, closeTo(4 * e.value * 2, 1e-9));
      }
    });

    test('the 5 and 6 GHz multipliers are settings, clamped to 1 to 2', () {
      final BlConfig c = BlConfig(band: WifiBand.band6).withMultiplier6(1.8);
      expect(c.multiplier, 1.8);
      expect(c.withMultiplier6(5).multiplier6, 2);
      expect(c.withMultiplier5(0).multiplier5, 1);
      expect(c.withBand(WifiBand.band24).multiplier, 1);
    });

    test('higher bands lose more to the body at the defaults', () {
      final BlConfig c = BlConfig();
      expect(
        c.fullHolderLossAt(WifiBand.band5),
        greaterThan(c.fullHolderLossAt(WifiBand.band24)),
      );
      expect(
        c.fullHolderLossAt(WifiBand.band6),
        greaterThan(c.fullHolderLossAt(WifiBand.band5)),
      );
    });
  });

  group('settings', () {
    test('the illustrative defaults of spec 34', () {
      final BlConfig c = BlConfig();
      expect(c.holderLossDb, 8);
      expect(c.perPersonLossDb, 4);
      expect(c.multiplier5, 1.2);
      expect(c.multiplier6, 1.3);
      expect(BlConfig.holderLossMax, 20);
      expect(BlConfig.perPersonLossMax, 10);
      expect(BlConfig.maxCrowd, 50);
      expect(BlConfig.rampHalfWidthDeg, 60);
    });

    test('every setter clamps and ignores non-finite input', () {
      final BlConfig c = BlConfig();
      expect(c.withHolderLoss(99).holderLossDb, 20);
      expect(c.withHolderLoss(-1).holderLossDb, 0);
      expect(c.withHolderLoss(double.nan).holderLossDb, 8);
      expect(c.withPerPersonLoss(11).perPersonLossDb, 10);
      expect(c.withPerPersonLoss(double.infinity).perPersonLossDb, 4);
      expect(c.withCrowdSize(80).crowdSize, 50);
      expect(c.withCrowdSize(-2).crowdSize, 0);
      expect(c.withFacing(-90).facingDeg, 270);
      expect(c.withFacing(720).facingDeg, 0);
      expect(c.withFacing(double.nan).facingDeg, c.facingDeg);
      expect(
        c.withHolder(const BlPoint(-5, 50)).holder,
        const BlPoint(0.3, 11.7),
      );
    });

    test('reset returns to the defaults', () {
      final BlConfig c = BlConfig()
          .withBand(WifiBand.band6)
          .withHolderLoss(15)
          .withOccupied(false)
          .scatter()
          .rotatedBy(45);
      final BlConfig r = c.reset();
      expect(r.band, WifiBand.band5);
      expect(r.holderLossDb, 8);
      expect(r.occupied, isTrue);
      expect(r.seed, BlConfig.defaultSeed);
      expect(r.facingDeg, BlConfig.defaultFacingDeg);
      expect(r.people, BlConfig().people);
    });
  });

  group('the link reuses Rate vs Range', () {
    test('path loss is FsplMath.logDistanceDb at n = 3', () {
      final BlConfig c = BlConfig();
      expect(
        c.pathLossDb,
        closeTo(FsplMath.logDistanceDb(c.distanceM, c.freqMHz, 3), 1e-9),
      );
      expect(c.freqMHz, 5500);
      expect(BlConfig(band: WifiBand.band24).freqMHz, 2437);
      expect(BlConfig(band: WifiBand.band6).freqMHz, 6135);
    });

    test('received = 20 dBm - path loss - holder - crowd; MCS from the '
        'Rate vs Range table at 20 MHz', () {
      final BlConfig c = BlConfig().backToAp();
      expect(
        c.receivedDbm,
        closeTo(
          20 - c.pathLossDb - c.holderLossAppliedDb - c.crowdLossDb,
          1e-9,
        ),
      );
      expect(c.mcs, RateVsRangeMath.mcsFor(c.receivedDbm, 20));
      expect(c.mcsEmpty, RateVsRangeMath.mcsFor(c.emptyDbm, 20));
    });

    test('the default scene, as the help example states it', () {
      final BlConfig c = BlConfig();
      expect(BlFormat.dist(c.distanceM), '14 m');
      expect(BlFormat.dbm(c.clearDbm), '-61.8 dBm');
      expect(BlFormat.dbm(c.emptyDbm), '-61.8 dBm');
      expect(c.mcsEmpty, 7);
      expect(c.crossingCount, 2);
      expect(BlFormat.db(c.crowdLossDb), '9.6 dB');
      expect(BlFormat.dbm(c.receivedDbm), '-71.4 dBm');
      expect(c.mcs, 3);
      final BlConfig back = c.backToAp();
      expect(back.crossingCount, 2);
      expect(BlFormat.db(back.holderLossAppliedDb), '9.6 dB');
      expect(BlFormat.dbm(back.receivedDbm), '-81.6 dBm');
      expect(back.mcs, 0);
      expect(BlFormat.dbm(back.emptyDbm), '-72.0 dBm');
      expect(back.mcsEmpty, 3);
    });
  });

  group('labels', () {
    test('every loss parameter is labeled illustrative in its UI string', () {
      for (final String l in BlLabels.all) {
        expect(l.toLowerCase(), contains('illustrative'), reason: l);
      }
      expect(BlLabels.holderLoss, contains('Holder body loss'));
      expect(BlLabels.perPersonLoss, contains('per person'));
      expect(BlLabels.multiplier5, contains('5 GHz'));
      expect(BlLabels.multiplier6, contains('6 GHz'));
    });

    test('formatting', () {
      expect(BlFormat.mcs(null), 'below MCS 0');
      expect(BlFormat.people(1), '1 person');
      expect(BlFormat.people(3), '3 people');
      expect(BlFormat.deg(359.6), '0°');
      expect(BlFormat.n(-0.04), '0.0');
    });
  });
}
