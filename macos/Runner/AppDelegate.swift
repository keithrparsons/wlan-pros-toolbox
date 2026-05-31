import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Retained for the app lifetime so the Wi-Fi method channel stays
  /// registered and its CLLocationManager delegate can fire.
  var wifiInfoChannel: WifiInfoChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    // Register the Wi-Fi info channel on the main Flutter engine. If the view
    // controller cast fails the app still launches; the channel is simply
    // absent and the Dart side surfaces a channel error.
    if let controller = mainFlutterWindow?.contentViewController
      as? FlutterViewController {
      wifiInfoChannel = WifiInfoChannel(
        messenger: controller.engine.binaryMessenger
      )
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ sender: NSApplication) -> Bool {
    return true
  }
}
