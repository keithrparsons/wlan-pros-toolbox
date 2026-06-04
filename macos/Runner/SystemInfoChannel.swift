import Cocoa
import FlutterMacOS

/// Device/System info channel (Batch 6) — the native side of the Dart
/// `SystemUptimeBridge`.
///
/// device_info_plus already provides the model and total memory on macOS, so the
/// ONLY value this channel supplies is uptime, which no package exposes. It reads
/// `ProcessInfo.processInfo.systemUptime` — seconds since the device last booted.
/// Unprivileged, no entitlement, no subprocess (GL-008): a plain Foundation
/// property read, the same in-process idiom as ArpTableChannel's sysctl read.
///
/// Registers a FlutterMethodChannel named `com.wlanpros.toolbox/system_info`.
/// Method: `systemUptime` → Double (seconds since boot).
final class SystemInfoChannel: NSObject {
  /// The exact method channel name shared with the Dart side.
  static let channelName = "com.wlanpros.toolbox/system_info"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: SystemInfoChannel.channelName,
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "systemUptime":
        // Foundation's seconds-since-boot. A finite, non-negative Double; the
        // Dart side null-checks for non-finite/negative defensively.
        result(ProcessInfo.processInfo.systemUptime)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
