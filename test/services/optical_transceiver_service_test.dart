// OpticalTransceiverService unit tests — JSON parsing (incl. malformed-row
// tolerance), tier ordering + lead flags, the IEEE/vendor honesty flag and its
// verbatim loss-budget caveat, substring search across every facet, and the
// empty-result honesty path. Built from an in-memory JSON string (no asset
// load), then a second group loads the REAL bundled asset and asserts the
// published counts (35 variants / 9 form factors / 5 vendor rows).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/optical_transceiver_service.dart';

const String _fixture = '''
{
  "tiers": [
    {
      "tier": "10G", "formFactor": "SFP+", "lead": true,
      "entries": [
        { "designation": "10GBASE-SR", "rate": "10 Gbps", "reach": "300 m (OM3); 400 m (OM4)", "fiber": "MMF (OM1-OM4)", "fiberKind": "mmf", "wavelength": "850 nm", "connector": "LC", "connectorKind": "lc", "notes": "Most common 10G multimode link.", "vendor": false, "reachCaveat": "" },
        { "designation": "10GBASE-ZR", "rate": "10 Gbps", "reach": "80 km", "fiber": "SMF (OS2)", "fiberKind": "smf", "wavelength": "1550 nm", "connector": "LC", "connectorKind": "lc", "notes": "Vendor variant, not IEEE-standardized.", "vendor": true, "reachCaveat": "vendor · loss-budget dependent" }
      ]
    },
    {
      "tier": "1G", "formFactor": "SFP", "lead": false,
      "entries": [
        { "designation": "1000BASE-SX", "rate": "1 Gbps", "reach": "550 m (OM3)", "fiber": "MMF (OM1-OM4)", "fiberKind": "mmf", "wavelength": "850 nm", "connector": "LC/SC", "connectorKind": "lc", "notes": "Short-reach multimode.", "vendor": false, "reachCaveat": "" }
      ]
    }
  ],
  "formFactors": [
    { "formFactor": "SFP", "maxRate": "1 Gbps", "lanes": "1", "power": "<1 W", "notes": "1G fiber and copper." },
    { "formFactor": "QSFP28", "maxRate": "100 Gbps", "lanes": "4", "power": "~3.5-4.5 W", "notes": "Workhorse 100G." }
  ]
}
''';

