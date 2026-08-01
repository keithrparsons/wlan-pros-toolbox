// Wi-Fi Throughput calculator.
//
// Pick a Wi-Fi standard, channel width, MCS index, spatial streams, and guard
// interval; read modulation, PHY rate, and estimated real throughput. Matches
// the RF Tools PWA reference (app.js calcThroughput, with updateTputOptions for
// the dependent option sets) value-for-value.
//
// Formula (PWA calcThroughput):
//   phyRate(Mbps)  = (Nsd · bitsPerSymbol · streams) / symbolTime(µs)
//   realRate(Mbps) = phyRate · efficiency(std)
// where Nsd is data subcarriers (per standard per width), bitsPerSymbol is
// MCS_BPS[mcs] (Nbpsc·Rc), symbolTime is the OFDM symbol duration (per standard
// per guard interval), and efficiency is the per-standard real/PHY factor.
//
// Constant tables are direct ports of the PWA: MCS_BPS, MCS_MOD, TPUT_NSD,
// TPUT_SYM, TPUT_MAX_MCS, TPUT_EFF, plus the bandwidth / GI / max-SS option
// sets from updateTputOptions. Output uses fmt(n, 1) — fixed 1-decimal Mbps.
//
// WHERE THE MATH NOW LIVES (extracted 2026-07-31): the tables and the two rate
// functions moved verbatim, value-for-value, to [WifiPhyRateService] in
// `lib/services/network/wifi_phy_rate_service.dart`, so a second screen can
// compute a PHY rate without reaching into this widget's statics. The full
// PWA provenance travelled with them and lives in that file's header.
//
// The statics below are kept as THIN DELEGATES, not duplicates: the calculator
// screen, the MCS-index screen's cross-check, and the existing tests all call
// `ThroughputCalcScreen.<member>`, and there is exactly one definition of each
// number (in the service). [WifiStd] is re-exported from this library so every
// existing `import '.../throughput_calc_screen.dart'` still resolves it.
//
// Dependent options mirror updateTputOptions: changing the standard reclamps
// bandwidth, MCS, spatial streams, and guard interval to that standard's valid
// set (keeping the prior choice when it still fits, the PWA behavior).
//
// Edge cases:
// - An invalid bandwidth / guard-interval combination → blank outputs (the PWA
//   showError path); the reclamp logic prevents this in normal use, but the
//   pure math guards it anyway so the function never divides by a missing Nsd
//   or symbol time.
// - MCS above the standard's max → blank (PWA showError path).
//
// Pure, no network, no platform APIs. The math is unit-tested against the PWA
// values twice over: directly on [WifiPhyRateService], and through the static
// delegates on this widget that the pre-extraction tests still call.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/wifi_phy_rate_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// [WifiStd] moved to [WifiPhyRateService] with the math it belongs to. It is
/// re-exported here so every existing importer of this screen (the MCS-index
/// screen's cross-check test, the audit suite, this tool's own test) keeps
/// resolving `WifiStd` from the same import it always used.
export '../../../services/network/wifi_phy_rate_service.dart' show WifiStd;

class ThroughputCalcScreen extends StatefulWidget {
  const ThroughputCalcScreen({super.key});

  // ─── Constant tables and math: DELEGATES to WifiPhyRateService ──────────────
  //
  // Every member below is an alias, not a copy. The one definition of each
  // number lives in `lib/services/network/wifi_phy_rate_service.dart`, together
  // with the PWA provenance. These aliases exist so the calculator screen, the
  // MCS-index cross-check, and the existing tests keep their call sites
  // (`ThroughputCalcScreen.maxMcs`, `.phyRateMbps(...)`, and so on) unchanged.
  //
  // Building something NEW? Call [WifiPhyRateService] directly. Do not add a
  // new member here.

  /// Bits per symbol per MCS — Nbpsc · Rc (PWA MCS_BPS).
  static const List<double> mcsBps = WifiPhyRateService.mcsBps;

  /// Modulation label per MCS (PWA MCS_MOD).
  static const List<String> mcsMod = WifiPhyRateService.mcsMod;

  /// Long MCS label (index — modulation) for the MCS select (PWA mcsLabels).
  static String mcsLabel(int mcs) => WifiPhyRateService.mcsLabel(mcs);

