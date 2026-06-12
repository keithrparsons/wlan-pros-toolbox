// Connected-AP — the normalized, cross-platform model the one Wi-Fi Information
// tool renders, regardless of which platform supplied the reading.
//
// TICKET-04 consolidates two platform-specific Wi-Fi tools into one. The two
// data sources stay live behind a platform-adapter seam (see
// [WifiInfoAdapter]) and both map their native payload into THIS model:
//
//   * macOS → CoreWLAN  (WifiInfoService / WifiInfoChannel.swift) → [fromWifiInfo]
//   * iOS   → Shortcuts  (WiFiDetailsBridge / ToolboxAppIntents.swift) →
//             [fromWifiDetails]
//   * Android → WifiManager (MainActivity.kt channel) → [fromAndroidWifiInfo]
//   * Windows → Native Wifi (wlanapi.dll, pure Dart FFI via win32 — NO C++
//             channel) → [fromWindowsWifiInfo]
//
// desktop Linux is a clean seam only (the adapter reports it unsupported); it
// slots a future native source into this same model.
//
// Every field is nullable: each platform exposes a different subset, and a
// reading can legitimately omit any field. The screen renders a missing field
// as an honest "Unavailable" row (per GL-008 + GL-005) — never a fabricated
// value, never a silent drop. Two availability flags ([rxRateAvailable],
// [channelWidthAvailable]) distinguish "this platform never exposes this datum"
// from "absent this reading", so the UI can show a precise per-field reason.

import 'wifi_details.dart';
import 'wifi_info_service.dart';
import 'wifi_security.dart';

/// A normalized snapshot of the connected access point, independent of the
/// platform that produced it. Immutable.
class ConnectedAp {
  const ConnectedAp({
    this.ssid,
    this.bssid,
    this.rssiDbm,
    this.noiseDbm,
    this.snrDb,
    this.txRateMbps,
    this.rxRateMbps,
    this.channel,
    this.channelWidthMhz,
    this.band,
    this.standard,
    this.countryCode,
    this.interfaceName,
    this.hardwareAddress,
    this.securityType,
    this.poweredOn = true,
    this.rxRateAvailable = false,
    this.channelWidthAvailable = false,
    this.bandDerived = false,
    this.snrDerived = false,
    this.securityAvailable = false,
  });

  /// Connected network name. Null when not connected, hidden, or omitted.
  final String? ssid;

  /// Connected access point MAC (BSSID). Null when hidden or omitted.
  final String? bssid;

  /// Received signal strength in dBm (negative). Null when unavailable.
  final int? rssiDbm;

  /// Noise floor in dBm (negative). Null when unavailable.
  final int? noiseDbm;

  /// Signal-to-noise ratio in dB. Null unless both RSSI and noise are present
  /// (computing it from a missing input would be a fabricated number).
  final int? snrDb;

  /// Transmit rate in Mbps. Null when unavailable.
  final double? txRateMbps;

  /// Receive rate in Mbps. Null when unavailable. See [rxRateAvailable] to
  /// distinguish "this platform never exposes Rx rate" from "absent this read".
  final double? rxRateMbps;

  /// Primary channel number. Null when unavailable.
  final int? channel;

  /// Channel width in MHz (20/40/80/160). Null when unavailable. See
  /// [channelWidthAvailable] to distinguish "platform never exposes it".
  final int? channelWidthMhz;

  /// Band label ("2.4 GHz", "5 GHz", "6 GHz"). Null when unknown.
  final String? band;

  /// Wi-Fi standard / PHY generation label (e.g. "802.11ax (Wi-Fi 6)"). Null
  /// when unknown.
  final String? standard;

  /// Regulatory country code. Null when unavailable.
  final String? countryCode;

  /// BSD interface name (e.g. "en0"). Null when unavailable (iOS does not
  /// expose it through the Shortcut path).
  final String? interfaceName;

  /// Interface hardware (MAC) address. Null when unavailable.
  final String? hardwareAddress;

  /// The connected network's security type, normalized across platforms. Null
  /// when this reading carried no security info (or the platform/permission did
  /// not supply it — see [securityAvailable] to tell those apart). macOS reports
  /// the fine WPA2-vs-WPA3 truth; iOS reports only the coarse Personal /
  /// Enterprise / Open distinction (see [WifiSecurity.isPersonalCoarse]).
  final WifiSecurity? securityType;

