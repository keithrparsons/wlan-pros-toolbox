// The stage for Down the Stack, Across the Air, Up the Other Side (Wi-Fi
// Classroom): the step and what it did, the stack columns (Laptop, AP,
// Router, Server) with the path the data takes down, across and up, what is
// on the wire or the air now, the addresses in force, and the To DS /
// From DS explorer. Reads a [DownTheStackController]; owns no state, so a
// presenter layout can place it beside [DownTheStackControls].
//
// COLOR (GL-003 §8.15.2 / §8.13). The header hues come from
// frame_journey_parts.dart and never carry meaning alone (every piece is
// labeled). Lime marks where the data is now and the path it has taken. No
// status hue: nothing here is a verdict.
//
// THE RF DRAWING. The air hop is drawn as a wave of ONE fixed wavelength
// that only drifts in phase while playing. It never implies a frequency
// change (Keith's standing rule).
//
// ACCESSIBILITY. The drawing has a worded Semantics label; everything it
// shows is also in text on the cards (SC 1.4.1). The step slider moves the
// data for keyboard and screen-reader users.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/frame_journey_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'down_the_stack_controller.dart';
import 'frame_journey_parts.dart';

class DownTheStackStage extends StatelessWidget {
  const DownTheStackStage({
    super.key,
    required this.controller,
    this.diagramHeight = 340,
  });

  final DownTheStackController controller;

