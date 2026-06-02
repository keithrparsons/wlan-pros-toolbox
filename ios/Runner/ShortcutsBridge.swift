// SHORTCUTS BRIDGE — NATIVE iOS.
//
// The shared store + notification plumbing that lets the App Intents (which
// run in an out-of-process / detached App Intent execution context) hand a
// payload to the running Flutter engine. Behind the Wi-Fi Details tool
// (TICKET-02); device-verified end-to-end (TICKET-01).
//
// HANDOFF MECHANISM:
//   The receiver App Intent's `perform()` cannot assume a live
//   FlutterViewController / FlutterEngine is reachable — App Intents can be
//   dispatched into a freshly-launched or background-resumed process, and
//   there is no first-party Flutter App Intents API to ride. So we DO NOT try
//   to message a MethodChannel directly from `perform()`. Instead the intent
//   writes the JSON to an App Group shared UserDefaults key and posts a Darwin
//   (CFNotificationCenter, Darwin) notification. The Flutter side then:
//     - PULLS the key on launch / resume (covers the foreground-bounce flow),
//     - and is PUSHED via the Darwin notification when already foregrounded.
//   App Group UserDefaults is process-agnostic, which is exactly why it
//   survives the intent firing in whatever context iOS chooses. A pure
//   MethodChannel would be simpler in code but fragile across that process
//   boundary; this is the robust path the shipping apps' pattern implies.

import Foundation

enum ShortcutsBridge {
  /// App Group container shared between the app target and (later) any
  /// extension / intent execution context. Must match the App Group capability
  /// declared in Runner.entitlements.
  static let appGroupID = "group.com.wlanpros.wlanProsToolbox"

  /// UserDefaults key holding the most recent JSON payload from the Shortcut.
  static let latestPayloadKey = "shortcuts_bridge.latest_wifi_json"

  /// UserDefaults key holding the most recent CELLULAR JSON payload from the
  /// companion Shortcut (TICKET-02 cellular). Separate from the Wi-Fi key so the
  /// two tools never clobber each other's last reading.
  static let latestCellularPayloadKey = "shortcuts_bridge.latest_cellular_json"

  /// Honest install-state flag for the cellular Shortcut: has any cellular
  /// payload ever arrived? Set true the first time a cellular payload is stored;
  /// never cleared. Separate from the Wi-Fi install-state flag.
  static let hasReceivedCellularPayloadKey =
    "shortcuts_bridge.has_received_cellular_payload"

  /// Honest install-state flag (TICKET-03 A1). iOS cannot query whether a
  /// Shortcut is installed, so the app infers it from "has any payload ever
  /// arrived". Set true the first time the receiver intent stores a payload;
  /// never cleared.
  static let hasReceivedPayloadKey = "shortcuts_bridge.has_received_payload"

  /// Monitoring-active flag (TICKET-03 A2/A3). The app sets this true on Start
  /// and false on Stop. The looping companion Shortcut reads it through
  /// `ShouldContinueMonitoringIntent` to decide whether to run itself again, so
  /// in-app Stop actually halts the loop. Process-agnostic (App Group), so the
  /// out-of-process Shortcut and the app agree on one value.
  static let monitoringActiveKey = "shortcuts_bridge.monitoring_active"

  /// Darwin notification name posted after a write, so a foregrounded Flutter
  /// engine can react immediately. Plain Darwin names are process-global.
  static let darwinNotificationName = "com.wlanpros.toolbox.shortcuts_bridge.delivered"

  // MARK: - One-tap trigger x-callback (TICKET-03)

  /// Custom URL scheme registered in Info.plist (CFBundleURLSchemes). The
  /// run-shortcut x-callback returns control to the app via this scheme.
  static let callbackScheme = "wlanprostoolbox"

  /// Host the x-callback returns to (`wlanprostoolbox://reading?...`). A single
  /// host now carries BOTH the originating tool and the ok/err status as query
  /// items so the app can deep-link the user straight back to the tool screen
  /// they triggered from — even after iOS cold-relaunches the app during the
  /// Shortcuts run (the killed-app case, TICKET-03 UX fix). The legacy bare
  /// `://ok` / `://err` hosts are still honored by `parseCallback` for safety.
  static let callbackReadingHost = "reading"

  /// Query-item key carrying the originating tool id (e.g. `wifi-info`,
  /// `cellular-info`) so the app routes the return to that tool's screen.
  static let callbackToolKey = "tool"

  /// Query-item key carrying the run status (`ok` | `err`).
  static let callbackStatusKey = "status"

  /// Status values on the `status=` query item.
  static let callbackStatusOk = "ok"
  static let callbackStatusErr = "err"

  /// Legacy bare-host success value (`wlanprostoolbox://ok`). Kept so an older
  /// published Shortcut whose callbacks were not re-encoded still resolves.
  static let callbackSuccessHost = "ok"

  /// Legacy bare-host error value (`wlanprostoolbox://err`).
  static let callbackErrorHost = "err"

  /// A parsed x-callback return: which tool fired it (nil if the legacy bare
  /// host was used) and whether the run succeeded.
  struct Callback {
    let tool: String?
    let isError: Bool
  }

