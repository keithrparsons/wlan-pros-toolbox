// Join Network - the pure list layer.
//
// Turns the Pi's raw `/toolboxapi/scan` rows into the list a human picks from.
// Kept OUT of the screen so the one rule that has already bitten us in the field
// can be unit-tested without a widget.
//
// THE RULE, AND THE INCIDENT BEHIND IT (Keith, 2026-08-30). A scan returns one
// row per BSS, so a dual-band AP appears two or three times under one name.
// Collapsing those rows by SSID ALONE is the obvious move and it is wrong:
//
//   MUDI  86:8f:31:56:df:b9  5745 MHz  wpa-psk/sae  -35 dBm
//   MUDI  e6:4b:3c:67:80:89  2437 MHz  wpa-psk      -24 dBm
//
// That is a live capture from Keith's own travel router, 2026-08-31. Keyed on
// SSID, the LOUDER 2.4 GHz row wins and the 5 GHz row disappears, and with it
// disappears the fact that the two bands run DIFFERENT SECURITY. The user is
// then offered a WPA2 join for a network whose 5 GHz BSS is WPA3-SAE, and there
// is nothing on screen that could have told them otherwise.
//
// SO THE KEY IS (SSID, BAND). Within a band the strongest BSS wins and the
// others are counted, because on one band the difference between BSSIDs is
// which radio you land on, not what the network IS.
//
// A HIDDEN SSID IS NEVER MERGED. Two hidden BSSs on the same band are two
// different networks that both decline to say their name; folding them together
// would invent a relationship the scan does not report (GL-005).

import '../../data/channel_frequency_data.dart'
    show WifiBand, WifiBandInfo, frequencyToChannel;
import 'pi_backend_client.dart'
    show PiScanNet, PiJoinSecurity, piJoinSecurityFromKeyMgmt;

/// One row in the join list: a network as it exists ON ONE BAND.
class JoinCandidate {
  const JoinCandidate({
    required this.ssid,
    required this.band,
    required this.security,
    required this.strongest,
    required this.bssCount,
    this.channel,
  });

  /// The network name, or null for a hidden BSS.
  final String? ssid;

  /// Null when the frequency matched no known channel. Kept rather than
  /// dropped: an unrecognised frequency is still a real BSS, and hiding it
  /// would be the "correct and unfindable" failure again.
  final WifiBand? band;

  final PiJoinSecurity security;

  /// The strongest BSS seen for this (SSID, band), and the one whose BSSID is
  /// shown. Joining does not target a BSSID, but the user is entitled to know
  /// which radio they are looking at.
  final PiScanNet strongest;

  /// How many BSSs on this band share this SSID. `1` is the common case; more
  /// than one means a multi-AP network and is worth showing.
  final int bssCount;

  /// The 20 MHz primary channel, when the frequency resolved to one.
  final int? channel;

  int get signalDbm => strongest.signalDbm;
  String? get bssid => strongest.bssid;
  bool get isHidden => ssid == null;

  /// "5 GHz ch 149" style secondary line, band first because band is the reason
  /// this row exists separately at all.
  String get bandLabel {
    final String b = band?.label ?? '${strongest.freqMhz} MHz';
    return channel == null ? b : '$b ch $channel';
  }
}

/// Collapse raw scan rows into the pick list.
///
/// Sorted strongest-first, which is the only ordering a person reading a scan in
/// a room expects. Ties break on SSID so the order is stable across refreshes;
/// a list that reshuffles under the finger is its own defect.
List<JoinCandidate> buildJoinCandidates(List<PiScanNet> nets) {
  final Map<String, List<PiScanNet>> groups = <String, List<PiScanNet>>{};
  final Map<String, WifiBand?> groupBand = <String, WifiBand?>{};
  final Map<String, int?> groupChannel = <String, int?>{};

  for (int i = 0; i < nets.length; i++) {
    final PiScanNet n = nets[i];
    final ({WifiBand band, int channel})? c = frequencyToChannel(
      n.freqMhz.toDouble(),
    );
    // A hidden BSS gets a key unique to itself, so two hidden networks on one
    // band stay two rows.
    final String key = n.ssid == null
        ? 'hidden $i'
        : 'named ${n.ssid} ${c?.band.name ?? n.freqMhz}';
    (groups[key] ??= <PiScanNet>[]).add(n);
    groupBand[key] = c?.band;
    groupChannel[key] = c?.channel;
  }

  final List<JoinCandidate> out = <JoinCandidate>[];
  for (final MapEntry<String, List<PiScanNet>> e in groups.entries) {
    final List<PiScanNet> members = e.value
      ..sort((PiScanNet a, PiScanNet b) => b.signalDbm.compareTo(a.signalDbm));
    final PiScanNet best = members.first;
    out.add(
      JoinCandidate(
        ssid: best.ssid,
        band: groupBand[e.key],
        channel: groupChannel[e.key],
        security: _groupSecurity(members),
        strongest: best,
        bssCount: members.length,
      ),
    );
  }

  out.sort((JoinCandidate a, JoinCandidate b) {
    final int bySignal = b.signalDbm.compareTo(a.signalDbm);
    if (bySignal != 0) return bySignal;
    // Hidden rows sort last within a signal tie: an empty name is not a name
    // that happens to sort first.
    if ((a.ssid == null) != (b.ssid == null)) return a.ssid == null ? 1 : -1;
    return (a.ssid ?? '').compareTo(b.ssid ?? '');
  });
  return out;
}

