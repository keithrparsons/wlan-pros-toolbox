import Cocoa
import FlutterMacOS

/// SPIKE-HSD-01 — macOS ARP-table read for the LAN Discovery spike (THROWAWAY).
///
/// Answers the Gate 2 question: can a SANDBOXED macOS build read the IPv4
/// ARP cache (IP → link-layer MAC) WITHOUT spawning a subprocess? We do NOT
/// shell out to `arp -a` (the App Sandbox kills subprocess spawning — the exact
/// trap that blocked System Traceroute). Instead we read the kernel's routing
/// table directly via `sysctl(CTL_NET, AF_ROUTE, 0, AF_INET, NET_RT_FLAGS,
/// RTF_LLINFO)` and parse the `sockaddr_dl` link-layer addresses out of each
/// ARP entry into an IP → MAC map. This is an in-process kernel info read, not
/// a privileged operation and not a subprocess — the whole point of the gate is
/// to learn whether the sandbox permits it.
///
/// HONESTY (GL-005 / GL-008): the channel never fabricates a MAC. It returns a
/// structured result: `available` (did the sysctl succeed?), `entries`
/// (IP → MAC for what was actually in the cache), and `error` (a short reason
/// when sysctl failed — e.g. EPERM under sandbox). A sandbox block surfaces as
/// `available: false` with an error string so the debug screen can show
/// "ARP read unavailable (sandbox-blocked)" rather than silently showing no
/// MACs.
///
/// Registers a FlutterMethodChannel named `com.wlanpros.toolbox/arp_table`.
/// Method: `readArpTable` → a dictionary:
///   {
///     "available": Bool,
///     "entries": [ { "ip": "10.0.10.5", "mac": "b8:27:eb:01:23:45" }, ... ],
///     "error": String?            // non-nil only when available == false
///   }
final class ArpTableChannel: NSObject {
  /// The exact method channel name shared with the Dart side.
  static let channelName = "com.wlanpros.toolbox/arp_table"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: ArpTableChannel.channelName,
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  // MARK: - Method dispatch

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "readArpTable":
      result(readArpTable())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - ARP read

  /// Reads the IPv4 ARP cache via sysctl and returns a structured payload.
  /// Never throws across to Dart.
  private func readArpTable() -> [String: Any] {
    // MIB: net.route.0.inet.flags == RTF_LLINFO — the ARP (link-layer info)
    // entries of the IPv4 routing table. This is the same data `arp -a`
    // prints, read in-process instead of by spawning the CLI.
    var mib: [Int32] = [
      CTL_NET,
      PF_ROUTE,
      0,
      AF_INET,
      NET_RT_FLAGS,
      RTF_LLINFO,
    ]

    // First call: ask for the required buffer size.
    var bufferSize = 0
    if sysctl(&mib, u_int(mib.count), nil, &bufferSize, nil, 0) < 0 {
      return failure("sysctl(size) failed: \(errnoString())")
    }
    if bufferSize == 0 {
      // The call succeeded but the cache is empty. That is a valid result
      // (no hosts talked to recently), NOT a failure.
      return ["available": true, "entries": [[String: String]]()]
    }

    // Second call: fetch the actual routing-table dump.
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    let fetched: Int32 = buffer.withUnsafeMutableBytes { raw -> Int32 in
      guard let base = raw.baseAddress else { return -1 }
      return sysctl(&mib, u_int(mib.count), base, &bufferSize, nil, 0)
    }
    if fetched < 0 {
      return failure("sysctl(fetch) failed: \(errnoString())")
    }

    var entries: [[String: String]] = []

    // Walk the variable-length routing messages packed into the buffer. Each
    // entry begins with an `rt_msghdr`; the socket addresses follow it. The
    // destination sockaddr (AF_INET) gives the IP; the gateway sockaddr
    // (AF_LINK / sockaddr_dl) gives the MAC.
    buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let base = raw.baseAddress else { return }
      var offset = 0
      while offset + MemoryLayout<rt_msghdr>.size <= bufferSize {
        let rtmPtr = base.advanced(by: offset).assumingMemoryBound(to: rt_msghdr.self)
        let rtm = rtmPtr.pointee
        let msgLen = Int(rtm.rtm_msglen)
        if msgLen <= 0 || offset + msgLen > bufferSize { break }

        // The destination sockaddr immediately follows the header.
        let saStart = offset + MemoryLayout<rt_msghdr>.size
        if saStart + MemoryLayout<sockaddr_in>.size <= bufferSize {
          let sinPtr = base.advanced(by: saStart)
            .assumingMemoryBound(to: sockaddr_in.self)
          let sin = sinPtr.pointee
          if sin.sin_family == sa_family_t(AF_INET) {
            let ip = ipv4String(sin.sin_addr)

            // The gateway (link-layer) sockaddr follows the destination,
            // advanced by the destination sockaddr's (padded) length.
            let dstLen = saRoundedLen(sin.sin_len)
            let dlOffset = saStart + dstLen
            if dlOffset + MemoryLayout<sockaddr_dl>.size <= bufferSize {
              let sdlPtr = base.advanced(by: dlOffset)
                .assumingMemoryBound(to: sockaddr_dl.self)
              if let mac = macString(sdlPtr), !ip.isEmpty {
                entries.append(["ip": ip, "mac": mac])
              }
            }
          }
        }

        offset += msgLen
      }
    }

