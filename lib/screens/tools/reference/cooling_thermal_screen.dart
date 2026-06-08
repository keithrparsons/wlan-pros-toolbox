// Cooling & Thermal — read-only reference for the heat-load conversions a field
// tech needs when sizing cooling for IT spaces: watts <-> BTU/hr <-> tons of
// refrigeration, the "IT load becomes heat becomes cooling" relationship, and
// the standard sensible-heat airflow (CFM / delta-T) formula.
//
// PAGE 3 of the "Power & Cooling" reference category. It follows the approved
// Power Phasing pilot template EXACTLY: typed const datasets, a §8.16
// AppCopyAction that emits the whole page as sectioned TSV, the LayoutBuilder /
// ConstrainedBox / SingleChildScrollView scaffold shared by every reference
// screen (power_phasing_screen / poe_reference_screen are the closest
// siblings), and a ToolHelpFooter keyed on the catalog id.
//
// TABLES ONLY — unlike the Power Phasing pilot and the Ohm's Law page, this
// page carries NO reference graphic. The relationships are numeric and read
// cleanly as tables, so there is no diagram band and no resolver.
//
// Data provenance (GL-005): Pax's verified research brief
// (Deliverables/2026-06-08-power-cooling-references/RESEARCH-BRIEF.md, cooling
// note) plus the two anchor conversions confirmed in the build brief:
//   * 1 W = 3.412 BTU/hr
//   * 1 ton of refrigeration = 12,000 BTU/hr  (so 1 ton ~= 3,517 W)
// Every value in the conversion table is derived from those two anchors only
// (W -> BTU/hr via x 3.412; W -> tons via W x 3.412 / 12,000), so the table
// cannot drift from the anchors. The "IT load becomes heat" relationship is the
// data-center sizing fact the brief states: essentially all electrical power
// drawn by IT equipment is dissipated as heat, so the cooling load in watts
// equals the IT load in watts (then converted to BTU/hr or tons to size the
// cooling plant). The sensible-heat airflow formula uses the standard moist-air
// constant 1.08 (BTU/hr per CFM per degree F at standard conditions); it is
// labeled as the standard-condition approximation, not an exact universal.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. There is no loading/empty/error
// path because nothing is fetched or parsed at runtime. GL-008 network/
// subprocess rules do not apply (nothing fetched, nothing shelled out to).
//
// Glyph / copy notes (GL-004): ASCII hyphen-minus only, never an em dash; US
// spelling; "BTU/hr" not "BTUH"; the degree sign is spelled "degrees F" in
// prose and rendered "deg F" in the formula/copy payload so the pasted text
// stays plain-text safe (no degree glyph); "delta-T" spelled out, not the Greek
// glyph; thousands grouped with a comma in display values (3,412) and left
// ungrouped in the copy payload so the TSV stays a clean number.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_row_semantics.dart';

/// One row of the watts <-> BTU/hr <-> tons conversion table. The display
/// strings are pre-derived from the two anchor conversions (1 W = 3.412 BTU/hr;
/// 1 ton = 12,000 BTU/hr) and verified against the build brief.
@immutable
class ThermalConversion {
  const ThermalConversion({
    required this.watts,
    required this.btuPerHour,
    required this.tons,
    required this.note,
  });

  /// Electrical / heat load in watts, e.g. `100 W`.
  final String watts;

  /// The same load in BTU/hr (watts x 3.412), e.g. `341 BTU/hr`.
  final String btuPerHour;

  /// The same load in tons of refrigeration (BTU/hr / 12,000), e.g.
  /// `0.028 tons`.
  final String tons;

  /// What the row anchors, e.g. `1 ton of refrigeration`.
  final String note;
}

/// One row of the IT-load -> heat -> cooling relationship table. Verified
/// against the research brief's cooling note.
@immutable
class HeatRelation {
  const HeatRelation({
    required this.step,
    required this.relationship,
    required this.detail,
  });

  /// The step, e.g. `IT load to heat`.
  final String step;

  /// The relationship in ASCII, e.g. `Heat (W) = IT load (W)`.
  final String relationship;

  /// A short clarifying detail.
  final String detail;
}

class CoolingThermalScreen extends StatelessWidget {
  const CoolingThermalScreen({super.key});

  /// The two unit anchors, stated plainly. Verified (build brief).
  static const String anchorNote =
      '1 W = 3.412 BTU/hr. 1 ton of refrigeration = 12,000 BTU/hr, which is '
      'about 3,517 W. Every figure in the table below is derived from these two '
      'anchors: watts to BTU/hr multiply by 3.412; watts to tons multiply by '
      '3.412 and divide by 12,000.';

  /// Watts <-> BTU/hr <-> tons. Each row is derived from the two anchors above.
  /// Verified (build brief anchors).
  static const List<ThermalConversion> conversions = <ThermalConversion>[
    ThermalConversion(
      watts: '1 W',
      btuPerHour: '3.412 BTU/hr',
      tons: '0.00028 tons',
      note: 'Unit anchor (1 W)',
    ),
    ThermalConversion(
      watts: '100 W',
      btuPerHour: '341 BTU/hr',
      tons: '0.028 tons',
      note: 'A single edge device or small Access Point',
    ),
    ThermalConversion(
      watts: '293 W',
      btuPerHour: '1,000 BTU/hr',
      tons: '0.083 tons',
      note: '1,000 BTU/hr reference point',
    ),
    ThermalConversion(
      watts: '1,000 W',
      btuPerHour: '3,412 BTU/hr',
      tons: '0.284 tons',
      note: '1 kW of IT load',
    ),
    ThermalConversion(
      watts: '3,517 W',
      btuPerHour: '12,000 BTU/hr',
      tons: '1 ton',
      note: '1 ton of refrigeration',
    ),
    ThermalConversion(
      watts: '5,000 W',
      btuPerHour: '17,060 BTU/hr',
      tons: '1.42 tons',
      note: 'A lightly loaded rack',
    ),
    ThermalConversion(
      watts: '10,000 W',
      btuPerHour: '34,120 BTU/hr',
      tons: '2.84 tons',
      note: '10 kW rack',
    ),
  ];

