// The stage for Conference Wi-Fi Runs Out of Addresses (Wi-Fi Classroom):
// whether the pool ran dry and why, the morning as a chart (addresses taken
// against the pool, devices in the hall, devices left with no address), the
// pool itself address by address at the playhead, and the readouts. Reads a
// [DhcpExhaustionController]; owns no state, so the presenter layout can
// place it beside [DhcpExhaustionControls].
//
// COLOR (GL-003 §8.13, §8.15.2). Lime marks the subject, the addresses
// taken. Each chart line also has its own pattern (solid, dashed, dotted)
// and a worded legend. The one status hue is the no-address area, a danger
// verdict named in words. Pool cells differ by fill AND pattern: free is an
// outline, in use is solid, held-for-a-device-that-left is hatched, held for
// an old private address is cross-hatched; at very small cell sizes the
// patterns are too fine to see, and the counts in the readouts carry it.
//
// MOTION (§8.8). The playhead jumps; nothing tweens.
//
// ACCESSIBILITY. The chart and grid are pictures with worded Semantics
// labels; every number is also printed in the readouts.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'dhcp_exhaustion_controller.dart';

/// The first line on the stage: every acronym the tool uses, spelled out.
const String kDxIntroText =
    'Every device on the Wi-Fi needs an IP (Internet Protocol) address. '
    'The DHCP (Dynamic Host Configuration Protocol) server lends one from '
    'its pool for a lease time, and keys each loan to the device\'s MAC '
    '(media access control) address.';

class DhcpExhaustionStage extends StatelessWidget {
  const DhcpExhaustionStage({super.key, required this.controller});