  /// Data subcarriers per standard per channel width MHz (PWA TPUT_NSD).
  static const Map<WifiStd, Map<int, int>> nsd = WifiPhyRateService.nsd;

  /// OFDM symbol duration µs per standard per guard interval key (PWA TPUT_SYM).
  static const Map<WifiStd, Map<String, double>> sym = WifiPhyRateService.sym;

  /// Highest valid MCS index per standard (PWA TPUT_MAX_MCS).
  static const Map<WifiStd, int> maxMcs = WifiPhyRateService.maxMcs;

  /// Real-throughput efficiency vs PHY rate per standard (PWA TPUT_EFF).
  static const Map<WifiStd, double> eff = WifiPhyRateService.eff;

  /// Bandwidth options MHz per standard (PWA updateTputOptions bwOpts).
  static const Map<WifiStd, List<int>> bandwidths =
      WifiPhyRateService.bandwidths;

  /// Guard-interval option keys per standard, in display order. Keys index into
  /// [sym] (PWA updateTputOptions giOpts).
  static const Map<WifiStd, List<String>> giKeys = WifiPhyRateService.giKeys;

  /// Max spatial streams per standard, capped at 8 (PWA updateTputOptions maxSS).
  static const Map<WifiStd, int> maxStreams = WifiPhyRateService.maxStreams;

  /// PHY rate in Mbps, or null when the bandwidth / guard-interval combination
  /// is invalid for the standard or the MCS exceeds the standard's max — the
  /// PWA showError paths. (nsd · MCS_BPS[mcs] · ss) / sym.
  static double? phyRateMbps({
    required WifiStd std,
    required int bandwidthMHz,
    required int mcs,
    required int streams,
    required String giKey,
  }) =>
      WifiPhyRateService.phyRateMbps(
        std: std,
        bandwidthMHz: bandwidthMHz,
        mcs: mcs,
        streams: streams,
        giKey: giKey,
      );

  /// Estimated real throughput in Mbps — phyRate · efficiency(std). Null when
  /// the PHY rate is null (same invalid-combination guard).
  static double? realRateMbps({
    required WifiStd std,
    required int bandwidthMHz,
    required int mcs,
    required int streams,
    required String giKey,
  }) =>
      WifiPhyRateService.realRateMbps(
        std: std,
        bandwidthMHz: bandwidthMHz,
        mcs: mcs,
        streams: streams,
        giKey: giKey,
      );

  @override
  State<ThroughputCalcScreen> createState() => _ThroughputCalcScreenState();
}

class _ThroughputCalcScreenState extends State<ThroughputCalcScreen> {
  WifiStd _std = WifiStd.he; // PWA default (he selected).
  int _bandwidth = 20;
  int _mcs = 0;
  int _streams = 1;
  String _gi = '0.8';

  // ─── Handlers ─────────────────────────────────────────────────────────────

  /// Reclamp the dependent selections to the new standard's valid sets, keeping
  /// the prior choice where it still fits (PWA updateTputOptions behavior).
  void _onStdChanged(WifiStd std) {
    setState(() {
      _std = std;

      final List<int> bws = ThroughputCalcScreen.bandwidths[std]!;
      if (!bws.contains(_bandwidth)) _bandwidth = bws.first;

      final int max = ThroughputCalcScreen.maxMcs[std]!;
      if (_mcs > max) _mcs = max;

      final int maxSS = ThroughputCalcScreen.maxStreams[std]!;
      if (_streams > maxSS) _streams = maxSS;

      final List<String> gis = ThroughputCalcScreen.giKeys[std]!;
      if (!gis.contains(_gi)) _gi = gis.first;
    });
  }

  // ─── Formatting ─────────────────────────────────────────────────────────────

  /// PWA fmt(n, 1): fixed 1-decimal, "—" when not finite / null.
  static String _formatRate(double? n) {
    if (n == null || !n.isFinite) return '—';
    return n.toStringAsFixed(1);
  }

  /// Modulation label for the current MCS, or "—" when out of range.
  String get _modulation {
    if (_mcs < 0 || _mcs >= ThroughputCalcScreen.mcsMod.length) return '—';
    return ThroughputCalcScreen.mcsMod[_mcs];
  }

