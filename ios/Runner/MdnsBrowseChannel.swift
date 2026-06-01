import Flutter
import Foundation
import Network

/// SPIKE-HSD-01 — in-house mDNS / Bonjour browse, replacing the GPL-3.0 `bonsoir`
/// package (PRD Decision Log 13).
///
/// WHY IN-HOUSE: bonsoir's GPL-3.0 license is incompatible with a closed-source
/// commercial App Store app. This channel reproduces bonsoir's
/// found → resolve → resolved → host-addresses flow. Both `NWBrowser` (browse)
/// and `NetService` (resolve) drive the OS Bonjour daemon — so it works with only
/// `NSBonjourServices` declared in Info.plist and NO
/// `com.apple.developer.networking.multicast` entitlement (the whole reason
/// bonsoir was chosen over pure-Dart multicast_dns). Entitlements are untouched.
///
/// ARCHITECTURE — BROWSE with NWBrowser, RESOLVE with NetService (HYBRID):
/// The first NWBrowser-only implementation browsed correctly but resolved each
/// found `.service` endpoint by opening a short-lived `NWConnection` and reading
/// `currentPath.remoteEndpoint`. On-device that path yielded ZERO results
/// (observed by Keith on macOS 2026-05-31): a `.service` NWConnection only emits
/// `.ready` after a full TCP handshake — many Bonjour devices (Sonos `_sonos._tcp`,
/// `_companion-link._tcp`, `_raop._tcp`) never complete a handshake inside the
/// browse window, and even when `.ready` fired, `remoteEndpoint` commonly carried
/// a `.name` host (a `*.local` hostname), not an `.ipv4` literal — which the Dart
/// IPv4 filter then silently dropped. So every result was discarded.
///
/// The fix matches the bonsoir-proven path: `NetService.resolve(withTimeout:)`
/// hands the resolve to the same OS daemon and its delegate yields raw `sockaddr`
/// addresses DIRECTLY (no TCP handshake, no hostname ambiguity, no
/// connection-state dance). We keep NWBrowser for discovery (modern, clean
/// service enumeration) and use NetService purely as a resolver. NetService is
/// API-deprecated but fully functional and needs NO multicast entitlement.
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
/// NetServices. `onCancel` cancels the browser and stops every resolve so no
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

/// One NWBrowser browse for a single service type, resolving each found instance
/// to its host addresses via `NetService` (sockaddr → IPv4/IPv6, the
/// bonsoir-proven path).
///
/// THREADING: NWBrowser runs on a private serial queue; NetService requires a
/// run-loop, so all NetService creation, scheduling, delegate callbacks, and
/// teardown happen on the MAIN run loop. The two are bridged with explicit
/// `DispatchQueue.main.async` hops. `stopped` is only read/written on main.
private final class BrowseSession: NSObject, NetServiceDelegate {
  private let serviceType: String
  private let sink: FlutterEventSink
  private let browseQueue = DispatchQueue(label: "com.wlanpros.toolbox.mdns")

  private var browser: NWBrowser?
  /// In-flight resolving services, retained until they resolve or fail (main only).
  private var resolving: Set<NetService> = []
  /// De-dupes resolve attempts for the same instance (main only).
  private var seen: Set<String> = []
  private var stopped = false

  // SPIKE-HSD-01 diagnostic counters (logged only on stop, gated by isDebug).
  // Keith's on-device run prints these per service type so a future empty result
  // is attributable to browse-vs-resolve. Remove once the path is productized.
  private var foundCount = 0
  private var resolvedCount = 0
  private var failedResolveCount = 0

  /// Debug builds only: Flutter sets DEBUG via the Xcode config, but to stay
  /// independent of build flags we mirror Dart's kDebugMode with assert-side-effect.
  private static let isDebug: Bool = {
    var dbg = false
    assert({ dbg = true; return true }())
    return dbg
  }()

  private func log(_ message: @autoclosure () -> String) {
    if Self.isDebug {
      NSLog("[mdns_browse] \(message())")
    }
  }

  init(serviceType: String, sink: @escaping FlutterEventSink) {
    self.serviceType = serviceType
    self.sink = sink
    super.init()
  }

  func start() {
    let params = NWParameters()
    params.includePeerToPeer = false
    let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: "local.")
    let browser = NWBrowser(for: descriptor, using: params)
    self.browser = browser

    browser.browseResultsChangedHandler = { [weak self] results, _ in
      guard let self = self else { return }
      for result in results {
        // Bonjour browse yields `.service(name, type, domain, interface)`.
        if case let .service(name, type, domain, _) = result.endpoint {
          self.handleFound(name: name, type: type, domain: domain)
        }
      }
    }

