// The stage for Legacy Protection Cost (Wi-Fi Classroom): the headline
// payload rate and loss, a few milliseconds of the channel with modern
// devices only beside this network, one send cycle of each drawn to scale,
// and a beacon inspector with the ERP bits and the HT Protection value.
// Reads a [LegacyProtectionController]; owns no state, so a presenter layout
// can place it beside [LegacyProtectionControls].
//
// COLOR AND PATTERN (GL-003 §8.13 / §8.15, §8.15.2). The frame parts reuse
// Airtime Anatomy's block styles (paintAirtimeBlock): hatching for waits,
// gray preamble, lime data, dashed SIFS, outlined ACK. The two costs an
// 802.11b device adds while silent are the only warning-hued marks, and
// each has its own pattern and its own label, never color alone:
//   - the protection frame: vertical bars, a warning outline, "CTS" / "RTS"
//   - the added wait (long slot, and CWmin 31 when chosen): the wait hatch
//     drawn in the warning hue with a warning outline
// Light theme: statusWarning is bronze (6.0:1), above the 3:1 graphics floor.
//
// MOTION (§8.8). Play sweeps the window, about two thousand times slower
// than real time. With reduced motion on, the window is drawn whole and
// nothing moves unless the user presses Play.
//
// ACCESSIBILITY. The drawings are pictures: each carries a worded Semantics
// label, and every duration they show is also in text (SC 1.4.1).
//
// PRESENTER (PresenterMode.isActive): the stage fills its bounded box; the
// lanes take the spare height, and the headline numbers use the presenter
// headline scale.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../services/wifi_lab/legacy_protection_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'airtime_anatomy_timeline.dart'
    show AirtimeBlockStyle, paintAirtimeBlock;
import 'legacy_protection_controller.dart';

class LegacyProtectionStage extends StatelessWidget {
  const LegacyProtectionStage({super.key, required this.controller});

  final LegacyProtectionController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final Widget headline = _Headline(controller: controller);
        final Widget channel = _ChannelCard(
          controller: controller,
          fill: presenting,
        );
        final Widget cycle = _CycleCard(controller: controller);
        final Widget inspector = _BeaconInspector(controller: controller);
        if (presenting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              headline,
              const SizedBox(height: AppSpacing.xs),
              Expanded(child: channel),
              const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 3, child: cycle),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(flex: 2, child: inspector),
                ],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            headline,
            const SizedBox(height: AppSpacing.sm),
            channel,
            const SizedBox(height: AppSpacing.sm),
            cycle,
            const SizedBox(height: AppSpacing.sm),
            inspector,
          ],
        );
      },
    );
  }
}

// ── Headline ────────────────────────────────────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline({required this.controller});

  final LegacyProtectionController controller;

  @override
  Widget build(BuildContext context) {
    final LpResult r = controller.result;
    final bool masked = controller.masked;
    final String rate = lpMbps(r.cycle.payloadRateMbps);
    final String base = lpMbps(r.baseline.payloadRateMbps);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        _HeadlineTile(
          label: 'The laptop\'s payload rate',
          value: masked ? '?' : rate,
          note: masked ? 'hidden until Reveal' : 'modern devices only: $base',
          semantics: masked
              ? 'Payload rate hidden until Reveal'
              : 'The laptop\'s payload rate is $rate; with modern devices '
                    'only it would be $base',
        ),
        _HeadlineTile(
          label: 'Lost to the old device',
          value: masked ? '?' : lpPct(r.lostShare),
          note: masked
              ? 'hidden until Reveal'
              : r.lostShare == 0
              ? 'nothing old is associated or heard'
              : 'while it sends nothing',
          semantics: masked
              ? 'Share lost hidden until Reveal'
              : '${lpPct(r.lostShare)} of the payload rate lost',
        ),
      ],
    );
  }
}

class _HeadlineTile extends StatelessWidget {
  const _HeadlineTile({
    required this.label,
    required this.value,
    required this.note,
    required this.semantics,
  });

