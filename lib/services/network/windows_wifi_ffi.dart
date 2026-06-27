// Windows Native Wifi FFI implementation — the win32 calls behind
// [WindowsWifiReader]. Split into its own file so the win32 surface area lives
// in one place and [WindowsWifiReader] stays a thin platform-guarded wrapper.
//
// feat/windows-port-prep (2026-06-11). NO C++ MethodChannel — pure dart:ffi
// against wlanapi.dll via the `win32` package's pre-bound WLAN functions and
// structs (WlanOpenHandle / WlanEnumInterfaces / WlanQueryInterface /
// WlanGetNetworkBssList / WlanFreeMemory / WlanCloseHandle and the WLAN_* /
// DOT11_* structs). See windows_wifi_reader.dart for the call-flow narrative.
//
// EVERY runtime-truth claim here is `// TODO(windows-verify):` — this module
// compiles and `flutter analyze`-checks on macOS but is EXECUTED for the first
// time on a real Windows box with a real wireless NIC. dart:ffi does not run on
// macOS, so struct layout, pointer arithmetic, and free discipline are
// written-not-executed until the 26th.

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:win32/win32.dart';

import 'wifi_info_service.dart'
    show WifiInfo, WifiInfoUnavailable, WifiInfoUnavailableReason;

// ── Win32 constants (declared locally from the documented Native Wifi values
// rather than imported, so this module is robust to the win32 package's
// constant-export surface and self-documenting). Values are the canonical
// Microsoft Learn / wlanapi.h definitions. ─────────────────────────────────

/// `wlan_intf_opcode_current_connection` — the WlanQueryInterface opcode that
/// returns WLAN_CONNECTION_ATTRIBUTES for the live connection.
const int _kOpcodeCurrentConnection = 7;

/// `wlan_intf_opcode_channel_number` — returns the operating channel (ULONG) of
/// the connected interface. Authoritative for the primary link, and used to
/// disambiguate which affiliated per-link BSS to read on a Wi-Fi 7 MLO / MBSSID
/// connection where the current-connection BSSID is the AP MLD address.
const int _kOpcodeChannelNumber = 8;

/// `wlan_interface_state_connected` — the interface is associated to a network.
const int _kInterfaceStateConnected = 1;

/// `dot11_BSS_type_infrastructure` — a BSS served by an AP (vs ad-hoc). The
/// connected AP is always infrastructure for our purposes.
const int _kBssTypeInfrastructure = 1;

/// The WLAN client version we negotiate. 2 = Vista+ Native Wifi (what every
/// supported Windows ships). The negotiated version comes back in an out-param
/// we read but do not branch on.
const int _kWlanClientVersion = 2;

/// `ERROR_SUCCESS`.
const int _kErrorSuccess = 0;

// dot11_phy_type_* — the PHY generation the radio is using on this link.
const int _kPhyTypeDsss = 2; // 802.11b (DSSS)
const int _kPhyTypeOfdm = 4; // 802.11a (OFDM)
const int _kPhyTypeHrdsss = 5; // 802.11b (HR/DSSS)
const int _kPhyTypeErp = 6; // 802.11g (ERP)
const int _kPhyTypeHt = 7; // 802.11n (HT)
const int _kPhyTypeVht = 8; // 802.11ac (VHT)
const int _kPhyTypeHe = 10; // 802.11ax (HE)
const int _kPhyTypeEht = 11; // 802.11be (EHT)

