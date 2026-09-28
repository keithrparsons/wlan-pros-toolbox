// Wi-Fi Classroom is its own home section (Keith, 2026-09-26: "Own section,
// next to Educational Resources"), and holds the WLAN Pros lessons and
// handouts as well as the simulators (same day: "Lessons and handouts, all
// ours").
//
// Pins: the category sits right after Educational Resources; every simulator,
// lesson and handout is in it and in none of its old homes; the shelves and
// the tools on them render in teaching order; no shelf holds a single tool;
// ids and routes did not change in the move.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';

/// Shelf -> tool ids, in the order the screen must show them.
const Map<String, List<String>> _teachingOrder = <String, List<String>>{
  'Guided Lessons': <String>[
    'antenna-fundamentals',
    'spectrum-analysis',
    // 2026-09-27: Find My, Explained, the lesson for the people Wi-Fi pros
    // get asked about Find My by.
    'find-my-explained',
    // 2026-09-27: Public Wi-Fi, what the person next to you can see.
    'public-wifi',
    // 2026-09-27: Wi-Fi Privacy Myths, the private address and the hidden name.
    'wifi-privacy-myths',
  ],
  'RF and Propagation': <String>[
    'fspl-simulator',
    'wifi-through-a-wall',
    // 2026-09-27: How to Measure Wall Attenuation, beside the wall tool.
    'measure-wall',
    'multipath-simulator',
    'devices-disagree',
    'room-propagation',
    'antenna-pattern',
    'rate-vs-range',
    'six-ghz-psd',
    'uplink-downlink',
    'body-loss',
  ],
  'Signals and PHY': <String>[
    'modulation-simulator',
    'fourier-fft',
    'ofdma-simulator',
    'mimo-beamforming',
    'phy-preamble',
  ],
  'Airtime and Access': <String>[
    'medium-access-simulator',
    'airtime-anatomy',
    'airtime-fairness',
    'rate-adaptation',
    'spatial-reuse',
    'power-save',
    'multicast-basic-rate',
    'channel-utilization',
    'legacy-protection',
    'mlo-simulator',
  ],
  'Network Design and Security': <String>[
    'channel-planner',
    'adjacent-channel',
    'roaming-walk',
    // 2026-09-27: Band Steering (spec 38), beside the walk it pairs with.
    'band-steering',
    'survey-walk',
    'heat-map-builder',
    'predict-then-measure',
    // 2026-09-26: Where Am I? (spec 33), shelved after the survey tools.
    'location-rssi-ftm',
    'repeater-mesh',
    // 2026-09-27: Why a Busy Line Lags (latency under load), the network
    // past the AP, after the relay tool.
    'latency-under-load',
    'dfs-simulator',
    // 2026-09-26: Association, Frame by Frame (spec 21b), its own tool
    // by Keith's call, shelved beside the ladder whose engine it shares.
    'join-ladder',
    'eap-ladder',
  ],
  'Course Handouts': <String>[
    'channel-allocations-24ghz',
    'channel-allocations-5ghz',
    'channel-allocations-6ghz',
    'channel-allocations-6ghz-gvp',
    'troubleshooting-causes',
    'bubble-diagram',
    'top-20-checklist',
    'extended-checklist',
    'extended-checklist-nonadvertised',
    'connection-checklist',
    'mcs-index-card',
  ],
};

const Set<String> _simulatorShelves = <String>{
  'RF and Propagation',
  'Signals and PHY',
  'Airtime and Access',
  'Network Design and Security',
};

ToolCategory _cat(String id) =>
    kToolCategories.firstWhere((ToolCategory c) => c.id == id);

// Guided Lessons built in the Classroom itself (2026-09-27 on), which never
// lived in Educational Resources and so are not among the 13 that moved.
const Set<String> _builtInClassroom = <String>{
  'find-my-explained',
  'public-wifi',
  'wifi-privacy-myths',
};

