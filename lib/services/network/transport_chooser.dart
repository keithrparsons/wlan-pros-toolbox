// Transport chooser - which path is this test actually taking, and may the user
// change it.
//
// WHY THIS EXISTS (Keith, 2026-08-31): "If I'm on an iPhone with Wi-Fi,
// Ethernet and Cellular - I NEED to know which path is being tested. So the
// chooser needs to be aware of platform, and capabilities before giving an
// option. Then explaining WHY some don't work in certain situations."
//
// THE DEFECT THIS REPLACES. Six screens and the shared gateway chip prefill a
// target by asking `network_info_plus` for "the" local address. On macOS that
// plugin does not ask which interface holds the default route; it looks for an
// interface literally NAMED `en0` and reads that
// (NetworkInfoPlusPlugin.swift:143, read 2026-08-31). On a MacBook `en0` is
// Wi-Fi, and a Phase 0 capture the day before had the live 2500Base-T wired
// link on `en5`. So a wired Mac was being told its own network was the wireless
// one, and Network Discovery - which derives its whole scan range this way and
// offers no field to correct - scanned the wrong subnet in silence.
//
// Phase 0 concluded "select by carrier, never by name, index or flag". A full
// read of the R4's link table on 2026-08-31 showed that is necessary and NOT
// SUFFICIENT: `wlanpi0`, `wlanpi1` (monitor) and `pan0` (virtual) all report
// `carrier: true` and none of them is a link a user can be on. So the rule
// needs all three clauses, and they are implemented in [selectDefaultLink].
//
// THE HONESTY THIS FILE OWES. Offering a control that cannot work is worse than
// offering none, because the user believes the selection took effect. So every
// entry that is not choosable carries a [TransportOption.reason] in plain
// words, and that string is NEVER empty. Same rule as the join screen's absent
// passphrase box, and the same rule Keith earned in June when a silent screen
// on cellular read as broken.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'link_info.dart';
import 'pi_backend.dart';

/// The three paths a person thinks in. Deliberately NOT [LinkKind]: monitor,
/// virtual and loopback interfaces are never a transport a user chooses, and
/// putting them in this enum would invite a UI that lists them.
enum TransportKind { wifi, ethernet, cellular }

extension TransportKindLabel on TransportKind {
  String get label => switch (this) {
        TransportKind.wifi => 'Wi-Fi',
        TransportKind.ethernet => 'Ethernet',
        TransportKind.cellular => 'Cellular',
      };
}

/// What a test is trying to reach, because the answer to "can I choose the
/// path" is different for the two and collapsing them produces a control that
/// works half the time.
enum TransportScope {
  /// A host on the same subnet: ping sweep, network discovery, ARP/NDP,
  /// Wake-on-LAN, a packet to a local target. Binding a source address on the
  /// chosen interface genuinely decides which wire these leave by.
  localSubnet,

  /// Anything off-link: DNS, WHOIS, IP geolocation, SSL and HTTP inspection,
  /// a speed test. The operating system's routing table picks the interface,
  /// and an unprivileged app does not overrule it.
  internet,
}

/// Whether a platform lets us pin traffic to a chosen interface.
///
/// THE MIDDLE VALUE IS THE POINT, and it exists because a measurement corrected
/// a reasoned guess. This file first declared `canSelectInternet: false` for the
/// desktops, on the sound-sounding argument that a route is chosen by
/// DESTINATION and a packet leaving the wrong interface would be dropped.
/// Measured on the M5 on 2026-08-31 with Wi-Fi on `en0` and a wired link on
/// `en5`, binding `en0` sent a github.com connection out the Wi-Fi source and it
/// CONNECTED, because both interfaces sat on one subnet behind one gateway.
///
/// It would very likely NOT connect across two different gateways, and that case
/// is untested. Neither `yes` nor `no` is honest for a platform, because the
/// answer belongs to the MACHINE. So the desktops answer [mustProbe]: bind,
/// connect, and report what actually happened on the box in front of the user.
enum SelectSupport {
  /// The platform has a first-class API for it and it always works.
  yes,

