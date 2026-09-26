// Unit tests for the Repeaters and Mesh Backhaul model (spec 36, "Done
// means"): two equal same-channel hops give exactly half; hops of 100 and
// 25 Mb/s give 20 on one channel and 25 with a dedicated backhaul radio; a
// third same-channel hop lowers the total again; wired backhaul equals the
// last hop alone; moving the relay toward the root AP raises the backhaul
// hop's rate; no string names a vendor or product. Plus the reuse pins (path
// loss is Roaming Walk's, the rate is Airtime Anatomy's) and determinism.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_anatomy.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_vs_range_math.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/repeater_mesh_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/roaming_walk_engine.dart';

void main() {
  group('the relay formula (rmCombine)', () {
    test('two equal same-channel hops give exactly half of one hop', () {
      expect(rmCombine(<double>[100, 100], RmBackhaul.sameChannel), 50);
      expect(rmCombine(<double>[346.5, 346.5], RmBackhaul.sameChannel), 173.25);
    });

    test('hops of 100 and 25 Mb/s: 20 on one channel, 25 with a dedicated '
        'backhaul radio', () {
      expect(
        rmCombine(<double>[100, 25], RmBackhaul.sameChannel),
        closeTo(20, 1e-12),
      );
      expect(rmCombine(<double>[100, 25], RmBackhaul.dedicated), 25);
    });

    test('a third same-channel hop lowers the total further', () {
      final double two = rmCombine(<double>[100, 100], RmBackhaul.sameChannel);
      final double three = rmCombine(<double>[
        100,
        100,
        100,
      ], RmBackhaul.sameChannel);
      expect(three, lessThan(two));
      expect(three, closeTo(100 / 3, 1e-12));
    });

    test('wired backhaul equals the last hop alone', () {
      expect(rmCombine(<double>[10, 400], RmBackhaul.wired), 400);
      expect(rmCombine(<double>[900, 5, 70], RmBackhaul.wired), 70);
    });

    test('a hop with no link stops the chain, except a wired one', () {
      expect(rmCombine(<double>[0, 100], RmBackhaul.sameChannel), 0);
      expect(rmCombine(<double>[0, 100], RmBackhaul.dedicated), 0);
      expect(rmCombine(<double>[0, 100], RmBackhaul.wired), 100);
    });
  });

  group('the full model', () {
    test('two equal same-channel hops give exactly half, end to end', () {
      final RmResult r = computeRepeaterMesh(
        RmConfig(relaysM: const <double>[18], clientM: 36),
      );
      expect(r.hops, hasLength(2));
      expect(r.hops[0].throughputMbps, r.hops[1].throughputMbps);
      expect(r.endToEndMbps, r.hops[0].throughputMbps / 2);
      // On one channel the two hops share the air half and half.
      expect(r.hops[0].airShare, closeTo(0.5, 1e-12));
      expect(r.hops[1].airShare, closeTo(0.5, 1e-12));
      // Equal hops: no single slowest hop to mark.
      expect(r.slowestIsUnique, isFalse);
    });

    test('dedicated backhaul gives the slower hop; its hop is busy all the '
        'time', () {
      final RmResult r = computeRepeaterMesh(
        RmConfig(
          relaysM: const <double>[10],
          clientM: 36,
          backhaul: RmBackhaul.dedicated,
        ),
      );
      final double slow = r.hops[1].throughputMbps;
      expect(slow, lessThan(r.hops[0].throughputMbps));
      expect(r.endToEndMbps, slow);
      expect(r.bottleneck, 1);
      expect(r.hops[1].airShare, 1);
      expect(r.hops[0].airShare, lessThan(1));
    });

    test('each added same-channel relay lowers the total and adds delay', () {
      final RmConfig one = RmConfig(clientM: 36).withRelayCount(1);
      final RmConfig two = one.withRelayCount(2);
      final RmConfig three = one.withRelayCount(3);
      // Keep every hop at the same rate so only the hop count changes.
      final List<RmConfig> same = <RmConfig>[
        RmConfig(relaysM: const <double>[10], clientM: 20),
        RmConfig(relaysM: const <double>[10, 20], clientM: 30),
        RmConfig(relaysM: const <double>[10, 20, 30], clientM: 40),
      ];
      final List<RmResult> r = same.map(computeRepeaterMesh).toList();
      expect(r[1].endToEndMbps, lessThan(r[0].endToEndMbps));
      expect(r[2].endToEndMbps, lessThan(r[1].endToEndMbps));
      expect(r[0].endToEndMbps, closeTo(r[0].hops[0].throughputMbps / 2, 1e-9));
      expect(r[2].endToEndMbps, closeTo(r[2].hops[0].throughputMbps / 4, 1e-9));
      expect(r[0].delayMs, 2);
      expect(r[1].delayMs, 3);
      expect(r[2].delayMs, 4);
      expect(r[0].directDelayMs, 1);
      // withRelayCount spaces the relays evenly toward the client.
      expect(one.relaysM, <double>[18]);
      expect(two.relaysM, <double>[12, 24]);
      expect(three.relaysM, <double>[9, 18, 27]);
    });

    test('wired backhaul equals the last hop alone', () {
      final RmResult r = computeRepeaterMesh(
        RmConfig(
          relaysM: const <double>[25, 50],
          clientM: 55,
          backhaul: RmBackhaul.wired,
        ),
      );
      // The 25 m radio hops would be slow; the cable makes them irrelevant.
      expect(r.hops[0].wired, isTrue);
      expect(r.hops[1].wired, isTrue);
      expect(r.hops[2].wired, isFalse);
      expect(r.endToEndMbps, r.hops[2].throughputMbps);
      expect(r.endToEndMbps, rmLink(RmBand.ghz5, 5, 0.6).throughputMbps);
      expect(r.hops[0].airShare, 0);
      expect(r.hops[2].airShare, 1);
    });

    test('moving the relay toward the root AP raises the backhaul hop\'s '
        'rate', () {
      final RmConfig far = RmConfig(relaysM: const <double>[30], clientM: 32);
      final RmConfig near = far.withNodeAt(1, 12);
      expect(near.relaysM, <double>[12]);
      final RmHop farBackhaul = computeRepeaterMesh(far).hops.first;
      final RmHop nearBackhaul = computeRepeaterMesh(near).hops.first;
      expect(nearBackhaul.link.rxDbm, greaterThan(farBackhaul.link.rxDbm));
      expect(nearBackhaul.link.mcs!, greaterThan(farBackhaul.link.mcs!));
      expect(nearBackhaul.link.phyMbps, greaterThan(farBackhaul.link.phyMbps));
      // And across the whole corridor, never lower as it moves in.
      double last = double.infinity;
      for (double m = 4; m <= 58; m += 2) {
        final double t = rmLink(RmBand.ghz5, m, 0.6).phyMbps;
        expect(t, lessThanOrEqualTo(last), reason: '$m m');
        last = t;
      }
    });

    test('the question: a repeater by the laptop is slower than the AP '
        'alone', () {
      final RmResult r = computeRepeaterMesh(
        RmConfig(relaysM: const <double>[30], clientM: 32),
      );
      // Full bars to the laptop: the top MCS on the 2 m hop.
      expect(r.hops[1].link.mcs, kRmMaxHeMcs);
      // The weak hop is the repeater's link back to the AP.
      expect(r.bottleneck, 0);
      expect(r.slowestIsUnique, isTrue);
      expect(r.endToEndMbps, lessThan(r.direct.throughputMbps));
      expect(r.versusDirect!, lessThan(1));
    });

    test('a hop past the last MCS has no link and the chain says so', () {
      final RmResult r = computeRepeaterMesh(
        RmConfig(relaysM: const <double>[50], clientM: 52),
      );
      expect(r.hops[0].link.hasLink, isFalse);
      expect(r.hops[0].link.mcs, isNull);
      expect(r.broken, isTrue);
      expect(r.endToEndMbps, 0);
    });

    test('nodes stay in order and inside the corridor', () {
      final RmConfig c = RmConfig(relaysM: const <double>[10, 20], clientM: 30);
      expect(c.withNodeAt(1, 25).relaysM, <double>[18, 20]);
      expect(c.withNodeAt(2, 1).relaysM, <double>[10, 12]);
      expect(c.withNodeAt(3, 99).clientM, kRmCorridorM);
      expect(c.withNodeAt(3, 0).clientM, 22);
      // The root AP never moves.
      expect(c.withNodeAt(0, 5), c);
      expect(c.withRelayCount(9).relayCount, kRmMaxRelays);
      expect(c.withRelayCount(0).relayCount, kRmMinRelays);
    });

    test('deterministic: the same inputs give the same numbers', () {
      final RmConfig c = RmConfig(
        relaysM: const <double>[11.5, 23],
        clientM: 41,
        band: RmBand.ghz6,
        efficiency: 0.5,
      );
      final RmResult a = computeRepeaterMesh(c);
      final RmResult b = computeRepeaterMesh(c);
      expect(a.endToEndMbps, b.endToEndMbps);
      for (int i = 0; i < a.hops.length; i++) {
        expect(a.hops[i].link.rxDbm, b.hops[i].link.rxDbm);
        expect(a.hops[i].throughputMbps, b.hops[i].throughputMbps);
      }
    });
  });

  group('reused, not re-derived', () {
    test('path loss is Roaming Walk\'s', () {
      for (final RmBand band in RmBand.values) {
        for (final double d in <double>[1, 7.5, 18, 42]) {
          expect(
            rmRxDbm(band, d),
            RoamWalkConfig(
              band: band.roamBand,
              eirpDbm: kRmEirpDbm,
              pathLossExponent: kRmExponent,
            ).meanRssiAtDistance(d),
          );
        }
      }
    });

    test('the MCS is Rate vs Range\'s and the PHY rate is Airtime '
        'Anatomy\'s', () {
      final RmLink l = rmLink(RmBand.ghz5, 18, 0.6);
      expect(l.mcs, RateVsRangeMath.mcsFor(l.rxDbm, 80));
      expect(
        l.phyMbps,
        computeAirtime(
          AirtimeScenario(
            band: AirtimeBand.ghz5,
            phy: AirtimePhy.he,
            widthMhz: 80,
            mcs: l.mcs!,
            streams: 2,
            guardInterval: GuardInterval.gi08,
          ),
        ).phyRateMbps,
      );
      expect(l.throughputMbps, closeTo(l.phyMbps * 0.6, 1e-9));
      // 802.11ax, 80 MHz, 2 streams, MCS 11, 0.8 us: 1,201 Mb/s.
      expect(rmPhyRateMbps(RmBand.ghz5, 11), closeTo(1201.0, 0.1));
      // MCS 12 and 13 do not exist in 802.11ax: held at 11.
      expect(rmLink(RmBand.ghz24, 1, 1).mcs, kRmMaxHeMcs);
    });

    test('efficiency scales every hop and the total linearly', () {
      final RmConfig c = RmConfig();
      final RmResult lo = computeRepeaterMesh(c.copyWith(efficiency: 0.4));
      final RmResult hi = computeRepeaterMesh(c.copyWith(efficiency: 0.8));
      expect(hi.endToEndMbps, closeTo(lo.endToEndMbps * 2, 1e-9));
    });
  });

  test('no string names a vendor or product', () {
    const List<String> banned = <String>[
      'cisco',
      'aruba',
      'juniper',
      'mist',
      'ubiquiti',
      'unifi',
      'eero',
      'orbi',
      'netgear',
      'tp-link',
      'deco',
      'linksys',
      'velop',
      'google',
      'nest',
      'asus',
      'aimesh',
      'plume',
      'meraki',
      'ruckus',
      'extreme',
      'fortinet',
      'apple',
      'airport',
      'amazon',
      'd-link',
      'mikrotik',
      'cambium',
      'engenius',
      'huawei',
      'tenda',
      'mercusys',
      'belkin',
      'xfinity',
      'comcast',
    ];
    final List<String> sources = <String>[
      'lib/services/wifi_lab/repeater_mesh_model.dart',
      'lib/screens/tools/calculators/repeater_mesh_controller.dart',
      'lib/screens/tools/calculators/repeater_mesh_controls.dart',
      'lib/screens/tools/calculators/repeater_mesh_stage.dart',
      'lib/screens/tools/calculators/repeater_mesh_painter.dart',
      'lib/screens/tools/calculators/repeater_mesh_screen.dart',
    ];
    final StringBuffer all = StringBuffer();
    final RegExp literal = RegExp(r"'(?:[^'\\]|\\.)*'");
    for (final String path in sources) {
      final String src = File(path).readAsStringSync();
      for (final RegExpMatch m in literal.allMatches(src)) {
        all.writeln(m[0]);
      }
    }
    final Map<String, dynamic> help =
        ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                    as Map<String, dynamic>)['tools']
                as Map<String, dynamic>)[kRepeaterMeshToolId]
            as Map<String, dynamic>;
    all.writeln(jsonEncode(help));
    for (final RmBackhaul b in RmBackhaul.values) {
      all.writeln('${b.label} ${b.short} ${b.rule}');
    }
    final String text = all.toString().toLowerCase();
    for (final String name in banned) {
      expect(
        RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(text),
        isFalse,
        reason: name,
      );
    }
  });
}
