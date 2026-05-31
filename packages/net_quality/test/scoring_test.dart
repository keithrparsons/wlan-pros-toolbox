import 'package:net_quality/net_quality.dart';
import 'package:test/test.dart';

void main() {
  group('gradeLatencyMs', () {
    test('boundaries', () {
      expect(QualityScoring.gradeLatencyMs(0), QualityGrade.excellent);
      expect(QualityScoring.gradeLatencyMs(19.9), QualityGrade.excellent);
      expect(QualityScoring.gradeLatencyMs(20), QualityGrade.good);
      expect(QualityScoring.gradeLatencyMs(49.9), QualityGrade.good);
      expect(QualityScoring.gradeLatencyMs(50), QualityGrade.fair);
      expect(QualityScoring.gradeLatencyMs(99.9), QualityGrade.fair);
      expect(QualityScoring.gradeLatencyMs(100), QualityGrade.poor);
      expect(QualityScoring.gradeLatencyMs(500), QualityGrade.poor);
    });
  });

  group('gradeJitterMs', () {
    test('boundaries', () {
      expect(QualityScoring.gradeJitterMs(0), QualityGrade.excellent);
      expect(QualityScoring.gradeJitterMs(5), QualityGrade.good);
      expect(QualityScoring.gradeJitterMs(15), QualityGrade.fair);
      expect(QualityScoring.gradeJitterMs(30), QualityGrade.poor);
      expect(QualityScoring.gradeJitterMs(100), QualityGrade.poor);
    });
  });

  group('gradeLossPct', () {
    test('boundaries', () {
      expect(QualityScoring.gradeLossPct(0), QualityGrade.excellent);
      expect(QualityScoring.gradeLossPct(0.5), QualityGrade.good);
      expect(QualityScoring.gradeLossPct(1), QualityGrade.fair);
      expect(QualityScoring.gradeLossPct(2.4), QualityGrade.fair);
      expect(QualityScoring.gradeLossPct(2.5), QualityGrade.poor);
      expect(QualityScoring.gradeLossPct(100), QualityGrade.poor);
    });
  });

  group('gradeResponsivenessRpm', () {
    test('boundaries (higher is better)', () {
      expect(QualityScoring.gradeResponsivenessRpm(2000),
          QualityGrade.excellent);
      expect(QualityScoring.gradeResponsivenessRpm(1000),
          QualityGrade.excellent);
      expect(QualityScoring.gradeResponsivenessRpm(999), QualityGrade.good);
      expect(QualityScoring.gradeResponsivenessRpm(500), QualityGrade.good);
      expect(QualityScoring.gradeResponsivenessRpm(499), QualityGrade.fair);
      expect(QualityScoring.gradeResponsivenessRpm(100), QualityGrade.fair);
      expect(QualityScoring.gradeResponsivenessRpm(99), QualityGrade.poor);
    });
  });

  group('gradeDownloadMbps', () {
    test('boundaries (higher is better)', () {
      expect(QualityScoring.gradeDownloadMbps(1000), QualityGrade.excellent);
      expect(QualityScoring.gradeDownloadMbps(100), QualityGrade.excellent);
      expect(QualityScoring.gradeDownloadMbps(99), QualityGrade.good);
      expect(QualityScoring.gradeDownloadMbps(25), QualityGrade.good);
      expect(QualityScoring.gradeDownloadMbps(24), QualityGrade.fair);
      expect(QualityScoring.gradeDownloadMbps(5), QualityGrade.fair);
      expect(QualityScoring.gradeDownloadMbps(4.9), QualityGrade.poor);
      expect(QualityScoring.gradeDownloadMbps(0), QualityGrade.poor);
    });
  });

  group('gradeUploadMbps', () {
    test('boundaries (higher is better)', () {
      expect(QualityScoring.gradeUploadMbps(100), QualityGrade.excellent);
      expect(QualityScoring.gradeUploadMbps(20), QualityGrade.excellent);
      expect(QualityScoring.gradeUploadMbps(19), QualityGrade.good);
      expect(QualityScoring.gradeUploadMbps(5), QualityGrade.good);
      expect(QualityScoring.gradeUploadMbps(4), QualityGrade.fair);
      expect(QualityScoring.gradeUploadMbps(1), QualityGrade.fair);
      expect(QualityScoring.gradeUploadMbps(0.9), QualityGrade.poor);
      expect(QualityScoring.gradeUploadMbps(0), QualityGrade.poor);
    });
  });
}
