import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // The Wi-Fi Information channel is registered in
  // MainFlutterWindow.awakeFromNib, where the engine messenger is guaranteed
  // available. Registering here relied on a contentViewController cast that
  // could run before the controller was set, leaving the channel unregistered
  // and the Dart side hanging on a never-answered call.

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ sender: NSApplication) -> Bool {
    return true
  }
}
