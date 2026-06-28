// Ham Radio Study Resources widget tests: the screen renders the resources, the
// two currency caveats, and the exam structure; "Open website" invokes the
// injected launcher with the EXACT url; and a failed launch surfaces an honest
// inline error with the link. Data correctness is locked in
// test/data/ham_reference_data_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/educational/ham_study_resources_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  Future<bool> Function(Uri url)? launcher,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: HamStudyResourcesScreen(launcher: launcher),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders resources, caveats, and the exam structure',
      (tester) async {
    await _pump(tester);

    expect(find.text('Ham Radio Study Resources'), findsWidgets);
    expect(find.text('hamstudy.org'), findsWidgets);
    // The exam structure is surfaced as the stable "35 questions, 26 to pass".
    expect(find.textContaining('35 questions, 26 correct to pass'), findsWidgets);
    // The two currency caveats lead the screen.
    expect(find.textContaining('1 Jul 2026'), findsWidgets);
    expect(find.textContaining('13 Feb 2026'), findsWidgets);
    // Every linked resource shows an Open website button.
    expect(find.text('Open website'), findsWidgets);
  });

  testWidgets('Open website invokes the launcher with the exact url',
      (tester) async {
    Uri? launched;
    await _pump(
      tester,
      launcher: (Uri u) async {
        launched = u;
        return true;
      },
    );

    // The first resource is hamstudy.org.
    await tester.tap(find.text('Open website').first);
    await tester.pump();

    expect(launched, isNotNull);
    expect(launched.toString(), 'https://hamstudy.org');
  });

  testWidgets('a failed launch surfaces an honest error with the link',
      (tester) async {
    await _pump(tester, launcher: (Uri u) async => false);

    await tester.tap(find.text('Open website').first);
    await tester.pump();

    expect(find.textContaining('Could not open the browser'), findsOneWidget);
    expect(find.textContaining('https://hamstudy.org'), findsOneWidget);
  });
}
