// 802.11 Feature Matrix — read-only Wi-Fi 5 to Wi-Fi 7 capability comparison.
//
// One table comparing the four current generations (Wi-Fi 5 / 802.11ac,
// Wi-Fi 6 / 802.11ax, Wi-Fi 6E / 802.11ax-6GHz, Wi-Fi 7 / 802.11be) across the
// feature axes that matter in design: bands, channel width, modulation (QAM),
// OFDMA, MU-MIMO, BSS Coloring, TWT, MLO, preamble puncturing, spatial streams,
// and the theoretical PHY-max rate.
//
// Feature presence/absence and the width/QAM ceilings come from the Pax
// reference dataset (Deliverables/2026-06-08-reference-batch/wifi-models-data.md,
// Page 2). Confidence: High — they are defined in the standards.
//
// ─── THE WI-FI 7 CEILING (corrected 2026-07-11) ─────────────────────────────
//
// This screen shipped "Wi-Fi 7 = 16 spatial streams, ~46 Gbps" in three rows
// and a footnote that explained the 16-stream derivation as arithmetic. It is
// wrong, and the ratified standard says so:
//
//   IEEE Std 802.11be-2024, Table 9-417t — "Encoding of the maximum number of
//   spatial streams (NSS) for a specified MCS value" — encodes max NSS 1 to 8.
//   Values 9-15 are RESERVED. EHT capability signalling cannot express a
//   16-stream mode, because the amendment never defines one.
//
// Ratified ceiling: 8 x 2882.4 Mbps (320 MHz, EHT-MCS 13 / 4096-QAM R=5/6,
// 0.8 us GI) = 23,059 Mbps ~= 23.1 Gbps. The 46 Gbps figure is 16 x 2882.4 —
// a draft-era number. 802.11be was approved 26 September 2024, so the old
// "values are from the draft and may shift" hedge no longer covers it.
//
// DOMAIN-FRAMING RULE (Keith): the "Max PHY rate" row is a theoretical CEILING,
// not a real-world client rate. The row is rendered with a trailing "ceiling"
// chip and a dedicated footnote spelling out the stream/width/QAM math behind
// each figure. It exists to size the standard, not the deployment. Never
// presented as an achievable speed.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform. The only state is "success": the compile-time const dataset
// always renders. No loading/empty/error path (nothing fetched or parsed at
// runtime; GL-008 network/subprocess rules do not apply).
//
// Pattern: mirrors poe_reference_screen exactly — Scaffold + AppBar
// (toolbarHeight 64) with AppCopyAction, SafeArea(top: false), LayoutBuilder
// isDesktop @720, ConstrainedBox to calculatorMaxWidth, SingleChildScrollView,
// ConceptGraphicBand header, _TableCard (HorizontalScrollTable + IntrinsicWidth +
// fixed-width cells), ReferenceRowSemantics per row, ToolHelpFooter. Here the
// table is transposed (one feature per row, one generation per column), so the
// key column is the feature name and the value cells are the four generations.
//
// Glyph note: "Wi-Fi" never "WiFi"; "802.11ac/ax/be" exact; ASCII hyphen-minus;
// no em dash; "Gbps"/"MHz"/"QAM" as written.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One feature row of the 802.11 matrix: the feature name and its value across
/// the four generations, in column order Wi-Fi 5 / 6 / 6E / 7.
@immutable
class WifiFeatureRow {
  const WifiFeatureRow({
    required this.feature,
    required this.wifi5,
    required this.wifi6,
    required this.wifi6e,
    required this.wifi7,
    this.isCeiling = false,
  });

  /// Feature axis name, e.g. `Max channel width`.
  final String feature;

  /// Value for Wi-Fi 5 (802.11ac).
  final String wifi5;

  /// Value for Wi-Fi 6 (802.11ax, 2.4/5 GHz).
  final String wifi6;

  /// Value for Wi-Fi 6E (802.11ax, +6 GHz).
  final String wifi6e;

  /// Value for Wi-Fi 7 (802.11be).
  final String wifi7;

  /// When true, the value cells are theoretical ceilings, not real-world rates,
  /// and the row is annotated with a "ceiling" chip (the Max PHY rate row).
  final bool isCeiling;
}

class WifiFeatureMatrixScreen extends StatelessWidget {
  const WifiFeatureMatrixScreen({super.key});

  /// Stable catalog id — backs the route, the §8.6.2 concept graphic, and the
  /// help entry.
  static const String toolId = 'wifi-feature-matrix';

