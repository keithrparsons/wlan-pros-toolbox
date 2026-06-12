// Cable & Connector — read-only twisted-pair reference (Tier-1, Pass 2b
// 2026-06-12). NATIVE throughout (the pinout renders cleanly as 8 swatch rows,
// so no PNG is embedded):
//   A. Category capability chart (Cat5e -> Cat8): speed, bandwidth, distance,
//      PoE. The headline speed is lime (the one measured capability the row is
//      about, GL-003 §8.15 case-3).
//   B. Cat 7 caveat — ISO/IEC Class F, NOT a TIA standard — as a warning verdict
//      (paired with the word, never color-only; §8.13).
//   C. PoE note.
//   D. RJ-45 pinout, T568B / T568A toggle, with the domain-canonical wire-color
//      swatches (the color IS the standard; §8.6.2 / §8.15 case-1) always paired
//      with the worded color name (never color-only; WCAG 1.4.1).
//
// DEDUPE: twisted-pair / Ethernet side only; coax has its own `coax-cable` tool.
// This is a NEW combined tile (id `cable-connector`), distinct from the existing
// `ethernet-cable` and `ethernet-pinout` tiles.
//
// States (SOP-007 §5):
//  - success    → the chart + pinout render (compile-time const data).
//  - loading / empty / error → not reachable; nothing fetched or parsed.
//  - interactive→ the T568B / T568A toggle + the AppBar §8.16 copy action.
//  - disabled   → copy is always enabled (const content always present).
//
// THEME: every chrome color comes from context.colors (dark §8 / light §8.20).
// The wire-color swatches are DATA glyphs (canonical wire colors), not tokens,
// and stay literal in both themes. No new tokens. Glyph note: no em dash;
// "Wi-Fi" casing in prose.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/cable_connector_data.dart';
import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kCableConnectorToolId = 'cable-connector';

class CableConnectorScreen extends StatefulWidget {
  const CableConnectorScreen({super.key});

  @override
  State<CableConnectorScreen> createState() => _CableConnectorScreenState();
}

class _CableConnectorScreenState extends State<CableConnectorScreen> {
  CableWiringStandard _std = CableWiringStandard.t568b;

  static String _label(CableWiringStandard s) =>
      s == CableWiringStandard.t568b ? 'T568B' : 'T568A';

  void _onStandardChanged(CableWiringStandard next) {
    if (next == _std) return;
    setState(() => _std = next);
    SemanticsService.sendAnnouncement(
      View.of(context),
      '${_label(next)} pinout',
      TextDirection.ltr,
    );
  }

