// Keyboard Shortcuts — a fully data-driven, read-only reference (Tier-1, Pass 2b
// 2026-06-12). Six panels built from lib/data/keyboard_shortcuts_data.dart:
//   A. macOS system shortcuts        D. Windows PowerShell (PSReadLine)
//   B. Windows system shortcuts      E. Special symbols on a Mac (Option layer)
//   C. macOS Terminal (zsh / bash)   F. Greek letters and symbols (RF math)
//
// No PNG: every panel is tabular text, so it is rendered natively (it reads
// sharper, recolors for light, and is copy-/screen-reader-friendly). The
// platform tabs (macOS / Windows / Symbols / Greek) keep a phone scroll short;
// each tab is a stack of copyable cards.
//
// States (SOP-007 §5) for a read-only reference screen:
//  - success    → the selected tab's panels render (compile-time const data).
//  - loading / empty / error → not reachable; nothing is fetched or parsed at
//    runtime, every panel always has rows.
//  - interactive→ the platform tabs (the only control) + the AppBar §8.16 copy
//    action; the symbol / Greek glyphs are SelectableText so a single glyph can
//    be grabbed directly.
//  - disabled   → copy is always enabled (const content always present).
//
// Glyph note: the combo strings render in DM Mono as keycaps; the symbol (™, ®,
// λ, Ω …) glyphs are reference DATA, not chrome. ASCII hyphen-minus in prose; no
// em dash (the em-dash ROW in panel E is reference content, the literal symbol
// the card teaches, not prose).
//
// THEME: every color comes from context.colors so the screen renders correctly
// in dark (§8) and light (§8.20). No new tokens introduced. "Wi-Fi" casing.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/keyboard_shortcuts_data.dart';
import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kKeyboardShortcutsToolId = 'keyboard-shortcuts';

/// Which panel group the platform tab shows.
enum _ShortcutTab { macos, windows, symbols, greek }

class KeyboardShortcutsScreen extends StatefulWidget {
  const KeyboardShortcutsScreen({super.key});

  @override
  State<KeyboardShortcutsScreen> createState() =>
      _KeyboardShortcutsScreenState();
}

class _KeyboardShortcutsScreenState extends State<KeyboardShortcutsScreen> {
  _ShortcutTab _tab = _ShortcutTab.macos;

  static const List<(_ShortcutTab, String)> _tabs = <(_ShortcutTab, String)>[
    (_ShortcutTab.macos, 'macOS'),
    (_ShortcutTab.windows, 'Windows'),
    (_ShortcutTab.symbols, 'Symbols'),
    (_ShortcutTab.greek, 'Greek'),
  ];

  static String _tabLabel(_ShortcutTab t) =>
      _tabs.firstWhere(((_ShortcutTab, String) e) => e.$1 == t).$2;

  void _onTabChanged(_ShortcutTab next) {
    if (next == _tab) return;
    setState(() => _tab = next);
    SemanticsService.sendAnnouncement(
      View.of(context),
      '${_tabLabel(next)} shortcuts',
      TextDirection.ltr,
    );
  }

