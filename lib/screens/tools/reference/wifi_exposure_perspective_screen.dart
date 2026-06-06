// How Strong Is Wi-Fi, Really? — a read-along Quick Reference screen that puts
// Wi-Fi RF exposure in perspective against everyday sunlight, using verified,
// stated numbers (content spec: Deliverables/2026-06-05-wifi-exposure-reference/
// content-spec.md; every figure traces to the Pax brief at 2026-06-05-wifi-vs-
// sun-exposure/brief.md). No inputs, no runtime computation — a static reference
// like Antenna Fundamentals / Optical Transceivers.
//
// STATES (SOP-007 §5): a static reference renders its success state only. There
// is no async data load (every figure is compile-time const copy), so there is
// no loading / error / empty / disabled path to handle — the screen is content,
// not a form. The one async element is the concept-graphic band, which degrades
// to nothing on its own (ToolAssets manifest gate) and is decorative.
//
// HONESTY (GL-005 / the verified brief): every on-screen number is stated as
// approximate and matches the spec's number-provenance table. The honest-note
// card states the non-ionizing mechanism plainly — this is a comparison of total
// energy and warmth, never of sunburn. No figure is invented or rounded beyond
// what the spec states.
//
// THEME: every color comes from `context.colors` (the AppColorScheme
// ThemeExtension) — no raw AppColors.*, no literal hex/px — so the screen renders
// correctly in both dark (§8) and light (§8.20). No new tokens introduced.
//
// §8.13 NON-VERDICT ACCENTS (sanctioned, paired with a worded label, never
// color-only):
//   * The two context cards (assumptions, safety-limit) carry a `statusInfo`
//     left accent — the token's own "'for reference' / non-verdict context"
//     role. Each is paired with its worded section title.
//   * The honest-note card carries a `statusWarning` (amber/bronze) left accent
//     + low-alpha tint — the editorial "HONEST NOTE" callout role, paired with
//     the worded `HONEST NOTE` eyebrow.
// Both are reinforced by a Semantics label so an AT user hears the role, never
// relying on hue. Vera confirms; if she reads either as decorative-status drift,
// the left accents drop to `borderStrong` neutral and the worded titles carry
// the grouping (the cards still read as sections via their headers).

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';

/// Stable catalog tool id — backs the route, the concept-graphic asset, the help
/// entry, and the tests. Permanent (never renamed even if the display title is).
const String kWifiExposurePerspectiveToolId = 'wifi-exposure-perspective';

/// One row of the energy-parity table: a time in sun and the equivalent time
/// inside the 10-AP ring. Pure value object — no behavior, just the two stated
/// strings the table renders. (Typed boundary per SOP-007 §4: no loose maps.)
class _ParityRow {
  const _ParityRow({required this.inSun, required this.inRing});

  /// Left column — time in midday sun (mono, primary).
  final String inSun;

  /// Right column — the same energy from the ring (sans, secondary).
  final String inRing;
}

/// One label/value row inside the assumptions card.
class _AssumptionRow {
  const _AssumptionRow({
    required this.key,
    required this.value,
    this.isResult = false,
  });

  final String key;
  final String value;

  /// The final "Result" row keys in the lime accent (§8.6 climax cue).
  final bool isResult;
}

/// One chip in the safety-limit card: a label above a mono value.
class _LimitChip {
  const _LimitChip({required this.label, required this.value});

  final String label;
  final String value;
}

class WifiExposurePerspectiveScreen extends StatelessWidget {
  const WifiExposurePerspectiveScreen({super.key});

  // ── content (verbatim from the content spec; figures from the verified brief) ──

  static const String _eyebrow =
      'WI-FI vs SUNLIGHT · RF EXPOSURE IN PERSPECTIVE';

  static const String _purpose =
      'A plain comparison of how much energy Wi-Fi puts into your body versus '
      'the everyday sun, using verified, stated numbers.';

  static const String _graphicCaption =
      'A person sits inside a ring of ten Wi-Fi access points while the midday '
      'sun pours energy from above.';

  static const String _heroEyebrow = 'THE SHORT VERSION';

  static const String _hero =
      'One hour of midday sun puts as much energy into your body as about 2.3 '
      'years sitting inside a ring of ten Wi-Fi access points 4 meters '
      '(13 feet) away.';

