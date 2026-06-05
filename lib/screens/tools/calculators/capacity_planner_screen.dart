// Capacity Planner — informational disclaimer (placeholder), not a calculator.
//
// The tool that used to live here squeezed real Wi-Fi capacity planning into a
// handful of input boxes and returned a confident AP count. Keith retired that
// math: a single formula can't honor the variables that actually drive capacity
// (applications and their airtime cost, client mix and roaming, AP/antenna
// choice, channel reuse and CCI, band steering, airtime fairness, QoS, and how
// people move through the space). A confidently-wrong number is worse than no
// number — see [[feedback_truthfulness_audit]] / GL-005.
//
// So this screen is now a read-only honesty statement. The tile and the
// `/tools/capacity-planner` route are kept (the tile still resolves where users
// expect), the class name `CapacityPlannerScreen` is kept, and the AppBar title
// stays "Capacity Planner". No inputs, no math, no copyable result.
//
// Copy is verbatim from Keith's approved draft — do not reword.
//
// Tokens: GL-003 §8.1/§8.20.1 surface stack, §4 spacing, §8.5/§8.20.3 type,
// read entirely through `context.colors` so the screen is correct in BOTH Light
// and Dark. Matches the AboutScreen `_Section` register (titled surface1 card,
// `Semantics(header: true)` heading, bodyLarge paragraphs).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/centered_content.dart';
import '../../../widgets/tool_help_footer.dart';

/// Verbatim approved copy. Kept as named constants so the rendered prose and any
/// future copy reuse stay in one place — never edit these strings.
const String _kHeading =
    'Capacity planning is a design problem, not a calculation.';

const List<String> _kParagraphs = <String>[
  'Real Wi-Fi capacity depends on too many moving parts for any single '
      'formula: the actual applications in use and their airtime cost, client '
      'device capabilities and how they roam, AP and antenna selection, '
      'channel reuse and co-channel interference, band steering, airtime '
      'fairness, QoS, and how people actually move through and use the space. '
      'Change any one of those and the answer changes.',
  'A tool that squeezed all of that into a few input boxes would hand you a '
      'confident number that\'s wrong, which is worse than no number at all.',
  'If you need a capacity plan you can trust, bring in a Wi-Fi professional '
      'experienced in your kind of environment. A real plan comes from '
      'measuring and modeling your specific space and usage, not from a '
      'one-size-fits-all estimate.',
];

class CapacityPlannerScreen extends StatelessWidget {
  const CapacityPlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capacity Planner'),
        toolbarHeight: 64,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double edge = constraints.maxWidth >= 720
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            return CenteredContent(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  edge,
                  AppSpacing.sm,
                  edge,
                  edge + AppSpacing.sm,
                ),
                children: <Widget>[
                  const _DisclaimerCard(),
                  ToolHelpFooter(toolId: 'capacity-planner'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The single informational card: a prominent heading followed by the three
/// approved body paragraphs. Same titled-surface1 register as the AboutScreen
/// sections; every color resolves through `context.colors` for Light/Dark.
class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        // Decorative hairline — this card is not an interactive component, so
        // §8.1 decorative `border` is correct (not borderStrong). §8.20.3-B
        // bumps the light-mode card border to 1.5px so white-on-gray reads.
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Prominent heading. H2 (screen-level emphasis, larger than the H3
          // About-section heads) so it reads as the page's statement. Marked as
          // a heading so a screen reader can land on it (WCAG 2.2 SC 1.3.1).
          // §8.20.3-A bumps section headings to 700 in light.
          Semantics(
            header: true,
            child: Text(
              _kHeading,
              style: text.headlineMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: colors.isLight ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (int i = 0; i < _kParagraphs.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            Text(
              _kParagraphs[i],
              style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
