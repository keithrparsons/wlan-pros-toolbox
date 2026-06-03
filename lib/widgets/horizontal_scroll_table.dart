// HorizontalScrollTable — a horizontally scrollable container that SIGNALS it
// scrolls.
//
// Why this exists (Vera web-demo gate, 2026-06-02 — "table horizontal-scroll
// affordance"): the reference tables (MCS Index and friends) wrap a wide
// DataTable in a bare horizontal SingleChildScrollView. On desktop/Web there is
// no trackpad-overscroll bounce and no persistent scrollbar, so a table whose
// rate columns run off the right edge gives the user no hint that more columns
// exist past the fold. This widget wraps the scroll view in an always-visible
// Scrollbar so the scroll affordance reads on web without interaction.
//
// It owns its own ScrollController (a Scrollbar requires the same controller as
// the scrollable it decorates), so callers just swap their bare
// `SingleChildScrollView(scrollDirection: Axis.horizontal, child: table)` for
// `HorizontalScrollTable(child: table)` with no controller plumbing.

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Wraps [child] in a horizontally scrollable view with an always-visible
/// scrollbar, so wide reference tables visibly signal they scroll sideways on
/// web/desktop (Vera web-demo gate, 2026-06-02).
class HorizontalScrollTable extends StatefulWidget {
  const HorizontalScrollTable({super.key, required this.child});

  /// The wide content (typically a `DataTable`) that may exceed the available
  /// width and therefore scrolls horizontally.
  final Widget child;

  @override
  State<HorizontalScrollTable> createState() => _HorizontalScrollTableState();
}

class _HorizontalScrollTableState extends State<HorizontalScrollTable> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      // Always show the thumb so the table signals it scrolls without the user
      // first having to drag it (the web/desktop affordance gap Vera flagged).
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        child: Padding(
          // Same bottom inset as the scrollbar padding so the thumb sits in a
          // clear gutter beneath the content.
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: widget.child,
        ),
      ),
    );
  }
}
