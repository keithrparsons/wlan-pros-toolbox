// TOOLBOX APP INTENTS — NATIVE iOS.
//
// Two hand-written App Intents that form the iOS Shortcuts Wi-Fi bridge — the
// data path behind the Wi-Fi Details tool (TICKET-02). Flutter has no
// first-party App Intents API, so these are authored directly in the runner.
// Device-verified end-to-end (TICKET-01, 2026-05-31). The companion Shortcut
// (built no-code, published in ticket 3) calls:
//
//   1. LaunchToolboxIntent        — foregrounds the app so the receiver intent
//                                    has a live process to deliver into.
//   2. ReceiveWiFiDetailsIntent   — takes the harvested Wi-Fi dictionary,
//                                    already serialized to a single JSON String
//                                    by the Shortcut, and forwards it to Dart
//                                    via the App Group store + Darwin notify.
//
// App Intents framework needs iOS 16+; the RF fields harvested by the Shortcut
// need iOS 17+ ("Get Network Details"). The app's deployment target is 17.0, so
// these intents are gated at iOS 17.

import AppIntents
import Foundation

/// Foregrounds the Toolbox. The harvest Shortcut runs this first because the
/// receiver intent needs the app alive to deliver into (every decoded shipping
/// Wi-Fi app launches before delivering).
@available(iOS 17.0, *)
struct LaunchToolboxIntent: AppIntent {
  static var title: LocalizedStringResource = "Launch WLAN Pros Toolbox"

  static var description = IntentDescription(
    "Brings the WLAN Pros Toolbox app to the foreground so it can receive Wi-Fi details."
  )

  /// Bring the app to the foreground when this intent runs.
  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult {
    return .result()
  }
}

/// Receives the harvested Wi-Fi metrics as a single JSON string and forwards
/// them to the Flutter layer. String (not a typed dictionary) is the robust
/// parameter type for the Dart handoff — the Shortcut serializes its assembled
/// dictionary to JSON text before calling this.
@available(iOS 17.0, *)
struct ReceiveWiFiDetailsIntent: AppIntent {
  static var title: LocalizedStringResource = "Receive Wi-Fi Details"

  static var description = IntentDescription(
    "Hands the connected network's harvested Wi-Fi details (as JSON text) to the WLAN Pros Toolbox app."
  )

  // Bring the app forward on delivery so the running engine can pull/receive.
  static var openAppWhenRun: Bool = true

  @Parameter(
    title: "Wi-Fi Details (JSON)",
    description: "The harvested Wi-Fi dictionary, serialized to JSON text."
  )
  var json: String

  func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
    ShortcutsBridge.store(json: json)
    // Return a value so the Shortcut can branch on success if desired.
    return .result(value: true)
  }
}

/// Streaming-loop gate (TICKET-03 A3). A looping companion Shortcut calls this
/// after each delivery to decide whether to run itself again: it returns the
/// App Group monitoring-active flag, which the app sets on Start and clears on
/// Stop (via the method channel). This is the mechanism that lets in-app Stop
/// actually halt the loop. Mirrors the decoded "should stop" kill-switch pattern
/// from the shipping WiFi Monitor Agent shortcut, inverted to a "continue" gate
/// so the Shortcut's `If` branch reads naturally (If true → Run Shortcut self).
@available(iOS 17.0, *)
struct ShouldContinueMonitoringIntent: AppIntent {
  static var title: LocalizedStringResource = "Should Continue Monitoring"

  static var description = IntentDescription(
    "Returns true while the WLAN Pros Toolbox app wants the Wi-Fi monitoring loop to keep running. The companion Shortcut loops while this is true."
  )

  func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
    return .result(value: ShortcutsBridge.isMonitoringActive())
  }
}

/// Advertises the intents to Shortcuts with friendly phrases. Optional but
/// makes them discoverable in the Shortcuts action list under the app name.
@available(iOS 17.0, *)
struct ToolboxShortcutsProvider: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: LaunchToolboxIntent(),
      phrases: ["Launch \(.applicationName)"],
      shortTitle: "Launch Toolbox",
      systemImageName: "wifi"
    )
    AppShortcut(
      intent: ReceiveWiFiDetailsIntent(),
      phrases: ["Send Wi-Fi details to \(.applicationName)"],
      shortTitle: "Receive Wi-Fi Details",
      systemImageName: "antenna.radiowaves.left.and.right"
    )
    AppShortcut(
      intent: ShouldContinueMonitoringIntent(),
      phrases: ["Should \(.applicationName) keep monitoring Wi-Fi"],
      shortTitle: "Should Continue Monitoring",
      systemImageName: "dot.radiowaves.left.and.right"
    )
  }
}