  /// The platform forbids it outright.
  no,

  /// It depends on how this machine is wired. One connection settles it.
  mustProbe,
}

/// Why an option is or is not offered.
enum TransportState {
  /// Present, up, and carrying traffic right now (holds the default route).
  active,

  /// Present, up, and we can route this scope over it if asked.
  selectable,

  /// The hardware is here and working, but this platform will not let an
  /// unprivileged app send this scope over it.
  presentNotSelectable,

  /// The hardware is here and working, and whether we can pin traffic to it has
  /// not been established on THIS machine yet. Distinct from
  /// [presentNotSelectable]: one is a refusal, this is an unanswered question,
  /// and showing them identically would be the two-kinds-of-null error.
  presentUntested,

  /// The interface exists but has no usable link: no carrier, or no address.
  presentNoLink,

  /// No such interface on this device.
  absent,
}

/// One row of the chooser.
class TransportOption {
  const TransportOption({
    required this.kind,
    required this.state,
    required this.reason,
    required this.shortReason,
    this.link,
  });

  final TransportKind kind;
  final TransportState state;

  /// Plain-words explanation. **Never empty for a state other than [active] or
  /// [selectable]**, and asserted by test. This is the whole point of the file:
  /// a greyed row that does not say why reads as a bug.
  final String reason;

  /// The one-clause form of [reason], for the collapsed row.
  ///
  /// RULED BY KEITH, 2026-09-04, choosing "short reason always, long on tap"
  /// over both "full reason always" (a screen and a half on a phone) and
  /// "collapsed behind a Why? link". The rejected option was rejected for a
  /// specific reason worth keeping here: **a row showing only a badge is the
  /// greyed-without-saying-why defect this whole file exists to prevent.**
  ///
  /// So this field carries the same guarantee [reason] does: **never empty,
  /// for any state, asserted by test.** The long form is the extra; the short
  /// form is what a person is guaranteed to see. If you add a construction
  /// site below, you write both strings or the test fails.
  ///
  /// Keep it to one clause and no interface-name-plus-explanation compounds:
  /// it has to survive a 330 px phone row without wrapping to three lines,
  /// which is the entire reason it exists.
  final String shortReason;

  /// The interface behind this option, when there is one.
  final LinkInfo? link;

  bool get isChoosable =>
      state == TransportState.active || state == TransportState.selectable;
}

/// What a platform can do about transport selection.
///
/// EVERY FIELD BELOW IS EITHER MEASURED OR MARKED UNVERIFIED IN ITS COMMENT.
/// None of it is reasoned from how the platform "ought" to behave.
class TransportCapability {
  const TransportCapability({
    required this.canEnumerate,
    required this.canSelectLocal,
    required this.canSelectInternet,
    required this.hasCellular,
    required this.mechanism,
  });

  /// Can we list the device's interfaces at all.
  final bool canEnumerate;

  /// Can we decide which interface local-subnet traffic leaves by.
  final SelectSupport canSelectLocal;

  /// Can we decide which interface internet traffic leaves by.
  final SelectSupport canSelectInternet;

  /// Whether a cellular radio is possible on this platform at all. False here
  /// means the chooser says "this kind of device has no cellular radio" rather
  /// than leaving a mystery gap.
  final bool hasCellular;

  /// How selection is achieved, for the record and for the help text.
  final String mechanism;
}

/// The platforms this app runs on, named here so the table does not depend on
/// `dart:io` and stays unit-testable.
enum TransportPlatform { macos, windows, linux, ios, android, web, wlanPi }

