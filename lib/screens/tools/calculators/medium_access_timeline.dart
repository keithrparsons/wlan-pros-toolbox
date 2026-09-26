// Timeline painter for the Medium Access Simulator (Wi-Fi Classroom).
//
// One lane for the medium (what the AP hears) plus one lane per station. The
// canvas always ends at "now" on its right edge and covers the last
// [TimelineZoom.windowUs] of simulated time; it sits inside a horizontal
// scroll view in its card, so the page never scrolls sideways. Only the part
// inside the scroll viewport is painted.
//
// COLOR (GL-003 §8.13 / §8.15). Stations are NOT told apart by hue: §8.15
// rules out a categorical palette, so a station is its lane and its letter.
// Lime (a FILL, §8.20.2) marks the one quantity the tool is about, a data
// frame on the air. The two status hues appear only as verdicts: danger on a
// frame that was lost (collision), success on the ACK that confirms delivery.
// Everything else is the neutral stack: hatching for AIFS/EIFS waits, an
// outlined cell per backoff slot with its count, a filled neutral cell for a
// frozen count.
//
// Accessibility: the painting is a picture. The screen supplies a worded
// status line and a legend with text, so no fact is carried by the drawing
// alone (SC 1.4.1).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/medium_access_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

/// Horizontal scale of the timeline.
enum TimelineZoom {
  slots('Slots', 2.0, 1500, 50),
  frames('Frames', 0.6, 5000, 200),
  wide('Wide', 0.2, 15000, 500);

  const TimelineZoom(this.label, this.pxPerUs, this.windowUs, this.tickUs);

  final String label;

  /// Logical pixels per simulated microsecond.
  final double pxPerUs;

  /// Simulated time the canvas spans.
  final int windowUs;

  /// Axis tick spacing.
  final int tickUs;

  double get canvasWidth => windowUs * pxPerUs;
}

/// Row geometry shared by the painter and the lane-label column.
class TimelineGeometry {
  TimelineGeometry._();

  static const double laneHeight = AppSpacing.lg;
  static const double laneGap = AppSpacing.xxs;
  static const double axisHeight = AppSpacing.md;

  /// Top of lane [row] (row 0 is the medium lane). [k] scales the lanes
  /// (the presenter layout fits them to the room; 1 everywhere else).
  static double laneTop(int row, [double k = 1]) =>
      row * (laneHeight * k + laneGap);

  /// Total canvas height for [stations] station lanes plus the medium lane.
  static double height(int stations, [double k = 1]) =>
      laneTop(stations + 1, k) + axisHeight * k;
}

/// Every visual kind a block on the timeline can take. Shared by the painter
/// and the legend so the two can never drift apart.
enum BlockStyle {
  wait,
  eifs,
  backoff,
  frozen,
  nav,
  data,
  control,
  lost,
  ack,
  awaiting,
}

/// Draws one block. Used by the timeline and by the legend swatches.
void paintTimelineBlock(
  Canvas canvas,
  Rect rect,
  BlockStyle style,
  AppColorScheme colors, [
  double stroke = 1,
]) {
  switch (style) {
    case BlockStyle.wait:
    case BlockStyle.eifs:
      _hatch(
        canvas,
        rect,
        style == BlockStyle.eifs ? colors.borderStrong : colors.textTertiary,
        dense: style == BlockStyle.eifs,
        stroke: stroke,
      );
    case BlockStyle.backoff:
      canvas.drawRect(
        rect.deflate(0.5 * stroke),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = colors.borderStrong,
      );
    case BlockStyle.frozen:
    case BlockStyle.nav:
      canvas.drawRect(rect, Paint()..color = colors.border);
      if (style == BlockStyle.nav) {
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, rect.width, 2 * stroke),
          Paint()..color = colors.textTertiary,
        );
      }
    case BlockStyle.data:
      canvas.drawRect(rect, Paint()..color = colors.primary);
      canvas.drawRect(
        rect.deflate(0.5 * stroke),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = colors.textAccent,
      );
    case BlockStyle.control:
      canvas.drawRect(
        rect.deflate(0.75 * stroke),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * stroke
          ..color = colors.textSecondary,
      );
    case BlockStyle.lost:
    case BlockStyle.ack:
      final Color hue = style == BlockStyle.lost
          ? colors.statusDanger
          : colors.statusSuccess;
      // §8.13 rule 3: a low-alpha tint band plus the full-strength hue as the
      // 2px boundary; the label on top is textPrimary.
      canvas.drawRect(rect, Paint()..color = hue.withValues(alpha: 0.3));
      canvas.drawRect(
        rect.deflate(stroke),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * stroke
          ..color = hue,
      );
    case BlockStyle.awaiting:
      final double y = rect.center.dy;
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(rect.right, y),
        Paint()
          ..strokeWidth = stroke
          ..color = colors.textTertiary,
      );
  }
}

