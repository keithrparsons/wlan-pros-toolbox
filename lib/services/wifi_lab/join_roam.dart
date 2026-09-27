// Joining a network and roaming, frame by frame (Wi-Fi Classroom,
// eap-ladder, spec 21b): the Join and Roam modes of the 802.1X and EAP
// Ladder.
//
// Pure Dart, no Flutter. [buildJoin] returns the ordered messages of a first
// connection: the scan (with a channel-by-channel plan the stage draws as a
// strip), authentication, association, the EAP exchange for 802.1X (taken
// from the existing ladder model, eap_ladder.dart, unchanged), the 4-way
// handshake, DHCP, the address check and the first ARP and DNS. [buildRoam]
// returns a roam from the current AP to a target AP by one of five methods.
//
// CLEAN-ROOM BUILD (2026-09-26) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/21b-join-and-roam-frames.md and the research it cites
// (Deliverables/2026-09-26-wifi-classroom-wave4-research/brief.md §1, §2).
// Sources, as that brief tags them:
//   - Beacon interval: default 100 TU = 102.4 ms (a default, not a mandate).
//   - Scan dwell: Linux mac80211 software scan, about 30 ms per active
//     channel and 111 ms per passive channel (net/mac80211/scan.c). One real
//     example; many drivers scan in firmware with their own dwell.
//   - 6 GHz: probes only on the 15 preferred scanning channels (PSCs) unless
//     the AP is already known; discovery through RNR in 2.4/5 GHz beacons, or
//     FILS Discovery / unsolicited Probe Responses every 20 TU. 6 GHz
//     requires WPA3 or OWE, with PMF.
//   - IEEE 802.11: Open System and SAE authentication, (re)association and
//     what the request carries, the 4-way handshake (EAPOL-Key frames are
//     DATA frames, EtherType 0x888E), PMF (802.11w) protecting
//     deauthentication, disassociation and robust Action frames only once
//     keys exist, PMKSA caching, Fast BSS Transition over the air and over
//     the DS.
//   - OKC: a vendor extension, not IEEE; Apple's own key caching is not
//     compatible with it.
//   - RFC 2131 (DHCP), RFC 5227 (Address Conflict Detection: PROBE_WAIT 1 s,
//     PROBE_NUM 3, PROBE_MIN 1 s, PROBE_MAX 2 s, ANNOUNCE_WAIT 2 s),
//     RFC 4436 (Detecting Network Attachment in IPv4: unicast ARP to the
//     remembered gateway, under 10 ms).
//   - RFC 5169: EAP-TLS needs at least 3, typically 4 or more, round trips.
//
// NO PUBLISHED MEASUREMENT breaks a typical join down by phase, so every
// phase time here is a labeled input, not a claim. Channel lists are the US
// 20 MHz channels.

import 'package:flutter/foundation.dart' show immutable;

import 'eap_ladder.dart';

// ── Modes ───────────────────────────────────────────────────────────────────

/// The three modes of the tool. Authenticate is the original spec 21 ladder,
/// unchanged; Join and Roam are spec 21b.
enum LadderMode {
  join('Associate'),
  authenticate('Authenticate'),
  roam('Roam');

  const LadderMode(this.label);

  final String label;
}

// ── Lanes, legs and frames ──────────────────────────────────────────────────

/// Lanes of the Join and Roam ladders. Join uses client, AP, RADIUS (802.1X
/// only) and DHCP server; Roam uses client, current AP, target AP and RADIUS
/// (full 802.1X only).
enum JrLane {
  client('Client', 'supplicant'),
  ap('AP', 'authenticator'),
  currentAp('Current AP', 'associated now'),
  targetAp('Target AP', 'roaming to'),
  radius('RADIUS server', 'authentication server'),
  dhcp('DHCP server', 'wired LAN, also gateway and DNS');

  const JrLane(this.label, this.role);

  final String label;
  final String role;
}

/// Management, data, or a packet on the wire.
enum JrFrameClass {
  management('Management'),
  data('Data'),
  wire('Wired packet');

  const JrFrameClass(this.label);

  final String label;
}

/// The outer frame or packet type of a Join or Roam message.
enum JrFrameKind {
  management('802.11 management frame', JrFrameClass.management),
  action('802.11 Action frame (management)', JrFrameClass.management),
  eapol('EAPOL in an 802.11 data frame', JrFrameClass.data),
  eapolKey('EAPOL-Key in an 802.11 data frame', JrFrameClass.data),
  data('802.11 data frame', JrFrameClass.data),
  radius('RADIUS over UDP', JrFrameClass.wire),
  ds('AP to AP over the DS (wired)', JrFrameClass.wire);

  const JrFrameKind(this.label, this.frameClass);

  final String label;
  final JrFrameClass frameClass;
}

/// Groups of messages, drawn as headings on the ladder.
enum JrPhase {
  scan('Scan'),
  openAuth('802.11 authentication (Open System)'),
  saeAuth('SAE authentication: commit and confirm'),
  association('Association'),
  ftAction('FT over the DS: through the current AP'),
  ftAuth('FT authentication, over the air'),
  reassociation('Reassociation'),
  eapIdentity('EAP identity'),
  eapMethod('EAP method: TLS handshake'),
  innerAuth('Inside the TLS tunnel'),
  eapResult('EAP result'),
  fourWay('4-way handshake'),
  dhcp('DHCP: Discover, Offer, Request, Ack'),
  addressCheck('Address check'),
  arpDns('ARP for the gateway, then DNS'),
  later('Later: a management frame once keys exist');

  const JrPhase(this.label);

  final String label;
}

/// What a message's time is booked to: the per-phase clocks of Join, which
/// Roam folds into scan, authentication and key handshake.
enum JrClock {
  scan('Scan'),
  authentication('Authentication'),
  association('Association'),
  eap('802.1X (EAP)'),
  keys('4-way handshake'),
  dhcp('DHCP'),
  addressCheck('Address check'),
  arpDns('ARP and DNS'),
  later('After association');

  const JrClock(this.label);

  final String label;

  /// The Join timeline: every clock but [later], which is not part of the
  /// join.
  static const List<JrClock> joinClocks = <JrClock>[
    scan,
    authentication,
    association,
    eap,
    keys,
    dhcp,
    addressCheck,
    arpDns,
  ];
}

/// The three bars of the Roam timeline.
enum RoamBar {
  scan('Scan'),
  authentication('Authentication'),
  keyHandshake('Key handshake');

  const RoamBar(this.label);

  final String label;

  static RoamBar of(JrClock c) => switch (c) {
    JrClock.scan => scan,
    JrClock.keys => keyHandshake,
    _ => authentication,
  };
}

// ── Settings ────────────────────────────────────────────────────────────────

/// Security of the network the client joins.
enum JrSecurity {
  open('Open'),
  owe('OWE (Enhanced Open)'),
  psk('WPA2-Personal (PSK)'),
  sae('WPA3-Personal (SAE)'),
  dot1x('802.1X (Enterprise)');

  const JrSecurity(this.label);

  final String label;

  /// 6 GHz requires WPA3 or OWE with PMF.
  bool get allowedIn6GHz => this != open && this != psk;
}

enum JrBand {
  g24('2.4 GHz'),
  g5('5 GHz'),
  g6('6 GHz');

  const JrBand(this.label);

  final String label;
}

enum JrScanType {
  active('Active'),
  passive('Passive');

  const JrScanType(this.label);

  final String label;
}

/// How a client finds a 6 GHz AP.
enum JrSixGhzDiscovery {
  psc('PSC scan', 'Scan 6 GHz itself: probes go only to the 15 PSCs'),
  rnr('Known via RNR', 'A 2.4 or 5 GHz beacon already named the 6 GHz AP');

  const JrSixGhzDiscovery(this.shortLabel, this.label);

  final String shortLabel;
  final String label;
}

/// How the client checks its new address.
enum JrAddressCheck {
  acd(
    'ACD',
    'Address Conflict Detection (ACD, RFC 5227): the client checks that no '
        'one else already has its new address',
  ),
  dnav4(
    'DNAv4',
    'Detecting Network Attachment (DNAv4, RFC 4436): for a network the '
        'client has used before',
  );

  const JrAddressCheck(this.shortLabel, this.label);

  final String shortLabel;
  final String label;
}

/// PMF (802.11w) as the RSN element states it: MFPC and MFPR bits.
enum JrPmf {
  off('Off', 'MFPC 0, MFPR 0 (not capable)'),
  optional('Optional', 'MFPC 1, MFPR 0 (capable)'),
  required('Required', 'MFPC 1, MFPR 1 (required)');

  const JrPmf(this.label, this.bits);

  final String label;

  /// The two RSN capability bits, worded.
  final String bits;

  /// PMF is used when both sides are capable; the client here always is.
  bool get inUse => this != off;
}

/// How the client roams to the target AP.
enum JrRoamMethod {
  full('Full 802.1X', 'Full 802.1X: EAP again with the RADIUS server'),
  pmkCaching(
    'PMK caching',
    'PMK caching: back to an AP that still holds this client\'s PMK',
  ),
  okc('OKC', 'OKC (opportunistic key caching): a vendor extension, not IEEE'),
  ftOverAir('FT over the air', '802.11r FT over the air, to the target AP'),
  ftOverDs('FT over the DS', '802.11r FT over the DS, through the current AP');

  const JrRoamMethod(this.shortLabel, this.label);

  final String shortLabel;
  final String label;

