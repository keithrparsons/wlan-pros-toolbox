// Tests for the Shannon-Hartley capacity calculator.
//
//   C = NSS · B · log2(1 + S/N),  S/N linear = 10^(dB/10)
//
// Expected values were computed from that exact formula at full double
// precision, not copied from a rounded figure in the brief.
//
// THE TWO THAT EARN THEIR PLACE are the exact ones: 20 MHz at 0 dB SNR is
// EXACTLY 20.0 Mbps, because log2(1 + 1) = 1, and the inverse of that is
// EXACTLY 0.0 dB. A natural-log-versus-log2 slip is the likely bug in this
// screen, and it cannot survive either assertion.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/shannon_capacity_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Shannon capacity math (pure)', () {
    test('20 MHz at 0 dB SNR is EXACTLY 20 Mbps', () {
      // log2(1 + 1) = 1 exactly, so capacity == bandwidth. This is the
      // assertion a log-base error cannot pass: with natural log it returns
      // 13.86, with log10 it returns 6.02.
      expect(
        ShannonCapacityScreen.capacityMbps(20, 0, 1),
        closeTo(20.0, 1e-12),
      );
      expect(
        ShannonCapacityScreen.spectralEfficiency(0),
        closeTo(1.0, 1e-12),
      );
    });

    test('20 MHz at 25 dB SNR on one stream', () {
      expect(
        ShannonCapacityScreen.capacityMbps(20, 25, 1),
        closeTo(166.1875048242561, 1e-9),
      );
    });

    test('80 MHz at 25 dB SNR on one stream', () {
      expect(
        ShannonCapacityScreen.capacityMbps(80, 25, 1),
        closeTo(664.7500192970244, 1e-9),
      );
    });

    test('spatial streams multiply the total exactly', () {
      final double one = ShannonCapacityScreen.capacityMbps(80, 25, 1);
      final double two = ShannonCapacityScreen.capacityMbps(80, 25, 2);
      expect(two, closeTo(1329.5000385940489, 1e-9));
      expect(two, closeTo(one * 2, 1e-9));
      // Per-stream is the single-stream bound regardless of NSS: the point of
      // showing it is that the MIMO multiplication stays visible.
      expect(
        ShannonCapacityScreen.perStreamCapacityMbps(80, 25),
        closeTo(one, 1e-12),
      );
    });

    test('NEGATIVE SNR computes and must not blank', () {
      // At -3 dB a link still carries about 0.586 bits/s/Hz. Wi-Fi genuinely
      // operates here at the bottom MCS rates, so returning null or zero would
      // teach something false.
      expect(
        ShannonCapacityScreen.capacityMbps(20, -3, 1),
        closeTo(11.722078528906948, 1e-9),
      );
      expect(ShannonCapacityScreen.capacityMbps(20, -3, 1), greaterThan(0));
    });

    test('spectral efficiency is per stream, not per link', () {
      // Same efficiency at every bandwidth and every stream count: it is a
      // property of the SNR alone.
      expect(
        ShannonCapacityScreen.spectralEfficiency(25),
        closeTo(8.309375241212805, 1e-9),
      );
    });

    test('SNR converts from dB to a LINEAR ratio', () {
      // 25 dB is 316, not 25. Feeding dB straight in is the classic error.
      expect(ShannonCapacityScreen.snrLinear(25), closeTo(316.22776601683796, 1e-9));
      expect(ShannonCapacityScreen.snrLinear(0), closeTo(1.0, 1e-12));
      expect(ShannonCapacityScreen.snrLinear(-3), closeTo(0.5011872336272722, 1e-12));
    });
  });

  group('Inverse mode: the SNR a target rate demands', () {
    test('1,000 Mbps on one 80 MHz stream needs about 37.6 dB', () {
      // The headline number, and the most useful thing this tool prints.
      expect(
        ShannonCapacityScreen.requiredSnrDb(80, 1000, 1),
        closeTo(37.627999655547775, 1e-9),
      );
      expect(
        ShannonCapacityScreen.requiredBitsPerHz(80, 1000, 1),
        closeTo(12.5, 1e-12),
      );
    });

    test('20 Mbps on one 20 MHz stream needs EXACTLY 0 dB', () {
      // The round trip of the 0 dB forward case, in the other direction.
      expect(
        ShannonCapacityScreen.requiredSnrDb(20, 20, 1),
        closeTo(0.0, 1e-9),
      );
    });

    test('an IMPOSSIBLE ask prints an honest number, it does not error', () {
      // 10 Gbps on one 20 MHz stream is 500 bits/s/Hz. 2^500 overflows a
      // double, so a naive implementation returns infinity and the screen
      // blanks. The honest answer is 1505.1 dB and printing it is the point.
      final double db = ShannonCapacityScreen.requiredSnrDb(20, 10000, 1);
      expect(db.isFinite, isTrue);
      expect(db, closeTo(1505.149978319906, 1e-6));
    });

    test('the large-value path agrees with the exact one at the crossover', () {
      // Below 60 bits/s/Hz the exact form runs; above it the identity
      // 10·log10(2^b) = 10·b·log10(2) does. They must not disagree at the
      // seam, or the tool steps at an arbitrary input value.
      //
      // 60 bits/s/Hz on 20 MHz with NSS 1 is a 1,200 Mbps target.
      const double justUnder = 1200.0;           // exactly 60 bits/s/Hz
      const double justOver = 1200.0000001;      // trips the > 60 branch
      final double a = ShannonCapacityScreen.requiredSnrDb(20, justUnder, 1);
      final double b = ShannonCapacityScreen.requiredSnrDb(20, justOver, 1);
      expect((a - b).abs(), lessThan(1e-6));
    });

    test('forward and inverse are true inverses of each other', () {
      // Round-trip at an ordinary operating point, not just at the exact ones.
      const double snr = 18.5;
      final double cap = ShannonCapacityScreen.capacityMbps(160, snr, 3);
      expect(
        ShannonCapacityScreen.requiredSnrDb(160, cap, 3),
        closeTo(snr, 1e-9),
      );
    });

    test('more streams lower the SNR each one has to carry', () {
      final double one = ShannonCapacityScreen.requiredSnrDb(80, 1000, 1);
      final double two = ShannonCapacityScreen.requiredSnrDb(80, 1000, 2);
      expect(two, lessThan(one));
    });
  });

  group('Verdict bands are factual', () {
    test('bands read off the required SNR', () {
      expect(
        ShannonCapacityScreen.verdictForSnrDb(15),
        contains('Comfortable'),
      );
      expect(
        ShannonCapacityScreen.verdictForSnrDb(25),
        contains('good link'),
      );
      expect(
        ShannonCapacityScreen.verdictForSnrDb(37.6),
        contains('Close to the AP'),
      );
      expect(
        ShannonCapacityScreen.verdictForSnrDb(1505),
        contains('Not achievable'),
      );
    });

    test('no verdict string carries an em dash', () {
      // GL-004: zero em dashes in our prose. These strings are user-visible.
      for (final double db in <double>[15, 25, 37.6, 1505]) {
        expect(ShannonCapacityScreen.verdictForSnrDb(db), isNot(contains('—')));
      }
    });
  });

  group('Screen', () {
    testWidgets('pumps and renders in a phone viewport', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const ShannonCapacityScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('Shannon Capacity'), findsWidgets);
      // Default state is 80 MHz, 25 dB, one stream.
      expect(find.text('664.8'), findsOneWidget);
    });

    testWidgets('switching to Required SNR shows the headline figure',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const ShannonCapacityScreen(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Required SNR'));
      await tester.pump();

      // 1,000 Mbps on one 80 MHz stream.
      expect(find.text('37.6'), findsOneWidget);
    });
  });
}
