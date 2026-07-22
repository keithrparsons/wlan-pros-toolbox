// Wi-Fi Details — normalized connected-AP model (TICKET-02).
//
// The single, cross-platform model the "Wi-Fi Details" screen renders. The iOS
// data path (the only one wired today) is the companion Shortcut → native
// `ReceiveWiFiDetailsIntent` → App Group handoff: the Shortcut harvests the
// connected AP's RF metrics with the stock "Get Network Details" action,
// serializes them to a JSON object, and hands that JSON to Dart. macOS /
// Android / Windows adapters land in later tickets and feed this same model.
//
// FIELD CONTRACT (the canonical key set the published Shortcut emits — the
// working device-verified shortcut uses these capitalized human keys):
//   SSID, BSSID, Channel, RSSI, Noise, Standard, RX Rate, TX Rate
// We ALSO match case-insensitively (and tolerate a few documented spelling
// variants) so a hand-built Shortcut still populates the screen. Every field is
// nullable: the Shortcut may omit any of them (and the location-gating test —
// TICKET-01 — proved any subset can be absent), so the model tolerates a missing
// field rather than guessing.
//
// DERIVED VALUES (computed app-side, never harvested):
//   * snr  = rssi − noise            (dB)
//   * band = derived from channel    (2.4 / 5 / 6 GHz; resolved against the
//     app's verified channel plan — see [WiFiBand.fromChannel]. Marked
//     "(derived)" only when the channel number is genuinely ambiguous across
//     bands — see [WiFiBand.bandFromChannelIsAmbiguous].)
//   * channel width is NOT in the harvested field set → it is honestly marked
//     UNAVAILABLE. We never fabricate a width.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/channel_frequency_data.dart'
    show k24Channels, k5Channels, k6Channels;

/// The frequency band a channel sits in. Derived from the channel number — the
/// harvested field set carries no band, so this is the only source.
enum WiFiBand {
  band24('2.4 GHz'),
  band5('5 GHz'),
  band6('6 GHz');

  const WiFiBand(this.label);

  /// Human label for the screen (e.g. "5 GHz").
  final String label;

  /// Derive the band from a Wi-Fi channel number.
  ///
  /// A bare channel number is USUALLY unambiguous — most numbers are valid in
  /// exactly one band. We resolve against the app's own verified channel plan
  /// ([k24Channels], [k5Channels], [k6Channels] in channel_frequency_data.dart,
  /// primary-source-verified by Pax against IEEE 802.11 + FCC), so a genuine
  /// 6 GHz channel like 37/53/69/85/101/117/133 resolves to 6 GHz — NOT to
  /// "5 GHz" as the old 36–177 range hack did (those numbers are not valid
  /// 5 GHz channels at all).
  ///
  /// The only GENUINELY ambiguous numbers appear in two bands' valid sets:
  ///   * 1, 2, 5, 9, 13   → 2.4 GHz vs 6 GHz  (default: 2.4 GHz)
  ///   * 149,153,157,161,165,169,173,177 → 5 GHz vs 6 GHz (default: 5 GHz)
  /// (Channel 2 is ambiguous because the app's 6 GHz plan includes the special
  /// 5935 MHz guard channel 2; the brief listed 2 as 2.4-GHz-only — see the
  /// logged discrepancy. We default it to 2.4 GHz and mark it derived.)
  /// For an ambiguous number we return the lower-band interpretation — the
  /// overwhelmingly common real case — and NEVER silently claim 6 GHz. The
  /// [bandFromChannelIsAmbiguous] predicate flags exactly these so the screen
  /// shows the honest "(derived)" asterisk ONLY when the band is a real guess.
  ///
  /// Returns null for a channel number in no band's valid set.
  static WiFiBand? fromChannel(int? channel) {
    if (channel == null) return null;
    // Order matters: it also encodes the ambiguous-channel defaults. A number
    // in 2.4 GHz's set wins over 6 GHz (1/2/5/9/13 → 2.4 GHz); a number in
    // 5 GHz's set wins over 6 GHz (149..177 → 5 GHz). A number only in the
    // 6 GHz set (e.g. 37, 69, 197) resolves to 6 GHz with certainty.
    if (k24Channels.contains(channel)) return WiFiBand.band24;
    if (k5Channels.contains(channel)) return WiFiBand.band5;
    if (k6Channels.contains(channel)) return WiFiBand.band6;
    return null;
  }

