// The stage for Multicast at the Basic Rate (Wi-Fi Classroom): the headline
// airtime shares, one second of the channel with its beacons and frames, a
// busy bar per lane, and one packet drawn to scale as a multicast frame and
// as unicast copies. Reads a [MulticastBasicRateController]; owns no state,
// so a presenter layout can place it beside [MulticastBasicRateControls].
//
// COLOR (GL-003 §8.13 / §8.15). No categorical hues. Lime marks the one
// quantity the tool is about: airtime on the channel (busy blocks, busy bars,
// data symbols). The one-packet close-up reuses Airtime Anatomy's block
// styles (paintAirtimeBlock), so a student who knows that tool reads this one
// the same way: hatching for waits, gray preamble, lime data, dashed SIFS,
// outlined ACK. The only status hue is the "does not fit" verdict, with an
// icon and words.
//
// MOTION (§8.8). The Play sweep draws the second as it happens, six times
// slower than real time. With reduced motion on, the second is drawn whole
// and nothing moves unless the user presses Play.
//
// ACCESSIBILITY. The drawings are pictures: each carries a worded Semantics
// label, and every number they show is also in text (SC 1.4.1).
//
// PRESENTER (PresenterMode.isActive): the stage fills its bounded box; the
// lanes and the close-up share the height, and the headline numbers use the
// presenter headline scale.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../services/wifi_lab/multicast_basic_rate_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'airtime_anatomy_timeline.dart'
    show AirtimeBlockStyle, paintAirtimeBlock;
import 'multicast_basic_rate_controller.dart';

/// Formats a share as a percentage: 0.738 -> "73.8%".
String mcPct(double share) => '${(share * 100).toStringAsFixed(1)}%';

/// Formats microseconds with a thousands separator: 1941.5 -> "1,941.5 µs".
String mcUs(double us) {
  final String fixed = us == us.roundToDouble()
      ? us.toStringAsFixed(0)
      : us.toStringAsFixed(1);
  final List<String> parts = fixed.split('.');
  final String whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (Match m) => '${m[1]},',
  );
  return '${parts.length > 1 ? '$whole.${parts[1]}' : whole} µs';
}

/// Formats milliseconds: 307200 us -> "307.2 ms".
String mcMs(double us) => '${(us / 1000).toStringAsFixed(1)} ms';

class MulticastBasicRateStage extends StatelessWidget {
  const MulticastBasicRateStage({super.key, required this.controller});

  final MulticastBasicRateController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final Widget headline = _Headline(controller: controller);
        final Widget second = _SecondCard(
          controller: controller,
          fill: presenting,
        );
        final Widget packet = _PacketCard(
          controller: controller,
          fill: presenting,
        );
        if (presenting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              headline,
              const SizedBox(height: AppSpacing.xs),
              Expanded(flex: 3, child: second),
              const SizedBox(height: AppSpacing.xs),
              Expanded(flex: 2, child: packet),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            headline,
            const SizedBox(height: AppSpacing.sm),
            second,
            const SizedBox(height: AppSpacing.sm),
            packet,
          ],
        );
      },
    );
  }
}

