// Non-Wi-Fi Wireless Channels — read-only channel/frequency reference for the
// common non-Wi-Fi radios that share (or sit beside) the bands a Wi-Fi pro
// works in: LoRaWAN, IEEE 802.15.4, Bluetooth Classic, Bluetooth LE, and
// Zigbee.
//
// All data is sourced ONLY from Pax's verified research brief
// (Deliverables/2026-06-02-wireless-channels-reference/data-brief.md): primary
// standards (LoRa Alliance RP002, IEEE 802.15.4, Bluetooth SIG Core Spec,
// CSA/Zigbee) cross-checked against secondary sources. Per GL-005 nothing is
// fabricated:
//   - frequency RANGES are shown (the headline fact);
//   - channel COUNTS are labelled "region-dependent" where the brief flags it;
//   - UNCERTAIN regions (LoRaWAN CN470/CN779/RU864) are marked "verify";
//   - BLE uses the brief's PIECEWISE channel→frequency mapping, NOT a naive
//     linear formula — the 3 advertising channels (37/38/39 = 2402/2426/2480
//     MHz) are interleaved among the data channels (the common BLE chart bug).
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// bundled compile-time const datasets always render. No loading / empty / error
// path because nothing is fetched or parsed at runtime (GL-008 network /
// subprocess rules do not apply — nothing to fabricate, nothing to shell out
// to).
//
// Pattern: matches poe_reference_screen / wifi_channels_screen — Scaffold +
// AppBar (toolbarHeight 64), SafeArea(top: false), LayoutBuilder isDesktop @720,
// ConstrainedBox to calculatorMaxWidth, SingleChildScrollView, cards from
// app_tokens / app_typography, AppCopyAction (§8.16). Wide tables reuse the
// shared HorizontalScrollTable + IntrinsicWidth fixed-cell idiom so they never
// RenderFlex-overflow on a 320pt phone.
//
// Glyph note: ASCII hyphen-minus only in prose; no em dash. "802.15.4" /
// "802.11" never the "x" form.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One LoRaWAN regional frequency plan. Channel counts/layout are entirely
/// region-defined, so the headline fact is the range + default channels; the
/// `verify` flag marks the UNCERTAIN/version-dependent plans (CN470 version-
/// dependent; CN779/RU864 sparsely sourced) per the brief.
@immutable
class LoraWanPlan {
  const LoraWanPlan({
    required this.plan,
    required this.rangeMhz,
    required this.channels,
    this.verify = false,
  });

  /// Region plan label, e.g. "EU868", "US915".
  final String plan;

  /// Frequency range in MHz, e.g. "863-870".
  final String rangeMhz;

  /// Channel-plan basics (defaults + counts) in the brief's words.
  final String channels;

  /// True for region plans the brief flags UNCERTAIN / version-dependent. These
  /// render with a "verify" chip and are never presented as authoritative.
  final bool verify;
}

/// One IEEE 802.15.4 band. The 868/915 MHz bands are region-restricted; the
/// 2.4 GHz channels 11-26 are global.
@immutable
class Ieee802154Band {
  const Ieee802154Band({
    required this.band,
    required this.channels,
    required this.spacing,
    required this.centers,
    required this.region,
  });

  /// Band label, e.g. "2.4 GHz".
  final String band;

  /// Channel-number range, e.g. "11-26".
  final String channels;

  /// Channel spacing, e.g. "5 MHz" (or "-" for the single 868 MHz channel).
  final String spacing;

  /// Center-frequency summary, e.g. "2405-2480 MHz".
  final String centers;

  /// Region applicability, e.g. "Worldwide" or "Europe".
  final String region;
}

/// One Bluetooth LE channel. The index→frequency mapping is NON-LINEAR: the 3
/// advertising channels (37/38/39) are interleaved among the 37 data channels.
/// Each row stores the explicit verified frequency from the brief's piecewise
/// lookup — no formula is applied at render time.
@immutable
class BleChannel {
  const BleChannel({
    required this.index,
    required this.freqMhz,
    required this.kind,
  });

  /// BLE channel index (0-39).
  final int index;

  /// Center frequency in MHz (verified, piecewise — not computed live).
  final int freqMhz;

  /// "Advertising" or "Data".
  final String kind;
}

