// The to-scale preamble bar for the PHY Preamble Reference (Wi-Fi Classroom).
//
// Top to bottom:
//   - leader lanes: names of blocks too narrow to hold their own label, each
//     on a thin leader down to its block, packed so no label covers another
//     label or another leader;
//   - the bar: every preamble field to scale in microseconds, then a Data
//     stub of fixed width with a dashed open end (not to scale);
//   - the modulation row: BPSK or QBPSK under every SIG symbol (or B / Q when
//     the symbol is too narrow for the word);
//   - the axis, in microseconds;
//   - the bracket over the first 20 µs: the legacy preamble every PHY sends.
//
// The drawing is a picture of time. It draws no waveform, so it cannot imply
// a frequency change (Wi-Fi Classroom standing rule).
//
// Accessibility: the stage wraps this in a worded Semantics label and lists
// every block as a focusable button under the bar, so no fact rests on the
// drawing alone (SC 1.4.1). Colors come from phy_preamble_palette.dart.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/phy_preamble.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'phy_preamble_palette.dart';

/// Lane rows (left, right, leader x per label) and each block's placement
/// (row, left, leader x).
typedef _Packing = ({
  List<List<(double, double, double)>> rows,
  Map<int, (int, double, double)> pos,
});

/// Where one block's name is drawn.
class PreambleLabelPlacement {
  const PreambleLabelPlacement({
    required this.block,
    required this.text,
    required this.rect,
    required this.inside,
    this.leaderX,
  });

  final int block;
  final String text;

  /// The text's box, in bar coordinates.
  final Rect rect;

  /// True when drawn inside the block; false when in a lane with a leader.
  final bool inside;

  /// X of the leader line, for lane labels.
  final double? leaderX;
}

/// A BPSK / QBPSK mark under one SIG symbol.
class PreambleModulationMark {
  const PreambleModulationMark({
    required this.text,
    required this.centerX,
    required this.left,
    required this.right,
  });

  final String text;
  final double centerX;
  final double left;
  final double right;
}

/// Geometry shared by the painter, the hit test and the tests.
class PreambleBarLayout {
  PreambleBarLayout._({
    required this.blocks,
    required this.width,
    required this.masked,
    required this.pxPerTenth,
    required this.scaleWidth,
    required this.rects,
    required this.labels,
    required this.marks,
    required this.laneHeight,
    required this.laneCount,
    required this.barTop,
    required this.modTop,
    required this.axisTop,
    required this.bracketTop,
    required this.height,
    required this.axisStepTenths,
    required this.textHeight,
    required this.barHeight,
  });

  /// The bar's height on the phone and desktop layouts.
  static const double defaultBarHeight = AppSpacing.xl - AppSpacing.xs; // 40
  static const double dataStubWidth = AppSpacing.xl; // 48
  static const double gap = AppSpacing.xxs;

  final List<PreambleBlock> blocks;
  final double width;
  final bool masked;

  /// Pixels per tenth of a microsecond.
  final double pxPerTenth;

  /// Width of the to-scale part (everything but the Data stub).
  final double scaleWidth;

  /// One rect per block, Data stub last.
  final List<Rect> rects;
  final List<PreambleLabelPlacement> labels;
  final List<PreambleModulationMark> marks;
  final double laneHeight;
  final int laneCount;
  final double barTop;
  final double modTop;
  final double axisTop;
  final double bracketTop;
  final double height;
  final int axisStepTenths;
  final double textHeight;

  /// The blocks' height ([defaultBarHeight] unless the presenter stage asks
  /// for a taller bar).
  final double barHeight;

  double get barBottom => barTop + barHeight;

  /// X for [tenths] from the start of the PPDU.
  double xFor(int tenths) => tenths * pxPerTenth;

  /// The text shown for [b] when it is masked (a mystery PPDU).
  static bool isMasked(PreambleBlock b, bool masked) =>
      masked && b.role == BlockRole.added;

