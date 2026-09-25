// MimoStage: the pictures half of the MIMO and Beamforming simulator.
//
// Three cards: the streams diagram (with the direction switch), the beam
// pattern seen from above (client and a movable sniffer), and the sounding
// exchange drawn to scale. Takes the shared MimoController and nothing else,
// so a phone layout can stack it with MimoControls and a presenter layout can
// put the two side by side. Dragging the pattern moves the client or the
// sniffer through the controller; the sliders in MimoControls do the same
// thing for keyboard users.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/mimo_beamforming_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';
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
    return MimoPaintStyle(
      accent: colors.textAccent,
      primary: colors.textPrimary,
      secondary: colors.textSecondary,
      tertiary: colors.textTertiary,
      grid: colors.border,
      axis: colors.borderStrong,
      fill: colors.surface3,
      background: colors.surface2,
      labelStyle: mono.inlineCode.copyWith(
        fontSize: AppTextSize.caption - 2,
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
        double at(Offset p) => BeamPatternPainter.angleAt(p, size);
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
