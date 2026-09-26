// Painters for the Wi-Fi Classroom 6 GHz Power and PSD tool (six-ghz-psd).
//
// Two views, both CustomPainters on one geometry each so the stage's tap
// handler and the painter can never disagree about where a width sits:
//   - PsdWidthChartPainter: EIRP or SNR against channel width, one line per
//     class, five evenly spaced columns (20, 40, 80, 160, 320 MHz). The
//     selected width is a highlighted column.
//   - PsdSpectrumPainter: one class's channel as a flat PSD block on a
//     frequency axis centered on the channel. The block's area is the EIRP.
//     Outlines of the other widths sit behind it so the doubling is visible.
//
// COLOR (GL-003 §8.15.2, Keith 2026-09-25): a teaching simulator may give
// each category its own hue when the color carries the lesson. Each power
// class (SP, LPI, GVP, VLP) gets one hue from PsdPalette
// (six_ghz_psd_parts.dart), the single place the palette lives. Color is never
// the only carrier: every class also has its own stroke and marker shape
// (the FSPL Simulator's CurveStroke and CurveMarker) and a text label. The
// PSD limit and the grid are neutral. No status hue: nothing here is a
// pass/fail verdict.
//
// All colors and text styles arrive through [PsdChartStyle], built by the
// stage from context.colors, so dark (§8) and light (§8.20) both work.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../widgets/presenter/presenter_mode.dart';

import 'fspl_simulator_chart.dart' show CurveMarker, CurveStroke;

/// One plotted class: a value per width column.
@immutable
class PsdSeries {
  const PsdSeries({
    required this.values,
    required this.stroke,
    required this.marker,
    required this.color,
  });

  /// One y per width column, in column order.
  final List<double> values;
  final CurveStroke stroke;
  final CurveMarker marker;

  /// The class's hue from PsdPalette (§8.15.2).
  final Color color;
}

/// Theme-derived paints and text styles. Built by the stage from tokens.
@immutable
class PsdChartStyle {
  const PsdChartStyle({
    required this.ghost,
    required this.grid,
    required this.axis,
    required this.limit,
    required this.highlight,
    required this.pill,
    required this.surface,
    required this.axisLabel,
    required this.limitLabel,
    required this.pillLabel,
    required this.blockLabel,
    required this.emptyLabel,
    this.scale = PresenterScale.normal,
  });

  final Color ghost;
  final Color grid;
  final Color axis;
  final Color limit;

  /// Fill behind the selected width column.
  final Color highlight;
  final Color pill;

  /// The plot background, used to knock out behind labels and marker rims.
  final Color surface;
  final TextStyle axisLabel;
  final TextStyle limitLabel;
  final TextStyle pillLabel;
  final TextStyle blockLabel;
  final TextStyle emptyLabel;

  /// Presenter scale for strokes, markers and the axis gutters. The text
  /// styles above arrive already scaled (the stage applies paintFont).
  final PresenterScale scale;

  @override
  bool operator ==(Object other) =>
      other is PsdChartStyle &&
      other.scale == scale &&
      other.ghost == ghost &&
      other.grid == grid &&
      other.axis == axis &&
      other.limit == limit &&
      other.highlight == highlight &&
      other.pill == pill &&
      other.surface == surface &&
      other.axisLabel == axisLabel &&
      other.limitLabel == limitLabel &&
      other.pillLabel == pillLabel &&
      other.blockLabel == blockLabel &&
      other.emptyLabel == emptyLabel;

  @override
  int get hashCode => Object.hash(
    ghost,
    grid,
    axis,
    limit,
    highlight,
    pill,
    surface,
    axisLabel,
    limitLabel,
    pillLabel,
    blockLabel,
    emptyLabel,
    scale,
  );
}

/// Plot insets shared by both views.
abstract final class PsdChartPad {
  static const double left = 40;
  static const double right = 12;
  static const double top = 12;
  static const double bottom = 24;

  /// [k] grows the gutters with the axis labels (the presenter text scale;
  /// 1 elsewhere).
  static Rect plot(Size size, [double k = 1]) => Rect.fromLTRB(
    left * k,
    top * k,
    math.max(left * k + 1, size.width - right * k),
    math.max(top * k + 1, size.height - bottom * k),
  );
}

/// The column mapping shared by the width chart painter and its tap handler.
@immutable
class PsdWidthGeometry {
  const PsdWidthGeometry({
    required this.size,
    required this.columns,
    required this.yMin,
    required this.yMax,
    this.padScale = 1,
  });

  final Size size;
  final int columns;
  final double yMin;
  final double yMax;

  /// Gutter factor (the presenter text scale; 1 elsewhere).
  final double padScale;

  Rect get plot => PsdChartPad.plot(size, padScale);

  double get columnWidth => plot.width / columns;

