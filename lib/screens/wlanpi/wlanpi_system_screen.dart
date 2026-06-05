// WlanPiSystemScreen — system + network status render scaffold.
//
// EXPERIMENTAL / COMPANION MODE. Renders `system/device/info`,
// `system/device/stats`, and `network/info` data. The LAYOUT and the typed
// models are real (source-accurate from wlanpi-core schemas); the DATA is
// sample data (clearly labeled) until Monday wires the live authenticated reads.
//
// Tokens: GL-003 §8.1 surfaces, §4 spacing, §8.5 type, theme-aware context.colors.

import 'package:flutter/material.dart';

import '../../data/wlanpi/wlanpi_models.dart';
import '../../data/wlanpi/wlanpi_sample_data.dart';
import '../../theme/app_color_scheme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/centered_content.dart';

class WlanPiSystemScreen extends StatelessWidget {
  const WlanPiSystemScreen({
    super.key,
    this.deviceInfo,
    this.deviceStats,
    this.useSampleData = false,
  });

  final WlanPiDeviceInfo? deviceInfo;
  final WlanPiDeviceStats? deviceStats;
  final bool useSampleData;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool sample = useSampleData && deviceInfo == null && deviceStats == null;
    final WlanPiDeviceInfo? info =
        deviceInfo ?? (useSampleData ? kSampleDeviceInfo : null);
    final WlanPiDeviceStats? stats =
        deviceStats ?? (useSampleData ? kSampleDeviceStats : null);

    return Scaffold(
      backgroundColor: colors.surface0,
      appBar: AppBar(title: const Text('System & network')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: CenteredContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (sample) _sampleBanner(colors),
                const SizedBox(height: AppSpacing.sm),
                if (info != null) _deviceCard(colors, info),
                if (info != null) const SizedBox(height: AppSpacing.sm),
                if (stats != null) _statsCard(colors, stats),
                if (info == null && stats == null) _emptyCard(colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _deviceCard(AppColorScheme colors, WlanPiDeviceInfo info) {
    return _Card(
      colors: colors,
      title: 'Device',
      rows: <MapEntry<String, String>>[
        MapEntry<String, String>('Model', info.model),
        MapEntry<String, String>('Hostname', info.hostname),
        MapEntry<String, String>('Name', info.name),
        MapEntry<String, String>('Software', info.softwareVersion),
        MapEntry<String, String>('Mode', info.mode),
      ],
    );
  }

  Widget _statsCard(AppColorScheme colors, WlanPiDeviceStats stats) {
    return _Card(
      colors: colors,
      title: 'Stats',
      rows: <MapEntry<String, String>>[
        MapEntry<String, String>('IP', stats.ip),
        MapEntry<String, String>('CPU', stats.cpu),
        MapEntry<String, String>('RAM', stats.ram),
        MapEntry<String, String>('Disk', stats.disk),
        MapEntry<String, String>('CPU temp', stats.cpuTemp),
        MapEntry<String, String>('Uptime', stats.uptime),
      ],
    );
  }

  Widget _emptyCard(AppColorScheme colors) {
    return _Card(
      colors: colors,
      title: 'Not connected',
      rows: const <MapEntry<String, String>>[],
      empty: 'Connect to a WLAN Pi to read its system and network status.',
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
        'Sample data — not from a device. Live reads land Monday.',
        style: TextStyle(
          fontSize: AppTextSize.caption,
          color: colors.statusWarning,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.colors,
    required this.title,
    required this.rows,
    this.empty,
  });

  final AppColorScheme colors;
  final String title;
  final List<MapEntry<String, String>> rows;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: AppTextSize.body,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          if (empty != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              empty!,
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          if (rows.isNotEmpty) const SizedBox(height: AppSpacing.sm),
          for (final MapEntry<String, String> r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 110,
                    child: Text(
                      r.key,
                      style: TextStyle(
                        fontSize: AppTextSize.caption,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.value,
                      style: TextStyle(
                        fontSize: AppTextSize.body,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
