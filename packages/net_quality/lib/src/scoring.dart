import 'quality_grade.dart';

/// Maps measured values to a [QualityGrade] per dimension.
///
/// Each function documents whether its bands are derived from a recognized
/// standard or are our own heuristic. Per GL-005, a heuristic is never
/// presented as a standard. The bands themselves (the exact cut points) are
/// ALWAYS our own choice; where a standard exists, it grounds the direction and
/// rough magnitude, not the precise numbers.
class QualityScoring {
  // Not constructible; namespace for static graders.
  const QualityScoring._();

  /// Grades one-way-ish latency in milliseconds.
  ///
  /// Excellent < 20, good < 50, fair < 100, poor >= 100.
  /// Grounded in ITU-T G.114, which treats up to ~150 ms mouth-to-ear as
  /// acceptable for interactive voice. These are OUR bands derived from that
  /// guidance, applied to network RTT; they are not a verbatim G.114 table.
  static QualityGrade gradeLatencyMs(double ms) {
    if (ms < 20) return QualityGrade.excellent;
    if (ms < 50) return QualityGrade.good;
    if (ms < 100) return QualityGrade.fair;
    return QualityGrade.poor;
  }

  /// Grades jitter in milliseconds.
  ///
  /// Excellent < 5, good < 15, fair < 30, poor >= 30.
  /// Common VoIP jitter-buffer guidance targets keeping jitter under ~30 ms.
  /// These are OUR bands informed by that guidance, not a published standard.
  static QualityGrade gradeJitterMs(double ms) {
    if (ms < 5) return QualityGrade.excellent;
    if (ms < 15) return QualityGrade.good;
    if (ms < 30) return QualityGrade.fair;
    return QualityGrade.poor;
  }

  /// Grades packet/sample loss in percent.
  ///
  /// Excellent == 0, good < 1, fair < 2.5, poor >= 2.5.
  /// ITU and Cisco design guidance hold that loss above ~1 percent noticeably
  /// degrades VoIP. These are OUR bands informed by that guidance.
  static QualityGrade gradeLossPct(double pct) {
    if (pct == 0) return QualityGrade.excellent;
    if (pct < 1) return QualityGrade.good;
    if (pct < 2.5) return QualityGrade.fair;
    return QualityGrade.poor;
  }

  /// Grades responsiveness in round-trips per minute (RPM).
  ///
  /// Excellent >= 1000, good >= 500, fair >= 100, poor < 100.
  /// Grounded in RFC 9097 and Apple's networkQuality, which use RPM with
  /// roughly this order of magnitude for good interactive responsiveness.
  /// These are OUR bands derived from that work. Note also that the RPM value
  /// fed in is our simplified single-flow estimate, not a full multi-flow RPM.
  static QualityGrade gradeResponsivenessRpm(double rpm) {
    if (rpm >= 1000) return QualityGrade.excellent;
    if (rpm >= 500) return QualityGrade.good;
    if (rpm >= 100) return QualityGrade.fair;
    return QualityGrade.poor;
  }

  /// Grades download throughput in Mbps.
  ///
  /// Excellent >= 100, good >= 25, fair >= 5, poor < 5.
  /// These bands are EXPLICITLY a heuristic, not a standard. "Good enough"
  /// throughput depends entirely on what the user is doing; we chose round
  /// numbers that map to common broadband tiers and household needs.
  static QualityGrade gradeDownloadMbps(double mbps) {
    if (mbps >= 100) return QualityGrade.excellent;
    if (mbps >= 25) return QualityGrade.good;
    if (mbps >= 5) return QualityGrade.fair;
    return QualityGrade.poor;
  }

  /// Grades upload throughput in Mbps.
  ///
  /// Excellent >= 20, good >= 5, fair >= 1, poor < 1.
  /// These bands are EXPLICITLY a heuristic, not a standard, chosen against
  /// typical needs for video calls, cloud backup, and uploads.
  static QualityGrade gradeUploadMbps(double mbps) {
    if (mbps >= 20) return QualityGrade.excellent;
    if (mbps >= 5) return QualityGrade.good;
    if (mbps >= 1) return QualityGrade.fair;
    return QualityGrade.poor;
  }
}
