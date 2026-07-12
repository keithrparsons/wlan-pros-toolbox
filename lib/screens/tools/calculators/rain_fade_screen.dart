// ITU Rain Fade calculator.
//
// Estimates rain attenuation on a microwave Wi-Fi backhaul link. Matters most
// above 10 GHz, where rain absorbs and scatters the signal.
//
// Two ITU recommendations:
//   ITU-R P.838-3 — specific attenuation:   gamma = k · R^alpha   (dB/km)
//   ITU-R P.530   — path-length reduction:   L_eff = L / (1 + L/d0)
//                   with d0 = 35 · e^(-0.015·R)
//   Rain attenuation = gamma · L_eff   (dB)
//
// k and alpha come from ITU-R P.838-3 Table 5 — all 116 published rows, 1 to
// 1000 GHz, transcribed from the ITU's own PDF. The 28-row table this screen
// previously carried was wrong in ALL 28 ROWS; it under-reported rain fade by
// ~12% at a routine 10 GHz / 25 mm-h backhaul case.
//
// Off-table frequencies use log-log interpolation on frequency (log-linear on
// alpha); frequencies at or beyond the table ends clamp to the nearest node.
// With rows at 1 GHz granularity through 100 GHz, interpolation error is
// negligible for any real link.
//
// ⚠️ k_H is genuinely NON-MONOTONIC below 6 GHz. Read the warning block on
// [RainFadeScreen.ituRain] before you "correct" anything in that table.
//
// Reference: Deliverables/2026-07-11-calculator-verification/CABLE-AND-RAIN-DATA.md
//
// Unit conventions mirror the PWA inputs exactly:
//   Frequency  — GHz (fixed; PWA has no toggle here).
//   Rain rate  — mm/hr.
//   Path length — km (default) or mi; mi ×1.60934 to km (PWA toKm).
//   Polarization — Horizontal or Vertical (PWA H / V select).
//
// Outputs match the PWA fmt() decimals:
//   Rain attenuation       — dB,    2 decimals  (fmt(attenuation, 2))
//   Specific attenuation γ — dB/km, 4 decimals  (fmt(gamma, 4))
//   Effective path length  — km,    2 decimals  (fmt(L_eff, 2))
//
// Edge cases (PWA guards f/R/L all finite and > 0):
// - Empty / partial input on any field → blank all outputs (no crash).
// - Any of frequency, rain rate, path length <= 0 → blank outputs, show "—".
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public class so it is unit-testable against the PWA values.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../utils/decimal_input.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/field_unit_row.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Path-length input units, mirroring the PWA rf-dist-unit select (km / mi).
enum PathUnit { km, mi }

/// Wave polarization, mirroring the PWA rf-pol select (H / V).
enum Polarization { horizontal, vertical }

class RainFadeScreen extends StatefulWidget {
  const RainFadeScreen({super.key});

