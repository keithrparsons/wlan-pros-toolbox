// Four ways to find a 6 GHz AP, timed (spec 40): the race view of
// Association, Frame by Frame (join-ladder).
//
// In Join at 6 GHz, "Compare all four" swaps the ladder for four channel
// strips stacked on one shared time axis: listen on all 59 channels, probe
// the 15 PSCs, go straight to the channel an RNR named, and listen 20 TU on
// each PSC for FILS Discovery. Each strip uses the Join strip's vocabulary
// (eap_ladder_jr_stage.dart): a block per channel's dwell, to scale; probed
// channels filled in the air-leg hue; the AP's channel outlined in lime;
// the AP's frames as ticks under the strip, FILS Discovery short and
// beacons tall, heard filled and missed hollow. RNR's 5 GHz scan is a muted
// block. A lime line marks when each lane first hears the AP, and the
// fastest lane is named in words, never by color alone.
//
// CLEAN-ROOM BUILD per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/
// specs/40-six-ghz-race.md. The model is sixGhzRace in
// lib/services/wifi_lab/join_roam.dart.
//
// States (SOP-007 §5):
//   - fresh     -> strips faint, no times, "Ready" caption
//   - running   -> a cursor sweeps the axis; lanes show "found at" as it
//                  passes; the rest of the axis is veiled
//   - paused    -> as running, cursor held
//   - ended     -> all four found, the first named
//   - not found -> a lane that never hears the AP reads "not found on this
//                  pass" (unreachable at the allowed dwells while the AP
//                  sends FILS every 20 TU; drawn anyway)
//   - disabled  -> outside 6 GHz the race is off and the toggle says why
//                  (eap_ladder_jr_controls.dart)
//   - loading / error -> not reachable: the model is synchronous and pure
//   - reduced motion -> Play shows the whole race at once
//
// Theme tokens only (context.colors, AppSpacing, AppRadius, AppTextSize).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/eap_ladder.dart';
import '../../../services/wifi_lab/join_roam.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter.dart';
import 'eap_ladder_controller.dart';
import 'eap_ladder_palette.dart';
import 'eap_ladder_parts.dart';

/// Height of one lane's channel strip and of the frame row under it.
const double _kStrip = 24;
const double _kTickRow = 12;

/// Height of the time axis under the lanes.
const double _kAxis = 22;

/// "found at 51.2 ms".
String raceFoundText(double ms) => 'found at ${formatJrMs(ms)}';

/// What one lane shows at the cursor.
String raceLaneStatus(EapLadderController c, SixGhzRaceLane l) {
  final double? t = l.foundAtMs;
  if (t == null) return 'not found on this pass';
  if (c.raceFound(l)) return raceFoundText(t);
  return c.raceMs <= 0 && !c.playing ? 'ready' : 'looking';
}

/// The caption under the race: what the cursor has shown so far.
String raceCaption(EapLadderController c) {
  final SixGhzRace r = c.race;
  final SixGhzRaceLane rnr = r.lane(SixGhzMethod.rnr);
  if (c.raceMs <= 0 && !c.playing) {
    return 'Ready. Press Play to race the four methods on one clock, or Step '
        'to jump to each finding.';
  }
  final List<String> found = <String>[
    for (final SixGhzRaceLane l in r.lanes)
      if (c.raceFound(l)) l.method.shortLabel,
  ];
  if (!c.atEnd) {
    return 'At ${formatJrMs(c.raceMs)}: '
        '${found.isEmpty ? 'nothing heard yet' : 'found by ${found.join(', ')}'}.';
  }
  final SixGhzRaceLane? w = r.winner;
  final StringBuffer b = StringBuffer();
  if (w != null) {
    b.write(
      '${w.method.shortLabel} found the AP first, at '
      '${formatJrMs(w.foundAtMs!)}. ',
    );
  } else {
    b.write('No method heard the AP on this pass. ');
  }
  final double alone = rnr.plan.firstHeard?.atMs ?? 0;
  if (r.rnrCountsPriorScan) {
    b.write(
      'RNR on its own needs ${formatJrMs(alone)}, but the client first had '
      'to hear the RNR in a 5 GHz scan (${formatJrMs(rnr.offsetMs)}). Leave '
      'that scan out and RNR wins. ',
    );
  } else {
    b.write(
      'RNR goes straight to channel ${r.targetChannel}: '
      '${formatJrMs(alone)}. The 2.4 or 5 GHz scan that heard the RNR is '
      'left out. ',
    );
  }
  final double? psc = r.lane(SixGhzMethod.pscProbe).foundAtMs;
  final double? fils = r.lane(SixGhzMethod.filsListen).foundAtMs;
  if (psc != null && fils != null) {
    b.write(
      psc < fils
          ? 'With this short active dwell, probing the PSCs beats listening '
                'for FILS.'
          : 'Listening 20 TU on each PSC beats probing them, because each '
                'probe waits for the channel to be idle '
                '${formatJrMs(kMinPscProbeDelayMs)} first.',
    );
  }
  return b.toString().trim();
}

