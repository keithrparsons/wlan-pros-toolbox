// macOS Menu-Bar Wi-Fi Tools — a data-driven reference for the RF data a Wi-Fi
// pro can pull from a stock Mac without a third-party app. This screen OWNS the
// per-field "what each RF value means" tables; the Apple Wi-Fi Tips screen links
// here for that detail (per the SSOT note in the staged DATA file).
//
// Four sections:
//   The four built-in paths (overview table).
//   A. Option-click Wi-Fi menu fields (what each value means).
//   B. sudo wdutil info — the WIFI block, with the sudo-masks-RF callout.
//   C. Wireless Diagnostics app (Window-menu tools).
//   D. Shortcuts "Get Network Details".
//
// Source of truth: lib/data/macos_menubar_wifi_data.dart (compile-time const,
// distilled from Apple docs + corroborating sources, verified live 2026-06-12).
//
// States (SOP-007 §5):
//  - success → the sections always render (const data; no fetch path).
//  - empty / loading / error → not applicable: reference text, never executed,
//    nothing fetched (GL-008 does not apply).
//  - interactive → the AppBar §8.16 copy action (keyboard-focusable via the
//    global §8.3 icon-button focus theme).
//  - disabled → copy is always enabled (const content always present).
//
// HONESTY (GL-005, load-bearing): the wdutil sudo-masks-RF callout and the
// "airport is gone" standing decision are carried as real on-screen notes.
//
// THEME: every color comes from context.colors so the screen renders correctly
// in dark (§8) and light (§8.20). No new tokens introduced.
//
// Glyph note: ASCII hyphen-minus only; no em dash. "Wi-Fi" / "802.11" casing.

import 'package:flutter/material.dart';

import '../../../data/macos_menubar_wifi_data.dart';
import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kMacosMenubarWifiToolId = 'macos-menubar-wifi';

class MacosMenubarWifiScreen extends StatelessWidget {
  const MacosMenubarWifiScreen({super.key});

