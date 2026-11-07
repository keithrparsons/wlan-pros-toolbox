import Flutter
import UIKit

/// iPhone Duo hinge channel (Keith, 2026-11-07, approach C): the native side
/// of the Dart `foldState` (lib/services/device/fold_state.dart).
///
/// Flutter does not report the Duo's fold on iOS (`MediaQuery.displayFeatures`
/// is filled only on Android; flutter/flutter#192515 is open), so this reads
/// Apple's iOS 27.1 APIs directly:
///   * `UIHingeInteraction` for the hinge status and angle;
///   * `UIView.reservedRegions(kind: .division)` for where the fold crosses
///     the app, in the Flutter view's own points (= Flutter logical pixels).
///
/// EventChannel `com.wlanpros.toolbox/hinge`. Each event is
/// `{status: String, angle: Double, folds: [[x, y, width, height]]}`, sent on
/// listen, on every hinge update and whenever the view lays out (fold, unfold,
/// rotation, Split View), and only when it differs from the last one sent.
/// Before iOS 27.1, or on a device without a hinge, it sends nothing and the
/// app keeps its plain layout.
final class HingeChannel: NSObject, FlutterStreamHandler {
  static let channelName = "com.wlanpros.toolbox/hinge"

  private let channel: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var probe: UIView?
  private var hinge: (status: String, angle: Double) = ("unknown", 0)
  private var lastSent: [String: Any]?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterEventChannel(name: HingeChannel.channelName, binaryMessenger: messenger)
    super.init()
    channel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    guard #available(iOS 27.1, *), let host = Self.flutterView() else { return nil }
    let probe = LayoutProbeView(frame: host.bounds) { [weak self] in self?.send() }
    probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    probe.isUserInteractionEnabled = false
    probe.addInteraction(
      UIHingeInteraction { [weak self] _, update in
        guard let self, let h = update.hinge else { return }
        self.hinge = (Self.name(h.status), Double(h.angle))
        self.send()
      })
    host.addSubview(probe)
    self.probe = probe
    send()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    probe?.removeFromSuperview()
    probe = nil
    sink = nil
    lastSent = nil
    return nil
  }

  private func send() {
    guard #available(iOS 27.1, *), let sink, let view = probe?.superview else { return }
    let folds: [[Double]] = view.reservedRegions(kind: .division)
      .filter { $0.isActive }
      .map { r in
        [Double(r.frame.minX), Double(r.frame.minY), Double(r.frame.width), Double(r.frame.height)]
      }
    let event: [String: Any] = ["status": hinge.status, "angle": hinge.angle, "folds": folds]
    if let last = lastSent, NSDictionary(dictionary: last).isEqual(to: event) { return }
    lastSent = event
    sink(event)
  }

  @available(iOS 27.1, *)
  private static func name(_ status: UIHinge.Status) -> String {
    switch status {
    case .closed: return "closed"
    case .partiallyOpen: return "partiallyOpen"
    case .fullyOpen: return "fullyOpen"
    default: return "unknown"
    }
  }

  /// The Flutter view of the app's (single) window scene.
  private static func flutterView() -> UIView? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    return (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController?.view
  }
}

/// An invisible full-size subview whose only job is to report layout passes,
/// so a fold, unfold or rotation re-reads the reserved regions.
private final class LayoutProbeView: UIView {
  private let onLayout: () -> Void

  init(frame: CGRect, onLayout: @escaping () -> Void) {
    self.onLayout = onLayout
    super.init(frame: frame)
  }

  required init?(coder: NSCoder) { nil }

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout()
  }
}
