// Tests for the Unit Converter math model (lib/data/unit_conversion.dart).
//
// Representative conversions per category, with special attention to the two
// correctness traps the brief flagged: decimal-vs-binary storage/rate units
// (a KB is 1000 bytes; a KiB is 1024 bytes) and the non-linear power (dBm) and
// temperature (affine) conversions. Pure math — no widget pump.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/unit_conversion.dart';

/// Find a unit by id within a category (test convenience).
Unit _u(UnitCategory cat, String id) =>
    UnitConversion.unitsFor(cat).firstWhere((Unit u) => u.id == id);

double _conv(UnitCategory cat, String from, String to, double v) =>
    UnitConversion.convert(v, cat, _u(cat, from), _u(cat, to));

void main() {
  group('Data transfer rate (decimal SI; networking convention)', () {
    test('1 Mbps = 1,000,000 bps (powers of 1000, not 1024)', () {
      expect(_conv(UnitCategory.dataRate, 'mbps', 'bps', 1), closeTo(1e6, 1e-6));
    });
    test('1 Gbps = 1000 Mbps', () {
      expect(
        _conv(UnitCategory.dataRate, 'gbps', 'mbps', 1),
        closeTo(1000, 1e-9),
      );
    });
    test('1 MB/s = 8 Mbps (byte-rate ×8)', () {
      expect(
        _conv(UnitCategory.dataRate, 'mBps', 'mbps', 1),
        closeTo(8, 1e-9),
      );
    });
    test('Ethernet preset 1000BASE-T = 1000 Mbps', () {
      expect(
        _conv(UnitCategory.dataRate, 'eth1000', 'mbps', 1),
        closeTo(1000, 1e-9),
      );
    });
    test('Ethernet preset 2.5GBASE-T = 2500 Mbps', () {
      expect(
        _conv(UnitCategory.dataRate, 'eth2g5', 'mbps', 1),
        closeTo(2500, 1e-6),
      );
    });
    test('Ethernet preset 10GBASE-T = 10 Gbps', () {
      expect(
        _conv(UnitCategory.dataRate, 'eth10g', 'gbps', 1),
        closeTo(10, 1e-9),
      );
    });
  });

  group('Data storage (decimal vs binary — the brief\'s key trap)', () {
    test('1 byte = 8 bits', () {
      expect(_conv(UnitCategory.dataStorage, 'byte', 'bit', 1), 8);
    });
    test('1 KB = 1000 bytes (DECIMAL, SI)', () {
      expect(
        _conv(UnitCategory.dataStorage, 'kb', 'byte', 1),
        closeTo(1000, 1e-9),
      );
    });
    test('1 KiB = 1024 bytes (BINARY, IEC) — NOT 1000', () {
      expect(
        _conv(UnitCategory.dataStorage, 'kib', 'byte', 1),
        closeTo(1024, 1e-9),
      );
    });
    test('1 MiB = 1,048,576 bytes (1024^2)', () {
      expect(
        _conv(UnitCategory.dataStorage, 'mib', 'byte', 1),
        closeTo(1048576, 1e-3),
      );
    });
    test('1 GiB = 1,073,741,824 bytes (1024^3)', () {
      expect(
        _conv(UnitCategory.dataStorage, 'gib', 'byte', 1),
        closeTo(1073741824, 1),
      );
    });
    test('1 GiB ≈ 1.073741824 GB (binary > decimal)', () {
      expect(
        _conv(UnitCategory.dataStorage, 'gib', 'gb', 1),
        closeTo(1.073741824, 1e-9),
      );
    });
    test('1 TB = 1e12 bytes (decimal)', () {
      expect(
        _conv(UnitCategory.dataStorage, 'tb', 'byte', 1),
        closeTo(1e12, 1),
      );
    });
  });

  group('Length (matches the metric-conversion factors)', () {
    test('1 mi = 1609.344 m', () {
      expect(
        _conv(UnitCategory.length, 'mi', 'm', 1),
        closeTo(1609.344, 1e-9),
      );
    });
    test('1 ft = 0.3048 m', () {
      expect(
        _conv(UnitCategory.length, 'ft', 'm', 1),
        closeTo(0.3048, 1e-12),
      );
    });
    test('1 nmi = 1852 m', () {
      expect(_conv(UnitCategory.length, 'nmi', 'm', 1), closeTo(1852, 1e-9));
    });
    test('1 in = 2.54 cm', () {
      expect(_conv(UnitCategory.length, 'in', 'cm', 1), closeTo(2.54, 1e-9));
    });
  });

  group('Power (dBm is non-linear — reuses the dBm/Watt math)', () {
    test('0 dBm = 1 mW', () {
      expect(_conv(UnitCategory.power, 'dbm', 'mw', 0), closeTo(1, 1e-9));
    });
    test('30 dBm = 1 W', () {
      expect(_conv(UnitCategory.power, 'dbm', 'w', 30), closeTo(1, 1e-9));
    });
    test('20 dBm = 100 mW', () {
      expect(_conv(UnitCategory.power, 'dbm', 'mw', 20), closeTo(100, 1e-9));
    });
    test('1 W = 30 dBm (round-trip)', () {
      expect(_conv(UnitCategory.power, 'w', 'dbm', 1), closeTo(30, 1e-9));
    });
    test('1 W = 1000 mW (linear members)', () {
      expect(_conv(UnitCategory.power, 'w', 'mw', 1), closeTo(1000, 1e-9));
    });
    test('1 kW = 1000 W', () {
      expect(_conv(UnitCategory.power, 'kw', 'w', 1), closeTo(1000, 1e-9));
    });
    test('0 W → dBm is NaN (log undefined), surfaced as "—"', () {
      final double r = _conv(UnitCategory.power, 'w', 'dbm', 0);
      expect(r.isNaN, isTrue);
      expect(UnitConversion.formatResult(r), '—');
    });
  });

  group('Metric prefix (pico→tera)', () {
    test('1 mega = 1,000,000 base', () {
      expect(
        _conv(UnitCategory.metricPrefix, 'mega', 'base', 1),
        closeTo(1e6, 1e-6),
      );
    });
    test('1 kilo = 1000 base', () {
      expect(
        _conv(UnitCategory.metricPrefix, 'kilo', 'base', 1),
        closeTo(1000, 1e-9),
      );
    });
    test('1 giga = 1000 mega', () {
      expect(
        _conv(UnitCategory.metricPrefix, 'giga', 'mega', 1),
        closeTo(1000, 1e-9),
      );
    });
    test('1 base = 1e12 pico', () {
      expect(
        _conv(UnitCategory.metricPrefix, 'base', 'pico', 1),
        closeTo(1e12, 1),
      );
    });
  });

  group('Speed', () {
    test('1 m/s = 3.6 km/h', () {
      expect(_conv(UnitCategory.speed, 'mps', 'kmh', 1), closeTo(3.6, 1e-9));
    });
    test('1 mph ≈ 1.609344 km/h', () {
      expect(
        _conv(UnitCategory.speed, 'mph', 'kmh', 1),
        closeTo(1.609344, 1e-9),
      );
    });
    test('1 knot = 1.852 km/h', () {
      expect(_conv(UnitCategory.speed, 'knot', 'kmh', 1), closeTo(1.852, 1e-9));
    });
  });

  group('Temperature (affine, not multiplicative)', () {
    test('0 °C = 32 °F', () {
      expect(_conv(UnitCategory.temperature, 'c', 'f', 0), closeTo(32, 1e-9));
    });
    test('100 °C = 212 °F', () {
      expect(
        _conv(UnitCategory.temperature, 'c', 'f', 100),
        closeTo(212, 1e-9),
      );
    });
    test('0 °C = 273.15 K', () {
      expect(
        _conv(UnitCategory.temperature, 'c', 'k', 0),
        closeTo(273.15, 1e-9),
      );
    });
    test('-40 °C = -40 °F (the crossover)', () {
      expect(
        _conv(UnitCategory.temperature, 'c', 'f', -40),
        closeTo(-40, 1e-9),
      );
    });
    test('98.6 °F = 37 °C', () {
      expect(
        _conv(UnitCategory.temperature, 'f', 'c', 98.6),
        closeTo(37, 1e-9),
      );
    });
  });

  group('Time', () {
    test('1 min = 60 s', () {
      expect(_conv(UnitCategory.time, 'min', 's', 1), closeTo(60, 1e-9));
    });
    test('1 hr = 3600 s', () {
      expect(_conv(UnitCategory.time, 'hr', 's', 1), closeTo(3600, 1e-9));
    });
    test('1 day = 86400 s', () {
      expect(_conv(UnitCategory.time, 'day', 's', 1), closeTo(86400, 1e-9));
    });
    test('1 s = 1000 ms', () {
      expect(_conv(UnitCategory.time, 's', 'ms', 1), closeTo(1000, 1e-9));
    });
  });

  group('Identities and formatting', () {
    test('same-unit conversion is the identity for every linear category', () {
      for (final UnitCategory cat in UnitCategory.values) {
        if (cat == UnitCategory.temperature || cat == UnitCategory.power) {
          continue; // covered by their own round-trips
        }
        for (final Unit u in UnitConversion.unitsFor(cat)) {
          expect(
            UnitConversion.convert(7.5, cat, u, u),
            closeTo(7.5, 1e-6),
            reason: '${cat.name}/${u.id}',
          );
        }
      }
    });

    test('formatResult: non-finite → dash, zero → 0, trims trailing zeros', () {
      expect(UnitConversion.formatResult(double.nan), '—');
      expect(UnitConversion.formatResult(double.infinity), '—');
      expect(UnitConversion.formatResult(0), '0');
      expect(UnitConversion.formatResult(100.0), '100');
      expect(UnitConversion.formatResult(2.54), '2.54');
    });

    test('formatResult: very small / very large → scientific', () {
      expect(UnitConversion.formatResult(1e-10), contains('e'));
      expect(UnitConversion.formatResult(5e13), contains('e'));
    });

    test('every category exposes at least two units', () {
      for (final UnitCategory cat in UnitCategory.values) {
        expect(
          UnitConversion.unitsFor(cat).length,
          greaterThanOrEqualTo(2),
          reason: cat.name,
        );
      }
    });
  });
}