/// Which platform this build is running on, for [buildTransportOptions].
///
/// HOISTED HERE 2026-09-01 because a second caller appeared. It lived inline in
/// `link_info_screen.dart`; `CurrentNetwork` now needs the same answer to
/// resolve the app-wide transport choice. **Two copies of a platform table
/// drift, and the one that drifts is the one nobody is looking at.**
///
/// [tableSource] is [LinkTable.source]. On web it is the only way to tell a
/// browser on a laptop from a browser served by the WLAN Pi, because both are
/// `kIsWeb` and they have completely different capabilities.
TransportPlatform currentTransportPlatform({String? tableSource}) {
  if (kIsWeb) {
    // THIS WAS A ONE-WORD BUG WITH THE WHOLE PI EDITION DOWNSTREAM OF IT, found
    // by Keith on 2026-09-04 with the chooser sitting inert on a real R4.
    //
    // The test was `tableSource.contains('wlanpi')` -- case-sensitive, against a
    // string a human wrote for humans. The Pi actually reports:
    //
    //     "sysfs + ip addr on the WLAN Pi (no ethtool; it is not installed)"
    //
    // "WLAN Pi" does not contain "wlanpi", so a genuine WLAN Pi was classified
    // as a PLAIN BROWSER. `kTransportCapabilities[web]` says `canEnumerate:
    // false`, so every row collapsed to absent with "A browser is not allowed to
    // see or choose network interfaces", nothing was choosable, and the chooser
    // rendered read-only. **On the same screen that was listing eth0 at 1 Gbps
    // directly above it.**
    //
    // THE REAL FIX IS NOT A BETTER SUBSTRING. [PiBackend.available] is the
    // authoritative answer -- it is set by a same-origin GET of the Pi's own
    // /toolboxapi/health, which is exactly the question being asked, and it is
    // already what [LinkTableService] uses to decide to call the Pi at all.
    // Deriving a capability from prose was the mistake; the prose is free to
    // change wording and nothing downstream should care.
    //
    // The source sniff is KEPT as a fallback, now case-insensitive and matching
    // the spaced spelling too, for callers that hold a table but no live probe
    // (the tool harnesses, and any test that constructs a table by hand).
    if (PiBackend.available) return TransportPlatform.wlanPi;
    final String s = (tableSource ?? '').toLowerCase();
    return (s.contains('wlanpi') || s.contains('wlan pi'))
        ? TransportPlatform.wlanPi
        : TransportPlatform.web;
  }
  if (Platform.isMacOS) return TransportPlatform.macos;
  if (Platform.isWindows) return TransportPlatform.windows;
  if (Platform.isLinux) return TransportPlatform.linux;
  if (Platform.isIOS) return TransportPlatform.ios;
  if (Platform.isAndroid) return TransportPlatform.android;
  return TransportPlatform.macos;
}

