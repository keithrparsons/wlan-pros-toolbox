import Cocoa
import FlutterMacOS
import Foundation

/// SPIKE-HSD-01 — in-house mDNS / Bonjour browse, replacing the GPL-3.0 `bonsoir`
/// package (PRD Decision Log 13).
///
/// WHY IN-HOUSE: bonsoir's GPL-3.0 license is incompatible with a closed-source
/// commercial App Store app. This channel reproduces bonsoir's
/// found → resolve → resolved → host-addresses flow using the EXACT same Apple
/// API stack `bonsoir_darwin` uses: `NetServiceBrowser` to BROWSE and `NetService`
/// to RESOLVE. Both drive the OS Bonjour daemon — so it works with only
/// `NSBonjourServices` declared in Info.plist and NO
/// `com.apple.developer.networking.multicast` entitlement (the whole reason
/// bonsoir was chosen over pure-Dart multicast_dns). Entitlements are untouched.
///
/// ARCHITECTURE — NetServiceBrowser browse, NetService resolve (the bonsoir path):
/// Two earlier attempts used `NWBrowser` for discovery. On a SANDBOXED macOS app,
/// on-device testing (Keith, 2026-05-31) showed `NWBrowser` reaching `.ready` for
/// every service type — including `_sonos._tcp` — but delivering ZERO browse
/// results: `browseResultsChangedHandler` never fired, so nothing was ever found,
/// let alone resolved. The TCP connect-scan + ARP read worked, so Local Network
/// access was granted; the failure was specific to `NWBrowser`'s browse not
/// surfacing results in this sandboxed context. We are done patching NWBrowser.
///
/// This rewrite removes `NWBrowser` ENTIRELY and uses the legacy `NetServiceBrowser`
/// for discovery — the path we KNOW discovered Sonos + Apple devices under bonsoir
/// (iOS Gate 1 passed). `searchForServices(ofType:inDomain:)` hands the browse to
/// the OS daemon and its delegate (`netServiceBrowser(_:didFind:moreComing:)`)
/// yields a `NetService` per instance; we then `resolve(withTimeout:)` each one and
/// read raw `sockaddr` addresses from `netServiceDidResolveAddress`. Both
/// `NetServiceBrowser` and `NetService` are API-deprecated but fully functional,
/// OS-daemon-based, and need NO multicast entitlement.
///
/// DOMAIN: bonsoir_darwin searches in `""` (the empty string), which the daemon
/// treats as the default registration domain (effectively `local.`). We match that
/// exactly — `searchForServices(ofType: serviceType, inDomain: "")` — rather than
/// passing `"local."`, to mirror the proven behavior.
///
/// DELEGATE ORDERING: the browser delegate is set BEFORE `searchForServices` is
/// called, and the browser is scheduled on the main run loop first, so no early
/// `didFind` callback is lost.
///
/// RETENTION (the #1 NetService bug): `NetServiceBrowser` is held in a strong
/// property for the session's lifetime, and EVERY in-flight `NetService` is held in
/// a strong `Set` until it resolves or fails — a `NetService` that is not retained
/// is deallocated before its async resolve completes and silently never fires its
/// delegate. All of them are torn down on `stop()` / dispose — no leak.
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
/// TEARDOWN: each stream owns its NetServiceBrowser plus the set of in-flight
/// resolving NetServices. `onCancel` stops the browser and every resolve so no
/// native resource leaks (the dispose contract the spike requires).
///
/// HONESTY (GL-005 / GL-008): a browse that finds nothing emits nothing; a
/// permission/platform failure surfaces as a browser-not-search state that simply
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

