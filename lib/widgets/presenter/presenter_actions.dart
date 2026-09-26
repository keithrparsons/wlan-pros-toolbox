// PresenterActions: what a Wi-Fi Lab tool lets the presenter keyboard do.
//
// A tool fills in only the callbacks it supports. A null callback means the
// key does nothing and the shortcut overlay leaves that row out, so an
// instructor never reads a shortcut the tool does not have.
//
// Callbacks are read at key-press time, so a tool may pass closures over its
// state object and let that object decide (for example Step while playing).

import 'package:flutter/foundation.dart';

@immutable
class PresenterActions {
  const PresenterActions({
    this.playPause,
    this.step,
    this.reset,
    this.sliderDown,
    this.sliderUp,
    this.sliderLabel,
  }) : assert(
         (sliderDown == null) == (sliderUp == null),
         'Declare both slider directions or neither.',
       );

  /// No keyboard actions beyond the shell's own (Esc, F, ?).
  static const PresenterActions none = PresenterActions();

  /// Space.
  final VoidCallback? playPause;

  /// Right arrow.
  final VoidCallback? step;

  /// R.
  final VoidCallback? reset;

  /// Down arrow or [ : the tool's main slider one notch down.
  final VoidCallback? sliderDown;

  /// Up arrow or ] : the tool's main slider one notch up.
  final VoidCallback? sliderUp;

  /// What the main slider is, for the shortcut overlay ("SNR", "EIRP").
  final String? sliderLabel;

  bool get hasSlider => sliderDown != null && sliderUp != null;
}