  /// The 802.11 feature matrix, one row per feature. Ported verbatim from the
  /// Page 2 dataset (column order: Wi-Fi 5 / 6 / 6E / 7).
  static const List<WifiFeatureRow> rows = [
    WifiFeatureRow(
      feature: 'Bands',
      wifi5: '5 GHz only',
      wifi6: '2.4 + 5 GHz',
      wifi6e: '2.4 + 5 + 6 GHz',
      wifi7: '2.4 + 5 + 6 GHz',
    ),
    WifiFeatureRow(
      feature: 'Max channel width',
      wifi5: '160 MHz',
      wifi6: '160 MHz',
      wifi6e: '160 MHz',
      wifi7: '320 MHz',
    ),
    WifiFeatureRow(
      feature: 'Highest modulation',
      wifi5: '256-QAM',
      wifi6: '1024-QAM',
      wifi6e: '1024-QAM',
      wifi7: '4096-QAM',
    ),
    WifiFeatureRow(
      feature: 'OFDMA',
      wifi5: 'No',
      wifi6: 'Yes (DL + UL)',
      wifi6e: 'Yes (DL + UL)',
      wifi7: 'Yes (DL + UL)',
    ),
    WifiFeatureRow(
      feature: 'MU-MIMO',
      wifi5: 'DL only, up to 8',
      wifi6: 'DL + UL, up to 8',
      wifi6e: 'DL + UL, up to 8',
      // 8, not 16. Same root cause as the spatial-stream row below: EHT
      // capability signalling cannot express more than 8 streams.
      wifi7: 'DL + UL, up to 8',
    ),
    WifiFeatureRow(
      feature: 'BSS Coloring',
      wifi5: 'No',
      wifi6: 'Yes',
      wifi6e: 'Yes',
      wifi7: 'Yes',
    ),
    WifiFeatureRow(
      feature: 'TWT (Target Wake Time)',
      wifi5: 'No',
      wifi6: 'Yes',
      wifi6e: 'Yes',
      wifi7: 'Yes',
    ),
    WifiFeatureRow(
      feature: 'MLO (Multi-Link Operation)',
      wifi5: 'No',
      wifi6: 'No',
      wifi6e: 'No',
      wifi7: 'Yes',
    ),
    WifiFeatureRow(
      feature: 'Preamble puncturing',
      wifi5: 'No',
      wifi6: 'Limited (reg./OBSS)',
      wifi6e: 'Limited (reg./OBSS)',
      wifi7: 'Yes (core feature)',
    ),
    WifiFeatureRow(
      feature: 'Max spatial streams',
      wifi5: '8',
      wifi6: '8',
      wifi6e: '8',
      // 8, NOT 16. IEEE Std 802.11be-2024, Table 9-417t ("Encoding of the
      // maximum number of spatial streams (NSS) for a specified MCS value")
      // encodes Max NSS 1 through 8; values 9-15 are RESERVED. The ratified
      // amendment cannot express a 16-stream mode, so 16 is a draft-era number.
      wifi7: '8',
    ),
    WifiFeatureRow(
      feature: 'Max PHY rate',
      wifi5: '~6.9 Gbps',
      wifi6: '~9.6 Gbps',
      wifi6e: '~9.6 Gbps',
      // 8 x 2882.4 Mbps = 23,059 Mbps. The old ~46 Gbps was 16 x 2882.4 — it
      // needed the 16-stream mode 802.11be never defines.
      wifi7: '~23.1 Gbps',
      isCeiling: true,
    ),
  ];