  // ─── Coefficient table (ITU-R P.838-3, Table 5) ────────────────────────────
  //
  // SOURCE: Recommendation ITU-R P.838-3, "Specific attenuation model for rain
  // for use in prediction methods" (Question ITU-R 201/3), TABLE 5, pp. 5-8.
  // All 116 published rows, 1 GHz to 1000 GHz, transcribed from the ITU's own
  // PDF. Each row: [freqGHz, kH, alphaH, kV, alphaV].
  //
  // The 28-row table that shipped before this was wrong in every single row.
  //
  // ⚠️⚠️ DO NOT "SANITY-CHECK" THESE COEFFICIENTS INTO BEING WRONG ⚠️⚠️
  //
  // k_H IS GENUINELY NON-MONOTONIC IN FREQUENCY BELOW 6 GHz:
  //
  //     3.0 GHz -> 1.390e-4
  //     3.5 GHz -> 1.155e-4
  //     4.0 GHz -> 1.071e-4     <-- a real trough, not a transcription error
  //     4.5 GHz -> 1.340e-4
  //
  // That dip is a genuine feature of the ITU's curve-fit (it is visible in
  // P.838-3 Figure 1) and it appears in the official Table 5. alpha_H likewise
  // PEAKS around 5 GHz (1.6969) and falls away on both sides; alpha_V peaks
  // around 5.5 GHz (1.5882).
  //
  // Anyone who applies a naive "attenuation must increase with frequency" guard
  // here will flag valid ITU data as broken, and may then "fix" it into being
  // wrong. There is no monotonicity assertion in the tests, deliberately, and
  // the dip is asserted POSITIVELY in rain_fade_screen_test.dart so that
  // smoothing it away breaks a test that explains why you should not.
  //
  // Validate against the table below, verbatim, and nothing else.
  static const List<List<double>> ituRain = [
    [1, 0.0000259, 0.9691, 0.0000308, 0.8592],
    [1.5, 0.0000443, 1.0185, 0.0000574, 0.8957],
    [2, 0.0000847, 1.0664, 0.0000998, 0.9490],
    [2.5, 0.0001321, 1.1209, 0.0001464, 1.0085],
    [3, 0.0001390, 1.2322, 0.0001942, 1.0688],
    [3.5, 0.0001155, 1.4189, 0.0002346, 1.1387],
    [4, 0.0001071, 1.6009, 0.0002461, 1.2476],
    [4.5, 0.0001340, 1.6948, 0.0002347, 1.3987],
    [5, 0.0002162, 1.6969, 0.0002428, 1.5317],
    [5.5, 0.0003909, 1.6499, 0.0003115, 1.5882],
    [6, 0.0007056, 1.5900, 0.0004878, 1.5728],
    [7, 0.001915, 1.4810, 0.001425, 1.4745],
    [8, 0.004115, 1.3905, 0.003450, 1.3797],
    [9, 0.007535, 1.3155, 0.006691, 1.2895],
    [10, 0.01217, 1.2571, 0.01129, 1.2156],
    [11, 0.01772, 1.2140, 0.01731, 1.1617],
    [12, 0.02386, 1.1825, 0.02455, 1.1216],
    [13, 0.03041, 1.1586, 0.03266, 1.0901],
    [14, 0.03738, 1.1396, 0.04126, 1.0646],
    [15, 0.04481, 1.1233, 0.05008, 1.0440],
    [16, 0.05282, 1.1086, 0.05899, 1.0273],
    [17, 0.06146, 1.0949, 0.06797, 1.0137],
    [18, 0.07078, 1.0818, 0.07708, 1.0025],
    [19, 0.08084, 1.0691, 0.08642, 0.9930],
    [20, 0.09164, 1.0568, 0.09611, 0.9847],
    [21, 0.1032, 1.0447, 0.1063, 0.9771],
    [22, 0.1155, 1.0329, 0.1170, 0.9700],
    [23, 0.1286, 1.0214, 0.1284, 0.9630],
    [24, 0.1425, 1.0101, 0.1404, 0.9561],
    [25, 0.1571, 0.9991, 0.1533, 0.9491],
    [26, 0.1724, 0.9884, 0.1669, 0.9421],
    [27, 0.1884, 0.9780, 0.1813, 0.9349],
    [28, 0.2051, 0.9679, 0.1964, 0.9277],
    [29, 0.2224, 0.9580, 0.2124, 0.9203],
    [30, 0.2403, 0.9485, 0.2291, 0.9129],
    [31, 0.2588, 0.9392, 0.2465, 0.9055],
    [32, 0.2778, 0.9302, 0.2646, 0.8981],
    [33, 0.2972, 0.9214, 0.2833, 0.8907],
    [34, 0.3171, 0.9129, 0.3026, 0.8834],
    [35, 0.3374, 0.9047, 0.3224, 0.8761],
    [36, 0.3580, 0.8967, 0.3427, 0.8690],
    [37, 0.3789, 0.8890, 0.3633, 0.8621],
    [38, 0.4001, 0.8816, 0.3844, 0.8552],
    [39, 0.4215, 0.8743, 0.4058, 0.8486],
    [40, 0.4431, 0.8673, 0.4274, 0.8421],
    [41, 0.4647, 0.8605, 0.4492, 0.8357],
    [42, 0.4865, 0.8539, 0.4712, 0.8296],
    [43, 0.5084, 0.8476, 0.4932, 0.8236],
    [44, 0.5302, 0.8414, 0.5153, 0.8179],
    [45, 0.5521, 0.8355, 0.5375, 0.8123],
    [46, 0.5738, 0.8297, 0.5596, 0.8069],
    [47, 0.5956, 0.8241, 0.5817, 0.8017],
    [48, 0.6172, 0.8187, 0.6037, 0.7967],
    [49, 0.6386, 0.8134, 0.6255, 0.7918],
    [50, 0.6600, 0.8084, 0.6472, 0.7871],
    [51, 0.6811, 0.8034, 0.6687, 0.7826],
    [52, 0.7020, 0.7987, 0.6901, 0.7783],
    [53, 0.7228, 0.7941, 0.7112, 0.7741],
    [54, 0.7433, 0.7896, 0.7321, 0.7700],
    [55, 0.7635, 0.7853, 0.7527, 0.7661],
    [56, 0.7835, 0.7811, 0.7730, 0.7623],
    [57, 0.8032, 0.7771, 0.7931, 0.7587],
    [58, 0.8226, 0.7731, 0.8129, 0.7552],
    [59, 0.8418, 0.7693, 0.8324, 0.7518],
    [60, 0.8606, 0.7656, 0.8515, 0.7486],
    [61, 0.8791, 0.7621, 0.8704, 0.7454],
    [62, 0.8974, 0.7586, 0.8889, 0.7424],
    [63, 0.9153, 0.7552, 0.9071, 0.7395],
    [64, 0.9328, 0.7520, 0.9250, 0.7366],
    [65, 0.9501, 0.7488, 0.9425, 0.7339],
    [66, 0.9670, 0.7458, 0.9598, 0.7313],
    [67, 0.9836, 0.7428, 0.9767, 0.7287],
    [68, 0.9999, 0.7400, 0.9932, 0.7262],
    [69, 1.0159, 0.7372, 1.0094, 0.7238],
    [70, 1.0315, 0.7345, 1.0253, 0.7215],
    [71, 1.0468, 0.7318, 1.0409, 0.7193],
    [72, 1.0618, 0.7293, 1.0561, 0.7171],
    [73, 1.0764, 0.7268, 1.0711, 0.7150],
    [74, 1.0908, 0.7244, 1.0857, 0.7130],
    [75, 1.1048, 0.7221, 1.1000, 0.7110],
    [76, 1.1185, 0.7199, 1.1139, 0.7091],
    [77, 1.1320, 0.7177, 1.1276, 0.7073],
    [78, 1.1451, 0.7156, 1.1410, 0.7055],
    [79, 1.1579, 0.7135, 1.1541, 0.7038],
    [80, 1.1704, 0.7115, 1.1668, 0.7021],
    [81, 1.1827, 0.7096, 1.1793, 0.7004],
    [82, 1.1946, 0.7077, 1.1915, 0.6988],
    [83, 1.2063, 0.7058, 1.2034, 0.6973],
    [84, 1.2177, 0.7040, 1.2151, 0.6958],
    [85, 1.2289, 0.7023, 1.2265, 0.6943],
    [86, 1.2398, 0.7006, 1.2376, 0.6929],
    [87, 1.2504, 0.6990, 1.2484, 0.6915],
    [88, 1.2607, 0.6974, 1.2590, 0.6902],
    [89, 1.2708, 0.6959, 1.2694, 0.6889],
    [90, 1.2807, 0.6944, 1.2795, 0.6876],
    [91, 1.2903, 0.6929, 1.2893, 0.6864],
    [92, 1.2997, 0.6915, 1.2989, 0.6852],
    [93, 1.3089, 0.6901, 1.3083, 0.6840],
    [94, 1.3179, 0.6888, 1.3175, 0.6828],
    [95, 1.3266, 0.6875, 1.3265, 0.6817],
    [96, 1.3351, 0.6862, 1.3352, 0.6806],
    [97, 1.3434, 0.6850, 1.3437, 0.6796],
    [98, 1.3515, 0.6838, 1.3520, 0.6785],
    [99, 1.3594, 0.6826, 1.3601, 0.6775],
    [100, 1.3671, 0.6815, 1.3680, 0.6765],
    [120, 1.4866, 0.6640, 1.4911, 0.6609],
    [150, 1.5823, 0.6494, 1.5896, 0.6466],
    [200, 1.6378, 0.6382, 1.6443, 0.6343],
    [300, 1.6286, 0.6296, 1.6286, 0.6262],
    [400, 1.5860, 0.6262, 1.5820, 0.6256],
    [500, 1.5418, 0.6253, 1.5366, 0.6272],
    [600, 1.5013, 0.6262, 1.4967, 0.6293],
    [700, 1.4654, 0.6284, 1.4622, 0.6315],
    [800, 1.4335, 0.6315, 1.4321, 0.6334],
    [900, 1.4050, 0.6353, 1.4056, 0.6351],
    [1000, 1.3795, 0.6396, 1.3822, 0.6365],
  ];

