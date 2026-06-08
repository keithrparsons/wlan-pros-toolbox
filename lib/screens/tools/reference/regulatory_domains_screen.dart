// Wi-Fi Regulatory Domains — read-only region-level FCC / ETSI / ITU summary.
//
// A region-level (NOT per-country) summary of the FCC and ETSI rules for the
// 2.4 / 5 / 6 GHz Wi-Fi bands, plus the ITU three-region note. Four data cards:
//   1. FCC 2.4 + 5 GHz UNII sub-bands (allowed, DFS, EIRP notes)
//   2. FCC 6 GHz UNII-5..8 (power classes + max EIRP / PSD)
//   3. ETSI 2.4 / 5 / 6 GHz (allowed, DFS/TPC, EIRP)
//   4. ITU note (three regions + 2.4 GHz channel-count differences)
//
// Data ported verbatim from the Pax reference dataset
// (Deliverables/2026-06-08-reference-batch/wifi-models-data.md, Page 3).
// Confidence: High on the STRUCTURAL rules (band edges, DFS/TPC obligations,
// power-class availability), cross-checked across FCC/ETSI documents and vendor
// regulatory white papers; MEDIUM on the exact dBm figures, which carry per-band
// and per-device-type exceptions and have been amended recently for 6 GHz.
//
// REGULATORY-VOLATILITY CAVEAT (binding, per the build brief): a persistent
// §8.20.4 warning callout states up front that this is region-level, that
// regulations change (6 GHz is mid-rulemaking), and that the dBm figures are a
// snapshot to verify against current FCC/ETSI rule text (as of 2026). The 6 GHz
// dBm values are Medium confidence precisely because they are being amended
// (VLP extended band-wide, new geofenced classes added). Never presented as a
// settled constant — always "verify before deploying or certifying."
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform. The only state is "success": the compile-time const datasets
// always render. No loading/empty/error path (nothing fetched or parsed at
// runtime; GL-008 network/subprocess rules do not apply).
//
// Pattern: mirrors poe_reference_screen exactly — Scaffold + AppBar
// (toolbarHeight 64) with AppCopyAction, SafeArea(top: false), LayoutBuilder
// isDesktop @720, ConstrainedBox to calculatorMaxWidth, SingleChildScrollView,
// ConceptGraphicBand header, _TableCard per sub-table (HorizontalScrollTable +
// IntrinsicWidth + fixed-width cells), ReferenceRowSemantics per row,
// ToolHelpFooter.
//
// Glyph note: "Wi-Fi" never "WiFi"; "UNII" caps; "dBm"/"MHz"/"GHz" as written;
// ASCII hyphen-minus; no em dash. PSD = power spectral density (dBm/MHz).

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

/// One band row in the FCC 2.4 / 5 GHz card. Mirrors the Page 3 FCC table:
/// [band, allowed, dfs, notes].
@immutable
class FccBandRow {
  const FccBandRow({
    required this.band,
    required this.allowed,
    required this.dfs,
    required this.notes,
  });

  /// Band / UNII sub-band label, e.g. `5 GHz UNII-2A (5.250-5.350)`.
  final String band;

  /// Allowed channels / status, e.g. `Ch 1-11 (2.412-2.462)`.
  final String allowed;

  /// DFS / coordination requirement, e.g. `DFS required`.
  final String dfs;

  /// Power / EIRP note.
  final String notes;
}

/// One sub-band row in the FCC 6 GHz card. Mirrors the Page 3 6 GHz table:
/// [subBand, range, classes, eirp].
@immutable
class FccSixGhzRow {
  const FccSixGhzRow({
    required this.subBand,
    required this.range,
    required this.classes,
    required this.eirp,
  });

  /// UNII sub-band, e.g. `UNII-5`.
  final String subBand;

  /// Frequency range in GHz, e.g. `5.925-6.425`.
  final String range;

  /// Power classes allowed, e.g. `LPI, VLP, SP (AFC)`.
  final String classes;

  /// Max EIRP / PSD note (Medium confidence — verify against current rule text).
  final String eirp;
}

/// One band row in the ETSI card. Mirrors the Page 3 ETSI table:
/// [band, allowed, dfsTpc, eirp].
@immutable
class EtsiBandRow {
  const EtsiBandRow({
    required this.band,
    required this.allowed,
    required this.dfsTpc,
    required this.eirp,
  });

  /// Band label, e.g. `6 GHz 5.945-6.425 (UNII-5)`.
  final String band;

  /// Allowed channels / status.
  final String allowed;

  /// DFS / TPC requirement.
  final String dfsTpc;

  /// Max EIRP note.
  final String eirp;
}

