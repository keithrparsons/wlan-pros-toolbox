// MimoStage: the pictures half of the MIMO and Beamforming simulator.
//
// Three cards: the streams diagram (with the direction switch), the beam
// pattern seen from above (client and a movable sniffer), and the sounding
// exchange drawn to scale. Takes the shared MimoController and nothing else,
// so a phone layout can stack it with MimoControls and a presenter layout can
// put the two side by side. Dragging the pattern moves the client or the
// sniffer through the controller; the sliders in MimoControls do the same
// thing for keyboard users.
//
// PRESENTER (PresenterMode.isActive): the stage fills its bounded box with no
// scroll. The stream count is the headline, with the direction switch beside
// it (a view setting over the view). The streams diagram and the beam
// pattern share the height side by side; under the pattern sit the sniffer's
// verdict and level and our capture measurement, the numbers the capture
// lesson is about; the sounding strip and its share of airtime run along the
// bottom. Painters get the presenter scale through MimoPaintStyle.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/mimo_beamforming_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'mimo_beamforming_controller.dart';
import 'mimo_beamforming_painters.dart';
import 'mimo_beamforming_palette.dart';
import 'mimo_beamforming_parts.dart';

typedef _C = MimoController;

class MimoStage extends StatelessWidget {
  const MimoStage({super.key, required this.controller});

  final MimoController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final MimoPaintStyle style = paintStyle(context);
        if (PresenterMode.isActive(context)) {
          return _PresenterStage(controller: controller, style: style);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _StreamsCard(controller: controller, style: style),
            const SizedBox(height: AppSpacing.sm),
            _PatternCard(controller: controller, style: style),
            const SizedBox(height: AppSpacing.sm),
            _SoundingCard(controller: controller, style: style),
          ],
        );
      },
    );
  }

  static MimoPaintStyle paintStyle(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    return MimoPaintStyle(
      scale: scale,
      accent: colors.textAccent,
      primary: colors.textPrimary,
      secondary: colors.textSecondary,
      tertiary: colors.textTertiary,
      grid: colors.border,
      axis: colors.borderStrong,
      fill: colors.surface3,
      background: colors.surface2,
      labelStyle: mono.inlineCode.copyWith(
        fontSize: scale.paintFont(AppTextSize.caption - 2),
        color: colors.textSecondary,
      ),
    );
  }
}

/// A plot surface: surface-2, rounded, labelled for screen readers.
class _PlotSurface extends StatelessWidget {
  const _PlotSurface({
    required this.height,
    required this.semantic,
    required this.child,
  });

  final double height;
  final String semantic;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      label: semantic,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(height: height, color: colors.surface2, child: child),
      ),
    );
  }
}

// ── Presenter arrangement ───────────────────────────────────────────────────

class _PresenterStage extends StatelessWidget {
  const _PresenterStage({required this.controller, required this.style});

  final MimoController controller;
  final MimoPaintStyle style;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final MimoController c = controller;
    final MimoLink link = c.link;
    final int n = link.streams;
    final bool down = link.direction == LinkDirection.downlink;

    return MbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '$n spatial stream${n == 1 ? '' : 's'}',
                        style: scale
                            .headlineStyle(mono.outputMedium)
                            .copyWith(color: colors.textAccent),
                      ),
                      Text(
                        '${down ? 'Downlink, AP to client' : 'Uplink, client to AP'}. '
                        '${c.apChains}x${c.apChains} AP, '
                        '${c.clientChains}x${c.clientChains} client: the '
                        'smaller side sets the streams.',
                        style: text.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 280,
                child: AppToggle<LinkDirection>(
                  value: c.direction,
                  expand: true,
                  semanticLabel: 'Direction',
                  items: const <AppToggleItem<LinkDirection>>[
                    (LinkDirection.downlink, 'Downlink'),
                    (LinkDirection.uplink, 'Uplink'),
                  ],
                  onChanged: (LinkDirection d) => c.direction = d,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  flex: 4,
                  child: _PresenterStreams(controller: c, style: style),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 5,
                  child: _PresenterPattern(controller: c, style: style),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _PresenterSounding(controller: c, style: style),
        ],
      ),
    );
  }
}

class _PresenterStreams extends StatelessWidget {
  const _PresenterStreams({required this.controller, required this.style});

