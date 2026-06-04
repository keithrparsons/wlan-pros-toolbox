// Spectrum Ref — read-only Wi-Fi band allocation reference, offline.
//
// Ported verbatim from the rf-tools-pwa `spectrum` tool (index.html
// data-tool="spectrum"; www/app.js: buildSpectrumRef() `bands` const) and its
// three-tab view (2.4 / 5 / 6 GHz). Each band shows a range badge + eight
// key/value facts: total spectrum, standards, channels, non-overlapping,
// channel widths, DFS/radar, co-existence (common interferers), key notes.
// US (FCC) regulatory unless a row notes otherwise. No inputs, no network — a
// static reference, so there is no loading / error / empty / network surface;
// the dataset is compiled in.
//
// States (SOP-007 §5) for a read-only reference screen:
//  - success    → the selected band's facts render in a card.
//  - empty      → not reachable; every band has its full fact set. No
//                 fabricated value.
//  - loading    → not reachable; data is a compile-time const, not an asset.
//  - error      → not reachable; nothing to parse at runtime.
//  - interactive→ the band toggle (2.4 / 5 / 6 GHz) is the only control.
//
// The dataset is exposed as a public static const list on SpectrumScreen so it
// is unit-testable without pumping the widget.
//
// Token note (assumption): the PWA tinted each band badge with an arbitrary
// hex (#ff9800 / #0071e3 / #34c759). Hardcoded hex is forbidden (GL-003); the
// badge accent is mapped to design-system status tokens — 2.4 GHz → warning
// (amber, the congested band), 5 GHz → info (blue), 6 GHz → success (green).
// The accent is decorative chrome, paired with the always-present band label
// text (never color-only, §8.13 rule 2). All other values are verbatim.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_action.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// Which band's fact sheet is shown. 2.4 / 5 / 6 GHz — three short options, so
/// a segmented toggle, not an AppSelect (GL-003 §8.14).
enum SpectrumBand { ghz24, ghz5, ghz6 }

/// One band's complete fact sheet, verbatim from the PWA `bands` const.
class SpectrumBandInfo {
  const SpectrumBandInfo({
    required this.band,
    required this.label,
    required this.range,
    required this.accent,
    required this.total,
    required this.standards,
    required this.channels,
    required this.nonOverlap,
    required this.widths,
    required this.dfs,
    required this.coexist,
    required this.notes,
  });

  final SpectrumBand band;

  /// Tab/badge label: "2.4 GHz" / "5 GHz" / "6 GHz".
  final String label;

  /// Frequency range shown in the badge (e.g. "2400 - 2484 MHz").
  final String range;

  /// Decorative badge accent — a design-system status token, NOT the PWA hex.
  /// Always paired with the `label` text, never color-only.
  final Color accent;

  /// Total usable spectrum (US, with EU note where the PWA carries one).
  final String total;
  final String standards;
  final String channels;
  final String nonOverlap;
  final String widths;
  final String dfs;

  /// Co-existence — the band's common interferers / managed incumbents.
  final String coexist;
  final String notes;

  /// The eight key/value fact rows, in the PWA's row order.
  List<(String, String)> get facts => <(String, String)>[
    ('Total spectrum', total),
    ('Standards', standards),
    ('Channels (US)', channels),
    ('Non-overlapping', nonOverlap),
    ('Channel widths', widths),
    ('DFS / Radar', dfs),
    ('Co-existence', coexist),
    ('Key notes', notes),
  ];
}

class SpectrumScreen extends StatefulWidget {
  const SpectrumScreen({super.key});

  // ── Dataset (public, const, unit-testable) ────────────────────────────────

