import Flutter
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
/// Earlier attempts used `NWBrowser` for discovery; on a SANDBOXED macOS app it
/// reached `.ready` but delivered ZERO browse results, so NWBrowser was removed
/// entirely in favor of the bonsoir-proven `NetServiceBrowser` + `NetService`
/// path. `searchForServices(ofType:inDomain:)` hands the browse to the OS daemon
/// and its delegate (`netServiceBrowser(_:didFind:moreComing:)`) yields a
/// `NetService` per instance; we then `resolve(withTimeout:)` each one and read
/// raw `sockaddr` addresses from `netServiceDidResolveAddress`. Both
/// `NetServiceBrowser` and `NetService` are API-deprecated but fully functional,
/// OS-daemon-based, and need NO multicast entitlement.
///
/// SINGLE-STREAM CONTRACT (2026-05-31 stream-lifecycle fix): a Flutter
/// `FlutterEventChannel` keyed by NAME supports exactly ONE active stream. The
/// Dart browse therefore opens this channel ONCE and passes the FULL LIST of
/// service types (`[String]`) as the `onListen` argument. This channel starts
/// ONE `BrowseSession` that runs one `NetServiceBrowser` PER type and tags every
/// emitted event with the `serviceType` it was found under, so the single Dart
/// stream is demultiplexed back to per-type listeners. `onCancel` stops that one
/// session exactly once and is idempotent (a redundant/late cancel is a benign
/// no-op, never a `FlutterError`). The previous design accepted a single type
/// per stream and the Dart side opened 16 concurrent streams on this one channel
/// name — that thrashed the framework's subscribe/cancel bookkeeping, tore the
/// browsers down before mDNS could hear an announcement, and produced a
/// "No active stream to cancel" storm. Fixed by one stream, one session, N
/// browsers, held for the full dwell window.
///
/// DOMAIN: bonsoir_darwin searches in `""` (the empty string), which the daemon
/// treats as the default registration domain (effectively `local.`). We match
/// that exactly — `searchForServices(ofType:inDomain: "")`.
///
/// DELEGATE ORDERING: each browser's delegate is set BEFORE `searchForServices`
/// is called, and the browser is scheduled on the main run loop first, so no
/// early `didFind` callback is lost.
///
/// RETENTION (the #1 NetService bug): every `NetServiceBrowser` is held in a
/// strong collection for the session's lifetime, and EVERY in-flight
/// `NetService` is held in a strong `Set` until it resolves or fails — a
/// `NetService` that is not retained is deallocated before its async resolve
/// completes and silently never fires its delegate. All torn down on `stop()` —
/// no leak.
///
/// EventChannel `com.wlanpros.toolbox/mdns_browse`. ONE stream for the whole
/// browse; the listen argument is the `[String]` list of service types. Native
/// emits one event per RESOLVED instance, tagged with its service type:
///   { "name": String, "hostAddresses": [String], "serviceType": String }
/// Only resolved instances with at least one address are emitted. IPv6 literals
/// are passed through; the Dart browse layer keeps only IPv4 (existing behavior).
///
/// HONESTY (GL-005 / GL-008): a browse that finds nothing emits nothing; a
/// permission/platform failure surfaces as a browser-not-search state that
/// simply stops the stream. Nothing is ever fabricated.
final class MdnsBrowseChannel: NSObject, FlutterStreamHandler {
  /// The exact event-channel name shared with the Dart side.
  static let channelName = "com.wlanpros.toolbox/mdns_browse"

  private let channel: FlutterEventChannel

