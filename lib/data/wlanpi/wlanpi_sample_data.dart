// WLAN Pi companion — SAMPLE / PLACEHOLDER data for the render scaffold.
//
// THIS IS NOT REAL DEVICE DATA. Every value here is a hand-authored placeholder
// so the profiler-result and system/network render scaffolds can be built and
// visually QA'd WITHOUT a device. The companion screens render this sample set
// until Monday's on-device spike wires the live [WlanPiSession] reads. Each
// screen shows a clear "Sample data — not from a device" banner whenever it is
// rendering from here.
//
// GL-005 / Truthfulness: this file exists precisely so we never fake a real
// device response. Sample data is labeled sample data, everywhere it surfaces.

import 'wlanpi_models.dart';

/// Placeholder device info for the system-status render scaffold.
const WlanPiDeviceInfo kSampleDeviceInfo = WlanPiDeviceInfo(
  model: 'WLAN Pi M4+',
  name: 'wlanpi-cda',
  hostname: 'wlanpi-cda.local',
  softwareVersion: 'WLAN Pi OS 3.2.2 (sample)',
  mode: 'classic',
);

/// Placeholder device stats for the system-status render scaffold.
const WlanPiDeviceStats kSampleDeviceStats = WlanPiDeviceStats(
  ip: '192.168.1.42',
  cpu: '7%',
  ram: '512 MB / 4 GB',
  disk: '6.1 GB / 32 GB',
  cpuTemp: '47.2°C',
  uptime: '3 days, 4 hours',
);

/// Placeholder decoded client capabilities for the PROFILER render scaffold —
/// the flagship view. Field VALUES are illustrative; field NAMES (the parse
/// keys) are confirmed Monday. Until then this drives the layout work only.
final ProfilerClientCapabilities kSampleProfilerCapabilities =
    ProfilerClientCapabilities.fromJson(const <String, dynamic>{
  'mac': 'aa:bb:cc:dd:ee:ff',
  'channel_width': 160,
  'spatial_streams': 2,
  'max_mcs': 11,
  'bands': <String>['2.4 GHz', '5 GHz', '6 GHz'],
  'dot11k': true,
  'dot11r': false,
  'dot11v': true,
  'dot11w': true,
  'wpa3': true,
});

/// A completed sample profiler run for the result scaffold.
final ProfilerResult kSampleProfilerResult = ProfilerResult(
  state: ProfilerRunState.complete,
  capabilities: kSampleProfilerCapabilities,
  message: 'Sample run — replace with a real profiler capture on Monday.',
);