  static const List<_ParityRow> _parityRows = <_ParityRow>[
    _ParityRow(inSun: '10 seconds', inRing: 'about 2.3 days'),
    _ParityRow(inSun: '1 minute', inRing: 'about 14 days (two weeks)'),
    _ParityRow(inSun: '1 hour', inRing: 'about 2.3 years'),
  ];

  static const List<_AssumptionRow> _assumptionRows = <_AssumptionRow>[
    _AssumptionRow(
      key: '10 access points',
      value: 'each at 30 dBm (1 watt) EIRP, the US 2.4 GHz maximum',
    ),
    _AssumptionRow(
      key: '4 meters away',
      value: 'free-space spread, S = EIRP / (4πr²)',
    ),
    _AssumptionRow(
      key: 'Ring power density',
      value: '0.00497 W/m² per AP × 10 ≈ 0.05 W/m²',
    ),
    _AssumptionRow(
      key: 'Midday equatorial sun',
      value: '1,000 W/m², full spectrum (all radiation, not UV only)',
    ),
    _AssumptionRow(
      key: 'Result',
      value: 'the sun is about 20,000× stronger per square meter',
      isResult: true,
    ),
  ];

  static const String _limitBody =
      'The FCC (47 CFR 1.1310) and ICNIRP 2020 cap public RF exposure at '
      '10 W/m². The 10-AP ring at about 0.05 W/m² is roughly 200× '
      'below that limit. Measured real-world Wi-Fi runs far lower still.';

  static const List<_LimitChip> _limitChips = <_LimitChip>[
    _LimitChip(label: '10-AP ring', value: '~0.05 W/m²'),
    _LimitChip(label: 'Public limit', value: '10 W/m²'),
    _LimitChip(label: 'Headroom', value: '~200× below limit'),
  ];

  static const String _honestEyebrow = 'HONEST NOTE';

  static const String _honestTitle = 'An honest note on mechanism';

  static const String _honestBody =
      'Wi-Fi radio energy is non-ionizing. It can only gently warm tissue. It '
      'cannot cause the photochemical or DNA damage that sunburn does, at any '
      'Wi-Fi power level. So this is a comparison of total energy and warmth, '
      'never of sunburn. The UV in sunlight burns; Wi-Fi has no UV and no '
      'comparable mechanism.';