  final MimoController controller;
  final MimoPaintStyle style;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MimoController c = controller;
    final MimoLink link = c.link;
    final MimoStreamPalette palette = MimoStreamPalette.of(context);
    final List<String> notes = _StreamsCard.spareChainNotes(link);
    final bool down = link.direction == LinkDirection.downlink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const MbSectionLabel('Streams and spare chains'),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: _PlotSurface(
            height: double.infinity,
            semantic:
                '${link.direction.label}. The AP has ${c.apChains} chains and '
                'the client ${c.clientChains}, so ${link.streams} spatial '
                'stream${link.streams == 1 ? '' : 's'}. ${notes.join(' ')}',
            child: CustomPaint(
              size: Size.infinite,
              painter: StreamsPainter(
                link: link,
                streamColors: palette.colors,
                style: style,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        MbLegend(
          items: <MbLegendItem>[
            MbLegendItem(
              swatch: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colors.textPrimary,
                  shape: BoxShape.circle,
                ),
              ),
              label: 'Chain in use',
            ),
            MbLegendItem(
              swatch: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colors.textSecondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.textPrimary),
                ),
              ),
              label: 'Spare, helping',
            ),
            MbLegendItem(
              swatch: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.textTertiary, width: 1.5),
                ),
              ),
              label: 'Spare, idle',
            ),
          ],
        ),
        for (final String note in notes)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: MbNote(
              icon: down ? Icons.south_east : Icons.north_west,
              message: note,
            ),
          ),
      ],
    );
  }
}

class _PresenterPattern extends StatelessWidget {
  const _PresenterPattern({required this.controller, required this.style});

  final MimoController controller;
  final MimoPaintStyle style;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final MimoController c = controller;
    final bool ok = c.snifferDecodes;
    final int n = c.streams;
    final TextStyle big = scale.headlineStyle(mono.outputMedium);

