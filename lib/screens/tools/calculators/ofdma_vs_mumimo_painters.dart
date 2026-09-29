// Painters for OFDMA vs MU-MIMO (Wi-Fi Classroom): the room seen from above
// (the AP, its zero-forcing beams and the clients) and the sounding bracket
// under the MU-MIMO timeline. The timelines themselves reuse
// OfdmaBarPainter from OFDMA Resource Units, so the two tools draw airtime
// the same way.
//
// COLOR. Each client keeps one hue from the Wi-Fi Classroom client palette
// (GL-003 §8.15.2) in the room, its beam and its data lanes, and its letter
// is always drawn with it. The AP, the distance arcs and the wall are neutral
// (textPrimary, border, borderStrong).
//
// SCALE. Everything is linear: distance in meters (or feet) on the arcs, and
// each beam's radius is its power toward that direction as a share of the
// full array gain, so a null is drawn as zero, not as a floor on a log axis.
//
// The painting is a picture: the stage wraps it in a worded Semantics label.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/mu_mimo_model.dart';
import '../../../services/wifi_lab/ofdma_model.dart' show clientLetter;
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';

/// Where things sit in the room painting, for the painter, the drag handler
/// and the tests.
class MuRoomGeometry {
  MuRoomGeometry(
    this.size, {
    this.marker = 1,
    this.viewRadiusM = MuLimits.maxDistanceM,
  });

  final Size size;
  final double marker;

  /// Meters from the AP to the top of the drawing.
  final double viewRadiusM;

  /// Room the AP glyph and its label need under the array.
  double get bottomPad => AppSpacing.lg * marker;

  double get sidePad => AppSpacing.sm;

  /// The AP's array center, pixels.
  Offset get ap => Offset(size.width / 2, size.height - bottomPad);

  /// Pixels for the farthest allowed client.
  double get radiusPx => math.max(
    1,
    math.min(size.width / 2 - sidePad, size.height - bottomPad - sidePad),
  );

  double get pxPerM => radiusPx / viewRadiusM;

  /// Client dot radius.
  double get dotRadius => (AppSpacing.sm + AppSpacing.xxs) * marker;

  Offset toPx(MuClient c) {
    final (double x, double y) = c.xy;
    return ap + Offset(x * pxPerM, -y * pxPerM);
  }

  /// A point on the canvas as a client position.
  MuClient toClient(Offset p) {
    final Offset d = p - ap;
    return MuClient.fromXy(d.dx / pxPerM, -d.dy / pxPerM);
  }

