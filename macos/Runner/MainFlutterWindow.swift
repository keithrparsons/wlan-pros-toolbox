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

    super.awakeFromNib()
  }
}