void main() {
  final OpticalTransceiverService svc =
      OpticalTransceiverService.fromJson(_fixture);

  group('parse', () {
    test('loads every tier and variant, preserving asset (tier) order', () {
      expect(svc.tiers.length, 2);
      expect(svc.tiers.map((OpticalTier t) => t.tier), <String>['10G', '1G']);
      expect(svc.variantCount, 3);
      expect(svc.formFactorCount, 2);
    });

    test('lead flag is carried through', () {
      expect(svc.tiers.first.lead, isTrue); // 10G
      expect(svc.tiers.last.lead, isFalse); // 1G
    });

    test('maps every variant field', () {
      final OpticalVariant sr =
          svc.tiers.first.entries.firstWhere((v) => v.designation == '10GBASE-SR');
      expect(sr.rate, '10 Gbps');
      expect(sr.reach, contains('OM4'));
      expect(sr.fiber, 'MMF (OM1-OM4)');
      expect(sr.fiberKind, OpticalFiberKind.mmf);
      expect(sr.wavelength, '850 nm');
      expect(sr.connector, 'LC');
      expect(sr.connectorKind, OpticalConnectorKind.lc);
      expect(sr.vendor, isFalse);
      expect(sr.reachCaveat, isEmpty);
    });

    test('vendor flag + verbatim loss-budget caveat are preserved (honesty)', () {
      final OpticalVariant zr =
          svc.tiers.first.entries.firstWhere((v) => v.designation == '10GBASE-ZR');
      expect(zr.vendor, isTrue);
      expect(zr.reachCaveat, 'vendor · loss-budget dependent');
    });

    test('maps form-factor rows', () {
      expect(svc.formFactors.map((f) => f.formFactor),
          containsAll(<String>['SFP', 'QSFP28']));
      final OpticalFormFactor q = svc.formFactors
          .firstWhere((OpticalFormFactor f) => f.formFactor == 'QSFP28');
      expect(q.maxRate, '100 Gbps');
      expect(q.lanes, '4');
      expect(q.power, '~3.5-4.5 W');
    });

    test('drops malformed rows but keeps the good ones', () {
      const String bad = '''
      {
        "tiers": [
          { "tier": "", "lead": true, "entries": [ { "designation": "X", "rate": "1", "reach": "1" } ] },
          { "tier": "40G", "formFactor": "QSFP+", "lead": false, "entries": [
            { "designation": "40GBASE-SR4", "rate": "40 Gbps", "reach": "100 m", "fiber": "MMF", "fiberKind": "mmf", "wavelength": "850 nm", "connector": "MPO-12", "connectorKind": "mpo", "notes": "x", "vendor": false, "reachCaveat": "" },
            { "rate": "no designation -> dropped" },
            { "designation": "40GBASE-LR4", "rate": "40 Gbps", "reach": "10 km", "fiber": "SMF", "fiberKind": "smf", "wavelength": "1310 nm", "connector": "LC", "connectorKind": "lc", "notes": "y", "vendor": false, "reachCaveat": "" }
          ] },
          { "tier": "200G", "lead": false, "entries": [] }
        ],
        "formFactors": [
          { "formFactor": "", "maxRate": "x" },
          { "formFactor": "OSFP", "maxRate": "800 Gbps", "lanes": "8", "power": "~20 W", "notes": "z" }
        ]
      }
      ''';
      final OpticalTransceiverService s =
          OpticalTransceiverService.fromJson(bad);
      // empty-tier and empty-entries tiers are dropped; only 40G survives.
      expect(s.tiers.length, 1);
      expect(s.tiers.single.tier, '40G');
      expect(s.tiers.single.entries.length, 2); // bad designation row dropped
      expect(s.formFactorCount, 1); // empty formFactor dropped
    });

    test('garbage document yields an empty-but-valid service', () {
      expect(OpticalTransceiverService.fromJson('not json').variantCount, 0);
      expect(OpticalTransceiverService.fromJson('[]').tiers, isEmpty);
      expect(
          OpticalTransceiverService.fromJson('{"nope": true}').tiers, isEmpty);
    });

    test('connector + fiber kind tokens parse, default to safe values', () {
      expect(OpticalConnectorKindParse.fromToken('MPO'),
          OpticalConnectorKind.mpo);
      expect(OpticalConnectorKindParse.fromToken('lc'), OpticalConnectorKind.lc);
      expect(OpticalConnectorKindParse.fromToken('???'), OpticalConnectorKind.lc);
      expect(OpticalFiberKindParse.fromToken('smf'), OpticalFiberKind.smf);
      expect(OpticalFiberKindParse.fromToken('mixed'), OpticalFiberKind.mixed);
      expect(OpticalFiberKindParse.fromToken('???'), OpticalFiberKind.mixed);
    });
  });

  group('search', () {
    test('empty / whitespace query returns every tier unfiltered', () {
      expect(svc.search('').length, svc.tiers.length);
      expect(svc.search('   ').length, svc.tiers.length);
      // order preserved
      expect(svc.search('').map((t) => t.tier), <String>['10G', '1G']);
    });

    test('designation substring narrows the tier in place', () {
      final List<OpticalTier> r = svc.search('ZR');
      expect(r.length, 1);
      expect(r.single.tier, '10G');
      expect(r.single.entries.single.designation, '10GBASE-ZR');
    });

    test('matches reach, fiber, wavelength, connector, and tier label', () {
      expect(svc.search('850 nm').isNotEmpty, isTrue); // wavelength
      expect(svc.search('smf').single.tier, '10G'); // fiber (only the ZR row)
      expect(svc.search('1550').single.tier, '10G'); // wavelength, ZR only
      // '1000BASE' is unique to the 1G tier (avoids '1G' matching '10G').
      expect(svc.search('1000BASE').single.tier, '1G'); // designation prefix
      expect(svc.search('400 m').single.tier, '10G'); // reach grade (SR row)
    });

    test('case-insensitive', () {
      expect(svc.search('10gbase-sr').isNotEmpty, isTrue);
      expect(svc.search('10GBASE-SR').isNotEmpty, isTrue);
    });

    test('a query with no match returns empty, not a fabricated tier', () {
      expect(svc.search('zzznotatransceiver'), isEmpty);
    });

    test('vendor keyword finds vendor rows only', () {
      final List<OpticalTier> r = svc.search('vendor');
      expect(r.length, 1);
      expect(r.single.entries.every((v) => v.vendor), isTrue);
    });
  });

  group('bundled asset', () {
    // Guards the SHIPPED data file: the published counts the catalog/help/screen
    // copy all claim (35 variants, 9 form factors, 5 vendor rows). A future edit
    // to the asset that changes these must update the copy too.
    late OpticalTransceiverService bundled;

    setUpAll(() {
      final String raw =
          File('assets/data/optical_transceivers.json').readAsStringSync();
      // sanity: the file is valid JSON
      jsonDecode(raw);
      bundled = OpticalTransceiverService.fromJson(raw);
    });

    test('parses 35 optical variants across 7 tiers', () {
      expect(bundled.variantCount, 35);
      expect(bundled.tiers.length, 7);
    });

    test('carries the 9-row SFP→OSFP form-factor ladder', () {
      expect(bundled.formFactorCount, 9);
      expect(bundled.formFactors.first.formFactor, 'SFP');
      expect(bundled.formFactors.last.formFactor, 'OSFP');
    });

    test('lead tiers 10G / 25G / 100G surface first, in that order', () {
      final List<OpticalTier> lead =
          bundled.tiers.where((OpticalTier t) => t.lead).toList();
      expect(lead.map((t) => t.tier), <String>['10G', '25G', '100G']);
      // and they are the first three tiers in the file
      expect(bundled.tiers.take(3).map((t) => t.tier),
          <String>['10G', '25G', '100G']);
    });

    test('exactly 5 vendor rows, each with the loss-budget caveat', () {
      final List<OpticalVariant> vendors = bundled.tiers
          .expand((OpticalTier t) => t.entries)
          .where((OpticalVariant v) => v.vendor)
          .toList();
      expect(vendors.length, 5);
      expect(
        vendors.map((v) => v.designation),
        containsAll(<String>[
          '1000BASE-EX',
          '1000BASE-ZX',
          '10GBASE-ZR',
          '400GBASE-ZR',
        ]),
      );
      for (final OpticalVariant v in vendors) {
        expect(v.reachCaveat, isNotEmpty,
            reason: '${v.designation} must keep its loss-budget hedge');
      }
    });

    test('400GBASE-ZR keeps the verbatim coherent-DWDM wording (honesty)', () {
      final OpticalVariant zr = bundled.tiers
          .expand((OpticalTier t) => t.entries)
          .firstWhere((OpticalVariant v) => v.designation == '400GBASE-ZR');
      expect(zr.vendor, isTrue);
      expect(zr.notes, contains('Coherent DWDM (OIF 400ZR)'));
      expect(zr.notes, contains('beyond base IEEE 802.3'));
    });
  });
}
