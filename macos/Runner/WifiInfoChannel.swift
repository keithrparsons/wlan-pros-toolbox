import Cocoa
import FlutterMacOS
import CoreWLAN
import CoreLocation

/// Bridges live Wi-Fi interface metrics from CoreWLAN to Flutter.
///
/// Registers a FlutterMethodChannel named `com.wlanpros.toolbox/wifi_info`.
/// Every CoreWLAN read is wrapped defensively: a missing interface, a nil
/// value, or an unexpected enum case becomes null in the payload rather than
/// a thrown error or a crash. The channel never throws across to Dart.
///
/// Two honest platform constraints are encoded here:
///   1. On macOS Sonoma/Sequoia and later, reading the SSID and BSSID requires
///      Location Services authorization. Without it, `ssid` and `bssid` are
///      null while all RF metrics (RSSI, noise, rate, channel, width, band,
///      PHY) still resolve. The payload reports `locationAuthorized` so the UI
///      can explain the missing fields, and a method is offered to request it.
///   2. Public CoreWLAN exposes the Tx rate (`transmitRate`) but does not
///      expose the Rx rate or the Tx power. Those fields are simply absent.
///      They are not invented or estimated here.
final class WifiInfoChannel: NSObject, CLLocationManagerDelegate {
  /// The exact method channel name shared with the Dart service.
  static let channelName = "com.wlanpros.toolbox/wifi_info"

  private let channel: FlutterMethodChannel

  /// Retained for the lifetime of this object so the authorization-change
  /// delegate callback can fire. A CLLocationManager that is deallocated
  /// before the system responds would silently drop the callback.
  private let locationManager = CLLocationManager()

  /// The pending result for an in-flight `requestLocationPermission` call.
  /// Held strongly so it survives until the delegate reports a new status.
  private var pendingPermissionResult: FlutterResult?

  /// Registers the channel on the given binary messenger.
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: WifiInfoChannel.channelName,
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
    case "getWifiInfo":
      result(currentWifiInfo())
    case "isLocationAuthorized":
      result(isLocationAuthorized())
    case "requestLocationPermission":
      requestLocationPermission(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Wi-Fi info

  /// Builds the payload dictionary. Keys are null where a value is
  /// unavailable. If no interface exists, returns poweredOn=false and all
  /// other fields null.
  private func currentWifiInfo() -> [String: Any?] {
    let authorized = isLocationAuthorized()

    guard let interface = CWWiFiClient.shared().interface() else {
      return emptyPayload(locationAuthorized: authorized)
    }

    let rssi = interface.rssiValue()
    let noise = interface.noiseMeasurement()
    // rssiValue() and noiseMeasurement() return 0 when no value is available.
    // Treat 0 as "no reading" so SNR is only computed from real measurements.
    let rssiDbm: Int? = rssi == 0 ? nil : rssi
    let noiseDbm: Int? = noise == 0 ? nil : noise
    let snrDb: Int? = (rssiDbm != nil && noiseDbm != nil)
      ? rssiDbm! - noiseDbm!
      : nil

    let txRate = interface.transmitRate()
    let txRateMbps: Double? = txRate == 0 ? nil : txRate

    let wlanChannel = interface.wlanChannel()

    return [
      "interfaceName": interface.interfaceName,
      "poweredOn": interface.powerOn(),
      "ssid": interface.ssid(),
      "bssid": interface.bssid(),
      "rssiDbm": rssiDbm,
      "noiseDbm": noiseDbm,
      "snrDb": snrDb,
      "txRateMbps": txRateMbps,
      "phyMode": phyModeString(interface.activePHYMode()),
      "channel": wlanChannel?.channelNumber,
      "channelWidthMhz": channelWidthMhz(wlanChannel?.channelWidth),
      "band": bandString(wlanChannel?.channelBand),
      "countryCode": interface.countryCode(),
      "hardwareAddress": interface.hardwareAddress(),
      "locationAuthorized": authorized,
    ]
  }

  private func emptyPayload(locationAuthorized: Bool) -> [String: Any?] {
    return [
      "interfaceName": nil,
      "poweredOn": false,
      "ssid": nil,
      "bssid": nil,
      "rssiDbm": nil,
      "noiseDbm": nil,
      "snrDb": nil,
      "txRateMbps": nil,
      "phyMode": nil,
      "channel": nil,
      "channelWidthMhz": nil,
      "band": nil,
      "countryCode": nil,
      "hardwareAddress": nil,
      "locationAuthorized": locationAuthorized,
    ]
  }

  // MARK: - Enum mapping

  /// Maps CWPHYMode to a human-readable 802.11 string, or null when unknown.
  private func phyModeString(_ mode: CWPHYMode) -> String? {
    // Wi-Fi 7 (.mode11be) exists only on the macOS 15+ SDK, so it is matched
    // first behind an availability guard rather than as a switch case (a bare
    // case would not compile against older SDKs / deployment targets).
    if #available(macOS 15.0, *) {
      if mode == .mode11be {
        return "802.11be"
      }
    }
    switch mode {
    case .modeNone:
      return nil
    case .mode11a:
      return "802.11a"
    case .mode11b:
      return "802.11b"
    case .mode11g:
      return "802.11g"
    case .mode11n:
      return "802.11n"
    case .mode11ac:
      return "802.11ac"
    case .mode11ax:
      return "802.11ax"
    // Any case beyond those above (including a future PHY mode) maps to null,
    // the honest answer until an explicit label is wired. A plain default is
    // used rather than @unknown default because this SDK already carries cases
    // beyond the ones enumerated, so the switch would otherwise be
    // non-exhaustive.
    default:
      return nil
    }
  }