  final String label;
  final String value;
  final String note;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          Text(
            value,
            style: scale.headlineStyle(
              mono.outputLarge.copyWith(color: colors.textAccent),
            ),
          ),
          Text(
            note,
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── Pieces: a cycle split into drawable parts ───────────────────────────────

/// How one drawn part looks. The first five are Airtime Anatomy's styles.
enum LpPieceStyle {
  wait,
  addedWait,
  protection,
  preamble,
  data,
  gap,
  control;

  AirtimeBlockStyle? get airtime => switch (this) {
    LpPieceStyle.wait => AirtimeBlockStyle.wait,
    LpPieceStyle.preamble => AirtimeBlockStyle.preamble,
    LpPieceStyle.data => AirtimeBlockStyle.data,
    LpPieceStyle.gap => AirtimeBlockStyle.gap,
    LpPieceStyle.control => AirtimeBlockStyle.control,
    LpPieceStyle.addedWait || LpPieceStyle.protection => null,
  };
}

/// One drawn part of a cycle: its look, its length, and a short label for
/// inside the close-up bar.
typedef LpPiece = ({LpPieceStyle style, int tenths, String tag});

/// Splits a cycle into drawn parts, in order. A wait with an added part
/// becomes two pieces (base, then added); a protection exchange becomes its
/// frames and SIFS gaps.
List<LpPiece> lpPieces(LpCycle c) {
  final List<LpPiece> out = <LpPiece>[];
  for (final LpSegment s in c.segments) {
    switch (s.kind) {
      case LpSegmentKind.difs:
      case LpSegmentKind.backoff:
        final String name = s.kind == LpSegmentKind.difs ? 'DIFS' : 'Backoff';
        final int base = s.baseTenths ?? s.tenths;
        out.add((style: LpPieceStyle.wait, tenths: base, tag: name));
        if (s.addedTenths > 0) {
          out.add((
            style: LpPieceStyle.addedWait,
            tenths: s.addedTenths,
            tag: '+${formatUs(s.addedTenths / 10)}',
          ));
        }
      case LpSegmentKind.protection:
        final ProtectionTiming p = c.protection!;
        if (p.rtsTenths > 0) {
          out
            ..add((
              style: LpPieceStyle.protection,
              tenths: p.rtsTenths,
              tag: 'RTS',
            ))
            ..add((style: LpPieceStyle.gap, tenths: p.sifsTenths, tag: ''));
        }
        out
          ..add((
            style: LpPieceStyle.protection,
            tenths: p.ctsTenths,
            tag: 'CTS',
          ))
          ..add((style: LpPieceStyle.gap, tenths: p.sifsTenths, tag: ''));
      case LpSegmentKind.preamble:
        out.add((style: LpPieceStyle.preamble, tenths: s.tenths, tag: ''));
      case LpSegmentKind.data:
        out.add((style: LpPieceStyle.data, tenths: s.tenths, tag: 'Data'));
      case LpSegmentKind.sifs:
        out.add((style: LpPieceStyle.gap, tenths: s.tenths, tag: ''));
      case LpSegmentKind.ack:
        out.add((style: LpPieceStyle.control, tenths: s.tenths, tag: 'ACK'));
    }
  }
  return out;
}

/// "82.5" or "304" (no unit).
String formatUs(double us) =>
    us == us.roundToDouble() ? us.toStringAsFixed(0) : us.toStringAsFixed(1);

/// Draws one piece.
void paintLpPiece(
  Canvas canvas,
  Rect rect,
  LpPieceStyle style,
  AppColorScheme colors, {
  double stroke = 1,
}) {
  final AirtimeBlockStyle? a = style.airtime;
  if (a != null) {
    paintAirtimeBlock(canvas, rect, a, colors, stroke: stroke);
    return;
  }
  final double w = stroke;
  canvas.drawRect(rect, Paint()..color = colors.statusWarningFill);
  canvas.save();
  canvas.clipRect(rect);
  final Paint p = Paint()
    ..color = colors.statusWarning
    ..strokeWidth = w;
  if (style == LpPieceStyle.protection) {
    // Vertical bars.
    final double step = 4 * w;
    for (double x = rect.left + step / 2; x < rect.right; x += step) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), p);
    }
  } else {
    // The wait hatch, in the warning hue.
    final double step = 6 * w;
    for (double x = rect.left - rect.height; x < rect.right; x += step) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(x + rect.height, rect.top),
        p,
      );
    }
  }
  canvas.restore();
  canvas.drawRect(
    rect.deflate(0.75 * w),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * w
      ..color = colors.statusWarning,
  );
}

