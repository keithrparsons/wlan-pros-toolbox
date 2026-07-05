// Structured Cabling Standards - read-only field/trade reference (Field & Trade
// Reference set, 2026-07-05). Clones the Plan-Set Literacy / Site Access
// reference-screen pattern, but text-reference only: no DarkRasterDiagramCard
// (a decoder plate is optional here and can be added later, like many existing
// text-only reference screens).
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/08-structured-
// cabling.md) as native layout.
//
// States (SOP-007 §5): pure read-only reference - no inputs, no computation, no
// network (GL-008 does not apply; nothing to fetch, shell out to, or fabricate).
//   - success  → the compile-time const copy always renders.
//   - loading / empty / error → not reachable; nothing is fetched or parsed.
//   - interactive → the AppBar §8.16 copy action and the §8.16.1 help footer
//     (each carries its own §8.3 focus ring).
//   - disabled → copy is always enabled (static content is always present).
//
// THEME: every chrome color comes from context.colors (dark §8 / light §8.20).
// The defer footer is an info band (statusInfo glyph + word, never color-only,
// §8.13).
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; TIA standard numbers and cable categories in DM Mono
// (AppMonoText.inlineCode).

import 'package:flutter/material.dart';

import '../../../data/structured_cabling_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';

class StructuredCablingScreen extends StatelessWidget {
  const StructuredCablingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Structured Cabling'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _copyText)],
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
                children: const <Widget>[
                  _LeadCard(),
                  SizedBox(height: AppSpacing.md),
                  _TiaCard(),
                  SizedBox(height: AppSpacing.md),
                  _ChannelCard(),
                  SizedBox(height: AppSpacing.md),
                  _CategoriesCard(),
                  SizedBox(height: AppSpacing.md),
                  _TopologyCard(),
                  SizedBox(height: AppSpacing.md),
                  _BicsiCard(),
                  SizedBox(height: AppSpacing.md),
                  _WlanCaresCard(),
                  SizedBox(height: AppSpacing.md),
                  _DeferBand(),
                  ToolHelpFooter(toolId: kStructuredCablingToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// §8.16 plain-text payload - the full reference as tab-separated sections.
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Structured Cabling')
      ..writeln()
      ..writeln(kStructuredCablingLead)
      ..writeln()
      ..writeln('The TIA family');
    for (final TiaStandard s in kTiaStandards) {
      b.writeln(<String>[s.number, s.description].join(tab));
    }
    b
      ..writeln()
      ..writeln('The 90 plus 10 meter channel')
      ..writeln(kChannelIntro)
      ..writeln(kChannelApReality)
      ..writeln()
      ..writeln('Cable categories')
      ..writeln(<String>['Category', 'Practical reach'].join(tab));
    for (final CableCategory c in kCableCategories) {
      b.writeln(<String>[c.category, c.reach].join(tab));
    }
    b
      ..writeln(kPinoutNote)
      ..writeln()
      ..writeln('Topology and rooms')
      ..writeln(kTopologyNote)
      ..writeln()
      ..writeln('BICSI')
      ..writeln(kBicsiNote)
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kStructuredCablingWlanCares)
      ..writeln()
      ..writeln(kStructuredCablingDeferNote);
    return b.toString().trimRight();
  }
}

// ─────────────────────────────── shared card shell ──────────────────────────

/// Surface-1 card with an optional section title (labelMedium, tracked).
class _Card extends StatelessWidget {
  const _Card({this.title, required this.child});

  final String? title;
  final Widget child;

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
          if (title != null) ...<Widget>[
            Text(
              title!,
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          child,
        ],
      ),
    );
  }
}

/// A body paragraph in the standard secondary color.
class _Body extends StatelessWidget {
  const _Body(this.text);

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

/// A mono designator (a cable category) as a fixed-width accent chip.
class _CodeChip extends StatelessWidget {
  const _CodeChip(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return SizedBox(
      width: 72,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xxs,
          horizontal: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colors.border, width: 1),
        ),
        child: Text(
          code,
          textAlign: TextAlign.center,
          style: mono.inlineCode.copyWith(
            color: colors.textAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// One category row: a leading mono chip then the practical-reach label.
class _RefRow extends StatelessWidget {
  const _RefRow({required this.code, required this.label});

  final String code;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '$code. $label',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CodeChip(code),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: (t.bodyMedium ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertically-stacked list of rows with hairline dividers between them.
class _DividedList extends StatelessWidget {
  const _DividedList({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) Divider(color: colors.border, height: AppSpacing.md),
          rows[i],
        ],
      ],
    );
  }
}

/// The defer footer as an info band (icon + text, §8.13).
class _InfoBand extends StatelessWidget {
  const _InfoBand(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.statusInfoFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.statusInfo, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 20, color: colors.statusInfo),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────── section cards ──────────────────────────────

/// The italic lead paragraph.
class _LeadCard extends StatelessWidget {
  const _LeadCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(child: _Body(kStructuredCablingLead));
  }
}

/// The TIA family: each standard number (mono) with its coverage below.
class _TiaCard extends StatelessWidget {
  const _TiaCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'The TIA family',
      child: _DividedList(
        rows: <Widget>[
          for (final TiaStandard s in kTiaStandards) _TiaRowView(standard: s),
        ],
      ),
    );
  }
}

/// One TIA standard: the number as a mono heading, the coverage as body below.
class _TiaRowView extends StatelessWidget {
  const _TiaRowView({required this.standard});

  final TiaStandard standard;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      container: true,
      label: '${standard.number}. ${standard.description}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            standard.number,
            style: mono.inlineCode.copyWith(
              color: colors.textAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            standard.description,
            style: t.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The 90 plus 10 meter channel: the rule and the AP-cable-run reality check.
class _ChannelCard extends StatelessWidget {
  const _ChannelCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'The 90 plus 10 meter channel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          _Body(kChannelIntro),
          SizedBox(height: AppSpacing.sm),
          _Body(kChannelApReality),
        ],
      ),
    );
  }
}

/// Cable categories: category chip + practical reach, then the pin-out note.
class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Cable categories',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DividedList(
            rows: <Widget>[
              for (final CableCategory c in kCableCategories)
                _RefRow(code: c.category, label: c.reach),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _Body(kPinoutNote),
        ],
      ),
    );
  }
}

/// Topology and rooms.
class _TopologyCard extends StatelessWidget {
  const _TopologyCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      title: 'Topology and rooms',
      child: _Body(kTopologyNote),
    );
  }
}

/// BICSI.
class _BicsiCard extends StatelessWidget {
  const _BicsiCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(title: 'BICSI', child: _Body(kBicsiNote));
  }
}

/// Why a WLAN pro cares.
class _WlanCaresCard extends StatelessWidget {
  const _WlanCaresCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      title: 'Why a WLAN pro cares',
      child: _Body(kStructuredCablingWlanCares),
    );
  }
}

/// The defer footer as an info band.
class _DeferBand extends StatelessWidget {
  const _DeferBand();

  @override
  Widget build(BuildContext context) {
    return const _InfoBand(kStructuredCablingDeferNote);
  }
}