    return ["available": true, "entries": entries]
  }

  // MARK: - Parsing helpers

  /// Dotted-quad string for an `in_addr` (network byte order).
  private func ipv4String(_ addr: in_addr) -> String {
    let n = addr.s_addr  // network byte order
    let b0 = n & 0xff
    let b1 = (n >> 8) & 0xff
    let b2 = (n >> 16) & 0xff
    let b3 = (n >> 24) & 0xff
    return "\(b0).\(b1).\(b2).\(b3)"
  }

  /// Lower-case colon-separated MAC from a `sockaddr_dl`, or nil when the entry
  /// carries no 6-byte link-layer address (e.g. a non-Ethernet interface or an
  /// incomplete ARP entry). Never invents bytes.
  private func macString(_ sdlPtr: UnsafePointer<sockaddr_dl>) -> String? {
    let sdl = sdlPtr.pointee
    let alen = Int(sdl.sdl_alen)
    // Only standard 6-byte (EUI-48) link-layer addresses are reported. A 0-len
    // address is an incomplete ARP entry (IP known, MAC not yet resolved).
    guard alen == 6 else { return nil }

    // sdl_data holds [interface name (nlen bytes)][link addr (alen bytes)].
    let nlen = Int(sdl.sdl_nlen)
    var bytes = [UInt8](repeating: 0, count: alen)
    withUnsafePointer(to: sdl.sdl_data) { tuplePtr in
      tuplePtr.withMemoryRebound(to: CChar.self, capacity: nlen + alen) { cPtr in
        for i in 0..<alen {
          bytes[i] = UInt8(bitPattern: cPtr[nlen + i])
        }
      }
    }
    // A 6-byte all-zero address is not a real NIC; treat as absent.
    if bytes.allSatisfy({ $0 == 0 }) { return nil }
    return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
  }

  /// Routing-socket sockaddrs are padded to 4-byte boundaries; a 0-length
  /// sockaddr still consumes the minimum slot. Mirrors the kernel's SA_SIZE.
  private func saRoundedLen(_ len: UInt8) -> Int {
    let l = Int(len)
    if l == 0 { return 4 }
    return (l + 3) & ~3
  }

  /// Builds the structured failure payload (sysctl returned an error).
  private func failure(_ message: String) -> [String: Any] {
    return [
      "available": false,
      "entries": [[String: String]](),
      "error": message,
    ]
  }

  /// Current errno as "errno N (text)" for the surfaced error string.
  private func errnoString() -> String {
    let code = errno
    let text = String(cString: strerror(code))
    return "errno \(code) (\(text))"
  }
}
