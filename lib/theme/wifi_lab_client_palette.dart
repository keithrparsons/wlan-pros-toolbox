// Wi-Fi Classroom client palette: one hue per client, for teaching simulators only.
//
// GL-003 §8.15.2 (Keith, 2026-09-25): in a Wi-Fi Classroom teaching simulator,
// where telling clients apart by color is part of the lesson, extra hues from
// ONE harmonious family are allowed, provided they meet the §8.9 contrast
// floor and meaning never rests on color alone. Every use of this palette
// also draws the client's letter. Outside the Wi-Fi Classroom, §8.15 case 3 still
// applies: no categorical hues.
//
// THE FAMILY. Nine hues 40 degrees apart in OKLCH (25, 65, ..., 345), at one
// lightness and chroma per theme, so no hue is brighter or louder than
// another:
//   dark theme:  L 0.80, C 0.11; letters #1A1A1A on the fill
//   light theme: L 0.52, C 0.12; letters #FFFFFF on the fill
// Measured (WCAG relative luminance), worst case across the nine:
//   dark:  fill vs surface0 #1A1A1A 8.89:1, vs surface1 #222222 8.13:1;
//          letter on fill 8.89:1
//   light: fill vs surface0 #F7F6F7 4.61:1, vs surface1 #FFFFFF 4.97:1;
//          letter on fill 4.97:1
// So each fill clears the 3:1 non-text floor and each letter clears 4.5:1.
//
// Clients 10 to 18 (J to R) reuse the nine hues as an OUTLINE: a 2 px hue
// border and a hue letter on the card surface (the hue as text clears 4.5:1
// on both surfaces, per the fill figures above), so no two clients share a
// look.

import 'package:flutter/painting.dart';

import 'app_color_scheme.dart';

/// How one client is drawn.
class WifiLabClientStyle {
  const WifiLabClientStyle({
    required this.hue,
    required this.onHue,
    required this.outlined,
  });

  /// The client's hue: the fill, or the border and letter when [outlined].
  final Color hue;

  /// Letter color on a [hue] fill.
  final Color onHue;

  /// True for clients 10 and up: drawn as an outline, not a fill.
  final bool outlined;
}

class WifiLabClientPalette {
  WifiLabClientPalette._();

  static const List<Color> _dark = <Color>[
    Color(0xFFFDA19A),
    Color(0xFFEFAF6F),
    Color(0xFFC8C26B),
    Color(0xFF90D192),
    Color(0xFF5CD5C7),
    Color(0xFF65CDF3),
    Color(0xFF9BBDFF),
    Color(0xFFCEACF7),
    Color(0xFFF1A1CE),
  ];

  static const List<Color> _light = <Color>[
    Color(0xFFA34945),
    Color(0xFF975800),
    Color(0xFF746C00),
    Color(0xFF357A3A),
    Color(0xFF007E72),
    Color(0xFF00769C),
    Color(0xFF4665AE),
    Color(0xFF7955A0),
    Color(0xFF984979),
  ];

  static const Color _onDark = Color(0xFF1A1A1A);
  static const Color _onLight = Color(0xFFFFFFFF);

  /// Distinct hues before the outline style takes over.
  static const int hueCount = 9;

  /// The style for client [index] (0 = A) in [colors]' theme.
  static WifiLabClientStyle of(int index, AppColorScheme colors) {
    final List<Color> set = colors.isLight ? _light : _dark;
    return WifiLabClientStyle(
      hue: set[index % hueCount],
      onHue: colors.isLight ? _onLight : _onDark,
      outlined: index >= hueCount,
    );
  }
}
