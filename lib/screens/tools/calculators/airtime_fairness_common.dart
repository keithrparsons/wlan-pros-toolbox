// Airtime Fairness (Wi-Fi Classroom) — pieces shared by the stage, the controls and
// the screen: the view enum, the editable client draft, number formatting, the
// takeaway sentence, and the card / title chrome.
//
// THEME: context.colors only (dark §8 / light §8.20).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/airtime_fairness_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

/// Which sharing rule the results show.
enum FairnessView {
  packet('Packet'),
  airtime('Airtime'),
  compare('Compare');

  const FairnessView(this.label);

  final String label;

  List<FairnessMode> get modes => switch (this) {
    FairnessView.packet => const <FairnessMode>[FairnessMode.packet],
    FairnessView.airtime => const <FairnessMode>[FairnessMode.airtime],
    FairnessView.compare => FairnessMode.values,
  };
}

/// One editable client row. [preset] null means a custom rate.
///
/// Mutable on purpose: the screen owns the list, the controls edit a draft
/// only through the screen's change callback, and the stage never sees a
/// draft, only the [ClientConfig]s built from it.
class AirtimeClientDraft {
  AirtimeClientDraft({
    required this.id,
    this.preset,
    this.customLegacy = false,
    this.aggregation = 1,
    String customText = '',
  }) : controller = TextEditingController(text: customText);

  final int id;
  RatePreset? preset;
  bool customLegacy;
  int aggregation;
  final TextEditingController controller;

  bool get legacy => preset?.family.isLegacy ?? customLegacy;

  double? get customRate => double.tryParse(controller.text.trim());

  /// Null when the row's rate is usable.
  String? get rateError {
    if (preset != null) return null;
    final double? r = customRate;
    if (r == null) return 'Enter a rate in Mbps';
    if (r < AirtimeConstants.minRateMbps || r > AirtimeConstants.maxRateMbps) {
      return 'Use 1 to 10,000 Mbps';
    }
    return null;
  }

  ClientConfig? toConfig() {
    if (rateError != null) return null;
    return ClientConfig(
      rateMbps: preset?.mbps ?? customRate!,
      legacy: legacy,
      aggregation: aggregation,
    );
  }
}

// ── Text ─────────────────────────────────────────────────────────────────────

/// Throughput in Mbps at a precision that reads well at every size.
String fmtMbps(double v) {
  if (v >= 1000) return v.toStringAsFixed(0);
  if (v >= 10) return v.toStringAsFixed(1);
  return v.toStringAsFixed(2);
}

/// A 0 to 1 fraction as a percentage.
String fmtPct(double f) {
  final double p = f * 100;
  if (p > 0 && p < 1) return '<1%';
  if (p >= 10) return '${p.round()}%';
  return '${p.toStringAsFixed(1)}%';
}

String fmtRate(double mbps) => mbps == mbps.roundToDouble()
    ? mbps.round().toString()
    : mbps.toStringAsFixed(1);

String rateText(ClientConfig c) =>
    '${fmtRate(c.rateMbps)} Mbps, '
    '${c.frames == 1 ? '1 frame' : '${c.frames} frames'}';

String fmtUs(double us) =>
    us >= 1000 ? '${(us / 1000).toStringAsFixed(2)} ms' : '${us.round()} µs';

/// The takeaway line, computed from both results so it can compare.
String airtimeTakeaway(
  FairnessResult packet,
  FairnessResult airtime,
  FairnessView view,
) {
  final List<ClientResult> p = packet.clients;
  final List<ClientResult> a = airtime.clients;
  final int n = p.length;
  String who(ClientResult c) =>
      'client ${clientLetter(c.index)} (${fmtRate(c.config.rateMbps)} Mbps)';

  if (n == 1) {
    final ClientResult c = p.first;
    return 'One client has the air to itself, so both rules give it '
        '${fmtMbps(c.throughputMbps)} Mbps, '
        '${fmtPct(c.throughputMbps / c.config.rateMbps)} of its PHY rate.';
  }

  final double t0 = p.first.airtimePerTxUs;
  final bool sameTurns = p.every(
    (ClientResult c) => (c.airtimePerTxUs - t0).abs() <= 1e-6 * t0,
  );
  if (sameTurns) {
    return 'Every client needs the same time per turn, so both rules agree: '
        '${fmtPct(1 / n)} of the air each and '
        '${fmtMbps(packet.aggregateMbps)} Mbps in total.';
  }

  // The client whose turn is longest holds the most air under packet fairness.
  ClientResult hog = p.first;
  for (final ClientResult c in p) {
    if (c.airtimePerTxUs > hog.airtimePerTxUs) hog = c;
  }
  // The fastest other client.
  ClientResult fast = p.firstWhere((ClientResult c) => c.index != hog.index);
  for (final ClientResult c in p) {
    if (c.index != hog.index && c.config.rateMbps > fast.config.rateMbps) {
      fast = c;
    }
  }
  final bool sameFrames = p.every(
    (ClientResult c) => c.config.frames == p.first.config.frames,
  );

  final String gets = sameFrames
      ? 'so every client gets ${fmtMbps(fast.throughputMbps)} Mbps'
      : 'and ${who(fast)} gets ${fmtMbps(fast.throughputMbps)} Mbps';
  final String packetLine =
      'Packet fairness: ${who(hog)} holds ${fmtPct(hog.airtimeShare)} of '
      'the air, $gets.';
  final double pt = packet.aggregateMbps;
  final double at = airtime.aggregateMbps;
  final String airtimeLine =
      'Airtime fairness: ${fmtPct(1 / n)} of the air each, '
      'client ${clientLetter(fast.index)} gets '
      '${fmtMbps(a[fast.index].throughputMbps)} Mbps and '
      'client ${clientLetter(hog.index)} gets '
      '${fmtMbps(a[hog.index].throughputMbps)} Mbps.';
  final String totals =
      'The total ${at >= pt ? 'rises' : 'falls'} from ${fmtMbps(pt)} to '
      '${fmtMbps(at)} Mbps.';

  return switch (view) {
    FairnessView.packet => '$packetLine Total ${fmtMbps(pt)} Mbps.',
    FairnessView.airtime => '$airtimeLine Total ${fmtMbps(at)} Mbps.',
    FairnessView.compare => '$packetLine $airtimeLine $totals',
  };
}

// ── Chrome ───────────────────────────────────────────────────────────────────

/// A §8.1 card: surface 1, card radius, decorative border.
class LabCard extends StatelessWidget {
  const LabCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}

/// A card's section title, announced as a header.
class LabSectionTitle extends StatelessWidget {
  const LabSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: context.colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

TextStyle labLabelStyle(BuildContext context) =>
    Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: context.colors.textSecondary) ??
    TextStyle(color: context.colors.textSecondary);
