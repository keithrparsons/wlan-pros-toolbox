// THE GUARD FOR EVERY HAND-DRAWN GRAPHIC (2026-07-14).
//
// 122 SVGs shipped in assets/tool-graphics/. NONE was covered by any data test.
// Vera's line: "If one of them disagreed with its screen's table, nothing in
// this system would know." She was right, and it had already happened:
// signal-thresholds.svg drew the deleted 1.7.1 RSSI scale and called -73 dBm
// "Fair" while the table two inches below it said "Poor".
//
// THREE verification layers were blind to it, which is why this file exists:
//   * grep cannot read <rect> coordinates;
//   * the cross-check test compared two DART surfaces and never opened the asset;
//   * the GOLDENS are blind too -- signal-thresholds.svg was redrawn completely
//     and regenerated ZERO goldens, because flutter_svg does not paint in those
//     widget tests. A pixel test could not have caught a lying drawing either.
//
// WHAT THIS FILE ENFORCES
//
//   1. REACHABILITY. Every SVG must be reachable from Dart. pubspec.yaml:533
//      globs the whole directory, so an orphaned asset still ships in every
//      binary and publishes under AGPL. Three were found (wifi-channels,
//      rf-connectors, ethernet-pinout) and one of them carried a FALSE claim
//      about 6 GHz PSC channels. Dead assets are now a build failure.
//
//   2. CLASSIFICATION COMPLETENESS. Every SVG is either DATA-BEARING (its
//      numbers must trace to Dart) or ILLUSTRATIVE (it makes no data claim).
//      A new graphic belongs to neither until someone says so, and the build
//      fails until they do. A generator may not mint its own exemption
//      (GL-003 §0): the illustrative list below is a DOCUMENTED LIST, reviewed,
//      not a judgment call made at draw time.
//
//   3. LABEL->VALUE AGREEMENT, semantically, wherever a Dart dataset exists.
//      Not "is this number somewhere in the file" -- that is the weak check that
//      would have PASSED the concrete = -12 dB bug, because 12 IS in that file
//      (it is brick at 5 GHz). The guard instead reads the LABEL off the drawing,
//      looks THAT row up in the dataset, and compares THAT row's value. The
//      datasets carry an `assetName` field, which is the join key: no filename
//      guessing, and a renamed asset fails loudly.
//
// Every fix in this branch is mutation-proven against these tests.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rf_attenuation_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/channel_map_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/iec_connectors_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/international_plugs_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/nema_connectors_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/poe_reference_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/power_phasing_screen.dart';

const String _kGraphicsDir = 'assets/tool-graphics';

// ══ ILLUSTRATIVE: the documented exemption list ════════════════════════════
//
// VERA HIGH-3. The criterion that used to be written here was FALSE. It claimed
// its members "carry no threshold, band, rating, or constant that a screen also
// tabulates". Vera found five counter-examples by hand. A full audit of all 78
// entries found THIRTEEN MORE -- and one of the exempted graphics was actively
// LYING (see poe-reference below). An exemption granted on a false premise, by
// the maker being gated, is exactly the governance failure GL-005 names: THE
// MAKER MAY NOT AUTHOR ITS OWN EXEMPTION.
//
// THE TRUE CRITERION, stated so it can be checked: a graphic belongs here when
// it depicts a MECHANISM, a FORMULA, a SEQUENCE, or a universal constant that
// cannot drift (3 dB = 2x; 0 dBm = 1 mW; coax is 50/75 ohm) -- i.e. when there
// is NO screen dataset it could diverge FROM. Illustrative example values
// ("RTT = 24 ms") are fine: nothing tabulates them, so nothing can contradict
// them. If a graphic states a number that a SCREEN ALSO TABULATES, it does not
// belong here -- it belongs in _dataBearing (guarded) or, until someone writes
// that guard, in _dataBearingUnguarded (declared, below).
const Set<String> _illustrative = <String>{
  // Pure formula / mechanism diagrams.
  'cable-loss', 'rain-fade', 'poe-budget', 'throughput-calc', 'capacity-planner',
  'noise-floor', 'fspl', 'eirp', 'link-budget', 'fresnel', 'ptp-link',
  'rf-attenuation-legacy',
  'wavelength', 'earth-curvature', 'downtilt', 'downtilt-coverage', 'dist-bearing',
  'midpoint', 'final-point', 'lat-long', 'metric-conversion', 'ohms-law-wheel',
  'db-reference', 'dbm-watt-converter', 'coax-cable',
  // Protocol / flow / sequence diagrams. Numbers here are worked EXAMPLES
  // (an RTT, a sample IP), not values any screen tabulates.
  'roaming', 'frame-exchange', 'eap-8021x-flow', 'arp-ndp', 'dns-lookup', 'whois',
  'ping', 'icmp-ping', 'ping-sweep', 'traceroute', 'mobile-traceroute', 'port-scan',
  'packet-sender', 'http-headers', 'ssl-inspect', 'wake-on-lan', 'bgp-asn',
  'mac-oui-lookup', 'mac-bit-field', 'ip-geo', 'interface-info', 'ipv4-subnet',
  'ipv6-subnet', 'spectrum', 'wpa-security',
  'freeradius-wlanpi', 'markdown-render-example', 'wifi-exposure-perspective',
  // Physical / mechanical practice (geometry and technique, not a tabulated datum).
  'bend-radius-arc-vs-kink', 'rack-cage-nut', 'screw-drives-faces',
  'screw-phillips-vs-pozidriv', 'screw-security-drives', 'fiber-optic',
};

// ══ DECLARED DEBT: data-bearing, NOT YET GUARDED ═══════════════════════════
//
// This list is NOT an exemption. An exemption asserts "there is nothing here to
// check" -- a CLAIM, and the false one that HIGH-3 was about. This list asserts
// the opposite: "these DO state numbers a screen also tabulates, and NOBODY IS
// CHECKING THEM." It is an admission of debt, which the maker is allowed to
// write; it is not a pass, which the maker is not (GL-005, 2026-07-13).
//
// Each was found by auditing all 78 exempted graphics against the screens. Vera
// hand-checked five of them and they are CORRECT TODAY -- there is no known live
// lie in this list. But "correct today, unguarded tomorrow" is precisely the
// state signal-thresholds.svg was in before it started lying, so the debt is
// named rather than hidden.
//
// KEITH RATIFIES what happens to these (GL-003 §0). Two honest options per
// entry: write the guard, or Keith rules the graphic genuinely illustrative.
// Felix does not get to decide either one.
const Map<String, String> _dataBearingUnguarded = <String, String>{
  'dscp-qos': 'DscpQosScreen — EF=46, AF41=34, WMM UP values',
  'port-reference': 'PortReferenceScreen — 22/53/80/443',
  'mcs-index': 'McsIndexScreen — MCS 0..11 modulation + rate',
  'reason-codes': 'ReasonCodesScreen — 802.11 deauth codes 1/3/4/15',
  '80211-standards': 'StandardsScreen — Wi-Fi 4/5/6/7 generations',
  'ethernet-cable': 'EthernetCableScreen — cat / speed / MHz table',
  'rack-1u-dimension': 'RackUnitsScreen — 1.75 in, 44.45 mm, EIA-310',
  'data-units-prefixes': 'DataUnitsScreen — 1000 vs 1024, the % gaps',
  'iec-60309': 'IecConnectorsScreen — 60309 voltage bands + colors',
  'fiber-connectors-faces': 'fiber screens — LC 1.25 mm / SC 2.5 mm ferrule',
  'fiber-apc-endface': 'fiber screens — 8 deg angle, return-loss figures',
  'fiber-two-color-systems': 'fiber screens — OM/OS codes, TIA-598 colors',
  'pull-tension-gauge': 'cable screens — 25 lbf / 110 N, TIA-568',
};

