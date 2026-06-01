// Rendered-pixel golden tests for the 19 reference-table screens (Vera F-04).
//
// Until now the reference tables passed only code review and *computed*
// contrast checks — no one had snapshotted the actual rendered pixels, so a
// layout regression (overflow, clipped column, wrong weight, a token that
// resolves differently than expected) could ship unseen. These tests render
// each reference screen with the production theme (AppTheme.dark) and the real
// bundled typefaces (loaded in flutter_test_config.dart) and compare against a
// committed baseline PNG.
//
// Two widths per screen:
//   - 800 px  — the desktop/tablet layout (LayoutBuilder isDesktop @720, so
//               this exercises the wide branch and the calculatorMaxWidth clamp).
//   - 320 px  — the narrowest phone surface we support. This closes the F-04
//               320 px golden check: it is where horizontal-scroll tables,
//               fixed-width cells, and the row-grouping wrappers are most
//               likely to overflow or clip.
//
// Generating the baselines (build-locked for the agent; Larry runs centrally):
//   flutter test --update-goldens test/screens/reference/
// then review every test/screens/reference/goldens/*.png by eye before commit —
// --update-goldens writes whatever renders, so a defect captured as the
// baseline would lock the defect in. The first generation is the visual gate,
// not the test run.
//
// Re-running without --update-goldens compares against those baselines and
// fails on any pixel drift, which is the regression guard going forward.
//
// Note on fonts: the baselines are only valid if the bundled IBM Plex Sans /
// DM Mono / Roboto Mono faces loaded (see flutter_test_config.dart). If a
// future google_fonts bump changes a family name, the goldens will render in a
// fallback face and must be regenerated.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/reference/ap_placement_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/channel_map_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/coax_cable_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/db_reference_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ethernet_cable_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ethernet_pinout_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/fiber_optic_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/frame_exchange_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/mcs_index_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/osi_model_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/poe_reference_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/reason_codes_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/rf_connectors_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/roaming_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/signal_thresholds_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/spectrum_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/standards_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_channels_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wpa_security_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// One reference screen under test: a stable slug for the baseline filename and
/// a builder for a fresh instance (each test gets its own to avoid shared
/// state between the two width variants).
typedef _RefScreen = ({String slug, Widget Function() build});

/// The 19 reference screens, keyed by the same slug their tool id uses so the
/// golden filenames line up with the catalog.
final List<_RefScreen> _screens = <_RefScreen>[
  (slug: 'ap_placement', build: () => const ApPlacementScreen()),
  (slug: 'channel_map', build: () => const ChannelMapScreen()),
  (slug: 'coax_cable', build: () => const CoaxCableScreen()),
  (slug: 'db_reference', build: () => const DbReferenceScreen()),
  (slug: 'ethernet_cable', build: () => const EthernetCableScreen()),
  (slug: 'ethernet_pinout', build: () => const EthernetPinoutScreen()),
  (slug: 'fiber_optic', build: () => const FiberOpticScreen()),
  (slug: 'frame_exchange', build: () => const FrameExchangeScreen()),
  (slug: 'mcs_index', build: () => const McsIndexScreen()),
  (slug: 'osi_model', build: () => const OsiModelScreen()),
  (slug: 'poe_reference', build: () => const PoeReferenceScreen()),
  (slug: 'reason_codes', build: () => const ReasonCodesScreen()),
  (slug: 'rf_connectors', build: () => const RfConnectorsScreen()),
  (slug: 'roaming', build: () => const RoamingScreen()),
  (slug: 'signal_thresholds', build: () => const SignalThresholdsScreen()),
  (slug: 'spectrum', build: () => const SpectrumScreen()),
  (slug: 'standards', build: () => const StandardsScreen()),
  (slug: 'wifi_channels', build: () => const WifiChannelsScreen()),
  (slug: 'wpa_security', build: () => const WpaSecurityScreen()),
];

/// Width variants. 320 is the narrow-phone case F-04 calls out; 800 is the
/// wide (desktop/tablet) branch. Height is generous so the whole scroll surface
/// is captured rather than just the viewport.
const List<({String name, double width})> _variants = <({
  String name,
  double width
})>[
  (name: '320w', width: 320),
  (name: '800w', width: 800),
];

const double _captureHeight = 2400;

Future<void> _pumpAndCapture(
  WidgetTester tester,
  Widget screen,
  double width,
  String goldenPath,
) async {
  await tester.binding.setSurfaceSize(Size(width, _captureHeight));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = Size(width, _captureHeight);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: MediaQuery(
        // Pin textScaler so a host's accessibility settings cannot shift the
        // baseline; pin a fixed size so layout is deterministic.
        data: MediaQueryData(
          size: Size(width, _captureHeight),
          textScaler: const TextScaler.linear(1.0),
        ),
        child: screen,
      ),
    ),
  );
  // Let any SVG concept graphics and font shaping settle before snapping.
  await tester.pumpAndSettle();

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(goldenPath),
  );
}

void main() {
  group('reference screen goldens', () {
    for (final _RefScreen s in _screens) {
      for (final variant in _variants) {
        testWidgets('${s.slug} @ ${variant.name}', (WidgetTester tester) async {
          await _pumpAndCapture(
            tester,
            s.build(),
            variant.width,
            'goldens/${s.slug}_${variant.name}.png',
          );
        });
      }
    }
  });
}
