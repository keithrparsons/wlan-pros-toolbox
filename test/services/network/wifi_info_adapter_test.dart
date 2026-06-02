// MacWifiInfoAdapter — the Location-permission timeout guard (fix/tmc-macos-hang).
//
// macOS gates the network NAME behind a CLLocationManager authorization request.
// In notarized non-App-Store builds the system prompt can fail to surface, or
// the delegate callback never fires, so the native `requestLocationPermission`
// call never resolves. Before the fix, EVERY caller (Test My Connection and the
// pro Wi-Fi Information tool) awaited that call unbounded and hung forever.
//
// These tests prove the adapter bounds the wait: a never-completing native
// channel resolves to `false` (treated as "not authorized") within the
// timeout instead of hanging, and a normally-resolving channel is unaffected.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';

void main() {
  // A WifiInfoService whose native channel NEVER answers — models the stalled
  // CLLocationManager prompt. platformOverride 'macos' keeps the service on its
  // supported path so it actually reaches the (hanging) invoke.
  WifiInfoService neverResolvingService() => WifiInfoService(
        invoke: (String method, [dynamic args]) => Completer<Object?>().future,
        platformOverride: 'macos',
      );

  test(
    'requestNamePermission() returns false (does not hang) when the native '
    'channel never resolves',
    () async {
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(
        service: neverResolvingService(),
        permissionTimeout: const Duration(milliseconds: 50),
      );

      // Without the timeout this await would never complete. The test's own
      // timeout is the backstop proving the bound is the adapter's, not flutter
      // _test's: the call resolves well inside it.
      final bool authorized = await adapter
          .requestNamePermission()
          .timeout(const Duration(seconds: 2));

      // A stalled prompt degrades honestly to "not authorized" — never a hang,
      // never a fabricated "true".
      expect(authorized, isFalse);
    },
  );

  test(
    'requestNamePermission() passes through a real answer when the channel '
    'resolves in time',
    () async {
      final WifiInfoService service = WifiInfoService(
        invoke: (String method, [dynamic args]) async => true,
        platformOverride: 'macos',
      );
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(
        service: service,
        permissionTimeout: const Duration(seconds: 3),
      );

      expect(await adapter.requestNamePermission(), isTrue);
    },
  );
}