// ══ DATA-BEARING: each graphic and the Dart dataset that owns its numbers ═══
//
// LOW-2. This comment used to claim "Every entry here gets a semantic test
// below". That was false: signal-thresholds is tested in
// test/services/network/signal_grading_cross_check_test.dart, not here. A false
// claim about where the checking happens, in the file whose whole job is to stop
// false claims. The location is now named per entry.
const Map<String, String> _dataBearing = <String, String>{
  // Guarded in signal_grading_cross_check_test.dart (bands, ranges, contiguity).
  'signal-thresholds': 'WifiGradingBands.kRssiBands',
  // Guarded below.
  'channel-map': 'ChannelMapScreen.map5_40 / map5_80 / map5_160',
  'rf-attenuation': 'RfAttenuationScreen.materials',
  'poe-reference': 'PoeReferenceScreen.standards',
  'power-phasing-single-120v': 'PowerPhasingScreen.topologies',
  'power-phasing-split-240v': 'PowerPhasingScreen.topologies',
  'power-phasing-three-208v': 'PowerPhasingScreen.topologies',
  'nema-connectors': 'NemaConnectorsScreen (overview)',
  'iec-connectors': 'IecConnectorsScreen (overview)',
  'international-plugs': 'InternationalPlugsScreen (overview)',
  // The per-connector faces join their dataset row via `assetName`.
  ...<String, String>{},
};

List<String> _allGraphicSlugs() => Directory(_kGraphicsDir)
    .listSync()
    .whereType<File>()
    .map((File f) => f.uri.pathSegments.last)
    .where((String n) => n.endsWith('.svg'))
    .map((String n) => n.substring(0, n.length - 4))
    .toList()
  ..sort();

/// The rendered text of a graphic, comments stripped, entities unescaped.
/// Comments are stripped FIRST so nothing here can be satisfied by a claim made
/// only in a comment.
/// Decode SVG text to what a READER actually sees, then normalize the
/// typographic dashes (U+2212 minus, U+2013 en, U+2014 em) to ASCII '-' so a
/// pattern can match one character instead of four.
///
/// THIS IS NOT COSMETIC. The previous code hand-decoded exactly three entities.
/// international-plugs.svg draws Type I as "10&#8211;16 A", and the hand-decoder
/// left that as the LITERAL string `10&#8211;16 A` -- so the rating pattern did
/// not match it, the row was SILENTLY SKIPPED, and the orphan check (which used
/// the SAME pattern) could not see it either. A false rating was invisible at
/// BOTH ends of the check, and the suite went green over it.
///
/// A guard that decodes the document differently than the renderer does is
/// reading a different document than the user. Decode properly, and never let
/// the "did we check everything?" test share a pattern with the check itself.
String _decodeEntities(String s) => s
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAllMapped(RegExp(r'&#(\d+);'),
        (Match m) => String.fromCharCode(int.parse(m.group(1)!)))
    .replaceAll('&gt;', '>')
    .replaceAll('&lt;', '<')
    .replaceAll('&amp;', '&')
    .replaceAll('−', '-')
    .replaceAll('–', '-')
    .replaceAll('—', '-')
    .trim();

List<String> _texts(String slug) {
  final String raw = File('$_kGraphicsDir/$slug.svg').readAsStringSync();
  final String body = raw.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  return RegExp(r'<text\b[^>]*>(.*?)</text>', dotAll: true)
      .allMatches(body)
      .map((RegExpMatch m) => _decodeEntities(m.group(1)!))
      .where((String s) => s.isNotEmpty)
      .toList();
}

String _flat(String slug) => _texts(slug).join(' | ');

/// First integer in a string, e.g. '-10 dB' -> -10, '15A' -> 15.
int _firstInt(String s) =>
    int.parse(RegExp(r'-?\d+').firstMatch(s)!.group(0)!);

// ══ POSITIONAL PARSING ═════════════════════════════════════════════════════
//
// Vera HIGH-1. The first version of the rf-attenuation guard claimed in its own
// docstring to "read the wall's LABEL, resolve THAT row, compare THAT row's
// value" -- and then collected every `-(\d+) dB` in the file and asserted SET
// MEMBERSHIP. Vera swapped the two values, leaving both labels and both numbers
// present, and the suite stayed green: drywall -10 (truth 3), concrete block -3
// (truth 10). Both wrong for their labels; guard green.
//
// That is the SAME disease as the bug it was built to close, moved one level up:
// from "is this number in the FILE?" to "is this number in the DRAWING?". Both
// are set membership. A permutation within the set is invisible to both.
//
// A drawing has no rows. Its only binding between a label and its value is
// GEOMETRY: they share a column. So the guard must join by POSITION. These
// helpers do that, exactly as the branch-1 legend parser does.

/// A `<text>` with its position.
class _T {
  const _T(this.x, this.y, this.s);
  final double x;
  final double y;
  final String s;
}

/// A `<rect>` with its position.
class _R {
  const _R(this.x, this.y, this.w, this.h);
  final double x;
  final double y;
  final double w;
  final double h;
  double get cx => x + w / 2;
}

String _body(String slug) => File('$_kGraphicsDir/$slug.svg')
    .readAsStringSync()
    .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

double? _attr(String tag, String name) {
  final RegExpMatch? m =
      RegExp('(?:^|\\s)$name\\s*=\\s*"([\\d.-]+)"').firstMatch(tag);
  return m == null ? null : double.tryParse(m.group(1)!);
}

/// Every positioned `<text>` in [slug].
List<_T> _positionedTexts(String slug) =>
    RegExp(r'<text\b([^>]*)>(.*?)</text>', dotAll: true)
        .allMatches(_body(slug))
        .map((RegExpMatch m) {
          final double? x = _attr(m.group(1)!, 'x');
          final double? y = _attr(m.group(1)!, 'y');
          final String s = _decodeEntities(m.group(2)!);
          return (x == null || y == null || s.isEmpty) ? null : _T(x, y, s);
        })
        .whereType<_T>()
        .toList();