  /// Guard-interval display label (PWA giOpts label text).
  static String _giLabel(WifiStd std, String key) {
    final bool legacy = std == WifiStd.ht || std == WifiStd.vht;
    switch (key) {
      case '0.4':
        return '400 ns (Short GI)';
      case '0.8':
        return legacy ? '800 ns (Long GI)' : '0.8 µs';
      case '1.6':
        return '1.6 µs';
      case '3.2':
        return '3.2 µs';
    }
    return key;
  }

  static String _stdLabel(WifiStd std) {
    switch (std) {
      case WifiStd.ht:
        return 'Wi-Fi 4: 802.11n (HT)';
      case WifiStd.vht:
        return 'Wi-Fi 5: 802.11ac (VHT)';
      case WifiStd.he:
        return 'Wi-Fi 6 / 6E: 802.11ax (HE)';
      case WifiStd.eht:
        return 'Wi-Fi 7: 802.11be (EHT)';
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Throughput'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. The dependent-option
        // reclamp keeps the selection valid, so the rate is normally present;
        // disabled only on an invalid bandwidth/GI/MCS combination (no rate).
        // Copies the throughput breakdown as a labeled text block. Copy leads;
        // no help icon here.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            return Align(
              alignment: AppSpacing.calculatorVerticalAlignment(constraints),
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
                      // §8.6.2 concept-graphic header band — first child, above
                      // the input card. Self-collapses when no graphic is
                      // bundled, so the 24px gap below it disappears too.
                      ConceptGraphicBand(
                        toolId: 'throughput-calc',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('throughput-calc'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formulaCard(text, mono),
                      ToolHelpFooter(toolId: 'throughput-calc'),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// §8.16 copy payload — the throughput breakdown as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) only when the current standard /
  /// width / GI / MCS / streams combination yields no rate (the PWA showError
  /// path); the reclamp logic keeps the selection valid in normal use, so this
  /// is normally enabled. Selections, modulation, PHY rate, and real throughput
  /// match the on-screen result rows.
  String? _buildCopyText() {
    final double? phy = ThroughputCalcScreen.phyRateMbps(
      std: _std,
      bandwidthMHz: _bandwidth,
      mcs: _mcs,
      streams: _streams,
      giKey: _gi,
    );
    final double? real = ThroughputCalcScreen.realRateMbps(
      std: _std,
      bandwidthMHz: _bandwidth,
      mcs: _mcs,
      streams: _streams,
      giKey: _gi,
    );
    if (real == null || phy == null) return null;

    return (StringBuffer()
          ..writeln('Wi-Fi Throughput')
          ..writeln('Standard: ${_stdLabel(_std)}')
          ..writeln('Channel width: $_bandwidth MHz')
          ..writeln('MCS index: ${ThroughputCalcScreen.mcsLabel(_mcs)}')
          ..writeln('Spatial streams: $_streams')
          ..writeln('Guard interval: ${_giLabel(_std, _gi)}')
          ..writeln('Modulation: $_modulation')
          ..writeln('PHY rate: ${_formatRate(phy)} Mbps')
          ..writeln('Est. real throughput: ${_formatRate(real)} Mbps'))
        .toString()
        .trimRight();
  }

  Widget _inputCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stdSelector(),
          const SizedBox(height: AppSpacing.sm),
          _bandwidthSelector(),
          const SizedBox(height: AppSpacing.sm),
          _mcsSelector(),
          const SizedBox(height: AppSpacing.sm),
          _streamsSelector(),
          const SizedBox(height: AppSpacing.sm),
          _giSelector(),
          const SizedBox(height: AppSpacing.md),
          _resultRows(text, mono),
        ],
      ),
    );
  }

  Widget _stdSelector() {
    return LabeledField(
      label: 'Wi-Fi standard',
      field: AppSelect<WifiStd>(
        value: _std,
        semanticLabel: 'Wi-Fi standard',
        items: WifiStd.values.map((WifiStd s) => (s, _stdLabel(s))).toList(),
        onChanged: _onStdChanged,
      ),
    );
  }

