// Sparkline — widget tests (TICKET-01).
//
// The painter output is decorative, so these tests assert the widget renders
// without error across the edge cases (empty, single sample, all-gaps, mixed
// gaps) and that the a11y contract holds: a words [semanticLabel] is exposed
// and the pixels themselves are excluded from semantics.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/theme/app_tokens.dart';
import 'package:wlan_pros_toolbox/widgets/sparkline.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<double?> values) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: Sparkline(values: values, semanticLabel: 'RSSI trend'),
          ),
        ),
      ),
    );
  }

  testWidgets('renders an empty window without throwing', (tester) async {
    await pump(tester, const <double?>[]);
    expect(find.byType(Sparkline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a single sample without throwing', (tester) async {
    await pump(tester, const <double?>[-55]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders an all-null window (all gaps) without throwing',
      (tester) async {
    await pump(tester, const <double?>[null, null, null]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a flat series (zero range) without divide-by-zero',
      (tester) async {
    await pump(tester, const <double?>[-60, -60, -60, -60]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a window with interior gaps without throwing',
      (tester) async {
    await pump(tester, const <double?>[-50, null, -60, -55, null, -52]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exposes a words semantic label and excludes the pixels',
      (tester) async {
    await pump(tester, const <double?>[-50, -55, -52]);
    expect(find.bySemanticsLabel('RSSI trend'), findsOneWidget);
    // The painter is wrapped in ExcludeSemantics so the chart pixels do not
    // leak meaningless nodes into the a11y tree.
    expect(find.byType(ExcludeSemantics), findsWidgets);
  });

  testWidgets('accepts a status-tinted line color', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: Sparkline(
              values: const <double?>[40, 38, 42],
              semanticLabel: 'SNR trend',
              lineColor: AppColors.statusSuccess,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
