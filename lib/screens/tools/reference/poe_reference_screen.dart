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
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
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
/// `POE_CLASSES` const exactly: [class, max_pd_w, standard, note], extended with
/// the PSE OUTPUT watts per class so the class ladder shows both ends of the
/// link (what the switch sends vs. what the device gets). PSE-output values per
/// IEEE Std 802.3-2022 (Class 5-8 = 45/60/75/90 W).
@immutable
class PoeClass {
  const PoeClass({
    required this.classNum,
    required this.pseWatts,
    required this.maxPdWatts,
    required this.standard,
    required this.note,
  });

  /// Class number, 0–8.
  final int classNum;

  /// PSE output power for this class, in watts (what the switch/injector
  /// supplies). Class 5-8 = 45/60/75/90 W per IEEE 802.3bt.
  final double pseWatts;

  /// Maximum power available at the PD for this class, in watts.
  final double maxPdWatts;

  /// The 802.3 standard that defines this class.
  final String standard;

  /// Short descriptor, e.g. `Type 4 max`.
  final String note;
}

/// One IEEE 802.3 PoE Type row — the cable/power-budget dimension. Adds the
/// Type numbering, PSE voltage range, and pair count alongside the PSE/PD watts
/// already on the standards table. Values per IEEE Std 802.3-2022 Clause 33
/// (Type 1/2) and Clause 145 (Type 3/4).
@immutable
class PoeType {
  const PoeType({
    required this.type,
    required this.name,
    required this.clause,
    required this.voltageRange,
    required this.pseWatts,
    required this.pdWatts,
    required this.pairs,
  });

  /// IEEE Type number, e.g. `Type 3`.
  final String type;

  /// Common name, e.g. `PoE++ / 4PPoE`.
  final String name;

  /// 802.3 clause origin, e.g. `bt`.
  final String clause;

  /// PSE output voltage range at the switch, e.g. `52.0-57.0 V`.
  final String voltageRange;

  /// PSE power supplied, in watts.
  final double pseWatts;

  /// PD power available (minimum), in watts.
  final double pdWatts;

  /// Powered pairs, e.g. `4-pair`.
  final String pairs;
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

  /// PD power classes. Ported from PWA app.js POE_CLASSES; PSE output watts
  /// added per IEEE Std 802.3-2022 (Class 5-8 = 45/60/75/90 W).
  static const List<PoeClass> classes = [
    PoeClass(
      classNum: 0,
      pseWatts: 15.4,
      maxPdWatts: 12.95,
      standard: '802.3af',
      note: 'Default / unclassified',
    ),
    PoeClass(
      classNum: 1,
      pseWatts: 4.0,
      maxPdWatts: 3.84,
      standard: '802.3af',
      note: 'Low power',
    ),
    PoeClass(
      classNum: 2,
      pseWatts: 7.0,
      maxPdWatts: 6.49,
      standard: '802.3af',
      note: 'Medium power',
    ),
    PoeClass(
      classNum: 3,
      pseWatts: 15.4,
      maxPdWatts: 12.95,
      standard: '802.3af',
      note: 'af maximum',
    ),
    PoeClass(
      classNum: 4,
      pseWatts: 30.0,
      maxPdWatts: 25.5,
      standard: '802.3at',
      note: 'PoE+ max',
    ),
    PoeClass(
      classNum: 5,
      pseWatts: 45.0,
      maxPdWatts: 40.0,
      standard: '802.3bt',
      note: 'Type 3',
    ),
    PoeClass(
      classNum: 6,
      pseWatts: 60.0,
      maxPdWatts: 51.0,
      standard: '802.3bt',
      note: 'Type 3 max',
    ),
    PoeClass(
      classNum: 7,
      pseWatts: 75.0,
      maxPdWatts: 62.0,
      standard: '802.3bt',
      note: 'Type 4',
    ),
    PoeClass(
      classNum: 8,
      pseWatts: 90.0,
      maxPdWatts: 71.3,
      standard: '802.3bt',
      note: 'Type 4 max',
    ),
  ];