  /// True when [channel]'s number alone cannot pin the band — it is a valid
  /// channel in MORE THAN ONE band's plan, so the band [fromChannel] returns is
  /// a best-effort default, not a certainty. This is the ONLY case where a
  /// channel-derived band should wear the "(derived)" asterisk: an unambiguous
  /// number (e.g. 36, 69, 197) yields a band that is computed but CERTAIN.
  ///
  /// Ambiguous numbers, per the app's verified channel plan:
  ///   * 1, 2, 5, 9, 13 — in both 2.4 GHz and 6 GHz.
  ///   * 149,153,157,161,165,169,173,177 — in both 5 GHz and 6 GHz.
  /// Returns false for null or an off-plan number.
  static bool bandFromChannelIsAmbiguous(int? channel) {
    if (channel == null) return false;
    int bandsContaining = 0;
    if (k24Channels.contains(channel)) bandsContaining++;
    if (k5Channels.contains(channel)) bandsContaining++;
    if (k6Channels.contains(channel)) bandsContaining++;
    return bandsContaining > 1;
  }
}

/// A normalized snapshot of the connected access point's RF metrics.
///
/// Immutable. Built from the Shortcut's JSON via [WiFiDetails.fromJsonString]
/// (which never throws) or [WiFiDetails.fromMap]. Derived values ([snr], [band])
/// are computed on construction from the parsed fields.
@immutable
class WiFiDetails {
  const WiFiDetails({
    this.ssid,
    this.bssid,
    this.channel,
    this.rssi,
    this.noise,
    this.standard,
    this.rxRate,
    this.txRate,
    this.ipv4Local,
    this.ipv6Local,
    this.cellCarrier,
    this.cellRat,
    this.cellSignalBars,
    this.payloadVersion,
    this.reachUrl,
    this.reachOk,
    this.reachMs,
  });

  /// Network name. May be null if the Shortcut omitted it.
  final String? ssid;

  /// AP MAC address. May be null if the Shortcut omitted it.
  final String? bssid;

  /// Channel number (e.g. 36, 149, 197). Tolerant int parse; null when absent
  /// or non-numeric.
  final int? channel;

  /// Received signal strength in dBm (negative). Null when absent.
  final int? rssi;

  /// Noise floor in dBm (negative). Null when absent.
  final int? noise;

  /// Wi-Fi standard / PHY generation string as emitted (e.g.
  /// "802.11be - Wi-Fi 7"). Kept verbatim — it is descriptive text, not math.
  final String? standard;

  /// RX data rate in Mbps. Null when absent.
  final int? rxRate;

  /// TX data rate in Mbps. Null when absent.
  final int? txRate;

  // ── Orb-parity OPTIONAL fields (all nullable; absent → render nothing) ──────
  //
  // These extend the harvested field set with the connection-context data an
  // Orb-style combined payload carries alongside the RF metrics. NONE of them
  // populate until the companion Shortcut is updated (a separate track) to emit
  // them; every one is nullable and the screen renders nothing when it is
  // absent, so the app behaves IDENTICALLY to today under the current Shortcut.
  // The parser accepts BOTH our own capitalized-human keys AND the Orb-style
  // snake_case keys ([fromMap]).

  /// Device's local IPv4 address on this link (e.g. "192.168.1.42"). Null when
  /// absent. Orb key: `ipv4_local`.
  final String? ipv4Local;

  /// Device's local IPv6 address on this link. Null when absent. Orb key:
  /// `ipv6_local`.
  final String? ipv6Local;

  /// Cellular carrier / operator name (e.g. "Verizon"), when the combined
  /// payload also carries the cellular slice. Null when absent. Orb key:
  /// `cell_carrier_name`. Descriptive text, kept verbatim.
  final String? cellCarrier;

  /// Cellular radio access technology label (e.g. "LTE", "5G NR"), verbatim.
  /// Null when absent. Orb key: `cell_rat`.
  final String? cellRat;

  /// Cellular signal bars — a coarse 0-to-4 status-bar indicator, NOT a dBm /
  /// RSRP / RSRQ value and never to be presented as one (the platform exposes
  /// no raw cellular signal to apps). Clamped to 0..4 on parse; null when
  /// absent. Orb key: `cell_signal_bars`.
  final int? cellSignalBars;

