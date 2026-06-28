// US Amateur Band Plan — a read-only, grouped, searchable reference of the
// corrected US amateur radio band plan (HF / VHF / UHF / SHF).
//
// DATA: lib/data/ham_reference_data.dart (kHamBandPlan, kHam60mChannels), built
// from FCC Part 97 per Deliverables/2026-06-28-ham-radio-toolbox-research/
// build-spec.md. The corrected values live here: 1500 W PEP on 80/40/15/10 m,
// 30 m = 200 W, 60 m = 4 channels + the 9.15 W ERP segment, 2200/630 m IN,
// 9 cm OUT (footnoted), and no baud column.
//
// States (SOP-007 sec 5) for a read-only reference:
//   - success     -> matching band cards render, grouped by region.
//   - empty       -> a search query that matches no band: an honest "no match"
//                    card, never a fabricated row.
//   - loading     -> not reachable; the dataset is a compile-time const.
//   - error       -> not reachable; nothing parses at runtime.
//   - interactive -> the search field filters the list as the user types.
//
// THEME: chrome from context.colors (sec 8 dark / sec 8.20 light); frequencies
// and power values in Roboto Mono (identifier face, GL-003 sec 8.5); no calc
// numerics so no DM Mono. AppCopyAction copies the full plan as TSV. No new
// tokens; no em dash (GL-004).
//
// ICON: bespoke Tier-2 icon resolves by catalog id at
// assets/tool-icons/ham-band-plan.svg when Charta ships it; until then the tile
// falls back to the category glyph (graceful degradation).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/ham_reference_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/tool_help_footer.dart';
import '../labeled_field.dart';
import 'reference_row_semantics.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kHamBandPlanToolId = 'ham-band-plan';

class HamBandPlanScreen extends StatefulWidget {
  const HamBandPlanScreen({super.key});

  @override
  State<HamBandPlanScreen> createState() => _HamBandPlanScreenState();
}

