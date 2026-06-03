// PoE Reference — read-only Power-over-Ethernet reference card.
//
// Two static tables ported verbatim from the RF Tools PWA (app.js, the `poe`
// tool view data-tool="poe" → buildPoeTables(), with the `POE_STDS` and
// `POE_CLASSES` consts):
//   - PoE standards: 802.3 standard → PSE power, PD power, pairs, classes.
//   - PD power classes: class 0–8 → max power at PD, standard, note.
// The same values were already ported into poe_budget_screen.dart's reference
// cards; this screen mirrors the full PWA columns (pairs + classes for the
// standards table, the per-class note for the classes table) that the budget
// screen abbreviated.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. No loading/empty/error path
// because nothing is fetched or parsed at runtime (GL-008 network/subprocess
// rules do not apply — nothing to fabricate, nothing to shell out to).
//
// Pattern: matches db_reference_screen / wifi_channels_screen — Scaffold +
// AppBar (toolbarHeight 64), SafeArea(top: false), LayoutBuilder isDesktop @720,
// ConstrainedBox to calculatorMaxWidth, SingleChildScrollView, cards from
// app_tokens / app_typography. The two tables are wide, so each renders inside
// a horizontal SingleChildScrollView + IntrinsicWidth with fixed-width cells
// (the wifi_channels overflow-safe idiom): columns align and never overflow a
// phone-width card.
//
// Glyph note: "802.3" not "802.3x"; ASCII hyphen-minus only; no em dash.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One row of the PoE standards table. Field names + values mirror the PWA
/// `POE_STDS` const exactly: [standard, name, pse_w, pd_w, pairs, classes].
@immutable
class PoeStandard {
  const PoeStandard({
    required this.standard,
    required this.name,
    required this.pseWatts,
    required this.pdWatts,
    required this.pairs,
    required this.classes,
  });

  /// IEEE designation, e.g. `802.3af`.
  final String standard;

  /// Marketing name, e.g. `PoE+`.
  final String name;

  /// Power supplied at the PSE (switch / injector), in watts.
  final double pseWatts;

  /// Power available at the PD (device), in watts, after cable loss.
  final double pdWatts;

  /// Powered pairs, e.g. `2 of 4`.
  final String pairs;

  /// Supported class range, e.g. `0-4`.
  final String classes;
}

/// One row of the PD power-class table. Field names + values mirror the PWA
/// `POE_CLASSES` const exactly: [class, max_pd_w, standard, note].
@immutable
class PoeClass {
  const PoeClass({
    required this.classNum,
    required this.maxPdWatts,
    required this.standard,
    required this.note,
  });

  /// Class number, 0–8.
  final int classNum;

  /// Maximum power available at the PD for this class, in watts.
  final double maxPdWatts;

  /// The 802.3 standard that defines this class.
  final String standard;

  /// Short descriptor, e.g. `Type 4 max`.
  final String note;
}

class PoeReferenceScreen extends StatelessWidget {
  const PoeReferenceScreen({super.key});

  /// PoE standards. Ported verbatim from PWA app.js POE_STDS.
  static const List<PoeStandard> standards = [
    PoeStandard(
      standard: '802.3af',
      name: 'PoE',
      pseWatts: 15.4,
      pdWatts: 12.95,
      pairs: '2 of 4',
      classes: '0-3',
    ),
    PoeStandard(
      standard: '802.3at',
      name: 'PoE+',
      pseWatts: 30.0,
      pdWatts: 25.5,
      pairs: '2 of 4',
      classes: '0-4',
    ),
    PoeStandard(
      standard: '802.3bt Type 3',
      name: 'PoE++ / 4PPoE',
      pseWatts: 60.0,
      pdWatts: 51.0,
      pairs: '4 of 4',
      classes: '0-6',
    ),
    PoeStandard(
      standard: '802.3bt Type 4',
      name: 'PoE++ Hi',
      pseWatts: 90.0,
      pdWatts: 71.3,
      pairs: '4 of 4',
      classes: '0-8',
    ),
  ];

  /// PD power classes. Ported verbatim from PWA app.js POE_CLASSES.
  static const List<PoeClass> classes = [
    PoeClass(
      classNum: 0,
      maxPdWatts: 12.95,
      standard: '802.3af',
      note: 'Default / unclassified',
    ),
    PoeClass(
      classNum: 1,
      maxPdWatts: 3.84,
      standard: '802.3af',
      note: 'Low power',
    ),
    PoeClass(
      classNum: 2,
      maxPdWatts: 6.49,
      standard: '802.3af',
      note: 'Medium power',
    ),
    PoeClass(
      classNum: 3,
      maxPdWatts: 12.95,
      standard: '802.3af',
      note: 'af maximum',
    ),
    PoeClass(
      classNum: 4,
      maxPdWatts: 25.5,
      standard: '802.3at',
      note: 'PoE+ max',
    ),
    PoeClass(
      classNum: 5,
      maxPdWatts: 40.0,
      standard: '802.3bt',
      note: 'Type 3',
    ),
    PoeClass(
      classNum: 6,
      maxPdWatts: 51.0,
      standard: '802.3bt',
      note: 'Type 3 max',
    ),
    PoeClass(
      classNum: 7,
      maxPdWatts: 62.0,
      standard: '802.3bt',
      note: 'Type 4',
    ),
    PoeClass(
      classNum: 8,
      maxPdWatts: 71.3,
      standard: '802.3bt',
      note: 'Type 4 max',
    ),
  ];