// DOT11_AUTH_ALGO_* — the authentication algorithm from
// WLAN_SECURITY_ATTRIBUTES.dot11AuthAlgorithm. Mapped to the same security
// TOKEN strings the macOS/iOS channels emit, so WifiSecurityClassifier (Dart,
// shared) classifies them with zero new code.
const int _kAuthOpen = 1; // DOT11_AUTH_ALGO_80211_OPEN
const int _kAuthSharedKey = 2; // DOT11_AUTH_ALGO_80211_SHARED_KEY (WEP)
const int _kAuthWpa = 3; // DOT11_AUTH_ALGO_WPA (WPA Enterprise)
const int _kAuthWpaPsk = 4; // DOT11_AUTH_ALGO_WPA_PSK (WPA Personal)
const int _kAuthRsna = 6; // DOT11_AUTH_ALGO_RSNA (WPA2 Enterprise)
const int _kAuthRsnaPsk = 7; // DOT11_AUTH_ALGO_RSNA_PSK (WPA2 Personal)
const int _kAuthWpa3 = 8; // DOT11_AUTH_ALGO_WPA3 (WPA3 Enterprise, 192-bit)
const int _kAuthWpa3Sae = 9; // DOT11_AUTH_ALGO_WPA3_SAE (WPA3 Personal)
const int _kAuthOwe = 10; // DOT11_AUTH_ALGO_OWE (Enhanced Open)
const int _kAuthWpa3Ent = 11; // DOT11_AUTH_ALGO_WPA3_ENT (WPA3 Enterprise)

/// Reads the connected AP via the Native Wifi API and returns it as a [WifiInfo].
///
/// Throws [WifiInfoUnavailable] ([WifiInfoUnavailableReason.channelError]) on any
/// Native Wifi error, when there is no wireless interface, or when none is
/// connected. Frees every API-allocated buffer and closes the client handle on
/// every exit path (success or throw).
///
/// MUST only be called on Windows — [WindowsWifiReader] guards this.
WifiInfo readConnectedApFromNativeWifi() {
  final Pointer<IntPtr> phClientHandle = calloc<IntPtr>();
  final Pointer<Uint32> pdwNegotiated = calloc<Uint32>();
  Pointer<WLAN_INTERFACE_INFO_LIST> pIfList = nullptr;

  try {
    // 1. Open a client handle.
    final int openResult = WlanOpenHandle(
      _kWlanClientVersion,
      nullptr,
      pdwNegotiated,
      phClientHandle,
    );
    if (openResult != _kErrorSuccess) {
      throw WifiInfoUnavailable(
        WifiInfoUnavailableReason.channelError,
        'WlanOpenHandle failed (error $openResult).',
      );
    }
    final int handle = phClientHandle.value;

    try {
      // 2. Enumerate wireless interfaces; pick the first connected one.
      final Pointer<Pointer<WLAN_INTERFACE_INFO_LIST>> ppIfList =
          calloc<Pointer<WLAN_INTERFACE_INFO_LIST>>();
      try {
        final int enumResult =
            WlanEnumInterfaces(handle, nullptr, ppIfList);
        if (enumResult != _kErrorSuccess) {
          throw WifiInfoUnavailable(
            WifiInfoUnavailableReason.channelError,
            'WlanEnumInterfaces failed (error $enumResult).',
          );
        }
        pIfList = ppIfList.value;
      } finally {
        calloc.free(ppIfList);
      }

      final int count = pIfList.ref.dwNumberOfItems;
      if (count == 0) {
        throw const WifiInfoUnavailable(
          WifiInfoUnavailableReason.channelError,
          'No wireless interface present.',
        );
      }

      // Copy the GUID of the first connected interface into a buffer we own, so
      // it is unambiguously a Pointer<GUID> and outlives the list pointer.
      final Pointer<GUID> guidPtr = _interfaceGuidPointer(pIfList, count);
      if (guidPtr == nullptr) {
        throw const WifiInfoUnavailable(
          WifiInfoUnavailableReason.channelError,
          'No connected wireless interface.',
        );
      }

      try {
        // 3. Query the current connection attributes.
        final _ConnectionSnapshot conn =
            _queryCurrentConnection(handle, guidPtr);

        // 4. Read the BSS list to get the real dBm RSSI + center frequency for
        // the connected BSSID.
        final _BssSnapshot? bss = _queryConnectedBss(handle, guidPtr, conn);

        return _composeWifiInfo(conn, bss);
      } finally {
        calloc.free(guidPtr);
      }
    } finally {
      if (pIfList != nullptr) {
        WlanFreeMemory(pIfList.cast());
      }
      WlanCloseHandle(handle, nullptr);
    }
  } finally {
    calloc.free(phClientHandle);
    calloc.free(pdwNegotiated);
  }
}

