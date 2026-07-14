// Cross-surface guard for RSSI signal grading (audit findings F1/F2).
//
// THE MISSING TEST that let 1.7.1 ship. THREE surfaces state the RSSI scale,
// and all three must agree. The first two are Dart. The third is a DRAWING,
// and it is the one that was still wrong on 2026-07-13 after the other two
// were fixed, because grep cannot read a picture (GL-013, gate-until-clean
// class 1: "non-text leaks... you must open and look").
//   1. The VERDICT / Live engine — WifiGrading.gradeRssi (numeric, on
//      WifiGradingBands.kRssiBands minDbm bounds). This is what fires R-10/R-11/
//      R-12 and drives the Live grade word.
//   2. The Signal Thresholds REFERENCE SCREEN — the ranges it PRINTS in
//      SignalThresholdsScreen.kSignalBands, which the user reads off the table.
//
// In 1.7.1 these two disagreed (engine graded -73/-74 dBm "Poor / no plan will
// help", the reference table called the same reading "Fair / usable") because
// they were hand-maintained copies and NOTHING compared them. This test walks
// every dBm from -30 to -100 and FAILS THE BUILD the moment the graded grade
// and the printed grade disagree on a single reading.
//
// The reference-screen side is derived ONLY from the printed range STRINGS —
// deliberately independent of the numeric constants — so this genuinely
// compares the two user-facing representations, not a constant against itself
// ([[feedback_tests_that_cannot_fail]]). Expected grades in the boundary group
// are hand-typed from Keith's confirmed bands, never read back from the code.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart' show QualityGrade;
import 'package:wlan_pros_toolbox/screens/tools/reference/signal_thresholds_screen.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_grading.dart';

/// Maps a reference-table quality word to the grade it stands for.
QualityGrade _labelToGrade(String label) {
  switch (label) {
    case 'Excellent':
      return QualityGrade.excellent;
    case 'Good':
      return QualityGrade.good;
    case 'Fair':
      return QualityGrade.fair;
    case 'Poor':
      return QualityGrade.poor;
    default:
      fail('Unknown reference band label "$label".');
  }
}

/// True if [dbm] falls inside a reference-table range STRING, read the way a
/// user reads it. Parses the printed text ("> -60 dBm", "-60 to -67", "-73 or
/// weaker") into a predicate. Independent of WifiGradingBands numeric bounds on
/// purpose — this is the "what the screen shows" surface.
bool _rangeContains(String range, int dbm) {
  final List<int> nums = RegExp(r'-?\d+')
      .allMatches(range)
      .map((RegExpMatch m) => int.parse(m.group(0)!))
      .toList();
  expect(nums, isNotEmpty, reason: 'Unparseable reference range "$range".');
  if (range.contains('>')) return dbm > nums.first; // "> -60 dBm"
  if (range.contains('weaker')) return dbm <= nums.first; // "-73 or weaker"
  if (range.contains('<')) return dbm < nums.first; // "< -80 dBm" legacy form
  // "A to B", less-negative first, e.g. "-60 to -67": inclusive both ends.
  final int hi = nums.reduce((int a, int b) => a > b ? a : b);
  final int lo = nums.reduce((int a, int b) => a < b ? a : b);
  return dbm <= hi && dbm >= lo;
}

/// The grade a user would take off the REFERENCE SCREEN for [dbm]: the first
/// band (strongest-first, the way you read a table top to bottom) whose printed
/// range contains the reading.
QualityGrade _referenceScreenGrade(int dbm) {
  for (final SignalBand band in SignalThresholdsScreen.kSignalBands) {
    if (_rangeContains(band.range, dbm)) return _labelToGrade(band.label);
  }
  fail('No reference band covers $dbm dBm — the printed scale has a gap.');
}

