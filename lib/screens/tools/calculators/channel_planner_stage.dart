// ChannelPlannerStage: the floor and spectrum half of the Channel Planner.
//
// The stage is everything the student watches: the top-down floor with the
// APs, walls, contention links and the largest domain outlined, and under it
// a spectrum strip showing which channels are occupied across the band. It
// takes a ChannelPlannerState and knows nothing about the controls, so a
// screen can stack it above them (phone), beside them (desktop) or full
// screen beside them (the presenter layout, spec 00).
//
// INTERACTION: tap an AP to select it, drag it to move it. With the wall tool
// on, drag on the floor to draw a wall. Every one of these has a keyboard and
// screen-reader path in the controls (AP picker, position sliders, walls
// across the floor).
//
// THEME: context.colors for everything except the channel hues, which come
// from channel_planner_palette.dart under GL-003 §8.15.2. No motion, so
// reduced motion needs nothing (§8.8).
//
// PRESENTER (spec 00): inside a PresenterLayout the floor takes the height
// the verdict strip, spectrum and legend leave, and the plan's verdict (the
// largest contention domain, airtime each, channels at this width) sits over
// the floor, where the class looks. Painted labels, strokes and AP markers
// read PresenterMode.scaleOf (1.0 outside presenter mode).
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/channel_planner_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter.dart';
import 'channel_planner_palette.dart';
import 'channel_planner_panels.dart' show channelPlanVerdict, PlanVerdict;
import 'channel_planner_state.dart';

/// Floor width at which every link carries its dBm label. Narrower floors
/// label only the selected AP's links; the readouts list all of them.
const double _kAllLabelsWidth = 560;

/// Padding around the floor rectangle so edge APs and their labels fit.
const double _kFloorPad = 28;

class ChannelPlannerStage extends StatelessWidget {
  const ChannelPlannerStage({
    super.key,
    required this.state,
    required this.maxFloorHeight,
  });

  final ChannelPlannerState state;

