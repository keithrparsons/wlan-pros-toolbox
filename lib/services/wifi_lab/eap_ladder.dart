// 802.1X and EAP Ladder (Wi-Fi Classroom, eap-ladder): the message sequences.
//
// Pure Dart, no Flutter. Given a method (EAP-TLS, PEAP, EAP-TTLS, PSK or
// SAE), a roam mode (full, PMK caching, FT over the air), an inner method for
// EAP-TTLS and a certificate size in fragments, [buildLadder] returns the
// ordered messages across three lanes (client, AP, RADIUS server) and the
// counts the screen reads out.
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/21-eap-ladder.md. Sequences follow the documents the spec
// names, not anyone's ladder drawing:
//   - IEEE 802.11: Open System and SAE authentication (commit, confirm),
//     (re)association, the 4-way handshake (four EAPOL-Key frames), PMKSA
//     caching (PMKID in the RSN element), FT over the air (FT authentication
//     plus reassociation, four frames).
//   - IEEE 802.1X: EAP over LANs (EAPOL) between client and AP.
//   - RFC 3748 (EAP): Request/Response lockstep, Identity, Success.
//   - RFC 3579 (RADIUS support for EAP): each EAP-Response rides an
//     Access-Request, each EAP-Request an Access-Challenge, and the result an
//     Access-Accept; the AP may send the first EAP-Request/Identity itself.
//   - RFC 5216 (EAP-TLS) section 2.1: the exchange, and 2.1.5: each fragment
//     is acknowledged by an empty message from the other side.
//   - RFC 5281 (EAP-TTLS) section 11: inner PAP and MS-CHAP-V2 as AVPs; with
//     MS-CHAP-V2 the challenge is derived from the tunnel, so the client
//     sends its response in its first tunneled message.
//   - RFC 2759 (MS-CHAP-V2): challenge, NT-Response, authenticator response.
//   - PEAP has no RFC (the IANA EAP registry lists it as a vendor
//     registration); the tunneled identity, MSCHAPv2 and result exchange
//     follow Microsoft's published [MS-PEAP] shape for PEAPv0.
//   - RFC 2548: the MS-MPPE key attributes that carry the key material to
//     the AP in the Access-Accept.
//
// WHAT VARIES BY IMPLEMENTATION IS A SETTING, NOT A CLAIM. Certificate size is
// modelled as fragments per certificate message (1 to 6), because the count
// depends on the certificate chain and the server's fragment size. The TLS
// messages are the TLS 1.2 shape the RFCs above draw; TLS 1.3 (RFC 9190)
// and session resumption are not modelled. Frame airtime and RADIUS round-trip
// time are illustrative inputs.

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

/// The three lanes of the ladder.
enum LadderLane {
  client('Client', 'supplicant'),
  ap('AP', 'authenticator'),
  radius('RADIUS server', 'authentication server');

  const LadderLane(this.label, this.role);

  final String label;

  /// The 802.1X role name.
  final String role;
}

/// Which leg a message travels: between client and AP over the air, or
/// between AP and RADIUS server on the wire.
enum LadderLeg {
  air('Over the air'),
  wire('On the wire');

  const LadderLeg(this.label);

  final String label;
}

/// The outer frame or packet type.
enum LadderFrameKind {
  management('802.11 management frame'),
  eapol('EAPOL (EAP over LAN)'),
  eapolKey('EAPOL-Key'),
  radius('RADIUS over UDP');

  const LadderFrameKind(this.label);

  final String label;
}

/// Groups of messages, drawn as section headings on the ladder.
enum LadderPhase {
  discovery('Discovery (one channel of the scan)'),
  openAuth('802.11 authentication (Open System)'),
  saeAuth('SAE authentication: commit and confirm'),
  ftAuth('FT authentication'),
  association('Association'),
  reassociation('Reassociation'),
  eapIdentity('EAP identity'),
  eapMethod('EAP method: TLS handshake'),
  innerAuth('Inside the TLS tunnel'),
  eapResult('EAP result'),
  fourWay('4-way handshake');

  const LadderPhase(this.label);

  final String label;

  /// Phases that make up the EAP exchange (the part PMK caching and FT skip).
  bool get isEap =>
      this == eapIdentity ||
      this == eapMethod ||
      this == innerAuth ||
      this == eapResult;
}

/// A point on the ladder worth stopping at.
enum LadderMilestone {
  keysAvailable('Keys available'),
  trafficProtected('Traffic protected');

  const LadderMilestone(this.label);

  final String label;
}

/// Authentication methods on the selector.
enum LadderMethod {
  eapTls('EAP-TLS', eapTypesName: 'EAP-TLS', eapType: 'TLS'),
  peap('PEAP (MSCHAPv2)', eapTypesName: 'PEAP (MSCHAPv2)', eapType: 'PEAP'),
  eapTtls('EAP-TTLS', eapTypesName: 'EAP-TTLS', eapType: 'TTLS'),
  psk('WPA2-Personal (PSK)'),
  sae('WPA3-Personal (SAE)');

  const LadderMethod(this.label, {this.eapTypesName, this.eapType});

