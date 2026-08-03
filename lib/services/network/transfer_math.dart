// TransferMath — how long a transfer takes, how fast a link has to be, or how
// much fits in a window. One division, in base units, plus the formatting that
// makes the answer readable.
//
// THE BITS-VERSUS-BYTES TRAP IS THE WHOLE POINT. A link is quoted in BITS per
// second and a file is quoted in BYTES, and the factor of 8 between them is
// where most wrong answers come from. This service does not try to be clever
// about it: it works ONLY in bits and bits per second, and the unit tables that
// convert into those bases are the ones the Unit Converter already ships
// ([UnitConversion.dataRateUnits] and [UnitConversion.dataStorageUnits], both
// based on the bit). There is one definition of "a MB" and one of "a Mbps" in
// the app, and this is not a second one. The screen restates both operands in
// bits so the conversion is visible on the face of the result rather than
// hidden inside it.
//
// DECIMAL AND BINARY STAY SEPARATE for the same reason: a KB is 1000 bytes and
// a KiB is 1024, and the unit tables never conflate them.
//
// WHAT THIS DELIBERATELY DOES NOT DO: model overhead. There is no efficiency
// slider, because a made-up 85% is false precision dressed as help. The result
// is the time at exactly the rate entered, and the screen says so and tells the
// user to enter a throughput they measured if they want a realistic number.
//
// PURE: no Flutter, no I/O. Every function is total and returns null rather
// than an infinity or a NaN when the inputs cannot answer the question.

/// Which of the three quantities is being solved for.
enum TransferSolveFor {
  /// Size and rate in, time out.
  time,

  /// Size and time in, rate out.
  rate,

  /// Rate and time in, size out.
  size,
}

/// Transfer arithmetic and duration formatting, all in base units.
class TransferMath {
  const TransferMath._();

  /// Seconds to move [bits] at [bitsPerSecond]. Null when the rate is zero or
  /// negative, or when either input is not finite: a division that would give
  /// an infinity is a question with no answer, not an answer of infinity.
  static double? seconds({
    required double bits,
    required double bitsPerSecond,
  }) {
    if (!bits.isFinite || !bitsPerSecond.isFinite) return null;
    if (bits < 0 || bitsPerSecond <= 0) return null;
    return bits / bitsPerSecond;
  }

  /// The rate needed to move [bits] in [seconds]. Null when the window is zero
  /// or negative.
  static double? bitsPerSecond({
    required double bits,
    required double seconds,
  }) {
    if (!bits.isFinite || !seconds.isFinite) return null;
    if (bits < 0 || seconds <= 0) return null;
    return bits / seconds;
  }

  /// How many bits move in [seconds] at [bitsPerSecond]. Null on a negative or
  /// non-finite input.
  static double? bits({
    required double bitsPerSecond,
    required double seconds,
  }) {
    if (!bitsPerSecond.isFinite || !seconds.isFinite) return null;
    if (bitsPerSecond < 0 || seconds < 0) return null;
    return bitsPerSecond * seconds;
  }

  /// A duration in words, with the units a person would actually say.
  ///
  ///   0        → `0 s`
  ///   0.0005   → `0.5 ms`
  ///   42.5     → `42.5 s`
  ///   80       → `1 min 20 s`
  ///   3725     → `1 h 2 min 5 s`
  ///   273906   → `3 d 4 h 5 min`   (seconds stop mattering past a day)
  ///
  /// Branch selection uses the value ROUNDED to one decimal, so 59.96 s reads
  /// as `1 min 0 s` rather than the nonsense `60.0 s`.
  static String formatDuration(double seconds) {
    if (!seconds.isFinite || seconds < 0) return 'Unavailable';
    if (seconds == 0) return '0 s';

    final double r1 = (seconds * 10).round() / 10;

    if (r1 < 1) {
      final double ms = seconds * 1000;
      return '${_trim(ms, ms >= 10 ? 0 : 1)} ms';
    }
    if (r1 < 60) return '${_trim(r1, 1)} s';

    if (r1 < 3600) {
      final int m = r1 ~/ 60;
      final double s = r1 - m * 60;
      return '$m min ${_trim(s, 1)} s';
    }
    if (r1 < 86400) {
      final int total = r1.round();
      return '${total ~/ 3600} h ${(total % 3600) ~/ 60} min '
          '${total % 60} s';
    }
    final int total = r1.round();
    return '${_grouped(total ~/ 86400)} d ${(total % 86400) ~/ 3600} h '
        '${(total % 3600) ~/ 60} min';
  }

  /// `8,000,000,000 bits`, or `8,000,000,000.50 bits` when it is not whole.
  static String formatBits(double bits) => '${_number(bits)} bits';

  /// `100,000,000 bits per second`.
  static String formatRate(double bitsPerSecond) =>
      '${_number(bitsPerSecond)} bits per second';

  /// A number with thousands separators, integral when it is whole and two
  /// decimals when it is not. Very large or very small magnitudes fall back to
  /// scientific notation rather than printing a wall of digits.
  static String _number(double v) {
    if (!v.isFinite) return 'Unavailable';
    if (v != 0 && (v.abs() >= 1e15 || v.abs() < 1e-3)) {
      return v.toStringAsExponential(3);
    }
    if (v == v.roundToDouble()) return _grouped(v.round());
    final String s = v.toStringAsFixed(2);
    final int dot = s.indexOf('.');
    return '${_grouped(int.parse(s.substring(0, dot)))}${s.substring(dot)}';
  }

  /// Trim to [decimals] places and drop a trailing `.0`, so `20.0` reads `20`
  /// and `25.9` keeps its decimal.
  static String _trim(double v, int decimals) {
    final String s = v.toStringAsFixed(decimals);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  static String _grouped(int n) {
    final String s = n.abs().toString();
    final StringBuffer out = StringBuffer(n < 0 ? '-' : '');
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }
}
