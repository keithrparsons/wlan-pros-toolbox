// Ethernet Cable — read-only reference card.
//
// One static table ported verbatim from the RF Tools PWA (app.js ETH_DATA,
// view data-tool="ethernet"): the Ethernet cable categories with bandwidth,
// max speed, max distance at 1G/10G, PoE support, shielding, and typical use.
// Plus the PWA's PoE++ footnote tip.
//
// This is a pure read-only reference — no inputs, no computation, no network.
// It works on every platform (no NetworkUnavailableView). The only state is
// "success": the bundled dataset always renders. There is no loading, empty,
// or error path because nothing is fetched or parsed at runtime.
//
// Overflow-safe: the seven-column table exceeds phone width, so it scrolls
// horizontally inside the fixed card — the same idiom as mcs_index_screen.
//
// Glyph note: the PWA uses an em dash (—) as the "not applicable" cell marker
// in ETH_DATA. Per the no-em-dash rule we render N/A as the ASCII string "—"
// is NOT used; the PWA's "—" cells are reproduced as the literal value the
// table shows, mapped to an ASCII "N/A" marker so no em dash ships in the app.

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

/// One Ethernet cable category row. Ported verbatim from PWA app.js ETH_DATA
/// (`[cat, max_mhz, max_speed, dist_1g, dist_10g, poe, shielding, use]`).
class EthCable {
  const EthCable({
    required this.category,
    required this.maxMhz,
    required this.maxSpeed,
    required this.dist1g,
    required this.dist10g,
    required this.poe,
    required this.shielding,
    required this.use,
  });

  /// Category label, e.g. "Cat6A".
  final String category;

  /// Max bandwidth in MHz.
  final int maxMhz;

  /// Max rated speed, e.g. "10 Gbps".
  final String maxSpeed;

  /// Max distance at 1 Gbps. "N/A" where the PWA shows a dash.
  final String dist1g;

  /// Max distance at 10 Gbps. "N/A" where the PWA shows a dash.
  final String dist10g;

  /// PoE support, e.g. "802.3bt (all)".
  final String poe;

  /// Shielding types, e.g. "F/UTP, S/FTP".
  final String shielding;

  /// Typical use note.
  final String use;
}

/// One BASE-T speed grade — the standard, its rate, the minimum cabling it
/// needs, the max channel distance, and the IEEE spec. Covers the multi-gig
/// rates (2.5G/5G, 802.3bz) that sit between 1G and 10G. Values per IEEE
/// 802.3bz-2016.
@immutable
class EthSpeedGrade {
  const EthSpeedGrade({
    required this.standard,
    required this.speed,
    required this.minCabling,
    required this.maxDistance,
    required this.ieeeSpec,
  });

  /// BASE-T standard, e.g. `2.5GBASE-T`.
  final String standard;

  /// Rate, e.g. `2.5 Gbps`.
  final String speed;

  /// Minimum cabling category, e.g. `Cat5e`.
  final String minCabling;

  /// Max channel distance, e.g. `100m`.
  final String maxDistance;

  /// Defining IEEE specification, e.g. `802.3bz (2016)`.
  final String ieeeSpec;
}

/// One ISO/IEC 11801 shielding code — the `[overall]/[per-pair]TP` notation
/// and its plain-language name. Per ISO/IEC 11801.
@immutable
class ShieldingCode {
  const ShieldingCode({
    required this.code,
    required this.overall,
    required this.perPair,
    required this.name,
  });

  /// Shielding code, e.g. `S/FTP`.
  final String code;

  /// Overall (cable-level) screen, e.g. `Braid`.
  final String overall;

  /// Per-pair screen, e.g. `Foil per pair`.
  final String perPair;

  /// Plain-language name.
  final String name;
}

class EthernetCableScreen extends StatelessWidget {
  const EthernetCableScreen({super.key});