  // ─── Math (pure) ────────────────────────────────────────────────────────────
  // Mirrors app.js: toKm, interpolateITU, calcRainFade.

  /// Normalize a path length to km (PWA toKm). Only km / mi here, matching the
  /// PWA rf-dist-unit options. mi ×1.60934.
  static double pathToKm(double value, PathUnit unit) {
    switch (unit) {
      case PathUnit.mi:
        return value * 1.60934;
      case PathUnit.km:
        return value;
    }
  }

  /// Look up (k, alpha) for [freqGHz] at the given polarization, with the PWA's
  /// log-log frequency interpolation (PWA interpolateITU). Returns a record
  /// `(k, alpha)`. Clamps to the nearest node outside the table range.
  static (double k, double alpha) interpolateITU(
    double freqGHz,
    Polarization pol,
  ) {
    // polIdx 0 → H columns (kH=1, alphaH=2); 1 → V columns (kV=3, alphaV=4).
    final int polIdx = pol == Polarization.horizontal ? 0 : 1;
    final int ki = 1 + polIdx * 2;
    final int ai = 2 + polIdx * 2;

    final List<List<double>> t = ituRain;
    if (freqGHz <= t[0][0]) return (t[0][ki], t[0][ai]);
    final List<double> last = t[t.length - 1];
    if (freqGHz >= last[0]) return (last[ki], last[ai]);

    for (int i = 0; i < t.length - 1; i++) {
      final double f1 = t[i][0];
      final double f2 = t[i + 1][0];
      if (freqGHz >= f1 && freqGHz <= f2) {
        // log-log interpolation on frequency; log-linear on alpha.
        final double frac =
            (math.log(freqGHz) - math.log(f1)) / (math.log(f2) - math.log(f1));
        final double k = math.exp(
          math.log(t[i][ki]) +
              frac * (math.log(t[i + 1][ki]) - math.log(t[i][ki])),
        );
        final double a = t[i][ai] + frac * (t[i + 1][ai] - t[i][ai]);
        return (k, a);
      }
    }
    // Unreachable given the clamps above; satisfies the return contract.
    return (last[ki], last[ai]);
  }