void main() {
  group('RSSI grading — engine vs reference screen agree (F2 guard)', () {
    test(
        'the verdict engine and the reference screen assign the SAME grade at '
        'every dBm from -30 to -100', () {
      // This is the guard that would have caught 1.7.1. If either surface
      // drifts (a constant edited without the display, or vice versa), some
      // reading flips and this fails, naming the exact dBm.
      final List<String> disagreements = <String>[];
      for (int dbm = -30; dbm >= -100; dbm--) {
        final QualityGrade engine = WifiGrading.gradeRssi(dbm);
        final QualityGrade screen = _referenceScreenGrade(dbm);
        if (engine != screen) {
          disagreements.add('$dbm dBm: engine=${engine.name} '
              'screen=${screen.name}');
        }
      }
      expect(
        disagreements,
        isEmpty,
        reason: 'The verdict engine and the Signal Thresholds screen disagree '
            'on these readings — the exact class of drift that shipped in '
            '1.7.1:\n${disagreements.join('\n')}',
      );
    });

    test('the -73/-74 dBm regression: both surfaces now say Poor', () {
      // The 1.7.1 headline bug: the engine fired R-10 "Poor / no plan will
      // help" while the reference table called -73/-74 "Fair / usable". Pin it
      // shut on both surfaces.
      for (final int dbm in <int>[-73, -74]) {
        expect(WifiGrading.gradeRssi(dbm), QualityGrade.poor, reason: '$dbm');
        expect(_referenceScreenGrade(dbm), QualityGrade.poor, reason: '$dbm');
      }
    });

    test('four bands, no orphaned "Weak", labels strongest-first', () {
      expect(
        SignalThresholdsScreen.kSignalBands.map((SignalBand b) => b.label),
        <String>['Excellent', 'Good', 'Fair', 'Poor'],
      );
    });

    test('reference colour tier matches the graded quality', () {
      // Excellent/Good -> success, Fair -> warning, Poor -> danger. Guards the
      // QualityGrade -> SignalGrade presentation map.
      for (final SignalBand b in SignalThresholdsScreen.kSignalBands) {
        final QualityGrade q = _labelToGrade(b.label);
        final SignalGrade expected =
            (q == QualityGrade.excellent || q == QualityGrade.good)
                ? SignalGrade.good
                : q == QualityGrade.fair
                    ? SignalGrade.marginal
                    : SignalGrade.bad;
        expect(b.grade, expected, reason: b.label);
      }
    });
  });

  group('RSSI boundary grades — hand-derived from Keith\'s confirmed bands', () {
    // Expected values typed from Keith's bands (Excellent > -60, Good -60..-67,
    // Fair -67..-72, Poor -73 or weaker), NOT read back from WifiGradingBands.
    test('Excellent: rssi > -60 (so -59 in, -60 out)', () {
      expect(WifiGrading.gradeRssi(-30), QualityGrade.excellent);
      expect(WifiGrading.gradeRssi(-59), QualityGrade.excellent);
      expect(WifiGrading.gradeRssi(-60), isNot(QualityGrade.excellent));
    });
    test('Good: -60 down to -67 inclusive', () {
      expect(WifiGrading.gradeRssi(-60), QualityGrade.good);
      expect(WifiGrading.gradeRssi(-67), QualityGrade.good);
    });
    test('Fair: -68 down to -72 (-67 is Good, -73 is Poor)', () {
      expect(WifiGrading.gradeRssi(-68), QualityGrade.fair);
      expect(WifiGrading.gradeRssi(-72), QualityGrade.fair);
    });
    test('Poor: -73 and weaker', () {
      expect(WifiGrading.gradeRssi(-73), QualityGrade.poor);
      expect(WifiGrading.gradeRssi(-90), QualityGrade.poor);
    });
  });

  // ══ THE THIRD SURFACE: the concept graphic ═════════════════════════════
  //
  // The two groups above compare two DART surfaces. There is a third, and it
  // is a DRAWING: assets/tool-graphics/signal-thresholds.svg, mounted
  // UNCONDITIONALLY as the FIRST child of the screen's scroll column
  // (signal_thresholds_screen.dart:329), i.e. ABOVE the table those groups
  // guard. Nothing checked it, and grep is blind to a picture.
  //
  // So the 9402df8 fix left the graphic still drawing the deleted 1.7.1 scale:
  // five bands, an orphaned "Weak" band, Fair reaching -75. At -73 dBm the
  // GRAPHIC said "Fair" while the TABLE two inches below it said "Poor". The
  // exact bug the fix was for, on the exact screen, at the exact number, and
  // the suite was green.
  //
  // These tests parse the SVG and make it a CHECKED surface. They read the
  // drawing the way a user reads it: the boxes, their labels, the legend range
  // strings, and where the boxes physically sit on the drawn dBm axis. Every
  // number in the graphic must trace back to WifiGradingBands.kRssiBands or to
  // SignalThresholdsScreen.kAppThresholds. A hand-drawn band can never again
  // disagree with the canonical table without failing the build.
  group('THIRD SURFACE: the concept graphic (SVG) agrees with kRssiBands', () {
    late _SignalSvg svg;

    setUpAll(() => svg = _SignalSvg.load());

    test('exactly four bands, weakest-to-strongest, no orphaned "Weak"', () {
      expect(
        svg.bandsLeftToRight.map((_SvgBand b) => b.label),
        WifiGradingBands.kRssiBands
            .map((RssiBand b) => b.label)
            .toList()
            .reversed,
        reason: 'The drawn boxes, left to right, must be kRssiBands reversed '
            '(weakest signal on the left). Found: '
            '${svg.bandsLeftToRight.map((_SvgBand b) => b.label).toList()}',
      );
      // The word "Weak", not the substring: "-73 or weaker" is the canonical
      // Poor range and must survive. \bweak\b does not match "weaker".
      expect(
        RegExp(r'\bweak\b').hasMatch(svg.rawText.toLowerCase()),
        isFalse,
        reason: 'The graphic still draws a "Weak" band. kRssiBands has four '
            'bands and no Weak. This is the 1.7.1 scale.',
      );
    });

    test('each band prints kRssiBands displayRange VERBATIM', () {
      for (final RssiBand canonical in WifiGradingBands.kRssiBands) {
        final _SvgBand drawn = svg.byLabel(canonical.label);
        expect(
          drawn.range,
          canonical.displayRange,
          reason: 'The graphic prints "${drawn.range}" for '
              '${canonical.label}; kRssiBands says '
              '"${canonical.displayRange}".',
        );
      }
    });

    test(
        'the GRAPHIC and the ENGINE assign the same grade at every dBm from '
        '-30 to -100', () {
      // The guard that would have caught tonight. Read the graphic's own
      // printed ranges through the SAME parser the reference-screen surface
      // uses above, strongest-first, exactly as a user reads a table.
      final List<String> disagreements = <String>[];
      for (int dbm = -30; dbm >= -100; dbm--) {
        final QualityGrade engine = WifiGrading.gradeRssi(dbm);
        final QualityGrade graphic = svg.gradeAt(dbm);
        if (engine != graphic) {
          disagreements.add('$dbm dBm: engine=${engine.name} '
              'graphic=${graphic.name}');
        }
      }
      expect(
        disagreements,
        isEmpty,
        reason: 'The concept graphic disagrees with the grading engine on '
            'these readings. This is what shipped on 2026-07-13 (the graphic '
            'said Fair at -73, the table said Poor):\n'
            '${disagreements.join('\n')}',
      );
    });

    test('the -73 dBm regression, on the drawing itself', () {
      // The headline number. It must read Poor off the picture, not just off
      // the table underneath it.
      for (final int dbm in <int>[-73, -74]) {
        expect(svg.gradeAt(dbm), QualityGrade.poor, reason: '$dbm dBm');
      }
      // And -72 must still be Fair, so we did not simply shift everything.
      expect(svg.gradeAt(-72), QualityGrade.fair);
    });

    test('the boxes physically SIT where kRssiBands says they do', () {
      // Semantics are not enough: a graphic can print the right words over a
      // wrong picture. Invert each box's pixel edges through the drawn axis
      // (its endpoints are read from the axis line and its own labels) and
      // compare against the true band boundaries, which sit on the half-integer
      // between the weakest reading of one band and the strongest of the next.
      final List<double> expected = _expectedBoundariesDbm();
      final List<double> drawn = svg.internalBoundariesDbm();
      expect(drawn.length, expected.length);
      for (int i = 0; i < expected.length; i++) {
        expect(
          drawn[i],
          closeTo(expected[i], 0.1),
          reason: 'Band boundary ${i + 1} is drawn at '
              '${drawn[i].toStringAsFixed(2)} dBm; kRssiBands puts it at '
              '${expected[i].toStringAsFixed(1)} dBm. The picture is lying '
              'even if the labels are right.',
        );
      }
    });

    test('the bands are CONTIGUOUS: no gap, no overlap (Vera LOW-1)', () {
      // The boundary test below checks each band's RIGHT EDGE against kRssiBands,
      // which says nothing about whether the NEXT band starts there. Vera opened
      // a 10px hole between Poor and Fair, left every label untouched, and the
      // suite stayed green: a drawn scale with a gap in it, where some readings
      // fall into no band at all. Checking edges one at a time is not the same as
      // checking that they MEET.
      final List<_SvgBand> bands = svg.bandsLeftToRight;
      for (int i = 0; i < bands.length - 1; i++) {
        expect(
          bands[i + 1].x0,
          closeTo(bands[i].x1, 0.5),
          reason: 'Band "${bands[i].label}" ends at x=${bands[i].x1} but '
              '"${bands[i + 1].label}" starts at x=${bands[i + 1].x0}. The '
              'drawn scale has a ${bands[i + 1].x0 > bands[i].x1 ? "GAP" : "OVERLAP"} '
              'in it. Every dBm must fall in exactly one band.',
        );
      }
      // And the scale must span the whole drawn axis, edge to edge.
      expect(bands.first.x0, closeTo(svg.axisX1, 0.5),
          reason: 'The weakest band does not start at the axis origin.');
      expect(bands.last.x1, closeTo(svg.axisX2, 0.5),
          reason: 'The strongest band does not reach the axis end.');
    });

    test('NO ORPHAN NUMBERS: every number drawn traces to a Dart constant', () {
      // The catch-all. A stale "-80" or "-55" left behind anywhere in the
      // drawing fails here even if the bands themselves were fixed. The only
      // numbers allowed are those in kRssiBands' printed ranges, the VoIP
      // threshold from kAppThresholds, and the two axis endpoints (which are a
      // property of the drawn scale, not a claim about the bands).
      final Set<int> allowed = <int>{
        for (final RssiBand b in WifiGradingBands.kRssiBands)
          ..._intsIn(b.displayRange).map((int n) => n.abs()),
        _voipMinRssiDbm().abs(),
        ...svg.axisEndpointsDbm.map((double d) => d.abs().round()),
      };
      final Set<int> drawn = <int>{
        for (final String t in svg.textContents)
          ..._intsIn(t).map((int n) => n.abs()),
      };
      expect(
        drawn.difference(allowed),
        isEmpty,
        reason: 'The graphic draws numbers that appear in NO canonical '
            'constant. Allowed: $allowed. Drawn: $drawn. An orphan number in a '
            'drawing is a fact nobody owns.',
      );
    });

    test('the VoIP marker matches kAppThresholds, not a hand-picked number', () {
      // The SECOND contradiction on this screen, found 2026-07-13: the graphic
      // drew "VoIP >= -65" while kAppThresholds on the same screen says -67.
      final int canonical = _voipMinRssiDbm();
      expect(
        svg.voipLabelDbm,
        canonical,
        reason: 'The graphic labels the VoIP minimum ${svg.voipLabelDbm} dBm; '
            'kAppThresholds says $canonical dBm.',
      );
      expect(
        svg.voipMarkerDbm,
        closeTo(canonical.toDouble(), 0.1),
        reason: 'The VoIP marker LINE is drawn at ${svg.voipMarkerDbm} dBm but '
            'is labelled $canonical dBm.',
      );
    });

    test('band colours carry the §8.13 status tier of their grade', () {
      for (final RssiBand canonical in WifiGradingBands.kRssiBands) {
        expect(
          svg.byLabel(canonical.label).stroke.toUpperCase(),
          _statusHexFor(canonical.grade),
          reason: '${canonical.label} is drawn in the wrong status colour.',
        );
      }
    });

    test('ASCII only (the glyph-tofu rule holds)', () {
      expect(svg.raw.contains('&#'), isFalse,
          reason: 'Numeric character entity in the SVG; it will render as tofu '
              'on a platform missing the glyph. Use a vector path.');
      expect(svg.raw.codeUnits.every((int c) => c < 128), isTrue,
          reason: 'Non-ASCII code unit in the SVG.');
    });
  });
}