  bool get isFt => this == ftOverAir || this == ftOverDs;
}

// ── Setting ranges and constants ────────────────────────────────────────────

/// Beacon interval: the default 100 TU (1 TU = 1024 µs). A default, not a
/// mandate.
const double kBeaconIntervalMs = 102.4;

/// FILS Discovery or unsolicited Probe Response interval in 6 GHz: 20 TU.
const double kFilsIntervalMs = 20.48;

/// The model puts the first beacon on the AP's channel half an interval into
/// the dwell (the average wait when the phase is random); FILS frames the
/// same way at half of 20 TU.
const double kFirstBeaconOffsetMs = kBeaconIntervalMs / 2;
const double kFirstFilsOffsetMs = kFilsIntervalMs / 2;

/// Where in the dwell the probe goes out, and when the answer comes back
/// (illustrative).
const double kProbeAtMs = 1;
const double kProbeResponseAtMs = 3;

/// Dwell per channel, ms. Defaults from Linux mac80211 (about 30 and 111).
const double kMinActiveDwellMs = 10;
const double kMaxActiveDwellMs = 100;
const double kDefaultActiveDwellMs = 30;
const double kMinPassiveDwellMs = 20;
const double kMaxPassiveDwellMs = 250;
const double kDefaultPassiveDwellMs = 111;

/// One frame over the air including its wait for the medium and its ACK, ms
/// (illustrative).
const double kMinFrameMs = 0.5;
const double kMaxFrameMs = 5;

/// Public-key work (TLS, SAE or OWE), ms (illustrative).
const double kMinCryptoMs = 0;
const double kMaxCryptoMs = 500;

/// A round trip on the wired LAN (DHCP server, gateway, DNS), ms.
const double kMinLanRttMs = 1;
const double kMaxLanRttMs = 50;

/// AP to AP and back over the DS (FT over the DS), ms.
const double kMinDsRttMs = 1;
const double kMaxDsRttMs = 50;

/// RFC 5227: wait 0 to PROBE_WAIT (1 s) before the first probe, then
/// PROBE_MIN to PROBE_MAX (1 to 2 s) between probes, then ANNOUNCE_WAIT.
const double kMaxAcdProbeWaitMs = 1000;
const double kMinAcdSpacingMs = 1000;
const double kMaxAcdSpacingMs = 2000;
const double kAcdAnnounceWaitMs = 2000;
const int kAcdProbeCount = 3;

/// Published figures, shown only as labeled context (brief §2).
const double kFtOverAirCaptureMs = 14;
const double kFtOverDsCaptureMs = 88;

/// US 20 MHz channels.
const List<int> k24Channels = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
const List<int> k5Channels = <int>[
  36, 40, 44, 48, 52, 56, 60, 64, //
  100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, //
  149, 153, 157, 161, 165,
];

/// 6 GHz 20 MHz channels 1, 5, ... 233 (59 channels).
final List<int> k6Channels = List<int>.generate(59, (int i) => 1 + 4 * i);

/// The 15 preferred scanning channels: 5, 21, ... 229.
final Set<int> k6Pscs = <int>{for (int i = 0; i < 15; i++) 5 + 16 * i};

/// 5 GHz channels where a client listens before it may transmit (DFS).
bool isDfsChannel(int ch) => ch >= 52 && ch <= 144;

/// The AP's channel in each band (a PSC in 6 GHz).
int targetChannelFor(JrBand band) => switch (band) {
  JrBand.g24 => 6,
  JrBand.g5 => 44,
  JrBand.g6 => 37,
};

List<int> channelsFor(JrBand band) => switch (band) {
  JrBand.g24 => k24Channels,
  JrBand.g5 => k5Channels,
  JrBand.g6 => k6Channels,
};

// ── Config ──────────────────────────────────────────────────────────────────

/// Everything the Join and Roam ladders depend on. Both modes share the scan
/// and timing settings, so a class can switch between them and compare.
@immutable
class JrConfig {
  const JrConfig({
    this.security = JrSecurity.psk,
    this.eapMethod = LadderMethod.eapTls,
    this.inner = LadderInner.mschapv2,
    this.certFragments = 1,
    this.pmf = JrPmf.optional,
    this.band = JrBand.g5,
    this.scanType = JrScanType.active,
    this.sixGhz = JrSixGhzDiscovery.psc,
    this.addressCheck = JrAddressCheck.acd,
    this.roamMethod = JrRoamMethod.full,
    this.activeDwellMs = kDefaultActiveDwellMs,
    this.passiveDwellMs = kDefaultPassiveDwellMs,
    this.frameMs = kAirFrameMs,
    this.radiusRttMs = 10,
    this.cryptoMs = 50,
    this.lanRttMs = 5,
    this.dsRttMs = 5,
    this.acdProbeWaitMs = 500,
    this.acdSpacingMs = 1500,
  });

  /// Join only. Roam is always an 802.1X network.
  final JrSecurity security;

  /// EAP-TLS, PEAP or EAP-TTLS, for 802.1X.
  final LadderMethod eapMethod;
  final LadderInner inner;
  final int certFragments;

  /// For WPA2-Personal and 802.1X outside 6 GHz; the rest force it.
  final JrPmf pmf;

  final JrBand band;
  final JrScanType scanType;

  /// 6 GHz only.
  final JrSixGhzDiscovery sixGhz;

  /// Join only.
  final JrAddressCheck addressCheck;

  /// Roam only.
  final JrRoamMethod roamMethod;

  final double activeDwellMs;
  final double passiveDwellMs;
  final double frameMs;
  final double radiusRttMs;
  final double cryptoMs;
  final double lanRttMs;
  final double dsRttMs;
  final double acdProbeWaitMs;
  final double acdSpacingMs;

  /// The security the join actually uses: in 6 GHz, Open becomes OWE and
  /// WPA2-Personal becomes WPA3-Personal, because 6 GHz requires WPA3 or
  /// OWE.
  JrSecurity get effectiveSecurity {
    if (band != JrBand.g6 || security.allowedIn6GHz) return security;
    return security == JrSecurity.open ? JrSecurity.owe : JrSecurity.sae;
  }

  /// Whether the 6 GHz rule changed the chosen security.
  bool get securityForcedBy6GHz => effectiveSecurity != security;

  /// PMF as used for [s]: Open has no keys to protect with; OWE and SAE
  /// require it; 6 GHz requires it.
  JrPmf pmfFor(JrSecurity s) {
    if (s == JrSecurity.open) return JrPmf.off;
    if (s == JrSecurity.owe || s == JrSecurity.sae) return JrPmf.required;
    if (band == JrBand.g6) return JrPmf.required;
    return pmf;
  }

  /// Whether the PMF setting is the user's to choose for [s].
  bool pmfChoosable(JrSecurity s) =>
      (s == JrSecurity.psk || s == JrSecurity.dot1x) && band != JrBand.g6;

  /// The existing ladder's configuration for the EAP middle.
  LadderConfig get eapConfig => LadderConfig(
    method: eapMethod,
    inner: inner,
    certFragments: certFragments,
    radiusRttMs: radiusRttMs,
  );

  JrConfig copyWith({
    JrSecurity? security,
    LadderMethod? eapMethod,
    LadderInner? inner,
    int? certFragments,
    JrPmf? pmf,
    JrBand? band,
    JrScanType? scanType,
    JrSixGhzDiscovery? sixGhz,
    JrAddressCheck? addressCheck,
    JrRoamMethod? roamMethod,
    double? activeDwellMs,
    double? passiveDwellMs,
    double? frameMs,
    double? radiusRttMs,
    double? cryptoMs,
    double? lanRttMs,
    double? dsRttMs,
    double? acdProbeWaitMs,
    double? acdSpacingMs,
  }) {
    final LadderMethod m = eapMethod ?? this.eapMethod;
    return JrConfig(
      security: security ?? this.security,
      // Only the 802.1X methods belong here.
      eapMethod: m.uses8021X ? m : this.eapMethod,
      inner: inner ?? this.inner,
      certFragments: (certFragments ?? this.certFragments).clamp(
        kMinCertFragments,
        kMaxCertFragments,
      ),
      pmf: pmf ?? this.pmf,
      band: band ?? this.band,
      scanType: scanType ?? this.scanType,
      sixGhz: sixGhz ?? this.sixGhz,
      addressCheck: addressCheck ?? this.addressCheck,
      roamMethod: roamMethod ?? this.roamMethod,
      activeDwellMs: (activeDwellMs ?? this.activeDwellMs).clamp(
        kMinActiveDwellMs,
        kMaxActiveDwellMs,
      ),
      passiveDwellMs: (passiveDwellMs ?? this.passiveDwellMs).clamp(
        kMinPassiveDwellMs,
        kMaxPassiveDwellMs,
      ),
      frameMs: (frameMs ?? this.frameMs).clamp(kMinFrameMs, kMaxFrameMs),
      radiusRttMs: (radiusRttMs ?? this.radiusRttMs).clamp(
        kMinRadiusRttMs,
        kMaxRadiusRttMs,
      ),
      cryptoMs: (cryptoMs ?? this.cryptoMs).clamp(kMinCryptoMs, kMaxCryptoMs),
      lanRttMs: (lanRttMs ?? this.lanRttMs).clamp(kMinLanRttMs, kMaxLanRttMs),
      dsRttMs: (dsRttMs ?? this.dsRttMs).clamp(kMinDsRttMs, kMaxDsRttMs),
      acdProbeWaitMs: (acdProbeWaitMs ?? this.acdProbeWaitMs).clamp(
        0,
        kMaxAcdProbeWaitMs,
      ),
      acdSpacingMs: (acdSpacingMs ?? this.acdSpacingMs).clamp(
        kMinAcdSpacingMs,
        kMaxAcdSpacingMs,
      ),
    );
  }