  /// Footnote — the theoretical-ceiling caveat for the Max PHY rate row, spelled
  /// out per the domain-framing rule.
  ///
  /// The old text did not just carry the wrong Wi-Fi 7 number, it TAUGHT the
  /// wrong derivation ("be ~46 Gbps = 16 x 320 x 4096-QAM") as arithmetic — so
  /// the error was stated twice and looked checkable. The "values are from the
  /// draft and may shift at final ratification" hedge that covered it has
  /// expired: 802.11be was approved 26 September 2024, and the ratified
  /// amendment refutes the figure rather than confirming it.
  static const String footnote =
      'Max PHY rate is a theoretical ceiling, NOT a real-world client rate. '
      'Each figure is the standard-derived maximum at the top stream count, '
      'widest channel, highest modulation, and shortest guard interval: '
      'ac ~6.9 Gbps = 8 streams x 160 MHz x 256-QAM; ax ~9.6 Gbps = 8 x 160 x '
      '1024-QAM; be ~23.1 Gbps = 8 x 320 MHz x 4096-QAM (EHT-MCS 13, 0.8 us '
      'GI, 8 x 2882.4 Mbps). 802.11be-2024 caps EHT at 8 spatial streams '
      '(Table 9-417t: max-NSS values 9-15 are Reserved), so the widely-quoted '
      '46 Gbps figure - which assumes 16 streams - is not reachable under the '
      'ratified amendment. MLO aggregates traffic across links; it does not '
      'raise a single link\'s PHY ceiling. Real client radios run 2-4 streams, '
      'so these size the standard, not the deployment. OFDMA and MU-MIMO are '
      'efficiency/concurrency mechanisms (more devices, more efficiently), not '
      'single-client speed features.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('802.11 Feature Matrix'),
        toolbarHeight: 64,
        // §8.16 — copy the matrix as TSV. Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the feature matrix as a single-section TSV (feature,
  /// Wi-Fi 5/6/6E/7), with the Max PHY rate row marked "(ceiling)" and the
  /// theoretical-ceiling caveat appended. Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('802.11 Feature Matrix')
      ..writeln()
      ..writeln(
        <String>[
          'Feature',
          'Wi-Fi 5 (802.11ac)',
          'Wi-Fi 6 (802.11ax)',
          'Wi-Fi 6E (802.11ax)',
          'Wi-Fi 7 (802.11be)',
        ].join(tab),
      );
    for (final WifiFeatureRow r in rows) {
      final String feature = r.isCeiling ? '${r.feature} (ceiling)' : r.feature;
      buf.writeln(
        <String>[feature, r.wifi5, r.wifi6, r.wifi6e, r.wifi7].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(footnote);
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
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
                    toolId: toolId,
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic(toolId))
                    const SizedBox(height: AppSpacing.md),
                  _matrixCard(colors, text, mono),
                  ToolHelpFooter(toolId: toolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _matrixCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'Wi-Fi 5 to Wi-Fi 7',
      footnote: footnote,
      header: const Row(
        children: [
          _HeaderCell('Feature', width: 184),
          _HeaderCell('Wi-Fi 5', width: 120),
          _HeaderCell('Wi-Fi 6', width: 120),
          _HeaderCell('Wi-Fi 6E', width: 120),
          _HeaderCell('Wi-Fi 7', width: 132),
        ],
      ),
      rows: rows.map((WifiFeatureRow r) {
        final String ceilingClause = r.isCeiling ? ' (theoretical ceiling)' : '';
        return ReferenceRowSemantics(
          label: rowLabel('${r.feature}$ceilingClause', <String?>[
            'Wi-Fi 5 ${r.wifi5}',
            'Wi-Fi 6 ${r.wifi6}',
            'Wi-Fi 6E ${r.wifi6e}',
            'Wi-Fi 7 ${r.wifi7}',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 184,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.feature,
                        style: text.labelMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (r.isCeiling) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        _CeilingChip(colors: colors, text: text),
                      ],
                    ],
                  ),
                ),
                _ValueCell(r.wifi5, width: 120, mono: mono, colors: colors),
                _ValueCell(r.wifi6, width: 120, mono: mono, colors: colors),
                _ValueCell(r.wifi6e, width: 120, mono: mono, colors: colors),
                _ValueCell(
                  r.wifi7,
                  width: 132,
                  mono: mono,
                  colors: colors,
                  // Wi-Fi 7 is the leading column — accent it.
                  accent: true,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// One generation value cell. Mono-styled to align numeric/spec values; the
/// leading-generation column (Wi-Fi 7) is accented, the rest secondary.
class _ValueCell extends StatelessWidget {
  const _ValueCell(
    this.value, {
    required this.width,
    required this.mono,
    required this.colors,
    this.accent = false,
  });

  final String value;
  final double width;
  final AppMonoText mono;
  final AppColorScheme colors;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        style: mono.inlineCode.copyWith(
          color: accent ? colors.textAccent : colors.textSecondary,
          fontWeight: accent ? FontWeight.w500 : FontWeight.w400,
        ),
      ),
    );
  }
}

/// Small "ceiling" annotation chip on the Max PHY rate row, marking its values
/// as theoretical (domain-framing rule). Uses the warning hue as a tint fill,
/// never as the sole signal — the footnote carries the full explanation.
class _CeilingChip extends StatelessWidget {
  const _CeilingChip({required this.colors, required this.text});

  final AppColorScheme colors;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final Color warn = colors.statusWarning;
    return Container(
      decoration: BoxDecoration(
        color: colors.isLight
            ? colors.statusWarningFill
            : warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: warn, width: 1),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      child: Text(
        'theoretical ceiling',
        style: (text.labelSmall ?? const TextStyle()).copyWith(
          color: warn,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Card surface wrapping a wide table: title (full-width, wraps) over a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align), with an optional full-width footnote beneath. Matches the
/// poe_reference_screen / wifi_channels_screen overflow-safe idiom.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.header,
    required this.rows,
    this.footnote,
  });

  final String title;
  final Widget header;
  final List<Widget> rows;
  final String? footnote;

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
        children: [
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  Divider(color: colors.border, height: AppSpacing.sm),
                  ...rows,
                ],
              ),
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              footnote!,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One column-header label, caption-styled to align with the data cells.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: colors.textTertiary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
