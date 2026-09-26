// The GL-003 §8.22 analyzer rainbow: the ONE place its colors live in code.
//
// §8.22 (Keith-authorized 2026-06-28): spectrum-analyzer-style amplitude
// plots (waterfall, density, live FFT) map amplitude to the industry
// analyzer rainbow, noise-floor blue -> green -> yellow -> red -> peak white.
// It is a sequential encoding of one quantity (received power), not a
// categorical palette, so §8.15 does not reach it. Every plot that uses it
// MUST carry a labeled dBm legend (§8.22 "Mandatory dBm legend"), because a
// rainbow is not monotonic in luminance and meaning cannot rest on color.
//
// The stops are §8.22's table, copied exactly; do not re-derive them.
//
// The rainbow is confined to the data area. Chrome around the plot (axis
// labels, captions, the sweep-line annotation) stays WLAN Pros green and
// neutral. The data area is dark navy in BOTH themes, as the §8.22 signature
// cards are dark-baked: the top stops (yellow, white) vanish on a light
// ground.
//
// First user: the Wi-Fi Classroom "Fourier and FFT" tool, mode 3 (swept vs FFT).

import 'package:flutter/material.dart';

import 'app_tokens.dart';

class AppAnalyzerRainbow {
  AppAnalyzerRainbow._();

  /// `--app-spectrum-jet-0`: sub-noise / empty, "nothing here".
  static const Color jet0 = Color(0xFF0A1A3F);

  /// `--app-spectrum-jet-1`: the noise floor (about -95 dBm).
  static const Color jet1 = Color(0xFF173A8C);
  static const Color jet2 = Color(0xFF1C84C4);
  static const Color jet3 = Color(0xFF2BAE5E);
  static const Color jet4 = Color(0xFFE6D324);
  static const Color jet5 = Color(0xFFF09A2C);
  static const Color jet6 = Color(0xFFDE2F2F);

  /// `--app-spectrum-jet-7`: peak (about -30 dBm).
  static const Color jet7 = Color(0xFFFFFFFF);

  /// Stops 0 .. 7, weak to strong.
  static const List<Color> stops = <Color>[
    jet0,
    jet1,
    jet2,
    jet3,
    jet4,
    jet5,
    jet6,
    jet7,
  ];

  /// The data-area background: stop 0.
  static const Color viewport = jet0;

  /// A lime annotation over the rainbow (the §8.22 "non-trace accent stays
  /// lime" rule), with a stop-0 halo under it so it reads on yellow and green.
  static const Color annotation = AppColors.primary;
  static const Color annotationHalo = jet0;

  /// Flat fill for [dbm] on a legend from [floorDbm] (stop 1) to [topDbm]
  /// (stop 7). NaN (never measured) is stop 0. Each cell takes one stop, no
  /// gradient (§8.22).
  static int stopFor(double dbm, {double floorDbm = -95, double topDbm = -30}) {
    if (dbm.isNaN) return 0;
    if (dbm <= floorDbm) return 1;
    if (dbm >= topDbm) return 7;
    final double u = (dbm - floorDbm) / (topDbm - floorDbm);
    return (1 + (u * 6).round()).clamp(1, 7);
  }

  /// The dBm value each stop 1 .. 7 stands for on a [floorDbm] .. [topDbm]
  /// legend.
  static double dbmForStop(
    int stop, {
    double floorDbm = -95,
    double topDbm = -30,
  }) => floorDbm + (stop - 1) * (topDbm - floorDbm) / 6;
}
