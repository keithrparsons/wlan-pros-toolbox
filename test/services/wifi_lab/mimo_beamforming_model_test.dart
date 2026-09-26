// Tests for the MIMO and Beamforming model (Wi-Fi Classroom spec 06, "Done means").
//
// The first five groups map to the spec's clauses:
//   - a 4x4 AP to a 2x2 client gives Nss = 2 both ways;
//   - a 2x2 AP to a 4x4 client gives Nss = 2;
//   - ideal TxBF gain for 4 chains and 2 streams is 3.01 dB, for 4 chains and
//     1 stream 6.02 dB;
//   - the steered array factor peaks at the steering angle;
//   - a sniffer with 1 chain cannot decode a 2-stream frame.
// The rest pin the sounding estimate and the cited measurement.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/mimo_beamforming_model.dart';

void main() {
  group('spatial streams', () {
    test('4x4 AP to a 2x2 client: 2 streams in both directions', () {
      for (final LinkDirection d in LinkDirection.values) {
        final MimoLink link = MimoLink(
          apChains: 4,
          clientChains: 2,
          direction: d,
        );
        expect(link.streams, 2, reason: d.label);
      }
      expect(MimoMath.spatialStreams(4, 2), 2);
    });

    test('2x2 AP to a 4x4 client: 2 streams', () {
      expect(MimoMath.spatialStreams(2, 4), 2);
      for (final LinkDirection d in LinkDirection.values) {
        expect(MimoLink(apChains: 2, clientChains: 4, direction: d).streams, 2);
      }
    });

    test('never more than the client advertises', () {
      expect(MimoMath.spatialStreams(4, 4, 1), 1);
      expect(
        const MimoLink(
          apChains: 8,
          clientChains: 4,
          clientMaxStreams: 2,
          direction: LinkDirection.downlink,
        ).streams,
        2,
      );
    });

    test('spare chains sit on the side with more of them', () {
      const MimoLink down = MimoLink(
        apChains: 4,
        clientChains: 2,
        direction: LinkDirection.downlink,
      );
      expect(down.spareTx, 2);
      expect(down.spareRx, 0);
      const MimoLink up = MimoLink(
        apChains: 4,
        clientChains: 2,
        direction: LinkDirection.uplink,
      );
      expect(up.spareTx, 0);
      expect(up.spareRx, 2);
    });
  });

  group('ideal gains (upper bounds)', () {
    test('TxBF: 4 chains over 2 streams is 3.01 dB', () {
      expect(MimoMath.idealArrayGainDb(4, 2), closeTo(3.0103, 1e-4));
      const MimoLink link = MimoLink(
        apChains: 4,
        clientChains: 2,
        direction: LinkDirection.downlink,
      );
      expect(link.idealTxBfGainDb, closeTo(3.0103, 1e-4));
    });

    test('TxBF: 4 chains over 1 stream is 6.02 dB', () {
      expect(MimoMath.idealArrayGainDb(4, 1), closeTo(6.0206, 1e-4));
    });

    test('no spare chains, no array gain', () {
      expect(MimoMath.idealArrayGainDb(2, 2), 0);
      expect(MimoMath.idealArrayGainDb(1, 1), 0);
    });

    test('uplink: the AP spare receive chains give combining gain', () {
      const MimoLink up = MimoLink(
        apChains: 4,
        clientChains: 2,
        direction: LinkDirection.uplink,
      );
      expect(up.idealCombiningGainDb, closeTo(3.0103, 1e-4));
      // The client does not beamform in this model.
      expect(up.isBeamformed, isFalse);
      expect(up.idealTxBfGainDb, 0);
    });

    test('vice versa: a 4x4 client gains on receive in the downlink', () {
      const MimoLink down = MimoLink(
        apChains: 2,
        clientChains: 4,
        direction: LinkDirection.downlink,
      );
      expect(down.idealTxBfGainDb, 0);
      expect(down.idealCombiningGainDb, closeTo(3.0103, 1e-4));
    });

    test('beamforming off removes the TxBF gain', () {
      const MimoLink off = MimoLink(
        apChains: 4,
        clientChains: 1,
        direction: LinkDirection.downlink,
        beamforming: false,
      );
      expect(off.isBeamformed, isFalse);
      expect(off.idealTxBfGainDb, 0);
    });
  });

  group('array factor', () {
    test('the steered array factor peaks at the steering angle', () {
      for (final int n in <int>[2, 3, 4, 8]) {
        for (final double steer in <double>[-50, -20, 0, 15, 40, 60]) {
          double bestAngle = -90;
          double best = -1;
          for (double a = -90; a <= 90; a += 0.1) {
            final double af = MimoMath.arrayFactor(
              elements: n,
              angleDeg: a,
              steerDeg: steer,
            );
            if (af > best) {
              best = af;
              bestAngle = a;
            }
          }
          expect(bestAngle, closeTo(steer, 0.11), reason: 'N=$n steer=$steer');
          expect(best, closeTo(n.toDouble(), 1e-9));
          expect(
            MimoMath.patternDb(elements: n, angleDeg: steer, steerDeg: steer),
            closeTo(0, 1e-9),
          );
        }
      }
    });

    test('4 elements at lambda/2, broadside: first null at 30 deg', () {
      // Nulls where N psi / 2 = pi, psi = pi sin(phi): sin(phi) = 2 / N.
      expect(
        MimoMath.arrayFactor(elements: 4, angleDeg: 30, steerDeg: 0),
        lessThan(1e-12),
      );
    });

    test('one element has no pattern', () {
      expect(MimoMath.patternDb(elements: 1, angleDeg: 70, steerDeg: 0), 0);
    });
  });

  group('capture', () {
    test('a 1-chain sniffer cannot decode a 2-stream frame', () {
      expect(MimoMath.canDecode(receiveChains: 1, streams: 2), isFalse);
      expect(MimoMath.canDecode(receiveChains: 2, streams: 2), isTrue);
      expect(MimoMath.canDecode(receiveChains: 4, streams: 1), isTrue);
    });

    test('the cited measurement is the corrected, signal-matched pair', () {
      expect(CaptureMeasurement.fcsFailBeamformedPct, 50.8);
      expect(CaptureMeasurement.fcsFailNotBeamformedPct, 5.1);
      expect(
        (CaptureMeasurement.fcsFailBeamformedPct /
                CaptureMeasurement.fcsFailNotBeamformedPct)
            .round(),
        CaptureMeasurement.ratio,
      );
    });
  });

  group('sounding estimate', () {
    test('Givens angle counts', () {
      expect(SoundingEstimate.angleCount(2, 1), 2);
      expect(SoundingEstimate.angleCount(2, 2), 2);
      expect(SoundingEstimate.angleCount(3, 2), 6);
      expect(SoundingEstimate.angleCount(4, 1), 6);
      expect(SoundingEstimate.angleCount(4, 2), 10);
      expect(SoundingEstimate.angleCount(4, 4), 12);
      expect(SoundingEstimate.angleCount(8, 2), 26);
    });

    test('HE-LTF counts round odd antenna counts up', () {
      expect(
        <int>[for (int n = 1; n <= 8; n++) SoundingEstimate.heLtfCount(n)],
        <int>[1, 2, 4, 4, 6, 6, 8, 8],
      );
    });

    test('NDPA at 6 Mbps is 60 us', () {
      final SoundingEstimate s = SoundingEstimate(
        nr: 4,
        nc: 2,
        width: ChannelWidth.w80,
      );
      // 16 + 200 + 6 = 222 bits over 24 bits per symbol: 10 symbols.
      expect(s.ndpaUs, 60);
      // 36 + 4 HE-LTFs x 8 + 4 PE.
      expect(s.ndpUs, 72);
    });

    test('4x2 at 80 MHz: report about 1.6 kB, exchange under 0.3 ms', () {
      final SoundingEstimate s = SoundingEstimate(
        nr: 4,
        nc: 2,
        width: ChannelWidth.w80,
      );
      expect(s.subcarrierGroups, 250);
      // 16 SNR bits + 250 x 5 phi x 6 + 250 x 5 psi x 4 = 12,516 bits.
      expect(s.reportBodyBits, 12516);
      expect(s.reportBytes, 1565 + 35);
      expect(s.reportRateMbps, closeTo(216.18, 0.01));
      expect(
        s.totalUs,
        closeTo(s.segments.fold<double>(0, (a, b) => a + b.us), 1e-9),
      );
      expect(s.totalUs, inInclusiveRange(250, 300));
      expect(s.shareOfAirtime(10), closeTo(s.totalUs / 10000, 1e-12));
    });

    test('the report grows with Nr x Nc and with the channel width', () {
      int bytes(int nr, int nc, ChannelWidth w) =>
          SoundingEstimate(nr: nr, nc: nc, width: w).reportBytes;
      expect(
        bytes(4, 2, ChannelWidth.w80),
        greaterThan(bytes(2, 2, ChannelWidth.w80)),
      );
      expect(
        bytes(4, 4, ChannelWidth.w80),
        greaterThan(bytes(4, 2, ChannelWidth.w80)),
      );
      expect(
        bytes(8, 2, ChannelWidth.w80),
        greaterThan(bytes(4, 2, ChannelWidth.w80)),
      );
      expect(
        bytes(4, 2, ChannelWidth.w160),
        greaterThan(bytes(4, 2, ChannelWidth.w80)),
      );
      expect(
        bytes(4, 2, ChannelWidth.w20),
        lessThan(bytes(4, 2, ChannelWidth.w40)),
      );
    });

    test('a shorter sounding interval costs a larger share', () {
      final SoundingEstimate s = SoundingEstimate(
        nr: 4,
        nc: 1,
        width: ChannelWidth.w80,
      );
      expect(s.shareOfAirtime(5), greaterThan(s.shareOfAirtime(50)));
      expect(s.shareOfAirtime(0), 0);
    });
  });
}
