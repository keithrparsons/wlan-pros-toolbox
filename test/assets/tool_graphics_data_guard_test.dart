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
import 'package:wlan_pros_toolbox/screens/tools/reference/cable_bend_radius_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/channel_map_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/iec_connectors_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/international_plugs_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/nema_connectors_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/poe_reference_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/power_phasing_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/rack_units_screen.dart';

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

/// The GROUND on which a graphic is exempt. An exemption may no longer be
/// ASSERTED ("trust me, it's illustrative"); it must be CLAIMED UNDER A RULE,
/// and the rule must be one of the four the criterion above actually allows.
///
/// VERA MEDIUM-2 (2026-07-14). `_dataBearingUnguarded` -- the HONEST list, the
/// one that says "nobody is checking these" -- was size-pinned. `_illustrative`
/// -- the list that had been FALSE FOR 19 OF ITS 78 ENTRIES -- had no pin at
/// all. So the maker could still mint an exemption for free, AND could relieve
/// pressure on the debt list by MOVING an entry into the unpinned one.
/// The confession was pinned and the alibi was left unbounded. Both are pinned
/// now, and an exemption must name its ground.
enum _Exempt {
  /// Depicts HOW something works. A mechanism is not a datum; no screen
  /// tabulates it, so nothing can contradict it.
  mechanism,

  /// Depicts a FORMULA or its derivation. The formula IS the claim; the numbers
  /// in it are worked substitutions, not tabulated values.
  formula,

  /// Depicts a SEQUENCE / protocol exchange. Numbers are worked examples
  /// (an RTT, a sample IP) that no screen tabulates.
  sequence,

  /// A universal constant that cannot drift (3 dB = 2x; 0 dBm = 1 mW; coax is
  /// 50/75 ohm). There is no dataset for it to diverge FROM.
  constant,
}