/// A worded list of a cycle's parts, for screen readers and the visible text
/// under the close-up bars.
String lpCycleWords(LpCycle c) {
  final List<String> parts = <String>[];
  for (final LpSegment s in c.segments) {
    final String d = lpUs(s.us);
    switch (s.kind) {
      case LpSegmentKind.difs:
      case LpSegmentKind.backoff:
        parts.add(
          s.addedTenths > 0
              ? '${s.label} $d (${lpUs(s.addedTenths / 10)} added)'
              : '${s.label} $d',
        );
      case LpSegmentKind.protection:
        final ProtectionTiming p = c.protection!;
        parts.add(
          p.rtsTenths > 0
              ? 'RTS ${lpUs(p.rtsUs)} + SIFS + CTS ${lpUs(p.ctsUs)} + SIFS'
              : 'CTS ${lpUs(p.ctsUs)} + SIFS',
        );
      case LpSegmentKind.preamble:
      case LpSegmentKind.data:
      case LpSegmentKind.sifs:
      case LpSegmentKind.ack:
        parts.add('${s.label} $d');
    }
  }
  return parts.join(', ');
}

// ── The channel over a few milliseconds ─────────────────────────────────────

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.controller, required this.fill});

  final LegacyProtectionController controller;

  /// Fill a bounded box (presenter) instead of sizing to content.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final LpResult r = controller.result;
    final bool masked = controller.masked;
    final int window = r.windowUs;
    final TextStyle laneLabel =
        text.labelMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    int framesIn(LpCycle c) => (window / c.cycleUs).floor();

    Widget lane({
      required String label,
      required LpCycle cycle,
      required bool hide,
    }) {
      final String words = hide
          ? '$label: hidden until Reveal'
          : '$label: ${framesIn(cycle)} data frames finish in '
                '${window ~/ 1000} ms, one every ${lpUs(cycle.cycleUs)}';
      final Widget paint = Semantics(
        label: words,
        excludeSemantics: true,
        child: CustomPaint(
          painter: LpLanePainter(
            pieces: hide ? const <LpPiece>[] : lpPieces(cycle),
            cycleTenths: cycle.totalTenths,
            windowUs: window,
            colors: colors,
            scale: scale,
            playhead: controller.playhead,
          ),
          child: const SizedBox.expand(),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(label, style: laneLabel),
          const SizedBox(height: AppSpacing.xxs),
          if (fill)
            Expanded(child: paint)
          else
            SizedBox(height: AppSpacing.xl, child: paint),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            hide
                ? 'Data frames finished: ?'
                : 'Data frames finished: ${framesIn(cycle)}, one every '
                      '${lpUs(cycle.cycleUs)}',
            style: note,
          ),
        ],
      );
    }

    final Widget axis = SizedBox(
      height: AppSpacing.md * scale.text,
      child: CustomPaint(
        painter: LpAxisPainter(
          windowUs: window,
          colors: colors,
          scale: scale,
          labelStyle: note,
        ),
        child: const SizedBox.expand(),
      ),
    );

    final Widget modern = lane(
      label: 'Modern devices only: short slot (9 µs), no protection',
      cycle: r.baseline,
      hide: false,
    );
    final Widget mine = lane(
      label: r.protecting || r.longSlot
          ? 'This network: ${_whatChanged(r)}'
          : 'This network: nothing old associated or heard, same as above',
      cycle: r.cycle,
      hide: masked,
    );

    final List<Widget> children = <Widget>[
      const AirtimeSectionTitle('The channel, one laptop sending'),
      Text(
        fill
            ? 'Before each OFDM (orthogonal frequency-division multiplexing) '
                  'frame: a CTS (Clear to Send) to itself, or an RTS (Request '
                  'to Send) and CTS pair, at a rate 802.11b can decode.'
            : 'An 802.11b device cannot decode OFDM (orthogonal '
                  'frequency-division multiplexing), which 802.11g and later '
                  'use. So before each OFDM frame the sender first sends a '
                  'slow protection frame the old device can decode: a CTS '
                  '(Clear to Send) addressed to itself, or an RTS (Request to '
                  'Send) and CTS pair. Play sweeps ${window ~/ 1000} ms about '
                  'two thousand times slower than real time.',
        style: note,
      ),
      const SizedBox(height: AppSpacing.xs),
      axis,
      const SizedBox(height: AppSpacing.xxs),
      if (fill) Expanded(child: modern) else modern,
      const SizedBox(height: AppSpacing.xs),
      if (fill) Expanded(child: mine) else mine,
    ];

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: children,
      ),
    );
  }
}

String _whatChanged(LpResult r) {
  final List<String> parts = <String>[
    if (r.protecting) r.config.protection.label,
    if (r.longSlot) 'long slot (20 µs)',
    if (r.cwAddedTenths > 0) 'CWmin (minimum contention window) 31',
  ];
  return parts.join(', ');
}