  /// Whether THIS platform can ever expose the security type. macOS (CoreWLAN)
  /// and iOS (NEHotspotNetwork, entitlement + Location gated) both can; an
  /// unsupported platform cannot. When false the UI shows a precise
  /// "Not exposed by `<platform>`" reason rather than a generic blank.
  final bool securityAvailable;

  /// Whether the Wi-Fi radio is powered on. Defaults true for sources that do
  /// not report a radio-power state (the iOS Shortcut only runs while connected).
  final bool poweredOn;

  /// Whether THIS platform can ever expose the Rx rate. macOS public CoreWLAN
  /// cannot; iOS can. When false the UI shows a "Not exposed by `<platform>`"
  /// reason rather than a generic "Unavailable".
  final bool rxRateAvailable;

  /// Whether THIS platform can ever expose the channel width. The iOS Shortcut
  /// harvest does not return it; macOS CoreWLAN does. When false the UI shows a
  /// precise "Not reported by `<platform>`" reason.
  final bool channelWidthAvailable;

  /// Whether [band] was computed app-side (true on iOS, where band is derived
  /// from the channel number) rather than read from the source (macOS reports
  /// it directly). Drives the honest "derived" caption.
  final bool bandDerived;

  /// Whether [snrDb] was computed app-side (rssi − noise). True on the iOS path;
  /// macOS reports SNR directly. Drives the honest "derived" caption.
  final bool snrDerived;

  /// Maps the macOS CoreWLAN snapshot into the normalized model.
  ///
  /// macOS reports band and SNR directly (not derived), exposes channel width
  /// and country/interface/hardware address, but public CoreWLAN does NOT expose
  /// the Rx rate — so [rxRateAvailable] is false and the UI says so.
  factory ConnectedAp.fromWifiInfo(WifiInfo info) {
    return ConnectedAp(
      ssid: info.ssid,
      bssid: info.bssid,
      rssiDbm: info.rssiDbm,
      noiseDbm: info.noiseDbm,
      snrDb: info.snrDb,
      txRateMbps: info.txRateMbps,
      rxRateMbps: null,
      channel: info.channel,
      channelWidthMhz: info.channelWidthMhz,
      band: info.band,
      standard: _macStandardLabel(info.phyMode, info.band),
      countryCode: info.countryCode,
      interfaceName: info.interfaceName,
      hardwareAddress: info.hardwareAddress,
      // macOS CoreWLAN CWInterface.security() gives the fine WPA2-vs-WPA3 truth.
      securityType: WifiSecurityClassifier.classify(info.securityToken),
      poweredOn: info.poweredOn,
      // macOS public CoreWLAN never exposes Rx rate or Tx power.
      rxRateAvailable: false,
      // macOS DOES expose channel width.
      channelWidthAvailable: true,
      bandDerived: false,
      snrDerived: false,
      // macOS exposes the security type whenever an interface is present.
      securityAvailable: true,
    );
  }

