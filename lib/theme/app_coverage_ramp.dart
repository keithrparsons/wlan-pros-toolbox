// The coverage heat-map colors for the Wi-Fi Lab Room Propagation simulator:
// the ONE place they live.
//
// THE RAMP is the GL-003 §8.22 brand-green amplitude ramp, stop for stop
// (`--app-spectrum-amp-0` .. `-7`), which §8.22 names the default for
// non-analyzer heat maps such as coverage maps. It is one hue family,
// monotonic in luminance (each step 1.21:1 to 1.81:1 over the one below), so
// the order survives grayscale and color-vision deficiency. Cells are flat
// fills of one stop, and every map carries its dBm legend (§8.22). Not the
// analyzer rainbow: that is for spectrum-analyzer plots only.
//
// §8.22 says non-analyzer heat maps come back to Keith for sign-off; this use
// is reported to him with the build.
//
// THE VIEWPORT stays dark in both themes, as the Antenna Pattern viewport
// does (lib/theme/app_gain_ramp.dart): stop 0 IS the dark canvas, and the
// pale top stops would vanish on a white page.
//
// WALL HUES (GL-003 §8.15.2, Keith 2026-09-25: extra same-family hues are
// allowed in a teaching simulator where the color teaches, always with a
// label). Wall material is told apart by hue plus the legend and the
// selected-wall name, never by hue alone. The hues are the dark-theme set of
// lib/theme/wifi_lab_client_palette.dart (OKLCH L 0.80, C 0.11), minus its
// green and teal, which would sink into the green ramp; metal is white.
// Every wall is drawn with a [casing] of the viewport color around a hue
// core, so its edge clears 3:1 (SC 1.4.11) against every ramp stop through
// one or the other (computed with the GL-003 §8.12 formula):
//   core vs stops 0-2: 8.89, 7.06, 4.38 to 1 at worst (pink, coral)
//   casing vs stops 3-7: 3.67, 5.59, 9.29, 12.91, 15.61 to 1

import 'package:flutter/material.dart';

import '../services/wifi_lab/wall_slab_physics.dart';
import 'app_tokens.dart';

class AppCoverageRamp {
  AppCoverageRamp._();

  /// The plan viewport. Equals the dark canvas (`--app-surface-0`) and
  /// ramp stop 0; used in BOTH themes (see the header).
  static const Color viewport = AppColors.surface0;

  /// GL-003 §8.22 brand-green ramp, stops 0 to 7.
  static const List<Color> stops = <Color>[
    Color(0xFF1A1A1A), // 0  sub-noise / empty, equals the canvas
    Color(0xFF26301A), // 1
    Color(0xFF3C5320), // 2
    Color(0xFF5E7D22), // 3
    Color(0xFF7A9E26), // 4  = --color-accent
    Color(0xFFA1CC3A), // 5  = --color-primary (lime)
    Color(0xFFCFE88C), // 6
    Color(0xFFEEF7CF), // 7  peak
  ];

  /// Received-power legend: the lower edge of stops 1 to 7, dBm. Below the
  /// first edge a cell takes stop 0.
  static const List<double> powerEdgesDbm = <double>[
    -90,
    -80,
    -70,
    -60,
    -50,
    -40,
    -30,
  ];

  /// Close-up legend: the lower edge of stops 1 to 7 in dB relative to the
  /// local average. Stop 1 holds everything below -12 dB (the nulls).
  static const List<double> rippleEdgesDb = <double>[
    double.negativeInfinity,
    -12,
    -9,
    -6,
    -3,
    0,
    3,
  ];

  /// The stop index for [value] against [edges] (lower edges of stops 1..7).
  static int stopFor(double value, List<double> edges) {
    int s = 0;
    for (int i = 0; i < edges.length; i++) {
      if (value >= edges[i]) s = i + 1;
    }
    return s;
  }

  /// Dark ring around every wall and marker.
  static const Color casing = AppColors.surface0;

  /// Text and lines drawn ON the viewport, in both themes: the dark-theme §8.2
  /// text tokens, because the viewport is dark in both.
  static const Color viewportText = AppColors.textPrimary; // 17.4:1
  static const Color viewportMuted = AppColors.textSecondary; // 13.8:1

  static const Color _orange = Color(0xFFEFAF6F);
  static const Color _coral = Color(0xFFFDA19A);
  static const Color _olive = Color(0xFFC8C26B);
  static const Color _cyan = Color(0xFF65CDF3);
  static const Color _blue = Color(0xFF9BBDFF);
  static const Color _violet = Color(0xFFCEACF7);
  static const Color _pink = Color(0xFFF1A1CE);
  static const Color _metal = AppColors.textPrimary;

  /// Wall hue by material. The three wood products share one hue; the
  /// legend names each one present.
  static Color wall(WallMaterial m) {
    switch (m) {
      case WallMaterial.concrete:
        return _orange;
      case WallMaterial.brick:
        return _coral;
      case WallMaterial.marble:
        return _pink;
      case WallMaterial.plasterboard:
        return _blue;
      case WallMaterial.ceilingBoard:
        return _violet;
      case WallMaterial.glass:
        return _cyan;
      case WallMaterial.wood:
      case WallMaterial.plywood:
      case WallMaterial.chipboard:
        return _olive;
      case WallMaterial.metal:
        return _metal;
    }
  }
}
