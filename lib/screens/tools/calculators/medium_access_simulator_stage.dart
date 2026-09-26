// Stage for the Medium Access Simulator: the lane timeline, its worded status
// line and its legend, over one MediumAccessSimulatorController.
//
// Two arrangements:
//   - phone / desktop screen: the timeline card exactly as before the
//     2026-09-26 split (fixed 32 px lanes in a horizontal scroll);
//   - presenter (PresenterMode.isActive): the card fills the stage box. The
//     lanes grow to fill the height (up to 2.5x with few stations, never
//     below 1x), the time axis widens with them (up to 2x) so the backoff
//     counts inside each slot stay readable from the back of the room, lane
//     labels carry each station's contention window, and a results strip
//     (throughput, busy, collisions) runs underneath.
//
// View-local state lives HERE, not in the controller: the horizontal
// ScrollController (a controller attaches to one scroll view, and the phone
// screen stays mounted under the presenter) and the TextPainter cache (it
// depends on this view's theme and text scale).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/medium_access_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'medium_access_simulator_controller.dart';
import 'medium_access_simulator_parts.dart';
import 'medium_access_timeline.dart';

typedef _C = MediumAccessSimulatorController;

/// Largest lane and time scale in presenter mode.
const double _kMaxLaneScale = 2.5;
const double _kMaxTimeScale = 2;

class MediumAccessSimulatorStage extends StatefulWidget {
  const MediumAccessSimulatorStage({super.key, required this.controller});

  final MediumAccessSimulatorController controller;

  @override
  State<MediumAccessSimulatorStage> createState() =>
      _MediumAccessSimulatorStageState();
}

