// Open Location Code (Plus Code) encoder — pure Dart, offline, no API key,
// no network. The free/open alternative to what3words: a Plus Code is computed
// directly from a WGS-84 latitude/longitude with a published, deterministic
// algorithm, so the device can render one from any GPS fix without a round-trip.
//
// Reference: Google's Open Location Code specification (Apache-2.0). This is a
// clean-room reimplementation of the ENCODE half of that spec in pure Dart —
// matching the in-house-compute pattern the Toolbox already uses for DTMF tone
// synthesis, QR generation, and the net_quality engine, so we add no pub
// dependency and stay 100% offline (GL-008: local computation, no network).
//
// We implement ONLY encode (lat/long -> code). Decode (code -> area) is not
// needed for the Current Location readout and is intentionally omitted to keep
// the surface small.
//
// A full code is 10 characters with a '+' separator after the 8th character,
// e.g. `849VCWC8+R9`. The first 10 significant digits give roughly a 13.9 m x
// 13.9 m grid cell — fine enough to identify a building. An 11th digit (one
// grid-refinement step) tightens it further; we expose an optional [codeLength]
// for callers that want the extra precision, defaulting to the standard 10.
//
// Implementation follows the canonical INTEGER form of the reference algorithm:
// latitude and longitude are scaled up to the finest integer grid the longest
// (15-digit) code resolves, then digits are read off by repeated modulo and
// integer division — the pair section (digits 1..10, base-20 lat/long pairs)
// most-significant first, and the grid section (digits 11..15, a 4-wide x
// 5-tall subdivision per step) appended. Integer arithmetic avoids the
// floating-point drift a repeated-divide approach accumulates, so the encode
// matches the published reference vectors exactly.

abstract final class OpenLocationCode {
  OpenLocationCode._();

  /// The digit alphabet, in value order (index = digit value 0-19). Twenty
  /// characters; vowels and easily-confused characters are excluded by the spec.
  static const String _alphabet = '23456789CFGHJMPQRVWX';

  /// Separates the area code from the local part; always after the 8th digit.
  static const String separator = '+';

  /// The number of significant digits before the separator.
  static const int separatorPosition = 8;

  /// Padding character used when a code is shorter than the separator position.
  static const String padding = '0';

  /// Standard full-code length (10 significant digits → ~13.9 m cell).
  static const int standardCodeLength = 10;

  /// The longest code this encoder produces (10 pair digits + 5 grid digits).
  static const int maxCodeLength = 15;

  /// The pair section covers the first 10 digits; digits 11+ are grid steps.
  static const int _pairCodeLength = 10;

  /// Base of the pair-section positional digits (20-character alphabet).
  static const int _encodingBase = 20;

  /// Latitude is clamped to +/- this many degrees.
  static const int _latitudeMax = 90;

  /// Longitude wraps within +/- this many degrees.
  static const int _longitudeMax = 180;

  /// Grid-refinement step dimensions for digits 11+ (4 columns x 5 rows).
  static const int _gridColumns = 4;
  static const int _gridRows = 5;

  /// Number of grid-refinement digits past the pair section.
  static const int _gridCodeLength = maxCodeLength - _pairCodeLength; // 5

  /// Integer cells the pair section resolves (base^3 per the reference form).
  static const int _pairPrecision = _encodingBase * _encodingBase * _encodingBase; // 8000

  /// Finest integer precision (cells per degree) for latitude and longitude:
  /// the pair precision times the full grid refinement.
  static final int _finalLatPrecision = _pairPrecision * _pow(_gridRows, _gridCodeLength);
  static final int _finalLngPrecision = _pairPrecision * _pow(_gridColumns, _gridCodeLength);

  /// Encodes a WGS-84 [latitude]/[longitude] to a Plus Code string.
  ///
  /// [codeLength] is the number of significant digits (default 10, the standard
  /// full code). Pass 11 for one extra grid-refinement digit. The value is
  /// clamped to a valid length; odd sub-pair lengths the spec forbids (1, 3, 5,
  /// 7) are bumped to the next legal even length, so the caller always gets a
  /// valid code.
  ///
  /// Latitude is clamped to its valid range and longitude is normalized into
  /// [-180, 180); the function never throws on out-of-range input.
  static String encode(
    double latitude,
    double longitude, {
    int codeLength = standardCodeLength,
  }) {
    int length = codeLength.clamp(2, maxCodeLength);
    if (length < _pairCodeLength && length.isOdd) length += 1;

    double lat = _clipLatitude(latitude);
    final double lng = _normalizeLongitude(longitude);

    // Nudge the north pole down one finest-cell so the index never runs off the
    // top of the grid.
    if (lat == _latitudeMax.toDouble()) {
      lat -= 1 / _finalLatPrecision;
    }

    // Scale into positive integer space (origin at the SW corner). The *1e6 /
    // round / ~/1000000 dance matches the reference's fixed-point rounding so we
    // reproduce its vectors exactly.
    int latVal =
        (((lat + _latitudeMax) * _finalLatPrecision * 1e6).round()) ~/ 1000000;
    int lngVal =
        (((lng + _longitudeMax) * _finalLngPrecision * 1e6).round()) ~/ 1000000;

    String code = '';

    // ── Grid section (digits 11..15), least-significant first, prepended. ────
    if (length > _pairCodeLength) {
      for (int i = 0; i < _gridCodeLength; i++) {
        final int latDigit = latVal % _gridRows;
        final int lngDigit = lngVal % _gridColumns;
        code = _alphabet[latDigit * _gridColumns + lngDigit] + code;
        latVal ~/= _gridRows;
        lngVal ~/= _gridColumns;
      }
    } else {
      // Not emitting grid digits — strip the grid resolution off both axes.
      latVal ~/= _pow(_gridRows, _gridCodeLength);
      lngVal ~/= _pow(_gridColumns, _gridCodeLength);
    }

    // ── Pair section (digits 1..10), most-significant pair last, prepended. ──
    for (int i = 0; i < _pairCodeLength ~/ 2; i++) {
      code = _alphabet[lngVal % _encodingBase] + code;
      code = _alphabet[latVal % _encodingBase] + code;
      latVal ~/= _encodingBase;
      lngVal ~/= _encodingBase;
    }

    // ── Insert the separator and trim/pad to the requested length. ───────────
    code = code.substring(0, separatorPosition) +
        separator +
        code.substring(separatorPosition);
    if (length >= separatorPosition) {
      // Keep `length` significant digits plus the one separator character.
      return code.substring(0, length + 1);
    }
    // Short code: keep `length` digits, pad to the separator, then add it.
    return code.substring(0, length).padRight(separatorPosition, padding) +
        separator;
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  /// Integer power for small non-negative exponents.
  static int _pow(int base, int exp) {
    int result = 1;
    for (int i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }

  static double _clipLatitude(double latitude) => latitude
      .clamp(-_latitudeMax.toDouble(), _latitudeMax.toDouble())
      .toDouble();

  static double _normalizeLongitude(double longitude) {
    double lng = longitude;
    const int span = _longitudeMax * 2;
    while (lng < -_longitudeMax) {
      lng += span;
    }
    while (lng >= _longitudeMax) {
      lng -= span;
    }
    return lng;
  }
}