  /// The tallest the floor may draw. A presenter layout passes more.
  final double maxFloorHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, Widget? _) =>
          PresenterMode.isActive(context)
          ? _buildPresenter(context)
          : _build(context),
    );
  }

  BoxDecoration _cardDecoration(AppColorScheme colors) => BoxDecoration(
    color: colors.surface1,
    borderRadius: BorderRadius.circular(AppRadius.card),
    border: Border.all(color: colors.border, width: colors.isLight ? 1.5 : 1),
  );

  /// Presenter: verdict strip, then the floor filling the height left over,
  /// then the spectrum and legend. Nothing scrolls.
  Widget _buildPresenter(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final _Style style = _Style.of(context);
    return Container(
      decoration: _cardDecoration(colors),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PresenterVerdict(state: state),
          if (state.wallMode) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Wall tool on: drag on the floor to draw a wall.',
              style: text.bodyMedium?.copyWith(color: colors.textAccent),
            ),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) => Align(
                alignment: Alignment.topCenter,
                child: _floor(style, box.maxHeight),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          ChannelSpectrumStrip(state: state),
          const SizedBox(height: AppSpacing.xs),
          _legend(context),
        ],
      ),
    );
  }

  /// The floor at most [maxHeight] tall, as wide as its box allows.
  Widget _floor(_Style style, double maxHeight) {
    final double pad = _kFloorPad * style.sc.text;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double innerW = c.maxWidth - 2 * pad;
        double h = innerW * state.floorH / state.floorW;
        double w = innerW;
        final double maxInner = maxHeight - 2 * pad;
        if (h > maxInner) {
          h = math.max(40, maxInner);
          w = h * state.floorW / state.floorH;
        }
        final Size size = Size(c.maxWidth, h + 2 * pad);
        final double scale = w / state.floorW;
        final Offset origin = Offset((c.maxWidth - w) / 2, pad);
        return _FloorGestures(
          state: state,
          origin: origin,
          scale: scale,
          hitRadius: style.sc.markerSize(26),
          child: Semantics(
            label: _semantics(),
            excludeSemantics: true,
            child: CustomPaint(
              size: size,
              painter: _FloorPainter(
                state: state,
                origin: origin,
                scale: scale,
                style: style,
                allLabels: w >= _kAllLabelsWidth,
                revision: state.revision,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final _Style style = _Style.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Text(
              state.wallMode
                  ? 'Wall tool on: drag on the floor to draw a wall.'
                  : 'Floor ${state.floorW.round()} x ${state.floorH.round()} m, '
                        'grid 10 m. Tap an AP to select it, drag to move it.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          _floor(style, maxFloorHeight),
          const SizedBox(height: AppSpacing.xxs),
          ChannelSpectrumStrip(state: state),
          const SizedBox(height: AppSpacing.xs),
          _legend(context),
        ],
      ),
    );
  }

  String _semantics() {
    final PlanAnalysis a = state.analysis;
    final StringBuffer b = StringBuffer(
      'Floor plan, ${state.floorW.round()} by ${state.floorH.round()} metres, '
      '${state.apCount} access points, ${state.walls.length} walls. ',
    );
    for (int i = 0; i < state.apCount; i++) {
      final ChannelOption? c = state.channelOf(i);
      b.write(
        '${state.apName(i)} on ${c == null ? 'no channel' : 'channel ${c.primary}, ${c.width} megahertz'}. ',
      );
    }
    final List<ApLink> links = a.contending;
    b.write(
      links.isEmpty
          ? 'No two access points contend. '
          : '${links.length} contending pair${links.length == 1 ? '' : 's'}. ',
    );
    b.write(
      'Largest contention domain: ${a.largestDomain.length} access '
      'point${a.largestDomain.length == 1 ? '' : 's'}.',
    );
    return b.toString();
  }

  Widget _legend(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    Widget item(CustomPainter p, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 28 * sc.text,
          height: 14 * sc.text,
          child: CustomPaint(painter: p),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          item(
            _LineSample(colors.textSecondary, dashed: false, sc: sc),
            'Contend',
          ),
          item(
            _LineSample(colors.textSecondary, dashed: true, sc: sc),
            'One side defers',
          ),
          item(_RingSample(colors.textPrimary, sc), 'Largest domain'),
          item(_WallSample(colors.textSecondary, sc), 'Wall'),
        ],
      ),
    );
  }
}

// ── Gestures ──────────────────────────────────────────────────────────────

class _FloorGestures extends StatefulWidget {
  const _FloorGestures({
    required this.state,
    required this.origin,
    required this.scale,
    required this.hitRadius,
    required this.child,
  });

  final ChannelPlannerState state;
  final Offset origin;
  final double scale;

  /// How close a press must be to an AP to pick it, px.
  final double hitRadius;
  final Widget child;

  @override
  State<_FloorGestures> createState() => _FloorGesturesState();
}

class _FloorGesturesState extends State<_FloorGestures> {
  int? _dragging;

  FloorPoint _toFloor(Offset p) => FloorPoint(
    (p.dx - widget.origin.dx) / widget.scale,
    (p.dy - widget.origin.dy) / widget.scale,
  );

  int? _hit(Offset p) {
    final ChannelPlannerState s = widget.state;
    int? best;
    double bestD = widget.hitRadius;
    for (int i = 0; i < s.apCount; i++) {
      final FloorPoint f = s.position(i);
      final Offset c =
          widget.origin + Offset(f.x * widget.scale, f.y * widget.scale);
      final double d = (c - p).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final ChannelPlannerState s = widget.state;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (TapUpDetails d) {
        final int? i = _hit(d.localPosition);
        if (i != null) s.select(i);
      },
      onPanStart: (DragStartDetails d) {
        if (s.wallMode) {
          s.startWall(_toFloor(d.localPosition));
          return;
        }
        _dragging = _hit(d.localPosition);
        if (_dragging != null) s.select(_dragging);
      },
      onPanUpdate: (DragUpdateDetails d) {
        if (s.wallMode) {
          s.dragWall(_toFloor(d.localPosition));
        } else if (_dragging != null) {
          s.moveAp(_dragging!, _toFloor(d.localPosition));
        }
      },
      onPanEnd: (DragEndDetails _) {
        if (s.wallMode) s.endWall();
        _dragging = null;
      },
      onPanCancel: () {
        if (s.wallMode) s.endWall();
        _dragging = null;
      },
      child: widget.child,
    );
  }
}

