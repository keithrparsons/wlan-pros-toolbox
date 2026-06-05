// WLAN Pi companion — typed models.
//
// EXPERIMENTAL / COMPANION MODE. These models are shaped from the PUBLIC
// wlanpi-core source (BSD-3, github.com/WLAN-Pi/wlanpi-core), read from the
// FastAPI route + Pydantic schema definitions on `main` (2026-06-05). The
// OpenAPI document itself is generated at runtime on the device — there is no
// static `openapi.json` checked into the repo — so these are hand-shaped from
// the same schemas FastAPI would serialize, NOT machine-generated. Field names
// below are source-accurate for auth / system / network_info; the PROFILER
// capability fields are the ONE place still unknown until Monday's on-device
// spike (see [ProfilerResult] and the Monday TODO in wlanpi_session.dart).
//
// All deserialization is defensive (`_asString`, `_asMap`) so a slightly
// different OS build never crashes the parse — it renders what it understands
// and leaves the rest. Nothing here touches PKM/; this is a live read model.

/// Source-accurate request body for `POST /api/v1/auth/token`.
///
/// From `wlanpi_core/schemas/auth/auth.py`:
/// ```python
/// class TokenRequest(BaseModel):
///     device_id: str
/// ```
class WlanPiTokenRequest {
  const WlanPiTokenRequest({required this.deviceId});

  final String deviceId;

  Map<String, dynamic> toJson() => <String, dynamic>{'device_id': deviceId};
}

/// Source-accurate response body for `POST /api/v1/auth/token`.
///
/// From `wlanpi_core/schemas/auth/auth.py`:
/// ```python
/// class Token(BaseModel):
///     access_token: str
///     token_type: str
/// ```
class WlanPiToken {
  const WlanPiToken({required this.accessToken, required this.tokenType});

  final String accessToken;

  /// Always `"bearer"` on the units inspected; carried verbatim regardless.
  final String tokenType;

  factory WlanPiToken.fromJson(Map<String, dynamic> json) => WlanPiToken(
        accessToken: _asString(json['access_token']),
        tokenType: _asString(json['token_type']),
      );

  bool get isBearer => tokenType.toLowerCase() == 'bearer';
}

/// Source-accurate model for `GET /api/v1/system/device/info`.
///
/// From `wlanpi_core/schemas/system/system.py`:
/// ```python
/// class DeviceInfo(BaseModel):
///     model: str
///     name: str
///     hostname: str
///     software_version: str
///     mode: str
/// ```
class WlanPiDeviceInfo {
  const WlanPiDeviceInfo({
    required this.model,
    required this.name,
    required this.hostname,
    required this.softwareVersion,
    required this.mode,
  });

  final String model;
  final String name;
  final String hostname;
  final String softwareVersion;
  final String mode;

  factory WlanPiDeviceInfo.fromJson(Map<String, dynamic> json) =>
      WlanPiDeviceInfo(
        model: _asString(json['model']),
        name: _asString(json['name']),
        hostname: _asString(json['hostname']),
        softwareVersion: _asString(json['software_version']),
        mode: _asString(json['mode']),
      );
}

/// Source-accurate model for `GET /api/v1/system/device/stats`.
///
/// From `wlanpi_core/schemas/system/system.py`:
/// ```python
/// class DeviceStats(BaseModel):
///     ip: str
///     cpu: str
///     ram: str
///     disk: str
///     cpu_temp: str
///     uptime: str
/// ```
class WlanPiDeviceStats {
  const WlanPiDeviceStats({
    required this.ip,
    required this.cpu,
    required this.ram,
    required this.disk,
    required this.cpuTemp,
    required this.uptime,
  });

  final String ip;
  final String cpu;
  final String ram;
  final String disk;
  final String cpuTemp;
  final String uptime;

  factory WlanPiDeviceStats.fromJson(Map<String, dynamic> json) =>
      WlanPiDeviceStats(
        ip: _asString(json['ip']),
        cpu: _asString(json['cpu']),
        ram: _asString(json['ram']),
        disk: _asString(json['disk']),
        cpuTemp: _asString(json['cpu_temp']),
        uptime: _asString(json['uptime']),
      );
}

/// Source-accurate model for `GET /api/v1/network/info/`.
///
/// From `wlanpi_core/schemas/network_info/network_info.py`, every field is a
/// free-form `dict` on the device side (the Pi assembles them from `ip`, `iw`,
/// LLDP/CDP, etc.), so we hold them as opaque maps and let the render layer pull
/// what it recognizes. We do NOT over-type these here — the device is the source
/// of truth for their inner shape, and Monday's spike captures real samples.
class WlanPiNetworkInfo {
  const WlanPiNetworkInfo({
    required this.interfaces,
    required this.wlanInterfaces,
    required this.eth0IpConfigInfo,
    required this.vlanInfo,
    required this.lldpNeighbourInfo,
    required this.cdpNeighbourInfo,
    required this.publicIp,
  });

  final Map<String, dynamic> interfaces;
  final Map<String, dynamic> wlanInterfaces;
  final Map<String, dynamic> eth0IpConfigInfo;
  final Map<String, dynamic> vlanInfo;
  final Map<String, dynamic> lldpNeighbourInfo;
  final Map<String, dynamic> cdpNeighbourInfo;
  final Map<String, dynamic> publicIp;