  /// The three Wi-Fi bands, verbatim from rf-tools-pwa buildSpectrumRef()
  /// `bands`. Frequency allocations, channel counts, DFS sub-bands (UNII-2A
  /// 5250-5350, UNII-2C 5470-5725), and power modes are reproduced exactly;
  /// only the badge accent is re-mapped to a design-system token (see header).
  static const List<SpectrumBandInfo> bands = [
    SpectrumBandInfo(
      band: SpectrumBand.ghz24,
      label: '2.4 GHz',
      range: '2400 - 2484 MHz',
      accent: AppColors.statusWarning,
      total: '84 MHz (US)',
      standards: '802.11b / g / n / ax (Wi-Fi 4 / 6)',
      channels: 'Ch 1-11 (US) · Ch 1-13 (EU) · Ch 1-14 (JP)',
      nonOverlap: '3 channels at 20 MHz: 1, 6, 11',
      widths: '20 MHz, 40 MHz',
      dfs: 'None',
      coexist:
          'Bluetooth (2.402-2.480 GHz), Zigbee (2.4 GHz), microwave ovens '
          '(~2.45 GHz), baby monitors, cordless phones',
      notes:
          'High interference environment. Best wall penetration of the three '
          'bands. Avoid as primary band in dense enterprise deployments. '
          'Wi-Fi 5 (802.11ac) does not operate in 2.4 GHz.',
    ),
    SpectrumBandInfo(
      band: SpectrumBand.ghz5,
      label: '5 GHz',
      range: '5150 - 5850 MHz (US UNII-1/2A/2C/3)',
      accent: AppColors.statusInfo,
      total: '~580 MHz usable (US UNII-1/2A/2C/3)',
      standards: '802.11a / n / ac / ax (Wi-Fi 5 / 6)',
      channels: '25 channels at 20 MHz (US, including DFS)',
      nonOverlap: '25 @ 20 MHz · 12 @ 40 MHz · 6 @ 80 MHz · 2 @ 160 MHz',
      widths: '20 / 40 / 80 / 160 MHz',
      dfs:
          'Required in UNII-2A (5250-5350 MHz) and UNII-2C (5470-5725 MHz) - '
          'radar avoidance mandatory',
      coexist:
          'Weather radar, terminal Doppler radar, military radar (all managed '
          'by DFS)',
      notes:
          'UNII-1 (5150-5250 MHz): indoor use only in some regions. '
          'UNII-2A/2C require DFS - expect 60-second channel availability '
          'delay after radar detection. UNII-3 (5725-5850 MHz): no DFS.',
    ),
    SpectrumBandInfo(
      band: SpectrumBand.ghz6,
      label: '6 GHz',
      range: '5925 - 7125 MHz',
      accent: AppColors.statusSuccess,
      total: '1200 MHz',
      standards: '802.11ax / be (Wi-Fi 6E / 7)',
      channels:
          '59 × 20 MHz · 29 × 40 MHz · 14 × 80 MHz · 7 × 160 MHz · '
          '3 × 320 MHz (Wi-Fi 7)',
      nonOverlap:
          '59 non-overlapping at 20 MHz · 14 PSC (Preferred Scanning '
          'Channels) for APs',
      widths: '20 / 40 / 80 / 160 MHz (Wi-Fi 6E) · + 320 MHz (Wi-Fi 7)',
      dfs:
          'No DFS - incumbent protection via AFC (Automated Frequency '
          'Coordination) for standard-power outdoor',
      coexist: 'Fixed microwave backhaul links (managed via AFC database)',
      notes:
          'Three power modes in US: Standard Power (up to 36 dBm EIRP, '
          'requires AFC outdoors) · Low Power Indoor / LPI (up to 30 dBm, no '
          'AFC) · Very Low Power / VLP (up to 14 dBm EIRP, no AFC, mobile '
          'use). No '
          'legacy Wi-Fi 4 or older devices - WPA3 mandatory.',
    ),
  ];

  @override
  State<SpectrumScreen> createState() => _SpectrumScreenState();
}

class _SpectrumScreenState extends State<SpectrumScreen> {
  SpectrumBand _band = SpectrumBand.ghz24;

  void _onBandChanged(SpectrumBand next) {
    if (next == _band) return;
    setState(() => _band = next);
    // WCAG 4.1.3 — announce which band's fact sheet is now shown.
    SemanticsService.sendAnnouncement(
      View.of(context),
      '${_info(next).label} spectrum',
      TextDirection.ltr,
    );
  }

  SpectrumBandInfo _info(SpectrumBand b) =>
      SpectrumScreen.bands.firstWhere((SpectrumBandInfo i) => i.band == b);

