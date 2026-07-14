// Packet-flow loading animation — the on-brand presentation layer for the ~10s
// data-gathering phase on Test My Connection / Check My Connection (Felix,
// 2026-06-13; Keith picked this concept over the bare percentage bar).
//
// WHAT IT IS: a horizontal three-node path  [You] → [AP] → [Internet]  with a
// single lime dot that travels along the path, and each node lights lime
// (#A1CC3A) as that phase of the live test completes (Wi-Fi link → gateway →
// internet). It is PURELY a presentation layer over the SAME QualityPhase /
// fraction the engine already streams — it starts/measures nothing.
//
// ACCESSIBILITY (binding, GL-003 §8.3 / WCAG 2.2):
//   * SC 1.4.1 (use of color): the node state is NEVER carried by lime alone.
//     Each node renders a check glyph when complete and a hollow ring while
//     pending, AND the textual phase caption + percentage stay on screen above
//     the path. Color only reinforces.
//   * Screen reader: a single live region announces the phase + percentage as it
//     advances (the painter itself is excluded from semantics). The host screen
//     keeps its own announcement on completion.
//   * Reduced motion (SC 2.3.3 / a user "reduce motion" OS flag): when
//     MediaQuery.disableAnimations is set, the traveling dot and the node
//     fill-tween are dropped — nodes snap to their lit/unlit state and the
//     percentage view carries progress statically. Same data, no motion.
//
// MOTION: one repeating AnimationController drives ONLY the dot's travel along
// the active segment and a soft pulse on the in-flight node. Node completion is
// data-driven (from [completed]) and tweened with AppMotion, not by the loop.
// Lightweight: a single CustomPainter, no per-frame allocation of Paint in the
// hot path beyond what the painter caches.

import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';

/// The three nodes of the packet-flow path, in order. Each maps to one phase of
/// the live connection test completing.
enum PacketFlowNode {
  /// The user's device — lit as soon as the test is underway.
  you,

  /// The access point / gateway hop — lit once the Wi-Fi link round-trip is
  /// confirmed (latency phase complete).
  ap,

  /// The public internet — lit once the throughput phases complete.
  internet,
}

/// How many nodes (out of three) are lit. [PacketFlowStage.none] = test just
/// started; [PacketFlowStage.all] = every phase done.
///
/// This is the SINGLE contract the host passes in. The host maps its own engine
/// phase (e.g. [QualityPhase]) to a stage; this widget knows nothing about the
/// engine, only how many hops have completed and the overall fraction.
enum PacketFlowStage {
  /// Nothing complete yet — the dot travels You → AP.
  none,

  /// [PacketFlowNode.you] lit — the dot travels You → AP.
  you,

  /// You + AP lit — the dot travels AP → Internet.
  ap,

  /// All three lit — the path is complete.
  all;

  /// The number of fully lit nodes for this stage (0..3).
  int get litNodes {
    switch (this) {
      case PacketFlowStage.none:
        return 0;
      case PacketFlowStage.you:
        return 1;
      case PacketFlowStage.ap:
        return 2;
      case PacketFlowStage.all:
        return 3;
    }
  }

  /// The index of the segment the traveling dot animates along (0 = You→AP,
  /// 1 = AP→Internet). Clamped so the completed state parks the dot at the end.
  int get activeSegment {
    switch (this) {
      case PacketFlowStage.none:
      case PacketFlowStage.you:
        return 0;
      case PacketFlowStage.ap:
      case PacketFlowStage.all:
        return 1;
    }
  }
}

/// The packet-flow loading view: the textual phase caption + percentage, then
/// the animated [You] → [AP] → [Internet] path.
///
/// Drop-in over a percentage bar: pass the live [caption], [fraction] (0..1) and
/// [stage]. Everything visual — including the accessible percentage view and the
/// reduced-motion fallback — is handled inside.
class PacketFlowProgress extends StatefulWidget {
  const PacketFlowProgress({
    super.key,
    required this.caption,
    required this.fraction,
    required this.stage,
    this.semanticsLabelBuilder,
    this.indeterminate = false,
  });

  /// True when the engine no longer knows how far along it is, so no percentage
  /// may be shown.
  ///
  /// A percentage that sits on one number for tens of seconds is not "progress
  /// information", it is a HANG signal — and it is the thing that sent Keith
  /// looking for a bug in his own app. When the engine says it does not know, the
  /// honest render is to stop claiming a number: the path keeps animating (work
  /// IS happening), and the figure is replaced by a plain "still working" word.
  /// The dot must never advance on a timer while nothing is happening — that is
  /// the same lie as a stale LIVE badge, just prettier.
  final bool indeterminate;

  /// The human phase caption shown above the path (e.g. "Testing your internet
  /// speed…"). Owned by the host so the existing jargon-free copy is unchanged.
  final String caption;