  List<Object> get _props => <Object>[
    security,
    eapMethod,
    inner,
    certFragments,
    pmf,
    band,
    scanType,
    sixGhz,
    addressCheck,
    roamMethod,
    activeDwellMs,
    passiveDwellMs,
    frameMs,
    radiusRttMs,
    cryptoMs,
    lanRttMs,
    dsRttMs,
    acdProbeWaitMs,
    acdSpacingMs,
  ];

  @override
  bool operator ==(Object other) {
    if (other is! JrConfig) return false;
    final List<Object> a = _props;
    final List<Object> b = other._props;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_props);
}

// ── The scan ────────────────────────────────────────────────────────────────

/// One channel visit in the scan.
@immutable
class JrScanChannel {
  const JrScanChannel({
    required this.number,
    required this.startMs,
    required this.dwellMs,
    required this.probed,
    required this.psc,
    required this.dfs,
    required this.target,
  });

  final int number;
  final double startMs;
  final double dwellMs;

  /// A probe request goes out here (otherwise the client only listens).
  final bool probed;

  /// A 6 GHz preferred scanning channel.
  final bool psc;

  /// A 5 GHz DFS channel: listened to, never probed.
  final bool dfs;

  /// The AP's channel.
  final bool target;

  double get endMs => startMs + dwellMs;
}

enum JrScanEventKind {
  probeRequest('Probe Request'),
  probeResponse('Probe Response'),
  beacon('Beacon'),
  fils('FILS Discovery');

  const JrScanEventKind(this.label);

  final String label;
}

/// A frame in the scan, on the channel strip's time axis.
@immutable
class JrScanEvent {
  const JrScanEvent({
    required this.kind,
    required this.channel,
    required this.atMs,
    required this.heard,
  });

  final JrScanEventKind kind;
  final int channel;
  final double atMs;

  /// The client's radio was on this channel when it was sent.
  final bool heard;
}

/// The whole scan: which channels, how long on each, and which of the AP's
/// frames the client caught.
@immutable
class JrScanPlan {
  const JrScanPlan({
    required this.band,
    required this.scanType,
    required this.channels,
    required this.events,
    required this.targetChannel,
    required this.rnr,
  });

  final JrBand band;
  final JrScanType scanType;
  final List<JrScanChannel> channels;
  final List<JrScanEvent> events;
  final int targetChannel;

  /// 6 GHz found through RNR: only the AP's channel is visited.
  final bool rnr;

  double get totalMs => channels.isEmpty ? 0 : channels.last.endMs;

  int get probedCount => channels.where((JrScanChannel c) => c.probed).length;

  int get listenedCount => channels.length - probedCount;

  JrScanChannel get target =>
      channels.firstWhere((JrScanChannel c) => c.target);

  /// The first frame from the AP the client heard, or null.
  JrScanEvent? get firstHeard {
    for (final JrScanEvent e in events) {
      if (e.heard && e.kind != JrScanEventKind.probeRequest) return e;
    }
    return null;
  }

  bool get found => firstHeard != null;

  /// Channels a 6 GHz active scan probed: must all be PSCs unless RNR named
  /// the AP.
  List<int> get probedChannels => <int>[
    for (final JrScanChannel c in channels)
      if (c.probed) c.number,
  ];
}

/// Builds the scan for [c].
JrScanPlan buildScan(JrConfig c) {
  final JrBand band = c.band;
  final int target = targetChannelFor(band);
  final bool rnr = band == JrBand.g6 && c.sixGhz == JrSixGhzDiscovery.rnr;
  final bool active = c.scanType == JrScanType.active;
  final List<JrScanChannel> channels = <JrScanChannel>[];
  double t = 0;
  final List<int> list = rnr ? <int>[target] : channelsFor(band);
  for (final int ch in list) {
    final bool psc = band == JrBand.g6 && k6Pscs.contains(ch);
    final bool dfs = band == JrBand.g5 && isDfsChannel(ch);
    bool probed;
    bool visit = true;
    if (!active) {
      probed = false;
    } else if (band == JrBand.g6 && !rnr) {
      // 6 GHz active: probes only on PSCs; the rest are not visited.
      probed = psc;
      visit = psc;
    } else {
      // A DFS channel is listened to; RNR names the AP, so a directed
      // probe is allowed on its channel.
      probed = !dfs;
    }
    if (!visit) continue;
    final double dwell = probed ? c.activeDwellMs : c.passiveDwellMs;
    channels.add(
      JrScanChannel(
        number: ch,
        startMs: t,
        dwellMs: dwell,
        probed: probed,
        psc: psc,
        dfs: dfs,
        target: ch == target,
      ),
    );
    t += dwell;
  }
  final double total = t;
  final JrScanChannel tc = channels.firstWhere((JrScanChannel x) => x.target);
  final List<JrScanEvent> events = <JrScanEvent>[];
  for (final JrScanChannel ch in channels) {
    if (ch.probed) {
      events.add(
        JrScanEvent(
          kind: JrScanEventKind.probeRequest,
          channel: ch.number,
          atMs: ch.startMs + kProbeAtMs,
          heard: true,
        ),
      );
    }
  }
  bool inDwell(double at) => at >= tc.startMs && at <= tc.endMs;
  // The AP beacons all through the scan, whether or not the client's radio
  // is on its channel.
  for (
    double at = tc.startMs + kFirstBeaconOffsetMs;
    at >= 0 && at <= total;
    at += kBeaconIntervalMs
  ) {
    events.add(
      JrScanEvent(
        kind: JrScanEventKind.beacon,
        channel: target,
        atMs: at,
        heard: inDwell(at),
      ),
    );
  }
  for (
    double at = tc.startMs + kFirstBeaconOffsetMs - kBeaconIntervalMs;
    at >= 0;
    at -= kBeaconIntervalMs
  ) {
    events.add(
      JrScanEvent(
        kind: JrScanEventKind.beacon,
        channel: target,
        atMs: at,
        heard: false,
      ),
    );
  }
  if (band == JrBand.g6) {
    for (
      double at = tc.startMs + kFirstFilsOffsetMs;
      at <= total;
      at += kFilsIntervalMs
    ) {
      events.add(
        JrScanEvent(
          kind: JrScanEventKind.fils,
          channel: target,
          atMs: at,
          heard: inDwell(at),
        ),
      );
    }
  }
  if (tc.probed) {
    events.add(
      JrScanEvent(
        kind: JrScanEventKind.probeResponse,
        channel: target,
        atMs: tc.startMs + kProbeResponseAtMs,
        heard: kProbeResponseAtMs <= tc.dwellMs,
      ),
    );
  }
  events.sort((JrScanEvent a, JrScanEvent b) => a.atMs.compareTo(b.atMs));
  return JrScanPlan(
    band: band,
    scanType: c.scanType,
    channels: List<JrScanChannel>.unmodifiable(channels),
    events: List<JrScanEvent>.unmodifiable(events),
    targetChannel: target,
    rnr: rnr,
  );
}

// ── Messages and sequences ──────────────────────────────────────────────────

/// One line of what a frame carries (tap a message to see them).
typedef JrField = (String name, String value);

/// One arrow on a Join or Roam ladder.
@immutable
class JrMessage {
  const JrMessage({
    required this.from,
    required this.to,
    required this.kind,
    required this.phase,
    required this.clock,
    required this.label,
    required this.description,
    required this.ms,
    this.via,
    this.detail,
    this.fields = const <JrField>[],
    this.encrypted = false,
    this.pmfProtected = false,
    this.tunneled = false,
    this.missed = false,
    this.milestone,
    this.milestoneText,
  });

  final JrLane from;
  final JrLane to;

  /// The AP the frame is bridged through (DHCP, ARP, DNS): over the air to
  /// the AP, then on the wire beyond it. Null for a single hop.
  final JrLane? via;

  final JrFrameKind kind;
  final JrPhase phase;
  final JrClock clock;
  final String label;
  final String? detail;
  final String description;

  /// What the frame carries, for the caption.
  final List<JrField> fields;

  /// Time booked to this message (its frame, its wait, its share of a round
  /// trip), ms.
  final double ms;

  /// An 802.11 data frame encrypted with the session keys (after message 4).
  final bool encrypted;

  /// A management frame protected by PMF.
  final bool pmfProtected;

  /// Inside the EAP method's TLS tunnel.
  final bool tunneled;

  /// Sent while the client's radio was elsewhere (a missed beacon).
  final bool missed;

  final LadderMilestone? milestone;
  final String? milestoneText;

  bool get isManagement => kind.frameClass == JrFrameClass.management;

  bool get isData => kind.frameClass == JrFrameClass.data;

  /// The hops this arrow crosses, in order.
  List<(JrLane, JrLane)> get hops => via == null
      ? <(JrLane, JrLane)>[(from, to)]
      : <(JrLane, JrLane)>[(from, via!), (via!, to)];

  /// Frames over the air: hops with the client at one end.
  int get airHops =>
      hops.where(((JrLane, JrLane) h) => legOf(h) == LadderLeg.air).length;

  int get wireHops => hops.length - airHops;

