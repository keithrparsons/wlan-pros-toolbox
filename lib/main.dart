// WLAN Pros Toolbox — entry point.
//
// Dark-only theme (GL-003 §8 scope), IBM Plex Sans + DM Mono + Roboto Mono as
// bundled Flutter font families (pubspec `flutter: fonts:`), Material 3, named
// routes for live tools; category screens push themselves with a typed
// argument.

import 'package:flutter/material.dart';

import 'data/tool_assets.dart';
import 'router/app_router.dart';
import 'router/shortcut_deep_link_router.dart';
import 'services/network/dart_ping_icmp_backend.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Binding up first so the async asset-manifest load below can run before the
  // first frame paints.
  WidgetsFlutterBinding.ensureInitialized();

  // Typography is bundled as Flutter font families (IBM Plex Sans / DM Mono /
  // Roboto Mono — see pubspec `flutter: fonts:`) and referenced by family name
  // in lib/theme/. Nothing is fetched at runtime, so type renders fully offline
  // / on first launch — critical for the macOS sandbox (no network.client
  // entitlement) and for offline use on any platform.

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
      // Shared navigator key so the one-tap-trigger deep-link router (TICKET-03)
      // can navigate to a tool route on the cold-relaunch path, where no screen
      // is listening. Reuses this Navigator; adds no second nav system.
      navigatorKey: AppRouter.navigatorKey,
      initialRoute: AppRouter.home,
      routes: AppRouter.routes,
      onUnknownRoute: AppRouter.onUnknownRoute,
      // App-wide keyboard dismissal. The iOS number pad
      // (TextInputType.number / numberWithOptions without `signed`) renders no
      // return/Done key, so the per-field `textInputAction: TextInputAction.done`
      // on the RF calculators is inert — there is no key to trigger it and no
      // other affordance to drop the keyboard, which covers the results on
      // EIRP / Link Budget / Fresnel etc. (live-device bug, 2026-05-30).
      //
      // The shared input primitive (LabeledField) receives its field as an
      // opaque Widget, so `onTapOutside` cannot be attached there. Wrapping the
      // whole app in a translucent GestureDetector that unfocuses on any tap
      // outside a text field is the equivalent standard Flutter idiom and fixes
      // every screen at once from one place — including any field that does not
      // route through LabeledField. `translucent` so the tap still reaches the
      // widgets beneath (buttons, list rows): this only adds the unfocus, it
      // does not swallow the tap. It is additive and safe for fields that
      // already dismiss via a return key (e.g. Lat/Long, signed number pad):
      // tapping outside simply dismisses, matching that field's behavior.
      builder: (BuildContext context, Widget? child) {
        // ShortcutDeepLinkRouter subscribes to the iOS one-tap-trigger return
        // streams and deep-links to the originating tool (warm + cold). Placing
        // it in the MaterialApp builder keeps it under the navigator key and
        // alive for the app's lifetime so the cold-launch buffer flushes on
        // first listen. Inert off-iOS and when no deep-link return arrives.
        return ShortcutDeepLinkRouter(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: child,
          ),
        );
      },
    );
  }
}