/// The time axis over the lanes: 0 to the window, a tick every 500 us.
class LpAxisPainter extends CustomPainter {
  LpAxisPainter({
    required this.windowUs,
    required this.colors,
    required this.scale,
    required this.labelStyle,
  });

  final int windowUs;
  final AppColorScheme colors;
  final PresenterScale scale;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final TextStyle style = labelStyle.copyWith(
      fontSize: scale.paintFont(labelStyle.fontSize ?? 12),
    );
    final double base = size.height - 1;
    final Paint line = Paint()
      ..color = colors.border
      ..strokeWidth = scale.strokeWidth(1);
    canvas.drawLine(Offset(0, base), Offset(size.width, base), line);
    final int tick = windowUs <= 4000 ? 500 : 1000;
    for (int us = 0; us <= windowUs; us += tick) {
      final double x = us / windowUs * size.width;
      final bool major = us % 1000 == 0;
      canvas.drawLine(
        Offset(x, base - (major ? AppSpacing.xs : AppSpacing.xxs)),
        Offset(x, base),
        Paint()
          ..color = colors.borderStrong
          ..strokeWidth = scale.strokeWidth(1),
      );
      if (!major) continue;
      final String label = us == 0 ? '0' : '${us ~/ 1000} ms';
      final TextPainter tp = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      double lx = x - tp.width / 2;
      lx = lx.clamp(0, math.max(0, size.width - tp.width));
      tp.paint(canvas, Offset(lx, 0));
    }
  }

  @override
  bool shouldRepaint(LpAxisPainter old) =>
      old.windowUs != windowUs ||
      old.colors != colors ||
      old.scale != scale ||
      old.labelStyle != labelStyle;
}

/// One lane: send cycles back to back from 0 across the window, drawn up to
/// the playhead, and the playhead itself while a sweep is under way.
class LpLanePainter extends CustomPainter {
  LpLanePainter({
    required this.pieces,
    required this.cycleTenths,
    required this.windowUs,
    required this.colors,
    required this.scale,
    required this.playhead,
  }) : super(repaint: playhead);

  final List<LpPiece> pieces;
  final int cycleTenths;
  final int windowUs;
  final AppColorScheme colors;
  final PresenterScale scale;
  final ValueListenable<double> playhead;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect lane = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(lane, const Radius.circular(AppRadius.control)),
      Paint()..color = colors.inputFill,
    );
    final double head = playhead.value.clamp(0.0, 1.0);
    final double headX = head * size.width;
    final double pxPerTenth = size.width / (windowUs * 10);
    final double top = size.height * 0.15;
    final double bottom = size.height * 0.85;
    if (pieces.isNotEmpty && cycleTenths > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, headX, size.height));
      double x = 0;
      while (x < size.width) {
        for (final LpPiece p in pieces) {
          final double w = p.tenths * pxPerTenth;
          if (w > 0 && x < size.width) {
            paintLpPiece(
              canvas,
              Rect.fromLTRB(x, top, x + w, bottom),
              p.style,
              colors,
              stroke: w < 3 ? 0.5 : scale.stroke,
            );
          }
          x += w;
        }
      }
      canvas.restore();
    }
    if (head < 1) {
      canvas.drawLine(
        Offset(headX, 0),
        Offset(headX, size.height),
        Paint()
          ..color = colors.textPrimary
          ..strokeWidth = scale.strokeWidth(2),
      );
    }
  }

  @override
  bool shouldRepaint(LpLanePainter old) =>
      !listEquals(old.pieces, pieces) ||
      old.cycleTenths != cycleTenths ||
      old.windowUs != windowUs ||
      old.colors != colors ||
      old.scale != scale ||
      old.playhead != playhead;
}

// ── One cycle, to scale ─────────────────────────────────────────────────────

class _CycleCard extends StatelessWidget {
  const _CycleCard({required this.controller});

