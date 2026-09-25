// Pins the 6 GHz Power and PSD model to the Pax brief §1 tables
// (myPKA Deliverables/2026-09-25-wifi-lab-wave3-research/brief.md), which
// read 47 CFR §15.407 and ETSI EN 303 687 V1.1.1 directly. Spec 17's
// "Done means" list is covered test by test below.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fspl_math.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/six_ghz_psd_math.dart';

const List<int> _w = SixGhzPsdMath.widthsMHz;

/// EIRP at each width, rounded to 0.1 dB as the brief prints it.
List<String> _row(
  PowerClass c, {
  double sp = SixGhzPsdMath.defaultSpAuthorizedDbm,
  double gvp = SixGhzPsdMath.defaultGvpAuthorizedDbm,
}) => <String>[
  for (final int w in _w)
    SixGhzPsdMath.eirp(
      c,
      w,
      spAuthorizedDbm: sp,
      gvpAuthorizedDbm: gvp,
    ).eirpDbm.toStringAsFixed(1),
];

List<String> _dbm(List<num> v) => <String>[
  for (final num x in v) x.toStringAsFixed(1),
];

double _snr(PowerClass c, int w, {double d = 10}) => SixGhzPsdMath.snrDb(
  eirpDbm: SixGhzPsdMath.eirp(c, w).eirpDbm,
  widthMHz: w,
  distanceM: d,
  extraLossDb: 0,
  noiseFigureDb: SixGhzPsdMath.defaultNoiseFigureDb,
);

