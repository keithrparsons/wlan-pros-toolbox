// WIFI SECURITY CHANNEL — NATIVE iOS (TICKET-BATCH7, items #6 + #9/#10).
//
// Bridges the connected network's SECURITY TYPE and BSSID from NEHotspotNetwork
// to Flutter. Registers a FlutterMethodChannel named
// `com.wlanpros.toolbox/wifi_security`.
//
// WHY A SEPARATE CHANNEL FROM THE SHORTCUTS BRIDGE: the iOS RF metrics (RSSI,
// rate, channel) arrive through the companion Shortcut path (Apple's privacy
// context yields more than an app can read directly). But the SECURITY TYPE and
// the BSSID are readable DIRECTLY by the app via NEHotspotNetwork — provided the
// app holds the Access Wi-Fi Information entitlement
// (`com.apple.developer.networking.wifi-info`) AND has Location-When-In-Use
// authorization. So we read those two fields natively here and the Dart side
// folds them onto the Shortcut-derived ConnectedAp.
//
// HONESTY (GL-005 / GL-008): every read is wrapped defensively. Without the
// entitlement, without Location permission, or with no current network,
// `fetchCurrent` yields nil and we return a payload with `available:false` plus
// an honest `reason`, NOT a fabricated value. The security enum is COARSE on
// iOS: NEHotspotNetworkSecurityType is open / WEP / personal / enterprise /
// unknown — `.personal` does NOT distinguish WPA2 from WPA3, and there is no
// `.owe` case. We emit the coarse token verbatim ("personal"/"enterprise"/...)
// and let the Dart classifier label it honestly; we never claim a specific WPA3.
//
// REQUIREMENTS:
//   * iOS 14+ for NEHotspotNetwork.fetchCurrent; iOS 15+ for .securityType.
//   * Entitlement: com.apple.developer.networking.wifi-info (added to
//     Runner.entitlements this ticket — flag for App Store justification).
//   * Location-When-In-Use permission (the app already declares
//     NSLocationWhenInUseUsageDescription; the macOS/Wi-Fi-info Location gate).

import CoreLocation
import Flutter
import Foundation
import Network
import NetworkExtension
import UIKit

/// Reports the RAW facts of the device's current network path, via NWPathMonitor.
///
/// WHY THIS EXISTS (round 4, 2026-07-13). For three rounds the app answered "is
/// this device on Wi-Fi?" by asking `network_info_plus` for an IP ADDRESS and
/// inferring the link from whether one came back. That is the wrong question, and
/// every bug in rounds 2 and 3 was a consequence of it: the plugin's interface
/// filter is `strncmp(name, "en", 2)`, which is not Wi-Fi-specific (it matches a
/// USB-tether `en*` just as happily), and it returns the FIRST address it finds,
/// which on an associated interface is the link-local `fe80::`.
///
/// iOS will answer the real question directly. `NWPathMonitor` reports the
/// interface TYPES a path runs over, and `nw_interface_type_wifi` is a distinct
/// type from `_cellular` and `_wired` (pinned in the SDK: Network.framework
/// Headers/interface.h:47-52, "A Wi-Fi link"). It needs no entitlement and no
/// Location grant.
///
/// THIS CLASS DOES NOT DECIDE ANYTHING. It reports three booleans and lets the
/// Dart `WifiConnectionService` own the decision table, where every branch is
/// unit-tested and mutation-proven. A decision made here would be a decision made
/// in the one place in this codebase that the test suite cannot reach.
///
/// WHAT WAS MEASURED (2026-07-13, live NWPathMonitor on macOS 15, same framework):
///   * On an associated Wi-Fi link: default path `status = satisfied`,
///     `usesInterfaceType(.wifi) = true`, `availableInterfaces = [en0:wifi]`.
///     Notably this was true while `networksetup` reported "not associated with an
///     AirPort network" (the Location-gated SSID read) — the path monitor is
///     definitive exactly where the SSID read is blind.
///   * For an interface that cannot carry a path (`requiredInterfaceType:
///     .wiredEthernet` on a machine with no wired NIC): `status = unsatisfied`,
///     `usesInterfaceType = false`, `availableInterfaces = []`. That is the shape
///     an iPhone's Wi-Fi path takes with the radio off, and it is the ONLY shape
///     the Dart side is permitted to read as `notOnWifi`.
///
/// WHAT WAS NOT MEASURED: the behavior on a real iPhone (no device in this loop),
/// on an unassociated-but-powered Wi-Fi radio, or while hosting a Personal
/// Hotspot. The Dart decision table treats every ambiguous shape as `unknown`, so
/// an unmeasured shape degrades to the caller's prior behavior — never to a false
/// "you have no Wi-Fi". See KNOWN LIMITS in `wifi_connection_service.dart`.
final class WifiPathMonitor {
  /// A pending `read` that arrived before the monitors delivered their first path.
  private final class Waiter {
    let completion: ([String: Any]) -> Void
    init(_ completion: @escaping ([String: Any]) -> Void) {
      self.completion = completion
    }
  }