  /// §8.16 copy payload — the full band-allocation reference as TSV. Static
  /// data, so always enabled, and it copies ALL THREE bands (not just the
  /// selected one) so the clipboard carries the complete reference. Each band
  /// is its own section: a subtitle (label + range), a Fact/Value header, then
  /// one row per fact in the band's fixed fact order.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()..writeln('Spectrum Reference');
    for (final SpectrumBandInfo info in SpectrumScreen.bands) {
      buf
        ..writeln()
        ..writeln('${info.label} (${info.range})')
        ..writeln(<String>['Fact', 'Value'].join(tab));
      for (final (String key, String value) in info.facts) {
        buf.writeln(<String>[key, value].join(tab));
      }
    }
    buf
      ..writeln()
      ..writeln(
        'US (FCC) regulatory domain. Verify local rules before '
        'deployment.',
      );
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spectrum Ref'),
        toolbarHeight: 64,
        // §8.16 order: copy LEADS, help TRAILS.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
          ToolHelpAction(toolId: 'spectrum'),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
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
                  ConceptGraphicBand(toolId: 'spectrum', isDesktop: isDesktop),
                  if (ToolAssets.hasGraphic('spectrum'))
                    const SizedBox(height: AppSpacing.md),
                  _bandCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _factCard(context, _info(_band)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bandCard(BuildContext context) {
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
            'Band',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // 2.4 / 5 / 6 GHz — three short options, segmented toggle (§8.14).
          _BandToggle(value: _band, onChanged: _onBandChanged),
        ],
      ),
    );
  }

  Widget _factCard(BuildContext context, SpectrumBandInfo info) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Range badge — left accent bar + tinted fill, mirrors the PWA
          // `.spectrum-badge`. Accent paired with the label text (never
          // color-only, §8.13 rule 2).
          _BandBadge(info: info),
          const SizedBox(height: AppSpacing.sm),
          // Eight key/value facts. Each fact is a label column + value column
          // that wraps; no fixed-width cells means no horizontal overflow on a
          // narrow phone (long values reflow downward, not off-screen).
          ...info.facts.asMap().entries.expand((entry) {
            final (String key, String value) = entry.value;
            return [
              if (entry.key > 0)
                const Divider(color: AppColors.border, height: AppSpacing.sm),
              _FactRow(label: key, value: value),
            ];
          }),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'US (FCC) regulatory domain. Verify local rules before deployment.',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// The range badge for the selected band: a left accent rule, the band label
/// in the accent color, and the frequency range beneath.
class _BandBadge extends StatelessWidget {
  const _BandBadge({required this.info});

  final SpectrumBandInfo info;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: info.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border(left: BorderSide(color: info.accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            info.label,
            style: text.titleLarge?.copyWith(
              color: info.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            info.range,
            style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// One key/value fact: the label (secondary) on the left, the value (primary)
/// flexing on the right and wrapping. Right-aligned value mirrors the PWA's
/// two-column `.ref-table`; on a phone the value wraps within its column rather
/// than overflowing.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ReferenceRowSemantics(
      label: rowLabel(label, <String?>[value]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fixed label column — wide enough for the longest key
            // ("Non-overlapping") without truncating, narrow enough to leave the
            // value the majority of a 320pt phone width.
            SizedBox(
              width: 116,
              child: Text(
                label,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                value,
                style: text.bodyMedium?.copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented band toggle (2.4 / 5 / 6 GHz). Mirrors the calculators' private
/// `_UnitToggle` idiom and the Wi-Fi Channels `_BandToggle` (§8.14: a Toggle is
/// correct for 2-3 short options) so this reference screen stays consistent
/// with the rest of the app.
class _BandToggle extends StatelessWidget {
  const _BandToggle({required this.value, required this.onChanged});

  final SpectrumBand value;
  final ValueChanged<SpectrumBand> onChanged;

  static const List<(SpectrumBand, String)> _options = [
    (SpectrumBand.ghz24, '2.4 GHz'),
    (SpectrumBand.ghz5, '5 GHz'),
    (SpectrumBand.ghz6, '6 GHz'),
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
          // Each segment flexes to share the row width so the three band chips
          // never overflow a narrow phone surface.
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