  /// IT load -> heat -> cooling. Verified against the research brief's cooling
  /// note (effectively all IT power becomes heat that the cooling plant must
  /// remove).
  static const List<HeatRelation> heatChain = <HeatRelation>[
    HeatRelation(
      step: 'IT load to heat',
      relationship: 'Heat (W) = IT load (W)',
      detail:
          'Essentially all electrical power an IT device draws is dissipated '
          'as heat into the room. A 1,000 W server adds about 1,000 W of heat.',
    ),
    HeatRelation(
      step: 'Heat to cooling load',
      relationship: 'Cooling (W) = Heat (W)',
      detail:
          'The cooling plant has to remove as much heat as the equipment '
          'produces, so the cooling load in watts equals the IT load in watts '
          'before any margin.',
    ),
    HeatRelation(
      step: 'Size the plant',
      relationship: 'BTU/hr = W x 3.412;  tons = BTU/hr / 12,000',
      detail:
          'Convert the IT load to BTU/hr or tons to match the cooling '
          'equipment nameplate, then add headroom for losses and growth.',
    ),
  ];

  /// The sensible-heat airflow (CFM / delta-T) guidance. Verified relationship,
  /// standard-condition constant 1.08.
  static const String airflowNote =
      'Airflow for sensible cooling uses the standard-air relationship '
      'BTU/hr = 1.08 x CFM x delta-T (deg F), so CFM = BTU/hr / (1.08 x '
      'delta-T). The constant 1.08 is for standard moist air at sea level; it '
      'shifts with altitude and air density. Rearranged for a target rise: a '
      '3,412 BTU/hr (1 kW) load across a 20 deg F supply-to-return rise needs '
      'about 158 CFM.';

  /// Provenance footnote.
  static const String footnote =
      'Conversions derived from 1 W = 3.412 BTU/hr and 1 ton = 12,000 BTU/hr. '
      'Airflow figure uses the standard-air sensible-heat constant 1.08; verify '
      'against site altitude and air density before sizing equipment.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cooling & Thermal'),
        toolbarHeight: 64,
        // §8.16 — copy the whole page as sectioned TSV: the watts/BTU/ton
        // conversion table, then the IT-load-to-cooling chain. Static data,
        // always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full page as two TSV sections. Section 1 is the
  /// watts/BTU-hr/tons conversion table (watts, BTU/hr, tons, anchor); section
  /// 2 is the IT-load-to-cooling chain (step, relationship, detail). ASCII
  /// tokens ("deg F", "delta-T", "x 3.412") carry straight through so the
  /// pasted text stays plain-text safe. Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Cooling & Thermal')
      ..writeln()
      ..writeln(anchorNote)
      ..writeln()
      ..writeln('Watts / BTU per hour / tons')
      ..writeln(
        <String>['Watts', 'BTU/hr', 'Tons', 'Anchor'].join(tab),
      );
    for (final ThermalConversion c in conversions) {
      buf.writeln(
        <String>[c.watts, c.btuPerHour, c.tons, c.note].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('IT load to heat to cooling')
      ..writeln(
        <String>['Step', 'Relationship', 'Detail'].join(tab),
      );
    for (final HeatRelation h in heatChain) {
      buf.writeln(
        <String>[h.step, h.relationship, h.detail].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(airflowNote)
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
                  _conversionCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _heatChainCard(colors, text, mono),
                  ToolHelpFooter(toolId: 'cooling-thermal'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _conversionCard(
      AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'Watts / BTU per hour / tons',
      note: anchorNote,
      footnote: footnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Watts', width: 96),
          _HeaderCell('BTU/hr', width: 120),
          _HeaderCell('Tons', width: 104),
          _HeaderCell('Anchor', width: 240),
        ],
      ),
      rows: conversions.map((ThermalConversion c) {
        return ReferenceRowSemantics(
          label: rowLabel(c.watts, <String?>[
            c.btuPerHour,
            c.tons,
            c.note,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 96,
                  child: Text(
                    c.watts,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    c.btuPerHour,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 104,
                  child: Text(
                    c.tons,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 240,
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

  Widget _heatChainCard(
      AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'IT load to heat to cooling',
      note: airflowNote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Step', width: 168),
          _HeaderCell('Relationship', width: 288),
          _HeaderCell('Detail', width: 320),
        ],
      ),
      rows: heatChain.map((HeatRelation h) {
        return ReferenceRowSemantics(
          label: rowLabel(h.step, <String?>[
            h.relationship,
            h.detail,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 168,
                  child: Text(
                    h.step,
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 288,
                  child: Text(
                    h.relationship,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Text(
                    h.detail,
                    style: text.bodyMedium?.copyWith(
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
}

/// Card surface wrapping a wide table: title over an optional note, then a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align), with an optional full-width footnote beneath. Matches the
/// power_phasing_screen / poe_reference_screen / wifi_channels_screen
/// overflow-safe idiom.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.header,
    required this.rows,
    this.note,
    this.footnote,
  });

  final String title;
  final Widget header;
  final List<Widget> rows;
  final String? note;
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
        children: <Widget>[
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
                children: <Widget>[
                  header,
                  Divider(color: colors.border, height: AppSpacing.sm),
                  ...rows,
                ],
              ),
            ),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              note!,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
          if (footnote != null) ...<Widget>[
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