  /// Payload schema/version string the emitting Shortcut stamps, for
  /// forward-compatibility diagnostics. Null when absent. Orb key: `version`.
  final String? payloadVersion;

  // Reachability result — the internet-reachability probe the combined payload
  // reports. These keys are NEW (no Orb equivalent); the companion Shortcut
  // will be updated separately to emit them. Canonical keys:
  //   reachUrl → "Reachability URL"  / reach_url
  //   reachOk  → "Reachability OK"   / reach_ok   (true/false/1/0/yes/no)
  //   reachMs  → "Reachability Ms"   / reach_ms   (round-trip milliseconds)
  // Together they let the screen say "internet is reachable / not reachable"
  // WITHOUT ever blaming the Wi-Fi for an upstream outage (the standing rule).

  /// The URL the reachability probe targeted (e.g. a keyless HTTPS endpoint).
  /// Null when absent. Key: `reach_url` / "Reachability URL".
  final String? reachUrl;

  /// Whether the internet was reachable on the probe. `true` reachable,
  /// `false` not reachable, `null` when the payload carried no reachability
  /// result. Key: `reach_ok` / "Reachability OK".
  final bool? reachOk;

  /// Round-trip time of the reachability probe in milliseconds. Null when
  /// absent. Key: `reach_ms` / "Reachability Ms".
  final int? reachMs;

  /// True when the payload carried an internet-reachability RESULT (a definite
  /// reachable/not-reachable verdict). Drives whether the Internet card renders.
  bool get hasReachability => reachOk != null;

  /// Signal-to-noise ratio in dB, computed as `rssi − noise`. Null unless BOTH
  /// rssi and noise are present (computing it from a missing input would be a
  /// fabricated number).
  int? get snr {
    final int? r = rssi;
    final int? n = noise;
    if (r == null || n == null) return null;
    return r - n;
  }

  /// Frequency band derived from [channel]. Null when the channel is absent or
  /// outside every known Wi-Fi range. NEVER harvested — always derived.
  WiFiBand? get band => WiFiBand.fromChannel(channel);

  /// Channel width is NOT part of the harvested field set ("Get Network
  /// Details" does not return it), so it is structurally unavailable. This is
  /// always false today; it exists so the screen reads the availability from the
  /// model rather than hardcoding the honest-unavailable copy. A future adapter
  /// that does expose width would set a real value and flip this.
  bool get hasChannelWidth => false;

  /// `true` when at least one field parsed — i.e. the payload carried real data.
  /// An all-null model means the Shortcut delivered an empty/garbage object and
  /// the screen should show its empty state, not a grid of "Not available".
  bool get hasAnyData =>
      ssid != null ||
      bssid != null ||
      channel != null ||
      rssi != null ||
      noise != null ||
      standard != null ||
      rxRate != null ||
      txRate != null;