/// The security for a group.
///
/// WHY NOT JUST THE STRONGEST BSS's. Members of one (SSID, band) group should
/// advertise the same security, and when they do not, the safe answer is the
/// one that needs the MOST from the user, not the one that happens to be
/// loudest. Ordering: unsupported > WPA3 > WPA2 > open. Reporting a group as
/// open because the nearest BSS was open is exactly the kind of quiet downgrade
/// that produces a join which cannot work.
PiJoinSecurity _groupSecurity(List<PiScanNet> members) {
  PiJoinSecurity worst = PiJoinSecurity.open;
  for (final PiScanNet m in members) {
    final PiJoinSecurity s = piJoinSecurityFromKeyMgmt(m.keyMgmt);
    if (_rank(s) > _rank(worst)) worst = s;
  }
  return worst;
}

int _rank(PiJoinSecurity s) {
  switch (s) {
    case PiJoinSecurity.open:
      return 0;
    // OWE sits ABOVE open and below PSK: it encrypts, but it authenticates
    // nobody. Relative order of everything else is unchanged.
    case PiJoinSecurity.owe:
      return 1;
    case PiJoinSecurity.wpa2Psk:
      return 2;
    case PiJoinSecurity.wpa3Psk:
      return 3;
    case PiJoinSecurity.unsupported:
      return 4;
  }
}

/// What the action panel says where a passphrase field would otherwise be.
///
/// NEVER RETURNS NULL. An absent control that explains itself is the
/// requirement Keith earned on the prototype: he hit an open network, correctly
/// saw no passphrase box, and read the page as broken. Silence is itself a
/// message, and the message it sends is "this is broken".
String absentPassphraseReason(PiJoinSecurity security) {
  switch (security) {
    case PiJoinSecurity.open:
      return 'This network is open, so there is no passphrase to enter.';
    case PiJoinSecurity.owe:
      return 'This network uses OWE, sometimes called Enhanced Open. It '
          'encrypts your traffic without a password, so there is nothing to '
          'enter and nothing is sent.';
    case PiJoinSecurity.unsupported:
      // SAYS 802.1X AND NOT "Pi edition". Keith saw "this Pi edition cannot
      // accept yet" on a Mac, which is the Web-badge-on-Windows defect wearing
      // a different coat: a true statement about the wrong machine. This
      // sentence is true on every platform, because the tool deliberately
      // collects no enterprise credentials anywhere.
      return 'This network uses 802.1X. Joining it needs enterprise '
          'credentials this tool does not collect, so there is nothing to type '
          'here.';
    case PiJoinSecurity.wpa2Psk:
    case PiJoinSecurity.wpa3Psk:
      return '';
  }
}

// ── The native-scan adapter ─────────────────────────────────────────────────
//
// `buildJoinCandidates` above consumes `PiScanNet`, the WLAN Pi's scan row.
// macOS and Windows produce `ScannedAp` instead, from their own OS scan. Rather
// than grow a second grouping implementation that has to be kept in step with
// the one the MUDI incident is written into, this converts a native row into
// the Pi's shape and reuses that grouping unchanged.
//
// THE ONE THING THAT NEEDS CARE IS SECURITY, because the two sides speak
// different vocabularies. `ScannedAp.security` is a LIST of our own tokens
// (`wpa3Personal`, `owe`, ...). `PiScanNet.keyMgmt` is a single wpa_supplicant
// string (`wpa-psk sae`). This maps the first into the second rather than
// re-deriving a `PiJoinSecurity` by hand, so `piJoinSecurityFromKeyMgmt` stays
// the ONE place the precedence rules live: SAE before PSK so a transition BSS
// joins as WPA3, and EAP before either so an enterprise network with a PSK
// fallback is never silently downgraded.
//
// It is not a fudge: `wpa-psk sae` is precisely what wpa_supplicant reports for
// the transition BSS our tokens describe as `[wpa2Personal, wpa3Personal]`. The
// same fact, in the other side's words.

