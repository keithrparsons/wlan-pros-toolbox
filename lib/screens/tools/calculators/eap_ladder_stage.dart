// EapLadderStage: the pictures half of the 802.1X and EAP Ladder.
//
// A three-lane sequence diagram (client, AP, RADIUS server). Each message is
// an arrow with its frame name on it; arrows over the air and arrows on the
// wire take the two leg hues from eap_ladder_palette.dart, and wire arrows are
// also dashed, so the leg never rests on color. Messages not yet sent show as
// faint arrows with their text held back; phase headings are always visible,
// so the shape of the exchange is there before it plays. Two milestone bands
// appear as they are reached: keys available, traffic protected.
//
// Below the ladder, a caption says what the latest message is, which leg it
// crossed, and why it is there. The ladder scrolls vertically inside its card
// and follows the latest message; the page never scrolls sideways.
//
// PRESENTER (spec 00): inside a PresenterLayout the ladder takes the stage
// height the caption leaves and still scrolls inside its own viewport,
// following the latest message (the page never scrolls). The counts (air
// frames, RADIUS messages, round trips, time to connect) sit in the ladder's
// header, and the caption leads with "Step n of N". Strokes, arrowheads and
// icons read PresenterMode.scaleOf.
//
// Takes the shared EapLadderController and nothing else. In Roam mode (spec
// 21b) it hands the whole stage to JoinRoamStage (eap_ladder_jr_stage.dart).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import '../../../services/wifi_lab/eap_ladder.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter.dart';
import 'eap_ladder_controller.dart';
import 'eap_ladder_failure.dart';
import 'eap_ladder_jr_stage.dart';
import 'eap_ladder_palette.dart';
import 'eap_ladder_parts.dart';

/// Lane centers as fractions of the ladder width. Each header box is the
/// width around its lane (0 to 0.3, 0.3 to 0.7, 0.7 to 1), so the headers
/// center on the lanes exactly.
const List<double> _kLaneFractions = <double>[0.15, 0.5, 0.85];
const List<double> _kHeaderFractions = <double>[0.3, 0.4, 0.3];

/// Height of the ladder's own scroll viewport (a dimension, GL-003 §4.2).
const double _kViewportPhone = 440;
const double _kViewportWide = 560;

/// Height of the band under a label where the arrow is drawn (a dimension).
const double _kArrowBand = 16;

class EapLadderStage extends StatelessWidget {
  const EapLadderStage({super.key, required this.controller});

  final EapLadderController controller;

  /// The ladder's own vertical scroll view. It is the one scroll the
  /// presenter layout allows on this stage (long sequences), and it follows
  /// the latest message; tests use this key to tell it from a page scroll.
  static const Key ladderScrollKey = ValueKey<String>('eap-ladder-scroll');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        // Roam (and Join, in the join-ladder tool) draw their own
        // ladder: more lanes, the channel strip and the phase timeline.
        if (controller.isJr) return JoinRoamStage(controller: controller);
        if (PresenterMode.isActive(context)) {
          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _LadderCard(controller: controller, fill: true),
                ),
                const SizedBox(height: AppSpacing.xs),
                // A long description scales down as one piece rather than
                // take the ladder's height or clip.
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: box.maxHeight * 0.3),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: box.maxWidth,
                      child: _CaptionCard(
                        controller: controller,
                        presenter: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _LadderCard(controller: controller),
            const SizedBox(height: AppSpacing.sm),
            _CaptionCard(controller: controller),
          ],
        );
      },
    );
  }
}

// ── The ladder ──────────────────────────────────────────────────────────────

class _LadderCard extends StatelessWidget {
  const _LadderCard({required this.controller, this.fill = false});

  final EapLadderController controller;