/// The label color that sits on a block of [style].
Color timelineLabelColor(BlockStyle style, AppColorScheme colors) {
  switch (style) {
    case BlockStyle.data:
      return colors.onPrimary;
    case BlockStyle.frozen:
    case BlockStyle.nav:
    case BlockStyle.backoff:
      return colors.textSecondary;
    case BlockStyle.wait:
    case BlockStyle.eifs:
    case BlockStyle.awaiting:
      return colors.textSecondary;
    case BlockStyle.control:
    case BlockStyle.lost:
    case BlockStyle.ack:
      return colors.textPrimary;
  }
}

void _hatch(
  Canvas canvas,
  Rect rect,
  Color color, {
  required bool dense,
  double stroke = 1,
}) {
  final double step = (dense ? AppSpacing.xxs : AppSpacing.xs) * stroke;
  final Paint p = Paint()
    ..color = color
    ..strokeWidth = stroke;
  canvas.save();
  canvas.clipRect(rect);
  final double h = rect.height;
  for (double x = rect.left - h; x < rect.right; x += step) {
    canvas.drawLine(Offset(x, rect.bottom), Offset(x + h, rect.top), p);
  }
  canvas.restore();
}

/// Caches laid-out label text so the painter does not rebuild a TextPainter
/// for every slot number on every frame. Owned by the screen state.
class TimelineLabelCache {
  final Map<String, TextPainter> _cache = <String, TextPainter>{};

  TextPainter label(String text, TextStyle style) {
    final String key = '$text|${style.color?.toARGB32()}|${style.fontSize}';
    return _cache.putIfAbsent(key, () {
      if (_cache.length > 600) _cache.clear();
      return TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
    });
  }

  void clear() => _cache.clear();
}

/// Paints the lanes. Repaints when [scroll] moves so culling stays correct.
class MediumAccessTimelinePainter extends CustomPainter {
  MediumAccessTimelinePainter({
    required this.engine,
    required this.nowUs,
    required this.zoom,
    required this.colors,
    required this.labelStyle,
    required this.monoStyle,
    required this.labels,
    required this.scroll,
    required this.legacyDcf,
    this.laneScale = 1,
    this.timeScale = 1,
    this.strokeScale = 1,
  }) : super(repaint: scroll);

  final MediumAccessEngine engine;

  /// Snapshot of the engine clock this frame paints; part of the repaint key.
  final int nowUs;
  final TimelineZoom zoom;
  final AppColorScheme colors;
  final TextStyle labelStyle;
  final TextStyle monoStyle;
  final TimelineLabelCache labels;
  final ScrollController scroll;

  /// Label the plain wait "DIFS" in legacy mode and "AIFS" under EDCA.
  final bool legacyDcf;

  /// Presenter scales: lane height, pixels per microsecond, line widths.
  /// All 1 outside presenter mode.
  final double laneScale;
  final double timeScale;
  final double strokeScale;

  double get _pxPerUs => zoom.pxPerUs * timeScale;

  double _labelLeft = 0;
  double _labelRight = double.infinity;

  double _x(int us) => (us - (nowUs - zoom.windowUs)) * _pxPerUs;

