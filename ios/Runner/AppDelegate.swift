import Flutter
import Foundation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // THROWAWAY SPIKE (TICKET-01): retained so we can tear down the Darwin
  // observer when the event channel is cancelled.
  private var bridgeEventSink: FlutterEventSink?

  // TICKET-05 cellular Live streaming: retained so the cellular stream handler
  // (its own Darwin observer + sink) stays alive for the channel's lifetime.
  private var cellularEventChannel: CellularEventStreamHandler?

  // SPIKE-HSD-01: retained so the in-house mDNS EventChannel stream handler
  // stays live (replaces the GPL-3.0 bonsoir plugin; NWBrowser-backed).
  private var mdnsBrowseChannel: MdnsBrowseChannel?

  // Batch 6: retained so the Device/System info channel handler (uptime) stays
  // live for the engine lifetime.
  private var systemInfoChannel: SystemInfoChannel?

  // TICKET-BATCH7: retained so the NEHotspotNetwork security + BSSID method
  // channel handler stays live for the engine's lifetime.
  private var wifiSecurityChannel: WifiSecurityChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The application-level binary messenger for app-owned channels.
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerShortcutsBridge(with: messenger)
    // SPIKE-HSD-01 — register the in-house NWBrowser mDNS EventChannel. Drives
    // the OS Bonjour daemon (NSBonjourServices in Info.plist, no multicast
    // entitlement). Replaces the removed GPL-3.0 bonsoir plugin.
    mdnsBrowseChannel = MdnsBrowseChannel(messenger: messenger)
    // Batch 6 — register the Device/System info channel (uptime via
    // ProcessInfo.systemUptime). App-owned MethodChannel, no entitlement.
    systemInfoChannel = SystemInfoChannel(messenger: messenger)
    // TICKET-BATCH7 — register the NEHotspotNetwork security + BSSID channel.
    // Reads the connected network's (coarse) security type and BSSID directly,
    // gated by the Access Wi-Fi Information entitlement + Location permission.
    wifiSecurityChannel = WifiSecurityChannel(messenger: messenger)
  }

  // MARK: - Shortcuts bridge (TICKET-01 spike)

  /// Wires the Dart side of the Shortcuts Wi-Fi bridge:
  ///  - MethodChannel `readLatest` → reads the App Group payload (PULL).
  ///  - EventChannel → forwards Darwin "delivered" notifications (PUSH).
  private func registerShortcutsBridge(with messenger: FlutterBinaryMessenger) {
    let method = FlutterMethodChannel(
      name: "com.wlanpros.toolbox/shortcuts_bridge",
      binaryMessenger: messenger
    )
    method.setMethodCallHandler { call, result in
      switch call.method {
      case "readLatest":
        result(ShortcutsBridge.readLatest())
      case "hasEverReceivedPayload":
        // Honest install-state (TICKET-03 A1): has any payload ever arrived?
        result(ShortcutsBridge.hasEverReceivedPayload())
      case "payloadReceivedAt":
        // WHEN the last payload landed (epoch ms), or nil. Lets the Start-aware
        // missing-Shortcut settle ask "did a payload arrive AFTER this Start?"
        // rather than demanding a live-stream push the backgrounded app cannot
        // receive — the 2026-07-14 live-feed regression. See ShortcutsBridge.store.
        result(ShortcutsBridge.payloadReceivedAt())
      case "consumeShortcutMissing":
        // One-shot consume of the transient missing-Shortcut marker (set when the
        // one-shot x-error callback fired because "WLAN Pros Live" was gone).
        // Drives the "Shortcut not found — re-run setup" recovery copy once on the
        // next foreground load.
        result(ShortcutsBridge.consumeShortcutMissing())
      case "markSetupInitiated":
        // The user started setup (tapped "Add the Shortcut"). Drives the
        // post-install priming step until the first payload completes the
        // round-trip.
        ShortcutsBridge.markSetupInitiated()
        result(nil)
      case "hasInitiatedSetup":
        // True between "started setup" and "first payload arrives" — the app shows
        // the priming step ("tap Get reading to finish") instead of cold setup.
        result(ShortcutsBridge.hasInitiatedSetup())
      case "setLiveOriginRoute":
        // The live tool records its route so an x-error can route the user back to
        // it (and its recovery card) instead of the home strand.
        if let route = call.arguments as? String {
          ShortcutsBridge.setLiveOriginRoute(route)
        }
        result(nil)
      case "consumeLiveErrorNav":
        // One-shot consume of the pending x-error navigation; returns the origin
        // tool route (or "" when none), or nil when no nav is pending.
        result(ShortcutsBridge.consumeLiveErrorNav())
      case "isShortcutsAppInstalled":
        // Best-effort presence check (Tom Hollingsworth): many users do not have
        // Apple's Shortcuts app installed, so they fail before step one. `shortcuts`
        // is whitelisted in LSApplicationQueriesSchemes, so canOpenURL is a valid
        // signal here. Run on the main thread (UIApplication).
        DispatchQueue.main.async {
          let url = URL(string: "shortcuts://")
          let installed = url.map { UIApplication.shared.canOpenURL($0) } ?? false
          result(installed)
        }
      case "readLatestCellular":
        // TICKET-02 cellular: read the App Group cellular payload (PULL).
        result(ShortcutsBridge.readLatestCellular())
      case "hasEverReceivedCellularPayload":
        // Honest cellular install-state: has any cellular payload arrived?
        result(ShortcutsBridge.hasEverReceivedCellularPayload())
      case "setMonitoringActive":
        // Write/clear the loop-gate flag from the in-app Start/Stop control.
        let active = (call.arguments as? Bool) ?? false
        ShortcutsBridge.setMonitoringActive(active)
        result(nil)
      case "isMonitoringActive":
        result(ShortcutsBridge.isMonitoringActive())
      case "resetMonitoringColdStart":
        // Option B cold-start reset: clear a stale monitoring flag + start stamp
        // left by a prior force-quit so it neither keeps an orphaned loop trusted
        // nor suppresses a legitimate new Start (the app-wide single-flight would
        // otherwise ADOPT the phantom flag instead of firing the trigger). Called
        // once from Dart main() before any live screen can run.
        ShortcutsBridge.resetMonitoringOnColdStart()
        result(nil)
      case "openUrl":
        // Open the iCloud companion-Shortcut link (TICKET-03 A1). Routed
        // through this app-owned channel so no URL-launcher plugin is added.
        guard let urlString = call.arguments as? String,
              let url = URL(string: urlString) else {
          result(false)
          return
        }
        DispatchQueue.main.async {
          UIApplication.shared.open(url, options: [:]) { success in
            result(success)
          }
        }
      case "runShortcut":
        // Live streaming trigger: build and open the PLAIN, fire-and-forget
        // `shortcuts://run-shortcut?name=<enc>` URL for the named Shortcut. NOT
        // the x-callback form — that makes the app WAIT for the Shortcut to
        // finish, and the looping Live Shortcut never finishes, so the app would
        // hang. The plain form hands the Shortcut off and returns immediately;
        // the app then passively consumes the App Group + Darwin stream the
        // recursive Shortcut feeds. `result(success)` reports only whether iOS
        // could OPEN the URL, not whether the Shortcut finished.
        //
        // Args: { "name": <shortcut name> } (a legacy "tool" key, if present,
        // is ignored — the plain trigger has no return to route).
        guard let args = call.arguments as? [String: Any],
              let name = args["name"] as? String,
              let url = ShortcutsBridge.runShortcutURL(name: name) else {
          result(false)
          return
        }
        DispatchQueue.main.async {
          UIApplication.shared.open(url, options: [:]) { success in
            result(success)
          }
        }
      case "runShortcutOneShot":
        // ONE-SHOT trigger: build and open the `x-callback-url` form for the
        // named Shortcut. Unlike `runShortcut` (the plain STREAMING trigger),
        // this returns control to the app via the registered
        // `wlanprostoolbox://live-done` scheme the moment the Shortcut FINISHES —
        // so a single read auto-returns to the app instead of stranding the user
        // on the Shortcuts page. Used only for one-shot reads (Get reading,
        // auto-capture, the first read right after install); the looping monitor
        // never finishes so it stays on the plain form. `result(success)` reports
        // only whether iOS could OPEN the URL.
        guard let args = call.arguments as? [String: Any],
              let name = args["name"] as? String,
              let url = ShortcutsBridge.runShortcutOneShotURL(name: name) else {
          result(false)
          return
        }
        DispatchQueue.main.async {
          UIApplication.shared.open(url, options: [:]) { success in
            result(success)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let events = FlutterEventChannel(
      name: "com.wlanpros.toolbox/shortcuts_bridge/events",
      binaryMessenger: messenger
    )
    events.setStreamHandler(self)

    // TICKET-05 cellular Live streaming: a dedicated event channel that, on the
    // shared Darwin "delivered" notification, re-reads the CELLULAR App Group
    // key and pushes its JSON. Separate from the Wi-Fi `events` channel above so
    // the two tools stream independently and never push each other's payload.
    let cellularEvents = FlutterEventChannel(
      name: "com.wlanpros.toolbox/shortcuts_bridge/cellular_events",
      binaryMessenger: messenger
    )
    let cellularHandler = CellularEventStreamHandler()
    cellularEventChannel = cellularHandler
    cellularEvents.setStreamHandler(cellularHandler)
  }

  /// Darwin notification → push the latest payload up the event channel.
  fileprivate func handleBridgeDarwinNotification() {
    guard let sink = bridgeEventSink, let json = ShortcutsBridge.readLatest() else {
      return
    }
    sink(json)
  }
}

// MARK: - Cellular Live stream handler (TICKET-05)

/// Stream handler for the cellular Live channel. Self-contained: it owns its own
/// Darwin observer (registered with its OWN pointer, so it never interferes with
/// the AppDelegate's Wi-Fi observer) and, on each shared "delivered"
/// notification, re-reads the CELLULAR App Group key and pushes its JSON. The
/// Wi-Fi and cellular tools therefore stream independently from the one Darwin
/// signal; each reads its own key.
final class CellularEventStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    let observer = Unmanaged.passUnretained(self).toOpaque()
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      observer,
      { _, observer, _, _, _ in
        guard let observer = observer else { return }
        let me = Unmanaged<CellularEventStreamHandler>
          .fromOpaque(observer).takeUnretainedValue()
        me.handleDarwinNotification()
      },
      ShortcutsBridge.darwinNotificationName as CFString,
      nil,
      .deliverImmediately
    )
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    let observer = Unmanaged.passUnretained(self).toOpaque()
    CFNotificationCenterRemoveObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      observer,
      CFNotificationName(ShortcutsBridge.darwinNotificationName as CFString),
      nil
    )
    sink = nil
    return nil
  }

  private func handleDarwinNotification() {
    guard let sink = sink, let json = ShortcutsBridge.readLatestCellular() else {
      return
    }
    sink(json)
  }
}

// MARK: - FlutterStreamHandler (Darwin notification → event channel)

extension AppDelegate: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    bridgeEventSink = events
    let observer = Unmanaged.passUnretained(self).toOpaque()
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      observer,
      { _, observer, _, _, _ in
        guard let observer = observer else { return }
        let me = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
        me.handleBridgeDarwinNotification()
      },
      ShortcutsBridge.darwinNotificationName as CFString,
      nil,
      .deliverImmediately
    )
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    let observer = Unmanaged.passUnretained(self).toOpaque()
    CFNotificationCenterRemoveObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      observer,
      CFNotificationName(ShortcutsBridge.darwinNotificationName as CFString),
      nil
    )
    bridgeEventSink = nil
    return nil
  }
}
