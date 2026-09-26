// JoinRoamStage: the pictures half of the Join and Roam modes of the 802.1X
// and EAP Ladder (spec 21b).
//
// The same ladder idea as EapLadderStage (eap_ladder_stage.dart, which hands
// over to this widget in those two modes): lanes labeled at the top, one
// arrow per message with its frame name on it, air arrows solid and wire
// arrows dashed in the two leg hues of eap_ladder_palette.dart, unsent
// messages faint with their text held back, phase headings always visible,
// and milestone bands as they are reached. What is new:
//
//   - N lanes: Join draws Client, AP, RADIUS server (802.1X only) and DHCP
//     server; Roam draws Client, Current AP, Target AP and RADIUS server
//     (full 802.1X only). DHCP, ARP and DNS frames are bridged: one arrow,
//     solid over the air to the AP, dashed on the wire beyond it.
//   - A channel strip above the ladder (Join): every channel the scan visits,
//     its dwell to scale, and the AP's beacons every 102.4 ms, heard or
//     missed.
//   - Marks in the gutter beside each step number: M or D (management or
//     data frame), a closed lock for a data frame encrypted with the session
//     keys, a shield for a management frame protected by PMF.
//   - A phase timeline under the ladder: one bar per phase to scale (Join) or
//     scan, authentication and key handshake (Roam), with a running clock.
//   - Tap a sent message to see what it carries in the caption.
//
// Theme tokens only (context.colors, AppSpacing, AppRadius, AppMotion). Lime
// marks the elapsed time and the milestones; the two leg hues are the
// ladder's own (GL-003 §8.15.2), never the only cue.
//
// States: fresh (Ready caption, faint arrows), running, paused, ended,
// inspecting (a tapped message in the caption, marked as such), not found
// (a passive dwell too short to hear the AP: a warning band on the ladder
// and in the caption, and the ladder stops after the scan).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import '../../../services/wifi_lab/eap_ladder.dart';
import '../../../services/wifi_lab/join_roam.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter.dart';
import 'eap_ladder_controller.dart';
import 'eap_ladder_palette.dart';
import 'eap_ladder_parts.dart';

/// Height of the ladder's own scroll viewport (a dimension, GL-003 §4.2).
const double _kViewportPhone = 440;
const double _kViewportWide = 560;

/// Height of the band under a label where the arrow is drawn (a dimension).
const double _kArrowBand = 16;

/// Height of the channel strip and of the beacon row under it.
const double _kStripHeight = 28;
const double _kBeaconRow = 14;

/// Height of the phase timeline bar.
const double _kTimelineBar = 14;

/// Lane centers as fractions of the ladder width, for [n] lanes.
List<double> jrLaneFractions(int n) {
  if (n <= 1) return <double>[0.5];
  final double margin = n <= 3 ? 0.15 : 0.12;
  final double step = (1 - 2 * margin) / (n - 1);
  return <double>[for (int i = 0; i < n; i++) margin + step * i];
}

class JoinRoamStage extends StatelessWidget {
  const JoinRoamStage({super.key, required this.controller});

  final EapLadderController controller;

  /// The ladder's own vertical scroll view in Join and Roam.
  static const Key ladderScrollKey = ValueKey<String>('jr-ladder-scroll');

  /// The channel strip (Join).
  static const Key stripKey = ValueKey<String>('jr-channel-strip');

  /// The phase timeline.
  static const Key timelineKey = ValueKey<String>('jr-timeline');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        if (PresenterMode.isActive(context)) {
          // Two columns: the ladder takes the full stage height on the
          // left; the timeline and the caption share the right. Vertical
          // space is what a projector lacks.
          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final double side = box.maxWidth * 0.38;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _JrLadderCard(controller: controller, fill: true),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox(
                    width: side,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _TimelineCard(controller: controller),
                        const SizedBox(height: AppSpacing.xs),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: side,
                              child: _JrCaption(
                                controller: controller,
                                presenter: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _JrLadderCard(controller: controller),
            const SizedBox(height: AppSpacing.sm),
            _TimelineCard(controller: controller),
            const SizedBox(height: AppSpacing.sm),
            _JrCaption(controller: controller),
          ],
        );
      },
    );
  }
}

// ── The ladder card ─────────────────────────────────────────────────────────

class _JrLadderCard extends StatelessWidget {
  const _JrLadderCard({required this.controller, this.fill = false});

  final EapLadderController controller;
  final bool fill;

  String _title() {
    final JrSequence s = controller.jr;
    final JrConfig c = s.config;
    final String scan =
        '${c.band.label}, ${c.scanType.label.toLowerCase()} scan'
        '${s.scan.rnr ? ' (via RNR)' : ''}';
    return s.mode == LadderMode.roam
        ? 'Roam: ${c.roamMethod.label}. $scan'
        : 'Join: ${s.security.label}. $scan';
  }

