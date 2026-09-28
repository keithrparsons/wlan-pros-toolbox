// LengthFormat — the ONE place a Classroom tool turns an SI length into text,
// turns typed text back into SI, and picks round axis ticks.
//
// Models stay in SI (metres, or millimetres where a model already stores
// them). Conversion happens only here, at display and at input, so no tool
// rolls its own feet or inches.
//
// Quantities and their display units:
//   distance   m        | ft      (long ranges: km | mi)
//   height     m        | ft      (same rules as distance)
//   small      cm       | in      (wall and material thickness, wavelength,
//                                   device spacing, rulers)
//   speed      m/s      | ft/s
//
// Radio units (dB, dBm, dBi, MHz, GHz, Mb/s, µs) never pass through here.
//
// Rounding (Keith's rulings are the metric column; imperial mirrors them on
// the displayed number, not on the SI value):
//   distance   under 10 in the displayed unit: one decimal; else whole
//   small      under 2: two decimals; under 100: one decimal; else whole
//              (the wall's old mm rule, a decimal below 20 mm, in cm)
//   trailing ".0" / ".00" is kept only when [keepZeros] asks for it, so a
//   readout column does not jitter between "10 m" and "10.5 m" widths.

import 'dart:math' as math;

import 'unit_system.dart';

/// Exact conversion constants (international foot and inch, 1959).
abstract final class LengthUnits {
  static const double metresPerFoot = 0.3048;
  static const double metresPerInch = 0.0254;
  static const double metresPerMile = 1609.344;
  static const double feetPerMile = 5280;

  static double metresToFeet(double m) => m / metresPerFoot;
  static double feetToMetres(double ft) => ft * metresPerFoot;
  static double metresToInches(double m) => m / metresPerInch;
  static double inchesToMetres(double inch) => inch * metresPerInch;
  static double cmToInches(double cm) => cm / 2.54;
  static double inchesToCm(double inch) => inch * 2.54;
}

/// Formats and parses lengths for one [UnitSystem]. Cheap; build one per
/// frame or per call.
class LengthFormat {
  const LengthFormat(this.system);

  final UnitSystem system;

  bool get isMetric => system.isMetric;

  // ── Distance and height: m | ft ────────────────────────────────────────

  /// Unit symbol for distances.
  String get distUnit => isMetric ? 'm' : 'ft';

  /// Spoken unit for distances, for screen readers.
  String get distUnitSpoken => isMetric ? 'meters' : 'feet';

  /// Metres to the displayed number.
  double distValue(double metres) =>
      isMetric ? metres : LengthUnits.metresToFeet(metres);

  /// A displayed (typed) number back to metres.
  double distToMetres(double shown) =>
      isMetric ? shown : LengthUnits.feetToMetres(shown);

  /// The number alone, rounded per the distance rule (or [decimals]).
  String distNumber(double metres, {int? decimals, bool keepZeros = false}) {
    final double v = distValue(metres);
    return _num(v, decimals ?? (v.abs() < 10 ? 1 : 0), keepZeros);
  }

  /// "12 m" / "39 ft". [decimals] overrides the automatic rule.
  String dist(double metres, {int? decimals, bool keepZeros = false}) =>
      '${distNumber(metres, decimals: decimals, keepZeros: keepZeros)} '
      '$distUnit';

  /// "12 meters" / "39 feet", for semantics.
  String distSpoken(double metres, {int? decimals}) =>
      '${distNumber(metres, decimals: decimals)} $distUnitSpoken';

  /// A distance that may be long: km or mi once it reaches one of them,
  /// otherwise [dist].
  String distLong(double metres, {int? decimals}) {
    if (isMetric) {
      if (metres.abs() >= 1000) {
        final double km = metres / 1000;
        return '${_num(km, decimals ?? (km < 10 ? 1 : 0), false)} km';
      }
      return dist(metres, decimals: decimals);
    }
    if (metres.abs() >= LengthUnits.metresPerMile) {
      final double mi = metres / LengthUnits.metresPerMile;
      return '${_num(mi, decimals ?? (mi < 10 ? 1 : 0), false)} mi';
    }
    return dist(metres, decimals: decimals);
  }