  /// §8.16 plain-text payload — the whole reference so nothing on-screen
  /// survives only as layout. Always non-null (static data).
  String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Cable & Connector (twisted-pair)')
      ..writeln()
      ..writeln('Category capability')
      ..writeln(
        <String>[
          'Category',
          'Max speed',
          'Bandwidth',
          'Max distance',
          'PoE',
        ].join(tab),
      );
    for (final CableCategory c in kCableCategories) {
      b.writeln(
        <String>[
          c.category,
          c.maxSpeed,
          c.bandwidth,
          c.maxDistance,
          c.poe,
        ].join(tab),
      );
    }
    b
      ..writeln(kCat7Caveat)
      ..writeln(kCablePoeNote)
      ..writeln()
      ..writeln('${_label(_std)} pinout')
      ..writeln(<String>['Pin', 'Wire'].join(tab));
    for (final CablePin p in kCablePinout[_std]!) {
      b.writeln(<String>['${p.pin}', p.colorName].join(tab));
    }
    b.writeln(kPinoutNote);
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cable & Connector'),
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
                    toolId: kCableConnectorToolId,
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic(kCableConnectorToolId))
                    const SizedBox(height: AppSpacing.md),
                  const _CategoryCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _Cat7CaveatCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _PoeNoteCard(),
                  const SizedBox(height: AppSpacing.md),
                  _PinoutCard(std: _std, onChanged: _onStandardChanged),
                  ToolHelpFooter(toolId: kCableConnectorToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The Category capability chart. Headline speed is lime (the measured
/// capability); the Cat 7 row name carries a warning glyph.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);
    final TextStyle smallStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textSecondary);

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
            'Category capability',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          HorizontalScrollTable(
            child: DataTable(
              headingRowHeight: 44,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 64,
              columnSpacing: AppSpacing.md,
              horizontalMargin: 0,
              dividerThickness: 1,
              headingTextStyle: headStyle,
              columns: const <DataColumn>[
                DataColumn(label: Text('Category')),
                DataColumn(label: Text('Max speed')),
                DataColumn(label: Text('Bandwidth')),
                DataColumn(label: Text('Max distance')),
              ],
              rows: kCableCategories.map((CableCategory c) {
                final String summary = rowLabel(c.category, <String?>[
                  'max speed ${c.maxSpeed}',
                  'bandwidth ${c.bandwidth}',
                  'max distance ${c.maxDistance}',
                  c.caveat ? 'ISO/IEC Class F, not a TIA standard' : null,
                ]);
                return DataRow(
                  cells: <DataCell>[
                    DataCell(
                      Semantics(
                        label: summary,
                        container: true,
                        child: ExcludeSemantics(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                c.category,
                                style: mono.inlineCode.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (c.caveat) ...<Widget>[
                                const SizedBox(width: AppSpacing.xxs),
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 14,
                                  color: colors.statusWarning,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(
                          c.maxSpeed,
                          // §8.15 case-3: the headline speed is the one measured
                          // capability the row is about, so it is lime.
                          style: mono.inlineCode.copyWith(
                            color: colors.textAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(
                          c.bandwidth,
                          style: mono.inlineCode.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(c.maxDistance, style: smallStyle),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // The PoE-relevance column is dropped from the scroll table to keep the
          // rows legible; surface it here so no data is lost.
          for (final CableCategory c in kCableCategories)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: RichText(
                text: TextSpan(
                  style: text.labelMedium?.copyWith(color: colors.textTertiary),
                  children: <InlineSpan>[
                    TextSpan(
                      text: '${c.category}: ',
                      style: text.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: c.poe),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The Cat 7 caveat as a warning verdict card (glyph + word, §8.13).
class _Cat7CaveatCard extends StatelessWidget {
  const _Cat7CaveatCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Cat 7: ISO/IEC Class F, not a TIA standard',
                  style: (text.bodyMedium ?? const TextStyle()).copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  kCat7Caveat,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The PoE note card.
class _PoeNoteCard extends StatelessWidget {
  const _PoeNoteCard();

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
            'Power over Ethernet',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kCablePoeNote,
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// The RJ-45 pinout card: T568B / T568A toggle + the 8 swatch rows + footnote.
class _PinoutCard extends StatelessWidget {
  const _PinoutCard({required this.std, required this.onChanged});

  final CableWiringStandard std;
  final ValueChanged<CableWiringStandard> onChanged;

  static String _label(CableWiringStandard s) =>
      s == CableWiringStandard.t568b ? 'T568B' : 'T568A';

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final List<CablePin> pins = kCablePinout[std]!;
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
            'RJ-45 pinout (8P8C, 4 pairs)',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _StandardToggle(value: std, onChanged: onChanged),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${_label(std)} (pin to wire)',
            style: text.labelSmall?.copyWith(
              color: colors.textTertiary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final CablePin p in pins) _PinRowTile(pin: p),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kPinoutNote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// One pin row: the pin number, a wire-color swatch (DATA glyph), and the worded
/// wire-color name. The color is never the sole signal (the name carries it).
class _PinRowTile extends StatelessWidget {
  const _PinRowTile({required this.pin});

  final CablePin pin;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Pin ${pin.pin}, ${pin.colorName}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 40,
              child: Text(
                '${pin.pin}',
                style: mono.inlineCode.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            _WireSwatch(colorHex: pin.colorHex, striped: pin.striped),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                pin.colorName,
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wire-color swatch. Solid for a single-color wire; a 135-degree split (color
/// over the canonical white-stripe hex) for a striped wire. The fill is the
/// literal canonical wire color (a DATA glyph), bordered with a hairline so a
/// near-white stripe stays visible on either canvas.
class _WireSwatch extends StatelessWidget {
  const _WireSwatch({required this.colorHex, required this.striped});

  final int colorHex;
  final bool striped;

  static const double _size = 16;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final Color wire = Color(colorHex);
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.border, width: 1),
        gradient: striped
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const <double>[0.5, 0.5],
                colors: <Color>[const Color(WireColors.white), wire],
              )
            : null,
        color: striped ? null : wire,
      ),
    );
  }
}

/// Segmented T568B / T568A toggle (§8.14: a toggle for 2-3 short options).
class _StandardToggle extends StatelessWidget {
  const _StandardToggle({required this.value, required this.onChanged});

  final CableWiringStandard value;
  final ValueChanged<CableWiringStandard> onChanged;

  static const List<(CableWiringStandard, String)> _options =
      <(CableWiringStandard, String)>[
        (CableWiringStandard.t568b, 'T568B'),
        (CableWiringStandard.t568a, 'T568A'),
      ];

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
        children: _options.map(((CableWiringStandard, String) opt) {
          final bool selected = opt.$1 == value;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: opt.$2,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: () => onChanged(opt.$1),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: selected ? colors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    opt.$2,
                    style: text.labelLarge?.copyWith(
                      color: selected ? colors.onPrimary : colors.textSecondary,
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
