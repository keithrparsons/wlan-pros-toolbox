// Model tests for Why won't it associate? (spec 43), the security-
// compatibility mode of Association, Frame by Frame (join-ladder).
//
// One group per item of spec 43's "Done means" (myPKA Deliverables/
// 2026-09-25-wifi-lab-cleanroom/specs/43-security-compat.md), then every
// client preset against every network, band and Wi-Fi 7 setting, checked
// against the rules written out independently below.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/security_compat_model.dart';

ScVerdict _v(
  ScClientPreset p,
  ScNetSecurity s, {
  JrBand band = JrBand.g5,
  JrPmf pmf = JrPmf.optional,
  bool wifi7 = false,
  bool h2eOnly = false,
}) => evaluateSecurityVerdict(
  p.client,
  ScNetwork(security: s, band: band, pmf: pmf, wifi7: wifi7, h2eOnly: h2eOnly),
);

JrSequence _ladder(
  ScClient client,
  ScNetwork net, {
  JrScanType scan = JrScanType.active,
}) => buildSecurityCompat(
  JrConfig(band: net.band, pmf: net.pmf, scanType: scan),
  client,
  net,
);

const Set<String> _authOrAssoc = <String>{
  'Authentication',
  'SAE Commit',
  'SAE Confirm',
  'Association Request',
  'Association Response',
};

/// Every network a test sweeps: security x band x PMF x Wi-Fi 7 AP x H2E.
Iterable<ScNetwork> _networks() sync* {
  for (final ScNetSecurity s in ScNetSecurity.values) {
    for (final JrBand b in JrBand.values) {
      for (final JrPmf p in JrPmf.values) {
        if (!s.pmfChoosable && p != JrPmf.optional) continue;
        for (final bool w in <bool>[false, true]) {
          for (final bool h in <bool>[false, true]) {
            if (!s.usesSae && h) continue;
            yield ScNetwork(security: s, band: b, pmf: p, wifi7: w, h2eOnly: h);
          }
        }
      }
    }
  }
}

