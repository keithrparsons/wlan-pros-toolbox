// WLAN Pros Toolbox — entry point.
//
// Dark-only theme (GL-003 §8 scope), IBM Plex Sans + DM Mono via google_fonts,
// Material 3, named routes for live tools; category screens push themselves
// with a typed argument.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/tool_assets.dart';
import 'router/app_router.dart';
import 'services/network/dart_ping_icmp_backend.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Binding up first so the async asset-manifest load below can run before the
  // first frame paints.
  WidgetsFlutterBinding.ensureInitialized();

  // Force `google_fonts` to use the bundled assets only (no runtime HTTP
  // fetch). The font files are declared as assets in pubspec.yaml; this flag
  // ensures we never depend on network access just to render typography —
  // critical for the macOS sandbox and for offline use on any platform.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Install the iOS ICMP factory (SimplePing/GBPing) for Real ICMP Ping. No-op
  // off iOS and idempotent; kept behind this helper so the dart_ping_ios import
  // stays confined to the backend file.
  registerIcmpBackend();

  // Cache which per-tool icon/concept-graphic SVGs the build actually bundled,
  // so the convention-based resolver (ToolAssets) degrades gracefully for the
  // ~60 tools whose assets are not authored yet. A failure here must never
  // block startup — a missing manifest just means "no custom assets", and every
  // screen falls back cleanly (GL-003 §8.6.2 a11y: graphics are decorative).
  try {
    await ToolAssets.ensureLoaded();
  } catch (_) {
    // Manifest unavailable → has*() stays false → fallbacks render. No crash.
  }

  runApp(const ToolboxApp());
}

class ToolboxApp extends StatelessWidget {
  const ToolboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = AppTheme.dark();
    return MaterialApp(
      title: 'WLAN Pros Toolbox',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      initialRoute: AppRouter.home,
      routes: AppRouter.routes,
      onUnknownRoute: AppRouter.onUnknownRoute,
    );
  }
}
