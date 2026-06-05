// WlanPiProfilerScreen — the FLAGSHIP render scaffold: decoded client
// capabilities (channel width / MCS / spatial streams / 802.11k/r/v/w / WPA3).
//
// EXPERIMENTAL / COMPANION MODE. This is the reason the mode exists — the fields
// iOS/macOS block. The LAYOUT is real and theme-aware; the DATA is sample data
// (clearly banner-labeled) until Monday wires the live profiler poll and the
// exact decoded capability field names are confirmed (see
// ProfilerClientCapabilities — the parse keys are the one Monday unknown).
//
// Tokens: GL-003 §8.1 surfaces, §4 spacing, §8.5 type, theme-aware context.colors.

import 'package:flutter/material.dart';

import '../../data/wlanpi/wlanpi_models.dart';
import '../../data/wlanpi/wlanpi_sample_data.dart';
import '../../theme/app_color_scheme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/centered_content.dart';

class WlanPiProfilerScreen extends StatelessWidget {
  const WlanPiProfilerScreen({
    super.key,
    this.result,
    this.useSampleData = false,
  });

  /// A live result, when one exists. When null and [useSampleData] is true, the
  /// screen renders the labeled sample.
  final ProfilerResult? result;
  final bool useSampleData;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final ProfilerResult shown =
        result ?? (useSampleData ? kSampleProfilerResult : _empty);

    return Scaffold(
      backgroundColor: colors.surface0,
      appBar: AppBar(title: const Text('Client capabilities')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: CenteredContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (useSampleData && result == null) _sampleBanner(colors),
                const SizedBox(height: AppSpacing.sm),
                _body(colors, shown),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const ProfilerResult _empty = ProfilerResult(state: ProfilerRunState.idle);

  Widget _body(AppColorScheme colors, ProfilerResult shown) {
    if (!shown.hasResult) {
      return _Card(
        colors: colors,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'No profiler result yet',
              style: TextStyle(
                fontSize: AppTextSize.body,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Start a profiler run on the WLAN Pi and associate a client to its '
              'profiler AP. The decoded capabilities appear here.',
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    final ProfilerClientCapabilities cap = shown.capabilities!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _headlineCard(colors, cap),
        const SizedBox(height: AppSpacing.sm),
        _featuresCard(colors, cap),
      ],
    );
  }

  Widget _headlineCard(AppColorScheme colors, ProfilerClientCapabilities cap) {
    return _Card(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Client ${_maskMac(cap.clientMac)}',
            style: TextStyle(
              fontSize: AppTextSize.body,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _metric(colors, 'Max channel width',
              cap.maxChannelWidthMhz == null ? '—' : '${cap.maxChannelWidthMhz} MHz'),
          _metric(colors, 'Spatial streams',
              cap.maxSpatialStreams?.toString() ?? '—'),
          _metric(colors, 'Max MCS', cap.maxMcs?.toString() ?? '—'),
          _metric(colors, 'Bands',
              cap.bands.isEmpty ? '—' : cap.bands.join(', ')),
        ],
      ),
    );
  }

  Widget _featuresCard(AppColorScheme colors, ProfilerClientCapabilities cap) {
    return _Card(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Roaming & security',
            style: TextStyle(
              fontSize: AppTextSize.body,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _flag(colors, '802.11k (neighbor reports)', cap.supports11k),
          _flag(colors, '802.11r (fast BSS transition)', cap.supports11r),
          _flag(colors, '802.11v (BSS transition mgmt)', cap.supports11v),
          _flag(colors, '802.11w (protected mgmt frames)', cap.supports11w),
          _flag(colors, 'WPA3 / SAE', cap.wpa3Sae),
        ],
      ),
    );
  }

  Widget _metric(AppColorScheme colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: colors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: AppTextSize.body,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _flag(AppColorScheme colors, String label, bool? supported) {
    final Color color = supported == null
        ? colors.textTertiary
        : (supported ? colors.statusSuccess : colors.textTertiary);
    final IconData icon = supported == null
        ? Icons.help_outline
        : (supported ? Icons.check_circle : Icons.remove_circle_outline);
    final String state =
        supported == null ? 'Unknown' : (supported ? 'Supported' : 'Not supported');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: colors.textSecondary,
              ),
            ),
          ),
          Text(
            state,
            style: TextStyle(
              fontSize: AppTextSize.caption,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sampleBanner(AppColorScheme colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.statusWarningFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.statusWarning),
      ),
      child: Text(
        'Sample data — not from a device. Capability field names are confirmed '
        'on Monday’s on-device spike.',
        style: TextStyle(
          fontSize: AppTextSize.caption,
          color: colors.statusWarning,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }

  /// MACs are semi-sensitive in shared screenshots — show OUI + masked tail.
  static String _maskMac(String mac) {
    final List<String> parts = mac.split(':');
    if (parts.length != 6) return mac;
    return '${parts[0]}:${parts[1]}:${parts[2]}:••:••:••';
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.colors, required this.child});

  final AppColorScheme colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}
