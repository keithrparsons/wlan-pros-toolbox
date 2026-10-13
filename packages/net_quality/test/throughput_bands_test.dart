import 'package:net_quality/net_quality.dart';
import 'package:test/test.dart';

void main() {
  group('ThroughputBands is the one table the graders read', () {
    test('download cut points', () {
      expect(ThroughputBands.downloadExcellentMbps, 100);
      expect(ThroughputBands.downloadGoodMbps, 25);
      expect(ThroughputBands.downloadFairMbps, 5);
    });

    test('upload cut points', () {
      expect(ThroughputBands.uploadExcellentMbps, 20);
      expect(ThroughputBands.uploadGoodMbps, 5);
      expect(ThroughputBands.uploadFairMbps, 1);
    });

    test('graders flip exactly at the table values', () {
      for (final double c in <double>[
        ThroughputBands.downloadExcellentMbps,
        ThroughputBands.downloadGoodMbps,
        ThroughputBands.downloadFairMbps,
      ]) {
        expect(QualityScoring.gradeDownloadMbps(c),
            isNot(QualityScoring.gradeDownloadMbps(c - 0.1)));
      }
      for (final double c in <double>[
        ThroughputBands.uploadExcellentMbps,
        ThroughputBands.uploadGoodMbps,
        ThroughputBands.uploadFairMbps,
      ]) {
        expect(QualityScoring.gradeUploadMbps(c),
            isNot(QualityScoring.gradeUploadMbps(c - 0.1)));
      }
    });
  });
}