class NonWifiChannelsScreen extends StatelessWidget {
  const NonWifiChannelsScreen({super.key});

  // ── LoRaWAN (LoRa Alliance RP002 Regional Parameters) ──────────────────────

  /// What LoRaWAN is for (app copy, from the brief).
  static const String loraWanUse =
      'Low-power wide-area networking (LPWAN): battery sensors and trackers '
      'sending small payloads over kilometers, often years on one battery. '
      'LoRa is the PHY (chirp spread spectrum); LoRaWAN is the network layer.';

  /// LoRaWAN regional plans. Verified plans shipped; CN470/CN779/RU864 flagged
  /// `verify` per the brief (version-dependent or sparsely sourced). Channel
  /// widths are 125 kHz (some 250/500 kHz). Region-dependent is the headline.
  static const List<LoraWanPlan> loraWanPlans = [
    LoraWanPlan(
      plan: 'EU868',
      rangeMhz: '863-870',
      channels: '3 default join channels 868.1 / 868.3 / 868.5 MHz (125 kHz); '
          'up to ~16, duty-cycle limited',
    ),
    LoraWanPlan(
      plan: 'US915',
      rangeMhz: '902-928',
      channels: '64 × 125 kHz uplink (ch 0-63) + 8 × 500 kHz uplink (ch 64-71) '
          '+ 8 × 500 kHz downlink',
    ),
    LoraWanPlan(
      plan: 'AU915',
      rangeMhz: '915-928',
      channels: '72 channels: 64 × 125 kHz + 8 × 500 kHz, 8 sub-bands '
          '(same structure as US915)',
    ),
    LoraWanPlan(
      plan: 'AS923',
      rangeMhz: '~915-928',
      channels: '2 default channels 923.2 / 923.4 MHz (AS923-1); up to 16; '
          'four offset variants (AS923-1..4)',
    ),
    LoraWanPlan(
      plan: 'IN865',
      rangeMhz: '865-867',
      channels: '3 default channels 865.0625 / 865.4025 / 865.985 MHz '
          '(125 kHz)',
    ),
    LoraWanPlan(
      plan: 'KR920',
      rangeMhz: '917-923.5',
      channels: 'Default channels in 922.1-923.3 MHz; listen-before-talk '
          'required',
    ),
    LoraWanPlan(
      plan: 'CN470',
      rangeMhz: '470-510',
      channels: 'Up to 96 × 125 kHz uplink; count varies by RP002 revision',
      verify: true,
    ),
    LoraWanPlan(
      plan: 'CN779',
      rangeMhz: '779-787',
      channels: '3 default channels 779.5 / 779.7 / 779.9 MHz; '
          'deprecated/limited',
      verify: true,
    ),
    LoraWanPlan(
      plan: 'RU864',
      rangeMhz: '864-870',
      channels: '2 default channels 868.9 / 869.1 MHz',
      verify: true,
    ),
  ];

  static const String loraWanFootnote =
      'LoRaWAN frequency plan, channel count, and layout are entirely region-'
      'defined — there is no global LoRaWAN channel map. Source: LoRa Alliance '
      'RP002 Regional Parameters. Plans marked "verify" are version-dependent '
      'or sparsely sourced (CN470/CN779/RU864) — confirm against RP002 §2 and '
      'the local regulator before use.';

  // ── IEEE 802.15.4 ──────────────────────────────────────────────────────────

  /// What 802.15.4 is for (app copy).
  static const String ieee802154Use =
      'The low-rate wireless PAN (LR-WPAN) PHY/MAC under Zigbee, Thread, '
      'Matter-over-Thread, WirelessHART, and 6LoWPAN. 27 channels across three '
      'bands.';

  /// IEEE 802.15.4 bands. Verified verbatim against the standard formula:
  /// ch 0 = 868.3 MHz; ch 1-10 = 906 + 2·(k-1); ch 11-26 = 2405 + 5·(k-11).
  static const List<Ieee802154Band> ieee802154Bands = [
    Ieee802154Band(
      band: '868 MHz',
      channels: '0',
      spacing: '-',
      centers: '868.3 MHz',
      region: 'Europe',
    ),
    Ieee802154Band(
      band: '915 MHz',
      channels: '1-10',
      spacing: '2 MHz',
      centers: '906-924 MHz',
      region: 'Americas / Australia',
    ),
    Ieee802154Band(
      band: '2.4 GHz',
      channels: '11-26',
      spacing: '5 MHz',
      centers: '2405-2480 MHz',
      region: 'Worldwide',
    ),
  ];