  /// Maps the Android WifiManager + ConnectivityManager snapshot into the
  /// normalized model.
  ///
  /// Android exposes RSSI, the Tx (link) rate, frequency (→ channel/band), the
  /// Wi-Fi standard (API 30+ via `WifiInfo.getWifiStandard`), the security type
  /// (derived from the matching ScanResult capabilities), and channel width
  /// (from the matching `ScanResult.channelWidth`, Location-gated). The public
  /// Android API does NOT expose the noise floor, so SNR cannot be computed —
  /// both stay null and [snrDerived] is false (no estimate, GL-005). The Rx
  /// rate is read on API 30+ (`getRxLinkSpeedMbps`); when the platform returns
  /// the unknown sentinel it is null and [rxRateAvailable] reflects whether the
  /// platform can ever supply it. Android does not expose the device Wi-Fi MAC
  /// to apps (returns the fixed `02:00:00:00:00:00`), so [hardwareAddress] is
  /// the native side's honest null rather than that sentinel.
  factory ConnectedAp.fromAndroidWifiInfo(WifiInfo info) {
    return ConnectedAp(
      ssid: info.ssid,
      bssid: info.bssid,
      rssiDbm: info.rssiDbm,
      // Android public API exposes no noise floor; SNR therefore cannot be
      // computed and is never estimated.
      noiseDbm: info.noiseDbm,
      snrDb: info.snrDb,
      txRateMbps: info.txRateMbps,
      // The native side reads Rx via WifiInfo.getRxLinkSpeedMbps() on API 30+
      // and passes it through `rxRateMbps` (null when the platform returns the
      // unknown sentinel -1, which many devices/links do). We surface the value
      // when present; when null the platform CAN still expose Rx in principle,
      // so rxRateAvailable stays true and the screen labels it a platform limit
      // for this reading rather than "not on this platform" (GL-005).
      rxRateMbps: info.rxRateMbps,
      channel: info.channel,
      channelWidthMhz: info.channelWidthMhz,
      band: info.band,
      standard: info.phyMode,
      countryCode: info.countryCode,
      interfaceName: info.interfaceName,
      hardwareAddress: info.hardwareAddress,
      // Security comes from the native ScanResult.capabilities match.
      securityType: WifiSecurityClassifier.classify(info.securityToken),
      poweredOn: info.poweredOn,
      // Android CAN expose Rx on API 30+; the row shows it when present, and a
      // precise "not in this reading" when the platform returns the unknown
      // sentinel — never "not on this platform".
      rxRateAvailable: true,
      // Channel width is read from the matching ScanResult.channelWidth (the
      // connected WifiInfo does not carry it). When the native side could not
      // read it (no scan match / no Location grant), it passes null and the row
      // says "Not reported". The 80+80 MHz case arrives as the sentinel 8080.
      channelWidthAvailable: info.channelWidthMhz != null,
      // Android reports the band/channel from the frequency directly (native
      // side), and never the noise floor, so neither is app-derived here.
      bandDerived: false,
      snrDerived: false,
      // Android exposes the security type whenever a scan match is found.
      securityAvailable: true,
    );
  }

  /// Maps the Windows Native Wifi (wlanapi.dll) snapshot into the normalized
  /// model. Mirrors [fromAndroidWifiInfo].
  ///
  /// Windows exposes a REAL dBm RSSI (`lRssi` from the BSS entry — not just the
  /// 0–100 signal quality), the Tx AND Rx link rates (`ulTxRate` / `ulRxRate`
  /// from the association attributes — a field macOS cannot supply), the PHY
  /// type (→ 802.11 standard), the channel + band (derived from the BSS center
  /// frequency), and the security type (from the auth algorithm in
  /// WLAN_SECURITY_ATTRIBUTES, classified by the shared [WifiSecurityClassifier]
  /// — the SAME fine WPA2-vs-WPA3 / Personal-vs-Enterprise truth macOS gives).
  ///
  /// The public Native Wifi API exposes NO noise floor, so SNR cannot be
  /// computed — both stay null and [snrDerived] is false (no estimate, GL-005),
  /// exactly the two fields Android omits. Channel WIDTH needs IE-blob parsing
  /// (HT/VHT/HE operation elements) deferred to device-time, so it arrives null
  /// and [channelWidthAvailable] rides false until that lands — the same honest
  /// "Not reported" posture Android uses when there is no scan match.
  factory ConnectedAp.fromWindowsWifiInfo(WifiInfo info) {
    return ConnectedAp(
      ssid: info.ssid,
      bssid: info.bssid,
      // Real dBm from the matching WLAN_BSS_ENTRY.lRssi; null when no BSS match.
      rssiDbm: info.rssiDbm,
      // Native Wifi exposes no noise floor; SNR therefore cannot be computed and
      // is never estimated.
      noiseDbm: info.noiseDbm,
      snrDb: info.snrDb,
      txRateMbps: info.txRateMbps,
      // Windows supplies the Rx rate (ulRxRate) — macOS does not. The reader
      // passes null only when the platform reports the rate as 0/unknown, never
      // a fabricated value.
      rxRateMbps: info.rxRateMbps,
      channel: info.channel,
      channelWidthMhz: info.channelWidthMhz,
      band: info.band,
      standard: _macStandardLabel(info.phyMode, info.band),
      countryCode: info.countryCode,
      interfaceName: info.interfaceName,
      hardwareAddress: info.hardwareAddress,
      // Auth algorithm from WLAN_SECURITY_ATTRIBUTES, mapped to a shared token.
      securityType: WifiSecurityClassifier.classify(info.securityToken),
      poweredOn: info.poweredOn,
      // Windows CAN expose Rx (ulRxRate) — the row shows it when present and a
      // precise "not in this reading" when the platform reports 0/unknown.
      rxRateAvailable: true,
      // Channel width is IE-derived and deferred; null until that lands, so the
      // row reads "Not reported" rather than guessing.
      channelWidthAvailable: info.channelWidthMhz != null,
      // The reader derives band/channel from the BSS center frequency on the
      // native (FFI) side and never the noise floor, so neither is app-derived
      // here — both arrive on the WifiInfo already resolved.
      bandDerived: false,
      snrDerived: false,
      // Windows exposes the security type whenever a connection is present.
      securityAvailable: true,
    );
  }

