// Painters for Repeaters and Mesh Backhaul (Wi-Fi Classroom): the corridor
// with the root AP, the relays and the client, each hop drawn with its rate
// and a frame crossing it; and the airtime lanes, which show the hops taking
// turns on one shared channel or running at once on channels of their own.
//
// COLOR (GL-003 §8.13 / §8.15). No categorical hues: hops are told apart by
// their "Hop 1", "Hop 2" labels. Lime marks the one quantity the tool is
// about, air in use: the hop that is sending now and the busy blocks in the
// lanes. On light, lime is a fill only (§8.20.2): the sending hop's thin arc
// uses textAccent, the frame dot and the busy blocks keep the vivid fill. The only status hue is a hop with no link, drawn dashed in danger
// with the words "no link" (a verdict, §8.13 rule 6).
//
// MOTION (§8.8). Both painters repaint from the controller's phase notifier,
// and only while the animation plays; with it paused they draw the same
// moment still.
//
// PRESENTER. Strokes, markers and painted labels follow PresenterScale.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../services/wifi_lab/repeater_mesh_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';

/// Where a hop is busy inside one pass of the animation, as a fraction of
/// the pass: [start, start + length). Null for a wired hop.
typedef RmSlot = ({double start, double length});

/// The schedule the animation plays. On one shared channel the hops take
/// turns, back to back, each for its share of the air. On channels of their
/// own every hop starts at once and is busy for its share. Wired hops are
/// not on the air.
List<RmSlot?> rmSchedule(RmResult r) {
  final List<RmSlot?> out = <RmSlot?>[];
  double at = 0;
  final bool turns = r.config.backhaul == RmBackhaul.sameChannel;
  for (final RmHop h in r.hops) {
    if (h.wired) {
      out.add(null);
      continue;
    }
    out.add((start: turns ? at : 0, length: h.airShare));
    if (turns) at += h.airShare;
  }
  return out;
}

/// Maps corridor meters to painter x and back, and places the rows.
///
/// From the bottom up: the meter axis labels, two rows of node names (a
/// node's name alternates rows, so two nodes a step apart never overprint),
/// the floor with the nodes on it, and the hop arcs above.
@immutable
class RmCorridorGeometry {
  const RmCorridorGeometry(this.size, this.scale, this.lineHeight);

  final Size size;
  final PresenterScale scale;

  /// Height of one painted label line.
  final double lineHeight;

  double get padX => 28 * scale.marker;
  double get nodeRadius => scale.markerSize(9);

  double get baselineY =>
      size.height - (nodeRadius * 1.15 + 6 + 3 * lineHeight + 4);

  /// Top of node-name row [row] (0 or 1).
  double nameRowY(int row) =>
      baselineY + nodeRadius * 1.15 + 4 + row * lineHeight;

  /// Top of the meter labels.
  double get axisLabelY => nameRowY(2);

  double xOf(double m) =>
      padX + (size.width - 2 * padX) * (m / kRmCorridorM).clamp(0.0, 1.0);

  double mOf(double x) =>
      (x - padX) / math.max(1, size.width - 2 * padX) * kRmCorridorM;

  /// The tallest arc: leaves room for a two-line label above it.
  double get arcRise => math.max(
    8,
    math.min(baselineY - 2 * lineHeight - 10, 110 * scale.marker),
  );

  /// Rise of hop [i]'s arc. Alternate hops rise less, so the labels of two
  /// short hops side by side sit at different heights.
  double riseOf(int i) => i.isEven ? arcRise : arcRise * 0.62;