  /// §8.16 plain-text payload — every path, field, and note in order so nothing
  /// on-screen survives only as layout.
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('macOS Menu-Bar Wi-Fi Tools')
      ..writeln()
      ..writeln(kMenuBarIntro)
      ..writeln()
      ..writeln('The four built-in paths')
      ..writeln(<String>['Path', 'What', 'Detail', 'Needs sudo?'].join(tab));
    for (final MenuBarPath p in kMenuBarPaths) {
      b.writeln(<String>[p.path, p.what, p.detail, p.needsSudo].join(tab));
    }
    b
      ..writeln()
      ..writeln('A. Option-click Wi-Fi menu fields')
      ..writeln(kMenuBarOptionClickIntro);
    for (final RfField f in kMenuBarOptionClickFields) {
      b.writeln('  ${f.field}: ${f.meaning}'
          '${f.proNote != null ? ' (${f.proNote})' : ''}');
    }
    b
      ..writeln(kMenuBarOptionClickNote)
      ..writeln()
      ..writeln('B. sudo wdutil info (the WIFI block)')
      ..writeln(kMenuBarWdutilIntro)
      ..writeln(kMenuBarSudoCallout);
    for (final RfField f in kMenuBarWdutilFields) {
      b.writeln('  ${f.field}: ${f.meaning}');
    }
    b
      ..writeln(kMenuBarWdutilNote)
      ..writeln(kMenuBarAirportGone)
      ..writeln()
      ..writeln('C. Wireless Diagnostics app (Window menu)')
      ..writeln(kMenuBarDiagIntro);
    for (final WdUtility u in kMenuBarDiagUtilities) {
      b.writeln('  ${u.name}: ${u.what}');
    }
    b
      ..writeln(kMenuBarDiagNote)
      ..writeln()
      ..writeln('D. Shortcuts "Get Network Details"')
      ..writeln(kMenuBarShortcutsBody);
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('macOS Menu-Bar Wi-Fi'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _copyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
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
                    toolId: kMacosMenubarWifiToolId,
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic(kMacosMenubarWifiToolId))
                    const SizedBox(height: AppSpacing.md),
                  _IntroCard(),
                  const SizedBox(height: AppSpacing.md),
                  // The four built-in paths overview.
                  _SectionCard(
                    label: 'The four built-in paths',
                    intro: '',
                    children: <Widget>[
                      for (final MenuBarPath p in kMenuBarPaths)
                        _PathRow(path: p),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // A. Option-click fields.
                  _SectionCard(
                    label: 'A. Option-click Wi-Fi menu fields',
                    intro: kMenuBarOptionClickIntro,
                    children: <Widget>[
                      for (final RfField f in kMenuBarOptionClickFields)
                        _FieldRow(field: f),
                      _CaveatLine(
                        icon: Icons.info_outline,
                        text: kMenuBarOptionClickNote,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // B. wdutil WIFI block + sudo callout.
                  _SectionCard(
                    label: 'B. sudo wdutil info (the WIFI block)',
                    intro: kMenuBarWdutilIntro,
                    children: <Widget>[
                      _SudoCallout(text: kMenuBarSudoCallout),
                      const SizedBox(height: AppSpacing.xs),
                      for (final RfField f in kMenuBarWdutilFields)
                        _FieldRow(field: f),
                      _CaveatLine(
                        icon: Icons.info_outline,
                        text: kMenuBarWdutilNote,
                      ),
                      _CaveatLine(
                        icon: Icons.history_toggle_off,
                        text: kMenuBarAirportGone,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // C. Wireless Diagnostics app.
                  _SectionCard(
                    label: 'C. Wireless Diagnostics app (Window menu)',
                    intro: kMenuBarDiagIntro,
                    children: <Widget>[
                      for (final WdUtility u in kMenuBarDiagUtilities)
                        _LabeledRow(label: u.name, value: u.what),
                      _CaveatLine(
                        icon: Icons.save_outlined,
                        text: kMenuBarDiagNote,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // D. Shortcuts.
                  _SectionCard(
                    label: 'D. Shortcuts "Get Network Details"',
                    intro: kMenuBarShortcutsBody,
                    children: const <Widget>[],
                  ),
                  ToolHelpFooter(toolId: kMacosMenubarWifiToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The intro band.
class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        kMenuBarIntro,
        style: (t.bodyMedium ?? const TextStyle())
            .copyWith(color: colors.textSecondary),
      ),
    );
  }
}

/// One section: a heading, an optional intro line, then its body rows.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.label,
    required this.intro,
    required this.children,
  });

  final String label;
  final String intro;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
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
            label,
            style: (t.titleMedium ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (intro.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              intro,
              style: (t.bodySmall ?? const TextStyle())
                  .copyWith(color: colors.textSecondary),
            ),
          ],
          if (children.isNotEmpty) const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

/// One built-in-path row: the path name (lime accent) + what / detail / sudo.
class _PathRow extends StatelessWidget {
  const _PathRow({required this.path});

  final MenuBarPath path;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          '${path.path}. ${path.what}. ${path.detail}. Needs sudo: ${path.needsSudo}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              path.path,
              style: mono.inlineCode.copyWith(
                color: colors.textAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${path.what}. ${path.detail}.',
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            Text(
              'Needs sudo: ${path.needsSudo}',
              style: t.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// One RF-field row: the field name + meaning, and an optional "why a pro cares"
/// note.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});

  final RfField field;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${field.field}. ${field.meaning}.'
          '${field.proNote != null ? ' ${field.proNote}' : ''}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            RichText(
              text: TextSpan(
                style: t.bodySmall?.copyWith(color: colors.textSecondary),
                children: <InlineSpan>[
                  TextSpan(
                    text: '${field.field}  ',
                    style: (t.labelMedium ?? const TextStyle()).copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: field.meaning),
                ],
              ),
            ),
            if (field.proNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  field.proNote!,
                  style: t.labelSmall?.copyWith(color: colors.textTertiary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// An inline "Label: value" row (Window-menu utilities).
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$label. $value',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: RichText(
          text: TextSpan(
            style: t.bodySmall?.copyWith(color: colors.textSecondary),
            children: <InlineSpan>[
              TextSpan(
                text: '$label  ',
                style: (t.labelMedium ?? const TextStyle()).copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sudo-masks-RF callout — an info-toned band, paired with a glyph and full
/// text (never color-only, §8.13).
class _SudoCallout extends StatelessWidget {
  const _SudoCallout({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.isLight
              ? colors.statusInfoFill
              : colors.statusInfo.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border(
            left: BorderSide(color: colors.statusInfo, width: 6),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.rowPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.lock_outline, size: 16, color: colors.statusInfo),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                text,
                style: t.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A caveat / note line: a small leading glyph + tertiary text.
class _CaveatLine extends StatelessWidget {
  const _CaveatLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: t.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