class _HamBandPlanScreenState extends State<HamBandPlanScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  /// Case-insensitive substring match across the band name, frequency range,
  /// and mode text. An empty query matches everything.
  bool _matches(HamBand b, String q) {
    if (q.isEmpty) return true;
    final String hay = <String?>[
      b.band,
      b.freqRange,
      b.modes,
      b.tech,
      b.general,
      b.extra,
      b.allClasses,
      b.power,
    ].whereType<String>().join(' ').toLowerCase();
    return hay.contains(q);
  }

  List<HamBand> get _filtered {
    final String q = _query.trim().toLowerCase();
    return kHamBandPlan.where((HamBand b) => _matches(b, q)).toList();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final int n = _filtered.length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching bands' : '$n matching band${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  /// §8.16 copy payload — the full band plan as TSV, plus the 60 m channel
  /// detail and the power/data/sunset notes. Static data, so always enabled.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('US Amateur Band Plan (Technician / General / Amateur Extra)')
      ..writeln(
        <String>[
          'Band',
          'Frequency',
          'Technician',
          'General',
          'Amateur Extra',
          'Max power',
          'Notes',
        ].join(tab),
      );
    for (final HamBand b in kHamBandPlan) {
      final String t = b.isAllClasses
          ? 'All license classes'
          : (b.tech ?? 'No Technician privileges');
      final String g = b.isAllClasses ? (b.allClasses ?? '') : (b.general ?? '');
      final String e = b.isAllClasses ? (b.allClasses ?? '') : (b.extra ?? '');
      buf.writeln(
        <String>[
          b.band,
          b.freqRange,
          t,
          g,
          e,
          b.power,
          b.modes ?? '',
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('60 m channel detail (canonical = center; dial = USB 1.5 kHz '
          'below center)')
      ..writeln(<String>['Channel', 'Center', 'Dial', 'Power', 'Notes']
          .join(tab));
    for (final Ham60mChannel c in kHam60mChannels) {
      buf.writeln(
        <String>[c.label, c.center, c.dial, c.power, c.notes ?? ''].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Power: $kHamPowerSummary')
      ..writeln('HF data: $kHamHfDataRule')
      ..writeln('9 cm: $kHam9cmSunsetNote');
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('US Amateur Band Plan'),
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
                  _searchCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  ..._sections(context),
                  const SizedBox(height: AppSpacing.sm),
                  _channel60mCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _notesCard(context),
                  ToolHelpFooter(toolId: kHamBandPlanToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _searchCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LabeledField(
        label: 'Search bands',
        hint: 'band name or frequency',
        semanticLabel: 'Search bands by name or frequency',
        field: TextField(
          controller: _queryCtrl,
          focusNode: _queryFocus,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          cursorColor: colors.textAccent,
          decoration: const InputDecoration(hintText: 'e.g. 20 m or 14.2'),
        ),
      ),
    );
  }

  /// One SectionHeader + the matching band cards per region, in HF/VHF/UHF/SHF
  /// order. Empty regions are dropped. When the whole filter is empty, a single
  /// honest "no match" card is shown.
  List<Widget> _sections(BuildContext context) {
    final List<HamBand> filtered = _filtered;
    if (filtered.isEmpty) {
      return <Widget>[
        _MessageCard(
          icon: Icons.search_off,
          title: 'No match',
          body: 'No band matches "${_query.trim()}".',
        ),
      ];
    }
    final List<Widget> out = <Widget>[];
    for (final HamRegion region in HamRegion.values) {
      final List<HamBand> inRegion =
          filtered.where((HamBand b) => b.region == region).toList();
      if (inRegion.isEmpty) continue;
      out.add(SectionHeader(title: region.label, count: inRegion.length));
      for (final HamBand b in inRegion) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: _BandCard(band: b),
        ));
      }
    }
    return out;
  }

  Widget _channel60mCard(BuildContext context) {
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
            '60 m channel detail',
            style: text.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'The FCC references 60 m by channel center; operators tune USB '
            '1.5 kHz below center (the dial frequency).',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...kHam60mChannels.asMap().entries.expand(
            (MapEntry<int, Ham60mChannel> entry) {
              final Ham60mChannel c = entry.value;
              return <Widget>[
                if (entry.key > 0)
                  Divider(color: colors.border, height: AppSpacing.sm),
                ReferenceRowSemantics(
                  label: rowLabel(c.label, <String?>[
                    'center ${c.center}',
                    c.dial == 'n/a' ? null : 'dial ${c.dial}',
                    c.power,
                    c.notes,
                  ]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                              width: 88,
                              child: Text(
                                c.label,
                                style: text.labelMedium?.copyWith(
                                  color: colors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(c.center, style: mono.robotoMono),
                                  if (c.dial != 'n/a')
                                    Text(
                                      'dial ${c.dial}',
                                      style: mono.robotoMono.copyWith(
                                        color: colors.textTertiary,
                                        fontSize: AppTextSize.caption,
                                      ),
                                    ),
                                  Text(
                                    c.power,
                                    style: mono.robotoMono.copyWith(
                                      color: colors.textAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (c.notes != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              c.notes!,
                              style: text.labelSmall
                                  ?.copyWith(color: colors.textTertiary),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

  Widget _notesCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    Widget note(String label, String body) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: text.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
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
          note('Power limits', kHamPowerSummary),
          note('HF data', kHamHfDataRule),
          note('9 cm (sunset)', kHam9cmSunsetNote),
          Text(
            'US (FCC) Part 97. Novice and Advanced classes are closed to new '
            'applicants and are omitted. Verify the current rules before '
            'operating.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// One band's card: a header (band name + frequency + power badge) and the
/// per-class privilege rows (or a single all-classes line).
class _BandCard extends StatelessWidget {
  const _BandCard({required this.band});

  final HamBand band;

  @override
  Widget build(BuildContext context) {
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
          // Header: band name (accent), frequency (mono), power.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      band.band,
                      style: text.titleLarge?.copyWith(
                        color: colors.textAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      band.freqRange,
                      style: mono.robotoMono.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  band.power,
                  textAlign: TextAlign.right,
                  style: mono.robotoMono.copyWith(
                    fontSize: AppTextSize.caption,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Divider(color: colors.border, height: AppSpacing.sm),
          if (band.isAllClasses)
            _PrivilegeRow(
              label: 'All license classes',
              value: band.allClasses!,
            )
          else ...<Widget>[
            _PrivilegeRow(
              label: 'Technician',
              value: band.tech ?? 'No privileges on this band',
              muted: band.tech == null,
            ),
            _PrivilegeRow(label: 'General', value: band.general ?? ''),
            _PrivilegeRow(label: 'Amateur Extra', value: band.extra ?? ''),
          ],
          if (band.modes != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              band.modes!,
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One license-class privilege line: the class label and its privilege text.
class _PrivilegeRow extends StatelessWidget {
  const _PrivilegeRow({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return ReferenceRowSemantics(
      label: rowLabel(label, <String?>[value]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 104,
              child: Text(
                label,
                style: text.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                value,
                style: text.bodyMedium?.copyWith(
                  color: muted ? colors.textTertiary : colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Honest empty / message card (shared shape with the other reference screens).
class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.labelMedium?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