  /// Overall progress 0..1, shown as a percentage and announced to screen
  /// readers. Drives nothing in the path geometry (the [stage] does that); it is
  /// the same honest figure the bar showed.
  final String Function()? semanticsLabelBuilder;

  /// 0..1 overall completion.
  final double fraction;

  /// How many hops have completed — the node-lighting contract.
  final PacketFlowStage stage;

  @override
  State<PacketFlowProgress> createState() => _PacketFlowProgressState();
}

class _PacketFlowProgressState extends State<PacketFlowProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // One ~1.1s loop drives the dot travel + the in-flight node pulse. It is
    // started/stopped by reduced-motion in build (a controller that is never
    // animated costs nothing per frame).
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    // Drive (or stop) the loop based on the reduced-motion flag. Running only
    // while motion is allowed AND the path is incomplete keeps it cheap.
    final bool shouldAnimate =
        !reduceMotion && widget.stage != PacketFlowStage.all;
    if (shouldAnimate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      if (_controller.isAnimating) _controller.stop();
    }

    final int pct = (widget.fraction.clamp(0.0, 1.0) * 100).round();
    // The non-color, non-motion carrier of progress (SC 1.4.1). When the engine
    // has stopped knowing, this says so in words rather than showing a frozen
    // number. Reduced-motion users get the same honest text — they are the ones
    // who most need it, because for them the animation is not there to reassure.
    final String progressLabel = widget.indeterminate ? 'Still working' : '$pct%';

    // Lime is a sanctioned FILL in both themes (§8.20.2). The node fill, the dot
    // and the completed-segment all read as lime AREAS, not thin foreground
    // strokes, so brand lime holds on white. The pending track/ring uses a
    // theme-aware low-contrast tone.
    final Color litColor = colors.primary;
    final Color pendingColor = colors.isLight ? colors.surface0 : colors.surface2;
    final Color trackInk = colors.borderStrong;
    final Color labelInk = colors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // (1) Textual phase + percentage — the WCAG SC 1.4.1 non-color carrier.
        // Wrapped in one live region so a screen reader hears each advance.
        Semantics(
          liveRegion: true,
          label: widget.semanticsLabelBuilder?.call() ??
              (widget.indeterminate
                  ? '${widget.caption}, still working'
                  : '${widget.caption}, $pct percent complete'),
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Flexible(
                  child: Text(
                    widget.caption,
                    style: text.labelMedium?.copyWith(
                      color: labelInk,
                      letterSpacing: 0.4,
                      fontWeight:
                          colors.isLight ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  progressLabel,
                  style: text.labelMedium?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // (2) The animated path. The painter is excluded from semantics — the
        // live region above already speaks the progress.
        ExcludeSemantics(
          child: SizedBox(
            height: _kNodeDiameter + _kLabelGap + _kLabelHeight,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, _) {
                return CustomPaint(
                  painter: _PacketFlowPainter(
                    stage: widget.stage,
                    dotProgress: shouldAnimate ? _controller.value : 1.0,
                    animate: shouldAnimate,
                    litColor: litColor,
                    // The in-flight pulse RING is a thin accent stroke, not a
                    // fill — so it must clear SC 1.4.11's 3:1 floor on the light
                    // canvas where lime computes only ~1.8:1. textAccent is the
                    // theme-aware accent: lime #A1CC3A on dark (9.3:1), olive
                    // #5A7A1C on light (~4.6:1) per GL-003 §8.20.3-B.
                    ringAccent: colors.textAccent,
                    pendingFill: pendingColor,
                    trackInk: trackInk,
                    nodeOutline: colors.borderStrong,
                    onLitGlyphColor: colors.onPrimary,
                    pendingGlyphColor: colors.textTertiary,
                    labelLitColor: colors.textPrimary,
                    labelPendingColor: colors.textTertiary,
                    labelStyle: text.labelSmall ?? const TextStyle(),
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// Node + label geometry. Kept as named constants so the SizedBox height above
// and the painter agree on the layout box.
const double _kNodeDiameter = 28;
const double _kLabelGap = AppSpacing.xs;
const double _kLabelHeight = 16;

/// Paints the three-node [You] → [AP] → [Internet] path: the connecting track,
/// the lit/unlit segments, each node (filled + check glyph when complete, hollow
/// ring + outline glyph when pending), the traveling dot, and the node labels.
///
/// State (lit nodes, active segment) is data-driven from [stage]; only the dot
/// position and the in-flight pulse come from [dotProgress] / [animate]. With
/// [animate] false (reduced motion / complete) the dot parks at the segment end
/// and no pulse is drawn — a static, fully legible snapshot.
class _PacketFlowPainter extends CustomPainter {
  _PacketFlowPainter({
    required this.stage,
    required this.dotProgress,
    required this.animate,
    required this.litColor,
    required this.ringAccent,
    required this.pendingFill,
    required this.trackInk,
    required this.nodeOutline,
    required this.onLitGlyphColor,
    required this.pendingGlyphColor,
    required this.labelLitColor,
    required this.labelPendingColor,
    required this.labelStyle,
  });

  final PacketFlowStage stage;
  final double dotProgress;
  final bool animate;
  final Color litColor;

  /// Theme-aware accent for the in-flight pulse RING (a thin stroke): lime on
  /// dark, olive on light, so it clears the SC 1.4.11 3:1 non-text floor. The
  /// lime [litColor] still drives all FILLS (nodes / dot / lit segments).
  final Color ringAccent;
  final Color pendingFill;
  final Color trackInk;
  final Color nodeOutline;
  final Color onLitGlyphColor;
  final Color pendingGlyphColor;
  final Color labelLitColor;
  final Color labelPendingColor;
  final TextStyle labelStyle;

  static const List<String> _labels = <String>['You', 'AP', 'Internet'];
  static const List<IconData> _icons = <IconData>[
    Icons.smartphone,
    Icons.router,
    Icons.public,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const double r = _kNodeDiameter / 2;
    final double cy = r; // node row centered at the top of the box
    // Three node centers spread edge-to-edge, inset by the radius so circles do
    // not clip.
    final double left = r;
    final double right = size.width - r;
    final List<double> cx = <double>[
      left,
      (left + right) / 2,
      right,
    ];

    final int lit = stage.litNodes;

    // --- 1. Track segments (drawn first, behind the nodes). ---
    final Paint trackPaint = Paint()
      ..color = trackInk
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final Paint litSegPaint = Paint()
      ..color = litColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (int seg = 0; seg < 2; seg++) {
      final Offset a = Offset(cx[seg] + r, cy);
      final Offset b = Offset(cx[seg + 1] - r, cy);
      // A segment is fully lit once BOTH its end nodes are lit.
      final bool segLit = lit >= seg + 2;
      canvas.drawLine(a, b, segLit ? litSegPaint : trackPaint);
    }

    // --- 2. The traveling dot on the active segment (motion only). ---
    if (animate) {
      final int seg = stage.activeSegment;
      final Offset a = Offset(cx[seg] + r, cy);
      final Offset b = Offset(cx[seg + 1] - r, cy);
      final Offset dot = Offset.lerp(a, b, dotProgress)!;
      // A soft lime halo + a solid lime core — a packet in flight.
      canvas.drawCircle(dot, 7, Paint()..color = litColor.withValues(alpha: 0.25));
      canvas.drawCircle(dot, 4, Paint()..color = litColor);
    }

    // --- 3. Nodes (filled + check when complete; ring + icon when pending). ---
    for (int i = 0; i < 3; i++) {
      final Offset center = Offset(cx[i], cy);
      final bool nodeLit = i < lit;
      // The node in flight (the first un-lit node) gets a gentle pulsing outline
      // while motion is allowed, so the eye knows which hop is being measured.
      final bool inFlight = animate && i == lit;

      if (nodeLit) {
        canvas.drawCircle(center, r, Paint()..color = litColor);
      } else {
        canvas.drawCircle(center, r, Paint()..color = pendingFill);
        final Paint ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = inFlight ? 2.5 : 1.5
          ..color = inFlight
              ? Color.lerp(nodeOutline, ringAccent,
                  0.5 + 0.5 * (dotProgress))!
              : nodeOutline;
        canvas.drawCircle(center, r - 1, ring);
      }

      // The state glyph: a check when complete (SC 1.4.1 — shape, not color),
      // the node's own icon when pending.
      final IconData glyph = nodeLit ? Icons.check : _icons[i];
      _paintGlyph(
        canvas,
        glyph,
        center,
        nodeLit ? onLitGlyphColor : pendingGlyphColor,
        nodeLit ? 18 : 16,
      );

      // The node label beneath.
      _paintLabel(
        canvas,
        _labels[i],
        Offset(cx[i], _kNodeDiameter + _kLabelGap),
        nodeLit ? labelLitColor : labelPendingColor,
      );
    }
  }

  void _paintGlyph(
    Canvas canvas,
    IconData icon,
    Offset center,
    Color color,
    double fontSize,
  ) {
    final TextPainter tp = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
    )..layout();
    tp.paint(
      canvas,
      center - Offset(tp.width / 2, tp.height / 2),
    );
  }

  void _paintLabel(Canvas canvas, String label, Offset top, Color color) {
    final TextPainter tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: label,
        style: labelStyle.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    )..layout();
    tp.paint(canvas, Offset(top.dx - tp.width / 2, top.dy));
  }

  @override
  bool shouldRepaint(_PacketFlowPainter old) {
    return old.stage != stage ||
        old.dotProgress != dotProgress ||
        old.animate != animate ||
        old.litColor != litColor ||
        old.ringAccent != ringAccent ||
        old.pendingFill != pendingFill ||
        old.trackInk != trackInk;
  }
}
