// RssiScale and RssiScaleStore: Keith Parsons' default RSSI bands (master
// scale, 19 Nov 2026), the user's own boundaries, validation, persistence and
// reset. Expected values are hand-typed from Keith's scale, never read back
// from RssiScale.defaults, so a drift in the code fails here.
//
// Also the help consistency guard: the help and the in-app Field Manual must
// quote the default scale exactly as the code prints it, and no superseded
// band edge may come back.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart' show QualityGrade;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/services/network/rssi_scale.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RssiScaleStore.resetForTest();
  });

  group('defaults: Keith Parsons\' master scale', () {
    const RssiScale d = RssiScale.defaults;

    test('the four boundaries are -66, -72, -78, -84', () {
      expect(d.boundaries, <int>[-66, -72, -78, -84]);
    });

    test('grades at every boundary', () {
      expect(d.grade(-66), QualityGrade.excellent);
      expect(d.grade(-67), QualityGrade.good);
      expect(d.grade(-72), QualityGrade.good);
      expect(d.grade(-73), QualityGrade.fair);
      expect(d.grade(-78), QualityGrade.fair);
      expect(d.grade(-79), QualityGrade.poor);
      expect(d.grade(-84), QualityGrade.poor);
      expect(d.grade(-85), QualityGrade.unusable);
    });

    test('far ends and null', () {
      expect(d.grade(-20), QualityGrade.excellent);
      expect(d.grade(-120), QualityGrade.unusable);
      expect(d.grade(null), QualityGrade.unavailable);
    });

    test('prints the five ranges the way Keith writes them', () {
      expect(
        d.bands.map((RssiBand b) => '${b.label} ${b.displayRange}'),
        <String>[
          'Excellent -66 dBm and stronger',
          'Good -67 to -72',
          'Fair -73 to -78',
          'Poor -79 to -84',
          'Unusable -85 and weaker',
        ],
      );
      expect(
        d.summary,
        'Excellent -66 dBm and stronger, Good -67 to -72, Fair -73 to -78, '
        'Poor -79 to -84, Unusable -85 and weaker',
      );
    });
  });

  group('custom boundaries', () {
    const RssiScale c = RssiScale(
      excellentMinDbm: -60,
      goodMinDbm: -65,
      fairMinDbm: -70,
      poorMinDbm: -80,
    );

    test('grade at and across every custom boundary', () {
      expect(c.grade(-60), QualityGrade.excellent);
      expect(c.grade(-61), QualityGrade.good);
      expect(c.grade(-65), QualityGrade.good);
      expect(c.grade(-66), QualityGrade.fair);
      expect(c.grade(-70), QualityGrade.fair);
      expect(c.grade(-71), QualityGrade.poor);
      expect(c.grade(-80), QualityGrade.poor);
      expect(c.grade(-81), QualityGrade.unusable);
    });

    test('a 1 dB band prints as one number', () {
      const RssiScale narrow = RssiScale(
        excellentMinDbm: -70,
        goodMinDbm: -71,
        fairMinDbm: -72,
        poorMinDbm: -73,
      );
      expect(narrow.bands[1].displayRange, '-71');
      expect(narrow.grade(-71), QualityGrade.good);
    });

    test('every reading falls in exactly one band: no gaps, no overlaps', () {
      for (final RssiScale s in <RssiScale>[RssiScale.defaults, c]) {
        final List<RssiBand> bands = s.bands;
        for (int dbm = -20; dbm >= -120; dbm--) {
          int hits = 0;
          for (int i = 0; i < bands.length; i++) {
            final int top = i == 0 ? 1000 : bands[i - 1].minDbm - 1;
            if (dbm <= top && dbm >= bands[i].minDbm) hits++;
          }
          expect(hits, 1, reason: '$s at $dbm dBm');
        }
      }
    });
  });

  group('validation', () {
    test('accepts the defaults and a sensible custom scale', () {
      expect(RssiScale.validate(<int?>[-66, -72, -78, -84]), isEmpty);
      expect(RssiScale.validate(<int?>[-30, -31, -99, -100]), isEmpty);
      expect(RssiScale.tryFrom(<int?>[-66, -72, -78, -84]), RssiScale.defaults);
    });

    test('rejects boundaries out of order', () {
      final Map<RssiBoundary, String> e = RssiScale.validate(<int?>[
        -72,
        -66,
        -78,
        -84,
      ]);
      expect(e.keys, <RssiBoundary>[RssiBoundary.good]);
      expect(e[RssiBoundary.good], 'Must be weaker than -72');
      expect(RssiScale.tryFrom(<int?>[-72, -66, -78, -84]), isNull);
      expect(RssiScale.tryFrom(<int?>[-84, -78, -72, -66]), isNull);
    });

    test('rejects equal boundaries (an empty band, which would be a gap)', () {
      final Map<RssiBoundary, String> e = RssiScale.validate(<int?>[
        -66,
        -72,
        -72,
        -84,
      ]);
      expect(e.keys, <RssiBoundary>[RssiBoundary.fair]);
      expect(RssiScale.tryFrom(<int?>[-66, -72, -72, -84]), isNull);
    });

    test('rejects values outside -100 to -30 dBm', () {
      expect(
        RssiScale.validate(<int?>[-29, -72, -78, -84])[RssiBoundary.excellent],
        'Enter -100 to -30 dBm',
      );
      expect(
        RssiScale.validate(<int?>[-66, -72, -78, -101])[RssiBoundary.poor],
        'Enter -100 to -30 dBm',
      );
      expect(RssiScale.tryFrom(<int?>[0, -72, -78, -84]), isNull);
    });

    test('rejects empty and non-whole-number input', () {
      expect(RssiScale.parseDbm(''), isNull);
      expect(RssiScale.parseDbm('-70.5'), isNull);
      expect(RssiScale.parseDbm('abc'), isNull);
      expect(RssiScale.parseDbm(' -70 '), -70);
      expect(RssiScale.parseDbm('\u221270'), -70); // Unicode minus sign
      expect(
        RssiScale.validate(<int?>[null, -72, -78, -84]).keys,
        <RssiBoundary>[RssiBoundary.excellent],
      );
      expect(RssiScale.tryFrom(<int?>[-66, -72, -78]), isNull);
    });

    test('decode drops a saved value that is invalid or unreadable', () {
      expect(RssiScale.decode(null), isNull);
      expect(RssiScale.decode('not json'), isNull);
      expect(
        RssiScale.decode('{"excellent":-72,"good":-66,"fair":-78,"poor":-84}'),
        isNull,
      );
      expect(RssiScale.decode(RssiScale.defaults.encode()), RssiScale.defaults);
    });
  });

  group('RssiScaleStore: persistence and reset', () {
    const RssiScale custom = RssiScale(
      excellentMinDbm: -60,
      goodMinDbm: -65,
      fairMinDbm: -70,
      poorMinDbm: -80,
    );

    test('starts on the defaults', () {
      expect(RssiScaleStore.instance.value, RssiScale.defaults);
      expect(RssiScaleStore.instance.isCustom, isFalse);
    });

    test('save persists, and a fresh load reads it back', () async {
      await RssiScaleStore.instance.save(custom);
      expect(RssiScaleStore.instance.isCustom, isTrue);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(RssiScaleStore.prefsKey), custom.encode());

      RssiScaleStore.resetForTest();
      expect(RssiScaleStore.instance.value, RssiScale.defaults);
      await RssiScaleStore.instance.load();
      expect(RssiScaleStore.instance.value, custom);
    });

    test('reset restores the defaults and forgets the saved scale', () async {
      await RssiScaleStore.instance.save(custom);
      int notified = 0;
      RssiScaleStore.instance.addListener(() => notified++);
      await RssiScaleStore.instance.reset();
      expect(notified, 1);
      expect(RssiScaleStore.instance.value, RssiScale.defaults);
      expect(RssiScaleStore.instance.value.boundaries, <int>[
        -66,
        -72,
        -78,
        -84,
      ]);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(RssiScaleStore.prefsKey), isFalse);
    });

    test('an invalid saved value loads as the defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RssiScaleStore.prefsKey:
            '{"excellent":-66,"good":-66,"fair":-78,"poor":-84}',
      });
      await RssiScaleStore.instance.load();
      expect(RssiScaleStore.instance.value, RssiScale.defaults);
    });
  });

  group('help and guides match the code (drift guard)', () {
    final String help = File('assets/help/tool_help.json').readAsStringSync();
    final String manual = File(
      'assets/guides/field-manual.md',
    ).readAsStringSync();
    final String manualAscii = manual.replaceAll('\u2212', '-');

    test('the help quotes the default scale exactly as the code prints it', () {
      for (final RssiBand b in RssiScale.defaults.bands) {
        expect(help, contains('${b.label} ${b.displayRange}'), reason: b.label);
        expect(
          manualAscii,
          contains('${b.label} ${b.displayRange}'),
          reason: 'field-manual.md: ${b.label}',
        );
      }
      expect(help, contains(RssiScale.defaults.summary));
    });

    test(
      'no superseded band scale is left in the help or the Field Manual',
      () {
        for (final String stale in <String>[
          // 1 Nov 2026 scale.
          '-67 dBm or better',
          '-68 to -72',
          '-73 to -75',
          '-76 or worse',
          // 12 Jul 2026 scale.
          '> -60 dBm',
          '-60 to -67',
          '-73 or weaker',
          'Excellent -59',
          '≥-59',
          // Older five-band picture.
          'Excellent > -55',
        ]) {
          expect(help, isNot(contains(stale)), reason: 'help: $stale');
          expect(
            manualAscii,
            isNot(contains(stale)),
            reason: 'field-manual.md: $stale',
          );
        }
      },
    );

    test('the bands are never called a standard', () {
      expect(help, isNot(contains('standard bands')));
      expect(manual, isNot(contains('standard bands')));
      expect(
        File('lib/services/network/wifi_grading.dart').readAsStringSync(),
        isNot(contains('standard bands')),
      );
    });

    test('the graphic shows the five default bands', () {
      final String svg = File(
        'assets/tool-graphics/signal-thresholds.svg',
      ).readAsStringSync();
      for (final String label in <String>[
        'Excellent',
        'Good',
        'Fair',
        'Poor',
        'Unusable',
      ]) {
        expect(svg, contains('>$label</text>'), reason: label);
      }
      // Derived from the code defaults, so changing the defaults without
      // redrawing the graphic fails here.
      const RssiScale d = RssiScale.defaults;
      for (final String range in <String>[
        '&#8804; ${d.poorMinDbm - 1}',
        '${d.fairMinDbm - 1}..${d.poorMinDbm}',
        '${d.goodMinDbm - 1}..${d.fairMinDbm}',
        '${d.excellentMinDbm - 1}..${d.goodMinDbm}',
        '&#8805; ${d.excellentMinDbm}',
      ]) {
        expect(svg, contains(range), reason: range);
      }
      expect(svg, isNot(contains('>Weak<')));
    });
  });
}
