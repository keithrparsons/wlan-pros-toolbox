// Plan-Set Literacy - read-only field/trade reference (Field Reference set,
// 2026-07-05). Clones the Enclosure Ratings reference-screen pattern.
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/05-plan-set-literacy.md)
// as native layout, with Charta's sheet-number-anatomy plate embedded at the top
// via the established DarkRasterDiagramCard (always-dark surface in both themes,
// tap to pinch-zoom). Every fact the plate depicts is ALSO in the native text
// below it, so the image is decorative for screen readers and never the sole
// carrier of meaning (GL-003 §8.6.2 a11y rule).
//
// States (SOP-007 §5): pure read-only reference - no inputs, no computation, no
// network (GL-008 does not apply; nothing to fetch, shell out to, or fabricate).
//   - success  → the compile-time const copy always renders. The diagram card
//     appears only when its PNG is bundled (ReferenceImages.isBundled);
//     otherwise it is omitted and every card still reads end-to-end.
//   - loading / empty / error → not reachable; nothing is fetched or parsed.
//   - interactive → the plate's tap-to-zoom, the AppBar §8.16 copy action, and
//     the §8.16.1 help footer (each carries its own §8.3 focus ring).
//   - disabled → copy is always enabled (static content is always present).
//
// THEME: every chrome color comes from context.colors (dark §8 / light §8.20).
// The RCP anti-pattern is a warning band (statusWarning glyph + word, never
// color-only, §8.13); the defer footer is an info band (statusInfo).
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; sheet number and scales in DM Mono (AppMonoText.inlineCode).

import 'package:flutter/material.dart';

import '../../../data/plan_set_literacy_data.dart';
import '../../../data/reference_images.dart';
import '../../../data/reference_pdfs.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/reference_pdf_download.dart';
import '../../../widgets/tool_help_footer.dart';

class PlanSetLiteracyScreen extends StatelessWidget {
  const PlanSetLiteracyScreen({super.key});

  /// The plate's true aspect ratio (width / height). Master render is 3000 x
  /// 3278 (assets/reference/plan-set-literacy.png).
  static const double _diagramAspect = 3000 / 3278;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan-Set Literacy'),
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
        final bool hasDiagram =
            ReferenceImages.isBundled(kPlanSetLiteracyToolId);
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
                  if (hasDiagram) ...<Widget>[
                    DarkRasterDiagramCard(
                      assetPath:
                          ReferenceImages.pathFor(kPlanSetLiteracyToolId),
                      aspectRatio: _diagramAspect,
                      semanticLabel:
                          'Sheet-number anatomy diagram: discipline letter, '
                          'sheet-type digit, and sequence number',
                      caption: 'Decode a sheet number and find the RCP.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (ReferencePdfs.isBundled(kPlanSetLiteracyToolId)) ...<Widget>[
                    ReferencePdfDownloadCard(
                      assetPath: ReferencePdfs.pathFor(kPlanSetLiteracyToolId),
                      title: 'Plan-Set Literacy',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const _LeadCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _SheetNumberCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _RcpCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _PlanSetElementsCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _ScalesCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _WlanCaresCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _DeferBand(),
                  ToolHelpFooter(toolId: kPlanSetLiteracyToolId),
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
      ..writeln('Plan-Set Literacy')
      ..writeln()
      ..writeln(kPlanSetLead)
      ..writeln()
      ..writeln('Reading a sheet number')
      ..writeln(kSheetNumberIntro)
      ..writeln(kSheetNumberExample)
      ..writeln()
      ..writeln('Discipline designators: who owns the sheet')
      ..writeln(<String>['Letter', 'Discipline'].join(tab));
    for (final DisciplineDesignator d in kDisciplineDesignators) {
      b.writeln(<String>[d.letter, d.discipline].join(tab));
    }
    b
      ..writeln(kDisciplineNote)
      ..writeln(kTelecomDisciplineNote)
      ..writeln()
      ..writeln('Sheet-type digit: what kind of drawing')
      ..writeln(<String>['Digit', 'Drawing type'].join(tab));
    for (final SheetTypeDigit s in kSheetTypeDigits) {
      b.writeln(<String>[s.digit, s.meaning].join(tab));
    }
    b
      ..writeln(kSheetTypeNote)
      ..writeln()
      ..writeln('The Reflected Ceiling Plan is the AP sheet')
      ..writeln(kRcpIntro)
      ..writeln(kRcpWhyIntro);
    for (final String r in kRcpReasons) {
      b.writeln('- $r');
    }
    b
      ..writeln(kRcpAntiPattern)
      ..writeln()
      ..writeln('The rest of a plan set worth knowing');
    for (final String e in kPlanSetElements) {
      b.writeln('- $e');
    }
    b
      ..writeln()
      ..writeln('Scales')
      ..writeln(kScalesNote)
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kPlanSetWlanCares)
      ..writeln()
      ..writeln(kPlanSetDeferNote);
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

/// A muted one-line caption / footnote (tertiary).
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: t.bodySmall?.copyWith(color: colors.textTertiary),
    );
  }
}