  /// Presenter: fill a bounded box; counts replace the relay sentence.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final LadderConfig c = controller.config;
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return ElCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ElSectionLabel(
            '${c.method.label}'
            '${c.method == LadderMethod.eapTtls ? ' with ${c.inner.label} inside' : ''}'
            ': ${c.roam.label}'
            '${controller.sequence.failed ? '. Broken: ${c.effectiveFault.label}' : ''}',
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (fill)
            _Counts(controller: controller)
          else
            Text(
              controller.sequence.usesRadius
                  ? 'The AP relays EAP between the client and the RADIUS '
                        'server. It does not do the authentication.'
                  : 'No RADIUS server: the client and the AP prove the key '
                        'to each other directly.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          const SizedBox(height: AppSpacing.xs),
          _Legend(
            showTunnel: controller.sequence.messages.any(
              (LadderMessage m) => m.tunneled,
            ),
            showFailure: controller.sequence.messages.any(
              (LadderMessage m) => m.failure,
            ),
            showLost: controller.sequence.messages.any(
              (LadderMessage m) => m.lost,
            ),
          ),
          SizedBox(height: fill ? AppSpacing.xs : AppSpacing.sm),
          if (fill)
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _LaneHeader(
                      width: box.maxWidth,
                      radiusUsed: controller.sequence.usesRadius,
                    ),
                    Expanded(
                      child: _LadderViewport(
                        controller: controller,
                        width: box.maxWidth,
                        height: double.infinity,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double w = constraints.maxWidth;
                final bool wide = MediaQuery.sizeOf(context).width >= 720;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _LaneHeader(
                      width: w,
                      radiusUsed: controller.sequence.usesRadius,
                    ),
                    _LadderViewport(
                      controller: controller,
                      width: w,
                      height: wide ? _kViewportWide : _kViewportPhone,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.showTunnel,
    this.showFailure = false,
    this.showLost = false,
  });

  /// Only ladders with tunneled content list the tunnel mark.
  final bool showTunnel;

  /// Break it: only failed ladders list the failure and lost marks.
  final bool showFailure;
  final bool showLost;

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
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        item(
          const _LegSample(leg: LadderLeg.air),
          'Over the air: 802.11 and EAPOL',
        ),
        item(
          const _LegSample(leg: LadderLeg.wire),
          'On the wire: RADIUS over UDP (dashed)',
        ),
        if (showTunnel)
          item(
            Icon(
              Icons.lock_outline_rounded,
              size: icon,
              color: colors.textSecondary,
            ),
            '{ } inside the TLS tunnel',
          ),
        if (showFailure)
          item(
            Icon(kFailureIcon, size: icon, color: colors.statusDanger),
            'Failure: refused or ended',
          ),
        if (showLost)
          item(
            Icon(kLostIcon, size: icon, color: colors.textSecondary),
            'No answer',
          ),
        item(
          Icon(Icons.key_rounded, size: icon, color: colors.textAccent),
          'Keys available',
        ),
        item(
          Icon(
            Icons.verified_user_rounded,
            size: icon,
            color: colors.textAccent,
          ),
          'Traffic protected',
        ),
      ],
    );
  }
}

class _LegSample extends StatelessWidget {
  const _LegSample({required this.leg});

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
        painter: _ArrowPainter(
          color: ladderLegColor(leg, isLight: colors.isLight),
          dashed: leg == LadderLeg.wire,
          fromX: 0,
          toX: w,
          y: 6 * sc.text,
          stroke: sc.strokeWidth(2),
          progress: 1,
          head: sc.markerSize(8),
        ),
      ),
    );
  }
}

class _LaneHeader extends StatelessWidget {
  const _LaneHeader({required this.width, required this.radiusUsed});

