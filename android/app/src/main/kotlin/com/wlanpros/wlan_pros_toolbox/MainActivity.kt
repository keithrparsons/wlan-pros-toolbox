package com.wlanpros.wlan_pros_toolbox

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.ScanResult
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet6Address
import java.net.InetAddress

// MainActivity — the Android native host for the WLAN Pros Toolbox.
//
// Two method channels are wired:
//
//   1. lan_discovery/multicast — the Wi-Fi multicast lock for the mDNS browse
//      (SPIKE-HSD-01). Android drops inbound multicast frames by default to
//      save power, so multicast_dns (UDP/5353) returns nothing without a held
//      lock. Requires CHANGE_WIFI_MULTICAST_STATE (declared in the manifest).
//
//   2. com.wlanpros.toolbox/wifi_info — the Android arm of the cross-platform
//      Wi-Fi Information bridge (Android Phase 2). Reads the connected link via
//      WifiManager + ConnectivityManager and maps it into the SAME payload
//      shape the macOS CoreWLAN channel emits, so the shared Dart WifiInfo model
//      and ConnectedAp.fromAndroidWifiInfo consume it unchanged.
//
//   3a. com.wlanpros.toolbox/network_addressing — the Android arm of the
//      Test My Connection local-addressing report. Reads the DHCP server
//      identifier (option 54) via WifiManager.getDhcpInfo().serverAddress and
//      the resolver list via ConnectivityManager.getLinkProperties().dnsServers
//      (modern, non-deprecated; DhcpInfo.dns1/dns2 only as the fallback). These
//      ARE available on Android (unlike sandboxed iOS/macOS, where the app
//      genuinely cannot read them), so the Dart NetworkDetails populates real
//      values here. Requires ACCESS_WIFI_STATE + ACCESS_NETWORK_STATE (both
//      normal, already declared) — NO location permission. A 0 / 0.0.0.0 read
//      is returned as null (never a fabricated address, GL-005).
//
//   3b. com.wlanpros.toolbox/network_transport — WHICH TRANSPORT the ACTIVE
//      network runs over (cellular / Wi-Fi / Ethernet / VPN), read from
//      ConnectivityManager.getNetworkCapabilities(activeNetwork).hasTransport().
//      This is the ANDROID CELLULAR-DATA CONSENT GATE's input: it is the MEASURED
//      answer to "is the user paying per byte right now?", and it is what makes
//      WifiConnectionStatus.notOnWifi reachable on Android at all.
//
//      Requires ACCESS_NETWORK_STATE ONLY — a `normal` (install-time) permission
//      that is ALREADY declared in AndroidManifest.xml and NEVER prompts. NO
//      Location grant: the transport TYPE is not identifying information, unlike
//      the SSID/BSSID reads above, so this answers on a device that has denied
//      Location outright.
//
//      IT DECIDES NOTHING. It returns the four capability bits verbatim and the
//      Dart decision table (WifiConnectionService) resolves them, because a
//      decision made here is a decision the Dart test suite cannot reach.
//
//   3. com.wlanpros.toolbox/ap_scan — the Android-ONLY nearby-AP scan (H3).
//      Calls WifiManager.getScanResults() and returns every visible BSS with the
//      CLEAN fields the public API exposes reliably: SSID, BSSID, channel, band,
//      and RSSI. NO noise / SNR / MCS — Android does not expose those for a
//      scanned (non-connected) BSS, so they are never reported (GL-005 / GL-008).
//      Scan results are gated by ACCESS_FINE_LOCATION at runtime; without it the
//      list is empty and locationAuthorized=false drives the Dart Location card.
//      getScanResults() returns the LAST cached scan, so a fresh startScan()
//      that the OS throttles still yields the previous results (the honest
//      "last scan" fallback) rather than nothing.
//
// Honesty (GL-005 / GL-008): every field the public Android API cannot supply
// is returned as a genuine null — never an estimate. Android exposes no noise
// floor, so noiseDbm and snrDb are always null and SNR is never computed.
// SSID/BSSID require ACCESS_FINE_LOCATION granted at runtime; without it Android
// redacts them and we pass null with locationAuthorized=false so the Dart UI
// shows its honest Location-gate card.
class MainActivity : FlutterActivity() {
    private val multicastChannelName = "lan_discovery/multicast"
    private val wifiInfoChannelName = "com.wlanpros.toolbox/wifi_info"
    private val apScanChannelName = "com.wlanpros.toolbox/ap_scan"
    private val networkAddressingChannelName = "com.wlanpros.toolbox/network_addressing"
    private val networkTransportChannelName = "com.wlanpros.toolbox/network_transport"
    private var multicastLock: WifiManager.MulticastLock? = null