  /// Index of the movable node (1 and up; the AP never moves) nearest to
  /// [x] in [nodesM], or null when there is none.
  int? nearestMovable(List<double> nodesM, double x) {
    int? best;
    double bestD = double.infinity;
    for (int i = 1; i < nodesM.length; i++) {
      final double d = (xOf(nodesM[i]) - x).abs();
      if (d <= bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }
}

/// The styles the corridor painter needs, resolved from the theme.
@immutable
class RmPaintStyle {
  const RmPaintStyle({
    required this.colors,
    required this.scale,
    required this.label,
    required this.small,
  });

  final AppColorScheme colors;
  final PresenterScale scale;

  /// Hop and node labels.
  final TextStyle label;

  /// Axis labels.
  final TextStyle small;
}

class RmCorridorPainter extends CustomPainter {
  RmCorridorPainter({
    required this.result,
    required this.schedule,
    required this.masked,
    required this.style,
    required this.phase,
    this.units = UnitSystem.metric,
  }) : super(repaint: phase);

  /// Units for the corridor ticks (every 10 m, or every 25 ft) and labels.
  final UnitSystem units;

  final RmResult result;
  final List<RmSlot?> schedule;

  /// Hide the throughputs (the question is being asked).
  final bool masked;
  final RmPaintStyle style;
  final ValueListenable<double> phase;

  @override
  void paint(Canvas canvas, Size size) {
    final AppColorScheme colors = style.colors;
    final PresenterScale scale = style.scale;
    final RmCorridorGeometry g = RmCorridorGeometry(
      size,
      scale,
      rmLineHeight(style.small),
    );
    final RmConfig c = result.config;
    final List<double> nodes = c.nodesM;
    final double y = g.baselineY;
    final double p = phase.value;

    // The corridor floor and its meter ticks.
    final Paint floor = Paint()
      ..color = colors.borderStrong
      ..strokeWidth = scale.strokeWidth(1.5);
    canvas.drawLine(Offset(g.xOf(0), y), Offset(g.xOf(kRmCorridorM), y), floor);
    final LengthFormat f = LengthFormat(units);
    final double stepShown = units.isMetric ? 10 : 25;
    for (
      double v = 0;
      f.distToMetres(v) <= kRmCorridorM + 1e-9;
      v += stepShown
    ) {
      final double x = g.xOf(f.distToMetres(v));
      canvas.drawLine(Offset(x, y), Offset(x, y + 4 * scale.marker), floor);
      _text(
        canvas,
        '${v.round()} ${f.distUnit}',
        Offset(x, g.axisLabelY),
        style.small,
        align: _Align.topCenter,
        width: size.width,
      );
    }

    // Hops.
    for (int i = 0; i < result.hops.length; i++) {
      final RmHop h = result.hops[i];
      final double x0 = g.xOf(nodes[i]);
      final double x1 = g.xOf(nodes[i + 1]);
      final RmSlot? slot = schedule[i];

      if (h.wired) {
        final Paint cable = Paint()
          ..color = colors.textSecondary
          ..strokeWidth = scale.strokeWidth(5)
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x0, y), Offset(x1, y), cable);
        _text(
          canvas,
          'Hop ${i + 1}\ncable',
          Offset((x0 + x1) / 2, y - g.nodeRadius - 4),
          style.label.copyWith(color: colors.textSecondary),
          align: _Align.bottomCenter,
        );
        continue;
      }

      final bool active =
          slot != null &&
          h.link.hasLink &&
          slot.length > 0 &&
          p >= slot.start &&
          p < slot.start + slot.length;
      // A short hop gets a low arc, so it never reads as a spike; its label
      // still sits at the staggered height, clear of its neighbors'.
      final double labelRise = g.riseOf(i);
      final double rise = math.min(
        labelRise,
        math.max(10 * scale.marker, (x1 - x0).abs() * 0.7),
      );
      final Offset a = Offset(x0, y);
      final Offset b = Offset(x1, y);
      final Offset ctrl = Offset((x0 + x1) / 2, y - 2 * rise);
      final Path arc = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, b.dx, b.dy);

      // On light, lime is a fill only (§8.20.2): a thin lime stroke uses the
      // darkened textAccent there, and the frame dot keeps the vivid fill.
      final Color ink = !h.link.hasLink
          ? colors.statusDanger
          : active
          ? (colors.isLight ? colors.textAccent : colors.primary)
          : colors.textSecondary;
      final Paint stroke = Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = scale.strokeWidth(active ? 3.5 : 2);
      if (labelRise - rise > 12 * scale.marker) {
        // A leader from a low arc up to its label.
        canvas.drawLine(
          Offset((x0 + x1) / 2, y - rise - 2),
          Offset((x0 + x1) / 2, y - labelRise),
          Paint()
            ..color = colors.textTertiary
            ..strokeWidth = scale.strokeWidth(1),
        );
      }
      if (h.link.hasLink) {
        canvas.drawPath(arc, stroke);
      } else {
        _dashed(canvas, arc, stroke, 6 * scale.stroke);
      }

      // The label above the top of the arc.
      final String rate = !h.link.hasLink
          ? 'no link'
          : masked
          ? 'MCS ${h.link.mcs}, ? Mb/s'
          : 'MCS ${h.link.mcs}, ${rmMbps(h.throughputMbps)}';
      final bool slowest =
          !masked && result.bottleneck == i && result.slowestIsUnique;
      _text(
        canvas,
        'Hop ${i + 1}${slowest ? ', slowest' : ''}\n$rate',
        Offset((x0 + x1) / 2, y - labelRise - 4 * scale.marker),
        style.label.copyWith(
          color: h.link.hasLink ? colors.textPrimary : colors.statusDanger,
        ),
        align: _Align.bottomCenter,
        width: size.width,
      );

      // The frame crossing this hop now.
      if (active) {
        final double t = ((p - slot.start) / slot.length).clamp(0.0, 1.0);
        final Offset at = _quad(a, ctrl, b, t);
        final double r = scale.markerSize(6);
        canvas.drawCircle(at, r, Paint()..color = colors.primary);
        canvas.drawCircle(
          at,
          r,
          Paint()
            ..color = colors.textPrimary
            ..style = PaintingStyle.stroke
            ..strokeWidth = scale.strokeWidth(1),
        );
      }
    }