  static const String _sources =
      'Sources: FCC 47 CFR 1.1310 and OET-65; ICNIRP 2020 RF guidelines; '
      'ASTM G173 / NREL reference solar spectrum; WHO and IARC on non-ionizing '
      'RF (Group 2B) versus solar UV (Group 1); peer-reviewed Wi-Fi exposure '
      'surveys (PMC5927334, PMC8172712). Power density via S = EIRP / '
      '(4πr²), free space at 4 m, stated as approximate. Assumes 10 '
      'APs at 30 dBm (1 W) EIRP and 1,000 W/m² midday equatorial sun.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('How Strong Is Wi-Fi, Really?'),
        toolbarHeight: 64,
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
            constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
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
                  // §8.6.2 concept graphic — first child, own card. Degrades to
                  // nothing when the asset is absent. Decorative for AT.
                  ConceptGraphicBand(
                    toolId: kWifiExposurePerspectiveToolId,
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic(kWifiExposurePerspectiveToolId)) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    _Caption(text: _graphicCaption),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _Eyebrow(text: _eyebrow),
                  const SizedBox(height: AppSpacing.xs),
                  _Purpose(text: _purpose),
                  const SizedBox(height: AppSpacing.md),
                  const _HeroCard(eyebrow: _heroEyebrow, statement: _hero),
                  const SizedBox(height: AppSpacing.md),
                  _SectionHeading(label: 'Energy-parity table'),
                  const SizedBox(height: AppSpacing.xs),
                  const _ParityTable(rows: _parityRows),
                  const SizedBox(height: AppSpacing.md),
                  const _AssumptionsCard(rows: _assumptionRows),
                  const SizedBox(height: AppSpacing.md),
                  const _SafetyLimitCard(body: _limitBody, chips: _limitChips),
                  const SizedBox(height: AppSpacing.md),
                  const _HonestNoteCard(
                    eyebrow: _honestEyebrow,
                    title: _honestTitle,
                    body: _honestBody,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _Caption(text: _sources),
                  ToolHelpFooter(toolId: kWifiExposurePerspectiveToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The small all-caps eyebrow label above the purpose line — lime accent text,
/// 0.10em tracking (§2.2 eyebrow pattern).
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: (t.labelSmall ?? const TextStyle()).copyWith(
        color: colors.textAccent,
        letterSpacing: 1.3, // ~0.10em at 13px
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// The one-line purpose statement under the eyebrow.
class _Purpose extends StatelessWidget {
  const _Purpose({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: (t.bodyMedium ?? const TextStyle()).copyWith(
        color: colors.textSecondary,
      ),
    );
  }
}

/// A tertiary-text caption block (graphic caption + sources footnote). No card.
class _Caption extends StatelessWidget {
  const _Caption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: (t.bodySmall ?? const TextStyle()).copyWith(
        color: colors.textTertiary,
      ),
    );
  }
}

/// The hero card — the short version. A lime top accent band (6px dark / 8px
/// light per §8.20.3), then the lime eyebrow and the bold H3 statement.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.eyebrow, required this.statement});

  final String eyebrow;
  final String statement;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    // §8.20.3: lime as a filled AREA (the top band) is valid in both themes.
    // Light bumps the band for legibility.
    final double accentHeight = colors.isLight ? 8 : 6;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Lime top accent band — the §8.6 climax cue for the headline card.
          Container(height: accentHeight, color: colors.primary),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  eyebrow,
                  style: (t.labelSmall ?? const TextStyle()).copyWith(
                    color: colors.textAccent,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  statement,
                  style: (t.titleLarge ?? const TextStyle()).copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The energy-parity table: a two-column header + three rows. Left = time in sun
/// (DM Mono, primary); right = same energy from the ring (sans, secondary).
/// Alternating row tint (rows 2 and 4 of the rendered list, i.e. header + every
/// other body row) per the reference-table pattern.
class _ParityTable extends StatelessWidget {
  const _ParityTable({required this.rows});

  final List<_ParityRow> rows;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          const _ParityHeaderRow(),
          ...List<Widget>.generate(rows.length, (int i) {
            return _ParityBodyRow(
              row: rows[i],
              // Tint alternate body rows (the 1st and 3rd, 0-indexed even) for
              // the reference-table zebra rhythm.
              tinted: i.isEven,
              isLast: i == rows.length - 1,
            );
          }),
        ],
      ),
    );
  }
}

