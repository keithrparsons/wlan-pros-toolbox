// Airtime Fairness (Wi-Fi Lab) — the animated round.
//
// One lane per fairness rule. Each transmission is a block whose width is its
// airtime on one shared time scale, so under packet fairness the slow client's
// block visibly dominates. Inside a block the fixed overhead (wait, backoff,
// preamble, SIFS, ACK) is drawn outlined and the frames are drawn filled, which
// is lesson 1 of the spec: a PHY rate is not a throughput.
//
// THEME: context.colors only. Clients are told apart by the letter above each
// block and by position, never by hue (GL-003 §8.15). Lime fill marks the one
// quantity the chart is about, the frames on the air.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/airtime_fairness_model.dart';
import '../../../theme/app_color_scheme.dart';

/// Lane geometry, in logical pixels.
abstract final class RoundLaneGeometry {
  /// Strip above the blocks that carries the client letters.
  static const double letterStrip = 16;

  /// Height of a transmission block.
  static const double blockHeight = 28;

  static const double height = letterStrip + blockHeight;
}

class AirtimeRoundPainter extends CustomPainter {
  AirtimeRoundPainter({
    required this.schedule,
    required this.windowUs,
    required this.progress,
    required this.colors,
    required this.letterStyle,
  }) : super(repaint: progress);

  final List<ScheduledTx> schedule;
  final double windowUs;

  /// 0 to 1: how much of the window has played. 1 draws the round complete.
  final Animation<double> progress;
  final AppColorScheme colors;
  final TextStyle letterStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (windowUs <= 0 || size.width <= 0) return;
    final double scale = size.width / windowUs;
    final double shown = progress.value.clamp(0.0, 1.0) * windowUs;
    const double top = RoundLaneGeometry.letterStrip;
    const double h = RoundLaneGeometry.blockHeight;

    // Lane track.
    final Rect lane = Rect.fromLTWH(0, top, size.width, h);
    canvas.drawRect(lane, Paint()..color = colors.surface2);

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final Paint dataFill = Paint()..color = colors.primary;
    final Paint dataEdge = Paint()
      ..color = colors.textAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final Paint overheadEdge = Paint()
      ..color = colors.borderStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final List<TextPainter> letters = <TextPainter>[
      for (int i = 0; i < AirtimeConstants.maxClients; i++)
        TextPainter(
          text: TextSpan(
            text: clientLetter(i),
            style: letterStyle.copyWith(color: colors.textPrimary),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];

    for (final ScheduledTx tx in schedule) {
      if (tx.startUs >= shown || tx.startUs >= windowUs) break;
      final double end = tx.endUs < shown ? tx.endUs : shown;
      final double x0 = tx.startUs * scale;
      final double xOh = (tx.startUs + tx.overheadUs) * scale;
      final double x1 = end * scale;

      // Overhead: outlined, unfilled.
      final double ohRight = xOh < x1 ? xOh : x1;
      if (ohRight > x0) {
        canvas.drawRect(
          Rect.fromLTRB(x0 + 0.5, top + 0.5, ohRight - 0.5, top + h - 0.5),
          overheadEdge,
        );
      }
      // Frames: filled lime with an accent edge (keeps 3:1 on light).
      if (x1 > xOh) {
        final Rect data = Rect.fromLTRB(xOh, top, x1, top + h);
        canvas.drawRect(data, dataFill);
        canvas.drawRect(data.deflate(0.5), dataEdge);
      }
      // Letter above the block, once the block has started and fits.
      final TextPainter tp = letters[tx.client % letters.length];
      final double fullW = tx.durationUs * scale;
      if (fullW >= tp.width + 2) {
        final double cx = x0 + fullW / 2;
        if (cx <= shown * scale || progress.value >= 1) {
          tp.paint(canvas, Offset(cx - tp.width / 2, 0));
        }
      }
    }
    canvas.restore();

    // Playhead while the round is playing.
    if (progress.value < 1) {
      final double x = shown * scale;
      canvas.drawLine(
        Offset(x, top - 2),
        Offset(x, top + h + 2),
        Paint()
          ..color = colors.textPrimary
          ..strokeWidth = 2,
      );
    }

    for (final TextPainter tp in letters) {
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(AirtimeRoundPainter old) =>
      old.schedule != schedule ||
      old.windowUs != windowUs ||
      old.progress != progress ||
      old.colors != colors ||
      old.letterStyle != letterStyle;
}

/// Legend swatch: the overhead outline or the frames fill, painted the same
/// way the lane paints them.
class RoundSwatchPainter extends CustomPainter {
  RoundSwatchPainter({required this.frames, required this.colors});

  final bool frames;
  final AppColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    if (frames) {
      canvas.drawRect(r, Paint()..color = colors.primary);
      canvas.drawRect(
        r.deflate(0.5),
        Paint()
          ..color = colors.textAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    } else {
      canvas.drawRect(r, Paint()..color = colors.surface2);
      canvas.drawRect(
        r.deflate(0.5),
        Paint()
          ..color = colors.borderStrong
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(RoundSwatchPainter old) =>
      old.frames != frames || old.colors != colors;
}
