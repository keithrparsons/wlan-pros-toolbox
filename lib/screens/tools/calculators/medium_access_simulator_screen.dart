// Medium Access Simulator (Wi-Fi Lab, 2026-09-25) — medium-access-simulator.
//
// Watch 802.11 contention happen one 9 us slot at a time: stations wait out
// AIFS, count down a random backoff, freeze when someone else takes the
// medium, collide when two counts hit zero together, and double their
// contention window after each loss. Toggle EDCA to see voice win, hidden node
// to see collisions no one could hear coming, and RTS/CTS to see them go away.
//
// Built clean-room from IEEE 802.11 clause 10 (DCF/EDCA) and clause 17 (OFDM
// timing). Spec: myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 02-medium-access-simulator.md. The engine is pure Dart and lives in
// lib/services/wifi_lab/medium_access_engine.dart; this screen only drives it
// (a Ticker) and draws it (MediumAccessTimelinePainter).
//
// THEME: context.colors only (dark §8 / light §8.20). Stations are told apart
// by lane and letter, never by hue (§8.15). Status hues are verdicts only
// (§8.13): danger on a lost frame, success on an ACK. Numerics in DM Mono.
//
// States (SOP-007 §5):
//   - fresh     -> clock at 0, paused, stats read "Press Play or Step"
//   - running   -> Ticker advances whole slots at the chosen speed
//   - paused    -> clock frozen; the timeline can be scrolled back
//   - disabled  -> Add at 10 stations, Remove at 1, access-category selects
//                  in Legacy DCF, hidden node with one station
//   - reduced motion -> starts paused (it always does); Step works; the
//                  timeline jumps to "now" rather than animating
//   - interactive -> every control is a themed Material control with the
//                  global focus ring

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/medium_access_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/tool_help_footer.dart';
import '../labeled_field.dart';
import 'medium_access_timeline.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kMediumAccessToolId = 'medium-access-simulator';

/// Simulated air time per real second.
enum SimSpeed {
  crawl('0.1 ms per second', 100),
  slow('0.5 ms per second', 500),
  normal('2 ms per second', 2000),
  fast('20 ms per second', 20000),
  fastest('200 ms per second', 200000);

  const SimSpeed(this.label, this.usPerSecond);

  final String label;
  final int usPerSecond;
}

/// Offered-load choices; null is "always has a frame".
const List<double?> _kLoads = <double?>[null, 50, 200, 500, 1000, 2000];

const List<int> _kFrameSizes = <int>[100, 500, 1000, 1500, 2304];

/// Slots the Ticker may advance in one frame, so a stalled frame cannot turn
/// into a long synchronous catch-up.
const int _kMaxSlotsPerFrame = 3000;

class MediumAccessSimulatorScreen extends StatefulWidget {
  const MediumAccessSimulatorScreen({super.key, this.seed = 1});

  /// Seed for every random draw. Same seed, same run.
  final int seed;

  @override
  State<MediumAccessSimulatorScreen> createState() =>
      _MediumAccessSimulatorScreenState();
}