// ── Style ─────────────────────────────────────────────────────────────────

class _Style {
  const _Style({
    required this.floor,
    required this.grid,
    required this.frame,
    required this.wall,
    required this.link,
    required this.ring,
    required this.selected,
    required this.onChannel,
    required this.chipFill,
    required this.chipBorder,
    required this.unassigned,
    required this.hatch,
    required this.light,
    required this.label,
    required this.axisLabel,
    required this.chipLabel,
    required this.sc,
  });

  final Color floor, grid, frame, wall, link, ring, selected, onChannel;
  final Color chipFill, chipBorder, unassigned, hatch;
  final bool light;
  final TextStyle label, axisLabel, chipLabel;

  /// Presenter scale (PresenterScale.normal outside presenter mode).
  final PresenterScale sc;

  /// Height of one spectrum lane.
  double get lane => 20 * sc.text;

  double w(double px) => sc.strokeWidth(px);

  factory _Style.of(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale sc = PresenterMode.scaleOf(context);
    // Painted labels do not see MediaQuery's text scale; the presenter scale
    // reaches them here.
    final TextStyle small = mono.inlineCode.copyWith(
      fontSize: sc.paintFont(AppTextSize.caption),
    );
    return _Style(
      floor: colors.surface2,
      grid: colors.border,
      frame: colors.borderStrong,
      wall: colors.textSecondary,
      link: colors.textSecondary,
      ring: colors.textPrimary,
      selected: colors.textAccent,
      // Text and pattern strokes on a channel fill (see the palette file).
      onChannel: colors.isLight ? colors.surface1 : colors.surface0,
      chipFill: colors.surface1,
      chipBorder: colors.borderStrong,
      unassigned: colors.surface3,
      hatch: colors.borderStrong,
      light: colors.isLight,
      label: small.copyWith(color: colors.textPrimary),
      axisLabel: small.copyWith(color: colors.textTertiary),
      chipLabel: small.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      sc: sc,
    );
  }
}

// ── Painting helpers ──────────────────────────────────────────────────────

void _paintPattern(
  Canvas canvas,
  Rect bounds,
  ChannelPattern p,
  Color color, {
  PresenterScale sc = PresenterScale.normal,
}) {
  if (p == ChannelPattern.solid) return;
  final Paint line = Paint()
    ..color = color
    ..strokeWidth = sc.strokeWidth(1.5)
    ..style = PaintingStyle.stroke;
  final double gap = 6 * sc.stroke;
  final double l = bounds.left, t = bounds.top, r = bounds.right;
  final double b = bounds.bottom;
  final double span = bounds.width + bounds.height;
  void diag(bool back) {
    for (double k = -bounds.height; k < span; k += gap) {
      if (back) {
        canvas.drawLine(Offset(r - k, t), Offset(r - k - span, t + span), line);
      } else {
        canvas.drawLine(Offset(l + k, t), Offset(l + k + span, t + span), line);
      }
    }
  }

  void horiz() {
    for (double y = t + gap / 2; y < b; y += gap) {
      canvas.drawLine(Offset(l, y), Offset(r, y), line);
    }
  }

  void vert() {
    for (double x = l + gap / 2; x < r; x += gap) {
      canvas.drawLine(Offset(x, t), Offset(x, b), line);
    }
  }

  switch (p) {
    case ChannelPattern.solid:
      return;
    case ChannelPattern.diagonal:
      diag(false);
    case ChannelPattern.backDiagonal:
      diag(true);
    case ChannelPattern.cross:
      diag(false);
      diag(true);
    case ChannelPattern.horizontal:
      horiz();
    case ChannelPattern.vertical:
      vert();
    case ChannelPattern.grid:
      horiz();
      vert();
    case ChannelPattern.dots:
      final Paint dot = Paint()..color = color;
      for (double y = t + gap / 2; y < b; y += gap) {
        for (double x = l + gap / 2; x < r; x += gap) {
          canvas.drawCircle(Offset(x, y), sc.markerSize(1.4), dot);
        }
      }
  }
}

