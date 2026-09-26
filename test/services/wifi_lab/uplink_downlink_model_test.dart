// Pins the Uplink vs Downlink model (spec 28, "Done means"):
//   - uplink RSSI moves with client power and AP antenna gain, not AP power;
//     downlink the reverse;
//   - AP power above client power with equal antenna gains: the downlink
//     ring is the larger;
//   - US Standard Power keeps the client exactly 6 dB below the AP's
//     authorized power as the AP moves (and GVP the same);
//   - EU LPI applies no offset;
//   - "turn AP down to match" never changes the uplink;
//   - no string in the tool recommends matching power.
// Plus determinism and the reuse of the Rate vs Range math.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/uplink_downlink_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/uplink_downlink_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/uplink_downlink_readouts.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_vs_range_math.dart';

const double _eps = 1e-9;

void main() {
  const UdConfig base = UdConfig(clientDistanceM: 25);

  group('each direction has its own inputs', () {
    test('uplink moves with client power and AP gain, not AP power', () {
      final double ul = base.uplink.rssiDbm;
      expect(base.withApTx(28).uplink.rssiDbm, closeTo(ul, _eps));
      expect(base.withApTx(3).uplink.rssiDbm, closeTo(ul, _eps));
      expect(base.withClientTx(20).uplink.rssiDbm, closeTo(ul + 6, _eps));
      expect(base.withApGain(7).uplink.rssiDbm, closeTo(ul + 3, _eps));
    });

    test('downlink moves with AP power and client gain, not client power', () {
      final double dl = base.downlink.rssiDbm;
      expect(base.withClientTx(2).downlink.rssiDbm, closeTo(dl, _eps));
      expect(base.withClientTx(24).downlink.rssiDbm, closeTo(dl, _eps));
      expect(base.withApTx(26).downlink.rssiDbm, closeTo(dl + 6, _eps));
      expect(base.withClientGain(1).downlink.rssiDbm, closeTo(dl + 3, _eps));
    });

    test('imbalance equals AP power minus client power at any distance', () {
      final UdConfig c = base.withApTx(23).withClientTx(11).withApGain(6);
      expect(c.imbalanceDb, closeTo(12, _eps));
      for (final double d in <double>[1, 7, 40, 300]) {
        final UdConfig at = c.withClientDistance(d);
        expect(
          at.downlink.rssiDbm - at.uplink.rssiDbm,
          closeTo(12, 1e-9),
        );
      }
    });

    test('the defaults: 5 GHz ch 100, the numbers the help example quotes', () {
      const UdConfig c = UdConfig();
      expect(c.freqMHz, 5500);
      expect(c.apEirpDbm, 24);
      expect(c.clientEirpDbm, 12);
      // Path loss at 20 m, n = 3: FSPL(1 m) at 5500 MHz + 30 log10(20).
      final double pl = RateVsRangeMath.pathLossDb(20, 5500, 3);
      expect(c.downlink.rssiDbm, closeTo(24 - pl - 2, _eps));
      expect(c.uplink.rssiDbm, closeTo(12 - pl + 4, _eps));
      expect(c.imbalanceDb, closeTo(6, _eps));
      expect(c.downlink.mcs, RateVsRangeMath.mcsFor(c.downlink.rssiDbm, 20));
      expect(c.downlinkRingM, greaterThan(c.uplinkRingM));
      expect(
        c.asymmetryZoneM,
        closeTo(c.downlinkRingM - c.uplinkRingM, _eps),
      );
    });

    test('rings sit where each direction falls to the MCS 0 floor', () {
      final UdConfig c = base.withBand(WifiBand.band6).withWidth(80);
      expect(
        c.withClientDistance(c.downlinkRingM).downlink.rssiDbm,
        closeTo(RateVsRangeMath.sensitivityDbm(0, 80), 1e-6),
      );
      expect(
        c.withClientDistance(c.uplinkRingM).uplink.rssiDbm,
        closeTo(RateVsRangeMath.sensitivityDbm(0, 80), 1e-6),
      );
    });

    test('deterministic: the same inputs give the same numbers', () {
      UdConfig build() => const UdConfig()
          .withPreset(UdPreset.usLpi)
          .withWidth(160)
          .withApTx(12)
          .withClientGain(1)
          .withClientDistance(33);
      final UdConfig a = build();
      final UdConfig b = build();
      expect(a.downlink, b.downlink);
      expect(a.uplink, b.uplink);
      expect(a.downlinkRingM, b.downlinkRingM);
    });
  });

  group('rings', () {
    test('AP power above client power with equal gains: downlink ring larger',
        () {
      for (final WifiBand band in WifiBand.values) {
        final UdConfig c = base
            .withBand(band)
            .withApGain(2)
            .withClientGain(2)
            .withApTx(20)
            .withClientTx(14);
        expect(c.downlinkRingM, greaterThan(c.uplinkRingM), reason: '$band');
        expect(c.zoneMiddleM, isNotNull);
        final UdConfig mid = c.withClientDistance(c.zoneMiddleM!);
        expect(mid.clientInZone, isTrue);
        expect(mid.downlink.mcs, isNotNull, reason: 'client decodes the AP');
        expect(mid.uplink.mcs, isNull, reason: 'AP cannot decode the client');
      }
    });

    test('equal powers and equal gains: the rings coincide, no zone', () {
      final UdConfig c = base
          .withApGain(3)
          .withClientGain(3)
          .withApTx(15)
          .withClientTx(15);
      expect(c.downlinkRingM, closeTo(c.uplinkRingM, 1e-9));
      expect(c.zoneMiddleM, isNull);
    });
  });

  group('regulatory presets', () {
    test('US Standard Power: client exactly 6 dB below the AP authorized '
        'power as the AP moves', () {
      UdConfig c = base.withPreset(UdPreset.usStandardPower);
      expect(c.band, WifiBand.band6);
      for (double ap = 0; ap <= UdConfig.apTxMax; ap += 1.5) {
        c = c.withApTx(ap);
        expect(c.authorizedApEirpDbm, closeTo(c.apEirpDbm, _eps));
        expect(
          c.clientEirpDbm,
          closeTo(c.authorizedApEirpDbm! - 6, _eps),
          reason: 'AP $ap dBm',
        );
      }
      // Across widths and gains too.
      for (final int w in WifiBand.band6.widthsMHz) {
        final UdConfig at = c.withWidth(w).withApGain(8).withApTx(26);
        expect(at.clientEirpDbm, closeTo(at.apEirpDbm - 6, _eps));
        expect(at.apEirpDbm, lessThanOrEqualTo(36 + _eps));
      }
    });

    test('US GVP: the same 6 dB rule under a 24 dBm AP cap', () {
      UdConfig c = base.withPreset(UdPreset.usGvp);
      for (double ap = 0; ap <= UdConfig.apTxMax; ap += 2) {
        c = c.withApTx(ap);
        expect(c.apEirpDbm, lessThanOrEqualTo(24 + _eps));
        expect(c.clientEirpDbm, closeTo(c.apEirpDbm - 6, _eps));
      }
    });

    test('US LPI: the client limit is flat, not tied to the AP', () {
      final UdConfig c = base.withPreset(UdPreset.usLpi).withWidth(320);
      expect(c.apEirpDbm, closeTo(30, _eps), reason: 'AP set to its cap');
      expect(c.clientEirpDbm, closeTo(24, _eps));
      final UdConfig lower = c.withApTx(5);
      expect(lower.clientEirpDbm, closeTo(24, _eps));
      // PSD-limited at 20 MHz: 5 and -1 dBm/MHz over 20 MHz.
      final UdConfig narrow = c.withWidth(20);
      expect(narrow.apEirpDbm, closeTo(5 + 13.0103, 1e-3));
      expect(narrow.clientEirpDbm, closeTo(-1 + 13.0103, 1e-3));
    });

    test('EU LPI: AP and client share one limit, no offset', () {
      for (final int w in WifiBand.band6.widthsMHz) {
        final UdConfig c = base.withPreset(UdPreset.euLpi).withWidth(w);
        expect(c.apCeilingEirpDbm, closeTo(c.clientLimitEirpDbm!, _eps));
        expect(c.clientEirpDbm, closeTo(c.apEirpDbm, _eps), reason: '$w MHz');
        expect(c.clientEirpDbm, closeTo(23, _eps));
      }
    });

    test('a preset holds the client slider; Custom frees it', () {
      final UdConfig c = base.withPreset(UdPreset.usLpi);
      expect(c.withClientTx(3).clientEirpDbm, c.clientEirpDbm);
      final UdConfig free = c.withPreset(UdPreset.custom).withClientTx(3);
      expect(free.clientTxEffectiveDbm, 3);
    });

    test('leaving 6 GHz returns to Custom', () {
      final UdConfig c = base
          .withPreset(UdPreset.usStandardPower)
          .withBand(WifiBand.band5);
      expect(c.preset, UdPreset.custom);
      expect(c.authorizedApEirpDbm, isNull);
    });
  });

  group('turn AP down to match', () {
    final List<UdConfig> scenes = <UdConfig>[
      base,
      base.withApTx(30).withClientTx(8),
      base.withBand(WifiBand.band24).withApGain(8).withClientGain(-5),
      base.withPreset(UdPreset.usStandardPower),
      // Standard Power with a 0 dBi AP antenna: the AP out-transmits the
      // client, so the match runs, and the grant (and the client) must stay.
      base.withApGain(0).withPreset(UdPreset.usStandardPower).withApTx(20),
      base.withPreset(UdPreset.usGvp).withApTx(14),
      base.withPreset(UdPreset.usLpi).withWidth(320),
      base.withPreset(UdPreset.euLpi).withApGain(0).withClientGain(3),
    ];

    test('never changes the uplink', () {
      for (final UdConfig s in scenes) {
        final UdConfig m = s.matchApToClient();
        expect(m.uplink.rssiDbm, closeTo(s.uplink.rssiDbm, _eps));
        expect(m.uplinkRingM, closeTo(s.uplinkRingM, _eps));
        expect(m.clientEirpDbm, closeTo(s.clientEirpDbm, _eps));
        // And putting it back restores the downlink.
        expect(
          m.undoMatch().downlink.rssiDbm,
          closeTo(s.downlink.rssiDbm, _eps),
        );
      }
    });

    test('shrinks the downlink ring whenever it does anything', () {
      expect(scenes.where((UdConfig s) => s.canMatch).length, greaterThan(3));
      expect(scenes[4].canMatch, isTrue, reason: 'the Standard Power case');
      expect(
        scenes[4].matchApToClient().authorizedApEirpDbm,
        scenes[4].authorizedApEirpDbm,
      );
      for (final UdConfig s in scenes) {
        if (!s.canMatch) continue;
        final UdConfig m = s.matchApToClient();
        expect(m.apTxDbm, closeTo(s.clientTxEffectiveDbm, _eps));
        expect(m.downlinkRingM, lessThan(s.downlinkRingM));
        expect(m.isMatched, isTrue);
      }
    });

    test('is refused when the AP already transmits no more than the client',
        () {
      final UdConfig s = base.withApTx(10).withClientTx(18);
      expect(s.canMatch, isFalse);
      expect(identical(s.matchApToClient(), s), isTrue);
    });

    test('the controller toggles it and the summary says what changed', () {
      final UplinkDownlinkController k = UplinkDownlinkController();
      final double ul = k.config.uplink.rssiDbm;
      k.toggleMatch();
      expect(k.config.isMatched, isTrue);
      expect(k.config.uplink.rssiDbm, closeTo(ul, _eps));
      final String s = udMatchSummary(k.beforeMatch!, k.config);
      expect(s, contains('What did not change: the uplink'));
      expect(s, contains('shrank'));
      k.toggleMatch();
      expect(k.config.isMatched, isFalse);
      expect(k.config.apTxDbm, UdConfig.defaultApTxDbm);
      k.dispose();
    });
  });

  group('controller', () {
    test('Up and Down move the client a quarter doubling; R resets', () {
      final UplinkDownlinkController k = UplinkDownlinkController();
      k.setClientDistance(10);
      for (int i = 0; i < 4; i++) {
        k.presenterActions.sliderUp!();
      }
      expect(k.config.clientDistanceM, closeTo(20, 1e-9));
      k.presenterActions.sliderDown!();
      expect(k.config.clientDistanceM, closeTo(16.818, 1e-3));
      k
        ..setApTx(5)
        ..setPreset(UdPreset.euLpi)
        ..setRevealed(true);
      k.presenterActions.reset!();
      expect(k.config.apTxDbm, UdConfig.defaultApTxDbm);
      expect(k.config.preset, UdPreset.custom);
      expect(k.revealed, isFalse);
      k.dispose();
    });

    test('the client never leaves the view', () {
      final UplinkDownlinkController k = UplinkDownlinkController();
      k.setClientDistance(1e9);
      expect(k.config.clientDistanceM, k.viewRangeM);
      k.dispose();
    });

    test('the view holds both rings, and the pre-match ring while matched',
        () {
      final UplinkDownlinkController k = UplinkDownlinkController();
      for (final double ap in <double>[0, 10, 20, 30]) {
        k.setApTx(ap);
        expect(k.viewRangeM, greaterThan(k.config.downlinkRingM));
        expect(k.viewRangeM, greaterThan(k.config.uplinkRingM));
      }
      k
        ..setApTx(24)
        ..matchApToClient();
      expect(k.viewRangeM, greaterThan(k.beforeMatch!.downlinkRingM));
      // A small slider move stays inside one nice range.
      k
        ..undoMatch()
        ..setApTx(20);
      final double r = k.viewRangeM;
      k.setApTx(20.5);
      expect(k.viewRangeM, r);
      k.dispose();
    });
  });

  group('copy', () {
    /// Recommending language anywhere near "match". The tool may SAY
    /// "match" (it names the vendor advice to show what it does); it may
    /// never tell anyone to do it.
    final RegExp recommends = RegExp(
      r"\b(should|recommend\w*|best practice|you need to|make sure|always|"
      r"ideal\w*|optimal\w*|improv\w*|fix(es)? the|better)\b[^.]{0,80}"
      r"\bmatch"
      r"|\bmatch\w*[^.]{0,80}\b(recommend\w*|best practice|improv\w*|"
      r"is better|helps?|fix(es)? the uplink|balance[sd]? the link)\b",
      caseSensitive: false,
    );

    List<String> toolStrings() {
      final List<String> out = <String>[
        ...UplinkDownlinkExplainer.lessons,
        UplinkDownlinkPredict.question,
        for (final UdPreset p in UdPreset.values) ...<String>[p.label, p.rule],
      ];
      final UplinkDownlinkController k = UplinkDownlinkController();
      for (final UdPreset p in UdPreset.values) {
        k.setPreset(p);
        out
          ..add(k.copyText())
          ..add(udImbalanceSentence(k.config))
          ..add(udZoneSentence(k.config));
        k.matchApToClient();
        out.add(k.copyText());
        k.undoMatch();
      }
      k.dispose();
      // Every string literal in the tool's source files.
      final RegExp lit = RegExp(r"'((?:[^'\\]|\\.)*)'");
      for (final FileSystemEntity f in <FileSystemEntity>[
        ...Directory('lib/screens/tools/calculators').listSync(),
        File('lib/services/wifi_lab/uplink_downlink_model.dart'),
      ]) {
        if (f is! File || !f.path.contains('uplink_downlink')) continue;
        final String src = f.readAsStringSync();
        // Adjacent literals form one sentence: join them before sweeping.
        final String joined = src.replaceAll(RegExp(r"'\s*\n\s*'"), '');
        out.addAll(lit.allMatches(joined).map((RegExpMatch m) => m.group(1)!));
      }
      // The help entry.
      final Map<String, dynamic> help =
          (jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                  as Map<String, dynamic>)['tools']
              as Map<String, dynamic>;
      out.add(jsonEncode(help[kUplinkDownlinkToolId]));
      return out;
    }

    test('the sweep itself catches a recommendation', () {
      for (final String bad in <String>[
        'You should match AP power to the client.',
        'Best practice is to turn the AP down to match the client.',
        'Matching the AP to the client improves roaming.',
        'Match power to balance the link.',
      ]) {
        expect(recommends.hasMatch(bad), isTrue, reason: bad);
      }
    });

    test('no string in the tool recommends matching power', () {
      final List<String> all = toolStrings();
      expect(all.length, greaterThan(50), reason: 'the sweep saw the copy');
      final List<String> hits = <String>[
        for (final String s in all)
          if (recommends.hasMatch(s)) s,
      ];
      expect(hits, isEmpty);
    });
  });
}
