// WifiPhyRateService — unit tests for the extracted PHY-rate math.
//
// This math used to live as statics on the throughput calculator's
// StatefulWidget. It was extracted 2026-07-31 so a second screen (Client
// Capabilities) can compute a PHY ceiling without reaching into a widget. These
// tests exercise the SERVICE directly: no widget, no pump, no Flutter binding.
//
// WHERE THE EXPECTED NUMBERS COME FROM (this matters, per GL-005). They are NOT
// read off this implementation's output. Each headline case is a PHY rate that
// is independently published in the standard maximum-data-rate tables, so a
// silent regression in the tables or the formula shows up as a number a Wi-Fi
// engineer would recognize as wrong:
//
//   802.11n  40 MHz, MCS 7,  4 SS, 400 ns GI ->    600    Mbps (11n maximum)
//   802.11ac 80 MHz, MCS 9,  2 SS, 400 ns GI ->    866.7  Mbps
//   802.11ax 20 MHz, MCS 0,  1 SS, 0.8 us GI ->      8.6  Mbps
//   802.11ax 160 MHz, MCS 11, 2 SS, 0.8 us GI ->  2401.9  Mbps
//   802.11be 320 MHz, MCS 13, 8 SS, 0.8 us GI -> 23058.8  Mbps
//
// The service's own tables are a value-for-value port of the RF Tools PWA
// (app.js calcThroughput / updateTputOptions); the provenance lives in the
// service file header.
//
// The last group is a DELEGATION PARITY check. `ThroughputCalcScreen` keeps its
// public statics as thin aliases so the pre-extraction call sites still work,
// and the parity test is what stops those aliases from silently drifting into a
// second, divergent copy of the numbers.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/throughput_calc_screen.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_phy_rate_service.dart';