class _ParityHeaderRow extends StatelessWidget {
  const _ParityHeaderRow();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    TextStyle head() => (t.labelSmall ?? const TextStyle()).copyWith(
          color: colors.textTertiary,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w600,
        );
    return Semantics(
      header: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface2,
          border: Border(bottom: BorderSide(color: colors.border, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.rowPadding,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 5,
              child: Text('TIME IN MIDDAY SUN', style: head()),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 6,
              child: Text('SAME ENERGY FROM THE 10-AP RING', style: head()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParityBodyRow extends StatelessWidget {
  const _ParityBodyRow({
    required this.row,
    required this.tinted,
    required this.isLast,
  });

  final _ParityRow row;
  final bool tinted;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: tinted ? colors.surface2 : colors.surface1,
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.rowPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Text(
              row.inSun,
              style: (t.bodyMedium ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontFamily: 'DM Mono',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 6,
            child: Text(
              row.inRing,
              style: (t.bodyMedium ?? const TextStyle()).copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A card with a left status accent strip (drawn as a clipped left fill, not a
/// non-uniform Border, which cannot coexist with a borderRadius). The accent is
/// always paired with the worded section title + a Semantics label so the role
/// is announced, never color-only (§8.13). Used by the two info context cards
/// and the amber honest-note card.
class _AccentCard extends StatelessWidget {
  const _AccentCard({
    required this.accent,
    required this.semanticsLabel,
    required this.child,
    this.fill,
  });

  /// The left-strip accent color (statusInfo for context, statusWarning for the
  /// honest note).
  final Color accent;

  /// The non-visual role announced to AT (so meaning never rides on hue alone).
  final String semanticsLabel;

  /// Optional low-alpha background tint over surface1 (the honest-note band).
  final Color? fill;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    // Light bumps the strip wider for legibility (same rule as §8.20.3 accents).
    final double accentWidth = colors.isLight ? 4 : 3;
    return Semantics(
      label: semanticsLabel,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            // Optional tint band over the card body (honest note).
            Padding(
              padding: EdgeInsets.only(left: accentWidth),
              child: Container(
                color: fill,
                padding: const EdgeInsets.all(AppSpacing.sm),
                width: double.infinity,
                child: child,
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              child: Container(width: accentWidth, color: accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// The assumptions card — a `statusInfo` context accent, the section head, and
/// five label/value rows (the last keyed in the lime accent).
class _AssumptionsCard extends StatelessWidget {
  const _AssumptionsCard({required this.rows});

  final List<_AssumptionRow> rows;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return _AccentCard(
      accent: colors.statusInfo,
      semanticsLabel: 'For reference: the assumptions behind these numbers',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardHeading(label: 'The assumptions behind these numbers'),
          const SizedBox(height: AppSpacing.sm),
          ...List<Widget>.generate(rows.length, (int i) {
            final _AssumptionRow r = rows[i];
            return Padding(
              padding: EdgeInsets.only(
                top: i == 0 ? 0 : AppSpacing.xs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 4,
                    child: Text(
                      r.key,
                      style: (t.bodySmall ?? const TextStyle()).copyWith(
                        color: r.isResult ? colors.textAccent : colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 7,
                    child: Text(
                      r.value,
                      style: (t.bodySmall ?? const TextStyle()).copyWith(
                        color: r.isResult
                            ? colors.textAccent
                            : colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// The safety-limit context card — a `statusInfo` accent, the section head, a
/// body paragraph, then three label/value chips on a surface-2 fill.
class _SafetyLimitCard extends StatelessWidget {
  const _SafetyLimitCard({required this.body, required this.chips});

  final String body;
  final List<_LimitChip> chips;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return _AccentCard(
      accent: colors.statusInfo,
      semanticsLabel: 'For reference: where this sits against the safety limit',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardHeading(label: 'Where this sits against the safety limit'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: (t.bodyMedium ?? const TextStyle()).copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final _LimitChip c in chips) _LimitChipView(chip: c),
            ],
          ),
        ],
      ),
    );
  }
}

class _LimitChipView extends StatelessWidget {
  const _LimitChipView({required this.chip});

  final _LimitChip chip;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            chip.label.toUpperCase(),
            style: (t.labelSmall ?? const TextStyle()).copyWith(
              color: colors.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            chip.value,
            style: (t.bodyMedium ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              fontFamily: 'DM Mono',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The honest-note card — an amber (`statusWarning`) left accent over a low-alpha
/// amber tint band, the amber `HONEST NOTE` eyebrow, an 18px bold title, then the
/// mechanism note. The one cautionary editorial beat on the screen.
class _HonestNoteCard extends StatelessWidget {
  const _HonestNoteCard({
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  final String eyebrow;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    // §8.20.7-equivalent wash: the statusWarning hue at low alpha. Derived from
    // the resolved token so it tracks the theme (amber in dark, bronze in light)
    // rather than a literal hex.
    final Color tint = colors.statusWarning.withValues(alpha: 0.10);
    return _AccentCard(
      accent: colors.statusWarning,
      fill: tint,
      semanticsLabel: 'Honest note on mechanism',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            eyebrow,
            style: (t.labelSmall ?? const TextStyle()).copyWith(
              color: colors.statusWarning,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            title,
            style: (t.titleMedium ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: (t.bodyMedium ?? const TextStyle()).copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// A section heading with a short lime underbar accent — matches the established
/// reference-screen `_SectionHeading` (title + 38×3 lime bar).
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              style: (t.titleMedium ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            width: 38,
            height: 3,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// An in-card section heading (no underbar) marked as a header for AT — used by
/// the two context cards whose accent strip carries the lime cue instead.
class _CardHeading extends StatelessWidget {
  const _CardHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Text(
        label,
        style: (t.titleMedium ?? const TextStyle()).copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