  /// The client under [p], nearest first, within a 44 px touch target.
  int? clientAt(List<MuClient> clients, Offset p) {
    int? best;
    double bestD = math.max(dotRadius, AppSpacing.minTouchTarget / 2);
    for (int i = 0; i < clients.length; i++) {
      final double d = (toPx(clients[i]) - p).distance;
      if (d <= bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// Pixel height the room wants for [width]: a half disc plus the AP.
  static double heightFor(double width, {double marker = 1}) =>
      width / 2 + AppSpacing.lg * marker;
}

class MuRoomPainter extends CustomPainter {
  MuRoomPainter({
    required this.clients,
    required this.precoding,
    required this.antennas,
    required this.reflection,
    required this.selected,
    required this.colors,
    required this.labelStyle,
    required this.letterStyle,
    required this.textScaler,
    required this.units,
    required this.viewRadiusM,
    this.stroke = 1,
    this.marker = 1,
  });

  final double viewRadiusM;

  final List<MuClient> clients;
  final MuPrecoding precoding;
  final int antennas;
  final bool reflection;
  final int selected;
  final AppColorScheme colors;
  final TextStyle labelStyle;
  final TextStyle letterStyle;
  final TextScaler textScaler;
  final UnitSystem units;
  final double stroke;
  final double marker;

  TextPainter _text(String s, TextStyle style) => TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final MuRoomGeometry g = MuRoomGeometry(
      size,
      marker: marker,
      viewRadiusM: viewRadiusM,
    );
    final Offset ap = g.ap;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Distance arcs, in round numbers of the unit on screen.
    final LengthFormat f = LengthFormat(units);
    final bool close = viewRadiusM <= 15;
    final List<double> arcsM = <double>[
      if (units.isMetric)
        for (double m = close ? 5 : 10; m < viewRadiusM; m += close ? 5 : 10) m
      else
        for (
          double ft = close ? 15 : 25;
          LengthUnits.feetToMetres(ft) < viewRadiusM;
          ft += close ? 15 : 25
        )
          LengthUnits.feetToMetres(ft),
    ];
    // Arc labels go under the baseline, clear of the beams; any that would
    // touch the AP label are skipped.
    final List<(double, String)> arcLabels = <(double, String)>[];
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = colors.border;
    for (final double m in arcsM) {
      final double r = m * g.pxPerM;
      canvas.drawArc(
        Rect.fromCircle(center: ap, radius: r),
        math.pi,
        math.pi,
        false,
        arc,
      );
      arcLabels.add((ap.dx + r, f.dist(m, decimals: 0)));
    }
    // The wall the AP is mounted on.
    canvas.drawLine(
      Offset(0, ap.dy),
      Offset(size.width, ap.dy),
      Paint()
        ..strokeWidth = stroke
        ..color = colors.borderStrong,
    );

    // Side wall for the reflection.
    if (reflection) {
      final double wx = ap.dx + MuLink.wallOffsetM * g.pxPerM;
      if (wx < size.width) {
        canvas.drawLine(
          Offset(wx, 0),
          Offset(wx, ap.dy),
          Paint()
            ..strokeWidth = 3 * stroke
            ..color = colors.borderStrong,
        );
        final TextPainter tp = _text(
          'Wall',
          labelStyle.copyWith(color: colors.textSecondary),
        );
        tp.paint(
          canvas,
          Offset(wx - tp.width - AppSpacing.xxs, AppSpacing.xxs),
        );
        for (int i = 0; i < clients.length; i++) {
          final (double x, double y) = clients[i].xy;
          final double imageX = 2 * MuLink.wallOffsetM - x;
          if (imageX <= 0) continue;
          final double t = MuLink.wallOffsetM / imageX;
          final Offset hit = ap + Offset(wx - ap.dx, -y * t * g.pxPerM);
          final Color hue = WifiLabClientPalette.of(i, colors).hue;
          _dashed(canvas, ap, hit, hue);
          _dashed(canvas, hit, g.toPx(clients[i]), hue);
        }
      }
    }

    // Zero-forcing beams: power toward each direction, linear, 1.0 = the
    // whole array aimed at one client.
    if (precoding.possible) {
      final double rb = g.radiusPx * 0.95;
      for (int k = 0; k < clients.length; k++) {
        final Color hue = WifiLabClientPalette.of(k, colors).hue;
        final Path p = Path()..moveTo(ap.dx, ap.dy);
        for (int d = -90; d <= 90; d++) {
          final double gain = precoding.beamGain(k, d.toDouble());
          final double a = d * math.pi / 180;
          p.lineTo(
            ap.dx + rb * gain * math.sin(a),
            ap.dy - rb * gain * math.cos(a),
          );
        }
        p.close();
        canvas.drawPath(p, Paint()..color = hue.withValues(alpha: 0.14));
        canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 * stroke
            ..color = hue,
        );
      }
    }

    // The AP: one dot per antenna along the array.
    final double spacing = AppSpacing.xs * marker;
    final double half = (antennas - 1) * spacing / 2;
    final Rect body = Rect.fromLTRB(
      ap.dx - half - AppSpacing.xxs * marker,
      ap.dy - AppSpacing.xxs * marker,
      ap.dx + half + AppSpacing.xxs * marker,
      ap.dy + AppSpacing.xxs * marker,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(AppRadius.control)),
      Paint()..color = colors.surface2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(AppRadius.control)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = colors.textPrimary,
    );
    for (int n = 0; n < antennas; n++) {
      canvas.drawCircle(
        Offset(ap.dx - half + n * spacing, ap.dy),
        1.5 * marker,
        Paint()..color = colors.textPrimary,
      );
    }
    final TextPainter apLabel = _text(
      'AP, $antennas antennas',
      labelStyle.copyWith(color: colors.textSecondary),
    );
    final Offset apAt = Offset(
      ap.dx - apLabel.width / 2,
      body.bottom + AppSpacing.xxs,
    );
    apLabel.paint(canvas, apAt);
    final Rect apRect = (apAt & apLabel.size).inflate(AppSpacing.xxs);
    for (final (double x, String s) in arcLabels) {
      final TextPainter tp = _text(
        s,
        labelStyle.copyWith(color: colors.textTertiary),
      );
      final Rect at =
          Offset(x - tp.width / 2, ap.dy + AppSpacing.xxs) & tp.size;
      if (at.overlaps(apRect) || at.right > size.width) continue;
      tp.paint(canvas, at.topLeft);
    }

    // Clients.
    for (int i = 0; i < clients.length; i++) {
      final WifiLabClientStyle st = WifiLabClientPalette.of(i, colors);
      final Offset c = g.toPx(clients[i]);
      if (i == selected) {
        canvas.drawCircle(
          c,
          g.dotRadius + 3 * stroke,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * stroke
            ..color = colors.textPrimary,
        );
      }
      canvas.drawCircle(c, g.dotRadius, Paint()..color = st.hue);
      final TextPainter tp = _text(
        clientLetter(i),
        letterStyle.copyWith(color: st.onHue),
      );
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
    canvas.restore();
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Color hue) {
    final Paint p = Paint()
      ..strokeWidth = stroke
      ..color = hue.withValues(alpha: 0.7);
    final double len = (b - a).distance;
    if (len <= 0) return;
    final Offset dir = (b - a) / len;
    const double dash = 6;
    for (double s = 0; s < len; s += dash * 2) {
      canvas.drawLine(a + dir * s, a + dir * math.min(s + dash, len), p);
    }
  }

  @override
  bool shouldRepaint(MuRoomPainter old) =>
      old.clients != clients ||
      old.precoding != precoding ||
      old.antennas != antennas ||
      old.reflection != reflection ||
      old.selected != selected ||
      old.colors != colors ||
      old.labelStyle != labelStyle ||
      old.letterStyle != letterStyle ||
      old.textScaler != textScaler ||
      old.units != units ||
      old.viewRadiusM != viewRadiusM ||
      old.stroke != stroke ||
      old.marker != marker;
}

/// A bracket under the MU-MIMO bar spanning the sounding, with its label.
class MuSoundingBracketPainter extends CustomPainter {
  MuSoundingBracketPainter({
    required this.startUs,
    required this.lengthUs,
    required this.scaleUs,
    required this.label,
    required this.colors,
    required this.style,
    required this.textScaler,
    this.stroke = 1,
  });