  final LegacyProtectionController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final bool presenting = PresenterMode.isActive(context);
    final LpResult r = controller.result;
    final bool masked = controller.masked;
    final int scaleTenths = math.max(
      r.baseline.totalTenths,
      masked ? 0 : r.cycle.totalTenths,
    );
    final TextStyle rowLabel =
        text.labelMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    Widget bar(LpCycle c, String title, {required bool hide}) {
      final String words = hide
          ? '$title: hidden until Reveal'
          : '$title, ${lpUs(c.cycleUs)}: ${lpCycleWords(c)}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            hide ? '$title: ?' : '$title: ${lpUs(c.cycleUs)}',
            style: rowLabel,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            label: words,
            excludeSemantics: true,
            child: SizedBox(
              height: AppSpacing.lg * scale.text,
              child: CustomPaint(
                painter: LpCyclePainter(
                  pieces: hide ? const <LpPiece>[] : lpPieces(c),
                  scaleTenths: scaleTenths,
                  colors: colors,
                  scale: scale,
                  labelStyle: text.labelSmall ?? const TextStyle(fontSize: 11),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          if (!presenting && !hide) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            ExcludeSemantics(child: Text(lpCycleWords(c), style: note)),
          ],
        ],
      );
    }

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AirtimeSectionTitle('One send cycle, drawn to scale'),
          const SizedBox(height: AppSpacing.xs),
          if (presenting)
            const Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                _PieceKey(
                  LpPieceStyle.wait,
                  'Wait: DIFS (distributed interframe space), backoff',
                ),
                _PieceKey(
                  LpPieceStyle.addedWait,
                  'Cost 1: added wait (long slot; CWmin, minimum contention '
                  'window, 31)',
                ),
                _PieceKey(LpPieceStyle.protection, 'Cost 2: protection frame'),
                _PieceKey(LpPieceStyle.preamble, 'Preamble'),
                _PieceKey(LpPieceStyle.data, 'Data'),
                _PieceKey(LpPieceStyle.gap, 'SIFS (short interframe space)'),
                _PieceKey(LpPieceStyle.control, 'ACK (acknowledgment)'),
              ],
            )
          else
            const Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                _PieceKey(
                  LpPieceStyle.wait,
                  'Waiting: DIFS (distributed interframe space), then backoff',
                ),
                _PieceKey(
                  LpPieceStyle.addedWait,
                  'Cost 1, added wait: the long slot, and a CWmin (minimum '
                  'contention window) of 31 when chosen',
                ),
                _PieceKey(
                  LpPieceStyle.protection,
                  'Cost 2, protection frame: CTS (Clear to Send) or RTS '
                  '(Request to Send)',
                ),
                _PieceKey(LpPieceStyle.preamble, 'Preamble'),
                _PieceKey(LpPieceStyle.data, 'Data'),
                _PieceKey(LpPieceStyle.gap, 'SIFS (short interframe space)'),
                _PieceKey(LpPieceStyle.control, 'ACK (acknowledgment)'),
              ],
            ),
          const SizedBox(height: AppSpacing.xs),
          bar(r.baseline, 'Modern devices only', hide: false),
          const SizedBox(height: AppSpacing.xs),
          bar(r.cycle, 'This network', hide: masked),
        ],
      ),
    );
  }
}

class _PieceKey extends StatelessWidget {
  const _PieceKey(this.style, this.label);

  final LpPieceStyle style;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: SizedBox(
            width: AppSpacing.md,
            height: AppSpacing.sm,
            child: CustomPaint(
              painter: _PieceSwatchPainter(style: style, colors: colors),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            label,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _PieceSwatchPainter extends CustomPainter {
  _PieceSwatchPainter({required this.style, required this.colors});

  final LpPieceStyle style;
  final AppColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) =>
      paintLpPiece(canvas, Offset.zero & size, style, colors);

  @override
  bool shouldRepaint(_PieceSwatchPainter old) =>
      old.style != style || old.colors != colors;
}

/// One cycle's bar, to a microsecond scale shared with the other bar, with a
/// short tag inside each part wide enough to hold it.
class LpCyclePainter extends CustomPainter {
  LpCyclePainter({
    required this.pieces,
    required this.scaleTenths,
    required this.colors,
    required this.scale,
    required this.labelStyle,
  });

  final List<LpPiece> pieces;
  final int scaleTenths;
  final AppColorScheme colors;
  final PresenterScale scale;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (scaleTenths <= 0) return;
    final double pxPerTenth = size.width / scaleTenths;
    double x = 0;
    for (final LpPiece p in pieces) {
      final double w = p.tenths * pxPerTenth;
      if (w > 0) {
        final Rect rect = Rect.fromLTWH(x, 0, w, size.height);
        paintLpPiece(
          canvas,
          rect,
          p.style,
          colors,
          stroke: w < 3 ? 0.5 : scale.stroke,
        );
        if (p.tag.isNotEmpty) _tag(canvas, rect, p);
      }
      x += w;
    }
  }

  void _tag(Canvas canvas, Rect rect, LpPiece p) {
    final Color ink = p.style == LpPieceStyle.data
        ? colors.onPrimary
        : colors.textPrimary;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: p.tag,
        style: labelStyle.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
          fontSize: scale.paintFont(labelStyle.fontSize ?? 11),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (tp.width + 2 * AppSpacing.xxs > rect.width) return;
    // A plate behind the tag so it reads over the hatching and bars.
    final Rect plate = Rect.fromCenter(
      center: rect.center,
      width: tp.width + AppSpacing.xxs,
      height: tp.height,
    );
    if (p.style != LpPieceStyle.data) {
      canvas.drawRect(plate, Paint()..color = colors.surface1);
    }
    tp.paint(canvas, plate.topLeft + const Offset(AppSpacing.xxs / 2, 0));
  }

  @override
  bool shouldRepaint(LpCyclePainter old) =>
      !listEquals(old.pieces, pieces) ||
      old.scaleTenths != scaleTenths ||
      old.colors != colors ||
      old.scale != scale ||
      old.labelStyle != labelStyle;
}

// ── Beacon inspector ────────────────────────────────────────────────────────

class _BeaconInspector extends StatelessWidget {
  const _BeaconInspector({required this.controller});