    Widget stat(String label, String value, {Color? color, IconData? icon}) =>
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, color: color, size: big.fontSize),
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                  Text(
                    value,
                    style: big.copyWith(color: color ?? colors.textPrimary),
                  ),
                ],
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const MbSectionLabel('Beam pattern, seen from above'),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: _PlotSurface(
            height: double.infinity,
            semantic: c.steered
                ? 'Beam pattern seen from above: the AP array of '
                      '${c.apChains} elements steers its main lobe at the '
                      'client, ${_C.deg(c.clientDeg)}. The sniffer, '
                      '${_C.deg(c.snifferDeg)}, receives '
                      '${_C.db(c.snifferRelativeDb)} against the client.'
                : 'Seen from above, nothing steered. Client '
                      '${_C.deg(c.clientDeg)}, sniffer ${_C.deg(c.snifferDeg)}.',
            child: _PatternDrag(controller: c, style: style),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            stat(
              'Sniffer separates the $n stream${n == 1 ? '' : 's'}',
              ok ? 'Yes' : 'No',
              color: ok ? null : colors.statusDanger,
              icon: ok ? null : Icons.error_outline,
            ),
            stat(
              'Sniffer level vs the client',
              c.steered ? _C.db(c.snifferRelativeDb) : 'not steered',
              color: colors.textAccent,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Our capture (one sniffer, signal-matched): beamformed frames '
          'failed FCS ${CaptureMeasurement.fcsFailBeamformedPct}% of the time, '
          'not beamformed ${CaptureMeasurement.fcsFailNotBeamformedPct}%.',
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _PresenterSounding extends StatelessWidget {
  const _PresenterSounding({required this.controller, required this.style});

  final MimoController controller;
  final MimoPaintStyle style;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final MimoController c = controller;
    if (!c.sounding) {
      return MbNote(
        icon: Icons.block,
        message: c.apCanBeamform
            ? 'Sounding: none. Beamforming is off, so the AP never sounds '
                  'the client and spends no airtime on it.'
            : 'Sounding: none. A 1-chain AP cannot beamform.',
      );
    }
    final SoundingEstimate s = c.soundingEstimate;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Semantics(
            label:
                'Sounding exchange to scale, ${_C.us(s.totalUs)} in all, '
                'repeated every ${_C.ms(c.intervalMs)}: '
                '${_C.pct(c.soundingShare)} of the airtime for one client.',
            excludeSemantics: true,
            child: SizedBox(
              height: SoundingPainter.heightFor(scale.text),
              child: CustomPaint(
                size: Size.infinite,
                painter: SoundingPainter(
                  segments: s.segments,
                  share: c.soundingShare,
                  style: style,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Sounding, one client',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              Text(
                _C.pct(c.soundingShare),
                style: scale
                    .headlineStyle(mono.outputMedium)
                    .copyWith(color: colors.textAccent),
              ),
              Text(
                '${_C.us(s.totalUs)} every ${_C.ms(c.intervalMs)}',
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Streams ─────────────────────────────────────────────────────────────────

class _StreamsCard extends StatelessWidget {
  const _StreamsCard({required this.controller, required this.style});

  final MimoController controller;
  final MimoPaintStyle style;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MimoController c = controller;
    final MimoLink link = c.link;
    final MimoStreamPalette palette = MimoStreamPalette.of(context);
    final List<String> notes = spareChainNotes(link);
    final bool down = link.direction == LinkDirection.downlink;
    final String semantic =
        '${link.direction.label}, ${link.direction.detail}. The AP has '
        '${c.apChains} chains and the client ${c.clientChains}, so '
        '${link.streams} spatial stream${link.streams == 1 ? '' : 's'}, '
        'labeled S1 to S${link.streams}. ${notes.join(' ')}';
    final double height = 64 + 22.0 * (c.apChains > 4 ? 8 : 4);
    return MbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MbSectionLabel('Streams and spare chains'),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<LinkDirection>(
            value: c.direction,
            expand: true,
            semanticLabel: 'Direction',
            items: const <AppToggleItem<LinkDirection>>[
              (LinkDirection.downlink, 'Downlink'),
              (LinkDirection.uplink, 'Uplink'),
            ],
            onChanged: (LinkDirection d) => c.direction = d,
          ),
          const SizedBox(height: AppSpacing.xs),
          _PlotSurface(
            height: height,
            semantic: semantic,
            child: CustomPaint(
              size: Size.infinite,
              painter: StreamsPainter(
                link: link,
                streamColors: palette.colors,
                style: style,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          MbLegend(
            items: <MbLegendItem>[
              for (int i = 0; i < link.streams; i++)
                MbLegendItem.line(
                  color: palette.stream(i),
                  width: 3,
                  label: 'S${i + 1}',
                ),
              MbLegendItem(
                swatch: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
                label: 'Chain in use',
              ),
              MbLegendItem(
                swatch: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colors.textSecondary,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.textPrimary),
                  ),
                ),
                label: 'Spare, helping (dashed)',
              ),
              MbLegendItem(
                swatch: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.textTertiary, width: 1.5),
                  ),
                ),
                label: 'Spare, idle',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final String n in notes)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: MbNote(
                icon: down ? Icons.south_east : Icons.north_west,
                message: n,
              ),
            ),
        ],
      ),
    );
  }

  /// One sentence per side that has spare chains, naming what they do and
  /// labeling every gain as an ideal upper bound.
  static List<String> spareChainNotes(MimoLink l) {
    final bool down = l.direction == LinkDirection.downlink;
    final String tx = down ? 'AP' : 'Client';
    final String rx = down ? 'Client' : 'AP';
    final List<String> out = <String>[];
    String chains(int n) => '$n spare chain${n == 1 ? '' : 's'}';
    if (l.spareTx > 0) {
      if (l.isBeamformed) {
        out.add(
          '$tx: ${chains(l.spareTx)} steer the signal at the client '
          '(transmit beamforming): ${_C.gain(l.idealTxBfGainDb)}, an ideal '
          'upper bound.',
        );
      } else if (down) {
        out.add(
          '$tx: ${chains(l.spareTx)} add no steering while beamforming is '
          'off.',
        );
      } else {
        out.add(
          '$tx: ${chains(l.spareTx)} add no steering: clients seldom '
          'beamform, so this model does not.',
        );
      }
    }
    if (l.spareRx > 0) {
      out.add(
        '$rx: ${chains(l.spareRx)} listen too and combine what they hear '
        '(receive diversity): ${_C.gain(l.idealCombiningGainDb)}, an ideal '
        'upper bound.',
      );
    }
    if (out.isEmpty) {
      out.add('No spare chains: every chain carries a stream.');
    }
    return out;
  }
}

// ── Beam pattern ────────────────────────────────────────────────────────────

class _PatternCard extends StatelessWidget {
  const _PatternCard({required this.controller, required this.style});

  final MimoController controller;
  final MimoPaintStyle style;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MimoController c = controller;
    final bool steered = c.steered;
    final String why = !steered
        ? (c.direction == LinkDirection.uplink
              ? 'Uplink: the client transmits and does not beamform, so '
                    'nothing is steered.'
              : !c.apCanBeamform
              ? 'A 1-chain AP has nothing to steer with.'
              : 'Beamforming is off, so nothing is steered.')
        : '';
    final String semantic = steered
        ? 'Beam pattern seen from above: the AP array of ${c.apChains} '
              'elements steers its main lobe at the client, '
              '${_C.deg(c.clientDeg)}. The sniffer, ${_C.deg(c.snifferDeg)}, '
              'receives ${_C.db(c.snifferRelativeDb)} against the client.'
        : 'Seen from above: $why The level is the same in every direction. '
              'Client ${_C.deg(c.clientDeg)}, sniffer '
              '${_C.deg(c.snifferDeg)}.';
    return MbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MbSectionLabel('Beam pattern, seen from above'),
          const SizedBox(height: AppSpacing.xs),
          _PlotSurface(
            height: 230,
            semantic: semantic,
            child: _PatternDrag(controller: c, style: style),
          ),
          const SizedBox(height: AppSpacing.xs),
          MbLegend(
            items: <MbLegendItem>[
              MbLegendItem.line(
                color: colors.textAccent,
                width: 3,
                dashed: !steered,
                label: steered ? 'Steered beam' : 'Not steered',
              ),
              MbLegendItem(
                swatch: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
                label: 'Client',
              ),
              MbLegendItem(
                swatch: Container(
                  width: 10,
                  height: 10,
                  color: colors.textSecondary,
                ),
                label: 'Sniffer',
              ),
              MbLegendItem.line(
                color: colors.border,
                width: 1,
                label: 'Rings every 10 dB',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          MbNote(
            icon: Icons.info_outline,
            message: steered
                ? 'Line of sight, one steered stream, elements half a '
                      'wavelength apart. The outer ring is the client\'s '
                      'level; the sniffer hears what the curve reaches at its '
                      'angle. Drag the client or the sniffer.'
                : '$why Drag the client or the sniffer.',
          ),
        ],
      ),
    );
  }
}

