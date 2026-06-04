// Ethernet Pinout — read-only T568A / T568B wiring reference, offline.
//
// Ported verbatim from the RF Tools PWA `pinout` tool (rf-tools-pwa/www
// app.js: const PINOUT, plus buildPinoutTable / buildPinout). The PWA shows
// two standards (T568B default tab, T568A) each as a pin → wire-color → pair →
// 100/1000 Base-T function table, with a note and a footnote. This screen
// reproduces that exact pin-to-pair-to-color mapping. The wiring is not
// invented — every row is the PWA's own data array.
//
// States (SOP-007 §5) for a read-only reference screen:
//  - success    → the selected standard's eight pin rows render in a card.
//  - empty      → not reachable; both standards always have eight rows. (No
//                 fabricated row.)
//  - loading    → not reachable; data is a compile-time const, not an asset.
//  - error      → not reachable; nothing is parsed at runtime.
//  - interactive→ the standard toggle (T568B / T568A) is the only control.
//
// Color glyph note: the wire-insulation swatch and the pair-color swatch are
// DATA glyphs (the literal copper-pair colors an installer sees), not UI chrome
// — the same role the dB Reference gives its green/red dB values and the PWA
// gives its <span class="wire-dot">. They are intentionally the real wire
// colors and are kept verbatim from the PWA hexes; they are NOT design-system
// surface/text tokens and must not be swapped for them. Every text, surface,
// border, radius, and spacing value below is a GL-003 token.
//
// The dataset is exposed as a public static const map on EthernetPinoutScreen
// so it is unit-testable without pumping the widget.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_action.dart';
import '../concept_graphic_band.dart';

/// Which wiring standard's table is shown. Two short options → segmented
/// toggle, not an AppSelect (GL-003 §8.14). T568B is the PWA's default tab.
enum WiringStandard { t568b, t568a }

/// One pin row in a wiring standard. Verbatim shape of the PWA's PINOUT array
/// entry `[pin, colorHex, colorName, pair, function]`.
class PinoutPin {
  const PinoutPin({
    required this.pin,
    required this.colorHex,
    required this.colorName,
    required this.pair,
    required this.function,
  });

  /// RJ-45 pin number, 1–8.
  final int pin;

  /// Wire-insulation color as the literal PWA hex — a DATA glyph (the real
  /// copper color), not a GL-003 token. A name containing '/' is a striped
  /// (color-on-white) wire; rendered as a 135° split swatch like the PWA.
  final int colorHex;

  /// Human-readable wire color, verbatim from the PWA (e.g. 'Orange / White').
  final String colorName;

  /// Twisted-pair number this wire belongs to, 1–4.
  final int pair;

  /// 100/1000 Base-T signal function (e.g. 'TX+', 'BI-D A+').
  final String function;
}

class EthernetPinoutScreen extends StatefulWidget {
  const EthernetPinoutScreen({super.key});

  // ── Dataset (public, const, unit-testable) ────────────────────────────────

  /// Pin → wire-color → pair → function, per standard. Ported VERBATIM from
  /// the RF Tools PWA app.js `const PINOUT`. Hex values are the PWA's literal
  /// wire-color hexes (data glyphs). Do not edit without re-checking the PWA.
  static const Map<WiringStandard, List<PinoutPin>> pinout = {
    WiringStandard.t568b: [
      PinoutPin(
        pin: 1,
        colorHex: 0xFFE65100,
        colorName: 'Orange / White',
        pair: 2,
        function: 'TX+',
      ),
      PinoutPin(
        pin: 2,
        colorHex: 0xFFE65100,
        colorName: 'Orange',
        pair: 2,
        function: 'TX-',
      ),
      PinoutPin(
        pin: 3,
        colorHex: 0xFF2E7D32,
        colorName: 'Green / White',
        pair: 3,
        function: 'RX+',
      ),
      PinoutPin(
        pin: 4,
        colorHex: 0xFF1565C0,
        colorName: 'Blue',
        pair: 1,
        function: 'BI-D A+',
      ),
      PinoutPin(
        pin: 5,
        colorHex: 0xFF1565C0,
        colorName: 'Blue / White',
        pair: 1,
        function: 'BI-D A-',
      ),
      PinoutPin(
        pin: 6,
        colorHex: 0xFF2E7D32,
        colorName: 'Green',
        pair: 3,
        function: 'RX-',
      ),
      PinoutPin(
        pin: 7,
        colorHex: 0xFF6D4C41,
        colorName: 'Brown / White',
        pair: 4,
        function: 'BI-D B+',
      ),
      PinoutPin(
        pin: 8,
        colorHex: 0xFF6D4C41,
        colorName: 'Brown',
        pair: 4,
        function: 'BI-D B-',
      ),
    ],
    WiringStandard.t568a: [
      PinoutPin(
        pin: 1,
        colorHex: 0xFF2E7D32,
        colorName: 'Green / White',
        pair: 3,
        function: 'TX+',
      ),
      PinoutPin(
        pin: 2,
        colorHex: 0xFF2E7D32,
        colorName: 'Green',
        pair: 3,
        function: 'TX-',
      ),
      PinoutPin(
        pin: 3,
        colorHex: 0xFFE65100,
        colorName: 'Orange / White',
        pair: 2,
        function: 'RX+',
      ),
      PinoutPin(
        pin: 4,
        colorHex: 0xFF1565C0,
        colorName: 'Blue',
        pair: 1,
        function: 'BI-D A+',
      ),
      PinoutPin(
        pin: 5,
        colorHex: 0xFF1565C0,
        colorName: 'Blue / White',
        pair: 1,
        function: 'BI-D A-',
      ),
      PinoutPin(
        pin: 6,
        colorHex: 0xFFE65100,
        colorName: 'Orange',
        pair: 2,
        function: 'RX-',
      ),
      PinoutPin(
        pin: 7,
        colorHex: 0xFF6D4C41,
        colorName: 'Brown / White',
        pair: 4,
        function: 'BI-D B+',
      ),
      PinoutPin(
        pin: 8,
        colorHex: 0xFF6D4C41,
        colorName: 'Brown',
        pair: 4,
        function: 'BI-D B-',
      ),
    ],
  };

