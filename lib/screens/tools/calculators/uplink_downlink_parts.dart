// Shared small widgets for the Wi-Fi Classroom Uplink vs Downlink tool: card,
// section label, note row, the two direction hues and a line swatch. Used by
// the stage and the controls, so neither imports the other.
//
// COLOR (GL-003 §8.15.2): the two directions take two hues from the Wi-Fi
// Classroom family (lib/theme/wifi_lab_client_palette.dart), which clears the
// §8.9 non-text contrast floor on both themes. Color never carries the
// direction alone: the downlink is a SOLID line and the uplink a DASHED one,
// every line is labeled in words, and every arrow has a head.
//
// ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import '../../../widgets/presenter/presenter_mode.dart';

class UdCard extends StatelessWidget {
  const UdCard({super.key, required this.child});
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

class UdSectionLabel extends StatelessWidget {
  const UdSectionLabel(this.label, {super.key});
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

class UdNote extends StatelessWidget {
  const UdNote(this.icon, this.message, {super.key});
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

/// The two directions.
enum UdDir { downlink, uplink }

/// The hue of each direction, the one home of this tool's palette.
abstract final class UdPalette {
  /// Classroom family index: the blue for the downlink, the amber for the
  /// uplink. Far apart in hue, and the line pattern tells them apart anyway.
  static const int _downIndex = 6;
  static const int _upIndex = 1;

  static Color of(UdDir d, AppColorScheme colors) => WifiLabClientPalette.of(
    d == UdDir.downlink ? _downIndex : _upIndex,
    colors,
  ).hue;
}

/// A short line in a direction's hue and pattern (solid down, dashed up),
/// for legends.
class UdLineSwatch extends StatelessWidget {
  const UdLineSwatch({super.key, required this.dir});
  final UdDir dir;

  @override
  Widget build(BuildContext context) {
    final PresenterScale s = PresenterMode.scaleOf(context);
    return CustomPaint(
      size: Size(28 * s.marker, 12 * s.marker),
      painter: _LineSwatchPainter(
        color: UdPalette.of(dir, context.colors),
        dashed: dir == UdDir.uplink,
        width: s.strokeWidth(2.5),
      ),
    );
  }
}

class _LineSwatchPainter extends CustomPainter {
  _LineSwatchPainter({
    required this.color,
    required this.dashed,
    required this.width,
  });

  final Color color;
  final bool dashed;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final double y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(1, y), Offset(size.width - 1, y), p);
      return;
    }
    final double dash = size.width / 4;
    for (double x = 1; x < size.width; x += dash * 1.6) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dash).clamp(0, size.width - 1), y),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_LineSwatchPainter old) =>
      old.color != color || old.dashed != dashed || old.width != width;
}

/// A filled swatch for the asymmetry zone in legends.
class UdZoneSwatch extends StatelessWidget {
  const UdZoneSwatch({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final double k = PresenterMode.scaleOf(context).marker;
    return Container(
      width: 28 * k,
      height: 12 * k,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.primary.withValues(alpha: kUdZoneAlpha),
          colors.surface2,
        ),
        border: Border.all(color: colors.primary),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Opacity of the asymmetry-zone wash (stage and legend share it).
const double kUdZoneAlpha = 0.22;