  /// Specific attenuation gamma in dB/km (ITU-R P.838-3): k · R^alpha.
  static double specificAttenuation(
    double freqGHz,
    double rainRateMmHr,
    Polarization pol,
  ) {
    final (double k, double alpha) = interpolateITU(freqGHz, pol);
    return k * math.pow(rainRateMmHr, alpha).toDouble();
  }

  /// Effective path length in km (simplified ITU-R P.530-17):
  /// L / (1 + L/d0), d0 = 35 · e^(-0.015·R).
  static double effectivePathKm(double pathKm, double rainRateMmHr) {
    final double d0 = 35 * math.exp(-0.015 * rainRateMmHr);
    return pathKm / (1 + pathKm / d0);
  }

  /// Total rain attenuation in dB: gamma · L_eff (PWA calcRainFade).
  static double rainAttenuationDb(
    double freqGHz,
    double rainRateMmHr,
    double pathKm,
    Polarization pol,
  ) {
    final double gamma = specificAttenuation(freqGHz, rainRateMmHr, pol);
    final double leff = effectivePathKm(pathKm, rainRateMmHr);
    return gamma * leff;
  }

  @override
  State<RainFadeScreen> createState() => _RainFadeScreenState();
}

class _RainFadeScreenState extends State<RainFadeScreen> {
  final TextEditingController _freqCtrl = TextEditingController();
  final TextEditingController _rainCtrl = TextEditingController();
  final TextEditingController _pathCtrl = TextEditingController();