// ── The race card ───────────────────────────────────────────────────────────

class SixGhzRaceCard extends StatelessWidget {
  const SixGhzRaceCard({
    super.key,
    required this.controller,
    this.fill = false,
  });

  final EapLadderController controller;

  /// Presenter: fill the stage height, lanes share it.
  final bool fill;

  /// The race card (tests find it by this key).
  static const Key raceKey = ValueKey<String>('jr-six-ghz-race');

  /// Lane [m]'s row.
  static Key laneKey(SixGhzMethod m) =>
      ValueKey<String>('jr-race-lane-${m.name}');

  @override
  Widget build(BuildContext context) {
    // Play reads this when pressed; it never notifies.
    controller.raceReduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final EapLadderController c = controller;
    final SixGhzRace r = c.race;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? small = text.bodySmall?.copyWith(
      color: colors.textSecondary,
    );
    final List<Widget> lanes = <Widget>[
      for (int i = 0; i < r.lanes.length; i++)
        _RaceLane(controller: c, lane: r.lanes[i], fill: fill),
    ];
    final Widget caption = Semantics(
      liveRegion: true,
      container: true,
      child: Text(
        raceCaption(c),
        style: text.bodyMedium?.copyWith(color: colors.textPrimary),
      ),
    );
    return ElCard(
      child: Column(
        key: raceKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          const ElSectionLabel('Four ways to find a 6 GHz AP, on one clock'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'One AP on channel ${r.targetChannel}, a PSC, sending FILS '
            'Discovery every 20 TU. Each strip is one method\'s scan, channel '
            'by channel, to scale; the lime line is when it first hears the '
            'AP.',
            style: small,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (fill)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final Widget l in lanes) Expanded(child: l),
                ],
              ),
            )
          else
            ...lanes,
          _RaceAxis(axisMs: r.axisMs),
          const SizedBox(height: AppSpacing.xs),
          caption,
          if (!fill) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const _RaceLegend(),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Assumes an AP that sends a FILS Discovery frame every 20 TU, '
              'which IEEE 802.11-2024 requires of a 6 GHz-only AP that wants '
              'to be found; an AP with a 2.4 or 5 GHz radio may not. A PSC '
              'probe waits for the channel to be idle '
              '${formatJrMs(kMinPscProbeDelayMs)} (dot11MinPSCProbeDelay). '
              'Each frame\'s wait is the average, half its interval. The '
              'client finishes its 5 GHz scan before it tunes to the channel '
              'RNR named. Dwell times are inputs: Linux mac80211 as one real '
              'example.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _RaceLane extends StatelessWidget {
  const _RaceLane({
    required this.controller,
    required this.lane,
    required this.fill,
  });

  final EapLadderController controller;
  final SixGhzRaceLane lane;
  final bool fill;

  String _scanWords() {
    final JrScanPlan p = lane.plan;
    final String six = switch (lane.method) {
      SixGhzMethod.passiveAll =>
        '${p.channels.length} channels listened to for '
            '${formatJrMs(p.channels.first.dwellMs)} each',
      SixGhzMethod.pscProbe =>
        '${p.probedCount} PSCs probed for '
            '${formatJrMs(p.channels.first.dwellMs)} each',
      SixGhzMethod.rnr =>
        'one channel (${p.targetChannel}), probed for '
            '${formatJrMs(p.target.dwellMs)}',
      SixGhzMethod.filsListen =>
        '${p.channels.length} PSCs listened to for '
            '${formatJrMs(p.channels.first.dwellMs)} each',
    };
    final JrScanPlan? prior = lane.prior;
    return prior == null
        ? six
        : 'a 5 GHz scan of ${prior.channels.length} channels '
              '(${formatJrMs(prior.totalMs)}), then $six';
  }

