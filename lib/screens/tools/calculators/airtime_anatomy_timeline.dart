// Timeline painters for Airtime Anatomy (Wi-Fi Lab).
//
// One horizontal bar per scenario, every segment drawn to scale in
// microseconds against a shared axis, so two scenarios compare by length. The
// bar always fills the card's width; the scale (px per us) comes from the
// longest scenario on screen. A segment too narrow for its own label gets a
// leader line down to a label in a lane under the bar; those labels are
// packed left to right in as many rows as they need.
//
// COLOR (GL-003 §8.13 / §8.15). No categorical hues. Lime (a fill, §8.20.2)
// marks the one quantity the tool is about: the data symbols. Everything else
// is the neutral stack, told apart by structure: hatching for the waits
// (AIFS, backoff), a neutral fill for the preamble, an outline for control
// frames (RTS/CTS, ACK), a bare dashed box for SIFS, the silence between
// frames. No status hue appears in the bar: nothing in it is a verdict.
//
// Accessibility: the painting is a picture. The screen wraps it in a worded
// Semantics label and lists every segment with its duration in a table of
// focusable buttons, so no fact is carried by the drawing alone (SC 1.4.1).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/airtime_anatomy.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

/// The visual families a segment can take. Shared by the bar and the legend.
enum AirtimeBlockStyle {
  wait('Waiting (AIFS, backoff)'),
  preamble('Preamble'),
  data('Data symbols'),
  control('Control frame (RTS/CTS, ACK)'),
  gap('SIFS (silence)');

  const AirtimeBlockStyle(this.label);

  final String label;

  static AirtimeBlockStyle of(TxopSegmentKind k) {
    switch (k) {
      case TxopSegmentKind.aifs:
      case TxopSegmentKind.backoff:
        return AirtimeBlockStyle.wait;
      case TxopSegmentKind.rtsCts:
      case TxopSegmentKind.ack:
        return AirtimeBlockStyle.control;
      case TxopSegmentKind.preamble:
        return AirtimeBlockStyle.preamble;
      case TxopSegmentKind.data:
        return AirtimeBlockStyle.data;
      case TxopSegmentKind.sifs:
        return AirtimeBlockStyle.gap;
    }
  }
}

/// Bar geometry shared by the layout, the painter and the tests.
class AirtimeBarGeometry {
  AirtimeBarGeometry._();

  static const double barHeight = AppSpacing.lg;

  /// Space between the bar and the first row of leader labels.
  static const double leaderGap = AppSpacing.xs;

  /// Space between leader-label rows, and between neighbors in a row.
  static const double labelGap = AppSpacing.xxs;

  /// Inner padding a label needs to sit inside its segment.
  static const double insidePad = AppSpacing.xxs;
}

/// Draws one block. Used by the bar and by the legend swatches.
void paintAirtimeBlock(
  Canvas canvas,
  Rect rect,
  AirtimeBlockStyle style,
  AppColorScheme colors,
) {
  switch (style) {
    case AirtimeBlockStyle.wait:
      _hatch(canvas, rect, colors.textTertiary);
      canvas.drawRect(
        rect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = colors.borderStrong,
      );
    case AirtimeBlockStyle.preamble:
      canvas.drawRect(rect, Paint()..color = colors.border);
      canvas.drawRect(
        rect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = colors.borderStrong,
      );
    case AirtimeBlockStyle.data:
      canvas.drawRect(rect, Paint()..color = colors.primary);
      canvas.drawRect(
        rect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = colors.textAccent,
      );
    case AirtimeBlockStyle.control:
      canvas.drawRect(
        rect.deflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colors.textSecondary,
      );
    case AirtimeBlockStyle.gap:
      _dashedRect(canvas, rect.deflate(0.5), colors.borderStrong);
  }
}

void _hatch(Canvas canvas, Rect rect, Color color) {
  canvas.save();
  canvas.clipRect(rect);
  final Paint p = Paint()
    ..color = color
    ..strokeWidth = 1;
  const double step = 6;
  for (double x = rect.left - rect.height; x < rect.right; x += step) {
    canvas.drawLine(
      Offset(x, rect.bottom),
      Offset(x + rect.height, rect.top),
      p,
    );
  }
  canvas.restore();
}

