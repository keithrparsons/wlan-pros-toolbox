// Part 15 vs Part 97 over 2.4 / 5 GHz — the signature Wi-Fi-adjacent reference.
// The amateur allocations that overlap Wi-Fi (13 cm over 2.4 GHz, 5 cm over
// 5 GHz U-NII) mapped to the Wi-Fi grid, plus the rule-delta table: unlicensed
// + power-limited + encryption-OK Part 15 against licensed + higher-power +
// station-ID-every-10-min + no-encryption Part 97. AREDN / Broadband-Hamnet is
// the real-world example.
//
// DATA: lib/data/ham_reference_data.dart (kWifiHamOverlaps, kRuleDeltas,
// kAredNote, kPart97NineCmNote).
//
// States (SOP-007 sec 5): a read-only reference. success = the overlap + delta
// render; loading/error/empty are not reachable. Only the AppCopyAction is
// interactive.
//
// THEME: chrome from context.colors; frequency/channel identifiers in Roboto
// Mono (GL-003 sec 8.5). The Part 15 / Part 97 columns are always labeled in
// text (never distinguished by color alone, GL-003 sec 8.13). No new tokens; no
// em dash (GL-004).
//
// ICON: bespoke Tier-2 icon resolves at assets/tool-icons/part15-part97.svg
// when Charta ships it; falls back to the category glyph until then.

import 'package:flutter/material.dart';

import '../../../data/ham_reference_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_row_semantics.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kPart15Part97ToolId = 'part15-part97';

class Part15VsPart97Screen extends StatelessWidget {
  const Part15VsPart97Screen({super.key});

  /// §8.16 copy payload — the overlap table, the rule-delta table (both columns
  /// labeled in words so the clipboard carries the full comparison), and the
  /// AREDN + 9 cm notes.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Part 15 vs Part 97 over 2.4 / 5 GHz')
      ..writeln()
      ..writeln('Overlapping amateur allocations, mapped to the Wi-Fi grid')
      ..writeln(<String>[
        'Wi-Fi band',
        'Amateur band',
        'Overlap',
        'Wi-Fi channels inside',
      ].join(tab));
    for (final WifiHamOverlap o in kWifiHamOverlaps) {
      buf.writeln(<String>[
        o.wifiBand,
        o.hamBand,
        o.overlap,
        o.channelsInside,
      ].join(tab));
    }
    buf
      ..writeln()
      ..writeln('Rule-delta table')
      ..writeln(<String>['Dimension', 'Part 15', 'Part 97'].join(tab));
    for (final RuleDelta d in kRuleDeltas) {
      buf.writeln(<String>[d.dimension, d.part15, d.part97].join(tab));
    }
    buf
      ..writeln()
      ..writeln('AREDN: $kAredNote')
      ..writeln()
      ..writeln('9 cm note: $kPart97NineCmNote');
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Part 15 vs Part 97'),
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
                  _overlapCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _deltaCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _arednCard(context),
                  ToolHelpFooter(toolId: kPart15Part97ToolId),
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
        'Some amateur bands sit right on top of the Wi-Fi bands. The same '
        '802.11 silicon can run under Part 15 (unlicensed Wi-Fi) or Part 97 '
        '(licensed amateur). The rules are very different, and that difference '
        'is the whole point of amateur mesh networks like AREDN.',
        style: text.bodyMedium?.copyWith(color: colors.textPrimary),
      ),
    );
  }

  Widget _overlapCard(BuildContext context) {
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
            'Overlapping allocations, on the Wi-Fi grid',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...kWifiHamOverlaps.asMap().entries.expand(
            (MapEntry<int, WifiHamOverlap> entry) {
              final WifiHamOverlap o = entry.value;
              return <Widget>[
                if (entry.key > 0)
                  Divider(color: colors.border, height: AppSpacing.md),
                ReferenceRowSemantics(
                  merge: false,
                  label: rowLabel(o.wifiBand, <String?>[
                    o.hamBand,
                    o.overlap,
                    o.channelsInside,
                  ]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(o.wifiBand, style: mono.robotoMono),
                      const SizedBox(height: 2),
                      Text(
                        o.hamBand,
                        style: mono.robotoMono.copyWith(
                          color: colors.textAccent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        o.overlap,
                        style: text.bodyMedium
                            ?.copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        o.channelsInside,
                        style: text.labelMedium
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

  Widget _deltaCard(BuildContext context) {
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
            'The rules, side by side',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...kRuleDeltas.asMap().entries.expand(
            (MapEntry<int, RuleDelta> entry) {
              return <Widget>[
                if (entry.key > 0)
                  Divider(color: colors.border, height: AppSpacing.md),
                _DeltaRow(delta: entry.value),
              ];
            },
          ),
        ],
      ),
    );
  }

  Widget _arednCard(BuildContext context) {
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
            'Real-world: AREDN',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kAredNote,
            style: text.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            kPart97NineCmNote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// One rule-delta dimension: the dimension label, then the Part 15 block and
/// the Part 97 block stacked (mobile-friendly). Each column is labeled in text,
/// never distinguished by color alone (GL-003 sec 8.13).
class _DeltaRow extends StatelessWidget {
  const _DeltaRow({required this.delta});

  final RuleDelta delta;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    Widget side(String tag, String body, Color tagColor) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                tag,
                style: text.labelSmall?.copyWith(
                  color: tagColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                body,
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        );
    return ReferenceRowSemantics(
      merge: false,
      label: rowLabel(delta.dimension, <String?>[
        'Part 15: ${delta.part15}',
        'Part 97: ${delta.part97}',
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              delta.dimension,
              style: text.bodyLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            // Part 15 in the neutral info tone label, Part 97 in the lime accent
            // label — but both ALWAYS carry their "Part 15" / "Part 97" word.
            side('PART 15', delta.part15, colors.textSecondary),
            side('PART 97', delta.part97, colors.textAccent),
          ],
        ),
      ),
    );
  }
}