  @override
  Widget build(BuildContext context) {
    final JrSequence s = controller.jr;
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final bool join = s.mode == LadderMode.join;
    Widget ladder(double width, double height) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: height.isFinite ? MainAxisSize.min : MainAxisSize.max,
      children: <Widget>[
        _JrLaneHeader(width: width, lanes: s.lanes),
        if (height.isFinite)
          _JrViewport(controller: controller, width: width, height: height)
        else
          Expanded(
            child: _JrViewport(
              controller: controller,
              width: width,
              height: double.infinity,
            ),
          ),
      ],
    );
    return ElCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ElSectionLabel(_title()),
          const SizedBox(height: AppSpacing.xxs),
          if (fill)
            _JrCounts(controller: controller)
          else
            Text(
              join
                  ? 'A first connection, from the scan to the first useful '
                        'packet. Tap a sent message to see what it carries.'
                  : 'A roam from the current AP to a target AP. Tap a sent '
                        'message to see what it carries.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          if (join) ...<Widget>[
            SizedBox(height: fill ? AppSpacing.xs : AppSpacing.sm),
            _ChannelStrip(
              plan: s.scan,
              sent: controller.shown > 0,
              compact: fill,
            ),
          ],
          if (!s.found) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _NotFoundBand(plan: s.scan),
          ],
          const SizedBox(height: AppSpacing.xs),
          _JrLegend(sequence: s),
          SizedBox(height: fill ? AppSpacing.xs : AppSpacing.sm),
          if (fill)
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) =>
                    ladder(box.maxWidth, double.infinity),
              ),
            )
          else
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final bool wide = MediaQuery.sizeOf(context).width >= 720;
                return ladder(
                  box.maxWidth,
                  wide ? _kViewportWide : _kViewportPhone,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _NotFoundBand extends StatelessWidget {
  const _NotFoundBand({required this.plan});

  final JrScanPlan plan;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final String msg =
        'Not found on this pass. The AP\'s beacon comes '
        '${formatJrMs(kFirstBeaconOffsetMs)} into the dwell on channel '
        '${plan.targetChannel}, and the radio listened for only '
        '${formatJrMs(plan.target.dwellMs)}. Lengthen the passive dwell, or '
        'switch to an active scan.';
    return Semantics(
      container: true,
      label: msg,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.statusWarningFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colors.statusWarning, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.warning_amber_rounded,
              size: PresenterMode.scaleOf(context).markerSize(20),
              color: colors.statusWarning,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                msg,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Channel strip ───────────────────────────────────────────────────────────

class _ChannelStrip extends StatelessWidget {
  const _ChannelStrip({
    required this.plan,
    required this.sent,
    required this.compact,
  });

  final JrScanPlan plan;

  /// The scan has been played (the first message is out).
  final bool sent;

  /// Presenter: one line of explanation instead of three.
  final bool compact;

  String _summary() {
    if (plan.rnr) {
      return 'RNR named the AP: one 6 GHz channel (${plan.targetChannel}), '
          '${plan.scanType == JrScanType.active ? 'probed' : 'listened to'} '
          'for ${formatJrMs(plan.target.dwellMs)}.';
    }
    final int probed = plan.probedCount;
    final int listened = plan.listenedCount;
    final List<String> parts = <String>[
      if (probed > 0)
        '$probed probed for ${formatJrMs(plan.channels.firstWhere((JrScanChannel c) => c.probed).dwellMs)} each',
      if (listened > 0)
        '$listened ${plan.band == JrBand.g5 && probed > 0 ? 'DFS channels ' : ''}'
            'listened to for '
            '${formatJrMs(plan.channels.firstWhere((JrScanChannel c) => !c.probed).dwellMs)} each',
    ];
    final String six =
        plan.band == JrBand.g6 && plan.scanType == JrScanType.active
        ? ' Only the 15 PSCs are probed in 6 GHz.'
        : '';
    final String how = plan.scanType == JrScanType.active
        ? ' It answered the probe there (the lime tick), whatever its beacons '
              'did.'
        : '';
    return '${plan.channels.length} channels: ${parts.join(', ')}. The AP is '
        'on channel ${plan.targetChannel}.$how Scan '
        '${formatJrMs(plan.totalMs)}.$six';
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final int heard = plan.events
        .where(
          (JrScanEvent e) =>
              e.heard &&
              (e.kind == JrScanEventKind.beacon ||
                  e.kind == JrScanEventKind.fils),
        )
        .length;
    final int missed = plan.events
        .where((JrScanEvent e) => !e.heard && e.kind == JrScanEventKind.beacon)
        .length;
    final String beacons =
        'Beacons from the AP every 102.4 ms: $heard heard (filled), $missed '
        'missed while the radio was on other channels (hollow).'
        '${plan.band == JrBand.g6 ? ' Short ticks: FILS Discovery every 20 TU.' : ''}';
    final TextStyle? small = text.bodySmall?.copyWith(
      color: colors.textSecondary,
    );
    return Semantics(
      container: true,
      label: 'Channel strip. ${_summary()} $beacons',
      excludeSemantics: true,
      child: Column(
        key: JoinRoamStage.stripKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Channel strip: each block is one channel\'s dwell, to '
                  'scale',
                  style: text.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                formatJrMs(plan.totalMs),
                style:
                    (Theme.of(context).extension<AppMonoText>() ??
                            AppMonoText.defaults())
                        .inlineCode
                        .copyWith(color: colors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          SizedBox(
            height: (_kStripHeight + _kBeaconRow) * sc.text,
            child: CustomPaint(
              painter: _StripPainter(
                plan: plan,
                sent: sent,
                probedFill: ladderLegColor(
                  LadderLeg.air,
                  isLight: colors.isLight,
                ),
                outline: colors.borderStrong,
                faint: colors.border,
                target: colors.primary,
                heard: colors.textAccent,
                missed: colors.textTertiary,
                labelColor: colors.textPrimary,
                labelSize: AppTextSize.caption * sc.text,
                stroke: sc.strokeWidth(1),
                stripHeight: _kStripHeight * sc.text,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(_summary(), style: small),
          if (!compact) ...<Widget>[
            Text(beacons, style: small),
            Text(
              'Dwell: one real example (Linux mac80211, about 30 ms active and '
              '111 ms passive); many drivers scan in firmware with their own '
              'dwell. Channel changes are not counted.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.plan,
    required this.sent,
    required this.probedFill,
    required this.outline,
    required this.faint,
    required this.target,
    required this.heard,
    required this.missed,
    required this.labelColor,
    required this.labelSize,
    required this.stroke,
    required this.stripHeight,
  });

  final JrScanPlan plan;
  final bool sent;
  final Color probedFill;
  final Color outline;
  final Color faint;
  final Color target;
  final Color heard;
  final Color missed;
  final Color labelColor;
  final double labelSize;
  final double stroke;
  final double stripHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final double total = plan.totalMs;
    if (total <= 0) return;
    double x(double ms) => ms / total * size.width;
    final double alpha = sent ? 1 : 0.45;
    for (final JrScanChannel ch in plan.channels) {
      final Rect r = Rect.fromLTRB(
        x(ch.startMs),
        0,
        x(ch.endMs),
        stripHeight,
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
          ..color = (sent ? outline : faint)
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
        final TextPainter tp = TextPainter(
          text: TextSpan(
            text: '${ch.number}',
            style: TextStyle(
              color: labelColor,
              fontSize: labelSize,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final double cx = (r.center.dx - tp.width / 2).clamp(
          0,
          math.max(0, size.width - tp.width),
        );
        tp.paint(canvas, Offset(cx, (stripHeight - tp.height) / 2));
      }
    }
    // The AP's frames on its channel, under the strip.
    final double y0 = stripHeight + 2;
    final double y1 = size.height - 1;
    for (final JrScanEvent e in plan.events) {
      if (e.kind == JrScanEventKind.probeRequest) continue;
      final double ex = x(e.atMs).clamp(1, size.width - 1);
      final bool short = e.kind == JrScanEventKind.fils;
      final double top = short ? y0 + (y1 - y0) * 0.45 : y0;
      final Path tick = Path()
        ..moveTo(ex, top)
        ..lineTo(ex - 3, y1)
        ..lineTo(ex + 3, y1)
        ..close();
      final bool isHeard = e.heard;
      canvas.drawPath(
        tick,
        Paint()
          ..color = (isHeard ? heard : missed).withValues(alpha: alpha)
          ..style = isHeard ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.plan != plan ||
      old.sent != sent ||
      old.probedFill != probedFill ||
      old.outline != outline ||
      old.labelSize != labelSize ||
      old.stroke != stroke;
}

// ── Legend and lane header ──────────────────────────────────────────────────

class _JrLegend extends StatelessWidget {
  const _JrLegend({required this.sequence});

  final JrSequence sequence;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final double icon = sc.markerSize(16);
    final TextStyle? style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textSecondary);
    Widget item(Widget glyph, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(child: glyph),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(label, style: style)),
      ],
    );
    Widget letter(String l) => Text(
      l,
      style: style?.copyWith(
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
    );
    final bool anyTunnel = sequence.messages.any((JrMessage m) => m.tunneled);
    final bool anyEnc = sequence.messages.any((JrMessage m) => m.encrypted);
    final bool anyPmf = sequence.messages.any((JrMessage m) => m.pmfProtected);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        item(const _JrLegSample(leg: LadderLeg.air), 'Over the air (solid)'),
        item(const _JrLegSample(leg: LadderLeg.wire), 'On the wire (dashed)'),
        item(letter('M'), 'management frame'),
        item(letter('D'), 'data frame'),
        if (anyEnc)
          item(
            Icon(Icons.lock_rounded, size: icon, color: colors.textAccent),
            'encrypted data',
          ),
        if (anyPmf)
          item(
            Icon(Icons.shield_rounded, size: icon, color: colors.textAccent),
            'PMF protected',
          ),
        if (anyTunnel)
          item(
            Icon(
              Icons.lock_outline_rounded,
              size: icon,
              color: colors.textSecondary,
            ),
            '{ } inside the TLS tunnel',
          ),
      ],
    );
  }
}

class _JrLegSample extends StatelessWidget {
  const _JrLegSample({required this.leg});

  final LadderLeg leg;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final double w = 28 * sc.text;
    return SizedBox(
      width: w,
      height: 12 * sc.text,
      child: CustomPaint(
        painter: _HopArrowPainter(
          hops: <_Hop>[
            _Hop(
              0,
              w,
              ladderLegColor(leg, isLight: colors.isLight),
              leg == LadderLeg.wire,
            ),
          ],
          y: 6 * sc.text,
          stroke: sc.strokeWidth(2),
          progress: 1,
          head: sc.markerSize(8),
        ),
      ),
    );
  }
}

class _JrLaneHeader extends StatelessWidget {
  const _JrLaneHeader({required this.width, required this.lanes});

  final double width;
  final List<JrLane> lanes;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final List<double> fx = jrLaneFractions(lanes.length);
    final double half = lanes.length < 2
        ? 0.5
        : math.min(fx.first, (fx[1] - fx[0]) / 2);
    return Semantics(
      container: true,
      label:
          'Lanes: ${lanes.map((JrLane l) => '${l.label}, ${l.role}').join('; ')}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: width,
              child: Stack(
                children: <Widget>[
                  // Sized by the tallest header.
                  Opacity(
                    opacity: 0,
                    child: Column(
                      children: <Widget>[
                        Text(' ', style: text.labelMedium),
                        Text(' \n ', style: text.bodySmall),
                      ],
                    ),
                  ),
                  for (int i = 0; i < lanes.length; i++)
                    Positioned(
                      left: width * (fx[i] - half),
                      width: width * half * 2,
                      top: 0,
                      child: Column(
                        children: <Widget>[
                          Text(
                            lanes[i].label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            lanes[i].role,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Divider(height: 1, thickness: 1, color: colors.border),
          ],
        ),
      ),
    );
  }
}

// ── The scrolling ladder ────────────────────────────────────────────────────

class _JrViewport extends StatefulWidget {
  const _JrViewport({
    required this.controller,
    required this.width,
    required this.height,
  });

  final EapLadderController controller;
  final double width;
  final double height;

  @override
  State<_JrViewport> createState() => _JrViewportState();
}

class _JrViewportState extends State<_JrViewport> {
  final ScrollController _scroll = ScrollController();
  List<GlobalKey> _keys = <GlobalKey>[];
  JrSequence? _keyedFor;
  int _lastShown = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _syncKeys(JrSequence s) {
    if (identical(s, _keyedFor)) return;
    _keyedFor = s;
    _keys = List<GlobalKey>.generate(s.length, (_) => GlobalKey());
  }

  void _follow(int shown, {required bool reduceMotion}) {
    if (shown == _lastShown) return;
    _lastShown = shown;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (shown == 0 || shown > _keys.length) {
        _scroll.jumpTo(0);
        return;
      }
      final RenderObject? target = _keys[shown - 1].currentContext
          ?.findRenderObject();
      if (target == null) return;
      // Only this viewport scrolls, never the page.
      final RenderAbstractViewport viewport = RenderAbstractViewport.of(target);
      final ScrollPosition pos = _scroll.position;
      final double to = viewport
          .getOffsetToReveal(target, 0.6)
          .offset
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (reduceMotion) {
        _scroll.jumpTo(to);
      } else {
        _scroll.animateTo(
          to,
          duration: AppMotion.base,
          curve: AppMotion.standardEase,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final EapLadderController c = widget.controller;
    final JrSequence s = c.jr;
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncKeys(s);
    _follow(c.shown, reduceMotion: reduceMotion);
    final List<double> fx = jrLaneFractions(s.lanes.length);
    double laneX(JrLane l) => widget.width * fx[s.lanes.indexOf(l)];

    final List<Widget> rows = <Widget>[];
    JrPhase? phase;
    for (int i = 0; i < s.length; i++) {
      final JrMessage m = s.messages[i];
      if (m.phase != phase) {
        phase = m.phase;
        rows.add(
          _JrPhaseRow(
            label: s.phaseTitle(m.phase),
            width: widget.width,
            xs: <double>[for (final JrLane l in s.lanes) laneX(l)],
          ),
        );
      }
      final _JrRowState state = i < c.shown - 1
          ? _JrRowState.sent
          : i == c.shown - 1
          ? _JrRowState.latest
          : _JrRowState.waiting;
      rows.add(
        _JrMessageRow(
          key: _keys[i],
          index: i,
          total: s.length,
          message: m,
          state: state,
          inspected: c.inspecting && c.captionIndex == i,
          width: widget.width,
          laneX: laneX,
          lanes: s.lanes,
          reduceMotion: reduceMotion,
          onTap: state == _JrRowState.waiting ? null : () => c.inspect(i),
        ),
      );
      if (m.milestone != null) {
        rows.add(
          _JrMilestoneRow(
            milestone: m.milestone!,
            text: m.milestoneText ?? m.milestone!.label,
            reached: i < c.shown,
          ),
        );
      }
    }

    return Semantics(
      container: true,
      label:
          'Ladder: ${c.shown} of ${s.length} messages sent. Each sent message '
          'is listed below with its step number; activate one to see what '
          'it carries.',
      child: SizedBox(
        height: widget.height,
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            key: JoinRoamStage.ladderScrollKey,
            controller: _scroll,
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      ),
    );
  }
}

enum _JrRowState { sent, latest, waiting }

class _JrPhaseRow extends StatelessWidget {
  const _JrPhaseRow({
    required this.label,
    required this.width,
    required this.xs,
  });

  final String label;
  final double width;
  final List<double> xs;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return CustomPaint(
      painter: _JrLanesPainter(
        xs: xs,
        color: colors.border,
        stroke: PresenterMode.scaleOf(context).strokeWidth(1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.xxs,
        ),
        child: Center(
          child: Semantics(
            header: true,
            child: Container(
              color: colors.surface1,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textTertiary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JrMessageRow extends StatelessWidget {
  const _JrMessageRow({
    super.key,
    required this.index,
    required this.total,
    required this.message,
    required this.state,
    required this.inspected,
    required this.width,
    required this.laneX,
    required this.lanes,
    required this.reduceMotion,
    required this.onTap,
  });

  final int index;
  final int total;
  final JrMessage message;
  final _JrRowState state;
  final bool inspected;
  final double width;
  final double Function(JrLane) laneX;
  final List<JrLane> lanes;
  final bool reduceMotion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final JrMessage m = message;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final double band = _kArrowBand * sc.text;
    final bool visible = state != _JrRowState.waiting;
    final Color labelColor = m.missed
        ? colors.textTertiary
        : ladderLegColor(m.leg, isLight: colors.isLight);
    final double fromX = laneX(m.from);
    final double toX = laneX(m.to);
    final double lo = math.min(fromX, toX);
    final double hi = math.max(fromX, toX);
    final double left = lo + AppSpacing.xxs;
    final double right = width - hi + AppSpacing.xxs;
    final List<_Hop> hops = <_Hop>[
      for (final (JrLane, JrLane) h in m.hops)
        _Hop(
          laneX(h.$1),
          laneX(h.$2),
          !visible
              ? colors.border
              : m.missed
              ? colors.textTertiary
              : ladderLegColor(JrMessage.legOf(h), isLight: colors.isLight),
          JrMessage.legOf(h) == LadderLeg.wire || m.missed,
        ),
    ];
    final List<double> xs = <double>[for (final JrLane l in lanes) laneX(l)];

    final Widget labels = Visibility(
      visible: visible,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            m.label,
            textAlign: TextAlign.center,
            style: text.labelMedium?.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (m.detail != null)
            Text(
              m.detail!,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );

    final Color markColor = colors.textAccent;
    final Widget gutter = Visibility(
      visible: visible,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (m.pmfProtected) ...<Widget>[
              Icon(
                Icons.shield_rounded,
                size: sc.markerSize(14),
                color: markColor,
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
            if (m.encrypted) ...<Widget>[
              Icon(
                Icons.lock_rounded,
                size: sc.markerSize(14),
                color: markColor,
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
            if (m.tunneled) ...<Widget>[
              Icon(
                Icons.lock_outline_rounded,
                size: sc.markerSize(14),
                color: colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
            if (m.kind.frameClass != JrFrameClass.wire) ...<Widget>[
              Text(
                m.isManagement ? 'M' : 'D',
                style: text.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Text(
              '${index + 1}',
              style: mono.inlineCode.copyWith(
                fontSize: AppTextSize.caption,
                color: state == _JrRowState.latest || inspected
                    ? colors.textAccent
                    : colors.textTertiary,
                fontWeight: state == _JrRowState.latest || inspected
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );

    final bool highlight = state == _JrRowState.latest || inspected;
    Widget row = Container(
      decoration: BoxDecoration(
        color: highlight
            ? (colors.isLight ? colors.surface0 : colors.surface2)
            : null,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: inspected
            ? Border.all(color: colors.primary, width: 1.5)
            : null,
      ),
      child: TweenAnimationBuilder<double>(
        key: ValueKey<String>('jr-arrow-$index-${state.name}'),
        tween: Tween<double>(
          begin: state == _JrRowState.latest && !reduceMotion ? 0 : 1,
          end: 1,
        ),
        duration: AppMotion.slow,
        curve: AppMotion.standardEase,
        builder: (BuildContext context, double progress, Widget? child) {
          return CustomPaint(
            painter: _JrLanesPainter(
              xs: xs,
              color: colors.border,
              stroke: sc.strokeWidth(1.5),
              arrow: _HopArrowPainter(
                hops: hops,
                y: null,
                stroke: sc.strokeWidth(highlight ? 3 : 2),
                // A missed beacon never reaches the client.
                progress: m.missed ? math.min(progress, 0.5) : progress,
                head: m.missed ? 0 : sc.markerSize(8),
                band: band,
              ),
            ),
            child: child,
          );
        },
        child: Stack(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.only(
                left: left,
                right: right,
                top: AppSpacing.xs,
                bottom: band,
              ),
              child: Center(child: labels),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              width: math.max(0, laneX(lanes.first) - AppSpacing.xs),
              child: gutter,
            ),
          ],
        ),
      ),
    );

    if (!visible) return ExcludeSemantics(child: row);
    row = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: row,
      ),
    );
    final String marks = <String>[
      m.kind.frameClass == JrFrameClass.wire
          ? 'wired packet'
          : '${m.kind.frameClass.label.toLowerCase()} frame',
      if (m.encrypted) 'encrypted',
      if (m.pmfProtected) 'protected by PMF',
      if (m.missed) 'missed',
    ].join(', ');
    final String via = m.via == null ? '' : ' through the ${m.via!.label}';
    final String contents = m.contents.isEmpty ? '' : ', ${m.contents}';
    return Semantics(
      button: true,
      selected: inspected,
      label:
          'Step ${index + 1} of $total, $marks, ${m.from.label} to '
          '${m.to.label}$via: ${m.label}$contents. ${m.description}',
      hint: 'Shows what it carries',
      excludeSemantics: true,
      child: row,
    );
  }
}

class _JrMilestoneRow extends StatelessWidget {
  const _JrMilestoneRow({
    required this.milestone,
    required this.text,
    required this.reached,
  });

  final LadderMilestone milestone;
  final String text;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme theme = Theme.of(context).textTheme;
    final Widget band = Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.primary, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            milestone == LadderMilestone.keysAvailable
                ? Icons.key_rounded
                : Icons.lock_rounded,
            size: PresenterMode.scaleOf(context).markerSize(20),
            color: colors.textAccent,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: theme.bodySmall?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
    if (!reached) {
      return ExcludeSemantics(
        child: Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: band,
        ),
      );
    }
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: band,
    );
  }
}

// ── Painters ────────────────────────────────────────────────────────────────

/// Vertical lane lines at [xs], with an optional arrow on top.
class _JrLanesPainter extends CustomPainter {
  _JrLanesPainter({
    required this.xs,
    required this.color,
    this.stroke = 1.5,
    this.arrow,
  });

  final List<double> xs;
  final Color color;
  final double stroke;
  final _HopArrowPainter? arrow;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint lane = Paint()
      ..color = color
      ..strokeWidth = stroke;
    for (final double x in xs) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), lane);
    }
    arrow?.paint(canvas, size);
  }

  @override
  bool shouldRepaint(_JrLanesPainter old) =>
      old.color != color ||
      old.stroke != stroke ||
      old.xs.length != xs.length ||
      old.arrow?.progress != arrow?.progress ||
      old.arrow?.stroke != arrow?.stroke ||
      old.arrow?.hops.first.color != arrow?.hops.first.color;
}

/// One hop of an arrow: [fromX] to [toX], its color, dashed or solid.
@immutable
class _Hop {
  const _Hop(this.fromX, this.toX, this.color, this.dashed);

  final double fromX;
  final double toX;
  final Color color;
  final bool dashed;
}

/// An arrow of one or more hops in the same direction, drawn in from its
/// source as [progress] goes 0 to 1; the head sits on the last hop.
class _HopArrowPainter extends CustomPainter {
  _HopArrowPainter({
    required this.hops,
    required this.y,
    required this.stroke,
    required this.progress,
    this.head = 8,
    this.band = _kArrowBand,
  });

  final List<_Hop> hops;
  final double? y;
  final double stroke;
  final double progress;
  final double head;
  final double band;

  @override
  void paint(Canvas canvas, Size size) {
    if (hops.isEmpty) return;
    final double yy = y ?? size.height - band / 2;
    final double startX = hops.first.fromX;
    final double endX = hops.last.toX;
    final double dir = endX >= startX ? 1 : -1;
    final double reach = startX + (endX - startX) * progress;
    for (int i = 0; i < hops.length; i++) {
      final _Hop h = hops[i];
      final bool last = i == hops.length - 1;
      // Clip this hop to how far the arrow has drawn.
      final double a = h.fromX;
      double b = (reach - h.toX) * dir >= 0 ? h.toX : reach;
      if ((b - a) * dir <= 0) break;
      final bool headHere = last && (reach - h.toX) * dir >= -0.01;
      final double shaftEnd = headHere && head > 0 ? b - dir * head * 0.6 : b;
      final Paint p = Paint()
        ..color = h.color
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      if (h.dashed) {
        const double dash = 6;
        const double gap = 4;
        double x = a;
        while ((shaftEnd - x) * dir > 0) {
          final double next = x + dir * dash;
          final double clipped = (shaftEnd - next) * dir < 0 ? shaftEnd : next;
          canvas.drawLine(Offset(x, yy), Offset(clipped, yy), p);
          x = next + dir * gap;
        }
      } else if ((shaftEnd - a) * dir > 0) {
        canvas.drawLine(Offset(a, yy), Offset(shaftEnd, yy), p);
      }
      if (last && head > 0 && progress > 0) {
        b = reach;
        final Path tip = Path()
          ..moveTo(b, yy)
          ..lineTo(b - dir * head, yy - head / 2)
          ..lineTo(b - dir * head, yy + head / 2)
          ..close();
        canvas.drawPath(
          tip,
          Paint()
            ..color = h.color
            ..style = PaintingStyle.fill,
        );
      }
    }
    // A head while still drawing the first hop of a two-hop arrow.
    if (hops.length > 1 && head > 0 && progress > 0) {
      final _Hop h0 = hops.first;
      if ((h0.toX - reach) * dir > 0) {
        final Path tip = Path()
          ..moveTo(reach, yy)
          ..lineTo(reach - dir * head, yy - head / 2)
          ..lineTo(reach - dir * head, yy + head / 2)
          ..close();
        canvas.drawPath(
          tip,
          Paint()
            ..color = h0.color
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HopArrowPainter old) =>
      old.progress != progress ||
      old.stroke != stroke ||
      old.head != head ||
      old.band != band ||
      old.hops.length != hops.length;
}

// ── Timeline ────────────────────────────────────────────────────────────────

/// One bar of the timeline: its name, its full time and how much of it has
/// run at the current step.
typedef _Bar = (String label, double totalMs, double elapsedMs);

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.controller});

  final EapLadderController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final JrSequence s = controller.jr;
    final int shown = controller.shown;
    final bool roam = s.mode == LadderMode.roam;
    final List<_Bar> bars;
    if (roam) {
      final Map<RoamBar, double> t = s.roamTotals;
      bars = <_Bar>[
        for (final RoamBar b in RoamBar.values)
          (
            b.label,
            t[b]!,
            s.messages
                .take(shown)
                .where(
                  (JrMessage m) =>
                      m.clock != JrClock.later && RoamBar.of(m.clock) == b,
                )
                .fold(0.0, (double a, JrMessage m) => a + m.ms),
          ),
      ];
    } else {
      final Map<JrClock, double> t = s.clockTotals;
      bars = <_Bar>[
        for (final JrClock c in JrClock.joinClocks)
          if (t[c]! > 0) (c.label, t[c]!, s.clockElapsedMs(c, shown)),
      ];
    }
    final double total = s.totalMs;
    final double elapsed = s.elapsedMs(shown);
    final String heading = roam
        ? 'Roam time: scan, authentication and key handshake, to scale'
        : 'Join time by phase, to scale';
    final String semantic =
        '$heading. ${bars.map((_Bar b) => '${b.$1} ${formatJrMs(b.$2)}').join(', ')}. '
        'Total ${formatJrMs(total)}; ${formatJrMs(elapsed)} so far.';
    return Semantics(
      container: true,
      label: semantic,
      excludeSemantics: true,
      child: ElCard(
        key: JoinRoamStage.timelineKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Stacked, so the elapsed time never fights the heading for
            // width (the presenter's side column is narrow).
            ElSectionLabel(heading),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${formatJrMs(elapsed)} of ${formatJrMs(total)}',
              style: (sc.isPresenting ? mono.outputMedium : mono.inlineCode)
                  .copyWith(color: colors.textAccent),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: _kTimelineBar * sc.text,
              child: CustomPaint(
                size: Size.infinite,
                painter: _TimelinePainter(
                  bars: bars,
                  total: total,
                  done: colors.primary,
                  todo: colors.surface3,
                  outline: colors.borderStrong,
                  stroke: sc.strokeWidth(1),
                ),
              ),
            ),
            if (roam) _RoamZoom(sequence: s, shown: shown),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                for (final _Bar b in bars)
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: '${b.$1} ',
                          style: text.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        TextSpan(
                          text: b.$3 > 0 && b.$3 < b.$2
                              ? '${formatJrMs(b.$3)} of ${formatJrMs(b.$2)}'
                              : formatJrMs(b.$2),
                          style: mono.inlineCode.copyWith(
                            fontSize: AppTextSize.caption,
                            color: b.$3 > 0
                                ? colors.textAccent
                                : colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (!sc.isPresenting) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                roam
                    ? 'Every time is a setting (see Timing). FT shrinks the '
                          'middle bar; no method shortens the scan.'
                    : 'Every phase time is a setting (see Timing): no '
                          'published measurement breaks a typical join down '
                          'by phase. Lime is the time run so far.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Roam only: authentication and key handshake again, zoomed so a full
/// 802.1X roam fills the bar. At full scale the scan swamps them; here FT
/// visibly shrinks the middle while the scan (above) stays the same.
class _RoamZoom extends StatelessWidget {
  const _RoamZoom({required this.sequence, required this.shown});

  final JrSequence sequence;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final Map<RoamBar, double> t = sequence.roamTotals;
    final Map<RoamBar, double> full = buildRoam(
      sequence.config.copyWith(roamMethod: JrRoamMethod.full),
    ).roamTotals;
    final double ref =
        full[RoamBar.authentication]! + full[RoamBar.keyHandshake]!;
    final double mine = t[RoamBar.authentication]! + t[RoamBar.keyHandshake]!;
    double elapsed(RoamBar b) => sequence.messages
        .take(shown)
        .where(
          (JrMessage m) => m.clock != JrClock.later && RoamBar.of(m.clock) == b,
        )
        .fold(0.0, (double a, JrMessage m) => a + m.ms);
    final List<_Bar> bars = <_Bar>[
      for (final RoamBar b in <RoamBar>[
        RoamBar.authentication,
        RoamBar.keyHandshake,
      ])
        (b.label, t[b]!, elapsed(b)),
    ];
    final double frac = ref <= 0 ? 1 : (mine / ref).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'After the scan, zoomed: ${formatJrMs(mine)} against '
            '${formatJrMs(ref)} for a full 802.1X roam (the whole width)',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SizedBox(
            height: _kTimelineBar * sc.text,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) => Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.border),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: math.max(4, box.maxWidth * frac),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _TimelinePainter(
                        bars: bars,
                        total: mine,
                        done: colors.primary,
                        todo: colors.surface3,
                        outline: colors.borderStrong,
                        stroke: sc.strokeWidth(1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.bars,
    required this.total,
    required this.done,
    required this.todo,
    required this.outline,
    required this.stroke,
  });

  final List<_Bar> bars;
  final double total;
  final Color done;
  final Color todo;
  final Color outline;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || bars.isEmpty) return;
    // Every bar at least 2 px, so a 4 ms phase still shows next to seconds.
    const double minW = 2;
    const double gap = 2;
    final double usable = size.width - gap * (bars.length - 1);
    final double scale =
        (usable - minW * bars.length).clamp(0, double.infinity) / total;
    double x = 0;
    for (final _Bar b in bars) {
      final double w = minW + b.$2 * scale;
      final Rect r = Rect.fromLTWH(x, 0, w, size.height);
      canvas.drawRect(r, Paint()..color = todo);
      final double f = b.$2 <= 0 ? 0 : (b.$3 / b.$2).clamp(0.0, 1.0);
      if (f > 0) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, w * f, size.height),
          Paint()..color = done,
        );
      }
      canvas.drawRect(
        r,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      x += w + gap;
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.total != total ||
      old.done != done ||
      old.todo != todo ||
      old.bars.length != bars.length ||
      !_sameBars(old.bars, bars);

  static bool _sameBars(List<_Bar> a, List<_Bar> b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ── Caption ─────────────────────────────────────────────────────────────────

class _JrCaption extends StatelessWidget {
  const _JrCaption({required this.controller, this.presenter = false});

  final EapLadderController controller;
  final bool presenter;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final JrSequence s = controller.jr;
    final JrMessage? m = controller.captionJr;
    final int n = s.length;
    final List<Widget> children;
    if (m == null) {
      children = <Widget>[
        const ElSectionLabel('Ready'),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          presenter
              ? 'Press Play or Step to send the first of $n messages.'
              : 'Press Play or Step to send the first of $n messages. Tap any '
                    'sent message to see what it carries.',
          style: text.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
      ];
    } else {
      final int step = controller.captionIndex + 1;
      final String stepText = controller.inspecting
          ? 'Step $step of $n (tapped; Step or Play returns to the latest)'
          : 'Step $step of $n';
      final Color legColor = m.missed
          ? colors.textTertiary
          : ladderLegColor(m.leg, isLight: colors.isLight);
      children = <Widget>[
        if (presenter)
          Text(
            stepText,
            style: sc
                .headlineStyle(mono.outputLarge)
                .copyWith(color: colors.textAccent),
          )
        else
          ElSectionLabel(stepText),
        const SizedBox(height: AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _JrChip(
              label: m.via == null
                  ? m.leg.label
                  : 'Over the air, then on the wire',
              color: legColor,
            ),
            _JrChip(label: m.kind.label, color: colors.textSecondary),
            if (m.encrypted)
              _JrChip(label: 'Encrypted', color: colors.textAccent),
            if (m.pmfProtected)
              _JrChip(label: 'PMF protected', color: colors.textAccent),
            Text(
              '${m.from.label} to ${m.to.label}'
              '${m.via == null ? '' : ', through the ${m.via!.label}'}',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          m.label,
          style: text.titleMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (m.contents.isNotEmpty)
          Text(
            m.contents,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          m.description,
          style: text.bodyMedium?.copyWith(color: colors.textPrimary),
        ),
        if (m.milestoneText != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ExcludeSemantics(
                child: Icon(
                  m.milestone == LadderMilestone.keysAvailable
                      ? Icons.key_rounded
                      : Icons.lock_rounded,
                  size: sc.markerSize(20),
                  color: colors.textAccent,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  m.milestoneText!,
                  style: text.bodyMedium?.copyWith(
                    color: colors.textAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (m.fields.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          const ElSectionLabel('What it carries'),
          for (final JrField f in m.fields) ElRow(label: f.$1, value: f.$2),
        ],
        if (m.missed) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ExcludeSemantics(
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: sc.markerSize(20),
                  color: colors.statusWarning,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Not found: the join stops here.',
                  style: text.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ];
    }
    return Semantics(
      liveRegion: true,
      container: true,
      child: ElCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _JrChip extends StatelessWidget {
  const _JrChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Presenter counts ────────────────────────────────────────────────────────

class _JrCounts extends StatelessWidget {
  const _JrCounts({required this.controller});

  final EapLadderController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final JrSequence s = controller.jr;
    Widget stat(String label, String value, {Color? color}) => MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          Text(
            value,
            style: mono.outputMedium.copyWith(
              color: color ?? colors.textPrimary,
            ),
          ),
        ],
      ),
    );
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        stat(
          'Over the air',
          '${s.airCount} (${s.managementCount} M, ${s.dataCount} D)',
          color: ladderLegColor(LadderLeg.air, isLight: colors.isLight),
        ),
        stat(
          'On the wire',
          '${s.wireCount}',
          color: ladderLegColor(LadderLeg.wire, isLight: colors.isLight),
        ),
        if (s.radiusRoundTrips > 0)
          stat('RADIUS round trips', '${s.radiusRoundTrips}'),
      ],
    );
  }
}