  /// The leg of the first hop.
  LadderLeg get leg => legOf(hops.first);

  /// Over the air when the client is at one end, otherwise on the wire.
  static LadderLeg legOf((JrLane, JrLane) hop) =>
      hop.$1 == JrLane.client || hop.$2 == JrLane.client
      ? LadderLeg.air
      : LadderLeg.wire;

  String get contents => detail ?? '';
}

/// A built Join or Roam ladder and its counts.
@immutable
class JrSequence {
  const JrSequence._({
    required this.mode,
    required this.config,
    required this.messages,
    required this.scan,
    required this.lanes,
  });

  final LadderMode mode;
  final JrConfig config;
  final List<JrMessage> messages;
  final JrScanPlan scan;

  /// Lanes in drawing order, left to right.
  final List<JrLane> lanes;

  int get length => messages.length;

  /// The scan found the AP; otherwise the ladder stops after the scan.
  bool get found => scan.found;

  JrSecurity get security =>
      mode == LadderMode.roam ? JrSecurity.dot1x : config.effectiveSecurity;

  JrPmf get pmf => config.pmfFor(security);

  /// Over-the-air frames, excluding a missed beacon.
  int get airCount => messages
      .where((JrMessage m) => !m.missed)
      .fold(0, (int s, JrMessage m) => s + m.airHops);

  int get managementCount =>
      messages.where((JrMessage m) => !m.missed && m.isManagement).length;

  /// Air frames that are 802.11 data frames (EAPOL, EAPOL-Key, DHCP...).
  int get dataCount => messages
      .where((JrMessage m) => !m.missed && m.isData)
      .fold(0, (int s, JrMessage m) => s + m.airHops);

  /// Packets on the wire: RADIUS, AP to AP, and the wired half of bridged
  /// frames.
  int get wireCount => messages.fold(0, (int s, JrMessage m) => s + m.wireHops);

  int get radiusCount =>
      messages.where((JrMessage m) => m.kind == JrFrameKind.radius).length;

  int get radiusRoundTrips => messages
      .where(
        (JrMessage m) => m.kind == JrFrameKind.radius && m.to == JrLane.radius,
      )
      .length;

  int get dsCount =>
      messages.where((JrMessage m) => m.kind == JrFrameKind.ds).length;

  /// Wire halves of bridged frames (DHCP, ARP, DNS).
  int get lanCount => wireCount - radiusCount - dsCount;

  /// Time per clock, ms.
  Map<JrClock, double> get clockTotals {
    final Map<JrClock, double> out = <JrClock, double>{
      for (final JrClock c in JrClock.values) c: 0,
    };
    for (final JrMessage m in messages) {
      out[m.clock] = out[m.clock]! + m.ms;
    }
    return out;
  }

  /// Time per Roam bar, ms.
  Map<RoamBar, double> get roamTotals {
    final Map<RoamBar, double> out = <RoamBar, double>{
      for (final RoamBar b in RoamBar.values) b: 0,
    };
    for (final JrMessage m in messages) {
      if (m.clock == JrClock.later) continue;
      final RoamBar b = RoamBar.of(m.clock);
      out[b] = out[b]! + m.ms;
    }
    return out;
  }

  double get scanMs => clockTotals[JrClock.scan]!;

  /// Total time, excluding anything after the join.
  double get totalMs => messages
      .where((JrMessage m) => m.clock != JrClock.later)
      .fold(0.0, (double s, JrMessage m) => s + m.ms);

  /// Time up to and including message [count] (1-based count of sent
  /// messages), excluding anything after the join.
  double elapsedMs(int count) => messages
      .take(count)
      .where((JrMessage m) => m.clock != JrClock.later)
      .fold(0.0, (double s, JrMessage m) => s + m.ms);

  /// Time on [clock] up to message [count].
  double clockElapsedMs(JrClock clock, int count) => messages
      .take(count)
      .where((JrMessage m) => m.clock == clock)
      .fold(0.0, (double s, JrMessage m) => s + m.ms);

  List<JrMessage> inPhase(JrPhase phase) =>
      messages.where((JrMessage m) => m.phase == phase).toList(growable: false);

  /// Messages after the scan.
  List<JrMessage> get afterScan => messages
      .where((JrMessage m) => m.phase != JrPhase.scan)
      .toList(growable: false);

  int indexOfMilestone(LadderMilestone milestone) =>
      messages.indexWhere((JrMessage m) => m.milestone == milestone);

  /// The heading for [phase] on this ladder.
  String phaseTitle(JrPhase phase) {
    switch (phase) {
      case JrPhase.scan:
        final String where = scan.rnr
            ? 'the 6 GHz channel RNR named'
            : '${scan.channels.length} channel'
                  '${scan.channels.length == 1 ? '' : 's'}';
        return 'Scan: ${scan.scanType.label.toLowerCase()}, $where; the AP '
            'is on channel ${scan.targetChannel}';
      case JrPhase.addressCheck:
        return config.addressCheck == JrAddressCheck.acd
            ? 'Address check: Address Conflict Detection (ACD, RFC 5227)'
            : 'Address check: Detecting Network Attachment (DNAv4, RFC 4436)';
      case JrPhase.arpDns:
        return config.addressCheck == JrAddressCheck.acd
            ? 'ARP for the gateway, then DNS'
            : 'DNS (the DNAv4 check already found the gateway)';
      default:
        return phase.label;
    }
  }
}

/// What a roam method skipped, compared with a full 802.1X roam.
@immutable
class RoamSkipped {
  const RoamSkipped({required this.lines, required this.fewerMessages});

  final List<String> lines;
  final int fewerMessages;
}

/// Builds a first connection for [c].
JrSequence buildJoin(JrConfig c) {
  final _JrBuilder b = _JrBuilder(c, LadderMode.join);
  b.buildJoin();
  final JrSecurity s = c.effectiveSecurity;
  return JrSequence._(
    mode: LadderMode.join,
    config: c,
    messages: List<JrMessage>.unmodifiable(b.out),
    scan: b.scan,
    lanes: <JrLane>[
      JrLane.client,
      JrLane.ap,
      if (s == JrSecurity.dot1x) JrLane.radius,
      JrLane.dhcp,
    ],
  );
}

/// Builds a roam from the current AP to the target AP for [c].
JrSequence buildRoam(JrConfig c) {
  final _JrBuilder b = _JrBuilder(c, LadderMode.roam);
  b.buildRoam();
  return JrSequence._(
    mode: LadderMode.roam,
    config: c,
    messages: List<JrMessage>.unmodifiable(b.out),
    scan: b.scan,
    lanes: <JrLane>[
      JrLane.client,
      JrLane.currentAp,
      JrLane.targetAp,
      if (c.roamMethod == JrRoamMethod.full) JrLane.radius,
    ],
  );
}

/// Compares a roam with a full 802.1X roam of the same settings.
RoamSkipped roamSkippedVersusFull(JrSequence seq) {
  final JrConfig c = seq.config;
  final String scan = formatJrMs(seq.scanMs);
  final String scanLine =
      'Not the scan: $scan, the same for every method. No roam method '
      'shortens it.';
  if (c.roamMethod == JrRoamMethod.full) {
    return RoamSkipped(
      lines: <String>['Nothing: this is the full 802.1X roam.', scanLine],
      fewerMessages: 0,
    );
  }
  final JrSequence full = buildRoam(c.copyWith(roamMethod: JrRoamMethod.full));
  final List<JrMessage> eap = full.messages
      .where((JrMessage m) => _isEapPhase(m.phase))
      .toList();
  final int eapAir = eap.fold(0, (int s, JrMessage m) => s + m.airHops);
  final int eapWire = eap.fold(0, (int s, JrMessage m) => s + m.wireHops);
  final List<String> lines = <String>[
    'The whole EAP exchange: $eapAir frames over the air and $eapWire RADIUS '
        'messages on the wire (${full.radiusRoundTrips} round trips). The '
        'RADIUS server is not asked.',
  ];
  if (c.roamMethod.isFt) {
    lines.add(
      'The separate 4-way handshake: its nonces and MICs ride in the FT '
      'frames instead.',
    );
  }
  if (c.roamMethod == JrRoamMethod.ftOverDs) {
    lines.add(
      'Open System authentication with the target AP: the FT exchange goes '
      'through the current AP over the wire instead, before the client '
      'leaves it.',
    );
  } else if (c.roamMethod == JrRoamMethod.ftOverAir) {
    lines.add('Open System authentication: FT authentication takes its place.');
  }
  lines.add(scanLine);
  return RoamSkipped(lines: lines, fewerMessages: full.length - seq.length);
}

bool _isEapPhase(JrPhase p) =>
    p == JrPhase.eapIdentity ||
    p == JrPhase.eapMethod ||
    p == JrPhase.innerAuth ||
    p == JrPhase.eapResult;

/// "7 ms", "5.52 s"; fractions of a millisecond shown to one decimal.
String formatJrMs(double ms) {
  if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(2)} s';
  if (ms != ms.roundToDouble() && ms < 10) {
    return '${ms.toStringAsFixed(1)} ms';
  }
  return '${ms.round()} ms';
}

// ── Builder ─────────────────────────────────────────────────────────────────

class _JrBuilder {
  _JrBuilder(this.c, this.mode) : scan = buildScan(c);

  final JrConfig c;
  final LadderMode mode;
  final JrScanPlan scan;
  final List<JrMessage> out = <JrMessage>[];

  static const JrLane _c = JrLane.client;