/// A small bold subheading inside a card.
class _SubHeading extends StatelessWidget {
  const _SubHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: (t.bodyMedium ?? const TextStyle()).copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// A bulleted list of prose strings, each a real semantic line.
class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2, right: AppSpacing.sm),
                child: Icon(Icons.circle, size: 6, color: colors.textAccent),
              ),
              Expanded(
                child: Text(
                  items[i],
                  style: t.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A mono "code chip" (a discipline letter or a sheet-type digit) with a fixed
/// leading width so a column of rows aligns. Accent-tinted, DM Mono.
class _CodeChip extends StatelessWidget {
  const _CodeChip(this.code, {this.width = 44});

  final String code;
  final double width;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return SizedBox(
      width: width,
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

/// One key/value reference row: a leading [code] chip then a [label].
class _RefRow extends StatelessWidget {
  const _RefRow({required this.code, required this.label, this.chipWidth = 44});

  final String code;
  final String label;
  final double chipWidth;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '$code. $label',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _CodeChip(code, width: chipWidth),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: (t.bodyMedium ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertically-stacked list of [_RefRow]s with hairline dividers between them.
class _RefTable extends StatelessWidget {
  const _RefTable({required this.rows});

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

/// The worked sheet-number example on a subtle inset mono band.
class _ExampleBand extends StatelessWidget {
  const _ExampleBand(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Text(
        text,
        style: mono.inlineCode.copyWith(color: colors.textPrimary),
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
    return const _Card(child: _Body(kPlanSetLead));
  }
}

/// Reading a sheet number: intro + example + the two decode tables.
class _SheetNumberCard extends StatelessWidget {
  const _SheetNumberCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Reading a sheet number',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Body(kSheetNumberIntro),
          const SizedBox(height: AppSpacing.sm),
          const _ExampleBand(kSheetNumberExample),
          const SizedBox(height: AppSpacing.md),
          const _SubHeading('Discipline designators: who owns the sheet'),
          const SizedBox(height: AppSpacing.sm),
          _RefTable(
            rows: <Widget>[
              for (final DisciplineDesignator d in kDisciplineDesignators)
                _RefRow(code: d.letter, label: d.discipline),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Caption(kDisciplineNote),
          const SizedBox(height: AppSpacing.sm),
          const _Body(kTelecomDisciplineNote),
          const SizedBox(height: AppSpacing.md),
          const _SubHeading('Sheet-type digit: what kind of drawing'),
          const SizedBox(height: AppSpacing.sm),
          _RefTable(
            rows: <Widget>[
              for (final SheetTypeDigit s in kSheetTypeDigits)
                _RefRow(code: s.digit, label: s.meaning, chipWidth: 68),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Caption(kSheetTypeNote),
        ],
      ),
    );
  }
}

/// The Reflected Ceiling Plan is the AP sheet: intro + reasons + anti-pattern.
class _RcpCard extends StatelessWidget {
  const _RcpCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'The Reflected Ceiling Plan is the AP sheet',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Body(kRcpIntro),
          const SizedBox(height: AppSpacing.md),
          const _SubHeading(kRcpWhyIntro),
          const SizedBox(height: AppSpacing.sm),
          const _Bullets(kRcpReasons),
          const SizedBox(height: AppSpacing.md),
          const _WarningBand(kRcpAntiPattern),
        ],
      ),
    );
  }
}

/// The RCP anti-pattern as a warning band (icon + text, never color-only, §8.13).
class _WarningBand extends StatelessWidget {
  const _WarningBand(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.statusWarningFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.statusWarning, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: colors.statusWarning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: (t.bodySmall ?? const TextStyle()).copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rest of a plan set worth knowing.
class _PlanSetElementsCard extends StatelessWidget {
  const _PlanSetElementsCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      title: 'The rest of a plan set worth knowing',
      child: _Bullets(kPlanSetElements),
    );
  }
}

/// Scales.
class _ScalesCard extends StatelessWidget {
  const _ScalesCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(title: 'Scales', child: _Body(kScalesNote));
  }
}

/// Why a WLAN pro cares.
class _WlanCaresCard extends StatelessWidget {
  const _WlanCaresCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      title: 'Why a WLAN pro cares',
      child: _Body(kPlanSetWlanCares),
    );
  }
}

/// The defer footer as an info band (icon + text, §8.13).
class _DeferBand extends StatelessWidget {
  const _DeferBand();

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
              kPlanSetDeferNote,
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