void _dashedRect(Canvas canvas, Rect r, Color color) {
  final Paint p = Paint()
    ..color = color
    ..strokeWidth = 1;
  const double dash = 3;
  void h(double y) {
    for (double x = r.left; x < r.right; x += dash * 2) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, r.right), y), p);
    }
  }

  void v(double x) {
    for (double y = r.top; y < r.bottom; y += dash * 2) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + dash, r.bottom)), p);
    }
  }

  h(r.top);
  h(r.bottom);
  v(r.left);
  v(r.right);
}

typedef _Pending = ({TxopSegment segment, Rect rect, TextPainter label});
typedef _Leader = ({
  TxopSegment segment,
  Rect rect,
  TextPainter label,
  double x,
  bool right,
});
typedef _Done = ({double anchor, double left, double right, int row});

/// Where one segment and its label landed.
class PlacedSegment {
  PlacedSegment({
    required this.segment,
    required this.rect,
    required this.label,
    required this.labelOffset,
    required this.inside,
  });

  final TxopSegment segment;

  /// The segment's rectangle on the bar (at least 1 px wide).
  final Rect rect;

  /// Laid-out label text.
  final TextPainter label;

  /// Top-left of the label.
  final Offset labelOffset;

  /// True when the label sits inside the segment; false for a leader label.
  final bool inside;

  Rect get labelRect => labelOffset & label.size;
}

/// Lays out one scenario's bar at a given width and scale. Pure geometry:
/// the painter draws it and the screen hit-tests it.
class AirtimeBarLayout {
  AirtimeBarLayout._(this.placed, this.height, this.width);

