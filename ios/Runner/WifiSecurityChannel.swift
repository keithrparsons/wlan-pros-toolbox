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
import NetworkExtension
import UIKit

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
