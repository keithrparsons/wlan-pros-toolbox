// FloorCoverageStage: the Floor coverage view of the Wi-Fi Classroom "Antenna
// Pattern" tool (antenna-pattern), spec 46.
//
// A side view drawn to true scale, so every angle on screen is the real
// angle: the ceiling at the mount height with the AP on it, the antenna's
// vertical cut drawn around the AP (its shape only, sized to read, not to
// the distance scale), the client plane 1 m up, and a floor strip colored by
// what a client there receives, in 5 dB bands of the Antenna Pattern gain
// ramp (GL-003 §8.15.2) with a dBm legend, so the color never carries the
// number alone. The -67 dBm edges are marked on the strip, distances every
// 10 m, the vendor guidance height for omnis as a dashed line labeled as
// guidance, and the client as a dot joined to the AP. Linear axes only
// (Keith, 2026-09-29: no log scales).
//
// Dark viewport in both themes, as the 3D view: the ramp is measured against
// it (app_gain_ramp.dart).
//
// PRESENTER: the stage fills its box. The mount height, the level directly
// below and the floor cell radius sit on top as large numbers; the side view
// takes the rest. Painter strokes, markers and text take the presenter scale.
//
// Interactive: drag or tap along the floor to move the client (the Client
// position slider does the same from the keyboard).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_gain_ramp.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'antenna_floor_controller.dart';
import 'antenna_pattern_model.dart';
import 'antenna_pattern_parts.dart';

/// The lowest band edge of the floor colors, dBm. Seven 5 dB bands run from
/// here to -57 dBm, so -67 dBm is a band edge.
const double kFloorScaleBottomDbm = -92;

/// Floor color band for a downlink level (0 = weakest, 6 = strongest).
int floorBandOf(double dbm) =>
    ((dbm - kFloorScaleBottomDbm) / AppGainRamp.bandDb).floor().clamp(0, 6);

/// The world window the side view shows, m.
const double kFloorViewMinXM = -6;
const double kFloorViewMaxXM = 36;
const double kFloorViewTopM = 16;

class FloorCoverageStage extends StatelessWidget {
  const FloorCoverageStage({
    super.key,
    required this.floor,
    this.viewportHeight = 320,
  });

  final FloorCoverageController floor;

  /// Height of the side view. The presenter layout fills its box instead.
  final double viewportHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: floor,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final FloorLink? link = floor.link;
        final FloorCell? cell = floor.cell;
        if (link == null || cell == null) {
          return _EmptyFloor(height: presenting ? 320 : viewportHeight);
        }
        final Widget view = _SideView(
          floor: floor,
          link: link,
          cell: cell,
          height: presenting ? null : viewportHeight,
        );
        if (presenting) {
          return PatternCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const PatternSectionLabel('Floor coverage, side view to scale'),
                const SizedBox(height: AppSpacing.xxs),
                _Headline(floor: floor, link: link, cell: cell),
                const SizedBox(height: AppSpacing.xs),
                Expanded(child: view),
                const SizedBox(height: AppSpacing.xs),
                const FloorLegend(),
              ],
            ),
          );
        }
        return PatternCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PatternSectionLabel('Floor coverage, side view to scale'),
              const SizedBox(height: AppSpacing.xs),
              view,
              const SizedBox(height: AppSpacing.xs),
              const FloorLegend(),
              const SizedBox(height: AppSpacing.xxs),
              PatternCaption(
                'The floor strip is what a client 1 m up receives from the '
                'AP, in 5 dB bands. Lines on the strip mark where it crosses '
                '$fmtFloorTarget. The shape around the AP is '
                'the antenna\'s pattern from the side, drawn to be read, not '
                'to the distance scale. Drag along the floor to move the '
                'client.',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyFloor extends StatelessWidget {
  const _EmptyFloor({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return PatternCard(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height * 0.6),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.content_paste_go_outlined,
                  size: 32,
                  color: colors.textTertiary,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'No pattern to put on the floor yet. Paste an MSI or NSMA '
                  'file below, pick a generated example, or choose a preset.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Presenter headline: the three numbers the lesson is about.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.floor,
    required this.link,
    required this.cell,
  });

  final FloorCoverageController floor;
  final FloorLink link;
  final FloorCell cell;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono = patternMono(context);
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final TextStyle big = scale.headlineStyle(mono.outputMedium);
    final FloorPoint below = link.at(0);
    Widget stat(String label, String value, {bool accent = false}) =>
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              Text(
                value,
                style: big.copyWith(
                  color: accent ? colors.textAccent : colors.textPrimary,
                ),
              ),
            ],
          ),
        );
    return Semantics(
      liveRegion: true,
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.xs,
        children: <Widget>[
          stat('Mount height', fmtFloorLength(floor.heightM)),
          stat(
            // Under -95 dBm the headline gives the bound and says "in the
            // null" in its label (headline type has no room for both); the
            // depth would only quote the model's 60 dB floor, so it stays in
            // the readouts' note.
            below.downlinkDbm < kFloorReadableDbm
                ? (floorInNull(below)
                      ? 'Directly below, in the null'
                      : 'Directly below')
                : link.nullBelow
                ? 'Directly below, ${fmtFloorDb(below.belowPeakDb)} dB under '
                      'the peak'
                : 'Directly below',
            fmtFloorLevelDbm(below.downlinkDbm, inNull: false),
            accent: true,
          ),
          stat(
            'Floor cell radius at $fmtFloorTarget',
            cell.radiusM == null ? 'none' : floorCellWords(cell),
          ),
        ],
      ),
    );
  }
}