/// The `key_mgmt` string a Pi scan would have carried for a BSS whose security
/// our native scanners describe as [tokens].
///
/// EMPTY IN, UNSUPPORTED OUT. An empty token list means the platform named no
/// scheme we could resolve, and `ScannedAp.security` is explicit that this must
/// never be read as open. Returning `''` here would resolve to
/// `PiJoinSecurity.open` and put a user one tap from a join that cannot work,
/// so an unresolvable BSS is reported as unsupported instead.
String keyMgmtFromSecurityTokens(List<String> tokens) {
  if (tokens.isEmpty) return 'unresolved';
  final Set<String> parts = <String>{};
  for (final String raw in tokens) {
    switch (raw.trim().toLowerCase()) {
      case 'none' || 'open':
        parts.add('none');
      case 'wep':
        // No WEP case exists in PiJoinSecurity, and there should not be one: a
        // WEP join needs key material this path cannot accept. It must land on
        // unsupported, NOT on open, so it is passed through as a token the
        // resolver does not recognise.
        parts.add('wep');
      // wpaPersonalMixed is WPA/WPA2 mixed mode and was MISSING, so it fell to
      // `default` and added `unresolved`. Measured on Keith's network
      // 2026-09-17: Keith-IoT reports `wpaPersonalMixed wpa2Personal personal
      // wpa3Transition`, so every WPA2 network on his site was carrying an
      // unresolved token it did not deserve.
      case 'wpapersonal' || 'wpapersonalmixed' || 'wpa2personal' || 'personal':
        parts.add('wpa-psk');
      case 'wpa3personal':
        parts.add('sae');
      case 'wpa3transition':
        // A TRANSITION MARKER IS NOT A SCHEME. Measured on Keith's network:
        //   Keith     (WPA3 in the controller): personal wpa3Personal wpa3Transition
        //   Keith-IoT (WPA2 in the controller): wpaPersonalMixed wpa2Personal personal wpa3Transition
        // BOTH carry wpa3Transition, so it cannot be the discriminator.
        // `wpa3Personal` is. Mapping this to SAE labelled a WPA2 network WPA3.
        break;
      case 'wpaenterprise' ||
          'wpa2enterprise' ||
          'wpa3enterprise' ||
          'enterprise':
        parts.add('wpa-eap');
      case 'owe':
        parts.add('owe');
      case 'owetransition':
        // THE SAME MISTAKE, AND THE ONE KEITH CAUGHT. This marks a BSS as one
        // HALF of a transition pair and does not say which half. Measured:
        //   Keith Guest 2.4 and 5 GHz: none oweTransition  -> OPEN
        //   Keith Guest 6 GHz:         owe  oweTransition  -> OWE
        //   RACHEL-SLOW:               none oweTransition  -> OPEN
        // Reading it as OWE, then dropping `none` because two schemes were
        // present, turned every open half into an unjoinable OWE network.
        // His words: "RACHEL is NOT OWE... it is OPEN."
        break;
      default:
        // An unknown token is NOT nothing. Dropping it would leave an empty
        // string, which reads as open.
        parts.add('unresolved');
    }
  }
  // `none` alongside a real scheme is a contradiction in the source data; the
  // real scheme wins, because offering an open join for a BSS that also
  // advertises encryption is the failure that matters.
  if (parts.length > 1) parts.remove('none');
  return parts.join(' ');
}

/// Join-list rows from a native OS scan, grouped by the same (SSID, band) rule
/// the Pi path uses.
///
/// [rows] are `ScannedAp`-shaped maps as the platform channels deliver them,
/// which keeps this layer free of a dependency on the scan service.
List<JoinCandidate> joinCandidatesFromNativeRows(
  List<
    ({
      String? ssid,
      String bssid,
      int rssiDbm,
      int frequencyMhz,
      List<String> security,
    })
  >
  rows,
) {
  return buildJoinCandidates(<PiScanNet>[
    for (final r in rows)
      PiScanNet(
        ssid: r.ssid,
        bssid: r.bssid,
        signalDbm: r.rssiDbm,
        freqMhz: r.frequencyMhz,
        keyMgmt: keyMgmtFromSecurityTokens(r.security),
      ),
  ]);
}