  /// Builds the layout. [scaleUs] is the microseconds the full [width]
  /// represents (the longest scenario on screen).
  factory AirtimeBarLayout.compute({
    required AirtimeResult result,
    required double width,
    required double scaleUs,
    required TextStyle insideStyle,
    required TextStyle dataInsideStyle,
    required TextStyle leaderStyle,
    required TextScaler textScaler,
  }) {
    final double pxPerUs = scaleUs <= 0 ? 0 : width / scaleUs;
    final List<PlacedSegment> placed = <PlacedSegment>[];
    final List<_Pending> leaders = <_Pending>[];
    double rowHeight = 0;

    TextPainter paintText(String s, TextStyle style) => TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();

    for (final TxopSegment s in result.segments) {
      if (s.tenths == 0) continue;
      final double x0 = s.startUs * pxPerUs;
      final double x1 = math.max(s.endUs * pxPerUs, x0 + 1);
      final Rect rect = Rect.fromLTRB(
        x0,
        0,
        math.min(x1, math.max(width, x0 + 1)),
        AirtimeBarGeometry.barHeight,
      );
      final TextStyle inStyle = s.kind == TxopSegmentKind.data
          ? dataInsideStyle
          : insideStyle;
      const double pad = AirtimeBarGeometry.insidePad * 2;

      // Inside: "Data 340 µs", else "Data".
      final TextPainter full = paintText(
        '${s.label} ${s.durationLabel}',
        inStyle,
      );
      TextPainter? inside;
      if (full.width + pad <= rect.width &&
          full.height <= AirtimeBarGeometry.barHeight) {
        inside = full;
      } else {
        final TextPainter short = paintText(s.label, inStyle);
        if (short.width + pad <= rect.width &&
            short.height <= AirtimeBarGeometry.barHeight) {
          inside = short;
        }
      }
      if (inside != null) {
        placed.add(
          PlacedSegment(
            segment: s,
            rect: rect,
            label: inside,
            labelOffset: Offset(
              rect.center.dx - inside.width / 2,
              rect.center.dy - inside.height / 2,
            ),
            inside: true,
          ),
        );
        continue;
      }

      // Leader label under the bar; placed once every segment is known.
      final TextPainter lead = paintText(
        '${s.label} ${s.durationLabel}',
        leaderStyle,
      );
      rowHeight = math.max(rowHeight, lead.height);
      leaders.add((segment: s, rect: rect, label: lead));
    }

    // LEADER PLACEMENT. Each leader line drops straight down from its
    // segment's center, then turns to its label. A label sits to the right
    // of its line when it fits inside the width, otherwise to the left. Row
    // r is the first row where the label (1) overlaps no label in row r,
    // (2) its own line crosses no label in a row above r, and (3) it covers
    // no line that drops to a row below r. Processing labels that open
    // leftward from the left end, and labels that open rightward from the
    // right end, lets the rule always find a row: the result is a staircase
    // for a cluster of slivers and a single row for slivers far apart.
    const double inset = AirtimeBarGeometry.labelGap;
    const double gap = AirtimeBarGeometry.labelGap * 2;
    final List<_Leader> opened = <_Leader>[
      for (final _Pending l in leaders)
        (
          segment: l.segment,
          rect: l.rect,
          label: l.label,
          x: l.rect.center.dx,
          right: l.rect.center.dx + inset + l.label.width <= width,
        ),
    ];
    final List<_Leader> order = <_Leader>[
      ...opened.where((_Leader o) => !o.right).toList()
        ..sort((_Leader p, _Leader q) => p.x.compareTo(q.x)),
      ...opened.where((_Leader o) => o.right).toList()
        ..sort((_Leader p, _Leader q) => q.x.compareTo(p.x)),
    ];
    final List<_Done> done = <_Done>[];
    int rows = 0;
    for (final _Leader o in order) {
      final double left = o.right
          ? o.x + inset
          : math.max(0, o.x - inset - o.label.width);
      final double right = left + o.label.width;
      int row = 0;
      for (; row <= done.length; row++) {
        bool ok = true;
        for (final _Done d in done) {
          if (d.row == row && left < d.right + gap && right + gap > d.left) {
            ok = false;
          } else if (d.row < row &&
              o.x >= d.left - inset &&
              o.x <= d.right + inset) {
            ok = false;
          } else if (d.row > row &&
              d.anchor >= left - inset &&
              d.anchor <= right + inset) {
            ok = false;
          }
          if (!ok) break;
        }
        if (ok) break;
      }
      done.add((anchor: o.x, left: left, right: right, row: row));
      rows = math.max(rows, row + 1);
      placed.add(
        PlacedSegment(
          segment: o.segment,
          rect: o.rect,
          label: o.label,
          // Row index for now; resolved to a y below.
          labelOffset: Offset(left, row.toDouble()),
          inside: false,
        ),
      );
    }

    // Resolve leader rows to y positions.
    final double rowPitch = rowHeight + AirtimeBarGeometry.labelGap;
    const double firstRowTop =
        AirtimeBarGeometry.barHeight + AirtimeBarGeometry.leaderGap;
    final List<PlacedSegment> resolved =
        <PlacedSegment>[
          for (final PlacedSegment p in placed)
            if (p.inside)
              p
            else
              PlacedSegment(
                segment: p.segment,
                rect: p.rect,
                label: p.label,
                labelOffset: Offset(
                  p.labelOffset.dx,
                  firstRowTop + p.labelOffset.dy * rowPitch,
                ),
                inside: false,
              ),
        ]..sort(
          (PlacedSegment p, PlacedSegment q) =>
              p.segment.startTenths.compareTo(q.segment.startTenths),
        );
    final double height = rows == 0
        ? AirtimeBarGeometry.barHeight
        : firstRowTop + rows * rowPitch - AirtimeBarGeometry.labelGap;
    return AirtimeBarLayout._(resolved, height, width);
  }

  final List<PlacedSegment> placed;
  final double height;
  final double width;

  /// The segment under [p], checking labels first (a leader label is the
  /// bigger target for a sliver of a segment), then the bar, then the nearest
  /// segment within a finger's reach on the bar.
  TxopSegmentKind? hitTest(Offset p) {
    for (final PlacedSegment s in placed) {
      if (!s.inside && s.labelRect.inflate(2).contains(p)) {
        return s.segment.kind;
      }
    }
    if (p.dy < -2 || p.dy > AirtimeBarGeometry.barHeight + 2) return null;
    for (final PlacedSegment s in placed) {
      if (p.dx >= s.rect.left && p.dx <= s.rect.right) return s.segment.kind;
    }
    PlacedSegment? best;
    double bestD = AppSpacing.xs;
    for (final PlacedSegment s in placed) {
      final double d = math.min(
        (p.dx - s.rect.left).abs(),
        (p.dx - s.rect.right).abs(),
      );
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    return best?.segment.kind;
  }
}

/// Paints one scenario's bar from its [AirtimeBarLayout].
class AirtimeBarPainter extends CustomPainter {
  AirtimeBarPainter({
    required this.layout,
    required this.colors,
    required this.selected,
  });