  /// The ONE live browse session for the single active stream listener.
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
    // The single stream's argument is the FULL list of service types to browse.
    // Accept a list; tolerate a bare string for backward compatibility.
    let serviceTypes: [String]
    if let list = arguments as? [String] {
      serviceTypes = list.filter { !$0.isEmpty }
    } else if let one = arguments as? String, !one.isEmpty {
      serviceTypes = [one]
    } else {
      return FlutterError(
        code: "bad_args",
        message:
          "mDNS browse requires a [String] list of service types as the stream argument.",
        details: nil
      )
    }
    guard !serviceTypes.isEmpty else {
      return FlutterError(
        code: "bad_args",
        message: "mDNS browse requires at least one non-empty service type.",
        details: nil
      )
    }
    // Replace any prior session (a stream is 1:1 with a listener here). Stopping
    // a prior session is safe and idempotent.
    session?.stop()
    session = BrowseSession(serviceTypes: serviceTypes, sink: events)
    session?.start()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    // Idempotent: a cancel when there is no live session is a benign no-op, NOT
    // a FlutterError. `stop()` itself is idempotent (guards on `stopped`).
    session?.stop()
    session = nil
    return nil
  }
}

/// ONE browse session running a `NetServiceBrowser` PER service type, resolving
/// each found instance to its host addresses via `NetService` (sockaddr →
/// IPv4/IPv6) — the exact bonsoir_darwin path. Every emitted event is tagged
/// with the service type it was found under so the single Dart stream can
/// demultiplex back to per-type listeners.
///
/// THREADING: `NetServiceBrowser` and `NetService` both require a live run loop,
/// so everything — browser creation/scheduling/search, each NetService schedule
/// + resolve, all delegate callbacks, and teardown — runs on the MAIN run loop
/// (scheduled `forMode: .common`). The Flutter sink is therefore always invoked
/// on main. All mutable state is touched only on main.
private final class BrowseSession: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
  private let serviceTypes: [String]
  private let sink: FlutterEventSink

  /// One browser per service type, retained for the session's lifetime. Keyed by
  /// `ObjectIdentifier` so a delegate callback can recover the browser's type.
  private var browsers: [ObjectIdentifier: (browser: NetServiceBrowser, type: String)] = [:]
  /// In-flight resolving services, retained until they resolve or fail (main
  /// only). CRITICAL: a NetService that is not strongly held is deallocated
  /// before its async resolve completes and its delegate never fires. Maps each
  /// service to the type it was found under, so the emitted event is tagged.
  private var resolving: [ObjectIdentifier: (service: NetService, type: String)] = [:]
  /// De-dupes resolve attempts for the same instance, per type (main only).
  private var seen: Set<String> = []
  private var stopped = false

  /// When the dwell window began, for the elapsed-ms log on stop.
  private var startedAt: Date?

  // SPIKE-HSD-01 diagnostic counters, per service type (logged only on stop,
  // gated by isDebug). Keith's on-device run prints these so a future empty
  // result is attributable to browse-vs-resolve.
  private var foundCount: [String: Int] = [:]
  private var resolvedCount: [String: Int] = [:]
  private var failedResolveCount: [String: Int] = [:]

  /// Debug builds only: mirror Dart's kDebugMode with an assert side-effect so
  /// the logging is independent of build flags.
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

  init(serviceTypes: [String], sink: @escaping FlutterEventSink) {
    self.serviceTypes = serviceTypes
    self.sink = sink
    super.init()
  }

  func start() {
    // NetServiceBrowser is run-loop bound; drive it from main so its delegate and
    // every NetService resolve share one live run loop (what bonsoir effectively
    // does). Set the delegate and schedule BEFORE searching so no early didFind
    // is lost. ONE browser per service type, all under this single session.
    DispatchQueue.main.async { [weak self] in
      guard let self = self, !self.stopped else { return }
      self.startedAt = Date()
      for type in self.serviceTypes {
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.schedule(in: .main, forMode: .common)
        self.browsers[ObjectIdentifier(browser)] = (browser, type)
        // Domain "" = the daemon's default registration domain (== local.),
        // exactly what bonsoir_darwin searches.
        browser.searchForServices(ofType: type, inDomain: "")
        self.log("browser searching for \(type)")
      }
    }
  }

  /// Recovers the service type a given browser was created for.
  private func type(for browser: NetServiceBrowser) -> String? {
    browsers[ObjectIdentifier(browser)]?.type
  }

  // MARK: - NetServiceBrowserDelegate (main run loop)

  func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
    log("willSearch \(type(for: browser) ?? "?")")
  }

  func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didNotSearch errorDict: [String: NSNumber]
  ) {
    // Non-fatal: this type produced no search. The Dart browse layer treats an
    // empty stream as "no mDNS results".
    log("didNotSearch \(type(for: browser) ?? "?"): \(errorDict)")
  }

  func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didFind service: NetService,
    moreComing: Bool
  ) {
    guard !stopped else { return }
    let svcType = type(for: browser) ?? service.type
    // Log every didFind the instant it arrives so a found>0 / resolved=0 outcome
    // is distinguishable from a found=0 outcome.
    log("didFind \(service.name) [\(svcType)] moreComing=\(moreComing)")

    // Bonjour browse results can repeat; resolve each instance once.
    let key = "\(service.name).\(service.type)\(service.domain)"
    if seen.contains(key) { return }
    seen.insert(key)
    foundCount[svcType, default: 0] += 1

    // Retain (the #1 NetService bug is the service being deallocated before it
    // resolves), set the delegate, schedule on the same main run loop, resolve.
    service.delegate = self
    resolving[ObjectIdentifier(service)] = (service, svcType)
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
    if resolving[ObjectIdentifier(service)] != nil {
      finishResolving(service)
    }
  }

  // MARK: - NetServiceDelegate (main run loop)

  func netServiceDidResolveAddress(_ service: NetService) {
    guard !stopped else { return }
    let svcType = resolving[ObjectIdentifier(service)]?.type ?? service.type
    let addresses = Self.ipStrings(from: service.addresses ?? [])
    finishResolving(service)
    guard !addresses.isEmpty else {
      log("resolved \(service.name) [\(svcType)] but NO usable address")
      return
    }
    resolvedCount[svcType, default: 0] += 1
    log("resolved \(service.name) [\(svcType)] -> \(addresses)")
    emit(serviceType: svcType, name: service.name, addresses: addresses)
  }

  func netService(_ service: NetService, didNotResolve errorDict: [String: NSNumber]) {
    // Non-fatal: drop this instance, keep browsing/resolving the rest.
    let svcType = resolving[ObjectIdentifier(service)]?.type ?? service.type
    failedResolveCount[svcType, default: 0] += 1
    log("didNotResolve \(service.name) [\(svcType)]: \(errorDict)")
    finishResolving(service)
  }

  private func finishResolving(_ service: NetService) {
    service.stop()
    service.delegate = nil
    resolving.removeValue(forKey: ObjectIdentifier(service))
  }

  /// Emit one resolved instance up the Flutter sink (already on main), tagged
  /// with its service type so the single Dart stream demultiplexes correctly.
  private func emit(serviceType: String, name: String, addresses: [String]) {
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
    // main-run-loop bound). Log the dwell window + per-type browse/resolve
    // summaries first. Idempotent: a second stop() is a no-op (guards on
    // `stopped`), so a redundant cancel never double-tears-down or throws.
    DispatchQueue.main.async { [weak self] in
      guard let self = self, !self.stopped else { return }

      let elapsedMs: Int
      if let s = self.startedAt {
        elapsedMs = Int(Date().timeIntervalSince(s) * 1000.0)
      } else {
        elapsedMs = 0
      }
      self.log("STOP browse: dwell=\(elapsedMs)ms types=\(self.serviceTypes.count)")
      for type in self.serviceTypes {
        self.log(
          "STOP \(type): found=\(self.foundCount[type] ?? 0) "
            + "resolved=\(self.resolvedCount[type] ?? 0) "
            + "failedResolve=\(self.failedResolveCount[type] ?? 0)"
        )
      }

      self.stopped = true

      for (browser, _) in self.browsers.values {
        browser.stop()
        browser.delegate = nil
        browser.remove(from: .main, forMode: .common)
      }
      self.browsers.removeAll()

      for (service, _) in self.resolving.values {
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