// ══ SVG parsing: read the drawing the way a user reads it ═════════════════

/// `assets/tool-graphics/signal-thresholds.svg`, relative to the package root
/// (which is `flutter test`'s working directory).
const String _kSignalSvgPath = 'assets/tool-graphics/signal-thresholds.svg';

// GL-003 §8.13 status hues, as baked into the dark SVGs.
const String _kStatusDanger = '#F26E6E';
const String _kStatusWarning = '#E0A23A';
const String _kStatusSuccess = '#5BD68A';
const String _kLime = '#A1CC3A';

String _statusHexFor(QualityGrade g) {
  switch (g) {
    case QualityGrade.excellent:
    case QualityGrade.good:
      return _kStatusSuccess;
    case QualityGrade.fair:
      return _kStatusWarning;
    case QualityGrade.poor:
      return _kStatusDanger;
    default:
      fail('No status hue for $g.');
  }
}

/// Every signed integer in [s], in order.
List<int> _intsIn(String s) => RegExp(r'-?\d+')
    .allMatches(s)
    .map((RegExpMatch m) => int.parse(m.group(0)!))
    .toList();

/// The VoIP minimum RSSI the SCREEN's own application table prints, as an int.
int _voipMinRssiDbm() {
  final AppThreshold voip = SignalThresholdsScreen.kAppThresholds
      .firstWhere((AppThreshold r) => r.application.startsWith('VoIP'));
  return _intsIn(voip.minRssi).first;
}

