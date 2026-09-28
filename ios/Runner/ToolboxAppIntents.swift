// TOOLBOX APP INTENTS — NATIVE iOS.
//
// Hand-written App Intents that form the iOS Shortcuts bridge. Flutter has no
// first-party App Intents API, so these are authored directly in the runner.
// Device-verified end-to-end (TICKET-01, 2026-05-31). The companion Shortcuts
// call them:
//
//   1. LaunchToolboxIntent        — foregrounds the app so a receiver intent
//                                    has a live process to deliver into.
//   2. ReceiveWiFiDetailsIntent   — Wi-Fi-only receiver. Still used by the
//                                    Test My Connection consumer flow, which
//                                    reads the last Wi-Fi payload the user's
//                                    manual "WLAN Pros Wi-Fi" Shortcut stored.
//   3. ReceiveLiveDetailsIntent   — the COMBINED Live receiver. The one
//                                    "WLAN Pros Live" Shortcut gathers Wi-Fi +
//                                    cellular each cycle and hands BOTH to this
//                                    intent as one JSON; it splits the payload
//                                    into the two App Group keys and posts the
//                                    shared Darwin notification once. It ALSO
//                                    RETURNS the loop verdict ("Continue" /
//                                    "Stop"), so a current Shortcut needs one
//                                    intent call per cycle, not two.
//   4. ShouldContinueMonitoringIntent — the SAME loop gate as a standalone
//                                    call, kept for the older published
//                                    Shortcut generation that polls it after
//                                    the delivery. Both read one source of
//                                    truth (ShortcutsBridge.shouldContinue-
//                                    Monitoring), so the two Shortcut
//                                    generations stop identically.
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

  // STORE SILENTLY — do NOT foreground here.
  //
  // The receiver runs in a detached App Intent context. It writes the payload to
  // the App Group and posts the Darwin notification; the app picks it up on its
  // next foreground (Test My Connection re-reads the latest Wi-Fi payload). It
  // must NOT foreground the app itself — `openAppWhenRun = false` keeps the
  // receiver quiet so it can be called from inside a larger Shortcut without
  // bouncing the user into the app every cycle.
  static var openAppWhenRun: Bool = false

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

/// COMBINED Live receiver. The single "WLAN Pros Live" companion Shortcut
/// gathers Wi-Fi AND cellular each cycle and hands BOTH to this intent as ONE
/// JSON object. The intent splits that combined payload into the two App Group
/// keys the existing bridges already parse — the Wi-Fi key in the
/// `SSID/BSSID/Channel/RSSI/Noise/Standard/RX Rate/TX Rate` shape and the
/// cellular key in the `carrier/radioTechnology/signalBars/countryCode/roaming`
/// shape — then posts the shared Darwin notification ONCE. Both existing
/// observers (Wi-Fi + cellular) wake on that one post and each re-reads its own
/// key, so the two Live screens update from a single delivery.
///
/// The combined object may carry either group nested under a `wifi` / `cellular`
/// key, OR all fields flat at the top level (a hand-built Shortcut can do
/// either). We pull a nested object when present and otherwise reuse the whole
/// object for both sides — the Dart parsers are field-name-scoped and
/// case-insensitive, so a flat object populates each side from its own keys
/// without cross-contamination.
///
/// There is NO native read here: the Shortcut runs in Apple's privacy context
/// and yields more than a third-party app can read directly (CTCarrier is
/// deprecated/junk and raw cellular signal is private-API-only; Wi-Fi RF needs
/// the stock "Get Network Details" action).
@available(iOS 17.0, *)
struct ReceiveLiveDetailsIntent: AppIntent {
  static var title: LocalizedStringResource = "Receive Live Details"

  static var description = IntentDescription(
    "Hands the device's combined Wi-Fi and cellular details (as one JSON text) to the WLAN Pros Toolbox app for Live monitoring."
  )

  // STORE SILENTLY — never foreground from inside the Live loop. Foregrounding
  // each cycle would bounce the user into the app constantly; the app is already
  // foregrounded and passively consuming the stream.
  static var openAppWhenRun: Bool = false

  @Parameter(
    title: "Live Details (JSON)",
    description: "The combined Wi-Fi + cellular dictionary, serialized to JSON text."
  )
  var json: String