  final DhcpExhaustionController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final Widget headline = _Headline(controller: controller);
        final Widget chart = _ChartCard(controller: controller);
        final Widget pool = _PoolCard(controller: controller);
        final Widget readouts = _Readouts(controller: controller);
        const SizedBox gap = SizedBox(height: AppSpacing.sm);
        if (!presenting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[headline, gap, chart, gap, pool, gap, readouts],
          );
        }
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: box.maxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    headline,
                    gap,
                    chart,
                    gap,
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(flex: 3, child: pool),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(flex: 2, child: readouts),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Headline ────────────────────────────────────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline({required this.controller});

  final DhcpExhaustionController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final DxMorning m = controller.morning;
    final int? dry = m.firstDryMinute;
    return AirtimeCard(
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              kDxIntroText,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              dry == null
                  ? 'The pool held all morning'
                  : 'The pool ran dry at ${dxClock(dry)}',
              style: text.headlineSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              controller.hidingAnswer
                  ? 'Predict first: what would fix it? Then reveal.'
                  : m.why,
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── The morning chart ───────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.controller});

  final DhcpExhaustionController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final DxMorning m = controller.morning;
    final int? dry = m.firstDryMinute;
    final TextStyle axis = mono.inlineCode.copyWith(
      fontSize: scale.paintFont(AppTextSize.caption),
      color: colors.textSecondary,
    );
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('The morning, 07:00 to 13:00'),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label:
                'Chart of the morning. Pool ${m.poolSize} addresses. Peak '
                '${m.peakBound} addresses taken, peak ${m.peakHere} devices '
                'in the hall. '
                '${dry == null ? 'No device went without an address.' : 'From ${dxClock(dry)}, up to ${m.peakWaiting} devices had no address.'} '
                'Playhead at ${dxClock(controller.minute)}.',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 220 * scale.marker,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _ChartPainter(
                    morning: m,
                    minute: controller.minute,
                    taken: colors.textAccent,
                    here: colors.textPrimary,
                    pool: colors.textSecondary,
                    waiting: colors.statusDanger,
                    grid: colors.border,
                    axis: axis,
                    stroke: scale.strokeWidth(1),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[
              _LineKey(
                color: colors.textAccent,
                pattern: _Dash.solid,
                label: 'addresses taken (in use or held)',
              ),
              _LineKey(
                color: colors.textPrimary,
                pattern: _Dash.dashed,
                label: 'devices in the hall',
              ),
              _LineKey(
                color: colors.textSecondary,
                pattern: _Dash.dotted,
                label: 'the pool',
              ),
              _LineKey(
                color: colors.statusDanger,
                pattern: _Dash.area,
                label: 'devices with no address',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Arrivals: a rush before a 09:00 keynote, then a trickle '
            '(illustrative).',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

enum _Dash { solid, dashed, dotted, area }

void _patternLine(Canvas canvas, List<Offset> pts, Paint p, _Dash dash) {
  if (pts.length < 2) return;
  if (dash == _Dash.solid) {
    canvas.drawPath(
      Path()..addPolygon(pts, false),
      Paint()
        ..color = p.color
        ..strokeWidth = p.strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    return;
  }
  final double on = dash == _Dash.dashed ? 7 : 1.5;
  final double off = dash == _Dash.dashed ? 5 : 4;
  double carry = 0;
  bool drawing = true;
  for (int i = 1; i < pts.length; i++) {
    Offset a = pts[i - 1];
    final Offset b = pts[i];
    double segLeft = (b - a).distance;
    final Offset dir = segLeft == 0 ? Offset.zero : (b - a) / segLeft;
    while (segLeft > 0) {
      final double want = (drawing ? on : off) - carry;
      final double take = math.min(want, segLeft);
      final Offset e = a + dir * take;
      if (drawing) canvas.drawLine(a, e, p);
      a = e;
      segLeft -= take;
      carry += take;
      if (carry >= (drawing ? on : off) - 1e-9) {
        carry = 0;
        drawing = !drawing;
      }
    }
  }
}

class _LineKey extends StatelessWidget {
  const _LineKey({
    required this.color,
    required this.pattern,
    required this.label,
  });

  final Color color;
  final _Dash pattern;
  final String label;

  @override
  Widget build(BuildContext context) {
    final PresenterScale scale = PresenterMode.scaleOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: CustomPaint(
            size: Size(26 * scale.marker, 12 * scale.marker),
            painter: _KeyPainter(
              color: color,
              pattern: pattern,
              stroke: scale.strokeWidth(2.5),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: context.colors.textSecondary),
        ),
      ],
    );
  }
}

class _KeyPainter extends CustomPainter {
  _KeyPainter({
    required this.color,
    required this.pattern,
    required this.stroke,
  });

  final Color color;
  final _Dash pattern;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (pattern == _Dash.area) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = color.withValues(alpha: 0.35),
      );
      canvas.drawLine(
        Offset(0, 0),
        Offset(size.width, 0),
        Paint()
          ..color = color
          ..strokeWidth = stroke,
      );
      return;
    }
    final double y = size.height / 2;
    _patternLine(
      canvas,
      <Offset>[Offset(0, y), Offset(size.width, y)],
      Paint()
        ..color = color
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
      pattern,
    );
  }

  @override
  bool shouldRepaint(_KeyPainter o) =>
      o.color != color || o.pattern != pattern || o.stroke != stroke;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.morning,
    required this.minute,
    required this.taken,
    required this.here,
    required this.pool,
    required this.waiting,
    required this.grid,
    required this.axis,
    required this.stroke,
  });

  final DxMorning morning;
  final int minute;
  final Color taken;
  final Color here;
  final Color pool;
  final Color waiting;
  final Color grid;
  final TextStyle axis;
  final double stroke;

  static double _niceStep(double max) {
    final double raw = max / 4;
    final double mag = math
        .pow(10, (math.log(raw) / math.ln10).floor())
        .toDouble();
    for (final double m in <double>[1, 2, 2.5, 5, 10]) {
      if (raw <= m * mag) return m * mag;
    }
    return 10 * mag;
  }

  TextPainter _tp(String s) => TextPainter(
    text: TextSpan(text: s, style: axis),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final List<DxMinute> ms = morning.minutes;
    final double peak = <num>[
      morning.poolSize,
      morning.peakHere,
      morning.peakBound,
      morning.peakWaiting,
    ].reduce(math.max).toDouble();
    final double step = _niceStep(math.max(peak * 1.1, 4));
    final double yMax = (peak * 1.1 / step).ceil() * step;
    final double left = _tp(yMax.round().toString()).width + 8;
    final double bottom = _tp('07:00').height + 6;
    final Rect plot = Rect.fromLTRB(
      left,
      6,
      size.width - 8,
      size.height - bottom,
    );
    double x(int m) => plot.left + plot.width * m / kDxMinutes;
    double y(num v) => plot.bottom - plot.height * v / yMax;

    final Paint gridPaint = Paint()
      ..color = grid
      ..strokeWidth = stroke;
    for (double v = 0; v <= yMax + 1e-9; v += step) {
      canvas.drawLine(
        Offset(plot.left, y(v)),
        Offset(plot.right, y(v)),
        gridPaint,
      );
      final TextPainter t = _tp(v.round().toString());
      t.paint(canvas, Offset(left - 6 - t.width, y(v) - t.height / 2));
    }
    final double hourW = plot.width / 6;
    final int every = _tp('00:00').width + 16 > hourW ? 2 : 1;
    for (int h = 0; h <= 6; h++) {
      final double xx = x(h * 60);
      canvas.drawLine(Offset(xx, plot.top), Offset(xx, plot.bottom), gridPaint);
      if (h % every != 0) continue;
      final TextPainter t = _tp(dxClock(h * 60));
      final double tx = (xx - t.width / 2).clamp(0.0, size.width - t.width);
      t.paint(canvas, Offset(tx, plot.bottom + 4));
    }

    // Devices with no address: a filled area from zero.
    final Path area = Path()..moveTo(x(0), y(0));
    for (int m = 0; m < ms.length; m++) {
      area.lineTo(x(m), y(ms[m].waiting));
    }
    area
      ..lineTo(x(ms.length - 1), y(0))
      ..close();
    canvas.drawPath(area, Paint()..color = waiting.withValues(alpha: 0.35));
    _patternLine(
      canvas,
      <Offset>[
        for (int m = 0; m < ms.length; m++) Offset(x(m), y(ms[m].waiting)),
      ],
      Paint()
        ..color = waiting
        ..strokeWidth = stroke * 1.5
        ..style = PaintingStyle.stroke,
      _Dash.solid,
    );

    // The pool.
    _patternLine(
      canvas,
      <Offset>[
        Offset(plot.left, y(morning.poolSize)),
        Offset(plot.right, y(morning.poolSize)),
      ],
      Paint()
        ..color = pool
        ..strokeWidth = stroke * 2.5
        ..strokeCap = StrokeCap.round,
      _Dash.dotted,
    );
    final TextPainter poolLabel = _tp('pool ${morning.poolSize}');
    poolLabel.paint(
      canvas,
      Offset(
        plot.right - poolLabel.width - 4,
        y(morning.poolSize) - poolLabel.height - 2,
      ),
    );

    // Devices in the hall.
    _patternLine(
      canvas,
      <Offset>[
        for (int m = 0; m < ms.length; m++) Offset(x(m), y(ms[m].devicesHere)),
      ],
      Paint()
        ..color = here
        ..strokeWidth = stroke * 2
        ..style = PaintingStyle.stroke,
      _Dash.dashed,
    );

    // Addresses taken.
    _patternLine(
      canvas,
      <Offset>[
        for (int m = 0; m < ms.length; m++) Offset(x(m), y(ms[m].bound)),
      ],
      Paint()
        ..color = taken
        ..strokeWidth = stroke * 3
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
      _Dash.solid,
    );

    // Playhead.
    final double px = x(minute);
    canvas.drawLine(
      Offset(px, plot.top),
      Offset(px, plot.bottom),
      Paint()
        ..color = here
        ..strokeWidth = stroke * 1.5,
    );
    final TextPainter t = _tp(dxClock(minute));
    final double tx = (px + 4 + t.width > plot.right)
        ? px - 4 - t.width
        : px + 4;
    t.paint(canvas, Offset(tx, plot.top));
  }

  @override
  bool shouldRepaint(_ChartPainter o) =>
      !identical(o.morning, morning) ||
      o.minute != minute ||
      o.taken != taken ||
      o.here != here ||
      o.pool != pool ||
      o.waiting != waiting ||
      o.grid != grid ||
      o.axis != axis ||
      o.stroke != stroke;
}