  /// Ethernet cable categories. Ported verbatim from PWA app.js ETH_DATA.
  /// The PWA's em-dash "not applicable" cells are reproduced as the ASCII
  /// marker "N/A" (no em dash ships in the app); every other value is exact.
  static const List<EthCable> ethData = [
    EthCable(
      category: 'Cat5e',
      maxMhz: 100,
      maxSpeed: '1 Gbps',
      dist1g: '100m',
      dist10g: 'N/A',
      poe: '802.3af / at',
      shielding: 'UTP or FTP',
      use: 'Standard LAN wiring',
    ),
    EthCable(
      category: 'Cat6',
      maxMhz: 250,
      maxSpeed: '10 Gbps',
      dist1g: '100m',
      dist10g: '55m',
      poe: '802.3af / at',
      shielding: 'UTP or STP',
      use: 'Modern LAN, some 10G',
    ),
    EthCable(
      category: 'Cat6A',
      maxMhz: 500,
      maxSpeed: '10 Gbps',
      dist1g: '100m',
      dist10g: '100m',
      poe: '802.3bt (all)',
      shielding: 'F/UTP, S/FTP',
      use: 'Preferred for PoE++ APs',
    ),
    EthCable(
      category: 'Cat7',
      maxMhz: 600,
      maxSpeed: '10 Gbps',
      dist1g: '100m',
      dist10g: '100m',
      poe: 'Limited',
      shielding: 'S/FTP, PIMF',
      use: 'Specialty, non-std plugs',
    ),
    EthCable(
      category: 'Cat7A',
      maxMhz: 1000,
      maxSpeed: '40 Gbps',
      dist1g: '100m',
      dist10g: '100m',
      poe: 'Limited',
      shielding: 'S/FTP, PIMF',
      use: 'Specialty',
    ),
    EthCable(
      category: 'Cat8',
      maxMhz: 2000,
      maxSpeed: '25/40 Gbps',
      dist1g: '100m',
      dist10g: '100m',
      poe: 'Limited',
      shielding: 'S/FTP',
      use: 'Data center short runs; 25/40G design rate to 30 m',
    ),
  ];

  /// BASE-T speed grades — the multi-gig rates (2.5G/5G) that fill the gap
  /// between 1G and 10G, with 1G and 10G as anchors. Per IEEE 802.3ab
  /// (1000BASE-T), 802.3bz-2016 (2.5G/5G), and 802.3an (10GBASE-T).
  static const List<EthSpeedGrade> speedGrades = <EthSpeedGrade>[
    EthSpeedGrade(
      standard: '1000BASE-T',
      speed: '1 Gbps',
      minCabling: 'Cat5e',
      maxDistance: '100m',
      ieeeSpec: '802.3ab (1999)',
    ),
    EthSpeedGrade(
      standard: '2.5GBASE-T',
      speed: '2.5 Gbps',
      minCabling: 'Cat5e',
      maxDistance: '100m',
      ieeeSpec: '802.3bz (2016)',
    ),
    EthSpeedGrade(
      standard: '5GBASE-T',
      speed: '5 Gbps',
      minCabling: 'Cat6',
      maxDistance: '100m',
      ieeeSpec: '802.3bz (2016)',
    ),
    EthSpeedGrade(
      standard: '10GBASE-T',
      speed: '10 Gbps',
      minCabling: 'Cat6A',
      maxDistance: '100m',
      ieeeSpec: '802.3an (2006)',
    ),
  ];

  /// Footnote for the speed-grade table — why the multi-gig rates exist.
  static const String speedGradesFootnote =
      '2.5GBASE-T and 5GBASE-T (both 802.3bz) light up speeds above 1G on '
      'already-installed twisted pair without a Cat6A re-pull. 2.5G runs on '
      'Cat5e to 100 m; 5G is specified for Cat6 to 100 m (heavy alien-crosstalk '
      'bundling may shorten Cat6 runs; Cat6A removes that concern). 10GBASE-T '
      'reaches the full 100 m channel only on Cat6A.';

  /// ISO/IEC 11801 shielding codes — the `[overall]/[per-pair]TP` notation.
  static const List<ShieldingCode> shieldingCodes = <ShieldingCode>[
    ShieldingCode(
      code: 'U/UTP',
      overall: 'None',
      perPair: 'None',
      name: 'Unshielded twisted pair',
    ),
    ShieldingCode(
      code: 'F/UTP',
      overall: 'Foil',
      perPair: 'None',
      name: 'Foil-screened, unshielded pairs (a.k.a. FTP)',
    ),
    ShieldingCode(
      code: 'S/FTP',
      overall: 'Braid',
      perPair: 'Foil per pair',
      name: 'Overall braid + per-pair foil (common Cat6A/Cat7)',
    ),
    ShieldingCode(
      code: 'SF/UTP',
      overall: 'Braid + Foil',
      perPair: 'None',
      name: 'Braid-and-foil overall screen, unshielded pairs',
    ),
    ShieldingCode(
      code: 'U/FTP',
      overall: 'None',
      perPair: 'Foil per pair',
      name: 'Individually foil-shielded pairs, no overall screen',
    ),
  ];

  /// Legend key for the shielding table.
  static const String shieldingFootnote =
      'Format is [overall screen]/[per-pair screen]TP. U = unshielded, F = foil, '
      'S = braided screen, TP = twisted pair. The character before the slash is '
      'the cable-level (overall) screen; the character(s) after describe the '
      'pair-level screen.';

