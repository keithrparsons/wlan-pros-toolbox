// Tests for the AP Placement reference screen.
//
// Dataset tests assert the load-bearing guidance ported VERBATIM from the
// rf-tools-pwa `aplace` tool (data-tool="aplace", the AP_RULES const in
// www/app.js): the five rule groups, their headings, and key numeric guidance
// (cell overlap, coverage radii, the -67 dBm VoIP requirement, the 2.4 GHz
// channel rule). If a value here drifts from the PWA, these break — the point.
//
// The widget-viewport smoke test lives in test/widget_test.dart (uses the
// shared private `_withViewport` phone-viewport helper there).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ap_placement_screen.dart';

void main() {
  group('AP Placement dataset (verbatim from rf-tools-pwa aplace)', () {
    ApRuleGroup byCategory(String name) => ApPlacementScreen.kApRules
        .firstWhere((ApRuleGroup g) => g.category == name);

    test('all five PWA rule groups are present, in order', () {
      expect(
        ApPlacementScreen.kApRules.map((ApRuleGroup g) => g.category).toList(),
        <String>[
          'Start with requirements',
          'AP location',
          'Cell sizing and overlap',
          'Channel planning',
          'High-density venues',
        ],
      );
    });

    test('requirements group states the VoIP -67 / IoT -75 dBm use case', () {
      final ApRuleGroup g = byCategory('Start with requirements');
      expect(
        g.rules.any(
          (String r) => r.contains('VoIP requires -67 dBm') &&
              r.contains('IoT may tolerate -75 dBm'),
        ),
        isTrue,
      );
    });

    test('AP location group prefers ceiling mount over wall mount', () {
      final ApRuleGroup g = byCategory('AP location');
      expect(
        g.rules.any(
          (String r) => r.startsWith('Ceiling mount is preferred over wall'),
        ),
        isTrue,
      );
    });

    test('cell sizing group targets 15-20% overlap and 2 APs at -70 dBm', () {
      final ApRuleGroup g = byCategory('Cell sizing and overlap');
      expect(
        g.rules.any((String r) => r.contains('15-20% cell overlap')),
        isTrue,
      );
      expect(
        g.rules.any((String r) => r.contains('2 APs visible at -70 dBm')),
        isTrue,
      );
    });

    test('cell sizing group states the indoor coverage radii', () {
      final ApRuleGroup g = byCategory('Cell sizing and overlap');
      expect(
        g.rules.any(
          (String r) =>
              r.contains('20-30 m open office') &&
              r.contains('10-15 m'),
        ),
        isTrue,
      );
    });

    test('channel planning group restricts 2.4 GHz to channels 1, 6, 11', () {
      final ApRuleGroup g = byCategory('Channel planning');
      expect(
        g.rules.any(
          (String r) =>
              r.contains('channels 1, 6, and 11') &&
              r.contains('Never use channels 2, 3, 4, 7, 8, 9, or 10'),
        ),
        isTrue,
      );
    });

    test('high-density group reduces Tx power and adds APs, not power', () {
      final ApRuleGroup g = byCategory('High-density venues');
      expect(
        g.rules.any(
          (String r) =>
              r.contains('reduce Tx power and add') &&
              r.contains('rather than increasing power'),
        ),
        isTrue,
      );
    });

    test('high-density group plans 20-30 clients per radio', () {
      final ApRuleGroup g = byCategory('High-density venues');
      expect(
        g.rules.any((String r) => r.contains('20-30 clients per radio')),
        isTrue,
      );
    });

    test('no rule ever calls an AP a router (house rule)', () {
      for (final ApRuleGroup g in ApPlacementScreen.kApRules) {
        for (final String r in g.rules) {
          expect(
            r.toLowerCase().contains('router'),
            isFalse,
            reason: 'AP is never a router: "$r"',
          );
        }
      }
    });

    test('no em dash appears in any rule (house rule)', () {
      for (final ApRuleGroup g in ApPlacementScreen.kApRules) {
        for (final String r in g.rules) {
          expect(r.contains('—'), isFalse, reason: 'em dash in "$r"');
        }
      }
    });
  });
}
