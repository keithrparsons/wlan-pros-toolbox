// One grading scale (Keith, 13 OCT 2026: "A: keep both word sets").
//
// Excellent/Good/Fair/Poor and Strong/Moderate/Weak are two vocabularies for
// ONE set of cut points, ThroughputBands in packages/net_quality. Strong =
// Excellent, Moderate = Good, Weak = Fair or Poor, on the download scale, for
// both the internet axis and usable Wi-Fi. This file fails if a document or
// the help sheet states numbers that differ from the table. The website guide
// lives in another repo; its block is printed by tool/print_grading_block.dart
// on that repo's fix/one-grading-scale branch.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/net_quality_help_sheet.dart';
import 'package:wlan_pros_toolbox/services/network/consumer_verdict.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  final int strongFrom = ThroughputBands.downloadExcellentMbps.round();
  final int moderateFrom = ThroughputBands.downloadGoodMbps.round();

  group('chips read the table', () {
    test('Strong at the Excellent cut, Moderate at the Good cut', () {
      expect(AxisStatusThresholds.tierFor(strongFrom.toDouble()),
          AxisStatus.strong);
      expect(AxisStatusThresholds.tierFor(strongFrom - 0.1), AxisStatus.moderate);
      expect(AxisStatusThresholds.tierFor(moderateFrom.toDouble()),
          AxisStatus.moderate);
      expect(AxisStatusThresholds.tierFor(moderateFrom - 0.1), AxisStatus.weak);
    });

    test('Ben Story: usable Wi-Fi 79.75, down 97, up 55 is Moderate and Moderate',
        () {
      // Rx 117 / Tx 173: 0.55 x mean = 79.75.
      final WifiVsInternetResult r = WifiVsInternetEngine.evaluate(
        rxRateMbps: 117,
        txRateMbps: 173,
        rxRateAvailable: true,
        internetDownMbps: 97,
        internetUpMbps: 55,
        internetHealth: InternetHealth.good,
      );
      expect(r.usableWifiMbps, closeTo(79.75, 0.01));
      final ConsumerVerdict v = ConsumerVerdictMapper.map(r);
      expect(v.wifiStatus, AxisStatus.moderate);
      expect(v.internetStatus, AxisStatus.moderate);
    });
  });

  group('documents state the same numbers', () {
    test('Field Manual Test My Connection entry', () {
      final String fm = File('assets/guides/field-manual.md').readAsStringSync();
      expect(fm, contains('"Strong" ($strongFrom Mbps and up'));
      expect(fm, contains('"Moderate" ($moderateFrom to under $strongFrom Mbps'));
      expect(fm, contains('"Weak" (under $moderateFrom Mbps'));
      expect(fm, isNot(contains('> 250 Mbps')));
    });

    test('tool_help.json never states the old 250 cut point', () {
      final String help = File('assets/help/tool_help.json').readAsStringSync();
      expect(help, isNot(contains('250 Mbps')));
    });
  });

  testWidgets('help sheet band rows are built from the table', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: NetQualityHelpSheet()),
    ));
    String plus(double v) => '${v.round()}+ Mbps';
    for (final double v in <double>[
      ThroughputBands.downloadExcellentMbps,
      ThroughputBands.downloadGoodMbps,
      ThroughputBands.downloadFairMbps,
      ThroughputBands.uploadExcellentMbps,
      ThroughputBands.uploadGoodMbps,
      ThroughputBands.uploadFairMbps,
    ]) {
      expect(find.textContaining(plus(v), skipOffstage: false), findsWidgets);
    }
  });
}