  static Size _measure(String s, TextStyle style, TextScaler scaler) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return tp.size;
  }

  static PreambleBarLayout compute({
    required List<PreambleBlock> blocks,
    required double width,
    required TextStyle labelStyle,
    required TextScaler textScaler,
    bool masked = false,
    double barHeight = defaultBarHeight,
  }) {
    final double w = math.max(width, dataStubWidth * 2);
    final int total = blocks
        .where((PreambleBlock b) => b.isToScale)
        .fold<int>(0, (int a, PreambleBlock b) => a + b.tenths);
    final double scaleWidth = w - dataStubWidth - gap;
    final double px = total == 0 ? 0 : scaleWidth / total;
    final double th = _measure('Ag', labelStyle, textScaler).height;
    final double laneH = th + gap;

    // Block rects in bar-local x (y filled in once the lane count is known).
    final List<(double, double)> xs = <(double, double)>[];
    int t = 0;
    for (final PreambleBlock b in blocks) {
      if (b.isToScale) {
        xs.add((t * px, (t + b.tenths) * px));
        t += b.tenths;
      } else {
        xs.add((scaleWidth + gap, w));
      }
    }

    // Labels: full name, then short name, inside the block; else a lane.
    final List<({int block, String text, double w, bool inside})> pending =
        <({int block, String text, double w, bool inside})>[];
    for (int i = 0; i < blocks.length; i++) {
      final PreambleBlock b = blocks[i];
      final double bw = xs[i].$2 - xs[i].$1;
      final String full = isMasked(b, masked) ? '?' : b.name;
      final String short = isMasked(b, masked) ? '?' : b.shortName;
      final double fw = _measure(full, labelStyle, textScaler).width;
      if (fw + gap * 2 <= bw) {
        pending.add((block: i, text: full, w: fw, inside: true));
        continue;
      }
      final double sw = _measure(short, labelStyle, textScaler).width;
      if (sw + gap * 2 <= bw) {
        pending.add((block: i, text: short, w: sw, inside: true));
        continue;
      }
      pending.add((block: i, text: full, w: fw, inside: false));
    }

    // Pack lane labels. Row 0 sits nearest the bar. Packing is tried left
    // to right and right to left; the order with fewer leaders crossing a
    // label wins, then the one with fewer rows.
    bool overlaps(double a0, double a1, double b0, double b1) =>
        a0 < b1 + gap && b0 < a1 + gap;
    final List<({int block, String text, double w, bool inside})> lanes =
        pending.where((p) => !p.inside).toList();
    _Packing pack(
      Iterable<({int block, String text, double w, bool inside})> order, {
      bool anchorLeft = false,
    }) {
      // Centered on the leader, or starting just left of it.
      double leftFor(double lx, double lw) =>
          (anchorLeft ? lx - gap : lx - lw / 2).clamp(
            0.0,
            math.max(0.0, w - lw),
          );
      final List<List<(double, double, double)>> rows =
          <List<(double, double, double)>>[];
      final Map<int, (int, double, double)> lanePos =
          <int, (int, double, double)>{};
      for (final ({int block, String text, double w, bool inside}) p in order) {
        final double x0 = xs[p.block].$1;
        final double x1 = xs[p.block].$2;
        final double mid = (x0 + x1) / 2;
        // The leader may meet its block anywhere along it: the center first,
        // then points stepping outward, so it can slip past a lower label.
        final List<double> leaderXs = <double>[mid];
        for (double d = gap; d < (x1 - x0) / 2 - 1; d += gap) {
          leaderXs
            ..add(mid - d)
            ..add(mid + d);
        }

        // Lowest row where the label fits. Preferred: its leader crosses no
        // label in a lower row. That can be impossible, so the second pass
        // drops that preference. A new row on top always satisfies the rest,
        // so both passes end. r == rows.length stands for a new, empty row.
        bool fits(int r, double lx, {required bool strict}) {
          final double left = leftFor(lx, p.w);
          final double right = left + p.w;
          if (r < rows.length) {
            for (final (double, double, double) o in rows[r]) {
              if (overlaps(left, right, o.$1, o.$2)) return false;
            }
          }
          // The label must not sit on a leader from a higher row.
          for (int hr = r + 1; hr < rows.length; hr++) {
            for (final (double, double, double) o in rows[hr]) {
              if (o.$3 >= left - gap && o.$3 <= right + gap) return false;
            }
          }
          if (strict) {
            // Its own leader must not pass through a label in a lower row.
            for (int lr = 0; lr < r; lr++) {
              for (final (double, double, double) o in rows[lr]) {
                if (lx >= o.$1 - gap && lx <= o.$2 + gap) return false;
              }
            }
          }
          return true;
        }

        int? placed;
        double lx = mid;
        search:
        for (final bool strict in <bool>[true, false]) {
          for (int r = 0; r <= rows.length; r++) {
            for (final double x in strict ? leaderXs : <double>[mid]) {
              if (fits(r, x, strict: strict)) {
                placed = r;
                lx = x;
                break search;
              }
            }
          }
        }
        // The non-strict pass always accepts the new top row.
        placed ??= rows.length;
        if (placed == rows.length) rows.add(<(double, double, double)>[]);
        final double left = leftFor(lx, p.w);
        rows[placed].add((left, left + p.w, lx));
        lanePos[p.block] = (placed, left, lx);
      }
      return (rows: rows, pos: lanePos);
    }

    int crossings(List<List<(double, double, double)>> rows) {
      int n = 0;
      for (int hr = 0; hr < rows.length; hr++) {
        for (final (double, double, double) a in rows[hr]) {
          for (int lr = 0; lr < hr; lr++) {
            for (final (double, double, double) b in rows[lr]) {
              if (a.$3 >= b.$1 && a.$3 <= b.$2) n++;
            }
          }
        }
      }
      return n;
    }

    final List<_Packing> tries = <_Packing>[
      pack(lanes),
      pack(lanes.reversed),
      // Right to left, each label starting at its leader: a lower label then
      // starts right of every higher label's leader.
      pack(lanes.reversed, anchorLeft: true),
    ];
    _Packing best = tries.first;
    for (final _Packing t in tries.skip(1)) {
      final int ct = crossings(t.rows);
      final int cb = crossings(best.rows);
      if (ct < cb || (ct == cb && t.rows.length < best.rows.length)) best = t;
    }
    final List<List<(double, double, double)>> rows = best.rows;
    final Map<int, (int, double, double)> lanePos = best.pos;

    final int laneCount = rows.length;
    final double laneBlock = laneCount == 0 ? 0 : laneCount * laneH + gap * 2;
    final double barTop = laneBlock;
    final double modTop = barTop + barHeight + gap;
    final double axisTop = modTop + th + gap;
    final double bracketTop = axisTop + th + gap * 2;
    final double height = bracketTop + gap * 2 + th;

    final List<Rect> rects = <Rect>[
      for (final (double, double) x in xs)
        Rect.fromLTRB(x.$1, barTop, x.$2, barTop + barHeight),
    ];

    final List<PreambleLabelPlacement> labels = <PreambleLabelPlacement>[];
    for (final ({int block, String text, double w, bool inside}) p in pending) {
      if (p.inside) {
        final Rect r = rects[p.block];
        labels.add(
          PreambleLabelPlacement(
            block: p.block,
            text: p.text,
            inside: true,
            rect: Rect.fromLTWH(
              r.center.dx - p.w / 2,
              r.top + (barHeight - th) / 2,
              p.w,
              th,
            ),
          ),
        );
      } else {
        final (int, double, double) lp = lanePos[p.block]!;
        // Row 0 is the lowest lane.
        final double top = barTop - gap - (lp.$1 + 1) * laneH;
        labels.add(
          PreambleLabelPlacement(
            block: p.block,
            text: p.text,
            inside: false,
            rect: Rect.fromLTWH(lp.$2, top, p.w, th),
            leaderX: lp.$3,
          ),
        );
      }
    }

    // Modulation marks, one per SIG symbol.
    final double wordW = _measure('QBPSK', labelStyle, textScaler).width;
    final List<PreambleModulationMark> marks = <PreambleModulationMark>[];
    for (int i = 0; i < blocks.length; i++) {
      final PreambleBlock b = blocks[i];
      if (b.modulations.isEmpty) continue;
      final double sw = (xs[i].$2 - xs[i].$1) / b.modulations.length;
      for (int s = 0; s < b.modulations.length; s++) {
        final double l = xs[i].$1 + s * sw;
        final SymbolModulation m = b.modulations[s];
        marks.add(
          PreambleModulationMark(
            text: sw >= wordW + gap ? m.label : m.letter,
            centerX: l + sw / 2,
            left: l,
            right: l + sw,
          ),
        );
      }
    }

    // Axis step: the smallest nice step whose labels do not crowd.
    final double labelW = _measure('000', labelStyle, textScaler).width;
    int step = 40;
    for (final int s in <int>[20, 40, 50, 80, 100, 200, 400, 500, 1000]) {
      step = s;
      if (s * px >= labelW + AppSpacing.sm) break;
    }

    return PreambleBarLayout._(
      blocks: blocks,
      width: w,
      masked: masked,
      pxPerTenth: px,
      scaleWidth: scaleWidth,
      rects: rects,
      labels: labels,
      marks: marks,
      laneHeight: laneH,
      laneCount: laneCount,
      barTop: barTop,
      modTop: modTop,
      axisTop: axisTop,
      bracketTop: bracketTop,
      height: height,
      axisStepTenths: step,
      textHeight: th,
      barHeight: barHeight,
    );
  }

  /// The block under [p]: its rect, or its lane label.
  int? hitTest(Offset p) {
    for (int i = 0; i < rects.length; i++) {
      if (rects[i].inflate(1).contains(p)) return i;
    }
    for (final PreambleLabelPlacement l in labels) {
      if (!l.inside && l.rect.inflate(gap).contains(p)) return l.block;
    }
    return null;
  }
}

