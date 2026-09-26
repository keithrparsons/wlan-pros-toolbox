// Painters for the Wi-Fi Classroom MIMO and Beamforming simulator.
//
// Token-only CustomPainters in the multipath_simulator_painters.dart idiom:
// every color and text style arrives resolved from context.colors by the
// stage, so each painter is right in dark (§8) and light (§8.20) without
// knowing which theme it is in. The stage wraps each one in
// `Semantics(excludeSemantics: true)` with a worded label, and every number a
// painter shows is also in a text readout.
//
// Color roles (GL-003 §8.15, §8.15.2, §8.13 rule 6):
//   * each spatial stream has its own hue from MimoStreamPalette (§8.15.2:
//     the colors teach that each lane is a separate stream), and each lane
//     is also labeled S1 to S4 on the canvas;
//   * lime (`accent`) marks the one quantity the other pictures are about:
//     the steered beam and the sounding share of airtime;
//   * everything else is neutral and told apart by weight and dash: chains
//     in use are solid `primary`, spare chains that contribute are dashed
//     `secondary`, idle spare chains are `tertiary` outlines;
//   * no status hue appears in a painter. The two verdicts on this screen
//     (the sniffer cannot separate the streams; the sniffer sits in a
//     sidelobe) are worded text readouts.

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../services/wifi_lab/mimo_beamforming_model.dart';
import '../../../widgets/presenter/presenter_mode.dart';

/// Resolved colors and text styles shared by every MIMO painter.
@immutable
class MimoPaintStyle {
  const MimoPaintStyle({
    required this.accent,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.grid,
    required this.axis,
    required this.fill,
    required this.background,
    required this.labelStyle,
    this.scale = PresenterScale.normal,
  });

  /// Lime: the quantity the picture is about.
  final Color accent;

  /// Strongest neutral: chains in use, markers.
  final Color primary;

  /// Contributing spare chains, the sniffer.
  final Color secondary;

  /// Idle spare chains, minor labels.
  final Color tertiary;

  /// Decorative grid.
  final Color grid;

  /// Axes and reference lines (3:1 or better on the plot surface).
  final Color axis;

  /// Neutral block fill (the sounding frames).
  final Color fill;

  /// The plot surface itself, for knocking out a label's backing.
  final Color background;

  /// Already applied to [labelStyle]'s size.
  final TextStyle labelStyle;

  /// The presenter scale: strokes, markers and text-driven spacing grow with
  /// it. [PresenterScale.normal] (every factor 1) outside presenter mode.
  final PresenterScale scale;

  /// A stroke width at this scale.
  double w(double width) => scale.strokeWidth(width);

  /// A marker radius or size at this scale.
  double m(double r) => scale.markerSize(r);

  /// A text-driven offset (label bands, rows) at this scale.
  double t(double px) => px * scale.text;

  @override
  bool operator ==(Object other) =>
      other is MimoPaintStyle &&
      other.scale == scale &&
      other.accent == accent &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.tertiary == tertiary &&
      other.grid == grid &&
      other.axis == axis &&
      other.fill == fill &&
      other.background == background &&
      other.labelStyle == labelStyle;

  @override
  int get hashCode => Object.hash(
    accent,
    primary,
    secondary,
    tertiary,
    grid,
    axis,
    fill,
    background,
    labelStyle,
    scale,
  );
}

// ── Shared helpers ──────────────────────────────────────────────────────────

Size _label(
  Canvas canvas,
  String text,
  Offset at,
  TextStyle style, {
  Alignment align = Alignment.topLeft,
}) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final double dx = at.dx - tp.width * (align.x + 1) / 2;
  final double dy = at.dy - tp.height * (align.y + 1) / 2;
  tp.paint(canvas, Offset(dx, dy));
  return tp.size;
}

double _textWidth(String text, TextStyle style) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width;
}

void _dashedLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  double dash = 4,
  double gap = 3,
}) {
  final double len = (b - a).distance;
  if (len == 0) return;
  final Offset dir = (b - a) / len;
  double d = 0;
  while (d < len) {
    final double e = math.min(d + dash, len);
    canvas.drawLine(a + dir * d, a + dir * e, paint);
    d = e + gap;
  }
}

