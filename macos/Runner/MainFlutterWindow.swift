import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Retained for the window lifetime so its MethodChannel handler stays live.
  private var wifiInfoChannel: WifiInfoChannel?
  // SPIKE-HSD-01 — retained so the ARP-table channel handler stays live.
  private var arpTableChannel: ArpTableChannel?
  // SPIKE-HSD-01 — retained so the in-house mDNS EventChannel stream handler
  // stays live (replaces the GPL-3.0 bonsoir plugin; NWBrowser-backed).
  private var mdnsBrowseChannel: MdnsBrowseChannel?
  // Batch 6 — retained so the Device/System info channel handler (uptime) stays
  // live for the window lifetime.
  private var systemInfoChannel: SystemInfoChannel?
  // Nearby AP Scan — retained so the CoreWLAN neighbour-scan channel handler
  // stays live for the window lifetime.
  private var apScanChannel: ApScanChannel?
  // Wi-Fi Lab presenter mode: full screen on request (window.toggleFullScreen).
  // Retained so its handler stays live for the window lifetime.
  private var presenterWindowChannel: FlutterMethodChannel?
  private var fullScreenTarget: Bool?
  private var inFullScreenTransition = false
  private var fullScreenObservers: [NSObjectProtocol] = []

  /// A full-screen transition ended: if a later request wants the other
  /// state, apply it now.
  private func settleFullScreen() {
    inFullScreenTransition = false
    let isFull = styleMask.contains(.fullScreen)
    guard let want = fullScreenTarget else { return }
    // Either way the request is spent: reached, or retried exactly once
    // (so a transition that fails can never loop), and the user's own
    // green-button toggle later is never reversed.
    fullScreenTarget = nil
    if want != isFull {
      toggleFullScreen(nil)
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register the Wi-Fi Information channel here, where the engine and its
    // binary messenger are unambiguously available. (Registering from
    // AppDelegate relied on a contentViewController cast that could be missed,
    // leaving the channel absent and the Dart side hanging.)
    self.wifiInfoChannel = WifiInfoChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )

    // SPIKE-HSD-01 — register the ARP-table channel (macOS-only MAC/vendor read
    // for the LAN Discovery debug screen). Same binary-messenger pattern as the
    // Wi-Fi channel so it is unambiguously available.
    self.arpTableChannel = ArpTableChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )

    // SPIKE-HSD-01 — register the in-house NWBrowser mDNS EventChannel. Same
    // binary-messenger pattern as the channels above so it is unambiguously
    // available. Drives the OS Bonjour daemon (NSBonjourServices in Info.plist,
    // no multicast entitlement). Replaces the removed GPL-3.0 bonsoir plugin.
    self.mdnsBrowseChannel = MdnsBrowseChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )

    // Batch 6 — register the Device/System info channel (uptime via
    // ProcessInfo.systemUptime). Same binary-messenger pattern as the channels
    // above so it is unambiguously available.
    self.systemInfoChannel = SystemInfoChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )

    // Nearby AP Scan — register the CoreWLAN neighbour-scan channel. Shares the
    // `com.wlanpros.toolbox/ap_scan` channel name and payload shape with the
    // Android implementation so one Dart model serves both. Same binary-
    // messenger pattern as the channels above so it is unambiguously available.
    self.apScanChannel = ApScanChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )

    // Wi-Fi Lab presenter mode: full screen for a projector. Dart side:
    // lib/widgets/presenter/presenter_window.dart. `setFullScreen` records the
    // wanted state and toggles only when the window differs, so a repeated
    // call never flips it back. A request that lands mid-animation is held
    // and applied when the transition ends, so a quick Esc after entering
    // still leaves full screen. It returns the state asked for, because the
    // transition animates and styleMask would still report the old state.
    self.collectionBehavior.insert(.fullScreenPrimary)
    let center = NotificationCenter.default
    for name in [NSWindow.willEnterFullScreenNotification,
                 NSWindow.willExitFullScreenNotification] {
      fullScreenObservers.append(center.addObserver(
        forName: name, object: self, queue: .main
      ) { [weak self] _ in self?.inFullScreenTransition = true })
    }
    for name in [NSWindow.didEnterFullScreenNotification,
                 NSWindow.didExitFullScreenNotification] {
      fullScreenObservers.append(center.addObserver(
        forName: name, object: self, queue: .main
      ) { [weak self] _ in self?.settleFullScreen() })
    }
    let presenter = FlutterMethodChannel(
      name: "com.wlanpros.toolbox/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    presenter.setMethodCallHandler { [weak self] call, result in
      guard let window = self else {
        result(false)
        return
      }
      let isFull = window.styleMask.contains(.fullScreen)
      switch call.method {
      case "isFullScreen":
        result(window.fullScreenTarget ?? isFull)
      case "setFullScreen":
        let want = (call.arguments as? Bool) ?? !isFull
        if window.inFullScreenTransition {
          window.fullScreenTarget = want
        } else if want != isFull {
          window.fullScreenTarget = want
          window.toggleFullScreen(nil)
        } else {
          window.fullScreenTarget = nil
        }
        result(want)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.presenterWindowChannel = presenter

    super.awakeFromNib()
  }
}
