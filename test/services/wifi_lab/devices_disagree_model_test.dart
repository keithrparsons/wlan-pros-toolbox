// Why Two Devices Disagree About Signal: model tests (spec 31 "Done means").

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/devices_disagree_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/roaming_walk_engine.dart';

/// Four devices with the given offsets and nothing else going on: zero grip,
/// body off, 1 dB step, no averaging.
List<DeviceSettings> _plain(List<double> offsets, {int averaging = 1}) =>
    <DeviceSettings>[
      for (int i = 0; i < 4; i++)
        DeviceSettings(
          kind: DeviceKind.values[i],
          offsetDb: offsets[i],
          averaging: averaging,
        ),
    ];

void main() {
  group('true power', () {
    test('reuses the Roaming Walk log-distance model', () {
      for (final DdBand b in DdBand.values) {
        final double expected = RoamWalkConfig(
          band: b.roam,
          eirpDbm: kDdEirpDbm,
          pathLossExponent: kDdPathLossExponent,
        ).meanRssiAtDistance(12);
        expect(DevicesDisagreeMath.truePowerDbm(b, 12), expected);
      }
    });

    test('is the same for every device', () {
      final DdResult r = DdResult.compute(DdConfig());
      expect(r.trueDbm, DevicesDisagreeMath.truePowerDbm(DdBand.b5, 8));
    });
  });

  group('deterministic with a seed', () {
    test('same config, same numbers', () {
      final DdResult a = DdResult.compute(DdConfig(seed: 7));
      final DdResult b = DdResult.compute(DdConfig(seed: 7));
      for (int i = 0; i < a.traces.length; i++) {
        expect(a.traces[i].reportedDbm, b.traces[i].reportedDbm);
        expect(a.traces[i].fadeDb, b.traces[i].fadeDb);
      }
    });

    test('a different seed gives a different run', () {
      final DdResult a = DdResult.compute(DdConfig(seed: 1));
      final DdResult b = DdResult.compute(DdConfig(seed: 2));
      expect(a.traces.first.fadeDb, isNot(b.traces.first.fadeDb));
    });
  });

  group('fading off', () {
    test('1 dB step and zero grip: reported = true + offset exactly', () {
      // The device reports whole dB, so "exactly" is true + offset on the
      // 1 dB grid. At a distance where true + offset is a whole number the
      // two are equal with no rounding at all.
      for (final double d in <double>[3, 8, 17.5, 40]) {
        final DdConfig c = DdConfig(
          distanceM: d,
          fadingOn: false,
          devices: _plain(<double>[0, -4, -2, 1]),
        );
        final DdResult r = DdResult.compute(c);
        for (final DeviceTrace t in r.traces) {
          for (final double v in t.reportedDbm) {
            expect(v, (r.trueDbm + t.settings.offsetDb).roundToDouble());
          }
        }
      }
    });

    test('reported = true + offset with no rounding when that is whole', () {
      // Solve for the distance where the 5 GHz true power is exactly -60.
      final DdConfig probe = DdConfig();
      final double d = RoamWalkConfig(
        band: probe.band.roam,
        eirpDbm: kDdEirpDbm,
        pathLossExponent: kDdPathLossExponent,
      ).contourRadiusM(-60);
      final DdResult r = DdResult.compute(
        DdConfig(
          distanceM: d,
          fadingOn: false,
          devices: _plain(<double>[0, -4, -2, 1], averaging: 5),
        ),
      );
      expect(r.trueDbm, closeTo(-60, 1e-9));
      expect(r.traces.map((DeviceTrace t) => t.latest), <double>[
        -60,
        -64,
        -62,
        -59,
      ]);
    });

    test('apply offsets removes the fixed spread entirely', () {
      final DdResult r = DdResult.compute(
        DdConfig(fadingOn: false, devices: _plain(<double>[0, -4, -2, 1])),
      );
      expect(r.spreadNow(), 5);
      expect(r.meanSpread(), 5);
      expect(r.spreadNow(corrected: true), 0);
      expect(r.meanSpread(corrected: true), 0);
    });

    test('grip and body are not removed by offsets', () {
      final List<DeviceSettings> ds = _plain(<double>[0, -4, -2, 1]);
      ds[1] = ds[1].copyWith(gripLossDb: 3, bodyOn: true);
      final DdResult r = DdResult.compute(
        DdConfig(fadingOn: false, bodyLossDb: 4, devices: ds),
      );
      expect(r.spreadNow(corrected: true), 7);
    });

    test('a 2 dB step reports only even values', () {
      final List<DeviceSettings> ds = _plain(<double>[0, 0, 0, 0]);
      ds[0] = ds[0].copyWith(stepDb: 2);
      for (final double d in <double>[3, 5, 8, 13, 21]) {
        final DdResult r = DdResult.compute(
          DdConfig(distanceM: d, fadingOn: false, devices: ds),
        );
        expect(r.traces.first.latest % 2, 0);
        expect((r.traces.first.latest - r.trueDbm).abs(), lessThanOrEqualTo(1));
      }
    });
  });

  group('fading on', () {
    test('averaging over more samples reduces the spread', () {
      // Identical devices, so all of the spread is fading.
      double one = 0;
      double ten = 0;
      for (int seed = 1; seed <= 20; seed++) {
        one += DdResult.compute(
          DdConfig(
            seed: seed,
            spacingM: 0.3,
            devices: _plain(<double>[0, 0, 0, 0]),
          ),
        ).meanSpread();
        ten += DdResult.compute(
          DdConfig(
            seed: seed,
            spacingM: 0.3,
            devices: _plain(<double>[0, 0, 0, 0], averaging: 10),
          ),
        ).meanSpread();
      }
      expect(ten, lessThan(one * 0.7));
    });

    test('offsets remove the fixed part and the fading remains', () {
      final DdResult r = DdResult.compute(
        DdConfig(devices: _plain(<double>[0, -4, -2, 1])),
      );
      final DdResult same = DdResult.compute(
        DdConfig(devices: _plain(<double>[0, 0, 0, 0])),
      );
      expect(r.meanSpread(corrected: true), same.meanSpread());
      expect(r.meanSpread(corrected: true), greaterThan(0));
    });

    test(
      'devices farther apart than half a wavelength see different fades',
      () {
        for (final DdBand band in DdBand.values) {
          final double half = band.wavelength / 2;
          double near = 0;
          double far = 0;
          const int seeds = 20;
          for (int seed = 1; seed <= seeds; seed++) {
            List<List<double>> fades(double spacing) =>
                DevicesDisagreeMath.fadeTraces(
                  DdConfig(band: band, seed: seed, spacingM: spacing),
                );
            final List<List<double>> n = fades(half / 20);
            final List<List<double>> f = fades(half * 1.2);
            near += DevicesDisagreeMath.correlation(n[0], n[1]);
            far += DevicesDisagreeMath.correlation(f[0], f[1]);
            expect(f[0], isNot(f[1]));
          }
          expect(near / seeds, greaterThan(0.9), reason: band.label);
          expect(far / seeds, lessThan(0.5), reason: band.label);
        }
      },
    );

    test('devices at the same point see the same fade', () {
      final List<List<double>> f = DevicesDisagreeMath.fadeTraces(
        DdConfig(spacingM: 0),
      );
      expect(f[0], f[1]);
      expect(f[2], f[3]);
    });

    test('fading averages to about 0 dB in power over many samples', () {
      double sumMw = 0;
      int n = 0;
      for (int seed = 1; seed <= 40; seed++) {
        for (final List<double> t in DevicesDisagreeMath.fadeTraces(
          DdConfig(seed: seed, spacingM: 0.3),
        )) {
          for (final double v in t) {
            sumMw += _mw(v);
            n++;
          }
        }
      }
      expect(sumMw / n, closeTo(1, 0.25));
    });
  });

  group('config', () {
    test('only the first deviceCount devices are measured', () {
      expect(DdResult.compute(DdConfig(deviceCount: 2)).traces, hasLength(2));
    });

    test('limits clamp', () {
      final DdConfig c = DdConfig().copyWith(
        distanceM: 500,
        spacingM: 3,
        deviceCount: 9,
      );
      expect(c.distanceM, kMaxDistanceM);
      expect(c.spacingM, kMaxSpacingM);
      expect(c.deviceCount, kMaxDevices);
      final DeviceSettings d = kDefaultDevices.first.copyWith(
        offsetDb: 40,
        gripLossDb: -3,
        averaging: 99,
        stepDb: 5,
      );
      expect(d.offsetDb, kMaxOffsetDb);
      expect(d.gripLossDb, 0);
      expect(d.averaging, kMaxAveraging);
      expect(d.stepDb, 1);
    });

    test('the defaults are the spec example offsets', () {
      expect(kDefaultDevices.map((DeviceSettings d) => d.offsetDb), <double>[
        0,
        -4,
        -2,
        1,
      ]);
    });
  });
}

double _mw(double db) => math.pow(10, db / 10).toDouble();
