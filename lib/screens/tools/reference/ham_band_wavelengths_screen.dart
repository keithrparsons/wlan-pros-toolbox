// Band Names & Wavelengths — the "two worlds" translation a Wi-Fi pro uses to
// cross into amateur radio. Hams name bands by wavelength in meters/cm, not
// frequency; this is the clean band-name <-> frequency lookup, the lambda = 300/f
// explainer, and a worked example each direction.
//
// DATA: lib/data/ham_reference_data.dart (kBandBridge). The lambda formula and
// worked examples are static copy on this screen.
//
// States (SOP-007 sec 5): a read-only reference. success = the table renders;
// loading/error/empty are not reachable (compile-time const, no input). The
// only interactive control is the AppCopyAction in the AppBar.
//
// THEME: chrome from context.colors; band names and frequencies in Roboto Mono
// (identifier face, GL-003 sec 8.5); the formula in DM Mono inline-code. No new
// tokens; no em dash (GL-004).
//
// ICON: bespoke Tier-2 icon resolves at assets/tool-icons/ham-band-wavelengths
// .svg when Charta ships it; falls back to the category glyph until then.

import 'package:flutter/material.dart';

import '../../../data/ham_reference_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_row_semantics.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kHamBandWavelengthsToolId = 'ham-band-wavelengths';

class HamBandWavelengthsScreen extends StatelessWidget {
  const HamBandWavelengthsScreen({super.key});

  /// §8.16 copy payload — the bridge table plus the formula and examples.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Band Names and Wavelengths (band name <-> frequency)')
      ..writeln(<String>['Band name', 'Frequency range', 'Region'].join(tab));
    for (final BandBridgeRow r in kBandBridge) {
      buf.writeln(<String>[r.bandName, r.freqRange, r.region].join(tab));
    }
    buf
      ..writeln()
      ..writeln('Formula: lambda(m) = 299.792458 / f(MHz); f(MHz) = '
          '299.792458 / lambda(m). Working approximation: lambda ~ 300 / f.')
      ..writeln('Name to frequency: "20 m" -> f ~ 300/20 = 15 MHz (actual '
          'allocation 14.000-14.350 MHz).')
      ..writeln('Frequency to name: 146 MHz -> lambda = 299.792458/146 = '
          '2.05 m -> the "2 m" band.')
      ..writeln('Wi-Fi crossover: 2442 MHz (Wi-Fi ch 7) -> 12.28 cm -> the '
          '"13 cm" amateur band.');
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Band Names & Wavelengths'),
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
                  _formulaCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _tableCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _examplesCard(context),
                  ToolHelpFooter(toolId: kHamBandWavelengthsToolId),
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
        'Hams name bands by wavelength in meters or centimeters; Wi-Fi pros '
        'name them by frequency. They are the same spectrum, two vocabularies. '
        'This table translates between them.',
        style: text.bodyMedium?.copyWith(color: colors.textPrimary),
      ),
    );
  }

  Widget _formulaCard(BuildContext context) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'The formula',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('lambda(m) = 299.792458 / f(MHz)', style: mono.inlineCode),
          Text('f(MHz) = 299.792458 / lambda(m)', style: mono.inlineCode),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Working approximation hams use: lambda ~ 300 / f (and f ~ 300 / '
            'lambda). The 300/f shortcut is within about 0.07 percent, fine for '
            'naming a band.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _tableCard(BuildContext context) {
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
          // Column header row.
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 76,
                  child: Text(
                    'Band',
                    style: text.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Frequency range',
                    style: text.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    'Region',
                    style: text.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...kBandBridge.asMap().entries.expand(
            (MapEntry<int, BandBridgeRow> entry) {
              return <Widget>[
                if (entry.key > 0)
                  Divider(color: colors.border, height: AppSpacing.sm),
                _BridgeRow(row: entry.value),
              ];
            },
          ),
        ],
      ),
    );
  }

  Widget _examplesCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    Widget example(String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: text.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        );
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
            'Worked examples',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          example(
            'Name to frequency',
            '"20 m" -> f ~ 300/20 = 15 MHz. The actual allocation is '
                '14.000-14.350 MHz.',
          ),
          example(
            'Frequency to name',
            '146 MHz -> lambda = 299.792458/146 = 2.05 m -> the "2 m" band.',
          ),
          example(
            'Wi-Fi crossover',
            // Reworded (Wave-2 finding G): the old example used 5500 MHz (ch
            // 100), which sits ~150 MHz BELOW the amateur 5 cm allocation
            // (5650-5925), so it implied an overlap that does not exist. 5825
            // MHz (ch 165) really is inside the 5 cm band.
            '2442 MHz (Wi-Fi ch 7) -> 12.28 cm -> sits in the "13 cm" amateur '
                'band. 5825 MHz (Wi-Fi ch 165) -> 5.15 cm -> sits in the "5 cm" '
                'amateur band (5650-5925 MHz).',
          ),
        ],
      ),
    );
  }
}

/// One band-name <-> frequency row. Band name and frequency render in Roboto
/// Mono so the two identifier columns align.
class _BridgeRow extends StatelessWidget {
  const _BridgeRow({required this.row});

  final BandBridgeRow row;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return ReferenceRowSemantics(
      label: rowLabel(row.bandName, <String?>[row.freqRange, row.region]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 76,
              child: Text(
                row.bandName,
                style: mono.robotoMono.copyWith(
                  color: row.sunset ? colors.textTertiary : colors.textAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                row.freqRange,
                style: mono.robotoMono.copyWith(
                  color: row.sunset ? colors.textTertiary : colors.textPrimary,
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                row.region,
                style: text.labelSmall?.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