/// The capability table.
///
/// PROVEN, 2026-08-31, on this Mac: `Socket.connect(sourceAddress: ...)` is a
/// REAL bind, not a hint. Binding to an address the machine does not hold fails
/// with `SocketException ... errno = 49`, and binding to the machine's own
/// address connects. That is what `canSelectLocal` rests on for the desktops.
///
/// `canSelectInternet` is [SelectSupport.mustProbe] on the desktops rather than
/// a flat yes or no. On 2026-08-31, with Wi-Fi and a wired link BOTH up on one
/// subnet behind one gateway, an internet connection bound to the non-default
/// interface connected fine. Across two gateways it very likely would not, and
/// that case is untested. The machine, not the platform, holds the answer.
const Map<TransportPlatform, TransportCapability> kTransportCapabilities =
    <TransportPlatform, TransportCapability>{
  // The Pi serves its own API and every endpoint already takes an `interface`
  // parameter, so selection here is not a socket trick: we ask the Pi to use a
  // named interface and it does. This is why the radio picker on Nearby AP Scan
  // works properly and is the model for the rest.
  TransportPlatform.wlanPi: TransportCapability(
    canEnumerate: true,
    canSelectLocal: SelectSupport.yes,
    canSelectInternet: SelectSupport.yes,
    hasCellular: false,
    mechanism: 'The Pi runs the test itself and takes the interface as a '
        'parameter, so the choice is honored end to end.',
  ),
  // ConnectivityManager.bindProcessToNetwork / Network.bindSocket is the
  // documented Android way to force traffic over a chosen transport, and it is
  // how any app offers "test over cellular". It needs a platform channel this
  // app does not yet have; MainActivity already holds a ConnectivityManager for
  // readDnsServers, so the addition is small. NOT YET WIRED - the table
  // describes the platform, and the UI must still check the wiring exists.
  TransportPlatform.android: TransportCapability(
    canEnumerate: true,
    canSelectLocal: SelectSupport.yes,
    canSelectInternet: SelectSupport.yes,
    hasCellular: true,
    mechanism: 'Android lets an app bind its sockets to a chosen network, so '
        'both local and internet tests can be pinned to one path.',
  ),
  TransportPlatform.macos: TransportCapability(
    canEnumerate: true,
    canSelectLocal: SelectSupport.yes,
    canSelectInternet: SelectSupport.mustProbe,
    hasCellular: false,
    mechanism: 'Local tests are sent from the chosen interface. Whether an '
        'internet test can be pinned to it depends on how this machine is '
        'wired, so the app tries it once and tells you what happened.',
  ),
  // UNVERIFIED: no Windows capture exists at all yet. The socket API is the
  // same, so the local case is expected to behave as macOS does, but nothing
  // has been measured. Treat a Windows result as provisional until it is.
  TransportPlatform.windows: TransportCapability(
    canEnumerate: true,
    canSelectLocal: SelectSupport.yes,
    canSelectInternet: SelectSupport.mustProbe,
    hasCellular: true,
    mechanism: 'Local tests are sent from the chosen interface. Whether an '
        'internet test can be pinned to it depends on how this machine is '
        'wired, so the app tries it once and tells you what happened.',
  ),
  TransportPlatform.linux: TransportCapability(
    canEnumerate: true,
    canSelectLocal: SelectSupport.yes,
    canSelectInternet: SelectSupport.mustProbe,
    hasCellular: false,
    mechanism: 'Local tests are sent from the chosen interface. Whether an '
        'internet test can be pinned to it depends on how this machine is '
        'wired, so the app tries it once and tells you what happened.',
  ),
  // UNVERIFIED, AND DELIBERATELY THE CAUTIOUS ANSWER. iOS enumerates
  // interfaces, and an iPhone genuinely can hold Wi-Fi, cellular and a USB-C
  // Ethernet adapter at once, which is exactly Keith's case. Whether a source
  // bind survives iOS's own routing has NOT been tested on a device, and the
  // HTTP client used by most tools goes through NSURLSession, which ignores a
  // socket-level bind entirely. Claiming selection here and being wrong would
  // tell a user their test ran over Ethernet when it ran over cellular, on a
  // metered link. So: report the path, do not offer to change it, until a
  // device test says otherwise.
  TransportPlatform.ios: TransportCapability(
    canEnumerate: true,
    canSelectLocal: SelectSupport.no,
    canSelectInternet: SelectSupport.no,
    hasCellular: true,
    mechanism: 'iOS decides which path each connection takes. The app can show '
        'you which one is carrying the test, but cannot move it.',
  ),
  TransportPlatform.web: TransportCapability(
    canEnumerate: false,
    canSelectLocal: SelectSupport.no,
    canSelectInternet: SelectSupport.no,
    hasCellular: false,
    mechanism: 'A browser is not allowed to see or choose network interfaces.',
  ),
};

/// Pick the interface that is actually carrying traffic.
///
/// THREE CLAUSES, IN ORDER, AND ALL THREE ARE NEEDED.
///
/// 1. The default route is the answer whenever a link claims it. It is the only
///    field that means "traffic goes here".
/// 2. Where nothing claims it (an isolated bench network with no gateway), fall
///    back to carrier true AND a kind a user can be on AND at least one global
///    address. That excludes monitor, virtual and loopback WITHOUT naming any
///    interface, which is the part the name-based approach got wrong.
/// 3. Never break a remaining tie by list order. Two qualifying links is a real
///    situation and the honest answer is to return null and let the caller ask,
///    not to pick one silently. Silently picking one is precisely the
///    `network_info_plus` defect.
LinkInfo? selectDefaultLink(List<LinkInfo> links) {
  for (final LinkInfo l in links) {
    if (l.isDefaultRouteV4) return l;
  }
  final List<LinkInfo> usable = links.where(_isUserLink).toList();
  if (usable.length == 1) return usable.single;
  return null;
}