  @override
  Widget build(BuildContext context) {
    final EapLadderController c = controller;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final SixGhzRace r = c.race;
    final bool isWinner =
        c.atEnd && r.winner?.method == lane.method && lane.found;
    final String status = raceLaneStatus(c, lane);
    final bool shownFound = c.raceFound(lane);
    final TextStyle mono =
        (Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults())
            .inlineCode
            .copyWith(
              color: shownFound ? colors.textAccent : colors.textTertiary,
              fontWeight: shownFound ? FontWeight.w700 : FontWeight.w400,
            );
    final Widget strip = CustomPaint(
      painter: _RaceStripPainter(
        lane: lane,
        axisMs: r.axisMs,
        cursorMs: c.raceMs,
        fresh: c.raceMs <= 0 && !c.playing,
        found: shownFound,
        probedFill: ladderLegColor(LadderLeg.air, isLight: colors.isLight),
        priorFill: colors.surface3,
        outline: colors.borderStrong,
        faint: colors.border,
        target: colors.primary,
        heard: colors.textAccent,
        missed: colors.textTertiary,
        veil: colors.surface1,
        labelColor: colors.textSecondary,
        labelSize: AppTextSize.caption * sc.text,
        labelFont: text.labelSmall ?? const TextStyle(),
        stroke: sc.strokeWidth(1),
        tickRow: _kTickRow * sc.text,
      ),
    );
    return Semantics(
      container: true,
      label:
          '${lane.method.shortLabel}: $status'
          '${isWinner ? ', first' : ''}. ${lane.method.label}. Scan: '
          '${_scanWords()}.',
      excludeSemantics: true,
      child: Padding(
        key: SixGhzRaceCard.laneKey(lane.method),
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    lane.method.shortLabel,
                    style: text.labelLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isWinner) ...<Widget>[
                  Icon(
                    Icons.flag_rounded,
                    size: sc.markerSize(16),
                    color: colors.textAccent,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'first',
                    style: text.labelMedium?.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(status, style: mono),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            if (fill)
              Expanded(child: strip)
            else
              SizedBox(height: (_kStrip + _kTickRow) * sc.text, child: strip),
            if (!fill)
              Text(
                _scanWords(),
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}

class _RaceStripPainter extends CustomPainter {
  _RaceStripPainter({
    required this.lane,
    required this.axisMs,
    required this.cursorMs,
    required this.fresh,
    required this.found,
    required this.probedFill,
    required this.priorFill,
    required this.outline,
    required this.faint,
    required this.target,
    required this.heard,
    required this.missed,
    required this.veil,
    required this.labelColor,
    required this.labelSize,
    required this.labelFont,
    required this.stroke,
    required this.tickRow,
  });

  final SixGhzRaceLane lane;
  final double axisMs;
  final double cursorMs;
  final bool fresh;
  final bool found;
  final Color probedFill;
  final Color priorFill;
  final Color outline;
  final Color faint;
  final Color target;
  final Color heard;
  final Color missed;
  final Color veil;
  final Color labelColor;
  final double labelSize;

  /// The theme's label style, so painted labels use the app's font.
  final TextStyle labelFont;
  final double stroke;
  final double tickRow;

  @override
  void paint(Canvas canvas, Size size) {
    if (axisMs <= 0 || size.width <= 0) return;
    final double w = size.width;
    final double stripH = math.max(8, size.height - tickRow);
    double x(double ms) => (ms / axisMs * w).clamp(0, w);
    final double alpha = fresh ? 0.45 : 1;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // RNR's 5 GHz scan: one muted block, divided per channel.
    final JrScanPlan? prior = lane.prior;
    if (prior != null) {
      final Rect r = Rect.fromLTRB(0, 0, x(prior.totalMs), stripH).deflate(0.5);
      canvas.drawRect(r, Paint()..color = priorFill.withValues(alpha: alpha));
      final Paint div = Paint()
        ..color = faint.withValues(alpha: alpha)
        ..strokeWidth = stroke;
      for (final JrScanChannel ch in prior.channels.skip(1)) {
        final double cx = x(ch.startMs);
        canvas.drawLine(Offset(cx, 0), Offset(cx, stripH), div);
      }
      canvas.drawRect(
        r,
        Paint()
          ..color = outline.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      _label(canvas, '5 GHz scan', r, alpha);
    }

    // The 6 GHz channels.
    final double off = lane.offsetMs;
    for (final JrScanChannel ch in lane.plan.channels) {
      final double a = off + ch.startMs;
      if (a >= axisMs) break;
      final Rect r = Rect.fromLTRB(
        x(a),
        0,
        x(off + ch.endMs),
        stripH,
      ).deflate(0.5);
      if (ch.probed) {
        canvas.drawRect(
          r,
          Paint()..color = probedFill.withValues(alpha: 0.35 * alpha),
        );
      }
      canvas.drawRect(
        r,
        Paint()
          ..color = (fresh ? faint : outline)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      if (ch.target) {
        canvas.drawRect(
          r.inflate(1),
          Paint()
            ..color = target.withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * 2.5,
        );
        _label(canvas, '${ch.number}', r, alpha);
      }
    }

    // The AP's frames under the strip.
    final double y0 = stripH + 2;
    final double y1 = size.height - 1;
    for (final JrScanEvent e in lane.plan.events) {
      if (e.kind == JrScanEventKind.probeRequest) continue;
      final double at = off + e.atMs;
      if (at > axisMs) continue;
      final double ex = x(at).clamp(1, w - 1);
      final double top = switch (e.kind) {
        JrScanEventKind.fils => y0 + (y1 - y0) * 0.45,
        JrScanEventKind.probeResponse => y0 + (y1 - y0) * 0.2,
        _ => y0,
      };
      final Path tick = Path()
        ..moveTo(ex, top)
        ..lineTo(ex - 3, y1)
        ..lineTo(ex + 3, y1)
        ..close();
      canvas.drawPath(
        tick,
        Paint()
          ..color = (e.heard ? heard : missed).withValues(alpha: alpha)
          ..style = e.heard ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    }

    // Veil what the cursor has not reached, then the cursor itself.
    if (!fresh && cursorMs < axisMs) {
      final double cx = x(cursorMs);
      canvas.drawRect(
        Rect.fromLTRB(cx, 0, w, size.height),
        Paint()..color = veil.withValues(alpha: 0.6),
      );
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, size.height),
        Paint()
          ..color = target
          ..strokeWidth = stroke * 1.5,
      );
    }

    // When it first heard the AP.
    final double? f = lane.foundAtMs;
    if (found && f != null) {
      final double fx = x(f).clamp(stroke * 2, w - stroke * 2);
      final Paint p = Paint()
        ..color = heard
        ..strokeWidth = stroke * 3;
      canvas.drawLine(Offset(fx, 0), Offset(fx, size.height), p);
      canvas.drawCircle(Offset(fx, 0), stroke * 4, Paint()..color = heard);
    }
    canvas.restore();
  }

  void _label(Canvas canvas, String s, Rect r, double alpha) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s,
        style: labelFont.copyWith(
          color: labelColor.withValues(alpha: alpha),
          fontSize: labelSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (tp.width + 4 > r.width || tp.height > r.height) return;
    tp.paint(
      canvas,
      Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_RaceStripPainter old) =>
      old.lane != lane ||
      old.axisMs != axisMs ||
      old.cursorMs != cursorMs ||
      old.fresh != fresh ||
      old.found != found ||
      old.probedFill != probedFill ||
      old.outline != outline ||
      old.labelSize != labelSize ||
      old.stroke != stroke ||
      old.tickRow != tickRow;
}

// ── Time axis and legend ────────────────────────────────────────────────────

/// A tick step of 1, 2 or 5 x 10^n giving about five ticks over [span].
double raceTickStep(double span) {
  if (span <= 0) return 1;
  final double raw = span / 5;
  final double mag = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  for (final double m in <double>[1, 2, 5, 10]) {
    if (raw <= m * mag) return m * mag;
  }
  return 10 * mag;
}

class _RaceAxis extends StatelessWidget {
  const _RaceAxis({required this.axisMs});

  final double axisMs;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    return Semantics(
      label: 'Time axis, 0 to ${formatJrMs(axisMs)}, shared by all four strips',
      excludeSemantics: true,
      child: SizedBox(
        height: _kAxis * sc.text,
        child: CustomPaint(
          painter: _AxisPainter(
            axisMs: axisMs,
            line: colors.borderStrong,
            labelColor: colors.textSecondary,
            labelSize: AppTextSize.caption * sc.text,
            labelFont:
                Theme.of(context).textTheme.labelSmall ?? const TextStyle(),
            stroke: sc.strokeWidth(1),
          ),
        ),
      ),
    );
  }
}

class _AxisPainter extends CustomPainter {
  _AxisPainter({
    required this.axisMs,
    required this.line,
    required this.labelColor,
    required this.labelSize,
    required this.labelFont,
    required this.stroke,
  });

  final double axisMs;
  final Color line;
  final Color labelColor;
  final double labelSize;
  final TextStyle labelFont;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (axisMs <= 0) return;
    final Paint p = Paint()
      ..color = line
      ..strokeWidth = stroke;
    canvas.drawLine(Offset.zero, Offset(size.width, 0), p);
    final double step = raceTickStep(axisMs);
    for (double t = 0; t <= axisMs + 1e-9; t += step) {
      final double x = t / axisMs * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, 4), p);
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: formatJrMs(t),
          style: labelFont.copyWith(color: labelColor, fontSize: labelSize),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final double lx = (x - tp.width / 2).clamp(0, size.width - tp.width);
      tp.paint(canvas, Offset(lx, 5));
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) =>
      old.axisMs != axisMs ||
      old.line != line ||
      old.labelSize != labelSize ||
      old.stroke != stroke;
}

class _RaceLegend extends StatelessWidget {
  const _RaceLegend();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final TextStyle? style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textSecondary);
    // Swatch dimensions match the Join legend's glyphs (GL-003 §4.2).
    Widget swatch(Color fill, {Color? border, double borderW = 1}) => Container(
      width: 16 * sc.text,
      height: 12 * sc.text,
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(
          color: border ?? colors.borderStrong,
          width: borderW,
        ),
      ),
    );
    Widget item(Widget glyph, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(child: glyph),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(child: Text(label, style: style)),
      ],
    );
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        item(
          swatch(
            ladderLegColor(
              LadderLeg.air,
              isLight: colors.isLight,
            ).withValues(alpha: 0.35),
          ),
          'probed channel',
        ),
        item(swatch(Colors.transparent), 'listened to'),
        item(
          swatch(Colors.transparent, border: colors.primary, borderW: 2),
          'the AP\'s channel',
        ),
        item(swatch(colors.surface3), '5 GHz scan (RNR)'),
        item(
          Container(
            width: sc.strokeWidth(3),
            height: 14 * sc.text,
            color: colors.textAccent,
          ),
          'first heard the AP',
        ),
        item(
          const SizedBox.shrink(),
          'Ticks: tall beacon, short FILS Discovery; filled heard, hollow '
          'missed',
        ),
      ],
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

/// The race's numbers, for the Readouts card.
class SixGhzRaceReadouts extends StatelessWidget {
  const SixGhzRaceReadouts({super.key, required this.controller});

  final EapLadderController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final SixGhzRace r = controller.race;
    final SixGhzRaceLane? w = r.winner;
    final TextStyle? note = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textTertiary);
    return ElCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const ElSectionLabel('Readouts: time to first hear the AP'),
          const SizedBox(height: AppSpacing.xxs),
          for (final SixGhzRaceLane l in r.lanes)
            ElRow(
              label: l.method.shortLabel,
              value: l.foundAtMs == null
                  ? 'not found'
                  : formatJrMs(l.foundAtMs!),
              emphasize: w?.method == l.method,
            ),
          if (w != null)
            ElRow(label: 'First to find it', value: w.method.shortLabel),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            r.rnrCountsPriorScan
                ? 'RNR includes the 5 GHz scan that heard the RNR '
                      '(${formatJrMs(r.lane(SixGhzMethod.rnr).offsetMs)}).'
                : 'RNR counts only its 6 GHz part.',
            style: note,
          ),
          Text(
            'Built from the dwell settings. A teaching model with labeled '
            'inputs, not a ranking of real clients.',
            style: note,
          ),
        ],
      ),
    );
  }
}