void _arrowHead(
  Canvas canvas,
  Offset tip,
  double angle,
  Color color, {
  double h = 7,
}) {
  const double spread = 0.5;
  final Path p = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(
      tip.dx - h * math.cos(angle - spread),
      tip.dy - h * math.sin(angle - spread),
    )
    ..lineTo(
      tip.dx - h * math.cos(angle + spread),
      tip.dy - h * math.sin(angle + spread),
    )
    ..close();
  canvas.drawPath(p, Paint()..color = color);
}

/// How one antenna chain is drawn.
enum ChainRole {
  /// Carries a stream.
  used,

  /// Spare, and contributing (beamforming or combining).
  contributing,

  /// Spare and idle (a client that does not beamform, or beamforming off).
  idle,
}

void _antenna(Canvas canvas, Offset c, ChainRole role, MimoPaintStyle s) {
  switch (role) {
    case ChainRole.used:
      canvas.drawCircle(c, s.m(5), Paint()..color = s.primary);
    case ChainRole.contributing:
      canvas.drawCircle(c, s.m(5), Paint()..color = s.secondary);
      canvas.drawCircle(
        c,
        s.m(5),
        Paint()
          ..color = s.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.w(1),
      );
    case ChainRole.idle:
      canvas.drawCircle(
        c,
        s.m(4.5),
        Paint()
          ..color = s.tertiary
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.w(1.5),
      );
  }
}

// ── Streams diagram ─────────────────────────────────────────────────────────

/// AP on the left, client on the right, every chain drawn as an element, and
/// one lane per spatial stream, each in its own stream hue and labeled. Spare chains join the lanes with dashed
/// lines when they contribute (beamforming, combining) and stand alone when
/// idle.
class StreamsPainter extends CustomPainter {
  StreamsPainter({
    required this.link,
    required this.streamColors,
    required this.style,
  });

  final MimoLink link;

  /// One hue per stream (MimoStreamPalette), stream 1 first.
  final List<Color> streamColors;
  final MimoPaintStyle style;

  static const double pad = 14;
  static const double labelBand = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final MimoPaintStyle s = style;
    final int ap = link.apChains;
    final int cl = link.clientChains;
    final int nss = link.streams;
    final bool down = link.direction == LinkDirection.downlink;

    final double band = s.t(labelBand);
    final double top = band + 6;
    final double bottom = size.height - band - 4;
    final double usable = bottom - top;
    // On the presenter stage the lanes spread to use the height it gives.
    final double spacing = math.min(
      s.scale.isPresenting ? s.t(64) : 22,
      usable / math.max(1, math.max(ap, cl)),
    );
    final double cy = (top + bottom) / 2;

    final double apX = pad + s.t(24);
    final double clX = size.width - pad - s.t(24);
    final double laneL = apX + s.t(44);
    final double laneR = clX - s.t(44);

    double yOf(int i, int n) => cy + (i - (n - 1) / 2) * spacing;
    double laneY(int i) => cy + (i - (nss - 1) / 2) * spacing;

    // Which chains carry streams: the middle ones, so lanes stay centered.
    Set<int> usedIdx(int n) {
      final int first = ((n - nss) / 2).floor();
      return <int>{for (int i = first; i < first + nss; i++) i};
    }

    final Set<int> apUsed = usedIdx(ap);
    final Set<int> clUsed = usedIdx(cl);

    // Roles for spare chains. AP side transmits on the downlink.
    ChainRole spareRole({required bool isAp}) {
      final bool transmits = isAp == down;
      if (!transmits) return ChainRole.contributing; // receive combining
      return link.isBeamformed ? ChainRole.contributing : ChainRole.idle;
    }

    Color hue(int i) => streamColors[i % streamColors.length];
    final Paint spareFeed = Paint()
      ..color = s.secondary
      ..strokeWidth = s.w(1.5);

    // Lanes.
    for (int i = 0; i < nss; i++) {
      final double y = laneY(i);
      final Color c = hue(i);
      canvas.drawLine(
        Offset(laneL, y),
        Offset(laneR, y),
        Paint()
          ..color = c
          ..strokeWidth = s.w(3)
          ..strokeCap = StrokeCap.round,
      );
      if (down) {
        _arrowHead(canvas, Offset(laneR + 2, y), 0, c, h: s.m(7));
      } else {
        _arrowHead(canvas, Offset(laneL - 2, y), math.pi, c, h: s.m(7));
      }
      // The label, so the stream never rests on its hue alone.
      final TextStyle tag = s.labelStyle.copyWith(
        color: c,
        fontWeight: FontWeight.w600,
      );
      final double tagW = _textWidth('S${i + 1}', tag) + 6;
      final Offset mid = Offset((laneL + laneR) / 2, y);
      canvas.drawRect(
        Rect.fromCenter(center: mid, width: tagW, height: spacing - 4),
        Paint()..color = s.background,
      );
      _label(canvas, 'S${i + 1}', mid, tag, align: Alignment.center);
    }

