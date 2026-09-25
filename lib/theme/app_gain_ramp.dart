// The gain ramp for the Wi-Fi Lab Antenna Pattern simulator: the ONE place
// its colors live.
//
// GL-003 §8.15.2 (Keith, 2026-09-25): in a Wi-Fi Lab teaching simulator,
// where color carries the lesson, the author may use extra hues from one
// harmonious family, keeping the §8.9 contrast floor and a label so meaning
// never rests on color alone. This ramp is that allowance, used for one
// continuous quantity: antenna gain in dBi. It is NOT the §8.22 brand-green
// amplitude ramp (which the same ruling says the author need not use here),
// and it is NOT a categorical palette: it is sequential, and every screen that
// uses it carries a dBi legend.
//
// Why these stops (the choice is reported to Keith for sign-off, per §8.22's
// standing scope note on non-analyzer heat maps):
//   - Seven 5 dB bands, blue -> teal -> green -> brand lime -> yellow -> cream,
//     so the color bands read as gain contours on the rotating 3D surface.
//   - Luminance rises monotonically (each step 1.23:1 to 1.34:1 against the
//     one below), so the order survives grayscale and color-vision deficiency.
//   - Every stop clears 3:1 (SC 1.4.11) against the viewport it is drawn on,
//     [viewport] #1A1A1A: 3.51, 4.69, 5.95, 7.30, 9.29, 12.07, 15.28 to 1,
//     computed with the GL-003 §8.12 formula.
//   - The top stops fail on white (1.44 and 1.14 to 1), so the 3D viewport
//     stays [viewport] in the light theme too. A light viewport would make the
//     antenna's strongest direction the least visible thing on screen.
//
// Touch nothing here without updating the report to Keith: he signs off
// non-analyzer heat maps.

import 'package:flutter/material.dart';

import 'app_tokens.dart';

class AppGainRamp {
  AppGainRamp._();

  /// The viewport the ramp is measured against. Equals the dark canvas
  /// (`--app-surface-0`) and is used in BOTH themes (see the header).
  static const Color viewport = AppColors.surface0;

  /// Lowest band (the floor and the first 5 dB above it).
  static const Color band1 = Color(0xFF4F6BC4);
  static const Color band2 = Color(0xFF3F8CB8);
  static const Color band3 = Color(0xFF2EA89A);
  static const Color band4 = Color(0xFF5CBC5E);

  /// Brand lime (`--color-primary`) sits in the fifth band.
  static const Color band5 = AppColors.primary;
  static const Color band6 = Color(0xFFD6DF5C);

  /// Strongest band.
  static const Color band7 = Color(0xFFF6F2C6);

  /// Low to high.
  static const List<Color> bands = <Color>[
    band1,
    band2,
    band3,
    band4,
    band5,
    band6,
    band7,
  ];

  /// Width of one band.
  static const double bandDb = 5;

  /// Text and scaffold on the dark viewport, in both themes. These are the
  /// dark-theme §8.2 text tokens, because the viewport is dark in both.
  static const Color viewportText = AppColors.textSecondary; // 13.8:1
  static const Color viewportMuted = AppColors.textTertiary; // 6.3:1
  static const Color viewportRule = AppColors.border; // decorative only
  static const Color viewportRuleStrong = AppColors.borderStrong; // 4.41:1
}
