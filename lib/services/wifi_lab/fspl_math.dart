// Free-space path loss math for the Wi-Fi Classroom FSPL Simulator.
//
// CLEAN-ROOM BUILD (2026-09-25) from the Friis transmission equation, per
// myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/03-fspl-simulator.md.
// Pure Dart, no Flutter imports, so every number the screen shows is pinned by
// test/services/wifi_lab/fspl_math_test.dart.
//
// The teaching split. FSPL = (4 pi d / lambda)^2 is the product of two parts:
//
//   spreading loss  = 10 log10(4 pi d^2)          same at every frequency
//   aperture term   = -10 log10(lambda^2 / 4 pi)  changes with frequency
//
// Their sum is exactly 20 log10(4 pi d / lambda). The aperture term is the
// effective area of an isotropic receive antenna: a shorter wavelength makes a
// smaller antenna that collects less of the spreading energy. Free space does
// not absorb higher frequencies more; the receive antenna catches less.
//
// Two forms of FSPL are exposed:
//   - [FsplMath.fsplDb]: the exact form from c = 299,792,458 m/s. The screen
//     uses this, so the spreading-plus-aperture bars add up to the curve.
//   - [FsplMath.fsplRoundedDb]: the working-engineer form with the rounded
//     constant 27.55 (d in m, f in MHz). It differs from the exact form by
//     about 0.004 dB and is shown in the explainer.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

/// Free-space path loss, its two-part split, the log-distance indoor model and
/// the link-budget arithmetic. All inputs are SI or MHz as named; every method
/// is a pure function.
abstract final class FsplMath {
  /// Speed of light in a vacuum, m/s (exact by definition of the metre).
  static const double speedOfLight = 299792458;

  /// The rounded constant in FSPL(dB) = 20 log10(d m) + 20 log10(f MHz) - 27.55.
  static const double roundedConstantDb = 27.55;

  /// The exact value the rounded constant stands for:
  /// 20 log10(c / (4 pi x 10^6)) with d in metres and f in MHz. About 27.5522.
  static final double exactConstantDb =
      20 * log10(speedOfLight / (4 * math.pi * 1e6));

  static double log10(double x) => math.log(x) / math.ln10;

  /// Wavelength in metres for a frequency in MHz.
  static double wavelengthM(double freqMHz) => speedOfLight / (freqMHz * 1e6);

  /// Effective aperture of an isotropic (0 dBi) antenna, lambda^2 / 4 pi, in
  /// square metres.
  static double isotropicApertureM2(double freqMHz) {
    final double l = wavelengthM(freqMHz);
    return l * l / (4 * math.pi);
  }

  /// Exact free-space path loss in dB: 20 log10(4 pi d / lambda).
  static double fsplDb(double distanceM, double freqMHz) =>
      20 * log10(4 * math.pi * distanceM / wavelengthM(freqMHz));

  /// Free-space path loss with the rounded 27.55 constant (d in m, f in MHz).
  static double fsplRoundedDb(double distanceM, double freqMHz) =>
      20 * log10(distanceM) + 20 * log10(freqMHz) - roundedConstantDb;

  /// Spreading loss in dB, 10 log10(4 pi d^2): the power density falls as the
  /// same energy covers a larger sphere. Independent of frequency.
  static double spreadingLossDb(double distanceM) =>
      10 * log10(4 * math.pi * distanceM * distanceM);

  /// Aperture term in dB, -10 log10(lambda^2 / 4 pi): how much less energy an
  /// isotropic receive antenna collects at this frequency. Independent of
  /// distance.
  static double apertureTermDb(double freqMHz) =>
      -10 * log10(isotropicApertureM2(freqMHz));

  /// Difference in path loss between two frequencies at the same distance,
  /// 20 log10(f2 / f1). Positive when [f2MHz] is the higher frequency.
  static double bandDifferenceDb(double f1MHz, double f2MHz) =>
      20 * log10(f2MHz / f1MHz);

  /// Log-distance model: PL(d) = FSPL(1 m) + 10 n log10(d / 1 m). With n = 2
  /// it is free space. A model with a chosen exponent, not a measurement.
  static double logDistanceDb(
    double distanceM,
    double freqMHz,
    double exponent,
  ) => fsplDb(1, freqMHz) + 10 * exponent * log10(distanceM);

  /// Received power in dBm:
  /// Tx power + Tx gain + Rx gain - path loss - other losses.
  static double receivedPowerDbm({
    required double txPowerDbm,
    required double txGainDbi,
    required double rxGainDbi,
    required double pathLossDb,
    double otherLossesDb = 0,
  }) => txPowerDbm + txGainDbi + rxGainDbi - pathLossDb - otherLossesDb;

  /// The path loss that would produce [rssiDbm] with this link budget, the
  /// inverse of [receivedPowerDbm]. Used to plot a measured point on the
  /// path-loss view.
  static double pathLossForRssi({
    required double rssiDbm,
    required double txPowerDbm,
    required double txGainDbi,
    required double rxGainDbi,
    double otherLossesDb = 0,
  }) => txPowerDbm + txGainDbi + rxGainDbi - otherLossesDb - rssiDbm;
}