  /// Parse a JSON string from the Shortcut into a [WiFiDetails]. Returns null
  /// when the string is not a JSON object (malformed, an array, a scalar) —
  /// callers treat null as "no valid payload yet" and show the empty state.
  /// Never throws.
  static WiFiDetails? fromJsonString(String jsonString) {
    if (jsonString.trim().isEmpty) return null;
    try {
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is! Map) return null;
      return WiFiDetails.fromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Build from an already-decoded map. Matches keys CASE-INSENSITIVELY against
  /// the canonical contract (`SSID, BSSID, Channel, RSSI, Noise, Standard,
  /// RX Rate, TX Rate`) plus documented spelling variants, so both the published
  /// Shortcut and a hand-built one populate the model.
  factory WiFiDetails.fromMap(Map<dynamic, dynamic> map) {
    // Lower-case every key once so lookups are O(1) and case-insensitive.
    final Map<String, dynamic> ci = <String, dynamic>{};
    map.forEach((dynamic k, dynamic v) {
      if (k != null) ci[k.toString().toLowerCase()] = v;
    });

    String? pickString(List<String> keys) {
      for (final String key in keys) {
        final dynamic v = ci[key.toLowerCase()];
        if (v == null) continue;
        final String s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
      return null;
    }

    int? pickInt(List<String> keys) {
      final String? s = pickString(keys);
      if (s == null) return null;
      // Tolerant: strip a trailing unit or stray non-numeric chars the Shortcut
      // might append (e.g. "-45 dBm", "864 Mbps"), keep sign + digits.
      final RegExp numRe = RegExp(r'-?\d+');
      final Match? m = numRe.firstMatch(s);
      if (m == null) return null;
      return int.tryParse(m.group(0)!);
    }

    // Tolerant boolean parse for the reachability verdict. Accepts the JSON
    // literals true/false, the numeric 1/0, and the string forms
    // true/false/yes/no/1/0 (case-insensitive). Returns null for anything else
    // so an unparseable value reads as "no reachability result", never a
    // fabricated verdict.
    bool? pickBool(List<String> keys) {
      for (final String key in keys) {
        final dynamic v = ci[key.toLowerCase()];
        if (v == null) continue;
        if (v is bool) return v;
        final String s = v.toString().trim().toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'no') return false;
      }
      return null;
    }

    // Cellular signal bars are a coarse 0-to-4 indicator; clamp so a stray
    // out-of-range value never renders as "7 of 4".
    int? bars = pickInt(<String>['Cell Signal Bars', 'cell_signal_bars']);
    if (bars != null) bars = bars.clamp(0, 4);

    return WiFiDetails(
      ssid: pickString(<String>['SSID']),
      bssid: pickString(<String>['BSSID']),
      channel: pickInt(<String>['Channel', 'Channel Number', 'channelNumber']),
      rssi: pickInt(<String>['RSSI']),
      noise: pickInt(<String>['Noise']),
      standard: pickString(<String>['Standard', 'Wi-Fi Standard', 'wifiStandard']),
      rxRate: pickInt(<String>['RX Rate', 'rxRate', 'RX']),
      txRate: pickInt(<String>['TX Rate', 'txRate', 'TX']),
      ipv4Local: pickString(<String>['IPv4 Local', 'ipv4_local']),
      ipv6Local: pickString(<String>['IPv6 Local', 'ipv6_local']),
      cellCarrier: pickString(<String>['Cell Carrier', 'cell_carrier_name']),
      cellRat: pickString(<String>['Cell RAT', 'cell_rat']),
      cellSignalBars: bars,
      payloadVersion: pickString(<String>['Payload Version', 'version']),
      reachUrl: pickString(<String>['Reachability URL', 'reach_url']),
      reachOk: pickBool(<String>['Reachability OK', 'reach_ok']),
      reachMs: pickInt(<String>['Reachability Ms', 'reach_ms']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WiFiDetails &&
      other.ssid == ssid &&
      other.bssid == bssid &&
      other.channel == channel &&
      other.rssi == rssi &&
      other.noise == noise &&
      other.standard == standard &&
      other.rxRate == rxRate &&
      other.txRate == txRate &&
      other.ipv4Local == ipv4Local &&
      other.ipv6Local == ipv6Local &&
      other.cellCarrier == cellCarrier &&
      other.cellRat == cellRat &&
      other.cellSignalBars == cellSignalBars &&
      other.payloadVersion == payloadVersion &&
      other.reachUrl == reachUrl &&
      other.reachOk == reachOk &&
      other.reachMs == reachMs;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        ssid,
        bssid,
        channel,
        rssi,
        noise,
        standard,
        rxRate,
        txRate,
        ipv4Local,
        ipv6Local,
        cellCarrier,
        cellRat,
        cellSignalBars,
        payloadVersion,
        reachUrl,
        reachOk,
        reachMs,
      ]);

  @override
  String toString() =>
      'WiFiDetails(ssid: $ssid, bssid: $bssid, channel: $channel, '
      'rssi: $rssi, noise: $noise, snr: $snr, band: ${band?.label}, '
      'standard: $standard, rxRate: $rxRate, txRate: $txRate, '
      'ipv4Local: $ipv4Local, ipv6Local: $ipv6Local, '
      'cellCarrier: $cellCarrier, cellRat: $cellRat, '
      'cellSignalBars: $cellSignalBars, payloadVersion: $payloadVersion, '
      'reachUrl: $reachUrl, reachOk: $reachOk, reachMs: $reachMs)';
}
