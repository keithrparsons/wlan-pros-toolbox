// DSCP / QoS Markings — a read-only reference for the Wi-Fi-to-wired QoS
// mapping: the four WMM Access Categories, the 802.11 User Priority (UP) values
// they carry, and the DSCP markings RFC 8325 recommends so wired and wireless
// agree. It PROMINENTLY flags the default-mapping trap that demotes voice into
// the video queue.
//
// DATA SOURCE: RFC 8325 (Mapping Diffserv to IEEE 802.11), Figure 1 and §4;
// IEEE 802.11e / 802.11-2020 (UP-to-AC mapping); IEEE 802.1Q (priority code
// point); Wi-Fi Alliance WMM. DSCP class decimal values per RFC 2474 (Class
// Selector / DF), RFC 2597 (Assured Forwarding), RFC 3246 (EF), RFC 5865
// (VOICE-ADMIT / VA). Values reproduced verbatim from the verified dataset
// Deliverables/2026-06-08-reference-batch/protocols-data.md, Page 4.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. No loading/empty/error path.
//
// The voice-into-video trap is rendered as a §8.13 status-WARNING callout card
// (statusWarning border + 12% tint, an Icons.warning_amber leading glyph, the
// verdict word in text so color is never the sole carrier — SC 1.4.1). It is
// placed directly beneath the mapping table, where it bites.
//
// CONCEPT GRAPHIC: this screen requests `assets/tool-graphics/dscp-qos-grid.svg`
// via the standard multi-graphic resolver (ConceptGraphicBand + ToolAssets) —
// it renders when the asset is bundled and degrades to nothing (no broken-image
// box, no layout jump) when Charta has not authored it yet.
//
// Pattern: mirrors poe_reference_screen — Scaffold + AppBar (toolbarHeight 64,
// AppCopyAction), SafeArea(top: false), LayoutBuilder isDesktop @720,
// ConstrainedBox to calculatorMaxWidth, SingleChildScrollView,
// ConceptGraphicBand, two wide tables, the warning callout, ToolHelpFooter.
//
// Glyph note: ASCII only; no em dash. AC names, UP values, DSCP names + decimal
// values render in the mono family (identifiers / numerics).

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One row of the WMM AC <-> 802.11 UP <-> DSCP mapping (per RFC 8325).
@immutable
class QosMapping {
  const QosMapping({
    required this.accessCategory,
    required this.traffic,
    required this.userPriority,
    required this.dscp,
    required this.dscpDecimal,
  });

  /// WMM Access Category, e.g. `AC_VO (Voice)`.
  final String accessCategory;

  /// The traffic class this row covers, e.g. `Telephony / voice`.
  final String traffic;

  /// 802.11 User Priority value(s), e.g. `6` or `3, 0`.
  final String userPriority;

  /// Recommended DSCP marking(s), e.g. `EF (and VA)`.
  final String dscp;

  /// DSCP decimal value(s), e.g. `46 (VA 44)`.
  final String dscpDecimal;
}

/// One DSCP class reference row: name, decimal value, and a note.
@immutable
class DscpClass {
  const DscpClass({
    required this.name,
    required this.decimal,
    required this.notes,
  });

  /// DSCP name, e.g. `EF`, `AF41 / AF42 / AF43`.
  final String name;

  /// Decimal value(s), e.g. `46` or `34 / 36 / 38`.
  final String decimal;

  /// Short note describing the class.
  final String notes;
}

class DscpQosScreen extends StatelessWidget {
  const DscpQosScreen({super.key});

  /// WMM AC <-> 802.11 UP <-> DSCP mapping per RFC 8325. Verbatim from the
  /// verified dataset (protocols-data.md, Page 4).
  static const List<QosMapping> mappings = <QosMapping>[
    QosMapping(
      accessCategory: 'AC_VO (Voice)',
      traffic: 'Network control',
      userPriority: '7',
      dscp: 'CS7 / CS6',
      dscpDecimal: '56 / 48',
    ),
    QosMapping(
      accessCategory: 'AC_VO (Voice)',
      traffic: 'Telephony / voice',
      userPriority: '6',
      dscp: 'EF (and VA)',
      dscpDecimal: '46 (VA 44)',
    ),
    QosMapping(
      accessCategory: 'AC_VI (Video)',
      traffic: 'Signaling',
      userPriority: '5',
      dscp: 'CS5',
      dscpDecimal: '40',
    ),
    QosMapping(
      accessCategory: 'AC_VI (Video)',
      traffic: 'Interactive / streaming video',
      userPriority: '4',
      dscp: 'AF41 / AF42 / AF43',
      dscpDecimal: '34 / 36 / 38',
    ),
    QosMapping(
      accessCategory: 'AC_BE (Best Effort)',
      traffic: 'Low-latency / standard data',
      userPriority: '3, 0',
      dscp: 'AF21-23, DF',
      dscpDecimal: '18/20/22, 0',
    ),
    QosMapping(
      accessCategory: 'AC_BK (Background)',
      traffic: 'Low-priority data',
      userPriority: '1, 2',
      dscp: 'CS1',
      dscpDecimal: '8',
    ),
  ];