  final double startUs;
  final double lengthUs;
  final double scaleUs;
  final String label;
  final AppColorScheme colors;
  final TextStyle style;
  final TextScaler textScaler;
  final double stroke;

  static double heightFor(TextStyle style, TextScaler scaler) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: 'Sounding', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return AppSpacing.xxs * 2 + tp.height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (scaleUs <= 0) return;
    final double px = size.width / scaleUs;
    final double l = startUs * px + 1;
    final double r = math.min((startUs + lengthUs) * px, size.width) - 1;
    if (r - l < 2) return;
    final Paint line = Paint()
      ..color = colors.textSecondary
      ..strokeWidth = stroke;
    const double y = AppSpacing.xxs;
    canvas
      ..drawLine(Offset(l, y), Offset(r, y), line)
      ..drawLine(Offset(l, 0), Offset(l, y), line)
      ..drawLine(Offset(r, 0), Offset(r, y), line);
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: label,
        style: style.copyWith(color: colors.textSecondary),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    // Centered under the bracket, kept inside the canvas.
    final double x = ((l + r) / 2 - tp.width / 2).clamp(
      0.0,
      math.max(0.0, size.width - tp.width),
    );
    tp.paint(canvas, Offset(x, y + 1));
  }

  @override
  bool shouldRepaint(MuSoundingBracketPainter old) =>
      old.startUs != startUs ||
      old.lengthUs != lengthUs ||
      old.scaleUs != scaleUs ||
      old.label != label ||
      old.colors != colors ||
      old.style != style ||
      old.textScaler != textScaler ||
      old.stroke != stroke;
}