  static const String ieee802154Footnote =
      'Center frequency: ch 0 = 868.3 MHz; ch 1-10 = 906 + 2 × (ch − 1) MHz; '
      'ch 11-26 = 2405 + 5 × (ch − 11) MHz. The 868 and 915 MHz bands are '
      'region-restricted; the 2.4 GHz channels 11-26 are global. Source: IEEE '
      'Std 802.15.4.';

  // ── Bluetooth Classic (BR/EDR) ──────────────────────────────────────────────

  /// What Bluetooth Classic is for (app copy).
  static const String bluetoothClassicUse =
      'Classic Bluetooth for audio streaming (A2DP headphones/speakers) and '
      'legacy serial/data links. Adaptive frequency hopping across the 2.4 GHz '
      'ISM band.';

  /// Bluetooth Classic facts (BR/EDR). Verified: 79 channels, 1 MHz spacing,
  /// f = 2402 + k MHz (k = 0..78), 2402-2480 MHz, global.
  static const List<(String, String)> bluetoothClassicFacts = [
    ('Channels', '79'),
    ('Spacing', '1 MHz'),
    ('Formula', 'f = 2402 + k MHz (k = 0-78)'),
    ('Range', '2402-2480 MHz (2.4 GHz ISM)'),
    ('Hopping', '~1600 hops/sec (adaptive)'),
    ('Region', 'Global — same channels worldwide'),
  ];

  // ── Bluetooth LE ────────────────────────────────────────────────────────────

  /// What BLE is for (app copy).
  static const String bleUse =
      'Low-power Bluetooth for wearables, beacons, sensors, and device '
      'pairing/discovery. 40 channels (3 advertising + 37 data), 2 MHz '
      'spacing, across 2402-2480 MHz.';

  /// BLE channels in PHYSICAL-FREQUENCY order (low→high), with the explicit
  /// verified frequency for each index. The mapping is non-linear: the 3
  /// advertising channels (37/38/39) interleave among the data channels to dodge
  /// the non-overlapping Wi-Fi channels 1/6/11. Stored as an explicit lookup —
  /// NO naive "2402 + 2·index" formula (the common BLE chart bug, per brief).
  ///   adv 37 = 2402 · data 0-10 = 2404 + 2·index · adv 38 = 2426 ·
  ///   data 11-36 = 2406 + 2·index · adv 39 = 2480.
  static const List<BleChannel> bleChannels = [
    BleChannel(index: 37, freqMhz: 2402, kind: 'Advertising'),
    BleChannel(index: 0, freqMhz: 2404, kind: 'Data'),
    BleChannel(index: 1, freqMhz: 2406, kind: 'Data'),
    BleChannel(index: 2, freqMhz: 2408, kind: 'Data'),
    BleChannel(index: 3, freqMhz: 2410, kind: 'Data'),
    BleChannel(index: 4, freqMhz: 2412, kind: 'Data'),
    BleChannel(index: 5, freqMhz: 2414, kind: 'Data'),
    BleChannel(index: 6, freqMhz: 2416, kind: 'Data'),
    BleChannel(index: 7, freqMhz: 2418, kind: 'Data'),
    BleChannel(index: 8, freqMhz: 2420, kind: 'Data'),
    BleChannel(index: 9, freqMhz: 2422, kind: 'Data'),
    BleChannel(index: 10, freqMhz: 2424, kind: 'Data'),
    BleChannel(index: 38, freqMhz: 2426, kind: 'Advertising'),
    BleChannel(index: 11, freqMhz: 2428, kind: 'Data'),
    BleChannel(index: 12, freqMhz: 2430, kind: 'Data'),
    BleChannel(index: 13, freqMhz: 2432, kind: 'Data'),
    BleChannel(index: 14, freqMhz: 2434, kind: 'Data'),
    BleChannel(index: 15, freqMhz: 2436, kind: 'Data'),
    BleChannel(index: 16, freqMhz: 2438, kind: 'Data'),
    BleChannel(index: 17, freqMhz: 2440, kind: 'Data'),
    BleChannel(index: 18, freqMhz: 2442, kind: 'Data'),
    BleChannel(index: 19, freqMhz: 2444, kind: 'Data'),
    BleChannel(index: 20, freqMhz: 2446, kind: 'Data'),
    BleChannel(index: 21, freqMhz: 2448, kind: 'Data'),
    BleChannel(index: 22, freqMhz: 2450, kind: 'Data'),
    BleChannel(index: 23, freqMhz: 2452, kind: 'Data'),
    BleChannel(index: 24, freqMhz: 2454, kind: 'Data'),
    BleChannel(index: 25, freqMhz: 2456, kind: 'Data'),
    BleChannel(index: 26, freqMhz: 2458, kind: 'Data'),
    BleChannel(index: 27, freqMhz: 2460, kind: 'Data'),
    BleChannel(index: 28, freqMhz: 2462, kind: 'Data'),
    BleChannel(index: 29, freqMhz: 2464, kind: 'Data'),
    BleChannel(index: 30, freqMhz: 2466, kind: 'Data'),
    BleChannel(index: 31, freqMhz: 2468, kind: 'Data'),
    BleChannel(index: 32, freqMhz: 2470, kind: 'Data'),
    BleChannel(index: 33, freqMhz: 2472, kind: 'Data'),
    BleChannel(index: 34, freqMhz: 2474, kind: 'Data'),
    BleChannel(index: 35, freqMhz: 2476, kind: 'Data'),
    BleChannel(index: 36, freqMhz: 2478, kind: 'Data'),
    BleChannel(index: 39, freqMhz: 2480, kind: 'Advertising'),
  ];