/// Every positioned `<rect>` in [slug].
List<_R> _positionedRects(String slug) => RegExp(r'<rect\b([^>]*?)/?>')
    .allMatches(_body(slug))
    .map((RegExpMatch m) {
      final String a = m.group(1)!;
      // NOTE the leading (?:^|\s) in _attr: without it, `width` also matches
      // STROKE-width, which once made every rect look 1.5px wide.
      final double? x = _attr(a, 'x');
      final double? y = _attr(a, 'y');
      final double? w = _attr(a, 'width');
      final double? h = _attr(a, 'height');
      return (x == null || y == null || w == null || h == null)
          ? null
          : _R(x, y, w, h);
    })
    .whereType<_R>()
    .toList();

/// The single text sharing [cx]'s column (within [tol]) and satisfying [where].
/// Throws if zero or more than one matches, which is itself the finding: a label
/// with no value, or a column so crowded the binding is ambiguous.
_T _inColumn(List<_T> texts, double cx, bool Function(_T) where,
    {double tol = 6}) {
  final List<_T> hits = texts
      .where((_T t) => (t.x - cx).abs() <= tol && where(t))
      .toList();
  if (hits.length != 1) {
    fail('Expected exactly ONE text in the column at x=$cx, found '
        '${hits.length}: ${hits.map((_T t) => t.s).toList()}. A drawing binds a '
        'label to its value by POSITION; an ambiguous column has no binding.');
  }
  return hits.single;
}

// ══ WAVEFORM GEOMETRY ══════════════════════════════════════════════════════
//
// Vera M-2: the power-phasing guard had NO geometry check. She moved the
// "120 V RMS" line to the wrong height and relabelled it, and the guard stayed
// green -- RIGHT WORDS, WRONG PICTURE. Reading only the <text> of a waveform
// graphic is exactly the label-only review GL-005 Scope C forbids.
//
// So these helpers read the ARTWORK: where the sine actually crests, where the
// axis ticks actually sit, and what the lime bracket actually spans.

/// A `<line>` with its endpoints and stroke.
class _L {
  const _L(this.x1, this.y1, this.x2, this.y2, this.stroke);
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final String stroke;
  bool get isHorizontal => (y1 - y2).abs() < 0.01;
  bool get isVertical => (x1 - x2).abs() < 0.01;
  bool get isLime => stroke.toUpperCase().contains('A1CC3A') ||
      stroke.toUpperCase().contains('A2CC3A');
}

String _attrStr(String tag, String name) =>
    RegExp('(?:^|\\s)$name\\s*=\\s*"([^"]*)"').firstMatch(tag)?.group(1) ?? '';

/// Every `<line>` in [slug], with its stroke resolved through `<g>` INHERITANCE.
///
/// The inheritance is not a nicety. The lime measurand bracket in
/// power-phasing-split-240v and -three-208v is written as bare
/// `<line x1=.. y1=.. x2=.. y2=../>` inside `<g stroke="#A1CC3A">` -- the lines
/// carry NO stroke attribute of their own. A naive `stroke="..."` read finds
/// ZERO lime lines in both files and every lime assertion below then vacuously
/// passes over an empty list. That is a guard that cannot fail, which is the
/// exact defect this whole file exists to stamp out -- and it was caught only
/// because the guard asserts `lime` is NOT EMPTY before trusting it. Assert that
/// your inputs exist before you assert things about them.
List<_L> _positionedLines(String slug) {
  final List<_L> out = <_L>[];
  final List<String> groupStroke = <String>[];
  final RegExp tok = RegExp(r'<g\b([^>]*)>|</g>|<line\b([^>]*?)/?>');
  for (final RegExpMatch m in tok.allMatches(_body(slug))) {
    final String tag = m.group(0)!;
    if (tag.startsWith('</g')) {
      if (groupStroke.isNotEmpty) groupStroke.removeLast();
      continue;
    }
    if (tag.startsWith('<g')) {
      groupStroke.add(_attrStr(m.group(1)!, 'stroke'));
      continue;
    }
    final String a = m.group(2)!;
    final double? x1 = _attr(a, 'x1');
    final double? y1 = _attr(a, 'y1');
    final double? x2 = _attr(a, 'x2');
    final double? y2 = _attr(a, 'y2');
    if (x1 == null || y1 == null || x2 == null || y2 == null) continue;
    String stroke = _attrStr(a, 'stroke');
    if (stroke.isEmpty) {
      for (int i = groupStroke.length - 1; i >= 0; i--) {
        if (groupStroke[i].isNotEmpty) {
          stroke = groupStroke[i];
          break;
        }
      }
    }
    out.add(_L(x1, y1, x2, y2, stroke));
  }
  return out;
}

/// The one text in the same GRID CELL as [id]: same column (within [xTol]) and
/// directly BELOW it (within [yBelow]), matching [rating].
///
/// A column join alone is not enough on the overview graphics: they are GRIDS,
/// and column x=150 of iec-connectors carries BOTH C5/C6 (y=252) and C15/C16
/// (y=588). Joining on x alone would happily read C15/C16's 10 A as C5/C6's
/// rating -- set membership's cousin, one axis short. The cell is the unit.
_T? _cellRating(List<_T> texts, _T id, RegExp rating,
    {double xTol = 3, double yBelow = 90}) {
  final List<_T> hits = texts
      .where((_T t) =>
          (t.x - id.x).abs() <= xTol &&
          t.y > id.y &&
          (t.y - id.y) <= yBelow &&
          rating.hasMatch(t.s))
      .toList();
  return hits.length == 1 ? hits.single : null;
}

/// The rating belonging to dataset identifier [id] in [slug], or null when [id]
/// is not drawn as an entry at all.
///
/// An identifier can legitimately appear more than once: nema-connectors prints
/// "14-50" both as a device tile AND as the worked example in its top-left key.
/// The tile is the one with a RATING in its cell; the key entry has none. So the
/// cell join is what disambiguates -- position again, not string matching. If
/// TWO occurrences both carry a rating, that is a genuine ambiguity and fails.
_T? _entryRating(List<_T> texts, String id, RegExp rating, String slug) {
  final List<_T> found = <_T>[
    for (final _T t in texts.where((_T t) => t.s == id))
      if (_cellRating(texts, t, rating) != null) t,
  ];
  if (found.isEmpty) return null; // not an entry on this graphic
  if (found.length > 1) {
    fail('$slug draws "$id" as ${found.length} separate rated entries. One '
        'dataset row cannot have two ratings in one drawing.');
  }
  return _cellRating(texts, found.single, rating);
}