  /// Stores the sample AND answers the loop gate in ONE round trip.
  ///
  /// Returns the literal string [ShortcutsBridge.continueVerdict] ("Continue")
  /// while the app wants the Live loop to keep running, and
  /// [ShortcutsBridge.stopVerdict] ("Stop") otherwise. The verdict is exactly
  /// [ShortcutsBridge.shouldContinueMonitoring] — the same monitoring-active
  /// flag AND 5-minute hard cap `ShouldContinueMonitoringIntent` reports, so
  /// behaviour is unchanged; what changes is that the looping Shortcut no
  /// longer needs a SECOND intent invocation per cycle to learn it.
  ///
  /// WHY A STRING AND NOT A BOOL. A String makes the version skew fail CLOSED.
  /// A Shortcut built for this gate tests `If (result) is "Continue"`. Run that
  /// same Shortcut against an OLDER build — one whose ReceiveLiveDetails still
  /// returned a constant `true` — and the test does not match, so the loop
  /// exits after one sample. The alternative (returning Bool) would match an
  /// old build's constant `true` FOREVER, on a Shortcut that no longer polls
  /// `ShouldContinueMonitoringIntent`: an unbounded loop with no cap and a dead
  /// in-app Stop button. One quiet sample beats an unkillable stream.
  ///
  /// `ShouldContinueMonitoringIntent` REMAINS for the Shortcut generation that
  /// still polls it. Both gates read the same source of truth, so a user on the
  /// old Shortcut and a user on the new one get identical stop behaviour.
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let (wifiJson, cellularJson) = ReceiveLiveDetailsIntent.split(json)
    ShortcutsBridge.storeLive(wifiJson: wifiJson, cellularJson: cellularJson)
    let keepGoing = ShortcutsBridge.shouldContinueMonitoring()
    return .result(
      value: keepGoing ? ShortcutsBridge.continueVerdict : ShortcutsBridge.stopVerdict
    )
  }

  /// Splits the combined Live JSON into (wifiJson, cellularJson) strings, each
  /// in the shape its existing bridge parses. Pulls a nested `wifi` / `cellular`
  /// object when present; otherwise hands the whole object to both sides (the
  /// field-scoped, case-insensitive Dart parsers each take only their own keys).
  /// Returns the original string for a side when it cannot be re-serialized, so
  /// a payload is never dropped on an edge case.
  static func split(_ combined: String) -> (String?, String?) {
    guard
      let data = combined.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data),
      let map = obj as? [String: Any]
    else {
      // Not a JSON object we can split: pass the raw string to both sides and
      // let the Dart parsers extract what they recognize.
      return (combined, combined)
    }

    func reserialize(_ value: Any?) -> String? {
      guard let value = value else { return nil }
      guard JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value),
            let s = String(data: data, encoding: .utf8) else { return nil }
      return s
    }

    // Case-insensitive lookup for the nested group keys.
    func nested(_ name: String) -> Any? {
      for (k, v) in map where k.lowercased() == name { return v }
      return nil
    }

    let wifiNested = reserialize(nested("wifi"))
    let cellularNested = reserialize(nested("cellular"))

    // When neither group is nested, hand the whole flat object to both sides.
    if wifiNested == nil && cellularNested == nil {
      return (combined, combined)
    }
    return (wifiNested, cellularNested)
  }
}

/// Streaming-loop gate (TICKET-03 A3; Option B hard cap). A looping companion
/// Shortcut calls this after each delivery to decide whether to run itself
/// again. It returns [ShortcutsBridge.shouldContinueMonitoring] — the App Group
/// monitoring-active flag (set on Start, cleared on Stop via the method channel)
/// AND-ed with a HARD 5-minute time cap. The active flag alone let a runaway
/// survive process death: on a force-quit/crash mid-stream the app never cleared
/// the flag, it survived in App Group UserDefaults, and the loop ran forever with
/// no cap. The cap bounds every such orphaned loop because this gate is polled
/// every cycle. Mirrors the decoded "should stop" kill-switch pattern from the
/// shipping WiFi Monitor Agent shortcut, inverted to a "continue" gate so the
/// Shortcut's `If` branch reads naturally (If true → Run Shortcut self).
///
/// CRITICAL: the cap only works if the published "WLAN Pros Live" Shortcut polls
/// THIS intent every loop iteration. That is the settled contract; if inspection
/// ever shows it does not, a minimal Shortcut republish is required.
@available(iOS 17.0, *)
struct ShouldContinueMonitoringIntent: AppIntent {
  static var title: LocalizedStringResource = "Should Continue Monitoring"

  static var description = IntentDescription(
    "Returns true while the WLAN Pros Toolbox app wants the Live monitoring loop to keep running. The companion Shortcut loops while this is true."
  )

  func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
    return .result(value: ShortcutsBridge.shouldContinueMonitoring())
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
      intent: ReceiveLiveDetailsIntent(),
      phrases: ["Send live details to \(.applicationName)"],
      shortTitle: "Receive Live Details",
      systemImageName: "antenna.radiowaves.left.and.right"
    )
    AppShortcut(
      intent: ShouldContinueMonitoringIntent(),
      phrases: ["Should \(.applicationName) keep monitoring"],
      shortTitle: "Should Continue Monitoring",
      systemImageName: "dot.radiowaves.left.and.right"
    )
  }
}
