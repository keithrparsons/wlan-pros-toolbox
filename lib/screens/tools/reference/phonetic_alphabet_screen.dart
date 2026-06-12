// Phonetic Alphabet — read-only A-Z reference (Tier-1, Pass 2b 2026-06-12).
//
// The native A-Z table carries letter -> ICAO/NATO word -> Morse. The semaphore
// arm dials and the maritime signal flags are the VISUAL the table cannot
// reproduce (the colorful flags and the two-flag arm bearings are the value), so
// the staged plate PNG is embedded via the established DarkRasterDiagramCard
// (always-dark in both themes, tap to pinch-zoom; the plate is dark-baked except
// the maritime flags, which keep their real international-code-of-signals colors
// per Keith). Every letter/word/Morse fact the plate shows is ALSO in the native
// table, so the image is decorative for screen readers, never the sole carrier.
//
// ICAO official spelling is preserved: Alfa, Juliett.
//
// States (SOP-007 §5):
//  - success    → the table always renders (compile-time const data); the plate
//    card appears only when its PNG is bundled (ReferenceImages.isBundled),
//    otherwise it is omitted and the table still reads end-to-end.
//  - loading / empty / error → not reachable; nothing fetched or parsed.
//  - interactive→ the plate's tap-to-zoom + the AppBar §8.16 copy action.
//  - disabled   → copy is always enabled (const content always present).
//
// THEME: chrome from context.colors (dark §8 / light §8.20). No new tokens.
// Glyph note: no em dash in prose; Morse uses ASCII dot/dash.

import 'package:flutter/material.dart';

import '../../../data/phonetic_alphabet_data.dart';
import '../../../data/reference_images.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_row_semantics.dart';

/// Stable catalog tool id — backs the route, the help entry, the bundled plate
/// PNG (assets/reference/phonetic-alphabet.png), and the tests.
const String kPhoneticAlphabetToolId = 'phonetic-alphabet';

class PhoneticAlphabetScreen extends StatelessWidget {
  const PhoneticAlphabetScreen({super.key});

  /// The plate's true aspect ratio (width / height), pinned so the inline card
  /// is the right shape with no measuring and no letterbox gutters.
  static const double _plateAspect = 2720 / 2526;

  /// §8.16 plain-text payload — the A-Z table (letter, word, Morse) plus the
  /// legend and note. Always non-null (static data).
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Phonetic Alphabet (NATO / ICAO)')
      ..writeln(<String>['Letter', 'NATO word', 'Morse'].join(tab));
    for (final PhoneticLetter p in kPhoneticAlphabet) {
      final String word = p.variant.isEmpty
          ? p.word
          : '${p.word} (variant ${p.variant})';
      b.writeln(<String>[p.letter, word, p.morse].join(tab));
    }
    b.writeln();
    for (final String line in kPhoneticLegend) {
      b.writeln(line);
    }
    b
      ..writeln()
      ..writeln(kPhoneticNote);
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phonetic Alphabet'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _copyText)],
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
        final bool hasPlate = ReferenceImages.isBundled(
          kPhoneticAlphabetToolId,
        );
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
                  if (hasPlate) ...<Widget>[
                    DarkRasterDiagramCard(
                      assetPath: ReferenceImages.pathFor(
                        kPhoneticAlphabetToolId,
                      ),
                      aspectRatio: _plateAspect,
                      semanticLabel:
                          'semaphore arm positions and maritime signal flags '
                          'for A to Z',
                      caption:
                          'Each letter as a semaphore arm position and an '
                          'international maritime signal flag. Tap to zoom.',
                      // The plate's bottom row carries the baked signal-flag
                      // legend; place the zoom badge in the clear dark band at
                      // top-center so it never sits over the legend text.
                      zoomBadgeAlignment: Alignment.topCenter,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const _AlphabetCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _LegendCard(),
                  ToolHelpFooter(toolId: kPhoneticAlphabetToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The native A-Z table: letter | NATO word (+ variant) | Morse.
class _AlphabetCard extends StatelessWidget {
  const _AlphabetCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);
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
            '${kPhoneticAlphabet.length} letters',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          HorizontalScrollTable(
            child: DataTable(
              headingRowHeight: 44,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 52,
              columnSpacing: AppSpacing.md,
              horizontalMargin: 0,
              dividerThickness: 1,
              headingTextStyle: headStyle,
              columns: const <DataColumn>[
                DataColumn(label: Text('Letter')),
                DataColumn(label: Text('NATO word')),
                DataColumn(label: Text('Morse')),
              ],
              rows: kPhoneticAlphabet.map((PhoneticLetter p) {
                final String summary = rowLabel(p.letter, <String?>[
                  p.word,
                  p.variant.isEmpty ? null : 'variant ${p.variant}',
                  'Morse ${_spokenMorse(p.morse)}',
                ]);
                return DataRow(
                  cells: <DataCell>[
                    DataCell(
                      Semantics(
                        label: summary,
                        container: true,
                        child: ExcludeSemantics(
                          child: Text(
                            p.letter,
                            style: mono.inlineCode.copyWith(
                              color: colors.textAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: RichText(
                          text: TextSpan(
                            style: (text.bodyMedium ?? const TextStyle())
                                .copyWith(color: colors.textPrimary),
                            children: <InlineSpan>[
                              TextSpan(text: p.word),
                              if (p.variant.isNotEmpty)
                                TextSpan(
                                  text: '  (${p.variant})',
                                  style: text.bodySmall?.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(
                          p.morse,
                          style: mono.inlineCode.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            kPhoneticNote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  /// Spell out a Morse pattern for screen readers ("dot dash").
  static String _spokenMorse(String morse) =>
      morse.split('').map((String c) => c == '.' ? 'dot' : 'dash').join(' ');
}

/// The legend describing the three signal layers on the embedded plate.
class _LegendCard extends StatelessWidget {
  const _LegendCard();

  @override
  Widget build(BuildContext context) {
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
            'Legend',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final String line in kPhoneticLegend)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      line,
                      style: text.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