/// Every rating text in [slug] must be consumed by exactly one dataset row.
///
/// Without this, a graphic could DROP an entry's rating (the row is skipped, the
/// loop finds nothing, and the test passes over it in silence) or carry an
/// ORPHAN rating belonging to no row at all. Counting both ends closes the
/// "guard that checks nothing" hole from the other side.
/// [loose] MUST be broader than the pattern the join uses. If the two share a
/// pattern, a rating drawn in an unexpected FORMAT fails both -- it is skipped
/// by the join AND uncounted by the audit -- and the guard goes green over a
/// number it never read. That is precisely how "10&#8211;16 A" hid.
void _expectNoOrphanRatings(
    List<_T> texts, RegExp loose, int joined, String slug) {
  final List<String> drawn =
      texts.where((_T t) => loose.hasMatch(t.s)).map((_T t) => t.s).toList();
  expect(joined, drawn.length,
      reason: '$slug draws ${drawn.length} rating texts but only $joined were '
          'matched to a dataset row. Either an entry is missing its rating, a '
          'rating is drawn for something not in the dataset, or one is drawn in '
          'a format the join does not parse. All three are findings: an '
          'unconsumed number is a number nobody is checking.\nDrawn: $drawn');
}

/// The vertices of every `<path>` polyline in [slug] with at least [minPoints]
/// points -- i.e. the WAVEFORMS, not the 3-point arrowheads or the sigma glyph.
List<List<double>> _waveformYs(String slug, {int minPoints = 50}) {
  final List<List<double>> waves = <List<double>>[];
  for (final RegExpMatch p
      in RegExp(r'<path\b[^>]*\sd="([^"]*)"[^>]*>').allMatches(_body(slug))) {
    // Every coordinate pair after an M/L command.
    final List<double> ys = RegExp(r'[ML]\s*(-?[\d.]+)[\s,]+(-?[\d.]+)')
        .allMatches(p.group(1)!)
        .map((RegExpMatch m) => double.parse(m.group(2)!))
        .toList();
    if (ys.length >= minPoints) waves.add(ys);
  }
  return waves;
}