class PreambleBarPainter extends CustomPainter {
  PreambleBarPainter({
    required this.layout,
    required this.colors,
    required this.labelStyle,
    required this.textScaler,
    required this.selected,
    this.scale = PresenterScale.normal,
  });

  final PreambleBarLayout layout;
  final AppColorScheme colors;
  final TextStyle labelStyle;
  final TextScaler textScaler;
  final int? selected;

  /// Presenter scale for strokes (text already follows [textScaler]).
  final PresenterScale scale;

  void _text(Canvas c, String s, Offset at, Color color, {FontWeight? weight}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s,
        style: labelStyle.copyWith(color: color, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    tp.paint(c, at);
  }

  double _textWidth(String s) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: s, style: labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final PreambleBarLayout l = layout;
    final double sw = scale.strokeWidth(colors.isLight ? 1.5 : 1);

    // Blocks.
    for (int i = 0; i < l.blocks.length; i++) {
      final PreambleBlock b = l.blocks[i];
      final bool m = PreambleBarLayout.isMasked(b, l.masked);
      final PreambleBlockStyle st = preambleBlockStyle(b, colors, masked: m);
      // Filled blocks stop short of their neighbors so two signal fields
      // side by side (RL-SIG, HE-SIG-A) still read as two blocks.
      final Rect r0 = l.rects[i].deflate(0.5);
      final Rect r = b.form == BlockForm.signal
          ? Rect.fromLTRB(r0.left + 1, r0.top, r0.right - 1, r0.bottom)
          : r0;
      canvas.drawRect(r, Paint()..color = st.fill);
      final Paint border = Paint()
        ..color = st.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = b.form == BlockForm.training && !m
            ? scale.strokeWidth(2)
            : sw;
      if (b.role == BlockRole.data) {
        // Open, dashed right end: the data field continues past the drawing.
        canvas.drawLine(r.topLeft, r.bottomLeft, border);
        _dashed(canvas, r.topLeft, r.topRight, border);
        _dashed(canvas, r.bottomLeft, r.bottomRight, border);
      } else {
        canvas.drawRect(
          r.deflate(b.form == BlockForm.training ? 1 : 0),
          border,
        );
      }
      // Symbol and repeat dividers.
      if (b.count > 1 && b.isToScale) {
        final Paint div = Paint()
          ..color = st.label.withValues(alpha: 0.55)
          ..strokeWidth = scale.strokeWidth(1);
        final double step = r.width / b.count;
        // Ticks at the top and bottom edges only, so they never cut
        // through the block's label.
        for (int s = 1; s < b.count; s++) {
          final double x = r.left + step * s;
          canvas.drawLine(
            Offset(x, r.top),
            Offset(x, r.top + AppSpacing.xs),
            div,
          );
          canvas.drawLine(
            Offset(x, r.bottom - AppSpacing.xs),
            Offset(x, r.bottom),
            div,
          );
        }
      }
    }

    // Labels and leaders.
    for (final PreambleLabelPlacement p in l.labels) {
      final PreambleBlock b = l.blocks[p.block];
      final bool m = PreambleBarLayout.isMasked(b, l.masked);
      final PreambleBlockStyle st = preambleBlockStyle(b, colors, masked: m);
      if (p.inside) {
        _text(
          canvas,
          p.text,
          p.rect.topLeft,
          st.label,
          weight: FontWeight.w600,
        );
      } else {
        final double x = p.leaderX!;
        canvas.drawLine(
          Offset(x, p.rect.bottom),
          Offset(x, l.barTop),
          Paint()
            ..color = colors.borderStrong
            ..strokeWidth = scale.strokeWidth(1),
        );
        _text(canvas, p.text, p.rect.topLeft, colors.textSecondary);
      }
    }

    // Selection ring.
    if (selected != null && selected! < l.rects.length) {
      canvas.drawRect(
        l.rects[selected!].inflate(scale.strokeWidth(1.5)),
        Paint()
          ..color = colors.textPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = scale.strokeWidth(2.5),
      );
    }

    // Modulation marks.
    for (final PreambleModulationMark mk in l.marks) {
      final double tw = _textWidth(mk.text);
      _text(
        canvas,
        mk.text,
        Offset(mk.centerX - tw / 2, l.modTop),
        colors.textPrimary,
        weight: FontWeight.w600,
      );
    }

    // Axis.
    final Paint axis = Paint()
      ..color = colors.borderStrong
      ..strokeWidth = scale.strokeWidth(1);
    canvas.drawLine(
      Offset(0, l.axisTop),
      Offset(l.scaleWidth, l.axisTop),
      axis,
    );
    final int total = l.blocks
        .where((PreambleBlock b) => b.isToScale)
        .fold<int>(0, (int a, PreambleBlock b) => a + b.tenths);
    for (int t = 0; t <= total; t += l.axisStepTenths) {
      final double x = l.xFor(t);
      canvas.drawLine(
        Offset(x, l.axisTop),
        Offset(x, l.axisTop + AppSpacing.xxs),
        axis,
      );
      final String s = formatPreambleTenths(t);
      final double tw = _textWidth(s);
      final double left = (x - tw / 2).clamp(0.0, l.scaleWidth - tw);
      _text(
        canvas,
        s,
        Offset(left, l.axisTop + AppSpacing.xxs),
        colors.textTertiary,
      );
    }
    final String unit = 'µs';
    _text(
      canvas,
      unit,
      Offset(l.scaleWidth + PreambleBarLayout.gap, l.axisTop + AppSpacing.xxs),
      colors.textTertiary,
    );

    // Legacy bracket over 0-20 us.
    final Color legacy = preambleRoleHue(BlockRole.legacy, colors);
    final Paint br = Paint()
      ..color = legacy
      ..strokeWidth = scale.strokeWidth(2);
    final double x20 = l.xFor(kLegacyPreambleTenths);
    final double by = l.bracketTop;
    canvas.drawLine(Offset(1, by), Offset(x20 - 1, by), br);
    canvas.drawLine(
      Offset(1, by - AppSpacing.xxs),
      Offset(1, by + AppSpacing.xxs),
      br,
    );
    canvas.drawLine(
      Offset(x20 - 1, by - AppSpacing.xxs),
      Offset(x20 - 1, by + AppSpacing.xxs),
      br,
    );
    String label = 'Legacy 20 µs, in every PHY';
    if (_textWidth(label) > l.width - AppSpacing.xs) label = 'Legacy 20 µs';
    final double lw = _textWidth(label);
    final double lx = (x20 / 2 - lw / 2).clamp(
      0.0,
      math.max(0.0, l.width - lw),
    );
    _text(
      canvas,
      label,
      Offset(lx, by + AppSpacing.xxs),
      legacy,
      weight: FontWeight.w600,
    );
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p) {
    const double dash = 4;
    const double space = 3;
    final double len = (b - a).distance;
    final Offset dir = (b - a) / len;
    double d = 0;
    while (d < len) {
      final double e = math.min(d + dash, len);
      c.drawLine(a + dir * d, a + dir * e, p);
      d = e + space;
    }
  }

  @override
  bool shouldRepaint(PreambleBarPainter old) =>
      old.layout != layout ||
      old.colors != colors ||
      old.selected != selected ||
      old.labelStyle != labelStyle ||
      old.scale != scale ||
      old.textScaler != textScaler;
}

/// A legend swatch: a small block in the given style.
class PreambleSwatchPainter extends CustomPainter {
  PreambleSwatchPainter({required this.style, required this.training});

  final PreambleBlockStyle style;
  final bool training;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = (Offset.zero & size).deflate(1);
    canvas.drawRect(r, Paint()..color = style.fill);
    canvas.drawRect(
      r,
      Paint()
        ..color = style.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = training ? 2 : 1,
    );
  }

  @override
  bool shouldRepaint(PreambleSwatchPainter old) =>
      old.style.fill != style.fill ||
      old.style.border != style.border ||
      old.training != training;
}