  /// Maps CWChannelWidth to a width in MHz, or null when unknown.
  private func channelWidthMhz(_ width: CWChannelWidth?) -> Int? {
    guard let width = width else { return nil }
    switch width {
    case .width20MHz:
      return 20
    case .width40MHz:
      return 40
    case .width80MHz:
      return 80
    case .width160MHz:
      return 160
    case .widthUnknown:
      return nil
    @unknown default:
      return nil
    }
  }

  /// Maps CWChannelBand to a human-readable band string, or null when unknown.
  ///
  /// The 6 GHz case (.band6GHz) is referenced directly because it is present
  /// in the macOS 13+ SDK. The @unknown default guards any unrecognized case.
  private func bandString(_ band: CWChannelBand?) -> String? {
    guard let band = band else { return nil }
    switch band {
    case .band2GHz:
      return "2.4 GHz"
    case .band5GHz:
      return "5 GHz"
    case .band6GHz:
      return "6 GHz"
    case .bandUnknown:
      return nil
    @unknown default:
      return nil
    }
  }

  // MARK: - Location authorization

  /// Returns the current authorization status across macOS versions.
  ///
  /// The instance property `authorizationStatus` is only available on macOS 11
  /// and later; the project deploys back to 10.15, so the deprecated class
  /// method is used as the fallback. Both return a CLAuthorizationStatus.
  private func currentAuthorizationStatus() -> CLAuthorizationStatus {
    if #available(macOS 11.0, *) {
      return locationManager.authorizationStatus
    } else {
      return CLLocationManager.authorizationStatus()
    }
  }

  /// Returns the current authorization status as a bool, no prompt.
  private func isLocationAuthorized() -> Bool {
    return isAuthorized(currentAuthorizationStatus())
  }

  /// Maps a CLAuthorizationStatus to a simple authorized bool.
  ///
  /// On macOS the relevant granted state is `.authorizedAlways`. The
  /// `.authorized` alias is handled defensively via the @unknown default so the
  /// switch stays exhaustive without referencing a case that may be absent.
  private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
    switch status {
    case .authorizedAlways:
      return true
    default:
      return false
    }
  }

  /// Requests authorization if undetermined, otherwise returns the current
  /// status immediately. Never blocks the main thread; the prompt result is
  /// delivered through locationManagerDidChangeAuthorization.
  private func requestLocationPermission(result: @escaping FlutterResult) {
    let status = currentAuthorizationStatus()
    if status != .notDetermined {
      result(isAuthorized(status))
      return
    }
    // Determined later by the delegate. Store the pending result strongly so
    // it is not lost before the system responds.
    pendingPermissionResult = result
    locationManager.requestAlwaysAuthorization()
  }

  // MARK: - CLLocationManagerDelegate

  /// Modern (macOS 11+) authorization-change callback.
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    deliverPendingPermission()
  }

  /// Legacy (macOS 10.15) authorization-change callback. macOS calls exactly
  /// one of these depending on the OS version, so both route to the same
  /// pending-result delivery.
  func locationManager(
    _ manager: CLLocationManager,
    didChangeAuthorization status: CLAuthorizationStatus
  ) {
    deliverPendingPermission()
  }

  /// Resolves the pending permission request once the status is determined.
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
