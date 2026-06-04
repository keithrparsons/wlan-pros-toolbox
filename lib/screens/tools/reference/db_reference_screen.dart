// dB Reference — read-only decibel reference card.
//
// Two static tables ported verbatim from the RF Tools PWA (app.js
// DB_RATIOS + DBM_REFS, view data-tool="dbref"):
//   - dB Power Ratios: dB change → power ratio, voltage ratio, rule of thumb.
//   - Common dBm Reference Points: dBm anchor → power, context.
// Plus the PWA's footnote (dBd/dBi, dBW, FCC-limit caveat).
//
// This is a pure read-only reference — no inputs, no computation, no network.
// It works on every platform (no NetworkUnavailableView). The only state is
// "success": the bundled datasets always render. There is no loading, empty,
// or error path because nothing is fetched or parsed at runtime.
//
// Glyph note: negatives use ASCII hyphen-minus (U+002D) to match the rest of
// the app (dbm_watt converter Vera F-08). The multiplication sign (×) and
// middot (·) are preserved as data glyphs, not punctuation.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One row of the dB power-ratio table.
class DbRatio {
  const DbRatio({
    required this.db,
    required this.powerRatio,
    required this.voltageRatio,
    required this.note,
  });

  final String db;
  final String powerRatio;
  final String voltageRatio;
  final String note;
}

/// One row of the dBm reference-points table.
class DbmRef {
  const DbmRef({required this.dbm, required this.power, required this.context});

  final String dbm;
  final String power;
  final String context;
}

class DbReferenceScreen extends StatelessWidget {
  const DbReferenceScreen({super.key});

  /// dB → power/voltage ratios. Ported verbatim from PWA app.js DB_RATIOS.
  static const List<DbRatio> dbRatios = [
    DbRatio(
      db: '+3 dB',
      powerRatio: '2x',
      voltageRatio: '1.41x (sqrt 2)',
      note: 'Double power, the most-used rule',
    ),
    DbRatio(
      db: '+6 dB',
      powerRatio: '4x',
      voltageRatio: '2x',
      note: 'Double voltage or field strength',
    ),
    DbRatio(
      db: '+10 dB',
      powerRatio: '10x',
      voltageRatio: '3.16x',
      note: 'Ten times power',
    ),
    DbRatio(
      db: '+13 dB',
      powerRatio: '20x',
      voltageRatio: '4.47x',
      note: '3 dB + 10 dB combined',
    ),
    DbRatio(
      db: '+20 dB',
      powerRatio: '100x',
      voltageRatio: '10x',
      note: 'Hundred times power',
    ),
    DbRatio(
      db: '+30 dB',
      powerRatio: '1,000x',
      voltageRatio: '31.6x',
      note: 'Thousand times (0 dBm to +30 dBm = 1 W)',
    ),
    DbRatio(
      db: '-3 dB',
      powerRatio: '1/2x',
      voltageRatio: '0.71x',
      note: 'Half power',
    ),
    DbRatio(
      db: '-10 dB',
      powerRatio: '1/10x',
      voltageRatio: '0.32x',
      note: 'One-tenth power',
    ),
    DbRatio(
      db: '-20 dB',
      powerRatio: '1/100x',
      voltageRatio: '0.1x',
      note: 'One-hundredth power',
    ),
  ];

  /// dBm anchor values. Ported verbatim from PWA app.js DBM_REFS.
  static const List<DbmRef> dbmRefs = [
    DbmRef(
      dbm: '+36 dBm',
      power: '4 W',
      context: 'FCC 6 GHz standard-power EIRP limit (AFC required)',
    ),
    DbmRef(
      dbm: '+30 dBm',
      power: '1,000 mW',
      context: 'FCC 2.4 GHz max conducted power (Part 15.247)',
    ),
    DbmRef(
      dbm: '+27 dBm',
      power: '500 mW',
      context: 'Common high-power AP transmit setting',
    ),
    DbmRef(
      dbm: '+24 dBm',
      power: '250 mW',
      context: 'FCC UNII-2A/2C conducted max; typical mid-power AP',
    ),
    DbmRef(
      dbm: '+23 dBm',
      power: '200 mW',
      context: 'ETSI 5 GHz EIRP limit (EN 301 893)',
    ),
    DbmRef(
      dbm: '+20 dBm',
      power: '100 mW',
      context: 'Common default AP Tx power',
    ),
    DbmRef(dbm: '+17 dBm', power: '50 mW', context: 'FCC UNII-1 conducted max'),
    DbmRef(dbm: '+15 dBm', power: '32 mW', context: 'Typical laptop Tx power'),
    DbmRef(
      dbm: '0 dBm',
      power: '1 mW',
      context: 'Reference point, 1 milliwatt',
    ),
    DbmRef(
      dbm: '-67 dBm',
      power: '0.2 nW',
      context: 'Minimum for enterprise VoIP (Ekahau / Aruba / Cisco)',
    ),
    DbmRef(
      dbm: '-70 dBm',
      power: '0.1 nW',
      context: 'Minimum for enterprise data',
    ),
    DbmRef(
      dbm: '-80 dBm',
      power: '10 pW',
      context: 'Typical Wi-Fi receiver sensitivity',
    ),
    DbmRef(
      dbm: '-100 dBm',
      power: '0.1 pW',
      context: 'Near thermal noise floor, unusable for Wi-Fi',
    ),
  ];

