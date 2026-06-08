// WLAN Pros Toolbox — entry point.
//
// Dark-only theme (GL-003 §8 scope), IBM Plex Sans + DM Mono + Roboto Mono as
// bundled Flutter font families (pubspec `flutter: fonts:`), Material 3, named
// routes for live tools; category screens push themselves with a typed
// argument.

import 'package:flutter/material.dart';

import 'data/antenna_fundamentals_diagrams.dart';
import 'data/connector_diagrams.dart';
import 'data/connector_photos.dart';
import 'data/connector_sections.dart';
import 'data/mac_bit_field_diagram.dart';
import 'data/tool_assets.dart';
import 'router/app_router.dart';
import 'services/help/tool_help_loader.dart';
import 'services/network/dart_ping_icmp_backend.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

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

  // Same convention for the Antenna Connectors per-connector diagram SVGs
  // (assets/connector-diagrams/<id>.svg). Until Charta's diagrams are bundled,
  // ConnectorDiagrams.has() stays false and each connector's diagram slot is
  // simply omitted — the data screen ships fully working today. A failure here
  // must never block startup.
  try {
    await ConnectorDiagrams.ensureLoaded();
  } catch (_) {
    // Manifest unavailable → has() stays false → diagram slots omitted. No crash.
  }

  // Same convention for the Antenna Fundamentals teaching diagrams
  // (assets/tool-diagrams/antenna-fundamentals/<slug>.svg). If the manifest is
  // unavailable, AntennaFundamentalsDiagrams.has() stays false and each diagram
  // band is omitted — the teaching prose still reads end-to-end. A failure here
  // must never block startup.
  try {
    await AntennaFundamentalsDiagrams.ensureLoaded();
  } catch (_) {
    // Manifest unavailable → has() stays false → diagram bands omitted. No crash.
  }

  // Same convention for the Antenna Connectors per-connector PHOTOS
  // (assets/connector-photos/<id>.jpg). We only ship a photo where a CC0/PD
  // photo actually exists; ConnectorPhotos.has() gates on both the bundle and
  // the vetted metadata map. A failure here must never block startup — has()
  // stays false and the photo slot is omitted (the line diagram still shows).
  try {
    await ConnectorPhotos.ensureLoaded();
  } catch (_) {
    // Manifest unavailable → has() stays false → photo slots omitted. No crash.
  }

  // Same convention for the Antenna Connectors editorial SECTION diagrams
  // (assets/connector-sections/<key>.svg: polarity-explained, size-comparison).
  // A failure here must never block startup — ConnectorSections.has() stays
  // false and each section renders its text without the diagram.
  try {
    await ConnectorSections.ensureLoaded();
  } catch (_) {
    // Manifest unavailable → has() stays false → section diagrams omitted.
  }

  // Same convention for the named MAC first-octet bit-field diagram on the
  // Naming & Addressing Conventions reference page
  // (assets/tool-graphics/mac-bit-field.svg). If the manifest is unavailable,
  // MacBitFieldDiagram.has() stays false and the bit-field band is omitted —
  // the data page still reads end-to-end. A failure here must never block
  // startup.
  try {
    await MacBitFieldDiagram.ensureLoaded();
  } catch (_) {
    // Manifest unavailable → has() stays false → bit-field band omitted.
  }

  // Load + cache the bundled tool-help JSON once (assets/help/tool_help.json).
  // Synchronous helpForId() reads the cache after this completes; a failure
  // here must never block startup — helpForId just returns null (no help
  // affordance shown), exactly like a tool with no entry. No crash.
  try {
    await ToolHelpLoader.ensureLoaded();
  } catch (_) {
    // Asset unavailable → helpForId() stays null → help icons hide. No crash.
  }

  // §8.20.5 — appearance controller. Default System; loads the persisted
  // Light/Dark pick (if any) before the first frame so there is no theme flash.
  // A storage failure leaves it on System (load() never throws).
  final ThemeController themeController = ThemeController();
  await themeController.load();

  runApp(ToolboxApp(themeController: themeController));
}

class ToolboxApp extends StatelessWidget {
  const ToolboxApp({super.key, required this.themeController});

  /// Owns the §8.20.5 ThemeMode (System / Light / Dark). Exposed via the
  /// inherited [ThemeControllerScope] so the Appearance toggle can drive it.
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return ThemeControllerScope(
      controller: themeController,
      child: ListenableBuilder(
        listenable: themeController,
        builder: (BuildContext context, Widget? _) {
          return _buildApp(themeController.mode);
        },
      ),
    );
  }

  Widget _buildApp(ThemeMode themeMode) {
    return MaterialApp(
      title: 'WLAN Pros Toolbox',
      debugShowCheckedModeBanner: false,
      // §8.20.6 — light theme on `theme:`, dark on `darkTheme:`, selection via
      // `themeMode:`. `ThemeMode.system` resolves to the dark brand default on a
      // dark-set OS and the §8.20 light theme on a light-set OS.
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
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
        // The Live streaming trigger fires a PLAIN, fire-and-forget Shortcut URL
        // with no x-callback return, so there is no deep-link return to route —
        // the former ShortcutDeepLinkRouter wrap was removed with the snapshot
        // one-tap trigger. The app passively consumes the Live stream instead.
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child,
        );
      },
    );
  }
}
