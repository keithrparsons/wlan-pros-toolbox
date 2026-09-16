// Tests for the VoIP over Wi-Fi Filters screen.
//
// The dataset assertions pin the thing that makes this card worth shipping:
// every filter string was compiled with `dftest` against a live Wireshark 4.6.6
// before it shipped, and the four plausible-looking fields that FAILED to
// compile must never appear. A filter that does not parse is worse than an
// absent one, because the reader concludes their capture is empty rather than
// their filter wrong.
//
// Widget tests cover render, the group-aware live filter, the empty state, both
// themes, and no overflow at 320 / 375 / 768 / 1280.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/command/voip_wifi_filters_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  List<VoipFilter> allFilters() => <VoipFilter>[
        for (final VoipFilterGroup g in VoipWifiFiltersScreen.groups)
          ...g.filters,
      ];

  VoipFilterGroup groupFor(String label) =>
      VoipWifiFiltersScreen.groups.firstWhere((g) => g.label == label);

  String allProse() => <String>[
        VoipWifiFiltersScreen.intro,
        VoipWifiFiltersScreen.caveat,
        VoipWifiFiltersScreen.dscpCrossLink,
        VoipWifiFiltersScreen.footnote,
        for (final VoipFilterGroup g in VoipWifiFiltersScreen.groups) ...<String>[
          g.label,
          g.note ?? '',
          for (final VoipFilter f in g.filters) ...<String>[
            f.filter,
            f.description,
          ],
        ],
      ].join('\n');

  group('VoIP filters - the verified-filter contract', () {
    // THE ONE THAT MATTERS. These four compiled-FAILED against Wireshark 4.6.6
    // ("is not a valid protocol or protocol field"). They are a plausible guess,
    // not fields. Shipping one would return nothing and look like an empty
    // capture.
    test('none of the four non-existent rtp.analysis fields ship', () {
      const List<String> banned = <String>[
        'rtp.analysis.lost',
        'rtp.analysis.jitter',
        'rtp.analysis.delta',
        'rtp.analysis.out_of_seq',
      ];
      final String prose = allProse();
      for (final String bad in banned) {
        for (final VoipFilter f in allFilters()) {
          expect(f.filter.contains(bad), isFalse,
              reason: '$bad does not exist in Wireshark and must never ship as '
                  'a filter row');
        }
        // The footnote NAMES rtp.analysis to say it does not exist. That is the
        // teaching, not a filter, so the row check above is the binding one and
        // this only guards the filter column.
        expect(prose.contains('$bad ='), isFalse,
            reason: '$bad must never be presented as usable syntax');
      }
    });

    test('no filter row uses any rtp.analysis field at all', () {
      for (final VoipFilter f in allFilters()) {
        expect(f.filter.contains('rtp.analysis'), isFalse,
            reason: 'Wireshark has no rtp.analysis display filter; per-stream '
                'loss and jitter is a statistic, which is what the tshark group '
                'is for');
      }
    });

    test('the four RTCP fields ship with the names Wireshark actually has', () {
      final FilterGroupProbe rtcp =
          FilterGroupProbe(groupFor('What the endpoint itself says: RTCP (display)'));
      expect(rtcp.hasFilter('rtcp.ssrc.fraction'), isTrue);
      expect(rtcp.hasFilter('rtcp.ssrc.cum_nr'), isTrue);
      expect(rtcp.hasFilter('rtcp.ssrc.high_seq'), isTrue);
      expect(rtcp.hasFilter('rtcp.ssrc.jitter'), isTrue);
    });
  });

  group('VoIP filters - the three Wi-Fi questions', () {
    test('the QoS-marking group carries the diagnostic filter and its teaching',
        () {
      final VoipFilterGroup qos =
          groupFor('Did the QoS marking survive? (display)');
      final FilterGroupProbe probe = FilterGroupProbe(qos);

      // The filter the card exists for.
      expect(
        probe.hasFilter('ip.dsfield.dscp == 46 && wlan.qos.priority != 6'),
        isTrue,
        reason: 'the marked-EF-but-not-Voice filter is the section that '
            'justifies this card',
      );
      // The specific signature: UP derived as DSCP >> 3 puts EF in UP 5.
      expect(
        probe.hasFilter('ip.dsfield.dscp == 46 && wlan.qos.priority == 5'),
        isTrue,
      );
      expect(probe.hasFilter('ip.dsfield.dscp == 46'), isTrue);
      expect(probe.hasFilter('wlan.qos.priority == 6'), isTrue);
      expect(probe.hasFilter('rtp && wlan.qos.priority == 0'), isTrue);

      // The teaching sits ON the card, not only in the help sheet.
      final String note = qos.note ?? '';
      expect(note, contains('IP header'));
      expect(note, contains('802.11 header'));
      expect(note, contains('map one to the other'));
    });

    test('the roam group follows one stream across a reassociation', () {
      final VoipFilterGroup roam = groupFor('Did it break at a roam? (display)');
      final FilterGroupProbe probe = FilterGroupProbe(roam);
      expect(probe.hasFilter('wlan.fc.type_subtype == 0x02'), isTrue);
      expect(probe.hasFilter('wlan.fc.type_subtype == 0x03'), isTrue);
      // rtp.ssrc is the "follow ONE stream" handle; it must be present on the
      // card somewhere, with a substitutable example value.
      expect(
        allFilters().any((f) => f.filter.contains('rtp.ssrc == 0x12345678')),
        isTrue,
      );
      expect(roam.note ?? '', contains('300 ms'));
    });

    test('the power-save group carries the mid-call sleep filter', () {
      final FilterGroupProbe probe =
          FilterGroupProbe(groupFor('Is power save eating it? (display)'));
      expect(probe.hasFilter('wlan.fc.pwrmgt == 1'), isTrue);
      expect(probe.hasFilter('wlan.fc.pwrmgt == 1 && rtp'), isTrue);
    });
  });

  group('VoIP filters - the two sources of loss and jitter', () {
    test('the statistics group is present, labelled as NOT display filters', () {
      final VoipFilterGroup stats = groupFor(
          'Loss and jitter: two sources, and the disagreement is the finding');
      final FilterGroupProbe probe = FilterGroupProbe(stats);
      expect(probe.hasFilter('tshark -q -z rtp,streams -r capture.pcapng'),
          isTrue);
      expect(probe.hasFilter('tshark -q -z sip,stat -r capture.pcapng'), isTrue);
      expect(probe.hasFilter('tshark -q -z follow,sip -r capture.pcapng'),
          isTrue);

      final String note = stats.note ?? '';
      expect(note, contains('NOT display'),
          reason: 'a tshark tap typed into the filter bar does nothing; the '
              'card must say so where the rows are');
      expect(note, contains('FAR ENDPOINT'));
      expect(note, contains('THIS CAPTURE'));
      expect(note, contains('disagree'));
    });
  });

  group('VoIP filters - wiring', () {
    test('the catalog entry sits in Quick Reference under CLI & Capture', () {
      final ToolCategory qr = kToolCategories
          .firstWhere((ToolCategory c) => c.id == 'quick-reference');
      final ToolEntry t =
          qr.tools.firstWhere((ToolEntry e) => e.id == 'voip-wifi-filters');
      expect(t.subgroup, 'CLI & Capture');
      expect(t.routeName, '/tools/voip-wifi-filters');
      expect(t.isLive, isTrue);
      // It ships beside the 802.11 filter sheet, not inside it.
      expect(
        qr.tools.any((ToolEntry e) => e.id == 'wireshark-80211-filters'),
        isTrue,
      );
    });

    test('the route is registered and builds the screen', () {
      expect(AppRouter.voipWifiFilters, '/tools/voip-wifi-filters');
      expect(AppRouter.routes.containsKey(AppRouter.voipWifiFilters), isTrue);
    });

    test('the card cross-links to the DSCP / QoS Markings tool', () {
      expect(VoipWifiFiltersScreen.dscpCrossLink, contains('DSCP / QoS Markings'));
      // And that tool actually exists in the catalog, so the pointer is not
      // pointing at a tool we removed.
      expect(
        kToolCategories
            .expand((ToolCategory c) => c.tools)
            .any((ToolEntry t) => t.id == 'dscp-qos'),
        isTrue,
      );
    });

    test('house style: no em dash, Wi-Fi hyphenated with a capital F', () {
      final String prose = allProse();
      expect(prose.contains(String.fromCharCode(0x2014)), isFalse,
          reason: 'GL-004 P0: zero em dashes in shipped copy');
      expect(RegExp(r'\bWifi\b|\bWiFi\b|\bwifi\b').hasMatch(prose), isFalse,
          reason: 'it is Wi-Fi, hyphenated, capital F');
    });
  });

  group('VoipWifiFiltersScreen widget', () {
    for (final MapEntry<String, ThemeData> theme
        in <String, ThemeData>{
      'dark': AppTheme.dark(),
      'light': AppTheme.light(),
    }.entries) {
      testWidgets('renders title and group headings (${theme.key})',
          (tester) async {
        await _withViewport(tester, const Size(375, 4000), () async {
          await tester.pumpWidget(
            MaterialApp(
                theme: theme.value, home: const VoipWifiFiltersScreen()),
          );
          expect(find.text('VoIP over Wi-Fi Filters'), findsWidgets);
          expect(find.text('Did the QoS marking survive? (display)'),
              findsOneWidget);
          expect(find.byType(TextField), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });
    }

    testWidgets('filtering by "roam" surfaces the roam group only',
        (tester) async {
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(
          MaterialApp(
              theme: AppTheme.dark(), home: const VoipWifiFiltersScreen()),
        );
        await tester.enterText(find.byType(TextField), 'roam');
        await tester.pump();
        expect(find.text('Did it break at a roam? (display)'), findsOneWidget);
        expect(find.text('Find the call: signaling (display)'), findsNothing);
      });
    });

    testWidgets('filtering by "dscp" keeps the QoS group', (tester) async {
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(
          MaterialApp(
              theme: AppTheme.dark(), home: const VoipWifiFiltersScreen()),
        );
        await tester.enterText(find.byType(TextField), 'dscp');
        await tester.pump();
        expect(find.text('Did the QoS marking survive? (display)'),
            findsOneWidget);
      });
    });

    testWidgets('a no-match query renders the honest empty state',
        (tester) async {
      await _withViewport(tester, const Size(375, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
              theme: AppTheme.dark(), home: const VoipWifiFiltersScreen()),
        );
        await tester.enterText(find.byType(TextField), 'zzzznotarealfilter');
        await tester.pump();
        expect(find.text('No match'), findsOneWidget);
        expect(find.text('Did the QoS marking survive? (display)'), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280', (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 5000), () async {
          await tester.pumpWidget(
            MaterialApp(
                theme: AppTheme.dark(), home: const VoipWifiFiltersScreen()),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });
  });
}

/// Tiny read-only probe so the row assertions read as questions about a group
/// rather than as repeated `.any((f) => ...)` closures.
class FilterGroupProbe {
  const FilterGroupProbe(this.group);

  final VoipFilterGroup group;

  bool hasFilter(String syntax) =>
      group.filters.any((VoipFilter f) => f.filter == syntax);
}

Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