  double xFor(int column) => plot.left + (column + 0.5) * columnWidth;

  double yFor(double v) {
    final Rect p = plot;
    return p.bottom - (v - yMin) / (yMax - yMin) * p.height;
  }

  /// Inverse of [xFor]: the column under x, clamped to the axis.
  int columnAt(double x) =>
      ((x - plot.left) / columnWidth).floor().clamp(0, columns - 1);
}

// ── Shared drawing helpers ─────────────────────────────────────────────────

Path _dash(Path source, double on, double off) {
  final Path out = Path();
  for (final ui.PathMetric m in source.computeMetrics()) {
    double at = 0;
    while (at < m.length) {
      out.addPath(m.extractPath(at, math.min(at + on, m.length)), Offset.zero);
      at += on + off;
    }
  }
  return out;
}

TextPainter _layout(
  String s,
  TextStyle ts, {
  double maxWidth = double.infinity,
  TextAlign align = TextAlign.left,
}) => TextPainter(
  text: TextSpan(text: s, style: ts),
  textDirection: TextDirection.ltr,
  textAlign: align,
)..layout(maxWidth: maxWidth);

/// Paints [s] so that [anchor] (0..1 of the text box) lands on [at].
void _text(
  Canvas canvas,
  String s,
  TextStyle ts,
  Offset at, {
  Offset anchor = Offset.zero,
  double maxWidth = double.infinity,
  TextAlign align = TextAlign.left,
  Color? knockout,
}) {
  final TextPainter tp = _layout(s, ts, maxWidth: maxWidth, align: align);
  final Offset o = at - Offset(tp.width * anchor.dx, tp.height * anchor.dy);
  if (knockout != null) {
    canvas.drawRect(
      Rect.fromLTWH(o.dx - 3, o.dy, tp.width + 6, tp.height),
      Paint()..color = knockout,
    );
  }
  tp.paint(canvas, o);
}

void _levelGrid(
  Canvas canvas,
  Rect p,
  double yMin,
  double yMax,
  double step,
  double Function(double) yFor,
  PsdChartStyle style,
) {
  final Paint minor = Paint()
    ..color = style.grid
    ..strokeWidth = style.scale.strokeWidth(1);
  final double first = (yMin / step).ceil() * step;
  for (double v = first; v <= yMax + 1e-9; v += step) {
    final double y = yFor(v);
    canvas.drawLine(Offset(p.left, y), Offset(p.right, y), minor);
    _text(
      canvas,
      v.toStringAsFixed(0),
      style.axisLabel,
      Offset(p.left - 6, y),
      anchor: const Offset(1, 0.5),
    );
  }
}

void _frame(Canvas canvas, Rect p, PsdChartStyle style) {
  canvas.drawRect(
    p,
    Paint()
      ..color = style.axis
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
}

void _marker(
  Canvas canvas,
  Offset c,
  CurveMarker shape,
  Color body,
  Color rim,
  PresenterScale scale,
) {
  final double r = scale.markerSize(5.5);
  final Path path = Path();
  switch (shape) {
    case CurveMarker.circle:
      path.addOval(Rect.fromCircle(center: c, radius: r));
    case CurveMarker.square:
      path.addRect(Rect.fromCenter(center: c, width: r * 1.8, height: r * 1.8));
    case CurveMarker.triangle:
      path
        ..moveTo(c.dx, c.dy - r * 1.1)
        ..lineTo(c.dx + r * 1.05, c.dy + r * 0.8)
        ..lineTo(c.dx - r * 1.05, c.dy + r * 0.8)
        ..close();
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = rim
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale.strokeWidth(4),
  );
  canvas.drawPath(path, Paint()..color = body);
}

void _pill(Canvas canvas, String label, double x, Rect p, PsdChartStyle style) {
  final TextPainter tp = _layout(label, style.pillLabel);
  final double w = tp.width + 10;
  final double left = (x - w / 2).clamp(p.left, p.right - w);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(left, p.top + 2, w, tp.height + 4),
      const Radius.circular(4),
    ),
    Paint()..color = style.pill,
  );
  tp.paint(canvas, Offset(left + 5, p.top + 4));
}

// ── Width chart ────────────────────────────────────────────────────────────

class PsdWidthChartPainter extends CustomPainter {
  PsdWidthChartPainter({
    required this.columnLabels,
    required this.selectedColumn,
    required this.yMin,
    required this.yMax,
    required this.yStep,
    required this.series,
    required this.style,
    required this.revision,
    this.emptyMessage,
  });

  final List<String> columnLabels;
  final int selectedColumn;
  final double yMin;
  final double yMax;
  final double yStep;
  final List<PsdSeries> series;
  final PsdChartStyle style;
  final int revision;

  /// Shown centered when there is nothing to draw (no class turned on).
  final String? emptyMessage;