class _MediumAccessSimulatorStageState
    extends State<MediumAccessSimulatorStage> {
  final ScrollController _scroll = ScrollController();
  final TimelineLabelCache _labels = TimelineLabelCache();
  int? _lastNow;
  TimelineZoom? _lastZoom;
  MediumAccessEngine? _lastEngine;

  _C get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    _scheduleFollow();
  }

  @override
  void didUpdateWidget(MediumAccessSimulatorStage old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Theme or text-scale changes invalidate laid-out labels.
    _labels.clear();
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _scroll.dispose();
    super.dispose();
  }

  /// Keep "now" in view when the clock, the zoom or the run changes (as the
  /// screen did before the split); a speed or play toggle leaves a paused
  /// look-back where it is.
  void _onChange() {
    final int now = _c.engine.nowUs;
    if (now != _lastNow || _c.zoom != _lastZoom || _c.engine != _lastEngine) {
      _scheduleFollow();
    }
    setState(() {});
  }

  void _scheduleFollow() {
    _lastNow = _c.engine.nowUs;
    _lastZoom = _c.zoom;
    _lastEngine = _c.engine;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ScrollPosition p = _scroll.position;
      if (p.pixels != p.maxScrollExtent) p.jumpTo(p.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!PresenterMode.isActive(context)) return _card(context, null);
    final MaUi ui = MaUi.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: _card(context, PresenterMode.scaleOf(context))),
        const SizedBox(height: AppSpacing.sm),
        ui.card(child: _ResultsStrip(controller: _c)),
      ],
    );
  }

  /// The timeline card. [presenter] is null on the phone.
  Widget _card(BuildContext context, PresenterScale? presenter) {
    final MaUi ui = MaUi.of(context);
    final AppColorScheme colors = ui.colors;
    final int n = _c.engine.config.stations.length;
    final String status = _c.statusLine();
    final bool presenting = presenter != null;

    final Widget header = Row(
      crossAxisAlignment: presenting
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        ui.sectionTitle('Timeline'),
        if (presenting) ...<Widget>[
          const SizedBox(width: AppSpacing.md),
          // The zoom lives here in presenter mode, over what it changes.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.textScalerOf(context).scale(300),
            ),
            child: AppToggle<TimelineZoom>(
              label: 'Zoom',
              value: _c.zoom,
              expand: true,
              items: <AppToggleItem<TimelineZoom>>[
                for (final TimelineZoom z in TimelineZoom.values) (z, z.label),
              ],
              onChanged: _c.setZoom,
            ),
          ),
        ],
        const Spacer(),
        Text(
          't = ${_C.fmtMs(_c.engine.nowUs)}',
          style: presenting
              ? presenter
                    .headlineStyle(ui.mono.inlineCode)
                    .copyWith(color: colors.textAccent)
              : ui.mono.inlineCode.copyWith(color: colors.textAccent),
        ),
      ],
    );
    final Widget statusText = ExcludeSemantics(
      child: Text(
        status,
        style: ui.text.bodySmall?.copyWith(color: colors.textSecondary),
      ),
    );

    if (!presenting) {
      return ui.card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header,
            const SizedBox(height: AppSpacing.xs),
            _timeline(context, n, status, 1, 1, PresenterScale.normal),
            const SizedBox(height: AppSpacing.xs),
            statusText,
            const SizedBox(height: AppSpacing.sm),
            _Legend(controller: _c),
          ],
        ),
      );
    }
    return ui.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          header,
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                // Lanes fill the height the status line and legend leave.
                final double k = (box.maxHeight / TimelineGeometry.height(n))
                    .clamp(1.0, _kMaxLaneScale);
                final double t = k.clamp(1.0, _kMaxTimeScale);
                return Align(
                  alignment: Alignment.topCenter,
                  child: _timeline(context, n, status, k, t, presenter),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          statusText,
          const SizedBox(height: AppSpacing.sm),
          _Legend(controller: _c),
        ],
      ),
    );
  }

  Widget _timeline(
    BuildContext context,
    int n,
    String status,
    double k,
    double t,
    PresenterScale scale,
  ) {
    final MaUi ui = MaUi.of(context);
    final AppColorScheme colors = ui.colors;
    final bool presenting = scale.isPresenting;
    final TextStyle laneLabel = ui.labelStyle;
    final TextStyle blockLabel = ui.mono.inlineCode.copyWith(
      fontSize: scale.paintFont(AppTextSize.caption),
      height: 1.2,
    );
    final List<StationSnapshot> stations = _c.engine.stations;
    final double height = TimelineGeometry.height(n, k);
    final double laneH = TimelineGeometry.laneHeight * k;
    // Room for a second label line (the contention window) in tall lanes.
    final double lineH =
        MediaQuery.textScalerOf(context).scale(laneLabel.fontSize ?? 12) * 1.3;
    final bool showCw = presenting && laneH >= 2 * lineH;
    final double labelW = presenting
        ? MediaQuery.textScalerOf(context).scale(AppSpacing.xxl) + AppSpacing.md
        : AppSpacing.xxl;

    Widget lane(String label, {String? second}) => Container(
      height: laneH,
      margin: const EdgeInsets.only(bottom: TimelineGeometry.laneGap),
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: laneLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (second != null)
            Text(
              second,
              style: ui.mono.inlineCode.copyWith(
                fontSize: laneLabel.fontSize,
                color: colors.textTertiary,
              ),
              maxLines: 1,
            ),
        ],
      ),
    );

    return Semantics(
      container: true,
      label:
          'Timeline of the last ${_C.fmtMs(_c.zoom.windowUs)}, one lane '
          'for the medium and one per station. $status',
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ExcludeSemantics(
              child: SizedBox(
                width: labelW,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    lane('Medium'),
                    for (final StationSnapshot s in stations)
                      lane(
                        '${s.letter} · ${_c.acShort(s)}',
                        second: showCw
                            ? 'CW ${s.cw}'
                                  '${_c.config.hiddenNode ? ', grp ${s.index.isEven ? 1 : 2}' : ''}'
                            : null,
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: _c.zoom.canvasWidth * t,
                    height: height,
                    child: CustomPaint(
                      painter: MediumAccessTimelinePainter(
                        engine: _c.engine,
                        nowUs: _c.engine.nowUs,
                        zoom: _c.zoom,
                        colors: colors,
                        labelStyle: blockLabel,
                        monoStyle: blockLabel,
                        labels: _labels,
                        scroll: _scroll,
                        legacyDcf: _c.dcf,
                        laneScale: k,
                        timeScale: t,
                        strokeScale: scale.stroke,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.controller});

  final MediumAccessSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final MaUi ui = MaUi.of(context);
    final AppColorScheme colors = ui.colors;
    final List<(BlockStyle, String)> items = <(BlockStyle, String)>[
      (BlockStyle.wait, controller.dcf ? 'DIFS wait' : 'AIFS wait'),
      (BlockStyle.eifs, 'EIFS wait (after a garbled frame)'),
      (BlockStyle.backoff, 'Backoff slot, with its count'),
      (BlockStyle.frozen, 'Frozen count (medium busy)'),
      (BlockStyle.nav, 'NAV set by RTS or CTS'),
      (BlockStyle.data, 'Data frame (letter = sender)'),
      (BlockStyle.control, 'RTS or CTS'),
      (BlockStyle.ack, 'ACK: delivered'),
      (BlockStyle.lost, 'Lost: collision, no ACK'),
      (BlockStyle.awaiting, 'Waiting for a response'),
    ];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        for (final (BlockStyle style, String label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ExcludeSemantics(
                child: SizedBox(
                  width: AppSpacing.md,
                  height: AppSpacing.sm,
                  child: CustomPaint(
                    painter: MaSwatchPainter(style: style, colors: colors),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: ui.text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
      ],
    );
  }
}

/// Presenter results: the numbers the timeline adds up to, in one strip.
class _ResultsStrip extends StatelessWidget {
  const _ResultsStrip({required this.controller});

  final MediumAccessSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final MaUi ui = MaUi.of(context);
    final AppColorScheme colors = ui.colors;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final MediumAccessStats s = controller.engine.stats;
    final bool fresh = s.elapsedUs == 0;
    String v(String value) => fresh ? '--' : value;

    Widget block(String label, String value, {bool headline = false}) =>
        MergeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: ui.labelStyle),
              Text(
                value,
                style: headline
                    ? scale
                          .headlineStyle(ui.mono.outputLarge)
                          .copyWith(color: colors.textAccent)
                    : ui.mono.outputMedium.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        );

    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: <Widget>[
        block(
          'Delivered throughput',
          v('${s.throughputMbps.toStringAsFixed(1)} Mbps'),
          headline: true,
        ),
        block(
          'Airtime busy',
          v('${s.utilizationPercent.toStringAsFixed(1)} %'),
        ),
        block(
          'Collision rate',
          v(
            '${s.collisionPercent.toStringAsFixed(1)} % '
            '(${s.failedAttempts} of ${s.attempts})',
          ),
        ),
        block('Delivered / dropped', v('${s.delivered} / ${s.dropped}')),
        if (fresh)
          Text(
            'Press Play (Space) or Step (Right arrow) to start the clock.',
            style: ui.text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
      ],
    );
  }
}