// ── Headline ────────────────────────────────────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline({required this.controller});

  final MulticastBasicRateController controller;

  @override
  Widget build(BuildContext context) {
    final McResult r = controller.result;
    final McConfig c = r.config;
    final McView v = controller.view;
    final bool masked = controller.masked;
    final List<Widget> tiles = <Widget>[
      if (v.showsMulticast)
        _HeadlineTile(
          label: 'Multicast at ${c.basicRate.label}',
          value: masked ? '?' : mcPct(r.multicastShare),
          note: masked
              ? 'of the channel: hidden until Reveal'
              : 'of the channel',
          semantics: masked
              ? 'Multicast airtime share hidden until Reveal'
              : 'Multicast at ${c.basicRate.label} uses '
                    '${mcPct(r.multicastShare)} of the channel',
        ),
      if (v.showsUnicast)
        _HeadlineTile(
          label:
              'Converted to unicast, ${c.listeners} listener'
              '${c.listeners == 1 ? '' : 's'}',
          value: masked ? '?' : mcPct(r.unicastShare),
          note: masked
              ? 'of the channel: hidden until Reveal'
              : 'of the channel',
          semantics: masked
              ? 'Unicast airtime share hidden until Reveal'
              : 'Converted to unicast for ${c.listeners} listeners uses '
                    '${mcPct(r.unicastShare)} of the channel',
        ),
      if (c.powerSave && v.showsMulticast)
        _HeadlineTile(
          label: 'Added delay from DTIM buffering',
          value: 'up to ${mcMs(r.maxDtimDelayUs)}',
          note:
              'average ${mcMs(r.meanDtimDelayUs)}; DTIM: delivery traffic '
              'indication message',
          semantics:
              'Multicast held for the DTIM beacon: up to '
              '${mcMs(r.maxDtimDelayUs)}, average ${mcMs(r.meanDtimDelayUs)}',
        ),
    ];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: tiles,
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

// ── One second of the channel ───────────────────────────────────────────────

class _SecondCard extends StatelessWidget {
  const _SecondCard({required this.controller, required this.fill});

  final MulticastBasicRateController controller;

  /// Fill a bounded box (presenter) instead of sizing to content.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final McResult r = controller.result;
    final McConfig c = r.config;
    final McView v = controller.view;
    final bool masked = controller.masked;
    final TextStyle laneLabel =
        text.labelMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);

    Widget lane({
      required String label,
      required List<McBlock> blocks,
      required double share,
      required String what,
    }) {
      final Widget paint = Semantics(
        label: masked
            ? '$label: hidden until Reveal'
            : '$label over one second: ${blocks.length} transmissions, '
                  '${mcPct(math.min(share, 1))} of the second busy',
        excludeSemantics: true,
        child: CustomPaint(
          painter: McLanePainter(
            blocks: masked ? const <McBlock>[] : blocks,
            beacons: r.beacons,
            colors: colors,
            scale: PresenterMode.scaleOf(context),
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
          McBusyBar(share: share, masked: masked, what: what),
        ],
      );
    }

    final List<Widget> lanes = <Widget>[
      if (v.showsMulticast)
        lane(
          label:
              'Multicast at ${c.basicRate.label} (${c.basicRate.phyLabel}), '
              'one frame per packet',
          blocks: r.multicastBlocks,
          share: r.multicastShare,
          what: 'Multicast',
        ),
      if (v.showsUnicast)
        lane(
          label:
              'Converted to unicast: ${c.listeners} cop'
              '${c.listeners == 1 ? 'y' : 'ies'} per packet',
          blocks: r.unicastBlocks,
          share: r.unicastShare,
          what: 'Unicast',
        ),
    ];

    final Widget axis = SizedBox(
      height: AppSpacing.md * PresenterMode.scaleOf(context).text,
      child: CustomPaint(
        painter: McAxisPainter(
          beacons: r.beacons,
          colors: colors,
          scale: PresenterMode.scaleOf(context),
          labelStyle: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
        child: const SizedBox.expand(),
      ),
    );

    final Widget legend = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        _GuideKey(dtim: false, label: 'Beacon, every 102.4 ms'),
        _GuideKey(
          dtim: true,
          label:
              'DTIM beacon (delivery traffic indication message), '
              'every ${c.dtimPeriod}',
        ),
      ],
    );

    final List<Widget> children = <Widget>[
      const AirtimeSectionTitle('One second of the channel'),
      Text(
        c.powerSave && v.showsMulticast
            ? 'A client is in power save, so the AP holds multicast and '
                  'sends it in a burst right after each DTIM beacon.'
            : 'Every busy block is air no other frame can use. Play sweeps '
                  'the second six times slower than real time.',
        style: text.bodySmall?.copyWith(color: colors.textTertiary),
      ),
      const SizedBox(height: AppSpacing.xs),
      axis,
      const SizedBox(height: AppSpacing.xxs),
    ];
    for (int i = 0; i < lanes.length; i++) {
      if (i > 0) children.add(const SizedBox(height: AppSpacing.xs));
      children.add(fill ? Expanded(child: lanes[i]) : lanes[i]);
    }
    children
      ..add(const SizedBox(height: AppSpacing.xs))
      ..add(legend);

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _GuideKey extends StatelessWidget {
  const _GuideKey({required this.dtim, required this.label});

  final bool dtim;
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
            width: AppSpacing.xs,
            height: AppSpacing.sm,
            child: CustomPaint(
              painter: _GuideSwatchPainter(dtim: dtim, colors: colors),
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

class _GuideSwatchPainter extends CustomPainter {
  _GuideSwatchPainter({required this.dtim, required this.colors});

  final bool dtim;
  final AppColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGuide(canvas, size.width / 2, 0, size.height, dtim, colors, 1);
  }

  @override
  bool shouldRepaint(_GuideSwatchPainter old) =>
      old.dtim != dtim || old.colors != colors;
}

/// A beacon guide line: a thin line, or a thick one for a DTIM beacon.
void _paintGuide(
  Canvas canvas,
  double x,
  double top,
  double bottom,
  bool dtim,
  AppColorScheme colors,
  double stroke,
) {
  canvas.drawLine(
    Offset(x, top),
    Offset(x, bottom),
    Paint()
      ..color = dtim ? colors.textSecondary : colors.borderStrong
      ..strokeWidth = (dtim ? 2.5 : 1) * stroke,
  );
}

/// The busy bar under a lane: share of the second, capped at 100%, and a
/// worded verdict when the stream does not fit.
class McBusyBar extends StatelessWidget {
  const McBusyBar({
    super.key,
    required this.share,
    required this.masked,
    required this.what,
  });

  final double share;
  final bool masked;
  final String what;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool overflow = !masked && share > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          label: masked
              ? '$what busy: hidden until Reveal'
              : '$what busy ${mcPct(share)} of the channel',
          excludeSemantics: true,
          child: Row(
            children: <Widget>[
              Text(
                'Busy',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  child: SizedBox(
                    height: AppSpacing.xs,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ColoredBox(color: colors.disabledFill),
                        if (!masked)
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: share.clamp(0.0, 1.0),
                            child: ColoredBox(color: colors.primary),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                masked ? '?' : mcPct(share),
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
        if (overflow)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.error_outline_rounded,
                  color: colors.statusDanger,
                  size: AppSpacing.sm,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    'Does not fit: needs ${mcPct(share)} of the channel. The '
                    'queue grows until packets are dropped.',
                    style: text.bodySmall?.copyWith(
                      color: colors.statusDanger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The time axis over the lanes: 0 to 1 s, and a mark at every beacon.
class McAxisPainter extends CustomPainter {
  McAxisPainter({
    required this.beacons,
    required this.colors,
    required this.scale,
    required this.labelStyle,
  });

  final List<McBeacon> beacons;
  final AppColorScheme colors;
  final PresenterScale scale;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final TextStyle style = (labelStyle ?? const TextStyle()).copyWith(
      fontSize: scale.paintFont(labelStyle?.fontSize ?? 12),
    );
    final double base = size.height - 1;
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = colors.border
        ..strokeWidth = scale.strokeWidth(1),
    );
    for (final McBeacon b in beacons) {
      final double x = b.atUs / kMcWindowUs * size.width;
      _paintGuide(
        canvas,
        x,
        base - (b.dtim ? AppSpacing.xs : AppSpacing.xxs),
        base,
        b.dtim,
        colors,
        scale.stroke,
      );
    }
    for (int ms = 0; ms <= 1000; ms += 250) {
      final String label = ms == 0 ? '0' : (ms == 1000 ? '1 s' : '$ms ms');
      final TextPainter tp = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      double x = ms / 1000 * size.width - tp.width / 2;
      x = x.clamp(0, math.max(0, size.width - tp.width));
      tp.paint(canvas, Offset(x, 0));
    }
  }

  @override
  bool shouldRepaint(McAxisPainter old) =>
      old.beacons != beacons ||
      old.colors != colors ||
      old.scale != scale ||
      old.labelStyle != labelStyle;
}

/// One lane of the second: beacon guides, the busy blocks up to the
/// playhead, and the playhead itself while a sweep is under way.
class McLanePainter extends CustomPainter {
  McLanePainter({
    required this.blocks,
    required this.beacons,
    required this.colors,
    required this.scale,
    required this.playhead,
  }) : super(repaint: playhead);

  final List<McBlock> blocks;
  final List<McBeacon> beacons;
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
    for (final McBeacon b in beacons) {
      _paintGuide(
        canvas,
        b.atUs / kMcWindowUs * size.width,
        0,
        size.height,
        b.dtim,
        colors,
        scale.stroke,
      );
    }
    final double head = playhead.value.clamp(0.0, 1.0);
    final double headUs = head * kMcWindowUs;
    final double pxPerUs = size.width / kMcWindowUs;
    final double top = size.height * 0.2;
    final double bottom = size.height * 0.8;
    final Paint fill = Paint()..color = colors.primary;

    // Coalesce blocks into pixel spans: thousands of frames can land in a
    // few hundred pixels. Every block is at least one pixel wide so a short
    // frame is still seen.
    double? spanL;
    double spanR = 0;
    void flush() {
      if (spanL != null) {
        canvas.drawRect(Rect.fromLTRB(spanL, top, spanR, bottom), fill);
      }
    }

    for (final McBlock b in blocks) {
      if (b.startUs >= headUs) break;
      final double l = b.startUs * pxPerUs;
      double r = math.min(math.min(b.endUs, headUs), kMcWindowUs) * pxPerUs;
      if (r - l < 1) r = l + 1;
      if (spanL != null && l <= spanR + 0.5) {
        spanR = math.max(spanR, r);
      } else {
        flush();
        spanL = l;
        spanR = r;
      }
    }
    flush();

    if (head < 1) {
      final double x = head * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = colors.textPrimary
          ..strokeWidth = scale.strokeWidth(2),
      );
    }
  }

  @override
  bool shouldRepaint(McLanePainter old) =>
      old.blocks != blocks ||
      old.beacons != beacons ||
      old.colors != colors ||
      old.scale != scale ||
      old.playhead != playhead;
}

// ── One packet, to scale ────────────────────────────────────────────────────

/// One segment of the close-up bar.
typedef McSegment = ({AirtimeBlockStyle style, int tenths});

/// The multicast frame's segments: DIFS, backoff, preamble, data. No ACK.
List<McSegment> multicastSegments(MulticastTiming t) => <McSegment>[
  (style: AirtimeBlockStyle.wait, tenths: t.difsTenths),
  (style: AirtimeBlockStyle.wait, tenths: t.backoffTenths),
  (style: AirtimeBlockStyle.preamble, tenths: t.preambleTenths),
  (style: AirtimeBlockStyle.data, tenths: t.dataTenths),
];

/// The unicast copies' segments, copy after copy.
List<McSegment> unicastSegments(List<UnicastCopy> copies) => <McSegment>[
  for (final UnicastCopy u in copies) ...<McSegment>[
    (style: AirtimeBlockStyle.wait, tenths: u.waitTenths),
    (style: AirtimeBlockStyle.preamble, tenths: u.preambleTenths),
    (style: AirtimeBlockStyle.data, tenths: u.dataTenths),
    (style: AirtimeBlockStyle.gap, tenths: u.sifsTenths),
    (style: AirtimeBlockStyle.control, tenths: u.ackTenths),
  ],
];

class _PacketCard extends StatelessWidget {
  const _PacketCard({required this.controller, required this.fill});

  final MulticastBasicRateController controller;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final McResult r = controller.result;
    final McConfig c = r.config;
    final McView v = controller.view;
    final int mcT = r.multicast.totalTenths;
    final int ucT = r.unicastPerPacketTenths;
    final int scaleTenths = math.max(
      v.showsMulticast ? mcT : 0,
      v.showsUnicast ? ucT : 0,
    );
    final TextStyle rowLabel =
        text.labelMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);

    Widget bar(List<McSegment> segs, String semantics) {
      final Widget paint = Semantics(
        label: semantics,
        excludeSemantics: true,
        child: CustomPaint(
          painter: McPacketPainter(
            segments: segs,
            scaleTenths: scaleTenths,
            colors: colors,
            scale: scale,
          ),
          child: const SizedBox.expand(),
        ),
      );
      return fill
          ? Expanded(child: paint)
          : SizedBox(height: AppSpacing.lg, child: paint);
    }

    final String mcLabel =
        'Multicast frame at ${c.basicRate.label}: ${mcUs(r.multicast.totalUs)}, '
        'no acknowledgment, no retry';
    final String ucLabel =
        '${c.listeners} unicast cop${c.listeners == 1 ? 'y' : 'ies'} '
        '(Wi-Fi 6, 20 MHz, 2 spatial streams: illustrative), each at its '
        'listener\'s MCS (modulation and coding scheme): '
        '${mcUs(ucT / 10)}, each acknowledged';

    final List<Widget> children = <Widget>[
      const AirtimeSectionTitle('One packet, drawn to scale'),
      const SizedBox(height: AppSpacing.xs),
      if (v.showsMulticast) ...<Widget>[
        Text(mcLabel, style: rowLabel),
        const SizedBox(height: AppSpacing.xxs),
        bar(multicastSegments(r.multicast), mcLabel),
      ],
      if (v.showsMulticast && v.showsUnicast)
        const SizedBox(height: AppSpacing.xs),
      if (v.showsUnicast) ...<Widget>[
        Text(ucLabel, style: rowLabel),
        const SizedBox(height: AppSpacing.xxs),
        bar(unicastSegments(r.copies), ucLabel),
      ],
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: const <Widget>[
          _BlockKey(
            AirtimeBlockStyle.wait,
            'Waiting: DIFS (distributed interframe space) or AIFS '
            '(arbitration interframe space), then backoff',
          ),
          _BlockKey(AirtimeBlockStyle.preamble, 'Preamble'),
          _BlockKey(AirtimeBlockStyle.data, 'Data'),
          _BlockKey(AirtimeBlockStyle.gap, 'SIFS (short interframe space)'),
          _BlockKey(AirtimeBlockStyle.control, 'ACK (acknowledgment)'),
        ],
      ),
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

class _BlockKey extends StatelessWidget {
  const _BlockKey(this.style, this.label);

  final AirtimeBlockStyle style;
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
              painter: _BlockSwatchPainter(style: style, colors: colors),
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

class _BlockSwatchPainter extends CustomPainter {
  _BlockSwatchPainter({required this.style, required this.colors});

  final AirtimeBlockStyle style;
  final AppColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) =>
      paintAirtimeBlock(canvas, Offset.zero & size, style, colors);

  @override
  bool shouldRepaint(_BlockSwatchPainter old) =>
      old.style != style || old.colors != colors;
}

/// One packet's bar, every segment to one microsecond scale shared with the
/// other bar on screen.
class McPacketPainter extends CustomPainter {
  McPacketPainter({
    required this.segments,
    required this.scaleTenths,
    required this.colors,
    required this.scale,
  });

  final List<McSegment> segments;
  final int scaleTenths;
  final AppColorScheme colors;
  final PresenterScale scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (scaleTenths <= 0) return;
    final double pxPerTenth = size.width / scaleTenths;
    double x = 0;
    for (final McSegment s in segments) {
      final double w = s.tenths * pxPerTenth;
      if (w > 0) {
        paintAirtimeBlock(
          canvas,
          Rect.fromLTWH(x, 0, w, size.height),
          s.style,
          colors,
          stroke: w < 3 ? 0.5 : scale.stroke,
        );
      }
      x += w;
    }
  }

  @override
  bool shouldRepaint(McPacketPainter old) =>
      old.segments != segments ||
      old.scaleTenths != scaleTenths ||
      old.colors != colors ||
      old.scale != scale;
}