void main() {
  // ══ 1. REACHABILITY ══════════════════════════════════════════════════════
  group('every shipped graphic is reachable from Dart', () {
    test('no orphaned asset (pubspec globs the directory, so dead assets SHIP)',
        () {
      // Read all of lib/, strip comments -- an asset "referenced" only in a
      // comment about its own DELETION is not reachable. That exact false
      // negative hid wifi-channels.svg, whose only mention was
      // tool_keywords.dart: "'wifi-channels' keywords removed ... tool deleted".
      final StringBuffer code = StringBuffer();
      for (final FileSystemEntity e
          in Directory('lib').listSync(recursive: true)) {
        if (e is File && e.path.endsWith('.dart')) {
          code.write(e
              .readAsStringSync()
              .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
              .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), ''));
        }
      }
      final String src = code.toString();

      final List<String> orphans = <String>[
        for (final String slug in _allGraphicSlugs())
          if (!src.contains("'$slug'") && !src.contains('"$slug"')) slug,
      ];
      expect(
        orphans,
        isEmpty,
        reason: 'These SVGs are referenced by NO Dart code, but pubspec.yaml '
            'globs assets/tool-graphics/ so they still ship in every binary and '
            'publish under AGPL. Delete them, or wire them to a screen. An '
            'unreachable graphic is one nobody reviews and nobody can '
            'fix:\n${orphans.join('\n')}',
      );
    });
  });

  // ══ 2. CLASSIFICATION COMPLETENESS ═══════════════════════════════════════
  group('every graphic is classified (no self-minted exemptions)', () {
    test('each SVG is either data-bearing or on the documented illustrative list',
        () {
      final List<String> unclassified = <String>[
        for (final String slug in _allGraphicSlugs())
          if (!_dataBearing.containsKey(slug) &&
              !_dataBearingUnguarded.containsKey(slug) &&
              !_illustrative.contains(slug) &&
              !_hasDatasetRow(slug))
            slug,
      ];
      expect(
        unclassified,
        isEmpty,
        reason: 'A new graphic has appeared and nobody has said whether it '
            'states data. Add it to _dataBearing (and give it a semantic test) '
            'or to _illustrative (a REVIEWED exemption, GL-003 §0). It may not '
            'sit in neither:\n${unclassified.join('\n')}',
      );
    });

    test('no graphic is classified twice', () {
      // A slug in two lists is a contradiction, and the more permissive entry
      // would silently win.
      final List<String> dupes = <String>[
        for (final String s in _allGraphicSlugs())
          if (<bool>[
                _dataBearing.containsKey(s),
                _dataBearingUnguarded.containsKey(s),
                _illustrative.contains(s),
              ].where((bool b) => b).length >
              1)
            s,
      ];
      expect(dupes, isEmpty, reason: 'Classified more than once: $dupes');
    });

    test('the declared-debt list does not silently GROW', () {
      // The quarantine is an admission of KNOWN debt, not a parking space for
      // new debt. It may shrink (someone writes the guard, or Keith rules the
      // graphic illustrative); it may not grow without this number moving, which
      // is a reviewed act. Without this, "unguarded" becomes the cheap default
      // and the list becomes the exemption it was written to replace.
      expect(_dataBearingUnguarded.length, lessThanOrEqualTo(13),
          reason: 'A graphic was added to the declared-debt list. That list is '
              'the audited backlog from 2026-07-14, not an intake queue. Guard '
              'the new graphic, or take it to Keith (GL-003 §0).');
    });

    test('neither exemption list has stale entries', () {
      final Set<String> present = _allGraphicSlugs().toSet();
      final List<String> stale = <String>[
        ..._illustrative,
        ..._dataBearingUnguarded.keys,
      ].where((String s) => !present.contains(s)).toList()
        ..sort();
      // 'rf-attenuation-legacy' is a deliberate tripwire: if it ever appears,
      // it means someone re-added the old file.
      stale.remove('rf-attenuation-legacy');
      expect(stale, isEmpty,
          reason: 'An exemption names graphics that no longer exist. A stale '
              'exemption is how an exemption quietly becomes '
              'architecture:\n${stale.join('\n')}');
    });
  });

  // ══ 3a. NEMA: 21 connector faces + the overview ══════════════════════════
  group('NEMA faces agree with NemaConnectorsScreen', () {
    final List<NemaDevice> devices = <NemaDevice>[
      ...NemaConnectorsScreen.group125v,
      ...NemaConnectorsScreen.group208v,
      ...NemaConnectorsScreen.groupCalifornia,
    ];

    test('every NEMA face draws its dataset row\'s voltage and amps', () {
      final List<String> bad = <String>[];
      for (final NemaDevice d in devices) {
        final String? slug = d.assetName;
        if (slug == null || !File('$_kGraphicsDir/$slug.svg').existsSync()) {
          continue;
        }
        // The face prints e.g. "125 V · 15 A".
        final RegExpMatch? m =
            RegExp(r'(\d+(?:/\d+)?)\s*V\s*·\s*(\d+)\s*A').firstMatch(_flat(slug));
        if (m == null) {
          bad.add('$slug: no "<volts> V · <amps> A" rating drawn');
          continue;
        }
        final String v = '${m.group(1)}V';
        final int a = int.parse(m.group(2)!);
        if (v != d.voltage || a != d.amps) {
          bad.add('$slug (${d.type}): graphic says $v/${a}A, dataset says '
              '${d.voltage}/${d.amps}A');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });
  });

  // ══ 3b. IEC couplers ═════════════════════════════════════════════════════
  group('IEC coupler faces agree with IecConnectorsScreen', () {
    test('every IEC face draws its dataset row\'s current rating', () {
      final List<String> bad = <String>[];
      for (final IecCoupler c in IecConnectorsScreen.couplers) {
        final String? slug = c.assetName;
        if (slug == null || !File('$_kGraphicsDir/$slug.svg').existsSync()) {
          continue;
        }
        final RegExpMatch? m =
            RegExp(r'([\d.]+)\s*A').firstMatch(_flat(slug));
        expect(m, isNotNull, reason: '$slug draws no current rating.');
        final String drawn = '${m!.group(1)} A';
        if (drawn != c.current) {
          bad.add('$slug (${c.pair}): graphic says $drawn, dataset says '
              '${c.current}');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });
  });

  // ══ 3c. International plugs ══════════════════════════════════════════════
  group('international plug faces agree with InternationalPlugsScreen', () {
    test('every plug face draws its dataset row\'s voltage and current', () {
      // The 2026-07-14 finding: intl-i drew "10-16 A" and intl-j drew "10 / 16 A"
      // while the dataset says 10A for both. The dataset is RIGHT and expresses a
      // genuine dual rating when one exists (Type L = "10 / 16A", Italy), which is
      // what proves the single 10A on I and J is deliberate, not an omission.
      final List<String> bad = <String>[];
      for (final PlugType p in InternationalPlugsScreen.plugTypes) {
        final String? slug = p.assetName;
        if (slug == null || !File('$_kGraphicsDir/$slug.svg').existsSync()) {
          continue;
        }
        final String flat = _flat(slug);
        // Allow decimals (Type C is 2.5 A) and dual ratings ("10 / 16 A").
        final RegExpMatch? m =
            RegExp(r'(\d+)\s*V\s*·\s*([\d.\s/–-]*[\d.])\s*A').firstMatch(flat);
        if (m == null) {
          bad.add('$slug (Type ${p.type}): no "<volts> V · <amps> A" drawn');
          continue;
        }
        final String v = '${m.group(1)}V';
        final String a = '${m.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim()}A';
        final String expectA = p.current.replaceAll(' (fused)', '');
        if (v != p.voltageClass || a.replaceAll(' ', '') != expectA.replaceAll(' ', '')) {
          bad.add('$slug (Type ${p.type}): graphic says $v / $a, dataset says '
              '${p.voltageClass} / ${p.current}');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });
  });

  // ══ 3d. rf-attenuation: the label and its value are joined by POSITION ═════
  group('rf-attenuation.svg agrees with RfAttenuationScreen.materials', () {
    test('each drawn wall resolves to ONE dataset row and prints THAT row\'s '
        '2.4 GHz loss', () {
      // VERA HIGH-1. The previous version of this test claimed, in its own
      // docstring, to "read the wall's LABEL, resolve THAT row, compare THAT
      // row's value" -- and then collected every `-(\d+) dB` in the file and
      // asserted SET MEMBERSHIP. Vera SWAPPED the two values between their
      // labels (drywall -10, concrete block -3; truth is 3 and 10) and the
      // suite stayed GREEN, because both numbers were still present somewhere.
      // Both values wrong for their labels; guard green.
      //
      // Set membership cannot see a PERMUTATION. That is the same disease as
      // the -12 dB bug this file exists to close, moved one level up: from "is
      // this number in the FILE?" to "is this number in the DRAWING?".
      //
      // A drawing has no rows. The ONLY thing binding a label to its value is
      // GEOMETRY: they share a column with the wall they describe. So join by
      // POSITION -- rect centre -> the label under it, the value over it.
      final String flat = _flat('rf-attenuation');
      expect(flat, contains('2.4 GHz'),
          reason: 'The graphic prints per-material losses but never says which '
              'BAND they are for. That ambiguity is what let the -12 dB hide.');

      final List<_T> texts = _positionedTexts('rf-attenuation');
      final List<_R> walls = _positionedRects('rf-attenuation');
      expect(walls, isNotEmpty,
          reason: 'No wall <rect> found. The guard joins a label to its value '
              'through the wall they share a column with; with no walls it '
              'would silently check nothing.');

      final List<String> bad = <String>[];
      for (final _R wall in walls) {
        // The value above the wall (e.g. "-3 dB") and the material label below
        // it. Exactly one of each in this column, or the binding is ambiguous
        // and _inColumn fails loudly -- which is itself the finding.
        final _T value = _inColumn(texts, wall.cx,
            (_T t) => RegExp(r'^-\d+\s*dB$').hasMatch(t.s));
        final _T label = _inColumn(
            texts, wall.cx, (_T t) => !RegExp(r'\d').hasMatch(t.s));

        // Resolve the DRAWN label against the real dataset. It must match
        // EXACTLY ONE row. This is what makes a vague label a build failure:
        // the original bug drew a wall called plain "concrete", which matches
        // THREE rows (CMU, poured, floor/ceiling) and is therefore not an
        // answer to any question. Ambiguity is the bug, not just the number.
        final List<RfMaterial> rows = RfAttenuationScreen.materials
            .where((RfMaterial m) =>
                m.name.toLowerCase().contains(label.s.toLowerCase()))
            .toList();
        if (rows.length != 1) {
          bad.add('wall "${label.s}" resolves to ${rows.length} dataset rows '
              '(${rows.map((RfMaterial m) => m.name).toList()}). A drawn label '
              'must name exactly one material. "concrete" alone matched three, '
              'which is how -12 dB hid.');
          continue;
        }
        final RfMaterial row = rows.single;
        final int drawn = _firstInt(value.s);
        if (drawn != -row.loss24) {
          bad.add('wall "${label.s}" (x=${wall.cx}) is drawn "${value.s}", but '
              'it resolves to dataset row "${row.name}", whose 2.4 GHz loss is '
              '${row.loss24} dB. Expected "-${row.loss24} dB". THIS IS THE '
              'CHECK THAT SET MEMBERSHIP COULD NOT MAKE: the number may well '
              'appear elsewhere in the drawing, on the wrong wall.');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });
  });

  // ══ 3e. channel-map: the bonding arithmetic, and the geometry ════════════
  group('channel-map.svg agrees with ChannelMapScreen', () {
    test('every channel number drawn is a real 20 MHz channel in a bonded block',
        () {
      final String flat = _flat('channel-map');
      // The 160 MHz block the drawing depicts: ch 36-64.
      final BondedBlock b160 = ChannelMapScreen.map5_160
          .firstWhere((BondedBlock b) => b.lowChannel == 36);
      final List<int> expected = <int>[
        for (int c = b160.lowChannel; c <= b160.highChannel; c += 4) c,
      ];
      expect(expected.length, 8,
          reason: 'A 160 MHz bond spans EIGHT 20 MHz channels '
              '(channel_map_screen.dart:103 -- "160->8").');
      for (final int c in expected) {
        expect(RegExp(r'\b' + c.toString() + r'\b').hasMatch(flat), isTrue,
            reason: 'The drawing omits channel $c, which is inside the '
                '160 MHz bond ch ${b160.lowChannel}-${b160.highChannel}.');
      }
    });

    test('160 MHz is drawn over EIGHT 20 MHz cells, not four', () {
      // THE BUG: the old drawing put a "160 MHz" span across the SAME pixel
      // extent as its own 80 MHz block. Read the boxes, not the words.
      final String body = File('$_kGraphicsDir/channel-map.svg')
          .readAsStringSync()
          .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      // NOTE the leading \s: without it this also matches STROKE-width, which
      // made every rect look 1.5px wide and the ratio a perfect 1.00. A guard
      // that measures the wrong thing reports a tidy number and proves nothing.
      final List<double> widths = RegExp(r'<rect[^>]*\swidth="([\d.]+)"')
          .allMatches(body)
          .map((RegExpMatch m) => double.parse(m.group(1)!))
          .toList();
      final double cell = widths.reduce(math.min); // the 20 MHz cell
      final double widest = widths.reduce(math.max); // the 160 MHz block
      // Eight cells plus seven inter-cell gaps == the full 160 MHz span.
      expect(widest / cell, closeTo(8.0, 0.5),
          reason: 'The widest block (160 MHz) is ${widest.toStringAsFixed(1)}px '
              'and a 20 MHz cell is ${cell.toStringAsFixed(1)}px, a ratio of '
              '${(widest / cell).toStringAsFixed(2)}. A 160 MHz bond must span '
              'EIGHT cells. The old drawing spanned four, and labelled the same '
              'extent both 80 and 160 MHz. The picture is lying even if the '
              'labels are right.');
    });
  });

  // ══ 3f. power-phasing: ALL THREE drawings, geometry included ═════════════
  //
  // VERA HIGH-2. Only single-120v was fixed. The other two were EXEMPTED on the
  // grounds that "neither says 'peak', so neither asserts anything false".
  // Vera refuted that BY MEASUREMENT: she parsed the sine paths and found all
  // five crests landing exactly on the tick labelled +120. AN AXIS TICK AT THE
  // CREST IS A PEAK CLAIM, whether or not the word "peak" appears. A 120 V RMS
  // system peaks at 169.7 V. Removing the WORD would have removed the evidence,
  // not the error.
  //
  // And fixing one of three made it WORSE: all three come from ONE dataset
  // (PowerPhasingScreen.topologies), so the screen showed two different axis
  // conventions at once -- a self-contradiction, blocking under GL-005 /
  // SOP-009 §5.5. The dataset is the unit of correctness, so the guard now
  // iterates the DATASET, not a hand-listed slug. A fourth topology cannot be
  // added without a drawing that satisfies this.
  group('power-phasing: every topology drawing gets RMS vs peak right', () {
    for (final PowerTopology t in PowerPhasingScreen.topologies) {
      final String slug = t.assetName;
      final int rms = _firstInt(t.lineToNeutral); // 120, from the screen
      final double peakV = rms * math.sqrt2; // 169.7, DERIVED not typed
      final int peak = peakV.round(); // 170

      test('$slug: the axis is PEAK volts and the sine really reaches it', () {
        final String flat = _flat(slug);
        final List<List<double>> waves = _waveformYs(slug);
        expect(waves, isNotEmpty, reason: '$slug draws no waveform.');

        // The artwork's own extremes.
        final double crestY =
            waves.expand((List<double> w) => w).reduce(math.min);
        final double troughY =
            waves.expand((List<double> w) => w).reduce(math.max);
        final double zeroY = (crestY + troughY) / 2;
        final double fullScale = zeroY - crestY; // px representing peakV volts

        /// Instantaneous volts at a drawn y. THIS is the drawing's real claim.
        double voltsAt(double y) => (zeroY - y) / fullScale * peakV;

        // ── VALUE: the crest tick must read the DERIVED peak, not the RMS ──
        // Bind each axis tick line to the label sharing its row (baseline sits
        // a few px below the tick). Geometry, again -- not set membership.
        final List<_T> texts = _positionedTexts(slug);
        final List<_L> ticks = _positionedLines(slug)
            .where((_L l) => l.isHorizontal && (l.x2 - l.x1).abs() <= 10)
            .toList();
        expect(ticks.length, greaterThanOrEqualTo(3),
            reason: '$slug: expected +peak / 0 / -peak axis ticks.');

        _T labelFor(_L tick) {
          final List<_T> near = texts
              .where((_T t) =>
                  t.x < tick.x1 && // left margin
                  (t.y - tick.y1) >= 0 &&
                  (t.y - tick.y1) <= 6 && // baseline just below the tick
                  RegExp(r'^[+-]?\d+$').hasMatch(t.s))
              .toList();
          if (near.length != 1) {
            fail('$slug: the axis tick at y=${tick.y1} has ${near.length} '
                'numeric labels beside it (${near.map((_T t) => t.s).toList()}). '
                'A tick with no label makes no claim; a tick with two is '
                'ambiguous.');
          }
          return near.single;
        }

        final _L crestTick = ticks.reduce(
            (_L a, _L b) => (a.y1 - crestY).abs() < (b.y1 - crestY).abs() ? a : b);
        final _L troughTick = ticks.reduce((_L a, _L b) =>
            (a.y1 - troughY).abs() < (b.y1 - troughY).abs() ? a : b);

        // ── GEOMETRY (Vera M-2 + HIGH-2): the tick nearest the crest must BE
        // at the crest. This is the check that makes "an axis tick at the crest
        // is a peak claim" mechanical.
        expect((crestTick.y1 - crestY).abs(), lessThan(0.75),
            reason: '$slug: the sine crests at y=$crestY but the nearest axis '
                'tick is at y=${crestTick.y1}. The waveform must actually touch '
                'the tick it is claimed to reach.');
        expect((troughTick.y1 - troughY).abs(), lessThan(0.75),
            reason: '$slug: the sine troughs at y=$troughY but the nearest axis '
                'tick is at y=${troughTick.y1}.');

        expect(_firstInt(labelFor(crestTick).s), peak,
            reason: '$slug: the sine CRESTS on the tick labelled '
                '"${labelFor(crestTick).s}". An axis tick at the crest IS a peak '
                'claim, whether or not the word "peak" appears. ${t.name} is '
                '$rms V RMS, which peaks at ${peakV.toStringAsFixed(1)} V, so '
                'that tick must read $peak. Labelling it $rms puts the RMS and '
                'the peak at the same place on the axis -- the single most '
                'common way to get AC wrong.');
        expect(_firstInt(labelFor(troughTick).s), -peak,
            reason: '$slug: the trough tick must read -$peak.');

        // ── M-3: the negative check must not be defeated by a space. The old
        // regex was `\b120V peak\b`, which "120 V peak" walks straight through.
        expect(
          RegExp('\\b$rms\\s*V?\\s*peak\\b', caseSensitive: false).hasMatch(flat),
          isFalse,
          reason: '$slug still calls $rms V the PEAK. It is the RMS. (This '
              'check now tolerates any spacing: the previous `\\b${rms}V peak\\b` '
              'was defeated by a single space.)',
        );

        // ── The lime measurand: its PIXELS must agree with its label ────────
        // single-120v draws a HORIZONTAL lime line = the RMS level.
        // split/three draw a VERTICAL lime bracket = the line-to-line span.
        // Both are read off the same voltsAt(), so neither can be relabelled
        // without moving the artwork, nor moved without changing the number.
        final List<_L> lime =
            _positionedLines(slug).where((_L l) => l.isLime).toList();
        expect(lime, isNotEmpty,
            reason: '$slug draws no lime measurand line.');

        for (final _L l in lime.where((_L l) => l.isHorizontal)) {
          expect(voltsAt(l.y1), closeTo(rms.toDouble(), 1.0),
              reason: '$slug: the lime RMS line is drawn at y=${l.y1}, which on '
                  'this peak axis is ${voltsAt(l.y1).toStringAsFixed(1)} V -- '
                  'not the $rms V RMS it is labelled. $rms V RMS sits at 0.707 '
                  'of full scale, NOT at the peak. (Vera M-2: she moved this '
                  'line and the guard stayed green. Right words, wrong picture.)');
        }
        for (final _L l in lime.where((_L l) => l.isVertical)) {
          // A span between two curves: its peak-to-peak, converted back to RMS,
          // must equal the dataset's line-to-line voltage.
          final double spanPeak = (voltsAt(l.y1) - voltsAt(l.y2)).abs();
          final double impliedRms = spanPeak / math.sqrt2;
          final int expectRms = _firstInt(t.lineToLine);
          expect(impliedRms, closeTo(expectRms.toDouble(), 1.5),
              reason: '$slug: the lime bracket spans y=${l.y1}..${l.y2}, which '
                  'on this peak axis is ${spanPeak.toStringAsFixed(1)} V peak = '
                  '${impliedRms.toStringAsFixed(1)} V RMS. The dataset says '
                  '${t.name} is line-to-line ${t.lineToLine}. The bracket must '
                  'measure what it says it measures.');
        }
      });
    }
  });

  // ══ 3g. the connector OVERVIEW graphics ══════════════════════════════════
  //
  // VERA HIGH-3, and the hole she did not name. The per-connector FACES were
  // guarded (they join their dataset row through `assetName`), while the three
  // OVERVIEW graphics -- which redraw the SAME dataset rows, ratings and all --
  // sat on the illustrative exemption list, whose stated criterion was that its
  // members "carry no threshold, band, rating or constant that a screen also
  // tabulates". These three are nothing BUT ratings a screen tabulates. The
  // overview could contradict the face beside it and nothing would know.
  //
  // The join is the same one that made the faces cheap: the drawing binds an
  // identifier to its rating by GEOMETRY (they share a grid cell), so read the
  // identifier, resolve THAT dataset row, and compare THAT row's rating.
  group('connector overview graphics agree with their datasets', () {
    test('nema-connectors.svg draws each device\'s real voltage and amps', () {
      final List<_T> texts = _positionedTexts('nema-connectors');
      final RegExp re = RegExp(r'^\d+(?:/\d+)?V\s*·\s*\d+\s*A');
      final List<String> bad = <String>[];
      final Set<String> consumed = <String>{};
      for (final NemaDevice d in <NemaDevice>[
        ...NemaConnectorsScreen.group125v,
        ...NemaConnectorsScreen.group208v,
        ...NemaConnectorsScreen.groupCalifornia,
      ]) {
        final _T? rating = _entryRating(texts, d.type, re, 'nema-connectors');
        if (rating == null) continue; // not drawn on the overview
        consumed.add('${rating.x},${rating.y}');
        final RegExpMatch m =
            RegExp(r'^(\d+(?:/\d+)?)V\s*·\s*(\d+)\s*A').firstMatch(rating.s)!;
        if ('${m.group(1)}V' != d.voltage || int.parse(m.group(2)!) != d.amps) {
          bad.add('NEMA ${d.type}: overview draws "${rating.s}", dataset says '
              '${d.voltage} / ${d.amps}A');
        }
      }
      expect(bad.toSet().toList(), isEmpty, reason: bad.toSet().join('\n'));
      _expectNoOrphanRatings(
          texts, RegExp(r'^\d+(?:/\d+)?V\s*·'), consumed.length, 'nema-connectors');
    });

    test('iec-connectors.svg draws each coupler\'s real current rating', () {
      final List<_T> texts = _positionedTexts('iec-connectors');
      final RegExp re = RegExp(r'^[\d.]+\s*A\s*·');
      final List<String> bad = <String>[];
      final Set<String> consumed = <String>{};
      for (final IecCoupler c in IecConnectorsScreen.couplers) {
        final _T? rating = _entryRating(texts, c.pair, re, 'iec-connectors');
        if (rating == null) continue;
        consumed.add('${rating.x},${rating.y}');
        final String drawn =
            '${RegExp(r'^([\d.]+)\s*A').firstMatch(rating.s)!.group(1)} A';
        if (drawn != c.current) {
          bad.add('IEC ${c.pair}: overview draws "$drawn", dataset says '
              '"${c.current}"');
        }
      }
      expect(bad.toSet().toList(), isEmpty, reason: bad.toSet().join('\n'));
      _expectNoOrphanRatings(
          texts, RegExp(r'^[\d.]+\s*A\s*·'), consumed.length, 'iec-connectors');
    });

    test('international-plugs.svg draws each plug\'s real voltage and current',
        () {
      final List<_T> texts = _positionedTexts('international-plugs');
      // Type G is drawn "230 V · 13 A fused" -- the dataset says "13A (fused)".
      // The qualifier is part of the rating, so the pattern must admit it rather
      // than silently failing to find the cell (which would skip the row).
      final RegExp re =
          RegExp(r'^\d+\s*V\s*·\s*[\d.\s/-]*[\d.]\s*A(?:\s+fused)?$');

      // Iterate the DRAWN TILES, not the dataset rows. The drawing combines
      // North America into ONE tile, "Type A / B", which matches neither
      // 'Type A' nor 'Type B' -- so a dataset-driven loop skipped it in silence
      // and left it permanently unguarded. The orphan audit is what surfaced
      // that (10 ratings drawn, 9 consumed): iterating the artifact is what
      // makes "did I check everything I drew?" answerable at all.
      final List<String> bad = <String>[];
      final Set<String> consumed = <String>{};
      for (final _T tile in texts) {
        final RegExpMatch? id =
            RegExp(r'^Type ([A-Z](?:\s*/\s*[A-Z])*)$').firstMatch(tile.s);
        if (id == null) continue; // e.g. the "Type I caution:" footnote
        final _T? rating = _cellRating(texts, tile, re);
        if (rating == null) continue;
        consumed.add('${rating.x},${rating.y}');

        final RegExpMatch m =
            RegExp(r'^(\d+)\s*V\s*·\s*([\d.\s/-]*[\d.])\s*A(?:\s+fused)?$')
                .firstMatch(rating.s)!;
        final String v = '${m.group(1)}V';
        final String a =
            '${m.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim()}A';
        final bool drawnFused = rating.s.contains('fused');

        // "Type A / B" asserts the rating for BOTH A and B; every row it names
        // must agree with the one rating the tile prints.
        for (final String t in id.group(1)!.split('/').map((String s) => s.trim())) {
          final List<PlugType> rows = InternationalPlugsScreen.plugTypes
              .where((PlugType p) => p.type == t)
              .toList();
          if (rows.isEmpty) {
            bad.add('Tile "${tile.s}" names Type $t, which is not in the '
                'dataset at all.');
            continue;
          }
          for (final PlugType p in rows) {
            final String expectA = p.current.replaceAll(' (fused)', '');
            if (v != p.voltageClass ||
                a.replaceAll(' ', '') != expectA.replaceAll(' ', '') ||
                drawnFused != p.current.contains('fused')) {
              bad.add('Type $t (${p.standard}): overview draws "${rating.s}", '
                  'dataset says "${p.voltageClass} / ${p.current}"');
            }
          }
        }
      }
      expect(bad.toSet().toList(), isEmpty, reason: bad.toSet().join('\n'));
      _expectNoOrphanRatings(
          texts, RegExp(r'^\d+\s*V\s*·'), consumed.length, 'international-plugs');
    });
  });

  // ══ 3h. poe-reference: the VALUES and the BAR HEIGHTS ════════════════════
  //
  // Found while auditing the exemption list (Vera HIGH-3). This graphic was
  // EXEMPT as "illustrative". It is not: it is a bar chart of a dataset column,
  // and it was wrong in two independent ways, neither visible in its labels.
  //
  //   * THE BARS BROKE THEIR OWN SCALE. An axis labelled "Watts" makes the bar
  //     HEIGHT a claim -- the same principle as Vera's "an axis tick at the
  //     crest IS a peak claim". af and at were drawn at ~1.4 px/W; bt at
  //     0.82 px/W. 90 W was rendered at the height of ~53 W.
  //   * "802.3bt" RESOLVES TO TWO ROWS (Type 3 = 60 W, Type 4 = 90 W), and the
  //     drawing printed 90 W beside the ambiguous label. Exactly the -12 dB
  //     "concrete" shape.
  //   * "Watts" never said WHICH END. pseWatts and pdWatts are both real columns
  //     of this dataset; 802.3bt Type 4 sources 90 W but delivers 71.3 W.
  group('poe-reference.svg agrees with PoeReferenceScreen.standards', () {
    test('each bar names ONE standard, prints its PSE watts, and is drawn to '
        'scale', () {
      final List<_T> texts = _positionedTexts('poe-reference');
      final List<_R> bars = _positionedRects('poe-reference');
      expect(bars.length, 3, reason: 'Expected three power-step bars.');

      expect(_flat('poe-reference').toUpperCase(), contains('PSE'),
          reason: 'The graphic prints watts but never says which END of the '
              'link they describe. The dataset carries pseWatts AND pdWatts and '
              'they differ (802.3bt Type 4: 90 W sourced, 71.3 W delivered). '
              'That ambiguity is the -12 dB bug in another costume.');

      final List<String> bad = <String>[];
      final List<double> pxPerWatt = <double>[];
      for (final _R bar in bars) {
        final _T std = _inColumn(
            texts, bar.cx, (_T t) => t.s.startsWith('802.3'));
        final _T watts =
            _inColumn(texts, bar.cx, (_T t) => RegExp(r'^[\d.]+ W$').hasMatch(t.s));

        // Resolve the DRAWN label to exactly one dataset row. "802.3bt" alone
        // matches two and must fail.
        final List<PoeStandard> rows = PoeReferenceScreen.standards
            .where((PoeStandard s) => s.standard == std.s)
            .toList();
        if (rows.length != 1) {
          bad.add('bar "${std.s}" resolves to ${rows.length} dataset rows. A '
              'drawn label must name exactly one standard: "802.3bt" is not a '
              'row (Type 3 = 60 W, Type 4 = 90 W are).');
          continue;
        }
        final PoeStandard row = rows.single;
        final double drawn = double.parse(watts.s.replaceAll(' W', ''));
        if (drawn != row.pseWatts) {
          bad.add('bar "${std.s}" is drawn "${watts.s}", but that row\'s PSE '
              'power is ${row.pseWatts} W.');
          continue;
        }
        pxPerWatt.add(bar.h / row.pseWatts);
      }
      expect(bad, isEmpty, reason: bad.join('\n'));

      // GEOMETRY: one scale for every bar. This is the check that reads the
      // ARTWORK -- the labels were all individually true while the picture
      // understated 802.3bt by 40%.
      final double lo = pxPerWatt.reduce(math.min);
      final double hi = pxPerWatt.reduce(math.max);
      expect(hi - lo, lessThan(0.01),
          reason: 'The bars do not share one scale: px-per-watt ranges '
              '${lo.toStringAsFixed(3)}..${hi.toStringAsFixed(3)}. The axis is '
              'labelled "Watts", so bar HEIGHT is a claim. A bar drawn short '
              'because its true height would not fit is a lying drawing, even '
              'though its printed number is correct.');
    });
  });
}

/// True when [slug] is a connector/plug face owned by a dataset row (the
/// `assetName` join), so it is already covered by the semantic groups above and
/// does not need its own registry entry.
bool _hasDatasetRow(String slug) =>
    <String?>[
      ...NemaConnectorsScreen.group125v.map((NemaDevice d) => d.assetName),
      ...NemaConnectorsScreen.group208v.map((NemaDevice d) => d.assetName),
      ...NemaConnectorsScreen.groupCalifornia.map((NemaDevice d) => d.assetName),
      ...IecConnectorsScreen.couplers.map((IecCoupler c) => c.assetName),
      ...InternationalPlugsScreen.plugTypes.map((PlugType p) => p.assetName),
    ].contains(slug);
