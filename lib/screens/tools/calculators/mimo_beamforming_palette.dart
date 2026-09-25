// Spatial-stream palette for the Wi-Fi Lab MIMO and Beamforming simulator.
//
// GL-003 §8.15.2 (Keith, 2026-09-25): a teaching simulator MAY use extra
// hues when telling categories apart by color is part of the lesson, drawn
// from one harmonious family, at the §8.9 contrast floor, and always paired
// with a label. Here the lesson is "each lane is its own stream, and the
// spare chains are not streams", so each stream gets its own hue and the
// spare chains stay neutral. Every lane is also labeled S1 to S4 on the
// canvas, and the legend and screen-reader text name the streams, so no
// meaning rests on color alone.
//
// This is the ONLY place these hues are defined. Nothing else on the screen
// uses them: the beam pattern and the sounding share stay lime, and the
// verdicts stay §8.13 status tokens with words.
//
// The family: one analogous sweep from the brand lime through teal and sky
// to violet, matched in lightness so no stream looks more important than
// another. Stream 1 is the theme's own accent, so a 1-stream link looks like
// the rest of the app.
//
// Contrast, computed per GL-003 §8.12 (WCAG relative luminance):
//   dark, on surface2 #2A2A2A / surface1 #222222:
//     S1 #A1CC3A 7.66 / 8.50, S2 #3CC8B4 6.91 / 7.66,
//     S3 #6FA8F5 5.87 / 6.51, S4 #C39BF5 6.38 / 7.07
//   light, on surface2 #FFFFFF / surface0 #F7F6F7:
//     S1 #5A7A1C 4.96 / 4.60, S2 #0E7A6C 5.23 / 4.85,
//     S3 #2C62B8 5.92 / 5.49, S4 #7B4CC2 5.75 / 5.33
// Every value clears 4.5:1, so the S1 to S4 labels drawn in these hues pass
// as text as well as graphics (§8.9).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';

/// Stream hues for one theme, stream 1 first.
@immutable
class MimoStreamPalette {
  const MimoStreamPalette._(this.colors);

  /// Resolves the palette for the current theme.
  factory MimoStreamPalette.of(BuildContext context) {
    final AppColorScheme scheme = context.colors;
    return MimoStreamPalette._(<Color>[
      scheme.textAccent,
      ...(scheme.isLight ? _light : _dark),
    ]);
  }

  static const List<Color> _dark = <Color>[
    Color(0xFF3CC8B4), // teal
    Color(0xFF6FA8F5), // sky
    Color(0xFFC39BF5), // violet
  ];

  static const List<Color> _light = <Color>[
    Color(0xFF0E7A6C), // teal
    Color(0xFF2C62B8), // sky
    Color(0xFF7B4CC2), // violet
  ];

  /// Four hues: the most streams a client in this simulator can take.
  final List<Color> colors;

  /// The hue for stream [index] (0-based).
  Color stream(int index) => colors[index % colors.length];

  @override
  bool operator ==(Object other) =>
      other is MimoStreamPalette &&
      other.colors.length == colors.length &&
      <int>[
        for (int i = 0; i < colors.length; i++) i,
      ].every((int i) => other.colors[i] == colors[i]);

  @override
  int get hashCode => Object.hashAll(colors);
}
