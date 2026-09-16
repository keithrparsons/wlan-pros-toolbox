// RSN / WPA information-element → security-token decoder.
//
// Reads what a BSS ADVERTISES IN ITS OWN BEACON rather than what the OS says
// about the network the BSS belongs to. That distinction is the whole reason
// this file exists. Windows reports `dot11DefaultAuthAlgorithm` per NETWORK via
// `WlanGetAvailableNetworkList`, and `netsh wlan show networks mode=bssid`
// prints Authentication once per SSID and not once per BSSID (measured on real
// hardware 2026-09-16). So the OS cannot express one SSID running different
// security per band, which is exactly the case Join a Network exists to handle:
// a travel router advertising wpa-psk/sae on 5 GHz and plain wpa-psk on 2.4.
// The IE blob is already per-BSS, so it can.
//
// PLATFORM-NEUTRAL ON PURPOSE, and extracted for the same reason
// `ie_parser.dart` was: these are bytes off the air, and there should be ONE
// bounds-checked decoder rather than one per platform. Windows is the first
// caller; the WLAN Pi and Android both have per-BSS IE blobs available and can
// adopt it without a second implementation to keep in step.
//
// NEVER THROWS. Every length and count here comes off the air and may be
// hostile or simply truncated. A malformed element yields FEWER tokens, never
// an exception and never a fabricated one. The walk is the shared, tested
// `walkInformationElements`, so truncation stops the walk cleanly.
//
// THE VOCABULARY IS NOT NEW. Tokens are the ones `WifiSecurityClassifier`
// already resolves for macOS and iOS, so there is one set of names across the
// app rather than a Windows dialect. Adding a token here without adding it
// there produces `WifiSecurity.unknown`, which is the honest failure and not a
// crash, but it is still a bug: keep the two in step.

import 'dart:typed_data';

import 'ie_parser.dart';

/// Element ID 48 — the RSN element (WPA2 / WPA3).
const int kEidRsn = 48;

/// The RSN/IEEE 802.11 selector OUI, `00-0F-AC`.
const List<int> kRsnOui = <int>[0x00, 0x0f, 0xac];

/// The Microsoft selector OUI, `00-50-F2`, used by the pre-RSN WPA1 vendor IE.
const List<int> kMsOui = <int>[0x00, 0x50, 0xf2];

/// Vendor-IE type byte identifying the WPA1 element (`00-50-F2:01`).
const int kWpaVendorType = 1;

/// Bit 4 of the 802.11 Capability Information field: Privacy.
///
/// The ONLY way to tell an open BSS from a WEP one, because WEP advertises
/// neither an RSN nor a WPA element. Without this bit both look identical from
/// the IEs alone, which is why [securityTokensFromIes] takes it as an argument
/// rather than guessing.
const int kCapabilityPrivacyBit = 0x0010;

/// Security tokens advertised by the BSS whose beacon/probe IEs are [ies].
///
/// Returns a LIST because a BSS genuinely advertises more than one scheme at
/// once: a WPA2/WPA3 transition BSS carries both PSK and SAE AKMs, and
/// flattening that to one token would reintroduce, one layer down, the defect
/// per-BSS security exists to prevent. Order is canonical (oldest scheme first)
/// so the output is stable and diffable, not hash-ordered.
///
/// [capabilityInformation] is the 802.11 Capability Information field from the
/// same BSS entry, when the caller has it. It is consulted ONLY when no RSN and
/// no WPA element is present, to separate open from WEP.
///
/// RETURNS EMPTY when nothing can be resolved, and empty MUST NOT be read as
/// open. `ScannedAp.security` documents the same rule: an open BSS reports the
/// token `none`, and absence of information is not information. When no
/// security element is present AND no capability field was supplied, the honest
/// answer is that we do not know, so the list is empty.
List<String> securityTokensFromIes(
  Uint8List ies, {
  int? capabilityInformation,
}) {
  final Set<String> tokens = <String>{};
  bool sawSecurityElement = false;

  for (final InformationElement e in walkInformationElements(ies)) {
    if (e.id == kEidRsn) {
      sawSecurityElement = true;
      tokens.addAll(_tokensFromRsnBody(e.bytes));
    } else if (e.id == kEidVendorSpecific && _isWpaVendorIe(e.bytes)) {
      sawSecurityElement = true;
      // Skip OUI(3) + type(1); the remainder has the RSN body layout.
      tokens.addAll(
        _tokensFromRsnBody(
          Uint8List.sublistView(e.bytes, 4),
          oui: kMsOui,
          akmMap: _wpaAkmTokens,
        ),
      );
    }
  }

  if (tokens.isNotEmpty) return _canonical(tokens);

  // ORDER MATTERS HERE, and getting it wrong is not cosmetic. A security
  // element WAS present but named no AKM we recognise: a future scheme, a
  // vendor AKM, or a malformed count. Privacy is set on every encrypted
  // network, so falling through to the bit below would report a modern
  // WPA3-era BSS as WEP. That is a false and actively harmful statement about
  // someone's network, and it is worse than saying nothing. This check must
  // stay ABOVE the capability fallback; a test pins it.
  if (sawSecurityElement) return const <String>[];

  // No RSN and no WPA element at all. Either the BSS is open, or it is WEP,
  // and only the Privacy bit tells those apart.
  if (capabilityInformation != null) {
    return <String>[
      (capabilityInformation & kCapabilityPrivacyBit) != 0 ? 'wep' : 'none',
    ];
  }

  return const <String>[];
}