void _dashedLine(Canvas c, Offset a, Offset b, Paint p, {double dash = 6}) {
  final double len = (b - a).distance;
  if (len == 0) return;
  final Offset dir = (b - a) / len;
  for (double s = 0; s < len; s += dash * 2) {
    c.drawLine(a + dir * s, a + dir * math.min(len, s + dash), p);
  }
}

void _dashedCircle(Canvas c, Offset center, double r, Paint p) {
  const int n = 16;
  for (int i = 0; i < n; i++) {
    final double a0 = i * 2 * math.pi / n;
    c.drawArc(
      Rect.fromCircle(center: center, radius: r),
      a0,
      math.pi / n,
      false,
      p,
    );
  }
}

TextPainter _tp(String s, TextStyle style) => TextPainter(
  text: TextSpan(text: s, style: style),
  textDirection: TextDirection.ltr,
)..layout();

Rect _chip(Canvas canvas, Offset center, String s, _Style st, {Color? edge}) {
  final TextPainter tp = _tp(s, st.chipLabel);
  final Rect r = Rect.fromCenter(
    center: center,
    width: tp.width + 8,
    height: tp.height + 2,
  );
  final RRect rr = RRect.fromRectAndRadius(r, const Radius.circular(4));
  final double edgeW = edge == null ? 1 : 2;
  canvas.drawRRect(rr, Paint()..color = st.chipFill);
  canvas.drawRRect(
    rr,
    Paint()
      ..color = edge ?? st.chipBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = st.w(edgeW),
  );
  tp.paint(canvas, Offset(r.left + 4, r.top + 1));
  return r;
}

// ── Floor painter ─────────────────────────────────────────────────────────

class _FloorPainter extends CustomPainter {
  _FloorPainter({
    required this.state,
    required this.origin,
    required this.scale,
    required this.style,
    required this.allLabels,
    required this.revision,
  });

  final ChannelPlannerState state;
  final Offset origin;
  final double scale;
  final _Style style;
  final bool allLabels;
  final int revision;

  Offset _pt(double x, double y) => origin + Offset(x * scale, y * scale);

  @override
  void paint(Canvas canvas, Size size) {
    final _Style st = style;
    final Rect floor = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      state.floorW * scale,
      state.floorH * scale,
    );
    canvas.drawRect(floor, Paint()..color = st.floor);
    final Paint grid = Paint()
      ..color = st.grid
      ..strokeWidth = st.w(1);
    for (double x = 10; x < state.floorW; x += 10) {
      canvas.drawLine(_pt(x, 0), _pt(x, state.floorH), grid);
    }
    for (double y = 10; y < state.floorH; y += 10) {
      canvas.drawLine(_pt(0, y), _pt(state.floorW, y), grid);
    }
    canvas.drawRect(
      floor,
      Paint()
        ..color = st.frame
        ..style = PaintingStyle.stroke
        ..strokeWidth = st.w(1),
    );

    // Walls
    final Paint wall = Paint()
      ..color = st.wall
      ..strokeWidth = st.w(4)
      ..strokeCap = StrokeCap.round;
    for (final Wall w in state.walls) {
      canvas.drawLine(_pt(w.x1, w.y1), _pt(w.x2, w.y2), wall);
    }
    final Wall? d = state.draftWall;
    if (d != null) {
      _dashedLine(
        canvas,
        _pt(d.x1, d.y1),
        _pt(d.x2, d.y2),
        Paint()
          ..color = st.ring
          ..strokeWidth = st.w(3),
      );
    }

    final PlanAnalysis a = state.analysis;
    final double r = st.sc.markerSize(scale * 50 >= _kAllLabelsWidth ? 16 : 13);