  /// DSCP class reference (names and decimal values). Verbatim from the
  /// verified dataset.
  static const List<DscpClass> dscpClasses = <DscpClass>[
    DscpClass(
      name: 'DF (Default / CS0)',
      decimal: '0',
      notes: 'Best-effort, no preference.',
    ),
    DscpClass(
      name: 'CS1',
      decimal: '8',
      notes: 'Class Selector 1 (lowest priority / scavenger).',
    ),
    DscpClass(name: 'CS2', decimal: '16', notes: 'Class Selector 2.'),
    DscpClass(name: 'CS3', decimal: '24', notes: 'Class Selector 3.'),
    DscpClass(name: 'CS4', decimal: '32', notes: 'Class Selector 4.'),
    DscpClass(name: 'CS5', decimal: '40', notes: 'Class Selector 5.'),
    DscpClass(name: 'CS6', decimal: '48', notes: 'Class Selector 6.'),
    DscpClass(
      name: 'CS7',
      decimal: '56',
      notes: 'Class Selector 7 (network control).',
    ),
    DscpClass(
      name: 'AF11 / AF12 / AF13',
      decimal: '10 / 12 / 14',
      notes: 'Assured Forwarding class 1, drop precedence low/med/high.',
    ),
    DscpClass(
      name: 'AF21 / AF22 / AF23',
      decimal: '18 / 20 / 22',
      notes: 'Assured Forwarding class 2.',
    ),
    DscpClass(
      name: 'AF31 / AF32 / AF33',
      decimal: '26 / 28 / 30',
      notes: 'Assured Forwarding class 3.',
    ),
    DscpClass(
      name: 'AF41 / AF42 / AF43',
      decimal: '34 / 36 / 38',
      notes: 'Assured Forwarding class 4.',
    ),
    DscpClass(name: 'EF', decimal: '46', notes: 'Expedited Forwarding (voice).'),
    DscpClass(name: 'VA', decimal: '44', notes: 'Voice-Admit.'),
  ];

  /// The UP-to-AC grouping note (802.11e / WMM).
  static const String mappingNote =
      'UP-to-AC grouping (802.11e / WMM): UP 1 and 2 form AC_BK; UP 0 and 3 '
      'form AC_BE; UP 4 and 5 form AC_VI; UP 6 and 7 form AC_VO. RFC 8325 '
      'deliberately reassigns markings (it keeps voice in AC_VO via UP 6, not '
      'UP 5) to fix the default-mapping pitfall below.';

  /// The warning-callout title — the trap stated as a verdict word.
  static const String trapTitle =
      'Trap: the default mapping demotes voice into the video queue';

  /// The warning-callout body — why EF (46) lands in AC_VI, and the fix.
  static const String trapBody =
      'Most equipment, absent explicit policy, derives 802.11 UP from the three '
      'most significant bits of the DSCP value (UP = DSCP >> 3). That silently '
      'misclassifies the most important traffic:\n\n'
      '- Voice lands in the wrong queue. EF is 46 = 101110; the top three bits '
      'are 101 = 5, so EF maps to UP 5 — which is AC_VI (Video), not AC_VO '
      '(Voice). Voice loses its dedicated access category.\n'
      '- Video / streaming demote to best-effort. AF31 (26) and CS3 (24) map to '
      'UP 3, landing in AC_BE instead of the intended video treatment.\n'
      '- OAM falls to background. CS2 (16) maps to UP 2, which sits in AC_BK '
      '(Background).\n\n'
      'RFC 8325 fixes exactly this: it specifies an explicit DSCP-to-UP table '
      '(so EF -> UP 6 -> AC_VO) instead of the naive top-three-bits shortcut. '
      'When wired DSCP markings cross onto Wi-Fi without an RFC 8325-style '
      'policy applied, expect voice quality to degrade because it is competing '
      'in the video queue.';