  /// Pair number → wire-color hex. Verbatim from the PWA `pairCols` in
  /// buildPinoutTable. Data glyph, not a GL-003 token.
  static const Map<int, int> pairColors = {
    1: 0xFF1565C0, // Blue
    2: 0xFFE65100, // Orange
    3: 0xFF2E7D32, // Green
    4: 0xFF6D4C41, // Brown
  };

  /// Plug-orientation note, verbatim from the PWA pinout view.
  static const String orientationNote =
      'Plug face view — clip facing down. Pin 1 is on the left.';

  /// Footnote, verbatim from the PWA buildPinoutTable. The PWA's em dash is
  /// replaced with a comma per the no-em-dash hard rule.
  static const String footnote =
      'Applies to Cat5, Cat5e, Cat6, Cat6A, Cat7, and Cat8. A crossover cable '
      'uses T568A on one end and T568B on the other, rarely needed today since '
      'most switches and NICs auto-MDI-X.';

  @override
  State<EthernetPinoutScreen> createState() => _EthernetPinoutScreenState();
}

class _EthernetPinoutScreenState extends State<EthernetPinoutScreen> {
  WiringStandard _std = WiringStandard.t568b;

  void _onStandardChanged(WiringStandard next) {
    if (next == _std) return;
    setState(() => _std = next);
    // WCAG 4.1.3 — announce which standard's table is now shown.
    SemanticsService.sendAnnouncement(
      View.of(context),
      '${_label(next)} pinout',
      TextDirection.ltr,
    );
  }

  static String _label(WiringStandard s) =>
      s == WiringStandard.t568b ? 'T568B' : 'T568A';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ethernet Pinout'),
        toolbarHeight: 64,
        // §8.16 — copy the selected standard's pin table as TSV. Static data,
        // so the affordance is always enabled.
        // §8.16 order: copy LEADS, help TRAILS.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
          ToolHelpAction(toolId: 'ethernet-pinout'),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the selected standard's pin → wire → pair → function
  /// table as TSV. The selected standard names the title line; one header row;
  /// one tab-separated row per pin. Always non-null (static data).
  String _buildCopyText() {
    const String tab = '\t';
    final List<PinoutPin> pins = EthernetPinoutScreen.pinout[_std]!;
    final StringBuffer buf = StringBuffer()
      ..writeln('${_label(_std)} — pin to pair')
      ..writeln(
        <String>['Pin', 'Wire color', 'Pair', '100/1000 Base-T'].join(tab),
      );
    for (final PinoutPin p in pins) {
      buf.writeln(
        <String>['${p.pin}', p.colorName, '${p.pair}', p.function].join(tab),
      );
    }
    return buf.toString().trimRight();
  }

