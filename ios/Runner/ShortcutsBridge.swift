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
