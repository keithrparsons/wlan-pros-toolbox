import Flutter
import Foundation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // THROWAWAY SPIKE (TICKET-01): retained so we can tear down the Darwin
  // observer when the event channel is cancelled.
  private var bridgeEventSink: FlutterEventSink?

  // SPIKE-HSD-01: retained so the in-house mDNS EventChannel stream handler
  // stays live (replaces the GPL-3.0 bonsoir plugin; NWBrowser-backed).
  private var mdnsBrowseChannel: MdnsBrowseChannel?

  // TICKET-03 one-tap trigger: the x-callback result EventChannel sink. The
  // SceneDelegate catches the wlanprostoolbox://reading?tool=…&status=… return
  // URL and routes it here so the Flutter side learns WHICH tool fired it and
  // whether the Shortcut ran (refresh) or failed (honest error). Shared
  // statically because the URL arrives on the SceneDelegate, not the
  // AppDelegate, under the UIScene lifecycle.
  static weak var shared: AppDelegate?
  private var triggerResultSink: FlutterEventSink?

  // COLD-LAUNCH BUFFER (TICKET-03 UX fix). On a cold relaunch the callback
  // arrives in the SceneDelegate BEFORE the Flutter engine + Dart deep-link
  // listener exist. We stash it here and flush it the instant the listener
  // attaches (onListen), so the killed-app round trip deep-links to the right
  // tool instead of stranding the user on the home screen. Only the most recent
  // callback matters (a stale one would route to the wrong tool).
  private var pendingTriggerEvent: String?

  /// Serializes a parsed callback to the wire string the Dart side decodes:
  /// `"<tool>|<ok|err>"`, with an empty tool segment when the legacy bare host
  /// carried no tool (Dart then refreshes the listening screen in place).
  private func encode(_ callback: ShortcutsBridge.Callback) -> String {
    let status = callback.isError
      ? ShortcutsBridge.callbackStatusErr
      : ShortcutsBridge.callbackStatusOk
    return "\(callback.tool ?? "")|\(status)"
  }

  /// Delivers a caught x-callback to Flutter. If the Dart listener is attached
  /// (warm path) it pushes immediately; otherwise (cold launch, engine not yet
  /// listening) it buffers the event for replay on `onListen`. Called from the
  /// SceneDelegate.
  func deliverTriggerCallback(_ callback: ShortcutsBridge.Callback) {
    let wire = encode(callback)
    if let sink = triggerResultSink {
      sink(wire)
    } else {
      pendingTriggerEvent = wire
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    AppDelegate.shared = self
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The application-level binary messenger for app-owned channels.
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerShortcutsBridge(with: messenger)
    // SPIKE-HSD-01 — register the in-house NWBrowser mDNS EventChannel. Drives
    // the OS Bonjour daemon (NSBonjourServices in Info.plist, no multicast
    // entitlement). Replaces the removed GPL-3.0 bonsoir plugin.
    mdnsBrowseChannel = MdnsBrowseChannel(messenger: messenger)
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
        // TICKET-03 one-tap trigger: build and open the run-shortcut x-callback
        // URL for the named Shortcut, encoding the originating tool id so the
        // return can deep-link back to that tool's screen. iOS flicks to
        // Shortcuts, runs it (which stores the payload to the App Group via the
        // Receive*DetailsIntent), then returns to
        // wlanprostoolbox://reading?tool=<tool>&status=ok|err — caught by the
        // SceneDelegate and routed to the trigger-result event channel below.
        //
        // Args: { "name": <shortcut name>, "tool": <tool id> }.
        guard let args = call.arguments as? [String: Any],
              let name = args["name"] as? String,
              let tool = args["tool"] as? String,
              let url = ShortcutsBridge.runShortcutURL(name: name, tool: tool) else {
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

    // TICKET-03 one-tap trigger: a dedicated event channel carrying the
    // x-callback result ("ok" | "err"). Kept separate from the Darwin
    // payload-delivered stream above so the two never interleave.
    let triggerEvents = FlutterEventChannel(
      name: "com.wlanpros.toolbox/shortcuts_bridge/trigger_result",
      binaryMessenger: messenger
    )
    triggerEvents.setStreamHandler(TriggerResultStreamHandler(owner: self))
  }

  fileprivate func setTriggerResultSink(_ sink: FlutterEventSink?) {
    triggerResultSink = sink
    // Cold-launch flush: if a callback arrived before the Dart listener attached
    // (the killed-app relaunch case), replay it now so the deep-link router
    // routes to the originating tool instead of leaving the user on home.
    if let sink = sink, let pending = pendingTriggerEvent {
      pendingTriggerEvent = nil
      sink(pending)
    }
  }

  /// Darwin notification → push the latest payload up the event channel.
  fileprivate func handleBridgeDarwinNotification() {
    guard let sink = bridgeEventSink, let json = ShortcutsBridge.readLatest() else {
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

// MARK: - Trigger-result stream handler (x-callback ok/err → event channel)

/// Stream handler for the one-tap trigger result channel (TICKET-03). Holds the
/// sink on the owning AppDelegate so the SceneDelegate can push "ok" / "err"
/// when the x-callback return URL arrives.
final class TriggerResultStreamHandler: NSObject, FlutterStreamHandler {
  init(owner: AppDelegate) { self.owner = owner }
  private weak var owner: AppDelegate?

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    owner?.setTriggerResultSink(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    owner?.setTriggerResultSink(nil)
    return nil
  }
}