  /// Serial. NWPathMonitor delivers `pathUpdateHandler` on this queue, and every
  /// mutation of the snapshot/waiter state happens on it, so the state needs no
  /// further locking.
  private let queue = DispatchQueue(label: "com.wlanpros.toolbox.wifipath")

  /// The DEFAULT path: what the device is actually routing over right now.
  private let defaultMonitor = NWPathMonitor()

  /// A path that REQUIRES the Wi-Fi interface. `satisfied` here means a Wi-Fi link
  /// with a usable route exists, even when the default route runs elsewhere.
  private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)

  // NOTE: `NWPath` MUST be module-qualified. NetworkExtension declares its own
  // legacy `NWPath` class, and this file imports BOTH frameworks (the
  // NEHotspotNetwork read needs NetworkExtension), so the bare name is
  // ambiguous and does not compile. Caught by the iOS build, not by review.
  private var defaultPath: Network.NWPath?
  private var wifiPath: Network.NWPath?
  private var waiters: [Waiter] = []

  init() {
    defaultMonitor.pathUpdateHandler = { [weak self] path in
      guard let self = self else { return }
      self.defaultPath = path
      self.flushIfReady()
    }
    wifiMonitor.pathUpdateHandler = { [weak self] path in
      guard let self = self else { return }
      self.wifiPath = path
      self.flushIfReady()
    }
    defaultMonitor.start(queue: queue)
    wifiMonitor.start(queue: queue)
  }

  deinit {
    defaultMonitor.cancel()
    wifiMonitor.cancel()
  }

  /// Reads the latest path facts. The monitors fire their first update almost
  /// immediately on `start`, but a `read` racing app launch can still arrive
  /// first — so an unready read WAITS up to `timeoutMillis` and then answers
  /// honest-unavailable (`available: false`) rather than guessing. Dart maps
  /// `available: false` to null and falls back to the address probe.
  func read(timeoutMillis: Int, completion: @escaping ([String: Any]) -> Void) {
    queue.async {
      if let payload = self.readyPayload() {
        completion(payload)
        return
      }
      let waiter = Waiter(completion)
      self.waiters.append(waiter)
      self.queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMillis)) {
        guard let index = self.waiters.firstIndex(where: { $0 === waiter })
        else { return }  // already delivered by flushIfReady
        self.waiters.remove(at: index)
        waiter.completion(self.readyPayload() ?? WifiPathMonitor.unavailable())
      }
    }
  }

  /// Both monitors have reported at least once → we can answer.
  private func readyPayload() -> [String: Any]? {
    guard let d = defaultPath, let w = wifiPath else { return nil }
    return WifiPathMonitor.facts(defaultPath: d, wifiPath: w)
  }

  private func flushIfReady() {
    guard !waiters.isEmpty, let payload = readyPayload() else { return }
    let pending = waiters
    waiters = []
    for waiter in pending { waiter.completion(payload) }
  }

  /// The RAW facts. Three booleans, no interpretation (see the class note).
  ///
  ///   * usesWifi             the DEFAULT route runs over a Wi-Fi interface.
  ///   * wifiSatisfied        a Wi-Fi-required path has a usable route.
  ///   * wifiInterfacePresent a Wi-Fi interface appears on either path at all.
  static func facts(
    defaultPath d: Network.NWPath,
    wifiPath w: Network.NWPath
  ) -> [String: Any] {
    let wifiOnDefault = d.availableInterfaces.contains { $0.type == .wifi }
    let wifiOnWifiPath = w.availableInterfaces.contains { $0.type == .wifi }
    return [
      "available": true,
      "usesWifi": d.usesInterfaceType(.wifi),
      "wifiSatisfied": w.status == .satisfied,
      "wifiInterfacePresent": wifiOnDefault || wifiOnWifiPath,
    ]
  }

  /// The honest "iOS did not answer in time" payload. NOT a negative verdict:
  /// Dart reads this as null and falls back, never as `notOnWifi`.
  static func unavailable() -> [String: Any] {
    return [
      "available": false,
      "usesWifi": false,
      "wifiSatisfied": false,
      "wifiInterfacePresent": false,
    ]
  }
}

