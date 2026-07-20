import Cocoa
import FlutterMacOS
import CoreWLAN
import CoreLocation

/// Bridges the nearby-AP (neighbour BSS) list from CoreWLAN to Flutter.
///
/// Registers a FlutterMethodChannel named `com.wlanpros.toolbox/ap_scan`, the
/// SAME channel name and the SAME payload shape the Android implementation uses
/// (MainActivity.kt `readScanResults`), so both platforms feed one Dart model
/// (`ApScanSnapshot` / `ScannedAp`). The payload is:
///
///     {
///       "poweredOn": Bool,
///       "locationAuthorized": Bool,
///       "scanThrottled": Bool,
///       "accessPoints": [ { ssid, bssid, rssiDbm, channel, band, frequencyMhz } ]
///     }
///
/// Three honest constraints are encoded here:
///   1. CoreWLAN returns a nil/empty SSID and BSSID without Location Services
///      authorization (macOS 14+). A scan without it yields rows the UI cannot
///      identify, so this channel does not pretend: it reports
///      `locationAuthorized=false` with an EMPTY list, and the Dart UI renders
///      that as "the scan could not run" — deliberately distinct from a scan
///      that ran and genuinely found nothing.
///   2. CoreWLAN does NOT expose a per-neighbour noise floor for a scanned
///      (non-connected) BSS. There is therefore no noise and no SNR in this
///      payload, and none is derived. The connected interface's noise is a
///      different measurement and is not reused here.
///   3. `CWNetwork` carries a channel + band, not a center frequency. The
///      frequency is DERIVED from the channel using the fixed 802.11 channel
///      plan (an exact, standardized mapping, not an estimate) so the shared
///      Dart model keeps one required `frequencyMhz` field across platforms.
///      A BSS whose channel or band CoreWLAN leaves unknown is dropped rather
///      than guessed, mirroring Android's `mapScanResult` returning null.
///
/// Location AUTHORIZATION UI (grant prompt + Settings deep link) is deliberately
/// NOT reimplemented here. `WifiInfoChannel` already owns that flow — the
/// tri-state status token, the "Location Services is off system-wide" guard, and
/// the Privacy-pane deep link — and it is the shipped, proven path. The Dart
/// `ApScanService` routes its permission calls to the `wifi_info` channel on
/// macOS, so this channel only READS the current status to stamp the payload.
final class ApScanChannel: NSObject {
  /// The exact method channel name shared with the Dart service and with the
  /// Android implementation.
  static let channelName = "com.wlanpros.toolbox/ap_scan"

  private let channel: FlutterMethodChannel

  /// Retained for the lifetime of this object. Only its authorization STATUS is
  /// read here; no prompt is ever requested from this channel (see the class
  /// note), so no delegate is needed.
  private let locationManager = CLLocationManager()

  /// Serializes scans so two overlapping `scan` calls cannot stack two multi-
  /// second CoreWLAN scans on top of each other.
  private let scanQueue = DispatchQueue(label: "com.wlanpros.toolbox.apscan")

  /// When the last FRESH scan completed. Drives the self-imposed rate limit.
  /// Read and written on the main thread only.
  private var lastFreshScanAt: Date?

  /// Whether a fresh scan is in flight. Read and written on the main thread only.
  private var scanInFlight = false

  /// Minimum spacing between fresh CoreWLAN scans.
  ///
  /// `scanForNetworks` is an ACTIVE scan: it takes the radio off the connected
  /// channel to probe every other channel, which costs a few seconds and briefly
  /// disturbs the live connection. macOS does not rate-limit it for us the way
  /// Android rate-limits `startScan()`, so the app imposes its own floor. A
  /// request inside the window is answered from `cachedScanResults()` with
  /// `scanThrottled=true`, which is exactly the "showing the last scan" state
  /// the Android path already surfaces and the Dart UI already labels.
  private static let freshScanMinimumInterval: TimeInterval = 10

  /// Registers the channel on the given binary messenger.
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: ApScanChannel.channelName,
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  // MARK: - Method dispatch

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "scan":
      scan(result: result)
    case "lastResults":
      result(cachedSnapshot(scanThrottled: false))
    case "isLocationAuthorized":
      result(isLocationAuthorized())
    default:
      // Permission GRANT and the Settings deep link live on the wifi_info
      // channel (see the class note); the Dart service routes them there on
      // macOS rather than duplicating the flow here.
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Scanning

