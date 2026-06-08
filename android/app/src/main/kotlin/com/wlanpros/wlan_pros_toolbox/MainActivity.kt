package com.wlanpros.wlan_pros_toolbox

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
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
// Honesty (GL-005 / GL-008): every field the public Android API cannot supply
// is returned as a genuine null — never an estimate. Android exposes no noise
// floor, so noiseDbm and snrDb are always null and SNR is never computed.
// SSID/BSSID require ACCESS_FINE_LOCATION granted at runtime; without it Android
// redacts them and we pass null with locationAuthorized=false so the Dart UI
// shows its honest Location-gate card.
class MainActivity : FlutterActivity() {
    private val multicastChannelName = "lan_discovery/multicast"
    private val wifiInfoChannelName = "com.wlanpros.toolbox/wifi_info"
    private var multicastLock: WifiManager.MulticastLock? = null

    // The pending Flutter result for an in-flight runtime permission request, so
    // the onRequestPermissionsResult callback can resolve the same Dart Future.
    private var pendingPermissionResult: MethodChannel.Result? = null

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
                    "requestLocationPermission" -> requestLocationPermission(result)
                    "openLocationSettings" -> result.success(openAppSettings())
                    else -> result.notImplemented()
                }
            }
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