/// Returns a freshly-allocated pointer to a COPY of the first connected
/// interface's GUID, or nullptr when none is connected. The caller owns the
/// buffer and frees it with `calloc.free`.
///
/// Copying (rather than taking the address of the inline-array element) keeps
/// the GUID valid independent of the interface-list pointer's lifetime and makes
/// it unambiguously a `Pointer&lt;GUID&gt;` for WlanQueryInterface.
///
/// TODO(windows-verify): confirm the inline-array element read
/// `pIfList.ref.InterfaceInfo[i]` indexes correctly against the real
/// variable-length WLAN_INTERFACE_INFO_LIST layout (the part most likely to need
/// a tweak on the real struct).
Pointer<GUID> _interfaceGuidPointer(
  Pointer<WLAN_INTERFACE_INFO_LIST> pIfList,
  int count,
) {
  for (int i = 0; i < count; i++) {
    final WLAN_INTERFACE_INFO info = pIfList.ref.InterfaceInfo[i];
    if (info.isState == _kInterfaceStateConnected) {
      // Copy the 16-byte GUID into a stable buffer we own, so it outlives any
      // reshuffle of the list pointer and is unambiguously a Pointer<GUID>.
      final Pointer<GUID> out = calloc<GUID>();
      // win32's GUID models Data4 as a single Uint64 (not an 8-byte array), so
      // the whole 16-byte GUID copies as four scalar field assignments.
      out.ref
        ..Data1 = info.InterfaceGuid.Data1
        ..Data2 = info.InterfaceGuid.Data2
        ..Data3 = info.InterfaceGuid.Data3
        ..Data4 = info.InterfaceGuid.Data4;
      return out;
    }
  }
  return nullptr;
}

/// The fields we lift out of WLAN_CONNECTION_ATTRIBUTES (+ its security attrs).
class _ConnectionSnapshot {
  const _ConnectionSnapshot({
    required this.ssid,
    required this.bssid,
    required this.phyType,
    required this.signalQuality,
    required this.rxRateKbps,
    required this.txRateKbps,
    required this.securityToken,
  });

  final String? ssid;
  final String? bssid;
  final int phyType;
  final int signalQuality; // 0–100
  final int rxRateKbps; // ulRxRate is in Kbps
  final int txRateKbps; // ulTxRate is in Kbps
  final String? securityToken;
}

/// Queries WLAN_CONNECTION_ATTRIBUTES for the connected interface.
_ConnectionSnapshot _queryCurrentConnection(
  int handle,
  Pointer<GUID> guidPtr,
) {
  final Pointer<Uint32> pDataSize = calloc<Uint32>();
  final Pointer<Pointer> ppData = calloc<Pointer>();
  Pointer<WLAN_CONNECTION_ATTRIBUTES> pConn = nullptr;
  try {
    final int qResult = WlanQueryInterface(
      handle,
      guidPtr,
      _kOpcodeCurrentConnection,
      nullptr,
      pDataSize,
      ppData,
      nullptr,
    );
    if (qResult != _kErrorSuccess) {
      throw WifiInfoUnavailable(
        WifiInfoUnavailableReason.channelError,
        'WlanQueryInterface(current_connection) failed (error $qResult).',
      );
    }
    pConn = ppData.value.cast<WLAN_CONNECTION_ATTRIBUTES>();
    final WLAN_ASSOCIATION_ATTRIBUTES assoc = pConn.ref.wlanAssociationAttributes;

    // SSID: DOT11_SSID is a length-prefixed (NOT null-terminated) byte array.
    final String? ssid = _decodeSsid(assoc.dot11Ssid);
    // BSSID: 6 raw bytes → colon-hex.
    final String? bssid = _decodeBssid(assoc.dot11Bssid);

    final WLAN_SECURITY_ATTRIBUTES sec = pConn.ref.wlanSecurityAttributes;
    final String? token = sec.bSecurityEnabled == 0
        ? 'open'
        : _securityToken(sec.dot11AuthAlgorithm);

    return _ConnectionSnapshot(
      ssid: ssid,
      bssid: bssid,
      phyType: assoc.dot11PhyType,
      signalQuality: assoc.wlanSignalQuality,
      rxRateKbps: assoc.ulRxRate,
      txRateKbps: assoc.ulTxRate,
      securityToken: token,
    );
  } finally {
    if (pConn != nullptr) {
      WlanFreeMemory(pConn.cast());
    }
    calloc.free(pDataSize);
    calloc.free(ppData);
  }
}

