// One grading scale (Keith, 13 OCT 2026: "A: keep both word sets").
//
// Excellent/Good/Fair/Poor and Strong/Moderate/Weak are two vocabularies for
// ONE set of cut points, ThroughputBands in packages/net_quality. Strong =
// Excellent, Moderate = Good, Weak = Fair or Poor, on the download scale, for
// both the internet axis and usable Wi-Fi. This file fails if a document or
// the help sheet states numbers that differ from the table. The website guide
// lives in another repo; its block is printed by tool/print_grading_block.dart
// on that repo's fix/one-grading-scale branch.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/net_quality_help_sheet.dart';
import 'package:wlan_pros_toolbox/services/network/consumer_verdict.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// The help text of the entry that describes the two status chips.
String _chipHelpText() {
  final Object? root =
      jsonDecode(File('assets/help/tool_help.json').readAsStringSync());
  String? found;
  void walk(Object? node) {
    if (node is String) {
      if (node.contains('two-part chip status')) found = node;
    } else if (node is List) {
      node.forEach(walk);
    } else if (node is Map) {
      node.values.forEach(walk);
    }
  }

  walk(root);
  return found ?? fail('no help text mentions the two-part chip status');
}

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

    test('tool_help.json Test My Connection entry states the scale', () {
      final String help = _chipHelpText();
      expect(help, contains('Strong, Moderate, Weak'));
      expect(help, contains('Strong is $strongFrom Mbps and up'));
      expect(help,
          contains('Moderate is $moderateFrom to under $strongFrom Mbps'));
      expect(help, contains('Weak is under $moderateFrom Mbps'));
      expect(help, contains('same download scale'));
      expect(help, isNot(contains('Slow')));
    });
  });

  testWidgets('help sheet band rows are built from the table', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: NetQualityHelpSheet()),
    ));
    String plus(double v) => '${v == v.roundToDouble() ? v.round() : v}+ Mbps';
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