  bool get _roam => mode == LadderMode.roam;

  JrSecurity get _sec => _roam ? JrSecurity.dot1x : c.effectiveSecurity;

  JrPmf get _pmf => c.pmfFor(_sec);

  /// The AP the client authenticates with: the only AP when joining, the
  /// target AP when roaming.
  JrLane get _ap => _roam ? JrLane.targetAp : JrLane.ap;

  String get _ssid => 'Classroom';

  // ── Join ──────────────────────────────────────────────────────────────────

  void buildJoin() {
    _scan();
    if (!scan.found) return;
    if (_sec == JrSecurity.sae) {
      _sae();
    } else {
      _openAuth(roam: false);
    }
    _association(reassociation: false);
    if (_sec == JrSecurity.dot1x) _eap();
    if (_sec != JrSecurity.open) _fourWay();
    _dhcp();
    _addressCheck();
    _arpDns();
    _later();
  }

  // ── Roam ──────────────────────────────────────────────────────────────────

  void buildRoam() {
    _scan();
    if (!scan.found) return;
    switch (c.roamMethod) {
      case JrRoamMethod.full:
        _openAuth(roam: true);
        _association(reassociation: true);
        _eap();
        _fourWay();
      case JrRoamMethod.pmkCaching:
      case JrRoamMethod.okc:
        _openAuth(roam: true);
        _association(reassociation: true);
        _fourWay();
      case JrRoamMethod.ftOverAir:
        _ftOverAir();
        _ftReassociation();
      case JrRoamMethod.ftOverDs:
        _ftOverDs();
        _ftReassociation();
    }
  }

  // ── Scan ──────────────────────────────────────────────────────────────────

  String get _akm => switch (_sec) {
    JrSecurity.open => 'none (open network)',
    JrSecurity.owe => 'OWE',
    JrSecurity.psk => 'PSK',
    JrSecurity.sae => 'SAE',
    JrSecurity.dot1x =>
      _roam && c.roamMethod.isFt ? 'FT over 802.1X' : '802.1X',
  };

  void _scan() {
    final JrScanPlan p = scan;
    final double total = p.totalMs;
    final String chs = p.rnr
        ? 'one 6 GHz channel'
        : '${p.channels.length} channels in ${p.band.label}';
    final String cost =
        'The whole scan, $chs, takes ${formatJrMs(total)} at the dwell '
        'settings.';
    bool first = true;
    double take() {
      final double v = first ? total : 0;
      first = false;
      return v;
    }

    if (p.rnr) {
      out.add(
        JrMessage(
          from: _ap,
          to: _c,
          kind: JrFrameKind.management,
          phase: JrPhase.scan,
          clock: JrClock.scan,
          label: 'Beacon (2.4 or 5 GHz radio)',
          detail: 'RNR: 6 GHz AP on channel ${p.targetChannel}',
          fields: <JrField>[
            (
              'Reduced Neighbor Report',
              'the 6 GHz AP\'s channel (${p.targetChannel}), BSSID and '
                  'short SSID',
            ),
          ],
          description:
              'Earlier, a beacon from the same AP\'s 2.4 or 5 GHz radio '
              'carried a Reduced Neighbor Report naming its 6 GHz radio. '
              'The client can now go straight to that one 6 GHz channel. '
              'The time to hear this beacon is not counted.',
          ms: 0,
        ),
      );
    }

    if (!p.found) {
      final JrScanChannel t = p.target;
      out.add(
        JrMessage(
          from: _ap,
          to: _c,
          kind: JrFrameKind.management,
          phase: JrPhase.scan,
          clock: JrClock.scan,
          label: 'Beacon (missed)',
          detail: 'Channel ${p.targetChannel}',
          missed: true,
          description:
              'The client listened on channel ${p.targetChannel} for '
              '${formatJrMs(t.dwellMs)}, but the AP\'s next beacon came '
              '${formatJrMs(kFirstBeaconOffsetMs)} into the dwell. The radio '
              'had already moved on, so the network was not found on this '
              'pass. Lengthen the passive dwell or use an active scan. $cost',
          ms: take(),
        ),
      );
      return;
    }

    final JrScanEvent heard = p.firstHeard!;
    if (heard.kind == JrScanEventKind.probeResponse) {
      final bool directed = p.rnr;
      out.add(
        JrMessage(
          from: _c,
          to: _ap,
          kind: JrFrameKind.management,
          phase: JrPhase.scan,
          clock: JrClock.scan,
          label: 'Probe Request',
          detail: directed
              ? 'Directed, channel ${p.targetChannel}'
              : 'Broadcast, channel ${p.targetChannel}',
          fields: <JrField>[
            ('SSID', directed ? _ssid : 'wildcard (any network)'),
            ('Supported rates and capabilities', 'the client\'s own'),
          ],
          description: directed
              ? 'RNR named this AP, so the client may probe it on a 6 GHz '
                    'channel that is not a PSC. $cost'
              : 'The client asks which networks are on this channel. It sends '
                    'the same probe on each of the ${p.probedCount} channels '
                    'it probes${p.listenedCount > 0 ? ' and only listens on the other ${p.listenedCount}' : ''}. '
                    '$cost',
          ms: take(),
        ),
      );
      out.add(
        JrMessage(
          from: _ap,
          to: _c,
          kind: JrFrameKind.management,
          phase: JrPhase.scan,
          clock: JrClock.scan,
          label: 'Probe Response',
          detail: 'SSID $_ssid, RSN: $_akm',
          fields: _apAdvertises(),
          description:
              'The AP answers with its SSID, rates, capabilities and security '
              '(the RSN element). Probe Responses are never protected, even '
              'with PMF.',
          ms: take(),
        ),
      );
      return;
    }

    final bool fils = heard.kind == JrScanEventKind.fils;
    out.add(
      JrMessage(
        from: _ap,
        to: _c,
        kind: JrFrameKind.management,
        phase: JrPhase.scan,
        clock: JrClock.scan,
        label: fils ? 'FILS Discovery' : 'Beacon',
        detail: fils
            ? 'or an unsolicited Probe Response, every 20 TU'
            : 'Every ${kBeaconIntervalMs.toStringAsFixed(1)} ms, channel '
                  '${p.targetChannel}',
        fields: fils
            ? <JrField>[
                ('Interval', '20 TU (20.48 ms)'),
                ('Carries', 'SSID (short form) and BSSID, enough to find it'),
              ]
            : _apAdvertises(),
        description: fils
            ? 'A 6 GHz AP sends a short discovery frame every 20 TU, so a '
                  'passive scanner finds it long before the next beacon. '
                  '$cost'
            : 'A passive scan only listens. The client heard this beacon '
                  'because its radio was on channel ${p.targetChannel} when '
                  'the beacon went out. Beacons are never protected, even '
                  'with PMF. $cost',
        ms: take(),
      ),
    );
  }

  List<JrField> _apAdvertises() => <JrField>[
    ('SSID', _ssid),
    ('Beacon interval', '100 TU (102.4 ms, a default)'),
    ('Supported rates', _rates),
    if (_sec != JrSecurity.open) ('RSN element', 'AKM: $_akm; cipher CCMP-128'),
    if (_sec != JrSecurity.open) ('PMF', _pmf.bits),
    if (_roam && c.roamMethod.isFt)
      ('Mobility Domain element', 'the FT mobility domain'),
  ];

  String get _rates => c.band == JrBand.g24
      ? '1, 2, 5.5, 11 Mb/s, and 6 to 54 Mb/s as Extended Supported Rates'
      : '6, 9, 12, 18, 24, 36, 48, 54 Mb/s';

  // ── Authentication ────────────────────────────────────────────────────────

  void _openAuth({required bool roam}) {
    out.add(
      JrMessage(
        from: _c,
        to: _ap,
        kind: JrFrameKind.management,
        phase: JrPhase.openAuth,
        clock: JrClock.authentication,
        label: 'Authentication',
        detail: 'Open System, seq 1',
        fields: const <JrField>[
          ('Algorithm', '0 (Open System)'),
          ('Sequence', '1'),
        ],
        description: roam
            ? 'Open System authentication with the target AP. It is '
                  'bookkeeping, not security: the real proof comes later.'
            : 'Open System authentication is bookkeeping, not security. It '
                  'proves nothing; the real proof, if any, comes later.',
        ms: c.frameMs,
      ),
    );
    out.add(
      JrMessage(
        from: _ap,
        to: _c,
        kind: JrFrameKind.management,
        phase: JrPhase.openAuth,
        clock: JrClock.authentication,
        label: 'Authentication',
        detail: 'Open System, seq 2',
        fields: const <JrField>[
          ('Algorithm', '0 (Open System)'),
          ('Sequence', '2'),
          ('Status code', '0 (success)'),
        ],
        description:
            'Status 0, success. Authentication frames are never protected, '
            'even with PMF.',
        ms: c.frameMs,
      ),
    );
  }