  @override
  void paint(Canvas canvas, Size size) {
    final PsdWidthGeometry g = PsdWidthGeometry(
      size: size,
      columns: columnLabels.length,
      yMin: yMin,
      yMax: yMax,
      padScale: style.scale.text,
    );
    final Rect p = g.plot;

    // Selected column first, under everything.
    if (emptyMessage == null) {
      canvas.drawRect(
        Rect.fromLTWH(
          p.left + selectedColumn * g.columnWidth,
          p.top,
          g.columnWidth,
          p.height,
        ),
        Paint()..color = style.highlight,
      );
    }
    _levelGrid(canvas, p, yMin, yMax, yStep, g.yFor, style);
    final Paint colLine = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    for (int i = 0; i < columnLabels.length; i++) {
      final double x = g.xFor(i);
      canvas.drawLine(Offset(x, p.top), Offset(x, p.bottom), colLine);
      _text(
        canvas,
        columnLabels[i],
        style.axisLabel,
        Offset(x, p.bottom + 4),
        anchor: const Offset(0.5, 0),
      );
    }
    _frame(canvas, p, style);

    if (emptyMessage != null) {
      _text(
        canvas,
        emptyMessage!,
        style.emptyLabel,
        p.center,
        maxWidth: p.width - 16,
        align: TextAlign.center,
        anchor: const Offset(0.5, 0.5),
      );
      return;
    }

    canvas.save();
    canvas.clipRect(p.inflate(2));
    for (final PsdSeries s in series) {
      _line(canvas, g, s);
    }
    canvas.restore();

    // Markers: where several classes share a value at a column (SP AP and
    // fixed client, LPI AP and subordinate), spread them sideways so every
    // shape stays visible.
    for (int col = 0; col < columnLabels.length; col++) {
      final List<List<PsdSeries>> groups = <List<PsdSeries>>[];
      for (final PsdSeries s in series) {
        final double v = s.values[col];
        final List<PsdSeries>? same = groups
            .where(
              (List<PsdSeries> gr) => (gr.first.values[col] - v).abs() < 0.3,
            )
            .firstOrNull;
        same == null ? groups.add(<PsdSeries>[s]) : same.add(s);
      }
      for (final List<PsdSeries> gr in groups) {
        for (int k = 0; k < gr.length; k++) {
          final double v = gr[k].values[col];
          if (v < yMin || v > yMax) continue;
          final double dx =
              (k - (gr.length - 1) / 2) * style.scale.markerSize(12);
          _marker(
            canvas,
            Offset(g.xFor(col) + dx, g.yFor(v)),
            gr[k].marker,
            gr[k].color,
            style.surface,
            style.scale,
          );
        }
      }
    }
    _pill(
      canvas,
      columnLabels[selectedColumn],
      g.xFor(selectedColumn),
      p,
      style,
    );
  }

  void _line(Canvas canvas, PsdWidthGeometry g, PsdSeries s) {
    if (s.values.length < 2) return;
    final Path path = Path();
    for (int i = 0; i < s.values.length; i++) {
      final Offset o = Offset(g.xFor(i), g.yFor(s.values[i]));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    final Paint paint = Paint()
      ..color = s.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.scale.strokeWidth(2.5)
      ..strokeCap = s.stroke == CurveStroke.dotted
          ? StrokeCap.round
          : StrokeCap.butt
      ..strokeJoin = StrokeJoin.round;
    final double k = style.scale.stroke;
    switch (s.stroke) {
      case CurveStroke.solid:
        canvas.drawPath(path, paint);
      case CurveStroke.dashed:
        canvas.drawPath(_dash(path, 10 * k, 6 * k), paint);
      case CurveStroke.dotted:
        canvas.drawPath(_dash(path, 0.1, 6 * k), paint);
    }
  }

  @override
  bool shouldRepaint(PsdWidthChartPainter old) =>
      old.revision != revision || old.style != style;
}

// ── Spectrum view ──────────────────────────────────────────────────────────

/// One channel width's block on the spectrum view.
@immutable
class PsdBlock {
  const PsdBlock({required this.widthMHz, required this.psdDbmPerMHz});
  final int widthMHz;

  /// Radiated PSD, dBm/MHz: the block's height.
  final double psdDbmPerMHz;
}

class PsdSpectrumPainter extends CustomPainter {
  PsdSpectrumPainter({
    required this.selected,
    required this.blockColor,
    required this.others,
    required this.psdLimit,
    required this.psdLimitLabel,
    required this.blockLabel,
    required this.yMin,
    required this.yMax,
    required this.yStep,
    required this.style,
    required this.revision,
    this.emptyMessage,
  });

  /// Half-span of the frequency axis, MHz either side of the channel center.
  static const double spanMHz = 200;