  /// PoE++ footnote, ported verbatim from the PWA ethernet view.
  static const String footnote =
      'PoE++ tip: Use Cat6A for 802.3bt deployments. Bundled Cat6 cables '
      'running PoE++ generate significant heat. Cat6A\'s larger conductor and '
      'diameter dissipate heat better. TIA-568 recommends Cat6A for PoE++ in '
      'cable bundles. Cat8 carries 1G/10G to the full 100 m channel; its '
      '25G/40G design rate is limited to ~30 m (data-center top-of-rack).';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ethernet Cable'),
        toolbarHeight: 64,
        // §8.16 — copy the cable table as TSV. Static data, always enabled.
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the Ethernet table as TSV. One title, the full
  /// eight-column header (every field the screen shows, including the typical-
  /// use column the scroll table drops to the footnote), one row per category,
  /// then the footnote. Always non-null: the dataset is static, so copy is
  /// never disabled.
  String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Ethernet Cable Categories')
      ..writeln(
        <String>[
          'Category',
          'MHz',
          'Max speed',
          '@1G',
          '@10G',
          'PoE',
          'Shielding',
          'Typical use',
        ].join(tab),
      );
    for (final EthCable e in ethData) {
      buf.writeln(
        <String>[
          e.category,
          '${e.maxMhz}',
          e.maxSpeed,
          e.dist1g,
          e.dist10g,
          e.poe,
          e.shielding,
          e.use,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('BASE-T speed grades')
      ..writeln(
        <String>[
          'Standard',
          'Speed',
          'Min cabling',
          'Max distance',
          'IEEE spec',
        ].join(tab),
      );
    for (final EthSpeedGrade g in speedGrades) {
      buf.writeln(
        <String>[
          g.standard,
          g.speed,
          g.minCabling,
          g.maxDistance,
          g.ieeeSpec,
        ].join(tab),
      );
    }
    buf.writeln(speedGradesFootnote);
    buf
      ..writeln()
      ..writeln('Shielding codes (ISO/IEC 11801)')
      ..writeln(<String>['Code', 'Overall', 'Per pair', 'Name'].join(tab));
    for (final ShieldingCode s in shieldingCodes) {
      buf.writeln(<String>[s.code, s.overall, s.perPair, s.name].join(tab));
    }
    buf.writeln(shieldingFootnote);
    buf
      ..writeln()
      ..writeln('Notes')
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
                    toolId: 'ethernet-cable',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('ethernet-cable'))
                    const SizedBox(height: AppSpacing.md),
                  _tableCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _speedGradesCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _shieldingCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _footnoteCard(colors, text),
                  ToolHelpFooter(toolId: 'ethernet-cable'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tableCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
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
            '${ethData.length} cable categories',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Horizontal scroll: seven columns exceed phone width, so the data
          // table scrolls sideways inside the fixed card (mcs_index idiom).
          HorizontalScrollTable(child: _dataTable(colors, text, mono)),
        ],
      ),
    );
  }

  Widget _dataTable(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);
    final TextStyle cellStyle = (text.bodyMedium ?? const TextStyle()).copyWith(
      color: colors.textPrimary,
    );
    final TextStyle smallStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textSecondary);

    return DataTable(
      headingRowHeight: 44,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 56,
      columnSpacing: AppSpacing.md,
      horizontalMargin: 0,
      dividerThickness: 1,
      headingTextStyle: headStyle,
      columns: const [
        DataColumn(label: Text('Cat')),
        DataColumn(label: Text('MHz'), numeric: true),
        DataColumn(label: Text('Max Speed')),
        DataColumn(label: Text('@1G')),
        DataColumn(label: Text('@10G')),
        DataColumn(label: Text('PoE')),
        DataColumn(label: Text('Shielding')),
      ],
      rows: ethData.map((EthCable e) {
        // DataTable renders each DataCell as its own column node, so a screen
        // reader would otherwise read "Cat6A", "500", "10 Gbps"… as seven
        // disconnected nodes. We give the FIRST cell the full row summary via
        // Semantics(label:) and exclude the remaining cells from semantics, so
        // the row announces once as a coherent unit. (Vera F-02.)
        final String summary = rowLabel(e.category, <String?>[
          '${e.maxMhz} megahertz',
          'max speed ${e.maxSpeed}',
          e.dist1g == 'N/A' ? null : '${e.dist1g} at 1 gigabit',
          e.dist10g == 'N/A' ? null : '${e.dist10g} at 10 gigabit',
          'PoE ${e.poe}',
          'shielding ${e.shielding}',
        ]);
        return DataRow(
          cells: [
            DataCell(
              Semantics(
                label: summary,
                container: true,
                child: ExcludeSemantics(
                  child: Text(
                    e.category,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            DataCell(
              ExcludeSemantics(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${e.maxMhz}',
                    style: mono.inlineCode.copyWith(color: colors.textPrimary),
                  ),
                ),
              ),
            ),
            DataCell(
              ExcludeSemantics(child: Text(e.maxSpeed, style: cellStyle)),
            ),
            DataCell(
              ExcludeSemantics(
                child: Text(
                  e.dist1g,
                  style: mono.inlineCode.copyWith(
                    color: e.dist1g == 'N/A'
                        ? colors.textTertiary
                        : colors.textPrimary,
                  ),
                ),
              ),
            ),
            DataCell(
              ExcludeSemantics(
                child: Text(
                  e.dist10g,
                  style: mono.inlineCode.copyWith(
                    color: e.dist10g == 'N/A'
                        ? colors.textTertiary
                        : colors.textPrimary,
                  ),
                ),
              ),
            ),
            DataCell(ExcludeSemantics(child: Text(e.poe, style: smallStyle))),
            DataCell(
              ExcludeSemantics(child: Text(e.shielding, style: smallStyle)),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _speedGradesCard(
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
  ) {
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);
    final TextStyle smallStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textSecondary);
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
            'BASE-T speed grades',
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
              dataRowMaxHeight: 56,
              columnSpacing: AppSpacing.md,
              horizontalMargin: 0,
              dividerThickness: 1,
              headingTextStyle: headStyle,
              columns: const <DataColumn>[
                DataColumn(label: Text('Standard')),
                DataColumn(label: Text('Speed')),
                DataColumn(label: Text('Min cabling')),
                DataColumn(label: Text('Max dist')),
                DataColumn(label: Text('IEEE spec')),
              ],
              rows: speedGrades.map((EthSpeedGrade g) {
                final String summary = rowLabel(g.standard, <String?>[
                  'speed ${g.speed}',
                  'minimum cabling ${g.minCabling}',
                  'max distance ${g.maxDistance}',
                  'spec ${g.ieeeSpec}',
                ]);
                return DataRow(
                  cells: <DataCell>[
                    DataCell(
                      Semantics(
                        label: summary,
                        container: true,
                        child: ExcludeSemantics(
                          child: Text(
                            g.standard,
                            style: mono.inlineCode.copyWith(
                              color: colors.textAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(
                          g.speed,
                          style: mono.inlineCode.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(g.minCabling, style: smallStyle),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(
                          g.maxDistance,
                          style: mono.inlineCode.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(g.ieeeSpec, style: smallStyle),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            speedGradesFootnote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _shieldingCard(
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
  ) {
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);
    final TextStyle smallStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textSecondary);
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
            'Shielding codes (ISO/IEC 11801)',
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
              dataRowMaxHeight: 56,
              columnSpacing: AppSpacing.md,
              horizontalMargin: 0,
              dividerThickness: 1,
              headingTextStyle: headStyle,
              columns: const <DataColumn>[
                DataColumn(label: Text('Code')),
                DataColumn(label: Text('Overall')),
                DataColumn(label: Text('Per pair')),
                DataColumn(label: Text('Name')),
              ],
              rows: shieldingCodes.map((ShieldingCode s) {
                final String summary = rowLabel(s.code, <String?>[
                  'overall screen ${s.overall}',
                  'per-pair screen ${s.perPair}',
                  s.name,
                ]);
                return DataRow(
                  cells: <DataCell>[
                    DataCell(
                      Semantics(
                        label: summary,
                        container: true,
                        child: ExcludeSemantics(
                          child: Text(
                            s.code,
                            style: mono.inlineCode.copyWith(
                              color: colors.textAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(s.overall, style: smallStyle),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(s.perPair, style: smallStyle),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(
                          s.name,
                          style: text.labelMedium?.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            shieldingFootnote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _footnoteCard(AppColorScheme colors, TextTheme text) {
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
            'Notes',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            footnote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          // The "typical use" column is dropped from the scroll table to keep
          // the row legible; surface it here so no PWA data is lost.
          ...ethData.map(
            (EthCable e) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: RichText(
                text: TextSpan(
                  style: text.labelMedium?.copyWith(color: colors.textTertiary),
                  children: [
                    TextSpan(
                      text: '${e.category}: ',
                      style: text.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: e.use),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