/// The fields we lift out of the connected WLAN_BSS_ENTRY (real dBm + frequency).
class _BssSnapshot {
  const _BssSnapshot({required this.rssiDbm, required this.centerFreqKhz});

  final int rssiDbm; // lRssi — a true negative dBm
  final int centerFreqKhz; // ulChCenterFrequency, in kHz
}

/// A decoded BSS-list entry we may select the connected link from.
///
/// A plain Dart value object (no win32 struct), so the link-selection logic that
/// consumes it ([selectConnectedLink]) is unit-testable off Windows.
/// [_queryConnectedBss] builds these from WLAN_BSS_ENTRY rows.
@visibleForTesting
class WifiBssCandidate {
  const WifiBssCandidate({
    required this.bssid,
    required this.ssid,
    required this.rssiDbm,
    required this.centerFreqKhz,
  });

  final String bssid; // lowercase colon-hex
  final String? ssid;
  final int rssiDbm;
  final int centerFreqKhz;
}

/// First 5 octets of a colon-hex BSSID (`94:2a:6f:a0:a5`), lowercased. Groups
/// the transmitted + non-transmitted BSSIDs of one AP radio (MBSSID), and
/// bridges a Wi-Fi 7 AP MLD address to its affiliated per-link APs, which share
/// the OUI + first device octets and differ only in the last byte. Lowercasing
/// makes the prefix match case-insensitive; the real call path already feeds it
/// lowercase BSSIDs, so this is behavior-preserving.
@visibleForTesting
String bssidRadioPrefix(String bssid) {
  final String lower = bssid.toLowerCase();
  final List<String> parts = lower.split(':');
  return parts.length >= 6 ? parts.sublist(0, 5).join(':') : lower;
}

/// Picks the candidate on [operatingChannel] when known, else the strongest
/// (least-negative dBm). Returns null for an empty list.
WifiBssCandidate? _selectLink(
  List<WifiBssCandidate> list,
  int? operatingChannel,
) {
  if (list.isEmpty) return null;
  if (operatingChannel != null) {
    for (final WifiBssCandidate c in list) {
      if (_frequencyKhzToChannel(c.centerFreqKhz) == operatingChannel) return c;
    }
  }
  final List<WifiBssCandidate> sorted = List<WifiBssCandidate>.of(list)
    ..sort((WifiBssCandidate a, WifiBssCandidate b) =>
        b.rssiDbm.compareTo(a.rssiDbm));
  return sorted.first;
}

/// The pure connected-link selection: given the decoded BSS candidates and the
/// current-connection identifiers, returns the candidate that represents the
/// connected link, or null when nothing advertises the connection.
///
/// Precedence (exact → broad), identical to the win32 path it was extracted
/// from, so the common single-link case is unchanged:
///   1. Exact BSSID match (non-MLO APs).
///   2. Same AP radio (shared first-5-octet prefix) — the Wi-Fi 7 MLO / MBSSID
///      case where [connBssid] is the AP MLD address that never beacons;
///      selects the affiliated link on [operatingChannel], else the strongest.
///   3. Same SSID — last resort; same selection rule.
///
/// [connBssid] is matched case-insensitively against the (lowercase)
/// candidate BSSIDs.
@visibleForTesting
WifiBssCandidate? selectConnectedLink(
  List<WifiBssCandidate> candidates, {
  required String? connBssid,
  required String? connSsid,
  required int? operatingChannel,
}) {
  if (candidates.isEmpty) return null;

  final String? lowerBssid = connBssid?.toLowerCase();

  // 1. Exact BSSID match — the normal single-link case.
  if (lowerBssid != null) {
    for (final WifiBssCandidate c in candidates) {
      if (c.bssid == lowerBssid) return c;
    }
    // 2. Same AP radio (Wi-Fi 7 MLO / MBSSID): the connection BSSID is the AP
    // MLD address; read the affiliated per-link AP on the operating channel.
    final String prefix = bssidRadioPrefix(lowerBssid);
    final List<WifiBssCandidate> sameRadio = candidates
        .where((WifiBssCandidate c) => bssidRadioPrefix(c.bssid) == prefix)
        .toList();
    final WifiBssCandidate? link = _selectLink(sameRadio, operatingChannel);
    if (link != null) return link;
  }

  // 3. Same SSID — last resort.
  if (connSsid != null) {
    final List<WifiBssCandidate> sameSsid = candidates
        .where((WifiBssCandidate c) => c.ssid != null && c.ssid == connSsid)
        .toList();
    final WifiBssCandidate? link = _selectLink(sameSsid, operatingChannel);
    if (link != null) return link;
  }

  return null;
}

