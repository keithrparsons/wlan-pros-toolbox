// AP colors for the Wi-Fi Classroom Roaming Walk (roaming-walk). THE ONE PLACE
// these hues live.
//
// GL-003 §8.15.2 (Keith, 2026-09-25): a Wi-Fi Classroom teaching simulator may use
// extra hues when telling categories apart by color is part of the lesson.
// Here it is: the student matches each AP on the floor plan, its -67 and
// -70 dBm contours, and its RSSI trace on the time plot. The hues are one
// family: equal OKLCH lightness and chroma (dark L 0.78 C 0.11; light L 0.52
// C 0.13; the sixth, sand, at C 0.07), stepped around the wheel and kept
// away from lime (the serving link, §8.3), amber and red (the §8.13 warning
// and danger verdicts). Every AP keeps its "AP n" label, so no meaning rests
// on color alone (§8.13 rule 2, WCAG 1.4.1).
//
// Contrast, measured per §8.12 as graphical objects (SC 1.4.11, 3:1 floor):
//   dark, on surface2 #2A2A2A: 7.24, 6.85, 7.48, 6.98, 6.80, 7.04
//   light, on white #FFFFFF:   5.48, 5.88, 4.89, 5.75, 5.93, 5.64

import 'package:flutter/material.dart';

/// Hue for AP [index] (0-based), for the current theme.
Color roamApColor(int index, {required bool isLight}) {
  final List<Color> set = isLight ? _light : _dark;
  return set[index % set.length];
}

const List<Color> _dark = <Color>[
  Color(0xFF80BDFB), // AP 1, blue
  Color(0xFFD7A0E3), // AP 2, orchid
  Color(0xFF4FCDCD), // AP 3, teal
  Color(0xFFB0ADFB), // AP 4, violet
  Color(0xFFEF99BB), // AP 5, rose
  Color(0xFFDBAC8D), // AP 6, sand
];

const List<Color> _light = <Color>[
  Color(0xFF1F6CB0), // AP 1, blue
  Color(0xFF894D97), // AP 2, orchid
  Color(0xFF007E80), // AP 3, teal
  Color(0xFF635BB0), // AP 4, violet
  Color(0xFFA0446D), // AP 5, rose
  Color(0xFF885E41), // AP 6, sand
];
