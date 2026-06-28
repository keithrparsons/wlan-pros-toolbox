// Maidenhead Grid Square (QTH locator) encode / decode engine + great-circle
// helpers. Pure math, no I/O, no platform APIs — independently unit-testable.
//
// ALGORITHM (the IARU / amateur-radio standard locator):
//   Normalize lon to 0..360 (lon + 180) and lat to 0..180 (lat + 90), then
//   subdivide each axis level by level, most-significant pair first:
//
//     Level 0  Field       lon / 18 (20 deg)   lat / 18 (10 deg)    letters A-R
//     Level 1  Square       lon / 10 ( 2 deg)   lat / 10 ( 1 deg)    digits  0-9
//     Level 2  Subsquare    lon / 24 ( 5 min)   lat / 24 (2.5 min)   letters a-x
//     Level 3  Ext. square  lon / 10 (0.5 min)  lat / 10 (0.25 min)  digits  0-9
//
//   Each pair writes the LONGITUDE character first, then the LATITUDE character.
//   Canonical case is UPPER field, lower subsquare; decode is case-insensitive.
//
//   Output precision is in characters: 4 (field+square), 6 (+subsquare), or
//   8 (+extended square). Encoding clamps exactly +180 lon / +90 lat one ulp
//   inside the range so the top edge does not index past the last cell.
//
// VERIFIED ANCHORS (see maidenhead_data_test.dart):
//   lon -122.0, lat  37.4  -> CM87  (6-char ~ CM87wx, the classic SF Bay anchor)
//   Berlin     13.4 E, 52.5 N -> JO62  (6-char JO62qm area)
//   Both reproduced by the encoder below before this file shipped.
//
// Glyph note: ASCII hyphen-minus throughout; no em dash (GL-004).

import 'dart:math' as math;

/// The decoded extent of a Maidenhead locator: its south-west corner, its
/// width/height in degrees, and the convenience center point.
class MaidenheadCell {
  const MaidenheadCell({
    required this.swLat,
    required this.swLon,
    required this.latHeight,
    required this.lonWidth,
  });

  /// South-west (lower-left) corner latitude, decimal degrees.
  final double swLat;

  /// South-west (lower-left) corner longitude, decimal degrees.
  final double swLon;

  /// Cell height (latitude span) in decimal degrees.
  final double latHeight;

  /// Cell width (longitude span) in decimal degrees.
  final double lonWidth;

  /// North-east (upper-right) corner latitude.
  double get neLat => swLat + latHeight;

  /// North-east (upper-right) corner longitude.
  double get neLon => swLon + lonWidth;

  /// Center-of-square latitude — what a "locator -> position" lookup returns.
  double get centerLat => swLat + latHeight / 2.0;

  /// Center-of-square longitude.
  double get centerLon => swLon + lonWidth / 2.0;
}

/// A great-circle leg between two grid-square centers: distance and the initial
/// (forward) bearing from the first square to the second.
class GridLeg {
  const GridLeg({required this.km, required this.bearingDeg});

  /// Great-circle distance in kilometers (spherical earth, R = 6371 km).
  final double km;

  /// Initial bearing in degrees, 0..360 clockwise from true north.
  final double bearingDeg;

  /// Distance in statute miles.
  double get miles => km * 0.621371;
}

/// Maidenhead locator encode/decode. All methods are static and pure.
class Maidenhead {
  Maidenhead._();

  /// Mean earth radius (km) — same spherical constant the Distance & Bearing
  /// tool uses, so cross-tool results agree.
  static const double earthRadiusKm = 6371.0;

  // Per-level axis divisions, most-significant pair first.
  static const List<int> _divs = <int>[18, 10, 24, 10];

  /// Encode a latitude/longitude (decimal degrees) to a Maidenhead locator.
  ///
  /// [precision] is the character count: 4, 6, or 8. Throws [ArgumentError] for
  /// an out-of-range coordinate or an unsupported precision.
  static String encode(double lat, double lon, {int precision = 6}) {
    if (precision != 4 && precision != 6 && precision != 8) {
      throw ArgumentError.value(
        precision,
        'precision',
        'must be 4, 6, or 8',
      );
    }
    if (!lat.isFinite || !lon.isFinite || lat < -90 || lat > 90 ||
        lon < -180 || lon > 180) {
      throw ArgumentError('latitude must be -90..90 and longitude -180..180');
    }

    // Clamp exactly +180 / +90 one ulp inside so floor() stays in the last cell.
    double adjLon = (lon + 180.0).clamp(0.0, 360.0 - 1e-9).toDouble();
    double adjLat = (lat + 90.0).clamp(0.0, 180.0 - 1e-9).toDouble();

    final int pairs = precision ~/ 2;
    double lonCell = 360.0;
    double latCell = 180.0;
    final StringBuffer sb = StringBuffer();

    for (int level = 0; level < pairs; level++) {
      final int div = _divs[level];
      lonCell /= div;
      latCell /= div;
      final int lonIdx = (adjLon / lonCell).floor();
      final int latIdx = (adjLat / latCell).floor();
      adjLon -= lonIdx * lonCell;
      adjLat -= latIdx * latCell;
      sb
        ..write(_indexToChar(level, lonIdx))
        ..write(_indexToChar(level, latIdx));
    }
    return sb.toString();
  }

