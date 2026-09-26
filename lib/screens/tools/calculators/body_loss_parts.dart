// Shared small widgets for the Wi-Fi Classroom Body Loss tool: card, section
// label, note row, legend swatches and the received-level gauge. Used by the
// stage, the readouts and the controls, so none imports another.
//
// COLOR: context.colors only. The crowd is neutral (textTertiary); a person
// on the line to the AP takes the accent (colors.primary, the "computed"
// role) as a FILL with an ink outline, AND a numbered badge, so the mark
// never rests on color alone. On light, lime is a fill only and the ink
// outline carries the contrast (GL-003 §8.20.2 rule 1). No
// status hues: a level or an MCS is a description, not a verdict
// (GL-003 §8.13 rule 6).
//
// ASCII copy, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'body_loss_controller.dart';

class BlCard extends StatelessWidget {
  const BlCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}

class BlSectionLabel extends StatelessWidget {
  const BlSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.textSecondary,
          letterSpacing: 0.4,
          fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

class BlNote extends StatelessWidget {
  const BlNote(this.icon, this.message, {super.key});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: colors.textTertiary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// What a legend swatch shows.
enum BlSwatchKind { person, onLine, holder, line }

/// A small legend mark drawn the way the stage draws the thing it names.
class BlSwatch extends StatelessWidget {
  const BlSwatch({super.key, required this.kind});
  final BlSwatchKind kind;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PresenterScale s = PresenterMode.scaleOf(context);
    return CustomPaint(
      size: Size(22 * s.marker, 14 * s.marker),
      painter: _SwatchPainter(
        kind: kind,
        ink: colors.textPrimary,
        crowd: colors.textTertiary,
        accent: colors.primary,
        surface: colors.surface2,
        stroke: s.strokeWidth(2),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter({
    required this.kind,
    required this.ink,
    required this.crowd,
    required this.accent,
    required this.surface,
    required this.stroke,
  });

  final BlSwatchKind kind;
  final Color ink;
  final Color crowd;
  final Color accent;
  final Color surface;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.height * 0.36;
    switch (kind) {
      case BlSwatchKind.person:
        canvas.drawCircle(c, r, Paint()..color = crowd);
      case BlSwatchKind.onLine:
        canvas.drawCircle(c, r, Paint()..color = accent);
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * 0.75
            ..color = ink,
        );
      case BlSwatchKind.holder:
        canvas.drawOval(
          Rect.fromCenter(center: c, width: size.width * 0.7, height: r * 1.6),
          Paint()..color = ink,
        );
      case BlSwatchKind.line:
        canvas.drawLine(
          Offset(1, c.dy),
          Offset(size.width - 1, c.dy),
          Paint()
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round
            ..color = ink,
        );
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.kind != kind ||
      old.ink != ink ||
      old.crowd != crowd ||
      old.accent != accent ||
      old.stroke != stroke;
}

// ── Gauge ─────────────────────────────────────────────────────────────────

/// The received-level gauge: a bar from [minDbm] to [maxDbm] with the level
/// now (solid marker) and, when it differs, the empty-building level (open
/// marker), and the MCS in words beside it.
class BlGauge extends StatelessWidget {
  const BlGauge({super.key, required this.config});
  final BlConfig config;

  static const double minDbm = -95;
  static const double maxDbm = -35;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale s = PresenterMode.scaleOf(context);
    final BlConfig c = config;
    final bool showEmpty = (c.emptyDbm - c.receivedDbm).abs() > 0.05;
    return Semantics(
      label:
          'Received level ${BlFormat.dbm(c.receivedDbm)}, '
          '${BlFormat.mcs(c.mcs)}'
          '${showEmpty ? '. Empty building ${BlFormat.dbm(c.emptyDbm)}' : ''}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                'Received  ',
                style: text.labelMedium?.copyWith(color: colors.textSecondary),
              ),
              Text(
                BlFormat.dbm(c.receivedDbm),
                style: mono.outputMedium.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  c.mcs == null ? 'Below MCS 0' : 'MCS ${c.mcs}',
                  style: mono.outputMedium.copyWith(color: colors.textAccent),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          SizedBox(
            height: 22 * s.marker,
            child: CustomPaint(
              painter: _GaugePainter(
                now: c.receivedDbm,
                empty: showEmpty ? c.emptyDbm : null,
                track: colors.disabledFill,
                fill: colors.primary,
                ink: colors.textPrimary,
                surface: colors.surface1,
                stroke: s.strokeWidth(2),
                marker: s.markerSize(7),
              ),
            ),
          ),
          Row(
            children: <Widget>[
              Text(
                '${minDbm.round()} dBm',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
              const Spacer(),
              if (showEmpty)
                Flexible(
                  flex: 4,
                  child: Text(
                    'Open marker: empty building',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ),
              const Spacer(),
              Text(
                '${maxDbm.round()} dBm',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.now,
    required this.empty,
    required this.track,
    required this.fill,
    required this.ink,
    required this.surface,
    required this.stroke,
    required this.marker,
  });

  final double now;
  final double? empty;
  final Color track;
  final Color fill;
  final Color ink;
  final Color surface;
  final double stroke;
  final double marker;

  double _x(Size size, double dbm) {
    final double t =
        ((dbm - BlGauge.minDbm) / (BlGauge.maxDbm - BlGauge.minDbm)).clamp(
          0.0,
          1.0,
        );
    return marker + t * (size.width - 2 * marker);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height / 2;
    final double h = math.max(6, size.height * 0.34);
    final RRect bar = RRect.fromLTRBR(
      marker,
      y - h / 2,
      size.width - marker,
      y + h / 2,
      Radius.circular(h / 2),
    );
    canvas.drawRRect(bar, Paint()..color = track);
    final double xn = _x(size, now);
    canvas.drawRRect(
      RRect.fromLTRBR(marker, y - h / 2, xn, y + h / 2, Radius.circular(h / 2)),
      Paint()..color = fill,
    );
    final double? e = empty;
    if (e != null) {
      canvas.drawCircle(
        Offset(_x(size, e), y),
        marker,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = ink,
      );
    }
    canvas.drawCircle(
      Offset(xn, y),
      marker + stroke / 2,
      Paint()..color = surface,
    );
    canvas.drawCircle(Offset(xn, y), marker, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.now != now ||
      old.empty != empty ||
      old.track != track ||
      old.fill != fill ||
      old.ink != ink ||
      old.stroke != stroke ||
      old.marker != marker;
}