void main() {
  final ToolCategory classroom = _cat('wifi-classroom');

  test('the section is titled Wi-Fi Classroom and sits right after '
      'Educational Resources', () {
    expect(classroom.title, 'Wi-Fi Classroom');
    final List<String> ids = kToolCategories
        .map((ToolCategory c) => c.id)
        .toList();
    expect(
      ids.indexOf('wifi-classroom'),
      ids.indexOf('educational-resources') + 1,
    );
  });

  test('all 39 simulators are in wifi-classroom and none remain in '
      'rf-calculators', () {
    final Set<String> sims = <String>{
      for (final String shelf in _simulatorShelves) ..._teachingOrder[shelf]!,
    };
    // 2026-09-26: Classroom wave-4 tools added; the count is set at each merge into wifi-lab/preview.
    expect(sims, hasLength(39));
    final Set<String> inClassroom = <String>{
      for (final ToolEntry t in classroom.tools) t.id,
    };
    final Set<String> inCalc = <String>{
      for (final ToolEntry t in _cat('rf-calculators').tools) t.id,
    };
    expect(
      inClassroom.containsAll(sims),
      isTrue,
      reason: 'missing: ${sims.difference(inClassroom)}',
    );
    expect(inCalc.intersection(sims), isEmpty);
    expect(
      _cat(
        'rf-calculators',
      ).tools.where((ToolEntry t) => t.subgroup == 'Wi-Fi Classroom'),
      isEmpty,
    );
    expect(
      kCategorySubgroupOrder['rf-calculators'],
      isNot(contains('Wi-Fi Classroom')),
    );
  });

  test('the 13 lessons and handouts left educational-resources; Ham Radio '
      'Study Resources stayed', () {
    // find-my-explained was built in the Classroom (2026-09-27) and never
    // lived in Educational Resources, so it is not one of the 13 that moved.
    final Set<String> moved = <String>{
      ..._teachingOrder['Guided Lessons']!.where(
        (String id) =>
            !_builtInClassroom.contains(id),
      ),
      ..._teachingOrder['Course Handouts']!,
    };
    expect(moved, hasLength(13));
    final Set<String> edu = <String>{
      for (final ToolEntry t in _cat('educational-resources').tools) t.id,
    };
    expect(edu.intersection(moved), isEmpty);
    expect(edu, contains('ham-study-resources'));
  });

  test('each tool is in exactly one category', () {
    final Map<String, int> seen = <String, int>{};
    for (final ToolCategory c in kToolCategories) {
      for (final ToolEntry t in c.tools) {
        seen[t.id] = (seen[t.id] ?? 0) + 1;
      }
    }
    for (final String id in _teachingOrder.values.expand(
      (List<String> l) => l,
    )) {
      expect(seen[id], 1, reason: id);
    }
  });

  test('shelves and tools render in teaching order, not A-Z', () {
    final List<ToolSection> sections = groupedCategoryTools(classroom);
    expect(
      sections.map((ToolSection s) => s.header).toList(),
      _teachingOrder.keys.toList(),
    );
    for (final ToolSection s in sections) {
      expect(
        s.tools.map((ToolEntry t) => t.id).toList(),
        _teachingOrder[s.header],
        reason: s.header,
      );
    }
    // 2026-09-26: Classroom wave-4 tools added; the count is set at each merge into wifi-lab/preview.
    expect(classroom.tools, hasLength(55));
  });

  test('no Classroom shelf holds a single tool (Keith, 2026-09-17)', () {
    for (final ToolSection s in groupedCategoryTools(classroom)) {
      expect(s.count, greaterThanOrEqualTo(2), reason: s.header);
    }
  });

  test('ids and routes did not change in the move', () {
    for (final ToolEntry t in classroom.tools) {
      expect(t.routeName, '/tools/${t.id}', reason: t.id);
      expect(AppRouter.routes.containsKey(t.routeName), isTrue, reason: t.id);
      expect(t.isLive, isTrue, reason: t.id);
    }
  });

  test('home-tile examples name tools that are in the section (GL-005)', () {
    final Set<String> titles = <String>{
      for (final ToolEntry t in classroom.tools) t.title,
    };
    for (final String ex in classroom.exampleToolTitles) {
      expect(titles, contains(ex));
    }
  });
}
