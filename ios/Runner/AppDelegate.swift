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
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let events = FlutterEventChannel(
      name: "com.wlanpros.toolbox/shortcuts_bridge/events",
      binaryMessenger: messenger
    )
    events.setStreamHandler(self)
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