  Widget _bandwidthSelector() {
    final List<int> bws = ThroughputCalcScreen.bandwidths[_std]!;
    return LabeledField(
      label: 'Channel width',
      field: AppSelect<int>(
        value: _bandwidth,
        semanticLabel: 'Channel width',
        items: bws.map((int b) => (b, '$b MHz')).toList(),
        onChanged: (int b) => setState(() => _bandwidth = b),
      ),
    );
  }

  Widget _mcsSelector() {
    final int max = ThroughputCalcScreen.maxMcs[_std]!;
    final List<AppSelectItem<int>> items = [
      for (int i = 0; i <= max; i++) (i, ThroughputCalcScreen.mcsLabel(i)),
    ];
    return LabeledField(
      label: 'MCS index',
      field: AppSelect<int>(
        value: _mcs,
        semanticLabel: 'MCS index',
        items: items,
        onChanged: (int m) => setState(() => _mcs = m),
      ),
    );
  }

  Widget _streamsSelector() {
    final int maxSS = ThroughputCalcScreen.maxStreams[_std]!;
    final List<AppSelectItem<int>> items = [
      for (int i = 1; i <= maxSS; i++) (i, '$i'),
    ];
    return LabeledField(
      label: 'Spatial streams',
      field: AppSelect<int>(
        value: _streams,
        semanticLabel: 'Spatial streams',
        items: items,
        onChanged: (int s) => setState(() => _streams = s),
      ),
    );
  }

  Widget _giSelector() {
    final List<String> keys = ThroughputCalcScreen.giKeys[_std]!;
    return LabeledField(
      label: 'Guard interval',
      field: AppSelect<String>(
        value: _gi,
        semanticLabel: 'Guard interval',
        items: keys.map((String k) => (k, _giLabel(_std, k))).toList(),
        onChanged: (String k) => setState(() => _gi = k),
      ),
    );
  }

  Widget _resultRows(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final double? phy = ThroughputCalcScreen.phyRateMbps(
      std: _std,
      bandwidthMHz: _bandwidth,
      mcs: _mcs,
      streams: _streams,
      giKey: _gi,
    );
    final double? real = ThroughputCalcScreen.realRateMbps(
      std: _std,
      bandwidthMHz: _bandwidth,
      mcs: _mcs,
      streams: _streams,
      giKey: _gi,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Modulation — supporting context for the rate (PWA tput-mod).
        _detailRow(text, mono, 'Modulation', _modulation),
        const SizedBox(height: AppSpacing.sm),
        // PHY rate — secondary numeric (PWA tput-phy).
        _detailRow(
          text,
          mono,
          'PHY rate',
          phy == null ? '—' : '${_formatRate(phy)} Mbps',
        ),
        const SizedBox(height: AppSpacing.md),
        // Estimated real throughput — the headline result (PWA tput-real).
        Text(
          'Est. real throughput',
          style: text.labelMedium?.copyWith(
            color: colors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // One SR node for the headline: "Est. real throughput: 720 Mbps" (or
        // "not calculated"), instead of value/unit fragments (Vera finding #6).
        Semantics(
          label: 'Estimated real throughput',
          value: real == null ? 'not calculated' : '${_formatRate(real)} Mbps',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SelectableText(
                _formatRate(real),
                style: mono.outputXL.copyWith(
                  color: real == null
                      ? colors.textTertiary
                      : colors.textAccent,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Mbps',
                style: text.labelLarge?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailRow(
    TextTheme text,
    AppMonoText mono,
    String label,
    String value,
  ) {
    final AppColorScheme colors = context.colors;
    final bool blank = value == '—';
    // One SR node per detail row: "PHY rate: 960 Mbps" (or "not calculated"),
    // instead of label and value fragments (Vera finding #6).
    return Semantics(
      label: label,
      value: blank ? 'not calculated' : value,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: mono.outputMedium.copyWith(
                color: blank ? colors.textTertiary : colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formulaCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Formula',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            'PHY = (Nsd × bits/symbol × streams) ÷ symbol time',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            'Real ≈ PHY × efficiency',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Nsd is data subcarriers (standard × width); bits/symbol is the '
            'MCS modulation and coding. Efficiency is an approximate real/PHY '
            'factor per standard (HT 0.70, VHT 0.72, HE 0.76, EHT 0.80).',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
