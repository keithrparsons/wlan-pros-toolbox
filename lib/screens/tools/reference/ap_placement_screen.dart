// AP Placement — a fully offline, read-only design-guidance reference. Mirrors
// the signal_thresholds_screen idiom: Scaffold + AppBar (toolbarHeight 64),
// SafeArea(top:false), LayoutBuilder isDesktop@720, Center + ConstrainedBox
// (calculatorMaxWidth), one SingleChildScrollView of cards built from semantic
// tokens.
//
// States (SOP-007 §5): a static bundled dataset — no fetch, so no loading /
// error / empty paths exist. The only state is the rendered guidance (success).
// No NetworkUnavailableView: works on every platform, no OS data, no I/O.
//
// Data is ported VERBATIM from the rf-tools-pwa `aplace` tool (data-tool=
// "aplace", the AP_RULES const in www/app.js). Five rule groups: requirements,
// AP location, cell sizing and overlap, channel planning, high-density venues.
// Guidance is reproduced, not invented.
//
// Text normalization (no values changed): the PWA source minus sign (U+2212)
// in dBm figures is rendered as an ASCII hyphen to match the sibling
// signal_thresholds screen ("-67 dBm"); en dashes in numeric ranges (e.g.
// "15-20%", "1-2 m") are kept as ASCII hyphens per the no-em-dash house rule.
// No em dashes appear in the source or here.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../concept_graphic_band.dart';

/// One AP_RULES group: a category heading and its ordered guidance lines.
/// Mirrors the PWA `{ cat, rules }` shape one-to-one.
class ApRuleGroup {
  const ApRuleGroup({required this.category, required this.rules});

  /// Group heading, e.g. "AP location".
  final String category;

  /// Ordered guidance lines under the heading, verbatim from the PWA.
  final List<String> rules;
}

class ApPlacementScreen extends StatelessWidget {
  const ApPlacementScreen({super.key});

  // ─── Dataset (public static for testing) ──────────────────────────────────
  // Verbatim from rf-tools-pwa www/app.js, `const AP_RULES` (data-tool=
  // "aplace"). Order, grouping, and wording preserved; only the minus-sign /
  // en-dash normalization noted in the header is applied. Never an AP-as-router.

  static const List<ApRuleGroup> kApRules = <ApRuleGroup>[
    ApRuleGroup(
      category: 'Start with requirements',
      rules: <String>[
        'Design for capacity first, coverage second in dense environments - '
            'offices, classrooms, convention halls.',
        'Define the use case before placing APs. VoIP requires -67 dBm '
            'everywhere; IoT may tolerate -75 dBm.',
        'Get a floor plan with wall types and materials before doing any '
            'placement math.',
      ],
    ),
    ApRuleGroup(
      category: 'AP location',
      rules: <String>[
        'Ceiling mount is preferred over wall mount for consistent '
            'omni-directional coverage patterns.',
        'Center the AP over the zone it serves - not at the room perimeter.',
        'Keep APs >= 1-2 m away from large metal surfaces, HVAC ducts, '
            'elevator shafts, and structural beams.',
        'Avoid placing APs directly above or beside microwave ovens or '
            'cordless phone base stations (2.4 GHz).',
        'Maintain clearance from fluorescent light ballasts - older magnetic '
            'ballasts can cause interference.',
      ],
    ),
    ApRuleGroup(
      category: 'Cell sizing and overlap',
      rules: <String>[
        'Design for >= 2 APs visible at -70 dBm or better everywhere in the '
            'coverage area.',
        'Target 15-20% cell overlap to enable roaming handoff without creating '
            'co-channel interference.',
        'Typical indoor omni coverage radius: 20-30 m open office, 10-15 m '
            'walled offices. Treat as a starting point only.',
        "Never design the coverage edge at the AP's maximum range - there is "
            'no roaming overlap and handoff fails.',
      ],
    ),
    ApRuleGroup(
      category: 'Channel planning',
      rules: <String>[
        'In 2.4 GHz, use only channels 1, 6, and 11 (US). Never use channels '
            '2, 3, 4, 7, 8, 9, or 10.',
        'Avoid co-channel APs within 30-50 m of each other in open space; '
            '20-30 m in walled environments.',
        'Prefer 5 GHz and 6 GHz for capacity. Reserve 2.4 GHz for legacy '
            'devices and extended range.',
        'Prefer DFS channels (UNII-2A/2C) where AP firmware is stable - '
            'typically fewer neighbor APs are on them.',
      ],
    ),
    ApRuleGroup(
      category: 'High-density venues',
      rules: <String>[
        'In auditoriums, stadiums, and lecture halls: reduce Tx power and add '
            'more APs rather than increasing power.',
        'Use directional patch or panel antennas to focus each AP on a defined '
            'seating zone.',
        'Plan for 20-30 clients per radio as a ceiling; actual limits depend '
            'on traffic type and AP model.',
        'Tri-radio APs may dedicate a radio to scanning or security - account '
            'for this in per-radio capacity math.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AP Placement'), toolbarHeight: 64),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
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
                  ConceptGraphicBand(
                    toolId: 'ap-placement',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('ap-placement'))
                    const SizedBox(height: AppSpacing.md),
                  _intro(context),
                  for (final ApRuleGroup group in kApRules) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    _RuleCard(group: group),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Honest framing — the PWA's own tool description, verbatim in intent.
  Widget _intro(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      'Field-tested rules for AP location, cell sizing, channel planning, and '
      'high-density deployments. Coverage radii and spacing are starting '
      'points; validate every design with a post-installation survey.',
      style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
    );
  }
}

/// One AP_RULES group rendered as a surface-1 card: the category heading over
/// a list of guidance lines, each marked with a lime bullet.
class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.group});

  final ApRuleGroup group;

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
        children: <Widget>[
          Text(
            group.category,
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final String rule in group.rules) _RuleLine(rule: rule),
        ],
      ),
    );
  }
}

/// One guidance line: a lime bullet glyph and the rule text. The bullet is
/// decorative (excluded from semantics); the text carries the meaning.
class _RuleLine extends StatelessWidget {
  const _RuleLine({required this.rule});

  final String rule;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Decorative bullet — the rule text beside it is the real signal.
          const ExcludeSemantics(
            child: Padding(
              padding: EdgeInsets.only(top: 7, right: AppSpacing.sm),
              child: SizedBox(
                width: 6,
                height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              rule,
              style: (text.bodyLarge ?? const TextStyle()).copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
