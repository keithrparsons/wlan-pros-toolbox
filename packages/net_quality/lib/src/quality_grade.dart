/// Graded outcome for a single network-quality dimension.
///
/// We grade each measured dimension individually. We deliberately do NOT
/// collapse the grades into a single composite "score": there is no Orb
/// measurement SDK, and a single headline number invites a trademark and
/// marketing comparison we cannot honestly make. Each metric stands alone.
enum QualityGrade {
  /// Best band for the dimension.
  excellent,

  /// Solidly usable.
  good,

  /// Usable but degraded; some applications will notice.
  fair,

  /// Below the threshold for a good experience.
  poor,

  /// The metric could not be measured on this platform or run, for example
  /// SNR on iOS where the OS does not expose it. Shown honestly as
  /// "Unavailable"; it is never faked or substituted with a guess.
  unavailable,
}

/// Human-readable labels for [QualityGrade].
extension QualityGradeLabel on QualityGrade {
  /// Title-case label suitable for direct display in the UI.
  String get label {
    switch (this) {
      case QualityGrade.excellent:
        return 'Excellent';
      case QualityGrade.good:
        return 'Good';
      case QualityGrade.fair:
        return 'Fair';
      case QualityGrade.poor:
        return 'Poor';
      case QualityGrade.unavailable:
        return 'Unavailable';
    }
  }
}