  /// Maps the iOS Shortcuts [WiFiDetails] payload into the normalized model.
  ///
  /// iOS exposes the Rx rate and reports SNR/band as APP-DERIVED (snr = rssi −
  /// noise; band from the channel number). The harvest action does NOT return
  /// channel width, so [channelWidthAvailable] is false and the UI says so.
  factory ConnectedAp.fromWifiDetails(WiFiDetails d) {
    return ConnectedAp(
      ssid: d.ssid,
      bssid: d.bssid,
      rssiDbm: d.rssi,
      noiseDbm: d.noise,
      snrDb: d.snr,
      txRateMbps: d.txRate?.toDouble(),
      rxRateMbps: d.rxRate?.toDouble(),
      channel: d.channel,
      channelWidthMhz: null,
      band: d.band?.label,
      standard: d.standard,
      countryCode: null,
      interfaceName: null,
      hardwareAddress: null,
      // The Shortcut does not carry the security type. iOS reads it from the
      // native NEHotspotNetwork channel and enriches this model via
      // [withSecurity]; until then it is null but [securityAvailable] is true so
      // the UI shows a "reading…" / honest-absent state rather than "not on this
      // platform".
      securityType: null,
      // The Shortcut only runs while connected; treat the radio as on.
      poweredOn: true,
      // iOS DOES expose Rx rate via "Get Network Details".
      rxRateAvailable: true,
      // The iOS harvest action does not return channel width.
      channelWidthAvailable: false,
      // On iOS both band and SNR are computed app-side.
      bandDerived: d.band != null,
      snrDerived: d.snr != null,
      // iOS CAN expose the (coarse) security type via NEHotspotNetwork, gated by
      // the Access Wi-Fi Information entitlement + Location permission.
      securityAvailable: true,
    );
  }

  /// Returns a copy with the security type filled in. Used by the iOS path,
  /// where the security token arrives from the native NEHotspotNetwork channel
  /// (a separate read from the Shortcut RF harvest) and is folded onto the
  /// Shortcut-derived model. A null [security] leaves the field unset (honest
  /// "not in this reading"). All other fields are preserved.
  ConnectedAp withSecurity(WifiSecurity? security) {
    return ConnectedAp(
      ssid: ssid,
      bssid: bssid,
      rssiDbm: rssiDbm,
      noiseDbm: noiseDbm,
      snrDb: snrDb,
      txRateMbps: txRateMbps,
      rxRateMbps: rxRateMbps,
      channel: channel,
      channelWidthMhz: channelWidthMhz,
      band: band,
      standard: standard,
      countryCode: countryCode,
      interfaceName: interfaceName,
      hardwareAddress: hardwareAddress,
      securityType: security ?? securityType,
      poweredOn: poweredOn,
      rxRateAvailable: rxRateAvailable,
      channelWidthAvailable: channelWidthAvailable,
      bandDerived: bandDerived,
      snrDerived: snrDerived,
      securityAvailable: securityAvailable,
    );
  }

