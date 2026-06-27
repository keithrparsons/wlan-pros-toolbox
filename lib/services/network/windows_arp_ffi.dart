// Windows ARP / neighbor-cache reader — pure dart:ffi against iphlpapi.dll's
// GetIpNetTable. NO C++ runner code, NO `arp.exe` subprocess, NO WMI.
//
// feat/windows-arp-enrichment. This is the Windows counterpart to the macOS
// sysctl ARP read (macos/Runner/ArpTableChannel.swift) and the Android/iOS
// honest-unavailable readers. It supplies the IP -> MAC map the Network
// Discovery engine folds onto each host, so the SHARED, pure-Dart MAC -> vendor
// resolver (MacOuiService.vendorLabelFor — already injected into
// LanDiscoveryEngine by network_discovery_screen.dart) then names the vendor on
// Windows with zero new code.
//
// WHY GetIpNetTable (not GetIpNetTable2): the LAN sweep is IPv4-only, and
// GetIpNetTable returns an IPv4 MIB_IPNETTABLE of fixed-layout MIB_IPNETROW
// rows (24 bytes each, 4-byte aligned, no unions). GetIpNetTable2 would force
// hand-marshalling the MIB_IPNET_ROW2 SOCKADDR_INET union for no benefit here.
// Neither function — nor the MIB_IPNET* structs — is bound by the pinned
// win32 5.15.0 (it exposes only 9 iphlpapi calls, none of them the neighbor
// table), so GetIpNetTable is bound here directly from iphlpapi.dll and
// MIB_IPNETROW is declared as a local FFI struct.
//
// TWO-CALL SIZE-THEN-FILL: GetIpNetTable(null, &size, false) returns
// ERROR_INSUFFICIENT_BUFFER with the byte count; we allocate, call again to
// fill, then walk dwNumEntries rows. Every allocated buffer is freed on every
// exit path (success or throw).
//
// HONESTY (GL-005 / GL-008): an entry whose dwType is INVALID, whose physical-
// address length is < 6, or whose MAC is all-zero is an unresolved / incomplete
// neighbor (never contacted, or a layer-3 hop away) — it is SKIPPED, never
// emitted with a fabricated MAC. A host simply absent from the cache keeps a
// null MAC upstream.
//
// PLATFORM GUARD: this module is only ever reached after a Platform.isWindows
// check in arp_reader.dart's platformArpReader(). `_iphlpapi` is a LAZY
// top-level final (Dart initializes top-level finals on first read), so
// DynamicLibrary.open('iphlpapi.dll') runs only on the first real read — i.e.
// only on Windows. Off Windows the symbol is never touched and the DLL is never
// loaded, exactly as windows_wifi_ffi.dart keeps wlanapi.dll inert off Windows.
//
// VERIFICATION STATUS: written-not-executed. dart:ffi does not run on macOS, so
// the struct layout, the size-then-fill flow, and the free discipline below are
// `flutter analyze`-clean here but EXECUTED for the first time on a real Windows
// box. The pure helpers (ipv4FromNetworkOrder / formatPhysAddr) ARE unit-tested
// off Windows. Each runtime-truth point is marked `// TODO(windows-verify):`.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

// ── iphlpapi result codes (winerror.h) and MIB_IPNET_TYPE values. Declared
// locally from the documented Microsoft values so this module is self-
// contained and robust to the win32 package's constant-export surface. ───────

/// `ERROR_SUCCESS`.
const int _kErrorSuccess = 0;

/// `ERROR_INSUFFICIENT_BUFFER` — the sizing call returns this with the required
/// byte count written to the size out-param. We then allocate and call again.
const int _kErrorInsufficientBuffer = 122;

/// `ERROR_NO_DATA` — the ARP table is empty. A SUCCESSFUL "warm cache, no
/// entries" outcome, NOT a failure: returns an empty list, never throws.
const int _kErrorNoData = 232;

/// `MIB_IPNET_TYPE_INVALID` — the row holds no valid mapping. Skipped.
const int _kIpNetTypeInvalid = 2;

/// Byte offset of the variable-length `table[]` array inside MIB_IPNETTABLE:
/// `dwNumEntries` (DWORD, 4) with no padding before the first MIB_IPNETROW
/// (whose max field alignment is 4). Rows therefore start at +4.
const int _kRowsOffset = 4;

/// Thrown for a genuine GetIpNetTable failure (a non-success, non-empty result
/// code). The reader in arp_reader.dart maps this to an honest unavailable
/// [ArpReadResult] — never a fabricated MAC.
class WindowsArpReadException implements Exception {
  const WindowsArpReadException(this.message);

  final String message;

  @override
  String toString() => 'WindowsArpReadException: $message';
}

// ── GetIpNetTable binding. `DynamicLibrary.open` lives in a LAZY top-level
// final, so iphlpapi.dll is opened only on the first real read (Windows only),
// never at import time. ──────────────────────────────────────────────────────

/// `DWORD GetIpNetTable(PMIB_IPNETTABLE, PULONG SizePointer, BOOL Order);`
typedef _GetIpNetTableC = Uint32 Function(
  Pointer<Uint8> table,
  Pointer<Uint32> size,
  Int32 order,
);
typedef _GetIpNetTableDart = int Function(
  Pointer<Uint8> table,
  Pointer<Uint32> size,
  int order,
);

final DynamicLibrary _iphlpapi = DynamicLibrary.open('iphlpapi.dll');

final _GetIpNetTableDart _getIpNetTable =
    _iphlpapi.lookupFunction<_GetIpNetTableC, _GetIpNetTableDart>(
  'GetIpNetTable',
);

