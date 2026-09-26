// PresenterActions: what a Wi-Fi Classroom tool lets the presenter keyboard do.
//
// A tool fills in only the callbacks it supports. A null callback means the
// key does nothing and the shortcut overlay leaves that row out, so an
// instructor never reads a shortcut the tool does not have.
//
// Callbacks are read at key-press time, so a tool may pass closures over its
// state object and let that object decide (for example Step while playing).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One key a tool adds beyond the shared set, for an action only that tool
/// has (DFS: radar now). The shared keys (Space, Right, R, F, Esc, ?, the
/// arrows and brackets) are handled first, so an extra key never overrides
/// them; pick a letter they do not use.
@immutable
class PresenterExtraKey {
  const PresenterExtraKey({
    required this.key,
    required this.keyLabel,
    required this.description,
    required this.onPressed,
  });

  /// The key that fires [onPressed] (for example LogicalKeyboardKey.keyD).
  final LogicalKeyboardKey key;

  /// How the shortcut list names the key ("D").
  final String keyLabel;

  /// What it does, for the shortcut list ("Radar now").
  final String description;

  final VoidCallback onPressed;
}

@immutable
class PresenterActions {
  const PresenterActions({
    this.playPause,
    this.step,
    this.reset,
    this.sliderDown,
    this.sliderUp,
    this.sliderLabel,
    this.extra = const <PresenterExtraKey>[],
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

  /// Tool-specific keys beyond the shared set. Empty for most tools.
  final List<PresenterExtraKey> extra;

  bool get hasSlider => sliderDown != null && sliderUp != null;
}
