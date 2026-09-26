// Model tests for the Join and Roam modes of the 802.1X and EAP Ladder
// (Wi-Fi Classroom, eap-ladder).
//
// One test per item of spec 21b's "Done means" (myPKA Deliverables/
// 2026-09-25-wifi-lab-cleanroom/specs/21b-join-and-roam-frames.md), then the
// supporting facts the model is built on (brief §1 and §2).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/eap_ladder.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';

const List<LadderMethod> _dot1x = <LadderMethod>[
  LadderMethod.eapTls,
  LadderMethod.peap,
  LadderMethod.eapTtls,
];

/// Every Join configuration that changes the frames.
Iterable<JrConfig> _joins() sync* {
  for (final JrSecurity s in JrSecurity.values) {
    for (final JrBand b in JrBand.values) {
      for (final JrScanType t in JrScanType.values) {
        for (final JrSixGhzDiscovery d in JrSixGhzDiscovery.values) {
          for (final JrAddressCheck a in JrAddressCheck.values) {
            for (final JrPmf p in JrPmf.values) {
              yield JrConfig(
                security: s,
                band: b,
                scanType: t,
                sixGhz: d,
                addressCheck: a,
                pmf: p,
              );
            }
          }
        }
      }
    }
  }
  for (final LadderMethod m in _dot1x) {
    yield JrConfig(security: JrSecurity.dot1x, eapMethod: m, certFragments: 3);
  }
}

/// Every Roam configuration that changes the frames.
Iterable<JrConfig> _roams() sync* {
  for (final JrRoamMethod r in JrRoamMethod.values) {
    for (final JrBand b in JrBand.values) {
      for (final JrScanType t in JrScanType.values) {
        for (final JrPmf p in JrPmf.values) {
          for (final LadderMethod m in _dot1x) {
            yield JrConfig(
              roamMethod: r,
              band: b,
              scanType: t,
              pmf: p,
              eapMethod: m,
            );
          }
        }
      }
    }
  }
}

Iterable<JrSequence> _all() sync* {
  for (final JrConfig c in _joins()) {
    yield buildJoin(c);
  }
  for (final JrConfig c in _roams()) {
    yield buildRoam(c);
  }
}

/// The order a Join's phases first appear in.
List<JrPhase> _phaseOrder(JrSequence s) {
  final List<JrPhase> out = <JrPhase>[];
  for (final JrMessage m in s.messages) {
    if (out.isEmpty || out.last != m.phase) out.add(m.phase);
  }
  return out;
}

/// Coarse steps, for the order test.
String _step(JrPhase p) => switch (p) {
  JrPhase.scan => 'scan',
  JrPhase.openAuth || JrPhase.saeAuth => 'auth',
  JrPhase.association => 'association',
  JrPhase.eapIdentity ||
  JrPhase.eapMethod ||
  JrPhase.innerAuth ||
  JrPhase.eapResult => 'eap',
  JrPhase.fourWay => '4-way',
  JrPhase.dhcp => 'dhcp',
  JrPhase.addressCheck => 'check',
  JrPhase.arpDns => 'arp/dns',
  JrPhase.later => 'later',
  _ => 'other:${p.name}',
};

bool _neverProtectable(JrMessage m) =>
    m.phase == JrPhase.scan ||
    m.phase == JrPhase.openAuth ||
    m.phase == JrPhase.saeAuth ||
    m.phase == JrPhase.ftAuth ||
    m.phase == JrPhase.association ||
    m.phase == JrPhase.reassociation ||
    m.label.startsWith('Beacon') ||
    m.label.startsWith('Probe') ||
    m.label.startsWith('Authentication') ||
    m.label.startsWith('SAE') ||
    m.label.contains('ssociation');