class RegulatoryDomainsScreen extends StatelessWidget {
  const RegulatoryDomainsScreen({super.key});

  /// Stable catalog id — backs the route, the §8.6.2 concept graphic, and the
  /// help entry.
  static const String toolId = 'regulatory-domains';

  /// FCC 2.4 + 5 GHz bands. Ported verbatim from the Page 3 FCC table.
  static const List<FccBandRow> fccLower = [
    FccBandRow(
      band: '2.4 GHz',
      allowed: 'Ch 1-11 (2.412-2.462)',
      dfs: 'None',
      notes: '11 channels; only 1/6/11 non-overlapping at 20 MHz.',
    ),
    FccBandRow(
      band: '5 GHz UNII-1 (5.150-5.250)',
      allowed: 'Yes',
      dfs: 'No DFS',
      notes: 'Max EIRP ~30 dBm (AP).',
    ),
    FccBandRow(
      band: '5 GHz UNII-2A (5.250-5.350)',
      allowed: 'Yes',
      dfs: 'DFS required',
      notes: 'Radar-avoidance. Max EIRP ~30 dBm.',
    ),
    FccBandRow(
      band: '5 GHz UNII-2C (5.470-5.725)',
      allowed: 'Yes',
      dfs: 'DFS required',
      notes: 'Largest DFS block. Max EIRP ~30 dBm.',
    ),
    FccBandRow(
      band: '5 GHz UNII-3 (5.725-5.850)',
      allowed: 'Yes',
      dfs: 'No DFS',
      notes: 'Higher power permitted; ~36 dBm EIRP typical for fixed '
          'point-to-multipoint, more under point-to-point rules.',
    ),
  ];

  /// FCC 6 GHz UNII-5..8. Ported verbatim from the Page 3 6 GHz table. EIRP/PSD
  /// figures are Medium confidence (6 GHz is mid-rulemaking).
  static const List<FccSixGhzRow> fccSixGhz = [
    FccSixGhzRow(
      subBand: 'UNII-5',
      range: '5.925-6.425',
      classes: 'LPI, VLP, SP (AFC)',
      eirp: 'SP: 36 dBm / 23 dBm/MHz PSD (AFC). LPI: 30 / 5. VLP: 14 / -5.',
    ),
    FccSixGhzRow(
      subBand: 'UNII-6',
      range: '6.425-6.525',
      classes: 'LPI, VLP (no SP)',
      eirp: 'LPI: 30 dBm / 5 dBm/MHz. VLP: 14 / -5.',
    ),
    FccSixGhzRow(
      subBand: 'UNII-7',
      range: '6.525-6.875',
      classes: 'LPI, VLP, SP (AFC)',
      eirp: 'Same as UNII-5 (SP 36 / 23; LPI 30 / 5; VLP 14 / -5).',
    ),
    FccSixGhzRow(
      subBand: 'UNII-8',
      range: '6.875-7.125',
      classes: 'LPI, VLP (no SP)',
      eirp: 'Same as UNII-6 (LPI 30 / 5; VLP 14 / -5).',
    ),
  ];

  /// Power-class legend for the FCC 6 GHz card.
  static const String fccSixGhzFootnote =
      'LPI (Low-Power Indoor): no AFC, indoor-only, no external antenna; all '
      'four sub-bands. SP (Standard Power): AFC-controlled, indoor or outdoor, '
      'UNII-5 and UNII-7 only. VLP (Very Low Power): no AFC, indoor or outdoor; '
      'recent FCC action extended VLP across the full band. A geofenced '
      'very-high-power (GVP) class also exists under recent rulemaking '
      '(evolving). dBm figures are Medium confidence — verify against current '
      'rule text.';

  /// ETSI 2.4 / 5 / 6 GHz. Ported verbatim from the Page 3 ETSI table.
  static const List<EtsiBandRow> etsi = [
    EtsiBandRow(
      band: '2.4 GHz',
      allowed: 'Ch 1-13 (2.412-2.472)',
      dfsTpc: 'None',
      eirp: '20 dBm (100 mW).',
    ),
    EtsiBandRow(
      band: '5 GHz 5.150-5.350',
      allowed: 'Ch 36-64',
      dfsTpc: 'DFS + TPC on 5.250-5.350',
      eirp: '23 dBm. Indoor-focused.',
    ),
    EtsiBandRow(
      band: '5 GHz 5.470-5.725',
      allowed: 'Ch 100-140',
      dfsTpc: 'DFS + TPC required',
      eirp: '30 dBm (with TPC).',
    ),
    EtsiBandRow(
      band: '6 GHz 5.945-6.425 (UNII-5 only)',
      allowed: 'Yes',
      dfsTpc: 'No AFC',
      eirp: 'LPI: 23 dBm / 10 dBm/MHz. VLP: 14 / -5 (indoor + outdoor).',
    ),
  ];