/// Queries `wlan_intf_opcode_channel_number` for the connected interface's
/// operating channel. Returns null on any error or a 0 channel.
int? _queryOperatingChannel(int handle, Pointer<GUID> guidPtr) {
  final Pointer<Uint32> pDataSize = calloc<Uint32>();
  final Pointer<Pointer> ppData = calloc<Pointer>();
  try {
    final int r = WlanQueryInterface(
      handle,
      guidPtr,
      _kOpcodeChannelNumber,
      nullptr,
      pDataSize,
      ppData,
      nullptr,
    );
    if (r != _kErrorSuccess || ppData.value == nullptr) return null;
    final int ch = ppData.value.cast<Uint32>().value;
    WlanFreeMemory(ppData.value);
    return ch == 0 ? null : ch;
  } finally {
    calloc.free(pDataSize);
    calloc.free(ppData);
  }
}

/// Reads the BSS list and returns the connected link's RSSI + center frequency.
///
/// Match order, exact → broad, so the common single-link case is unchanged:
///   1. Exact BSSID match (non-MLO APs).
///   2. Same AP radio (shared first-5-octet prefix) — the Wi-Fi 7 MLO / MBSSID
///      case where the current-connection BSSID is the AP MLD address that never
///      beacons; selects the affiliated link on the operating channel.
///   3. Same SSID — last resort; selects the link on the operating channel, else
///      the strongest.
/// Returns null only when nothing advertises the connection at all (then
/// RSSI-dBm/channel/band stay null and the signal-quality % still shows).
_BssSnapshot? _queryConnectedBss(
  int handle,
  Pointer<GUID> guidPtr,
  _ConnectionSnapshot conn,
) {
  final Pointer<Pointer<WLAN_BSS_LIST>> ppBssList =
      calloc<Pointer<WLAN_BSS_LIST>>();
  Pointer<WLAN_BSS_LIST> pBssList = nullptr;
  try {
    // Passing a null DOT11_SSID + infrastructure BSS type returns all BSS
    // entries the driver currently has; we then match the connected link.
    final int bResult = WlanGetNetworkBssList(
      handle,
      guidPtr,
      nullptr,
      _kBssTypeInfrastructure,
      0,
      nullptr,
      ppBssList,
    );
    if (bResult != _kErrorSuccess) {
      // The BSS list is an ENRICHMENT (real dBm + channel); its absence is not
      // fatal. Degrade honestly to signal-quality only.
      return null;
    }
    pBssList = ppBssList.value;
    final int n = pBssList.ref.dwNumberOfItems;

    final List<WifiBssCandidate> candidates = <WifiBssCandidate>[];
    for (int i = 0; i < n; i++) {
      final WLAN_BSS_ENTRY entry = pBssList.ref.wlanBssEntries[i];
      final String? bssid = _decodeBssid(entry.dot11Bssid);
      if (bssid == null) continue;
      candidates.add(WifiBssCandidate(
        bssid: bssid.toLowerCase(),
        ssid: _decodeSsid(entry.dot11Ssid),
        rssiDbm: entry.lRssi,
        centerFreqKhz: entry.ulChCenterFrequency,
      ));
    }
    if (candidates.isEmpty) return null;

    final int? operatingChannel = _queryOperatingChannel(handle, guidPtr);

    // Pure precedence (exact → same-radio → same-SSID), extracted so it is
    // unit-testable off Windows. See [selectConnectedLink].
    final WifiBssCandidate? link = selectConnectedLink(
      candidates,
      connBssid: conn.bssid,
      connSsid: conn.ssid,
      operatingChannel: operatingChannel,
    );
    if (link != null) {
      return _BssSnapshot(
        rssiDbm: link.rssiDbm,
        centerFreqKhz: link.centerFreqKhz,
      );
    }

    // TODO(windows-verify): channel WIDTH lives in the IE blob (entry.ulIeOffset
    // / entry.ulIeSize → HT/VHT/HE operation elements). Parsing is deferred to
    // device-time; until then channelWidthMhz is honestly null, the same posture
    // Android takes when there is no scan match.
    return null;
  } finally {
    if (pBssList != nullptr) {
      WlanFreeMemory(pBssList.cast());
    }
    calloc.free(ppBssList);
  }
}