/// The dBm scale for the floor colors (never color alone).
class FloorLegend extends StatelessWidget {
  const FloorLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle ts = patternMono(
      context,
    ).inlineCode.copyWith(color: colors.textSecondary, fontSize: 11);
    const double top = kFloorScaleBottomDbm + AppGainRamp.bandDb * 7;
    return Semantics(
      label:
          'Floor color scale: seven bands of 5 dB, from '
          '${fmtFloorDbm(kFloorScaleBottomDbm)} and below to '
          '${fmtFloorDbm(top)} and above, darker blue weakest, pale cream '
          'strongest.',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('dBm', style: ts),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    for (final Color c in AppGainRamp.bands)
                      Expanded(
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: c,
                            border: Border.all(
                              color: AppGainRamp.viewport,
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final double w = c.maxWidth / 7;
                    String edge(int k) =>
                        (kFloorScaleBottomDbm + AppGainRamp.bandDb * k)
                            .round()
                            .toString()
                            .replaceFirst('-', '−');
                    final double t =
                        MediaQuery.textScalerOf(context).scale(11) / 11;
                    final int every = w < 36 * t ? 2 : 1;
                    return SizedBox(
                      height: 16 * t,
                      child: Stack(
                        children: <Widget>[
                          Positioned(left: 0, child: Text(edge(0), style: ts)),
                          // Thinned labels skip the one beside the end label.
                          for (
                            int k = every;
                            k < (every == 1 ? 7 : 6);
                            k += every
                          )
                            Positioned(
                              left: w * k - 16 * t,
                              width: 32 * t,
                              child: Text(
                                edge(k),
                                textAlign: TextAlign.center,
                                style: ts,
                              ),
                            ),
                          Positioned(right: 0, child: Text(edge(7), style: ts)),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The side view: a painter plus drag-to-move-the-client.
class _SideView extends StatelessWidget {
  const _SideView({
    required this.floor,
    required this.link,
    required this.cell,
    required this.height,
  });

  final FloorCoverageController floor;
  final FloorLink link;
  final FloorCell cell;

  /// Null: fill the parent (presenter).
  final double? height;

  String _semantic() {
    final FloorPoint below = link.at(0);
    final double? hole = cell.holeM;
    final String cellWords = cell.radiusM == null
        ? 'No floor reaches $fmtFloorTarget.'
        : 'The floor reaches $fmtFloorTarget out to '
              '${floorCellWords(cell)}'
              '${hole == null ? '' : ', with a hole under the AP out to ${fmtFloorLength(hole)}'}.';
    return 'Side view of the floor, to scale. AP on a ceiling at '
        '${fmtFloorLength(floor.heightM)}, ${floor.lab.kind.label}, '
        '${floor.lab.mount.label.toLowerCase()} mounted. Directly below: '
        '${fmtFloorLevelDbm(below.downlinkDbm, inNull: floorInNull(below))}'
        '${link.nullBelow && below.downlinkDbm >= kFloorReadableDbm ? ', ${fmtFloorDb(below.belowPeakDb)} dB under the antenna\'s peak' : ''}. $cellWords '
        'Client ${fmtFloorLength(floor.clientXM)} out. Drag along the floor '
        'to move the client.';
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final TextStyle base = Theme.of(context).textTheme.labelSmall!;
    final TextStyle label = base.copyWith(
      color: AppGainRamp.viewportText,
      fontSize: scale.paintFont(base.fontSize ?? AppTextSize.caption),
    );
    final Widget box = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final FloorFrame frame = FloorFrame.fit(
          Size(c.maxWidth, c.maxHeight),
          scale: scale,
          labelFont: label.fontSize ?? AppTextSize.caption,
        );
        void moveTo(Offset p) => floor.setClientX(frame.worldX(p.dx));
        return GestureDetector(
          onTapDown: (TapDownDetails d) => moveTo(d.localPosition),
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              moveTo(d.localPosition),
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: FloorSidePainter(
                frame: frame,
                link: link,
                cell: cell,
                clientXM: floor.clientXM,
                wall: floor.lab.mount == AntennaMount.wall,
                labelStyle: label,
                lobe: AppGainRamp.band5,
                scale: scale,
                revision: floor.revision,
              ),
            ),
          ),
        );
      },
    );
    // Outside the presenter the box is only as tall as the drawing needs at
    // this width (never more than [height]), so a phone shows no empty band.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        double? boxH = height;
        if (boxH != null && c.maxWidth.isFinite) {
          final double labelFont = label.fontSize ?? AppTextSize.caption;
          final double pad = AppSpacing.xs * scale.marker;
          final double fitted =
              (c.maxWidth - 2 * pad) /
                  (kFloorViewMaxXM - kFloorViewMinXM) *
                  kFloorViewTopM +
              14 * scale.marker +
              labelFont * 3.2 +
              2 * pad +
              AppSpacing.sm;
          boxH = fitted < boxH ? fitted : boxH;
        }
        return _framed(context, colors, box, boxH);
      },
    );
  }