const Map<String, _Exempt> _illustrative = <String, _Exempt>{
  // ── Formula / mechanism diagrams ──
  'cable-loss': _Exempt.formula,
  'rain-fade': _Exempt.formula,
  'poe-budget': _Exempt.formula,
  'throughput-calc': _Exempt.formula,
  'capacity-planner': _Exempt.formula,
  'noise-floor': _Exempt.formula,
  'fspl': _Exempt.formula,
  'eirp': _Exempt.formula,
  'link-budget': _Exempt.formula,
  'fresnel': _Exempt.formula,
  'ptp-link': _Exempt.mechanism,
  // Deliberate tripwire: the file does not exist. If it ever reappears, the
  // stale-entry test below stops removing it and someone must explain why the
  // old lying drawing came back.
  'rf-attenuation-legacy': _Exempt.mechanism,
  'wavelength': _Exempt.formula,
  'earth-curvature': _Exempt.formula,
  'downtilt': _Exempt.formula,
  'downtilt-coverage': _Exempt.formula,
  'dist-bearing': _Exempt.formula,
  'midpoint': _Exempt.formula,
  'final-point': _Exempt.formula,
  'lat-long': _Exempt.mechanism,
  'metric-conversion': _Exempt.constant,
  'ohms-law-wheel': _Exempt.formula,
  'db-reference': _Exempt.constant,
  'dbm-watt-converter': _Exempt.formula,
  'coax-cable': _Exempt.constant,
  // ── Protocol / flow / sequence diagrams ──
  'roaming': _Exempt.sequence,
  'frame-exchange': _Exempt.sequence,
  'eap-8021x-flow': _Exempt.sequence,
  'arp-ndp': _Exempt.sequence,
  'dns-lookup': _Exempt.sequence,
  'whois': _Exempt.sequence,
  'ping': _Exempt.sequence,
  'icmp-ping': _Exempt.sequence,
  'ping-sweep': _Exempt.sequence,
  'traceroute': _Exempt.sequence,
  'mobile-traceroute': _Exempt.sequence,
  'port-scan': _Exempt.sequence,
  'packet-sender': _Exempt.sequence,
  'http-headers': _Exempt.sequence,
  'ssl-inspect': _Exempt.sequence,
  'wake-on-lan': _Exempt.sequence,
  'bgp-asn': _Exempt.sequence,
  'mac-oui-lookup': _Exempt.sequence,
  'ip-geo': _Exempt.sequence,
  'interface-info': _Exempt.sequence,
  'freeradius-wlanpi': _Exempt.sequence,
  'mac-bit-field': _Exempt.mechanism,
  'ipv4-subnet': _Exempt.mechanism,
  'ipv6-subnet': _Exempt.mechanism,
  'spectrum': _Exempt.mechanism,
  'wpa-security': _Exempt.mechanism,
  'markdown-render-example': _Exempt.mechanism,
  'wifi-exposure-perspective': _Exempt.mechanism,
  // ── Physical / mechanical practice (technique, not a tabulated datum) ──
  // NOTE what is NO LONGER here: 'bend-radius-arc-vs-kink' (it draws
  // "R >= 4x OD", which cable_bend_radius_screen.dart:142 tabulates) and
  // 'rack-cage-nut' (it draws "10-32, 12-24, or M6", which
  // rack_units_screen.dart:236/242/248 tabulates). Both were exempt; both are
  // now guarded. See §3i and §3j.
  'screw-drives-faces': _Exempt.mechanism,
  'screw-phillips-vs-pozidriv': _Exempt.mechanism,
  'screw-security-drives': _Exempt.mechanism,
  'fiber-optic': _Exempt.mechanism,
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
  // VERA MEDIUM-1 (2026-07-14). Both of these were on the ILLUSTRATIVE list --
  // i.e. someone had asserted they state no tabulated datum. Both do, and both
  // have a SIBLING (declared in the same lib/data/*_diagrams.dart, drawn on the
  // same screen, sourced from the same standard) that was correctly declared as
  // debt. One file, two graphics, two different verdicts: that split IS the
  // finding, and §2 now makes it a build failure.
  'bend-radius-arc-vs-kink': 'CableBendRadiusScreen.copperBend (guarded below)',
  'rack-cage-nut': 'RackUnitsScreen.threads (guarded below)',
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

// ══ THE `transform` HOLE ═══════════════════════════════════════════════════
//
// FOUND BY ATTACKING THIS FIX, 2026-07-14, after the three above were closed.
//
// Every geometry check in this file reads raw x / y / width / height attributes.
// SVG's `transform` moves the RENDERED artwork WITHOUT touching any of them. So
// the brand-new baseline pin below -- the one written to close Vera's HIGH-3 --
// could be walked straight past by re-floating the same bar with
// `transform="translate(0,-25)"`: y+h still reads 120, the pin is satisfied, and
// the bar hangs in mid-air on screen. HIGH-3, reopened, through the door its own
// fix left open. A transform on a rating <text> does the same to the cell join:
// the number renders under a DIFFERENT coupler while x,y still say otherwise.
//
// This is the same sin as the entity bug _decodeEntities was fixed for, in
// geometry instead of text: A GUARD THAT READS THE DOCUMENT DIFFERENTLY THAN THE
// RENDERER DOES IS READING A DIFFERENT DOCUMENT THAN THE USER.
//
// The fix is NOT to ban transforms -- 69 of them are load-bearing and legitimate
// (every connector face is composed inside a translated <g>; the "Watts" axis
// title is a rotated <text>). The fix is to REFUSE TO MEASURE a transformed
// element. Each parser records whether an element -- or ANY ancestor <g> --
// carries a transform, and every join and every geometry assertion below rejects
// a transformed element loudly. An element nobody measures may be transformed
// freely; an element the guard's verdict depends on may not.

/// A `<text>` with its position. [tf] is true when this element, or any ancestor
/// `<g>`, carries a `transform` -- i.e. when its drawn position is NOT the x,y
/// parsed here, and no assertion may be built on it.
class _T {
  const _T(this.x, this.y, this.s, {this.tf = false});
  final double x;
  final double y;
  final String s;
  final bool tf;
}

/// A `<rect>` with its position. [tf] as above.
class _R {
  const _R(this.x, this.y, this.w, this.h, {this.tf = false});
  final double x;
  final double y;
  final double w;
  final double h;
  final bool tf;
  double get cx => x + w / 2;
}

/// Refuse to measure a transformed element. Called at every point of USE, which
/// is what lets the 69 legitimate transforms stand: the composed connector faces
/// and the rotated axis titles are never selected by a join, so they are never
/// refused. Only an element the verdict RESTS on has to be honest about where it
/// is drawn.
void _refuseTransformed(bool tf, String what, String slug) {
  if (tf) {
    fail('$slug: the guard was about to measure $what, but that element (or an '
        'ancestor <g>) carries a `transform`. Its RENDERED position is not the '
        'x/y/width/height written on it, so every assertion built on those '
        'numbers would be about a drawing nobody sees. This is how the poe '
        'baseline pin was defeated the day it was written: '
        'transform="translate(0,-25)" floats the bar off the baseline while '
        'y+height still reads exactly 120. Draw it where it goes, or the guard '
        'cannot vouch for it.');
  }
}

String _body(String slug) => File('$_kGraphicsDir/$slug.svg')
    .readAsStringSync()
    .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

double? _attr(String tag, String name) {
  final RegExpMatch? m =
      RegExp('(?:^|\\s)$name\\s*=\\s*"([\\d.-]+)"').firstMatch(tag);
  return m == null ? null : double.tryParse(m.group(1)!);
}

/// Every positioned `<text>` in [slug], each tagged with whether it -- or any
/// ancestor `<g>` -- carries a `transform`.
List<_T> _positionedTexts(String slug) {
  final List<_T> out = <_T>[];
  final List<bool> gtf = <bool>[]; // the <g> transform stack
  final RegExp tok =
      RegExp(r'<g\b([^>]*)>|</g>|<text\b([^>]*)>(.*?)</text>', dotAll: true);
  for (final RegExpMatch m in tok.allMatches(_body(slug))) {
    final String tag = m.group(0)!;
    if (tag.startsWith('</g')) {
      if (gtf.isNotEmpty) gtf.removeLast();
      continue;
    }
    if (tag.startsWith('<g')) {
      gtf.add(_attrStr(m.group(1)!, 'transform').isNotEmpty);
      continue;
    }
    final String a = m.group(2)!;
    final double? x = _attr(a, 'x');
    final double? y = _attr(a, 'y');
    final String s = _decodeEntities(m.group(3)!);
    if (x == null || y == null || s.isEmpty) continue;
    final bool tf =
        _attrStr(a, 'transform').isNotEmpty || gtf.any((bool b) => b);
    out.add(_T(x, y, s, tf: tf));
  }
  return out;
}

/// Every positioned `<rect>` in [slug], tagged as above.
List<_R> _positionedRects(String slug) {
  final List<_R> out = <_R>[];
  final List<bool> gtf = <bool>[];
  final RegExp tok = RegExp(r'<g\b([^>]*)>|</g>|<rect\b([^>]*?)/?>');
  for (final RegExpMatch m in tok.allMatches(_body(slug))) {
    final String tag = m.group(0)!;
    if (tag.startsWith('</g')) {
      if (gtf.isNotEmpty) gtf.removeLast();
      continue;
    }
    if (tag.startsWith('<g')) {
      gtf.add(_attrStr(m.group(1)!, 'transform').isNotEmpty);
      continue;
    }
    final String a = m.group(2)!;
    // NOTE the leading (?:^|\s) in _attr: without it, `width` also matches
    // STROKE-width, which once made every rect look 1.5px wide.
    final double? x = _attr(a, 'x');
    final double? y = _attr(a, 'y');
    final double? w = _attr(a, 'width');
    final double? h = _attr(a, 'height');
    if (x == null || y == null || w == null || h == null) continue;
    final bool tf =
        _attrStr(a, 'transform').isNotEmpty || gtf.any((bool b) => b);
    out.add(_R(x, y, w, h, tf: tf));
  }
  return out;
}

/// The single text sharing [cx]'s column (within [tol]) and satisfying [where].
/// Throws if zero or more than one matches, which is itself the finding: a label
/// with no value, or a column so crowded the binding is ambiguous.
_T _inColumn(List<_T> texts, double cx, bool Function(_T) where,
    {double tol = 6, String slug = 'graphic'}) {
  final List<_T> hits = texts
      .where((_T t) => (t.x - cx).abs() <= tol && where(t))
      .toList();
  if (hits.length != 1) {
    fail('Expected exactly ONE text in the column at x=$cx, found '
        '${hits.length}: ${hits.map((_T t) => t.s).toList()}. A drawing binds a '
        'label to its value by POSITION; an ambiguous column has no binding.');
  }
  // The column join is only a binding if x is where the text is actually DRAWN.
  _refuseTransformed(hits.single.tf, 'the text "${hits.single.s}" at x=$cx', slug);
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
  const _L(this.x1, this.y1, this.x2, this.y2, this.stroke, {this.tf = false});
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final String stroke;
  final bool tf;
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
  final List<bool> groupTf = <bool>[];
  final RegExp tok = RegExp(r'<g\b([^>]*)>|</g>|<line\b([^>]*?)/?>');
  for (final RegExpMatch m in tok.allMatches(_body(slug))) {
    final String tag = m.group(0)!;
    if (tag.startsWith('</g')) {
      if (groupStroke.isNotEmpty) groupStroke.removeLast();
      if (groupTf.isNotEmpty) groupTf.removeLast();
      continue;
    }
    if (tag.startsWith('<g')) {
      groupStroke.add(_attrStr(m.group(1)!, 'stroke'));
      groupTf.add(_attrStr(m.group(1)!, 'transform').isNotEmpty);
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
    final bool tf =
        _attrStr(a, 'transform').isNotEmpty || groupTf.any((bool b) => b);
    out.add(_L(x1, y1, x2, y2, stroke, tf: tf));
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
    {double xTol = 3, double yBelow = 90, String slug = 'graphic'}) {
  final List<_T> hits = texts
      .where((_T t) =>
          (t.x - id.x).abs() <= xTol &&
          t.y > id.y &&
          (t.y - id.y) <= yBelow &&
          rating.hasMatch(t.s))
      .toList();
  if (hits.length != 1) return null;
  // The CELL is the binding. A transform on either half of it -- the identifier
  // or the rating -- renders them into different cells than the ones the guard
  // just joined, and the guard would be certifying a drawing nobody sees.
  _refuseTransformed(id.tf, 'the identifier "${id.s}"', slug);
  _refuseTransformed(
      hits.single.tf, 'the rating "${hits.single.s}" under "${id.s}"', slug);
  return hits.single;
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
      if (_cellRating(texts, t, rating, slug: slug) != null) t,
  ];
  if (found.isEmpty) return null; // not an entry on this graphic
  if (found.length > 1) {
    fail('$slug draws "$id" as ${found.length} separate rated entries. One '
        'dataset row cannot have two ratings in one drawing.');
  }
  return _cellRating(texts, found.single, rating, slug: slug);
}

// ══ THE TWO RULES THIS FILE FAILED, NOW MECHANICAL ═════════════════════════
//
// Vera attacked this guard on 2026-07-14 by trying to BUILD THE ARTIFACT IT
// FORBIDS -- a lying drawing -- and got three lies past it, on a full suite that
// read 4,178/4,178. Not one of the three was a bug in a check. All three were
// bugs in the SHAPE of the checks. Two rules came out of it, and they are
// written here as CODE rather than as advice, because a rule expressed as a
// comment is a rule the next maker may sincerely believe they have followed.
// The docstring that used to sit on _expectNoOrphanRatings said exactly the
// right thing (line 415: "[loose] MUST be broader than the pattern the join
// uses") and the code under it did exactly the wrong thing: the two patterns
// were BYTE-FOR-BYTE IDENTICAL. A warning that cannot fail is a comment.

/// RULE 1 (GL-013, 2026-07-14): **EVERY GUARD THAT ITERATES MUST FIRST ASSERT IT
/// FOUND SOMETHING TO ITERATE.**
///
/// Vera set "Rated 99 A" on all five IEC couplers the overview draws. Every row
/// then failed to parse, every row was skipped by `continue`, `bad` stayed
/// empty, and the orphan audit compared 0 to 0. The test literally named
/// "draws each coupler's REAL current rating" PASSED -- while checking ZERO
/// couplers. A loop over an empty list proves nothing, and reports that nothing
/// in green.
///
/// [atLeast] is the count observed on the known-good drawing, so this also fires
/// when a row is silently DROPPED, not only when all of them are. Adding rows is
/// free; losing one is a reviewed act.
void _expectChecked(int checked, int atLeast, String what, String where) {
  expect(checked, greaterThanOrEqualTo(atLeast),
      reason: 'VACUOUS GUARD in $where: it checked $checked $what, but the '
          'known-good drawing has $atLeast. This test was about to PASS while '
          'verifying less than it claims -- possibly nothing at all. Either a '
          'row lost its rating, or a rating is drawn in a format the join no '
          'longer parses (and was therefore skipped in silence). Both are '
          'findings. A guard that iterates must first prove it has something to '
          'iterate.');
}

/// RULE 2 (GL-013, 2026-07-14): **AN AUDIT MUST USE A STRICTLY LOOSER PATTERN
/// THAN THE CHECK IT AUDITS -- LOOSER IN EVERY DIMENSION, INCLUDING THE ANCHOR.**
/// If the audit can be defeated by the same input as the check, it is not an
/// audit. It is a second copy of the check, and it is blind in exactly the
/// places the check is blind.
///
/// This is the defect that let Vera fabricate an electrical rating. The IEC join
/// and its orphan audit were the same pattern, `^[\d.]+\s*A\s*·`, to the byte.
/// She drew C13/C14 -- a 10 A coupler -- as "Rated 16 A". The leading word
/// defeats the `^` anchor, so the join SKIPPED the row; and because the audit
/// was the same pattern, the audit did not COUNT the row either. Skipped by the
/// check, uncounted by the audit, `expect(0, 0)`, green. A fabricated electrical
/// rating shipped through a guard built to stop fabricated electrical ratings.
///
/// The previous round "fixed" the sibling bug (`10&#8211;16 A`) by loosening the
/// audit's TAIL and never touching its ANCHOR -- which is why the anchor check
/// below is explicit and separate. Loosening one dimension is not loosening.
///
/// HONEST LIMIT: regex containment is not decidable in general, so [corpus] is
/// an empirical witness, not a proof. It is seeded with every format that has
/// ever beaten this guard, plus the ones Vera used. It shrinks the hole; it does
/// not prove there is none. Add to it every time a new format gets past.
void _expectAuditStrictlyLooser(
    RegExp join, RegExp audit, List<String> corpus, String label) {
  // (a) MECHANICAL: the audit may not be anchored. The anchor is a dimension of
  //     strictness, and it is the dimension the last fix forgot.
  expect(audit.pattern.contains('^'), isFalse,
      reason: '$label: the ORPHAN AUDIT pattern `${audit.pattern}` is '
          '`^`-ANCHORED. An anchored audit cannot see a rating that is drawn '
          'with anything in front of it -- which is exactly how "Rated 16 A" '
          'passed as a 10 A coupler. The audit must be anchor-free.');
  expect(audit.pattern.contains(r'$'), isFalse,
      reason: '$label: the ORPHAN AUDIT pattern `${audit.pattern}` is '
          '`\$`-ANCHORED. Same defect, other end.');

  // (b) The audit is not literally the check wearing a different name.
  expect(audit.pattern == join.pattern, isFalse,
      reason: '$label: the join pattern and the orphan-audit pattern are '
          'IDENTICAL (`${join.pattern}`). This is not an audit. It is a second '
          'copy of the check, blind in precisely the places the check is blind, '
          'and it will report `expect(0, 0)` over every rating it cannot read.');

  // (c) CONTAINMENT: everything the join accepts, the audit must also accept.
  //     Otherwise a row could be joined-and-compared but never counted, and the
  //     orphan arithmetic would be nonsense.
  for (final String s in corpus) {
    if (join.hasMatch(s)) {
      expect(audit.hasMatch(s), isTrue,
          reason: '$label: the join ACCEPTS "$s" but the audit is BLIND to it. '
              'The audit must be a superset of the check, or the counts it '
              'compares are counting different things.');
    }
  }

  // (d) STRICTNESS: the audit must catch at least one thing the join does not.
  //     A "looser" pattern that accepts exactly the same language is the same
  //     net with a new label.
  expect(
      corpus.any((String s) => audit.hasMatch(s) && !join.hasMatch(s)), isTrue,
      reason: '$label: no string in the corpus is caught by the audit but '
          'missed by the join. The audit is not STRICTLY looser -- it is the '
          'same net. Every format that has ever beaten this guard is in that '
          'corpus; if the audit catches none of them, it audits nothing.');
}

/// Every rating text in [slug] must be consumed by exactly one dataset row.
///
/// Without this, a graphic could DROP an entry's rating (the row is skipped, the
/// loop finds nothing, and the test passes over it in silence) or carry an
/// ORPHAN rating belonging to no row at all. Counting both ends closes the
/// "guard that checks nothing" hole from the other side.
///
/// [audit] MUST be strictly looser than the pattern the join uses -- and that is
/// no longer a request in a docstring, which is what it was when it failed. It
/// is checked, mechanically, by [_expectAuditStrictlyLooser], which every caller
/// invokes before it trusts this arithmetic.
void _expectNoOrphanRatings(
    List<_T> texts, RegExp audit, int joined, String slug) {
  final List<String> drawn =
      texts.where((_T t) => audit.hasMatch(t.s)).map((_T t) => t.s).toList();
  expect(joined, drawn.length,
      reason: '$slug draws ${drawn.length} rating texts but only $joined were '
          'matched to a dataset row. Either an entry is missing its rating, a '
          'rating is drawn for something not in the dataset, or one is drawn in '
          'a format the join does not parse. All three are findings: an '
          'unconsumed number is a number nobody is checking.\nDrawn: $drawn');
}

// ══ THE RATING PATTERNS, PAIRED AND PROVEN ═════════════════════════════════
//
// Each graphic gets TWO patterns and they are declared TOGETHER, so that the
// asymmetry between them is visible in one screenful instead of 16 lines apart
// (which is how they drifted into being identical).
//
//   join  -- strict. It must PARSE, so it may demand a canonical format.
//   audit -- loose. It only has to RECOGNIZE "this text states a rating", so it
//            demands as little as possible. Anchor-free, whitespace-tolerant.
//
// The join is deliberately whitespace-tolerant now too: Vera's NEMA attack drew
// a 15 A receptacle as "125 V · 50A" -- one extra space before the V -- and the
// old join `^\d+(?:/\d+)?V` could not read it, so the wrong number was never
// compared to anything. A format the join cannot read is a number nobody checks.

/// IEC: "10 A · 70 °C · 3-pin".
final RegExp _iecJoin = RegExp(r'^\s*([\d.]+)\s*A\s*·');

/// IEC audit: any text stating an ampere figure, ANYWHERE in it, in any spacing.
/// Catches "Rated 16 A", "16A", "10-16 A" -- all of which the join misses.
final RegExp _iecAudit = RegExp(r'\d\s*A\b');

/// NEMA: "125V · 15A · 1Ø" (and "125/250V · 30A").
final RegExp _nemaJoin = RegExp(r'^\s*(\d+(?:/\d+)?)\s*V\s*·\s*(\d+)\s*A');

/// NEMA audit: any text stating a volt figure followed by the rating separator.
/// The separator is what distinguishes a RATING CELL from the prose footnote,
/// which says "...(4P/5W, 120/208V)." in passing and is not a claim about any
/// one device. Anchor-free, so "Rated 125V · 50A" is still counted.
final RegExp _nemaAudit = RegExp(r'\d\s*V\s*·');

/// International plugs: "230 V · 13 A fused", "230 V · 10 / 16 A".
final RegExp _plugJoin =
    RegExp(r'^\s*(\d+)\s*V\s*·\s*([\d.\s/-]*[\d.])\s*A(?:\s+fused)?\s*$');

/// Plug audit: same shape as NEMA's, and for the same reason.
final RegExp _plugAudit = RegExp(r'\d\s*V\s*·');

/// The formats that have ever beaten this guard, plus the ones Vera used, plus
/// the canonical ones. Any audit pattern must see ALL of the rating-shaped
/// strings here; the join is allowed to read only the canonical ones.
const List<String> _ampCorpus = <String>[
  '10 A · 70 °C · 3-pin', // canonical -- join reads it
  '2.5 A · 70 °C · 2-pin', // canonical, decimal
  '16 A · 70 °C · 3-pin', // canonical
  'Rated 16 A · 70 °C · 3-pin', // VERA: fabricated C13/C14 rating. Join is blind.
  'Rated 99 A · 70 °C · 3-pin', // VERA: the vacuous-assertion attack.
  '10-16 A', // the 2026-07-13 entity bug, decoded.
  '16A', // no space at all.
];

const List<String> _voltCorpus = <String>[
  '125V · 15A · 1Ø', // canonical NEMA -- join reads it
  '125/250V · 30A', // canonical NEMA, dual voltage
  '230 V · 13 A fused', // canonical plug -- join reads it
  '230 V · 10 / 16 A', // canonical plug, dual rating
  '125 V · 50A · 1Ø', // VERA: the space before the V. Old join was blind.
  'Rated 125V · 50A', // leading word defeats any `^` anchor.
];

/// The vertices of every `<path>` polyline in [slug] with at least [minPoints]
/// points -- i.e. the WAVEFORMS, not the 3-point arrowheads or the sigma glyph.
List<List<double>> _waveformYs(String slug, {int minPoints = 50}) {
  final List<List<double>> waves = <List<double>>[];
  final List<bool> groupTf = <bool>[];
  final RegExp tok = RegExp(r'<g\b([^>]*)>|</g>|<path\b([^>]*?)/?>');
  for (final RegExpMatch m in tok.allMatches(_body(slug))) {
    final String tag = m.group(0)!;
    if (tag.startsWith('</g')) {
      if (groupTf.isNotEmpty) groupTf.removeLast();
      continue;
    }
    if (tag.startsWith('<g')) {
      groupTf.add(_attrStr(m.group(1)!, 'transform').isNotEmpty);
      continue;
    }
    final String a = m.group(2)!;
    final String d = _attrStr(a, 'd');
    if (d.isEmpty) continue;
    // Every coordinate pair after an M/L command.
    final List<double> ys = RegExp(r'[ML]\s*(-?[\d.]+)[\s,]+(-?[\d.]+)')
        .allMatches(d)
        .map((RegExpMatch m) => double.parse(m.group(2)!))
        .toList();
    if (ys.length < minPoints) continue;
    // The waveform's crest IS the peak claim. A transformed sine crests
    // somewhere other than where its `d` says, and every volt derived from it
    // would be fiction.
    _refuseTransformed(
        _attrStr(a, 'transform').isNotEmpty || groupTf.any((bool b) => b),
        'a waveform <path>', slug);
    waves.add(ys);
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
    test('the guard can SEE the graphics directory at all', () {
      // RULE 1. Every test in this group iterates _allGraphicSlugs(). If that
      // glob ever returns empty -- a moved directory, a renamed extension, a
      // test run from the wrong cwd -- then EVERY list comprehension below
      // yields [], every `expect(..., isEmpty)` passes, and this entire file
      // reports green while reading nothing. The classification guard would be
      // the first thing to go quietly blind, and nothing downstream would know.
      _expectChecked(_allGraphicSlugs().length, 110, 'SVG files',
          'the graphics directory glob');
    });

    test('each SVG is either data-bearing or on the documented illustrative list',
        () {
      final List<String> unclassified = <String>[
        for (final String slug in _allGraphicSlugs())
          if (!_dataBearing.containsKey(slug) &&
              !_dataBearingUnguarded.containsKey(slug) &&
              !_illustrative.containsKey(slug) &&
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
                _illustrative.containsKey(s),
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

    test('the EXEMPTION list does not silently grow either', () {
      // VERA MEDIUM-2. The debt list -- the one that CONFESSES ("nobody is
      // checking these") -- was pinned. The exemption list -- the one that
      // ALIBIS ("there is nothing here to check"), and which had been FALSE for
      // 19 of its 78 entries -- was not pinned at all.
      //
      // So the cheapest path for a maker under pressure was: mint a fresh
      // exemption (free, unbounded), or relieve the pinned debt list by MOVING
      // an entry into the unpinned one. The confession was pinned and the alibi
      // was left open. That is backwards: the list that ASSERTS A CLAIM needs
      // the tighter bound, because it is the one that can be WRONG.
      //
      // 57 is the post-audit count: 59, minus bend-radius-arc-vs-kink and
      // rack-cage-nut, both of which turned out to state tabulated data.
      expect(_illustrative.length, lessThanOrEqualTo(57),
          reason: 'A graphic was added to the ILLUSTRATIVE exemption list. That '
              'list asserts "this graphic states no number any screen '
              'tabulates" -- a CLAIM, and one that has been wrong 19 times '
              'before. The maker may not mint its own exemption (GL-003 §0). '
              'Guard the graphic, declare it as debt, or take the exemption to '
              'Keith. Moving the pin is a reviewed act.');
    });

    test('every exemption states a ground the criterion actually allows', () {
      // An exemption must be CLAIMED UNDER A RULE, not asserted. The _Exempt
      // enum makes the ground un-omittable (the map will not compile without
      // one) and un-inventable (only the four grounds the criterion allows
      // exist). This test is what keeps that true as the enum evolves: a fifth,
      // vaguer ground cannot be quietly added and then used.
      const Set<_Exempt> allowed = <_Exempt>{
        _Exempt.mechanism,
        _Exempt.formula,
        _Exempt.sequence,
        _Exempt.constant,
      };
      expect(_Exempt.values.toSet(), allowed,
          reason: 'A new exemption GROUND was added to the _Exempt enum. The '
              'four grounds are the criterion, and the criterion is reviewed '
              '(GL-003 §0). Widening the grounds is how "illustrative" became '
              'false for 19 of 78 entries the last time.');
      final List<String> groundless = <String>[
        for (final MapEntry<String, _Exempt> e in _illustrative.entries)
          if (!allowed.contains(e.value)) e.key,
      ];
      expect(groundless, isEmpty, reason: 'Exempt on no stated ground: $groundless');
      _expectChecked(_illustrative.length, 50, 'exemptions',
          'the exemption-ground check');
    });

    test('an exempt graphic may not have a GUARDED sibling in the same data file',
        () {
      // VERA MEDIUM-1, generalized -- and this is the part of her finding with
      // teeth. bend-radius-arc-vs-kink was EXEMPT while pull-tension-gauge was
      // declared DEBT. Same declaring file (lib/data/bend_diagrams.dart:47
      // and :51), same screen, same TIA-568 table. One file, two graphics, two
      // opposite verdicts about whether the screen tabulates their numbers. Both
      // cannot be right, and the split is mechanically visible -- so check it,
      // instead of relying on whoever adds the next graphic to notice.
      //
      // Running this at the time of her report found TWO, not one:
      //   bend_diagrams.dart : bend-radius-arc-vs-kink (exempt) / pull-tension-gauge (debt)
      //   rack_diagrams.dart : rack-cage-nut (exempt)          / rack-1u-dimension (debt)
      // Both exempt siblings did state tabulated data. Both are now guarded.
      //
      // This is not a claim that siblings must ALWAYS share a class. It is a
      // claim that a split is a REVIEWED act, not a silent one: if a genuine
      // split ever arises, it goes to Keith (GL-003 §0), like every other
      // exemption. The maker does not get to settle it alone -- which is the
      // whole point.
      final RegExp decl = RegExp(r"=\s*'([a-z0-9][a-z0-9-]+)'\s*;");
      final Set<String> present = _allGraphicSlugs().toSet();
      final List<String> splits = <String>[];
      int filesScanned = 0;

      for (final FileSystemEntity e in Directory('lib/data').listSync()) {
        if (e is! File || !e.path.endsWith('_diagrams.dart')) continue;
        final List<String> slugs = decl
            .allMatches(e.readAsStringSync())
            .map((RegExpMatch m) => m.group(1)!)
            .where(present.contains)
            .toSet()
            .toList()
          ..sort();
        if (slugs.isEmpty) continue;
        filesScanned++;

        final List<String> exempt =
            slugs.where(_illustrative.containsKey).toList();
        final List<String> checked = slugs
            .where((String s) =>
                _dataBearing.containsKey(s) ||
                _dataBearingUnguarded.containsKey(s))
            .toList();
        if (exempt.isNotEmpty && checked.isNotEmpty) {
          splits.add('${e.uri.pathSegments.last}: EXEMPT $exempt vs '
              'DATA-BEARING/DEBT $checked');
        }
      }

      _expectChecked(filesScanned, 10, 'diagram-declaration files',
          'the sibling-classification check');
      expect(splits, isEmpty,
          reason: 'A graphic is EXEMPT while a sibling declared in the SAME '
              'lib/data file -- same screen, same source table -- is treated as '
              'data-bearing. One of the two verdicts is wrong, and the exempt '
              'one is the one that gets no checking. Resolve it, or take the '
              'split to Keith:\n${splits.join('\n')}');
    });

    test('neither exemption list has stale entries', () {
      final Set<String> present = _allGraphicSlugs().toSet();
      final List<String> stale = <String>[
        ..._illustrative.keys,
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
      int checked = 0;
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
        checked++;
        final String v = '${m.group(1)}V';
        final int a = int.parse(m.group(2)!);
        if (v != d.voltage || a != d.amps) {
          bad.add('$slug (${d.type}): graphic says $v/${a}A, dataset says '
              '${d.voltage}/${d.amps}A');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
      // RULE 1: this loop `continue`s past any row whose asset is missing or
      // whose rating will not parse. Without the pin, deleting every face SVG
      // would make it iterate nothing and pass.
      _expectChecked(checked, 21, 'NEMA faces', 'the NEMA face guard');
    });
  });

  // ══ 3b. IEC couplers ═════════════════════════════════════════════════════
  group('IEC coupler faces agree with IecConnectorsScreen', () {
    test('every IEC face draws its dataset row\'s current rating', () {
      final List<String> bad = <String>[];
      int checked = 0;
      for (final IecCoupler c in IecConnectorsScreen.couplers) {
        final String? slug = c.assetName;
        if (slug == null || !File('$_kGraphicsDir/$slug.svg').existsSync()) {
          continue;
        }
        final RegExpMatch? m =
            RegExp(r'([\d.]+)\s*A').firstMatch(_flat(slug));
        expect(m, isNotNull, reason: '$slug draws no current rating.');
        checked++;
        final String drawn = '${m!.group(1)} A';
        if (drawn != c.current) {
          bad.add('$slug (${c.pair}): graphic says $drawn, dataset says '
              '${c.current}');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
      _expectChecked(checked, 6, 'IEC faces', 'the IEC face guard');
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
      int checked = 0;
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
        checked++;
        final String v = '${m.group(1)}V';
        final String a = '${m.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim()}A';
        final String expectA = p.current.replaceAll(' (fused)', '');
        if (v != p.voltageClass || a.replaceAll(' ', '') != expectA.replaceAll(' ', '')) {
          bad.add('$slug (Type ${p.type}): graphic says $v / $a, dataset says '
              '${p.voltageClass} / ${p.current}');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
      _expectChecked(checked, 13, 'plug faces', 'the plug face guard');
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
        _refuseTransformed(wall.tf, 'the wall at x=${wall.x}', 'rf-attenuation');
        // The value above the wall (e.g. "-3 dB") and the material label below
        // it. Exactly one of each in this column, or the binding is ambiguous
        // and _inColumn fails loudly -- which is itself the finding.
        final _T value = _inColumn(texts, wall.cx,
            (_T t) => RegExp(r'^-\d+\s*dB$').hasMatch(t.s),
            slug: 'rf-attenuation');
        final _T label = _inColumn(
            texts, wall.cx, (_T t) => !RegExp(r'\d').hasMatch(t.s),
            slug: 'rf-attenuation');

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
    test('each 20 MHz CELL carries ITS OWN channel number, in order', () {
      // SET MEMBERSHIP, THE LAST HOLDOUT. Until 2026-07-14 this test asked, for
      // each expected channel, "does this number appear SOMEWHERE in the flat
      // text?" -- and nothing else. That is the exact disease the rest of this
      // file was written to kill: it is "is the number in the FILE?", the check
      // that PASSED the -12 dB concrete bug and PASSED Vera's drywall/concrete
      // swap. It survived here because the numbers looked like an innocent list.
      //
      // I found it by attacking my own fix: SWAP the labels on channels 44 and
      // 48. Both numbers are still present, so every `hasMatch` still passed --
      // and the drawing now puts channel 44 on 48's frequency. A channel map
      // whose channels are on the wrong cells is worse than no channel map.
      // GREEN, on the fixed guard, until this test was rewritten.
      //
      // A drawing has no rows. Join by POSITION: each 20 MHz cell owns the
      // number printed in ITS column, and the cells read left to right in
      // frequency order. A permutation now changes the SEQUENCE, and a sequence
      // is something a guard can actually compare.
      final List<_T> texts = _positionedTexts('channel-map');
      final List<_R> rects = _positionedRects('channel-map');
      expect(rects, isNotEmpty, reason: 'channel-map.svg draws no <rect> cells.');

      // The 20 MHz cells are the narrowest rects (the 40/80/160 blocks are
      // multiples of them).
      final double cellW = rects.map((_R r) => r.w).reduce(math.min);
      final List<_R> cells = rects
          .where((_R r) => (r.w - cellW).abs() < 0.5)
          .toList()
        ..sort((_R a, _R b) => a.cx.compareTo(b.cx));

      final BondedBlock b160 = ChannelMapScreen.map5_160
          .firstWhere((BondedBlock b) => b.lowChannel == 36);
      final List<int> expected = <int>[
        for (int c = b160.lowChannel; c <= b160.highChannel; c += 4) c,
      ];
      expect(expected.length, 8,
          reason: 'A 160 MHz bond spans EIGHT 20 MHz channels '
              '(channel_map_screen.dart:103 -- "160->8").');
      _expectChecked(cells.length, 8, '20 MHz cells', 'the channel-map guard');

      final List<int> drawn = <int>[];
      for (final _R cell in cells) {
        _refuseTransformed(
            cell.tf, 'the 20 MHz cell at x=${cell.x}', 'channel-map');
        final _T label = _inColumn(
            texts, cell.cx, (_T t) => RegExp(r'^\d+$').hasMatch(t.s),
            slug: 'channel-map');
        drawn.add(int.parse(label.s));
      }

      expect(drawn, expected,
          reason: 'The 20 MHz cells, read left to right, carry channels $drawn. '
              'The 160 MHz bond at ch ${b160.lowChannel}-${b160.highChannel} is '
              '$expected. Every number may well be PRESENT -- that is what the '
              'old set-membership check tested, and a swapped pair walked '
              'straight through it. A channel drawn on the wrong cell is on the '
              'wrong FREQUENCY, and the reader plans a network around it.');
    });

    test('160 MHz is drawn over EIGHT 20 MHz cells, not four', () {
      // THE BUG: the old drawing put a "160 MHz" span across the SAME pixel
      // extent as its own 80 MHz block. Read the boxes, not the words.
      final List<_R> rects = _positionedRects('channel-map');
      expect(rects, isNotEmpty, reason: 'channel-map.svg draws no <rect> cells.');
      for (final _R r in rects) {
        _refuseTransformed(r.tf, 'the block at x=${r.x}', 'channel-map');
      }
      // NOTE _positionedRects' _attr uses a leading (?:^|\s): without it,
      // `width` also matches STROKE-width, which made every rect look 1.5px wide
      // and the ratio a perfect 1.00. A guard that measures the wrong thing
      // reports a tidy number and proves nothing.
      final List<double> widths = rects.map((_R r) => r.w).toList();
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
    // RULE 1, in its nastiest form. This group does not LOOP over the dataset
    // inside a test -- it GENERATES a test per dataset row. So if topologies
    // were ever empty, this group would emit ZERO TESTS, and zero tests do not
    // fail. They do not even appear. The suite total would drop from 18 to 15
    // and read "All tests passed", and no assertion anywhere would have run
    // against any waveform. A vacuous loop at least reports green; a vacuous
    // GENERATOR reports nothing at all, which is worse -- there is no test to
    // point at and ask what it checked.
    test('the topology dataset is not empty (or the tests below do not exist)',
        () {
      _expectChecked(PowerPhasingScreen.topologies.length, 3, 'topologies',
          'the power-phasing test GENERATOR');
    });

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
        for (final _L tick in ticks) {
          _refuseTransformed(tick.tf, 'the axis tick at y=${tick.y1}', slug);
        }

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
          _refuseTransformed(
              near.single.tf, 'the axis label "${near.single.s}"', slug);
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
        for (final _L l in lime) {
          _refuseTransformed(l.tf, 'the lime measurand line', slug);
        }

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
    test('the orphan audits are STRICTLY LOOSER than the joins they audit', () {
      // RULE 2, made mechanical. This test is the one that would have stopped
      // Vera's fabricated 16 A rating -- not by reading any SVG, but by refusing
      // to let the audit be a copy of the check. It runs first, and everything
      // below depends on it: the orphan arithmetic in the three tests that
      // follow is only meaningful if the audit can see strictly more than the
      // join can read.
      _expectAuditStrictlyLooser(_iecJoin, _iecAudit, _ampCorpus, 'iec-connectors');
      _expectAuditStrictlyLooser(
          _nemaJoin, _nemaAudit, _voltCorpus, 'nema-connectors');
      _expectAuditStrictlyLooser(
          _plugJoin, _plugAudit, _voltCorpus, 'international-plugs');
    });

    test('nema-connectors.svg draws each device\'s real voltage and amps', () {
      final List<_T> texts = _positionedTexts('nema-connectors');
      final List<String> bad = <String>[];
      final Set<String> consumed = <String>{};
      for (final NemaDevice d in <NemaDevice>[
        ...NemaConnectorsScreen.group125v,
        ...NemaConnectorsScreen.group208v,
        ...NemaConnectorsScreen.groupCalifornia,
      ]) {
        final _T? rating =
            _entryRating(texts, d.type, _nemaJoin, 'nema-connectors');
        if (rating == null) continue; // not drawn on the overview
        consumed.add('${rating.x},${rating.y}');
        final RegExpMatch m = _nemaJoin.firstMatch(rating.s)!;
        if ('${m.group(1)}V' != d.voltage || int.parse(m.group(2)!) != d.amps) {
          bad.add('NEMA ${d.type}: overview draws "${rating.s}", dataset says '
              '${d.voltage} / ${d.amps}A');
        }
      }
      expect(bad.toSet().toList(), isEmpty, reason: bad.toSet().join('\n'));
      // RULE 1: the overview draws 11 rated devices. If a rating is retyped into
      // a format the join cannot read, this row is `continue`d past -- and the
      // pin, not the orphan count, is what makes that silence audible.
      _expectChecked(consumed.length, 11, 'NEMA devices',
          'the nema-connectors overview guard');
      _expectNoOrphanRatings(
          texts, _nemaAudit, consumed.length, 'nema-connectors');
    });

    test('iec-connectors.svg draws each coupler\'s real current rating', () {
      // THE TEST VERA BROKE. Its name is a promise -- "draws each coupler's REAL
      // current rating" -- and on 2026-07-14 it kept that promise for ZERO
      // couplers, in green, twice over:
      //
      //   HIGH-1: C13/C14 (a 10 A coupler) drawn "Rated 16 A". The `^` anchor in
      //     the join could not read it, so the row was skipped -- and the orphan
      //     audit used the BYTE-IDENTICAL pattern, so it could not count the row
      //     either. Invisible at both ends. 18/18. 4,178/4,178.
      //   HIGH-2: all five drawn couplers set to "Rated 99 A". Every row skipped,
      //     `bad` empty, expect(0, 0). A fabricated rating on every single
      //     coupler, and the guard's verdict was PASS.
      //
      // Three things now stand between that and green, and they fail
      // independently: the audit is anchor-free (so it COUNTS what it cannot
      // parse), the join is whitespace-tolerant (so it PARSES more), and the
      // consumed count is PINNED (so a skipped row is a failure whatever the
      // reason).
      final List<_T> texts = _positionedTexts('iec-connectors');
      final List<String> bad = <String>[];
      final Set<String> consumed = <String>{};
      for (final IecCoupler c in IecConnectorsScreen.couplers) {
        final _T? rating =
            _entryRating(texts, c.pair, _iecJoin, 'iec-connectors');
        if (rating == null) continue;
        consumed.add('${rating.x},${rating.y}');
        final String drawn = '${_iecJoin.firstMatch(rating.s)!.group(1)} A';
        if (drawn != c.current) {
          bad.add('IEC ${c.pair}: overview draws "$drawn", dataset says '
              '"${c.current}"');
        }
      }
      expect(bad.toSet().toList(), isEmpty, reason: bad.toSet().join('\n'));
      // The overview draws FIVE of the six couplers (C1/C2 is not on it).
      _expectChecked(consumed.length, 5, 'IEC couplers',
          'the iec-connectors overview guard');
      _expectNoOrphanRatings(
          texts, _iecAudit, consumed.length, 'iec-connectors');
    });

    test('international-plugs.svg draws each plug\'s real voltage and current',
        () {
      final List<_T> texts = _positionedTexts('international-plugs');
      // Type G is drawn "230 V · 13 A fused" -- the dataset says "13A (fused)".
      // The qualifier is part of the rating, so the pattern must admit it rather
      // than silently failing to find the cell (which would skip the row).

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
        final _T? rating =
            _cellRating(texts, tile, _plugJoin, slug: 'international-plugs');
        if (rating == null) continue;
        consumed.add('${rating.x},${rating.y}');

        final RegExpMatch m = _plugJoin.firstMatch(rating.s)!;
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
      _expectChecked(consumed.length, 10, 'plug tiles',
          'the international-plugs overview guard');
      _expectNoOrphanRatings(
          texts, _plugAudit, consumed.length, 'international-plugs');
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
        // The bar's HEIGHT and its BASELINE are both claims. Neither means
        // anything if the rect is moved by a transform the parser cannot see.
        _refuseTransformed(bar.tf, 'the bar at x=${bar.x}', 'poe-reference');
        final _T std = _inColumn(
            texts, bar.cx, (_T t) => t.s.startsWith('802.3'),
            slug: 'poe-reference');
        final _T watts = _inColumn(
            texts, bar.cx, (_T t) => RegExp(r'^[\d.]+ W$').hasMatch(t.s),
            slug: 'poe-reference');

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
      _expectChecked(pxPerWatt.length, 3, 'PoE bars', 'the poe-reference guard');

      // ── GEOMETRY 1: ONE COMMON BASELINE ───────────────────────────────────
      //
      // VERA HIGH-3 (2026-07-14). The check below this one -- px/W uniformity --
      // was the only geometry this guard had, and it is not enough. Vera kept
      // EVERY bar height correct and EVERY label correct, and simply floated the
      // three bars to three different baselines. Green.
      //
      // Uniform px/W says the bars are mutually consistent in SCALE. It says
      // nothing about where they START. A bar's height only encodes a quantity
      // if the bar is measured from a shared origin; three bars hanging from
      // three different origins is not a bar chart, it is three unrelated
      // rectangles that happen to be the right size. The reader compares TOPS.
      //
      // Same principle as Vera's own rule about the sine crest: an axis makes
      // the geometry a claim. Here the axis is labelled "Watts" and runs
      // vertically, so the BASELINE is the zero of that axis -- and a zero that
      // moves per bar is not a zero.
      final List<double> bottoms =
          bars.map((_R b) => b.y + b.h).toList()..sort();
      expect(bottoms.last - bottoms.first, lessThan(0.01),
          reason: 'The bars do not share a baseline: their bottom edges are at '
              'y=${bottoms.map((double b) => b.toStringAsFixed(2)).toList()}. '
              'A bar chart encodes quantity as height ABOVE A COMMON ZERO. With '
              'the bars floated to different origins the heights encode nothing, '
              'and the reader -- who compares the TOPS of the bars -- is misled '
              'even though every printed number and every bar height is '
              'individually correct. (Vera kept all three labels and all three '
              'heights right, moved the baselines, and this guard stayed green.)');

      // ── GEOMETRY 2: ONE SCALE ─────────────────────────────────────────────
      // The check that reads the ARTWORK -- the labels were all individually
      // true while the picture understated 802.3bt by 40%.
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

  // ══ 3i. bend-radius-arc-vs-kink: the 14th data-bearing graphic ═══════════
  //
  // VERA MEDIUM-1. This graphic was on the ILLUSTRATIVE EXEMPTION LIST -- the
  // list that asserts "this states no number a screen tabulates". It draws
  // "R >= 4x OD". cable_bend_radius_screen.dart:142 tabulates
  // `limit: '>= 4x OD'`. Its SIBLING, pull-tension-gauge, is declared in the
  // same file (bend_diagrams.dart:47 and :51), drawn on the same screen, sourced
  // from the same TIA-568 table -- and was correctly declared as DEBT. One file,
  // two graphics, two opposite verdicts. That split is now a build failure (§2).
  group('bend-radius-arc-vs-kink.svg agrees with CableBendRadiusScreen', () {
    /// "R ≥ 4× OD" -> "R >= 4x OD". The typographic forms are what the reader
    /// sees; the ASCII forms are what the dataset stores. Compare like with like.
    String norm(String s) => s
        .replaceAll('≥', '>=')
        .replaceAll('≤', '<=')
        .replaceAll('×', 'x')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final RegExp limitRe =
        RegExp(r'(>=|<=|>|<)\s*(\d+)\s*x\s*OD', caseSensitive: false);

    test('the drawn bend limit is the limit of the dataset row it NAMES', () {
      final List<_T> texts = _positionedTexts('bend-radius-arc-vs-kink');
      _expectChecked(texts.length, 5, 'texts', 'the bend-radius guard');

      // The drawing names its own row: "installed, 4-pair UTP". Resolve THAT row
      // in the dataset and compare THAT row's limit -- the same label->value
      // discipline the rest of this file uses, not set membership over the file.
      final _T caption = texts.singleWhere(
          (_T t) => t.s.toLowerCase().contains('4-pair utp'),
          orElse: () => fail('The graphic no longer names which bend condition '
              'it depicts. An unlabelled "R >= 4x OD" is the "concrete" bug: it '
              'could be the installed limit (4x), the under-tension limit (8x), '
              'or the backbone limit (10x), and it answers no question.'));

      // The limit claim sits in the caption's own column. Geometry binds them.
      _refuseTransformed(caption.tf, 'the condition caption "${caption.s}"',
          'bend-radius-arc-vs-kink');
      final _T limit = _inColumn(
          texts, caption.x, (_T t) => limitRe.hasMatch(norm(t.s)),
          slug: 'bend-radius-arc-vs-kink');

      final List<BendLimit> rows = CableBendRadiusScreen.copperBend
          .where((BendLimit b) =>
              b.condition.toLowerCase().contains('installed') &&
              b.condition.toLowerCase().contains('4-pair'))
          .toList();
      expect(rows.length, 1,
          reason: 'The drawn caption "${caption.s}" must resolve to exactly ONE '
              'dataset row; it resolved to ${rows.length} '
              '(${rows.map((BendLimit b) => b.condition).toList()}).');

      final RegExpMatch drawn = limitRe.firstMatch(norm(limit.s))!;
      final RegExpMatch truth = limitRe.firstMatch(norm(rows.single.limit))!;
      expect('${drawn.group(1)} ${drawn.group(2)}x OD',
          '${truth.group(1)} ${truth.group(2)}x OD',
          reason: 'The graphic draws "${limit.s}" for the condition it names '
              '("${caption.s}"), but cable_bend_radius_screen.dart tabulates '
              '"${rows.single.limit}" for "${rows.single.condition}" '
              '(${rows.single.source}). The drawing and the table under it must '
              'state the same limit.');
    });

    test('the kink half uses the SAME multiplier it just declared the limit', () {
      // The drawing's two halves are one claim: "R >= 4x OD" is OK, "< 4x OD"
      // is a kink. If the halves ever disagree -- limit 4x, kink "< 8x OD" --
      // the graphic contradicts itself, and every number in it is still
      // individually findable in the dataset. Set membership cannot see that.
      final List<String> lims = _texts('bend-radius-arc-vs-kink')
          .map(norm)
          .where(limitRe.hasMatch)
          .toList();
      _expectChecked(lims.length, 2, 'limit claims', 'the bend-radius kink check');

      final Set<String> multipliers = lims
          .map((String s) => limitRe.firstMatch(s)!.group(2)!)
          .toSet();
      expect(multipliers.length, 1,
          reason: 'The graphic states its bend limit with more than one '
              'multiplier ($multipliers): $lims. The "OK" arc and the "kink" '
              'are the two sides of ONE threshold. Two multipliers means the '
              'drawing disagrees with itself about where the threshold is.');
    });
  });

  // ══ 3j. rack-cage-nut: the 15th, which the brief did not name ════════════
  //
  // Found by generalizing Vera MEDIUM-1 into the sibling check in §2 and running
  // it. rack-cage-nut was EXEMPT; its sibling rack-1u-dimension (same file,
  // rack_diagrams.dart; same screen) was declared DEBT. The exemption was false
  // by the same test as bend-radius: the graphic draws "10-32, 12-24, or M6",
  // and rack_units_screen.dart:236/242/248 tabulates exactly those three as the
  // `thread` column of RackUnitsScreen.threads.
  //
  // Cross-threading a rack rail destroys the rail. A drawing that named the
  // wrong thread set would be a real-world error, and nothing was checking it.
  group('rack-cage-nut.svg agrees with RackUnitsScreen.threads', () {
    test('the thread designations drawn are EXACTLY the dataset\'s, both ways',
        () {
      final String flat = _flat('rack-cage-nut');
      final Set<String> truth =
          RackUnitsScreen.threads.map((RackThread t) => t.thread).toSet();
      _expectChecked(truth.length, 3, 'dataset threads', 'the rack-cage-nut guard');

      // Both directions, and BOTH matter:
      //   drawn-but-not-tabulated -> the graphic invented a thread type;
      //   tabulated-but-not-drawn -> the graphic silently dropped one, and the
      //     tech packs two of the three cage nuts they need.
      final Set<String> drawn = RegExp(r'\b(\d+-\d+|M\d+)\b')
          .allMatches(flat)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      expect(drawn, truth,
          reason: 'rack-cage-nut.svg names thread designations $drawn; '
              'RackUnitsScreen.threads tabulates $truth. These must be the same '
              'set. A thread type drawn but not tabulated is invented; one '
              'tabulated but not drawn is silently dropped from the graphic a '
              'tech reads before buying cage nuts. 10-32, 12-24 and M6 are NOT '
              'interchangeable -- forcing the wrong one strips the rail.');
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