  void _sae() {
    JrMessage saeFrame({
      required bool client,
      required bool commit,
      required String description,
      double extra = 0,
      bool last = false,
    }) {
      return JrMessage(
        from: client ? _c : _ap,
        to: client ? _ap : _c,
        kind: JrFrameKind.management,
        phase: JrPhase.saeAuth,
        clock: JrClock.authentication,
        label: commit ? 'SAE Commit' : 'SAE Confirm',
        detail: 'Authentication, seq ${commit ? 1 : 2}',
        fields: <JrField>[
          ('Algorithm', '3 (SAE)'),
          ('Sequence', commit ? '1 (commit)' : '2 (confirm)'),
          ('Contents', commit ? 'scalar and element' : 'confirm'),
        ],
        description: description,
        ms: c.frameMs + extra,
        milestone: last ? LadderMilestone.keysAvailable : null,
        milestoneText: last
            ? 'Keys available: SAE produced the PMK on both sides. Nothing '
                  'is encrypted yet.'
            : null,
      );
    }

    out.add(
      saeFrame(
        client: true,
        commit: true,
        description:
            'SAE takes the place of Open System authentication, before '
            'association. The client sends a commitment computed from the '
            'password; the password is never sent.',
      ),
    );
    out.add(
      saeFrame(
        client: false,
        commit: true,
        extra: c.cryptoMs,
        description:
            'The AP sends its own commitment. Both sides now compute the '
            'same secret (the crypto time is booked here).',
      ),
    );
    out.add(
      saeFrame(
        client: true,
        commit: false,
        description: 'The client proves it computed the same secret.',
      ),
    );
    out.add(
      saeFrame(
        client: false,
        commit: false,
        last: true,
        description:
            'The AP proves the same. Both sides hold the PMK. Like every '
            'authentication frame, these four are never protected.',
      ),
    );
  }

  // ── (Re)association ───────────────────────────────────────────────────────

  List<JrField> _capabilities() => switch (c.band) {
    JrBand.g24 => const <JrField>[
      ('HT Capabilities', 'streams, 20/40 MHz, MCS set'),
      ('HE Capabilities', 'streams, MCS set'),
      ('EHT Capabilities', 'streams, MCS set'),
    ],
    JrBand.g5 => const <JrField>[
      ('HT Capabilities', 'streams, 20/40 MHz, MCS set'),
      ('VHT Capabilities', 'streams, 80/160 MHz, MCS set'),
      ('HE Capabilities', 'streams, MCS set'),
      ('EHT Capabilities', 'streams, 320 MHz where allowed, MCS set'),
    ],
    JrBand.g6 => const <JrField>[
      ('HE Capabilities', 'streams, MCS set'),
      ('HE 6 GHz Band Capabilities', 'in place of HT and VHT in 6 GHz'),
      ('EHT Capabilities', 'streams, 320 MHz, MCS set'),
    ],
  };

  void _association({required bool reassociation}) {
    final String name = reassociation ? 'Reassociation' : 'Association';
    final JrPhase phase = reassociation
        ? JrPhase.reassociation
        : JrPhase.association;
    final JrClock clock = JrClock.association;
    final bool cached =
        reassociation &&
        (c.roamMethod == JrRoamMethod.pmkCaching ||
            c.roamMethod == JrRoamMethod.okc);
    final bool okc = reassociation && c.roamMethod == JrRoamMethod.okc;
    final JrSecurity s = _sec;
    final List<JrField> rsn = s == JrSecurity.open
        ? const <JrField>[]
        : <JrField>[
            ('RSN element: AKM', _akm),
            ('RSN element: ciphers', 'pairwise CCMP-128, group CCMP-128'),
            ('RSN element: PMF bits', _pmf.bits),
            if (_pmf.inUse)
              ('RSN element: group management cipher', 'BIP-CMAC-128'),
            if (cached)
              (
                'RSN element: PMKID',
                okc
                    ? 'computed from the PMK of the first connection and the '
                          'TARGET AP\'s address'
                    : 'names the PMK this client and this AP already share',
              ),
          ];
    final String requestDetail = cached
        ? 'RSN: PMKID'
        : s == JrSecurity.open
        ? 'No RSN element'
        : 'RSN: $_akm, PMF ${_pmf.label.toLowerCase()}';
    out.add(
      JrMessage(
        from: _c,
        to: _ap,
        kind: JrFrameKind.management,
        phase: phase,
        clock: clock,
        label: '$name Request',
        detail: reassociation
            ? '$requestDetail; names the current AP'
            : requestDetail,
        fields: <JrField>[
          ('SSID', _ssid),
          if (reassociation)
            ('Current AP address', 'the BSSID of the AP it is leaving'),
          ('Listen interval', '10 beacon intervals (example)'),
          (
            'Capability information',
            s == JrSecurity.open ? 'ESS' : 'ESS, Privacy',
          ),
          ('Supported rates', _rates),
          ...rsn,
          if (s == JrSecurity.owe)
            (
              'OWE Diffie-Hellman Parameter',
              'group 19: the client\'s public key',
            ),
          ..._capabilities(),
        ],
        description: reassociation
            ? (cached
                  ? (okc
                        ? 'A Reassociation, not an Association: it names the '
                              'current AP. The PMKID is computed from the '
                              'same PMK for the NEW AP\'s address. OKC is a '
                              'vendor extension, not IEEE; Apple\'s own key '
                              'caching is not compatible with it.'
                        : 'A Reassociation, not an Association: it names the '
                              'current AP. The PMKID names a PMK the client '
                              'still holds from an earlier full '
                              'authentication with this same AP.')
                  : 'A Reassociation, not an Association: it names the '
                        'current AP so the network can move the client\'s '
                        'traffic. Nothing cached here, so 802.1X runs again.')
            : 'Where client and AP agree on capabilities: rates, streams, '
                  'channel width and the security suite. Association is '
                  'bookkeeping, not security, and is never protected by '
                  'PMF. Tap it to see what it carries.',
        ms: c.frameMs,
      ),
    );
    final bool keysHere = cached || s == JrSecurity.psk || s == JrSecurity.owe;
    out.add(
      JrMessage(
        from: _ap,
        to: _c,
        kind: JrFrameKind.management,
        phase: phase,
        clock: clock,
        label: '$name Response',
        detail: 'Status 0, AID 1',
        fields: <JrField>[
          ('Status code', '0 (success)'),
          ('Association ID (AID)', '1'),
          ('Supported rates', _rates),
          if (s == JrSecurity.owe)
            ('OWE Diffie-Hellman Parameter', 'group 19: the AP\'s public key'),
          ('Operation elements', 'the AP\'s own HT/VHT/HE/EHT operation'),
        ],
        description: switch (s) {
          _ when cached =>
            'The AP still holds the PMK that PMKID names, so EAP is '
                'skipped and it goes straight to the 4-way handshake.',
          JrSecurity.open =>
            'Associated, and on an open network that is all: no keys, '
                'nothing encrypted, ever.',
          JrSecurity.owe =>
            'OWE: the two public keys in the association frames give both '
                'sides the same PMK with no password. Encryption without '
                'authentication.',
          JrSecurity.dot1x =>
            'Associated, but the AP blocks the client\'s data until 802.1X '
                'and the 4-way handshake finish.',
          _ =>
            'Associated. The AP blocks the client\'s data until the 4-way '
                'handshake finishes.',
        },
        ms: c.frameMs + (s == JrSecurity.owe ? c.cryptoMs : 0),
        milestone: keysHere ? LadderMilestone.keysAvailable : null,
        milestoneText: keysHere
            ? switch (s) {
                _ when cached =>
                  'Keys available: both sides reuse the cached PMK. Nothing '
                      'is encrypted yet.',
                JrSecurity.owe =>
                  'Keys available: the Diffie-Hellman exchange gave both '
                      'sides the PMK. Nothing is encrypted yet.',
                _ =>
                  'Keys available: the PMK comes from the passphrase, which '
                      'both sides already know. Nothing is encrypted yet.',
              }
            : null,
      ),
    );
  }

  // ── EAP: the existing ladder's middle, unchanged ──────────────────────────

  void _eap() {
    final LadderSequence ladder = buildLadder(c.eapConfig);
    for (final LadderMessage m in ladder.messages) {
      if (!m.phase.isEap) continue;
      JrLane lane(LadderLane l) => switch (l) {
        LadderLane.client => _c,
        LadderLane.ap => _ap,
        LadderLane.radius => JrLane.radius,
      };
      final bool wire = m.leg == LadderLeg.wire;
      final bool accept = m.label == 'Access-Accept';
      out.add(
        JrMessage(
          from: lane(m.from),
          to: lane(m.to),
          kind: switch (m.kind) {
            LadderFrameKind.management => JrFrameKind.management,
            LadderFrameKind.eapol => JrFrameKind.eapol,
            LadderFrameKind.eapolKey => JrFrameKind.eapolKey,
            LadderFrameKind.radius => JrFrameKind.radius,
          },
          phase: switch (m.phase) {
            LadderPhase.eapIdentity => JrPhase.eapIdentity,
            LadderPhase.eapMethod => JrPhase.eapMethod,
            LadderPhase.innerAuth => JrPhase.innerAuth,
            _ => JrPhase.eapResult,
          },
          clock: JrClock.eap,
          label: m.label,
          detail: m.detail,
          fields: m.contents.isEmpty
              ? const <JrField>[]
              : <JrField>[('Contents', m.contents)],
          description: accept
              ? '${m.description} (The crypto time is booked here.)'
              : m.description,
          tunneled: m.tunneled,
          ms:
              (wire ? c.radiusRttMs / 2 : c.frameMs) +
              (accept ? c.cryptoMs : 0),
          milestone: m.milestone,
          milestoneText: m.milestoneText,
        ),
      );
    }
  }

  // ── 4-way handshake ───────────────────────────────────────────────────────

