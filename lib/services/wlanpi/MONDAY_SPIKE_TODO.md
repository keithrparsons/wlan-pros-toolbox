# WLAN Pi companion — Monday on-device spike TODO

This scaffold is **device-independent**. Everything that genuinely cannot be
confirmed without a running WLAN Pi (OS 3.x) is clearly STUBBED in code and
listed here. The spike's job is to capture the real artifacts so wiring the live
mode is mechanical. **Mask every secret before writing anything down.**

## What is already DONE (device-independent, in this branch)

- Typed models, **source-accurate** from public wlanpi-core schemas (`main`,
  2026-06-05): `WlanPiToken`, `WlanPiTokenRequest`, `WlanPiDeviceInfo`,
  `WlanPiDeviceStats`, `WlanPiNetworkInfo` — `lib/data/wlanpi/wlanpi_models.dart`.
- Confirmed routes + path prefixes (from the FastAPI source):
  - `POST  /api/v1/auth/token`            → `{access_token, token_type}`
  - `DELETE /api/v1/auth/token`           (revoke)
  - `POST  /api/v1/auth/signing_key`      (HMAC-gated)
  - `GET   /api/v1/system/device/info`    → DeviceInfo
  - `GET   /api/v1/system/device/stats`   → DeviceStats
  - `GET   /api/v1/system/device/model`   → DeviceModel
  - `GET   /api/v1/network/info/`         → NetworkInfo
  - `POST  /api/v1/profiler/start`        → `{success: bool}`
  - `GET   /api/v1/profiler/status`       → Status
  - `POST  /api/v1/profiler/stop`         → Stop
- HMAC **canonical-string** construction, implemented + unit-tested to match
  core/auth.py exactly: `"{METHOD}\n{PATH}\n{QUERY}\n{BODY}"`, header
  `X-Request-Signature`, HMAC-SHA256 hex.
- Version gate (`parseOpenApiVersion`, `isVersionSupported`, floor = OS 3.x).
- `Retry-After` parsing + capped exponential backoff (slowapi 429 handling).
- `WlanPiSession.send()` seam (auth headers + 401/429 mapping) ready for reads.
- Discovery/connection state machine + friendly screens for every phase.
- Profiler + system render scaffolds (render labeled SAMPLE data today).

## What the spike MUST capture (the STUBBED unknowns)

### 1. The full OpenAPI spec  ← single most valuable artifact
- Save `http://<wlanpi-ip>:31415/openapi.json` to the spike folder.
- Confirm the live endpoint set matches the source tree above; note any the
  device omits. This pins versions and can drive optional codegen.

### 2. Core/OS version
- Record `info.version` from the spec → confirms the 3.x floor is correct.

### 3. THE TOKEN HANDSHAKE — the #1 unknown
The request/response **shape** is confirmed (`{"device_id": "..."}` →
`{"access_token","token_type":"bearer"}`). The missing piece:
- **What does an EXTERNAL client present to be ISSUED that token?** core/auth.py
  shows: OTG bypasses auth, **localhost uses HMAC**, **external requires a valid
  JWT bearer** — and `signing_key` issuance is itself HMAC-gated. So there is a
  bootstrapping step. Capture exactly what it is:
  - A shared secret / key shown in the front-panel menu or web UI?
  - A pairing step? A `POST /auth/signing_key` exchange? Username/password?
- Capture the exact request that succeeds (masked), the token response, expiry,
  and refresh (if any).
- → Wire: `WlanPiSession.authenticate()` (currently throws `WlanPiNotYetWired`).

### 4. HMAC application to external calls
- Confirm whether external LAN calls need `X-Request-Signature` at all, or if
  bearer-only is sufficient (the code path suggests HMAC is the localhost path,
  but the bootstrap may require it). Confirm the **secret source** and the exact
  bytes signed (we already match the documented canonical form).
- → Wire: add `crypto` dep and replace the `computeHmacSignature` STUB body with
  `Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(canonical)).toString()`.
  Apply in `buildAuthHeaders` only where the spike says it's required.

### 5. Real profiler capability payload  ← the flagship field names
- Run a profiler, associate a client, capture a **completed-run** decoded
  capability JSON. The profiler writes per-client JSON (wlanpi-profiler); confirm
  how `/profiler/status` surfaces it to an external client.
- Record the **exact field names** for: channel width, MCS, spatial streams,
  802.11k/r/v/w/mc, bands, WPA3/SAE, max power, etc.
- → Update the placeholder parse keys in `ProfilerClientCapabilities.fromJson`
  (currently candidate keys like `channel_width`/`spatial_streams`). Swap
  `kSampleProfilerResult` for the live poll.

### 6. Per-endpoint real samples (system / network_info / profiler / auth)
- Capture real JSON for `system/device/info`, `system/device/stats`,
  `network/info/`, profiler start/status/stop, and the auth flow — as fixtures
  for the live-read tests.

### 7. Rate-limit behavior
- Hit an endpoint in a tight loop until 429; record `Retry-After` presence,
  the window, and the body. Tune `backoffForAttempt` to observed limits.

### 8. mDNS discoverability
- Confirm `wlanpi-*.local:31415` resolves via mDNS on the test network, or that
  it is filtered (then manual entry stays the primary path). Wire the real mDNS
  browse (`multicast_dns`/`nsd`) in `_startMdnsSearch`.

## Wiring order after the spike (fast path)
1. `crypto` dep + real `computeHmacSignature` (if external HMAC needed).
2. Inject a real `WlanPiTransport` (dart:io `HttpClient`, mirror
   `JsonHttpClient`) into `WlanPiSession`.
3. `authenticate()` per the captured handshake.
4. `detectCoreVersion()` live fetch → version gate.
5. Live `readDeviceInfo/Stats/NetworkInfo` via `send()`.
6. Profiler poll loop + real capability keys.
7. Real mDNS browse.
8. Vex review (token/HMAC/Keychain) before profiler ships; Vera visual gate.

## Hard rules carried into the spike
- Secrets masked everywhere; never logged, never in a session-log, never in a
  committed file. Token in memory only (or Keychain via `flutter_secure_storage`
  if persistence is added — never SharedPreferences/plist).
- Never fabricate the handshake or fake a device response. Sample data is always
  labeled sample data.