/// One `NetServiceBrowser` browse for a single service type, resolving each found
/// instance to its host addresses via `NetService` (sockaddr → IPv4/IPv6) — the
/// exact bonsoir_darwin path.
///
/// THREADING: `NetServiceBrowser` and `NetService` both require a live run loop,
/// so everything — browser creation/scheduling/search, each NetService schedule +
/// resolve, all delegate callbacks, and teardown — runs on the MAIN run loop
/// (scheduled `forMode: .common`). The Flutter sink is therefore always invoked on
/// main. `stopped`/`resolving`/`seen` are touched only on main.
private final class BrowseSession: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
  private let serviceType: String
  private let sink: FlutterEventSink

  /// The browser, retained for the session's lifetime (main only).
  private var browser: NetServiceBrowser?
  /// In-flight resolving services, retained until they resolve or fail (main only).
  /// CRITICAL: a NetService that is not strongly held is deallocated before its
  /// async resolve completes and its delegate never fires.
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
    // NetServiceBrowser is run-loop bound; drive it from main so its delegate and
    // every NetService resolve share one live run loop (what bonsoir effectively
    // does). Set the delegate and schedule BEFORE searching so no early didFind is
    // lost.
    DispatchQueue.main.async { [weak self] in
      guard let self = self, !self.stopped else { return }
      let browser = NetServiceBrowser()
      browser.delegate = self
      browser.schedule(in: .main, forMode: .common)
      self.browser = browser
      // Domain "" = the daemon's default registration domain (== local.), exactly
      // what bonsoir_darwin searches. Do NOT pass "local." here — match the proven
      // behavior.
      browser.searchForServices(ofType: self.serviceType, inDomain: "")
      self.log("browser searching for \(self.serviceType)")
    }
  }

  // MARK: - NetServiceBrowserDelegate (main run loop)

  func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
    log("willSearch \(serviceType)")
  }

  func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didNotSearch errorDict: [String: NSNumber]
  ) {
    // Non-fatal: this type produced no search. The Dart browse layer treats an
    // empty stream as "no mDNS results".
    log("didNotSearch \(serviceType): \(errorDict)")
  }

  func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didFind service: NetService,
    moreComing: Bool
  ) {
    guard !stopped else { return }
    // Log every didFind the instant it arrives so a found>0 / resolved=0 outcome
    // is distinguishable from a found=0 outcome.
    log("didFind \(service.name) [\(serviceType)] moreComing=\(moreComing)")

    // Bonjour browse results can repeat; resolve each instance once.
    let key = "\(service.name).\(service.type)\(service.domain)"
    if seen.contains(key) { return }
    seen.insert(key)
    foundCount += 1

    // Retain (the #1 NetService bug is the service being deallocated before it
    // resolves), set the delegate, schedule on the same main run loop, resolve.
    service.delegate = self
    resolving.insert(service)
    service.schedule(in: .main, forMode: .common)
    service.resolve(withTimeout: 5.0)
  }

  func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didRemove service: NetService,
    moreComing: Bool
  ) {
    // We only enrich on presence; a removed service is dropped silently. Stop any
    // in-flight resolve for it so it does not leak.
    if resolving.contains(service) {
      finishResolving(service)
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

  /// Emit one resolved instance up the Flutter sink (already on main).
  private func emit(name: String, addresses: [String]) {
    guard !stopped else { return }
    let payload: [String: Any] = [
      "serviceType": serviceType,
      "name": name,
      "hostAddresses": addresses,
    ]
    sink(payload)
  }

  func stop() {
    // Tear down everything on main (NetServiceBrowser + NetService are
    // main-run-loop bound). Log the per-type browse/resolve summary first.
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.log(
        "STOP \(self.serviceType): found=\(self.foundCount) "
          + "resolved=\(self.resolvedCount) failedResolve=\(self.failedResolveCount)"
      )
      self.stopped = true

      if let browser = self.browser {
        browser.stop()
        browser.delegate = nil
        browser.remove(from: .main, forMode: .common)
      }
      self.browser = nil

      for service in self.resolving {
        service.stop()
        service.delegate = nil
        service.remove(from: .main, forMode: .common)
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