void main() {
  group('Known-good PHY rates, one per standard (published table values)', () {
    test('HT: 802.11n 40 MHz / MCS 7 / 4 SS / 400 ns GI is 600 Mbps', () {
      final double? phy = WifiPhyRateService.phyRateMbps(
        std: WifiStd.ht,
        bandwidthMHz: 40,
        mcs: 7,
        streams: 4,
        giKey: '0.4',
      );
      // (108 subcarriers x 5.0 bits/symbol x 4 streams) / 3.6 us = 600.0
      expect(phy, isNotNull);
      expect(phy!, closeTo(600.0, 0.001));
    });

    test('VHT: 802.11ac 80 MHz / MCS 9 / 2 SS / 400 ns GI is 866.7 Mbps', () {
      final double? phy = WifiPhyRateService.phyRateMbps(
        std: WifiStd.vht,
        bandwidthMHz: 80,
        mcs: 9,
        streams: 2,
        giKey: '0.4',
      );
      expect(phy, isNotNull);
      expect(phy!, closeTo(866.7, 0.1));
    });

    test('HE: 802.11ax 20 MHz / MCS 0 / 1 SS / 0.8 us GI is 8.6 Mbps', () {
      final double? phy = WifiPhyRateService.phyRateMbps(
        std: WifiStd.he,
        bandwidthMHz: 20,
        mcs: 0,
        streams: 1,
        giKey: '0.8',
      );
      expect(phy, isNotNull);
      expect(phy!, closeTo(8.6, 0.1));
    });

    test('HE: 802.11ax 160 MHz / MCS 11 / 2 SS / 0.8 us GI is 2401.9 Mbps', () {
      final double? phy = WifiPhyRateService.phyRateMbps(
        std: WifiStd.he,
        bandwidthMHz: 160,
        mcs: 11,
        streams: 2,
        giKey: '0.8',
      );
      expect(phy, isNotNull);
      expect(phy!, closeTo(2401.9, 0.1));
    });

    test('EHT: 802.11be 320 MHz / MCS 13 / 8 SS / 0.8 us GI is 23058.8 Mbps',
        () {
      final double? phy = WifiPhyRateService.phyRateMbps(
        std: WifiStd.eht,
        bandwidthMHz: 320,
        mcs: 13,
        streams: 8,
        giKey: '0.8',
      );
      expect(phy, isNotNull);
      expect(phy!, closeTo(23058.8, 0.1));
    });
  });

  group('Blank output on an invalid combination (the PWA showError paths)', () {
    test('bandwidth the standard does not have -> null, never a guess', () {
      // 80 MHz and 160 MHz do not exist for HT; 320 MHz is EHT-only.
      for (final int bw in <int>[80, 160, 320]) {
        expect(
          WifiPhyRateService.phyRateMbps(
            std: WifiStd.ht,
            bandwidthMHz: bw,
            mcs: 0,
            streams: 1,
            giKey: '0.8',
          ),
          isNull,
          reason: 'HT has no $bw MHz',
        );
      }
      expect(
        WifiPhyRateService.phyRateMbps(
          std: WifiStd.he,
          bandwidthMHz: 320,
          mcs: 0,
          streams: 1,
          giKey: '0.8',
        ),
        isNull,
        reason: '320 MHz is EHT only',
      );
      // A width that exists for no standard at all.
      expect(
        WifiPhyRateService.phyRateMbps(
          std: WifiStd.eht,
          bandwidthMHz: 60,
          mcs: 0,
          streams: 1,
          giKey: '0.8',
        ),
        isNull,
      );
    });

    test('guard interval the standard does not have -> null', () {
      // The 400 ns short GI is an HT/VHT concept; HE and EHT use 0.8/1.6/3.2.
      for (final WifiStd std in <WifiStd>[WifiStd.he, WifiStd.eht]) {
        expect(
          WifiPhyRateService.phyRateMbps(
            std: std,
            bandwidthMHz: 20,
            mcs: 0,
            streams: 1,
            giKey: '0.4',
          ),
          isNull,
          reason: '$std has no 400 ns GI',
        );
      }
      // ...and the HE/EHT long intervals do not exist for HT/VHT.
      for (final WifiStd std in <WifiStd>[WifiStd.ht, WifiStd.vht]) {
        for (final String gi in <String>['1.6', '3.2']) {
          expect(
            WifiPhyRateService.phyRateMbps(
              std: std,
              bandwidthMHz: 20,
              mcs: 0,
              streams: 1,
              giKey: gi,
            ),
            isNull,
            reason: '$std has no $gi us GI',
          );
        }
      }
      // An unrecognised key is blank, not a fallback to some default.
      expect(
        WifiPhyRateService.phyRateMbps(
          std: WifiStd.he,
          bandwidthMHz: 20,
          mcs: 0,
          streams: 1,
          giKey: 'short',
        ),
        isNull,
      );
    });

    test('MCS above the standard maximum -> null, for every standard', () {
      // maxMcs: HT 7, VHT 9, HE 11, EHT 13. One above each must blank.
      for (final MapEntry<WifiStd, int> e
          in WifiPhyRateService.maxMcs.entries) {
        final int bw = WifiPhyRateService.bandwidths[e.key]!.first;
        final String gi = WifiPhyRateService.giKeys[e.key]!.first;

        expect(
          WifiPhyRateService.phyRateMbps(
            std: e.key,
            bandwidthMHz: bw,
            mcs: e.value,
            streams: 1,
            giKey: gi,
          ),
          isNotNull,
          reason: 'MCS ${e.value} is valid for ${e.key}',
        );
        expect(
          WifiPhyRateService.phyRateMbps(
            std: e.key,
            bandwidthMHz: bw,
            mcs: e.value + 1,
            streams: 1,
            giKey: gi,
          ),
          isNull,
          reason: 'MCS ${e.value + 1} is above ${e.key} maximum',
        );
      }
    });

    test('negative MCS and non-positive spatial streams -> null', () {
      expect(
        WifiPhyRateService.phyRateMbps(
          std: WifiStd.he,
          bandwidthMHz: 20,
          mcs: -1,
          streams: 1,
          giKey: '0.8',
        ),
        isNull,
      );
      for (final int ss in <int>[0, -2]) {
        expect(
          WifiPhyRateService.phyRateMbps(
            std: WifiStd.he,
            bandwidthMHz: 20,
            mcs: 0,
            streams: ss,
            giKey: '0.8',
          ),
          isNull,
          reason: '$ss spatial streams is not a link',
        );
      }
    });

    test('realRateMbps blanks wherever phyRateMbps blanks', () {
      expect(
        WifiPhyRateService.realRateMbps(
          std: WifiStd.ht,
          bandwidthMHz: 160,
          mcs: 0,
          streams: 1,
          giKey: '0.8',
        ),
        isNull,
      );
      expect(
        WifiPhyRateService.realRateMbps(
          std: WifiStd.eht,
          bandwidthMHz: 320,
          mcs: 14,
          streams: 8,
          giKey: '0.8',
        ),
        isNull,
      );
    });
  });

  group('realRateMbps applies the per-standard efficiency factor', () {
    test('the factors are HT 0.70, VHT 0.72, HE 0.76, EHT 0.80', () {
      expect(WifiPhyRateService.eff[WifiStd.ht], 0.70);
      expect(WifiPhyRateService.eff[WifiStd.vht], 0.72);
      expect(WifiPhyRateService.eff[WifiStd.he], 0.76);
      expect(WifiPhyRateService.eff[WifiStd.eht], 0.80);
    });

    test('real = phy x eff(std) across every standard, width, GI and stream '
        'count', () {
      int checked = 0;
      for (final WifiStd std in WifiStd.values) {
        final double e = WifiPhyRateService.eff[std]!;
        for (final int bw in WifiPhyRateService.bandwidths[std]!) {
          for (final String gi in WifiPhyRateService.giKeys[std]!) {
            for (final int ss
                in <int>[1, 2, WifiPhyRateService.maxStreams[std]!]) {
              for (final int mcs
                  in <int>[0, WifiPhyRateService.maxMcs[std]!]) {
                final double? phy = WifiPhyRateService.phyRateMbps(
                  std: std,
                  bandwidthMHz: bw,
                  mcs: mcs,
                  streams: ss,
                  giKey: gi,
                );
                final double? real = WifiPhyRateService.realRateMbps(
                  std: std,
                  bandwidthMHz: bw,
                  mcs: mcs,
                  streams: ss,
                  giKey: gi,
                );
                expect(phy, isNotNull, reason: '$std $bw MHz $gi us is valid');
                expect(real, isNotNull);
                expect(real!, closeTo(phy! * e, 1e-9));
                checked++;
              }
            }
          }
        }
      }
      // Guard the loop itself: a bounds change that silently emptied it would
      // otherwise leave this test passing while asserting nothing.
      expect(checked, greaterThan(50));
    });

    test('the HE 160 MHz headline case: 2401.9 PHY -> 1825.5 real', () {
      final double? real = WifiPhyRateService.realRateMbps(
        std: WifiStd.he,
        bandwidthMHz: 160,
        mcs: 11,
        streams: 2,
        giKey: '0.8',
      );
      // 2401.95 x 0.76 = 1825.48
      expect(real, isNotNull);
      expect(real!, closeTo(1825.5, 0.1));
    });

    test('real is always below phy, because every factor is below 1.0', () {
      for (final double e in WifiPhyRateService.eff.values) {
        expect(e, greaterThan(0.0));
        expect(e, lessThan(1.0));
      }
    });
  });

  group('Table integrity', () {
    test('mcsBps and mcsMod are the same length and cover every maxMcs', () {
      expect(WifiPhyRateService.mcsBps.length,
          WifiPhyRateService.mcsMod.length);
      for (final int max in WifiPhyRateService.maxMcs.values) {
        expect(max, lessThan(WifiPhyRateService.mcsBps.length));
      }
    });

    test('every standard has bandwidths, GI keys, nsd, sym, eff and maxStreams',
        () {
      for (final WifiStd std in WifiStd.values) {
        expect(WifiPhyRateService.bandwidths[std], isNotNull, reason: '$std');
        expect(WifiPhyRateService.giKeys[std], isNotNull, reason: '$std');
        expect(WifiPhyRateService.nsd[std], isNotNull, reason: '$std');
        expect(WifiPhyRateService.sym[std], isNotNull, reason: '$std');
        expect(WifiPhyRateService.eff[std], isNotNull, reason: '$std');
        expect(WifiPhyRateService.maxStreams[std], isNotNull, reason: '$std');
        // Every offered bandwidth has an Nsd, and every offered GI a symbol
        // time. An option the user can pick that yields a blank is a bug.
        for (final int bw in WifiPhyRateService.bandwidths[std]!) {
          expect(WifiPhyRateService.nsd[std]![bw], isNotNull,
              reason: '$std offers $bw MHz but has no Nsd for it');
        }
        for (final String gi in WifiPhyRateService.giKeys[std]!) {
          expect(WifiPhyRateService.sym[std]![gi], isNotNull,
              reason: '$std offers $gi us GI but has no symbol time for it');
        }
      }
    });

    test('mcsLabel reads "MCS n: modulation"', () {
      expect(WifiPhyRateService.mcsLabel(0), 'MCS 0: BPSK ½');
      expect(WifiPhyRateService.mcsLabel(13), 'MCS 13: 4096-QAM ⅚');
    });
  });

  // Every table pinned to its literal PWA value. This group exists because
  // mutation-testing the first draft of this file found a hole: the
  // "MCS above the maximum" test walked `maxMcs` to decide what "above" meant,
  // so RAISING a standard's maximum (VHT 9 -> 10) left the whole file green. A
  // test that reads the table it is meant to guard cannot guard it. The service
  // is now the single source of these numbers, so its own test pins them
  // literally rather than leaning on the calculator screen's test to do it.
  group('Constant tables pinned to the PWA, value-for-value', () {
    test('MCS_BPS: bits per symbol, all 14 indices', () {
      expect(WifiPhyRateService.mcsBps, <double>[
        0.5,
        1.0,
        1.5,
        2.0,
        3.0,
        4.0,
        4.5,
        5.0,
        6.0,
        6.6667,
        7.5,
        8.3333,
        9.0,
        10.0,
      ]);
    });

    test('MCS_MOD: modulation labels, all 14 indices', () {
      expect(WifiPhyRateService.mcsMod, <String>[
        'BPSK ½',
        'QPSK ½',
        'QPSK ¾',
        '16-QAM ½',
        '16-QAM ¾',
        '64-QAM ⅔',
        '64-QAM ¾',
        '64-QAM ⅚',
        '256-QAM ¾',
        '256-QAM ⅚',
        '1024-QAM ¾',
        '1024-QAM ⅚',
        '4096-QAM ¾',
        '4096-QAM ⅚',
      ]);
    });

    test('TPUT_NSD: data subcarriers per standard per width', () {
      expect(WifiPhyRateService.nsd, <WifiStd, Map<int, int>>{
        WifiStd.ht: <int, int>{20: 52, 40: 108},
        WifiStd.vht: <int, int>{20: 52, 40: 108, 80: 234, 160: 468},
        WifiStd.he: <int, int>{20: 234, 40: 468, 80: 980, 160: 1960},
        WifiStd.eht: <int, int>{
          20: 234,
          40: 468,
          80: 980,
          160: 1960,
          320: 3920,
        },
      });
    });

    test('TPUT_SYM: OFDM symbol duration us per standard per GI', () {
      expect(WifiPhyRateService.sym, <WifiStd, Map<String, double>>{
        WifiStd.ht: <String, double>{'0.4': 3.6, '0.8': 4.0},
        WifiStd.vht: <String, double>{'0.4': 3.6, '0.8': 4.0},
        WifiStd.he: <String, double>{'0.8': 13.6, '1.6': 14.4, '3.2': 16.0},
        WifiStd.eht: <String, double>{'0.8': 13.6, '1.6': 14.4, '3.2': 16.0},
      });
    });

    test('TPUT_MAX_MCS: HT 7, VHT 9, HE 11, EHT 13', () {
      expect(WifiPhyRateService.maxMcs, <WifiStd, int>{
        WifiStd.ht: 7,
        WifiStd.vht: 9,
        WifiStd.he: 11,
        WifiStd.eht: 13,
      });
    });

    test('TPUT_EFF: HT 0.70, VHT 0.72, HE 0.76, EHT 0.80', () {
      expect(WifiPhyRateService.eff, <WifiStd, double>{
        WifiStd.ht: 0.70,
        WifiStd.vht: 0.72,
        WifiStd.he: 0.76,
        WifiStd.eht: 0.80,
      });
    });

    test('bandwidth option sets per standard', () {
      expect(WifiPhyRateService.bandwidths, <WifiStd, List<int>>{
        WifiStd.ht: <int>[20, 40],
        WifiStd.vht: <int>[20, 40, 80, 160],
        WifiStd.he: <int>[20, 40, 80, 160],
        WifiStd.eht: <int>[20, 40, 80, 160, 320],
      });
    });

    test('guard-interval option sets per standard, in display order', () {
      expect(WifiPhyRateService.giKeys, <WifiStd, List<String>>{
        WifiStd.ht: <String>['0.4', '0.8'],
        WifiStd.vht: <String>['0.4', '0.8'],
        WifiStd.he: <String>['0.8', '1.6', '3.2'],
        WifiStd.eht: <String>['0.8', '1.6', '3.2'],
      });
    });

    test('max spatial streams: HT 4, everything later 8', () {
      expect(WifiPhyRateService.maxStreams, <WifiStd, int>{
        WifiStd.ht: 4,
        WifiStd.vht: 8,
        WifiStd.he: 8,
        WifiStd.eht: 8,
      });
    });
  });

  group('The service is pure Dart: usable without a widget pump', () {
    test('wifi_phy_rate_service.dart imports no Flutter package', () {
      final File f = File(
        '${_packageRoot()}/lib/services/network/wifi_phy_rate_service.dart',
      );
      expect(f.existsSync(), isTrue, reason: 'service file not found');

      final List<String> flutterImports = f
          .readAsLinesSync()
          .where((String l) => l.trimLeft().startsWith('import '))
          .where((String l) => l.contains('package:flutter'))
          .toList();

      expect(
        flutterImports,
        isEmpty,
        reason: 'The Client Capabilities screen and any future caller must be '
            'able to compute a PHY rate without a Flutter binding. Found: '
            '${flutterImports.join(', ')}',
      );
    });
  });

  group('ThroughputCalcScreen statics still delegate to the service', () {
    test('the constant tables are the SAME objects, not copies', () {
      expect(identical(ThroughputCalcScreen.mcsBps, WifiPhyRateService.mcsBps),
          isTrue);
      expect(identical(ThroughputCalcScreen.mcsMod, WifiPhyRateService.mcsMod),
          isTrue);
      expect(
          identical(ThroughputCalcScreen.nsd, WifiPhyRateService.nsd), isTrue);
      expect(
          identical(ThroughputCalcScreen.sym, WifiPhyRateService.sym), isTrue);
      expect(identical(ThroughputCalcScreen.maxMcs, WifiPhyRateService.maxMcs),
          isTrue);
      expect(
          identical(ThroughputCalcScreen.eff, WifiPhyRateService.eff), isTrue);
      expect(
          identical(
              ThroughputCalcScreen.bandwidths, WifiPhyRateService.bandwidths),
          isTrue);
      expect(identical(ThroughputCalcScreen.giKeys, WifiPhyRateService.giKeys),
          isTrue);
      expect(
          identical(
              ThroughputCalcScreen.maxStreams, WifiPhyRateService.maxStreams),
          isTrue);
    });

    test('phyRateMbps and realRateMbps agree on every valid combination', () {
      int checked = 0;
      for (final WifiStd std in WifiStd.values) {
        for (final int bw in WifiPhyRateService.bandwidths[std]!) {
          for (final String gi in WifiPhyRateService.giKeys[std]!) {
            for (int ss = 1; ss <= WifiPhyRateService.maxStreams[std]!; ss++) {
              for (int mcs = 0;
                  mcs <= WifiPhyRateService.maxMcs[std]!;
                  mcs++) {
                expect(
                  ThroughputCalcScreen.phyRateMbps(
                    std: std,
                    bandwidthMHz: bw,
                    mcs: mcs,
                    streams: ss,
                    giKey: gi,
                  ),
                  WifiPhyRateService.phyRateMbps(
                    std: std,
                    bandwidthMHz: bw,
                    mcs: mcs,
                    streams: ss,
                    giKey: gi,
                  ),
                );
                expect(
                  ThroughputCalcScreen.realRateMbps(
                    std: std,
                    bandwidthMHz: bw,
                    mcs: mcs,
                    streams: ss,
                    giKey: gi,
                  ),
                  WifiPhyRateService.realRateMbps(
                    std: std,
                    bandwidthMHz: bw,
                    mcs: mcs,
                    streams: ss,
                    giKey: gi,
                  ),
                );
                checked++;
              }
            }
          }
        }
      }
      expect(checked, greaterThan(500));
    });

    test('mcsLabel agrees across the whole MCS table', () {
      for (int i = 0; i < WifiPhyRateService.mcsBps.length; i++) {
        expect(ThroughputCalcScreen.mcsLabel(i), WifiPhyRateService.mcsLabel(i));
      }
    });
  });
}

/// Walks up from the test's working directory to the package root (the folder
/// holding `pubspec.yaml` and `lib/`), matching the house guard-test pattern.
String _packageRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 6; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/lib').existsSync()) {
      return dir.path;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}
