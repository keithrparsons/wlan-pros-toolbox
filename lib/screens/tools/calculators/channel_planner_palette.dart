// Channel colors and patterns for the Wi-Fi Classroom Channel Planner.
//
// GL-003 §8.15.2 (Keith, 2026-09-25): in a Wi-Fi Classroom teaching simulator,
// where telling categories apart by color is part of the lesson, extra hues
// are allowed if they come from one harmonious family, meet the §8.9
// contrast floor, and are always paired with a label. Here the categories are
// the channels in a plan: seeing which APs share a channel is the lesson.
// This file is the only place those hues live.
//
// THE FAMILY: eight hues stepped evenly from lime (the brand side) through
// green, teal, cyan, sky, periwinkle and violet to orchid, at one lightness
// per theme so no hue shouts over another. The warm reds and ambers are left
// out on purpose: they belong to the §8.13 status verdicts.
//
// CONTRAST (WCAG 2.2, computed per §8.12, pinned by
// test/screens/calculators/channel_planner_screen_test.dart):
//   dark set  vs surface2 #2A2A2A: 6.1 to 8.7:1 (non-text floor 3:1)
//   light set vs white surface:    5.0 to 6.7:1
// Labels drawn ON a channel fill use surface0 (dark) or white (light), which
// clears 4.5:1 on every hue in its set.
//
// NEVER COLOR ALONE: every AP carries its channel label, every channel also
// gets a fill pattern, and the spectrum strip sits on a labeled channel axis.
//
// ASCII only, no em dashes (GL-004).

import 'dart:ui';

/// Dark-theme channel hues, lime to orchid.
const List<Color> kChannelHuesDark = <Color>[
  Color(0xFFB5D65A), // lime
  Color(0xFF6FD08C), // green
  Color(0xFF4FC9B8), // teal
  Color(0xFF58C3E0), // cyan
  Color(0xFF7AAEF0), // sky
  Color(0xFFA3A0F5), // periwinkle
  Color(0xFFC79AEB), // violet
  Color(0xFFE992CB), // orchid
];

/// Light-theme channel hues: the same family, darker.
const List<Color> kChannelHuesLight = <Color>[
  Color(0xFF557A1C),
  Color(0xFF1C7A45),
  Color(0xFF0B7568),
  Color(0xFF0A6F8C),
  Color(0xFF2B62B3),
  Color(0xFF4F4DC0),
  Color(0xFF7446B5),
  Color(0xFF9A3D82),
];

/// Fill patterns, the second cue after the hue.
enum ChannelPattern {
  solid,
  diagonal,
  dots,
  horizontal,
  cross,
  vertical,
  backDiagonal,
  grid,
}

/// Occupied channels are numbered by frequency. Neighbors in frequency take
/// hues three steps apart, so adjacent channels never get adjacent hues.
int channelHueIndex(int occupiedIndex) => (occupiedIndex * 3) % 8;

Color channelHue(int occupiedIndex, {required bool light}) => (light
    ? kChannelHuesLight
    : kChannelHuesDark)[channelHueIndex(occupiedIndex)];

ChannelPattern channelPattern(int occupiedIndex) =>
    ChannelPattern.values[occupiedIndex % ChannelPattern.values.length];