  void _fourWay() {
    JrMessage key(
      int n,
      String detail,
      List<JrField> fields,
      String description, {
      bool last = false,
    }) => JrMessage(
      from: n.isOdd ? _ap : _c,
      to: n.isOdd ? _c : _ap,
      kind: JrFrameKind.eapolKey,
      phase: JrPhase.fourWay,
      clock: JrClock.keys,
      label: 'EAPOL-Key',
      detail: 'Message $n of 4: $detail',
      fields: <JrField>[
        ('Frame', 'an 802.11 DATA frame, EtherType 0x888E (not management)'),
        ...fields,
      ],
      description: description,
      ms: c.frameMs,
      milestone: last ? LadderMilestone.trafficProtected : null,
      milestoneText: last
          ? 'Traffic protected: data frames are now encrypted'
                '${_pmf.inUse ? ', and PMF protects later deauthentication, disassociation and robust Action frames' : ''}.'
          : null,
    );

    out.add(
      key(
        1,
        'ANonce',
        const <JrField>[('Key Nonce', 'ANonce'), ('Key MIC', 'none yet')],
        'The AP sends a random number (ANonce). EAPOL-Key frames are data '
            'frames, not management frames.',
      ),
    );
    out.add(
      key(
        2,
        'SNonce, MIC',
        const <JrField>[('Key Nonce', 'SNonce'), ('Key MIC', 'yes')],
        'The client sends its own random number (SNonce) with a MIC that '
            'proves it holds the same PMK. Both sides can derive the PTK.',
      ),
    );
    out.add(
      key(
        3,
        'GTK (encrypted), MIC, install',
        const <JrField>[
          ('Key Data', 'the GTK, encrypted'),
          ('Key MIC', 'yes'),
          ('Install', 'set'),
        ],
        'The AP proves it holds the PMK too, sends the group key (GTK) '
            'encrypted, and says to install the keys.',
      ),
    );
    out.add(
      key(
        4,
        'confirm',
        const <JrField>[('Key MIC', 'yes')],
        'The client confirms. Both sides install the keys: the lock goes on.',
        last: true,
      ),
    );
  }

  // ── FT ────────────────────────────────────────────────────────────────────

  void _ftOverAir() {
    out.add(
      JrMessage(
        from: _c,
        to: JrLane.targetAp,
        kind: JrFrameKind.management,
        phase: JrPhase.ftAuth,
        clock: JrClock.authentication,
        label: 'Authentication',
        detail: 'FT (algorithm 2): SNonce',
        fields: const <JrField>[
          ('Algorithm', '2 (Fast BSS Transition)'),
          ('RSN element', 'AKM FT over 802.1X, PMKR0Name'),
          ('Mobility Domain element', 'the mobility domain'),
          ('FT element', 'SNonce, R0KH-ID'),
        ],
        description:
            'Fast BSS Transition authentication, straight to the target AP. '
            'The client sends its nonce and names the key hierarchy from its '
            'first connection in this mobility domain.',
        ms: c.frameMs,
      ),
    );
    out.add(
      JrMessage(
        from: JrLane.targetAp,
        to: _c,
        kind: JrFrameKind.management,
        phase: JrPhase.ftAuth,
        clock: JrClock.authentication,
        label: 'Authentication',
        detail: 'FT: ANonce, R1KH-ID',
        fields: const <JrField>[
          ('Algorithm', '2 (Fast BSS Transition)'),
          ('FT element', 'ANonce, SNonce, R1KH-ID, R0KH-ID'),
          ('Status code', '0 (success)'),
        ],
        description:
            'The target AP already holds this client\'s PMK-R1 (key '
            'distribution between APs is not drawn) and sends its nonce. '
            'Both sides can now derive the PTK. Authentication frames are '
            'never PMF-protected.',
        ms: c.frameMs,
        milestone: LadderMilestone.keysAvailable,
        milestoneText:
            'Keys available: both sides derive the PTK from PMK-R1 and the two '
            'nonces. Nothing is encrypted yet.',
      ),
    );
  }

  void _ftOverDs() {
    final bool pmf = _pmf.inUse;
    const String shieldNote =
        ' The client already has keys with the current AP, so PMF protects '
        'this Action frame.';
    const String noShield =
        ' PMF is off, so this Action frame goes unprotected.';
    out.add(
      JrMessage(
        from: _c,
        to: JrLane.currentAp,
        kind: JrFrameKind.action,
        phase: JrPhase.ftAction,
        clock: JrClock.authentication,
        label: 'FT Action: Request',
        detail: 'to the CURRENT AP, for the target',
        fields: const <JrField>[
          ('Target AP address', 'the BSSID it wants to move to'),
          ('RSN element', 'AKM FT over 802.1X, PMKR0Name'),
          ('Mobility Domain element', 'the mobility domain'),
          ('FT element', 'SNonce, R0KH-ID'),
        ],
        pmfProtected: pmf,
        description:
            'Over the DS, the client never talks to the target AP until it '
            'reassociates. It hands the FT request to the AP it is still '
            'associated with.${pmf ? shieldNote : noShield}',
        ms: c.frameMs,
      ),
    );
    out.add(
      JrMessage(
        from: JrLane.currentAp,
        to: JrLane.targetAp,
        kind: JrFrameKind.ds,
        phase: JrPhase.ftAction,
        clock: JrClock.authentication,
        label: 'FT Request, forwarded',
        detail: 'over the DS (the wired side)',
        fields: const <JrField>[('Carries', 'the client\'s FT request')],
        description:
            'The current AP forwards the request to the target AP over the '
            'distribution system, the wired network between the APs.',
        ms: c.dsRttMs / 2,
      ),
    );
    out.add(
      JrMessage(
        from: JrLane.targetAp,
        to: JrLane.currentAp,
        kind: JrFrameKind.ds,
        phase: JrPhase.ftAction,
        clock: JrClock.authentication,
        label: 'FT Response, forwarded',
        detail: 'ANonce, R1KH-ID',
        fields: const <JrField>[
          ('FT element', 'ANonce, SNonce, R1KH-ID, R0KH-ID'),
        ],
        description:
            'The target AP holds this client\'s PMK-R1 and answers with its '
            'nonce, back over the DS.',
        ms: c.dsRttMs / 2,
      ),
    );
    out.add(
      JrMessage(
        from: JrLane.currentAp,
        to: _c,
        kind: JrFrameKind.action,
        phase: JrPhase.ftAction,
        clock: JrClock.authentication,
        label: 'FT Action: Response',
        detail: 'from the current AP',
        fields: const <JrField>[
          ('FT element', 'ANonce, SNonce, R1KH-ID, R0KH-ID'),
          ('Status code', '0 (success)'),
        ],
        pmfProtected: pmf,
        description:
            'The current AP relays the answer. Both sides can now derive the '
            'PTK for the target AP.${pmf ? shieldNote : noShield}',
        ms: c.frameMs,
        milestone: LadderMilestone.keysAvailable,
        milestoneText:
            'Keys available: the client and the target AP derive the PTK from '
            'PMK-R1 and the two nonces. Nothing is encrypted with it yet.',
      ),
    );
  }

  void _ftReassociation() {
    out.add(
      JrMessage(
        from: _c,
        to: JrLane.targetAp,
        kind: JrFrameKind.management,
        phase: JrPhase.reassociation,
        clock: JrClock.keys,
        label: 'Reassociation Request',
        detail: 'FT: MIC; names the current AP',
        fields: const <JrField>[
          ('Current AP address', 'the BSSID of the AP it is leaving'),
          ('RSN element', 'AKM FT over 802.1X, PMKR1Name'),
          ('Mobility Domain element', 'the mobility domain'),
          ('FT element', 'MIC, ANonce, SNonce'),
        ],
        description:
            'The client proves it derived the same PTK. This and the '
            'response carry what the 4-way handshake would, so the time is '
            'booked as the key handshake.',
        ms: c.frameMs,
      ),
    );
    out.add(
      JrMessage(
        from: JrLane.targetAp,
        to: _c,
        kind: JrFrameKind.management,
        phase: JrPhase.reassociation,
        clock: JrClock.keys,
        label: 'Reassociation Response',
        detail: 'FT: MIC, GTK',
        fields: const <JrField>[
          ('Status code', '0 (success)'),
          ('Association ID (AID)', '1'),
          ('FT element', 'MIC, the GTK (encrypted)'),
        ],
        description:
            'The target AP proves the same and delivers the group key. The '
            '4-way handshake is folded into the FT frames.',
        ms: c.frameMs,
        milestone: LadderMilestone.trafficProtected,
        milestoneText:
            'Traffic protected: data frames to the target AP are now '
            'encrypted.',
      ),
    );
  }

  // ── IP ────────────────────────────────────────────────────────────────────

  bool get _enc => _sec != JrSecurity.open;

  JrMessage _bridged({
    required bool up,
    required JrPhase phase,
    required JrClock clock,
    required String label,
    required String detail,
    required List<JrField> fields,
    required String description,
    required double ms,
  }) {
    final String encNote = _enc
        ? ' Over the air it is an encrypted data frame.'
        : ' Over the air it is a data frame anyone nearby can read: an open '
              'network encrypts nothing.';
    return JrMessage(
      from: up ? _c : JrLane.dhcp,
      to: up ? JrLane.dhcp : _c,
      via: JrLane.ap,
      kind: JrFrameKind.data,
      phase: phase,
      clock: clock,
      label: label,
      detail: detail,
      fields: fields,
      encrypted: _enc,
      description: '$description$encNote',
      ms: ms,
    );
  }