    // Links
    final Paint solid = Paint()
      ..color = st.link
      ..strokeWidth = st.w(2);
    final List<ApLink> shown = <ApLink>[
      for (final ApLink l in a.links)
        if (l.aDefersToB.defers || l.bDefersToA.defers) l,
    ];
    for (final ApLink l in shown) {
      final FloorPoint p = state.position(l.a), q = state.position(l.b);
      if (l.mutual) {
        canvas.drawLine(_pt(p.x, p.y), _pt(q.x, q.y), solid);
      } else {
        _dashedLine(canvas, _pt(p.x, p.y), _pt(q.x, q.y), solid);
      }
    }

    // Largest domain: a ring round each member and a hull between them.
    final List<int> dom = a.largestDomain;
    if (dom.length >= 2) {
      final Paint ring = Paint()
        ..color = st.ring
        ..strokeWidth = st.w(2)
        ..style = PaintingStyle.stroke;
      final List<Offset> pts = <Offset>[
        for (final int i in dom) _pt(state.position(i).x, state.position(i).y),
      ];
      final List<Offset> hull = _hull(pts);
      for (int i = 0; i < hull.length; i++) {
        _dashedLine(
          canvas,
          hull[i],
          hull[(i + 1) % hull.length],
          ring,
          dash: 4,
        );
      }
      for (final Offset c in pts) {
        _dashedCircle(canvas, c, r + st.sc.markerSize(7), ring);
      }
    }

    // APs
    final int? sel = state.selected;
    final List<Rect> taken = <Rect>[];
    for (int i = 0; i < state.apCount; i++) {
      final FloorPoint f = state.position(i);
      final Offset c = _pt(f.x, f.y);
      final ChannelOption? ch = state.channelOf(i);
      final Rect box = Rect.fromCircle(center: c, radius: r);
      if (ch == null) {
        canvas.drawCircle(c, r, Paint()..color = st.unassigned);
        _dashedCircle(
          canvas,
          c,
          r,
          Paint()
            ..color = st.frame
            ..style = PaintingStyle.stroke
            ..strokeWidth = st.w(1.5),
        );
      } else {
        final int k = state.occupiedIndex(ch.group);
        canvas.drawCircle(
          c,
          r,
          Paint()..color = channelHue(k, light: st.light),
        );
        canvas.save();
        canvas.clipPath(Path()..addOval(box));
        _paintPattern(canvas, box, channelPattern(k), st.onChannel, sc: st.sc);
        canvas.restore();
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..color = st.ring
            ..style = PaintingStyle.stroke
            ..strokeWidth = st.w(1.5),
        );
      }
      if (i == sel) {
        canvas.drawCircle(
          c,
          r + st.sc.markerSize(3.5),
          Paint()
            ..color = st.selected
            ..style = PaintingStyle.stroke
            ..strokeWidth = st.w(3),
        );
      }
      taken.add(box.inflate(4));
      final String lbl = '${i + 1}: ${ch == null ? '--' : ch.shortLabel}';
      taken.add(
        _chip(
          canvas,
          c + Offset(0, r + 10 * st.sc.text),
          lbl,
          st,
          edge: ch == null
              ? null
              : channelHue(state.occupiedIndex(ch.group), light: st.light),
        ),
      );
    }
    // Link labels go last and never cover a node, a node label or each
    // other; one that finds no clear spot is left to the readouts.
    // Link labels: all when there is room, else the selected AP's.
    for (final ApLink l in shown) {
      if (!allLabels && l.a != sel && l.b != sel) continue;
      final FloorPoint p = state.position(l.a), q = state.position(l.b);
      final String t = '${l.rxDbm.round()} ${l.ruleShort}';
      final TextPainter probe = _tp(t, st.chipLabel);
      for (final double f in <double>[0.5, 0.35, 0.65, 0.25, 0.75]) {
        final Offset at = Offset.lerp(_pt(p.x, p.y), _pt(q.x, q.y), f)!;
        final Rect want = Rect.fromCenter(
          center: at,
          width: probe.width + 8,
          height: probe.height + 2,
        ).inflate(2);
        if (taken.any((Rect r) => r.overlaps(want))) continue;
        taken.add(_chip(canvas, at, t, st));
        break;
      }
    }
  }

  /// Convex hull (monotone chain); two points come back as a segment.
  static List<Offset> _hull(List<Offset> p) {
    final List<Offset> s = List<Offset>.of(p)
      ..sort(
        (Offset a, Offset b) =>
            a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy),
      );
    if (s.length < 3) return s;
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final List<Offset> lower = <Offset>[];
    for (final Offset q in s) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, q) <= 0) {
        lower.removeLast();
      }
      lower.add(q);
    }
    final List<Offset> upper = <Offset>[];
    for (final Offset q in s.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, q) <= 0) {
        upper.removeLast();
      }
      upper.add(q);
    }
    return <Offset>[
      ...lower.sublist(0, lower.length - 1),
      ...upper.sublist(0, upper.length - 1),
    ];
  }

  @override
  bool shouldRepaint(_FloorPainter old) =>
      old.revision != revision ||
      old.scale != scale ||
      old.origin != origin ||
      old.allLabels != allLabels ||
      old.style.light != style.light ||
      old.style.sc != style.sc;
}

