// Tests for the PHY Preamble Reference model (Wi-Fi Lab).
//
// Pins every "Done means" clause of myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/13-phy-preamble.md against Pax's wave-5 brief
// (Deliverables/2026-09-25-wifi-lab-wave5-research/brief.md) and against the
// Airtime Anatomy service, which draws the same preambles.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_anatomy.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/phy_preamble.dart';

int _pre(PreambleSettings s) => preambleTenths(s);

PreambleBlock _block(PreambleSettings s, String name) =>
    preambleBlocks(s).firstWhere((PreambleBlock b) => b.name == name);

/// Every table the model can open, with a name for failure messages.
Map<String, SigTable> _allTables() => <String, SigTable>{
  'L-SIG': kLsigTable,
  'SERVICE': serviceTable(vht: false),
  'SERVICE VHT': serviceTable(vht: true),
  'HT-SIG': kHtSigTable,
  'VHT-SIG-A': kVhtSigATable,
  for (final int w in kPreambleWidthsMhz) 'VHT-SIG-B $w': vhtSigBTable(w),
  'HE-SIG-A SU': heSigASuTable(erSu: false),
  'HE-SIG-A ER SU': heSigASuTable(erSu: true),
  'HE-SIG-A MU': kHeSigAMuTable,
  'HE-SIG-A TB': kHeSigATbTable,
  'HE-SIG-B': kHeSigBTable,
  'U-SIG MU': uSigTable(tb: false),
  'U-SIG TB': uSigTable(tb: true),
  'EHT-SIG': kEhtSigTable,
};

