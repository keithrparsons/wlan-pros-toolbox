// Spectrum Band Designations — the ITU HF / VHF / UHF / SHF decade bands, what
// propagation each implies, and the neighbors a Wi-Fi pro should recognize (the
// VHF aviation airband and military UHF airband, plus the ISM/U-NII bands that
// overlap amateur allocations). The "why it matters when you talk to other
// hams, aircraft, and the military" framing.
//
// DATA: lib/data/ham_reference_data.dart (kItuBands, kSpectrumNeighbors).
//
// States (SOP-007 sec 5): a read-only reference. success = the bands and
// neighbors render; loading/error/empty are not reachable. The only interactive
// control is the AppCopyAction.
//
// THEME: chrome from context.colors; frequency spans in Roboto Mono (identifier
// face, GL-003 sec 8.5). No new tokens; no em dash (GL-004).
//
// ICON: bespoke Tier-2 icon resolves at assets/tool-icons/band-designations.svg
// when Charta ships it; falls back to the category glyph until then.

import 'package:flutter/material.dart';

import '../../../data/ham_reference_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_row_semantics.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kBandDesignationsToolId = 'band-designations';

class BandDesignationsScreen extends StatelessWidget {
  const BandDesignationsScreen({super.key});

  /// §8.16 copy payload — the ITU band table plus the neighbor table.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Spectrum Band Designations (ITU)')
      ..writeln(<String>[
        'Band',
        'Name',
        'Frequency',
        'Wavelength',
        'Propagation',
      ].join(tab));
    for (final ItuBandDesignation b in kItuBands) {
      buf.writeln(<String>[
        b.designation,
        b.name,
        b.frequency,
        b.wavelength,
        b.propagation,
      ].join(tab));
    }
    buf
      ..writeln()
      ..writeln('Each band is 10x the previous. Below HF: MF (300 kHz-3 MHz, '
          'AM broadcast + 160/630 m) and LF (30-300 kHz, 2200 m). Above SHF: '
          'EHF (30-300 GHz).')
      ..writeln()
      ..writeln('Neighbors a Wi-Fi pro should recognize')
      ..writeln(<String>['Service', 'Allocation', 'Mode', 'Why it matters']
          .join(tab));
    for (final SpectrumNeighbor n in kSpectrumNeighbors) {
      buf.writeln(
        <String>[n.service, n.allocation, n.mode, n.why].join(tab),
      );
    }
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spectrum Band Designations'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
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
                  _introCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  ...kItuBands.map(
                    (ItuBandDesignation b) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _BandCard(band: b),
                    ),
                  ),
                  _neighborsCard(context),
                  ToolHelpFooter(toolId: kBandDesignationsToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _introCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        'The ITU divides the radio spectrum into decade bands, each ten times '
        'the last. The Wi-Fi bands sit in UHF and SHF; knowing the band names '
        'and their propagation tells you who else you share the spectrum with, '
        'and why a 2.4 GHz signal behaves nothing like an HF one.',
        style: text.bodyMedium?.copyWith(color: colors.textPrimary),
      ),
    );
  }

  Widget _neighborsCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Neighbors a Wi-Fi pro should recognize',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...kSpectrumNeighbors.asMap().entries.expand(
            (MapEntry<int, SpectrumNeighbor> entry) {
              return <Widget>[
                if (entry.key > 0)
                  Divider(color: colors.border, height: AppSpacing.md),
                _NeighborRow(neighbor: entry.value),
              ];
            },
          ),
        ],
      ),
    );
  }
}

/// One ITU band: the designation + name, its frequency and wavelength spans in
/// mono, and the propagation paragraph.
class _BandCard extends StatelessWidget {
  const _BandCard({required this.band});

  final ItuBandDesignation band;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: ReferenceRowSemantics(
        merge: false,
        label: rowLabel(
          '${band.designation}, ${band.name}',
          <String?>[band.frequency, band.wavelength, band.propagation],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  band.designation,
                  style: text.titleLarge?.copyWith(
                    color: colors.textAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    band.name,
                    style: text.titleSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(band.frequency, style: mono.robotoMono),
                ),
                Expanded(
                  child: Text(
                    band.wavelength,
                    style: mono.robotoMono.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              band.propagation,
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// One neighbor service: the service name + allocation (mono), the mode, and
/// the "why it matters" line.
class _NeighborRow extends StatelessWidget {
  const _NeighborRow({required this.neighbor});

  final SpectrumNeighbor neighbor;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return ReferenceRowSemantics(
      merge: false,
      label: rowLabel(neighbor.service, <String?>[
        neighbor.allocation,
        neighbor.mode,
        neighbor.why,
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              neighbor.service,
              style: text.bodyLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(neighbor.allocation, style: mono.robotoMono),
            const SizedBox(height: 2),
            Text(
              neighbor.mode,
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              neighbor.why,
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