/// Method channel that reads the connected network's security type and BSSID via
/// NEHotspotNetwork. Self-contained: owns a CLLocationManager so it can request
/// and report Location authorization (the gate NEHotspotNetwork shares with the
/// BSSID read).
final class WifiSecurityChannel: NSObject, CLLocationManagerDelegate {
  /// The exact method channel name shared with the Dart service.
  static let channelName = "com.wlanpros.toolbox/wifi_security"

  private let channel: FlutterMethodChannel

  /// Retained for this object's lifetime so the authorization-change delegate
  /// callback can fire (a deallocated manager silently drops the callback).
  private let locationManager = CLLocationManager()

  /// Pending result for an in-flight `requestLocationPermission` call, held
  /// strongly so it survives until the delegate reports a new status.
  private var pendingPermissionResult: FlutterResult?

  /// The permission-free NWPathMonitor probe (round 4). Long-lived: it is started
  /// once at channel registration so its first path has almost always landed by
  /// the time any screen asks, and a `getWifiPath` call is then a snapshot read.
  private let pathMonitor = WifiPathMonitor()

  /// Registers the channel on the given binary messenger.
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: WifiSecurityChannel.channelName,
      binaryMessenger: messenger
    )
    super.init()
    locationManager.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  // MARK: - Method dispatch

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getSecurityInfo":
      getSecurityInfo(result: result)
    case "getWifiPath":
      // The PRIMARY "is this device on Wi-Fi?" signal (round 4). Permission-free:
      // no entitlement, no Location grant, unlike `getSecurityInfo` above. Raw
      // facts only — the Dart side owns the verdict.
      pathMonitor.read(timeoutMillis: 1500) { payload in
        DispatchQueue.main.async { result(payload) }
      }
    case "isLocationAuthorized":
      result(isLocationAuthorized())
    case "requestLocationPermission":
      requestLocationPermission(result: result)
    case "openLocationSettings":
      openLocationSettings(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Security + BSSID read

  /// Reads the current network's coarse security token and BSSID via
  /// NEHotspotNetwork.fetchCurrent. Returns a payload dictionary, never throws.
  ///
  /// Payload keys:
  ///   * available           Bool   — true only when a real network resolved.
  ///   * reason              String? — why unavailable (entitlement / permission
  ///                                   / no-network), for the honest UI state.
  ///   * securityToken       String? — "open"/"wep"/"personal"/"enterprise"/
  ///                                   "unknown" (coarse iOS enum).
  ///   * bssid               String? — the AP MAC, for the offline OUI lookup.
  ///   * ssid                String? — the network name (context only).
  ///   * locationAuthorized  Bool   — the shared Location gate's current state.
  private func getSecurityInfo(result: @escaping FlutterResult) {
    let authorized = isLocationAuthorized()

    // fetchCurrent requires iOS 14+. Below that, honest-unavailable.
    guard #available(iOS 14.0, *) else {
      result(unavailablePayload(
        reason: "Requires iOS 14 or later.",
        locationAuthorized: authorized
      ))
      return
    }

    NEHotspotNetwork.fetchCurrent { [weak self] network in
      guard let self = self else { return }
      guard let network = network else {
        // nil means: missing entitlement, no Location permission, or not
        // connected to Wi-Fi. We cannot tell which from the API alone, so the
        // reason is permission-or-network-shaped and honest about both.
        result(self.unavailablePayload(
          reason: authorized
            ? "No Wi-Fi network, or the Access Wi-Fi Information entitlement is "
              + "not active for this build."
            : "Location permission is needed to read the Wi-Fi security type "
              + "and AP vendor on iOS.",
          locationAuthorized: authorized
        ))
        return
      }

      var token: String?
      if #available(iOS 15.0, *) {
        token = self.securityToken(network.securityType)
      } else {
        // .securityType is iOS 15+. On iOS 14 we still get the BSSID but cannot
        // read the security type — honest null token, BSSID still flows.
        token = nil
      }

      result([
        "available": true,
        "reason": nil,
        "securityToken": token,
        "bssid": network.bssid,
        "ssid": network.ssid,
        "locationAuthorized": authorized,
      ] as [String: Any?])
    }
  }

  private func unavailablePayload(
    reason: String,
    locationAuthorized: Bool
  ) -> [String: Any?] {
    return [
      "available": false,
      "reason": reason,
      "securityToken": nil,
      "bssid": nil,
      "ssid": nil,
      "locationAuthorized": locationAuthorized,
    ]
  }

  /// Maps the COARSE NEHotspotNetworkSecurityType to the stable token the Dart
  /// WifiSecurityClassifier resolves. iOS gives no WPA2-vs-WPA3 distinction and
  /// no OWE case, so the tokens stay coarse on purpose (Truthfulness Audit).
  @available(iOS 15.0, *)
  private func securityToken(_ type: NEHotspotNetworkSecurityType) -> String? {
    switch type {
    case .open:
      return "open"
    case .WEP:
      return "wep"
    case .personal:
      return "personal"
    case .enterprise:
      return "enterprise"
    case .unknown:
      return "unknown"
    @unknown default:
      // A future case → honest "unknown", never a guessed scheme.
      return "unknown"
    }
  }

  // MARK: - Location authorization (shared gate with the BSSID read)

  private func currentAuthorizationStatus() -> CLAuthorizationStatus {
    if #available(iOS 14.0, *) {
      return locationManager.authorizationStatus
    } else {
      return CLLocationManager.authorizationStatus()
    }
  }

  /// Returns the current authorization status as a bool, no prompt. On iOS the
  /// relevant granted states for When-In-Use are .authorizedWhenInUse and
  /// .authorizedAlways.
  private func isLocationAuthorized() -> Bool {
    return isAuthorized(currentAuthorizationStatus())
  }

  private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
    switch status {
    case .authorizedWhenInUse, .authorizedAlways:
      return true
    default:
      return false
    }
  }

  /// Requests When-In-Use authorization if undetermined, otherwise returns the
  /// current status immediately. The result is delivered through the
  /// authorization-change delegate. If Location Services is off system-wide no
  /// prompt appears and no callback fires, so we detect that and answer the
  /// current (unauthorized) status rather than awaiting a callback forever.
  private func requestLocationPermission(result: @escaping FlutterResult) {
    let status = currentAuthorizationStatus()
    if status != .notDetermined {
      result(isAuthorized(status))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let servicesEnabled = CLLocationManager.locationServicesEnabled()
      DispatchQueue.main.async {
        guard let self = self else { return }
        if !servicesEnabled {
          result(self.isAuthorized(self.currentAuthorizationStatus()))
          return
        }
        self.pendingPermissionResult = result
        self.locationManager.requestWhenInUseAuthorization()
      }
    }
  }

  /// Opens the app's Settings page so the user can enable Location manually.
  private func openLocationSettings(result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    DispatchQueue.main.async {
      UIApplication.shared.open(url, options: [:]) { opened in
        result(opened)
      }
    }
  }

  // MARK: - CLLocationManagerDelegate

  /// Modern (iOS 14+) authorization-change callback.
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    deliverPendingPermission()
  }

  /// Legacy authorization-change callback (pre-iOS 14). iOS calls exactly one of
  /// these depending on the OS version, so both route to the same delivery.
  func locationManager(
    _ manager: CLLocationManager,
    didChangeAuthorization status: CLAuthorizationStatus
  ) {
    deliverPendingPermission()
  }

  private func deliverPendingPermission() {
    let status = currentAuthorizationStatus()
    // Ignore the transient .notDetermined that can precede the user's choice.
    guard status != .notDetermined else { return }
    if let pending = pendingPermissionResult {
      pendingPermissionResult = nil
      pending(isAuthorized(status))
    }
  }
}