  final LegacyProtectionController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool presenting = PresenterMode.isActive(context);
    final LpResult r = controller.result;
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    final List<Widget> bits = <Widget>[
      _BitRow(
        name: 'NonERP_Present',
        on: r.erp.nonErpPresent,
        why: r.erp.nonErpPresent
            ? 'an 802.11b station is associated'
            : 'no 802.11b station is associated',
      ),
      _BitRow(
        name: 'Use_Protection',
        on: r.erp.useProtection,
        why: r.erp.useProtection
            ? (r.config.associated
                  ? 'an 802.11b station is associated'
                  : 'an 802.11b network is heard')
            : 'nothing old is associated or heard',
      ),
      _BitRow(
        name: 'Barker_Preamble_Mode',
        on: r.erp.barkerPreambleMode,
        why: r.erp.barkerPreambleMode
            ? 'the associated old device cannot use short preamble'
            : 'no associated device needs the long preamble',
      ),
    ];

    final Widget ht = _HtRow(ht: r.ht);

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AirtimeSectionTitle('Beacon inspector'),
          Text(
            presenting
                ? 'ERP (Extended Rate PHY, the 802.11g physical layer) '
                      'element'
                : 'ERP (Extended Rate PHY, the 802.11g physical layer) '
                      'Information element, ID 42',
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          ...bits,
          const SizedBox(height: AppSpacing.xs),
          Text(
            presenting
                ? 'HT (High Throughput, 802.11n) Protection'
                : 'HT (High Throughput, 802.11n) Operation element: HT '
                      'Protection',
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          ht,
          if (!presenting) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Readout only, not animated: which 802.11n frames need a '
              'protection frame in mode 3 is not verified. Including this '
              'readout is a provisional default, not yet confirmed.',
              style: note,
            ),
          ],
        ],
      ),
    );
  }
}

class _BitRow extends StatelessWidget {
  const _BitRow({required this.name, required this.on, required this.why});

  final String name;
  final bool on;
  final String why;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool presenting = PresenterMode.isActive(context);
    return Semantics(
      label: '$name is ${on ? 1 : 0}: $why',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
        child: Row(
          mainAxisSize: presenting ? MainAxisSize.min : MainAxisSize.max,
          children: <Widget>[
            _BitChip(on: on, label: on ? '1' : '0'),
            const SizedBox(width: AppSpacing.xs),
            Text(
              name,
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
            if (!presenting) ...<Widget>[
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  why,
                  style: text.bodySmall?.copyWith(color: colors.textTertiary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BitChip extends StatelessWidget {
  const _BitChip({required this.on, required this.label});

  final bool on;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Container(
      constraints: const BoxConstraints(minWidth: AppSpacing.lg),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: on ? colors.primary : colors.surface2,
        border: Border.all(color: on ? colors.primary : colors.borderStrong),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: mono.inlineCode.copyWith(
          color: on ? colors.onPrimary : colors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HtRow extends StatelessWidget {
  const _HtRow({required this.ht});

  final HtProtection ht;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      label: 'HT Protection is ${ht.value}, ${ht.name}: ${ht.meaning}',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          _BitChip(on: ht.value != 0, label: '${ht.value}'),
          const SizedBox(width: AppSpacing.xs),
          Text(
            ht.name,
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              ht.meaning,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
