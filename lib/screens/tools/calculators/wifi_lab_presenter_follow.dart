// PresenterFollow: rebuilds a presenter layout when one chosen value of a
// tool's state changes, and not otherwise.
//
// A tool whose keys depend on its state (Fourier's four modes, the antenna
// the Antenna Pattern tool is showing) hands PresenterLayout new
// PresenterActions when that state changes, so the "?" list and the slider's
// name follow it. Listening to the whole state object would rebuild the
// layout on every tick of a running animation; this rebuilds only when
// [select] returns something new. The stage and controls keep their own
// ListenableBuilders, so they redraw on every change as before.
//
// Not part of the presenter shell's API (lib/widgets/presenter/): a Wi-Fi
// Lab helper, used by fourier_fft_screen.dart and antenna_pattern_screen.dart.

import 'package:flutter/widgets.dart';

class PresenterFollow extends StatefulWidget {
  const PresenterFollow({
    super.key,
    required this.listenable,
    required this.select,
    required this.builder,
  });

  /// The tool's state object.
  final Listenable listenable;

  /// The value the layout depends on (a mode, a kind, a record of both).
  final Object? Function() select;

  /// Builds the PresenterLayout for the current value.
  final WidgetBuilder builder;

  @override
  State<PresenterFollow> createState() => _PresenterFollowState();
}

class _PresenterFollowState extends State<PresenterFollow> {
  // Read at mount, not lazily: a lazy first read would happen inside
  // [_changed], after the change, and miss it.
  Object? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.select();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(PresenterFollow old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final Object? next = widget.select();
    if (next != _value) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