  Widget _body() {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
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
                children: [
                  ConceptGraphicBand(
                    toolId: 'ethernet-pinout',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('ethernet-pinout'))
                    const SizedBox(height: AppSpacing.md),
                  _standardCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _tableCard(context, mono),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _standardCard(BuildContext context) {
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
        children: [
          Text(
            'Standard',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // T568B / T568A — two short options, segmented toggle (§8.14).
          _StandardToggle(value: _std, onChanged: _onStandardChanged),
          const SizedBox(height: AppSpacing.sm),
          Text(
            EthernetPinoutScreen.orientationNote,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _tableCard(BuildContext context, AppMonoText mono) {
    final List<PinoutPin> pins = EthernetPinoutScreen.pinout[_std]!;
    return _TableCard(
      title: '${_label(_std)} — pin to pair',
      footnote: EthernetPinoutScreen.footnote,
      header: const Row(
        children: [
          _HeaderCell('Pin', width: 40),
          _HeaderCell('Wire color', width: 152),
          _HeaderCell('Pair', width: 64),
          _HeaderCell('100/1000 Base-T', width: 120),
        ],
      ),
      rows: pins.map((p) => _PinRow(pin: p, mono: mono)).toList(),
    );
  }
}

/// Shared card chrome for the pinout table: title, horizontal-scroll grid
/// (header + rows), footnote. Mirrors the wifi_channels `_TableCard` idiom.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.header,
    required this.rows,
    this.footnote,
  });

  final String title;
  final Widget header;
  final List<Widget> rows;
  final String? footnote;

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
        children: [
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Fixed-width cells inside a horizontal scroll: children of a
          // horizontal SingleChildScrollView get unbounded width, so
          // IntrinsicWidth lets every Row shrink-wrap its fixed-width cells
          // and share one common width — columns align and nothing is pinned
          // to a guessed (too-small) value that would overflow. Title and
          // footnote stay full-width and wrap.
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const Divider(color: AppColors.border, height: AppSpacing.sm),
                  ...rows,
                ],
              ),
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              footnote!,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One column-header label, mono-caption styled to align with the data cells.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: AppColors.textTertiary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// One pin row: pin number, wire-color swatch + name, pair swatch + number,
/// Base-T function. Swatch fills are DATA glyphs (real wire colors), not UI
/// tokens.
class _PinRow extends StatelessWidget {
  const _PinRow({required this.pin, required this.mono});

  final PinoutPin pin;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool striped = pin.colorName.contains('/');
    // Pin function and pair carried by text, so the color swatch is never the
    // only signal (§8.13 rule 2 / WCAG 1.4.1).
    return Semantics(
      label:
          'Pin ${pin.pin}, ${pin.colorName}, pair ${pin.pair}, ${pin.function}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  '${pin.pin}',
                  style: mono.inlineCode.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(
                width: 152,
                child: Row(
                  children: [
                    _WireSwatch(colorHex: pin.colorHex, striped: striped),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        pin.colorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 64,
                child: Row(
                  children: [
                    _WireSwatch(
                      colorHex: EthernetPinoutScreen.pairColors[pin.pair]!,
                      striped: false,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '${pin.pair}',
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 120,
                child: Text(
                  pin.function,
                  style: mono.inlineCode.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wire-color swatch. Solid for a single-color wire; a 135° split (color over
/// white) for a striped wire — mirrors the PWA's linear-gradient wire dot. The
/// fill is the literal copper-pair color (a data glyph), bordered with a
/// low-alpha hairline like the PWA so a near-white wire reads on dark.
class _WireSwatch extends StatelessWidget {
  const _WireSwatch({required this.colorHex, required this.striped});

  final int colorHex;
  final bool striped;

  static const double _size = 14;

  @override
  Widget build(BuildContext context) {
    final Color wire = Color(colorHex);
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Hairline keeps the swatch visible on the dark card (§8.1 decorative
        // border is correct here — the swatch is non-interactive).
        border: Border.all(color: AppColors.border, width: 1),
        gradient: striped
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.5, 0.5],
                colors: [wire, AppColors.neutral0],
              )
            : null,
        color: striped ? null : wire,
      ),
    );
  }
}

/// Segmented standard toggle (T568B / T568A). Mirrors the wifi_channels
/// `_BandToggle` idiom (§8.14: a Toggle is correct for 2–3 short options).
class _StandardToggle extends StatelessWidget {
  const _StandardToggle({required this.value, required this.onChanged});

  final WiringStandard value;
  final ValueChanged<WiringStandard> onChanged;

  static const List<(WiringStandard, String)> _options = [
    (WiringStandard.t568b, 'T568B'),
    (WiringStandard.t568a, 'T568A'),
  ];

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.borderStrong, width: 1),
      ),
      child: Row(
        children: _options.map((opt) {
          final bool selected = opt.$1 == value;
          // Each segment flexes to share the row width so the two chips never
          // overflow a narrow phone surface.
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
                    color: selected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    opt.$2,
                    style: text.labelLarge?.copyWith(
                      color: selected
                          ? AppColors.secondary
                          : AppColors.textSecondary,
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
