// Connection comparison phrasing — the pure "how do the two sides compare?"
// sentence builder for Test My Connection.
//
// A pure-Dart function with NO Flutter, NO platform channels, NO I/O. It takes
// the two rates the verdict already compares — the usable Wi-Fi data rate and
// the measured internet rate — and turns them into the single plain-English
// comparison line the result screen and the copy report both show. Keeping it
// pure keeps the wording exhaustively unit-testable with plain values.
//
// RATIO PHRASING (Keith 2026-06-17): a giant percentage reads as noise. Above a
// ~10x ratio the phrase switches from "N% faster" to a clean "about Nx faster",
// and past ~100x to a plain "far faster", because at that point even a multiple
// has stopped being meaningful. Small ratios keep the familiar percentage. The
// motivating bug: a verdict that said "Your Wi-Fi link is 3913% faster than your
// internet connection" — now "about 40x faster".

/// The pure comparison-phrase builder. Stateless: [phrase] is a total function
/// of its two rate inputs, so every wording band is unit-testable.
class ConnectionComparison {
  const ConnectionComparison._();

  /// The +/-10% band within which the two sides read as "about the same speed"
  /// rather than a near-zero percentage.
  static const double kSameSpeedPctBand = 10.0;

  /// The ratio at/above which a percentage stops reading cleanly and the phrase
  /// switches to an "Nx" multiple. At 10x the slower side is 1000% behind; a
  /// "3913% faster" figure is technically correct but lands as noise, so above
  /// this the phrase says "about 40x faster" instead. Below it, small ratios
  /// keep the existing percentage wording unchanged.
  static const double kCleanMultipleRatio = 10.0;

  /// The ratio at/above which even a multiple stops being meaningful and the
  /// phrase says "far faster / slower" plainly.
  static const double kFarRatio = 100.0;

  /// Builds the comparison phrase from two positive rates: [usable] (the usable
  /// Wi-Fi capacity, Mbps) versus [internet] (the measured internet rate, Mbps).
  ///
  /// Wording bands:
  ///   * within +/-10%            → "running at about the same speed"
  ///   * the faster side ≤ 10x    → "N% faster / slower" (unchanged small ratios)
  ///   * 10x < faster side < 100x → "about Nx faster / slower" (clean multiple)
  ///   * the faster side ≥ 100x   → "far faster / slower"
  ///
  /// The caller is responsible for only invoking this with real measured rates
  /// (both positive); it does not fabricate a result from a missing side.
  static String phrase(double usable, double internet) {
    final double deltaPct = 100 * (usable - internet) / internet;
    // Within +/-10% reads as "about the same speed" rather than a near-zero %.
    if (deltaPct.abs() <= kSameSpeedPctBand) {
      return 'Your Wi-Fi link and your internet connection are running at about '
          'the same speed.';
    }
    final bool wifiFaster = deltaPct > 0;
    final String direction = wifiFaster ? 'faster' : 'slower';
    // The ratio of the faster side to the slower side (always >= 1 here).
    final double multiple = wifiFaster ? usable / internet : internet / usable;

    if (multiple <= kCleanMultipleRatio) {
      // Small ratios keep the familiar percentage wording.
      final int n = deltaPct.abs().round();
      return 'Your Wi-Fi link is $n% $direction than your internet connection.';
    }
    if (multiple >= kFarRatio) {
      // Past ~100x even a clean multiple stops being meaningful — say it plainly.
      return 'Your Wi-Fi link is far $direction than your internet connection.';
    }
    // 10x to 100x: a clean "about Nx" multiple instead of a giant percentage.
    final int x = multiple.round();
    return 'Your Wi-Fi link is about ${x}x $direction than your internet '
        'connection.';
  }
}