  /// Builds the Shortcuts run-shortcut x-callback URL for [name], encoding the
  /// originating [tool] into the success/error callback targets so the return
  /// can deep-link back to that tool's screen. URL-encodes the Shortcut name and
  /// both callback URLs. Returns nil if the name cannot be percent-encoded (it
  /// always can in practice).
  ///
  /// Result:
  ///   shortcuts://x-callback-url/run-shortcut?name=<enc>
  ///     &x-success=<enc wlanprostoolbox://reading?tool=<tool>&status=ok>
  ///     &x-error=<enc   wlanprostoolbox://reading?tool=<tool>&status=err>
  static func runShortcutURL(name: String, tool: String) -> URL? {
    var components = URLComponents()
    components.scheme = "shortcuts"
    components.host = "x-callback-url"
    components.path = "/run-shortcut"
    components.queryItems = [
      URLQueryItem(name: "name", value: name),
      URLQueryItem(name: "x-success", value: callbackURLString(tool: tool, status: callbackStatusOk)),
      URLQueryItem(name: "x-error", value: callbackURLString(tool: tool, status: callbackStatusErr)),
    ]
    return components.url
  }

  /// Builds one return URL string (`wlanprostoolbox://reading?tool=<tool>&status=<status>`),
  /// URL-encoding the tool + status query items. Used as the x-success / x-error
  /// target embedded in the run-shortcut URL.
  static func callbackURLString(tool: String, status: String) -> String {
    var components = URLComponents()
    components.scheme = callbackScheme
    components.host = callbackReadingHost
    components.queryItems = [
      URLQueryItem(name: callbackToolKey, value: tool),
      URLQueryItem(name: callbackStatusKey, value: status),
    ]
    return components.url?.absoluteString
      ?? "\(callbackScheme)://\(callbackReadingHost)?\(callbackToolKey)=\(tool)&\(callbackStatusKey)=\(status)"
  }

  /// Parses a return URL into a [Callback], or nil if it is not one of ours.
  /// Handles the new `reading?tool=&status=` form AND the legacy bare `ok`/`err`
  /// hosts (treated as tool-less, so the app falls back to refreshing whatever
  /// trigger screen is already listening).
  static func parseCallback(_ url: URL) -> Callback? {
    guard url.scheme == callbackScheme else { return nil }
    switch url.host {
    case callbackReadingHost:
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
      let tool = items?.first(where: { $0.name == callbackToolKey })?.value
      let status = items?.first(where: { $0.name == callbackStatusKey })?.value
      return Callback(tool: tool, isError: status == callbackStatusErr)
    case callbackErrorHost:
      return Callback(tool: nil, isError: true)
    case callbackSuccessHost:
      return Callback(tool: nil, isError: false)
    default:
      // Any other host on our scheme: treat as a tool-less success so the app
      // still re-reads the App Group rather than dropping the return.
      return Callback(tool: nil, isError: false)
    }
  }

  /// Shared defaults for the App Group, or nil if the capability is missing
  /// (e.g. entitlement not provisioned yet). Callers degrade honestly.
  static var sharedDefaults: UserDefaults? {
    UserDefaults(suiteName: appGroupID)
  }

  /// Persist a payload and notify any foregrounded listener. Called from the
  /// receiver App Intent's `perform()`. Also raises the honest install-state
  /// flag the first time real data arrives (TICKET-03 A1).
  static func store(json: String) {
    sharedDefaults?.set(json, forKey: latestPayloadKey)
    sharedDefaults?.set(true, forKey: hasReceivedPayloadKey)
    sharedDefaults?.synchronize()
    postDarwinNotification()
  }

  /// Read the most recent payload, or nil if none stored.
  static func readLatest() -> String? {
    sharedDefaults?.string(forKey: latestPayloadKey)
  }

  /// Honest install-state: has the app ever received a payload? (TICKET-03 A1.)
  static func hasEverReceivedPayload() -> Bool {
    sharedDefaults?.bool(forKey: hasReceivedPayloadKey) ?? false
  }

  /// Persist a CELLULAR payload and notify any foregrounded listener. Called
  /// from `ReceiveCellularDetailsIntent.perform()`. Raises the honest cellular
  /// install-state flag the first time a cellular payload arrives. Reuses the
  /// same Darwin notification as Wi-Fi so a foregrounded engine wakes; the Dart
  /// side reads the cellular key specifically.
  static func storeCellular(json: String) {
    sharedDefaults?.set(json, forKey: latestCellularPayloadKey)
    sharedDefaults?.set(true, forKey: hasReceivedCellularPayloadKey)
    sharedDefaults?.synchronize()
    postDarwinNotification()
  }

  /// Read the most recent cellular payload, or nil if none stored.
  static func readLatestCellular() -> String? {
    sharedDefaults?.string(forKey: latestCellularPayloadKey)
  }

  /// Honest install-state for the cellular Shortcut: has any cellular payload
  /// ever arrived?
  static func hasEverReceivedCellularPayload() -> Bool {
    sharedDefaults?.bool(forKey: hasReceivedCellularPayloadKey) ?? false
  }

  /// Set the monitoring-active flag the looping Shortcut consumes (A2/A3).
  static func setMonitoringActive(_ active: Bool) {
    sharedDefaults?.set(active, forKey: monitoringActiveKey)
    sharedDefaults?.synchronize()
  }

  /// Read the monitoring-active flag (A2/A3). Defaults to false.
  static func isMonitoringActive() -> Bool {
    sharedDefaults?.bool(forKey: monitoringActiveKey) ?? false
  }

  static func postDarwinNotification() {
    let name = CFNotificationName(darwinNotificationName as CFString)
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      name,
      nil,
      nil,
      true
    )
  }
}