void main() {
  group('brief §1 EIRP table, US', () {
    test('LPI AP 18/21/24/27/30 dBm', () {
      expect(_row(PowerClass.usLpiAp), _dbm(<num>[18, 21, 24, 27, 30]));
    });
    test('subordinate matches the LPI AP', () {
      expect(_row(PowerClass.usSubordinate), _row(PowerClass.usLpiAp));
    });
    test('VLP 8/11/14/14/14 dBm', () {
      expect(_row(PowerClass.usVlp), _dbm(<num>[8, 11, 14, 14, 14]));
    });
    test('SP AP 36 at every width, and so is the fixed client', () {
      expect(_row(PowerClass.usSpAp), _dbm(<num>[36, 36, 36, 36, 36]));
      expect(_row(PowerClass.usFixedClient), _dbm(<num>[36, 36, 36, 36, 36]));
    });
    test('LPI client 12/15/18/21/24 dBm, a flat 24 not tied to the AP', () {
      expect(_row(PowerClass.usLpiClient), _dbm(<num>[12, 15, 18, 21, 24]));
      expect(PowerClass.usLpiClient.followsAp, isNull);
    });
    test('SP client 30 and GVP AP 24 and GVP client 18 at every width', () {
      expect(_row(PowerClass.usSpClient), _dbm(<num>[30, 30, 30, 30, 30]));
      expect(_row(PowerClass.usGvpAp), _dbm(<num>[24, 24, 24, 24, 24]));
      expect(_row(PowerClass.usGvpClient), _dbm(<num>[18, 18, 18, 18, 18]));
    });
    test('the pre-cap products are the brief figures', () {
      // 10 log10(BW) = 13.01, 16.02, 19.03, 22.04, 25.05.
      expect(
        <String>[
          for (final int w in _w)
            SixGhzPsdMath.bandwidthDb(w).toStringAsFixed(2),
        ],
        <String>['13.01', '16.02', '19.03', '22.04', '25.05'],
      );
      expect(
        SixGhzPsdMath.psdEirpDbm(PowerClass.usLpiAp, 320),
        closeTo(30.05, 0.005),
      );
    });
  });

  group('brief §1, EU', () {
    test('EU LPI 23 at every width', () {
      expect(_row(PowerClass.euLpi), _dbm(<num>[23, 23, 23, 23, 23]));
    });
    test('EU VLP 14 at every width', () {
      expect(_row(PowerClass.euVlp), _dbm(<num>[14, 14, 14, 14, 14]));
    });
    test('no EU class carries a client offset', () {
      for (final PowerClass c in PowerClass.forRegion(PsdRegion.eu)) {
        expect(c.followsAp, isNull);
      }
    });
  });

  group('the client -6 dB rule', () {
    test('an SP client with its AP authorized at 30 dBm is limited to 24', () {
      final PsdEirp e = SixGhzPsdMath.eirp(
        PowerClass.usSpClient,
        80,
        spAuthorizedDbm: 30,
      );
      expect(e.eirpDbm, 24);
      expect(e.limit, PsdLimit.apRelative);
      expect(
        _row(PowerClass.usSpClient, sp: 30),
        _dbm(<num>[24, 24, 24, 24, 24]),
      );
    });
    test('with the AP at the full 36 the SP client reads as capped at 30', () {
      final PsdEirp e = SixGhzPsdMath.eirp(PowerClass.usSpClient, 20);
      expect(e.eirpDbm, 30);
      expect(e.limit, PsdLimit.cap);
    });
    test('the AP is held to its own grant too', () {
      final PsdEirp e = SixGhzPsdMath.eirp(
        PowerClass.usSpAp,
        160,
        spAuthorizedDbm: 30,
      );
      expect(e.eirpDbm, 30);
      expect(e.limit, PsdLimit.authorized);
    });
    test('GVP client follows the GVP AP grant, not the SP one', () {
      expect(
        SixGhzPsdMath.eirp(
          PowerClass.usGvpClient,
          20,
          spAuthorizedDbm: 10,
          gvpAuthorizedDbm: 20,
        ).eirpDbm,
        14,
      );
    });
    test('fixed client is exempt from the relative rule', () {
      expect(
        SixGhzPsdMath.eirp(
          PowerClass.usFixedClient,
          20,
          spAuthorizedDbm: 20,
        ).eirpDbm,
        36,
      );
    });
  });

  group('PSD-limited vs cap-limited', () {
    test('LPI AP is PSD-limited to 160 MHz and capped at 320', () {
      expect(
        <bool>[
          for (final int w in _w)
            SixGhzPsdMath.eirp(PowerClass.usLpiAp, w).limit.isPsd,
        ],
        <bool>[true, true, true, true, false],
      );
    });
    test('VLP is PSD-limited only below 80 MHz', () {
      expect(
        <bool>[
          for (final int w in _w)
            SixGhzPsdMath.eirp(PowerClass.usVlp, w).limit.isPsd,
        ],
        <bool>[true, true, false, false, false],
      );
    });
    test('radiated PSD holds while PSD-limited, falls 3 dB once capped', () {
      double psd(int w) => SixGhzPsdMath.radiatedPsdDbmPerMHz(
        SixGhzPsdMath.eirp(PowerClass.usSpAp, w).eirpDbm,
        w,
      );
      expect(psd(40) - psd(80), closeTo(3.0103, 1e-4));
      final double lpi20 = SixGhzPsdMath.radiatedPsdDbmPerMHz(
        SixGhzPsdMath.eirp(PowerClass.usLpiAp, 20).eirpDbm,
        20,
      );
      expect(lpi20, closeTo(5, 1e-9));
    });
  });

  group('noise floor and SNR', () {
    test('noise floor -174 + 10 log10(BW Hz) + NF', () {
      expect(SixGhzPsdMath.noiseFloorDbm(20, 7), closeTo(-93.99, 0.005));
      expect(SixGhzPsdMath.noiseFloorDbm(320, 7), closeTo(-81.95, 0.005));
      expect(SixGhzPsdMath.noiseFloorDbm(20, 0), closeTo(-100.99, 0.005));
    });
    test('received power uses the FSPL Simulator math at 6105 MHz', () {
      expect(
        SixGhzPsdMath.receivedDbm(30, 10, 5),
        closeTo(30 - FsplMath.fsplDb(10, 6105) - 5, 1e-9),
      );
    });
    test('LPI SNR is constant across widths at a fixed distance', () {
      final double base = _snr(PowerClass.usLpiAp, 20);
      for (final int w in <int>[40, 80, 160]) {
        expect(_snr(PowerClass.usLpiAp, w), closeTo(base, 1e-9));
      }
      // At 320 MHz the 30 dBm cap trims the 30.05 dBm product: 0.05 dB.
      expect(_snr(PowerClass.usLpiAp, 320), closeTo(base - 0.0515, 0.001));
      // 5 dBm/MHz - (-174 + 60 + 7) dBm/MHz = 112 dB before path loss.
      expect(base, closeTo(112 - FsplMath.fsplDb(10, 6105), 1e-9));
    });
    test('SP SNR falls 3 dB per doubling of width', () {
      for (int i = 1; i < _w.length; i++) {
        expect(
          _snr(PowerClass.usSpAp, _w[i - 1]) - _snr(PowerClass.usSpAp, _w[i]),
          closeTo(3.0103, 1e-4),
        );
      }
    });
  });

  group('sub-bands and channel counts (brief §1 refinement b)', () {
    List<int> counts(PowerClass c) => <int>[
      for (final int w in _w) SixGhzPsdMath.channelCount(c, w),
    ];
    test('LPI and VLP get 59/29/14/7/3', () {
      expect(counts(PowerClass.usLpiAp), <int>[59, 29, 14, 7, 3]);
      expect(counts(PowerClass.usVlp), <int>[59, 29, 14, 7, 3]);
    });
    test('SP and GVP get 41/20/9/4/1', () {
      expect(counts(PowerClass.usSpAp), <int>[41, 20, 9, 4, 1]);
      expect(counts(PowerClass.usGvpClient), <int>[41, 20, 9, 4, 1]);
    });
    test('EU band 5945-6425 holds 24/12/6/3/1 (fc = 5935 + 20 n)', () {
      expect(counts(PowerClass.euLpi), <int>[24, 12, 6, 3, 1]);
    });
    test('SP may not use U-NII-6 or U-NII-8', () {
      // Channel 101 = 6455 MHz (U-NII-6); channel 197 = 6935 MHz (U-NII-8).
      expect(SixGhzPsdMath.channelAllowed(PowerClass.usSpAp, 101, 20), isFalse);
      expect(SixGhzPsdMath.channelAllowed(PowerClass.usSpAp, 197, 20), isFalse);
      expect(SixGhzPsdMath.channelAllowed(PowerClass.usLpiAp, 101, 20), isTrue);
      expect(SixGhzPsdMath.channelAllowed(PowerClass.usSpAp, 117, 20), isTrue);
    });
    test('the reference frequency is legal for every class', () {
      for (final PowerClass c in PowerClass.values) {
        expect(SixGhzPsdMath.channelAllowed(c, 31, 20), isTrue, reason: '$c');
      }
      expect(SixGhzPsdMath.centerMHz(31), SixGhzPsdMath.referenceFreqMHz);
    });
  });
}