  final AirtimeBarLayout layout;
  final AppColorScheme colors;
  final TxopSegmentKind? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint leader = Paint()
      ..color = colors.textTertiary
      ..strokeWidth = 1;

    for (final PlacedSegment p in layout.placed) {
      paintAirtimeBlock(
        canvas,
        p.rect,
        AirtimeBlockStyle.of(p.segment.kind),
        colors,
      );
    }
    for (final PlacedSegment p in layout.placed) {
      if (p.inside) {
        p.label.paint(canvas, p.labelOffset);
      } else {
        // Straight down from the segment, then across to the label.
        final double ax = p.rect.center.dx;
        final Rect lr = p.labelRect;
        final double y = lr.center.dy;
        canvas.drawLine(Offset(ax, p.rect.bottom), Offset(ax, y), leader);
        final double edge = ax <= lr.left ? lr.left - 1 : lr.right + 1;
        canvas.drawLine(Offset(ax, y), Offset(edge, y), leader);
        p.label.paint(canvas, p.labelOffset);
      }
    }
    // Selection: a 2px textPrimary ring round the segment (and its label).
    if (selected != null) {
      final Paint ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = colors.textPrimary;
      for (final PlacedSegment p in layout.placed) {
        if (p.segment.kind != selected) continue;
        canvas.drawRect(p.rect.inflate(1), ring);
        if (!p.inside) {
          canvas.drawRect(p.labelRect.inflate(2), ring..strokeWidth = 1);
        }
      }
    }
  }

  @override
  bool shouldRepaint(AirtimeBarPainter old) =>
      old.layout != layout || old.colors != colors || old.selected != selected;
}

/// The shared microsecond axis under the bars.
class AirtimeAxisPainter extends CustomPainter {
  AirtimeAxisPainter({
    required this.scaleUs,
    required this.colors,
    required this.style,
    required this.textScaler,
  });

  final double scaleUs;
  final AppColorScheme colors;
  final TextStyle style;
  final TextScaler textScaler;

  /// Tick spacing for [scaleUs] across [width] px, about 64 px apart or more.
  static double tickStepUs(double scaleUs, double width) {
    const List<double> steps = <double>[
      5,
      10,
      20,
      25,
      50,
      100,
      200,
      250,
      500,
      1000,
      2000,
      2500,
      5000,
    ];
    final double maxTicks = math.max(1, width / 64);
    for (final double s in steps) {
      if (scaleUs / s <= maxTicks) return s;
    }
    return steps.last;
  }

  /// Height the axis needs for its labels.
  static double heightFor(TextStyle style, TextScaler scaler) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    return AppSpacing.xs + tp.height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (scaleUs <= 0) return;
    final Paint line = Paint()
      ..color = colors.borderStrong
      ..strokeWidth = 1;
    canvas.drawLine(Offset.zero, Offset(size.width, 0), line);
    final double step = tickStepUs(scaleUs, size.width);
    final double pxPerUs = size.width / scaleUs;
    double lastRight = -double.infinity;
    for (double us = 0; us <= scaleUs + 1e-9; us += step) {
      final double x = us * pxPerUs;
      canvas.drawLine(Offset(x, 0), Offset(x, AppSpacing.xxs), line);
      final String label = us == 0 ? '0 µs' : formatTenthsUs((us * 10).round());
      final TextPainter tp = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      final double lx = (x - tp.width / 2).clamp(0, size.width - tp.width);
      if (lx < lastRight + AppSpacing.xxs) continue;
      tp.paint(canvas, Offset(lx, AppSpacing.xxs + 2));
      lastRight = lx + tp.width;
    }
  }

  @override
  bool shouldRepaint(AirtimeAxisPainter old) =>
      old.scaleUs != scaleUs ||
      old.colors != colors ||
      old.style != style ||
      old.textScaler != textScaler;
}

/// A legend swatch.
class AirtimeSwatchPainter extends CustomPainter {
  AirtimeSwatchPainter({required this.style, required this.colors});

  final AirtimeBlockStyle style;
  final AppColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) =>
      paintAirtimeBlock(canvas, Offset.zero & size, style, colors);

  @override
  bool shouldRepaint(AirtimeSwatchPainter old) =>
      old.style != style || old.colors != colors;
}