// ── The pool, address by address ────────────────────────────────────────────

class _PoolCard extends StatelessWidget {
  const _PoolCard({required this.controller});

  final DhcpExhaustionController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final DxMorning m = controller.morning;
    final DxMinute x = controller.now;
    final List<DxCell> cells = m.cellsAt(controller.minute);
    final int free = m.poolSize - x.bound;
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AirtimeSectionTitle(
            'The pool at ${dxClock(controller.minute)}: '
            '${m.poolSize} addresses',
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label:
                'Pool at ${dxClock(controller.minute)}: ${x.inUse} in use, '
                '${x.heldLeft} held for devices that left, '
                '${x.heldRotated} held for old private addresses, $free free.',
            child: ExcludeSemantics(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  final double w = box.maxWidth;
                  final int n = math.max(1, cells.length);
                  // Square cells, as large as fit in about a 2:1 box.
                  final double side = math
                      .sqrt(w * (w / 2) / n)
                      .clamp(2.0, 22.0 * scale.marker);
                  final int cols = math.max(1, (w / side).floor());
                  final int rows = (n / cols).ceil();
                  return SizedBox(
                    height: rows * side,
                    child: CustomPaint(
                      size: Size(w, rows * side),
                      painter: _PoolPainter(
                        cells: cells,
                        cols: cols,
                        side: side,
                        inUse: colors.textAccent,
                        held: colors.textSecondary,
                        outline: colors.borderStrong,
                        stroke: scale.strokeWidth(1),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[
              _CellKey(kind: DxCell.inUse, label: 'in use, device here'),
              _CellKey(kind: DxCell.heldLeft, label: 'held, device left'),
              if (controller.config.rotation)
                _CellKey(
                  kind: DxCell.heldRotated,
                  label: 'held, old private address',
                ),
              _CellKey(kind: DxCell.free, label: 'free'),
            ],
          ),
        ],
      ),
    );
  }
}