/// The true internal band boundaries in dBm, derived from [kRssiBands] alone.
///
/// The bands are integer-quantized, so the boundary between band i (stronger)
/// and band i+1 (weaker) sits on the half-integer below band i's inclusive
/// floor: Excellent's floor is -59, so Excellent/Good divides at -59.5. Ordered
/// weakest-first to match a left-to-right drawing.
List<double> _expectedBoundariesDbm() {
  final List<RssiBand> bands = WifiGradingBands.kRssiBands;
  return <double>[
    for (int i = bands.length - 2; i >= 0; i--) bands[i].minDbm - 0.5,
  ];
}

/// One band as the DRAWING presents it: a box, the word inside it, and the
/// range string the legend prints beside that word.
class _SvgBand {
  const _SvgBand({
    required this.label,
    required this.range,
    required this.stroke,
    required this.x0,
    required this.x1,
  });

  final String label;
  final String range;
  final String stroke;
  final double x0;
  final double x1;
}

/// A parsed `<rect>`, `<line>` or `<text>`.
class _El {
  const _El(this.attrs, this.text);
  final Map<String, String> attrs;
  final String text;

  String? s(String k) => attrs[k];
  double d(String k) => double.parse(attrs[k]!);
  double? dOrNull(String k) {
    final String? v = attrs[k];
    return v == null ? null : double.tryParse(v);
  }
}

