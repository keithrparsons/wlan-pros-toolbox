// PortCheck verdict: "what does this network let out?" as PURE DART. No
// Flutter, no sockets. The service (port_check_service.dart) probes the
// targets below and hands one [TargetOutcome] per target to [judgePortCheck],
// which groups them by what the user is trying to do.
//
// Design source: Deliverables/2026-11-16-port-check/port-check-approaches
// --RESULTS.md sections 0.1, 0.2, 0.4, 0.5. Keith's rulings: approach A (16 NOV),
// VPN row ships as Not checked (16 NOV), public services only and never a
// server of ours (13 NOV), runs only on a tap.
//
// RULES THIS FILE EXISTS TO KEEP
//   * A RST on a far-end target is a rejection, not "gets out". Ping counts a
//     RST as an answer ([TcpProbeFailure.hostAnswered]); this check must not.
//   * A port is "blocked" only when EVERY target for it failed while the
//     baseline (two unrelated hosts on 443) got through. One server being down
//     is never blamed on the network.
//   * UDP has two outcomes only (reply or silence). Silence from a pair of
//     targets is the verdict; silence from one is "no verdict".
//   * Status words come from [TriageStatus], the ladder's own set.
//   * US spelling, no em dashes, never a bare "AP".

import 'analyze/triage_ladder.dart'
    show TriageLadder, TriageRung, TriageRungId, TriageStatus;

enum PortCheckTransport { tcp, udp }

/// How a UDP target is probed and how its reply is recognized.
enum UdpProbeKind { dns, ntp, stun, quic }

/// What one probe of one target showed.
enum TargetOutcome {
  /// A TCP handshake completed, or a valid UDP reply came from the address we
  /// asked.
  gotOut,

  /// TCP: refused, timed out or unreachable. UDP: no valid reply in the window.
  didNotGetOut,

  /// The target name did not resolve: a DNS problem, not a port problem.
  noVerdict,

  /// This device could not even open the socket (UDP on a platform that
  /// forbids it). Never reported as a blocked network.
  unavailable,
}

class PortCheckTarget {
  const PortCheckTarget(
    this.host,
    this.port,
    this.transport,
    this.operator, {
    this.udp,
    this.baseline = false,
  });

  final String host;
  final int port;
  final PortCheckTransport transport;

  /// Who runs it. Two targets for one port never share an operator.
  final String operator;
  final UdpProbeKind? udp;

  /// One of the two unrelated hosts that must answer on 443 before anything
  /// else is judged.
  final bool baseline;
}

/// Public services on their published ports only. Never a wlanpros.com host
/// (Keith, 13 NOV). Every TCP target completed from one unblocked network on
/// 16 NOV (design section 0.2, a `socket.connect` loop). The UDP probes were
/// measured the same day (section 0.6). That proves the hosts listen from one
/// network, not that they answer from every country.
const List<PortCheckTarget> kPortCheckTargets = <PortCheckTarget>[
  PortCheckTarget(
    'cloudflare.com',
    443,
    PortCheckTransport.tcp,
    'Cloudflare',
    baseline: true,
  ),
  PortCheckTarget(
    'example.com',
    443,
    PortCheckTransport.tcp,
    'IANA',
    baseline: true,
  ),
  PortCheckTarget('cloudflare.com', 80, PortCheckTransport.tcp, 'Cloudflare'),
  PortCheckTarget('github.com', 22, PortCheckTransport.tcp, 'GitHub'),
  PortCheckTarget('gitlab.com', 22, PortCheckTransport.tcp, 'GitLab'),
  PortCheckTarget(
    'gmail-smtp-in.l.google.com',
    25,
    PortCheckTransport.tcp,
    'Google',
  ),
  PortCheckTarget(
    'outlook-com.olc.protection.outlook.com',
    25,
    PortCheckTransport.tcp,
    'Microsoft',
  ),
  PortCheckTarget('smtp.gmail.com', 587, PortCheckTransport.tcp, 'Google'),
  PortCheckTarget(
    'smtp.office365.com',
    587,
    PortCheckTransport.tcp,
    'Microsoft',
  ),
  PortCheckTarget('smtp.gmail.com', 465, PortCheckTransport.tcp, 'Google'),
  PortCheckTarget('smtp.mail.yahoo.com', 465, PortCheckTransport.tcp, 'Yahoo'),
  PortCheckTarget('imap.gmail.com', 993, PortCheckTransport.tcp, 'Google'),
  PortCheckTarget(
    'outlook.office365.com',
    993,
    PortCheckTransport.tcp,
    'Microsoft',
  ),
  PortCheckTarget('1.1.1.1', 853, PortCheckTransport.tcp, 'Cloudflare'),
  PortCheckTarget('9.9.9.9', 853, PortCheckTransport.tcp, 'Quad9'),
  PortCheckTarget(
    '1.1.1.1',
    53,
    PortCheckTransport.udp,
    'Cloudflare',
    udp: UdpProbeKind.dns,
  ),
  PortCheckTarget(
    '8.8.8.8',
    53,
    PortCheckTransport.udp,
    'Google',
    udp: UdpProbeKind.dns,
  ),
  PortCheckTarget(
    'time.cloudflare.com',
    123,
    PortCheckTransport.udp,
    'Cloudflare',
    udp: UdpProbeKind.ntp,
  ),
  PortCheckTarget(
    'time.google.com',
    123,
    PortCheckTransport.udp,
    'Google',
    udp: UdpProbeKind.ntp,
  ),
  PortCheckTarget(
    'stun.cloudflare.com',
    3478,
    PortCheckTransport.udp,
    'Cloudflare',
    udp: UdpProbeKind.stun,
  ),
  PortCheckTarget(
    'stun.l.google.com',
    19302,
    PortCheckTransport.udp,
    'Google',
    udp: UdpProbeKind.stun,
  ),
  PortCheckTarget(
    '1.1.1.1',
    443,
    PortCheckTransport.udp,
    'Cloudflare',
    udp: UdpProbeKind.quic,
  ),
];

