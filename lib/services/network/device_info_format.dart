// DeviceInfoFormat — pure, Flutter-free formatting for the Device Info tool.
//
// Two formatters, isolated here so they unit-test without a binding:
//   * formatBytes  — total RAM bytes → a human-readable size. Uses BINARY units
//     (GiB = 1024^3) because physical RAM is sized in powers of two; an 8 GiB
//     stick reads "8 GB" the way a user expects, not "8.59 GB". The unit label
//     stays the familiar "GB"/"MB" (not "GiB") to match everyday device specs.
//   * formatUptime — seconds since boot → "3d 4h 12m" style. Drops leading
//     zero units (no "0d") and always shows at least minutes, so a freshly
//     booted device reads "0m", not an empty string.
//
// Both return null for a null / invalid input so the caller renders the honest
// "Not available" state rather than a fabricated value (GL-005).

class DeviceInfoFormat {
  DeviceInfoFormat._();

  static const int _kKiB = 1024;
  static const int _kMiB = 1024 * 1024;
  static const int _kGiB = 1024 * 1024 * 1024;
  static const int _kTiB = 1024 * 1024 * 1024 * 1024;

  /// Formats a byte count as a human-readable memory size using binary units
  /// (1024-based) with a conventional "GB"/"MB" label. Returns null for a null
  /// or non-positive input (0 / negative is not a real reading).
  ///
  /// Examples: 8589934592 → "8 GB", 17179869184 → "16 GB",
  /// 3221225472 → "3 GB", 536870912 → "512 MB".
  static String? formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return null;

    if (bytes >= _kTiB) return '${_trim(bytes / _kTiB)} TB';
    if (bytes >= _kGiB) return '${_trim(bytes / _kGiB)} GB';
    if (bytes >= _kMiB) return '${_trim(bytes / _kMiB)} MB';
    if (bytes >= _kKiB) return '${_trim(bytes / _kKiB)} KB';
    return '$bytes B';
  }

  /// Formats seconds-since-boot as "Dd Hh Mm", dropping leading zero units and
  /// always showing at least minutes ("0m" for a just-booted device). Returns
  /// null for a null, non-finite, or negative input.
  ///
  /// Examples: 273120 → "3d 4h 12m", 4500 → "1h 15m", 600 → "10m", 30 → "0m".
  static String? formatUptime(double? seconds) {
    if (seconds == null || !seconds.isFinite || seconds < 0) return null;

    final int total = seconds.floor();
    final int days = total ~/ 86400;
    final int hours = (total % 86400) ~/ 3600;
    final int minutes = (total % 3600) ~/ 60;

    final List<String> parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0 || days > 0) parts.add('${hours}h');
    parts.add('${minutes}m'); // always present, even at 0m
    return parts.join(' ');
  }

  /// Renders a unit-scaled double without a trailing ".0": 8.0 → "8",
  /// 7.5 → "7.5". Keeps one decimal place where it carries information.
  static String _trim(double v) {
    final String s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
}
