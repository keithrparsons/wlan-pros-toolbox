// Why is this Wi-Fi surface empty? Answer it, on every platform that can know.
//
// THE DEFECT THIS CLOSES, AND IT HAS BEEN OPEN SINCE JUNE ON ONE PATH.
//
// On 2026-06-25 a user spent hours debugging "no live data" on the live Wi-Fi
// surfaces when the real cause was that the iPhone was on CELLULAR. The app
// showed nothing, or a perpetual "Waiting for the first reading...". Keith had
// NotOnWifiCard built to end that, and it works: it fires on a POSITIVE
// not-on-Wi-Fi signal from iOS or Android.
//
// It never fires on a WIRED DESKTOP. `WifiConnectionService` can only reach
// `notOnWifi` on those two platforms; everywhere else an absent Wi-Fi address
// resolves to `unknown`, and `unknown` deliberately keeps the normal flow. So a
// Mac on Ethernet with the Wi-Fi radio off opens Wi-Fi Information and is
// offered "Start Live Monitoring" for RF that does not exist. That is the exact
// silent dead-end of June, still standing on the wired path.
//
// WHAT CHANGED TODAY, AND WHY THIS IS NOW HONEST RATHER THAN A GUESS. Until
// this morning macOS could not positively say "not on Wi-Fi": all we had was
// the absence of a Wi-Fi IP, and absence of evidence is not evidence (GL-005).
// The link table changes that. `ifconfig` reports `status: active` per
// interface, so "the Wi-Fi interface exists and has NO carrier" is a
// MEASUREMENT, not an inference. That licenses the claim the old code correctly
// refused to make.
//
// EVERY BRANCH RETURNS COPY THAT NAMES A NEXT ACTION. "Not on Wi-Fi" alone is
// only half an answer; the user still has to work out what to do.

import 'link_info.dart';
import 'transport_chooser.dart';

/// Why a live Wi-Fi surface has nothing to show.
enum WifiAbsence {
  /// A Wi-Fi interface is associated. The live surfaces should proceed.
  associated,

  /// This machine has no Wi-Fi interface at all.
  noRadio,

  /// The radio is present and not joined to anything, AND a wired link is
  /// carrying the traffic instead. The most useful case, and the one that has
  /// been silent.
  onWiredInstead,

  /// The radio is present and not joined to anything, and nothing else is
  /// carrying traffic either.
  notAssociated,

  /// We could not read enough to say. NEVER rendered as "not on Wi-Fi".
  unknown,
}

/// Classify from a link table.
///
/// [table] null means the platform could not give us one, which is [unknown]
/// and must stay that way: on iOS and Android the existing
/// `WifiConnectionService` signal is the authority and this must not overrule
/// it with a weaker guess.
WifiAbsence classifyWifiAbsence(LinkTable? table) {
  if (table == null) return WifiAbsence.unknown;

  final List<LinkInfo> wifi = table.links
      .where((LinkInfo l) => l.kind == LinkKind.wifi)
      .toList();

  if (wifi.isEmpty) {
    // Only assert "no radio" when we actually enumerated something. An empty
    // table is a failed read, not a laptop without Wi-Fi.
    return table.links.isEmpty ? WifiAbsence.unknown : WifiAbsence.noRadio;
  }

  final bool anyAssociated = wifi.any(
    (LinkInfo l) =>
        l.carrier == true && l.addresses.any((LinkAddress a) => !a.isLinkLocal),
  );
  if (anyAssociated) return WifiAbsence.associated;

  // Carrier must be a real false, not a null. A driver that did not report
  // carrier tells us nothing, and inferring "off" from silence is the mistake
  // this file exists to avoid.
  final bool allKnownDown = wifi.every((LinkInfo l) => l.carrier == false);
  if (!allKnownDown) return WifiAbsence.unknown;

  final LinkInfo? carrying = selectDefaultLink(table.links);
  if (carrying != null && carrying.kind == LinkKind.wired) {
    return WifiAbsence.onWiredInstead;
  }
  return WifiAbsence.notAssociated;
}

/// Headline and body for the empty state.
///
/// Returns null for [WifiAbsence.associated] and [WifiAbsence.unknown]: in both
/// cases the screen must keep its existing behavior. Unknown is NOT an
/// opportunity to say something reassuring.
({String title, String message})? wifiAbsenceCopy(
  WifiAbsence absence, {
  String? wiredInterfaceName,
  String? surface,
}) {
  final String what = surface ?? 'These readings';
  switch (absence) {
    case WifiAbsence.associated:
    case WifiAbsence.unknown:
      return null;
    case WifiAbsence.noRadio:
      return (
        title: 'This machine has no Wi-Fi radio',
        message:
            '$what come from a live 802.11 association: signal, noise, '
            'channel, BSSID. There is no radio here to read them from. The '
            'wired tools all work normally, and Link Info will show you what '
            'this machine does have.',
      );
    case WifiAbsence.onWiredInstead:
      return (
        title: "You're on Ethernet, not Wi-Fi",
        message:
            'Your traffic is going out '
            '${wiredInterfaceName ?? 'the wired link'}, and the Wi-Fi radio is '
            'not joined to anything. $what need a Wi-Fi association to exist, '
            'so there is nothing here to measure. Everything that runs over '
            'any connection, such as ping, DNS and the path tools, is working '
            'normally over the cable.',
      );
    case WifiAbsence.notAssociated:
      return (
        title: 'Wi-Fi is not connected',
        message:
            'The radio is present and not joined to a network. Join one '
            'and check again. $what come from a live association and cannot be '
            'read without one.',
      );
  }
}