    // The pending Flutter result for an in-flight runtime permission request, so
    // the onRequestPermissionsResult callback can resolve the same Dart Future.
    private var pendingPermissionResult: MethodChannel.Result? = null

    // True once the runtime Location dialog has been requested at least once this
    // process. Used to tell "never asked" (promptable → notDetermined) from
    // "asked and dismissed without rationale" (permanently denied → denied) in
    // locationAuthorizationStatusToken, since shouldShowRequestPermissionRationale
    // alone returns false in both cases.
    private var hasRequestedLocationOnce: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, multicastChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        acquire()
                        result.success(true)
                    }
                    "release" -> {
                        releaseLock()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wifiInfoChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getWifiInfo" -> result.success(readWifiInfo())
                    "isLocationAuthorized" -> result.success(isLocationAuthorized())
                    "locationAuthorizationStatus" ->
                        result.success(locationAuthorizationStatusToken())
                    "requestLocationPermission" -> requestLocationPermission(result)
                    "openLocationSettings" -> result.success(openAppSettings())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, apScanChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Kick a fresh scan (best-effort; the OS may throttle it) and
                    // return whatever getScanResults() now holds — the fresh scan
                    // if it ran, otherwise the last cached scan (the honest
                    // throttled fallback). Either way the caller gets the most
                    // recent results the OS will give us.
                    "scan" -> result.success(readScanResults(triggerFresh = true))
                    // Return the last cached scan without requesting a new one.
                    "lastResults" -> result.success(readScanResults(triggerFresh = false))
                    "isLocationAuthorized" -> result.success(isLocationAuthorized())
                    "requestLocationPermission" -> requestLocationPermission(result)
                    "openLocationSettings" -> result.success(openAppSettings())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, networkAddressingChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNetworkAddressing" -> result.success(readNetworkAddressing())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, networkTransportChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getTransport" -> result.success(readTransport())
                    else -> result.notImplemented()
                }
            }
    }

    // ---- Active-network transport (the Android cellular-data consent gate) ----

    /// Reads WHICH TRANSPORT the device's ACTIVE (default) network runs over, as
    /// the four raw `NetworkCapabilities.hasTransport(...)` bits. This is the
    /// MEASURED input to the cellular-data consent gate: it is how the app knows,
    /// definitively, that the user is paying per byte before it spends 50-500 MB
    /// of their data on the speed test.
    ///
    /// PERMISSION: ACCESS_NETWORK_STATE only — `normal` protection level, declared
    /// in the manifest, granted at install, never prompts. NOT Location-gated: we
    /// ask what KIND of link this is, never WHICH network it is, so this answers
    /// correctly on a device that has denied Location.
    ///
    /// HONESTY (GL-005 / GL-008). This method DECIDES NOTHING — it reports. Every
    /// judgement (what counts as Wi-Fi, what licenses a "you're on cellular"
    /// warning, what is too ambiguous to call) lives in the Dart decision table in
    /// `WifiConnectionService`, where it is unit-tested and mutation-proven.
    ///
    /// TWO KINDS OF NULL, KEPT APART, because conflating them is the bug this whole
    /// change exists to remove:
    ///   * `available = false` — WE COULD NOT READ IT (no ConnectivityManager, the
    ///     read threw, pre-API-23 device). The Dart side falls back and resolves to
    ///     `unknown`. It must never be read as "not on cellular".
    ///   * `available = true` with EVERY BIT FALSE — WE READ IT, AND THERE IS NO
    ///     ACTIVE NETWORK (airplane mode), or the transport is one we do not
    ///     enumerate (Bluetooth tether, USB, LoWPAN). That is a real, successful
    ///     read of a state that is NEITHER cellular NOR Wi-Fi. The Dart side
    ///     resolves it to `unknown` too — no nag, and no false claim of Wi-Fi.
    ///
    /// Both land on `unknown`, but they are not the same fact and the payload does
    /// not pretend they are.
    private fun readTransport(): Map<String, Any?> = try {
        val cm = applicationContext
            .getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        when {
            cm == null -> unavailableTransport()
            // getActiveNetwork / getNetworkCapabilities are API 23+. Below that we
            // cannot read the transport honestly, so we say so rather than falling
            // back to the deprecated activeNetworkInfo guesswork.
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M -> unavailableTransport()
            else -> {
                val network = cm.activeNetwork
                if (network == null) {
                    // A SUCCESSFUL read of "there is no active network" (airplane
                    // mode / fully offline). Not a failure, and not cellular.
                    mapOf(
                        "available" to true,
                        "cellular" to false,
                        "wifi" to false,
                        "ethernet" to false,
                        "vpn" to false,
                    )
                } else {
                    val caps = cm.getNetworkCapabilities(network)
                    if (caps == null) {
                        unavailableTransport()
                    } else {
                        mapOf(
                            "available" to true,
                            "cellular" to
                                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
                            "wifi" to
                                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                            "ethernet" to
                                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET),
                            "vpn" to
                                caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN),
                        )
                    }
                }
            }
        }
    } catch (e: Throwable) {
        // SecurityException / anything else — honest unavailable, never a verdict.
        unavailableTransport()
    }

    /// The honest "we could not read the transport" payload. The Dart side maps it
    /// to null → `unknown`, never to a verdict either way.
    private fun unavailableTransport(): Map<String, Any?> = mapOf("available" to false)

    // ---- Local network addressing (DHCP server + DNS, Android) ----------

    /// Reads the local-network addressing the Test My Connection report shows
    /// that iOS/macOS cannot: the DHCP server identifier (option 54) and the
    /// resolver list. Both come from public, unprivileged Android APIs gated only
    /// by ACCESS_WIFI_STATE / ACCESS_NETWORK_STATE (no Location grant).
    ///
    /// HONESTY (GL-005 / GL-008): a 0 / 0.0.0.0 / empty read is returned as a
    /// genuine null (DHCP) or omitted from the list (DNS) — never a placeholder.
    /// When nothing is readable (not connected, no active network), `dhcpServer`
    /// is null and `dnsServers` is empty and the Dart side shows its honest
    /// "not reported for this network" state.
    private fun readNetworkAddressing(): Map<String, Any?> = mapOf(
        "dhcpServer" to readDhcpServer(),
        "dnsServers" to readDnsServers(),
    )

    /// DHCP server identifier (option 54) from WifiManager.getDhcpInfo(). That
    /// API is deprecated but is the only public Android source for the DHCP
    /// server address, so its use is accepted. `serverAddress` is a host-order
    /// (little-endian) int — formatted LSB-first. A 0 / 0.0.0.0 result (no DHCP
    /// lease, wired, or not connected) returns null, never a fabricated address.
    private fun readDhcpServer(): String? = try {
        val wifiManager = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION")
        val dhcp = wifiManager.dhcpInfo
        if (dhcp == null) null else intToIpv4LittleEndian(dhcp.serverAddress)
    } catch (e: Throwable) {
        null
    }

    /// Configured DNS resolver(s) for the active network. Prefers the modern,
    /// non-deprecated ConnectivityManager.getLinkProperties(activeNetwork)
    /// .getDnsServers() (returns List<InetAddress>, IPv4 + IPv6). Falls back to
    /// the deprecated DhcpInfo.dns1/dns2 only when LinkProperties yields nothing
    /// (e.g. pre-API-23, or a transport that does not expose link properties).
    /// De-dupes (insertion-ordered), drops empty / 0.0.0.0 / unspecified
    /// addresses, and strips any IPv6 scope suffix. Empty list = honest "none
    /// reported", never a guessed resolver.
    private fun readDnsServers(): List<String> {
        val out = LinkedHashSet<String>()

        // Modern path — ConnectivityManager link properties (API 21+; the active
        // network accessor is API 23+, so guard it and fall through below on
        // older devices).
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val cm = applicationContext
                    .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                val network = cm.activeNetwork
                if (network != null) {
                    val lp: LinkProperties? = cm.getLinkProperties(network)
                    lp?.dnsServers?.forEach { addr -> formatInetAddress(addr)?.let(out::add) }
                }
            }
        } catch (e: Throwable) {
            // Fall through to the DhcpInfo fallback below.
        }

        // Fallback — deprecated DhcpInfo dns1/dns2 (IPv4 only). Only used when
        // the modern path produced nothing.
        if (out.isEmpty()) {
            try {
                val wifiManager = applicationContext
                    .getSystemService(Context.WIFI_SERVICE) as WifiManager
                @Suppress("DEPRECATION")
                val dhcp = wifiManager.dhcpInfo
                if (dhcp != null) {
                    intToIpv4LittleEndian(dhcp.dns1)?.let(out::add)
                    intToIpv4LittleEndian(dhcp.dns2)?.let(out::add)
                }
            } catch (e: Throwable) {
                // Honest empty.
            }
        }

        return out.toList()
    }

    /// Formats an InetAddress to its CANONICAL textual form, dropping the
    /// unspecified address (0.0.0.0 / ::). IPv4 passes through as dotted-quad.
    /// IPv6 is rendered in the RFC 5952 canonical compressed form
    /// (`compressIpv6` from the 16 raw bytes), NOT Java's expanded
    /// `getHostAddress()` (which emits e.g. `2001:4860:4860:0:0:0:0:8888`,
    /// overflowing the narrow value column). The scope suffix (`%wlan0`) never
    /// appears because we build IPv6 from `Inet6Address.address` (scopeless).
    private fun formatInetAddress(addr: InetAddress?): String? {
        if (addr == null || addr.isAnyLocalAddress) return null
        val host: String? = when (addr) {
            is Inet6Address -> compressIpv6(addr.address)
            else -> addr.hostAddress?.trim()?.substringBefore('%')
        }
        if (host.isNullOrEmpty() || host == "0.0.0.0" || host == "::") return null
        return host
    }

    /// Renders 16 IPv6 address bytes to the RFC 5952 canonical string: lowercase
    /// hextets with leading zeros stripped, and the LONGEST run of consecutive
    /// all-zero hextets (length >= 2, leftmost on a tie) collapsed to `::`. A run
    /// of a single zero hextet is NOT collapsed (per RFC 5952). Returns null when
    /// the byte array is not 16 bytes long.
    private fun compressIpv6(bytes: ByteArray?): String? {
        if (bytes == null || bytes.size != 16) return null
        val groups = IntArray(8)
        for (i in 0 until 8) {
            groups[i] = ((bytes[i * 2].toInt() and 0xff) shl 8) or
                (bytes[i * 2 + 1].toInt() and 0xff)
        }

        // Longest zero run (>= 2), leftmost on a tie.
        var bestStart = -1
        var bestLen = 0
        var curStart = -1
        var curLen = 0
        for (i in 0 until 8) {
            if (groups[i] == 0) {
                if (curStart == -1) curStart = i
                curLen++
                if (curLen > bestLen) {
                    bestLen = curLen
                    bestStart = curStart
                }
            } else {
                curStart = -1
                curLen = 0
            }
        }
        if (bestLen < 2) bestStart = -1

        val sb = StringBuilder()
        var i = 0
        while (i < 8) {
            if (i == bestStart) {
                sb.append("::")
                i = bestStart + bestLen
            } else {
                sb.append(Integer.toHexString(groups[i]))
                // Emit a separator unless the next index opens the "::" gap (which
                // already carries its own colons) or this is the final hextet.
                if (i < 7 && (i + 1) != bestStart) sb.append(':')
                i++
            }
        }
        return sb.toString()
    }

    /// Formats a host-order (little-endian) IPv4 int — the shape every DhcpInfo
    /// field uses — to dotted-quad, LSB first. Returns null for 0 / 0.0.0.0.
    private fun intToIpv4LittleEndian(addr: Int): String? {
        if (addr == 0) return null
        val a = addr and 0xff
        val b = (addr shr 8) and 0xff
        val c = (addr shr 16) and 0xff
        val d = (addr shr 24) and 0xff
        val dotted = "$a.$b.$c.$d"
        return if (dotted == "0.0.0.0") null else dotted
    }

    // ---- Nearby-AP scan (H3, Android-only) ------------------------------

    /// Reads the visible BSSs from WifiManager.getScanResults() and maps each to
    /// the CLEAN field set the Dart layer renders: SSID, BSSID, channel, band,
    /// and RSSI. No noise / SNR / MCS — the scanned-BSS API does not expose them,
    /// so they are never invented (GL-005 / GL-008).
    ///
    /// [triggerFresh] requests a new scan first (best-effort: startScan() is
    /// rate-limited on Android 9+ and returns false when throttled). Whether or
    /// not the fresh scan runs, getScanResults() returns the OS's last cached
    /// scan, so a throttled request still yields the previous results rather than
    /// nothing — the honest "last scan" fallback the UI labels as such.
    ///
    /// The returned map always carries [poweredOn] and [locationAuthorized] so the
    /// Dart UI can show the Wi-Fi-off and Location-gate states without guessing.
    /// [scanThrottled] tells the UI a requested fresh scan was rejected so the
    /// list it shows is the last cached one.
    private fun readScanResults(triggerFresh: Boolean): Map<String, Any?> {
        val wifiManager = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager
        val locationOk = isLocationAuthorized()
        val poweredOn = wifiManager.isWifiEnabled

        if (!locationOk || !poweredOn) {
            return mapOf(
                "poweredOn" to poweredOn,
                "locationAuthorized" to locationOk,
                "scanThrottled" to false,
                "accessPoints" to emptyList<Map<String, Any?>>(),
            )
        }

        // Best-effort fresh scan. startScan() is deprecated and rate-limited
        // (Android 9+ caps an app to a handful of scans per two minutes); a
        // false return means the OS throttled us and getScanResults() will hand
        // back the LAST scan instead. We surface that as scanThrottled so the UI
        // can say "showing the last scan".
        var throttled = false
        if (triggerFresh) {
            val started = try {
                @Suppress("DEPRECATION")
                wifiManager.startScan()
            } catch (e: SecurityException) {
                false
            }
            throttled = !started
        }

        val results: List<ScanResult> = try {
            @Suppress("DEPRECATION")
            wifiManager.scanResults ?: emptyList()
        } catch (e: SecurityException) {
            // Location revoked between the check and the read — honest empty.
            return mapOf(
                "poweredOn" to poweredOn,
                "locationAuthorized" to false,
                "scanThrottled" to false,
                "accessPoints" to emptyList<Map<String, Any?>>(),
            )
        }

        val aps = results.mapNotNull { mapScanResult(it) }

        return mapOf(
            "poweredOn" to poweredOn,
            "locationAuthorized" to locationOk,
            "scanThrottled" to throttled,
            "accessPoints" to aps,
        )
    }

    /// Maps one ScanResult to the CLEAN payload. Drops a BSS with no usable
    /// frequency (channel/band cannot be derived honestly). The hidden-SSID case
    /// is a genuine empty string and is passed as null so the Dart UI renders
    /// "(hidden network)" rather than a blank, never a fabricated name.
    private fun mapScanResult(r: ScanResult): Map<String, Any?>? {
        val freq = r.frequency
        val channel = channelForFrequency(freq) ?: return null
        val band = bandForFrequency(freq) ?: return null

        @Suppress("DEPRECATION")
        val rawSsid: String? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            r.wifiSsid?.toString()?.removeSurrounding("\"")
        } else {
            r.SSID
        }
        val ssid = if (rawSsid.isNullOrEmpty()) null else rawSsid

        val bssid: String? = r.BSSID

        return mapOf(
            "ssid" to ssid,
            "bssid" to bssid,
            "rssiDbm" to r.level,
            "channel" to channel,
            "band" to band,
            "frequencyMhz" to freq,
        )
    }

    // ---- Wi-Fi Information bridge ----------------------------------------

    /// Reads a snapshot of the connected Wi-Fi link as a map matching the shared
    /// Dart WifiInfo payload. Returns a powered-off / disconnected snapshot
    /// (honest nulls) rather than throwing when there is no active link.
    private fun readWifiInfo(): Map<String, Any?> {
        val wifiManager = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager
        val locationOk = isLocationAuthorized()
        val poweredOn = wifiManager.isWifiEnabled

        @Suppress("DEPRECATION")
        val info: WifiInfo? = wifiManager.connectionInfo

        // networkId == -1 means not associated to an AP.
        val connected = info != null && info.networkId != -1

        if (info == null || !connected) {
            return baseSnapshot(poweredOn, locationOk)
        }

        val frequency = info.frequency // MHz, 0 if unknown
        val channel = channelForFrequency(frequency)
        val band = bandForFrequency(frequency)

        // SSID arrives quoted ("MyNet") and is redacted to <unknown ssid> /
        // 02:00:00:00:00:00 BSSID without the Location grant on Android 8.0+.
        val ssid = sanitizeSsid(info.ssid, locationOk)
        val bssid = sanitizeBssid(info.bssid, locationOk)

        val txRate = if (info.linkSpeed > 0) info.linkSpeed.toDouble() else null

        val rxRate: Double? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val rx = info.rxLinkSpeedMbps
                if (rx > 0) rx.toDouble() else null
            } else {
                null
            }

        val standard: String? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                standardLabel(info.wifiStandard)
            } else {
                null
            }

        val securityToken: String? = securityTokenForConnected(wifiManager, info, locationOk)

        // Channel width: WifiInfo does not carry it, but the matching ScanResult
        // does (ScanResult.channelWidth, available since API 23). Match the
        // connected BSSID in getScanResults() and map the enum to MHz. Scan
        // results are Location-gated, so this only resolves with the grant; null
        // otherwise and the Dart side says "Not reported".
        val channelWidthMhz: Int? = channelWidthForConnected(wifiManager, info, locationOk)

        // Regulatory country code: WifiManager.getCountryCode() exists but is a
        // restricted/system API (hidden on the public SDK, and limited on
        // Android 11+ — often requires a privileged caller). Try it reflectively;
        // a null/blank/refused result stays null and the Dart side shows the
        // honest Android limit note rather than a fabricated value.
        val countryCode: String? = readCountryCode(wifiManager)

        return mapOf(
            "interfaceName" to "wlan0",
            "poweredOn" to poweredOn,
            "ssid" to ssid,
            "bssid" to bssid,
            "rssiDbm" to info.rssi,
            // Android public API exposes no noise floor → SNR cannot be computed.
            "noiseDbm" to null,
            "snrDb" to null,
            "txRateMbps" to txRate,
            "rxRateMbps" to rxRate,
            "phyMode" to standard,
            "channel" to channel,
            // Channel width from the matching ScanResult (null when no scan
            // match / no Location grant); the Dart side says "Not reported".
            "channelWidthMhz" to channelWidthMhz,
            "band" to band,
            // Regulatory country, restricted on Android 11+; null when the OS
            // refuses it and the Dart side shows the honest limit note.
            "countryCode" to countryCode,
            // Android returns a fixed 02:00:00:00:00:00 device MAC to apps; the
            // honest answer is null rather than that sentinel.
            "hardwareAddress" to null,
            "securityToken" to securityToken,
            "locationAuthorized" to locationOk,
        )
    }

    private fun baseSnapshot(poweredOn: Boolean, locationOk: Boolean): Map<String, Any?> =
        mapOf(
            "interfaceName" to "wlan0",
            "poweredOn" to poweredOn,
            "ssid" to null,
            "bssid" to null,
            "rssiDbm" to null,
            "noiseDbm" to null,
            "snrDb" to null,
            "txRateMbps" to null,
            "rxRateMbps" to null,
            "phyMode" to null,
            "channel" to null,
            "channelWidthMhz" to null,
            "band" to null,
            "countryCode" to null,
            "hardwareAddress" to null,
            "securityToken" to null,
            "locationAuthorized" to locationOk,
        )

    /// Strips the surrounding quotes Android wraps the SSID in, and maps the
    /// redaction sentinels (no Location grant, or hidden) to null.
    private fun sanitizeSsid(raw: String?, locationOk: Boolean): String? {
        if (raw == null) return null
        var s = raw
        if (s.startsWith("\"") && s.endsWith("\"") && s.length >= 2) {
            s = s.substring(1, s.length - 1)
        }
        if (s.isEmpty() || s == WifiManager.UNKNOWN_SSID || s == "<unknown ssid>") {
            return null
        }
        // Without the Location grant Android still may return UNKNOWN_SSID above;
        // belt-and-suspenders, never surface a name we are not authorized to read.
        if (!locationOk) return null
        return s
    }

    private fun sanitizeBssid(raw: String?, locationOk: Boolean): String? {
        if (raw == null) return null
        // 02:00:00:00:00:00 is the "no permission" placeholder BSSID.
        if (raw == "02:00:00:00:00:00" || raw == "00:00:00:00:00:00") return null
        if (!locationOk) return null
        return raw
    }

    /// Derives the security token from the matching scan result's capabilities
    /// string, mapped to the shared classifier's token vocabulary. Requires the
    /// Location grant (scan results are gated by it). Null when it cannot be
    /// resolved — the Dart UI then shows an honest "not in this reading".
    private fun securityTokenForConnected(
        wifiManager: WifiManager,
        info: WifiInfo,
        locationOk: Boolean,
    ): String? {
        if (!locationOk) return null

        // API 31+ exposes the current security type directly — the precise path.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            securityTokenForCurrentType(info)?.let { return it }
        }

        val bssid = info.bssid ?: return null
        if (bssid == "02:00:00:00:00:00") return null
        val results: List<ScanResult> = try {
            @Suppress("DEPRECATION")
            wifiManager.scanResults ?: return null
        } catch (e: SecurityException) {
            return null
        }
        val match = results.firstOrNull { it.BSSID.equals(bssid, ignoreCase = true) }
            ?: return null
        return securityTokenForCapabilities(match.capabilities)
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun securityTokenForCurrentType(info: WifiInfo): String? =
        when (info.currentSecurityType) {
            WifiInfo.SECURITY_TYPE_OPEN -> "open"
            WifiInfo.SECURITY_TYPE_WEP -> "wep"
            WifiInfo.SECURITY_TYPE_PSK -> "wpa2Personal"
            WifiInfo.SECURITY_TYPE_EAP -> "wpa2Enterprise"
            WifiInfo.SECURITY_TYPE_SAE -> "wpa3Personal"
            WifiInfo.SECURITY_TYPE_EAP_WPA3_ENTERPRISE -> "wpa3Enterprise"
            WifiInfo.SECURITY_TYPE_EAP_WPA3_ENTERPRISE_192_BIT -> "wpa3Enterprise"
            WifiInfo.SECURITY_TYPE_OWE -> "owe"
            WifiInfo.SECURITY_TYPE_WAPI_PSK -> "unknown"
            WifiInfo.SECURITY_TYPE_WAPI_CERT -> "unknown"
            WifiInfo.SECURITY_TYPE_PASSPOINT_R1_R2 -> "wpa2Enterprise"
            WifiInfo.SECURITY_TYPE_PASSPOINT_R3 -> "wpa3Enterprise"
            else -> null
        }

    /// Maps a ScanResult.capabilities string into the shared classifier tokens.
    /// Honest precedence: WPA3/SAE before WPA2/PSK before WEP before Open.
    private fun securityTokenForCapabilities(caps: String?): String {
        if (caps == null) return "unknown"
        val c = caps.uppercase()
        val enterprise = c.contains("EAP")
        return when {
            c.contains("SAE") && enterprise -> "wpa3Enterprise"
            c.contains("SAE") -> "wpa3Personal"
            c.contains("OWE") -> "owe"
            c.contains("WPA2") && enterprise -> "wpa2Enterprise"
            c.contains("RSN") && enterprise -> "wpa2Enterprise"
            c.contains("WPA") && enterprise -> "wpaEnterprise"
            c.contains("WPA2") -> "wpa2Personal"
            c.contains("RSN") -> "wpa2Personal"
            c.contains("WPA") -> "wpaPersonal"
            c.contains("WEP") -> "wep"
            else -> "open"
        }
    }

    /// Channel width in MHz for the connected link, read from the matching
    /// ScanResult.channelWidth (the connected WifiInfo does not carry width).
    /// Matches the connected BSSID against getScanResults() and maps the enum to
    /// MHz. Returns null when there is no Location grant, no BSSID, no scan
    /// match, or the width is unknown — the Dart side then shows "Not reported"
    /// rather than guessing (GL-005 / GL-008).
    private fun channelWidthForConnected(
        wifiManager: WifiManager,
        info: WifiInfo,
        locationOk: Boolean,
    ): Int? {
        if (!locationOk) return null
        val bssid = info.bssid ?: return null
        if (bssid == "02:00:00:00:00:00" || bssid == "00:00:00:00:00:00") return null
        val results: List<ScanResult> = try {
            @Suppress("DEPRECATION")
            wifiManager.scanResults ?: return null
        } catch (e: SecurityException) {
            return null
        }
        val match = results.firstOrNull { it.BSSID.equals(bssid, ignoreCase = true) }
            ?: return null
        return when (match.channelWidth) {
            ScanResult.CHANNEL_WIDTH_20MHZ -> 20
            ScanResult.CHANNEL_WIDTH_40MHZ -> 40
            ScanResult.CHANNEL_WIDTH_80MHZ -> 80
            ScanResult.CHANNEL_WIDTH_160MHZ -> 160
            // 80+80 MHz (two non-contiguous 80 MHz segments). Report the total
            // occupied width; the Dart label renders "80+80" specially when the
            // value is 160 is ambiguous, so we surface the dedicated sentinel.
            ScanResult.CHANNEL_WIDTH_80MHZ_PLUS_MHZ -> 8080
            else -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                channelWidth320(match)
            } else {
                null
            }
        }
    }

    /// 320 MHz (Wi-Fi 7) width, only on API 33+ where the constant exists. Kept
    /// in its own gated helper so older SDK builds never reference the constant.
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun channelWidth320(match: ScanResult): Int? =
        if (match.channelWidth == ScanResult.CHANNEL_WIDTH_320MHZ) 320 else null

    /// Regulatory country code via WifiManager.getCountryCode(). The method is a
    /// restricted/system API (not on the public SDK; limited on Android 11+ and
    /// often requires a privileged caller), so it is invoked reflectively and
    /// any failure or empty result returns null. Honest per GL-005: a null here
    /// drives the Dart "restricted on this Android version" note, never a guess.
    private fun readCountryCode(wifiManager: WifiManager): String? = try {
        val method = WifiManager::class.java.getMethod("getCountryCode")
        val raw = method.invoke(wifiManager) as? String
        val cc = raw?.trim()?.uppercase()
        if (cc.isNullOrEmpty() || cc == "00") null else cc
    } catch (e: Throwable) {
        // NoSuchMethodException / SecurityException / hidden-API block — all
        // resolve to the honest null.
        null
    }

    /// 802.11 standard label from WifiInfo.getWifiStandard (API 30+), in the
    /// "802.11ax (Wi-Fi 6)" form the cards render.
    @RequiresApi(Build.VERSION_CODES.R)
    private fun standardLabel(standard: Int): String? =
        when (standard) {
            ScanResult.WIFI_STANDARD_LEGACY -> "802.11a/b/g"
            ScanResult.WIFI_STANDARD_11N -> "802.11n (Wi-Fi 4)"
            ScanResult.WIFI_STANDARD_11AC -> "802.11ac (Wi-Fi 5)"
            ScanResult.WIFI_STANDARD_11AX -> "802.11ax (Wi-Fi 6)"
            ScanResult.WIFI_STANDARD_11AD -> "802.11ad (WiGig)"
            ScanResult.WIFI_STANDARD_11BE -> "802.11be (Wi-Fi 7)"
            else -> null
        }

    /// Wi-Fi channel number from the center frequency in MHz. Returns null for
    /// an unknown (0) frequency. Covers 2.4 GHz, 5 GHz, and 6 GHz.
    private fun channelForFrequency(freq: Int): Int? = when {
        freq <= 0 -> null
        freq == 2484 -> 14
        freq in 2412..2472 -> (freq - 2412) / 5 + 1
        // 5 GHz: ch = (freq - 5000) / 5.
        freq in 5160..5885 -> (freq - 5000) / 5
        // 6 GHz: ch = (freq - 5950) / 5 (channel 1 at 5955 MHz).
        freq in 5955..7115 -> (freq - 5950) / 5
        else -> null
    }

    /// Human band label from the center frequency in MHz.
    private fun bandForFrequency(freq: Int): String? = when {
        freq <= 0 -> null
        freq in 2401..2495 -> "2.4 GHz"
        freq in 4900..5895 -> "5 GHz"
        freq in 5925..7125 -> "6 GHz"
        else -> null
    }

    // ---- Location runtime permission ------------------------------------

    private fun isLocationAuthorized(): Boolean =
        ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED

    /// Maps the Android ACCESS_FINE_LOCATION grant to the same tri-state token
    /// the macOS channel returns, so the shared Dart side resolves one enum.
    /// Android cannot tell "never asked" from "asked once and dismissed"
    /// reliably without a prior request, so an ungranted permission that is NOT
    /// permanently denied reports `notDetermined` (the runtime dialog can still
    /// surface), and a permanently-denied permission reports `denied` (the UI
    /// must deep-link to App Settings). `shouldShowRequestPermissionRationale`
    /// is false BOTH before the first ask and after a permanent denial; we treat
    /// the not-yet-granted case as promptable, which is the safe default — the
    /// runtime request simply no-ops to the current grant if it cannot show.
    private fun locationAuthorizationStatusToken(): String {
        if (isLocationAuthorized()) return "authorized"
        val permanentlyDenied =
            !ActivityCompat.shouldShowRequestPermissionRationale(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ) && hasRequestedLocationOnce
        return if (permanentlyDenied) "denied" else "notDetermined"
    }

    /// Surfaces the standard Android runtime permission dialog for
    /// ACCESS_FINE_LOCATION. The result resolves the Dart Future in
    /// onRequestPermissionsResult. If already granted, resolves true immediately.
    private fun requestLocationPermission(result: MethodChannel.Result) {
        if (isLocationAuthorized()) {
            result.success(true)
            return
        }
        // Reject a second concurrent request rather than orphaning the first.
        if (pendingPermissionResult != null) {
            result.success(false)
            return
        }
        pendingPermissionResult = result
        hasRequestedLocationOnce = true
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
            LOCATION_PERMISSION_REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    /// Opens this app's system Settings page so the user can enable Location
    /// after a permanent denial ("Don't ask again"). Returns whether it opened.
    private fun openAppSettings(): Boolean = try {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    // ---- Multicast lock (mDNS browse) -----------------------------------

    private fun acquire() {
        if (multicastLock?.isHeld == true) return
        val wifi = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("lan_discovery_mdns").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    override fun onDestroy() {
        releaseLock()
        super.onDestroy()
    }

    companion object {
        private const val LOCATION_PERMISSION_REQUEST_CODE = 4711
    }
}