  /// Requests a fresh CoreWLAN scan and returns the full neighbour list.
  ///
  /// THREADING (load-bearing): `scanForNetworks` BLOCKS for seconds. Running it
  /// on the platform/main thread stalls the main thread and beachballs the UI —
  /// the same failure `connectedApIeBlob` in WifiInfoChannel documents from a
  /// field-confirmed macOS roam. The scan therefore runs on a background queue
  /// and the FlutterResult is delivered back on the main thread. The method-
  /// channel handler returns immediately; it never blocks on the scan.
  private func scan(result: @escaping FlutterResult) {
    // Inside the rate-limit window, or a scan is already running: answer from
    // the OS scan cache and SAY so, rather than queueing another active scan.
    let now = Date()
    if scanInFlight ||
        (lastFreshScanAt.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude)
        < ApScanChannel.freshScanMinimumInterval {
      result(cachedSnapshot(scanThrottled: true))
      return
    }

    let authorized = isLocationAuthorized()
    guard let iface = CWWiFiClient.shared().interface() else {
      // No Wi-Fi interface at all: poweredOn=false and an empty list.
      result(emptyPayload(poweredOn: false, locationAuthorized: authorized))
      return
    }
    let poweredOn = iface.powerOn()
    guard poweredOn, authorized else {
      // Radio off, or no Location grant. Either way the scan cannot produce an
      // honest list, so return empty WITH the flag that explains which it is.
      // The UI must render these two nulls differently from "found nothing".
      result(emptyPayload(poweredOn: poweredOn, locationAuthorized: authorized))
      return
    }

    scanInFlight = true
    scanQueue.async { [weak self] in
      var networks: [CWNetwork] = []
      var failed = false
      do {
        networks = Array(try iface.scanForNetworks(withSSID: nil))
      } catch {
        // Scan failed (radio busy, interface torn down mid-scan). Fall back to
        // the OS scan cache rather than inventing a list or throwing to Dart.
        failed = true
      }
      let aps = ApScanChannel.mapNetworks(networks)
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.scanInFlight = false
        if failed {
          // A failed fresh scan is reported as throttled-with-cache: the list
          // shown is the last one the OS holds, and the UI labels it as such.
          result(self.cachedSnapshot(scanThrottled: true))
          return
        }
        self.lastFreshScanAt = Date()
        result([
          "poweredOn": poweredOn,
          "locationAuthorized": authorized,
          "scanThrottled": false,
          "accessPoints": aps,
        ] as [String: Any?])
      }
    }
  }

  /// Builds a snapshot from the OS scan cache without triggering a new scan.
  ///
  /// `cachedScanResults()` returns whatever the last scan (ours or the system's)
  /// left behind. It is instant and does not disturb the connected link, which
  /// is what makes it the right answer both for `lastResults` and for a
  /// throttled `scan`. The cache can legitimately be empty (nil) on a machine
  /// that has not scanned since boot; that is reported as an empty list, and the
  /// authorization/power flags travelling with it let the UI explain why.
  private func cachedSnapshot(scanThrottled: Bool) -> [String: Any?] {
    let authorized = isLocationAuthorized()
    guard let iface = CWWiFiClient.shared().interface() else {
      return emptyPayload(poweredOn: false, locationAuthorized: authorized)
    }
    let poweredOn = iface.powerOn()
    guard poweredOn, authorized else {
      return emptyPayload(poweredOn: poweredOn, locationAuthorized: authorized)
    }
    let cached = iface.cachedScanResults() ?? []
    return [
      "poweredOn": poweredOn,
      "locationAuthorized": authorized,
      "scanThrottled": scanThrottled,
      "accessPoints": ApScanChannel.mapNetworks(Array(cached)),
    ]
  }

  private func emptyPayload(
    poweredOn: Bool,
    locationAuthorized: Bool
  ) -> [String: Any?] {
    return [
      "poweredOn": poweredOn,
      "locationAuthorized": locationAuthorized,
      "scanThrottled": false,
      "accessPoints": [] as [[String: Any?]],
    ]
  }

  // MARK: - CWNetwork mapping

  /// Maps a CoreWLAN scan result set to the CLEAN payload rows, dropping any
  /// BSS that cannot be described honestly.
  ///
  /// CoreWLAN can return several `CWNetwork` objects for the same BSSID across
  /// a scan (one per probe response). They are de-duplicated by BSSID, keeping
  /// the strongest RSSI seen, so the channel-occupancy counts in the UI reflect
  /// radios and not probe responses.
  private static func mapNetworks(_ networks: [CWNetwork]) -> [[String: Any?]] {
    var byBssid: [String: [String: Any?]] = [:]
    var withoutBssid: [[String: Any?]] = []
    for network in networks {
      guard let row = mapNetwork(network) else { continue }
      guard let bssid = row["bssid"] as? String, !bssid.isEmpty else {
        // BSSID withheld (Location revoked mid-scan). Kept, not merged: without
        // an identity there is nothing to de-duplicate against.
        withoutBssid.append(row)
        continue
      }
      if let existing = byBssid[bssid],
         let existingRssi = existing["rssiDbm"] as? Int,
         let newRssi = row["rssiDbm"] as? Int,
         existingRssi >= newRssi {
        continue
      }
      byBssid[bssid] = row
    }
    return Array(byBssid.values) + withoutBssid
  }

  /// Maps one `CWNetwork` to the CLEAN payload row, or null when the BSS cannot
  /// be described without guessing.
  ///
  /// Dropped when: the channel or band is unknown (no honest channel/band/
  /// frequency), or the RSSI reads 0 (CoreWLAN's "no measurement" value — the
  /// shared model requires a real dBm and a 0 dBm reading would be a fiction).
  /// A hidden network's empty SSID is passed as nil so the Dart UI renders
  /// "(hidden network)" rather than a blank or a fabricated name, matching
  /// Android's `mapScanResult`.
  ///
  /// NOT included, deliberately: noise and SNR. CoreWLAN exposes no per-
  /// neighbour noise floor, so there is nothing to report and nothing is
  /// derived (GL-005 / GL-008).
  private static func mapNetwork(_ network: CWNetwork) -> [String: Any?]? {
    guard let wlanChannel = network.wlanChannel else { return nil }
    let channelNumber = wlanChannel.channelNumber
    guard channelNumber > 0 else { return nil }
    guard let band = bandString(wlanChannel.channelBand) else { return nil }
    guard let frequency = frequencyMhz(
      channel: channelNumber,
      band: wlanChannel.channelBand
    ) else { return nil }

    let rssi = network.rssiValue
    guard rssi != 0 else { return nil }

    let rawSsid = network.ssid
    let ssid: String? = (rawSsid?.isEmpty ?? true) ? nil : rawSsid

    return [
      "ssid": ssid,
      "bssid": network.bssid,
      "rssiDbm": rssi,
      "channel": channelNumber,
      "band": band,
      "frequencyMhz": frequency,
    ]
  }

  /// Maps CWChannelBand to the band label the Dart model and the Android
  /// payload both use. Returns null for an unknown band so the BSS is dropped
  /// rather than filed under a guessed band.
  private static func bandString(_ band: CWChannelBand) -> String? {
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

  /// Derives the channel center frequency in MHz from the channel number and
  /// band, using the fixed 802.11 channel plans.
  ///
  /// This is an exact standardized mapping, not an estimate: 2.4 GHz channels
  /// 1-13 are 2407 + 5n with channel 14 the 2484 MHz exception; 5 GHz channels
  /// are 5000 + 5n; 6 GHz channels are 5950 + 5n with channel 2 the 5935 MHz
  /// exception. Android reports the frequency directly from the driver, so this
  /// keeps `frequencyMhz` a single required field in the shared Dart model.
  /// Returns null for a channel number outside the plan rather than
  /// extrapolating past it.
  private static func frequencyMhz(channel: Int, band: CWChannelBand) -> Int? {
    switch band {
    case .band2GHz:
      if channel == 14 { return 2484 }
      guard (1...13).contains(channel) else { return nil }
      return 2407 + (channel * 5)
    case .band5GHz:
      guard (1...196).contains(channel) else { return nil }
      return 5000 + (channel * 5)
    case .band6GHz:
      if channel == 2 { return 5935 }
      guard (1...233).contains(channel) else { return nil }
      return 5950 + (channel * 5)
    case .bandUnknown:
      return nil
    @unknown default:
      return nil
    }
  }

  // MARK: - Location authorization (status read only)

  /// Returns the current authorization status across macOS versions.
  ///
  /// Mirrors `WifiInfoChannel.currentAuthorizationStatus`: the instance property
  /// is macOS 11+, and the project deploys back to 10.15, so the deprecated
  /// class method is the fallback.
  private func isLocationAuthorized() -> Bool {
    let status: CLAuthorizationStatus
    if #available(macOS 11.0, *) {
      status = locationManager.authorizationStatus
    } else {
      status = CLLocationManager.authorizationStatus()
    }
    // CoreWLAN's SSID/BSSID gate is satisfied by EITHER granted state:
    // When-In-Use or Always. Anything else is unauthorized.
    switch status {
    case .authorizedAlways, .authorizedWhenInUse:
      return true
    default:
      return false
    }
  }
}