/// Every link a user could meaningfully be "on".
List<LinkInfo> userSelectableLinks(List<LinkInfo> links) =>
    links.where(_isUserLink).toList(growable: false);

bool _isUserLink(LinkInfo l) {
  if (l.kind != LinkKind.wired && l.kind != LinkKind.wifi) return false;
  if (l.carrier != true) return false;
  return l.addresses.any((LinkAddress a) => !a.isLinkLocal);
}

/// Map a link to the transport a person would call it. Cellular interfaces are
/// reported as [LinkKind.wired] by some sources (a modem presents as a network
/// device), so the caller passes cellular links in explicitly rather than
/// having this guess from a name - guessing from a name is the whole defect.
TransportKind? transportKindOf(LinkInfo l) => switch (l.kind) {
      LinkKind.wired => TransportKind.ethernet,
      LinkKind.wifi => TransportKind.wifi,
      _ => null,
    };

/// Build the chooser rows for one platform, one scope, and one link table.
///
/// [cellularLink] is passed separately because no platform reports a modem in a
/// way this app can distinguish from a wired interface by inspection. On iOS it
/// is `pdp_ip0`; on Android it is whatever `ConnectivityManager` names as the
/// TRANSPORT_CELLULAR network. Both are answers from a platform channel, not
/// inferences from a table.
List<TransportOption> buildTransportOptions({
  required TransportPlatform platform,
  required TransportScope scope,
  required List<LinkInfo> links,
  LinkInfo? cellularLink,
  Map<String, bool> probed = const <String, bool>{},
}) {
  final TransportCapability cap = kTransportCapabilities[platform]!;

  if (!cap.canEnumerate) {
    return TransportKind.values
        .map((TransportKind k) => TransportOption(
              kind: k,
              state: TransportState.absent,
              reason: cap.mechanism,
              shortReason: 'Not available on this platform.',
            ))
        .toList(growable: false);
  }

  final SelectSupport support = scope == TransportScope.localSubnet
      ? cap.canSelectLocal
      : cap.canSelectInternet;

  final LinkInfo? active = selectDefaultLink(links);
  final List<TransportOption> out = <TransportOption>[];

  for (final TransportKind kind in TransportKind.values) {
    if (kind == TransportKind.cellular) {
      out.add(_cellularOption(cap, cellularLink, support, scope, active, probed));
      continue;
    }

    final List<LinkInfo> ofKind =
        links.where((LinkInfo l) => transportKindOf(l) == kind).toList();

    if (ofKind.isEmpty) {
      out.add(TransportOption(
        kind: kind,
        state: TransportState.absent,
        reason: kind == TransportKind.ethernet
            ? 'No wired interface is present. Plug in an adapter or a cable '
                'and check again.'
            : 'No Wi-Fi interface is present on this device.',
        shortReason: kind == TransportKind.ethernet
            ? 'No wired interface on this device.'
            : 'No Wi-Fi interface on this device.',
      ));
      continue;
    }

    final LinkInfo? up = ofKind.where(_isUserLink).firstOrNull;
    if (up == null) {
      final LinkInfo first = ofKind.first;
      out.add(TransportOption(
        kind: kind,
        state: TransportState.presentNoLink,
        link: first,
        reason: first.carrier == true
            ? '${first.name} is up but has no address, so nothing can be sent '
                'over it yet.'
            : kind == TransportKind.ethernet
                ? '${first.name} is present with no link. A cable into a dead '
                    'switch looks exactly like no cable at all, so check both.'
                : '${first.name} is present but not associated to a network.',
        shortReason: first.carrier == true
            ? '${first.name} is up but has no address.'
            : kind == TransportKind.ethernet
                ? '${first.name} has no link. Check both ends.'
                : '${first.name} is not associated to a network.',
      ));
      continue;
    }

    if (identical(up, active) || (active != null && up.name == active.name)) {
      out.add(TransportOption(
        kind: kind,
        state: TransportState.active,
        link: up,
        reason: 'Carrying traffic now. ${up.name} holds the default route.',
        shortReason: 'Carrying traffic now.',
      ));
      continue;
    }

    out.add(_supportRow(kind, support, up, cap, scope, probed));
  }
  return out;
}