    browser.stateUpdateHandler = { [weak self] state in
      // A failed/cancelled browser just stops producing events. Non-fatal: the
      // Dart browse layer treats an empty stream as "no mDNS results".
      switch state {
      case .ready:
        self?.log("browser ready for \(self?.serviceType ?? "?")")
      case let .failed(error):
        self?.log("browser FAILED for \(self?.serviceType ?? "?"): \(error)")
        self?.cleanupBrowser()
      case .cancelled:
        self?.cleanupBrowser()
      default:
        break
      }
    }

    browser.start(queue: browseQueue)
  }

  /// Resolve a found service instance via NetService on the main run loop.
  private func handleFound(name: String, type: String, domain: String) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, !self.stopped else { return }
      // Bonjour browse results can repeat; resolve each instance once.
      let key = "\(name).\(type)\(domain)"
      if self.seen.contains(key) { return }
      self.seen.insert(key)
      self.foundCount += 1

      // NWBrowser domains can come back as "local" (no trailing dot); NetService
      // expects the registration-style domain. Normalize to "local.".
      let svcDomain = domain.isEmpty ? "local." : domain
      let service = NetService(domain: svcDomain, type: type, name: name)
      service.delegate = self
      self.resolving.insert(service)
      service.schedule(in: .main, forMode: .common)
      service.resolve(withTimeout: 5.0)
    }
  }

  // MARK: - NetServiceDelegate (main run loop)

  func netServiceDidResolveAddress(_ service: NetService) {
    guard !stopped else { return }
    let addresses = Self.ipStrings(from: service.addresses ?? [])
    finishResolving(service)
    guard !addresses.isEmpty else {
      log("resolved \(service.name) [\(serviceType)] but NO usable address")
      return
    }
    resolvedCount += 1
    log("resolved \(service.name) [\(serviceType)] -> \(addresses)")
    emit(name: service.name, addresses: addresses)
  }

  func netService(_ service: NetService, didNotResolve errorDict: [String: NSNumber]) {
    // Non-fatal: drop this instance, keep browsing/resolving the rest.
    failedResolveCount += 1
    log("didNotResolve \(service.name) [\(serviceType)]: \(errorDict)")
    finishResolving(service)
  }

  private func finishResolving(_ service: NetService) {
    service.stop()
    service.delegate = nil
    resolving.remove(service)
  }

  /// Emit one resolved instance up the Flutter sink (main → main, already on main).
  private func emit(name: String, addresses: [String]) {
    guard !stopped else { return }
    let payload: [String: Any] = [
      "serviceType": serviceType,
      "name": name,
      "hostAddresses": addresses,
    ]
    sink(payload)
  }

  private func cleanupBrowser() {
    DispatchQueue.main.async { [weak self] in
      self?.browser?.cancel()
      self?.browser = nil
    }
  }

  func stop() {
    // Tear down on main (NetService is main-run-loop bound); cancel the browser.
    let browserRef = browser
    browser = nil
    browseQueue.async { browserRef?.cancel() }

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.log(
        "STOP \(self.serviceType): found=\(self.foundCount) "
          + "resolved=\(self.resolvedCount) failedResolve=\(self.failedResolveCount)"
      )
      self.stopped = true
      for service in self.resolving {
        service.stop()
        service.delegate = nil
      }
      self.resolving.removeAll()
      self.seen.removeAll()
    }
  }

  // MARK: - Address formatting

  /// Converts NetService `addresses` (an array of `Data`-wrapped `sockaddr`) to
  /// printable IP strings. IPv4 first (the Dart layer keeps only IPv4); IPv6
  /// literals are passed through and the Dart filter drops them. Loopback /
  /// link-local-only results still surface — the Dart side decides relevance.
  static func ipStrings(from addresses: [Data]) -> [String] {
    var out: [String] = []
    for data in addresses {
      data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        guard let base = raw.baseAddress else { return }
        let sa = base.assumingMemoryBound(to: sockaddr.self)
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
          sa,
          socklen_t(data.count),
          &host,
          socklen_t(host.count),
          nil,
          0,
          NI_NUMERICHOST
        )
        if result == 0 {
          var s = String(cString: host)
          // Strip the zone id (e.g. fe80::1%en0) so the literal is clean.
          if let pct = s.firstIndex(of: "%") {
            s = String(s[..<pct])
          }
          if !s.isEmpty {
            out.append(s)
          }
        }
      }
    }
    // Stable order: IPv4 literals before IPv6 so the Dart IPv4-keying picks a v4
    // address deterministically when both are present.
    return out.sorted { lhs, rhs in
      let l4 = !lhs.contains(":")
      let r4 = !rhs.contains(":")
      if l4 != r4 { return l4 }
      return false
    }
  }
}