/// The signal-thresholds concept graphic, parsed into the surfaces a reader
/// actually sees. Comments are stripped first, so nothing in this file can be
/// satisfied by a claim made only in a comment.
class _SignalSvg {
  _SignalSvg._(this.raw, this._rects, this._lines, this._texts);

  final String raw;
  final List<_El> _rects;
  final List<_El> _lines;
  final List<_El> _texts;

  static _SignalSvg load() {
    final File f = File(_kSignalSvgPath);
    if (!f.existsSync()) {
      fail('Concept graphic not found at $_kSignalSvgPath (cwd '
          '${Directory.current.path}).');
    }
    final String raw = f.readAsStringSync();
    final String body =
        raw.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    return _SignalSvg._(
      raw,
      _all(body, 'rect'),
      _all(body, 'line'),
      _all(body, 'text'),
    );
  }

  static List<_El> _all(String body, String tag) {
    final RegExp re = tag == 'text'
        ? RegExp('<text\\b([^>]*)>(.*?)</text>', dotAll: true)
        : RegExp('<$tag\\b([^>]*?)/?>');
    return re.allMatches(body).map((RegExpMatch m) {
      final Map<String, String> attrs = <String, String>{};
      for (final RegExpMatch a
          in RegExp(r'([\w:-]+)\s*=\s*"([^"]*)"').allMatches(m.group(1)!)) {
        attrs[a.group(1)!] = a.group(2)!;
      }
      final String text = m.groupCount >= 2 ? _unescape(m.group(2)!) : '';
      return _El(attrs, text.trim());
    }).toList();
  }

  static String _unescape(String s) => s
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&');

  /// All rendered text in the drawing (comments excluded).
  List<String> get textContents =>
      _texts.map((_El t) => t.text).where((String s) => s.isNotEmpty).toList();

  String get rawText => textContents.join(' ');

  /// The band boxes: the wide status-coloured rects. The legend swatches are
  /// the same hues but 9px, so width separates them.
  List<_El> get _boxes => _rects
      .where((_El r) =>
          r.d('width') > 20 &&
          <String>[_kStatusDanger, _kStatusWarning, _kStatusSuccess]
              .contains(r.s('stroke')?.toUpperCase()))
      .toList()
    ..sort((_El a, _El b) => a.d('x').compareTo(b.d('x')));

  /// The horizontal axis line (the only scaffold-coloured horizontal line).
  _El get _axis => _lines.singleWhere((_El l) =>
      l.s('stroke')?.toUpperCase() == '#E5E5E5' && l.d('y1') == l.d('y2'));

  /// The drawn axis's start and end x, so the band boxes can be proved to span
  /// the whole scale with no gap at either end (Vera LOW-1).
  double get axisX1 => _axis.d('x1');
  double get axisX2 => _axis.d('x2');

