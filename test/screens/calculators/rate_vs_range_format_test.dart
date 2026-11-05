import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_model.dart';
import 'package:wlan_pros_toolbox/units/unit_system.dart';

void main() {
  group('RvrFormat.dist', () {
    test('one decimal below 100 m, so a 19.6 m ring edge does not read as 20 m',
        () {
      expect(RvrFormat.dist(19.6), '19.6 m');
      expect(RvrFormat.dist(20.0), '20.0 m');
      expect(RvrFormat.dist(99.94), '99.9 m');
    });

    test('whole metres from 100 m, km from 1000 m', () {
      expect(RvrFormat.dist(100), '100 m');
      expect(RvrFormat.dist(250.4), '250 m');
      expect(RvrFormat.dist(1500), '1.50 km');
      expect(RvrFormat.dist(0.5), 'under 1 m');
    });

    test('imperial: one decimal below 100 ft', () {
      expect(RvrFormat.dist(10, UnitSystem.imperial), '32.8 ft');
      expect(RvrFormat.dist(40, UnitSystem.imperial), '131 ft');
    });
  });
}