  final String label;

  /// The row name in the app's 802.1X / EAP Types reference
  /// (EapTypesScreen.methods), or null for PSK and SAE. The controls read
  /// that row's wording rather than restating it.
  final String? eapTypesName;

  /// The EAP method name as it appears in EAP-Request / EAP-Response.
  final String? eapType;

  bool get uses8021X => eapTypesName != null;

  /// A TLS tunnel carrying an inner method.
  bool get isTunneled => this == peap || this == eapTtls;
}

/// Inner method for EAP-TTLS. PEAP here always carries MSCHAPv2.
enum LadderInner {
  mschapv2('MSCHAPv2'),
  pap('PAP');

  const LadderInner(this.label);

  final String label;
}

/// How the client joins this AP.
enum LadderRoam {
  full('Full', 'Full authentication (first connection or a full roam)'),
  pmkCaching(
    'PMK caching',
    'PMK caching (roam back to an AP with a cached PMK)',
  ),
  ftOverAir('FT (802.11r)', '802.11r Fast BSS Transition over the air');

  const LadderRoam(this.shortLabel, this.label);

  final String shortLabel;
  final String label;
}

/// Certificate fragments per certificate message: the range the setting
/// offers.
const int kMinCertFragments = 1;
const int kMaxCertFragments = 6;

/// RADIUS round-trip time range, milliseconds (illustrative).
const double kMinRadiusRttMs = 1;
const double kMaxRadiusRttMs = 200;

/// Illustrative time for one over-the-air frame, including its wait for the
/// medium and its ACK, in milliseconds. Small next to a RADIUS round trip or
/// a scan; the help entry says it is illustrative.
const double kAirFrameMs = 1.0;

/// Everything the ladder depends on.
@immutable
class LadderConfig {
  const LadderConfig({
    this.method = LadderMethod.eapTls,
    this.inner = LadderInner.mschapv2,
    this.roam = LadderRoam.full,
    this.certFragments = 1,
    this.radiusRttMs = 10,
  });

  final LadderMethod method;

  /// Used only by EAP-TTLS.
  final LadderInner inner;
  final LadderRoam roam;

  /// Fragments per certificate-bearing TLS message (the server's certificate
  /// flight, and the client's for EAP-TLS).
  final int certFragments;

  /// AP to RADIUS server and back, including server processing.
  final double radiusRttMs;

  /// Whether the certificate-size setting changes anything for this config.
  bool get certificateMatters => method.uses8021X && roam == LadderRoam.full;

  /// Whether the RADIUS round-trip setting changes anything.
  bool get radiusMatters => method.uses8021X && roam == LadderRoam.full;