  Widget _framed(
    BuildContext context,
    AppColorScheme colors,
    Widget box,
    double? boxH,
  ) {
    return Semantics(
      label: _semantic(),
      image: true,
      excludeSemantics: true,
      child: Container(
        height: boxH,
        decoration: BoxDecoration(
          color: AppGainRamp.viewport,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: box,
        ),
      ),
    );
  }
}

/// Where the world (metres) lands in the view (pixels): one scale for both
/// axes, so angles are true.
class FloorFrame {
  const FloorFrame({
    required this.size,
    required this.pxPerM,
    required this.originX,
    required this.floorY,
    required this.stripHeight,
  });

  /// Fits the world window into [size], leaving room for the labels above
  /// the ceiling and under the strip.
  factory FloorFrame.fit(
    Size size, {
    required PresenterScale scale,
    required double labelFont,
  }) {
    final double pad = AppSpacing.xs * scale.marker;
    final double strip = 14 * scale.marker;
    final double below = strip + labelFont * 1.6 + pad;
    final double above = labelFont * 1.6 + pad;
    const double spanX = kFloorViewMaxXM - kFloorViewMinXM;
    final double byW = (size.width - 2 * pad) / spanX;
    final double byH = (size.height - above - below) / kFloorViewTopM;
    final double s = math.max(1, math.min(byW, byH));
    final double drawW = spanX * s;
    final double drawH = kFloorViewTopM * s;
    final double left = (size.width - drawW) / 2;
    final double top = math.max(above, (size.height - below - drawH) / 2);
    return FloorFrame(
      size: size,
      pxPerM: s,
      originX: left - kFloorViewMinXM * s,
      floorY: top + drawH,
      stripHeight: strip,
    );
  }

  final Size size;
  final double pxPerM;

  /// Screen x of x = 0 (the AP).
  final double originX;

  /// Screen y of the floor.
  final double floorY;
  final double stripHeight;

  Offset toPx(double xM, double zM) =>
      Offset(originX + xM * pxPerM, floorY - zM * pxPerM);

  double worldX(double px) => (px - originX) / pxPerM;
}

class FloorSidePainter extends CustomPainter {
  FloorSidePainter({
    required this.frame,
    required this.link,
    required this.cell,
    required this.clientXM,
    required this.wall,
    required this.labelStyle,
    required this.lobe,
    required this.scale,
    required this.revision,
  });

  final FloorFrame frame;
  final FloorLink link;
  final FloorCell cell;
  final double clientXM;
  final bool wall;
  final TextStyle labelStyle;
  final Color lobe;
  final PresenterScale scale;
  final int revision;

  static const double _lobeSpanDb = 35;