  static const String bleFootnote =
      'Channel rows are in physical-frequency order. The index→frequency map is '
      'non-linear: the 3 advertising channels 37/38/39 (2402 / 2426 / 2480 '
      'MHz) interleave among the data channels to sit beside the non-'
      'overlapping Wi-Fi channels 1/6/11. Source: Bluetooth SIG Core Spec. '
      'Region: global.';

  // ── Zigbee ──────────────────────────────────────────────────────────────────

  /// What Zigbee is for (app copy).
  static const String zigbeeUse =
      'Mesh networking for home automation and industrial sensors (lights, '
      'locks, thermostats). Zigbee is an application/network stack that runs on '
      'the IEEE 802.15.4 PHY — it does not define its own channels.';

  static const List<(String, String)> zigbeeFacts = [
    ('2.4 GHz band', '802.15.4 ch 11-26 (2405-2480 MHz, 5 MHz spacing) — '
        '16 channels, worldwide'),
    ('Sub-GHz', '868 MHz (ch 0, Europe) and 902-928 MHz (ch 1-10, Americas) — '
        'lower rate, region-restricted'),
    ('Common 2.4 GHz picks', '11, 15, 20, 25, 26 (convention, not a mandate) — '
        'chosen to avoid the busiest Wi-Fi channels'),
  ];

  static const String zigbeeFootnote =
      'Zigbee = IEEE 802.15.4 PHY; the 2.4 GHz channels 11-26 are global, the '
      'sub-GHz bands are region-restricted. The "common picks" list is a widely-'
      'repeated convention (CSA/vendor guidance varies), not a standards '
      'requirement. Source: CSA/Zigbee spec + IEEE 802.15.4.';

  static const String _toolId = 'non-wifi-channels';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Non-Wi-Fi Wireless Channels'),
        toolbarHeight: 64,
        // §8.16 order: copy LEADS, help TRAILS.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
          ToolHelpAction(toolId: 'non-wifi-channels'),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — every technology's channel data as a sectioned TSV.
  /// Static data, so copy is always enabled. Each technology is its own section
  /// carrying its "what it's used for" line so the meaning survives the copy.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Non-Wi-Fi Wireless Channels');

    buf
      ..writeln()
      ..writeln('LoRaWAN (LoRa Alliance RP002)')
      ..writeln(loraWanUse)
      ..writeln(<String>['Region plan', 'Range MHz', 'Channel plan'].join(tab));
    for (final LoraWanPlan p in loraWanPlans) {
      buf.writeln(
        <String>[
          p.verify ? '${p.plan} (verify)' : p.plan,
          p.rangeMhz,
          p.channels,
        ].join(tab),
      );
    }
    buf.writeln(loraWanFootnote);

