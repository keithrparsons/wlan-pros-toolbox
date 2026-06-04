// DeviceInfoFormat unit tests — the memory + uptime formatters and their honest
// null handling (Batch 6).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/device_info_format.dart';

void main() {
  group('formatBytes', () {
    test('whole-GiB RAM reads as a clean GB value', () {
      expect(DeviceInfoFormat.formatBytes(8 * 1024 * 1024 * 1024), '8 GB');
      expect(DeviceInfoFormat.formatBytes(16 * 1024 * 1024 * 1024), '16 GB');
      expect(DeviceInfoFormat.formatBytes(6 * 1024 * 1024 * 1024), '6 GB');
    });

    test('non-whole GiB keeps one decimal', () {
      // 1.5 GiB
      expect(
        DeviceInfoFormat.formatBytes((1.5 * 1024 * 1024 * 1024).round()),
        '1.5 GB',
      );
    });

    test('sub-GiB scales down to MB / KB / B', () {
      expect(DeviceInfoFormat.formatBytes(512 * 1024 * 1024), '512 MB');
      expect(DeviceInfoFormat.formatBytes(256 * 1024), '256 KB');
      expect(DeviceInfoFormat.formatBytes(900), '900 B');
    });

    test('TiB-scale values use TB', () {
      expect(DeviceInfoFormat.formatBytes(2 * 1024 * 1024 * 1024 * 1024),
          '2 TB');
    });

    test('null / zero / negative → null (honest unavailable)', () {
      expect(DeviceInfoFormat.formatBytes(null), isNull);
      expect(DeviceInfoFormat.formatBytes(0), isNull);
      expect(DeviceInfoFormat.formatBytes(-1), isNull);
    });
  });

  group('formatUptime', () {
    test('days + hours + minutes', () {
      // 3d 4h 12m = 3*86400 + 4*3600 + 12*60 = 274320
      expect(DeviceInfoFormat.formatUptime(274320), '3d 4h 12m');
    });

    test('hours + minutes (no days) drops the days unit', () {
      // 1h 15m = 4500s
      expect(DeviceInfoFormat.formatUptime(4500), '1h 15m');
    });

    test('minutes only (under an hour) shows just minutes', () {
      expect(DeviceInfoFormat.formatUptime(600), '10m');
    });

    test('just booted reads 0m, never empty', () {
      expect(DeviceInfoFormat.formatUptime(30), '0m');
      expect(DeviceInfoFormat.formatUptime(0), '0m');
    });

    test('days with zero hours still shows the 0h slot', () {
      // 2d 0h 5m = 2*86400 + 5*60 = 173100
      expect(DeviceInfoFormat.formatUptime(173100), '2d 0h 5m');
    });

    test('fractional seconds floor to the whole minute', () {
      expect(DeviceInfoFormat.formatUptime(119.9), '1m');
    });

    test('null / non-finite / negative → null (honest unavailable)', () {
      expect(DeviceInfoFormat.formatUptime(null), isNull);
      expect(DeviceInfoFormat.formatUptime(double.nan), isNull);
      expect(DeviceInfoFormat.formatUptime(double.infinity), isNull);
      expect(DeviceInfoFormat.formatUptime(-5), isNull);
    });
  });
}