void main() {
  group('spec 21b Done means', () {
    test('Join order: scan, auth, association, 4-way, DHCP, address check, '
        'ARP and DNS', () {
      for (final JrConfig c in _joins()) {
        final JrSequence s = buildJoin(c);
        if (!s.found) continue;
        // Distinct steps, in first-seen order.
        final List<String> steps = <String>{
          for (final JrPhase p in _phaseOrder(s)) _step(p),
        }.toList();
        final JrSecurity sec = c.effectiveSecurity;
        expect(steps, <String>[
          'scan',
          'auth',
          'association',
          if (sec == JrSecurity.dot1x) 'eap',
          if (sec != JrSecurity.open) '4-way',
          'dhcp',
          'check',
          'arp/dns',
          'later',
        ], reason: '${sec.name} ${c.band.name} ${c.addressCheck.name}');
        // Each step is one contiguous block.
        final List<String> blocks = <String>[
          for (final JrPhase p in _phaseOrder(s)) _step(p),
        ];
        for (int i = 1; i < blocks.length; i++) {
          if (blocks[i] == blocks[i - 1]) continue;
          expect(
            blocks.sublist(i + 1).contains(blocks[i - 1]),
            isFalse,
            reason: '${blocks[i - 1]} comes back after ${blocks[i]}',
          );
        }
        // DHCP is the four messages of RFC 2131, in order.
        expect(
          s.inPhase(JrPhase.dhcp).map((JrMessage m) => m.label).toList(),
          <String>['DHCP Discover', 'DHCP Offer', 'DHCP Request', 'DHCP Ack'],
        );
        // The ACD check is three probes and an announcement; DNAv4 one
        // unicast ARP and its reply.
        final List<String> check = s
            .inPhase(JrPhase.addressCheck)
            .map((JrMessage m) => m.label)
            .toList();
        expect(
          check,
          c.addressCheck == JrAddressCheck.acd
              ? <String>[
                  'ARP Probe 1 of 3',
                  'ARP Probe 2 of 3',
                  'ARP Probe 3 of 3',
                  'ARP Announcement',
                ]
              : <String>['ARP Request (unicast)', 'ARP Reply'],
        );
        // ARP for the gateway (unless DNAv4 already found it), then DNS last.
        final List<String> tail = s
            .inPhase(JrPhase.arpDns)
            .map((JrMessage m) => m.label)
            .toList();
        expect(tail.sublist(tail.length - 2), <String>[
          'DNS Query',
          'DNS Response',
        ]);
        expect(
          tail.contains('ARP Request'),
          c.addressCheck == JrAddressCheck.acd,
        );
      }
    });

    test('EAPOL-Key frames are typed as data, never management', () {
      int seen = 0;
      for (final JrSequence s in _all()) {
        for (final JrMessage m in s.messages) {
          if (m.label == 'EAPOL-Key' || m.kind == JrFrameKind.eapolKey) {
            seen++;
            expect(m.kind, JrFrameKind.eapolKey);
            expect(m.kind.frameClass, JrFrameClass.data);
            expect(m.isData, isTrue);
            expect(m.isManagement, isFalse);
            expect(m.leg, LadderLeg.air);
          }
          // EAP over the air rides data frames too.
          if (m.kind == JrFrameKind.eapol) {
            expect(m.kind.frameClass, JrFrameClass.data);
          }
        }
      }
      expect(seen, greaterThan(1000));
      // The 4-way handshake is four of them, AP first.
      final JrSequence psk = buildJoin(const JrConfig());
      final List<JrMessage> keys = psk.inPhase(JrPhase.fourWay);
      expect(keys.length, 4);
      for (int i = 0; i < 4; i++) {
        expect(keys[i].from, i.isEven ? JrLane.ap : JrLane.client);
        expect(keys[i].detail, startsWith('Message ${i + 1} of 4'));
      }
      expect(keys[0].detail, contains('ANonce'));
      expect(keys[1].detail, contains('SNonce'));
      expect(keys[1].detail, contains('MIC'));
      expect(keys[2].detail, contains('GTK'));
      expect(keys[2].detail, contains('install'));
      expect(keys[3].milestone, LadderMilestone.trafficProtected);
    });

    test('the PMF shield never appears on beacons, probes, authentication or '
        'association frames', () {
      int shields = 0;
      for (final JrSequence s in _all()) {
        final int m4 = s.indexOfMilestone(LadderMilestone.trafficProtected);
        final int keys = s.indexOfMilestone(LadderMilestone.keysAvailable);
        for (int i = 0; i < s.length; i++) {
          final JrMessage m = s.messages[i];
          if (_neverProtectable(m)) {
            expect(m.pmfProtected, isFalse, reason: '${m.label} ${m.phase}');
          }
          if (!m.pmfProtected) continue;
          shields++;
          // Only on management frames, only with PMF in use, only once keys
          // exist with the AP the frame goes to.
          expect(m.isManagement, isTrue);
          expect(s.pmf.inUse, isTrue);
          if (s.mode == LadderMode.join) {
            expect(i, greaterThan(m4));
          } else {
            // FT over the DS: keys with the CURRENT AP exist already.
            expect(m.kind, JrFrameKind.action);
            expect(
              m.from == JrLane.currentAp || m.to == JrLane.currentAp,
              isTrue,
            );
            expect(keys, isNonNegative);
          }
        }
      }
      expect(shields, greaterThan(0));
    });

    test('WPA3-SAE replaces Open System with 4 SAE frames before '
        'association', () {
      for (final JrBand b in JrBand.values) {
        final JrSequence s = buildJoin(
          JrConfig(security: JrSecurity.sae, band: b),
        );
        expect(s.inPhase(JrPhase.openAuth), isEmpty);
        final List<JrMessage> sae = s.inPhase(JrPhase.saeAuth);
        expect(sae.map((JrMessage m) => m.label).toList(), <String>[
          'SAE Commit',
          'SAE Commit',
          'SAE Confirm',
          'SAE Confirm',
        ]);
        for (final JrMessage m in sae) {
          expect(m.kind, JrFrameKind.management);
          expect(m.detail, startsWith('Authentication'));
        }
        final int lastSae = s.messages.indexOf(sae.last);
        final int assoc = s.messages.indexWhere(
          (JrMessage m) => m.phase == JrPhase.association,
        );
        expect(lastSae, lessThan(assoc));
        expect(s.messages.indexOf(sae.first), greaterThan(0));
      }
      // Every other security uses Open System, two frames.
      for (final JrSecurity sec in <JrSecurity>[
        JrSecurity.open,
        JrSecurity.owe,
        JrSecurity.psk,
        JrSecurity.dot1x,
      ]) {
        final JrSequence s = buildJoin(JrConfig(security: sec));
        expect(s.inPhase(JrPhase.openAuth).length, 2, reason: '$sec');
        expect(s.inPhase(JrPhase.saeAuth), isEmpty);
      }
    });

    test('a 6 GHz active scan probes only PSCs', () {
      for (final JrConfig c in _joins()) {
        if (c.band != JrBand.g6 || c.scanType != JrScanType.active) continue;
        final JrScanPlan p = buildScan(c);
        if (c.sixGhz == JrSixGhzDiscovery.psc) {
          expect(p.probedChannels, isNotEmpty);
          expect(p.probedChannels.every(k6Pscs.contains), isTrue);
          expect(p.probedChannels.length, 15);
          // Non-PSC channels are not visited at all in an active 6 GHz scan.
          expect(p.channels.every((JrScanChannel ch) => ch.psc), isTrue);
        } else {
          // RNR already named the AP: one directed probe on its channel.
          expect(p.probedChannels, <int>[p.targetChannel]);
          expect(p.rnr, isTrue);
        }
        for (final JrScanEvent e in p.events) {
          if (e.kind != JrScanEventKind.probeRequest) continue;
          expect(
            k6Pscs.contains(e.channel) || p.rnr,
            isTrue,
            reason: 'probe on ${e.channel}',
          );
        }
      }
      expect(k6Pscs.length, 15);
      expect(k6Channels.length, 59);
    });

    test('DNAv4 total is shorter than ACD', () {
      for (final JrSecurity sec in JrSecurity.values) {
        for (final JrBand b in JrBand.values) {
          final JrConfig acd = JrConfig(security: sec, band: b);
          final JrSequence a = buildJoin(acd);
          final JrSequence d = buildJoin(
            acd.copyWith(addressCheck: JrAddressCheck.dnav4),
          );
          expect(d.totalMs, lessThan(a.totalMs), reason: '$sec $b');
          expect(
            d.clockTotals[JrClock.addressCheck],
            lessThan(10),
            reason: 'DNAv4 targets under 10 ms',
          );
          // At the RFC 5227 extremes ACD takes 4 to 7 s.
          final double lo = buildJoin(
            acd.copyWith(acdProbeWaitMs: 0, acdSpacingMs: kMinAcdSpacingMs),
          ).clockTotals[JrClock.addressCheck]!;
          final double hi = buildJoin(
            acd.copyWith(
              acdProbeWaitMs: kMaxAcdProbeWaitMs,
              acdSpacingMs: kMaxAcdSpacingMs,
            ),
          ).clockTotals[JrClock.addressCheck]!;
          expect(lo, greaterThanOrEqualTo(4000));
          expect(lo, lessThan(4100));
          expect(hi, greaterThanOrEqualTo(7000));
          expect(hi, lessThan(7100));
        }
      }
    });

    test('FT over the air is 4 frames', () {
      for (final JrConfig c in _roams()) {
        if (c.roamMethod != JrRoamMethod.ftOverAir) continue;
        final JrSequence s = buildRoam(c);
        final List<JrMessage> roam = s.afterScan;
        expect(roam.length, 4);
        expect(roam.map((JrMessage m) => m.label).toList(), <String>[
          'Authentication',
          'Authentication',
          'Reassociation Request',
          'Reassociation Response',
        ]);
        expect(roam[0].detail, contains('algorithm 2'));
        expect(roam[0].detail, contains('SNonce'));
        expect(roam[1].detail, contains('ANonce'));
        expect(roam[1].detail, contains('R1KH-ID'));
        expect(roam[2].detail, contains('MIC'));
        expect(roam[3].detail, contains('GTK'));
        expect(
          roam.every(
            (JrMessage m) =>
                m.leg == LadderLeg.air &&
                (m.from == JrLane.targetAp || m.to == JrLane.targetAp),
          ),
          isTrue,
        );
        expect(s.wireCount, 0);
        expect(s.inPhase(JrPhase.fourWay), isEmpty);
      }
    });

    test('FT over the DS starts with an Action frame to the current AP', () {
      for (final JrConfig c in _roams()) {
        if (c.roamMethod != JrRoamMethod.ftOverDs) continue;
        final JrSequence s = buildRoam(c);
        final List<JrMessage> roam = s.afterScan;
        expect(roam.first.kind, JrFrameKind.action);
        expect(roam.first.isManagement, isTrue);
        expect(roam.first.from, JrLane.client);
        expect(roam.first.to, JrLane.currentAp);
        // Forwarded to the target over the DS and back, then relayed.
        expect(roam[1].kind, JrFrameKind.ds);
        expect(roam[1].from, JrLane.currentAp);
        expect(roam[1].to, JrLane.targetAp);
        expect(roam[1].leg, LadderLeg.wire);
        expect(roam[2].kind, JrFrameKind.ds);
        expect(roam[2].to, JrLane.currentAp);
        expect(roam[3].kind, JrFrameKind.action);
        expect(roam[3].to, JrLane.client);
        // Then Reassociation with the target, over the air.
        expect(roam[4].label, 'Reassociation Request');
        expect(roam[4].to, JrLane.targetAp);
        expect(roam[5].label, 'Reassociation Response');
        expect(roam.length, 6);
        expect(s.dsCount, 2);
      }
    });

    test('OKC and PMK caching have the same frame list', () {
      String key(JrMessage m) =>
          '${m.from.name}>${m.to.name}|${m.kind.name}|${m.label}';
      for (final JrConfig c in _roams()) {
        if (c.roamMethod != JrRoamMethod.okc) continue;
        final JrSequence okc = buildRoam(c);
        final JrSequence pmk = buildRoam(
          c.copyWith(roamMethod: JrRoamMethod.pmkCaching),
        );
        expect(okc.messages.map(key).toList(), pmk.messages.map(key).toList());
        expect(okc.totalMs, pmk.totalMs);
      }
      // What differs is how the PMKID is made, and the vendor label.
      final JrSequence okc = buildRoam(
        const JrConfig(roamMethod: JrRoamMethod.okc),
      );
      final JrMessage req = okc.inPhase(JrPhase.reassociation).first;
      expect(req.description, contains('vendor extension, not IEEE'));
      expect(req.description, contains('Apple'));
      expect(
        req.fields.any(
          (JrField f) => f.$1.contains('PMKID') && f.$2.contains('TARGET'),
        ),
        isTrue,
      );
      expect(JrRoamMethod.okc.label, contains('vendor extension, not IEEE'));
    });

    test('no roam method changes scan time', () {
      for (final JrBand b in JrBand.values) {
        for (final JrScanType t in JrScanType.values) {
          final Set<double> scans = <double>{
            for (final JrRoamMethod r in JrRoamMethod.values)
              buildRoam(
                JrConfig(roamMethod: r, band: b, scanType: t),
              ).roamTotals[RoamBar.scan]!,
          };
          expect(scans.length, 1, reason: '$b $t');
          expect(
            scans.single,
            buildScan(JrConfig(band: b, scanType: t)).totalMs,
          );
        }
      }
      // And FT shrinks the middle while the scan bar stays.
      final JrSequence full = buildRoam(const JrConfig());
      final JrSequence ft = buildRoam(
        const JrConfig(roamMethod: JrRoamMethod.ftOverAir),
      );
      expect(
        ft.roamTotals[RoamBar.authentication]!,
        lessThan(full.roamTotals[RoamBar.authentication]!),
      );
      expect(ft.roamTotals[RoamBar.scan], full.roamTotals[RoamBar.scan]);
    });
  });

  group('join details', () {
    test('the scan: dwell, beacons every 102.4 ms, a short passive dwell '
        'misses', () {
      // Defaults are the mac80211 figures.
      const JrConfig c = JrConfig();
      expect(c.activeDwellMs, 30);
      expect(c.passiveDwellMs, 111);
      final JrScanPlan passive = buildScan(
        const JrConfig(scanType: JrScanType.passive),
      );
      expect(passive.found, isTrue);
      expect(passive.channels.length, 25);
      final List<JrScanEvent> beacons = passive.events
          .where((JrScanEvent e) => e.kind == JrScanEventKind.beacon)
          .toList();
      for (int i = 1; i < beacons.length; i++) {
        expect(beacons[i].atMs - beacons[i - 1].atMs, closeTo(102.4, 1e-9));
      }
      // The radio is on the AP's channel for one dwell; beacons outside it
      // are missed.
      expect(beacons.where((JrScanEvent e) => e.heard).length, 1);
      expect(beacons.where((JrScanEvent e) => !e.heard), isNotEmpty);
      // A dwell shorter than the wait for the beacon misses the AP.
      final JrSequence short = buildJoin(
        const JrConfig(scanType: JrScanType.passive, passiveDwellMs: 40),
      );
      expect(short.found, isFalse);
      expect(short.length, 1);
      expect(short.messages.single.missed, isTrue);
      expect(short.airCount, 0);
      // An active scan still finds it: the AP answers the probe.
      expect(buildJoin(const JrConfig(activeDwellMs: 10)).found, isTrue);
      // 6 GHz passive: FILS Discovery every 20 TU catches even a short dwell.
      final JrSequence six = buildJoin(
        const JrConfig(
          band: JrBand.g6,
          scanType: JrScanType.passive,
          passiveDwellMs: 40,
          security: JrSecurity.sae,
        ),
      );
      expect(six.found, isTrue);
      expect(six.messages.first.label, 'FILS Discovery');
    });

    test('5 GHz: DFS channels are listened to, not probed', () {
      final JrScanPlan p = buildScan(const JrConfig());
      for (final JrScanChannel ch in p.channels) {
        expect(ch.probed, !isDfsChannel(ch.number), reason: '${ch.number}');
        expect(
          ch.dwellMs,
          ch.probed ? kDefaultActiveDwellMs : kDefaultPassiveDwellMs,
        );
      }
      expect(p.probedCount, 9);
      expect(p.listenedCount, 16);
    });

    test('6 GHz requires WPA3 or OWE with PMF', () {
      for (final JrSecurity sec in JrSecurity.values) {
        for (final JrPmf pmf in JrPmf.values) {
          final JrConfig c = JrConfig(security: sec, band: JrBand.g6, pmf: pmf);
          expect(c.effectiveSecurity.allowedIn6GHz, isTrue);
          expect(c.pmfFor(c.effectiveSecurity), JrPmf.required);
          expect(c.pmfChoosable(c.effectiveSecurity), isFalse);
        }
      }
      expect(
        const JrConfig(
          security: JrSecurity.open,
          band: JrBand.g6,
        ).effectiveSecurity,
        JrSecurity.owe,
      );
      expect(const JrConfig(band: JrBand.g6).effectiveSecurity, JrSecurity.sae);
      // Outside 6 GHz the choice stands.
      expect(const JrConfig().effectiveSecurity, JrSecurity.psk);
      expect(const JrConfig(pmf: JrPmf.off).pmfFor(JrSecurity.psk), JrPmf.off);
      expect(const JrConfig().pmfFor(JrSecurity.open), JrPmf.off);
      expect(const JrConfig().pmfFor(JrSecurity.owe), JrPmf.required);
    });

    test('the Association Request carries the capabilities and the RSNE; '
        'the response a status code and AID', () {
      final JrSequence s = buildJoin(const JrConfig());
      final List<JrMessage> assoc = s.inPhase(JrPhase.association);
      final Map<String, String> req = <String, String>{
        for (final JrField f in assoc[0].fields) f.$1: f.$2,
      };
      for (final String k in <String>[
        'SSID',
        'Listen interval',
        'Capability information',
        'Supported rates',
        'RSN element: AKM',
        'RSN element: ciphers',
        'RSN element: PMF bits',
        'HT Capabilities',
        'VHT Capabilities',
        'HE Capabilities',
        'EHT Capabilities',
      ]) {
        expect(req.containsKey(k), isTrue, reason: k);
      }
      expect(req['RSN element: PMF bits'], contains('MFPC 1'));
      final Map<String, String> resp = <String, String>{
        for (final JrField f in assoc[1].fields) f.$1: f.$2,
      };
      expect(resp['Status code'], startsWith('0'));
      expect(resp.containsKey('Association ID (AID)'), isTrue);
      // 6 GHz: no HT or VHT elements.
      final Map<String, String> six = <String, String>{
        for (final JrField f in buildJoin(
          const JrConfig(band: JrBand.g6),
        ).inPhase(JrPhase.association)[0].fields)
          f.$1: f.$2,
      };
      expect(six.containsKey('HT Capabilities'), isFalse);
      expect(six.containsKey('VHT Capabilities'), isFalse);
      expect(six.containsKey('HE 6 GHz Band Capabilities'), isTrue);
      expect(six['RSN element: PMF bits'], contains('MFPR 1'));
      // Open: no RSN element at all.
      final JrMessage open = buildJoin(
        const JrConfig(security: JrSecurity.open),
      ).inPhase(JrPhase.association)[0];
      expect(open.fields.any((JrField f) => f.$1.startsWith('RSN')), isFalse);
    });

    test('lock after M4: data frames after it are encrypted; open never', () {
      for (final JrConfig c in _joins()) {
        final JrSequence s = buildJoin(c);
        if (!s.found) continue;
        final int m4 = s.indexOfMilestone(LadderMilestone.trafficProtected);
        final bool open = c.effectiveSecurity == JrSecurity.open;
        expect(m4 < 0, open);
        for (int i = 0; i < s.length; i++) {
          final JrMessage m = s.messages[i];
          if (m.encrypted) {
            expect(open, isFalse);
            expect(i, greaterThan(m4));
            expect(m.isData, isTrue);
          }
          if (!open && m.kind == JrFrameKind.data) {
            expect(m.encrypted, isTrue);
          }
        }
      }
    });

    test('802.1X hands the EAP middle to the existing ladder unchanged', () {
      for (final LadderMethod method in _dot1x) {
        final JrConfig c = JrConfig(
          security: JrSecurity.dot1x,
          eapMethod: method,
          certFragments: 2,
        );
        final JrSequence s = buildJoin(c);
        final LadderSequence ladder = buildLadder(c.eapConfig);
        final List<String> fromLadder = <String>[
          for (final LadderMessage m in ladder.messages)
            if (m.phase.isEap) '${m.label}|${m.detail}',
        ];
        final List<String> inJoin = <String>[
          for (final JrMessage m in s.messages)
            if (m.clock == JrClock.eap) '${m.label}|${m.detail}',
        ];
        expect(inJoin, fromLadder);
        expect(s.radiusRoundTrips, ladder.radiusRoundTrips);
        expect(s.lanes, contains(JrLane.radius));
      }
      expect(buildJoin(const JrConfig()).lanes, isNot(contains(JrLane.radius)));
    });

    test('ACD dominates the join timeline at the defaults', () {
      final JrSequence s = buildJoin(const JrConfig());
      final Map<JrClock, double> t = s.clockTotals;
      for (final JrClock c in JrClock.joinClocks) {
        if (c == JrClock.addressCheck) continue;
        expect(t[JrClock.addressCheck], greaterThan(t[c]!), reason: '$c');
      }
      // The total is the sum of the join's clocks; later frames are not in
      // it.
      final double sum = JrClock.joinClocks.fold(
        0,
        (double a, JrClock c) => a + t[c]!,
      );
      expect(s.totalMs, closeTo(sum, 1e-9));
      expect(s.elapsedMs(s.length), closeTo(s.totalMs, 1e-9));
    });

    test('counts: management vs data, air vs wire', () {
      final JrSequence s = buildJoin(const JrConfig());
      // Scan 2 + auth 2 + association 2 + ADDBA 2 management.
      expect(s.managementCount, 8);
      // 4 EAPOL-Key + 4 DHCP + 4 ACD + 2 ARP + 2 DNS.
      expect(s.dataCount, 16);
      expect(s.airCount, s.managementCount + s.dataCount);
      // Each bridged frame also crosses the wire once.
      expect(s.lanCount, 12);
      expect(s.radiusCount, 0);
    });
  });

  group('roam details', () {
    test('every roam uses Reassociation, which names the current AP', () {
      for (final JrConfig c in _roams()) {
        final JrSequence s = buildRoam(c);
        expect(s.inPhase(JrPhase.association), isEmpty);
        final JrMessage req = s.messages.firstWhere(
          (JrMessage m) => m.label == 'Reassociation Request',
        );
        expect(req.to, JrLane.targetAp);
        expect(
          req.fields.any((JrField f) => f.$1 == 'Current AP address'),
          isTrue,
        );
      }
    });

    test('full 802.1X repeats EAP; caching skips it; all keep the 4-way but '
        'FT', () {
      final JrSequence full = buildRoam(const JrConfig());
      expect(full.radiusRoundTrips, greaterThan(0));
      expect(full.inPhase(JrPhase.fourWay).length, 4);
      expect(full.lanes, contains(JrLane.radius));
      for (final JrRoamMethod r in <JrRoamMethod>[
        JrRoamMethod.pmkCaching,
        JrRoamMethod.okc,
      ]) {
        final JrSequence s = buildRoam(JrConfig(roamMethod: r));
        expect(s.radiusCount, 0);
        expect(s.inPhase(JrPhase.fourWay).length, 4);
        expect(s.lanes, isNot(contains(JrLane.radius)));
        final JrMessage req = s.inPhase(JrPhase.reassociation).first;
        expect(req.detail, contains('PMKID'));
      }
    });

    test('authentication time: round trips x RTT + crypto + 4-way', () {
      const JrConfig c = JrConfig(radiusRttMs: 20, cryptoMs: 100);
      final JrSequence s = buildRoam(c);
      final List<JrMessage> eap = s.messages
          .where((JrMessage m) => m.clock == JrClock.eap)
          .toList();
      final int air = eap.where((JrMessage m) => m.leg == LadderLeg.air).length;
      final double eapMs = eap.fold(0, (double a, JrMessage m) => a + m.ms);
      expect(eapMs, closeTo(s.radiusRoundTrips * 20 + 100 + air * 1, 1e-9));
      final JrSequence slow = buildRoam(c.copyWith(radiusRttMs: 60));
      expect(slow.totalMs - s.totalMs, closeTo(s.radiusRoundTrips * 40, 1e-9));
      // FT is untouched by RADIUS time and crypto time.
      final JrConfig ft = c.copyWith(roamMethod: JrRoamMethod.ftOverAir);
      expect(
        buildRoam(ft).totalMs,
        buildRoam(ft.copyWith(radiusRttMs: 200, cryptoMs: 500)).totalMs,
      );
    });

    test('what a roam method skipped', () {
      expect(
        roamSkippedVersusFull(buildRoam(const JrConfig())).fewerMessages,
        0,
      );
      for (final JrRoamMethod r in JrRoamMethod.values) {
        if (r == JrRoamMethod.full) continue;
        final RoamSkipped sk = roamSkippedVersusFull(
          buildRoam(JrConfig(roamMethod: r)),
        );
        expect(sk.fewerMessages, greaterThan(10), reason: '$r');
        expect(sk.lines.first, contains('EAP exchange'));
        expect(sk.lines.last, startsWith('Not the scan'));
        expect(sk.lines.join(' ').contains('4-way'), r.isFt);
      }
    });
  });

  test('wording: 802.1X casing, no em dashes, ACD and DNAv4 spelled out', () {
    for (final JrSequence s in _all()) {
      for (final JrPhase p in JrPhase.values) {
        final String t = s.phaseTitle(p);
        expect(t.contains('—'), isFalse, reason: t);
      }
      for (final JrMessage m in s.messages) {
        for (final String t in <String>[
          m.label,
          m.detail ?? '',
          m.description,
          m.milestoneText ?? '',
          for (final JrField f in m.fields) '${f.$1} ${f.$2}',
        ]) {
          expect(t.contains('802.1x'), isFalse, reason: t);
          expect(t.contains('—'), isFalse, reason: t);
          // A bare ACD or DNAv4 is always introduced by its full name in
          // the same string.
          if (RegExp(r'\bACD\b').hasMatch(t)) {
            expect(t, contains('Address Conflict Detection'), reason: t);
          }
          if (t.contains('DNAv4')) {
            expect(t, contains('Detecting Network Attachment'), reason: t);
          }
        }
      }
    }
    final JrSequence acd = buildJoin(const JrConfig());
    expect(
      acd.phaseTitle(JrPhase.addressCheck),
      contains('Address Conflict Detection (ACD, RFC 5227)'),
    );
    final JrSequence dna = buildJoin(
      const JrConfig(addressCheck: JrAddressCheck.dnav4),
    );
    expect(
      dna.phaseTitle(JrPhase.addressCheck),
      contains('Detecting Network Attachment (DNAv4, RFC 4436)'),
    );
    expect(JrAddressCheck.acd.label, contains('Address Conflict Detection'));
    expect(
      JrAddressCheck.dnav4.label,
      contains('Detecting Network Attachment'),
    );
  });

  test('config clamps its settings', () {
    const JrConfig c = JrConfig();
    expect(c.copyWith(activeDwellMs: 0).activeDwellMs, kMinActiveDwellMs);
    expect(c.copyWith(passiveDwellMs: 9999).passiveDwellMs, kMaxPassiveDwellMs);
    expect(c.copyWith(acdSpacingMs: 0).acdSpacingMs, kMinAcdSpacingMs);
    expect(c.copyWith(acdProbeWaitMs: -5).acdProbeWaitMs, 0);
    expect(c.copyWith(certFragments: 99).certFragments, kMaxCertFragments);
    // Only 802.1X methods are accepted for the EAP middle.
    expect(c.copyWith(eapMethod: LadderMethod.psk).eapMethod, c.eapMethod);
    expect(
      c.copyWith(eapMethod: LadderMethod.peap).eapMethod,
      LadderMethod.peap,
    );
    expect(c == const JrConfig(), isTrue);
    expect(c == c.copyWith(cryptoMs: 51), isFalse);
  });
}
