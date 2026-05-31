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
//   * band = derived from channel    (2.4 / 5 / 6 GHz; see [WiFiBand.fromChannel])
//   * channel width is NOT in the harvested field set → it is honestly marked
//     UNAVAILABLE. We never fabricate a width.

import 'dart:convert';

import 'package:flutter/foundation.dart';

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
  /// The 2.4 GHz and 6 GHz channel-number ranges OVERLAP (e.g. ch 1–13 exist in
  /// both bands), so a channel number alone is ambiguous in that low range. The
  /// harvested data does not include a center frequency to disambiguate, so we
  /// use the documented, practical mapping:
  ///   * 1–14    → 2.4 GHz   (the classic 2.4 GHz channel set; 14 is JP-only)
  ///   * 36–177  → 5 GHz     (U-NII-1 through U-NII-4; 165/169/173/177 included)
  ///   * 181–233 → 6 GHz     (the unambiguous upper 6 GHz channels, incl. 197)
  /// 6 GHz channels 1–93 collide numerically with 2.4/5 GHz and CANNOT be told
  /// apart from a bare channel number; in that ambiguous low range we return the
  /// 2.4/5 GHz interpretation (the overwhelmingly common case for a value that
  /// low) and never silently claim 6 GHz. The honest "derived" label on the
  /// screen makes clear the band is computed, not reported.
  ///
  /// Returns null for a channel number outside every known Wi-Fi range.
  static WiFiBand? fromChannel(int? channel) {
    if (channel == null) return null;
    if (channel >= 1 && channel <= 14) return WiFiBand.band24;
    if (channel >= 36 && channel <= 177) return WiFiBand.band5;
    // 6 GHz uses channels 1..233; only the upper range is numerically
    // unambiguous against 2.4/5 GHz. ch 197 (a real Wi-Fi 7 / 6 GHz channel,
    // per the TICKET-02 sample payload) lands here.
    if (channel >= 181 && channel <= 233) return WiFiBand.band6;
    return null;
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

    return WiFiDetails(
      ssid: pickString(<String>['SSID']),
      bssid: pickString(<String>['BSSID']),
      channel: pickInt(<String>['Channel', 'Channel Number', 'channelNumber']),
      rssi: pickInt(<String>['RSSI']),
      noise: pickInt(<String>['Noise']),
      standard: pickString(<String>['Standard', 'Wi-Fi Standard', 'wifiStandard']),
      rxRate: pickInt(<String>['RX Rate', 'rxRate', 'RX']),
      txRate: pickInt(<String>['TX Rate', 'txRate', 'TX']),
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
      other.txRate == txRate;

  @override
  int get hashCode => Object.hash(
        ssid,
        bssid,
        channel,
        rssi,
        noise,
        standard,
        rxRate,
        txRate,
      );

  @override
  String toString() =>
      'WiFiDetails(ssid: $ssid, bssid: $bssid, channel: $channel, '
      'rssi: $rssi, noise: $noise, snr: $snr, band: ${band?.label}, '
      'standard: $standard, rxRate: $rxRate, txRate: $txRate)';
}