TransportOption _cellularOption(
  TransportCapability cap,
  LinkInfo? cellularLink,
  SelectSupport support,
  TransportScope scope,
  LinkInfo? active,
  Map<String, bool> probed,
) {
  if (!cap.hasCellular) {
    return const TransportOption(
      kind: TransportKind.cellular,
      state: TransportState.absent,
      reason: 'This kind of device has no cellular radio.',
      shortReason: 'No cellular radio on this device.',
    );
  }
  if (cellularLink == null) {
    return const TransportOption(
      kind: TransportKind.cellular,
      state: TransportState.absent,
      reason: 'No cellular connection. The radio may be off, in airplane '
          'mode, or without service.',
      shortReason: 'No cellular connection.',
    );
  }
  if (active != null && cellularLink.name == active.name) {
    return TransportOption(
      kind: TransportKind.cellular,
      state: TransportState.active,
      link: cellularLink,
      reason: 'Carrying traffic now. This is a metered path, so a throughput '
          'test spends your data.',
      // The metered warning stays in the SHORT form. It is the one fact here
      // that costs the user money if they miss it, and a cost warning that
      // only appears after a tap is not a warning.
      shortReason: 'Carrying traffic now. Metered, so tests spend your data.',
    );
  }
  return _supportRow(
      TransportKind.cellular, support, cellularLink, cap, scope, probed,
      extra: ' Testing over cellular spends your data allowance.',
      shortExtra: ' Metered.');
}

/// Turn a [SelectSupport] into the row a user reads.
///
/// THE THREE OUTCOMES ARE DELIBERATELY DISTINCT. "We will not" and "we have not
/// found out yet" are different facts, and rendering them the same way is the
/// two-kinds-of-null error that this codebase has already paid for twice.
TransportOption _supportRow(
  TransportKind kind,
  SelectSupport support,
  LinkInfo link,
  TransportCapability cap,
  TransportScope scope,
  Map<String, bool> probed, {
  String extra = '',
  String shortExtra = '',
}) {
  switch (support) {
    case SelectSupport.yes:
      return TransportOption(
        kind: kind,
        state: TransportState.selectable,
        link: link,
        reason: '${link.name} is up and tests can be sent from it.$extra',
        shortReason: '${link.name} is up.$shortExtra',
      );
    case SelectSupport.no:
      return TransportOption(
        kind: kind,
        state: TransportState.presentNotSelectable,
        link: link,
        reason: '${link.name} is up and carrying its own traffic, but this '
            'test cannot be moved onto it. ${cap.mechanism}',
        shortReason: '${link.name} is up, but tests cannot be moved onto it.',
      );
    case SelectSupport.mustProbe:
      final bool? result = probed[link.name];
      if (result == true) {
        return TransportOption(
          kind: kind,
          state: TransportState.selectable,
          link: link,
          reason: 'Tested on this machine: a connection sent from '
              '${link.name} succeeded.$extra',
          shortReason: 'Tested on this machine: it worked.$shortExtra',
        );
      }
      if (result == false) {
        return TransportOption(
          kind: kind,
          state: TransportState.presentNotSelectable,
          link: link,
          reason: '${link.name} is up, but a test connection sent from it did '
              'not get through. That usually means this machine routes to the '
              'internet through a different gateway.',
          shortReason: 'Tested: the connection did not get through.',
        );
      }
      return TransportOption(
        kind: kind,
        state: TransportState.presentUntested,
        link: link,
        reason: '${link.name} is up. Whether a test can be pinned to it '
            'depends on how this machine is wired, and that has not been '
            'checked yet.$extra',
        shortReason: 'Not checked on this machine yet.$shortExtra',
      );
  }
}