  /// A range-circle label, round in the unit on screen: whole m, or km from
  /// 1 km; whole ft, or mi once the view ([rangeM]) reaches half a mile.
  /// Pairs with [NiceTicks.halvingRangesFt].
  String ring(double metres, {required double rangeM}) {
    if (isMetric) {
      return metres >= 1000
          ? '${(metres / 1000).toStringAsFixed(metres % 1000 == 0 ? 0 : 1)} km'
          : '${metres.round()} m';
    }
    if (rangeM >= LengthUnits.metresPerMile / 2 - 1e-6) {
      return '${_num(metres / LengthUnits.metresPerMile, 2, false)} mi';
    }
    return '${LengthUnits.metresToFeet(metres).round()} ft';
  }

  /// Heights follow the distance rules.
  String height(double metres, {int? decimals}) =>
      dist(metres, decimals: decimals);

  // ── Small lengths: cm | in ─────────────────────────────────────────────

  /// Unit symbol for thickness, wavelength and other short lengths.
  String get smallUnit => isMetric ? 'cm' : 'in';

  /// Spoken unit for short lengths.
  String get smallUnitSpoken => isMetric ? 'centimeters' : 'inches';

  /// Metres to the displayed cm or in.
  double smallValue(double metres) =>
      isMetric ? metres * 100 : LengthUnits.metresToInches(metres);

  /// A displayed (typed) cm or in back to metres.
  double smallToMetres(double shown) =>
      isMetric ? shown / 100 : LengthUnits.inchesToMetres(shown);

  /// Millimetres to the displayed cm or in. Direct factors, so a typed
  /// 2.6 cm is exactly 26 mm (no round trip through metres).
  double smallValueFromMm(double mm) => isMetric ? mm / 10 : mm / 25.4;

  /// A displayed (typed) cm or in back to millimetres.
  /// Cleaned to nine decimals so 1.27 cm is 12.7 mm, not 12.700000000000001.
  double smallToMm(double shown) =>
      _clean(isMetric ? shown * 10 : shown * 25.4);

  static double _clean(double v) => double.parse(v.toStringAsFixed(9));

  /// Decimals the small rule picks for a displayed value.
  static int smallDecimals(double shown) {
    final double a = shown.abs();
    if (a < 2) return 2;
    if (a < 100) return 1;
    return 0;
  }

  /// The number alone, rounded per the small rule (or [decimals]).
  String smallNumber(double metres, {int? decimals, bool keepZeros = false}) {
    final double v = smallValue(metres);
    return _num(v, decimals ?? smallDecimals(v), keepZeros);
  }

  /// "10.2 cm" / "4 in".
  String small(double metres, {int? decimals, bool keepZeros = false}) =>
      '${smallNumber(metres, decimals: decimals, keepZeros: keepZeros)} '
      '$smallUnit';

  /// "10.2 centimeters" / "4 inches".
  String smallSpoken(double metres, {int? decimals}) =>
      '${smallNumber(metres, decimals: decimals)} $smallUnitSpoken';

  /// [small] from millimetres (the wall models store mm).
  String smallFromMm(double mm, {int? decimals}) =>
      '${smallNumberFromMm(mm, decimals: decimals)} $smallUnit';

  /// [smallNumber] from millimetres.
  String smallNumberFromMm(double mm, {int? decimals}) {
    final double v = smallValueFromMm(mm);
    return _num(v, decimals ?? smallDecimals(v), false);
  }

  /// [smallSpoken] from millimetres.
  String smallSpokenFromMm(double mm, {int? decimals}) =>
      '${smallNumberFromMm(mm, decimals: decimals)} $smallUnitSpoken';