    void side({required bool isAp}) {
      final int n = isAp ? ap : cl;
      final Set<int> used = isAp ? apUsed : clUsed;
      final double x = isAp ? apX : clX;
      final double laneEnd = isAp ? laneL : laneR;
      final ChainRole spare = spareRole(isAp: isAp);
      final List<int> usedSorted = used.toList()..sort();
      for (int i = 0; i < n; i++) {
        final Offset e = Offset(x, yOf(i, n));
        if (used.contains(i)) {
          final int laneIdx = usedSorted.indexOf(i);
          canvas.drawLine(
            e,
            Offset(laneEnd, laneY(laneIdx)),
            Paint()
              ..color = hue(laneIdx)
              ..strokeWidth = s.w(1.5),
          );
          _antenna(canvas, e, ChainRole.used, s);
        } else {
          if (spare == ChainRole.contributing && nss > 0) {
            // A spare chain feeds the lanes rather than carrying its own
            // stream. Drawn into the nearest lane only, so 8 chains stay
            // legible.
            final int j = i < n / 2 ? 0 : nss - 1;
            _dashedLine(canvas, e, Offset(laneEnd, laneY(j)), spareFeed);
          }
          _antenna(canvas, e, spare, s);
        }
      }
      // Side label and chain count.
      final TextStyle strong = s.labelStyle.copyWith(
        color: s.primary,
        fontWeight: FontWeight.w600,
      );
      _label(
        canvas,
        isAp ? 'AP' : 'Client',
        Offset(x, 2),
        strong,
        align: Alignment.topCenter,
      );
      _label(
        canvas,
        '$n chain${n == 1 ? '' : 's'}',
        Offset(x, size.height - 2),
        s.labelStyle,
        align: Alignment.bottomCenter,
      );
    }

    side(isAp: true);
    side(isAp: false);

    // Stream count and direction over the lanes.
    _label(
      canvas,
      '$nss stream${nss == 1 ? '' : 's'}, ${down ? 'AP to client' : 'client to AP'}',
      Offset((laneL + laneR) / 2, laneY(0) - spacing / 2 - 2),
      s.labelStyle.copyWith(color: s.primary, fontWeight: FontWeight.w600),
      align: Alignment.bottomCenter,
    );
  }

  @override
  bool shouldRepaint(StreamsPainter old) =>
      old.link.apChains != link.apChains ||
      old.link.clientChains != link.clientChains ||
      old.link.direction != link.direction ||
      old.link.isBeamformed != link.isBeamformed ||
      !listEquals(old.streamColors, streamColors) ||
      old.style != style;
}

// ── Beam pattern, seen from above ───────────────────────────────────────────

/// The AP array at the bottom center, the half-plane in front of it, the
/// array's steered pattern in dB (0 dB at the outer ring, -30 dB at the
/// center), the client, and the sniffer.
class BeamPatternPainter extends CustomPainter {
  BeamPatternPainter({
    required this.elements,
    required this.steered,
    required this.clientDeg,
    required this.snifferDeg,
    required this.style,
  });

  /// AP chains in the array.
  final int elements;

  /// False draws the unsteered reference circle instead of a pattern.
  final bool steered;
  final double clientDeg;
  final double snifferDeg;
  final MimoPaintStyle style;

  static const double rangeDb = 30;
  static const double pad = 14;

  /// [labelRoom] is the space kept above the outer ring for the client and
  /// sniffer labels and beside it for the dB labels (grows with the
  /// presenter text scale).
  static ({Offset center, double radius}) geometry(
    Size size, {
    double labelRoom = 1,
  }) {
    final double r = math.max(
      10,
      math.min(
        size.width / 2 - pad - 18 * labelRoom,
        size.height - pad - 22 * labelRoom,
      ),
    );
    return (center: Offset(size.width / 2, size.height - pad), radius: r);
  }

