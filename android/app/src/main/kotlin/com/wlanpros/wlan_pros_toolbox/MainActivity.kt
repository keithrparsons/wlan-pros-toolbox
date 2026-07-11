package com.wlanpros.wlan_pros_toolbox

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.LinkProperties
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
//   4. com.wlanpros.toolbox/platform_env — the ChromeOS / ARC-VM probe. See the
//      CHROMEOS block below; the Dart SSOT is ChromeOsArc.
//
// Honesty (GL-005 / GL-008): every field the public Android API cannot supply
// is returned as a genuine null — never an estimate. Android exposes no noise
// floor, so noiseDbm and snrDb are always null and SNR is never computed.
// SSID/BSSID require ACCESS_FINE_LOCATION granted at runtime; without it Android
// redacts them and we pass null with locationAuthorized=false so the Dart UI
// shows its honest Location-gate card.
//
// ============================ CHROMEOS / ARCVM =============================
// On a Chromebook this app does NOT run on the Chromebook's network stack. It
// runs inside ARCVM, a virtual machine whose network is a small NAT'd private
// network created by ChromeOS (`patchpanel`) out of the RFC 6598 shared-address
// block at 100.115.92.0/24. That breaks two whole classes of reading, and BOTH
// are suppressed at the source here so no Dart consumer can render them:
//
//   (a) ADDRESSING. getDhcpInfo() and getLinkProperties() describe the ARC VM's
//       virtual adapter — a 100.115.92.x address, a /30 subnet, a 100.115.92.x
//       gateway, and ChromeOS's own DNS proxy. The user's REAL gateway and REAL
//       resolvers sit on the far side of the NAT and are not visible to us at
//       all. Reporting the VM's as "your network" is not degraded data, it is
//       WRONG data — a K-12 admin troubleshooting a school network would be
//       handed a virtual machine's gateway with no way to know. So on ChromeOS
//       readNetworkAddressing() returns nulls and the Dart side says why.
//
//   (b) RF. ARC's Wi-Fi bridge is fed from ChromeOS's ONC (Open Network
//       Configuration) vocabulary, which defines signal strength as a 0-100
//       PERCENTAGE and carries NO dBm field, and which has no vocabulary at all
//       for channel width, PHY/link rate, the 802.11 generation, or MLO. Any
//       dBm we could read here is therefore at best a lossy reconstruction of a
//       percentage — a number that LOOKS like dBm and is not one. We do not have
//       the percentage either (there is no ONC access from inside Android), so
//       the honest answer is nothing-plus-a-reason, never a converted number.
//       readWifiInfo() therefore nulls rssiDbm, txRateMbps, rxRateMbps, phyMode,
//       and channelWidthMhz on ChromeOS. (noiseDbm/snrDb are already always null
//       on Android.)
//
// WHAT SURVIVES, and why: the fields ONC actually defines pass through and are
// kept — SSID (WiFi.SSID), BSSID (WiFi.BSSID), the center frequency (WiFi.
// Frequency, from which channel + band derive), and the security type (WiFi.
// Security). BSSID's failure mode is a null or the 02:00:00:00:00:00 sentinel,
// both already mapped to null below — it cannot come back plausibly WRONG. A
// frequency of 0 already resolves to a null channel/band.
//
// DETECTION: hasSystemFeature("org.chromium.arc") is the canonical probe. We
// also accept "org.chromium.arc.device_management" (managed/enterprise
// Chromebooks — the K-12 case) and FEATURE_PC ("android.hardware.type.pc",
// which ChromeOS declares), so a device reporting any of the three is treated as
// ChromeOS. Resolved once, cached, and never guessed.
// ===========================================================================
class MainActivity : FlutterActivity() {
    private val multicastChannelName = "lan_discovery/multicast"
    private val wifiInfoChannelName = "com.wlanpros.toolbox/wifi_info"
    private val apScanChannelName = "com.wlanpros.toolbox/ap_scan"
    private val networkAddressingChannelName = "com.wlanpros.toolbox/network_addressing"
    private val platformEnvChannelName = "com.wlanpros.toolbox/platform_env"
    private var multicastLock: WifiManager.MulticastLock? = null