  /// Footnote — PD power is what reaches the device after cable loss.
  static const String footnote =
      'PSE power is supplied at the switch or injector; PD power is what '
      'reaches the device after cable loss. Use the PoE Budget tool to size a '
      'switch against connected devices.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PoE Reference'),
        toolbarHeight: 64,
        // §8.16 — copy both sub-tables as TSV (PoE standards + PD power
        // classes), each its own section. Static data, always enabled.
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — both PoE sub-tables as a two-section TSV. Section 1
  /// is the standards table (standard, name, PSE W, PD W, pairs, classes);
  /// section 2 is the PD power-class table (class, max at PD, standard, note).
  /// Each section gets a subtitle + header + one row per entry. Watt values use
  /// the same `_fmt` trimming the screen shows. Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('PoE Reference')
      ..writeln()
      ..writeln('PoE standards')
      ..writeln(
        <String>[
          'Standard',
          'Name',
          'PSE (W)',
          'PD (W)',
          'Pairs',
          'Classes',
        ].join(tab),
      );
    for (final PoeStandard s in standards) {
      buf.writeln(
        <String>[
          s.standard,
          s.name,
          _fmt(s.pseWatts),
          _fmt(s.pdWatts),
          s.pairs,
          s.classes,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('PD power classes')
      ..writeln(
        <String>['Class', 'Max at PD (W)', 'Standard', 'Note'].join(tab),
      );
    for (final PoeClass c in classes) {
      buf.writeln(
        <String>[
          '${c.classNum}',
          _fmt(c.maxPdWatts),
          c.standard,
          c.note,
        ].join(tab),
      );
    }
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
                    toolId: 'poe-reference',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('poe-reference'))
                    const SizedBox(height: AppSpacing.md),
                  _standardsCard(text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _classesCard(text, mono),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _standardsCard(TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'PoE standards',
      footnote: footnote,
      header: const Row(
        children: [
          _HeaderCell('Standard', width: 120),
          _HeaderCell('Name', width: 120),
          _HeaderCell('PSE', width: 64),
          _HeaderCell('PD', width: 64),
          _HeaderCell('Pairs', width: 64),
          _HeaderCell('Classes', width: 56),
        ],
      ),
      rows: standards.map((PoeStandard s) {
        return ReferenceRowSemantics(
          label: rowLabel(s.standard, <String?>[
            s.name,
            'PSE ${_fmt(s.pseWatts)} watts',
            'PD ${_fmt(s.pdWatts)} watts',
            'pairs ${s.pairs}',
            'classes ${s.classes}',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    s.standard,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    s.name,
                    style: text.labelMedium?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '${_fmt(s.pseWatts)} W',
                    style: mono.inlineCode.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '${_fmt(s.pdWatts)} W',
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    s.pairs,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    s.classes,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _classesCard(TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'PD power classes',
      header: const Row(
        children: [
          _HeaderCell('Class', width: 56),
          _HeaderCell('Max at PD', width: 88),
          _HeaderCell('Standard', width: 88),
          _HeaderCell('Note', width: 160),
        ],
      ),
      rows: classes.map((PoeClass c) {
        return ReferenceRowSemantics(
          label: rowLabel('Class ${c.classNum}', <String?>[
            'max at PD ${_fmt(c.maxPdWatts)} watts',
            'standard ${c.standard}',
            c.note,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    '${c.classNum}',
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    '${_fmt(c.maxPdWatts)} W',
                    style: mono.inlineCode.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    c.standard,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: Text(
                    c.note,
                    style: text.labelMedium?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Trim a trailing `.0` so 15.4 stays 15.4 but 30.0 reads as 30, matching the
  /// PWA's bare-number rendering (e.g. `30W`, `15.4W`).
  static String _fmt(double w) {
    final String s = w.toStringAsFixed(2);
    if (s.endsWith('.00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) return s.substring(0, s.length - 1);
    return s;
  }
}

/// Card surface wrapping a wide table: title (full-width, wraps) over a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align), with an optional full-width footnote beneath. Matches the
/// wifi_channels_screen overflow-safe idiom.
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
    final TextTheme text = Theme.of(context).textTheme;
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
            title,
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // The grid sizes to its intrinsic content width and scrolls
          // horizontally when that exceeds the card. Children of a horizontal
          // SingleChildScrollView get unbounded width, so IntrinsicWidth lets
          // each Row shrink-wrap its fixed-width cells while sharing one common
          // width — columns align, nothing overflows. Title + footnote stay
          // full-width and wrap.
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const Divider(color: AppColors.border, height: AppSpacing.sm),
                  ...rows,
                ],
              ),
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              footnote!,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
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
    final TextTheme text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: AppColors.textTertiary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