  @override
  void paint(Canvas canvas, Size size) {
    double visLeft = 0;
    double visRight = size.width;
    if (scroll.hasClients && scroll.position.hasContentDimensions) {
      visLeft = scroll.position.pixels;
      visRight = visLeft + scroll.position.viewportDimension;
    }
    // Labels center on the visible slice of a block, so a long frame that
    // runs off the viewport still shows its sender.
    _labelLeft = visLeft;
    _labelRight = visRight;
    // Margin so a block straddling the edge still draws.
    visLeft -= AppSpacing.xl;
    visRight += AppSpacing.xl;

    final int nStations = engine.config.stations.length;
    final double k = laneScale;
    final double lh = TimelineGeometry.laneHeight * k;

    // Lane backgrounds: a decorative hairline under each lane.
    final Paint rule = Paint()
      ..color = colors.border
      ..strokeWidth = strokeScale;
    for (int row = 0; row <= nStations; row++) {
      final double y = TimelineGeometry.laneTop(row, k) + lh;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
    }

    // Station lanes (rows 1..n).
    for (final LaneSegment s in engine.segments) {
      final double x0 = _x(s.startUs);
      final double x1 = _x(s.endUs);
      if (x1 < visLeft || x0 > visRight) continue;
      final Rect r = Rect.fromLTRB(
        x0,
        TimelineGeometry.laneTop(s.lane + 1, k),
        x1,
        TimelineGeometry.laneTop(s.lane + 1, k) + lh,
      );
      final BlockStyle style = _styleFor(s);
      paintTimelineBlock(canvas, r, style, colors, strokeScale);
      _label(canvas, r, _textFor(s), style);
    }

    // Medium lane (row 0): what the AP hears. Overlapping frames paint on
    // top of each other; a collision cluster gets ONE label naming everyone
    // in it, drawn across the cluster's full span.
    final List<AirFrame> air = engine.airFrames;
    for (int i = 0; i < air.length; i++) {
      final AirFrame f = air[i];
      final double x0 = _x(f.startUs);
      final double x1 = _x(f.endUs);
      if (x1 < visLeft || x0 > visRight) continue;
      final BlockStyle style = _airStyle(f);
      paintTimelineBlock(
        canvas,
        Rect.fromLTRB(x0, 0, x1, lh),
        style,
        colors,
        strokeScale,
      );
    }
    int clusterEnd = -1;
    for (int i = 0; i < air.length; i++) {
      final AirFrame f = air[i];
      if (f.startUs < clusterEnd) continue; // already labeled with its cluster
      int end = f.endUs;
      final List<AirFrame> cluster = <AirFrame>[f];
      for (int j = i + 1; j < air.length && air[j].startUs < end; j++) {
        cluster.add(air[j]);
        if (air[j].endUs > end) end = air[j].endUs;
      }
      clusterEnd = end;
      final double x0 = _x(f.startUs);
      final double x1 = _x(end);
      if (x1 < visLeft || x0 > visRight) continue;
      final Rect r = Rect.fromLTRB(x0, 0, x1, lh);
      if (cluster.length == 1) {
        _label(canvas, r, _airText(f), _airStyle(f));
      } else {
        final String who = cluster
            .map(
              (AirFrame c) => c.fromAp
                  ? (c.kind == FrameKind.ack ? 'ACK' : 'CTS')
                  : stationLetter(c.source),
            )
            .join('+');
        _label(canvas, r, '$who collide', BlockStyle.lost);
      }
    }

    _axis(canvas, size, visLeft, visRight, nStations);
  }

  BlockStyle _styleFor(LaneSegment s) {
    switch (s.activity) {
      case LaneActivity.aifs:
        return BlockStyle.wait;
      case LaneActivity.eifs:
        return BlockStyle.eifs;
      case LaneActivity.backoff:
        return BlockStyle.backoff;
      case LaneActivity.frozen:
        return BlockStyle.frozen;
      case LaneActivity.nav:
        return BlockStyle.nav;
      case LaneActivity.awaitResponse:
        return BlockStyle.awaiting;
      case LaneActivity.transmit:
        if (s.failed) return BlockStyle.lost;
        return s.frame == FrameKind.data ? BlockStyle.data : BlockStyle.control;
    }
  }

  String _textFor(LaneSegment s) {
    switch (s.activity) {
      case LaneActivity.aifs:
        return legacyDcf ? 'DIFS' : 'AIFS';
      case LaneActivity.eifs:
        return 'EIFS';
      case LaneActivity.backoff:
      case LaneActivity.frozen:
        return '${s.count ?? ''}';
      case LaneActivity.nav:
        return 'NAV';
      case LaneActivity.awaitResponse:
        return '';
      case LaneActivity.transmit:
        final String kind = s.frame == FrameKind.rts ? 'RTS' : 'Data';
        return s.failed ? '$kind lost' : kind;
    }
  }

