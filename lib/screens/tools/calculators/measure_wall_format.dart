// Number formatting for How to Measure Wall Attenuation (measure-wall).
//
// Every length goes through LengthFormat, so the tool follows the app-wide
// metric/imperial switch. Distances from the source read in m or ft; gaps to
// the wall under 1 m read in cm or in, because "0.1 m" rounds away the
// difference between 5 cm and 10 cm that the lesson is about.
//
// ASCII only, no em dashes (GL-004).

import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';

class MwFormat {
  const MwFormat(this.units);

  final UnitSystem units;

  LengthFormat get _f => LengthFormat(units);

  /// A distance from the source, "4 m" / "13.1 ft".
  String dist(double m, {int? decimals}) => _f.dist(m, decimals: decimals);

  /// Spoken distance, for semantics.
  String distSpoken(double m) => _f.distSpoken(m);

  /// A gap to the wall: under 1 m in cm or in ("10 cm", "3.94 in"), else as
  /// a distance.
  String gap(double m) => m < 1 - 1e-9 ? _f.small(m) : _f.dist(m);

  /// Spoken gap, for semantics.
  String gapSpoken(double m) =>
      m < 1 - 1e-9 ? _f.smallSpoken(m) : _f.distSpoken(m);

  /// Wall thickness, "10.2 cm" / "4.02 in".
  String thickness(double m) => _f.small(m);

  /// One decimal (or [d]), no "-0.0".
  static String n(double v, [int d = 1]) {
    final String s = v.toStringAsFixed(d);
    return (s.startsWith('-') && double.parse(s) == 0) ? s.substring(1) : s;
  }

  static String db(double v) => '${n(v)} dB';

  /// A wall loss, capped as Wi-Fi Through a Wall caps it: past 150 dB the
  /// digits only say that nothing gets through.
  static String wallDb(double v) =>
      (!v.isFinite || v > 150) ? 'more than 150 dB' : db(v);

  /// "+0.4 dB" / "-1.2 dB" / "0.0 dB".
  static String signedDb(double v) {
    final String s = n(v);
    if (s == '0.0') return '0.0 dB';
    return v > 0 ? '+$s dB' : '$s dB';
  }

  static String dbm(double v) => '${n(v)} dBm';
}
