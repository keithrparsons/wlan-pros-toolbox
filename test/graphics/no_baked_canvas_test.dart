// Guards GL-003 §11.8: a concept graphic never bakes a full-canvas background.
//
// A bundled §8.6.2 concept graphic (and every face graphic rendered through the
// same asset class) ships TRANSPARENT. The background is the themed card the
// graphic sits on, not a shape inside the file. A rectangle that starts at the
// viewBox origin and spans the viewBox extent is that shape, and ANY fill on it
// is the defect whatever the hex.
//
// WHY THIS IS A TEST AND NOT A REVIEW. The §8.20.7 light treatment is a runtime
// hex swap keyed on an allow-list, and #1A1A1A is deliberately NOT on it because
// its light target equals its dark value. A baked #1A1A1A canvas therefore
// survives the swap unchanged while every mark drawn on it does not (scaffold
// #E5E5E5 becomes #4A4A4A), so the drawing renders dark on dark and disappears.
// In dark mode the same rectangle reads as a black box sitting on the lighter
// surface1 / surface2 card. This has bitten twice, the international plug faces
// and the screw-drive graphics, both 2026-06-08, and BOTH TIMES a render check
// on a black background passed over it. A review on black cannot see this class
// of defect; only geometry can.
//
// THE DISCRIMINATOR IS GEOMETRY, NOT THE HEX. #1A1A1A has legitimate uses inside
// these graphics and they stay: the §11.3-1 label knockout plate that carries a
// dimension label across a busy field (rack-1u-dimension.svg), and drawn shapes
// such as the cage-nut holes (rack-cage-nut.svg) and the coax anchor dot. Those
// are POSITIONED shapes and this test leaves them alone. Keying the rule on a
// hex is what made the previous sweep miss the next instance: a white or
// #222222 canvas defeats the themed card exactly as a black one does.
//
// AND THE ABSENCE OF x/y IS NOT THE DISCRIMINATOR EITHER. The working-memory
// note this rule grew from described the offender as a full-canvas rect with
// "no x/y". The live offender that reached the bundle carried an explicit
// `x="0" y="0"`, so a check keyed on the absence of those attributes PASSES the
// defective file. Absent and zero are treated identically below.
//
// SCOPE. The directories holding graphics WE author. Deliberately excluded:
//   * assets/branding/. The app-icon sources carry a full-canvas #1A1A1A and
//     SHOULD: an app icon is a fixed brand artifact rendered by the platform,
//     not a themed surface, and those files are absent from the pubspec asset
//     list so flutter_svg never renders them at runtime.
//   * the vendor-mark directories (regulator-logos, standards-body-logos,
//     speedtest-logos). Third-party marks bundled unchanged. A vendor tile
//     whose background IS the logo (the Bluetooth SIG rounded blue square)
//     spans its own viewBox by design and is not ours to re-author.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Directories holding SVGs this team authors and bundles. Walked recursively.
const List<String> _authoredGraphicDirs = <String>[
  'assets/tool-graphics',
  'assets/tool-icons',
  'assets/connector-diagrams',
  'assets/connector-sections',
  'assets/tool-diagrams',
];

final RegExp _viewBox = RegExp(
    r'viewBox="\s*([-\d.]+)[ ,]+([-\d.]+)[ ,]+([\d.]+)[ ,]+([\d.]+)');
final RegExp _rectTag = RegExp(r'<rect\b[^>]*>', dotAll: true);
final RegExp _fillAttr = RegExp(r'fill="([^"]+)"');

/// Reads a numeric presentation attribute off a tag.
///
/// The `(?:^|\s)` prefix is load-bearing, not decorative: a bare `x=` also
/// matches `rx=` and a bare `width=` also matches `stroke-width=`, which would
/// read a corner radius as an origin and a hairline as a canvas width.
double _attr(String tag, String name, double fallback) {
  final RegExpMatch? m =
      RegExp('(?:^|\\s)$name="([-\\d.]+)"').firstMatch(tag);
  return m == null ? fallback : (double.tryParse(m.group(1)!) ?? fallback);
}