  LadderConfig copyWith({
    LadderMethod? method,
    LadderInner? inner,
    LadderRoam? roam,
    int? certFragments,
    double? radiusRttMs,
  }) {
    return LadderConfig(
      method: method ?? this.method,
      inner: inner ?? this.inner,
      roam: roam ?? this.roam,
      certFragments: (certFragments ?? this.certFragments).clamp(
        kMinCertFragments,
        kMaxCertFragments,
      ),
      radiusRttMs: (radiusRttMs ?? this.radiusRttMs).clamp(
        kMinRadiusRttMs,
        kMaxRadiusRttMs,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LadderConfig &&
      other.method == method &&
      other.inner == inner &&
      other.roam == roam &&
      other.certFragments == certFragments &&
      other.radiusRttMs == radiusRttMs;

  @override
  int get hashCode =>
      Object.hash(method, inner, roam, certFragments, radiusRttMs);
}

/// One arrow on the ladder.
@immutable
class LadderMessage {
  const LadderMessage({
    required this.from,
    required this.to,
    required this.kind,
    required this.phase,
    required this.label,
    required this.description,
    this.detail,
    this.fullDetail,
    this.eapCode,
    this.tunneled = false,
    this.clientCertificate = false,
    this.serverCertificate = false,
    this.milestone,
    this.milestoneText,
    this.failure = false,
    this.lost = false,
    this.waitMs = 0,
  });

  final LadderLane from;
  final LadderLane to;
  final LadderFrameKind kind;
  final LadderPhase phase;

  /// Top line on the arrow, e.g. `EAP-Request / Identity`, `Access-Request`.
  final String label;

  /// Short second line, e.g. `ClientHello`.
  final String? detail;

  /// The complete contents for the caption; falls back to [detail].
  final String? fullDetail;

  /// One or two sentences: what this message does and why.
  final String description;

  /// The EAP message this carries, for tests and the caption:
  /// `EAP-Request/Identity`, `EAP-Response/Identity`, `EAP-Request`,
  /// `EAP-Response`, `EAP-Success`; null when it carries no EAP.
  final String? eapCode;

  /// Encrypted by the TLS tunnel between client and RADIUS server.
  final bool tunneled;

  /// Carries the client's certificate (EAP-TLS only).
  final bool clientCertificate;

  /// Carries the server's certificate.
  final bool serverCertificate;

  /// A milestone reached once this message has been sent.
  final LadderMilestone? milestone;
  final String? milestoneText;

  /// THE SHARED FAILURE MARKER (spec 42; feature 1 uses the same pair on
  /// JrMessage). This message carries the failure, or is the one the other
  /// side refused: drawn with a red X at its end, and the caption says so.
  final bool failure;

  /// Sent and never answered (a RADIUS server silently discarding it): drawn
  /// as a dashed arrow that stops in a gap, with a clock.
  final bool lost;

  /// Time spent waiting before this message is sent (a retry after a
  /// timeout), ms. Zero on every fault-free message.
  final double waitMs;

  /// Either half of the failure marker.
  bool get marksFailure => failure || lost;

  LadderLeg get leg => from == LadderLane.radius || to == LadderLane.radius
      ? LadderLeg.wire
      : LadderLeg.air;

  String get contents => fullDetail ?? detail ?? '';
}

/// A built ladder and its counts.
@immutable
class LadderSequence {
  LadderSequence._(this.config, this.messages, {this.faultNote, this.helpDesk})
    : airCount = messages.where((m) => m.leg == LadderLeg.air).length,
      wireCount = messages.where((m) => m.leg == LadderLeg.wire).length,
      radiusRoundTrips = messages
          .where(
            (m) =>
                m.from == LadderLane.ap && m.to == LadderLane.radius && !m.lost,
          )
          .length,
      failedAt = messages.indexWhere((m) => m.marksFailure);

  /// A sequence from explicit messages, for tests of the failure marker's
  /// drawing without a fault in the builder.
  @visibleForTesting
  factory LadderSequence.forTest(
    LadderConfig config,
    List<LadderMessage> messages, {
    String? faultNote,
    String? helpDesk,
  }) => LadderSequence._(
    config,
    List<LadderMessage>.unmodifiable(messages),
    faultNote: faultNote,
    helpDesk: helpDesk,
  );

  final LadderConfig config;
  final List<LadderMessage> messages;

  /// Index of the first message that fails or is lost, or -1: where the
  /// exchange broke.
  final int failedAt;

  /// Whether the exchange breaks before it completes.
  bool get failed => failedAt >= 0;

  /// The "Stopped here" sentence, drawn in the band after the last message;
  /// null when nothing failed.
  final String? faultNote;

  /// What the help desk sees when this happens; null when nothing failed.
  final String? helpDesk;

  /// Frames between client and AP.
  final int airCount;

  /// RADIUS packets between AP and server.
  final int wireCount;

  /// Access-Request and its answer, counted once per Access-Request. An
  /// Access-Request that is never answered (lost) is not a round trip.
  final int radiusRoundTrips;

  int get length => messages.length;

  bool get usesRadius => wireCount > 0;

  /// Messages after the scan: what the roam mode actually changes.
  List<LadderMessage> get afterScan => messages
      .where((m) => m.phase != LadderPhase.discovery)
      .toList(growable: false);

  /// Illustrative time after the scan: frames x airtime + RADIUS round trips
  /// x round-trip time + any waits before retries. The scan itself is not
  /// included. On a failed ladder this is the time until it stops.
  double get estimatedMs =>
      afterScan.where((m) => m.leg == LadderLeg.air).length * kAirFrameMs +
      radiusRoundTrips * config.radiusRttMs +
      _waitMs;

  double get _waitMs =>
      messages.fold(0.0, (double t, LadderMessage m) => t + m.waitMs);

  /// Messages in [phase].
  List<LadderMessage> inPhase(LadderPhase phase) =>
      messages.where((m) => m.phase == phase).toList(growable: false);

  /// Index of the first message that reaches [milestone], or -1.
  int indexOfMilestone(LadderMilestone milestone) =>
      messages.indexWhere((m) => m.milestone == milestone);
}

/// What a roam mode skipped, compared with a full authentication of the same
/// method and certificate size.
@immutable
class LadderSkipped {
  const LadderSkipped({required this.lines, required this.fewerMessages});

  /// One sentence per skipped part; empty for a full authentication.
  final List<String> lines;

  /// Messages fewer than the full authentication (air plus wire).
  final int fewerMessages;
}

/// Builds the ladder for [config].
LadderSequence buildLadder(LadderConfig config) {
  final _Builder b = _Builder(config);
  b.build();
  return LadderSequence._(config, List<LadderMessage>.unmodifiable(b.out));
}

/// Compares [seq] with the full authentication of the same method.
LadderSkipped skippedVersusFull(LadderSequence seq) {
  final LadderConfig c = seq.config;
  if (c.roam == LadderRoam.full) {
    return const LadderSkipped(
      lines: <String>['Nothing: this is the full authentication.'],
      fewerMessages: 0,
    );
  }
  final LadderSequence full = buildLadder(c.copyWith(roam: LadderRoam.full));
  final int fewer = full.length - seq.length;
  final List<String> lines = <String>[];
  if (c.method.uses8021X) {
    final List<LadderMessage> eap = full.messages
        .where((m) => m.phase.isEap)
        .toList();
    final int air = eap.where((m) => m.leg == LadderLeg.air).length;
    final int wire = eap.where((m) => m.leg == LadderLeg.wire).length;
    lines.add(
      'The whole EAP exchange: $air frames over the air, $wire RADIUS '
      'messages on the wire (${full.radiusRoundTrips} round trips). The RADIUS '
      'server is not asked.',
    );
  }
  if (c.method == LadderMethod.sae) {
    lines.add(
      c.roam == LadderRoam.pmkCaching
          ? 'SAE commit and confirm (4 frames): the cached PMK replaces them, '
                'and Open System authentication takes their place.'
          : 'SAE commit and confirm (4 frames): FT authentication takes '
                'their place.',
    );
  }
  if (c.roam == LadderRoam.ftOverAir) {
    lines.add(
      'The separate 4-way handshake: its nonces and key checks ride in the '
      'four FT frames instead.',
    );
  }
  if (c.method == LadderMethod.psk && c.roam == LadderRoam.pmkCaching) {
    lines.add(
      'Nothing: with a PSK the PMK always comes from the passphrase, so '
      'there is nothing to cache. The roam is the same as a full one.',
    );
  }
  return LadderSkipped(lines: lines, fewerMessages: fewer);
}

class _Builder {
  _Builder(this.c);

  final LadderConfig c;
  final List<LadderMessage> out = <LadderMessage>[];

  static const LadderLane _c = LadderLane.client;
  static const LadderLane _ap = LadderLane.ap;
  static const LadderLane _r = LadderLane.radius;

  String get _type => c.method.eapType ?? '';

  void build() {
    _discovery();
    switch (c.roam) {
      case LadderRoam.full:
        if (c.method == LadderMethod.sae) {
          _sae();
        } else {
          _openAuth();
        }
        _association(reassociation: false);
        if (c.method.uses8021X) _eap();
        _fourWay();
      case LadderRoam.pmkCaching:
        _openAuth();
        _association(reassociation: true);
        _fourWay();
      case LadderRoam.ftOverAir:
        _ft();
    }
  }

  // ── 802.11 ────────────────────────────────────────────────────────────────

  String get _akm => switch (c.method) {
    LadderMethod.psk => 'PSK',
    LadderMethod.sae => 'SAE',
    _ => '802.1X',
  };

  void _discovery() {
    out.add(
      const LadderMessage(
        from: _c,
        to: _ap,
        kind: LadderFrameKind.management,
        phase: LadderPhase.discovery,
        label: 'Probe Request',
        description:
            'The client asks which networks are on this channel. A real scan '
            'repeats this on many channels. In measured handoffs (802.11b, '
            'open authentication) the scan was over 90% of the delay.',
      ),
    );
    out.add(
      LadderMessage(
        from: _ap,
        to: _c,
        kind: LadderFrameKind.management,
        phase: LadderPhase.discovery,
        label: 'Probe Response',
        detail:
            'RSN element: $_akm'
            '${c.roam == LadderRoam.ftOverAir ? ', FT' : ''}',
        description:
            'The AP answers with its capabilities. Its RSN element lists the '
            'key management it accepts ($_akm'
            '${c.roam == LadderRoam.ftOverAir ? ' and FT, with its mobility domain' : ''}'
            ').',
      ),
    );
  }

  void _openAuth() {
    final bool cached =
        c.roam == LadderRoam.pmkCaching && c.method != LadderMethod.psk;
    out.add(
      LadderMessage(
        from: _c,
        to: _ap,
        kind: LadderFrameKind.management,
        phase: LadderPhase.openAuth,
        label: 'Authentication',
        detail: 'Open System, seq 1',
        description: cached
            ? 'Open System authentication is a formality and proves nothing. '
                  'With a cached PMK nothing else replaces it: the PMKID and '
                  'the 4-way handshake do the proving.'
            : 'Open System authentication is a formality from the original '
                  'standard and proves nothing. The real proof comes later.',
      ),
    );
    out.add(
      const LadderMessage(
        from: _ap,
        to: _c,
        kind: LadderFrameKind.management,
        phase: LadderPhase.openAuth,
        label: 'Authentication',
        detail: 'Open System, seq 2',
        description: 'Status 0, success. No keys exist yet.',
      ),
    );
  }

  void _sae() {
    out.add(
      const LadderMessage(
        from: _c,
        to: _ap,
        kind: LadderFrameKind.management,
        phase: LadderPhase.saeAuth,
        label: 'SAE Commit',
        detail: 'Authentication, seq 1',
        fullDetail: 'Authentication frame, SAE, seq 1: scalar and element',
        description:
            'The client sends a commitment computed from the password. The '
            'password itself is never sent, and a captured exchange does '
            'not let an attacker test guesses offline.',
      ),
    );
    out.add(
      const LadderMessage(
        from: _ap,
        to: _c,
        kind: LadderFrameKind.management,
        phase: LadderPhase.saeAuth,
        label: 'SAE Commit',
        detail: 'Authentication, seq 1',
        fullDetail: 'Authentication frame, SAE, seq 1: scalar and element',
        description:
            'The AP sends its own commitment. Each side can now compute the '
            'same shared secret.',
      ),
    );
    out.add(
      const LadderMessage(
        from: _c,
        to: _ap,
        kind: LadderFrameKind.management,
        phase: LadderPhase.saeAuth,
        label: 'SAE Confirm',
        detail: 'Authentication, seq 2',
        fullDetail: 'Authentication frame, SAE, seq 2: confirm',
        description: 'The client proves it computed the same secret.',
      ),
    );
    out.add(
      const LadderMessage(
        from: _ap,
        to: _c,
        kind: LadderFrameKind.management,
        phase: LadderPhase.saeAuth,
        label: 'SAE Confirm',
        detail: 'Authentication, seq 2',
        fullDetail: 'Authentication frame, SAE, seq 2: confirm',
        description:
            'The AP proves the same. Both sides now hold the PMK, and no '
            'RADIUS server was asked.',
        milestone: LadderMilestone.keysAvailable,
        milestoneText:
            'Keys available: SAE produced the PMK on both sides. Nothing is '
            'encrypted yet.',
      ),
    );
  }

  void _association({required bool reassociation}) {
    final String name = reassociation ? 'Reassociation' : 'Association';
    final LadderPhase phase = reassociation
        ? LadderPhase.reassociation
        : LadderPhase.association;
    final bool pmkid = reassociation;
    out.add(
      LadderMessage(
        from: _c,
        to: _ap,
        kind: LadderFrameKind.management,
        phase: phase,
        label: '$name Request',
        detail: pmkid && c.method != LadderMethod.psk
            ? 'RSN element: PMKID'
            : 'RSN element: $_akm',
        description: pmkid
            ? (c.method == LadderMethod.psk
                  ? 'The client picks PSK. A PSK network has no PMK worth '
                        'naming: both sides already derive it from the '
                        'passphrase.'
                  : 'The client names, by its PMKID, a PMK it still holds '
                        'from an earlier full authentication with this AP.')
            : switch (c.method) {
                LadderMethod.psk =>
                  'The client picks PSK key management in its RSN element.',
                LadderMethod.sae =>
                  'The client picks SAE in its RSN element. WPA3 requires '
                      'protected management frames.',
                _ =>
                  'The client picks 802.1X key management in its RSN '
                      'element.',
              },
      ),
    );
    final bool keysHere =
        (pmkid && c.method != LadderMethod.psk) || c.method == LadderMethod.psk;
    out.add(
      LadderMessage(
        from: _ap,
        to: _c,
        kind: LadderFrameKind.management,
        phase: phase,
        label: '$name Response',
        detail: 'Status 0, AID',
        description: pmkid && c.method != LadderMethod.psk
            ? 'The AP still holds the PMK that PMKID names, so it skips '
                  'authentication and goes straight to the 4-way handshake. '
                  'OKC, a vendor extension, shares that PMK between the APs '
                  'of one controller.'
            : c.method.uses8021X
            ? 'Associated, but the AP blocks the client\'s data until 802.1X '
                  'and the 4-way handshake finish.'
            : 'Associated. The AP blocks the client\'s data until the 4-way '
                  'handshake finishes.',
        milestone: keysHere ? LadderMilestone.keysAvailable : null,
        milestoneText: keysHere
            ? (c.method == LadderMethod.psk
                  ? 'Keys available: the PMK comes from the passphrase, '
                        'which both sides already know. Nothing is encrypted '
                        'yet.'
                  : 'Keys available: both sides reuse the cached PMK. '
                        'Nothing is encrypted yet.')
            : null,
      ),
    );
  }

  void _fourWay() {
    out.add(
      const LadderMessage(
        from: _ap,
        to: _c,
        kind: LadderFrameKind.eapolKey,
        phase: LadderPhase.fourWay,
        label: 'EAPOL-Key',
        detail: 'Message 1 of 4: ANonce',
        description:
            'The AP sends a random number (ANonce). The client can now '
            'derive the session key (PTK) from the PMK and both nonces.',
      ),
    );
    out.add(
      const LadderMessage(
        from: _c,
        to: _ap,
        kind: LadderFrameKind.eapolKey,
        phase: LadderPhase.fourWay,
        label: 'EAPOL-Key',
        detail: 'Message 2 of 4: SNonce, MIC',
        description:
            'The client sends its own random number (SNonce) with a MIC that '
            'proves it holds the same PMK. The AP derives the PTK.',
      ),
    );
    out.add(
      const LadderMessage(
        from: _ap,
        to: _c,
        kind: LadderFrameKind.eapolKey,
        phase: LadderPhase.fourWay,
        label: 'EAPOL-Key',
        detail: 'Message 3 of 4: MIC, GTK',
        description:
            'The AP proves it holds the PMK too and sends the group key '
            '(GTK), encrypted.',
      ),
    );
    out.add(
      const LadderMessage(
        from: _c,
        to: _ap,
        kind: LadderFrameKind.eapolKey,
        phase: LadderPhase.fourWay,
        label: 'EAPOL-Key',
        detail: 'Message 4 of 4: ACK',
        description: 'The client confirms. Both sides install the keys.',
        milestone: LadderMilestone.trafficProtected,
        milestoneText:
            'Traffic protected: data frames are now encrypted, and the AP '
            'lets the client\'s data through.',
      ),
    );
  }

  void _ft() {
    out.add(
      const LadderMessage(
        from: _c,
        to: _ap,
        kind: LadderFrameKind.management,
        phase: LadderPhase.ftAuth,
        label: 'Authentication',
        detail: 'FT, seq 1: SNonce',
        fullDetail:
            'Authentication frame, Fast BSS Transition, seq 1: '
            'SNonce, PMKR0Name',
        description:
            'Fast BSS Transition authentication. The client sends its nonce '
            'and names the key hierarchy from its first connection in this '
            'mobility domain.',
      ),
    );
    out.add(
      const LadderMessage(
        from: _ap,
        to: _c,
        kind: LadderFrameKind.management,
        phase: LadderPhase.ftAuth,
        label: 'Authentication',
        detail: 'FT, seq 2: ANonce',
        fullDetail:
            'Authentication frame, Fast BSS Transition, seq 2: '
            'ANonce, R1KH-ID',
        description:
            'The target AP already holds this client\'s PMK-R1 (key '
            'distribution between APs is not drawn) and sends its nonce. '
            'Both sides can now derive the PTK.',
        milestone: LadderMilestone.keysAvailable,
        milestoneText:
            'Keys available: both sides derive the PTK from PMK-R1 and the '
            'two nonces. Nothing is encrypted yet.',
      ),
    );
    out.add(
      const LadderMessage(
        from: _c,
        to: _ap,
        kind: LadderFrameKind.management,
        phase: LadderPhase.reassociation,
        label: 'Reassociation Request',
        detail: 'FT: MIC',
        description: 'The client proves it derived the same PTK.',
      ),
    );
    out.add(
      const LadderMessage(
        from: _ap,
        to: _c,
        kind: LadderFrameKind.management,
        phase: LadderPhase.reassociation,
        label: 'Reassociation Response',
        detail: 'FT: MIC, GTK',
        description:
            'The AP proves the same and delivers the group key. The 4-way '
            'handshake is folded into these four frames.',
        milestone: LadderMilestone.trafficProtected,
        milestoneText:
            'Traffic protected: data frames are now encrypted, and the AP '
            'lets the client\'s data through.',
      ),
    );
  }

  // ── 802.1X / EAP ──────────────────────────────────────────────────────────

  void _eap() {
    final bool tunnel = c.method.isTunneled;
    out.add(
      const LadderMessage(
        from: _ap,
        to: _c,
        kind: LadderFrameKind.eapol,
        phase: LadderPhase.eapIdentity,
        label: 'EAP-Request / Identity',
        eapCode: 'EAP-Request/Identity',
        description:
            'The AP, the authenticator, asks who the client is. The AP starts '
            'this itself; the RADIUS server is not involved yet.',
      ),
    );
    out.add(
      LadderMessage(
        from: _c,
        to: _ap,
        kind: LadderFrameKind.eapol,
        phase: LadderPhase.eapIdentity,
        label: 'EAP-Response / Identity',
        detail: tunnel ? 'anonymous@realm' : 'user@realm',
        eapCode: 'EAP-Response/Identity',
        description: tunnel
            ? 'The outer identity travels unencrypted, so it is often '
                  'anonymous with only the realm. The real username goes '
                  'inside the tunnel later.'
            : 'The client names itself. This travels unencrypted.',
      ),
    );
    out.add(
      LadderMessage(
        from: _ap,
        to: _r,
        kind: LadderFrameKind.radius,
        phase: LadderPhase.eapIdentity,
        label: 'Access-Request',
        detail: 'EAP-Response / Identity',
        eapCode: 'EAP-Response/Identity',
        description:
            'The AP copies the EAP message into a RADIUS Access-Request '
            '(UDP 1812). It relays EAP; it does not authenticate the client.',
      ),
    );

    // TLS handshake.
    _turn(
      server: 'Start',
      client: 'ClientHello',
      serverDesc:
          'The RADIUS server picks $_type and starts it. The AP only relays.',
      clientDesc:
          'The client opens a TLS handshake: its TLS versions and cipher '
          'suites.',
    );
    final int f = c.certFragments;
    final bool tls = c.method == LadderMethod.eapTls;
    final String serverFlight = tls
        ? 'ServerHello, Certificate, CertificateRequest, ServerHelloDone'
        : 'ServerHello, Certificate, ServerHelloDone';
    const String clientTlsFlight =
        'Certificate, ClientKeyExchange, CertificateVerify, '
        'ChangeCipherSpec, Finished';
    const String clientTunnelFlight =
        'ClientKeyExchange, ChangeCipherSpec, Finished';
    for (int i = 1; i <= f; i++) {
      final bool last = i == f;
      final String part = f > 1 ? ' ($i of $f)' : '';
      _turn(
        server: 'Server certificate$part',
        serverFull: '$serverFlight${f > 1 ? ', fragment $i of $f' : ''}',
        serverCert: true,
        serverDesc: i == 1
            ? 'The server proves who it is with its certificate'
                  '${tls ? ' and asks for the client\'s certificate' : ''}.'
                  '${f > 1 ? ' The certificate does not fit in one EAP message, so it arrives in $f fragments.' : ''}'
            : 'The next fragment of the server\'s certificate message.',
        client: last
            ? (tls
                  ? 'Client certificate${f > 1 ? ' (1 of $f)' : ''}'
                  : 'Key exchange, Finished')
            : 'ACK (empty)',
        clientFull: last
            ? (tls
                  ? '$clientTlsFlight${f > 1 ? ', fragment 1 of $f' : ''}'
                  : clientTunnelFlight)
            : 'EAP-Response / $_type with no data: send the next fragment',
        clientCert: last && tls,
        clientDesc: last
            ? (tls
                  ? 'The client checks the server certificate, then sends '
                        'its own certificate and proof it holds the private '
                        'key. This is what PEAP and EAP-TTLS leave out.'
                  : 'The client checks the server certificate (skipping this '
                        'check is the dominant real-world EAP '
                        'misconfiguration), then finishes the handshake. It '
                        'sends no certificate of its own.')
            : 'An empty response: the client acknowledges the fragment.',
      );
    }
    if (tls) {
      for (int i = 2; i <= f; i++) {
        _turn(
          server: 'ACK (empty)',
          serverFull: 'EAP-Request / TLS with no data: send the next fragment',
          serverDesc: 'An empty request: the server acknowledges the fragment.',
          client: 'Client certificate ($i of $f)',
          clientFull: '$clientTlsFlight, fragment $i of $f',
          clientCert: true,
          clientDesc: 'The next fragment of the client\'s certificate message.',
        );
      }
    }
    switch (c.method) {
      case LadderMethod.eapTls:
        _turn(
          server: 'TLS Finished',
          serverFull: 'ChangeCipherSpec, Finished',
          serverDesc:
              'The server has checked the client certificate and finishes '
              'TLS. Both sides now share keying material.',
          client: 'ACK (empty)',
          clientFull: 'EAP-Response / TLS with no data',
          clientDesc: 'An empty response: the client is done.',
        );
      case LadderMethod.peap:
        _turn(
          server: 'TLS Finished',
          serverFull: 'ChangeCipherSpec, Finished',
          serverDesc:
              'The server finishes TLS. The tunnel is up, and only the '
              'server has proved who it is.',
          client: 'ACK (empty)',
          clientFull: 'EAP-Response / PEAP with no data',
          clientDesc: 'An empty response: the client is ready for the tunnel.',
        );
        _turn(
          tunneled: true,
          server: '{Identity}',
          serverFull: '{EAP-Request / Identity}, inside the tunnel',
          serverDesc:
              'Inside the tunnel the server asks for the identity '
              'again.',
          client: '{Identity: username}',
          clientFull: '{EAP-Response / Identity}: the real username',
          clientDesc: 'The real username, encrypted by the tunnel.',
        );
        _turn(
          tunneled: true,
          server: '{MSCHAPv2 Challenge}',
          serverDesc: 'The server sends a random challenge.',
          client: '{MSCHAPv2 Response}',
          clientFull: '{MSCHAPv2 Response}: NT-Response and peer challenge',
          clientDesc:
              'The client answers with a hash of the challenge and its '
              'password (the NT-Response). The password itself is not sent.',
        );
        _turn(
          tunneled: true,
          server: '{MSCHAPv2 Success}',
          serverFull: '{MSCHAPv2 Success}: authenticator response',
          serverDesc:
              'The server proves it knows the password too, and says the '
              'password was right.',
          client: '{MSCHAPv2 Success}',
          clientFull: '{MSCHAPv2 Success}: acknowledgement',
          clientDesc: 'The client acknowledges.',
        );
        _turn(
          tunneled: true,
          server: '{Result: success}',
          serverFull: '{Result TLV: success}',
          serverDesc: 'PEAP\'s own result message, still inside the tunnel.',
          client: '{Result: success}',
          clientFull: '{Result TLV: success}',
          clientDesc:
              'The client agrees. Both sides derive keys from the '
              'tunnel.',
        );
      case LadderMethod.eapTtls:
        if (c.inner == LadderInner.pap) {
          _turn(
            server: 'TLS Finished',
            serverFull: 'ChangeCipherSpec, Finished',
            serverDesc:
                'The server finishes TLS. The tunnel is up, and only the '
                'server has proved who it is.',
            client: '{User-Name, User-Password}',
            clientFull: '{User-Name, User-Password} AVPs, inside the tunnel',
            clientTunneled: true,
            clientDesc:
                'PAP inside the tunnel: the username and the password '
                'itself, protected only by the tunnel. The server checks it '
                'and answers with the result.',
          );
        } else {
          _turn(
            server: 'TLS Finished',
            serverFull: 'ChangeCipherSpec, Finished',
            serverDesc:
                'The server finishes TLS. The tunnel is up, and only the '
                'server has proved who it is.',
            client: '{User-Name, MSCHAPv2 Response}',
            clientFull:
                '{User-Name, MS-CHAP-Challenge, MS-CHAP2-Response} AVPs, '
                'inside the tunnel',
            clientTunneled: true,
            clientDesc:
                'The challenge comes from the tunnel keys, so the client can '
                'send its MSCHAPv2 response right away: one round trip fewer '
                'than PEAP.',
          );
          _turn(
            tunneled: true,
            server: '{MSCHAPv2 Success}',
            serverFull: '{MS-CHAP2-Success} AVP: authenticator response',
            serverDesc: 'The server proves it knows the password too.',
            client: 'ACK (empty)',
            clientFull: 'EAP-Response / TTLS with no data',
            clientTunneled: false,
            clientDesc: 'An empty response: the client is done.',
          );
        }
      case LadderMethod.psk:
      case LadderMethod.sae:
        break;
    }

    out.add(
      const LadderMessage(
        from: _r,
        to: _ap,
        kind: LadderFrameKind.radius,
        phase: LadderPhase.eapResult,
        label: 'Access-Accept',
        detail: 'EAP-Success, PMK',
        fullDetail:
            'EAP-Success, plus the PMK in the MS-MPPE key attributes (and '
            'often a VLAN)',
        eapCode: 'EAP-Success',
        description:
            'Authentication succeeded. The server hands the AP the key '
            'material, the PMK. The client derived the same PMK on its own, '
            'so it never crosses the air.',
        milestone: LadderMilestone.keysAvailable,
        milestoneText:
            'Keys available: the RADIUS server sent the PMK to the AP, and '
            'the client derived the same PMK itself. Nothing is encrypted '
            'over the air yet.',
      ),
    );
    out.add(
      const LadderMessage(
        from: _ap,
        to: _c,
        kind: LadderFrameKind.eapol,
        phase: LadderPhase.eapResult,
        label: 'EAP-Success',
        eapCode: 'EAP-Success',
        description:
            'The AP passes on the result. Both sides hold the PMK; the 4-way '
            'handshake turns it into session keys.',
      ),
    );
  }

  /// One server turn: the RADIUS server's EAP-Request in an Access-Challenge,
  /// relayed by the AP over the air; the client's EAP-Response, relayed back
  /// in an Access-Request.
  void _turn({
    required String server,
    required String client,
    required String serverDesc,
    required String clientDesc,
    String? serverFull,
    String? clientFull,
    bool tunneled = false,
    bool? clientTunneled,
    bool serverCert = false,
    bool clientCert = false,
  }) {
    final bool clientTun = clientTunneled ?? tunneled;
    final String tunnelNote = tunneled
        ? ' The braces mark content encrypted by the TLS tunnel between '
              'client and RADIUS server; the AP cannot read it.'
        : '';
    final String clientTunnelNote = clientTun
        ? ' The braces mark content encrypted by the TLS tunnel between '
              'client and RADIUS server; the AP cannot read it.'
        : '';
    final LadderPhase serverPhase = tunneled
        ? LadderPhase.innerAuth
        : LadderPhase.eapMethod;
    final LadderPhase clientPhase = clientTun
        ? LadderPhase.innerAuth
        : serverPhase;
    out.add(
      LadderMessage(
        from: _r,
        to: _ap,
        kind: LadderFrameKind.radius,
        phase: serverPhase,
        label: 'Access-Challenge',
        detail: server,
        fullDetail: 'EAP-Request / $_type: ${serverFull ?? server}',
        eapCode: 'EAP-Request',
        tunneled: tunneled,
        serverCertificate: serverCert,
        description:
            'The RADIUS server\'s next EAP-Request, inside an Access-'
            'Challenge for the AP to relay.$tunnelNote',
      ),
    );
    out.add(
      LadderMessage(
        from: _ap,
        to: _c,
        kind: LadderFrameKind.eapol,
        phase: serverPhase,
        label: 'EAP-Request / $_type',
        detail: server,
        fullDetail: serverFull,
        eapCode: 'EAP-Request',
        tunneled: tunneled,
        serverCertificate: serverCert,
        description: '$serverDesc$tunnelNote',
      ),
    );
    out.add(
      LadderMessage(
        from: _c,
        to: _ap,
        kind: LadderFrameKind.eapol,
        phase: clientPhase,
        label: 'EAP-Response / $_type',
        detail: client,
        fullDetail: clientFull,
        eapCode: 'EAP-Response',
        tunneled: clientTun,
        clientCertificate: clientCert,
        description: '$clientDesc$clientTunnelNote',
      ),
    );
    out.add(
      LadderMessage(
        from: _ap,
        to: _r,
        kind: LadderFrameKind.radius,
        phase: clientPhase,
        label: 'Access-Request',
        detail: client,
        fullDetail: 'EAP-Response / $_type: ${clientFull ?? client}',
        eapCode: 'EAP-Response',
        tunneled: clientTun,
        clientCertificate: clientCert,
        description:
            'The AP relays the client\'s EAP-Response to the RADIUS server in '
            'an Access-Request.$clientTunnelNote',
      ),
    );
  }
}