    /// Cached ChromeOS / ARC-VM verdict. Null until first probed; the answer
    /// cannot change while the process is alive, so it is computed once.
    private var chromeOsCache: Boolean? = null

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, platformEnvChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isChromeOs" -> result.success(isChromeOs())
                    else -> result.notImplemented()
                }
            }
    }

    // ---- ChromeOS / ARC-VM detection ------------------------------------

    /// True when this Android process is running inside ChromeOS's ARC virtual
    /// machine. See the CHROMEOS block in the file header for what that breaks
    /// and why every affected field is suppressed rather than shown.
    ///
    /// Three probes, OR-ed:
    ///   * "org.chromium.arc" — the canonical ARC presence feature.
    ///   * "org.chromium.arc.device_management" — declared on managed /
    ///     enterprise-enrolled Chromebooks (the K-12 fleet case). Belt-and-
    ///     suspenders: a managed device that somehow withheld the base feature
    ///     is still correctly identified.
    ///   * FEATURE_PC ("android.hardware.type.pc") — declared by ChromeOS.
    ///
    /// A throw resolves to FALSE, deliberately: the cost of a false negative is
    /// a Chromebook keeping the old behavior; the cost of a false positive is a
    /// real phone hiding its perfectly good RSSI. We take the former (GL-005 —
    /// a failed read never manufactures a ceiling).
    private fun isChromeOs(): Boolean {
        chromeOsCache?.let { return it }
        val verdict = try {
            val pm = packageManager
            pm.hasSystemFeature(ARC_FEATURE) ||
                pm.hasSystemFeature(ARC_DEVICE_MANAGEMENT_FEATURE) ||
                pm.hasSystemFeature(PackageManager.FEATURE_PC)
        } catch (e: Throwable) {
            false
        }
        chromeOsCache = verdict
        return verdict
    }

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
    ///
    /// CHROMEOS (2026-07-10): on a Chromebook BOTH reads describe the ARC virtual
    /// machine's private NAT'd network (100.115.92.x — the DHCP server is
    /// ChromeOS's own, the resolvers are ChromeOS's DNS proxy), NOT the user's
    /// real LAN. Showing them as "your network" is wrong, not merely degraded, so
    /// they are suppressed AT THE SOURCE here — a Dart consumer cannot render
    /// what never arrives. `isChromeOs` rides along so the Dart side can carry
    /// the precise reason instead of a bare "Unavailable".
    private fun readNetworkAddressing(): Map<String, Any?> {
        val chromeOs = isChromeOs()
        if (chromeOs) {
            return mapOf(
                "isChromeOs" to true,
                "dhcpServer" to null,
                "dnsServers" to emptyList<String>(),
            )
        }
        return mapOf(
            "isChromeOs" to false,
            "dhcpServer" to readDhcpServer(),
            "dnsServers" to readDnsServers(),
        )
    }

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

        // CHROMEOS: a scan list's headline datum is SIGNAL, and ChromeOS gives
        // Android no trustworthy dBm (ONC is a 0-100 percentage with no dBm
        // field — see the CHROMEOS block in the header). Per-BSS channel width
        // has no ONC vocabulary either. A list of APs carrying a signal column we
        // cannot vouch for is exactly the "confidently wrong" failure this whole
        // change exists to stop, so nothing is returned and the Dart side shows
        // the honest per-platform unavailable state (GL-008 decision order,
        // step 4). Suppressed at the source so no consumer can render a partial,
        // half-trustworthy scan.
        if (isChromeOs()) {
            return mapOf(
                "isChromeOs" to true,
                "poweredOn" to poweredOn,
                "locationAuthorized" to locationOk,
                "scanThrottled" to false,
                "accessPoints" to emptyList<Map<String, Any?>>(),
            )
        }

        if (!locationOk || !poweredOn) {
            return mapOf(
                "isChromeOs" to false,
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
                "isChromeOs" to false,
                "poweredOn" to poweredOn,
                "locationAuthorized" to false,
                "scanThrottled" to false,
                "accessPoints" to emptyList<Map<String, Any?>>(),
            )
        }

        val aps = results.mapNotNull { mapScanResult(it) }

        return mapOf(
            "isChromeOs" to false,
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
        val chromeOs = isChromeOs()

        @Suppress("DEPRECATION")
        val info: WifiInfo? = wifiManager.connectionInfo

        // networkId == -1 means not associated to an AP.
        val connected = info != null && info.networkId != -1

        if (info == null || !connected) {
            return baseSnapshot(poweredOn, locationOk, chromeOs)
        }

        val frequency = info.frequency // MHz, 0 if unknown
        val channel = channelForFrequency(frequency)
        val band = bandForFrequency(frequency)

        // SSID arrives quoted ("MyNet") and is redacted to <unknown ssid> /
        // 02:00:00:00:00:00 BSSID without the Location grant on Android 8.0+.
        val ssid = sanitizeSsid(info.ssid, locationOk)
        val bssid = sanitizeBssid(info.bssid, locationOk)

        // ---- ChromeOS honest-null (see the CHROMEOS block in the header) ----
        // ONC — the vocabulary ChromeOS feeds ARC — has NO dBm field (signal is a
        // 0-100 percentage there) and NO field at all for link rate, channel
        // width, or the 802.11 generation. Whatever WifiInfo hands back for those
        // on a Chromebook is either a lossy reconstruction of a percentage or an
        // Android default (e.g. WIFI_STANDARD_LEGACY, CHANNEL_WIDTH_20MHZ) that
        // would render as a CONFIDENT, WRONG claim: "802.11a/b/g" on a Wi-Fi 6E
        // Chromebook, "20 MHz" on an 80 MHz link, "-45 dBm" that was never
        // measured in dBm. All five are nulled here, at the source.
        //
        // We do NOT synthesize a percentage from the dBm either — that would be a
        // second lossy hop on top of the first, and we have no access to ONC's
        // real percentage from inside Android. Nothing-plus-a-reason is the only
        // honest answer (GL-005 / GL-008).

        val txRate: Double? = if (chromeOs) {
            null
        } else if (info.linkSpeed > 0) {
            info.linkSpeed.toDouble()
        } else {
            null
        }

        val rxRate: Double? =
            if (chromeOs) {
                null
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val rx = info.rxLinkSpeedMbps
                if (rx > 0) rx.toDouble() else null
            } else {
                null
            }

        val standard: String? =
            if (chromeOs) {
                null
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                standardLabel(info.wifiStandard)
            } else {
                null
            }

        // Security IS an ONC field (WiFi.Security), so it survives on ChromeOS.
        val securityToken: String? = securityTokenForConnected(wifiManager, info, locationOk)

        // Channel width: WifiInfo does not carry it, but the matching ScanResult
        // does (ScanResult.channelWidth, available since API 23). Match the
        // connected BSSID in getScanResults() and map the enum to MHz. Scan
        // results are Location-gated, so this only resolves with the grant; null
        // otherwise and the Dart side says "Not reported". ONC has no
        // channel-width vocabulary, so on ChromeOS it is never read.
        val channelWidthMhz: Int? =
            if (chromeOs) null else channelWidthForConnected(wifiManager, info, locationOk)

        // Regulatory country code: WifiManager.getCountryCode() exists but is a
        // restricted/system API (hidden on the public SDK, and limited on
        // Android 11+ — often requires a privileged caller). Try it reflectively;
        // a null/blank/refused result stays null and the Dart side shows the
        // honest Android limit note rather than a fabricated value.
        val countryCode: String? = readCountryCode(wifiManager)

        return mapOf(
            "interfaceName" to "wlan0",
            "poweredOn" to poweredOn,
            // Rides on every snapshot so the Dart side can carry the precise
            // ChromeOS reason on each suppressed row (and show the notice card)
            // instead of a bare "Unavailable".
            "isChromeOs" to chromeOs,
            "ssid" to ssid,
            "bssid" to bssid,
            // ChromeOS: no trustworthy dBm exists (ONC is a 0-100 percentage with
            // no dBm field). Never a converted number.
            "rssiDbm" to if (chromeOs) null else info.rssi,
            // Android public API exposes no noise floor → SNR cannot be computed.
            "noiseDbm" to null,
            "snrDb" to null,
            "txRateMbps" to txRate,
            "rxRateMbps" to rxRate,
            "phyMode" to standard,
            "channel" to channel,
            // Channel width from the matching ScanResult (null when no scan
            // match / no Location grant, and always null on ChromeOS); the Dart
            // side says "Not reported" / names ChromeOS.
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

    private fun baseSnapshot(
        poweredOn: Boolean,
        locationOk: Boolean,
        chromeOs: Boolean,
    ): Map<String, Any?> =
        mapOf(
            "interfaceName" to "wlan0",
            "poweredOn" to poweredOn,
            "isChromeOs" to chromeOs,
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

        /// The canonical ChromeOS / ARC presence feature. Declared by every
        /// Chromebook that can run Android apps. This is the primary probe.
        private const val ARC_FEATURE = "org.chromium.arc"

        /// Declared on managed / enterprise-enrolled Chromebooks — i.e. the K-12
        /// fleet, which is exactly the population this whole fix protects.
        /// Checked as a belt-and-suspenders second probe so a managed device that
        /// somehow withheld the base feature is still identified correctly.
        private const val ARC_DEVICE_MANAGEMENT_FEATURE =
            "org.chromium.arc.device_management"
    }
}