  /// Legend for the ETSI card.
  static const String etsiFootnote =
      'Europe permits only the lower 6 GHz (5.945-6.425, ~UNII-5) — a quarter '
      'of what the FCC opened. Upper 6 GHz (6.425-7.125) is not available for '
      'Wi-Fi across the EU at time of writing. TPC (Transmit Power Control) is '
      'mandatory in the DFS bands under ETSI, unlike the FCC.';

  /// ITU note paragraphs (region structure + 2.4 GHz channel differences).
  static const List<String> ituNotes = [
    'The ITU divides the world into three regions: Region 1 (Europe, Africa, '
        'Middle East, former-Soviet states), Region 2 (Americas), Region 3 '
        '(Asia-Pacific). Allocations differ per region and per national '
        'administration.',
    '2.4 GHz: most of the world uses channels 1-13; the US (FCC) caps at 1-11; '
        'Japan historically allowed channel 14 for 802.11b only.',
    '5 GHz and 6 GHz adoption varies widely by country — some Region-3 '
        'administrations follow FCC-style full 6 GHz, others the ETSI '
        'lower-only model, others have not opened 6 GHz at all.',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Regulatory Domains'),
        toolbarHeight: 64,
        // §8.16 — copy all sub-tables + notes as TSV. Static data, always on.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full region-level summary as a multi-section TSV
  /// (FCC 2.4/5 GHz, FCC 6 GHz, ETSI, ITU note), led by the volatility caveat.
  /// Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Wi-Fi Regulatory Domains (region-level)')
      ..writeln()
      ..writeln(caveatBody)
      ..writeln()
      ..writeln('FCC 2.4 + 5 GHz')
      ..writeln(
        <String>['Band', 'Allowed', 'DFS', 'Notes'].join(tab),
      );
    for (final FccBandRow r in fccLower) {
      buf.writeln(<String>[r.band, r.allowed, r.dfs, r.notes].join(tab));
    }
    buf
      ..writeln()
      ..writeln('FCC 6 GHz (UNII-5 to UNII-8)')
      ..writeln(
        <String>['Sub-band', 'Range (GHz)', 'Power classes', 'Max EIRP / PSD']
            .join(tab),
      );
    for (final FccSixGhzRow r in fccSixGhz) {
      buf.writeln(
        <String>[r.subBand, r.range, r.classes, r.eirp].join(tab),
      );
    }
    buf
      ..writeln(fccSixGhzFootnote)
      ..writeln()
      ..writeln('ETSI (Europe)')
      ..writeln(
        <String>['Band', 'Allowed', 'DFS / TPC', 'Max EIRP'].join(tab),
      );
    for (final EtsiBandRow r in etsi) {
      buf.writeln(<String>[r.band, r.allowed, r.dfsTpc, r.eirp].join(tab));
    }
    buf
      ..writeln(etsiFootnote)
      ..writeln()
      ..writeln('ITU / other');
    for (final String note in ituNotes) {
      buf.writeln('- $note');
    }
    return buf.toString().trimRight();
  }