/// Folds the connection + BSS snapshots into the shared [WifiInfo] contract.
///
/// Field availability mirrors Android's honest posture, plus Windows extras:
///   * RSSI dBm  — from the BSS entry (real dBm); null when no BSS match.
///   * Tx + Rx rate — from the association attrs (Windows supplies BOTH, unlike
///     macOS which has no Rx). Kbps → Mbps.
///   * channel + band — derived from the BSS center frequency.
///   * noise / SNR — NOT exposed by Native Wifi → null, never derived (GL-005).
///   * channelWidthMhz — IE parsing deferred → null for now.
WifiInfo _composeWifiInfo(_ConnectionSnapshot conn, _BssSnapshot? bss) {
  final int? channel =
      bss == null ? null : _frequencyKhzToChannel(bss.centerFreqKhz);
  final String? band =
      bss == null ? null : _frequencyKhzToBand(bss.centerFreqKhz);

  // ulTxRate / ulRxRate are in units of Kbps. Mbps = Kbps / 1000. A 0 value
  // means "not reported" → null, never a fabricated 0 Mbps.
  final double? txMbps =
      conn.txRateKbps > 0 ? conn.txRateKbps / 1000.0 : null;
  final double? rxMbps =
      conn.rxRateKbps > 0 ? conn.rxRateKbps / 1000.0 : null;

  return WifiInfo(
    interfaceName: null, // Native Wifi exposes a GUID, not a BSD-style name.
    ssid: conn.ssid,
    bssid: conn.bssid,
    rssiDbm: bss?.rssiDbm, // real dBm from the BSS entry, or null.
    // Native Wifi exposes no noise floor → SNR cannot be computed (GL-005).
    noiseDbm: null,
    snrDb: null,
    txRateMbps: txMbps,
    rxRateMbps: rxMbps, // Windows DOES supply Rx (macOS does not).
    phyMode: _phyTypeToStandard(conn.phyType),
    channel: channel,
    channelWidthMhz: null, // IE parse deferred; see TODO(windows-verify).
    band: band,
    countryCode: null, // WLAN_COUNTRY_OR_REGION_STRING_LIST read deferred.
    hardwareAddress: null, // device MAC read deferred (not the AP BSSID).
    securityToken: conn.securityToken,
    poweredOn: true, // a current-connection read implies the radio is on.
    locationAuthorized: true, // Windows Native Wifi needs no Location grant.
  );
}

// ── Decoders + mappers (pure, would be unit-testable if not for the win32
// struct inputs; the value→token/standard/band helpers below ARE pure and are
// exercised by windows_wifi_mapping_test.dart). ────────────────────────────

/// DOT11_SSID is length-prefixed: `uSSIDLength` valid bytes in `ucSSID[32]`.
/// Decoded as UTF-8 (the common case); an empty/oversize length → null.
String? _decodeSsid(DOT11_SSID ssid) {
  final int len = ssid.uSSIDLength;
  if (len <= 0 || len > 32) return null;
  final List<int> bytes = <int>[for (int i = 0; i < len; i++) ssid.ucSSID[i]];
  try {
    return _utf8OrLatin1(bytes);
  } catch (_) {
    return null;
  }
}