class PortCheckGroup {
  const PortCheckGroup(this.name, this.status, this.details);

  final String name;
  final TriageStatus status;

  /// Plain sentences, one per line on screen and in the copy text.
  final List<String> details;
}

class PortCheckReport {
  const PortCheckReport(this.groups, this.summary);

  final List<PortCheckGroup> groups;
  final String summary;
}

const String _noInternet =
    'No internet got through, so this cannot tell what is blocked.';
const String _signIn =
    'This network wants a sign-in first. Sign in, then run this again.';
const String _vpnGap =
    'No public server answers a test packet on UDP 500 or 4500, so VPN setup '
    'traffic cannot be tested here.';

/// One port (or one UDP probe kind) as all of its targets saw it.
enum _Port { out, blocked, unavailable, unknown }

PortCheckReport judgePortCheck(
  Map<PortCheckTarget, TargetOutcome> outcomes, {
  bool signInNeeded = false,
}) {
  _Port stateOf(bool Function(PortCheckTarget) which) {
    final List<TargetOutcome> seen = <TargetOutcome>[
      for (final PortCheckTarget t in kPortCheckTargets)
        if (which(t)) outcomes[t] ?? TargetOutcome.noVerdict,
    ];
    if (seen.contains(TargetOutcome.gotOut)) return _Port.out;
    if (seen.isEmpty) return _Port.unknown;
    if (seen.every((TargetOutcome o) => o == TargetOutcome.didNotGetOut)) {
      return _Port.blocked;
    }
    if (seen.every((TargetOutcome o) => o == TargetOutcome.unavailable)) {
      return _Port.unavailable;
    }
    return _Port.unknown;
  }

  _Port tcp(int number) => stateOf(
    (PortCheckTarget t) =>
        t.transport == PortCheckTransport.tcp && t.port == number,
  );
  _Port udp(UdpProbeKind kind) => stateOf((PortCheckTarget t) => t.udp == kind);

  final bool baselinePassed = kPortCheckTargets.any(
    (PortCheckTarget t) => t.baseline && outcomes[t] == TargetOutcome.gotOut,
  );
  if (signInNeeded || !baselinePassed) {
    final String why = signInNeeded ? _signIn : _noInternet;
    return PortCheckReport(
      _groupNames
          .map(
            (String n) =>
                PortCheckGroup(n, TriageStatus.notChecked, <String>[why]),
          )
          .toList(),
      why,
    );
  }

  String line(
    String label,
    _Port p, {
    String servers = 'either test server',
    String? blockedNote,
  }) => switch (p) {
    _Port.out => '$label got out.',
    _Port.blocked =>
      '$label did not get out to $servers.'
          '${blockedNote == null ? '' : ' $blockedNote'}',
    _Port.unavailable => '$label could not be tried on this device.',
    _Port.unknown => '$label was not checked.',
  };

  TriageStatus decide(bool fine, bool off) => fine
      ? TriageStatus.looksFine
      : off
      ? TriageStatus.looksOff
      : TriageStatus.notChecked;

  final _Port p443 = tcp(443);
  final _Port p80 = tcp(80);
  final _Port p25 = tcp(25);
  final _Port p587 = tcp(587);
  final _Port p465 = tcp(465);
  final _Port p993 = tcp(993);
  final _Port p22 = tcp(22);
  final _Port p853 = tcp(853);
  final _Port dns = udp(UdpProbeKind.dns);
  final _Port ntp = udp(UdpProbeKind.ntp);
  final _Port stun = udp(UdpProbeKind.stun);
  final _Port quic = udp(UdpProbeKind.quic);

  final List<_Port> udpStates = <_Port>[dns, ntp, stun, quic];
  final bool noUdpAtAll = udpStates.every((_Port p) => p == _Port.blocked);
  final bool udpUnavailable = udpStates.every(
    (_Port p) => p == _Port.unavailable,
  );
  final bool otherUdpOut = dns == _Port.out || ntp == _Port.out;
  const String noUdp = 'No UDP got through at all.';

  final List<PortCheckGroup> groups = <PortCheckGroup>[
    PortCheckGroup(_groupNames[0], decide(p443 == _Port.out, false), <String>[
      line('Port 443', p443),
      line('Port 80', p80),
      line('QUIC (UDP 443)', quic),
    ]),
    PortCheckGroup(
      _groupNames[1],
      decide(
        p587 == _Port.out || p465 == _Port.out,
        p587 == _Port.blocked && p465 == _Port.blocked,
      ),
      <String>[
        line('Port 587', p587),
        line('Port 465', p465),
        line(
          'Port 25',
          p25,
          blockedNote: 'That is common and does not stop mail apps.',
        ),
        if (p587 == _Port.blocked && p465 == _Port.blocked)
          'Ports 587 and 465 are what mail apps use.',
      ],
    ),
    PortCheckGroup(
      _groupNames[2],
      decide(p993 == _Port.out, p993 == _Port.blocked),
      <String>[line('Port 993', p993)],
    ),
    PortCheckGroup(
      _groupNames[3],
      decide(p22 == _Port.out, p22 == _Port.blocked),
      <String>[line('Port 22', p22, servers: 'github.com or gitlab.com')],
    ),
    PortCheckGroup(
      _groupNames[4],
      decide(
        dns == _Port.out || p853 == _Port.out,
        dns == _Port.blocked && p853 == _Port.blocked,
      ),
      <String>[
        line('UDP 53', dns),
        line('TLS 853', p853),
        if (noUdpAtAll) noUdp,
      ],
    ),
    PortCheckGroup(
      _groupNames[5],
      udpUnavailable
          ? TriageStatus.cantCheck
          : decide(
              stun == _Port.out,
              stun == _Port.blocked && (otherUdpOut || noUdpAtAll),
            ),
      <String>[
        line('UDP 3478 and 19302 (STUN)', stun),
        if (noUdpAtAll)
          noUdp
        else if (stun == _Port.blocked && otherUdpOut)
          'Other UDP did get out. Calls may fall back to a slower path or '
              'fail to connect.',
      ],
    ),
    PortCheckGroup(_groupNames[6], TriageStatus.notChecked, <String>[
      _vpnGap,
      if (otherUdpOut)
        'Other UDP did get out.'
      else if (noUdpAtAll)
        'Other UDP did not get out.',
    ]),
  ];

  final bool anyOff = groups.any(
    (PortCheckGroup g) => g.status == TriageStatus.looksOff,
  );
  return PortCheckReport(
    groups,
    anyOff
        ? 'Some things did not get out. Looks off here means blocked on this '
              'network. It is not a fault in your device.'
        : 'Everything we could test got out.',
  );
}

const List<String> _groupNames = <String>[
  'Websites and apps',
  'Email sending',
  'Email reading',
  'Remote login (SSH)',
  'Name lookups (DNS)',
  'Calls and video',
  'VPN (IPsec)',
];

/// Check My Connection offers the port check only when its ladder points at the
/// internet or at services. Offered, never run: the tap opens the tool.
bool offerPortCheck(TriageLadder ladder) => ladder.rungs.any(
  (TriageRung r) =>
      (r.id == TriageRungId.internet || r.id == TriageRungId.services) &&
      r.status == TriageStatus.looksOff,
);
