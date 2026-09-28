// The teaching claims of the guest-discovery lesson, pinned on the model.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/guest_discovery_model.dart';

void main() {
  test('the query is link-local Multicast DNS (RFC 6762): 224.0.0.251 or '
      'FF02::FB, UDP port 5353', () {
    expect(kMdnsIpv4Address, '224.0.0.251');
    expect(kMdnsIpv6Address, 'FF02::FB');
    expect(kMdnsPort, 5353);
    expect(kQueryAddressed, contains('224.0.0.251'));
    expect(kQueryAddressed, contains('5353'));
  });

  test('three steps, the same in every mode', () {
    expect(kStageTitles.keys.toList(), DiscoveryStage.values);
  });

  for (final DiscoveryNetwork n in DiscoveryNetwork.values) {
    test('$n: the phone asks first, and its internet still works', () {
      final DiscoveryScenario s = discoveryScenario(n);
      expect(s.network, n);
      expect(s.phone.outcome, HopOutcome.sender);
      expect(
        s.hops.where((DiscoveryHop h) => h.outcome == HopOutcome.sender),
        hasLength(1),
      );
      expect(s.targets.map((DiscoveryHop h) => h.label), <String>[
        'The TV',
        'The printer',
      ]);
      expect(s.internetWorks, isTrue);
    });

    test('$n: nothing past the stop hears the query', () {
      final DiscoveryScenario s = discoveryScenario(n);
      final int stop = s.hops.indexWhere(
        (DiscoveryHop h) => h.outcome == HopOutcome.stopped,
      );
      if (stop == -1) {
        expect(s.stopsAt, isNull);
        return;
      }
      expect(s.hops[stop].label, s.stopsAt);
      for (final DiscoveryHop h in s.hops.skip(stop + 1)) {
        expect(h.outcome, HopOutcome.missed, reason: h.label);
      }
    });
  }

  test(
    'same network: the TV and the printer both hear it and both show up',
    () {
      final DiscoveryScenario s = discoveryScenario(DiscoveryNetwork.same);
      expect(s.stopsAt, isNull);
      expect(s.found, <String>['The TV', 'The printer']);
      expect(
        s.hops.every((DiscoveryHop h) => h.segment == s.phone.segment),
        isTrue,
      );
    },
  );

  test('guest network: a different segment from the TV and the printer; the '
      'query stops at the router and the list is empty', () {
    final DiscoveryScenario s = discoveryScenario(DiscoveryNetwork.guest);
    for (final DiscoveryHop t in s.targets) {
      expect(t.segment, isNot(s.phone.segment));
    }
    expect(s.stopsAt, 'Router');
    expect(s.found, isEmpty);
  });

  test('client isolation: the same segment as the TV and the printer, and '
      'still nothing found; the query stops at the access point', () {
    final DiscoveryScenario s = discoveryScenario(DiscoveryNetwork.isolation);
    for (final DiscoveryHop t in s.targets) {
      expect(t.segment, s.phone.segment);
    }
    expect(s.stopsAt, 'Access point');
    expect(s.found, isEmpty);
  });

  test('no product or vendor names in anything the lesson shows (Larry\'s '
      'brief)', () {
    final RegExp banned = RegExp(
      r'AirPlay|AirPrint|Bonjour|Chromecast|Google Cast|Apple|Google|Roku|'
      r'Sonos|Miracast|iPhone|Android',
      caseSensitive: false,
    );
    final List<String> texts = <String>[
      kQueryPlain,
      kQueryAddressed,
      ...kStageTitles.values,
      for (final DiscoveryNetwork n in DiscoveryNetwork.values) ...<String>[
        discoveryScenario(n).why,
        for (final DiscoveryHop h in discoveryScenario(n).hops) ...<String>[
          h.label,
          h.segment,
        ],
      ],
    ];
    for (final String t in texts) {
      expect(banned.hasMatch(t), isFalse, reason: t);
    }
  });
}