class _CellKey extends StatelessWidget {
  const _CellKey({required this.kind, required this.label});

  final DxCell kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final double s = 14 * PresenterMode.scaleOf(context).marker;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: CustomPaint(
            size: Size(s, s),
            painter: _PoolPainter(
              cells: <DxCell>[kind],
              cols: 1,
              side: s,
              inUse: colors.textAccent,
              held: colors.textSecondary,
              outline: colors.borderStrong,
              stroke: 1,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _PoolPainter extends CustomPainter {
  _PoolPainter({
    required this.cells,
    required this.cols,
    required this.side,
    required this.inUse,
    required this.held,
    required this.outline,
    required this.stroke,
  });

  final List<DxCell> cells;
  final int cols;
  final double side;
  final Color inUse;
  final Color held;
  final Color outline;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double gap = side >= 6 ? 1.5 : 0.5;
    final Paint fill = Paint()..color = inUse;
    final Paint heldFill = Paint()..color = held.withValues(alpha: 0.25);
    final Paint hatch = Paint()
      ..color = held
      ..strokeWidth = math.max(1, stroke);
    final Paint box = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final bool patterns = side >= 7;
    for (int i = 0; i < cells.length; i++) {
      final Rect r = Rect.fromLTWH(
        (i % cols) * side + gap / 2,
        (i ~/ cols) * side + gap / 2,
        side - gap,
        side - gap,
      );
      switch (cells[i]) {
        case DxCell.free:
          if (patterns) canvas.drawRect(r.deflate(stroke / 2), box);
        case DxCell.inUse:
          canvas.drawRect(r, fill);
        case DxCell.heldLeft:
          canvas.drawRect(r, heldFill);
          if (patterns) {
            canvas.save();
            canvas.clipRect(r);
            for (double d = -r.height; d < r.width; d += 4) {
              canvas.drawLine(
                Offset(r.left + d, r.bottom),
                Offset(r.left + d + r.height, r.top),
                hatch,
              );
            }
            canvas.restore();
          }
        case DxCell.heldRotated:
          canvas.drawRect(r, heldFill);
          if (patterns) {
            canvas.save();
            canvas.clipRect(r);
            for (double d = -r.height; d < r.width; d += 5) {
              canvas.drawLine(
                Offset(r.left + d, r.bottom),
                Offset(r.left + d + r.height, r.top),
                hatch,
              );
              canvas.drawLine(
                Offset(r.left + d, r.top),
                Offset(r.left + d + r.height, r.bottom),
                hatch,
              );
            }
            canvas.restore();
          } else {
            canvas.drawRect(r, Paint()..color = held.withValues(alpha: 0.6));
          }
      }
    }
  }

  @override
  bool shouldRepaint(_PoolPainter o) =>
      !identical(o.cells, cells) ||
      o.cols != cols ||
      o.side != side ||
      o.inUse != inUse ||
      o.held != held ||
      o.outline != outline;
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _Readouts extends StatelessWidget {
  const _Readouts({required this.controller});

  final DhcpExhaustionController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final DxMorning m = controller.morning;
    final DxMinute x = controller.now;
    final TextStyle label =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle value = mono.inlineCode.copyWith(color: colors.textPrimary);
    TableRow row(String name, String v, {bool danger = false}) => TableRow(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(name, style: label),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(
            v,
            textAlign: TextAlign.end,
            style: danger
                ? value.copyWith(
                    color: colors.statusDanger,
                    fontWeight: FontWeight.w700,
                  )
                : value,
          ),
        ),
      ],
    );
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AirtimeSectionTitle('At ${dxClock(controller.minute)}'),
          const SizedBox(height: AppSpacing.xs),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(1.6),
              1: FlexColumnWidth(1),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              row('Devices in the hall', '${x.devicesHere}'),
              row('Addresses in use', '${x.inUse}'),
              row('Held for devices that left', '${x.heldLeft}'),
              if (controller.config.rotation)
                row('Held for old private addresses', '${x.heldRotated}'),
              row('Free', '${m.poolSize - x.bound} of ${m.poolSize}'),
              row(
                'Devices with no address',
                x.waiting == 0 ? '0' : '${x.waiting}, no internet',
                danger: x.waiting > 0,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Addresses the morning needed, with no pool limit: '
            '${m.peakDemand} at the peak.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