  static double _rad(double deg) => deg * math.pi / 180;

  static Offset polar(Offset c, double r, double deg) =>
      Offset(c.dx + r * math.sin(_rad(deg)), c.dy - r * math.cos(_rad(deg)));

  /// Angle from straight ahead for a canvas point, degrees, clamped.
  static double angleAt(Offset p, Size size, {double labelRoom = 1}) {
    final ({Offset center, double radius}) g = geometry(
      size,
      labelRoom: labelRoom,
    );
    final Offset v = p - g.center;
    final double a = math.atan2(v.dx, -v.dy) * 180 / math.pi;
    return a.clamp(-90.0, 90.0);
  }

  double _radiusFor(double db, double r) =>
      r * (1 + (db.clamp(-rangeDb, 0.0)) / rangeDb);

  @override
  void paint(Canvas canvas, Size size) {
    final MimoPaintStyle s = style;
    final ({Offset center, double radius}) g = geometry(
      size,
      labelRoom: s.scale.text,
    );
    final Offset c = g.center;
    final double r = g.radius;

    // Grid: rings every 10 dB, spokes every 30 deg.
    final Paint grid = Paint()
      ..color = s.grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.w(1);
    for (int db = 0; db > -rangeDb; db -= 10) {
      final double rr = _radiusFor(db.toDouble(), r);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: rr),
        math.pi,
        math.pi,
        false,
        grid,
      );
      _label(
        canvas,
        '$db',
        Offset(c.dx + rr + 2, c.dy - 2),
        s.labelStyle.copyWith(color: s.tertiary),
        align: Alignment.bottomLeft,
      );
    }
    for (int a = -90; a <= 90; a += 30) {
      canvas.drawLine(c, polar(c, r, a.toDouble()), grid);
    }
    canvas.drawLine(
      Offset(c.dx - r, c.dy),
      Offset(c.dx + r, c.dy),
      Paint()
        ..color = s.axis
        ..strokeWidth = s.w(1),
    );

    // Pattern or the unsteered reference.
    if (steered && elements >= 2) {
      final Path p = Path();
      for (double a = -90; a <= 90.001; a += 0.5) {
        final double db = MimoMath.patternDb(
          elements: elements,
          angleDeg: a,
          steerDeg: clientDeg,
        );
        final Offset pt = polar(c, _radiusFor(db, r), a);
        if (a == -90) {
          p.moveTo(pt.dx, pt.dy);
        } else {
          p.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = s.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.w(2.5)
          ..strokeJoin = StrokeJoin.round,
      );
    } else {
      final Paint ref = Paint()
        ..color = s.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.w(2.5);
      final Path arc = Path()
        ..addArc(Rect.fromCircle(center: c, radius: r), math.pi, math.pi);
      // Dashed: the same level everywhere, nothing steered.
      for (final PathMetric m in arc.computeMetrics()) {
        double d = 0;
        while (d < m.length) {
          canvas.drawPath(
            m.extractPath(d, math.min(d + s.m(8), m.length)),
            ref,
          );
          d += s.m(13);
        }
      }
    }

    // The array: elements along the baseline.
    final double span = math.min(s.m(56), r * 0.4);
    for (int i = 0; i < elements; i++) {
      final double x = elements == 1
          ? c.dx
          : c.dx - span / 2 + span * i / (elements - 1);
      canvas.drawCircle(Offset(x, c.dy), s.m(3), Paint()..color = s.primary);
    }
    _label(
      canvas,
      'AP',
      Offset(c.dx - span / 2 - s.m(8), c.dy + 1),
      s.labelStyle.copyWith(color: s.primary, fontWeight: FontWeight.w600),
      align: Alignment.bottomRight,
    );

    // Sniffer: a dotted radial line out to its position, with a mark where
    // the pattern crosses it.
    final Offset sn = polar(c, r, snifferDeg);
    _dashedLine(
      canvas,
      c,
      sn,
      Paint()
        ..color = s.secondary
        ..strokeWidth = s.w(1.2),
      dash: s.m(3),
      gap: s.m(3),
    );
    final double snDb = steered && elements >= 2
        ? MimoMath.patternDb(
            elements: elements,
            angleDeg: snifferDeg,
            steerDeg: clientDeg,
          )
        : 0;
    canvas.drawCircle(
      polar(c, _radiusFor(snDb, r), snifferDeg),
      s.m(4),
      Paint()
        ..color = s.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.w(2),
    );
    final Rect snBox = Rect.fromCenter(
      center: sn,
      width: s.m(14),
      height: s.m(14),
    );
    canvas.drawRect(snBox, Paint()..color = s.secondary);
    _label(
      canvas,
      'Sniffer',
      sn.translate(0, -s.m(10)),
      s.labelStyle.copyWith(color: s.secondary),
      align: Alignment.bottomCenter,
    );

    // Client: filled marker at its angle, on the outer ring.
    final Offset cl = polar(c, r, clientDeg);
    canvas.drawCircle(cl, s.m(8), Paint()..color = s.primary);
    canvas.drawCircle(cl, s.m(4), Paint()..color = s.accent);
    _label(
      canvas,
      'Client',
      cl.translate(0, -s.m(12)),
      s.labelStyle.copyWith(color: s.primary, fontWeight: FontWeight.w600),
      align: Alignment.bottomCenter,
    );
  }

  @override
  bool shouldRepaint(BeamPatternPainter old) =>
      old.elements != elements ||
      old.steered != steered ||
      old.clientDeg != clientDeg ||
      old.snifferDeg != snifferDeg ||
      old.style != style;
}

