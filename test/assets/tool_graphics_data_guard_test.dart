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
import 'package:wlan_pros_toolbox/screens/tools/reference/power_phasing_screen.dart';

const String _kGraphicsDir = 'assets/tool-graphics';

// ══ ILLUSTRATIVE: the documented exemption list ════════════════════════════
//
// These graphics depict a RELATIONSHIP, a FORMULA, or a SEQUENCE -- not a
// datum. They carry no threshold, band, rating, or constant that a screen also
// tabulates, so there is nothing for them to contradict. Notably `cable-loss`
// and `rain-fade` draw only the FORMULA (dB/m x L, dB/km x path) and no
// datasheet values, which is why the two worst findings of the 2026-07-11 audit
// never reached their graphics.
//
// This list is the exemption. Adding to it is a REVIEWED act, not a convenience:
// if a graphic starts stating a number that a screen also states, it comes OUT
// of this list and INTO the data-bearing registry.
const Set<String> _illustrative = <String>{
  // Pure formula / mechanism diagrams.
  'cable-loss', 'rain-fade', 'poe-budget', 'throughput-calc', 'capacity-planner',
  'noise-floor', 'fspl', 'eirp', 'link-budget', 'fresnel', 'ptp-link',
  'rf-attenuation-legacy',
  'wavelength', 'earth-curvature', 'downtilt', 'downtilt-coverage', 'dist-bearing',
  'midpoint', 'final-point', 'lat-long', 'metric-conversion', 'ohms-law-wheel',
  'db-reference', 'dbm-watt-converter', 'coax-cable',
  // Protocol / flow / sequence diagrams.
  'roaming', 'frame-exchange', 'eap-8021x-flow', 'arp-ndp', 'dns-lookup', 'whois',
  'ping', 'icmp-ping', 'ping-sweep', 'traceroute', 'mobile-traceroute', 'port-scan',
  'packet-sender', 'http-headers', 'ssl-inspect', 'wake-on-lan', 'bgp-asn',
  'mac-oui-lookup', 'mac-bit-field', 'ip-geo', 'interface-info', 'ipv4-subnet',
  'ipv6-subnet', 'dscp-qos', 'reason-codes', 'port-reference', 'spectrum',
  '80211-standards', 'mcs-index', 'wpa-security', 'data-units-prefixes',
  'freeradius-wlanpi', 'markdown-render-example', 'wifi-exposure-perspective',
  // Physical / mechanical reference (geometry and practice, not a tabulated datum).
  'bend-radius-arc-vs-kink', 'pull-tension-gauge', 'rack-1u-dimension',
  'rack-cage-nut', 'screw-drives-faces', 'screw-phillips-vs-pozidriv',
  'screw-security-drives', 'fiber-optic', 'fiber-apc-endface',
  'fiber-connectors-faces', 'fiber-two-color-systems', 'ethernet-cable',
  'iec-60309', 'poe-reference', 'international-plugs', 'nema-connectors',
  'iec-connectors', 'power-phasing-split-240v', 'power-phasing-three-208v',
};

