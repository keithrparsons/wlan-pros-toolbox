// Model tests for the Wi-Fi Lab 802.1X and EAP Ladder (eap-ladder).
//
// One group per clause of the spec's "Done means" (myPKA Deliverables/
// 2026-09-25-wifi-lab-cleanroom/specs/21-eap-ladder.md), plus the RFC shapes
// the sequences are built from and the agreement with the app's EAP Types
// reference.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/eap_types_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/eap_ladder.dart';

const List<LadderMethod> _dot1x = <LadderMethod>[
  LadderMethod.eapTls,
  LadderMethod.peap,
  LadderMethod.eapTtls,
];

/// Every 802.1X configuration a full authentication can take.
Iterable<LadderConfig> _full8021X() sync* {
  for (final LadderMethod m in _dot1x) {
    for (final LadderInner inner in LadderInner.values) {
      for (int f = kMinCertFragments; f <= kMaxCertFragments; f++) {
        yield LadderConfig(method: m, inner: inner, certFragments: f);
      }
    }
  }
}

Iterable<LadderConfig> _all() sync* {
  for (final LadderMethod m in LadderMethod.values) {
    for (final LadderRoam r in LadderRoam.values) {
      for (final LadderInner inner in LadderInner.values) {
        for (int f = kMinCertFragments; f <= kMaxCertFragments; f++) {
          yield LadderConfig(
            method: m,
            roam: r,
            inner: inner,
            certFragments: f,
          );
        }
      }
    }
  }
}

List<LadderMessage> _air(LadderSequence s) =>
    s.messages.where((LadderMessage m) => m.leg == LadderLeg.air).toList();

