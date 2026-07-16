// Tests for the RF Attenuation (building materials) calculator.
//
// Dataset and math are verified against the RF Tools PWA reference
// (app.js MATERIALS, line 998; calcMaterials, line 1090):
//   bi = band '2.4' -> 1, '5' -> 2, '6' -> 3
//   per-material loss = m[bi] * qty
//   total = sum of m[bi] * qty over every material with qty > 0
//
// The dataset asserts below lock the per-band dB values to the PWA constant so
// the native app and PWA agree exactly. One widget test confirms the screen
// pumps in a phone viewport and renders its cards.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rf_attenuation_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('MATERIALS dataset — verbatim PWA app.js port', () {
    test('has all 13 PWA materials in order', () {
      final List<String> names =
          RfAttenuationScreen.materials.map((RfMaterial m) => m.name).toList();
      expect(names, <String>[
        'Drywall / Plasterboard',
        'Wood door / hollow partition',
        'Cubicle / office panel',
        'Glass: clear single pane',
        'Glass: low-E / tinted coated',
        'Brick (4 in / 10 cm)',
        'Concrete block / CMU',
        'Concrete: poured (4 in / 10 cm)',
        'Metal door / steel panel',
        'Foil insulation / vapor barrier',
        'Concrete floor / ceiling',
        'Wood floor / raised subfloor',
        'Water / wet materials',
      ]);
    });

    test('per-band dB values match the PWA [name,2.4,5,6,note] rows', () {
      // [name, loss24, loss5, loss6] tuples copied from app.js MATERIALS.
      final List<List<Object>> expected = <List<Object>>[
        <Object>['Drywall / Plasterboard', 3, 4, 5],
        <Object>['Wood door / hollow partition', 4, 5, 6],
        <Object>['Cubicle / office panel', 2, 3, 4],
        <Object>['Glass: clear single pane', 2, 3, 4],
        <Object>['Glass: low-E / tinted coated', 8, 10, 12],
        <Object>['Brick (4 in / 10 cm)', 8, 12, 15],
        <Object>['Concrete block / CMU', 10, 13, 15],
        <Object>['Concrete: poured (4 in / 10 cm)', 13, 16, 19],
        <Object>['Metal door / steel panel', 20, 26, 30],
        <Object>['Foil insulation / vapor barrier', 25, 30, 35],
        <Object>['Concrete floor / ceiling', 15, 20, 22],
        <Object>['Wood floor / raised subfloor', 5, 7, 8],
        <Object>['Water / wet materials', 6, 9, 11],
      ];

      for (int i = 0; i < expected.length; i++) {
        final RfMaterial m = RfAttenuationScreen.materials[i];
        expect(m.name, expected[i][0], reason: 'name row $i');
        expect(m.loss24, expected[i][1], reason: '2.4 GHz row $i');
        expect(m.loss5, expected[i][2], reason: '5 GHz row $i');
        expect(m.loss6, expected[i][3], reason: '6 GHz row $i');
      }
    });
  });

  group('Band index — matches PWA bi ternary', () {
    test("'2.4' -> 1, '5' -> 2, '6' -> 3", () {
      expect(RfAttenuationScreen.bandIndex(MaterialBand.ghz24), 1);
      expect(RfAttenuationScreen.bandIndex(MaterialBand.ghz5), 2);
      expect(RfAttenuationScreen.bandIndex(MaterialBand.ghz6), 3);
    });
  });

  group('lossPerLayer — matches PWA m[bi]', () {
    final RfMaterial brick = RfAttenuationScreen.materials
        .firstWhere((RfMaterial m) => m.name == 'Brick (4 in / 10 cm)');

    test('brick reads 8 / 12 / 15 dB by band', () {
      expect(RfAttenuationScreen.lossPerLayer(brick, MaterialBand.ghz24), 8);
      expect(RfAttenuationScreen.lossPerLayer(brick, MaterialBand.ghz5), 12);
      expect(RfAttenuationScreen.lossPerLayer(brick, MaterialBand.ghz6), 15);
    });
  });

  group('totalLoss — matches PWA calcMaterials sum', () {
    final RfMaterial drywall = RfAttenuationScreen.materials[0]; // 3/4/5
    final RfMaterial brick = RfAttenuationScreen.materials[5]; // 8/12/15
    final RfMaterial metal = RfAttenuationScreen.materials[8]; // 20/26/30

    test('empty map is 0 dB', () {
      expect(
        RfAttenuationScreen.totalLoss(<RfMaterial, int>{}, MaterialBand.ghz5),
        0,
      );
    });

    test('2× drywall + 1× brick at 5 GHz = 2*4 + 1*12 = 20 dB', () {
      final int total = RfAttenuationScreen.totalLoss(
        <RfMaterial, int>{drywall: 2, brick: 1},
        MaterialBand.ghz5,
      );
      expect(total, 20);
    });

    test('same stack at 2.4 GHz = 2*3 + 1*8 = 14 dB', () {
      final int total = RfAttenuationScreen.totalLoss(
        <RfMaterial, int>{drywall: 2, brick: 1},
        MaterialBand.ghz24,
      );
      expect(total, 14);
    });

    test('same stack at 6 GHz = 2*5 + 1*15 = 25 dB', () {
      final int total = RfAttenuationScreen.totalLoss(
        <RfMaterial, int>{drywall: 2, brick: 1},
        MaterialBand.ghz6,
      );
      expect(total, 25);
    });

    test('qty <= 0 rows contribute nothing (PWA qty > 0 guard)', () {
      final int total = RfAttenuationScreen.totalLoss(
        <RfMaterial, int>{drywall: 0, metal: 1},
        MaterialBand.ghz5,
      );
      expect(total, 26); // only the metal row counts
    });
  });

  group('RfAttenuationScreen widget', () {
    testWidgets('renders in a phone viewport with title and controls',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const RfAttenuationScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('RF Attenuation'), findsWidgets);
        expect(find.text('Frequency band'), findsOneWidget);
        expect(find.text('Material'), findsOneWidget);
        expect(find.text('Total loss'), findsOneWidget);
        // No materials added yet -> blank total, empty-state breakdown.
        expect(find.text('—'), findsOneWidget);
        expect(
          find.text('Add a material above to see the breakdown.'),
          findsOneWidget,
        );
        // One quantity input.
        expect(find.byType(TextField), findsOneWidget);
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