  /// Rounds millimetres to what the small rule would display, and returns
  /// millimetres. Sliders snap through this so the value under the thumb is
  /// the value printed beside it.
  double snapMm(double mm) {
    final double shown = smallValueFromMm(mm);
    final double step = math.pow(10, -smallDecimals(shown)).toDouble();
    final double snapped = double.parse(
      ((shown / step).roundToDouble() * step).toStringAsFixed(
        smallDecimals(shown),
      ),
    );
    return smallToMm(snapped);
  }

  // ── Speed: m/s | ft/s ──────────────────────────────────────────────────

  String get speedUnit => isMetric ? 'm/s' : 'ft/s';

  String speed(double metresPerSecond, {int decimals = 1}) =>
      '${_num(distValue(metresPerSecond), decimals, false)} $speedUnit';

  // ── Numbers ────────────────────────────────────────────────────────────

  /// Fixed [decimals]; drops a zero fraction unless [keepZeros].
  static String _num(double v, int decimals, bool keepZeros) {
    String s = v.toStringAsFixed(decimals);
    if (!keepZeros && decimals > 0 && s.contains('.')) {
      s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    if (s == '-0') s = '0';
    return s;
  }

  /// Public for tools that print a displayed number with their own suffix.
  static String number(double v, int decimals, {bool keepZeros = false}) =>
      _num(v, decimals, keepZeros);
}

/// Round axis ticks in the displayed unit.
abstract final class NiceTicks {
  /// A 1, 2, 2.5 or 5 x 10^n step giving about [target] intervals over
  /// [span] (displayed units).
  static double step(double span, {int target = 5}) {
    if (span <= 0 || !span.isFinite) return 1;
    final double raw = span / target;
    final double mag = math
        .pow(10, (math.log(raw) / math.ln10).floor())
        .toDouble();
    final double f = raw / mag;
    final double nice = f < 1.5
        ? 1
        : f < 2.25
        ? 2
        : f < 3.5
        ? 2.5
        : f < 7.5
        ? 5
        : 10;
    return nice * mag;
  }

  /// Ticks from 0 (or the first multiple of the step at or above [min]) up to
  /// [max], all in displayed units, every one a multiple of the step.
  static List<double> between(double min, double max, {int target = 5}) {
    final double s = step(max - min, target: target);
    final List<double> out = <double>[];
    double t = (min / s).ceilToDouble() * s;
    while (t <= max + s * 1e-9) {
      out.add(double.parse(t.toStringAsFixed(6)));
      t += s;
    }
    return out;
  }

  /// View ranges in feet for a top-down stage that labels its edge and its
  /// half-way circle: each halves to a round number. Past 2,000 ft the steps
  /// are miles (0.5, 1, 2, 4 mi). The imperial twin of the metric 10, 20,
  /// 30, 50, 80, 100 ... 5000 m lists in Rate vs Range and Uplink/Downlink.
  static const List<double> halvingRangesFt = <double>[
    30,
    60,
    100,
    160,
    200,
    300,
    500,
    600,
    1000,
    1600,
    2000,
    2640,
    5280,
    10560,
    21120,
  ];

  /// The first range in [metricRangesM] (metric) or [halvingRangesFt]
  /// (imperial) at or past [farM], in metres.
  static double viewRange(
    double farM,
    UnitSystem u,
    List<double> metricRangesM,
  ) {
    if (u.isMetric) {
      for (final double r in metricRangesM) {
        if (r >= farM) return r;
      }
      return metricRangesM.last;
    }
    final double farFt = LengthUnits.metresToFeet(farM);
    for (final double r in halvingRangesFt) {
      if (r >= farFt) return LengthUnits.feetToMetres(r);
    }
    return LengthUnits.feetToMetres(halvingRangesFt.last);
  }

  /// A round upper bound: the smallest nice multiple at or above [v].
  static double roundUp(double v, {int target = 5}) {
    final double s = step(v, target: target);
    return (v / s - 1e-9).ceilToDouble() * s;
  }
}
