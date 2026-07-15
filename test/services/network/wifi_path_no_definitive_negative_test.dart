// NO DEFINITIVE NEGATIVE FROM AN UNVERIFIED SIGNAL (round-4 cold review, F-4).
//
// `WifiConnectionService` had exactly ONE branch that asserted a definitive
// negative — "you have no Wi-Fi" — from native data alone:
//
//     if (!path.wifiInterfacePresent) return WifiConnectionStatus.notOnWifi;
//
// The file header called that shape MEASURED. What was actually measured was
// macOS: `NWPathMonitor(requiredInterfaceType: .wiredEthernet)` on a machine with
// no wired NIC. That establishes precisely nothing about an iPhone mid-roam, mid
// network-transition, or backgrounded — and NO IPHONE HAS EVER RUN THIS CODE.
//
// If iOS ever reports empty `availableInterfaces` on both paths while the device
// is genuinely associated, this branch tells a user who IS on Wi-Fi that they have
// none, and BLANKS THEIR LIVE LINK. That is the R2 bug class — shipped and fixed
// twice already. Round 3 was structurally incapable of it, because it consulted
// addresses. So round 4 was NOT "strictly better in every shape": in this one
// shape, the shape nobody has ever run, it was strictly worse.
//
// THE FIX: treat `!wifiInterfacePresent` as AMBIGUOUS, not as a verdict, and let
// it fall through to the address probe exactly like every other ambiguous shape
// already does. We lose only USB-tether discrimination. We keep radio-off
// detection (no IPv4 AND no IPv6 -> notOnWifi, which the address probe resolves on
// its own). Blanking a genuinely-connected user's Wi-Fi is a vastly worse failure
// than failing to tell a tether from a link. We do not buy a small capability with
// a large silent lie.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';

/// The unmeasured shape: iOS reports NO Wi-Fi interface on either path. This is
/// what the code reads as a definitive "no Wi-Fi", and what no iPhone has ever
/// been observed to report while associated — or observed NOT to report.
class _NoWifiInterface implements WifiPathProbe {
  const _NoWifiInterface();
  @override
  Future<WifiPathFacts?> read() async => const WifiPathFacts(
        usesWifi: false,
        wifiSatisfied: false,
        wifiInterfacePresent: false,
      );
}

/// The device IS associated: the Wi-Fi interface carries a real, routable IPv4.
class _HasWifiAddress implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => '192.168.1.20';
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The radio is genuinely off / cellular-only: no address of either family.
class _NoAddressAtAll implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => null;
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

WifiConnectionService _svc(NetworkInfo net) => WifiConnectionService(
      networkInfo: net,
      platformOverride: TargetPlatform.iOS,
      pathProbe: const _NoWifiInterface(),
    );

void main() {
  test(
    'THE CONTRADICTION: native says "no Wi-Fi interface" but the device HAS a '
    'Wi-Fi address -> the user is ON WI-FI, and must never be blanked',
    () async {
      final WifiConnectionStatus status = await _svc(_HasWifiAddress()).status();

      expect(
        status,
        isNot(WifiConnectionStatus.notOnWifi),
        reason: 'A definitive negative from an UNVERIFIED native signal, '
            'contradicted by a real Wi-Fi address, is how you blank a live link '
            'for a user who is standing on it. That is the R2 bug, and this '
            'branch is the one place in the codebase that can still produce it.',
      );
      expect(
        status,
        WifiConnectionStatus.onWifi,
        reason: 'the address probe has a POSITIVE association signal — an IPv4 '
            'on the Wi-Fi interface — and it is the signal that has actually '
            'been verified in the field',
      );
    },
  );

  test(
    'radio-off / cellular-only STILL resolves to notOnWifi — the fall-through '
    'costs us nothing real',
    () async {
      // This is the whole reason the fall-through is safe: the address probe
      // already detects radio-off on its own (no IPv4 AND no IPv6). We are not
      // giving up the detection, only the unverified shortcut to it.
      final WifiConnectionStatus status = await _svc(_NoAddressAtAll()).status();

      expect(status, WifiConnectionStatus.notOnWifi,
          reason: 'the honest not-on-Wi-Fi state must survive the F-4 fix — this '
              'is the state Keith verified on his own phone');
    },
  );
}