  final PsdBlock? selected;

  /// The drawn class's hue from PsdPalette (§8.15.2).
  final Color blockColor;
  final List<PsdBlock> others;
  final double psdLimit;
  final String psdLimitLabel;
  final String blockLabel;
  final double yMin;
  final double yMax;
  final double yStep;
  final PsdChartStyle style;
  final int revision;
  final String? emptyMessage;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect p = PsdChartPad.plot(size, style.scale.text);
    double xFor(double mhz) =>
        p.left + (mhz + spanMHz) / (2 * spanMHz) * p.width;
    double yFor(double v) => p.bottom - (v - yMin) / (yMax - yMin) * p.height;

    _levelGrid(canvas, p, yMin, yMax, yStep, yFor, style);
    final Paint colLine = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    for (final double f in <double>[-160, -80, 0, 80, 160]) {
      final double x = xFor(f);
      canvas.drawLine(Offset(x, p.top), Offset(x, p.bottom), colLine);
      _text(
        canvas,
        f == 0 ? 'fc' : '${f > 0 ? '+' : ''}${f.round()}',
        style.axisLabel,
        Offset(x, p.bottom + 4),
        anchor: const Offset(0.5, 0),
      );
    }
    _frame(canvas, p, style);

    final PsdBlock? sel = selected;
    if (emptyMessage != null || sel == null) {
      _text(
        canvas,
        emptyMessage ?? '',
        style.emptyLabel,
        p.center,
        maxWidth: p.width - 16,
        align: TextAlign.center,
        anchor: const Offset(0.5, 0.5),
      );
      return;
    }

    canvas.save();
    canvas.clipRect(p);
    // Ghost outlines of the other widths.
    final Paint ghost = Paint()
      ..color = style.ghost
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.scale.strokeWidth(1.25);
    for (final PsdBlock b in others) {
      final Path o = Path()
        ..moveTo(xFor(-b.widthMHz / 2), p.bottom)
        ..lineTo(xFor(-b.widthMHz / 2), yFor(b.psdDbmPerMHz))
        ..lineTo(xFor(b.widthMHz / 2), yFor(b.psdDbmPerMHz))
        ..lineTo(xFor(b.widthMHz / 2), p.bottom);
      canvas.drawPath(_dash(o, 4, 3), ghost);
    }
    // The selected block: filled, lime outline.
    final Rect block = Rect.fromLTRB(
      xFor(-sel.widthMHz / 2),
      yFor(sel.psdDbmPerMHz),
      xFor(sel.widthMHz / 2),
      p.bottom,
    );
    canvas.drawRect(block, Paint()..color = blockColor.withValues(alpha: 0.22));
    canvas.drawPath(
      Path()
        ..moveTo(block.left, block.bottom)
        ..lineTo(block.left, block.top)
        ..lineTo(block.right, block.top)
        ..lineTo(block.right, block.bottom),
      Paint()
        ..color = blockColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.scale.strokeWidth(2.5),
    );
    // PSD limit.
    final double yl = yFor(psdLimit);
    canvas.drawPath(
      _dash(
        Path()
          ..moveTo(p.left, yl)
          ..lineTo(p.right, yl),
        6,
        4,
      ),
      Paint()
        ..color = style.limit
        ..strokeWidth = style.scale.strokeWidth(1.5)
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();

    // Limit label at the left end, above the line; block label inside the
    // block when it fits, otherwise above it.
    _text(
      canvas,
      psdLimitLabel,
      style.limitLabel,
      Offset(p.left + 4, yl - 2),
      anchor: const Offset(0, 1),
      knockout: style.surface,
    );
    final TextPainter bl = _layout(
      blockLabel,
      style.blockLabel,
      maxWidth: p.width - 8,
      align: TextAlign.center,
    );
    // Centered in the block when it fits; otherwise beside it, knocked out,
    // so a narrow 20 MHz block never hides its own label or the limit label.
    final bool inside =
        bl.width + 8 <= block.width && bl.height + 8 <= block.height;
    final double midY = (block.center.dy - bl.height / 2).clamp(
      yl + 4,
      p.bottom - bl.height - 2,
    );
    double bx;
    if (inside) {
      bx = block.center.dx - bl.width / 2;
    } else if (block.right + 8 + bl.width <= p.right - 4) {
      bx = block.right + 8;
    } else {
      bx = math.max(p.left + 4, block.left - 8 - bl.width);
    }
    final double by = midY;
    if (!inside) {
      canvas.drawRect(
        Rect.fromLTWH(bx - 3, by, bl.width + 6, bl.height),
        Paint()..color = style.surface,
      );
    }
    bl.paint(canvas, Offset(bx, by));
  }

  @override
  bool shouldRepaint(PsdSpectrumPainter old) =>
      old.revision != revision || old.style != style;
}