class _MediumAccessSimulatorScreenState
    extends State<MediumAccessSimulatorScreen>
    with SingleTickerProviderStateMixin {
  // ── Configuration ──────────────────────────────────────────────────────────
  List<StationConfig> _stations = const <StationConfig>[
    StationConfig(),
    StationConfig(),
    StationConfig(),
  ];
  AccessMode _mode = AccessMode.dcf;
  bool _hidden = false;
  bool _rts = false;
  int _frameBytes = 1500;
  int _rateMbps = 54;

  // ── Run state ──────────────────────────────────────────────────────────────
  late MediumAccessEngine _engine;
  late final Ticker _ticker;
  bool _playing = false;
  Duration _lastElapsed = Duration.zero;
  double _carryUs = 0;
  SimSpeed _speed = SimSpeed.crawl;
  TimelineZoom _zoom = TimelineZoom.slots;

  final ScrollController _timelineScroll = ScrollController();
  final TimelineLabelCache _labels = TimelineLabelCache();

  @override
  void initState() {
    super.initState();
    _engine = _buildEngine();
    _ticker = createTicker(_onTick);
    _scheduleFollow();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _timelineScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Theme or text-scale changes invalidate laid-out labels.
    _labels.clear();
  }

  MediumAccessConfig get _config => MediumAccessConfig(
    stations: _stations,
    mode: _mode,
    hiddenNode: _hidden && _stations.length > 1,
    rtsCts: _rts,
    frameBytes: _frameBytes,
    phyRateMbps: _rateMbps,
    seed: widget.seed,
  );

  MediumAccessEngine _buildEngine() => MediumAccessEngine(_config);

  // ── Transport ──────────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    final Duration dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    _carryUs += dt.inMicroseconds / 1e6 * _speed.usPerSecond;
    final int slots = (_carryUs / OfdmTiming.slotUs).floor();
    if (slots <= 0) return;
    _carryUs -= slots * OfdmTiming.slotUs;
    setState(() {
      _engine.advanceSlots(slots.clamp(1, _kMaxSlotsPerFrame));
    });
    _scheduleFollow();
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _lastElapsed = Duration.zero;
      _carryUs = 0;
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  void _step() {
    setState(() => _engine.stepSlot());
    _scheduleFollow();
  }

  /// Rebuild the run from the current configuration, keeping play state.
  void _reset() {
    setState(() {
      _engine = _buildEngine();
      _carryUs = 0;
    });
    _scheduleFollow();
  }

  void _reconfigure(VoidCallback change) {
    change();
    _reset();
  }

  /// Keep "now" (the right edge of the canvas) in view.
  void _scheduleFollow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_timelineScroll.hasClients) return;
      final ScrollPosition p = _timelineScroll.position;
      if (p.pixels != p.maxScrollExtent) p.jumpTo(p.maxScrollExtent);
    });
  }

  // ── Copy ───────────────────────────────────────────────────────────────────

  String? _copyText() {
    final MediumAccessStats s = _engine.stats;
    if (s.elapsedUs == 0) return null;
    final StringBuffer b = StringBuffer()
      ..writeln('Medium Access Simulator (WLAN Pros Toolbox)')
      ..writeln(
        'Mode: ${_mode == AccessMode.dcf ? 'Legacy DCF' : 'EDCA'}; '
        'hidden node ${_config.hiddenNode ? 'on' : 'off'}; '
        'RTS/CTS ${_rts ? 'on' : 'off'}; '
        '$_frameBytes bytes at $_rateMbps Mbps',
      )
      ..writeln('Simulated time: ${_fmtMs(s.elapsedUs)}')
      ..writeln(
        'Delivered throughput: ${s.throughputMbps.toStringAsFixed(1)} Mbps',
      )
      ..writeln('Airtime busy: ${s.utilizationPercent.toStringAsFixed(1)} %')
      ..writeln(
        'Collision rate: ${s.collisionPercent.toStringAsFixed(1)} % '
        '(${s.failedAttempts} of ${s.attempts} accesses)',
      );
    for (final StationSnapshot st in _engine.stations) {
      b.writeln(
        'Station ${st.letter} (${_acLabel(st)}): CW ${st.cw}, '
        'delivered ${st.delivered}, dropped ${st.dropped}',
      );
    }
    return b.toString().trimRight();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medium Access Simulator'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _copyText)],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.contentMaxWidth,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    edge,
                    AppSpacing.sm,
                    edge,
                    edge + AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _transportCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _timelineCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _statsCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _stationsCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _mediumCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _aboutCard(text),
                      ToolHelpFooter(toolId: kMediumAccessToolId),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Transport card ─────────────────────────────────────────────────────────

  Widget _transportCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final bool reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Only one station talks at a time. Each waits for a quiet '
            'medium, counts down a random number of 9 µs slots, and '
            'transmits at zero. Two zeros in the same slot is a collision.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: Semantics(
              button: true,
              label: _playing ? 'Pause simulation' : 'Play simulation',
              excludeSemantics: true,
              child: FilledButton.icon(
                onPressed: _togglePlay,
                icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(_playing ? 'Pause' : 'Play'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
                  textStyle: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: _outlineButton(
                  text,
                  icon: Icons.skip_next_rounded,
                  label: 'Step 1 slot',
                  semanticLabel: 'Step one 9 microsecond slot',
                  onPressed: _step,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _outlineButton(
                  text,
                  icon: Icons.restart_alt_rounded,
                  label: 'Reset',
                  semanticLabel: 'Reset the simulation to time zero',
                  onPressed: _reset,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _labeledSelect<SimSpeed>(
            label: 'Speed (air time per real second)',
            value: _speed,
            items: <AppSelectItem<SimSpeed>>[
              for (final SimSpeed s in SimSpeed.values) (s, s.label),
            ],
            onChanged: (SimSpeed s) => setState(() => _speed = s),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<TimelineZoom>(
            label: 'Zoom',
            value: _zoom,
            expand: true,
            items: <AppToggleItem<TimelineZoom>>[
              for (final TimelineZoom z in TimelineZoom.values) (z, z.label),
            ],
            onChanged: (TimelineZoom z) {
              setState(() => _zoom = z);
              _scheduleFollow();
            },
          ),
          if (reducedMotion) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Reduced motion is on. The simulation waits for you: use Step '
              'to move one slot at a time, or Play at the slowest speed.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _outlineButton(
    TextTheme text, {
    required IconData icon,
    required String label,
    required String semanticLabel,
    required VoidCallback? onPressed,
  }) {
    final AppColorScheme colors = context.colors;
    final bool enabled = onPressed != null;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      enabled: enabled,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textAccent,
          disabledForegroundColor: colors.textDisabled,
          side: BorderSide(
            color: enabled ? colors.borderStrong : colors.disabledFill,
            width: colors.isLight ? 1.5 : 1,
          ),
          minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ── Timeline card ──────────────────────────────────────────────────────────

  Widget _timelineCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final int n = _engine.config.stations.length;
    final TextStyle laneLabel =
        text.labelMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle blockLabel = mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
      height: 1.2,
    );
    final List<StationSnapshot> stations = _engine.stations;
    final String status = _statusLine(stations);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              _sectionTitle(text, 'Timeline'),
              const Spacer(),
              Text(
                't = ${_fmtMs(_engine.nowUs)}',
                style: mono.inlineCode.copyWith(color: colors.textAccent),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            container: true,
            label:
                'Timeline of the last ${_fmtMs(_zoom.windowUs)}, one lane '
                'for the medium and one per station. $status',
            child: SizedBox(
              height: TimelineGeometry.height(n),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ExcludeSemantics(
                    child: SizedBox(
                      width: AppSpacing.xxl,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _laneLabel('Medium', laneLabel),
                          for (final StationSnapshot s in stations)
                            _laneLabel(
                              '${s.letter} · ${_acShort(s)}',
                              laneLabel,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: _timelineScroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _timelineScroll,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: _zoom.canvasWidth,
                          height: TimelineGeometry.height(n),
                          child: CustomPaint(
                            painter: MediumAccessTimelinePainter(
                              engine: _engine,
                              nowUs: _engine.nowUs,
                              zoom: _zoom,
                              colors: colors,
                              labelStyle: blockLabel,
                              monoStyle: blockLabel,
                              labels: _labels,
                              scroll: _timelineScroll,
                              legacyDcf: _mode == AccessMode.dcf,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ExcludeSemantics(
            child: Text(
              status,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _legend(text),
        ],
      ),
    );
  }

  Widget _laneLabel(String label, TextStyle style) {
    return Container(
      height: TimelineGeometry.laneHeight,
      margin: const EdgeInsets.only(bottom: TimelineGeometry.laneGap),
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _legend(TextTheme text) {
    final AppColorScheme colors = context.colors;
    final List<(BlockStyle, String)> items = <(BlockStyle, String)>[
      (BlockStyle.wait, _mode == AccessMode.dcf ? 'DIFS wait' : 'AIFS wait'),
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
                    painter: _SwatchPainter(style: style, colors: colors),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
      ],
    );
  }

  /// A one-line, worded account of what every lane is doing right now.
  String _statusLine(List<StationSnapshot> stations) {
    if (_engine.nowUs == 0) {
      return 'Paused at time zero. Press Play, or Step to move one slot.';
    }
    final Map<int, LaneSegment> latest = <int, LaneSegment>{};
    for (final LaneSegment s in _engine.segments.reversed) {
      if (s.endUs < _engine.nowUs) continue;
      latest.putIfAbsent(s.lane, () => s);
      if (latest.length == stations.length) break;
    }
    final List<String> parts = <String>[];
    final List<AirFrame> air = _engine.onAir;
    if (air.isEmpty) {
      parts.add('Medium idle.');
    } else {
      final String who = air
          .map(
            (AirFrame f) => f.fromAp
                ? 'AP sending ${f.kind == FrameKind.ack ? 'ACK' : 'CTS'}'
                : '${stationLetter(f.source)} sending '
                      '${f.kind == FrameKind.rts ? 'RTS' : 'data'}',
          )
          .join(', ');
      final bool clash =
          air.where((AirFrame f) => !f.fromAp).length > 1 ||
          air.any((AirFrame f) => f.corruptedAtAp);
      parts.add('Medium: $who${clash ? ', collision at the AP' : ''}.');
    }
    for (final StationSnapshot s in stations) {
      final LaneSegment? seg = latest[s.index];
      parts.add('${s.letter}: ${_describe(s, seg)}.');
    }
    return parts.join(' ');
  }

  String _describe(StationSnapshot s, LaneSegment? seg) {
    switch (s.phase) {
      case StationPhase.noFrame:
        return 'no frame queued';
      case StationPhase.transmitting:
        return 'transmitting';
      case StationPhase.awaitResponse:
        return _rts ? 'waiting for a response' : 'waiting for ACK';
      case StationPhase.contending:
        if (seg == null) return 'backoff ${s.backoff ?? 0}';
        switch (seg.activity) {
          case LaneActivity.aifs:
            return 'in ${_mode == AccessMode.dcf ? 'DIFS' : 'AIFS'}';
          case LaneActivity.eifs:
            return 'in EIFS';
          case LaneActivity.frozen:
            return 'frozen at ${seg.count}';
          case LaneActivity.nav:
            return 'deferring to NAV at ${seg.count}';
          case LaneActivity.backoff:
          case LaneActivity.transmit:
          case LaneActivity.awaitResponse:
            return 'backoff ${s.backoff ?? 0}';
        }
    }
  }

  // ── Stats card ─────────────────────────────────────────────────────────────

  Widget _statsCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final MediumAccessStats s = _engine.stats;
    final bool fresh = s.elapsedUs == 0;
    String v(String value) => fresh ? '--' : value;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _sectionTitle(text, 'Results'),
          const SizedBox(height: AppSpacing.xs),
          if (fresh)
            Text(
              'Press Play or Step to start the clock.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            )
          else
            Text(
              'Over ${_fmtMs(s.elapsedUs)} of simulated air time.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text('Delivered throughput', style: _labelStyle(text)),
          Text(
            v('${s.throughputMbps.toStringAsFixed(1)} Mbps'),
            style: mono.outputLarge.copyWith(color: colors.textAccent),
          ),
          const SizedBox(height: AppSpacing.xs),
          _statRow(
            text,
            mono,
            'Airtime busy',
            v('${s.utilizationPercent.toStringAsFixed(1)} %'),
          ),
          _statRow(
            text,
            mono,
            'Collision rate',
            v(
              '${s.collisionPercent.toStringAsFixed(1)} % '
              '(${s.failedAttempts} of ${s.attempts})',
            ),
          ),
          _statRow(
            text,
            mono,
            'Delivered / dropped',
            v('${s.delivered} / ${s.dropped}'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Average access delay', style: _labelStyle(text)),
          const SizedBox(height: AppSpacing.xxs),
          ..._delayRows(text, mono, s),
          const SizedBox(height: AppSpacing.sm),
          Text('Per station', style: _labelStyle(text)),
          const SizedBox(height: AppSpacing.xxs),
          _stationTable(text, mono),
        ],
      ),
    );
  }

  List<Widget> _delayRows(
    TextTheme text,
    AppMonoText mono,
    MediumAccessStats s,
  ) {
    String fmt(AccessDelayStat? d) {
      final double? us = d?.meanUs;
      if (us == null) return 'no deliveries yet';
      return '${(us / 1000).toStringAsFixed(2)} ms';
    }

    if (_mode == AccessMode.dcf) {
      int frames = 0, total = 0;
      for (final AccessDelayStat d in s.accessDelay.values) {
        frames += d.frames;
        total += d.totalUs;
      }
      return <Widget>[
        _statRow(
          text,
          mono,
          'All stations (DCF)',
          fmt(AccessDelayStat(frames: frames, totalUs: total)),
        ),
      ];
    }
    final List<AccessCategory> inUse = <AccessCategory>[
      for (final AccessCategory ac in AccessCategory.values)
        if (_stations.any((StationConfig c) => c.accessCategory == ac)) ac,
    ];
    return <Widget>[
      for (final AccessCategory ac in inUse)
        _statRow(text, mono, ac.label, fmt(s.accessDelay[ac])),
    ];
  }

  Widget _stationTable(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final TextStyle head = _labelStyle(text);
    final TextStyle cell = mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
      color: colors.textPrimary,
    );
    Widget pad(Widget w) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: w,
    );
    return Table(
      columnWidths: const <int, TableColumnWidth>{
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.3),
        4: FlexColumnWidth(1.1),
      },
      children: <TableRow>[
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          children: <Widget>[
            for (final String h in <String>[
              'Station',
              'CW',
              'Backoff',
              'Delivered',
              'Dropped',
            ])
              pad(Text(h, style: head)),
          ],
        ),
        for (final StationSnapshot st in _engine.stations)
          TableRow(
            children: <Widget>[
              pad(Text('${st.letter} ${_acShort(st)}', style: cell)),
              pad(Text('${st.cw}', style: cell)),
              pad(
                Text(st.backoff == null ? '-' : '${st.backoff}', style: cell),
              ),
              pad(Text('${st.delivered}', style: cell)),
              pad(Text('${st.dropped}', style: cell)),
            ],
          ),
      ],
    );
  }

  Widget _statRow(
    TextTheme text,
    AppMonoText mono,
    String label,
    String value,
  ) {
    final AppColorScheme colors = context.colors;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stations card ──────────────────────────────────────────────────────────

  Widget _stationsCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final int n = _stations.length;
    final bool dcf = _mode == AccessMode.dcf;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _sectionTitle(
            text,
            'Stations ($n of ${MediumAccessConfig.maxStations})',
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            dcf
                ? 'Legacy DCF: every station uses DIFS and a contention '
                      'window of 15 to 1023. Switch to EDCA below to give '
                      'stations a traffic class.'
                : 'Each station sends one class of traffic to the AP.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          for (int i = 0; i < n; i++) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _stationRow(text, i, dcf),
          ],
          const SizedBox(height: AppSpacing.sm),
          _outlineButton(
            text,
            icon: Icons.add_rounded,
            label: 'Add station',
            semanticLabel: n >= MediumAccessConfig.maxStations
                ? 'Add station, unavailable: 10 is the maximum'
                : 'Add station ${stationLetter(n)}',
            onPressed: n >= MediumAccessConfig.maxStations
                ? null
                : () => _reconfigure(
                    () => _stations = <StationConfig>[
                      ..._stations,
                      const StationConfig(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _stationRow(TextTheme text, int i, bool dcf) {
    final AppColorScheme colors = context.colors;
    final StationConfig c = _stations[i];
    final String letter = stationLetter(i);
    final bool canRemove = _stations.length > MediumAccessConfig.minStations;
    final String? group = _config.hiddenNode
        ? (i.isEven ? 'group 1' : 'group 2')
        : null;

    final Widget acSelect = _labeledSelect<AccessCategory>(
      label: 'Access category',
      semanticLabel: 'Station $letter access category',
      value: c.accessCategory,
      enabled: !dcf,
      items: <AppSelectItem<AccessCategory>>[
        for (final AccessCategory ac in AccessCategory.values)
          (ac, '${ac.label} (${ac.shortLabel})'),
      ],
      onChanged: (AccessCategory ac) => _reconfigure(() {
        _stations = <StationConfig>[
          for (int j = 0; j < _stations.length; j++)
            j == i ? _stations[j].copyWith(accessCategory: ac) : _stations[j],
        ];
      }),
    );
    final Widget loadSelect = _labeledSelect<double?>(
      label: 'Offered load',
      semanticLabel: 'Station $letter offered load',
      value: c.framesPerSecond,
      items: <AppSelectItem<double?>>[
        for (final double? l in _kLoads)
          (l, l == null ? 'Always has a frame' : '${l.round()} frames/s'),
      ],
      onChanged: (double? l) => _reconfigure(() {
        _stations = <StationConfig>[
          for (int j = 0; j < _stations.length; j++)
            j == i
                ? _stations[j].copyWith(framesPerSecond: () => l)
                : _stations[j],
        ];
      }),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  group == null
                      ? 'Station $letter'
                      : 'Station $letter · $group',
                  style: text.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: canRemove
                    ? () => _reconfigure(() {
                        _stations = <StationConfig>[
                          for (int j = 0; j < _stations.length; j++)
                            if (j != i) _stations[j],
                        ];
                      })
                    : null,
                tooltip: canRemove
                    ? 'Remove station $letter'
                    : 'At least one station is required',
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: colors.textSecondary,
                disabledColor: colors.textDisabled,
              ),
            ],
          ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              if (box.maxWidth < AppSpacing.gridTwoColBreakpoint) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    acSelect,
                    const SizedBox(height: AppSpacing.xs),
                    loadSelect,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(child: acSelect),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: loadSelect),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Medium card ────────────────────────────────────────────────────────────

  Widget _mediumCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final bool oneStation = _stations.length < 2;
    final int dataUs = OfdmTiming.frameDurationUs(_frameBytes, _rateMbps);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _sectionTitle(text, 'Medium and rules'),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<AccessMode>(
            label: 'Channel access',
            value: _mode,
            expand: true,
            items: const <AppToggleItem<AccessMode>>[
              (AccessMode.dcf, 'Legacy DCF'),
              (AccessMode.edca, 'EDCA'),
            ],
            onChanged: (AccessMode m) => _reconfigure(() => _mode = m),
          ),
          const SizedBox(height: AppSpacing.sm),
          _switchRow(
            text,
            title: 'Hidden node',
            subtitle: oneStation
                ? 'Needs two or more stations.'
                : 'Stations A, C, E ... cannot hear B, D, F ... Everyone '
                      'still reaches the AP.',
            value: _hidden && !oneStation,
            onChanged: oneStation
                ? null
                : (bool v) => _reconfigure(() => _hidden = v),
          ),
          _switchRow(
            text,
            title: 'RTS/CTS',
            subtitle:
                'Ask first: RTS, CTS, data, ACK. Anyone who hears the CTS '
                'sets its NAV and stays quiet.',
            value: _rts,
            onChanged: (bool v) => _reconfigure(() => _rts = v),
          ),
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final Widget size = _labeledSelect<int>(
                label: 'Frame size',
                value: _frameBytes,
                items: <AppSelectItem<int>>[
                  for (final int b in _kFrameSizes) (b, '$b bytes'),
                ],
                onChanged: (int b) => _reconfigure(() => _frameBytes = b),
              );
              final Widget rate = _labeledSelect<int>(
                label: 'PHY rate',
                value: _rateMbps,
                items: <AppSelectItem<int>>[
                  for (final int r in OfdmTiming.phyRatesMbps) (r, '$r Mbps'),
                ],
                onChanged: (int r) => _reconfigure(() => _rateMbps = r),
              );
              if (box.maxWidth < AppSpacing.gridTwoColBreakpoint) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    size,
                    const SizedBox(height: AppSpacing.sm),
                    rate,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(child: size),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: rate),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.surface2,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _statRow(text, mono, 'Data frame', '$dataUs µs'),
                _statRow(
                  text,
                  mono,
                  'ACK / RTS / CTS (24 Mbps)',
                  '${OfdmTiming.ackUs} µs each',
                ),
                _statRow(text, mono, 'Slot / SIFS', '9 µs / 16 µs'),
                _statRow(
                  text,
                  mono,
                  'DIFS / EIFS',
                  '${OfdmTiming.difsUs} µs / ${OfdmTiming.eifsUs} µs',
                ),
                const SizedBox(height: AppSpacing.xxs),
                SelectableText(
                  '20 + 4 x ceil((16 + 8 x $_frameBytes + 6) / '
                  '${OfdmTiming.dataBitsPerSymbol(_rateMbps)}) = $dataUs µs',
                  style: mono.inlineCode.copyWith(
                    fontSize: AppTextSize.caption,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (_mode == AccessMode.edca) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _edcaTable(text, mono),
          ],
        ],
      ),
    );
  }

  Widget _edcaTable(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final TextStyle head = _labelStyle(text);
    final TextStyle cell = mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
      color: colors.textPrimary,
    );
    Widget pad(Widget w) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: w,
    );
    return Table(
      children: <TableRow>[
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          children: <Widget>[
            for (final String h in <String>['Class', 'AIFS', 'CWmin', 'CWmax'])
              pad(Text(h, style: head)),
          ],
        ),
        for (final AccessCategory ac in AccessCategory.values)
          TableRow(
            children: <Widget>[
              pad(Text(ac.shortLabel, style: cell)),
              pad(Text('${ac.params.aifsUs} µs', style: cell)),
              pad(Text('${ac.params.cwMin}', style: cell)),
              pad(Text('${ac.params.cwMax}', style: cell)),
            ],
          ),
      ],
    );
  }

  Widget _switchRow(
    TextTheme text, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final AppColorScheme colors = context.colors;
    final bool enabled = onChanged != null;
    // The whole row toggles on tap (a label that ignores taps is a dead
    // zone); keyboard focus stays on the Switch, which paints the ring.
    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        canRequestFocus: false,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        color: enabled
                            ? colors.textPrimary
                            : colors.textDisabled,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        color: enabled
                            ? colors.textTertiary
                            : colors.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── About card ─────────────────────────────────────────────────────────────

  Widget _aboutCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    final TextStyle body =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _sectionTitle(text, 'What this models'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Timing is legacy OFDM (802.11a/g, 5 GHz): 9 µs slots, 16 µs '
            'SIFS, a 20 µs preamble. Newer PHYs have longer preambles and '
            'aggregate frames, and the lesson about contention is the same.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Every station sends to the AP; the AP answers with ACK or CTS. '
            'Control frames go at 24 Mbps. A frame is lost when anything '
            'else is on the air at the AP during it. After 7 failed tries a '
            'frame is dropped. Access delay runs from the moment a frame '
            'reaches the front of its queue to its ACK.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Not modeled: rate adaptation, the AP sending its own data, '
            'frame aggregation, and the NAV reset rule. Runs are seeded, so '
            'Reset replays the same run.',
            style: body,
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// A §8.14 Select under its §8.4 label line.
  Widget _labeledSelect<T>({
    required String label,
    String? semanticLabel,
    required T value,
    required List<AppSelectItem<T>> items,
    required ValueChanged<T> onChanged,
    bool enabled = true,
  }) {
    return LabeledField(
      label: label,
      field: AppSelect<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        enabled: enabled,
        semanticLabel: semanticLabel ?? label,
      ),
    );
  }

  String _acShort(StationSnapshot s) =>
      _mode == AccessMode.dcf ? 'DCF' : s.accessCategory.shortLabel;

  String _acLabel(StationSnapshot s) =>
      _mode == AccessMode.dcf ? 'Legacy DCF' : s.accessCategory.label;

  static String _fmtMs(int us) => '${(us / 1000).toStringAsFixed(3)} ms';

  TextStyle _labelStyle(TextTheme text) =>
      text.labelMedium?.copyWith(color: context.colors.textSecondary) ??
      TextStyle(color: context.colors.textSecondary);

  Widget _sectionTitle(TextTheme text, String title) => Semantics(
    header: true,
    child: Text(
      title,
      style: text.titleMedium?.copyWith(
        color: context.colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _card({required Widget child}) {
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

class _SwatchPainter extends CustomPainter {
  _SwatchPainter({required this.style, required this.colors});

  final BlockStyle style;
  final AppColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    paintTimelineBlock(canvas, Offset.zero & size, style, colors);
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.style != style || old.colors != colors;
}