void main() {
  group('SIG table widths sum to the field size', () {
    test('the five the spec names', () {
      expect(kLsigTable.totalBits, 24);
      expect(kLsigTable.fieldWidthSum, 24);
      expect(kHtSigTable.totalBits, 48);
      expect(kHtSigTable.fieldWidthSum, 48);
      expect(kVhtSigATable.totalBits, 48);
      expect(kVhtSigATable.fieldWidthSum, 48);
      for (final SigTable t in <SigTable>[
        heSigASuTable(erSu: false),
        heSigASuTable(erSu: true),
        kHeSigAMuTable,
        kHeSigATbTable,
      ]) {
        expect(t.totalBits, 52, reason: t.title);
        expect(t.fieldWidthSum, 52, reason: t.title);
      }
      for (final bool tb in <bool>[false, true]) {
        expect(uSigTable(tb: tb).totalBits, 52);
        expect(uSigTable(tb: tb).fieldWidthSum, 52);
      }
    });

    test('SERVICE is 16 bits, non-HT and VHT', () {
      expect(serviceTable(vht: false).fieldWidthSum, 16);
      expect(serviceTable(vht: true).fieldWidthSum, 16);
      expect(
        serviceTable(vht: true).find('VHT-SIG-B CRC')!.field.bitsLabel,
        'B8-B15',
      );
    });

    test('VHT-SIG-B: 26 / 27 / 29 bits for SU and MU per width', () {
      const Map<int, int> totals = <int, int>{20: 26, 40: 27, 80: 29, 160: 29};
      for (final MapEntry<int, int> e in totals.entries) {
        final SigTable t = vhtSigBTable(e.key);
        expect(t.groupsAreAlternatives, isTrue);
        expect(t.groups, hasLength(2));
        for (final BitGroup g in t.groups) {
          expect(g.bits, e.value, reason: g.title);
          expect(g.fieldWidthSum, e.value, reason: g.title);
        }
      }
      // Brief section 4: 20 MHz SU is LENGTH 17 + reserved 3 + tail 6.
      final BitGroup su20 = vhtSigBTable(20).groups.first;
      expect(su20.fields.map((BitField f) => f.width).toList(), <int>[
        17,
        3,
        6,
      ]);
      final BitGroup mu80 = vhtSigBTable(80).groups.last;
      expect(mu80.fields.map((BitField f) => f.width).toList(), <int>[
        19,
        4,
        6,
      ]);
    });

    test('every group with a declared size is exactly covered, B0 upward', () {
      _allTables().forEach((String name, SigTable t) {
        for (final BitGroup g in t.groups) {
          if (g.bits == null) continue;
          expect(g.fieldWidthSum, g.bits, reason: '$name ${g.title}');
          int next = 0;
          for (final BitField f in g.fields.where((BitField f) => f.isPlaced)) {
            expect(f.start, next, reason: '$name ${g.title} ${f.name}');
            next = f.end! + 1;
          }
          expect(next, g.bits, reason: '$name ${g.title} ends short');
        }
      });
    });

    test('HE-SIG-B user field is 21 bits either way', () {
      final List<BitGroup> users = kHeSigBTable.groups
          .where((BitGroup g) => g.title.startsWith('User field'))
          .toList();
      expect(users, hasLength(2));
      for (final BitGroup g in users) {
        expect(g.fieldWidthSum, 21, reason: g.title);
      }
    });
  });

  group('preamble totals: brief section 1', () {
    test('legacy is 20 us and every PHY starts with it', () {
      for (final PpduType t in PpduType.values) {
        final List<PreambleBlock> b = preambleBlocks(PreambleSettings(type: t));
        expect(b.take(3).map((PreambleBlock x) => x.name).toList(), <String>[
          'L-STF',
          'L-LTF',
          'L-SIG',
        ], reason: t.label);
        expect(
          b
              .where((PreambleBlock x) => x.role == BlockRole.legacy)
              .fold<int>(0, (int a, PreambleBlock x) => a + x.tenths),
          kLegacyPreambleTenths,
          reason: t.label,
        );
        expect(b.last.role, BlockRole.data);
      }
      expect(_pre(const PreambleSettings(type: PpduType.nonHt)), 200);
    });

    test('HT mixed: 20 + HT-SIG 8 + HT-STF 4 + 4 per HT-LTF (1, 2, 4, 4)', () {
      const List<int> ltfs = <int>[1, 2, 4, 4];
      for (int n = 1; n <= 4; n++) {
        expect(
          _pre(PreambleSettings(type: PpduType.htMixed, streams: n)),
          (32 + 4 * ltfs[n - 1]) * 10,
          reason: '$n streams',
        );
      }
    });

    test('VHT: 36 + 4 x N_VHT-LTF (20 + SIG-A 8 + STF 4 + SIG-B 4)', () {
      for (int n = 1; n <= 8; n++) {
        final PreambleSettings s = PreambleSettings(
          type: PpduType.vht,
          streams: n,
        );
        expect(_pre(s), (36 + 4 * kVhtLtfCount[n]!) * 10, reason: '$n SS');
      }
    });

    test('HE SU / MU / TB / ER SU and EHT MU / TB field by field', () {
      for (final HeLtfMode m in HeLtfMode.values) {
        for (int n = 1; n <= 8; n++) {
          final int ltf = kVhtLtfCount[n]! * m.ltfTenths;
          int p(PpduType t, {int sig = 2}) => _pre(
            PreambleSettings(type: t, streams: n, ltf: m, sigSymbols: sig),
          );
          // 20 + RL-SIG 4 + HE-SIG-A 8 + HE-STF 4 + LTFs.
          expect(p(PpduType.heSu), 360 + ltf);
          // HE-SIG-A is 16 us in ER SU.
          expect(p(PpduType.heErSu), 440 + ltf);
          // HE-SIG-B 4 us per symbol, MU only.
          expect(p(PpduType.heMu, sig: 5), 360 + 200 + ltf);
          // HE-STF is 8 us in TB.
          expect(p(PpduType.heTb), 400 + ltf);
          // 20 + RL-SIG 4 + U-SIG 8 + EHT-SIG 4n + EHT-STF 4 + LTFs.
          expect(p(PpduType.ehtMu, sig: 3), 360 + 120 + ltf);
          // TB: no EHT-SIG, EHT-STF 8.
          expect(p(PpduType.ehtTb), 400 + ltf);
        }
      }
    });

    test('HE-LTF lengths are 6.4 or 12.8 us plus GI', () {
      expect(HeLtfMode.x2gi08.ltfTenths, 72);
      expect(HeLtfMode.x2gi16.ltfTenths, 80);
      expect(HeLtfMode.x4gi08.ltfTenths, 136);
      expect(HeLtfMode.x4gi32.ltfTenths, 160);
    });

    test('HT stops at 4 streams; streams above clamp', () {
      expect(PpduType.htMixed.maxStreams, 4);
      expect(
        _pre(const PreambleSettings(type: PpduType.htMixed, streams: 8)),
        _pre(const PreambleSettings(type: PpduType.htMixed, streams: 4)),
      );
    });
  });

  group('agrees with the Airtime Anatomy service', () {
    AirtimeScenario scen(AirtimePhy phy, int n, GuardInterval gi) =>
        AirtimeScenario(
          band: AirtimeBand.ghz5,
          phy: phy,
          widthMhz: 20,
          mcs: 0,
          streams: n,
          guardInterval: gi,
        );

    test('Legacy', () {
      expect(
        _pre(const PreambleSettings(type: PpduType.nonHt)),
        computeAirtime(
          scen(AirtimePhy.legacy, 1, GuardInterval.gi08),
        ).preambleTenths,
      );
    });

    test('HT, 1-4 streams, both GIs', () {
      for (int n = 1; n <= 4; n++) {
        for (final GuardInterval gi in <GuardInterval>[
          GuardInterval.gi04,
          GuardInterval.gi08,
        ]) {
          expect(
            _pre(PreambleSettings(type: PpduType.htMixed, streams: n)),
            computeAirtime(scen(AirtimePhy.ht, n, gi)).preambleTenths,
            reason: 'HT $n SS',
          );
        }
      }
    });

    test('VHT, 1-8 streams', () {
      for (int n = 1; n <= 8; n++) {
        expect(
          _pre(PreambleSettings(type: PpduType.vht, streams: n)),
          computeAirtime(
            scen(AirtimePhy.vht, n, GuardInterval.gi08),
          ).preambleTenths,
          reason: 'VHT $n SS',
        );
      }
    });

    test('HE SU, 1-8 streams, the three LTF/GI pairs the service offers', () {
      const Map<GuardInterval, HeLtfMode> pairs = <GuardInterval, HeLtfMode>{
        GuardInterval.gi08: HeLtfMode.x2gi08,
        GuardInterval.gi16: HeLtfMode.x2gi16,
        GuardInterval.gi32: HeLtfMode.x4gi32,
      };
      for (int n = 1; n <= 8; n++) {
        pairs.forEach((GuardInterval gi, HeLtfMode m) {
          expect(
            _pre(PreambleSettings(type: PpduType.heSu, streams: n, ltf: m)),
            computeAirtime(scen(AirtimePhy.he, n, gi)).preambleTenths,
            reason: 'HE $n SS ${m.label}',
          );
        });
      }
    });

    test('the 12-bit LENGTH ceiling is the service\'s 5,484 us PPDU limit', () {
      expect(maxTxtimeTenths(0), AirtimeConstants.maxPpduUs * 10);
    });
  });

  group('L-SIG LENGTH', () {
    test('brief: LENGTH = 3k - 3 - m makes a legacy radio count k symbols', () {
      // The brief's worked derivation: 16 + 8 x (3k - 3 - m) + 6 = 24k - 2 -
      // 8m, and ceil((24k - 2) / 24), ceil((24k - 10) / 24) and
      // ceil((24k - 18) / 24) are all k.
      for (int k = 2; k <= 1366; k++) {
        for (final int m in <int>[0, 1, 2]) {
          final int length = 3 * k - 3 - m;
          if (length < 0) continue;
          expect(legacySymbolsFor(length), k, reason: 'k $k m $m');
        }
      }
    });

    test('TXTIME = 20 + 4k gives 3k - 3 - m and defers exactly TXTIME', () {
      for (final PpduType t in PpduType.values) {
        if (t == PpduType.nonHt) continue;
        final int pre = _pre(PreambleSettings(type: t));
        for (int k = 20; k <= 1360; k += 7) {
          final int tx = (20 + 4 * k) * 10;
          final LsigLengthResult r = spoofLsigLength(
            txtimeTenths: tx,
            type: t,
            preambleTenthsOfType: pre,
          );
          expect(r.ok, isTrue, reason: '${t.label} k $k');
          expect(r.length, 3 * k - 3 - lsigM(t));
          expect(r.legacySymbols, k);
          expect(r.legacyDeferTenths, tx);
        }
      }
    });

    test(
      'm is 1 for HE MU and ER SU, 2 for HE SU and TB, never mod 0 in HE',
      () {
        expect(lsigM(PpduType.heMu), 1);
        expect(lsigM(PpduType.heErSu), 1);
        expect(lsigM(PpduType.heSu), 2);
        expect(lsigM(PpduType.heTb), 2);
        for (final PpduType t in <PpduType>[
          PpduType.htMixed,
          PpduType.vht,
          PpduType.ehtMu,
          PpduType.ehtTb,
        ]) {
          expect(lsigM(t), 0);
        }
        for (final PpduType t in PpduType.values.where(
          (PpduType t) => t.isHe,
        )) {
          final LsigLengthResult r = spoofLsigLength(
            txtimeTenths: 3001,
            type: t,
            preambleTenthsOfType: _pre(PreambleSettings(type: t)),
          );
          expect(r.lengthMod3, isNot(0), reason: t.label);
          expect(
            r.lengthMod3,
            t == PpduType.heMu || t == PpduType.heErSu ? 2 : 1,
          );
        }
      },
    );

    test('a TXTIME that is not a whole number of symbols rounds up', () {
      // VHT with short GI: 3.6 us symbols. 100.8 us -> ceil(80.8 / 4) = 21.
      final LsigLengthResult r = spoofLsigLength(
        txtimeTenths: 1008,
        type: PpduType.vht,
        preambleTenthsOfType: 400,
      );
      expect(r.k, 21);
      expect(r.length, 60);
      expect(r.legacyDeferTenths, 1040);
      expect(r.legacyDeferTenths, greaterThanOrEqualTo(1008));
    });

    test('2.4 GHz: signal extension is taken off, then added back', () {
      final LsigLengthResult r = spoofLsigLength(
        txtimeTenths: 2060,
        type: PpduType.htMixed,
        preambleTenthsOfType: 360,
        signalExtensionUs: kSignalExtensionUs,
      );
      expect(r.k, 45);
      expect(r.length, 132);
      expect(r.legacyDeferTenths, 2060);
    });

    test('errors: non-HT, shorter than the preamble, over 4095', () {
      expect(
        spoofLsigLength(
          txtimeTenths: 2000,
          type: PpduType.nonHt,
          preambleTenthsOfType: 200,
        ).error,
        LsigLengthError.notSpoofed,
      );
      expect(
        spoofLsigLength(
          txtimeTenths: 300,
          type: PpduType.heSu,
          preambleTenthsOfType: 432,
        ).error,
        LsigLengthError.shorterThanPreamble,
      );
      expect(
        spoofLsigLength(
          txtimeTenths: 54840,
          type: PpduType.vht,
          preambleTenthsOfType: 400,
        ).ok,
        isTrue,
      );
      expect(
        spoofLsigLength(
          txtimeTenths: 54850,
          type: PpduType.vht,
          preambleTenthsOfType: 400,
        ).error,
        LsigLengthError.tooLong,
      );
    });

    test('the help example', () {
      // assets/help/tool_help.json, phy-preamble "example".
      const PreambleSettings s = PreambleSettings(
        type: PpduType.heSu,
        streams: 2,
      );
      expect(formatPreambleTenths(_pre(s)), '50.4');
      final LsigLengthResult r = spoofLsigLength(
        txtimeTenths: 2000,
        type: PpduType.heSu,
        preambleTenthsOfType: _pre(s),
      );
      expect(r.length, 130);
      expect(r.lengthMod3, 1);
      expect(r.legacySymbols, 45);
      expect(r.legacyDeferTenths, 2000);
      final LsigLengthResult mu = spoofLsigLength(
        txtimeTenths: 2000,
        type: PpduType.heMu,
        preambleTenthsOfType: _pre(const PreambleSettings(type: PpduType.heMu)),
      );
      expect(mu.length, 131);
      expect(mu.lengthMod3, 2);
    });
  });

  group('BSS color: brief section 5', () {
    test('position moves with the HE PPDU type and is fixed in EHT', () {
      expect(bssColorPosition(PpduType.heSu), (
        symbol: 'HE-SIG-A1',
        start: 8,
        end: 13,
      ));
      expect(bssColorPosition(PpduType.heErSu), (
        symbol: 'HE-SIG-A1',
        start: 8,
        end: 13,
      ));
      expect(bssColorPosition(PpduType.heMu), (
        symbol: 'HE-SIG-A1',
        start: 5,
        end: 10,
      ));
      expect(bssColorPosition(PpduType.heTb), (
        symbol: 'HE-SIG-A1',
        start: 1,
        end: 6,
      ));
      expect(bssColorPosition(PpduType.ehtMu), (
        symbol: 'U-SIG-1',
        start: 7,
        end: 12,
      ));
      expect(bssColorPosition(PpduType.ehtTb), (
        symbol: 'U-SIG-1',
        start: 7,
        end: 12,
      ));
      for (final PpduType t in <PpduType>[
        PpduType.nonHt,
        PpduType.htMixed,
        PpduType.vht,
      ]) {
        expect(bssColorPosition(t), isNull);
      }
    });
  });

  group('which PHY is this: brief section 8', () {
    test('the tree classifies every PPDU type correctly', () {
      for (final PpduType t in PpduType.values) {
        expect(
          classify(observe(t)).result,
          DetectedFormat.expectedFor(t),
          reason: t.label,
        );
      }
    });

    test('step shapes', () {
      expect(classify(observe(PpduType.htMixed)).steps, hasLength(1));
      expect(classify(observe(PpduType.vht)).steps, hasLength(3));
      expect(classify(observe(PpduType.nonHt)).steps, hasLength(3));
      for (final PpduType t in <PpduType>[
        PpduType.heSu,
        PpduType.heTb,
        PpduType.heMu,
        PpduType.heErSu,
        PpduType.ehtMu,
      ]) {
        expect(classify(observe(t)).steps, hasLength(4), reason: t.label);
      }
      // The ER SU test and the EHT branch are single-source in the brief.
      expect(classify(observe(PpduType.heErSu)).steps.last.evidence.tag, 'S1');
      expect(classify(observe(PpduType.ehtMu)).steps[2].evidence.tag, 'S1');
    });

    test('a later PHY version is not called EHT', () {
      const PpduObservation later = PpduObservation(
        firstAfterLsig: SymbolLook.bpsk,
        repeatsLsig: true,
        secondAfterLsig: SymbolLook.bpsk,
        lengthMod3: 0,
        uSigVersion: 1,
      );
      expect(classify(later).result, DetectedFormat.laterThanEht);
    });
  });

  group('modulation on each SIG symbol', () {
    List<SymbolModulation> mods(PpduType t, String name) =>
        _block(PreambleSettings(type: t), name).modulations;

    test('matches brief sections 1 and 8', () {
      const SymbolModulation b = SymbolModulation.bpsk;
      const SymbolModulation q = SymbolModulation.qbpsk;
      expect(mods(PpduType.nonHt, 'L-SIG'), <SymbolModulation>[b]);
      expect(mods(PpduType.htMixed, 'HT-SIG'), <SymbolModulation>[q, q]);
      expect(mods(PpduType.vht, 'VHT-SIG-A'), <SymbolModulation>[b, q]);
      expect(mods(PpduType.vht, 'VHT-SIG-B'), <SymbolModulation>[b]);
      expect(mods(PpduType.heSu, 'RL-SIG'), <SymbolModulation>[b]);
      expect(mods(PpduType.heSu, 'HE-SIG-A'), <SymbolModulation>[b, b]);
      expect(mods(PpduType.heErSu, 'HE-SIG-A'), <SymbolModulation>[b, q, b, b]);
      expect(mods(PpduType.ehtMu, 'U-SIG'), <SymbolModulation>[b, b]);
    });

    test('every 4 us SIG symbol is marked, or says why not', () {
      for (final PpduType t in PpduType.values) {
        for (final PreambleBlock blk in preambleBlocks(
          PreambleSettings(type: t, sigSymbols: 3),
        )) {
          if (blk.form != BlockForm.signal) continue;
          expect(
            blk.modulations.length == blk.count || blk.modulationNote != null,
            isTrue,
            reason: '${t.label} ${blk.name}',
          );
        }
      }
    });
  });

  group('evidence tags', () {
    const Set<String> briefTags = <String>{
      'P',
      'S2',
      'S2+',
      'P/S2',
      'S1',
      'INF',
      'P, single vendor',
      'not verified',
      'none',
    };

    test('every field carries at least one tag, from the brief\'s set', () {
      _allTables().forEach((String name, SigTable t) {
        for (final BitField f in t.allFields) {
          expect(f.evidence, isNotEmpty, reason: '$name ${f.name}');
          for (final Evidence e in f.evidence) {
            expect(briefTags, contains(e.tag), reason: '$name ${f.name}');
          }
        }
      });
    });

    test('S1, INF, single vendor and untagged are never settled', () {
      _allTables().forEach((String name, SigTable t) {
        for (final BitField f in t.allFields) {
          for (final Evidence e in f.evidence) {
            if (e.tag == 'S1' ||
                e.tag == 'INF' ||
                e.tag == 'P, single vendor' ||
                e.tag == 'not verified' ||
                e.tag == 'none') {
              expect(e.isSettled, isFalse, reason: '$name ${f.name}');
              expect(f.isSettled, isFalse, reason: '$name ${f.name}');
            }
          }
        }
      });
    });

    test('specific fields, as the brief marks them', () {
      // HE TB HE-SIG-A2 is inferred in full.
      for (final BitField f in kHeSigATbTable.groups.last.fields) {
        expect(f.evidence.single.tag, 'INF');
      }
      // HE TB HE-SIG-A1 is Intel only.
      expect(
        kHeSigATbTable.find('BSS Color')!.field.evidence.single.tag,
        'P, single vendor',
      );
      // VHT-SIG-B: 20 MHz settled, 40 and 80 not.
      expect(
        vhtSigBTable(20).allFields.every((BitField f) => f.isSettled),
        isTrue,
      );
      expect(
        vhtSigBTable(40).allFields.any((BitField f) => f.isSettled),
        isFalse,
      );
      // HE-SIG-B Beamformed at B14 is inferred.
      final BitField bf = kHeSigBTable.find('Beamformed')!.field;
      expect(bf.bitsLabel, 'B14');
      expect(bf.evidence.single.tag, 'INF');
      // HE SU CRC and Tail are inferred; the rest of HE SU is S2.
      final SigTable su = heSigASuTable(erSu: false);
      expect(su.find('CRC')!.field.evidence.single.tag, 'INF');
      expect(su.find('BSS Color')!.field.evidence.single.tag, 'S2');
      // HE MU: one vendor, except the two Intel confirms.
      expect(kHeSigAMuTable.find('BSS Color')!.field.isSettled, isFalse);
      expect(kHeSigAMuTable.find('SIG-B Compression')!.field.isSettled, isTrue);
      expect(kHeSigAMuTable.find('Reserved')!.field.evidence.single.tag, 'INF');
      // U-SIG is S2+, but the 802.11bn value is S1.
      expect(uSigTable(tb: false).find('BSS Color')!.field.isSettled, isTrue);
      expect(
        uSigTable(tb: false).find('PHY Version Identifier')!.field.isSettled,
        isFalse,
      );
      // VHT-SIG-A2 CRC and Tail have no tag in the brief.
      final BitField crc = kVhtSigATable.groups.last.fields.firstWhere(
        (BitField f) => f.name == 'CRC',
      );
      expect(crc.evidence.single.level, EvidenceLevel.untagged);
      // L-SIG and HT-SIG are S2+ on every row.
      expect(kLsigTable.allFields.every((BitField f) => f.isSettled), isTrue);
      expect(kHtSigTable.allFields.every((BitField f) => f.isSettled), isTrue);
    });

    test('timing tags: HT-LTF count S1, VHT above 4 streams not verified,'
        ' EHT TB S1, EHT-LTF length inferred', () {
      expect(
        _block(
          const PreambleSettings(type: PpduType.htMixed),
          'HT-LTF',
        ).countEvidence!.tag,
        'S1',
      );
      expect(
        _block(
          const PreambleSettings(type: PpduType.vht, streams: 6),
          'VHT-LTF',
        ).countEvidence!.tag,
        'not verified',
      );
      expect(
        _block(
          const PreambleSettings(type: PpduType.ehtTb),
          'EHT-STF',
        ).timingSettled,
        isFalse,
      );
      expect(
        _block(
          const PreambleSettings(type: PpduType.ehtMu),
          'EHT-LTF',
        ).durationEvidence.any((Evidence e) => e.tag == 'INF'),
        isTrue,
      );
      expect(
        _block(
          const PreambleSettings(type: PpduType.nonHt),
          'L-STF',
        ).timingSettled,
        isTrue,
      );
    });
  });
}
