import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Retained for the window lifetime so its MethodChannel handler stays live.
  private var wifiInfoChannel: WifiInfoChannel?

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

    super.awakeFromNib()
  }
}