List<File> _svgsUnder(String dir) {
  final Directory d = Directory(dir);
  if (!d.existsSync()) return <File>[];
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.svg'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
}

List<File> _allAuthoredSvgs() =>
    <File>[for (final String d in _authoredGraphicDirs) ..._svgsUnder(d)]
      ..sort((File a, File b) => a.path.compareTo(b.path));

/// A filled rectangle spanning the file's own viewBox, or null when the file
/// carries none. The 0.99 extent and the 1% origin tolerance are TEST
/// tolerances, not brand values, on the same footing as the 0.95 in §11.2: a
/// canvas rectangle is routinely placed a rounding unit oversize.
String? _bakedCanvasIn(File f) {
  final String s = f.readAsStringSync();
  final RegExpMatch? vb = _viewBox.firstMatch(s);
  if (vb == null) return null; // reported separately by the coverage test
  final double x0 = double.parse(vb.group(1)!);
  final double y0 = double.parse(vb.group(2)!);
  final double w0 = double.parse(vb.group(3)!);
  final double h0 = double.parse(vb.group(4)!);

  for (final Match m in _rectTag.allMatches(s)) {
    final String tag = m.group(0)!;
    final RegExpMatch? fill = _fillAttr.firstMatch(tag);
    if (fill == null || fill.group(1)!.trim().toLowerCase() == 'none') continue;
    final double x = _attr(tag, 'x', x0);
    final double y = _attr(tag, 'y', y0);
    final double w = _attr(tag, 'width', 0);
    final double h = _attr(tag, 'height', 0);
    final bool atOrigin =
        (x - x0).abs() <= 0.01 * w0 && (y - y0).abs() <= 0.01 * h0;
    final bool spans = w >= 0.99 * w0 && h >= 0.99 * h0;
    if (atOrigin && spans) {
      return '${f.path}: full-canvas rect fill=${fill.group(1)} '
          '(${w}x$h on ${w0}x$h0)';
    }
  }
  return null;
}

void main() {
  group('GL-003 §11.8: no baked full-canvas background', () {
    test('no authored graphic carries a rectangle spanning its own viewBox',
        () {
      final List<String> offenders = <String>[
        for (final File f in _allAuthoredSvgs())
          if (_bakedCanvasIn(f) case final String hit) hit,
      ];
      expect(offenders, isEmpty,
          reason: 'A graphic that paints its own canvas defeats the themed '
              'card: the #1A1A1A fill survives the §8.20.7 light swap while '
              'the marks drawn on it do not, so the drawing goes invisible in '
              'light mode, and the rectangle reads as a black box on the '
              'lighter card in dark mode. Strip the rect; the background is '
              'the card.\n${offenders.join('\n')}');
    });

    // An absent run is not a pass (§11.3-2's discipline, applied here). The
    // geometry check needs a viewBox to compare against, so a file without one
    // is NOT ANALYZED rather than clean. Every authored graphic must therefore
    // carry a viewBox, which also keeps ConceptGraphicBand.parseAspectRatio off
    // its width/height fallback.
    test('every authored graphic declares a viewBox, so none escapes the check',
        () {
      final List<String> unanalyzable = <String>[
        for (final File f in _allAuthoredSvgs())
          if (_viewBox.firstMatch(f.readAsStringSync()) == null)
            '${f.path}: no viewBox, so the §11.8 geometry check cannot run',
      ];
      expect(unanalyzable, isEmpty,
          reason: 'These files are unchecked, not clean:\n'
              '${unanalyzable.join('\n')}');
    });

    // Guards the scope of the check itself. If the walk silently stops finding
    // files (a renamed directory, a bad path constant), both tests above pass
    // vacuously and the gate reports green over an unswept tree.
    test('the sweep actually walks a non-trivial number of files', () {
      expect(_allAuthoredSvgs().length, greaterThan(250),
          reason: 'The §11.8 sweep found too few SVGs to be walking the real '
              'asset tree. A test that inspects nothing cannot fail.');
    });
  });
}