  /// Height of the stack drawing on the normal screen. Ignored in presenter
  /// mode, where the drawing fills the space it is given.
  final double diagramHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        if (controller.view == DtsView.addresses) {
          final Widget explorer = DtsAddressExplorer(controller: controller);
          if (!presenting) return explorer;
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(width: 900, child: explorer),
          );
        }
        final Widget headline = _Headline(controller: controller);
        final Widget pdu = _PduCard(controller: controller);
        final Widget addresses = _AddressCard(controller: controller);
        if (!presenting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              headline,
              const SizedBox(height: AppSpacing.sm),
              _DiagramCard(controller: controller, height: diagramHeight),
              const SizedBox(height: AppSpacing.sm),
              pdu,
              const SizedBox(height: AppSpacing.sm),
              addresses,
            ],
          );
        }
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double side = (box.maxWidth * 0.36).clamp(320.0, 520.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: _DiagramCard(controller: controller)),
                      const SizedBox(height: AppSpacing.xs),
                      pdu,
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: side,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: side,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          headline,
                          const SizedBox(height: AppSpacing.xs),
                          addresses,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ── Headline: the step and what it did ──────────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline({required this.controller});

  final DownTheStackController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final FjStep s = controller.step;
    final String where = s.onMedium
        ? s.medium!.label
        : '${s.node!.label}, layer ${s.layer!.osi}: ${s.layer!.label}';
    return AirtimeCard(
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Step ${s.index + 1} of ${controller.stepCount}  |  $where',
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              s.title,
              style: text.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              s.detail,
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── The stack drawing ───────────────────────────────────────────────────────

class _DiagramCard extends StatelessWidget {
  const _DiagramCard({required this.controller, this.height});

  final DownTheStackController controller;

  /// Fixed height, or null to fill the parent (presenter).
  final double? height;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    TextStyle up(TextStyle t) =>
        t.copyWith(fontSize: scale.paintFont(t.fontSize ?? AppTextSize.body));
    final FjStep s = controller.step;
    final DtsDiagramStyle style = DtsDiagramStyle(
      scale: scale,
      box: colors.surface2,
      boxBorder: colors.borderStrong,
      unused: colors.textDisabled,
      route: colors.textTertiary,
      active: colors.primary,
      ink: colors.textPrimary,
      muted: colors.textSecondary,
      marker: colors.primary,
      markerInk: colors.onPrimary,
      layerLabel: up(text.labelSmall!.copyWith(color: colors.textPrimary)),
      nodeLabel: up(
        text.labelLarge!.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      mediumLabel: up(
        mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.textSecondary,
        ),
      ),
    );
    final String spoken = s.onMedium
        ? 'The data is crossing the ${s.medium == FjMedium.air ? 'air' : 'wire'} '
              'from the ${s.from!.label} to the ${s.to!.label}, as bits.'
        : 'The data is at the ${s.node!.label}, layer ${s.layer!.osi}, '
              '${s.layer!.label}, as a ${s.pduName.toLowerCase()} of '
              '${s.pduBytes} bytes.';
    final Widget paint = Semantics(
      label: 'Stack drawing. $spoken',
      excludeSemantics: true,
      child: ValueListenableBuilder<double>(
        valueListenable: controller.wave,
        builder: (BuildContext context, double phase, _) => CustomPaint(
          painter: DtsStackPainter(
            nodes: controller.nodes,
            journey: controller.journey,
            index: controller.index,
            phase: phase,
            style: style,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    return AirtimeCard(
      child: height == null ? paint : SizedBox(height: height, child: paint),
    );
  }
}

/// Theme values the stack painter needs.
class DtsDiagramStyle {
  const DtsDiagramStyle({
    required this.scale,
    required this.box,
    required this.boxBorder,
    required this.unused,
    required this.route,
    required this.active,
    required this.ink,
    required this.muted,
    required this.marker,
    required this.markerInk,
    required this.layerLabel,
    required this.nodeLabel,
    required this.mediumLabel,
  });

  final PresenterScale scale;
  final Color box;
  final Color boxBorder;
  final Color unused;
  final Color route;
  final Color active;
  final Color ink;
  final Color muted;
  final Color marker;
  final Color markerInk;
  final TextStyle layerLabel;
  final TextStyle nodeLabel;
  final TextStyle mediumLabel;
}

/// Draws the stack columns, the media between them, the route and where the
/// data is now.
class DtsStackPainter extends CustomPainter {
  DtsStackPainter({
    required this.nodes,
    required this.journey,
    required this.index,
    required this.phase,
    required this.style,
  });

  final List<FjNode> nodes;
  final List<FjStep> journey;
  final int index;
  final double phase;
  final DtsDiagramStyle style;

  static const List<FjLayer> _layers = FjLayer.values;

  @override
  void paint(Canvas canvas, Size size) {
    final _Layout g = _layout(size);
    final PresenterScale k = style.scale;
    final FjStep now = journey[index];

    // Layer names, once, in the left gutter.
    for (int r = 0; r < _layers.length; r++) {
      _text(
        canvas,
        '${_layers[r].osi} ${_layers[r].label}',
        style.layerLabel.copyWith(color: style.muted),
        Offset(0, g.rowTop(r) + g.rowH / 2),
        middle: true,
        maxWidth: g.gutter - 6 * k.marker,
      );
    }

    // Columns.
    for (int i = 0; i < nodes.length; i++) {
      final FjNode node = nodes[i];
      _text(
        canvas,
        node.label,
        style.nodeLabel,
        Offset(g.cx(i), 0),
        center: true,
      );
      for (int r = 0; r < _layers.length; r++) {
        final FjLayer layer = _layers[r];
        final bool used = layer.osi <= node.top.osi;
        final bool here =
            !now.onMedium && now.node == node && now.layer == layer;
        final RRect rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(g.cx(i) - g.colW / 2, g.rowTop(r), g.colW, g.rowH),
          Radius.circular(6 * k.marker),
        );
        if (used) canvas.drawRRect(rect, Paint()..color = style.box);
        final Paint border = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = k.strokeWidth(here ? 3 : 1)
          ..color = here
              ? style.active
              : (used ? style.boxBorder : style.unused);
        if (used) {
          canvas.drawRRect(rect, border);
        } else {
          _dashedRRect(canvas, rect, border);
        }
      }
    }

    // Media, below the physical row.
    for (int i = 0; i < nodes.length - 1; i++) {
      final FjMedium m =
          (nodes[i] == FjNode.laptop || nodes[i + 1] == FjNode.laptop)
          ? FjMedium.air
          : FjMedium.wire;
      final double x0 = g.cx(i);
      final double x1 = g.cx(i + 1);
      final bool here =
          now.onMedium &&
          ((now.from == nodes[i] && now.to == nodes[i + 1]) ||
              (now.from == nodes[i + 1] && now.to == nodes[i]));
      final Paint p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = k.strokeWidth(here ? 3 : 1.5)
        ..strokeCap = StrokeCap.round
        ..color = here ? style.active : style.muted;
      final double y = g.mediumY;
      final double inset = g.colW * 0.12;
      if (m == FjMedium.air) {
        _wave(
          canvas,
          x0 + inset,
          x1 - inset,
          y,
          5 * k.marker,
          16 * k.marker,
          here ? phase : 0,
          p,
        );
      } else {
        canvas.drawLine(
          Offset(x0 + inset, y - 2 * k.marker),
          Offset(x1 - inset, y - 2 * k.marker),
          p,
        );
        canvas.drawLine(
          Offset(x0 + inset, y + 2 * k.marker),
          Offset(x1 - inset, y + 2 * k.marker),
          p,
        );
      }
      _text(
        canvas,
        m == FjMedium.air ? 'air' : 'wire',
        style.mediumLabel.copyWith(color: here ? style.ink : style.muted),
        Offset((x0 + x1) / 2, y + 8 * k.marker),
        center: true,
      );
    }

    // The route: every step's anchor, joined.
    final List<Offset> pts = <Offset>[
      for (int i = 0; i < journey.length; i++) _anchor(i, g),
    ];
    final Paint all = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = k.strokeWidth(1.5)
      ..color = style.route;
    final Paint done = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = k.strokeWidth(3.5)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = style.active;
    for (int i = 0; i < pts.length - 1; i++) {
      _dashedLine(canvas, pts[i], pts[i + 1], all);
    }
    for (int i = 0; i < index; i++) {
      canvas.drawLine(pts[i], pts[i + 1], done);
    }
    // Where the data is now, and what it is called there.
    final double r = 8 * k.marker;
    canvas.drawCircle(
      pts[index],
      r + k.strokeWidth(2),
      Paint()..color = style.box,
    );
    canvas.drawCircle(pts[index], r, Paint()..color = style.marker);
    if (!now.onMedium) {
      final int col = nodes.indexOf(now.node!);
      final int row = _layers.indexOf(now.layer!);
      final double tx = pts[index].dx > g.cx(col)
          ? g.cx(col) - g.colW / 2 + 5 * k.marker
          : pts[index].dx + r + 4 * k.marker;
      final TextStyle pduStyle = style.layerLabel.copyWith(
        color: style.ink,
        fontWeight: FontWeight.w700,
      );
      // Only when it fits whole; the card below always names it.
      if (_tp(now.pduName, pduStyle).width <= g.colW * 0.62) {
        _text(
          canvas,
          now.pduName,
          pduStyle,
          Offset(tx, g.rowTop(row) + g.rowH / 2),
          middle: true,
        );
      }
    }
  }

  _Layout _layout(Size size) {
    final PresenterScale k = style.scale;
    final TextPainter nodeTp = _tp('Router', style.nodeLabel);
    final TextPainter gutterTp = _tp('7 Application', style.layerLabel);
    final double gutter = math.min(
      gutterTp.width + 8 * k.marker,
      size.width * 0.3,
    );
    final int n = nodes.length;
    final double colPitch = (size.width - gutter) / n;
    final double colW = math.min(colPitch * 0.8, 190 * k.marker);
    final double top = nodeTp.height + 6 * k.marker;
    final double mediumBand = 40 * k.marker;
    final double gap = 5 * k.marker;
    final double rowH = math.max(
      16.0,
      (size.height - top - mediumBand - gap * (_layers.length - 1)) /
          _layers.length,
    );
    return _Layout(
      gutter: gutter,
      colPitch: colPitch,
      colW: colW,
      top: top,
      gap: gap,
      rowH: rowH,
      mediumY: top + _layers.length * (rowH + gap) - gap + mediumBand * 0.3,
    );
  }

  /// Where step [i] sits on the drawing.
  Offset _anchor(int i, _Layout g) {
    final FjStep s = journey[i];
    if (s.onMedium) {
      final int a = nodes.indexOf(s.from!);
      final int b = nodes.indexOf(s.to!);
      return Offset((g.cx(a) + g.cx(b)) / 2, g.mediumY);
    }
    final int col = nodes.indexOf(s.node!);
    final int row = _layers.indexOf(s.layer!);
    final double y = g.rowTop(row) + g.rowH / 2;
    final bool endpoint = col == 0 || col == nodes.length - 1;
    final double off = g.colW * 0.3;
    if (endpoint) return Offset(g.cx(col) - off * 0.5, y);
    // An intermediate node: climb on the left, come down on the right.
    int start = i;
    while (start > 0 && journey[start - 1].node == s.node) {
      start--;
    }
    int end = i;
    while (end < journey.length - 1 && journey[end + 1].node == s.node) {
      end++;
    }
    final int len = end - start + 1;
    final int p = i - start;
    if (len.isOdd && p == len ~/ 2) return Offset(g.cx(col), y);
    return Offset(g.cx(col) + (p < len / 2 ? -off : off), y);
  }

  void _wave(
    Canvas c,
    double x0,
    double x1,
    double y,
    double amp,
    double wavelength,
    double phase,
    Paint p,
  ) {
    // One fixed wavelength; only the phase moves.
    final Path path = Path();
    const int steps = 80;
    for (int j = 0; j <= steps; j++) {
      final double x = x0 + (x1 - x0) * j / steps;
      final double v =
          math.sin(2 * math.pi * ((x - x0) / wavelength - phase)) * amp;
      if (j == 0) {
        path.moveTo(x, y + v);
      } else {
        path.lineTo(x, y + v);
      }
    }
    c.drawPath(path, p);
  }

  void _dashedLine(Canvas c, Offset a, Offset b, Paint p) {
    final double len = (b - a).distance;
    if (len == 0) return;
    final Offset d = (b - a) / len;
    const double dash = 4;
    for (double t = 0; t < len; t += dash * 2) {
      c.drawLine(a + d * t, a + d * math.min(t + dash, len), p);
    }
  }

  void _dashedRRect(Canvas c, RRect r, Paint p) {
    final Rect o = r.outerRect;
    _dashedLine(c, o.topLeft, o.topRight, p);
    _dashedLine(c, o.topRight, o.bottomRight, p);
    _dashedLine(c, o.bottomRight, o.bottomLeft, p);
    _dashedLine(c, o.bottomLeft, o.topLeft, p);
  }

  TextPainter _tp(String s, TextStyle st, {double? maxWidth}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    return tp;
  }

  void _text(
    Canvas c,
    String s,
    TextStyle st,
    Offset at, {
    bool center = false,
    bool middle = false,
    double? maxWidth,
  }) {
    final TextPainter tp = _tp(s, st, maxWidth: maxWidth);
    final double dx = center ? at.dx - tp.width / 2 : at.dx;
    final double dy = middle ? at.dy - tp.height / 2 : at.dy;
    tp.paint(c, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(DtsStackPainter old) =>
      old.index != index ||
      old.phase != phase ||
      old.journey != journey ||
      old.nodes != nodes ||
      old.style.scale != style.scale ||
      old.style.active != style.active ||
      old.style.box != style.box;
}

// ── What is on the wire now ─────────────────────────────────────────────────

class _PduCard extends StatelessWidget {
  const _PduCard({required this.controller});

  final DownTheStackController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final FjStep s = controller.step;
    final String verb = switch (s.action) {
      FjAction.remove =>
        'Removed here: ${s.changed.map((FjPart p) => p.label).join(', ')}',
      _ => '',
    };
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AirtimeSectionTitle('${s.pduName}: ${s.pduBytes} bytes'),
          const SizedBox(height: AppSpacing.xs),
          FjPduStrip(pieces: s.pieces, changed: s.changed, action: s.action),
          if (fjPieceLegend(s.pieces).isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${fjPieceLegend(s.pieces)}.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          if (verb.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              verb,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── The addresses in force ──────────────────────────────────────────────────

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.controller});

  final DownTheStackController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final FjStep s = controller.step;
    final FjStep? prev = s.index > 0 ? controller.journey[s.index - 1] : null;
    final bool ttlChanged = prev != null && prev.ip.ttl != s.ip.ttl;
    final List<(String, String)> rows = <(String, String)>[
      ('Source IP', s.ip.src),
      ('Destination IP', s.ip.dst),
      ('TTL (time to live)', '${s.ip.ttl}'),
      ('Source port', '${s.ports.src}'),
      ('Destination port', '${s.ports.dst}'),
    ];
    final FjLink? link = s.link;
    final List<(String, String)> l2 = <(String, String)>[];
    String l2Title = 'MAC (media access control) addresses';
    if (link is FjWifiLink) {
      l2Title = '802.11 header: ${link.dsCase.label}';
      for (final AddressField f in link.fields) {
        l2.add((
          'Address ${f.number} (${f.roleText}): ${f.device.name}',
          f.mac.text,
        ));
      }
    } else if (link is FjEthLink) {
      l2Title = 'Ethernet header';
      l2
        ..add(('Destination: ${link.dst.name}', link.dst.mac.text))
        ..add(('Source: ${link.src.name}', link.src.mac.text));
    }
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle(
            'Ports and IP (Internet Protocol) addresses',
          ),
          const SizedBox(height: AppSpacing.xxs),
          FjReadoutTable(
            rows: rows,
            highlight: ttlChanged ? <String>{'TTL (time to live)'} : null,
          ),
          if (ttlChanged)
            Text(
              'TTL lowered by the router; the header checksum is recomputed.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          const SizedBox(height: AppSpacing.xs),
          AirtimeSectionTitle(l2Title),
          const SizedBox(height: AppSpacing.xxs),
          if (l2.isEmpty)
            Text(
              'No layer 2 header on the data at this point.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            )
          else
            FjReadoutTable(rows: l2, fitValues: true),
          if (link is FjWifiLink)
            Text(
              'RA receiver address, TA transmitter address, DA destination '
              'address, SA source address, BSSID basic service set identifier.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Addresses are illustrative; the IP addresses come from the '
            'ranges reserved for documentation.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── The To DS / From DS explorer ────────────────────────────────────────────

class DtsAddressExplorer extends StatelessWidget {
  const DtsAddressExplorer({super.key, required this.controller});

  final DownTheStackController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final DsExample e = controller.dsExampleNow;
    final DsCase c = e.dsCase;
    final List<AddressField> fields = e.fields;
    final TextStyle cell =
        text.bodyMedium?.copyWith(color: colors.textPrimary) ??
        TextStyle(color: colors.textPrimary);
    final TextStyle head =
        text.labelMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);

    Widget pad(Widget w) => Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxs,
        horizontal: AppSpacing.xxs,
      ),
      child: w,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'To DS ${c.toDsBit}, From DS ${c.fromDsBit}',
                style: text.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(c.meaning, style: cell),
              const SizedBox(height: AppSpacing.xs),
              DtsHopRow(example: e),
              const SizedBox(height: AppSpacing.xs),
              Text(
                e.story,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AirtimeSectionTitle(
                'Addresses 1 to ${fields.length}, a ${e.macHeader}-byte QoS '
                'Data header',
              ),
              const SizedBox(height: AppSpacing.xs),
              Table(
                columnWidths: const <int, TableColumnWidth>{
                  0: IntrinsicColumnWidth(),
                  1: FlexColumnWidth(1.1),
                  2: FlexColumnWidth(1.0),
                  3: FlexColumnWidth(1.3),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: <TableRow>[
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: colors.borderStrong),
                      ),
                    ),
                    children: <Widget>[
                      pad(Text('Field', style: head)),
                      pad(Text('Holds', style: head)),
                      pad(Text('Device', style: head)),
                      pad(Text('MAC', style: head)),
                    ],
                  ),
                  for (final AddressField f in fields)
                    TableRow(
                      children: <Widget>[
                        pad(Text('Address ${f.number}', style: cell)),
                        pad(
                          Text(
                            f.roleText,
                            style: cell.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        pad(Text(f.device.name, style: cell)),
                        pad(
                          Text(
                            f.mac.text,
                            style: mono.inlineCode.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (fields.length == 3)
                    TableRow(
                      children: <Widget>[
                        pad(Text('Address 4', style: head)),
                        pad(Text('not present', style: head)),
                        pad(const SizedBox.shrink()),
                        pad(const SizedBox.shrink()),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'RA receiver address, TA transmitter address, DA destination '
                'address, SA source address, BSSID basic service set '
                'identifier (the AP radio\'s MAC for this network). Address 1 '
                'is always the radio that must receive the frame; Address 2 is '
                'always the radio that sent it.',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              if (c == DsCase.both) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Why a fourth address: with both bits set, the radio sending '
                  'and the radio receiving are both relays. Addresses 1 and 2 '
                  'are taken by them, so two more fields carry where the frame '
                  'started and where it is going.',
                  style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Source, transmitter, receiver and destination in a row: which hop this
/// frame is on, and who plays which role.
class DtsHopRow extends StatelessWidget {
  const DtsHopRow({super.key, required this.example});

  final DsExample example;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final DsParties p = example.parties;
    final List<(FjDevice, List<String>)> cast = <(FjDevice, List<String>)>[];
    void put(FjDevice d, String role) {
      final int i = cast.indexWhere(
        ((FjDevice, List<String>) x) =>
            x.$1.mac == d.mac && x.$1.name == d.name,
      );
      if (i >= 0) {
        cast[i].$2.add(role);
      } else {
        cast.add((d, <String>[role]));
      }
    }

    put(p.source, 'SA');
    put(p.transmitter, 'TA');
    if (p.bssid != null && p.bssid!.mac == p.transmitter.mac) {
      put(p.transmitter, 'BSSID');
    }
    put(p.receiver, 'RA');
    if (p.bssid != null && p.bssid!.mac == p.receiver.mac) {
      put(p.receiver, 'BSSID');
    }
    put(p.destination, 'DA');

    final int txAt = cast.indexWhere(
      ((FjDevice, List<String>) x) => x.$2.contains('TA'),
    );

    Widget chip(FjDevice d, List<String> roles, bool onHop) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: onHop ? colors.primary : colors.borderStrong,
          width: onHop ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            d.name,
            style: text.labelLarge?.copyWith(color: colors.textPrimary),
          ),
          Text(
            roles.join(', '),
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    Widget link(bool thisHop) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Text(
        thisHop ? '~ this frame, on the air ~>' : '...',
        style: text.labelMedium?.copyWith(
          color: thisHop ? colors.textAccent : colors.textTertiary,
          fontWeight: thisHop ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );

    return Semantics(
      label:
          'This frame goes over the air from ${p.transmitter.name} to '
          '${p.receiver.name}. It started at ${p.source.name} and is going to '
          '${p.destination.name}.',
      excludeSemantics: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          for (int i = 0; i < cast.length; i++) ...<Widget>[
            if (i > 0) link(i == txAt + 1),
            chip(
              cast[i].$1,
              cast[i].$2,
              cast[i].$2.contains('TA') || cast[i].$2.contains('RA'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Geometry of the stack drawing.
class _Layout {
  const _Layout({
    required this.gutter,
    required this.colPitch,
    required this.colW,
    required this.top,
    required this.gap,
    required this.rowH,
    required this.mediumY,
  });

  final double gutter;
  final double colPitch;
  final double colW;
  final double top;
  final double gap;
  final double rowH;
  final double mediumY;

  double cx(int i) => gutter + colPitch * (i + 0.5);
  double rowTop(int r) => top + r * (rowH + gap);
}