/// One ARP row: MIB_IPNETROW (winternl/iphlpapi.h).
///
/// ```c
/// typedef struct _MIB_IPNETROW {
///   DWORD dwIndex;            // adapter interface index
///   DWORD dwPhysAddrLen;      // valid bytes in bPhysAddr (6 for Ethernet/Wi-Fi)
///   UCHAR bPhysAddr[8];       // MAXLEN_PHYSADDR = 8
///   DWORD dwAddr;             // IPv4 in network byte order
///   DWORD dwType;             // MIB_IPNET_TYPE (2 == INVALID)
/// } MIB_IPNETROW;
/// ```
/// Size = 4 + 4 + 8 + 4 + 4 = 24 bytes, all fields 4-byte aligned.
final class _MibIpNetRow extends Struct {
  @Uint32()
  external int dwIndex;

  @Uint32()
  external int dwPhysAddrLen;

  @Array(8)
  external Array<Uint8> bPhysAddr;

  @Uint32()
  external int dwAddr;

  @Uint32()
  external int dwType;
}

/// Reads the system ARP/neighbor cache and returns IP -> MAC pairs for every
/// COMPLETE entry. Throws [WindowsArpReadException] on a genuine API failure;
/// returns an empty list when the cache is warm but holds no entries.
///
/// MUST only be called on Windows (arp_reader.dart guards Platform.isWindows).
/// Frees every buffer on every exit path.
///
/// TODO(windows-verify): first real execution of the FFI path — confirm the
/// two-call sizing flow, the MIB_IPNETROW marshalling (dwAddr network-byte
/// order, bPhysAddr[0..5] = MAC), the +4 rows offset / 24-byte stride, and the
/// free discipline against a real iphlpapi.dll.
List<MapEntry<String, String>> readArpTableViaIpHlpApi() {
  final Pointer<Uint32> pSize = calloc<Uint32>();
  Pointer<Uint8> table = nullptr;
  try {
    // 1. Sizing call: null buffer → ERROR_INSUFFICIENT_BUFFER + required bytes.
    int result = _getIpNetTable(nullptr, pSize, 0);
    if (result == _kErrorNoData) return const <MapEntry<String, String>>[];
    if (result != _kErrorInsufficientBuffer) {
      if (result == _kErrorSuccess && pSize.value == 0) {
        return const <MapEntry<String, String>>[];
      }
      throw WindowsArpReadException(
        'GetIpNetTable sizing call failed (error $result).',
      );
    }
    final int bytes = pSize.value;
    if (bytes <= 0) return const <MapEntry<String, String>>[];

    // 2. Fill call.
    table = calloc<Uint8>(bytes);
    result = _getIpNetTable(table, pSize, 0);
    if (result == _kErrorNoData) return const <MapEntry<String, String>>[];
    if (result != _kErrorSuccess) {
      throw WindowsArpReadException(
        'GetIpNetTable read call failed (error $result).',
      );
    }

    // 3. Walk dwNumEntries rows (first DWORD of MIB_IPNETTABLE, rows at +4).
    final int numEntries = table.cast<Uint32>().value;
    final Pointer<_MibIpNetRow> rows =
        Pointer<_MibIpNetRow>.fromAddress(table.address + _kRowsOffset);

    final List<MapEntry<String, String>> out = <MapEntry<String, String>>[];
    for (int i = 0; i < numEntries; i++) {
      final _MibIpNetRow row = (rows + i).ref;
      // Skip INVALID and incomplete rows — an unresolved neighbor has no MAC,
      // and we never fabricate one (GL-005).
      if (row.dwType == _kIpNetTypeInvalid) continue;
      if (row.dwPhysAddrLen < 6) continue;
      final List<int> macBytes = <int>[
        for (int b = 0; b < 6; b++) row.bPhysAddr[b],
      ];
      final String? mac = formatPhysAddr(macBytes);
      if (mac == null) continue; // all-zero / unresolved — skip, never fake.
      out.add(MapEntry<String, String>(ipv4FromNetworkOrder(row.dwAddr), mac));
    }
    return out;
  } finally {
    if (table != nullptr) calloc.free(table);
    calloc.free(pSize);
  }
}

// ── Pure helpers (no FFI symbol touched) — unit-tested off Windows. ──────────

/// IPv4 dotted-quad from a DWORD holding the address in NETWORK byte order.
///
/// MIB_IPNETROW.dwAddr stores the four octets `a.b.c.d` in memory order, so a
/// little-endian DWORD read yields `a + b<<8 + c<<16 + d<<24`; masking the
/// bytes back out recovers `a.b.c.d` directly (independent of host endianness,
/// because we read the scalar value, not raw memory).
String ipv4FromNetworkOrder(int dword) {
  final int a = dword & 0xff;
  final int b = (dword >> 8) & 0xff;
  final int c = (dword >> 16) & 0xff;
  final int d = (dword >> 24) & 0xff;
  return '$a.$b.$c.$d';
}

/// First 6 octets → lowercase colon-hex (`b8:27:eb:01:23:45`), matching the
/// app's MAC formatting (mirrors windows_wifi_ffi.formatMacBytes). Returns null
/// for a short input or the all-zero MAC (an unresolved/incomplete neighbor
/// entry) — never a fabricated address.
String? formatPhysAddr(List<int> bytes) {
  if (bytes.length < 6) return null;
  final List<String> parts = <String>[
    for (int i = 0; i < 6; i++) (bytes[i] & 0xff).toRadixString(16).padLeft(2, '0'),
  ];
  final String joined = parts.join(':');
  return joined == '00:00:00:00:00:00' ? null : joined;
}