// ── Spectrum strip ────────────────────────────────────────────────────────

/// Occupied channels across the band, over a labeled channel axis. Channels
/// the rules do not allow are hatched; DFS ranges are bracketed.
class ChannelSpectrumStrip extends StatelessWidget {
  const ChannelSpectrumStrip({super.key, required this.state});
  final ChannelPlannerState state;

  @override
  Widget build(BuildContext context) {
    final _Style st = _Style.of(context);
    final List<(ChannelGroup, List<int>)> occ = state.occupied;
    final List<int> lanes = _lanes(occ);
    final int laneCount = lanes.isEmpty ? 1 : lanes.reduce(math.max) + 1;
    final double h = laneCount * st.lane + 52 * st.sc.text;
    return Semantics(
      label: _semantics(occ),
      excludeSemantics: true,
      child: SizedBox(
        height: h,
        child: CustomPaint(
          size: Size.infinite,
          painter: _SpectrumPainter(
            state: state,
            occupied: occ,
            lanes: lanes,
            laneCount: laneCount,
            style: st,
            revision: state.revision,
          ),
        ),
      ),
    );
  }

  String _semantics(List<(ChannelGroup, List<int>)> occ) {
    if (occ.isEmpty) return 'Spectrum: no channel in use.';
    return 'Spectrum, ${state.band.label}: '
        '${occ.map(((ChannelGroup, List<int>) o) => 'channels ${o.$1.span}, ${o.$2.length} access point${o.$2.length == 1 ? '' : 's'}').join('; ')}.';
  }