  /// Decode a 4/6/8-character Maidenhead locator to its cell extent, or return
  /// `null` if the string is not a valid locator (wrong length or bad glyph).
  /// Case-insensitive.
  static MaidenheadCell? decode(String locator) {
    final String s = locator.trim();
    if (s.length != 4 && s.length != 6 && s.length != 8) return null;

    double swLon = -180.0;
    double swLat = -90.0;
    double lonCell = 360.0;
    double latCell = 180.0;

    final int pairs = s.length ~/ 2;
    for (int level = 0; level < pairs; level++) {
      final int div = _divs[level];
      lonCell /= div;
      latCell /= div;
      final int? lonIdx = _charToIndex(level, s[level * 2]);
      final int? latIdx = _charToIndex(level, s[level * 2 + 1]);
      if (lonIdx == null || latIdx == null) return null;
      swLon += lonIdx * lonCell;
      swLat += latIdx * latCell;
    }
    return MaidenheadCell(
      swLat: swLat,
      swLon: swLon,
      latHeight: latCell,
      lonWidth: lonCell,
    );
  }

  /// `true` when [locator] decodes to a valid cell.
  static bool isValid(String locator) => decode(locator) != null;

  /// Great-circle leg (distance + initial bearing) between the centers of two
  /// locators, or `null` if either locator is invalid. Mirrors the spherical
  /// haversine + forward-bearing formulas used by the Distance & Bearing tool.
  static GridLeg? legBetween(String from, String to) {
    final MaidenheadCell? a = decode(from);
    final MaidenheadCell? b = decode(to);
    if (a == null || b == null) return null;
    return legBetweenPoints(a.centerLat, a.centerLon, b.centerLat, b.centerLon);
  }

  /// Great-circle leg between two explicit lat/lon points (decimal degrees).
  static GridLeg legBetweenPoints(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final double phi1 = _rad(lat1);
    final double phi2 = _rad(lat2);
    final double dPhi = _rad(lat2 - lat1);
    final double dLambda = _rad(lon2 - lon1);

    final double a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) * math.cos(phi2) *
            math.sin(dLambda / 2) * math.sin(dLambda / 2);
    final double km =
        earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    final double y = math.sin(dLambda) * math.cos(phi2);
    final double x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
    final double bearing = (_deg(math.atan2(y, x)) + 360.0) % 360.0;

    return GridLeg(km: km, bearingDeg: bearing);
  }

  // ── Character <-> index, per level ──────────────────────────────────────────

  static String _indexToChar(int level, int index) {
    switch (level) {
      case 0: // Field: A-R
        return String.fromCharCode('A'.codeUnitAt(0) + index);
      case 2: // Subsquare: lowercase a-x
        return String.fromCharCode('a'.codeUnitAt(0) + index);
      default: // Square / extended square: digits 0-9
        return index.toString();
    }
  }

  /// Parse a single locator character at [level] to its 0-based index, or null
  /// when out of the level's valid range.
  static int? _charToIndex(int level, String ch) {
    switch (level) {
      case 0: // Field: A-R (case-insensitive)
        final int v = ch.toUpperCase().codeUnitAt(0) - 'A'.codeUnitAt(0);
        return (v >= 0 && v < 18) ? v : null;
      case 2: // Subsquare: A-X / a-x (case-insensitive)
        final int v = ch.toUpperCase().codeUnitAt(0) - 'A'.codeUnitAt(0);
        return (v >= 0 && v < 24) ? v : null;
      default: // Square / extended: digit 0-9
        final int v = ch.codeUnitAt(0) - '0'.codeUnitAt(0);
        return (v >= 0 && v < 10) ? v : null;
    }
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
  static double _deg(double rad) => rad * 180.0 / math.pi;
}
