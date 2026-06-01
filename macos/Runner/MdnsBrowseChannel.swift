import Cocoa
import FlutterMacOS
import Network

/// SPIKE-HSD-01 — in-house mDNS / Bonjour browse over Apple's Network framework
/// (`NWBrowser`), replacing the GPL-3.0 `bonsoir` package (PRD Decision Log 13).
///
/// WHY IN-HOUSE: bonsoir's GPL-3.0 license is incompatible with a closed-source
/// commercial App Store app. This channel reproduces bonsoir's
/// found → resolve → resolved → host-addresses flow using `NWBrowser` per
/// service type, which drives the OS Bonjour daemon — so it works with only
/// `NSBonjourServices` declared in Info.plist and NO
/// `com.apple.developer.networking.multicast` entitlement (the whole reason
/// bonsoir was chosen over pure-Dart multicast_dns). Entitlements are untouched.
///
/// WHY NWBrowser (NOT NetService/NetServiceBrowser): NWBrowser is the modern,
/// non-deprecated discovery API. It yields `NWBrowser.Result`s whose endpoint is
/// a `.service`; opening a short-lived `NWConnection` to that endpoint lets the
/// OS resolver populate `currentPath.remoteEndpoint`, from which we read the
/// resolved IPv4 host:port reliably. NetServiceBrowser is deprecated and its
/// address callbacks are clumsier.
///
/// EventChannel `com.wlanpros.toolbox/mdns_browse`. One stream per browsed
/// service type: Dart opens the stream with the service type as the listen
/// argument; native browses that single type and emits one event per RESOLVED
/// instance:
///   { "name": String, "hostAddresses": [String], "serviceType": String }
/// Only resolved instances with at least one address are emitted — mirroring the
/// Dart `MdnsDiscoveryEvent` contract (resolved-only). IPv6 literals are passed
/// through; the Dart browse layer keeps only IPv4 (existing behavior).
///
/// TEARDOWN: each stream owns its NWBrowser plus the set of in-flight resolving
/// NWConnections. `onCancel` cancels the browser and every connection so no
/// native resource leaks (the dispose contract the spike requires).
///
/// HONESTY (GL-005 / GL-008): a browse that finds nothing emits nothing; a
/// permission/platform failure surfaces as a browser-failed state that simply
/// stops the stream. Nothing is ever fabricated.
final class MdnsBrowseChannel: NSObject, FlutterStreamHandler {
  /// The exact event-channel name shared with the Dart side.
  static let channelName = "com.wlanpros.toolbox/mdns_browse"

  private let channel: FlutterEventChannel

  /// One live browse session per active stream listener.
  private var session: BrowseSession?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterEventChannel(
      name: MdnsBrowseChannel.channelName,
      binaryMessenger: messenger
    )
    super.init()
    channel.setStreamHandler(self)
  }

  // MARK: - FlutterStreamHandler

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard let serviceType = arguments as? String, !serviceType.isEmpty else {
      return FlutterError(
        code: "bad_args",
        message: "mDNS browse requires a service type string as the stream argument.",
        details: nil
      )
    }
    // Replace any prior session (a stream is 1:1 with a listener here).
    session?.stop()
    session = BrowseSession(serviceType: serviceType, sink: events)
    session?.start()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    session?.stop()
    session = nil
    return nil
  }
}

/// One NWBrowser browse for a single service type, with resolution of each
/// found instance to its host addresses via a short-lived NWConnection.
private final class BrowseSession {
  private let serviceType: String
  private let sink: FlutterEventSink
  private let queue = DispatchQueue(label: "com.wlanpros.toolbox.mdns")

  private var browser: NWBrowser?
  /// In-flight resolving connections, retained until they resolve or fail.
  private var connections: [ObjectIdentifier: NWConnection] = [:]
  private var stopped = false

  init(serviceType: String, sink: @escaping FlutterEventSink) {
    self.serviceType = serviceType
    self.sink = sink
  }

  func start() {
    let params = NWParameters()
    params.includePeerToPeer = false
    let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
    let browser = NWBrowser(for: descriptor, using: params)
    self.browser = browser

    browser.browseResultsChangedHandler = { [weak self] results, _ in
      guard let self = self else { return }
      for result in results {
        // We only resolve `.service` endpoints; that is what Bonjour yields.
        if case .service = result.endpoint {
          self.resolve(result.endpoint)
        }
      }
    }

    browser.stateUpdateHandler = { [weak self] state in
      // A failed/cancelled browser just stops producing events. Non-fatal: the
      // Dart browse layer treats an empty stream as "no mDNS results".
      switch state {
      case .failed, .cancelled:
        self?.queue.async { self?.cleanupBrowser() }
      default:
        break
      }
    }

    browser.start(queue: queue)
  }

  /// Opens a short-lived connection to a discovered service endpoint so the OS
  /// resolver fills in the concrete host address(es), then emits one event.
  private func resolve(_ endpoint: NWEndpoint) {
    let connection = NWConnection(to: endpoint, using: .tcp)
    let id = ObjectIdentifier(connection)
    queue.async { [weak self] in
      guard let self = self, !self.stopped else {
        connection.cancel()
        return
      }
      self.connections[id] = connection
    }

    connection.stateUpdateHandler = { [weak self] state in
      guard let self = self else { return }
      switch state {
      case .ready:
        // The resolved remote endpoint carries the concrete IP:port.
        if let path = connection.currentPath,
          let remote = path.remoteEndpoint {
          self.emit(for: endpoint, resolvedFrom: remote)
        }
        self.finish(id)
      case .failed, .cancelled:
        self.finish(id)
      default:
        break
      }
    }
    connection.start(queue: queue)
  }

  /// Extracts the IPv4/IPv6 literal from the resolved endpoint and emits the
  /// normalized event up the Flutter sink.
  private func emit(for service: NWEndpoint, resolvedFrom resolved: NWEndpoint) {
    guard !stopped else { return }
    var addresses: [String] = []
    if case let .hostPort(host, _) = resolved {
      switch host {
      case let .ipv4(addr):
        addresses.append(Self.ipv4String(addr))
      case let .ipv6(addr):
        if let v4 = addr.asIPv4 {
          addresses.append(Self.ipv4String(v4))
        } else {
          addresses.append(Self.ipv6String(addr))
        }
      case let .name(name, _):
        addresses.append(name)
      @unknown default:
        break
      }
    }
    guard !addresses.isEmpty else { return }

    var instanceName = ""
    if case let .service(name, _, _, _) = service {
      instanceName = name
    }

    let payload: [String: Any] = [
      "serviceType": serviceType,
      "name": instanceName,
      "hostAddresses": addresses,
    ]
    DispatchQueue.main.async { [weak self] in
      guard let self = self, !self.stopped else { return }
      self.sink(payload)
    }
  }

  private func finish(_ id: ObjectIdentifier) {
    queue.async { [weak self] in
      guard let self = self else { return }
      if let c = self.connections.removeValue(forKey: id) {
        c.cancel()
      }
    }
  }

  private func cleanupBrowser() {
    browser?.cancel()
    browser = nil
  }

  func stop() {
    queue.async { [weak self] in
      guard let self = self else { return }
      self.stopped = true
      self.cleanupBrowser()
      for (_, c) in self.connections {
        c.cancel()
      }
      self.connections.removeAll()
    }
  }

  // MARK: - Address formatting

  static func ipv4String(_ addr: IPv4Address) -> String {
    let b = addr.rawValue
    return b.map { String($0) }.joined(separator: ".")
  }

  static func ipv6String(_ addr: IPv6Address) -> String {
    return "\(addr)"
  }
}