    buf
      ..writeln()
      ..writeln('IEEE 802.15.4')
      ..writeln(ieee802154Use)
      ..writeln(
        <String>['Band', 'Channels', 'Spacing', 'Centers', 'Region'].join(tab),
      );
    for (final Ieee802154Band b in ieee802154Bands) {
      buf.writeln(
        <String>[b.band, b.channels, b.spacing, b.centers, b.region].join(tab),
      );
    }
    buf.writeln(ieee802154Footnote);

    buf
      ..writeln()
      ..writeln('Bluetooth Classic (BR/EDR)')
      ..writeln(bluetoothClassicUse)
      ..writeln(<String>['Fact', 'Value'].join(tab));
    for (final (String k, String v) in bluetoothClassicFacts) {
      buf.writeln(<String>[k, v].join(tab));
    }

    buf
      ..writeln()
      ..writeln('Bluetooth LE')
      ..writeln(bleUse)
      ..writeln(<String>['Index', 'Freq MHz', 'Kind'].join(tab));
    for (final BleChannel c in bleChannels) {
      buf.writeln(<String>['${c.index}', '${c.freqMhz}', c.kind].join(tab));
    }
    buf.writeln(bleFootnote);

    buf
      ..writeln()
      ..writeln('Zigbee')
      ..writeln(zigbeeUse)
      ..writeln(<String>['Fact', 'Value'].join(tab));
    for (final (String k, String v) in zigbeeFacts) {
      buf.writeln(<String>[k, v].join(tab));
    }
    buf.writeln(zigbeeFootnote);

    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
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
                  ConceptGraphicBand(toolId: _toolId, isDesktop: isDesktop),
                  if (ToolAssets.hasGraphic(_toolId))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(text),
                  const SizedBox(height: AppSpacing.md),
                  _loraWanCard(text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _ieee802154Card(text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _factCard(
                    text: text,
                    mono: mono,
                    title: 'Bluetooth Classic (BR/EDR)',
                    use: bluetoothClassicUse,
                    facts: bluetoothClassicFacts,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _bleCard(text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _factCard(
                    text: text,
                    mono: mono,
                    title: 'Zigbee',
                    use: zigbeeUse,
                    facts: zigbeeFacts,
                    footnote: zigbeeFootnote,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _introCard(TextTheme text) {
    return _Card(
      heading: 'About',
      headingText: text,
      child: Text(
        'Channel and frequency reference for the common non-Wi-Fi radios in '
        'and around the bands a Wi-Fi pro works in. Bluetooth, BLE, and '
        '802.15.4 use globally fixed channel grids; LoRaWAN frequency plans are '
        'region-dependent. Verify local regulator rules and transmit-power '
        'limits before deployment.',
        style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
      ),
    );
  }

  Widget _loraWanCard(TextTheme text, AppMonoText mono) {
    return _Card(
      heading: 'LoRaWAN',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UseLine(text: loraWanUse),
          const SizedBox(height: AppSpacing.sm),
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      _HeaderCell('Plan', width: 88),
                      _HeaderCell('Range MHz', width: 104),
                      _HeaderCell('Channel plan', width: 280),
                    ],
                  ),
                  const Divider(
                    color: AppColors.border,
                    height: AppSpacing.sm,
                  ),
                  for (final LoraWanPlan p in loraWanPlans)
                    _loraWanRow(text, mono, p),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            loraWanFootnote,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _loraWanRow(TextTheme text, AppMonoText mono, LoraWanPlan p) {
    return ReferenceRowSemantics(
      label: rowLabel(p.plan, <String?>[
        p.verify ? 'verify — region-dependent or version-dependent' : null,
        'range ${p.rangeMhz} megahertz',
        p.channels,
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.plan,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (p.verify) ...[
                    const SizedBox(height: 2),
                    const _Chip(
                      'verify',
                      color: AppColors.statusWarning,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: 104,
              child: Text(
                p.rangeMhz,
                style: mono.inlineCode.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 280,
              child: Text(
                p.channels,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ieee802154Card(TextTheme text, AppMonoText mono) {
    return _Card(
      heading: 'IEEE 802.15.4',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UseLine(text: ieee802154Use),
          const SizedBox(height: AppSpacing.sm),
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      _HeaderCell('Band', width: 72),
                      _HeaderCell('Ch', width: 64),
                      _HeaderCell('Spacing', width: 72),
                      _HeaderCell('Centers', width: 120),
                      _HeaderCell('Region', width: 160),
                    ],
                  ),
                  const Divider(
                    color: AppColors.border,
                    height: AppSpacing.sm,
                  ),
                  for (final Ieee802154Band b in ieee802154Bands)
                    _ieee802154Row(text, mono, b),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            ieee802154Footnote,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _ieee802154Row(TextTheme text, AppMonoText mono, Ieee802154Band b) {
    return ReferenceRowSemantics(
      label: rowLabel('${b.band} band', <String?>[
        'channels ${b.channels}',
        b.spacing == '-' ? null : 'spacing ${b.spacing}',
        'centers ${b.centers}',
        'region ${b.region}',
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(
                b.band,
                style: mono.inlineCode.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                b.channels,
                style: mono.inlineCode.copyWith(color: AppColors.primary),
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                b.spacing,
                style: mono.inlineCode.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                b.centers,
                style: mono.inlineCode.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 160,
              child: Text(
                b.region,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bleCard(TextTheme text, AppMonoText mono) {
    return _Card(
      heading: 'Bluetooth LE',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UseLine(text: bleUse),
          const SizedBox(height: AppSpacing.sm),
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      _HeaderCell('Index', width: 56),
                      _HeaderCell('Freq MHz', width: 88),
                      _HeaderCell('Kind', width: 120),
                    ],
                  ),
                  const Divider(
                    color: AppColors.border,
                    height: AppSpacing.sm,
                  ),
                  for (final BleChannel c in bleChannels) _bleRow(text, mono, c),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            bleFootnote,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _bleRow(TextTheme text, AppMonoText mono, BleChannel c) {
    final bool adv = c.kind == 'Advertising';
    return ReferenceRowSemantics(
      label: rowLabel('Index ${c.index}', <String?>[
        '${c.freqMhz} megahertz',
        c.kind,
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 56,
              child: Text(
                '${c.index}',
                style: mono.inlineCode.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              width: 88,
              child: Text(
                '${c.freqMhz}',
                style: mono.inlineCode.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                // Advertising channels get the primary-tinted chip; data
                // channels read as a neutral label (never color-only, §8.13).
                child: adv
                    ? const _Chip('Advertising', color: AppColors.primary)
                    : Text(
                        c.kind,
                        style: text.labelMedium?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A simple two-column key/value fact card (Bluetooth Classic, Zigbee): each
  /// fact is a label column + a value that wraps; no fixed-width cells, so no
  /// horizontal overflow on a narrow phone.
  Widget _factCard({
    required TextTheme text,
    required AppMonoText mono,
    required String title,
    required String use,
    required List<(String, String)> facts,
    String? footnote,
  }) {
    return _Card(
      heading: title,
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UseLine(text: use),
          const SizedBox(height: AppSpacing.sm),
          ...facts.asMap().entries.expand((entry) {
            final (String key, String value) = entry.value;
            return [
              if (entry.key > 0)
                const Divider(color: AppColors.border, height: AppSpacing.sm),
              ReferenceRowSemantics(
                label: rowLabel(key, <String?>[value]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 128,
                        child: Text(
                          key,
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
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ];
          }),
          if (footnote != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              footnote,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One "what it's used for" line under a technology heading.
class _UseLine extends StatelessWidget {
  const _UseLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: t.labelMedium?.copyWith(color: AppColors.textSecondary),
    );
  }
}

/// Shared surface-1 card with a heading, matching the dB / PoE / fiber idiom.
class _Card extends StatelessWidget {
  const _Card({
    required this.heading,
    required this.headingText,
    required this.child,
  });

  final String heading;
  final TextTheme headingText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
            heading,
            style: headingText.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

/// One column-header label, caption-styled to align with the data cells.
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

/// A small affordance chip — tinted fill + bordered, label always present so it
/// is never color-only (§8.13). Used for the LoRaWAN "verify" flag and the BLE
/// advertising-channel marker.
class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