  BlockStyle _airStyle(AirFrame f) {
    if (f.fromAp) {
      if (f.corruptedAtTarget) return BlockStyle.lost;
      return f.kind == FrameKind.ack ? BlockStyle.ack : BlockStyle.control;
    }
    if (f.corruptedAtAp) return BlockStyle.lost;
    return f.kind == FrameKind.data ? BlockStyle.data : BlockStyle.control;
  }

  String _airText(AirFrame f) {
    if (f.fromAp) {
      final String to = f.target == null ? '' : ' ${stationLetter(f.target!)}';
      return '${f.kind == FrameKind.ack ? 'ACK' : 'CTS'}$to';
    }
    final String who = stationLetter(f.source);
    final String kind = f.kind == FrameKind.rts ? 'RTS ' : '';
    return '$kind$who';
  }

  void _label(Canvas canvas, Rect block, String text, BlockStyle style) {
    if (text.isEmpty) return;
    final double left = block.left < _labelLeft ? _labelLeft : block.left;
    final double right = block.right > _labelRight ? _labelRight : block.right;
    if (right <= left) return;
    final Rect r = Rect.fromLTRB(left, block.top, right, block.bottom);
    final TextStyle st = labelStyle.copyWith(
      color: timelineLabelColor(style, colors),
    );
    final TextPainter tp = labels.label(text, st);
    if (tp.width + AppSpacing.xxs > r.width) {
      // Try the short form before giving up. A lost frame keeps the word
      // that says it was lost, so the verdict is never color-only (SC 1.4.1).
      final String short = text.endsWith(' lost')
          ? 'Lost'
          : text.split(' ').first;
      if (short == text) return;
      final TextPainter sp = labels.label(short, st);
      if (sp.width + AppSpacing.xxs > r.width) return;
      _drawCentered(canvas, sp, r, style);
      return;
    }
    _drawCentered(canvas, tp, r, style);
  }

  void _drawCentered(Canvas canvas, TextPainter tp, Rect r, BlockStyle style) {
    // Hatched waits get a solid chip behind the word so it reads over lines.
    final Offset o = Offset(
      r.center.dx - tp.width / 2,
      r.center.dy - tp.height / 2,
    );
    if (style == BlockStyle.wait || style == BlockStyle.eifs) {
      canvas.drawRect(
        Rect.fromLTWH(o.dx - 2, o.dy, tp.width + 4, tp.height),
        Paint()..color = colors.surface1,
      );
    }
    tp.paint(canvas, o);
  }

  void _axis(
    Canvas canvas,
    Size size,
    double visLeft,
    double visRight,
    int nStations,
  ) {
    final double top = TimelineGeometry.laneTop(nStations + 1, laneScale);
    final Paint tick = Paint()
      ..color = colors.borderStrong
      ..strokeWidth = strokeScale;
    final TextStyle st = monoStyle.copyWith(color: colors.textTertiary);
    final int start = nowUs - zoom.windowUs;
    int first = (start ~/ zoom.tickUs) * zoom.tickUs;
    if (first < start) first += zoom.tickUs;
    for (int us = first; us <= nowUs; us += zoom.tickUs) {
      if (us < 0) continue;
      final double x = _x(us);
      if (x < visLeft || x > visRight) continue;
      final double tickH = AppSpacing.xxs * laneScale;
      canvas.drawLine(Offset(x, top), Offset(x, top + tickH), tick);
      final TextPainter tp = labels.label(_fmtUs(us), st);
      tp.paint(canvas, Offset(x - tp.width / 2, top + tickH));
    }
    // The "now" edge.
    final double nx = size.width - 1;
    canvas.drawLine(
      Offset(nx, 0),
      Offset(nx, top),
      Paint()
        ..color = colors.textAccent
        ..strokeWidth = 2 * strokeScale,
    );
  }

  static String _fmtUs(int us) {
    if (us < 1000) return '$us µs';
    return '${(us / 1000).toStringAsFixed(us % 1000 == 0 ? 0 : 2)} ms';
  }

  @override
  bool shouldRepaint(MediumAccessTimelinePainter old) =>
      old.nowUs != nowUs ||
      old.engine != engine ||
      old.zoom != zoom ||
      old.colors != colors ||
      old.legacyDcf != legacyDcf ||
      old.laneScale != laneScale ||
      old.timeScale != timeScale ||
      old.strokeScale != strokeScale ||
      old.labelStyle != labelStyle;
}