  /// Overlays the richer RF of [other] onto this reading, field by field, taking
  /// a value from [other] only where this reading's own value is null (a
  /// non-destructive "fill the gaps" merge). Returns `this` unchanged when
  /// [other] is null.
  ///
  /// This unifies the COPY/technical source (a single one-shot link read taken at
  /// test-completion) with the LIVE sparkline source (the continuously-streamed
  /// sampler reading the sparklines bind to). On iOS the one-shot
  /// `WiFiDetailsBridge.readLatest()` can resolve before — or independently of —
  /// the live companion-Shortcut stream, so the one-shot model can lack RF the
  /// live card is already showing on screen. Folding the live reading onto the
  /// one-shot read makes "what's on screen is what's copied" (GL-005): the copy
  /// can only ever GAIN a field the platform genuinely reported live, never lose
  /// the native security/BSSID enrichment the one-shot read already carried.
  ///
  /// Existing (non-null) values WIN, so the native NEHotspotNetwork security/BSSID
  /// enrichment already folded onto [this] is never overwritten by a live sample
  /// that lacks it. The platform-availability flags (rxRateAvailable, etc.) are
  /// OR-ed so a "platform can expose this" signal from either source is kept.
  ConnectedAp mergedWith(ConnectedAp? other) {
    if (other == null) return this;
    final int? mergedRssi = rssiDbm ?? other.rssiDbm;
    final int? mergedNoise = noiseDbm ?? other.noiseDbm;
    return ConnectedAp(
      ssid: ssid ?? other.ssid,
      bssid: bssid ?? other.bssid,
      rssiDbm: mergedRssi,
      noiseDbm: mergedNoise,
      // Prefer a directly-reported SNR from either side; only fall back to a
      // derived value if both sides lack one but the inputs are now present.
      snrDb: snrDb ??
          other.snrDb ??
          ((mergedRssi != null && mergedNoise != null)
              ? mergedRssi - mergedNoise
              : null),
      txRateMbps: txRateMbps ?? other.txRateMbps,
      rxRateMbps: rxRateMbps ?? other.rxRateMbps,
      channel: channel ?? other.channel,
      channelWidthMhz: channelWidthMhz ?? other.channelWidthMhz,
      band: band ?? other.band,
      standard: standard ?? other.standard,
      countryCode: countryCode ?? other.countryCode,
      interfaceName: interfaceName ?? other.interfaceName,
      hardwareAddress: hardwareAddress ?? other.hardwareAddress,
      securityType: securityType ?? other.securityType,
      poweredOn: poweredOn,
      rxRateAvailable: rxRateAvailable || other.rxRateAvailable,
      channelWidthAvailable:
          channelWidthAvailable || other.channelWidthAvailable,
      // The "derived" captions only apply when the value itself came from the
      // side that derived it; keep this read's flag when it supplied the value,
      // otherwise inherit the contributing side's.
      bandDerived: band != null ? bandDerived : other.bandDerived,
      snrDerived: snrDb != null
          ? snrDerived
          : (other.snrDb != null
              ? other.snrDerived
              // We synthesized SNR from merged rssi/noise above → it is derived.
              : true),
      securityAvailable: securityAvailable || other.securityAvailable,
    );
  }

  /// True when at least one substantive field is present — i.e. a real reading
  /// arrived. An all-null model means the source delivered an empty payload and
  /// the screen should show its empty / waiting state, not a grid of
  /// "Unavailable".
  bool get hasAnyData =>
      ssid != null ||
      bssid != null ||
      rssiDbm != null ||
      noiseDbm != null ||
      txRateMbps != null ||
      rxRateMbps != null ||
      channel != null ||
      band != null ||
      standard != null;

  /// Renders the macOS PHY mode with both its 802.11 designation and its Wi-Fi
  /// generation, e.g. "802.11be (Wi-Fi 7)". The iOS path already supplies a
  /// formatted standard string, so this is macOS-only. The 6 GHz band
  /// distinguishes Wi-Fi 6E from Wi-Fi 6 (both 802.11ax). Pre-branding modes
  /// (a/b/g) have no Wi-Fi number, so only the 802.11 name shows. Returns null
  /// when the PHY mode is unknown.
  static String? _macStandardLabel(String? phyMode, String? band) {
    if (phyMode == null) return null;
    final String? generation = switch (phyMode) {
      '802.11be' => 'Wi-Fi 7',
      '802.11ax' => band == '6 GHz' ? 'Wi-Fi 6E' : 'Wi-Fi 6',
      '802.11ac' => 'Wi-Fi 5',
      '802.11n' => 'Wi-Fi 4',
      _ => null,
    };
    return generation == null ? phyMode : '$phyMode ($generation)';
  }
}