/// The pattern painter with drag: a touch moves whichever of the client and
/// the sniffer is nearer by angle, and keeps moving it for the whole drag.
class _PatternDrag extends StatefulWidget {
  const _PatternDrag({required this.controller, required this.style});

  final MimoController controller;
  final MimoPaintStyle style;

  @override
  State<_PatternDrag> createState() => _PatternDragState();
}

class _PatternDragState extends State<_PatternDrag> {
  bool _movingClient = false;

  void _pick(double angle) {
    final MimoController c = widget.controller;
    _movingClient = (angle - c.clientDeg).abs() <= (angle - c.snifferDeg).abs();
  }

  void _move(double angle) {
    final MimoController c = widget.controller;
    final double a = angle.roundToDouble();
    if (_movingClient) {
      c.clientDeg = a;
    } else {
      c.snifferDeg = a;
    }
  }

  @override
  Widget build(BuildContext context) {
    final MimoController c = widget.controller;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final Size size = Size(box.maxWidth, box.maxHeight);
        double at(Offset p) => BeamPatternPainter.angleAt(
          p,
          size,
          labelRoom: widget.style.scale.text,
        );
        return MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails e) {
              final double a = at(e.localPosition);
              _pick(a);
              _move(a);
            },
            onPanStart: (DragStartDetails e) => _pick(at(e.localPosition)),
            onPanUpdate: (DragUpdateDetails e) => _move(at(e.localPosition)),
            child: CustomPaint(
              size: size,
              painter: BeamPatternPainter(
                elements: c.apChains,
                steered: c.steered,
                clientDeg: c.clientDeg,
                snifferDeg: c.snifferDeg,
                style: widget.style,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Sounding ────────────────────────────────────────────────────────────────

class _SoundingCard extends StatelessWidget {
  const _SoundingCard({required this.controller, required this.style});

  final MimoController controller;
  final MimoPaintStyle style;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MimoController c = controller;
    final TextTheme text = Theme.of(context).textTheme;
    if (!c.sounding) {
      return MbCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const MbSectionLabel('What beamforming costs: sounding'),
            const SizedBox(height: AppSpacing.xs),
            MbNote(
              icon: Icons.block,
              message: c.apCanBeamform
                  ? 'Beamforming is off, so the AP never sounds the client '
                        'and spends no airtime on it. Turn it on to see the '
                        'cost.'
                  : 'A 1-chain AP cannot beamform, so there is nothing to '
                        'sound.',
            ),
          ],
        ),
      );
    }
    final SoundingEstimate s = c.soundingEstimate;
    final List<SoundingSegment> segs = s.segments;
    final String semantic =
        'Sounding exchange to scale: NDP Announcement ${_C.us(s.ndpaUs)}, '
        'SIFS, NDP ${_C.us(s.ndpUs)}, SIFS, compressed beamforming report '
        '${_C.us(s.reportUs)}; ${_C.us(s.totalUs)} in all. Repeated every '
        '${_C.ms(c.intervalMs)}, that is ${_C.pct(c.soundingShare)} of the '
        'airtime for one client.';
    return MbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MbSectionLabel('What beamforming costs: sounding'),
          const SizedBox(height: AppSpacing.xs),
          _PlotSurface(
            height: 118,
            semantic: semantic,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: CustomPaint(
                size: Size.infinite,
                painter: SoundingPainter(
                  segments: segs,
                  share: c.soundingShare,
                  style: style,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ExcludeSemantics(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                for (final SoundingSegment g in segs.where(
                  (SoundingSegment g) => !g.isGap,
                ))
                  Text(
                    '${g.name} ${_C.us(g.us)}',
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                Text(
                  'SIFS ${_C.us(kSifsUs)} each',
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          MbLegend(
            items: <MbLegendItem>[
              MbLegendItem(
                swatch: Container(
                  width: 14,
                  height: 8,
                  color: colors.textAccent,
                ),
                label: 'Sounding share of the interval',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