  /// The persistent regulatory-volatility caveat body (also reused in the copy
  /// payload so the warning travels with the pasted data).
  static const String caveatBody =
      'Region-level; regulations change — verify against current FCC/ETSI rule '
      'text (as of 2026). This is a region-level summary, not a per-country '
      'matrix. National regulators adopt rules at different times with local '
      'exceptions. 6 GHz is mid-rulemaking (VLP extended band-wide, new '
      'geofenced classes added), so the dBm figures are Medium confidence — '
      'treat every 6 GHz number as a snapshot, not a constant.';

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
                  const _VolatilityCaveat(),
                  const SizedBox(height: AppSpacing.md),
                  _fccLowerCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _fccSixGhzCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _etsiCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _ituCard(colors, text),
                  ToolHelpFooter(toolId: toolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fccLowerCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'FCC 2.4 + 5 GHz (ITU Region 2)',
      header: const Row(
        children: [
          _HeaderCell('Band', width: 220),
          _HeaderCell('Allowed', width: 168),
          _HeaderCell('DFS', width: 120),
          _HeaderCell('Notes', width: 280),
        ],
      ),
      rows: fccLower.map((FccBandRow r) {
        return ReferenceRowSemantics(
          label: rowLabel(r.band, <String?>[
            r.allowed,
            'DFS ${r.dfs}',
            r.notes,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _KeyCell(r.band, width: 220, colors: colors, mono: mono),
                _TextCell(r.allowed, width: 168, colors: colors, mono: mono,
                    accent: true),
                _TextCell(r.dfs, width: 120, colors: colors, mono: mono),
                _NoteCell(r.notes, width: 280, colors: colors, text: text),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _fccSixGhzCard(
      AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'FCC 6 GHz — UNII-5 to UNII-8',
      footnote: fccSixGhzFootnote,
      header: const Row(
        children: [
          _HeaderCell('Sub-band', width: 96),
          _HeaderCell('Range (GHz)', width: 120),
          _HeaderCell('Power classes', width: 160),
          _HeaderCell('Max EIRP / PSD', width: 320),
        ],
      ),
      rows: fccSixGhz.map((FccSixGhzRow r) {
        return ReferenceRowSemantics(
          label: rowLabel(r.subBand, <String?>[
            '${r.range} GHz',
            r.classes,
            r.eirp,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _KeyCell(r.subBand, width: 96, colors: colors, mono: mono),
                _TextCell(r.range, width: 120, colors: colors, mono: mono),
                _NoteCell(r.classes, width: 160, colors: colors, text: text),
                _NoteCell(r.eirp, width: 320, colors: colors, text: text),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _etsiCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'ETSI (Europe, ITU Region 1)',
      footnote: etsiFootnote,
      header: const Row(
        children: [
          _HeaderCell('Band', width: 220),
          _HeaderCell('Allowed', width: 120),
          _HeaderCell('DFS / TPC', width: 168),
          _HeaderCell('Max EIRP', width: 280),
        ],
      ),
      rows: etsi.map((EtsiBandRow r) {
        return ReferenceRowSemantics(
          label: rowLabel(r.band, <String?>[
            r.allowed,
            'DFS/TPC ${r.dfsTpc}',
            r.eirp,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _KeyCell(r.band, width: 220, colors: colors, mono: mono),
                _TextCell(r.allowed, width: 120, colors: colors, mono: mono,
                    accent: true),
                _NoteCell(r.dfsTpc, width: 168, colors: colors, text: text),
                _NoteCell(r.eirp, width: 280, colors: colors, text: text),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _ituCard(AppColorScheme colors, TextTheme text) {
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
            'ITU / other',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (int i = 0; i < ituNotes.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            Semantics(
              container: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '•',
                      style: text.bodyMedium?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      ituNotes[i],
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Persistent §8.20.4 warning callout: the regulatory-volatility caveat. Mirrors
/// the freeradius `_LabCaution` idiom (left-accent border, warning tint fill in
/// light / faint amber wash in dark, warning icon + title + body). One Semantics
/// container so a screen reader reads it as a single node.
class _VolatilityCaveat extends StatelessWidget {
  const _VolatilityCaveat();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color warn = colors.statusWarning;

    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.isLight
              ? colors.statusWarningFill
              : warn.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border(
            top: BorderSide(color: warn),
            right: BorderSide(color: warn),
            bottom: BorderSide(color: warn),
            left: BorderSide(color: warn, width: 6),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.rowPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, size: 24, color: warn),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'REGION-LEVEL — VERIFY CURRENT RULE TEXT (AS OF 2026)',
                    style: (text.labelMedium ?? const TextStyle()).copyWith(
                      color: warn,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    RegulatoryDomainsScreen.caveatBody,
                    style: (text.bodyMedium ?? const TextStyle()).copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mono key cell (left column — band / sub-band identifier).
class _KeyCell extends StatelessWidget {
  const _KeyCell(
    this.value, {
    required this.width,
    required this.colors,
    required this.mono,
  });

  final String value;
  final double width;
  final AppColorScheme colors;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        style: mono.inlineCode.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Mono value cell (short codes — allowed / DFS / range). Accent-colored when
/// [accent] is true (the "allowed" affirmative column).
class _TextCell extends StatelessWidget {
  const _TextCell(
    this.value, {
    required this.width,
    required this.colors,
    required this.mono,
    this.accent = false,
  });

  final String value;
  final double width;
  final AppColorScheme colors;
  final AppMonoText mono;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        style: mono.inlineCode.copyWith(
          color: accent ? colors.textAccent : colors.textSecondary,
        ),
      ),
    );
  }
}

/// Prose note cell (wrapping sentences — notes / EIRP / power classes).
class _NoteCell extends StatelessWidget {
  const _NoteCell(
    this.value, {
    required this.width,
    required this.colors,
    required this.text,
  });

  final String value;
  final double width;
  final AppColorScheme colors;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        style: text.labelMedium?.copyWith(
          color: colors.textTertiary,
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
