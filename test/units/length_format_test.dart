// The shared metric / imperial formatter and converter (Keith, 2026-09-27).
// Every Classroom tool formats lengths through LengthFormat, so these pin
// the conversions, the round trips and the rounding rules once.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/units/length_format.dart';
import 'package:wlan_pros_toolbox/units/unit_system.dart';

void main() {
  const LengthFormat metric = LengthFormat(UnitSystem.metric);
  const LengthFormat imperial = LengthFormat(UnitSystem.imperial);

  group('constants and converters', () {
    test('international foot, inch and mile are exact', () {
      expect(LengthUnits.feetToMetres(1), 0.3048);
      expect(LengthUnits.inchesToMetres(1), 0.0254);
      expect(LengthUnits.metresPerMile, 1609.344);
      expect(LengthUnits.inchesToCm(1), closeTo(2.54, 1e-12));
    });

    test('distance round trips in both systems', () {
      for (final double m in <double>[0.3, 1, 10, 33.3, 100, 1000]) {
        expect(metric.distToMetres(metric.distValue(m)), closeTo(m, 1e-9));
        expect(imperial.distToMetres(imperial.distValue(m)), closeTo(m, 1e-9));
      }
    });

    test('small lengths round trip through mm exactly', () {
      expect(metric.smallToMm(2.6), 26);
      expect(metric.smallToMm(1.27), 12.7);
      expect(metric.smallValueFromMm(102), closeTo(10.2, 1e-12));
      expect(imperial.smallToMm(4), closeTo(101.6, 1e-9));
      expect(imperial.smallValueFromMm(25.4), closeTo(1, 1e-12));
      for (final double mm in <double>[1, 12.7, 102, 500]) {
        expect(
          imperial.smallToMm(imperial.smallValueFromMm(mm)),
          closeTo(mm, 1e-6),
        );
      }
    });
  });

  group('rounding', () {
    test('distance: a tenth under 10 in the unit on screen, else whole', () {
      expect(metric.dist(3.24), '3.2 m');
      expect(metric.dist(12.4), '12 m');
      expect(imperial.dist(1), '3.3 ft');
      expect(imperial.dist(10), '33 ft');
      expect(imperial.dist(0.9144), '3 ft'); // trailing .0 dropped
      expect(metric.dist(20, decimals: 1, keepZeros: true), '20.0 m');
    });

    test('long distances switch to km and mi', () {
      expect(metric.distLong(999), '999 m');
      expect(metric.distLong(1500), '1.5 km');
      expect(imperial.distLong(1000), '3281 ft');
      expect(imperial.distLong(1609.344), '1 mi');
    });

    test('wall thickness: cm in metric, inches in imperial', () {
      expect(metric.smallFromMm(102), '10.2 cm');
      expect(metric.smallFromMm(500), '50 cm');
      expect(metric.smallFromMm(1), '0.1 cm');
      expect(metric.smallFromMm(12.7), '1.27 cm'); // the old 12.7 mm precision
      expect(imperial.smallFromMm(102), '4 in');
      expect(imperial.smallFromMm(500), '19.7 in');
      expect(imperial.smallFromMm(1), '0.04 in');
    });

    test('snapMm lands on what the readout prints', () {
      expect(metric.snapMm(102.4), 102);
      expect(metric.snapMm(12.74), 12.7);
      expect(imperial.snapMm(101), closeTo(101.6, 1e-9)); // 4.0 in
      expect(imperial.smallFromMm(imperial.snapMm(137)), '5.4 in');
    });

    test('speed and spoken units', () {
      expect(metric.speed(1.4), '1.4 m/s');
      expect(imperial.speed(1.4), '4.6 ft/s');
      expect(metric.distSpoken(5), '5 meters');
      expect(imperial.smallSpokenFromMm(254), '10 inches');
    });

    test('ring labels are round in the unit on screen', () {
      expect(metric.ring(50, rangeM: 100), '50 m');
      expect(metric.ring(1500, rangeM: 3000), '1.5 km');
      expect(
        imperial.ring(LengthUnits.feetToMetres(150), rangeM: 91.44),
        '150 ft',
      );
      expect(imperial.ring(1609.344 / 2, rangeM: 1609.344), '0.5 mi');
    });
  });

  group('NiceTicks', () {
    test('steps are 1, 2, 2.5 or 5 times a power of ten', () {
      expect(NiceTicks.step(100), 20);
      expect(NiceTicks.step(1000), 200);
      expect(NiceTicks.step(300), 50);
      expect(NiceTicks.step(196.85, target: 6), 25);
    });

    test('imperial ticks on a 100 m span are round feet', () {
      final List<double> ft = NiceTicks.between(
        0,
        imperial.distValue(100),
        target: 6,
      );
      expect(ft, <double>[0, 50, 100, 150, 200, 250, 300]);
    });

    test('view ranges pick round feet that halve to round feet', () {
      final double r = NiceTicks.viewRange(70, UnitSystem.imperial, <double>[
        80,
        100,
      ]);
      expect(LengthUnits.metresToFeet(r), closeTo(300, 1e-9));
      expect(NiceTicks.viewRange(70, UnitSystem.metric, <double>[80, 100]), 80);
    });
  });
}