  static List<int> _lanes(List<(ChannelGroup, List<int>)> occ) {
    final List<double> laneEnd = <double>[];
    final List<int> out = <int>[];
    for (final (ChannelGroup g, List<int> _) in occ) {
      int lane = laneEnd.indexWhere((double e) => e <= g.lowMHz);
      if (lane < 0) {
        lane = laneEnd.length;
        laneEnd.add(g.highMHz);
      } else {
        laneEnd[lane] = g.highMHz;
      }
      out.add(lane);
    }
    return out;
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({
    required this.state,
    required this.occupied,
    required this.lanes,
    required this.laneCount,
    required this.style,
    required this.revision,
  });

  final ChannelPlannerState state;
  final List<(ChannelGroup, List<int>)> occupied;
  final List<int> lanes;
  final int laneCount;
  final _Style style;
  final int revision;

  /// Axis pieces, MHz. 5 GHz skips 5350-5470, which holds no Wi-Fi channel.
  List<(double, double)> get _pieces => state.band == PlannerBand.band24
      ? const <(double, double)>[(2400, 2484)]
      : <(double, double)>[
          (5170, 5330),
          (5490, state.rules.region == PlannerRegion.eu ? 5730 : 5895),
        ];

  static const double _gapPx = 10;

  double Function(double) _mapper(double width) {
    final List<(double, double)> pc = _pieces;
    final double total = pc.fold(
      0,
      (double s, (double, double) p) => s + p.$2 - p.$1,
    );
    final double usable = width - _gapPx * (pc.length - 1);
    return (double f) {
      double x = 0;
      for (int i = 0; i < pc.length; i++) {
        final (double a, double b) = pc[i];
        if (f <= b || i == pc.length - 1) {
          return x + (f.clamp(a, b) - a) / total * usable;
        }
        x += (b - a) / total * usable + _gapPx;
      }
      return x;
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final _Style st = style;
    final double Function(double) fx = _mapper(size.width);
    final PlannerBand band = state.band;
    final Set<int> allowed = allowed20(state.rules).toSet();
    final List<int> all = band == PlannerBand.band24
        ? <int>[for (int c = 1; c <= 13; c++) c]
        : <int>[
            for (final int c in <int>[
              36, 40, 44, 48, 52, 56, 60, 64, //
              100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144,
              149, 153, 157, 161, 165, 169, 173, 177,
            ])
              if (state.rules.region == PlannerRegion.us || c <= 144) c,
          ];
    final double lane = st.lane;
    final double lanesH = laneCount * lane;
    final double axisY = lanesH + 4;

    // Slots: one cell per 20 MHz channel. Disallowed cells are hatched.
    final Paint slot = Paint()
      ..color = st.grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = st.w(1);
    for (final int c in all) {
      final double f = centerMHz(band, c).toDouble();
      final double half = band == PlannerBand.band24 ? 2.5 : 10;
      final Rect cell = Rect.fromLTRB(fx(f - half), 0, fx(f + half), lanesH);
      if (band == PlannerBand.band5) canvas.drawRect(cell, slot);
      if (!allowed.contains(c)) {
        canvas.save();
        canvas.clipRect(cell);
        _paintPattern(
          canvas,
          cell,
          ChannelPattern.backDiagonal,
          st.grid,
          sc: st.sc,
        );
        canvas.restore();
      }
    }

    // Occupied channels.
    for (int i = 0; i < occupied.length; i++) {
      final (ChannelGroup g, List<int> aps) = occupied[i];
      final Rect r = Rect.fromLTRB(
        fx(g.lowMHz) + 1,
        lanes[i] * lane + 2,
        fx(g.highMHz) - 1,
        lanes[i] * lane + lane - 2,
      );
      canvas.drawRect(r, Paint()..color = channelHue(i, light: st.light));
      canvas.save();
      canvas.clipRect(r);
      _paintPattern(canvas, r, channelPattern(i), st.onChannel, sc: st.sc);
      canvas.restore();
      final TextPainter tp = _tp('${g.span} x${aps.length}', st.chipLabel);
      if (tp.width + 8 <= r.width) {
        final Rect bg = Rect.fromCenter(
          center: r.center,
          width: tp.width + 6,
          height: tp.height,
        );
        canvas.drawRect(bg, Paint()..color = st.chipFill);
        tp.paint(canvas, Offset(bg.left + 3, bg.top));
      }
    }

    // Axis and channel numbers.
    canvas.drawLine(
      Offset(0, axisY - 2),
      Offset(size.width, axisY - 2),
      Paint()
        ..color = st.frame
        ..strokeWidth = st.w(1),
    );
    final List<int> labelled = band == PlannerBand.band24
        ? const <int>[1, 6, 11, 13]
        : const <int>[36, 52, 100, 116, 132, 149, 165];
    double lastRight = -1e9;
    for (final int c in labelled) {
      if (!all.contains(c)) continue;
      final double x = fx(centerMHz(band, c).toDouble());
      final TextPainter tp = _tp('$c', st.axisLabel);
      final double left = (x - tp.width / 2).clamp(0, size.width - tp.width);
      if (left < lastRight + 4) continue;
      tp.paint(canvas, Offset(left, axisY));
      lastRight = left + tp.width;
    }

    // DFS brackets (5 GHz).
    if (band == PlannerBand.band5) {
      final double y = axisY + 32 * st.sc.text;
      final Paint br = Paint()
        ..color = st.hatch
        ..strokeWidth = st.w(1);
      for (final (int a, int b) in <(int, int)>[
        (52, 64),
        (100, state.rules.region == PlannerRegion.us ? 144 : 140),
      ]) {
        final double x0 = fx(centerMHz(band, a) - 10.0);
        final double x1 = fx(centerMHz(band, b) + 10.0);
        canvas.drawLine(Offset(x0, y), Offset(x1, y), br);
        canvas.drawLine(Offset(x0, y - 3), Offset(x0, y + 3), br);
        canvas.drawLine(Offset(x1, y - 3), Offset(x1, y + 3), br);
        final TextPainter tp = _tp(
          state.rules.dfs ? 'DFS' : 'DFS off',
          st.axisLabel,
        );
        final Rect bg = Rect.fromCenter(
          center: Offset((x0 + x1) / 2, y),
          width: tp.width + 6,
          height: tp.height,
        );
        canvas.drawRect(bg, Paint()..color = st.chipFill);
        tp.paint(canvas, Offset(bg.left + 3, bg.top));
      }
    } else {
      final TextPainter tp = _tp(
        state.rules.region == PlannerRegion.us
            ? 'US: 1 to 11 (12 and 13 hatched)'
            : 'EU: 1 to 13',
        st.axisLabel,
      );
      tp.paint(canvas, Offset(0, axisY + 24 * st.sc.text));
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) =>
      old.revision != revision ||
      old.style.light != style.light ||
      old.style.sc != style.sc;
}

// ── Legend samples ────────────────────────────────────────────────────────

class _LineSample extends CustomPainter {
  _LineSample(this.color, {required this.dashed, required this.sc});
  final Color color;
  final bool dashed;
  final PresenterScale sc;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = sc.strokeWidth(2);
    final Offset a = Offset(0, size.height / 2);
    final Offset b = Offset(size.width, size.height / 2);
    if (dashed) {
      _dashedLine(canvas, a, b, p, dash: 4);
    } else {
      canvas.drawLine(a, b, p);
    }
  }

  @override
  bool shouldRepaint(_LineSample old) => old.color != color || old.sc != sc;
}

class _RingSample extends CustomPainter {
  _RingSample(this.color, this.sc);
  final Color color;
  final PresenterScale sc;

  @override
  void paint(Canvas canvas, Size size) {
    _dashedCircle(
      canvas,
      size.center(Offset.zero),
      size.height / 2 - 1,
      Paint()
        ..color = color
        ..strokeWidth = sc.strokeWidth(2)
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_RingSample old) => old.color != color || old.sc != sc;
}

class _WallSample extends CustomPainter {
  _WallSample(this.color, this.sc);
  final Color color;
  final PresenterScale sc;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(2, size.height / 2),
      Offset(size.width - 2, size.height / 2),
      Paint()
        ..color = color
        ..strokeWidth = sc.strokeWidth(4)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WallSample old) => old.color != color || old.sc != sc;
}

// ── Presenter verdict ─────────────────────────────────────────────────────

/// The plan's numbers, over the floor in presenter mode: the largest
/// contention domain (the number the lesson is about), the airtime each of
/// its APs gets, and how many channels this width leaves, then the verdict
/// in words.
class _PresenterVerdict extends StatelessWidget {
  const _PresenterVerdict({required this.state});

  final ChannelPlannerState state;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final ChannelPlannerState s = state;
    final PlanAnalysis a = s.analysis;
    final int n = a.largestDomain.length;
    final bool none = s.unassigned.length == s.apCount;
    final PlanVerdict v = channelPlanVerdict(s, colors);

    Widget stat(String label, String value, {bool headline = false}) =>
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              Text(
                value,
                style: headline
                    ? sc
                          .headlineStyle(mono.outputLarge)
                          .copyWith(color: colors.textAccent)
                    : mono.outputMedium.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        );

    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: <Widget>[
              stat(
                'Largest contention domain',
                none ? '--' : '$n AP${n == 1 ? '' : 's'}',
                headline: true,
              ),
              stat(
                'Airtime each (1/N)',
                none ? '--' : '${(a.largestShare * 100).round()}%',
              ),
              stat('Channels at ${s.width} MHz', '${s.available}'),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(v.icon, color: v.color),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  v.message,
                  style: text.bodyMedium?.copyWith(color: v.color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