  final FocusNode _freqFocus = FocusNode();
  final FocusNode _rainFocus = FocusNode();
  final FocusNode _pathFocus = FocusNode();

  PathUnit _pathUnit = PathUnit.km;
  Polarization _pol = Polarization.horizontal;

  // Computed outputs, or null when input is empty / invalid / non-positive.
  double? _attenDb;
  double? _gamma;
  double? _leffKm;

  // Unsigned-decimal only. Frequency, rain rate, and path length are positive
  // values typed by hand, so no sign and no scientific notation here.
  static final List<TextInputFormatter> _unsignedDecimal = unsignedDecimalFormatters;

  @override
  void dispose() {
    _freqCtrl.dispose();
    _rainCtrl.dispose();
    _pathCtrl.dispose();
    _freqFocus.dispose();
    _rainFocus.dispose();
    _pathFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? freq = tryParseFlexibleDouble(_freqCtrl.text);
    final double? rain = tryParseFlexibleDouble(_rainCtrl.text);
    final double? path = tryParseFlexibleDouble(_pathCtrl.text);
    if (freq == null || rain == null || path == null) {
      _blank();
      return;
    }
    final double pathKm = RainFadeScreen.pathToKm(path, _pathUnit);
    // PWA guards f <= 0 || R <= 0 || L <= 0 before computing.
    if (freq <= 0 || rain <= 0 || pathKm <= 0) {
      _blank();
      return;
    }
    final double gamma = RainFadeScreen.specificAttenuation(freq, rain, _pol);
    final double leff = RainFadeScreen.effectivePathKm(pathKm, rain);
    setState(() {
      _gamma = gamma;
      _leffKm = leff;
      _attenDb = gamma * leff;
    });
  }

