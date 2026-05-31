package com.wlanpros.wlan_pros_toolbox

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// SPIKE-HSD-01 — Android multicast lock for the LAN Discovery prototype.
//
// Android drops inbound multicast frames by default to save power, so the
// mDNS/Bonjour browse (multicast_dns over UDP/5353) returns nothing unless a
// Wi-Fi multicast lock is held for the duration of the browse. This exposes a
// tiny method channel the Dart mDNS pass calls to acquire/release the lock
// around a scan. Requires CHANGE_WIFI_MULTICAST_STATE (declared in the
// manifest). Deleted with the spike (TICKET-HSD-02).
class MainActivity : FlutterActivity() {
    private val channelName = "lan_discovery/multicast"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        acquire()
                        result.success(true)
                    }
                    "release" -> {
                        release()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun acquire() {
        if (multicastLock?.isHeld == true) return
        val wifi = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("lan_discovery_mdns").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun release() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    override fun onDestroy() {
        release()
        super.onDestroy()
    }
}