void main() {
  group('never tries: the common case', () {
    test('WPA2-only client vs WPA3-Personal only: never tries, no status', () {
      final ScVerdict v = _v(
        ScClientPreset.olderLaptop,
        ScNetSecurity.wpa3Personal,
      );
      expect(v.outcome, ScOutcome.neverTries);
      expect(
        v.headline,
        'Never tries to associate: no key management in common',
      );
      expect(v.status, isNull);
      expect(v.source, contains('12.6.3'));
    });

    test(
      'the ladder stops at the Probe Response, marked, with nothing after',
      () {
        final JrSequence s = _ladder(
          ScClientPreset.olderLaptop.client,
          const ScNetwork(security: ScNetSecurity.wpa3Personal),
        );
        expect(s.messages.last.label, 'Probe Response');
        expect(s.messages.last.failure, isTrue);
        expect(s.failedAt, s.length - 1);
        expect(
          s.messages.where((JrMessage m) => _authOrAssoc.contains(m.label)),
          isEmpty,
        );
        expect(
          s.faultNote,
          contains('No Authentication or Association Request'),
        );
        expect(s.helpDesk, contains('no log entry'));
        // The AP's RSN element is what the client read.
        expect(
          s.messages.last.fields,
          contains(('RSN element: AKM', 'SAE (8)')),
        );
      },
    );

    test('passive scan: stops at the Beacon it read', () {
      final JrSequence s = _ladder(
        ScClientPreset.olderLaptop.client,
        const ScNetwork(security: ScNetSecurity.wpa3Personal),
        scan: JrScanType.passive,
      );
      expect(s.messages.last.label, 'Beacon');
      expect(s.messages.last.failure, isTrue);
    });

    test('PMF-aware client that cannot do PMF vs PMF required: never tries, '
        'not 31', () {
      final ScClient c = ScClientPreset.olderLaptop.client.copyWith(
        pmf: ScClientPmf.none,
      );
      final ScVerdict v = evaluateSecurityVerdict(
        c,
        const ScNetwork(
          security: ScNetSecurity.wpa2Personal,
          pmf: JrPmf.required,
        ),
      );
      expect(v.outcome, ScOutcome.neverTries);
      expect(v.status, isNull);
      expect(v.source, contains('Table 12-5'));
    });

    test('client requires PMF, network offers none: never tries', () {
      final ScClient c = ScClientPreset.olderLaptop.client.copyWith(
        pmf: ScClientPmf.required,
      );
      final ScVerdict v = evaluateSecurityVerdict(
        c,
        const ScNetwork(security: ScNetSecurity.wpa2Personal, pmf: JrPmf.off),
      );
      expect(v.outcome, ScOutcome.neverTries);
      expect(v.headline, contains('the client requires PMF'));
    });

    test('no cipher in common: never tries', () {
      final ScVerdict v = _v(
        ScClientPreset.phoneWpa3,
        ScNetSecurity.wpa3Enterprise192,
      );
      // The phone lacks AKM 12 first; take a client with 12 but no GCMP-256.
      expect(v.outcome, ScOutcome.neverTries);
      final ScClient c = ScClientPreset.newLaptop.client.withCipher(
        ScCipher.gcmp256,
        false,
      );
      final ScVerdict w = evaluateSecurityVerdict(
        c,
        const ScNetwork(security: ScNetSecurity.wpa3Enterprise192),
      );
      expect(w.outcome, ScOutcome.neverTries);
      expect(w.headline, contains('no cipher in common'));
    });

    test('H2E only and a client without H2E: never tries; the 6 GHz source '
        'names the Wi-Fi Alliance rule', () {
      final ScClient c = ScClientPreset.newLaptop.client.copyWith(h2e: false);
      final ScVerdict v = evaluateSecurityVerdict(
        c,
        const ScNetwork(security: ScNetSecurity.wpa3Personal, h2eOnly: true),
      );
      expect(v.outcome, ScOutcome.neverTries);
      expect(v.headline, contains('H2E'));
      expect(v.source, contains('Table 9-131'));
      final ScVerdict six = evaluateSecurityVerdict(
        c,
        const ScNetwork(security: ScNetSecurity.wpa3Personal, band: JrBand.g6),
      );
      expect(six.outcome, ScOutcome.neverTries);
      expect(six.source, contains('Wi-Fi Alliance'));
      expect(six.source, contains('does not mention H2E'));
    });

    test('no radio in the band: one Beacon, never heard, marked; no scan', () {
      final ScVerdict v = _v(
        ScClientPreset.phoneWpa3,
        ScNetSecurity.wpa3Personal,
        band: JrBand.g6,
      );
      expect(v.outcome, ScOutcome.neverTries);
      expect(v.headline, 'Never tries to associate: no 6 GHz radio');
      final JrSequence s = _ladder(
        ScClientPreset.phoneWpa3.client,
        const ScNetwork(security: ScNetSecurity.wpa3Personal, band: JrBand.g6),
      );
      expect(s.length, 1);
      expect(s.messages.single.missed, isTrue);
      expect(s.messages.single.failure, isTrue);
      expect(s.scanDrawn, isFalse);
      expect(s.airCount, 0);
    });
  });

  group('refused: status 31', () {
    test('printer (older than PMF) vs WPA2-Personal, PMF required', () {
      final ScVerdict v = _v(
        ScClientPreset.printer,
        ScNetSecurity.wpa2Personal,
        pmf: JrPmf.required,
      );
      expect(v.outcome, ScOutcome.refused);
      expect(v.status?.$1, 31);
      expect(v.headline, 'Refused: status 31 at the Association Response');
      expect(v.source, contains('Table 9-80'));
    });

    test('the ladder: Open System, Association Request, then status 31 and '
        'nothing after', () {
      final JrSequence s = _ladder(
        ScClientPreset.printer.client,
        const ScNetwork(
          security: ScNetSecurity.wpa2Personal,
          pmf: JrPmf.required,
        ),
      );
      final JrMessage last = s.messages.last;
      expect(last.label, 'Association Response');
      expect(last.failure, isTrue);
      expect(last.detail, 'Status 31, no AID');
      expect(last.fields.first, (
        'Status code',
        '31 (robust management frame policy violation)',
      ));
      expect(s.failedAt, s.length - 1);
      expect(s.inPhase(JrPhase.fourWay), isEmpty);
      expect(s.inPhase(JrPhase.dhcp), isEmpty);
      final JrMessage req = s.messages[s.length - 2];
      expect(req.label, 'Association Request');
      expect(req.contents, 'RSN: PSK (2), PMF off');
      expect(
        s.messages.where((JrMessage m) => m.label == 'Authentication'),
        hasLength(2),
      );
    });

    test('the same printer vs PMF optional: associates with PMF off', () {
      final ScVerdict v = _v(
        ScClientPreset.printer,
        ScNetSecurity.wpa2Personal,
      );
      expect(v.outcome, ScOutcome.associates);
      expect(v.pmfOn, isFalse);
    });
  });

  group('transition modes', () {
    test('WPA3-Personal transition: PSK for the WPA2 client, SAE for WPA3', () {
      final ScVerdict old = _v(
        ScClientPreset.olderLaptop,
        ScNetSecurity.wpa3Transition,
      );
      final ScVerdict phone = _v(
        ScClientPreset.phoneWpa3,
        ScNetSecurity.wpa3Transition,
      );
      expect(old.akm, ScAkm.psk);
      expect(phone.akm, ScAkm.sae);
      expect(phone.headline, 'Associates with SAE (8), CCMP-128, PMF on');
      // The ladders differ where it matters: SAE frames for the phone only.
      final JrSequence a = _ladder(
        ScClientPreset.olderLaptop.client,
        const ScNetwork(security: ScNetSecurity.wpa3Transition),
      );
      final JrSequence b = _ladder(
        ScClientPreset.phoneWpa3.client,
        const ScNetwork(security: ScNetSecurity.wpa3Transition),
      );
      expect(a.inPhase(JrPhase.saeAuth), isEmpty);
      expect(a.inPhase(JrPhase.openAuth), hasLength(2));
      expect(b.inPhase(JrPhase.saeAuth), hasLength(4));
      expect(a.failed, isFalse);
      expect(b.failed, isFalse);
    });

    test('the printer on WPA3-Personal transition associates with PSK', () {
      final ScVerdict v = _v(
        ScClientPreset.printer,
        ScNetSecurity.wpa3Transition,
      );
      expect(v.outcome, ScOutcome.associates);
      expect(v.akm, ScAkm.psk);
      expect(v.pmfOn, isFalse);
    });

    test('WPA3-Enterprise transition: SHA-1 for the old laptop, SHA-256 for '
        'the phone', () {
      expect(
        _v(
          ScClientPreset.olderLaptop,
          ScNetSecurity.wpa3EnterpriseTransition,
        ).akm,
        ScAkm.dot1x,
      );
      expect(
        _v(
          ScClientPreset.phoneWpa3,
          ScNetSecurity.wpa3EnterpriseTransition,
        ).akm,
        ScAkm.dot1xSha256,
      );
    });
  });

  group('6 GHz: a refusal, never a swap', () {
    for (final ScNetSecurity s in ScNetSecurity.values) {
      test('${s.label} in 6 GHz', () {
        final ScVerdict v = _v(ScClientPreset.newLaptop, s, band: JrBand.g6);
        if (s.allowedIn6GHz) {
          expect(v.outcome, ScOutcome.associates);
        } else {
          expect(v.outcome, ScOutcome.notOffered);
          expect(v.headline, 'Not offered: 6 GHz does not allow ${s.label}');
          expect(v.source, s.sixGhzRule);
        }
      });
    }

    test('WPA2-Personal in 6 GHz: a lost probe, not SAE frames', () {
      final JrSequence s = _ladder(
        ScClientPreset.newLaptop.client,
        const ScNetwork(security: ScNetSecurity.wpa2Personal, band: JrBand.g6),
      );
      expect(s.length, 1);
      expect(s.messages.single.label, 'Probe Request');
      expect(s.messages.single.lost, isTrue);
      expect(s.inPhase(JrPhase.saeAuth), isEmpty);
      expect(s.scanDrawn, isFalse);
      // The ordinary Join mode still swaps, exactly as before.
      final JrSequence join = buildJoin(
        const JrConfig(security: JrSecurity.psk, band: JrBand.g6),
      );
      expect(join.security, JrSecurity.sae);
    });

    test('802.1X SHA-1 in 6 GHz: the source says it is a WFA rule only', () {
      expect(
        ScNetSecurity.wpa2Enterprise.sixGhzRule,
        contains('does not ban it'),
      );
    });
  });

  group('a Wi-Fi 7 connection', () {
    test('Wi-Fi 7 phone on a Wi-Fi 7 WPA3-Personal AP: SAE (24), GCMP-256, '
        'PMF on', () {
      final ScVerdict v = _v(
        ScClientPreset.phoneWifi7,
        ScNetSecurity.wpa3Personal,
        wifi7: true,
      );
      expect(v.wifi7, isTrue);
      expect(v.akm, ScAkm.saeExt);
      expect(v.pairwise, ScCipher.gcmp256);
      expect(v.pmfOn, isTrue);
      expect(
        v.headline,
        'Associates: a Wi-Fi 7 connection with SAE (24), GCMP-256, PMF on',
      );
      final JrSequence s = _ladder(
        ScClientPreset.phoneWifi7.client,
        const ScNetwork(security: ScNetSecurity.wpa3Personal, wifi7: true),
      );
      final JrMessage req = s.messages.firstWhere(
        (JrMessage m) => m.label == 'Association Request',
      );
      expect(req.fields.map((JrField f) => f.$1), contains('EHT Capabilities'));
      expect(req.fields, contains(('RSN element: AKM', 'SAE (24)')));
    });

    test(
      'Wi-Fi 7 phone on a Wi-Fi 7 WPA2-Personal AP: associates as Wi-Fi 6',
      () {
        final ScVerdict v = _v(
          ScClientPreset.phoneWifi7,
          ScNetSecurity.wpa2Personal,
          wifi7: true,
        );
        expect(v.outcome, ScOutcome.associates);
        expect(v.wifi7, isFalse);
        expect(v.wifi6Because, 'PSK is not allowed in a Wi-Fi 7 connection.');
        expect(v.headline, startsWith('Associates as Wi-Fi 6 with PSK (2)'));
        final JrSequence s = _ladder(
          ScClientPreset.phoneWifi7.client,
          const ScNetwork(security: ScNetSecurity.wpa2Personal, wifi7: true),
        );
        final JrMessage req = s.messages.firstWhere(
          (JrMessage m) => m.label == 'Association Request',
        );
        expect(
          req.fields.map((JrField f) => f.$1),
          isNot(contains('EHT Capabilities')),
        );
      },
    );

    test('a Wi-Fi 7 client with SAE type 8 only falls back to Wi-Fi 6', () {
      final ScClient c = ScClientPreset.phoneWifi7.client.withAkm(
        ScAkm.saeExt,
        false,
      );
      final ScVerdict v = evaluateSecurityVerdict(
        c,
        const ScNetwork(security: ScNetSecurity.wpa3Personal, wifi7: true),
      );
      expect(v.wifi7, isFalse);
      expect(v.akm, ScAkm.sae);
      expect(v.wifi6Because, contains('SAE type 24'));
    });

    test('without GCMP-256 on the client: Wi-Fi 6', () {
      final ScClient c = ScClientPreset.phoneWifi7.client.withCipher(
        ScCipher.gcmp256,
        false,
      );
      final ScVerdict v = evaluateSecurityVerdict(
        c,
        const ScNetwork(security: ScNetSecurity.wpa3Personal, wifi7: true),
      );
      expect(v.wifi7, isFalse);
      expect(v.wifi6Because, contains('GCMP-256'));
    });

    test('the WPA3-capable Wi-Fi 6 phone is never a Wi-Fi 7 connection', () {
      for (final ScNetwork n in _networks()) {
        final ScVerdict v = evaluateSecurityVerdict(
          ScClientPreset.phoneWpa3.client,
          n,
        );
        expect(v.wifi7, isFalse, reason: '${n.security} ${n.band}');
        expect(v.wifi6Because, isNull);
      }
    });

    test('open network with two Wi-Fi 7 sides: Wi-Fi 6, nothing encrypted', () {
      final ScVerdict v = _v(
        ScClientPreset.phoneWifi7,
        ScNetSecurity.open,
        wifi7: true,
      );
      expect(v.outcome, ScOutcome.associates);
      expect(v.wifi7, isFalse);
      expect(v.wifi6Because, isNotNull);
    });
  });

  group('every preset x every network (independent rules)', () {
    // The rules of spec 43, written out again here from the evidence file,
    // not from the model's code.
    ScOutcome expected(ScClient c, ScNetwork n) {
      const Set<ScNetSecurity> ok6 = <ScNetSecurity>{
        ScNetSecurity.owe,
        ScNetSecurity.wpa3Personal,
        ScNetSecurity.wpa3Enterprise,
        ScNetSecurity.wpa3Enterprise192,
      };
      if (n.band == JrBand.g6 && !ok6.contains(n.security)) {
        return ScOutcome.notOffered;
      }
      if (!c.bands.contains(n.band)) return ScOutcome.neverTries;
      if (n.security == ScNetSecurity.open) return ScOutcome.associates;
      final Set<ScAkm> common = c.akms.intersection(n.akms);
      if (common.isEmpty) return ScOutcome.neverTries;
      if (c.ciphers.intersection(n.pairwise).isEmpty ||
          !c.ciphers.contains(n.group)) {
        return ScOutcome.neverTries;
      }
      final bool apMfpc = n.pmfBits != JrPmf.off;
      final bool apMfpr = n.pmfBits == JrPmf.required;
      final bool aware = c.pmf != ScClientPmf.legacy;
      final bool cMfpc =
          c.pmf == ScClientPmf.capable || c.pmf == ScClientPmf.required;
      if (aware && apMfpr && !cMfpc) return ScOutcome.neverTries;
      if (aware && c.pmf == ScClientPmf.required && !apMfpc) {
        return ScOutcome.neverTries;
      }
      final bool pmfOn = cMfpc && apMfpc;
      final bool h2eNeeded =
          (n.security == ScNetSecurity.wpa3Personal ||
              n.security == ScNetSecurity.wpa3Transition) &&
          (n.h2eOnly || n.band == JrBand.g6);
      final Set<ScAkm> usable = common.where((ScAkm a) {
        final bool sae = a == ScAkm.sae || a == ScAkm.saeExt;
        if ((sae || a == ScAkm.owe) && !pmfOn) return false;
        if (sae && h2eNeeded && !c.h2e) return false;
        return true;
      }).toSet();
      if (usable.isEmpty) return ScOutcome.neverTries;
      if (!aware && apMfpr) return ScOutcome.refused;
      return ScOutcome.associates;
    }

    int count = 0;
    for (final ScClientPreset p in ScClientPreset.values) {
      test(p.label, () {
        for (final ScNetwork n in _networks()) {
          final ScVerdict v = evaluateSecurityVerdict(p.client, n);
          expect(
            v.outcome,
            expected(p.client, n),
            reason: '${n.security} ${n.band} pmf ${n.pmf} w7 ${n.wifi7}',
          );
          // A failure has a help-desk line; only a refusal has a status.
          expect(v.helpDesk != null, v.outcome.fails);
          expect(v.status != null, v.outcome == ScOutcome.refused);
          // Associate, never join.
          for (final String t in <String>[
            v.headline,
            v.why,
            v.helpDesk ?? '',
          ]) {
            expect(t.toLowerCase(), isNot(contains('join')));
            expect(t, isNot(contains('—')));
          }
          count++;
        }
      });
    }

    test('and the ladders stop where the verdict says', () {
      for (final ScClientPreset p in ScClientPreset.values) {
        for (final ScNetwork n in _networks()) {
          final ScResult r = evaluateSecurity(p.client, n);
          final JrSequence s = buildJoin(
            JrConfig(band: n.band, pmf: n.pmf),
            security: r.override,
          );
          final String why = '${p.name} ${n.security} ${n.band} ${n.wifi7}';
          expect(s.failed, r.verdict.outcome.fails, reason: why);
          if (s.failed) {
            expect(s.failedAt, s.length - 1, reason: why);
            expect(s.faultNote, isNotNull, reason: why);
            expect(s.faultNote!.toLowerCase(), isNot(contains('join')));
          } else {
            expect(s.messages.last.phase, JrPhase.later, reason: why);
          }
          if (r.verdict.outcome == ScOutcome.neverTries &&
              p.client.bands.contains(n.band)) {
            expect(
              s.messages.where((JrMessage m) => _authOrAssoc.contains(m.label)),
              isEmpty,
              reason: why,
            );
          }
        }
      }
    });

    test('the sweep covered every preset', () {
      expect(count, greaterThan(0));
    });
  });

  group('supporting facts', () {
    test('AKM and cipher selectors match Tables 9-190 and 9-188', () {
      expect(
        <int>[for (final ScAkm a in ScAkm.values) a.selector],
        <int>[2, 8, 24, 18, 1, 5, 12],
      );
      expect(
        <int>[for (final ScCipher c in ScCipher.values) c.selector],
        <int>[2, 4, 9],
      );
    });

    test('presets resolve back to themselves; an edit reads as custom', () {
      for (final ScClientPreset p in ScClientPreset.values) {
        expect(ScClientPreset.of(p.client), p);
      }
      expect(
        ScClientPreset.of(
          ScClientPreset.printer.client.withAkm(ScAkm.sae, true),
        ),
        isNull,
      );
    });

    test('ASCII only in every verdict string', () {
      for (final ScClientPreset p in ScClientPreset.values) {
        for (final ScNetwork n in _networks()) {
          final ScVerdict v = evaluateSecurityVerdict(p.client, n);
          for (final String t in <String>[
            v.headline,
            v.why,
            v.source,
            v.helpDesk ?? '',
          ]) {
            // Section sign is the one non-ASCII character allowed (citations).
            expect(
              t.replaceAll('§', '').codeUnits.every((int u) => u < 128),
              isTrue,
              reason: t,
            );
          }
        }
      }
    });
  });
}