  factory WlanPiNetworkInfo.fromJson(Map<String, dynamic> json) =>
      WlanPiNetworkInfo(
        interfaces: _asMap(json['interfaces']),
        wlanInterfaces: _asMap(json['wlan_interfaces']),
        eth0IpConfigInfo: _asMap(json['eth0_ipconfig_info']),
        vlanInfo: _asMap(json['vlan_info']),
        lldpNeighbourInfo: _asMap(json['lldp_neighbour_info']),
        cdpNeighbourInfo: _asMap(json['cdp_neighbour_info']),
        publicIp: _asMap(json['public_ip']),
      );
}

/// The profiler differentiator — the decoded client capabilities the iOS/macOS
/// Wi-Fi APIs block. This is the flagship view.
///
/// SCHEMA STATUS — STUBBED / UNCONFIRMED. The profiler routes are confirmed from
/// `wlanpi_core/api/api_v1/endpoints/profiler_api.py`:
///   POST /api/v1/profiler/start   -> schemas.Start  ({"success": bool})
///   POST /api/v1/profiler/stop    -> schemas.Stop
///   GET  /api/v1/profiler/status  -> schemas.Status
/// But the wlanpi-profiler README documents that the DECODED CLIENT CAPABILITY
/// payload (40+ fields: channel width, MCS, spatial streams, 802.11k/r/v/w/mc,
/// bands, WPA3/SAE, max power, etc.) is written by wlanpi-profiler to per-client
/// JSON files. The EXACT field names of that decoded payload, and how the
/// `/profiler/status` route surfaces them to an external client, are NOT pinned
/// from public source. The fields below are a PLACEHOLDER SHAPE drawn from the
/// profiler's documented capability set; Monday's on-device spike replaces them
/// with the real keys (see Monday TODO #5 in wlanpi_session.dart).
class ProfilerClientCapabilities {
  const ProfilerClientCapabilities({
    required this.clientMac,
    required this.maxChannelWidthMhz,
    required this.maxSpatialStreams,
    required this.maxMcs,
    required this.bands,
    required this.supports11k,
    required this.supports11r,
    required this.supports11v,
    required this.supports11w,
    required this.wpa3Sae,
    required this.rawCapabilities,
  });

  /// MAC of the client that associated to the profiler AP. Mask in any UI that
  /// is shared/screenshotted; treated as semi-sensitive.
  final String clientMac;

  /// Max channel width the client signalled (20/40/80/160 MHz).
  final int? maxChannelWidthMhz;

  /// Max spatial streams (1–8) advertised.
  final int? maxSpatialStreams;

  /// Highest MCS index advertised.
  final int? maxMcs;

  /// Bands the client showed capability on, e.g. ["2.4 GHz", "5 GHz", "6 GHz"].
  final List<String> bands;

  final bool? supports11k;
  final bool? supports11r;
  final bool? supports11v;
  final bool? supports11w;

  /// WPA3 / SAE support.
  final bool? wpa3Sae;

  /// The full decoded capability map, kept opaque so nothing is lost between the
  /// placeholder shape above and the real device payload Monday captures.
  final Map<String, dynamic> rawCapabilities;

  /// PLACEHOLDER PARSE. Reads the candidate key names defensively; when the real
  /// device keys are known (Monday), update the key strings here only.
  factory ProfilerClientCapabilities.fromJson(Map<String, dynamic> json) =>
      ProfilerClientCapabilities(
        clientMac: _asString(json['mac'] ?? json['client_mac']),
        maxChannelWidthMhz:
            _asIntOrNull(json['channel_width'] ?? json['max_channel_width']),
        maxSpatialStreams:
            _asIntOrNull(json['spatial_streams'] ?? json['max_streams']),
        maxMcs: _asIntOrNull(json['max_mcs'] ?? json['mcs']),
        bands: _asStringList(json['bands']),
        supports11k: _asBoolOrNull(json['dot11k'] ?? json['11k']),
        supports11r: _asBoolOrNull(json['dot11r'] ?? json['11r']),
        supports11v: _asBoolOrNull(json['dot11v'] ?? json['11v']),
        supports11w: _asBoolOrNull(json['dot11w'] ?? json['11w']),
        wpa3Sae: _asBoolOrNull(json['wpa3'] ?? json['sae']),
        rawCapabilities: Map<String, dynamic>.from(json),
      );
}

/// Lifecycle of a profiler run, modeled as a job (start -> poll -> result).
enum ProfilerRunState {
  /// No run started yet.
  idle,

  /// `POST /profiler/start` accepted; waiting for a client to associate.
  waitingForClient,

  /// A client associated and capabilities were decoded.
  complete,

  /// The run was stopped or timed out without a result.
  stopped,
}

/// A single profiler run and its decoded result, if any.
class ProfilerResult {
  const ProfilerResult({
    required this.state,
    this.capabilities,
    this.message,
  });

  final ProfilerRunState state;
  final ProfilerClientCapabilities? capabilities;

  /// Optional human-readable status from the device (e.g. "listening on chan 36").
  final String? message;

  bool get hasResult => capabilities != null;
}

// ---------------------------------------------------------------------------
// Defensive coercion helpers — never throw on a slightly-different device build.
// ---------------------------------------------------------------------------

String _asString(Object? v) => v == null ? '' : v.toString();

Map<String, dynamic> _asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

int? _asIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

bool? _asBoolOrNull(Object? v) {
  if (v == null) return null;
  if (v is bool) return v;
  final String s = v.toString().toLowerCase();
  if (s == 'true' || s == 'yes' || s == 'supported' || s == '1') return true;
  if (s == 'false' || s == 'no' || s == 'unsupported' || s == '0') return false;
  return null;
}

List<String> _asStringList(Object? v) {
  if (v is List) return v.map((Object? e) => e.toString()).toList();
  if (v is String && v.isNotEmpty) return <String>[v];
  return <String>[];
}
