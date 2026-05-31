import 'quality_grade.dart';

/// Stable string identifiers for every metric the toolbox can report.
///
/// IDs are split into two families:
///   * Transport metrics, measured by this pure-Dart package on all platforms.
///   * Wi-Fi link metrics, reserved here for an app-layer Flutter service that
///     reads the radio. They are not measured by this package; iOS blocks most
///     of them, so they are reported as [QualityGrade.unavailable] there.
class MetricIds {
  // Not constructible; this is a namespace for constants.
  const MetricIds._();

  // --- Transport metrics (measured by this package, all 5 platforms) ---

  /// Round-trip latency, milliseconds.
  static const String latency = 'latency';

  /// Latency variation (RFC 3550-style mean deviation), milliseconds.
  static const String jitter = 'jitter';

  /// Sample loss, percent.
  static const String loss = 'loss';

  /// Download throughput, megabits per second.
  static const String download = 'download';

  /// Upload throughput, megabits per second.
  static const String upload = 'upload';

  /// Responsiveness under load, round-trips per minute (RPM).
  static const String responsiveness = 'responsiveness';

  // --- Wi-Fi link metrics (reserved for an app-layer service) ---

  /// Received signal strength indicator, dBm.
  static const String rssi = 'rssi';

  /// Signal-to-noise ratio, dB.
  static const String snr = 'snr';

  /// Negotiated transmit rate, Mbps.
  static const String txRate = 'txRate';

  /// Modulation and coding scheme index.
  static const String mcs = 'mcs';

  /// Channel width, MHz.
  static const String channelWidth = 'channelWidth';
}

/// One graded network-quality dimension: an id, a label, an optional value,
/// a unit, a [QualityGrade], and an optional explanatory note.
///
/// A metric with a null [value] and [QualityGrade.unavailable] means the
/// dimension could not be measured on this run. That state is first-class and
/// shown honestly; it is never replaced with a fabricated number.
class QualityMetric {
  /// Stable identifier, one of [MetricIds].
  final String id;

  /// Human-readable label for display.
  final String label;

  /// Measured value, or null when [grade] is [QualityGrade.unavailable].
  final double? value;

  /// Unit string for [value], for example 'ms', 'Mbps', 'RPM', '%'.
  final String unit;

  /// Individual grade for this dimension.
  final QualityGrade grade;

  /// Optional note: a heuristic caveat, a failure reason, or context.
  final String? note;

  /// Creates a graded metric.
  const QualityMetric({
    required this.id,
    required this.label,
    required this.value,
    required this.unit,
    required this.grade,
    this.note,
  });

  /// Creates a metric that could not be measured on this run.
  ///
  /// Sets [value] to null and [grade] to [QualityGrade.unavailable].
  const QualityMetric.unavailable({
    required this.id,
    required this.label,
    required this.unit,
    this.note,
  })  : value = null,
        grade = QualityGrade.unavailable;

  /// True when the metric carries a real measured value.
  bool get isAvailable =>
      grade != QualityGrade.unavailable && value != null;

  /// JSON form. The [note] key is included only when it is non-null.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'label': label,
        'value': value,
        'unit': unit,
        'grade': grade.name,
        if (note != null) 'note': note,
      };

  @override
  String toString() =>
      'QualityMetric($id: ${value ?? '-'} $unit, ${grade.name}'
      '${note == null ? '' : ', note: $note'})';
}
