// MSI and NSMA read/write tests for the Antenna Pattern tool (Wi-Fi Lab,
// antenna-pattern). Every fixture is generated here from a closed-form model
// or written by hand from the brief's stated conventions; no vendor file.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/antenna_pattern_formats.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/antenna_pattern_math.dart';

/// A hand-written two-cut file body: a 3 dB-per-10° V lobe peaking at
/// [peakAt] (in the file's own vertical angles) and a flat H cut.
List<String> _lines(
  int from,
  int to,
  String Function(int angle) value, {
  String sep = ' ',
}) => <String>[for (int a = from; a <= to; a++) '$a$sep${value(a)}'];

void main() {
  final PatternCuts downtilted = GainGrid.fromShape(
    const CollinearShape(elements: 6, spacingWl: 0.75, tiltDeg: 8),
  ).toCuts();
  final PatternCuts sector = GainGrid.fromShape(
    const SectorShape(
      hBeamwidthDeg: 40,
      vBeamwidthDeg: 25,
      frontToBackDb: 25,
      sideLobeDb: 20,
      tiltDeg: 6,
    ),
  ).toCuts();

  group('MSI', () {
    test('a generated file parses back to the same cuts', () {
      for (final PatternCuts c in <PatternCuts>[downtilted, sector]) {
        final ParsedPattern p = parsePatternText(writeMsi(c, name: 'Test'));
        expect(p.format, PatternFormat.msi);
        expect(p.gainDbi, closeTo(c.peakGainDbi, 0.005));
        for (int a = 0; a < 360; a++) {
          expect(
            p.cuts.horizontalLossDb[a],
            closeTo(c.horizontalLossDb[a], 0.006),
          );
          expect(p.cuts.verticalLossDb[a], closeTo(c.verticalLossDb[a], 0.006));
        }
        expect(p.warnings, isEmpty);
      }
    });

    test('GAIN with no unit is dBd; with dBi it is dBi', () {
      final String body = <String>[
        'HORIZONTAL 4',
        ..._lines(0, 3, (_) => '0'),
        'VERTICAL 4',
        ..._lines(0, 3, (_) => '0'),
      ].join('\n');
      final ParsedPattern dbd = parseMsi('NAME x\nGAIN 7.69\n$body');
      expect(dbd.gainDbi, closeTo(9.84, 1e-9));
      expect(dbd.gainAsWritten, contains('no unit, so dBd'));
      final ParsedPattern dbi = parseMsi('NAME x\nGAIN 7.69 dBi\n$body');
      expect(dbi.gainDbi, closeTo(7.69, 1e-9));
    });

    test('a hand-written file with its V peak at 4° reads as DOWNTILT '
        '(MSI 90 = down)', () {
      final String text = <String>[
        'NAME hand',
        'GAIN 5 dBi',
        'ELECTRICAL_TILT 4',
        'HORIZONTAL 360',
        ..._lines(0, 359, (_) => '0'),
        'VERTICAL 360',
        ..._lines(0, 359, (int a) {
          final int d = ((a - 4 + 540) % 360) - 180;
          return (d.abs() * 0.3).toStringAsFixed(2);
        }),
      ].join('\n');
      final ParsedPattern p = parseMsi(text);
      expect(p.cuts.verticalPeakAngle, 4);
      expect(p.tilt, contains('4'));
      // Rebuilt in 3D, the strongest direction is below the horizon.
      final GainGrid g = GainGrid.fromShape(
        ReconstructedShape(p.cuts, ReconstructionMethod.summing),
        peakDbi: p.gainDbi,
      );
      expect(g.peakTheta, 94);
    });

    test('tolerates a wrong count, minus signs, unknown keys, key order', () {
      final String text = <String>[
        'GAIN 2 dBi',
        'Vendor_Thing 42',
        'NAME out of order',
        'HORIZONTAL 360', // declares 360, supplies 4
        '0 0', '90 -3', '180 -20', '270 -3',
        'VERTICAL 4',
        '0 0', '90 20', '180 20', '270 20',
      ].join('\n');
      final ParsedPattern p = parseMsi(text);
      expect(p.name, 'out of order');
      expect(p.cuts.horizontalLossDb[90], closeTo(3, 1e-9));
      expect(p.cuts.horizontalLossDb[45], closeTo(1.5, 1e-9));
      expect(p.warnings.join(' '), contains('says 360 points and holds 4'));
      expect(p.warnings.join(' '), contains('minus sign'));
      expect(p.warnings.join(' '), contains('unrecognized key'));
    });

    test('missing sections are errors with a reason', () {
      expect(
        () => parseMsi('NAME x\nGAIN 0\nHORIZONTAL 4\n0 0\n90 0\n180 0\n270 0'),
        throwsA(
          isA<PatternParseException>().having(
            (PatternParseException e) => e.message,
            'message',
            contains('VERTICAL'),
          ),
        ),
      );
      expect(() => parsePatternText(''), throwsA(isA<PatternParseException>()));
    });
  });

  group('NSMA', () {
    test('a generated NSMA file parses to the same orientation as the MSI '
        'file of the same antenna (not upside down)', () {
      final ParsedPattern msi = parsePatternText(
        writeMsi(downtilted, name: 'Collinear'),
      );
      final ParsedPattern nsma = parsePatternText(
        writeNsma(downtilted, model: 'Collinear', electricalTiltDeg: 8),
      );
      expect(nsma.format, PatternFormat.nsma);
      expect(nsma.gainDbi, closeTo(msi.gainDbi, 0.005));
      expect(nsma.cuts.verticalPeakAngle, 8);
      expect(msi.cuts.verticalPeakAngle, 8);
      for (int a = 0; a < 360; a++) {
        expect(
          nsma.cuts.verticalLossDb[a],
          closeTo(msi.cuts.verticalLossDb[a], 0.011),
        );
        expect(
          nsma.cuts.horizontalLossDb[a],
          closeTo(msi.cuts.horizontalLossDb[a], 0.011),
        );
      }
    });

    test('a hand-written EL cut peaking at -4 (elevation up is positive) '
        'reads as 4° of DOWNTILT, as the brief says of Annex C', () {
      final String text = <String>[
        'REVNUM:,NSMA WG16.99.050',
        'ANTMAN:,Hand',
        'MODNUM:,Tilt4',
        'LOWFRQ:,806',
        'HGHFRQ:,896',
        'GUNITS:,DBD/DBR',
        'MDGAIN:,10',
        'ELTILT:,4',
        'PATCUT:,EL ! elevation cut',
        'POLARI:,V/V',
        'NUPOIN:,361',
        'FSTLST:,-180,180',
        ..._lines(-180, 179, (int e) {
          final int d = e + 4; // peak at e = -4
          return (-(d.abs() * 0.4)).toStringAsFixed(3);
        }, sep: ','),
        'PATCUT:,AZ',
        'POLARI:,V/V',
        'NUPOIN:,180', // the Annex C mistake: declares 180, supplies 179
        'FSTLST:,-180,178',
        ..._lines(-180, -2, (_) => '0.000', sep: ','),
        'ENDFIL:,EOF',
      ].join('\r\n');
      final ParsedPattern p = parsePatternText(text);
      expect(p.gainDbi, closeTo(12.15, 1e-9)); // DBD gain
      expect(p.cuts.verticalPeakAngle, 4);
      expect(p.cuts.verticalLossDb[4], closeTo(0, 1e-9));
      expect(p.warnings.join(' '), contains('NUPOIN 180 and holds 179'));
      expect(p.warnings.join(' '), contains('NUPOIN 361 and holds 360'));
    });

    test('DBI data are converted to loss below MDGAIN', () {
      final String text = <String>[
        'GUNITS:,DBI/DBI',
        'MDGAIN:,8',
        'PATCUT:,H',
        '-90,5',
        '0,8',
        '90,5',
        '180,-12',
        'PATCUT:,V',
        '-90,-12',
        '0,8',
        '90,-12',
        '180,-12',
      ].join('\n');
      final ParsedPattern p = parsePatternText(text);
      expect(p.cuts.horizontalLossDb[0], closeTo(0, 1e-9));
      expect(p.cuts.horizontalLossDb[90], closeTo(3, 1e-9));
      expect(p.cuts.horizontalLossDb[180], closeTo(20, 1e-9));
    });

    test('an NSMA file without an EL cut is an error with a reason', () {
      expect(
        () => parsePatternText('GUNITS:,DBI/DBR\nPATCUT:,AZ\n0,0\n90,0\n'),
        throwsA(isA<PatternParseException>()),
      );
    });
  });
}