/// True when a vendor-specific element body is the WPA1 element: OUI `00-50-F2`
/// followed by type byte `1`.
bool _isWpaVendorIe(Uint8List body) {
  if (body.length < 4) return false;
  for (int i = 0; i < 3; i++) {
    if (body[i] != kMsOui[i]) return false;
  }
  return body[3] == kWpaVendorType;
}

/// RSN AKM suite type → token, for selectors under the `00-0F-AC` OUI.
///
/// Types absent from this map are real and simply not classified yet (FT
/// variants that duplicate their base scheme are mapped to that scheme, since
/// fast transition is a roaming mechanism and not a different security scheme
/// to a user choosing a network).
const Map<int, String> _rsnAkmTokens = <int, String>{
  1: 'wpa2Enterprise', // 802.1X
  2: 'wpa2Personal', // PSK
  3: 'wpa2Enterprise', // FT-802.1X
  4: 'wpa2Personal', // FT-PSK
  5: 'wpa2Enterprise', // 802.1X-SHA256
  6: 'wpa2Personal', // PSK-SHA256
  8: 'wpa3Personal', // SAE
  9: 'wpa3Personal', // FT-SAE
  11: 'wpa3Enterprise', // 802.1X Suite-B
  12: 'wpa3Enterprise', // 802.1X Suite-B-192
  13: 'wpa2Enterprise', // FT-802.1X-SHA384
  18: 'owe', // Opportunistic Wireless Encryption
  24: 'wpa3Personal', // SAE-EXT-KEY
  25: 'wpa3Personal', // FT-SAE-EXT-KEY
};

/// WPA1 AKM suite type → token, for selectors under the `00-50-F2` OUI.
const Map<int, String> _wpaAkmTokens = <int, String>{
  1: 'wpaEnterprise', // 802.1X
  2: 'wpaPersonal', // PSK
};

/// Canonical output order: oldest scheme first, so a transition BSS reads
/// "wpa2Personal, wpa3Personal" every time rather than in set order.
const List<String> _tokenOrder = <String>[
  'none',
  'wep',
  'wpaPersonal',
  'wpaEnterprise',
  'wpa2Personal',
  'wpa2Enterprise',
  'wpa3Personal',
  'wpa3Enterprise',
  'owe',
];

List<String> _canonical(Set<String> tokens) => <String>[
      for (final String t in _tokenOrder)
        if (tokens.contains(t)) t,
    ];

/// Decodes AKM selectors out of an RSN-shaped body.
///
/// Layout, all counts little-endian:
///   version(2) groupCipher(4) pairwiseCount(2) pairwise(4*n)
///   akmCount(2) akm(4*n) [rsnCapabilities(2) ...]
///
/// EVERY step is bounds-checked before it reads, and any failure returns what
/// was decoded so far rather than throwing. A count field is attacker-controlled
/// and a 65535-entry claim must not become a 262 KB read.
Set<String> _tokensFromRsnBody(
  Uint8List body, {
  List<int> oui = kRsnOui,
  Map<int, String> akmMap = _rsnAkmTokens,
}) {
  final Set<String> out = <String>{};
  int i = 0;

  int? u16() {
    if (i + 2 > body.length) return null;
    final int v = body[i] | (body[i + 1] << 8);
    i += 2;
    return v;
  }

  if (u16() == null) return out; // version
  i += 4; // group cipher suite
  if (i > body.length) return out;

  final int? pairwiseCount = u16();
  if (pairwiseCount == null) return out;
  i += pairwiseCount * 4; // pairwise cipher suites, not needed for the token
  if (i > body.length) return out;

  final int? akmCount = u16();
  if (akmCount == null) return out;

  for (int k = 0; k < akmCount; k++) {
    if (i + 4 > body.length) return out; // truncated: keep what we have
    bool ouiMatches = true;
    for (int b = 0; b < 3; b++) {
      if (body[i + b] != oui[b]) ouiMatches = false;
    }
    final int type = body[i + 3];
    i += 4;
    if (!ouiMatches) continue; // a vendor AKM we do not classify
    final String? token = akmMap[type];
    if (token != null) out.add(token);
  }
  return out;
}
