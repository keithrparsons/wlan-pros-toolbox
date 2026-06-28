// Ham Radio reference data-integrity tests.
//
// These lock the CORRECTED, spec-vetted values from
// Deliverables/2026-06-28-ham-radio-toolbox-research/build-spec.md so a future
// edit cannot silently reintroduce the regulatory decay points the spec fixed:
//   - General class = 1500 W PEP on 80/40/15/10 m (NOT 200 W).
//   - 30 m = 200 W; 60 m = 100 W ERP channels + 9.15 W ERP segment.
//   - 2200 m / 630 m are IN; 9 cm (3.3-3.5 GHz) is OUT.
//   - No baud column anywhere.
//   - The study page surfaces "35 questions, 26 to pass" with NO hard-coded
//     pool count.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/ham_reference_data.dart';

void main() {
  HamBand bandNamed(String name) =>
      kHamBandPlan.firstWhere((HamBand b) => b.band == name);

  group('US Amateur Band Plan power corrections (97.313)', () {
    test('80 / 40 / 15 / 10 m General run 1500 W PEP, not 200 W', () {
      for (final String name in <String>['80 m', '40 m', '15 m', '10 m']) {
        final HamBand b = bandNamed(name);
        expect(b.power, '1500 W PEP (Technician: 200 W)',
            reason: '$name must be 1500 W PEP for General (Technician 200 W)');
      }
    });

    test('20 / 17 / 12 m and 160 m General run the full 1500 W PEP', () {
      for (final String name in <String>['160 m', '20 m', '17 m', '12 m']) {
        expect(bandNamed(name).power, '1500 W PEP', reason: name);
      }
    });

    test('30 m is capped at 200 W PEP', () {
      expect(bandNamed('30 m').power, '200 W PEP (band cap)');
    });

    test('60 m is 100 W ERP channels + 9.15 W ERP segment', () {
      expect(bandNamed('60 m').power, 'Channels 100 W ERP; segment 9.15 W ERP');
    });

    test('2200 m = 1 W EIRP and 630 m = 5 W EIRP (both IN)', () {
      expect(bandNamed('2200 m').power, contains('1 W EIRP'));
      expect(bandNamed('630 m').power, contains('5 W EIRP'));
    });

    test('every band carries a non-empty power and frequency range', () {
      for (final HamBand b in kHamBandPlan) {
        expect(b.power, isNotEmpty, reason: '${b.band} power');
        expect(b.freqRange, isNotEmpty, reason: '${b.band} freq');
      }
    });
  });

  group('US Amateur Band Plan privileges', () {
    test('20 m General has the correct CW/data and phone sub-bands', () {
      final HamBand b = bandNamed('20 m');
      expect(b.tech, isNull, reason: 'Technicians have no 20 m privileges');
      expect(b.general, contains('14.025-14.150'));
      expect(b.general, contains('14.225-14.350'));
    });

    test('30 m is CW and data only (no phone, no image)', () {
      final HamBand b = bandNamed('30 m');
      expect(b.general, contains('ONLY'));
      expect(b.general!.toLowerCase(), contains('no phone'));
    });

    test('10 m gives Technicians a real (CW + SSB) segment', () {
      expect(bandNamed('10 m').tech, contains('28.300-28.500'));
    });
  });

  group('Band membership: 2200/630 in, 9 cm out, no baud', () {
    test('2200 m and 630 m are present', () {
      final Set<String> names =
          kHamBandPlan.map((HamBand b) => b.band).toSet();
      expect(names, containsAll(<String>['2200 m', '630 m']));
    });

    test('9 cm is omitted from the band plan (sunset)', () {
      expect(kHamBandPlan.any((HamBand b) => b.band == '9 cm'), isFalse);
    });

    test('the 9 cm sunset note is conservative (no residual-usability claim)',
        () {
      expect(kHam9cmSunsetNote, contains('omitted'));
      expect(kHam9cmSunsetNote, contains('does not overlap'));
    });

    test('the SHF bands cover 5 cm (Wi-Fi 5 GHz overlap) at 1500 W PEP', () {
      final HamBand b = bandNamed('5 cm');
      expect(b.region, HamRegion.shf);
      expect(b.power, '1500 W PEP');
      expect(b.modes, contains('5 GHz'));
    });
  });

  group('60 m channel detail', () {
    test('is 4 channels plus the segment, in order', () {
      expect(kHam60mChannels, hasLength(5));
      expect(kHam60mChannels.first.label, 'Channel 1');
      expect(kHam60mChannels.last.label, 'Segment');
    });

    test('channel 1 uses center 5332.0 / dial 5330.5 at 100 W ERP', () {
      final Ham60mChannel c1 = kHam60mChannels.first;
      expect(c1.center, '5332.0 kHz');
      expect(c1.dial, '5330.5 kHz');
      expect(c1.power, '100 W ERP');
    });

    test('the new segment is 5351.5-5366.5 kHz at 9.15 W ERP', () {
      final Ham60mChannel seg = kHam60mChannels.last;
      expect(seg.center, contains('5351.5-5366.5 kHz'));
      expect(seg.power, contains('9.15 W ERP'));
    });
  });

  group('Band names <-> wavelength bridge', () {
    BandBridgeRow rowNamed(String name) =>
        kBandBridge.firstWhere((BandBridgeRow r) => r.bandName == name);

    test('maps the headline bands to their ranges', () {
      expect(rowNamed('20 m').freqRange, '14.000-14.350 MHz');
      expect(rowNamed('2 m').freqRange, '144-148 MHz');
      expect(rowNamed('70 cm').freqRange, '420-450 MHz');
    });

    test('13 cm is the 2.4 GHz neighbor; 5 cm the 5 GHz neighbor', () {
      expect(rowNamed('13 cm').freqRange, contains('2390-2450'));
      expect(rowNamed('5 cm').freqRange, contains('5650-5925'));
    });

    test('9 cm is shown but flagged as sunset / out', () {
      final BandBridgeRow r = rowNamed('9 cm');
      expect(r.sunset, isTrue);
      expect(r.freqRange.toLowerCase(), contains('sunset'));
    });
  });

  group('ITU band designations', () {
    ItuBandDesignation des(String d) =>
        kItuBands.firstWhere((ItuBandDesignation b) => b.designation == d);

    test('covers HF / VHF / UHF / SHF with the correct decade boundaries', () {
      expect(kItuBands.map((ItuBandDesignation b) => b.designation),
          <String>['HF', 'VHF', 'UHF', 'SHF']);
      expect(des('HF').frequency, '3-30 MHz');
      expect(des('VHF').frequency, '30-300 MHz');
      expect(des('UHF').frequency, '300 MHz-3 GHz');
      expect(des('SHF').frequency, '3-30 GHz');
    });
  });

  group('Spectrum neighbors', () {
    test('include the VHF aviation airband and military UHF airband', () {
      final SpectrumNeighbor air = kSpectrumNeighbors
          .firstWhere((SpectrumNeighbor n) => n.service.contains('aviation'));
      expect(air.allocation, contains('108-137 MHz'));
      final SpectrumNeighbor mil = kSpectrumNeighbors
          .firstWhere((SpectrumNeighbor n) => n.service.contains('Military'));
      expect(mil.allocation, contains('225-400 MHz'));
    });
  });

  group('Part 15 vs Part 97', () {
    RuleDelta delta(String dim) =>
        kRuleDeltas.firstWhere((RuleDelta d) => d.dimension == dim);

    test('the overlaps cover 2.4 and 5 GHz but never 9 cm', () {
      expect(
        kWifiHamOverlaps.any((WifiHamOverlap o) => o.hamBand.contains('13 cm')),
        isTrue,
      );
      expect(
        kWifiHamOverlaps.any((WifiHamOverlap o) => o.hamBand.contains('5 cm')),
        isTrue,
      );
      expect(
        kWifiHamOverlaps.any((WifiHamOverlap o) => o.hamBand.contains('9 cm')),
        isFalse,
      );
    });

    test('encryption: allowed under Part 15, prohibited under Part 97', () {
      final RuleDelta enc = delta('Encryption');
      expect(enc.part15.toLowerCase(), contains('allowed'));
      expect(enc.part97.toLowerCase(), contains('prohibited'));
    });

    test('Part 97 requires station ID by callsign every 10 minutes', () {
      final RuleDelta id = delta('Station ID');
      expect(id.part15, 'None');
      expect(id.part97, contains('10 minutes'));
    });

    test('the AREDN note names the project and the no-encryption trade', () {
      expect(kAredNote, contains('AREDN'));
      expect(kAredNote.toLowerCase(), contains('no encryption'));
    });
  });

  group('Study resources + exam structure', () {
    HamStudyResource res(String t) =>
        kHamStudyResources.firstWhere((HamStudyResource r) => r.title == t);

    test('features hamstudy.org, ARRL, FCC Part 97, and AREDN', () {
      expect(res('hamstudy.org').url, 'https://hamstudy.org');
      expect(kHamStudyResources.any((HamStudyResource r) =>
          r.title.contains('ARRL')), isTrue);
      expect(kHamStudyResources.any((HamStudyResource r) =>
          r.title.contains('Part 97')), isTrue);
      expect(kHamStudyResources.any((HamStudyResource r) =>
          r.title.contains('AREDN')), isTrue);
    });

    test('every resource with a link uses HTTPS (GL-008 browser hand-off)', () {
      for (final HamStudyResource r in kHamStudyResources) {
        if (r.url != null) {
          expect(r.url, startsWith('https://'), reason: r.title);
        }
      }
    });

    test('exam structure: Technician 35/26, General 35/26, Extra 50/37', () {
      final HamExamFact tech = kHamExamStructure
          .firstWhere((HamExamFact f) => f.element.startsWith('Technician'));
      expect(tech.questions, '35 questions');
      expect(tech.toPass, '26 correct to pass');
      final HamExamFact extra = kHamExamStructure
          .firstWhere((HamExamFact f) => f.element.startsWith('Amateur Extra'));
      expect(extra.questions, '50 questions');
      expect(extra.toPass, '37 correct to pass');
    });

    test('the pool caveat gives the stable structure but no hard pool count',
        () {
      expect(kHamPoolCaveat, contains('35 questions'));
      expect(kHamPoolCaveat, contains('26 to pass'));
      expect(kHamPoolCaveat.toLowerCase(), contains('rotate'));
      // The 2026-2030 pool size (409) must never be hard-coded into the copy.
      expect(kHamPoolCaveat, isNot(contains('409')));
    });

    test('the 60 m caveat names the 13 Feb 2026 change', () {
      expect(kHam60mCaveat, contains('13 Feb 2026'));
    });
  });
}