/// 6 raw BSSID bytes → lowercase colon-separated hex (`a4:83:e7:00:11:22`).
String? _decodeBssid(Array<Uint8> mac) {
  final List<String> parts = <String>[
    for (int i = 0; i < 6; i++) mac[i].toRadixString(16).padLeft(2, '0'),
  ];
  final String joined = parts.join(':');
  return joined == '00:00:00:00:00:00' ? null : joined;
}

/// Maps a dot11 PHY type to the 802.11 designation the [WifiInfo] model carries.
/// ConnectedAp._macStandardLabel folds in the Wi-Fi N marketing name from this.
String? phyTypeToStandard(int phyType) => _phyTypeToStandard(phyType);

String? _phyTypeToStandard(int phyType) {
  return switch (phyType) {
    _kPhyTypeDsss || _kPhyTypeHrdsss => '802.11b',
    _kPhyTypeOfdm => '802.11a',
    _kPhyTypeErp => '802.11g',
    _kPhyTypeHt => '802.11n',
    _kPhyTypeVht => '802.11ac',
    _kPhyTypeHe => '802.11ax',
    _kPhyTypeEht => '802.11be',
    _ => null,
  };
}

/// Maps a DOT11_AUTH_ALGO_* value to the security TOKEN the shared
/// [WifiSecurityClassifier] understands. Windows exposes the FINE auth algorithm
/// (WPA2 vs WPA3, Personal vs Enterprise) — richer than iOS's coarse view, on a
/// par with macOS. Cipher could refine WEP-vs-open further but the auth algo is
/// sufficient for the model's label set.
String? securityTokenForAuthAlgo(int authAlgo) => _securityToken(authAlgo);

String? _securityToken(int authAlgo) {
  return switch (authAlgo) {
    _kAuthOpen => 'open',
    _kAuthSharedKey => 'wep',
    _kAuthWpa => 'wpaEnterprise',
    _kAuthWpaPsk => 'wpaPersonal',
    _kAuthRsna => 'wpa2Enterprise',
    _kAuthRsnaPsk => 'wpa2Personal',
    _kAuthWpa3 || _kAuthWpa3Ent => 'wpa3Enterprise',
    _kAuthWpa3Sae => 'wpa3Personal',
    _kAuthOwe => 'owe',
    _ => 'unknown',
  };
}

/// Center frequency (kHz) → 802.11 channel number. Covers 2.4 / 5 / 6 GHz.
/// Pure; unit-tested. Returns null for a frequency outside the known plans.
int? frequencyKhzToChannel(int freqKhz) => _frequencyKhzToChannel(freqKhz);

int? _frequencyKhzToChannel(int freqKhz) {
  final int mhz = (freqKhz / 1000).round();
  // 2.4 GHz: ch1=2412 … ch13=2472, ch14=2484.
  if (mhz == 2484) return 14;
  if (mhz >= 2412 && mhz <= 2472) return ((mhz - 2412) ~/ 5) + 1;
  // 5 GHz: ch = (MHz − 5000) / 5.
  if (mhz >= 5160 && mhz <= 5885) return (mhz - 5000) ~/ 5;
  // 6 GHz (Wi-Fi 6E/7): ch = (MHz − 5950) / 5, ch1=5955 … .
  if (mhz >= 5955 && mhz <= 7115) return (mhz - 5950) ~/ 5;
  return null;
}

/// Center frequency (kHz) → human band label, matching the model's set.
String? frequencyKhzToBand(int freqKhz) => _frequencyKhzToBand(freqKhz);

String? _frequencyKhzToBand(int freqKhz) {
  final int mhz = (freqKhz / 1000).round();
  if (mhz >= 2400 && mhz < 2500) return '2.4 GHz';
  if (mhz >= 4900 && mhz < 5900) return '5 GHz';
  if (mhz >= 5925 && mhz <= 7125) return '6 GHz';
  return null;
}

/// Decode bytes as UTF-8, falling back to Latin-1 for a non-UTF-8 SSID. Kept
/// tiny and dependency-free.
String _utf8OrLatin1(List<int> bytes) {
  try {
    return const Utf8Decoder(allowMalformed: false).convert(bytes);
  } catch (_) {
    return const Latin1Decoder().convert(bytes);
  }
}