  /// IEEE 802.3 PoE Types — the cable/power-budget dimension. Voltage range,
  /// pairs, and PSE/PD watts per IEEE Std 802.3-2022 Clause 33 (Type 1/2) and
  /// Clause 145 (Type 3/4).
  static const List<PoeType> types = [
    PoeType(
      type: 'Type 1',
      name: 'PoE',
      clause: 'af',
      voltageRange: '44.0-57.0 V',
      pseWatts: 15.4,
      pdWatts: 12.95,
      pairs: '2-pair',
    ),
    PoeType(
      type: 'Type 2',
      name: 'PoE+',
      clause: 'at',
      voltageRange: '50.0-57.0 V',
      pseWatts: 30.0,
      pdWatts: 25.5,
      pairs: '2-pair',
    ),
    PoeType(
      type: 'Type 3',
      name: 'PoE++ / 4PPoE',
      clause: 'bt',
      voltageRange: '52.0-57.0 V',
      pseWatts: 60.0,
      pdWatts: 51.0,
      pairs: '4-pair',
    ),
    PoeType(
      type: 'Type 4',
      name: 'PoE++ Hi',
      clause: 'bt',
      voltageRange: '52.0-57.0 V',
      pseWatts: 90.0,
      pdWatts: 71.3,
      pairs: '4-pair',
    ),
  ];

  /// Electrical-limit note for the Types card. Per-pair current per IEEE
  /// 802.3-2022.
  static const String typesFootnote =
      'PSE output voltage is measured at the switch or injector. Max current is '
      '600 mA per pair for Types 1-3 (Class up to 6); Type 4 at Class 8 draws up '
      'to 960 mA per pair across all four pairs.';

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
      ..writeln('IEEE 802.3 Types')
      ..writeln(
        <String>[
          'Type',
          'Name',
          'Clause',
          'PSE voltage',
          'PSE (W)',
          'PD (W)',
          'Pairs',
        ].join(tab),
      );
    for (final PoeType t in types) {
      buf.writeln(
        <String>[
          t.type,
          t.name,
          t.clause,
          t.voltageRange,
          _fmt(t.pseWatts),
          _fmt(t.pdWatts),
          t.pairs,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(typesFootnote)
      ..writeln()
      ..writeln('PD power classes')
      ..writeln(
        <String>[
          'Class',
          'PSE out (W)',
          'Max at PD (W)',
          'Standard',
          'Note',
        ].join(tab),
      );
    for (final PoeClass c in classes) {
      buf.writeln(
        <String>[
          '${c.classNum}',
          _fmt(c.pseWatts),
          _fmt(c.maxPdWatts),
          c.standard,
          c.note,
        ].join(tab),
      );
    }
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
                    toolId: 'poe-reference',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('poe-reference'))
                    const SizedBox(height: AppSpacing.md),
                  _standardsCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _typesCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _classesCard(colors, text, mono),
                  ToolHelpFooter(toolId: 'poe-reference'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _standardsCard(
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
  ) {
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
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    s.name,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '${_fmt(s.pseWatts)} W',
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '${_fmt(s.pdWatts)} W',
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    s.pairs,
                    style: mono.inlineCode.copyWith(color: colors.textTertiary),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    s.classes,
                    style: mono.inlineCode.copyWith(color: colors.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _typesCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'IEEE 802.3 Types',
      footnote: typesFootnote,
      header: const Row(
        children: [
          _HeaderCell('Type', width: 72),
          _HeaderCell('Name', width: 128),
          _HeaderCell('Clause', width: 56),
          _HeaderCell('PSE volts', width: 96),
          _HeaderCell('PSE', width: 64),
          _HeaderCell('PD', width: 64),
          _HeaderCell('Pairs', width: 64),
        ],
      ),
      rows: types.map((PoeType t) {
        return ReferenceRowSemantics(
          label: rowLabel(t.type, <String?>[
            t.name,
            'clause ${t.clause}',
            'PSE voltage ${t.voltageRange}',
            'PSE ${_fmt(t.pseWatts)} watts',
            'PD ${_fmt(t.pdWatts)} watts',
            'pairs ${t.pairs}',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    t.type,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 128,
                  child: Text(
                    t.name,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    t.clause,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    t.voltageRange,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '${_fmt(t.pseWatts)} W',
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '${_fmt(t.pdWatts)} W',
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    t.pairs,
                    style: mono.inlineCode.copyWith(color: colors.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _classesCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'PD power classes',
      header: const Row(
        children: [
          _HeaderCell('Class', width: 56),
          _HeaderCell('PSE out', width: 80),
          _HeaderCell('Max at PD', width: 88),
          _HeaderCell('Standard', width: 88),
          _HeaderCell('Note', width: 160),
        ],
      ),
      rows: classes.map((PoeClass c) {
        return ReferenceRowSemantics(
          label: rowLabel('Class ${c.classNum}', <String?>[
            'PSE output ${_fmt(c.pseWatts)} watts',
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
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    '${_fmt(c.pseWatts)} W',
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    '${_fmt(c.maxPdWatts)} W',
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    c.standard,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: Text(
                    c.note,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
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
