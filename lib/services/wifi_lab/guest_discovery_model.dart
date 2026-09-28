// Why the TV and the Printer Vanish on Guest Wi-Fi: the discovery model behind
// the Wi-Fi Classroom Guided Lesson `guest-discovery`. Pure Dart,
// deterministic, no Flutter imports.
//
// CLEAN ROOM. Built from RFC 6762 (Multicast DNS) only:
//  - queries go to the link-local multicast address 224.0.0.251 (IPv6
//    FF02::FB) on UDP port 5353 (§3, §5);
//  - names ending in .local are meaningful only on the link where they
//    originate (§3);
//  - a querier accepts only answers that originate from the local link
//    (§11).
// Client isolation is a setting on the access point, not a standard; the
// lesson says only that it stops the access point passing traffic between
// wireless devices, and that exactly what it blocks differs by product.
//
// GUARD (Pax, research brief §3 candidate 11; Larry's brief): no product
// names. The devices are "the TV" and "the printer", the feature is "screen
// casting" and "printing".

/// Where the phone is, relative to the TV and the printer.
enum DiscoveryNetwork {
  /// The phone, the TV and the printer share one network.
  same,

  /// The phone is on the guest network, a separate segment.
  guest,

  /// One network, but the access point will not pass traffic between
  /// wireless devices.
  isolation,
}

/// The three steps, identical in every mode.
enum DiscoveryStage { ask, travel, result }

/// What happened to the query at one hop.
enum HopOutcome {
  /// This device asked.
  sender,

  /// Passed the query on.
  passed,

  /// The query stops here.
  stopped,

  /// Heard the query and answered.
  heard,

  /// Never heard the query.
  missed,
}

/// One device on the query's path.
class DiscoveryHop {
  const DiscoveryHop({
    required this.label,
    required this.segment,
    required this.outcome,
    this.isTarget = false,
  });

  final String label;

  /// The network segment the hop sits on, as shown on screen.
  final String segment;
  final HopOutcome outcome;

  /// True for the TV and the printer, the devices the phone is looking for.
  final bool isTarget;
}

/// One mode of the lesson.
class DiscoveryScenario {
  const DiscoveryScenario({
    required this.network,
    required this.hops,
    required this.stopsAt,
    required this.why,
  });

  final DiscoveryNetwork network;

  /// Phone first, then the path, then the TV and the printer.
  final List<DiscoveryHop> hops;

  /// The hop where the query stops, or null when it reaches everyone.
  final String? stopsAt;

  /// Why this happens, in a sentence or two.
  final String why;

  DiscoveryHop get phone => hops.first;

  Iterable<DiscoveryHop> get targets =>
      hops.where((DiscoveryHop h) => h.isTarget);

  /// What the phone's list shows at the result step.
  List<String> get found => <String>[
    for (final DiscoveryHop h in targets)
      if (h.outcome == HopOutcome.heard) h.label,
  ];

  /// The phone's internet works in every mode: discovery failing does not
  /// mean the Wi-Fi is broken.
  bool get internetWorks => true;
}

/// The query, the same in every mode (RFC 6762 §3 and §5).
const String kMdnsIpv4Address = '224.0.0.251';
const String kMdnsIpv6Address = 'FF02::FB';
const int kMdnsPort = 5353;

/// What the phone asks, in plain words, and how it is addressed.
const String kQueryPlain =
    'Who here can show my screen? Is there a printer here?';
const String kQueryAddressed =
    'One Multicast DNS query to $kMdnsIpv4Address, UDP port $kMdnsPort: '
    'everyone on this network segment, and no one beyond it';

/// The step names, in order.
const Map<DiscoveryStage, String> kStageTitles = <DiscoveryStage, String>{
  DiscoveryStage.ask: 'The phone asks',
  DiscoveryStage.travel: 'Where the question goes',
  DiscoveryStage.result: "What the phone's list shows",
};

const String _main = 'Main network';
const String _guest = 'Guest network';

/// The scenario for [network].
DiscoveryScenario discoveryScenario(DiscoveryNetwork network) {
  switch (network) {
    case DiscoveryNetwork.same:
      return const DiscoveryScenario(
        network: DiscoveryNetwork.same,
        hops: <DiscoveryHop>[
          DiscoveryHop(
            label: 'This phone',
            segment: _main,
            outcome: HopOutcome.sender,
          ),
          DiscoveryHop(
            label: 'Access point',
            segment: _main,
            outcome: HopOutcome.passed,
          ),
          DiscoveryHop(
            label: 'The TV',
            segment: _main,
            outcome: HopOutcome.heard,
            isTarget: true,
          ),
          DiscoveryHop(
            label: 'The printer',
            segment: _main,
            outcome: HopOutcome.heard,
            isTarget: true,
          ),
        ],
        stopsAt: null,
        why:
            'Everyone is on the same segment, so the question reaches the TV '
            'and the printer, and both answer.',
      );
    case DiscoveryNetwork.guest:
      return const DiscoveryScenario(
        network: DiscoveryNetwork.guest,
        hops: <DiscoveryHop>[
          DiscoveryHop(
            label: 'This phone',
            segment: _guest,
            outcome: HopOutcome.sender,
          ),
          DiscoveryHop(
            label: 'Access point',
            segment: _guest,
            outcome: HopOutcome.passed,
          ),
          DiscoveryHop(
            label: 'Router',
            segment: 'Between the two networks',
            outcome: HopOutcome.stopped,
          ),
          DiscoveryHop(
            label: 'The TV',
            segment: _main,
            outcome: HopOutcome.missed,
            isTarget: true,
          ),
          DiscoveryHop(
            label: 'The printer',
            segment: _main,
            outcome: HopOutcome.missed,
            isTarget: true,
          ),
        ],
        stopsAt: 'Router',
        why:
            'The guest network is a separate segment. The question is '
            'addressed to the local segment only, so it goes no further than '
            'the router at its edge. The TV and the printer never hear it.',
      );
    case DiscoveryNetwork.isolation:
      return const DiscoveryScenario(
        network: DiscoveryNetwork.isolation,
        hops: <DiscoveryHop>[
          DiscoveryHop(
            label: 'This phone',
            segment: _main,
            outcome: HopOutcome.sender,
          ),
          DiscoveryHop(
            label: 'Access point',
            segment: '$_main, client isolation on',
            outcome: HopOutcome.stopped,
          ),
          DiscoveryHop(
            label: 'The TV',
            segment: _main,
            outcome: HopOutcome.missed,
            isTarget: true,
          ),
          DiscoveryHop(
            label: 'The printer',
            segment: _main,
            outcome: HopOutcome.missed,
            isTarget: true,
          ),
        ],
        stopsAt: 'Access point',
        why:
            'Same network, same segment, but the access point will not pass '
            'traffic from one wireless device to another. The question stops '
            'at the access point.',
      );
  }
}
