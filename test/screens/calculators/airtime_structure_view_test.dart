// Widget tests for Airtime Anatomy's frame-structure view (1.11.0,
// aggregation-structure). The byte math has its own tests (test/services/
// wifi_lab/aggregation_structure_test.dart); these check the screen: the
// Time / Structure toggle, the link to the time view, corruption under each
// arrangement, Legacy's single MPDU, phone widths in both themes with no
// overflow, the presenter layout fitting in its fullest structure states,
// and the presenter keys V, A, C and Right.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_anatomy_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_anatomy_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_structure_view.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/aggregation_structure.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_anatomy.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<void> _phone(
  WidgetTester tester,
  AirtimeAnatomyModel m, {
  double width = 390,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = Size(width, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: AirtimeAnatomyScreen(model: m),
    ),
  );
  await tester.pump();
}

AirtimeAnatomyModel _model() {
  final AirtimeAnatomyModel m = AirtimeAnatomyModel();
  addTearDown(m.dispose);
  return m;
}

void main() {
  testWidgets('the toggle swaps the time view for the structure view', (
    WidgetTester tester,
  ) async {
    final AirtimeAnatomyModel m = _model();
    await _phone(tester, m);
    expect(find.byType(AirtimeStructureView), findsNothing);
    expect(find.text('One TXOP, drawn to scale'), findsOneWidget);

    await tester.tap(find.text('Structure'));
    await tester.pump();
    expect(m.view, AirtimeView.structure);
    expect(find.byType(AirtimeStructureView), findsOneWidget);
    expect(find.text('One TXOP, drawn to scale'), findsNothing);
    // Scenario A is Legacy 6 Mbps: one bare MPDU, and it says why.
    expect(find.text('The PSDU: one MPDU'), findsOneWidget);
    expect(
      find.textContaining('Legacy (802.11a/g) has no aggregation'),
      findsOneWidget,
    );
    expect(
      find.textContaining('The same aggregate the time view draws'),
      findsOneWidget,
    );
    expect(find.text('not on Legacy'), findsNWidgets(3));

    await tester.tap(find.text('Time'));
    await tester.pump();
    expect(find.text('One TXOP, drawn to scale'), findsOneWidget);
  });

  testWidgets('HE 32: one bad A-MPDU subframe, then one bad A-MSDU', (
    WidgetTester tester,
  ) async {
    final AirtimeAnatomyModel m = _model()
      ..setEditing(1)
      ..setView(AirtimeView.structure);
    await _phone(tester, m);
    expect(find.text('The PSDU: 32 A-MPDU subframes'), findsOneWidget);
    expect(
      find.textContaining(
        'The same aggregate the time view draws: 49,664 '
        'bytes',
      ),
      findsOneWidget,
    );

    m.corruptMsdu(4);
    await tester.pump();
    expect(find.text('Resent: A-MPDU subframe 5 only'), findsOneWidget);
    expect(
      find.text('1,552 of 49,664 bytes (3.1 %), 1 of 32 MSDUs'),
      findsOneWidget,
    );
    expect(find.textContaining('Bit 5 is 0'), findsOneWidget);
    expect(
      find.textContaining('The resend is a new PPDU: 64 µs'),
      findsOneWidget,
    );

    m.setArrangement(AggregationKind.amsdu);
    await tester.pump();
    expect(find.text('The PSDU: one A-MSDU'), findsOneWidget);
    // Clamped into the 3 MSDUs this A-MSDU holds.
    expect(m.corruptedMsdu, 2);
    expect(find.text('Resent: the whole PSDU'), findsOneWidget);
    expect(find.textContaining('No ACK.'), findsOneWidget);
    expect(
      find.textContaining('The 2 good MSDUs beside the bad one'),
      findsOneWidget,
    );
    expect(
      find.textContaining('This arrangement packs 3 in 4,596 bytes'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a lime block corrupts that MSDU', (
    WidgetTester tester,
  ) async {
    final AirtimeAnatomyModel m = _model()
      ..setEditing(1)
      ..setView(AirtimeView.structure)
      ..setArrangement(AggregationKind.amsdu);
    await _phone(tester, m);
    expect(m.corruptedMsdu, isNull);
    await tester.tap(find.text('Corrupt one MSDU'));
    await tester.pump();
    // The switch starts on the middle MSDU.
    expect(m.corruptedMsdu, 1);
    await tester.tap(find.byTooltip('Corrupt the next MSDU'));
    await tester.pump();
    expect(m.corruptedMsdu, 2);
    expect(find.text('MSDU 3 of 3'), findsOneWidget);

    // A lime block: the A-MSDU is one cell, bytes to scale, so MSDU 1 sits
    // in its first third and MSDU 3 in its last.
    final Finder grid = find
        .bySemanticsLabel(RegExp(r'^The PSDU: one A-MSDU'))
        .last;
    final Rect r = tester.getRect(grid);
    await tester.tapAt(Offset(r.left + r.width * 0.2, r.center.dy));
    await tester.pump();
    expect(m.corruptedMsdu, 0);
    await tester.tapAt(Offset(r.left + r.width * 0.85, r.center.dy));
    await tester.pump();
    expect(m.corruptedMsdu, 2);
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final double width in <double>[320, 390, 800]) {
      testWidgets('$name ${width.toInt()} px: every arrangement, 64 frames, '
          'corrupted, no overflow', (WidgetTester tester) async {
        final AirtimeAnatomyModel m = _model()
          ..setEditing(1)
          ..setView(AirtimeView.structure);
        m.edit((AirtimeScenario s) => s.copyWith(framesAggregated: 64));
        m.setMsdusPerAmsdu(4);
        await _phone(tester, m, width: width, theme: theme());
        for (final AggregationKind k in AggregationKind.values) {
          m.setArrangement(k);
          m.setCorrupt(true);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: k.label);
        }
        final Iterable<Scrollable> horizontal = tester
            .widgetList<Scrollable>(find.byType(Scrollable))
            .where(
              (Scrollable s) =>
                  s.axisDirection == AxisDirection.right ||
                  s.axisDirection == AxisDirection.left,
            );
        expect(horizontal, isEmpty);
      });
    }
  }

  group('presenter', () {
    Future<AirtimeAnatomyModel> present(
      WidgetTester tester,
      Size window,
      ThemeData theme,
    ) async {
      setWindow(tester, window);
      installFakeWindow();
      final AirtimeAnatomyModel m = _model();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: AirtimeAnatomyScreen(model: m),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Present'));
      await tester.pumpAndSettle();
      expect(find.byType(PresenterLayout), findsOneWidget);
      return m;
    }

    for (final (String name, ThemeData Function() theme)
        in <(String, ThemeData Function())>[
          ('dark', AppTheme.dark),
          ('light', AppTheme.light),
        ]) {
      for (final Size window in const <Size>[
        Size(1920, 1080),
        Size(1440, 900),
        Size(1470, 923),
      ]) {
        final String size = '${window.width.toInt()}x${window.height.toInt()}';
        testWidgets('$name $size: A-MPDU of A-MSDUs, 64 frames, corrupted', (
          WidgetTester tester,
        ) async {
          final AirtimeAnatomyModel m = await present(tester, window, theme());
          m.setEditing(1);
          m.edit((AirtimeScenario s) => s.copyWith(framesAggregated: 64));
          m.setView(AirtimeView.structure);
          m.setArrangement(AggregationKind.ampduOfAmsdus);
          m.setMsdusPerAmsdu(4);
          m.setCorrupt(true);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
          expect(find.byType(AirtimeStructureView), findsOneWidget);
        });
      }
    }

    testWidgets('V, A, C and Right drive the structure view', (
      WidgetTester tester,
    ) async {
      final AirtimeAnatomyModel m = await present(
        tester,
        const Size(1920, 1080),
        AppTheme.dark(),
      );
      m.setEditing(1);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(m.view, AirtimeView.structure);
      expect(m.effectiveArrangement, AggregationKind.ampdu);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(m.effectiveArrangement, AggregationKind.ampduOfAmsdus);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(m.effectiveArrangement, AggregationKind.singleMpdu);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
      expect(m.corruptedMsdu, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
      expect(m.corruptedMsdu, isNull);

      // Right: in the structure view, the corruption walks the MSDUs.
      m.setArrangement(AggregationKind.ampdu);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(m.corruptedMsdu, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(m.corruptedMsdu, 1);
      expect(m.selection, isNull);

      // Back in the time view, Right walks the TXOP again.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(m.selection, (scenario: 1, kind: TxopSegmentKind.aifs));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('limits: an HT 64-frame A-MPDU is over 65,535; HE says what '
      'is not checked', (WidgetTester tester) async {
    final AirtimeAnatomyModel m = _model()
      ..setEditing(1)
      ..setView(AirtimeView.structure);
    await _phone(tester, m);
    expect(find.text('Limits from the standard'), findsOneWidget);
    expect(find.textContaining('Not checked for HE'), findsOneWidget);
    expect(
      find.textContaining('Block Ack bitmap, one bit per MPDU'),
      findsOneWidget,
    );
    expect(find.textContaining('HE raised it to 256 MPDUs'), findsOneWidget);
    expect(find.textContaining('a 14-bit MPDU Length'), findsOneWidget);

    m.edit(
      (AirtimeScenario s) => s.copyWith(
        band: AirtimeBand.ghz5,
        phy: AirtimePhy.ht,
        widthMhz: 40,
        mcs: 7,
        framesAggregated: 64,
      ),
    );
    await tester.pump();
    expect(
      find.textContaining(
        'A-MPDU length: 99,328 bytes, over the maximum of '
        '65,535 bytes',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Not checked for HE'), findsNothing);
    expect(find.textContaining('12-bit MPDU Length'), findsOneWidget);
    // Keith, 2026-09-27: the time view refuses it too, in words, and the
    // structure view keeps its duration row (the arithmetic still holds).
    expect(
      find.textContaining(
        'A-MPDU (aggregate MPDU) is 99,328 bytes, over the HT (802.11n) '
        'maximum of 65,535 bytes: send fewer frames',
      ),
      findsWidgets,
    );
    expect(
      find.textContaining(
        'PPDU duration: 2984 µs, within 5484 µs',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
