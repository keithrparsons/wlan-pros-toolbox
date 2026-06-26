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
  /// cleared by [markShortcutMissing] when the one-shot x-error callback proves
  /// the Shortcut is gone (renamed/deleted), so the app stops trusting it.
  static let hasReceivedPayloadKey = "shortcuts_bridge.has_received_payload"

  /// Transient "the companion Shortcut was NOT FOUND on the last one-shot fire"
  /// marker. Set by [markShortcutMissing] when iOS invokes the one-shot x-error
  /// callback (`wlanprostoolbox://live-error`) — the reliable missing-Shortcut
  /// signal — and CONSUMED-once by the Dart side ([consumeShortcutMissing]) on
  /// the next foreground load, so the honest "Shortcut not found — re-run setup"
  /// recovery copy shows exactly once and the tool then falls back to the normal
  /// one-time setup prompt. Distinct from the durable install-state flags, which
  /// [markShortcutMissing] also resets.
  static let shortcutMissingKey = "shortcuts_bridge.shortcut_missing"

  /// Monitoring-active flag (TICKET-03 A2/A3). The app sets this true on Start
  /// and false on Stop. The looping companion Shortcut reads it through
  /// `ShouldContinueMonitoringIntent` to decide whether to run itself again, so
  /// in-app Stop actually halts the loop. Process-agnostic (App Group), so the
  /// out-of-process Shortcut and the app agree on one value.
  static let monitoringActiveKey = "shortcuts_bridge.monitoring_active"

  /// Darwin notification name posted after a write, so a foregrounded Flutter
  /// engine can react immediately. Plain Darwin names are process-global.
  static let darwinNotificationName = "com.wlanpros.toolbox.shortcuts_bridge.delivered"

  // MARK: - Live streaming trigger (plain, fire-and-forget)

  /// Builds the PLAIN, fire-and-forget Shortcuts run-shortcut URL for [name]:
  ///
  ///   shortcuts://run-shortcut?name=<URL-encoded name>
  ///
  /// This is deliberately NOT the `x-callback-url` form. The x-callback variant
  /// makes the firing app WAIT for the Shortcut to finish and return control via
  /// an `x-success` URL. A continuous / looping Live Shortcut never finishes, so
  /// the app would hang ("stuck, very slow, nothing happens"). The plain form
  /// hands the Shortcut off and returns immediately; the app then passively
  /// consumes the App Group + Darwin stream the recursive Shortcut feeds. The
  /// name is percent-encoded by URLComponents. Returns nil only if the name
  /// cannot be encoded (never in practice).
  static func runShortcutURL(name: String) -> URL? {
    var components = URLComponents()
    components.scheme = "shortcuts"
    components.host = "run-shortcut"
    components.queryItems = [URLQueryItem(name: "name", value: name)]
    return components.url
  }

  /// The custom URL scheme iOS uses to bring the Toolbox back to the foreground
  /// after a ONE-SHOT Shortcut run completes. Registered in Info.plist
  /// (CFBundleURLTypes). Used only by the x-callback one-shot trigger below; the
  /// looping STREAMING trigger stays on the plain fire-and-forget form (it never
  /// finishes, so there is nothing to return to).
  static let callbackScheme = "wlanprostoolbox"

  /// The full return URL the one-shot x-callback hands to `x-success`. iOS opens
  /// this when the Shortcut FINISHES, which re-foregrounds the Toolbox so a
  /// one-shot read auto-returns instead of stranding the user on the Shortcuts
  /// page. The host (`live-done`) lets the app distinguish this callback.
  static let callbackSuccessURLString = "\(callbackScheme)://live-done"

  /// The full return URL the one-shot x-callback hands to `x-error`. iOS opens
  /// this when the named Shortcut CANNOT RUN — most importantly when "WLAN Pros
  /// Live" is MISSING (renamed or deleted). Before this existed there was no
  /// x-error URL, so iOS had nowhere to return: a missing Shortcut showed the
  /// system "The File Doesn't Exist" alert and then STRANDED the user on the
  /// Shortcuts page with no path back into the app (Keith, iPhone 17 Pro, build
  /// 41). With it, iOS re-foregrounds the Toolbox via this host so the app can
  /// surface the honest "Shortcut not found — re-run setup" recovery. The host
  /// (`live-error`) lets the app distinguish this from the `live-done` success
  /// callback. (Apple x-callback-url spec: `x-error` is invoked on action
  /// failure, e.g. a Shortcut that cannot be found.)
  static let callbackErrorURLString = "\(callbackScheme)://live-error"

  /// Builds the `x-callback-url` ONE-SHOT run-shortcut URL for [name]:
  ///
  ///   shortcuts://x-callback-url/run-shortcut?name=<enc>&x-success=<enc return>
  ///
  /// Unlike [runShortcutURL] (the plain, fire-and-forget STREAMING trigger), this
  /// form makes iOS return control to the app via the `x-success` URL the MOMENT
  /// the Shortcut finishes. A one-shot "WLAN Pros Live" run gathers ONE sample,
  /// delivers it via `ReceiveLiveDetailsIntent`, sees `ShouldContinueMonitoring`
  /// is false (the app clears the flag before a one-shot), and finishes — so the
  /// x-success fires and the user lands back in the app automatically. This is
  /// what stops the "stuck on the Shortcuts page, swipe back manually" strand.
  /// It is NEVER used for the looping monitor (which never finishes). Returns nil
  /// only if the name cannot be encoded (never in practice).
  static func runShortcutOneShotURL(name: String) -> URL? {
    var components = URLComponents()
    components.scheme = "shortcuts"
    components.host = "x-callback-url"
    components.path = "/run-shortcut"
    components.queryItems = [
      URLQueryItem(name: "name", value: name),
      URLQueryItem(name: "x-success", value: callbackSuccessURLString),
      // x-error gives iOS a return URL when the named Shortcut CANNOT RUN
      // (renamed/deleted). Without it, a missing Shortcut stranded the user on
      // the Shortcuts page after the "The File Doesn't Exist" alert, with no way
      // back into the app (Keith, build 41). With it, iOS re-foregrounds the app
      // via `live-error`, which the app turns into an honest "Shortcut not found
      // — re-run setup" recovery. Safe alongside x-success: x-error fires only on
      // launch/lookup failure, x-success only on completion — never both.
      URLQueryItem(name: "x-error", value: callbackErrorURLString),
    ]
    return components.url
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
    // A real delivery disproves any pending missing-Shortcut marker so a
    // recovered Shortcut never re-surfaces the "not found" recovery.
    sharedDefaults?.set(false, forKey: shortcutMissingKey)
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

  /// Records that the companion Shortcut was NOT FOUND on the last one-shot fire
  /// (iOS invoked the x-error callback) and performs the honest install-state
  /// RESET, so every fire site stops trusting / blind-firing the now-missing
  /// Shortcut and the live tools return to "Set up live Wi-Fi" mode.
  ///
  /// WHY RESET THE DURABLE FLAGS rather than hold a transient flag alone: the
  /// fire sites gate "set-up-vs-fire" on [hasReceivedPayloadKey], AND the Dart
  /// controllers re-derive install-state from the STORED payload too (a stored
  /// reading alone implies "installed"). So a transient marker on its own would
  /// be re-overridden by the stale [latestPayloadKey] on the very next load, and
  /// the app would blind-fire the missing Shortcut again — re-stranding the user.
  /// Clearing both the trust flag AND the stale stored reading makes the reset
  /// DURABLE: install-state resolves to false until a real new payload arrives,
  /// which is the honest state (the Shortcut that produced the old reading is
  /// gone). The monitoring flag is cleared so no phantom loop survives. The one
  /// combined "WLAN Pros Live" Shortcut feeds BOTH Wi-Fi and cellular, so both
  /// sides are reset. [shortcutMissingKey] is the ONLY thing left set — a
  /// transient, consumed-once marker that lets the next load show the precise
  /// "not found — re-run setup" copy rather than a generic first-run nudge. Posts
  /// the Darwin notification so any foregrounded Live screen reacts immediately.
  static func markShortcutMissing() {
    let defaults = sharedDefaults
    defaults?.set(true, forKey: shortcutMissingKey)
    defaults?.set(false, forKey: hasReceivedPayloadKey)
    defaults?.set(false, forKey: hasReceivedCellularPayloadKey)
    defaults?.removeObject(forKey: latestPayloadKey)
    defaults?.removeObject(forKey: latestCellularPayloadKey)
    defaults?.set(false, forKey: monitoringActiveKey)
    defaults?.synchronize()
    postDarwinNotification()
  }

  /// Reads and CLEARS the transient missing-Shortcut marker (one-shot consume).
  /// The Dart controllers call this on each foreground load: a `true` drives the
  /// "Shortcut not found — re-run setup" recovery copy once, then it is cleared
  /// so the tool returns to the normal one-time setup prompt.
  static func consumeShortcutMissing() -> Bool {
    let defaults = sharedDefaults
    let missing = defaults?.bool(forKey: shortcutMissingKey) ?? false
    if missing {
      defaults?.set(false, forKey: shortcutMissingKey)
      defaults?.synchronize()
    }
    return missing
  }

  /// Read the most recent cellular payload, or nil if none stored.
  static func readLatestCellular() -> String? {
    sharedDefaults?.string(forKey: latestCellularPayloadKey)
  }

  /// Persist BOTH a Wi-Fi and a cellular payload from ONE combined Live cycle
  /// and notify listeners with a SINGLE Darwin post. Called from
  /// `ReceiveLiveDetailsIntent.perform()`: the combined "WLAN Pros Live"
  /// Shortcut gathers Wi-Fi + cellular each cycle and delivers both as one JSON
  /// to the app, which splits it into the two App Group keys the existing
  /// `wifi_details_bridge` / `cellular_info_bridge` already parse. Either side
  /// may be nil for a cycle (e.g. Wi-Fi off, or no cellular radio): a nil side
  /// is left untouched so the last good value for that side stays on screen,
  /// and its install-state flag is raised only when a real payload is written.
  /// One notification wakes BOTH foregrounded observers; each re-reads its own
  /// key.
  static func storeLive(wifiJson: String?, cellularJson: String?) {
    let defaults = sharedDefaults
    if let wifi = wifiJson, !wifi.isEmpty {
      defaults?.set(wifi, forKey: latestPayloadKey)
      defaults?.set(true, forKey: hasReceivedPayloadKey)
    }
    if let cellular = cellularJson, !cellular.isEmpty {
      defaults?.set(cellular, forKey: latestCellularPayloadKey)
      defaults?.set(true, forKey: hasReceivedCellularPayloadKey)
    }
    // Any real delivery this cycle disproves a pending missing-Shortcut marker.
    if (wifiJson?.isEmpty == false) || (cellularJson?.isEmpty == false) {
      defaults?.set(false, forKey: shortcutMissingKey)
    }
    defaults?.synchronize()
    postDarwinNotification()
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