  /// §8.16 plain-text payload — every panel in order so nothing on-screen
  /// survives only as layout. Always non-null (static data).
  static String _copyText() {
    final StringBuffer b = StringBuffer()..writeln('Keyboard Shortcuts');
    for (final ShortcutGroup g in kShortcutGroups) {
      b
        ..writeln()
        ..writeln(g.title);
      for (final ShortcutRow r in g.rows) {
        b.writeln('  ${r.combo}\t${r.action}');
      }
    }
    b
      ..writeln()
      ..writeln('Special symbols on a Mac (hold Option)');
    for (final SymbolRow s in kMacSymbols) {
      b.writeln('  ${s.combo}\t${s.symbol}\t${s.name}');
    }
    b
      ..writeln(kMacSymbolsNote)
      ..writeln()
      ..writeln('Greek letters and symbols (RF math)');
    for (final GreekRow g in kGreekLetters) {
      final String use = g.use.isEmpty ? '' : '\t${g.use}';
      b.writeln('  ${g.lower} ${g.upper}\t${g.name}$use');
    }
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keyboard Shortcuts'),
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
                children: <Widget>[
                  ConceptGraphicBand(
                    toolId: kKeyboardShortcutsToolId,
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic(kKeyboardShortcutsToolId))
                    const SizedBox(height: AppSpacing.md),
                  _TabBar(
                    tabs: _tabs,
                    selected: _tab,
                    onChanged: _onTabChanged,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ..._panelsForTab(_tab),
                  ToolHelpFooter(toolId: kKeyboardShortcutsToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _panelsForTab(_ShortcutTab tab) {
    switch (tab) {
      case _ShortcutTab.macos:
        return <Widget>[
          _ShortcutPanel(group: kMacosShortcuts),
          const SizedBox(height: AppSpacing.md),
          _ShortcutPanel(group: kMacosTerminal),
        ];
      case _ShortcutTab.windows:
        return <Widget>[
          _ShortcutPanel(group: kWindowsShortcuts),
          const SizedBox(height: AppSpacing.md),
          _ShortcutPanel(group: kWindowsPowershell),
        ];
      case _ShortcutTab.symbols:
        return <Widget>[const _SymbolsPanel()];
      case _ShortcutTab.greek:
        return <Widget>[const _GreekPanel()];
    }
  }
}

/// Segmented platform tab bar (4 short options). Mirrors the §8.14 toggle idiom
/// used by ethernet_cable's `_StandardToggle`; each segment flexes so the row
/// never overflows a phone.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  final List<(_ShortcutTab, String)> tabs;
  final _ShortcutTab selected;
  final ValueChanged<_ShortcutTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      child: Row(
        children: tabs.map(((_ShortcutTab, String) opt) {
          final bool isSelected = opt.$1 == selected;
          return Expanded(
            child: Semantics(
              button: true,
              selected: isSelected,
              label: opt.$2,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: () => onChanged(opt.$1),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? colors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    opt.$2,
                    style: text.labelLarge?.copyWith(
                      color: isSelected
                          ? colors.onPrimary
                          : colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Shared card chrome: a titled surface1 container.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
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
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// One shortcut group (combo -> action rows).
class _ShortcutPanel extends StatelessWidget {
  const _ShortcutPanel({required this.group});

  final ShortcutGroup group;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: group.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final ShortcutRow r in group.rows)
            _ShortcutRowTile(combo: r.combo, action: r.action),
        ],
      ),
    );
  }
}

/// One combo -> action row: the combo as a DM Mono keycap chip, the action as
/// body text. The combo and action are read together as one semantic node.
class _ShortcutRowTile extends StatelessWidget {
  const _ShortcutRowTile({required this.combo, required this.action});

  final String combo;
  final String action;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$combo: $action',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 168,
              child: Text(
                combo,
                style: mono.inlineCode.copyWith(
                  color: colors.textAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                action,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Panel E — Mac Option-key special symbols. The glyph is SelectableText so a
/// single symbol can be grabbed; a note carries the degree-vs-ordinal caveat.
class _SymbolsPanel extends StatelessWidget {
  const _SymbolsPanel();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Card(
          title: 'Special symbols on a Mac (hold Option)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final SymbolRow s in kMacSymbols)
                _GlyphRowTile(combo: s.combo, glyph: s.symbol, name: s.name),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: colors.border, width: 1),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.info_outline, size: 16, color: colors.textTertiary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  kMacSymbolsNote,
                  style: text.bodySmall?.copyWith(color: colors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Panel F — Greek letters and their RF-math use.
class _GreekPanel extends StatelessWidget {
  const _GreekPanel();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Greek letters and symbols (RF math)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final GreekRow g in kGreekLetters)
            _GlyphRowTile(
              combo: '${g.lower}  ${g.upper}',
              glyph: g.lower,
              name: g.use.isEmpty ? g.name : '${g.name} (${g.use})',
              comboHasGreek: true,
            ),
        ],
      ),
    );
  }
}

/// A symbol / Greek row: the key combo (or lower+upper glyphs), the headline
/// glyph (SelectableText so one symbol can be grabbed), and the name / use.
class _GlyphRowTile extends StatelessWidget {
  const _GlyphRowTile({
    required this.combo,
    required this.glyph,
    required this.name,
    this.comboHasGreek = false,
  });

  final String combo;
  final String glyph;
  final String name;

  /// When the combo column carries Greek letters (the RF-symbol panel), render
  /// it in Roboto Mono, which has full Greek coverage. DM Mono (`inlineCode`)
  /// lacks the Greek block, so those glyphs would render as tofu boxes. The
  /// device OS font-fallback chain does not reliably backfill them inside a
  /// requested family (confirmed on iOS), so we pick a bundled face that has
  /// the glyphs rather than depending on fallback.
  final bool comboHasGreek;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 168,
            child: Text(
              combo,
              style: (comboHasGreek ? mono.robotoMono : mono.inlineCode)
                  .copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 40,
            child: SelectableText(
              glyph,
              style: (text.titleMedium ?? const TextStyle()).copyWith(
                color: colors.textAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              name,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