    // Nodes, drawn last so the arcs end under them.
    final double r = g.nodeRadius;
    for (int i = 0; i < nodes.length; i++) {
      final Offset at = Offset(g.xOf(nodes[i]), y);
      if (i == 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: at, width: 2 * r, height: 2 * r),
            Radius.circular(r * 0.3),
          ),
          Paint()..color = colors.textPrimary,
        );
      } else if (i == nodes.length - 1) {
        canvas.drawCircle(at, r, Paint()..color = colors.textPrimary);
      } else {
        final double d = r * 1.15;
        final Path diamond = Path()
          ..moveTo(at.dx, at.dy - d)
          ..lineTo(at.dx + d, at.dy)
          ..lineTo(at.dx, at.dy + d)
          ..lineTo(at.dx - d, at.dy)
          ..close();
        canvas.drawPath(diamond, Paint()..color = colors.surface1);
        canvas.drawPath(
          diamond,
          Paint()
            ..color = colors.textPrimary
            ..style = PaintingStyle.stroke
            ..strokeWidth = scale.strokeWidth(2),
        );
      }
      _text(
        canvas,
        '${rmNodeName(i, c.relayCount)}, ${rmMeters(nodes[i], units)}',
        Offset(at.dx, g.nameRowY(i % 2)),
        style.small.copyWith(color: colors.textPrimary),
        align: _Align.topCenter,
        width: size.width,
      );
    }
  }

  static Offset _quad(Offset a, Offset c, Offset b, double t) {
    final double u = 1 - t;
    return a * (u * u) + c * (2 * u * t) + b * (t * t);
  }

  static void _dashed(Canvas canvas, Path path, Paint paint, double dash) {
    for (final ui.PathMetric m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash * 2;
      }
    }
  }

  @override
  bool shouldRepaint(RmCorridorPainter old) =>
      old.result != result ||
      old.units != units ||
      old.masked != masked ||
      old.style.colors != style.colors ||
      old.style.scale != style.scale ||
      old.style.label != style.label;
}

/// The lanes the airtime view draws, in order: one shared lane on one
/// channel, or one lane per radio hop on channels of their own. Each lane is
/// a list of (hop index, slot).
List<List<(int, RmSlot)>> rmLanes(RmResult r, List<RmSlot?> schedule) {
  final List<(int, RmSlot)> radio = <(int, RmSlot)>[
    for (int i = 0; i < schedule.length; i++)
      if (schedule[i] != null) (i, schedule[i]!),
  ];
  if (r.config.backhaul == RmBackhaul.sameChannel) {
    return <List<(int, RmSlot)>>[radio];
  }
  return <List<(int, RmSlot)>>[
    for (final (int, RmSlot) s in radio) <(int, RmSlot)>[s],
  ];
}

/// One airtime lane: busy blocks in lime, each labeled with its hop when it
/// is wide enough, idle air in the input fill, and a playhead at the phase.
class RmLanePainter extends CustomPainter {
  RmLanePainter({
    required this.blocks,
    required this.style,
    required this.phase,
  }) : super(repaint: phase);

  final List<(int, RmSlot)> blocks;
  final RmPaintStyle style;
  final ValueListenable<double> phase;

  @override
  void paint(Canvas canvas, Size size) {
    final AppColorScheme colors = style.colors;
    final PresenterScale scale = style.scale;
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.inputFill);
    for (final (int hop, RmSlot s) in blocks) {
      if (s.length <= 0) continue;
      final Rect block = Rect.fromLTWH(
        s.start * size.width,
        0,
        s.length * size.width,
        size.height,
      );
      canvas.drawRect(block, Paint()..color = colors.primary);
      canvas.drawRect(
        block,
        Paint()
          ..color = colors.surface1
          ..style = PaintingStyle.stroke
          ..strokeWidth = scale.strokeWidth(1),
      );
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: 'Hop ${hop + 1}',
          style: style.small.copyWith(color: colors.onPrimary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width + 6 < block.width && tp.height < size.height) {
        tp.paint(
          canvas,
          Offset(
            block.left + (block.width - tp.width) / 2,
            (size.height - tp.height) / 2,
          ),
        );
      }
      tp.dispose();
    }
    final double x = phase.value * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = colors.textPrimary
        ..strokeWidth = scale.strokeWidth(2),
    );
  }

  @override
  bool shouldRepaint(RmLanePainter old) =>
      !listEquals(old.blocks, blocks) ||
      old.style.colors != style.colors ||
      old.style.scale != style.scale;
}

enum _Align { topCenter, bottomCenter }

/// Height of one painted line of [style].
double rmLineHeight(TextStyle style) => (style.fontSize ?? 12) * 1.35;

void _text(
  Canvas canvas,
  String s,
  Offset at,
  TextStyle style, {
  required _Align align,
  double? width,
}) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout();
  final double dy = align == _Align.topCenter ? 0 : -tp.height;
  double dx = at.dx - tp.width / 2;
  // Held inside the canvas, so a label at either end of the corridor is
  // never cut off.
  if (width != null) dx = dx.clamp(0.0, math.max(0.0, width - tp.width));
  tp.paint(canvas, Offset(dx, at.dy + dy));
  tp.dispose();
}
