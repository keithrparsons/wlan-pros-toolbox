// Modulation — a fully offline, read-only Quick Reference that teaches what
// modulation order means on the I/Q plane and why higher orders demand a cleaner
// link. Mirrors the sibling reference-screen idiom: Scaffold + AppBar
// (toolbarHeight 64) + AppCopyAction, SafeArea(top:false), LayoutBuilder
// isDesktop@720, Center + ConstrainedBox(calculatorMaxWidth), one
// SingleChildScrollView of cards built from semantic tokens, ToolHelpFooter.
//
// CONTENT: a short intro, then a gallery of eight Vera-passed, DARK-BAKED raster
// diagrams (Deliverables/2026-06-11-modulation-graphics): six constellations
// (BPSK, QPSK, 16/64/256/1024-QAM) in rising density, an Error Vector Magnitude
// explainer, and an order -> bits -> SNR/EVM summary capstone. Each is rendered
// in a DarkRasterDiagramCard (always-dark surface in both themes — the diagrams
// are dark-baked and cannot take the §8.20.7 light-mode swap; they would read
// inverted on a white canvas otherwise), tap-to-zoom for the detail-dense plane.
//
// REPRESENTATIVE NUMBERS (Keith-confirmed 2026-06-11): the per-card SNR and EVM
// figures are representative order-of-magnitude demands, NOT exact 802.11 MCS
// thresholds. The diagrams say so in their own footer, and the intro + help
// entry restate it so a reader never mistakes them for spec values (GL-005). The
// MCS Index tool carries the spec rate/modulation table; this screen teaches the
// concept.
//
// STATES (SOP-007 §5): a static bundled dataset — no fetch, so no loading /
// error / empty network paths exist. The success state is the rendered gallery.
// Each diagram card additionally degrades gracefully: the screen gates on
// ModulationDiagrams.isBundled before constructing a card, and the inner
// Image.asset has an errorBuilder, so a missing or undecodable asset is silently
// omitted — the intro and the other cards still read. No NetworkUnavailableView:
// works on every platform, no OS data, no I/O beyond the bundle.

import 'package:flutter/material.dart';

import '../../../data/modulation_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/tool_help_footer.dart';

class ModulationScreen extends StatelessWidget {
  const ModulationScreen({super.key});

  /// Catalog id — also the help-footer key.
  static const String toolId = 'modulation';

  /// The diagrams' true aspect ratio (2160 × 2700 source PNGs = 0.8 exactly).
  /// Pinned so each inline card is the right 4:5 portrait shape without
  /// measuring the image.
  static const double _diagramAspect = 2160 / 2700;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modulation'),
        toolbarHeight: 64,
        // §8.16 — copy the teaching summary as TSV. The content is a bundled
        // const, so the affordance is always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the modulation summary as a small TSV table plus the
  /// representative-numbers caveat. The diagrams are rasters (not copyable), so
  /// the copy carries the same facts as text. Always non-null: the data is
  /// static, so copy is never disabled.
  String _buildCopyText() {
    final StringBuffer buf = StringBuffer()
      ..writeln('Modulation')
      ..writeln()
      ..writeln(
          'Modulation\tPoints\tBits/symbol\tTypical SNR\tEVM ceiling');
    for (final List<String> row in _summaryRows) {
      buf.writeln(row.join('\t'));
    }
    buf
      ..writeln()
      ..writeln(_representativeCaveat);
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
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
                  Text(
                    'A constellation maps each transmitted symbol to a point on '
                    'the I/Q plane. Every step up in modulation order doubles '
                    'the points and adds one bit per symbol, so the link carries '
                    'more data - but the points sit closer together, so the '
                    'receiver needs a cleaner channel (lower EVM, higher SNR) to '
                    'tell them apart. Read the six constellations in order, then '
                    'the EVM explainer and the summary.',
                    style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _representativeCaveat,
                    style:
                        text.labelMedium?.copyWith(color: colors.textTertiary),
                  ),
                  for (final ModulationDiagram d in ModulationDiagrams.all)
                    if (ModulationDiagrams.isBundled(d.slug)) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      DarkRasterDiagramCard(
                        assetPath: ModulationDiagrams.pathFor(d.slug),
                        aspectRatio: _diagramAspect,
                        semanticLabel: d.title,
                      ),
                    ],
                  ToolHelpFooter(toolId: toolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The order -> bits -> SNR/EVM summary, mirroring the summary diagram's table
  /// so the §8.16 copy payload carries the same facts the raster shows.
  /// Representative figures, not exact MCS thresholds (see [_representativeCaveat]).
  static const List<List<String>> _summaryRows = <List<String>>[
    <String>['BPSK', '2', '1', '6 dB', '-10 dB'],
    <String>['QPSK', '4', '2', '9 dB', '-13 dB'],
    <String>['16-QAM', '16', '4', '16 dB', '-19 dB'],
    <String>['64-QAM', '64', '6', '22 dB', '-25 dB'],
    <String>['256-QAM', '256', '8', '28 dB', '-31 dB'],
    <String>['1024-QAM', '1024', '10', '34 dB', '-35 dB'],
  ];

  static const String _representativeCaveat =
      'SNR and EVM figures are representative order-of-magnitude demands, not '
      'exact 802.11 MCS thresholds. The relationship, not the precise number, '
      'is the point. See the MCS Index tool for the spec rate table.';
}
