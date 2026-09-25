// Leg colors for the Wi-Fi Lab 802.1X and EAP Ladder (eap-ladder). THE ONE
// PLACE these hues live.
//
// GL-003 §8.15.2 (Keith, 2026-09-25): a Wi-Fi Lab teaching simulator may use
// extra hues when telling categories apart by color is part of the lesson.
// Here it is: the student must see which messages cross the air (client and
// AP, 802.11 and EAPOL) and which cross the wire (AP and RADIUS server,
// RADIUS over UDP), and that the same EAP message makes both trips.
//
// Two hues from one family: the blue and the sand of the Wi-Fi Lab AP family
// (roaming_walk_palette.dart, equal OKLCH lightness, kept away from lime and
// from the §8.13 amber and red). Blue against sand stays apart for the common
// color-vision deficiencies. Neither carries meaning alone: every arrow has
// its frame name on it, wire arrows are also dashed, and the legend names
// both legs in words (§8.13 rule 2, WCAG 1.4.1).
//
// Contrast, measured per §8.12 (WCAG relative luminance), 2026-09-25:
//   dark on surface1 #222222:  air 8.02, wire 7.80
//   light on surface1 #FFFFFF: air 5.48, wire 5.64
// Both clear 4.5:1, so they are legal for text as well as for arrows.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/eap_ladder.dart';

/// Hue for [leg] in the current theme.
Color ladderLegColor(LadderLeg leg, {required bool isLight}) {
  switch (leg) {
    case LadderLeg.air:
      return isLight ? const Color(0xFF1F6CB0) : const Color(0xFF80BDFB);
    case LadderLeg.wire:
      return isLight ? const Color(0xFF885E41) : const Color(0xFFDBAC8D);
  }
}