  /// Footnote — RFC provenance for the mapping and the DSCP class values.
  static const String footnote =
      'Mapping per RFC 8325 (Mapping Diffserv to IEEE 802.11), Figure 1 / §4; '
      'UP-to-AC per IEEE 802.11e / 802.11-2020; WMM per Wi-Fi Alliance. DSCP '
      'class decimal values per RFC 2474 (CS / DF), RFC 2597 (AF), RFC 3246 '
      '(EF), RFC 5865 (VA).';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DSCP / QoS Markings'),
        toolbarHeight: 64,
        // §8.16 — copy both tables + the trap note as a multi-section TSV.
        // Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — three sections: the WMM AC mapping (AC, Traffic, UP,
  /// DSCP, Decimal), the DSCP class reference (Name, Decimal, Notes), and the
  /// trap as a plain-text note so the warning survives the copy. Always
  /// non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('DSCP / QoS Markings')
      ..writeln()
      ..writeln('WMM Access Category <-> 802.11 UP <-> DSCP (per RFC 8325)')
      ..writeln(
        <String>[
          'WMM AC',
          'Traffic',
          '802.11 UP',
          'Recommended DSCP',
          'DSCP decimal',
        ].join(tab),
      );
    for (final QosMapping m in mappings) {
      buf.writeln(
        <String>[
          m.accessCategory,
          m.traffic,
          m.userPriority,
          m.dscp,
          m.dscpDecimal,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(mappingNote)
      ..writeln()
      ..writeln('DSCP class reference')
      ..writeln(<String>['DSCP name', 'Decimal', 'Notes'].join(tab));
    for (final DscpClass c in dscpClasses) {
      buf.writeln(<String>[c.name, c.decimal, c.notes].join(tab));
    }
    buf
      ..writeln()
      ..writeln(trapTitle)
      ..writeln(trapBody);
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
                children: <Widget>[
                  // Multi-graphic resolver: requests dscp-qos-grid.svg and
                  // degrades to nothing when the asset is not bundled.
                  ConceptGraphicBand(
                    toolId: 'dscp-qos',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('dscp-qos'))
                    const SizedBox(height: AppSpacing.md),
                  _mappingCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  // The trap, flagged prominently right under the mapping.
                  _TrapCallout(title: trapTitle, body: trapBody),
                  const SizedBox(height: AppSpacing.md),
                  _dscpClassCard(colors, text, mono),
                  ToolHelpFooter(toolId: 'dscp-qos'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _mappingCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'WMM AC ↔ 802.11 UP ↔ DSCP (per RFC 8325)',
      footnote: mappingNote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('WMM AC', width: 132),
          _HeaderCell('Traffic', width: 180),
          _HeaderCell('UP', width: 48),
          _HeaderCell('DSCP', width: 132),
          _HeaderCell('Decimal', width: 96),
        ],
      ),
      rows: mappings.map((QosMapping m) {
        // Voice (AC_VO) rows carry the most-important traffic and are the heart
        // of the trap below; give the AC cell the accent so the eye lands there.
        final bool voice = m.accessCategory.startsWith('AC_VO');
        return ReferenceRowSemantics(
          label: rowLabel(m.accessCategory, <String?>[
            m.traffic,
            'UP ${m.userPriority}',
            'DSCP ${m.dscp}',
            'decimal ${m.dscpDecimal}',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 132,
                  child: Text(
                    m.accessCategory,
                    style: mono.inlineCode.copyWith(
                      color: voice ? colors.textAccent : colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: Text(
                    m.traffic,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    m.userPriority,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 132,
                  child: Text(
                    m.dscp,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    m.dscpDecimal,
                    style: mono.inlineCode.copyWith(
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

  Widget _dscpClassCard(
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
  ) {
    return _TableCard(
      title: 'DSCP class reference',
      footnote: footnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('DSCP name', width: 160),
          _HeaderCell('Decimal', width: 110),
          _HeaderCell('Notes', width: 280),
        ],
      ),
      rows: dscpClasses.map((DscpClass c) {
        return ReferenceRowSemantics(
          label: rowLabel(c.name, <String?>[
            'decimal ${c.decimal}',
            c.notes,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 160,
                  child: Text(
                    c.name,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    c.decimal,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: Text(
                    c.notes,
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
}

/// The prominent voice-into-video pitfall callout — a §8.13 status-WARNING
/// surface: statusWarning 1px border + 12% tint fill, a leading warning glyph,
/// the trap stated as a title word, then the explanation. The word "Trap" + the
/// body text carry the meaning, so color is never the sole signal (SC 1.4.1),
/// and the border clears SC 1.4.11 (3:1 non-text) on surface0. The whole card
/// is one semantic node so AT reads the warning as a unit.
class _TrapCallout extends StatelessWidget {
  const _TrapCallout({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: 'Warning. $title. $body',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.statusWarning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.statusWarning, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: colors.statusWarning,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    title,
                    style: text.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              body,
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card surface wrapping a wide table: title (full-width, wraps) over a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align), with an optional full-width footnote beneath. Matches the
/// poe_reference_screen overflow-safe idiom.
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