  void _text(
    Canvas canvas,
    String s,
    Offset at, {
    TextAlign align = TextAlign.left,
    Color? color,
    double? maxWidth,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s,
        style: labelStyle.copyWith(color: color ?? labelStyle.color),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth ?? frame.size.width);
    double dx = at.dx;
    if (align == TextAlign.center) dx -= tp.width / 2;
    if (align == TextAlign.right) dx -= tp.width;
    dx = dx.clamp(2, math.max(2, frame.size.width - tp.width - 2));
    tp.paint(canvas, Offset(dx, at.dy));
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p, double dash) {
    final double len = (b - a).distance;
    if (len <= 0) return;
    final Offset d = (b - a) / len;
    for (double t = 0; t < len; t += dash * 2) {
      canvas.drawLine(a + d * t, a + d * math.min(len, t + dash), p);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final FloorFrame f = frame;
    final double h = link.heightM;
    final double lineH = (labelStyle.fontSize ?? 11) * 1.4;
    final Paint rule = Paint()
      ..color = AppGainRamp.viewportRuleStrong
      ..strokeWidth = scale.strokeWidth(1);
    final Paint strong = Paint()
      ..color = AppGainRamp.viewportText
      ..strokeWidth = scale.strokeWidth(1.5);
    final double left = f.toPx(kFloorViewMinXM, 0).dx;
    final double right = f.toPx(kFloorViewMaxXM, 0).dx;
    final double wallX = f.toPx(0, 0).dx;

    // Behind a wall mount there is no floor to cover: dim it.
    if (wall) {
      canvas.drawRect(
        Rect.fromLTRB(left, f.toPx(0, h).dy, wallX, f.floorY + f.stripHeight),
        Paint()..color = AppGainRamp.viewportRule.withValues(alpha: 0.5),
      );
    }

    // Vendor guidance height for omnis, dashed and labeled as guidance.
    final Offset gA = f.toPx(kFloorViewMinXM, kVendorOmniHeightM);
    final Offset gB = f.toPx(kFloorViewMaxXM, kVendorOmniHeightM);
    _dashed(
      canvas,
      gA,
      gB,
      Paint()
        ..color = AppGainRamp.viewportMuted
        ..strokeWidth = scale.strokeWidth(1),
      6 * scale.stroke,
    );
    final String metres = kVendorOmniHeightM.toStringAsFixed(1);
    final String feet = kVendorOmniHeightFt.round().toString();
    _text(
      canvas,
      frame.size.width < 520
          ? 'Omni guidance $metres m ($feet ft)'
          : 'Vendor guidance for omnis: up to $metres m ($feet ft)',
      Offset(right - 4, gB.dy + 2),
      align: TextAlign.right,
      color: AppGainRamp.viewportMuted,
    );

    // Client plane, 1 m up.
    _dashed(
      canvas,
      f.toPx(wall ? 0 : kFloorViewMinXM, kClientHeightM),
      f.toPx(kFloorViewMaxXM, kClientHeightM),
      Paint()
        ..color = AppGainRamp.viewportRule
        ..strokeWidth = scale.strokeWidth(1),
      4 * scale.stroke,
    );

    // Ceiling.
    final Offset cA = f.toPx(kFloorViewMinXM, h);
    final Offset cB = f.toPx(kFloorViewMaxXM, h);
    canvas.drawLine(cA, cB, strong);
    _text(
      canvas,
      'Ceiling ${fmtFloorLength(h)}',
      Offset(right - 4, cA.dy - lineH),
      align: TextAlign.right,
    );

    // Wall behind a wall mount.
    if (wall) {
      canvas.drawLine(Offset(wallX, cA.dy), Offset(wallX, f.floorY), strong);
    }

    // Floor strip, colored by the downlink in 5 dB bands.
    final double stripTop = f.floorY;
    final double stripBottom = f.floorY + f.stripHeight;
    // One rect per run of the same band, so no seams show between pixels.
    final Paint band = Paint()..isAntiAlias = false;
    final double start = wall ? wallX : left;
    double runStart = start;
    int runBand = floorBandOf(link.downlinkDbmAt(f.worldX(start)));
    void flush(double end) {
      band.color = AppGainRamp.bands[runBand];
      canvas.drawRect(
        Rect.fromLTRB(runStart, stripTop, end, stripBottom),
        band,
      );
    }

    for (double px = start + 1; px < right; px += 1) {
      final int b = floorBandOf(link.downlinkDbmAt(f.worldX(px + 0.5)));
      if (b != runBand) {
        flush(px);
        runStart = px;
        runBand = b;
      }
    }
    flush(right);
    canvas.drawLine(Offset(left, f.floorY), Offset(right, f.floorY), strong);

    // Distance ticks every 10 m under the strip.
    for (double x = 0; x <= kFloorViewMaxXM; x += 10) {
      if (wall && x < 0) continue;
      final Offset p = f.toPx(x, 0);
      canvas.drawLine(
        Offset(p.dx, stripBottom),
        Offset(p.dx, stripBottom + 4 * scale.stroke),
        rule,
      );
      _text(
        canvas,
        x == 0 ? '0' : '${x.abs().round()} m',
        Offset(p.dx, stripBottom + 4 * scale.stroke),
        align: TextAlign.center,
      );
    }

    // The -67 dBm edges, as marks through the strip (both sides when the
    // pattern is the same both ways, i.e. not turned and not a wall).
    final bool mirror = !wall && !link.turned;
    final Paint edge = Paint()
      ..color = AppGainRamp.viewportText
      ..strokeWidth = scale.strokeWidth(2);
    for (final ({double fromM, double toM}) s in cell.segments) {
      for (final double e in <double>[s.fromM, s.toM]) {
        if (e <= 0 || e >= kFloorSearchM) continue;
        for (final double sx in mirror ? <double>[e, -e] : <double>[e]) {
          if (sx < kFloorViewMinXM || sx > kFloorViewMaxXM) continue;
          final Offset p = f.toPx(sx, 0);
          canvas.drawLine(
            Offset(p.dx, stripTop - 6 * scale.stroke),
            Offset(p.dx, stripBottom),
            edge,
          );
        }
      }
    }

    // The pattern's vertical cut around the AP, in the world frame.
    final Offset ap = f.toPx(0, h);
    // Big enough to read, never past the room: the lobe is clipped to the
    // space between the ceiling and the floor, where the clients are.
    final double lobeR = math.min(
      math.max(
        (frame.size.width < 400 ? 22 : 36) * scale.marker,
        (h - kClientHeightM) * f.pxPerM * 0.6,
      ),
      frame.size.height * 0.28,
    );
    final double peak = link.grid.peakDbi;
    final Path path = Path();
    for (int a = 0; a <= 360; a += 2) {
      final double rad = a * math.pi / 180;
      final double wx = math.cos(rad);
      final double wz = math.sin(rad);
      double theta;
      int phi;
      if (link.turned) {
        theta = math.acos((-wx).clamp(-1.0, 1.0)) * 180 / math.pi;
        phi = -wz >= 0 ? 0 : 180;
      } else {
        theta = math.acos(wz.clamp(-1.0, 1.0)) * 180 / math.pi;
        phi = wx >= 0 ? 0 : 180;
      }
      final double g = gainTowardDbi(link.grid, theta, phi);
      final double r =
          lobeR * ((g - (peak - _lobeSpanDb)) / _lobeSpanDb).clamp(0.0, 1.0);
      final Offset p = ap + Offset(wx * r, -wz * r);
      if (a == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.save();
    // Only the part inside the room is drawn (a wall mount: only in front).
    canvas.clipRect(
      Rect.fromLTRB(wall ? wallX : 0, ap.dy, frame.size.width, f.floorY),
    );
    canvas.drawPath(path, Paint()..color = lobe.withValues(alpha: 0.22));
    canvas.drawPath(
      path,
      Paint()
        ..color = lobe
        ..style = PaintingStyle.stroke
        ..strokeWidth = scale.strokeWidth(1.5),
    );
    canvas.restore();

    // The client and the path to it.
    final Offset client = f.toPx(clientXM, kClientHeightM);
    _dashed(
      canvas,
      ap,
      client,
      Paint()
        ..color = AppGainRamp.viewportText
        ..strokeWidth = scale.strokeWidth(1),
      5 * scale.stroke,
    );
    canvas.drawCircle(
      ap,
      scale.markerSize(5),
      Paint()..color = AppGainRamp.viewportText,
    );
    canvas.drawCircle(
      client,
      scale.markerSize(5),
      Paint()..color = AppGainRamp.band7,
    );
    canvas.drawCircle(
      client,
      scale.markerSize(5),
      Paint()
        ..color = AppGainRamp.viewport
        ..style = PaintingStyle.stroke
        ..strokeWidth = scale.strokeWidth(1.5),
    );
    final FloorPoint cp = link.at(clientXM);
    final bool labelLeft = client.dx > frame.size.width * 0.6;
    _text(
      canvas,
      'Client ${fmtFloorLevelDbm(cp.downlinkDbm, inNull: floorInNull(cp))}',
      Offset(
        client.dx + (labelLeft ? -8 : 8) * scale.marker,
        client.dy - lineH - 4 * scale.marker,
      ),
      align: labelLeft ? TextAlign.right : TextAlign.left,
    );
  }

  @override
  bool shouldRepaint(FloorSidePainter old) =>
      old.revision != revision ||
      old.clientXM != clientXM ||
      old.frame.size != frame.size ||
      old.scale != scale ||
      old.labelStyle != labelStyle;
}