  final double width;
  final bool radiusUsed;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    Widget lane(LadderLane l, double fraction) {
      final bool unused = l == LadderLane.radius && !radiusUsed;
      return SizedBox(
        width: width * fraction,
        child: Column(
          children: <Widget>[
            ElWholeWordText(
              l.label,
              textAlign: TextAlign.center,
              style: text.labelMedium?.copyWith(
                color: unused ? colors.textTertiary : colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            ElWholeWordText(
              unused ? 'not used here' : l.role,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      );
    }

    Widget legLabel(LadderLeg leg, {required bool dim}) => Expanded(
      child: Text(
        leg == LadderLeg.air ? 'over the air' : 'on the wire',
        textAlign: TextAlign.center,
        style: text.bodySmall?.copyWith(
          color: dim
              ? colors.textTertiary
              : ladderLegColor(leg, isLight: colors.isLight),
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final double clientX = width * _kLaneFractions[0];
    final double apX = width * _kLaneFractions[1];
    final double radiusX = width * _kLaneFractions[2];
    return Semantics(
      container: true,
      label:
          'Lanes: client, the supplicant; AP, the authenticator; RADIUS '
          'server${radiusUsed ? ', the authentication server' : ', not used in this method'}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                lane(LadderLane.client, _kHeaderFractions[0]),
                lane(LadderLane.ap, _kHeaderFractions[1]),
                lane(LadderLane.radius, _kHeaderFractions[2]),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: <Widget>[
                SizedBox(width: clientX),
                SizedBox(
                  width: apX - clientX,
                  child: Row(
                    children: <Widget>[legLabel(LadderLeg.air, dim: false)],
                  ),
                ),
                SizedBox(
                  width: radiusX - apX,
                  child: Row(
                    children: <Widget>[
                      legLabel(LadderLeg.wire, dim: !radiusUsed),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Divider(height: 1, thickness: 1, color: colors.border),
          ],
        ),
      ),
    );
  }
}

/// The scrolling list of rows. Stateful for its scroll position: it follows
/// the latest message.
class _LadderViewport extends StatefulWidget {
  const _LadderViewport({
    required this.controller,
    required this.width,
    required this.height,
  });

  final EapLadderController controller;
  final double width;
  final double height;

  @override
  State<_LadderViewport> createState() => _LadderViewportState();
}

class _LadderViewportState extends State<_LadderViewport> {
  final ScrollController _scroll = ScrollController();
  List<GlobalKey> _keys = <GlobalKey>[];
  LadderSequence? _keyedFor;
  int _lastShown = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _syncKeys(LadderSequence s) {
    if (identical(s, _keyedFor)) return;
    _keyedFor = s;
    _keys = List<GlobalKey>.generate(s.length, (_) => GlobalKey());
  }

  void _follow(int shown, {required bool reduceMotion}) {
    if (shown == _lastShown) return;
    _lastShown = shown;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (shown == 0) {
        _scroll.jumpTo(0);
        return;
      }
      final RenderObject? target = _keys[shown - 1].currentContext
          ?.findRenderObject();
      if (target == null) return;
      // Scroll only the ladder's own viewport. Scrollable.ensureVisible would
      // also scroll the page, moving the transport buttons under the user's
      // finger while the ladder plays.
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
    final LadderSequence s = c.sequence;
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncKeys(s);
    _follow(c.shown, reduceMotion: reduceMotion);

    final List<Widget> rows = <Widget>[];
    LadderPhase? phase;
    for (int i = 0; i < s.length; i++) {
      final LadderMessage m = s.messages[i];
      if (m.phase != phase) {
        phase = m.phase;
        rows.add(
          _PhaseRow(
            label: m.phase.label,
            width: widget.width,
            radiusUsed: s.usesRadius,
          ),
        );
      }
      final _RowState state = i < c.shown - 1
          ? _RowState.sent
          : i == c.shown - 1
          ? _RowState.latest
          : _RowState.waiting;
      rows.add(
        _MessageRow(
          key: _keys[i],
          index: i,
          total: s.length,
          message: m,
          state: state,
          width: widget.width,
          radiusUsed: s.usesRadius,
          reduceMotion: reduceMotion,
        ),
      );
      if (m.milestone != null) {
        rows.add(
          _MilestoneRow(
            milestone: m.milestone!,
            text: m.milestoneText ?? m.milestone!.label,
            reached: i < c.shown,
          ),
        );
      }
    }
    // The shared failure marker (spec 42): the band after the last message
    // of an exchange that broke, where the milestones would have been.
    if (s.failed && s.faultNote != null) {
      rows.add(
        LadderStoppedBand(text: s.faultNote!, reached: c.shown >= s.length),
      );
    }

    return Semantics(
      container: true,
      label:
          'Ladder: ${c.shown} of ${s.length} messages sent. Each sent message '
          'is listed below with its step number.',
      child: SizedBox(
        height: widget.height,
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            key: EapLadderStage.ladderScrollKey,
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

enum _RowState { sent, latest, waiting }

double _laneX(LadderLane lane, double width) =>
    width * _kLaneFractions[lane.index];

/// A phase heading across the ladder. Always visible.
class _PhaseRow extends StatelessWidget {
  const _PhaseRow({
    required this.label,
    required this.width,
    required this.radiusUsed,
  });

  final String label;
  final double width;
  final bool radiusUsed;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return CustomPaint(
      painter: _LanesPainter(
        width: width,
        color: colors.border,
        radiusUsed: radiusUsed,
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

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    super.key,
    required this.index,
    required this.total,
    required this.message,
    required this.state,
    required this.width,
    required this.radiusUsed,
    required this.reduceMotion,
  });

  final int index;
  final int total;
  final LadderMessage message;
  final _RowState state;
  final double width;
  final bool radiusUsed;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final LadderMessage m = message;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final double band = _kArrowBand * sc.text;
    final bool visible = state != _RowState.waiting;
    final Color legColor = ladderLegColor(m.leg, isLight: colors.isLight);
    final double fromX = _laneX(m.from, width);
    final double toX = _laneX(m.to, width);
    final double left = (fromX < toX ? fromX : toX) + AppSpacing.xxs;
    final double right = width - (fromX > toX ? fromX : toX) + AppSpacing.xxs;
    final double markSize = sc.markerSize(16);

    final Widget labels = Visibility(
      visible: visible,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Never breaks inside a word (Keith, 2026-09-29): shrinks instead.
          ElWholeWordText(
            m.label,
            textAlign: TextAlign.center,
            style: text.labelMedium?.copyWith(
              color: legColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (m.detail != null)
            ElWholeWordText(
              m.detail!,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );

    final Widget row = Container(
      decoration: BoxDecoration(
        // The latest message: a raised surface on dark; on light, where
        // surface2 is white like the card, the canvas gray.
        color: state == _RowState.latest
            ? (colors.isLight ? colors.surface0 : colors.surface2)
            : null,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: TweenAnimationBuilder<double>(
        key: ValueKey<String>('arrow-$index-${state.name}'),
        tween: Tween<double>(
          begin: state == _RowState.latest && !reduceMotion ? 0 : 1,
          end: 1,
        ),
        duration: AppMotion.slow,
        curve: AppMotion.standardEase,
        builder: (BuildContext context, double progress, Widget? child) {
          return CustomPaint(
            painter: _LanesPainter(
              width: width,
              color: colors.border,
              radiusUsed: radiusUsed,
              stroke: sc.strokeWidth(1.5),
              arrow: _ArrowPainter(
                color: visible ? legColor : colors.border,
                // A lost message is dashed on either leg and stops in a gap
                // with no head: it never arrives.
                dashed: m.leg == LadderLeg.wire || m.lost,
                fromX: fromX,
                toX: toX,
                y: null,
                stroke: sc.strokeWidth(state == _RowState.latest ? 3 : 2),
                progress: m.lost ? progress * kLostReach : progress,
                head: m.lost ? 0 : sc.markerSize(8),
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
            if (visible && m.marksFailure)
              positionedLadderMark(
                lost: m.lost,
                fromX: fromX,
                toX: toX,
                rowWidth: width,
                band: band,
                iconSize: markSize,
                child: m.lost
                    ? const LadderLostMark()
                    : const LadderFailureMark(),
              ),
            Positioned(
              left: 0,
              bottom: 0,
              width: _laneX(LadderLane.client, width) - AppSpacing.xs,
              child: Visibility(
                visible: visible,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                // The step number, with the tunnel lock beside it: the
                // gutter left of the client lane is free on every row, so
                // the lock does not take width from the frame name. Scaled
                // down rather than overflow on a narrow phone (a lock and a
                // two-digit step at 360 px overflowed by a rounding hair in
                // v1.11.0), as the Join and Roam gutter already is.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (m.tunneled) ...<Widget>[
                        Icon(
                          Icons.lock_outline_rounded,
                          size: sc.markerSize(16),
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                      ],
                      Text(
                        '${index + 1}',
                        style: mono.inlineCode.copyWith(
                          fontSize: AppTextSize.caption,
                          color: state == _RowState.latest
                              ? colors.textAccent
                              : colors.textTertiary,
                          fontWeight: state == _RowState.latest
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!visible) return ExcludeSemantics(child: row);
    final String contents = m.contents.isEmpty ? '' : ', ${m.contents}';
    final String mark = m.lost
        ? ' No answer.'
        : m.failure
        ? ' Failure.'
        : '';
    return Semantics(
      label:
          'Step ${index + 1} of $total, ${m.leg.label.toLowerCase()}, '
          '${m.from.label} to ${m.to.label}: ${m.label}$contents. '
          '${m.description}$mark',
      excludeSemantics: true,
      child: row,
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
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
                : Icons.verified_user_rounded,
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
      // Held back until reached; the space stays so the ladder does not
      // jump when it appears.
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

/// Vertical lane lines through a row, with an optional arrow on top.
class _LanesPainter extends CustomPainter {
  _LanesPainter({
    required this.width,
    required this.color,
    required this.radiusUsed,
    this.stroke = 1.5,
    this.arrow,
  });

  final double width;
  final Color color;
  final bool radiusUsed;
  final double stroke;
  final _ArrowPainter? arrow;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint lane = Paint()
      ..color = color
      ..strokeWidth = stroke;
    for (final LadderLane l in LadderLane.values) {
      final double x = _laneX(l, width);
      if (l == LadderLane.radius && !radiusUsed) {
        // Unused lane: dotted.
        for (double y = 0; y < size.height; y += 8) {
          canvas.drawLine(Offset(x, y), Offset(x, y + 2), lane);
        }
      } else {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), lane);
      }
    }
    arrow?.paint(canvas, size);
  }

  @override
  bool shouldRepaint(_LanesPainter old) =>
      old.width != width ||
      old.color != color ||
      old.radiusUsed != radiusUsed ||
      old.stroke != stroke ||
      old.arrow?.progress != arrow?.progress ||
      old.arrow?.color != arrow?.color ||
      old.arrow?.stroke != arrow?.stroke ||
      old.arrow?.dashed != arrow?.dashed ||
      old.arrow?.head != arrow?.head;
}

/// One arrow from [fromX] to [toX]. [y] null draws it in the arrow band at
/// the bottom of the row. [progress] 0 to 1 draws it in from its source.
class _ArrowPainter extends CustomPainter {
  _ArrowPainter({
    required this.color,
    required this.dashed,
    required this.fromX,
    required this.toX,
    required this.y,
    required this.stroke,
    required this.progress,
    this.head = 8,
    this.band = _kArrowBand,
  });

  final Color color;
  final bool dashed;
  final double fromX;
  final double toX;
  final double? y;
  final double stroke;
  final double progress;

  /// Arrowhead length, px.
  final double head;

  /// Height of the arrow band at the bottom of the row, px.
  final double band;

  @override
  void paint(Canvas canvas, Size size) {
    final double yy = y ?? size.height - band / 2;
    final double dir = toX >= fromX ? 1 : -1;
    // Stop short of the lane so the head's tip touches it.
    final double endX = fromX + (toX - fromX) * progress;
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final double shaftEnd = endX - dir * head * 0.6;
    if (dashed) {
      const double dash = 6;
      const double gap = 4;
      double x = fromX;
      while ((shaftEnd - x) * dir > 0) {
        final double next = x + dir * dash;
        final double clipped = (shaftEnd - next) * dir < 0 ? shaftEnd : next;
        canvas.drawLine(Offset(x, yy), Offset(clipped, yy), p);
        x = next + dir * gap;
      }
    } else if ((shaftEnd - fromX) * dir > 0) {
      canvas.drawLine(Offset(fromX, yy), Offset(shaftEnd, yy), p);
    }
    if (progress <= 0) return;
    final Path tip = Path()
      ..moveTo(endX, yy)
      ..lineTo(endX - dir * head, yy - head / 2)
      ..lineTo(endX - dir * head, yy + head / 2)
      ..close();
    canvas.drawPath(
      tip,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.color != color ||
      old.progress != progress ||
      old.stroke != stroke ||
      old.head != head ||
      old.band != band ||
      old.fromX != fromX ||
      old.toX != toX;
}

// ── Caption ─────────────────────────────────────────────────────────────────

class _CaptionCard extends StatelessWidget {
  const _CaptionCard({required this.controller, this.presenter = false});

  final EapLadderController controller;

  /// Presenter: "Step n of N" is the headline, and the prompt is short.
  final bool presenter;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final LadderMessage? m = controller.current;
    final int n = controller.sequence.length;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final List<Widget> children;
    if (m == null) {
      children = <Widget>[
        const ElSectionLabel('Ready'),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          presenter
              ? 'Press Play or Step to send the first of $n messages.'
              : 'Press Play or Step to send the first of $n messages. Each '
                    'arrow names its frame; the caption here says which leg '
                    'it crossed and why it is there.',
          style: text.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
      ];
    } else {
      final Color legColor = ladderLegColor(m.leg, isLight: colors.isLight);
      final String contents = m.contents;
      children = <Widget>[
        if (presenter)
          Text(
            'Step ${controller.shown} of $n',
            style: sc
                .headlineStyle(mono.outputLarge)
                .copyWith(color: colors.textAccent),
          )
        else
          ElSectionLabel('Step ${controller.shown} of $n'),
        const SizedBox(height: AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _Chip(label: m.leg.label, color: legColor),
            _Chip(label: m.kind.label, color: colors.textSecondary),
            Text(
              '${m.from.label} to ${m.to.label}',
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
        if (contents.isNotEmpty)
          Text(
            contents,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          m.description,
          style: text.bodyMedium?.copyWith(color: colors.textPrimary),
        ),
        if (m.marksFailure) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          LadderFailureCaptionLine(lost: m.lost),
        ],
        if (controller.atEnd &&
            controller.sequence.failed &&
            controller.sequence.faultNote != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          LadderStoppedCaption(
            faultNote: controller.sequence.faultNote!,
            helpDesk: controller.sequence.helpDesk,
          ),
        ],
        if (m.milestoneText != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ExcludeSemantics(
                child: Icon(
                  m.milestone == LadderMilestone.keysAvailable
                      ? Icons.key_rounded
                      : Icons.verified_user_rounded,
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

/// A small outlined label.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

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

/// Presenter only: the ladder's size and cost in one line of numbers, so a
/// class can flip methods and compare without opening the readouts.
class _Counts extends StatelessWidget {
  const _Counts({required this.controller});

  final EapLadderController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final LadderSequence s = controller.sequence;
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
          '${s.airCount} frames',
          color: ladderLegColor(LadderLeg.air, isLight: colors.isLight),
        ),
        stat(
          'On the wire',
          s.usesRadius ? '${s.wireCount} RADIUS' : 'none',
          color: s.usesRadius
              ? ladderLegColor(LadderLeg.wire, isLight: colors.isLight)
              : null,
        ),
        stat('Round trips', '${s.radiusRoundTrips}'),
        stat(
          s.failed ? 'Until it stops, est.' : 'After the scan, est.',
          formatLadderMs(s.estimatedMs),
        ),
      ],
    );
  }
}