// ── Sounding airtime ────────────────────────────────────────────────────────

/// Row 1: the sounding exchange to scale (NDPA, SIFS, NDP, SIFS, report).
/// Row 2: one sounding interval, with the exchange's share in lime.
class SoundingPainter extends CustomPainter {
  SoundingPainter({
    required this.segments,
    required this.share,
    required this.style,
  });

  final List<SoundingSegment> segments;

  /// 0 to 1: the exchange as a share of the interval.
  final double share;
  final MimoPaintStyle style;

  static const double barH = 26;

  /// Height the painter needs at text scale [t] (1 outside presenter mode).
  static double heightFor(double t) => (18 + barH + 26 + barH * 0.6) * t + 4;

  @override
  void paint(Canvas canvas, Size size) {
    final MimoPaintStyle s = style;
    final double total = segments.fold<double>(0, (double a, b) => a + b.us);
    if (total <= 0) return;
    final double w = size.width;

    // Row 1: the exchange. Rows grow with the presenter text scale.
    final double bar = s.t(barH);
    final double y1 = s.t(18);
    _label(
      canvas,
      'One sounding exchange',
      const Offset(0, 0),
      s.labelStyle.copyWith(color: s.tertiary),
    );
    double x = 0;
    final Paint block = Paint()..color = s.fill;
    final Paint edge = Paint()
      ..color = s.axis
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.w(1);
    for (final SoundingSegment seg in segments) {
      final double sw = w * seg.us / total;
      final Rect rect = Rect.fromLTWH(x, y1, sw, bar);
      if (seg.isGap) {
        _dashedLine(
          canvas,
          Offset(rect.center.dx, y1 + 4),
          Offset(rect.center.dx, y1 + bar - 4),
          Paint()
            ..color = s.tertiary
            ..strokeWidth = s.w(1),
          dash: 2,
          gap: 2,
        );
      } else {
        canvas.drawRect(rect.deflate(0.5), block);
        canvas.drawRect(rect.deflate(0.5), edge);
        if (_textWidth(seg.name, s.labelStyle) + 6 < sw) {
          _label(
            canvas,
            seg.name,
            rect.center,
            s.labelStyle.copyWith(color: s.primary),
            align: Alignment.center,
          );
        }
      }
      x += sw;
    }

    // Row 2: the interval.
    final double y2 = y1 + bar + s.t(26);
    _label(
      canvas,
      'One sounding interval',
      Offset(0, y2 - s.t(18)),
      s.labelStyle.copyWith(color: s.tertiary),
    );
    final Rect whole = Rect.fromLTWH(0, y2, w, bar * 0.6);
    canvas.drawRect(whole.deflate(0.5), edge);
    final double sw = math.max(2, w * share.clamp(0.0, 1.0));
    canvas.drawRect(
      Rect.fromLTWH(whole.left, whole.top, sw, whole.height),
      Paint()..color = s.accent,
    );
  }

  @override
  bool shouldRepaint(SoundingPainter old) =>
      old.share != share || old.style != style || old.segments != segments;
}
