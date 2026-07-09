// PiBackend — runtime "are we hosted on a WLAN Pi?" detection.
//
// The SAME web bundle ships to Netlify AND onto a WLAN Pi. On the Pi, a
// same-origin backend at `/toolboxapi/` can do the network work a browser
// cannot (RECON.md §9); on Netlify there is no such backend. This service
// probes once at startup and caches the answer, so the tool grid and each tool
// screen can decide — at runtime, from one artifact — whether the Pi-hosted
// path is available.
//
// DETECTION: on WEB only, `GET /toolboxapi/health` (same-origin, ~2s). Any 200
// means a Pi backend is answering -> `available == true`. On non-web, or when
// the probe fails / times out / 404s (Netlify), `available` stays false and the
// networking tools stay hidden exactly as before — no regression, one artifact,
// two behaviors.
//
// The probe must run in main() BEFORE runApp so the first build already reflects
// the correct gate state (no flash of hidden-then-shown tiles).

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import 'pi_backend_client.dart';

class PiBackend {
  PiBackend._();

  /// The tool IDs the Pi backend serves TODAY (Phase A — each has a live REST
  /// endpoint and a wired data path). A flag is only flipped for a capability we
  /// actually back; enabling a tool whose endpoint does not exist yet would
  /// reintroduce the broken "browser attempts a socket" state (brief).
  static const Set<String> servedToolIds = <String>{
    'net-quality', // -> /toolboxapi/conntest
    'nearby-ap-scan', // -> /toolboxapi/scan
    'interface-info', // -> /toolboxapi/interfaces
  };

  static bool _available = false;

  /// True only when this build is served from a WLAN Pi whose `/toolboxapi/`
  /// backend answered the startup probe. Always false off web and on Netlify.
  static bool get available => _available;

  /// True when the Pi backend is present AND serves [toolId] today. Consulted by
  /// the tool catalog's web-availability gate.
  static bool canServe(String toolId) =>
      _available && servedToolIds.contains(toolId);

  /// One-shot startup probe. No-op (leaves [available] false) off web, so native
  /// builds are byte-for-byte unchanged. On web, a single same-origin health GET
  /// decides Pi-hosted vs not. Never throws — any failure leaves [available]
  /// false. Call once from main() before runApp.
  static Future<void> probe({PiBackendClient? client}) async {
    if (!kIsWeb) return;
    try {
      final bool ok = await (client ?? PiBackendClient())
          .health()
          .timeout(const Duration(seconds: 2));
      _available = ok;
    } catch (_) {
      _available = false;
    }
  }

  /// Test seam: force the cached availability. Not for production code.
  @visibleForTesting
  static void debugSetAvailable(bool value) => _available = value;
}