void main() {
  group(
    'every 802.1X method: identity first, EAP-Success before the 4-way',
    () {
      for (final LadderConfig c in _full8021X()) {
        test(
          '${c.method.label}, ${c.inner.label}, ${c.certFragments} frag',
          () {
            final LadderSequence s = buildLadder(c);
            final List<LadderMessage> air = _air(s);
            final List<String?> codes = <String?>[
              for (final LadderMessage m in air) m.eapCode,
            ];
            final int req = codes.indexOf('EAP-Request/Identity');
            final int resp = codes.indexOf('EAP-Response/Identity');
            final int success = codes.indexOf('EAP-Success');
            expect(req, isNonNegative);
            expect(resp, req + 1);
            // The AP sends EAP-Request/Identity itself (RFC 3579).
            expect(air[req].from, LadderLane.ap);
            expect(air[req].to, LadderLane.client);
            expect(air[resp].from, LadderLane.client);
            // EAP ends with EAP-Success, over the air, before the 4-way.
            expect(success, greaterThan(resp));
            final int firstKey = s.messages.indexWhere(
              (LadderMessage m) => m.kind == LadderFrameKind.eapolKey,
            );
            final int successIdx = s.messages.indexOf(air[success]);
            expect(successIdx, lessThan(firstKey));
            // Nothing EAP happens after EAP-Success.
            expect(
              s.messages
                  .skip(successIdx + 1)
                  .where((LadderMessage m) => m.eapCode != null),
              isEmpty,
            );
            // Access-Accept carries it, just before.
            expect(s.messages[successIdx - 1].label, 'Access-Accept');
            expect(s.messages[successIdx - 1].eapCode, 'EAP-Success');
          },
        );
      }
    },
  );

  test('the 4-way handshake is exactly 4 EAPOL-Key frames, AP first', () {
    for (final LadderConfig c in _all()) {
      final LadderSequence s = buildLadder(c);
      final List<LadderMessage> keys = s.messages
          .where((LadderMessage m) => m.kind == LadderFrameKind.eapolKey)
          .toList();
      if (c.roam == LadderRoam.ftOverAir) {
        expect(keys, isEmpty, reason: 'FT folds the handshake in');
        continue;
      }
      expect(keys.length, 4, reason: '${c.method} ${c.roam}');
      expect(s.inPhase(LadderPhase.fourWay).length, 4);
      for (int i = 0; i < 4; i++) {
        expect(keys[i].from, i.isEven ? LadderLane.ap : LadderLane.client);
        expect(keys[i].leg, LadderLeg.air);
        expect(keys[i].detail, startsWith('Message ${i + 1} of 4'));
      }
      // They are the last four messages, contiguous.
      expect(s.messages.sublist(s.length - 4), keys);
    }
  });

  test('PSK and SAE have no RADIUS messages in any roam mode', () {
    for (final LadderMethod m in <LadderMethod>[
      LadderMethod.psk,
      LadderMethod.sae,
    ]) {
      for (final LadderRoam r in LadderRoam.values) {
        final LadderSequence s = buildLadder(
          LadderConfig(method: m, roam: r, certFragments: 6),
        );
        expect(s.wireCount, 0, reason: '$m $r');
        expect(s.radiusRoundTrips, 0);
        expect(
          s.messages.any(
            (LadderMessage x) =>
                x.from == LadderLane.radius || x.to == LadderLane.radius,
          ),
          isFalse,
        );
        expect(s.estimatedMs, s.afterScan.length * kAirFrameMs);
      }
    }
  });

  test('SAE: two Commit and two Confirm authentication frames, in order', () {
    final LadderSequence s = buildLadder(
      const LadderConfig(method: LadderMethod.sae),
    );
    final List<LadderMessage> sae = s.inPhase(LadderPhase.saeAuth);
    expect(sae.map((LadderMessage m) => m.label).toList(), <String>[
      'SAE Commit',
      'SAE Commit',
      'SAE Confirm',
      'SAE Confirm',
    ]);
    for (final LadderMessage m in sae) {
      expect(m.kind, LadderFrameKind.management);
      expect(m.detail, startsWith('Authentication'));
      expect(m.leg, LadderLeg.air);
    }
    expect(
      sae.where((LadderMessage m) => m.from == LadderLane.client).length,
      2,
    );
    // SAE replaces Open System authentication.
    expect(s.inPhase(LadderPhase.openAuth), isEmpty);
    // PSK has Open System and no SAE.
    final LadderSequence psk = buildLadder(
      const LadderConfig(method: LadderMethod.psk),
    );
    expect(psk.inPhase(LadderPhase.saeAuth), isEmpty);
    expect(psk.inPhase(LadderPhase.openAuth).length, 2);
  });

  test('PMK caching has no EAP exchange, for every method', () {
    for (final LadderMethod m in LadderMethod.values) {
      final LadderSequence s = buildLadder(
        LadderConfig(method: m, roam: LadderRoam.pmkCaching, certFragments: 4),
      );
      expect(
        s.messages.where((LadderMessage x) => x.eapCode != null),
        isEmpty,
        reason: '$m',
      );
      expect(s.messages.where((LadderMessage x) => x.phase.isEap), isEmpty);
      expect(s.inPhase(LadderPhase.saeAuth), isEmpty);
      expect(s.inPhase(LadderPhase.reassociation).length, 2);
      if (m != LadderMethod.psk) {
        expect(
          s.inPhase(LadderPhase.reassociation).first.detail,
          contains('PMKID'),
        );
      }
    }
  });

  test('FT over the air is exactly 4 frames after the scan', () {
    for (final LadderMethod m in LadderMethod.values) {
      final LadderSequence s = buildLadder(
        LadderConfig(method: m, roam: LadderRoam.ftOverAir, certFragments: 6),
      );
      final List<LadderMessage> roam = s.afterScan;
      expect(roam.length, 4, reason: '$m');
      expect(roam.map((LadderMessage x) => x.label).toList(), <String>[
        'Authentication',
        'Authentication',
        'Reassociation Request',
        'Reassociation Response',
      ]);
      expect(roam[0].detail, contains('SNonce'));
      expect(roam[1].detail, contains('ANonce'));
      expect(roam[3].detail, contains('GTK'));
      expect(roam.every((LadderMessage x) => x.leg == LadderLeg.air), isTrue);
      expect(s.wireCount, 0);
      expect(roam.last.milestone, LadderMilestone.trafficProtected);
    }
  });

  test('EAP-TLS carries a client certificate; PEAP and EAP-TTLS do not', () {
    for (int f = kMinCertFragments; f <= kMaxCertFragments; f++) {
      bool hasClientCert(LadderConfig c) =>
          buildLadder(c).messages.any((LadderMessage m) => m.clientCertificate);
      expect(
        hasClientCert(
          LadderConfig(method: LadderMethod.eapTls, certFragments: f),
        ),
        isTrue,
      );
      expect(
        hasClientCert(
          LadderConfig(method: LadderMethod.peap, certFragments: f),
        ),
        isFalse,
      );
      for (final LadderInner inner in LadderInner.values) {
        expect(
          hasClientCert(
            LadderConfig(
              method: LadderMethod.eapTtls,
              inner: inner,
              certFragments: f,
            ),
          ),
          isFalse,
        );
      }
    }
    // All three 802.1X methods carry the server certificate.
    for (final LadderMethod m in _dot1x) {
      expect(
        buildLadder(
          LadderConfig(method: m),
        ).messages.any((LadderMessage x) => x.serverCertificate),
        isTrue,
      );
    }
  });

  test('more certificate fragments add RADIUS round trips', () {
    for (final LadderMethod m in _dot1x) {
      for (final LadderInner inner in LadderInner.values) {
        int previous = -1;
        for (int f = kMinCertFragments; f <= kMaxCertFragments; f++) {
          final int rt = buildLadder(
            LadderConfig(method: m, inner: inner, certFragments: f),
          ).radiusRoundTrips;
          expect(rt, greaterThan(previous), reason: '$m $inner $f');
          previous = rt;
        }
      }
    }
  });

  test('round-trip counts follow the RFC shapes at one fragment', () {
    int rt(LadderConfig c) => buildLadder(c).radiusRoundTrips;
    // RFC 5216 2.1.1: identity, start/hello, server flight/client flight,
    // finished/ack; the last Access-Request is answered by Access-Accept.
    expect(rt(const LadderConfig(method: LadderMethod.eapTls)), 4);
    // Each extra fragment is acknowledged (RFC 5216 2.1.5); EAP-TLS
    // fragments both certificate messages at this setting.
    expect(
      rt(const LadderConfig(method: LadderMethod.eapTls, certFragments: 3)),
      8,
    );
    expect(
      rt(const LadderConfig(method: LadderMethod.peap, certFragments: 3)),
      10,
    );
    // RFC 5281 11.2.1 (PAP) and 11.2.4 (MS-CHAP-V2).
    expect(
      rt(
        const LadderConfig(
          method: LadderMethod.eapTtls,
          inner: LadderInner.pap,
        ),
      ),
      4,
    );
    expect(rt(const LadderConfig(method: LadderMethod.eapTtls)), 5);
    // PEAP: TLS, then identity, MSCHAPv2 challenge, success, result inside.
    expect(rt(const LadderConfig(method: LadderMethod.peap)), 8);
  });

  test('RADIUS is lockstep: each Access-Request is answered once', () {
    for (final LadderConfig c in _full8021X()) {
      final LadderSequence s = buildLadder(c);
      final List<LadderMessage> wire = s.messages
          .where((LadderMessage m) => m.leg == LadderLeg.wire)
          .toList();
      expect(wire.length, s.radiusRoundTrips * 2);
      for (int i = 0; i < wire.length; i += 2) {
        expect(wire[i].label, 'Access-Request');
        expect(
          wire[i + 1].label,
          i + 2 == wire.length ? 'Access-Accept' : 'Access-Challenge',
        );
      }
      // Every EAP message over the air has a RADIUS partner, except the
      // identity request, which the AP sends itself.
      final int eapAir = s.messages
          .where(
            (LadderMessage m) =>
                m.leg == LadderLeg.air && m.kind == LadderFrameKind.eapol,
          )
          .length;
      expect(eapAir, wire.length + 1);
    }
  });

  test('the AP only relays: no message runs client to RADIUS directly', () {
    for (final LadderConfig c in _all()) {
      for (final LadderMessage m in buildLadder(c).messages) {
        expect(<LadderLane>{
          m.from,
          m.to,
        }, isNot(<LadderLane>{LadderLane.client, LadderLane.radius}));
        expect(m.from, isNot(m.to));
      }
    }
  });

  test('keys available comes before traffic protected, once each', () {
    for (final LadderConfig c in _all()) {
      final LadderSequence s = buildLadder(c);
      final int keys = s.indexOfMilestone(LadderMilestone.keysAvailable);
      final int prot = s.indexOfMilestone(LadderMilestone.trafficProtected);
      expect(keys, isNonNegative, reason: '${c.method} ${c.roam}');
      expect(prot, greaterThan(keys));
      expect(prot, s.length - 1);
      expect(
        s.messages.where((LadderMessage m) => m.milestone != null).length,
        2,
      );
      if (c.method.uses8021X && c.roam == LadderRoam.full) {
        expect(s.messages[keys].label, 'Access-Accept');
      }
    }
  });

  test('tunneled content appears only for PEAP and EAP-TTLS', () {
    for (final LadderConfig c in _all()) {
      final bool any = buildLadder(
        c,
      ).messages.any((LadderMessage m) => m.tunneled);
      expect(
        any,
        c.method.isTunneled && c.roam == LadderRoam.full,
        reason: '${c.method} ${c.roam}',
      );
    }
  });

  test('estimated time: air frames plus RADIUS round trips x RTT', () {
    final LadderSequence s = buildLadder(
      const LadderConfig(method: LadderMethod.peap, radiusRttMs: 20),
    );
    final int airAfterScan = s.afterScan
        .where((LadderMessage m) => m.leg == LadderLeg.air)
        .length;
    expect(s.estimatedMs, airAfterScan * kAirFrameMs + 8 * 20);
    final LadderSequence slow = buildLadder(
      const LadderConfig(method: LadderMethod.peap, radiusRttMs: 100),
    );
    expect(slow.estimatedMs - s.estimatedMs, 8 * 80);
  });

  test('skipped versus full', () {
    final LadderSkipped full = skippedVersusFull(
      buildLadder(const LadderConfig()),
    );
    expect(full.fewerMessages, 0);
    final LadderSequence cached = buildLadder(
      const LadderConfig(
        method: LadderMethod.peap,
        roam: LadderRoam.pmkCaching,
      ),
    );
    final LadderSkipped sk = skippedVersusFull(cached);
    expect(sk.fewerMessages, greaterThan(20));
    expect(sk.lines.first, contains('EAP exchange'));
    expect(sk.lines.first, contains('8 round trips'));
    final LadderSkipped ft = skippedVersusFull(
      buildLadder(
        const LadderConfig(
          method: LadderMethod.sae,
          roam: LadderRoam.ftOverAir,
        ),
      ),
    );
    expect(ft.lines.join(' '), contains('SAE commit and confirm'));
    expect(ft.lines.join(' '), contains('4-way handshake'));
    final LadderSkipped psk = skippedVersusFull(
      buildLadder(
        const LadderConfig(
          method: LadderMethod.psk,
          roam: LadderRoam.pmkCaching,
        ),
      ),
    );
    expect(psk.fewerMessages, 0);
    expect(psk.lines.single, startsWith('Nothing'));
  });

  test('config clamps its settings', () {
    const LadderConfig c = LadderConfig();
    expect(c.copyWith(certFragments: 99).certFragments, kMaxCertFragments);
    expect(c.copyWith(certFragments: 0).certFragments, kMinCertFragments);
    expect(c.copyWith(radiusRttMs: 9999).radiusRttMs, kMaxRadiusRttMs);
    expect(c.copyWith(radiusRttMs: -1).radiusRttMs, kMinRadiusRttMs);
    expect(c.certificateMatters, isTrue);
    expect(c.copyWith(roam: LadderRoam.pmkCaching).certificateMatters, isFalse);
    expect(c.copyWith(method: LadderMethod.sae).radiusMatters, isFalse);
  });

  test('the 802.1X methods name rows of the EAP Types reference', () {
    final Set<String> names = <String>{
      for (final EapMethod m in EapTypesScreen.methods) m.method,
    };
    for (final LadderMethod m in _dot1x) {
      expect(names, contains(m.eapTypesName), reason: '$m');
    }
    // And that reference agrees on which method needs a client certificate.
    EapMethod row(LadderMethod m) => EapTypesScreen.methods.firstWhere(
      (EapMethod e) => e.method == m.eapTypesName,
    );
    expect(row(LadderMethod.eapTls).clientCert, 'Yes');
    expect(row(LadderMethod.peap).clientCert, 'No');
    expect(row(LadderMethod.eapTtls).clientCert, startsWith('No'));
  });

  test('the help example matches the model', () {
    // assets/help/tool_help.json, eap-ladder "example".
    final LadderSequence tls = buildLadder(const LadderConfig());
    expect(tls.airCount, 19);
    expect(tls.wireCount, 8);
    expect(tls.radiusRoundTrips, 4);
    expect(tls.estimatedMs, 57);
    final LadderSequence tls3 = buildLadder(
      const LadderConfig(certFragments: 3),
    );
    expect(tls3.airCount, 27);
    expect(tls3.wireCount, 16);
    expect(tls3.radiusRoundTrips, 8);
    expect(tls3.estimatedMs, 105);
    final LadderSequence peap = buildLadder(
      const LadderConfig(method: LadderMethod.peap),
    );
    expect(peap.radiusRoundTrips, 8);
    expect(peap.estimatedMs, 105);
    final LadderSequence cached = buildLadder(
      const LadderConfig(roam: LadderRoam.pmkCaching),
    );
    expect(skippedVersusFull(cached).fewerMessages, 17);
    expect(cached.estimatedMs, 8);
    final LadderSequence ft = buildLadder(
      const LadderConfig(roam: LadderRoam.ftOverAir),
    );
    expect(ft.afterScan.length, 4);
    expect(ft.estimatedMs, 4);
  });

  test('labels use 802.1X casing and no em dashes', () {
    for (final LadderConfig c in _all()) {
      for (final LadderMessage m in buildLadder(c).messages) {
        for (final String t in <String>[
          m.label,
          m.detail ?? '',
          m.contents,
          m.description,
          m.milestoneText ?? '',
        ]) {
          expect(t.contains('802.1x'), isFalse, reason: t);
          expect(t.contains('—'), isFalse, reason: t);
        }
      }
    }
  });
}