  void _blank() {
    setState(() {
      _attenDb = null;
      _gamma = null;
      _leffKm = null;
    });
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  /// PWA fmt(n, decimals): fixed decimals, "—" when not finite or null.
  static String _fmt(double? n, int decimals) {
    if (n == null || !n.isFinite) return '—';
    return n.toStringAsFixed(decimals);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rain Fade'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until frequency,
        // rain rate, and path length are all valid and > 0 (no attenuation);
        // copies the rain-fade breakdown as a labeled text block. Copy leads;
        // no help icon here.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            return Align(
              alignment: AppSpacing.calculatorVerticalAlignment(constraints),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.calculatorMaxWidth,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    edge,
                    AppSpacing.sm,
                    edge,
                    edge + AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // §8.6.2 concept-graphic header band — first child, above
                      // the input card. Self-collapses when no graphic is
                      // bundled, so the 24px gap below it disappears too.
                      ConceptGraphicBand(
                        toolId: 'rain-fade',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('rain-fade'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formulaCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _referenceCard(text, mono),
                      ToolHelpFooter(toolId: 'rain-fade'),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// §8.16 copy payload — the rain-fade breakdown as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) until frequency, rain rate, and path
  /// length are all valid and > 0, so there is no attenuation to keep. Inputs
  /// (path with its unit, polarization word) and outputs match the on-screen
  /// result rows.
  String? _buildCopyText() {
    final double? atten = _attenDb;
    if (atten == null || !atten.isFinite) return null;

    final String pathUnit = _pathUnit == PathUnit.km ? 'km' : 'mi';
    final String pol = _pol == Polarization.horizontal
        ? 'Horizontal'
        : 'Vertical';

    return (StringBuffer()
          ..writeln('Rain Fade')
          ..writeln('Frequency: ${_freqCtrl.text.trim()} GHz')
          ..writeln('Rain rate: ${_rainCtrl.text.trim()} mm/hr')
          ..writeln('Path length: ${_pathCtrl.text.trim()} $pathUnit')
          ..writeln('Polarization: $pol')
          ..writeln('Rain attenuation: ${_fmt(atten, 2)} dB')
          ..writeln('Specific attenuation (γ): ${_fmt(_gamma, 4)} dB/km')
          ..writeln('Effective path length: ${_fmt(_leffKm, 2)} km'))
        .toString()
        .trimRight();
  }

  Widget _inputCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Frequency — GHz, no unit toggle (PWA fixes this at GHz).
          LabeledField(
            label: 'Frequency',
            hint: '(GHz)',
            semanticLabel: 'Frequency in GHz',
            field: _numberField(
              controller: _freqCtrl,
              focusNode: _freqFocus,
              hintText: '11',
              monoStyle: mono.outputLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Rain rate — mm/hr, no unit toggle.
          LabeledField(
            label: 'Rain rate',
            hint: '(mm/hr)',
            semanticLabel: 'Rain rate in millimeters per hour',
            field: _numberField(
              controller: _rainCtrl,
              focusNode: _rainFocus,
              hintText: '25',
              monoStyle: mono.outputLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Typical: light 2, moderate 12, heavy 25, extreme 50 mm/hr.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Path length — km / mi toggle.
          _pathRow(mono),
          const SizedBox(height: AppSpacing.sm),
          // Polarization — H / V toggle, full width.
          _polRow(text),
          const SizedBox(height: AppSpacing.md),
          _resultRow(text, mono),
        ],
      ),
    );
  }

  TextField _numberField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required TextStyle monoStyle,
  }) {
    final AppColorScheme colors = context.colors;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: _unsignedDecimal,
      onChanged: (_) => _recompute(),
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      style: monoStyle.copyWith(fontSize: AppTextSize.fieldNumeric),
      cursorColor: colors.textAccent,
      decoration: InputDecoration(hintText: hintText),
    );
  }

  Widget _pathRow(AppMonoText mono) {
    // FieldUnitRow reflows the unit selector beneath the field below 440px so
    // it never clips at phone widths (Vera web-demo gate, 2026-06-02).
    return FieldUnitRow(
      field: LabeledField(
        label: 'Path length',
        hint: _pathUnit == PathUnit.km ? '(km)' : '(mi)',
        semanticLabel:
            'Path length in ${_pathUnit == PathUnit.km ? 'kilometers' : 'miles'}',
        field: _numberField(
          controller: _pathCtrl,
          focusNode: _pathFocus,
          hintText: '10',
          monoStyle: mono.outputLarge,
        ),
      ),
      unit: AppToggle<PathUnit>(
        value: _pathUnit,
        items: const [(PathUnit.km, 'km'), (PathUnit.mi, 'mi')],
        onChanged: (u) {
          setState(() => _pathUnit = u);
          _recompute();
        },
      ),
    );
  }

  Widget _polRow(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Polarization',
          style: text.labelMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppToggle<Polarization>(
          value: _pol,
          items: const [
            (Polarization.horizontal, 'Horizontal'),
            (Polarization.vertical, 'Vertical'),
          ],
          onChanged: (p) {
            setState(() => _pol = p);
            _recompute();
          },
        ),
      ],
    );
  }

  Widget _resultRow(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rain attenuation',
          style: text.labelMedium?.copyWith(
            color: colors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // One SR node for the headline: "Rain attenuation: 12.50 dB" (or "not
        // calculated"), instead of value/unit fragments (Vera finding #6).
        Semantics(
          label: 'Rain attenuation',
          value: _attenDb == null
              ? 'not calculated'
              : '${_fmt(_attenDb, 2)} dB',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SelectableText(
                _fmt(_attenDb, 2),
                style: mono.outputXL.copyWith(
                  color: _attenDb == null
                      ? colors.textTertiary
                      : colors.textAccent,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'dB',
                style: text.labelLarge?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Secondary outputs, matching the PWA's gamma / L_eff result rows.
        _secondaryRow(
          text,
          mono,
          label: 'Specific attenuation (γ)',
          value: _fmt(_gamma, 4),
          unit: 'dB/km',
        ),
        const SizedBox(height: AppSpacing.xs),
        _secondaryRow(
          text,
          mono,
          label: 'Effective path length',
          value: _fmt(_leffKm, 2),
          unit: 'km',
        ),
      ],
    );
  }

  Widget _secondaryRow(
    TextTheme text,
    AppMonoText mono, {
    required String label,
    required String value,
    required String unit,
  }) {
    final AppColorScheme colors = context.colors;
    // One SR node per row: "Specific attenuation (γ): 0.0123 dB/km" (or "not
    // calculated"), instead of label/value/unit fragments (Vera finding #6).
    return Semantics(
      label: label,
      value: value == '—' ? 'not calculated' : '$value $unit',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SelectableText(
            value,
            style: mono.inlineCode.copyWith(
              color: value == '—'
                  ? colors.textTertiary
                  : colors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            unit,
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _formulaCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Formula',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            // Real Greek γ and α; d0 keeps an ASCII digit — ₀ is absent from
            // the bundled Roboto Mono.
            'γ = k · R^α            (dB/km)',
            style: mono.robotoMono.copyWith(color: colors.textPrimary),
          ),
          SelectableText(
            'L_eff = L / (1 + L/d0)  (km)',
            style: mono.robotoMono.copyWith(color: colors.textPrimary),
          ),
          SelectableText(
            'A = γ · L_eff          (dB)',
            style: mono.robotoMono.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'k and α from ITU-R P.838-3 by frequency and polarization. '
            'd0 = 35 · e^(-0.015·R) per the simplified ITU-R P.530 path '
            'reduction. R is rain rate in mm/hr.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    // Anchor values computed from the same coefficients this screen uses, at a
    // 10 km horizontal path. Shows how rain fade explodes with frequency.
    final List<List<String>> refs = const [
      ['6 GHz', '25 mm/hr', '0.83 dB'],
      ['11 GHz', '25 mm/hr', '5.43 dB'],
      ['18 GHz', '25 mm/hr', '14.97 dB'],
      ['11 GHz', '50 mm/hr', '11.36 dB'],
      ['23 GHz', '50 mm/hr', '42.99 dB'],
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reference points',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '10 km horizontal path.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...refs.map((row) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Column widths snap to the 8px base unit (GL-003 §4).
                  SizedBox(
                    width: 80,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[1],
                      style: mono.inlineCode.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[2],
                      style: mono.inlineCode.copyWith(
                        color: colors.textAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