// ══ DATA-BEARING: each graphic and the Dart dataset that owns its numbers ═══
//
// Every entry here gets a semantic test below. The value is the human name of
// its source of truth, printed in failure messages so the fix is obvious.
const Map<String, String> _dataBearing = <String, String>{
  'signal-thresholds': 'WifiGradingBands.kRssiBands',
  'channel-map': 'ChannelMapScreen.map5_40 / map5_80 / map5_160',
  'rf-attenuation': 'RfAttenuationScreen.materials',
  'power-phasing-single-120v': 'PowerPhasingScreen.topologies',
  // The connector faces: each joins its dataset row via `assetName`.
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
List<String> _texts(String slug) {
  final String raw = File('$_kGraphicsDir/$slug.svg').readAsStringSync();
  final String body = raw.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  return RegExp(r'<text\b[^>]*>(.*?)</text>', dotAll: true)
      .allMatches(body)
      .map((RegExpMatch m) => m
          .group(1)!
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&gt;', '>')
          .replaceAll('&lt;', '<')
          .replaceAll('&#183;', '·')
          .replaceAll('&#8722;', '-')
          .replaceAll('&amp;', '&')
          .trim())
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
          final String s = m
              .group(2)!
              .replaceAll(RegExp(r'<[^>]+>'), '')
              .replaceAll('&#8722;', '-')
              .replaceAll('&#183;', '·')
              .replaceAll('&gt;', '>')
              .trim();
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

    test('the illustrative list has no stale entries', () {
      final Set<String> present = _allGraphicSlugs().toSet();
      final List<String> stale = _illustrative
          .where((String s) => !present.contains(s))
          .toList()
        ..sort();
      // 'rf-attenuation-legacy' is a deliberate tripwire-free placeholder guard:
      // if it ever appears, it means someone re-added the old file.
      stale.remove('rf-attenuation-legacy');
      expect(stale, isEmpty,
          reason: 'The exemption list names graphics that no longer exist. A '
              'stale exemption is how an exemption quietly becomes '
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

  // ══ 3d. rf-attenuation: the LABEL is looked up, not just the number ══════
  group('rf-attenuation.svg agrees with RfAttenuationScreen.materials', () {
    test('each drawn wall names a real material and prints THAT row\'s 2.4 GHz loss',
        () {
      // THE POINT. The old drawing said concrete = -12 dB. A weak guard ("is 12
      // anywhere in that file?") would have PASSED it -- 12 IS in the file, as
      // BRICK at 5 GHz. So this guard reads the wall's LABEL, resolves that row
      // in the dataset, and compares THAT row's value.
      final String flat = _flat('rf-attenuation');
      expect(flat, contains('2.4 GHz'),
          reason: 'The graphic prints per-material losses but never says which '
              'BAND they are for. That ambiguity is what let the -12 dB hide.');

      // (label drawn on the wall) -> (dataset row it must resolve to)
      const Map<String, String> walls = <String, String>{
        'drywall': 'Drywall / Plasterboard',
        'concrete block': 'Concrete block / CMU',
      };
      for (final MapEntry<String, String> w in walls.entries) {
        expect(flat, contains(w.key),
            reason: 'The graphic no longer draws a "${w.key}" wall.');
        final RfMaterial row = RfAttenuationScreen.materials
            .firstWhere((RfMaterial m) => m.name == w.value);
        // The loss printed beside that wall, e.g. "-10 dB".
        final Iterable<int> drawn = RegExp(r'-(\d+) dB')
            .allMatches(flat)
            .map((RegExpMatch m) => int.parse(m.group(1)!));
        expect(drawn, contains(row.loss24),
            reason: '"${w.key}" resolves to dataset row "${w.value}", whose '
                '2.4 GHz loss is ${row.loss24} dB. The graphic does not print '
                'that number. Drawn: $drawn');
      }

      // And no drawn loss may be a number absent from the two rows we name.
      final Set<int> allowed = <int>{
        for (final String name in walls.values)
          RfAttenuationScreen.materials
              .firstWhere((RfMaterial m) => m.name == name)
              .loss24,
      };
      final Set<int> drawnLosses = RegExp(r'-(\d+) dB')
          .allMatches(flat)
          .map((RegExpMatch m) => int.parse(m.group(1)!))
          .toSet();
      expect(drawnLosses.difference(allowed), isEmpty,
          reason: 'The graphic prints a dB figure that belongs to no wall it '
              'draws. Allowed $allowed, drawn $drawnLosses.');
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

  // ══ 3f. power-phasing: the peak is DERIVED, not asserted ═════════════════
  group('power-phasing-single-120v.svg gets RMS vs peak right', () {
    test('the axis peak equals nominal x sqrt(2), recomputed here', () {
      // The old drawing said "120V peak" AND "nominal 120 VAC" in the same
      // frame. Both cannot be true: nominal 120 VAC is RMS, whose peak is 169.7.
      final PowerTopology t = PowerPhasingScreen.topologies.firstWhere(
          (PowerTopology t) => t.assetName == 'power-phasing-single-120v');
      final int rms = _firstInt(t.lineToNeutral); // 120, from the screen
      final int peak = (rms * math.sqrt2).round(); // 170, DERIVED not typed
      final String flat = _flat('power-phasing-single-120v');

      expect(flat, contains('$peak'),
          reason: 'The axis must be labelled with the PEAK ($peak V = $rms x '
              'sqrt(2)), because the sine actually reaches it.');
      expect(flat, contains('$rms V RMS'),
          reason: 'The drawing must say the $rms V is RMS, and mark where it '
              'actually sits (0.707 of full scale), not at the peak.');
      expect(RegExp(r'\b' + rms.toString() + r'V peak\b').hasMatch(flat), isFalse,
          reason: 'The drawing still calls $rms V the PEAK. It is the RMS.');
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
