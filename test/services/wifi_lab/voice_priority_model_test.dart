// Voice Priority, End to End: the model's teaching claims.
//
//  1. The call gets the Voice queue only when EF survives every hop and the
//     AP maps it per RFC 8325 (EF -> UP 6 -> AC_VO).
//  2. Lose the marking at the tunnel, at the provider or at the AP, and the
//     call lands in Best Effort (UP 0).
//  3. The older top-three-bits mapping sends EF to UP 5, Video (RFC 8325
//     section 2.3), even when nothing is lost.
//  4. While a download runs, Best Effort waits far longer than Voice; with
//     no download the queues are close.
//  5. The Wi-Fi hop's numbers are the Medium Access Simulator engine's own
//     output: rerunning the engine reproduces the table the screen reads.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/voice_priority_model.dart';

void main() {
  group('DSCP to UP to access category', () {
    test('RFC 8325 maps EF to UP 6 and default to UP 0', () {
      expect(upForDscp(kDscpEf, ApMapping.rfc8325), 6);
      expect(upForDscp(kDscpDefault, ApMapping.rfc8325), 0);
    });

    test('the top three bits of EF (101110) are 5', () {
      expect(upForDscp(kDscpEf, ApMapping.topThreeBits), 5);
      expect(upForDscp(kDscpDefault, ApMapping.topThreeBits), 0);
    });

    test('only EF and default are accepted', () {
      expect(() => upForDscp(34, ApMapping.rfc8325), throwsArgumentError);
    });

    test('UP to access category follows the four WMM queues', () {
      expect(accessCategoryForUp(0), AccessCategory.bestEffort);
      expect(accessCategoryForUp(1), AccessCategory.background);
      expect(accessCategoryForUp(2), AccessCategory.background);
      expect(accessCategoryForUp(3), AccessCategory.bestEffort);
      expect(accessCategoryForUp(4), AccessCategory.video);
      expect(accessCategoryForUp(5), AccessCategory.video);
      expect(accessCategoryForUp(6), AccessCategory.voice);
      expect(accessCategoryForUp(7), AccessCategory.voice);
      expect(() => accessCategoryForUp(8), throwsArgumentError);
    });
  });

  group('where the marking is lost', () {
    test('nowhere, RFC 8325: Voice, EF at every hop', () {
      final VpTrip t = VpTrip(const VpConfig());
      expect(t.queue, AccessCategory.voice);
      expect(t.up, 6);
      expect(t.inVoiceQueue, isTrue);
      expect(t.hops.every((VpHop h) => h.dscpOut == kDscpEf), isTrue);
      expect(t.hops.where((VpHop h) => h.lostHere), isEmpty);
    });

    for (final MarkLoss loss in <MarkLoss>[
      MarkLoss.tunnel,
      MarkLoss.isp,
      MarkLoss.apMapping,
    ]) {
      test('${loss.name}: Best effort, UP 0, lost at exactly one hop', () {
        final VpTrip t = VpTrip(VpConfig(loss: loss));
        expect(t.queue, AccessCategory.bestEffort);
        expect(t.up, 0);
        expect(t.hops.where((VpHop h) => h.lostHere), hasLength(1));
      });
    }

    test('the tunnel hides EF from every hop after it', () {
      final VpTrip t = VpTrip(const VpConfig(loss: MarkLoss.tunnel));
      expect(t.hops[VpHopId.caller.index].dscpOut, kDscpEf);
      for (final VpHopId id in <VpHopId>[
        VpHopId.tunnel,
        VpHopId.internet,
        VpHopId.home,
      ]) {
        expect(t.hops[id.index].dscpOut, kDscpDefault, reason: id.name);
      }
      expect(t.hops[VpHopId.tunnel.index].lostHere, isTrue);
    });

    test('the provider resets it after the tunnel copied it', () {
      final VpTrip t = VpTrip(const VpConfig(loss: MarkLoss.isp));
      expect(t.hops[VpHopId.tunnel.index].dscpOut, kDscpEf);
      expect(t.hops[VpHopId.internet.index].dscpOut, kDscpDefault);
      expect(t.hops[VpHopId.internet.index].lostHere, isTrue);
    });

    test('at the AP the marking arrives as EF and is ignored', () {
      final VpTrip t = VpTrip(const VpConfig(loss: MarkLoss.apMapping));
      expect(t.dscpAtAp, kDscpEf);
      expect(t.up, 0);
      expect(t.hops[VpHopId.ap.index].lostHere, isTrue);
    });

    test('no loss but the top-three-bits mapping: Video, not Voice', () {
      final VpTrip t = VpTrip(
        const VpConfig(mapping: ApMapping.topThreeBits),
      );
      expect(t.up, 5);
      expect(t.queue, AccessCategory.video);
      expect(t.why, contains('Video, not Voice'));
    });

    test('the tunnel note says it depends on the device', () {
      final VpTrip t = VpTrip(const VpConfig());
      expect(t.hops[VpHopId.tunnel.index].note, contains('depends on'));
    });
  });

  group('the wait on the Wi-Fi hop', () {
    test('with a download, Best effort waits far longer than Voice', () {
      final VpTrip voice = VpTrip(const VpConfig());
      final VpTrip lost = VpTrip(const VpConfig(loss: MarkLoss.isp));
      expect(lost.waitUs, greaterThan(20 * voice.waitUs));
      // Behind 64 frames at about 0.4 ms each: about 26 ms.
      expect(lost.waitUs / 1000, closeTo(25.9, 0.1));
      expect(voice.waitUs / 1000, closeTo(0.48, 0.01));
    });

    test('Voice beats Video beside the download', () {
      final Map<AccessCategory, double> w = VpTrip(
        const VpConfig(),
      ).waitsByQueue;
      expect(w[AccessCategory.voice]!, lessThan(w[AccessCategory.video]!));
      expect(w[AccessCategory.video]!, lessThan(w[AccessCategory.bestEffort]!));
    });

    test('with no download, the queues are within 0.1 ms of each other', () {
      final Map<AccessCategory, double> w = VpTrip(
        const VpConfig(downloadRunning: false, loss: MarkLoss.isp),
      ).waitsByQueue;
      final double lo = w.values.reduce((double a, double b) => a < b ? a : b);
      final double hi = w.values.reduce((double a, double b) => a > b ? a : b);
      expect(hi - lo, lessThan(100));
    });

    test('Best effort grows with the frames ahead; Voice does not', () {
      double be(int n) => VpTrip(
        VpConfig(loss: MarkLoss.isp, framesAhead: n),
      ).waitUs;
      expect(be(128), greaterThan(be(64)));
      expect(be(0), closeTo(VpAirTable.bestEffortServiceUs, 1e-9));
      expect(
        VpTrip(const VpConfig(framesAhead: 200)).waitUs,
        VpTrip(const VpConfig(framesAhead: 0)).waitUs,
      );
    });

    test('frames ahead matter only in Best effort with a download', () {
      expect(VpTrip(const VpConfig()).framesAheadMatters, isFalse);
      expect(
        VpTrip(const VpConfig(loss: MarkLoss.tunnel)).framesAheadMatters,
        isTrue,
      );
      expect(
        VpTrip(
          const VpConfig(loss: MarkLoss.tunnel, downloadRunning: false),
        ).framesAheadMatters,
        isFalse,
      );
    });

    test('frames ahead are clamped', () {
      expect(const VpConfig().copyWith(framesAhead: 9999).framesAhead, 256);
      expect(const VpConfig().copyWith(framesAhead: -1).framesAhead, 0);
    });
  });

  test('the table is the Medium Access Simulator engine\'s output', () {
    for (final MapEntry<(AccessCategory, bool), double> e
        in VpAirTable.voiceAccessUs.entries) {
      final VpAirStat s = VpAirEngine.voiceAccess(
        e.key.$1,
        download: e.key.$2,
      );
      expect(s.frames, greaterThan(80), reason: '${e.key}');
      expect(s.meanAccessUs, closeTo(e.value, 1e-6), reason: '${e.key}');
    }
    expect(
      VpAirEngine.bestEffortServiceUs(),
      closeTo(VpAirTable.bestEffortServiceUs, 1e-6),
    );
  });

  test('vpMs formats', () {
    expect(vpMs(478.27), '0.48 ms');
    expect(vpMs(25886), '25.9 ms');
    expect(vpMs(150000), '150 ms');
  });
}