  /// Footnote, ported verbatim from the PWA dbref view.
  static const String footnote =
      '0 dBd is about 2.15 dBi (dipole reference). dBW = dBm - 30. '
      'Regulatory limits shown are US FCC; verify before compliance decisions.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('dB Reference'),
        toolbarHeight: 64,
        // §8.16 — copy both reference tables as TSV. Static data, always on.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — both dB tables as TSV. Two sections, each with its own
  /// subtitle + header + rows (dB Power Ratios, then Common dBm Reference
  /// Points), then the footnote. Always non-null: the dataset is static, so
  /// copy is never disabled.
  String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('dB Power Ratios')
      ..writeln(
        <String>[
          'dB',
          'Power ratio',
          'Voltage ratio',
          'Rule of thumb',
        ].join(tab),
      );
    for (final DbRatio r in dbRatios) {
      buf.writeln(
        <String>[r.db, r.powerRatio, r.voltageRatio, r.note].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Common dBm Reference Points')
      ..writeln(<String>['dBm', 'Power', 'Context'].join(tab));
    for (final DbmRef r in dbmRefs) {
      buf.writeln(<String>[r.dbm, r.power, r.context].join(tab));
    }
    buf
      ..writeln()
      ..writeln('Notes')
      ..writeln(footnote);
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

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
                children: [
                  ConceptGraphicBand(
                    toolId: 'db-reference',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('db-reference'))
                    const SizedBox(height: AppSpacing.md),
                  _ratioCard(text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _dbmCard(text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _footnoteCard(text),
                  ToolHelpFooter(toolId: 'db-reference'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ratioCard(TextTheme text, AppMonoText mono) {
    return _Card(
      heading: 'dB Power Ratios',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RatioHeaderRow(text: text),
          const SizedBox(height: AppSpacing.xs),
          for (final DbRatio r in dbRatios)
            _RatioRow(ratio: r, text: text, mono: mono),
        ],
      ),
    );
  }

  Widget _dbmCard(TextTheme text, AppMonoText mono) {
    return _Card(
      heading: 'Common dBm Reference Points',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final DbmRef r in dbmRefs)
            _DbmRow(ref: r, text: text, mono: mono),
        ],
      ),
    );
  }

  Widget _footnoteCard(TextTheme text) {
    return _Card(
      heading: 'Notes',
      headingText: text,
      child: Text(
        footnote,
        style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

/// Shared card surface — matches the reference-card idiom in dbm_watt_converter.
class _Card extends StatelessWidget {
  const _Card({
    required this.heading,
    required this.headingText,
    required this.child,
  });

  final String heading;
  final TextTheme headingText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: headingText.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

/// Column header for the ratio table. dB / Power / Voltage; the rule of thumb
/// drops below each row instead of a fourth column so it reads at phone width.
class _RatioHeaderRow extends StatelessWidget {
  const _RatioHeaderRow({required this.text});

  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = text.labelMedium?.copyWith(
      color: AppColors.textTertiary,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text('dB', style: style)),
          SizedBox(width: 80, child: Text('Power', style: style)),
          Expanded(child: Text('Voltage', style: style)),
        ],
      ),
    );
  }
}

/// One ratio row: dB / power / voltage on the top line, rule-of-thumb beneath.
class _RatioRow extends StatelessWidget {
  const _RatioRow({
    required this.ratio,
    required this.text,
    required this.mono,
  });

  final DbRatio ratio;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    // Positive gains read in lime; losses in the danger color — matches the
    // PWA's green/red dB-change coloring (app.js buildDBRefCard).
    final bool positive = ratio.db.startsWith('+');
    final Color dbColor = positive ? AppColors.primary : AppColors.statusDanger;
    return ReferenceRowSemantics(
      label: rowLabel('${ratio.db} dB', <String?>[
        'power ratio ${ratio.powerRatio}',
        'voltage ratio ${ratio.voltageRatio}',
        ratio.note,
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    ratio.db,
                    style: mono.inlineCode.copyWith(
                      color: dbColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    ratio.powerRatio,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    ratio.voltageRatio,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                ratio.note,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One dBm anchor: dBm / power on the top line, context beneath.
class _DbmRow extends StatelessWidget {
  const _DbmRow({required this.ref, required this.text, required this.mono});

  final DbmRef ref;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    return ReferenceRowSemantics(
      label: rowLabel(ref.dbm, <String?>[ref.power, ref.context]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    ref.dbm,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    ref.power,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                ref.context,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