  /// The dBm the axis endpoints are LABELLED with, read off the drawing: the
  /// bare-integer texts sitting at the axis's x1 and x2.
  List<double> get axisEndpointsDbm {
    double at(double x) {
      final _El t = _texts.singleWhere(
        (_El e) =>
            e.dOrNull('x') != null &&
            (e.d('x') - x).abs() < 0.5 &&
            RegExp(r'^-?\d+$').hasMatch(e.text),
        orElse: () => fail('No axis endpoint label at x=$x in the graphic.'),
      );
      return double.parse(t.text);
    }

    return <double>[at(_axis.d('x1')), at(_axis.d('x2'))];
  }

  /// Invert a pixel x back to dBm using the axis the drawing itself declares.
  double dbmAt(double x) {
    final List<double> ends = axisEndpointsDbm;
    final double x1 = _axis.d('x1');
    final double x2 = _axis.d('x2');
    return ends[0] + (x - x1) * (ends[1] - ends[0]) / (x2 - x1);
  }

  /// The bands, left (weakest) to right (strongest), each carrying the legend
  /// range string printed beside its label.
  List<_SvgBand> get bandsLeftToRight => _boxes.map((_El box) {
        final double x0 = box.d('x');
        final double x1 = x0 + box.d('width');
        final double y0 = box.d('y');
        final double y1 = y0 + box.d('height');
        // The word drawn INSIDE the box.
        final _El inside = _texts.singleWhere(
          (_El t) =>
              t.dOrNull('x') != null &&
              t.d('x') >= x0 &&
              t.d('x') <= x1 &&
              t.d('y') >= y0 &&
              t.d('y') <= y1,
          orElse: () => fail('Band box at x=$x0 carries no label. A colour-only '
              'band violates GL-003 §8.13.'),
        );
        return _SvgBand(
          label: inside.text,
          range: _legendRangeFor(inside.text, exclude: inside),
          stroke: box.s('stroke')!,
          x0: x0,
          x1: x1,
        );
      }).toList();

  /// The legend line for [label]: the text on the same baseline, immediately to
  /// its right. This is the string a user reads as that band's range.
  String _legendRangeFor(String label, {required _El exclude}) {
    final _El entry = _texts.singleWhere(
      (_El t) => t.text == label && !identical(t, exclude),
      orElse: () =>
          fail('No legend entry for "$label"; the band prints no range.'),
    );
    final List<_El> right = _texts
        .where((_El t) =>
            t.dOrNull('y') != null &&
            (t.d('y') - entry.d('y')).abs() < 0.5 &&
            t.d('x') > entry.d('x'))
        .toList()
      ..sort((_El a, _El b) => a.d('x').compareTo(b.d('x')));
    if (right.isEmpty) fail('Legend entry "$label" has no range beside it.');
    return right.first.text;
  }

  _SvgBand byLabel(String label) => bandsLeftToRight
      .singleWhere((_SvgBand b) => b.label == label, orElse: () {
    fail('The graphic draws no "$label" band.');
  });

  /// The internal band boundaries as DRAWN, converted to dBm, weakest-first.
  List<double> internalBoundariesDbm() {
    final List<_SvgBand> bands = bandsLeftToRight;
    return <double>[
      for (int i = 0; i < bands.length - 1; i++) dbmAt(bands[i].x1),
    ];
  }

  /// The grade a user takes OFF THE PICTURE at [dbm]: the strongest band whose
  /// printed range contains the reading, read strongest-first exactly as the
  /// reference-screen surface is read above.
  QualityGrade gradeAt(int dbm) {
    for (final _SvgBand b in bandsLeftToRight.reversed) {
      if (_rangeContains(b.range, dbm)) return _labelToGrade(b.label);
    }
    fail('No band in the graphic covers $dbm dBm; the drawn scale has a gap.');
  }

  /// The number the VoIP marker is LABELLED with.
  int get voipLabelDbm {
    final _El t = _texts.singleWhere(
      (_El e) => e.text.contains('VoIP'),
      orElse: () => fail('The graphic draws no VoIP marker label.'),
    );
    return _intsIn(t.text).first;
  }

  /// The dBm the VoIP marker LINE is actually drawn at.
  double get voipMarkerDbm {
    final _El l = _lines.singleWhere(
      (_El e) =>
          e.s('stroke')?.toUpperCase() == _kLime && e.d('x1') == e.d('x2'),
      orElse: () => fail('The graphic draws no vertical lime VoIP marker.'),
    );
    return dbmAt(l.d('x1'));
  }
}