  void _dhcp() {
    final double half = c.frameMs + c.lanRttMs / 2;
    const String rfc = ' (RFC 2131)';
    out.add(
      _bridged(
        up: true,
        phase: JrPhase.dhcp,
        clock: JrClock.dhcp,
        label: 'DHCP Discover',
        detail: '0.0.0.0 to 255.255.255.255, broadcast',
        fields: const <JrField>[
          ('Source', '0.0.0.0, UDP 68 (no address yet)'),
          ('Destination', '255.255.255.255, UDP 67 (broadcast)'),
        ],
        description:
            'The keys are in place but the client still has no IP address. '
            'It broadcasts for a DHCP server$rfc; the AP bridges the frame '
            'onto the wire.',
        ms: half,
      ),
    );
    out.add(
      _bridged(
        up: false,
        phase: JrPhase.dhcp,
        clock: JrClock.dhcp,
        label: 'DHCP Offer',
        detail: 'offers 192.168.1.23 (example)',
        fields: const <JrField>[
          ('Your address', '192.168.1.23 (example)'),
          ('Options', 'subnet mask, router (gateway), DNS servers, lease time'),
        ],
        description: 'A server offers an address and the network settings.',
        ms: half,
      ),
    );
    out.add(
      _bridged(
        up: true,
        phase: JrPhase.dhcp,
        clock: JrClock.dhcp,
        label: 'DHCP Request',
        detail: 'asks for 192.168.1.23',
        fields: const <JrField>[
          ('Requested address', '192.168.1.23'),
          ('Server identifier', 'the server whose offer it takes'),
        ],
        description: 'The client asks for the offered address, by server.',
        ms: half,
      ),
    );
    out.add(
      _bridged(
        up: false,
        phase: JrPhase.dhcp,
        clock: JrClock.dhcp,
        label: 'DHCP Ack',
        detail: 'the lease',
        fields: const <JrField>[
          ('Your address', '192.168.1.23'),
          ('Options', 'subnet mask, router 192.168.1.1, DNS, lease time'),
        ],
        description:
            'The lease is granted. Before using the address the client '
            'checks it.',
        ms: half,
      ),
    );
  }

  void _addressCheck() {
    if (c.addressCheck == JrAddressCheck.acd) {
      for (int i = 1; i <= kAcdProbeCount; i++) {
        final double wait = i == 1 ? c.acdProbeWaitMs : c.acdSpacingMs;
        out.add(
          _bridged(
            up: true,
            phase: JrPhase.addressCheck,
            clock: JrClock.addressCheck,
            label: 'ARP Probe $i of $kAcdProbeCount',
            detail: i == 1
                ? 'after ${formatJrMs(wait)}: who has 192.168.1.23?'
                : '${formatJrMs(wait)} later',
            fields: const <JrField>[
              ('Sender IP', '0.0.0.0 (not claimed yet)'),
              ('Target IP', '192.168.1.23, the new address'),
              ('Destination', 'broadcast'),
            ],
            description: i == 1
                ? 'Address Conflict Detection (ACD, RFC 5227): the client '
                      'checks that no one else already has its new address. '
                      'It waits a random 0 to 1 s (set here to '
                      '${formatJrMs(wait)}), then asks with an ARP Probe. An '
                      'answer would mean a conflict.'
                : 'No answer, so it probes again. RFC 5227 spaces the probes '
                      'a random 1 to 2 s apart (set here to '
                      '${formatJrMs(wait)}).',
            ms: wait + c.frameMs,
          ),
        );
      }
      out.add(
        _bridged(
          up: true,
          phase: JrPhase.addressCheck,
          clock: JrClock.addressCheck,
          label: 'ARP Announcement',
          detail: '${formatJrMs(kAcdAnnounceWaitMs)} after the last probe',
          fields: const <JrField>[
            ('Sender IP', '192.168.1.23'),
            ('Target IP', '192.168.1.23'),
            ('Destination', 'broadcast'),
          ],
          description:
              'Still no answer ${formatJrMs(kAcdAnnounceWaitMs)} after the '
              'last probe (ANNOUNCE_WAIT), so the address is the client\'s, '
              'and it announces it. This wait is why Address Conflict '
              'Detection can take several '
              'seconds (as much as seven, RFC 4436).',
          ms: kAcdAnnounceWaitMs + c.frameMs,
        ),
      );
      return;
    }
    out.add(
      _bridged(
        up: true,
        phase: JrPhase.addressCheck,
        clock: JrClock.addressCheck,
        label: 'ARP Request (unicast)',
        detail: 'to the gateway it remembers',
        fields: const <JrField>[
          ('Target IP', '192.168.1.1, the remembered gateway'),
          ('Destination', 'the gateway\'s remembered hardware address'),
        ],
        description:
            'Detecting Network Attachment (DNAv4, RFC 4436), for a network '
            'the client has used before: one unicast ARP to the gateway it '
            'remembers. A real DNAv4 client often also skips the four DHCP '
            'messages; the ladder keeps them so the two checks compare side '
            'by side.',
        ms: c.frameMs + c.lanRttMs / 2,
      ),
    );
    out.add(
      _bridged(
        up: false,
        phase: JrPhase.addressCheck,
        clock: JrClock.addressCheck,
        label: 'ARP Reply',
        detail: 'same gateway: same network',
        fields: const <JrField>[
          ('Sender IP', '192.168.1.1'),
          ('Sender hardware address', 'the one the client remembered'),
        ],
        description:
            'The same gateway answers from the same hardware address, so this '
            'is the same network and the address is still good. Under 10 ms, '
            'instead of seconds.',
        ms: c.frameMs + c.lanRttMs / 2,
      ),
    );
  }

  void _arpDns() {
    final double half = c.frameMs + c.lanRttMs / 2;
    if (c.addressCheck == JrAddressCheck.acd) {
      out.add(
        _bridged(
          up: true,
          phase: JrPhase.arpDns,
          clock: JrClock.arpDns,
          label: 'ARP Request',
          detail: 'who has 192.168.1.1 (the gateway)?',
          fields: const <JrField>[
            ('Target IP', '192.168.1.1, the router from DHCP'),
            ('Destination', 'broadcast'),
          ],
          description:
              'To send anything off the subnet the client needs the '
              'gateway\'s hardware address.',
          ms: half,
        ),
      );
      out.add(
        _bridged(
          up: false,
          phase: JrPhase.arpDns,
          clock: JrClock.arpDns,
          label: 'ARP Reply',
          detail: 'the gateway\'s hardware address',
          fields: const <JrField>[
            ('Sender IP', '192.168.1.1'),
            ('Sender hardware address', 'the gateway\'s'),
          ],
          description: 'The gateway answers.',
          ms: half,
        ),
      );
    }
    out.add(
      _bridged(
        up: true,
        phase: JrPhase.arpDns,
        clock: JrClock.arpDns,
        label: 'DNS Query',
        detail: 'a name, to the DNS server from DHCP',
        fields: const <JrField>[
          ('Question', 'the address of a name, e.g. wlanpros.com'),
          ('To', 'the DNS server DHCP named, UDP 53'),
        ],
        description:
            'Usually the first thing an app needs: a name looked up. The DNS '
            'server is drawn on the wired LAN lane.',
        ms: half,
      ),
    );
    out.add(
      _bridged(
        up: false,
        phase: JrPhase.arpDns,
        clock: JrClock.arpDns,
        label: 'DNS Response',
        detail: 'the address: the first useful packet can go',
        fields: const <JrField>[('Answer', 'the address for the name')],
        description:
            'The answer arrives. Only now can the first useful packet go out: '
            'the association is complete.',
        ms: half,
      ),
    );
  }

  void _later() {
    final bool pmf = _pmf.inUse;
    final String why = switch (_sec) {
      JrSecurity.open =>
        'On an open network there are no keys, so nothing can protect it.',
      _ when pmf =>
        'Keys exist and PMF (802.11w) is in use, so this robust Action frame '
            'is protected. Beacons, probes, authentication and association '
            'frames never are.',
      _ =>
        'PMF is off, so even with keys this frame goes unprotected and could '
            'be forged. Turn PMF on to see the shield.',
    };
    out.add(
      JrMessage(
        from: _c,
        to: _ap,
        kind: JrFrameKind.action,
        phase: JrPhase.later,
        clock: JrClock.later,
        label: 'Action: ADDBA Request',
        detail: 'Block Ack setup, a robust Action frame',
        fields: <JrField>[
          ('Category', 'Block Ack (robust)'),
          ('Protected by PMF', pmf ? 'yes' : 'no'),
        ],
        pmfProtected: pmf,
        description:
            'Later, when traffic flows, the two sides set up Block Ack. Not '
            'part of the association, and not counted in its time. $why',
        ms: c.frameMs,
      ),
    );
    out.add(
      JrMessage(
        from: _ap,
        to: _c,
        kind: JrFrameKind.action,
        phase: JrPhase.later,
        clock: JrClock.later,
        label: 'Action: ADDBA Response',
        detail: 'Block Ack agreed',
        fields: <JrField>[
          ('Category', 'Block Ack (robust)'),
          ('Protected by PMF', pmf ? 'yes' : 'no'),
        ],
        pmfProtected: pmf,
        description:
            'Deauthentication and Disassociation frames get the same '
            'protection once keys exist, which is what stops a forged '
            'deauthentication from knocking the client off.',
        ms: c.frameMs,
      ),
    );
  }
}
