// SSID Airtime — what each extra SSID costs the channel, in airtime.
//
// PROVENANCE, and it belongs ON SCREEN rather than in a credits page
// (Keith, 2026-08-30). The model is a port of Jonathan Finney's SSID Airtime
// Calculator (github.com/fintheman/wifi-tools, MIT, (c) 2026 Jonathan Finney),
// used with his explicit permission. The engine and its provenance notes live
// in lib/services/rf/ssid_airtime.dart; this file is presentation only and
// contains no arithmetic of its own.
//
// THE NUMBER THIS TOOL EXISTS TO PRODUCE is the MARGINAL cost of SSID N+1.
// "Your beacons use 12% of the channel" starts an argument. "The next SSID you
// add costs another 1.4 points of a channel already at 12" ends one. So the
// marginal figure is the large type and the total is the supporting row --
// deliberately the opposite weighting to the upstream page, because a phone
// screen shows one number well and four badly.
//
// WHY THREE BANDS AT ONCE. The whole insight is comparative: the same SSID
// count lands very differently on 2.4 vs 5 vs 6 GHz, because 2.4 GHz has three
// non-overlapping channels to spread across and 6 GHz has dozens. Showing one
// band at a time would hide the argument. Ship data 2026-08-30 measured 2.4 GHz
// at 2.27x the channel utilisation of 5 GHz on one network.
//
// FRAME LENGTH INCLUDES THE FCS. Cross-checked 2026-08-30 against WiFi Explorer
// Pi, which displays a 327-byte beacon and computes 0.468 ms of airtime at
// 6 Mbps. Our formula reproduces 0.468 ms exactly at 331 bytes, i.e. 327 + the
// 4-byte FCS. The field hint says so, because a user copying the length off
// another analyser would otherwise under-report by about 2%.
//
// OCCUPANCY IS THE DEFAULT. Contention (DIFS + average backoff) and probe
// exchanges are both OFF unless switched on. Occupancy makes no assumption
// about contention and cannot be accused of inflating the case, which is what
// you want in front of a customer.
//
// THEME: chrome from context.colors. Numerics in DM Mono per GL-003 sec 8.5.
// Glyph note: ASCII hyphen-minus throughout; no em dash (GL-004).
//
// States (SOP-007 sec 5):
//   - success     -> valid inputs yield three band results
//   - empty       -> a blank required field blanks that band's rows to "-"
//   - error       -> out-of-range input shows an honest note, copy disabled
//   - disabled    -> copy disabled when there is nothing to copy
//   - interactive -> hover/focus/pressed on toggles, selects, fields, copy

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../services/rf/ssid_airtime.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kSsidAirtimeToolId = 'ssid-airtime';

/// The three band columns, in the order they are shown.
enum _Band {
  ghz24('2.4 GHz', noCck: false, defaultRate: 12),
  ghz5('5 GHz', noCck: true, defaultRate: 6),
  ghz6('6 GHz', noCck: true, defaultRate: 6);

  const _Band(this.label, {required this.noCck, required this.defaultRate});

  final String label;

  /// 5 and 6 GHz have no CCK, so a DSSS rate is coerced to 6 Mbps.
  final bool noCck;

  final double defaultRate;
}

class SsidAirtimeScreen extends StatefulWidget {
  const SsidAirtimeScreen({super.key});

  @override
  State<SsidAirtimeScreen> createState() => _SsidAirtimeScreenState();
}

class _SsidAirtimeScreenState extends State<SsidAirtimeScreen> {
  static final List<TextInputFormatter> _unsignedInt = <TextInputFormatter>[
    FilteringTextInputFormatter.digitsOnly,
  ];

  final TextEditingController _ssidsCtrl = TextEditingController(text: '4');
  final TextEditingController _coCtrl = TextEditingController(text: '3');
  final TextEditingController _tuCtrl = TextEditingController(text: '100');
  final TextEditingController _beaconCtrl = TextEditingController(text: '331');

  final FocusNode _ssidsFocus = FocusNode();
  final FocusNode _coFocus = FocusNode();
  final FocusNode _tuFocus = FocusNode();
  final FocusNode _beaconFocus = FocusNode();

  bool _mbssid = false;
  bool _contention = false;
  bool _probes = false;
  WifiAmendment _amendment = WifiAmendment.ax;

  final Map<_Band, double> _rates = <_Band, double>{
    for (final _Band b in _Band.values) b: b.defaultRate,
  };

  String? _ssidsError;
  String? _coError;
  String? _tuError;
  String? _beaconError;

  @override
  void dispose() {
    _ssidsCtrl.dispose();
    _coCtrl.dispose();
    _tuCtrl.dispose();
    _beaconCtrl.dispose();
    _ssidsFocus.dispose();
    _coFocus.dispose();
    _tuFocus.dispose();
    _beaconFocus.dispose();
    super.dispose();
  }

  /// Parse with an inclusive range guard. Returns null and sets an error when
  /// the field is blank or out of range, so a band renders "-" rather than a
  /// number computed from a value the user did not mean.
  int? _readInt(
    TextEditingController c,
    int min,
    int max,
    void Function(String?) setError,
  ) {
    final String raw = c.text.trim();
    if (raw.isEmpty) {
      setError(null);
      return null;
    }
    final int? v = int.tryParse(raw);
    if (v == null) {
      setError('Enter a whole number');
      return null;
    }
    if (v < min || v > max) {
      setError('$min to $max');
      return null;
    }
    setError(null);
    return v;
  }

  SsidAirtimeShared get _shared => SsidAirtimeShared(
        countContention: _contention,
        countProbes: _probes,
        amendment: _amendment,
      );

  /// Compute one band, or null when any shared input is unusable.
  SsidAirtimeResult? _resultFor(_Band band) {
    final int? ssids = _readInt(_ssidsCtrl, 1, 64, (e) => _ssidsError = e);
    final int? co = _readInt(_coCtrl, 1, 40, (e) => _coError = e);
    final int? tu = _readInt(_tuCtrl, 20, 1000, (e) => _tuError = e);
    final int? beacon = _readInt(_beaconCtrl, 60, 2300, (e) => _beaconError = e);
    if (ssids == null || co == null || tu == null || beacon == null) return null;

    return SsidAirtimeCalculator(_shared).compute(
      SsidAirtimeBand(
        name: band.label,
        ssids: ssids,
        mbssid: _mbssid,
        rate: _rates[band]!,
        coChannelAps: co,
        noCck: band.noCck,
        beaconIntervalTu: tu.toDouble(),
        beaconBytes: beacon.toDouble(),
      ),
    );
  }

  bool get _hasAnyResult =>
      _Band.values.any((b) => _resultFor(b) != null);

  /// Null disables the copy affordance, which is the SOP-007 "disabled" state.
  String? _copyTextOrNull() => _hasAnyResult ? _buildCopyText() : null;

  String _buildCopyText() {
    final StringBuffer sb = StringBuffer()
      ..writeln('SSID Airtime')
      ..writeln('SSIDs per AP: ${_ssidsCtrl.text}   MBSSID: ${_mbssid ? "on" : "off"}')
      ..writeln('Co-channel APs: ${_coCtrl.text}   Beacon interval: ${_tuCtrl.text} TU')
      ..writeln('Beacon length: ${_beaconCtrl.text} bytes (incl. FCS)   ${_amendment.label}')
      ..writeln('Contention: ${_contention ? "counted" : "occupancy only"}   '
          'Probes: ${_probes ? "counted" : "not counted"}')
      ..writeln();
    for (final _Band b in _Band.values) {
      final SsidAirtimeResult? r = _resultFor(b);
      if (r == null) {
        sb.writeln('${b.label}: -');
        continue;
      }
      sb
        ..writeln('${b.label} at ${_rateLabel(_rates[b]!)}')
        ..writeln('  next SSID costs   ${r.marginalPercent.toStringAsFixed(2)} points')
        ..writeln('  management total  ${r.total.toStringAsFixed(2)} % of channel')
        ..writeln('  longest TXOP      ${(r.longestTxopUs / 1000).toStringAsFixed(3)} ms');
    }
    sb
      ..writeln()
      ..writeln('Management airtime only: no data frames, no RTS/CTS, no retries.')
      ..writeln('Model ported from Jonathan Finney\'s SSID Airtime Calculator (MIT).');
    return sb.toString();
  }

  static String _rateLabel(double r) =>
      r == r.roundToDouble() ? '${r.toInt()} Mbps' : '$r Mbps';

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SSID Airtime'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _copyTextOrNull),
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
                      ConceptGraphicBand(
                        toolId: kSsidAirtimeToolId,
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic(kSsidAirtimeToolId))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      for (final _Band b in _Band.values) ...<Widget>[
                        _bandCard(b, text, mono),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      _honestyCard(text),
                      const SizedBox(height: AppSpacing.md),
                      _attributionCard(text),
                      ToolHelpFooter(toolId: kSsidAirtimeToolId),
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

  Widget _inputCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LabeledField(
              label: 'SSIDs advertised',
              hint: '(per access point)',
              semanticLabel: 'SSIDs advertised per access point',
              field: TextField(
                controller: _ssidsCtrl,
                focusNode: _ssidsFocus,
                keyboardType: TextInputType.number,
                inputFormatters: _unsignedInt,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                style: mono.outputLarge
                    .copyWith(fontSize: AppTextSize.fieldNumeric),
                cursorColor: colors.textAccent,
                decoration: InputDecoration(
                  hintText: '4',
                  errorText: _ssidsError,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            LabeledField(
              label: 'Audible co-channel APs',
              hint: '(including this one)',
              semanticLabel: 'Audible co-channel access points including this one',
              field: TextField(
                controller: _coCtrl,
                focusNode: _coFocus,
                keyboardType: TextInputType.number,
                inputFormatters: _unsignedInt,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                style: mono.outputLarge
                    .copyWith(fontSize: AppTextSize.fieldNumeric),
                cursorColor: colors.textAccent,
                decoration:
                    InputDecoration(hintText: '3', errorText: _coError),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppToggle<bool>(
              label: 'Beaconing',
              value: _mbssid,
              expand: true,
              semanticLabel: 'Beaconing mode',
              items: const <AppToggleItem<bool>>[
                (false, 'One per SSID'),
                (true, 'MBSSID'),
              ],
              onChanged: (bool v) => setState(() => _mbssid = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final _Band b in _Band.values) ...<Widget>[
              LabeledField(
                label: '${b.label} basic rate',
                hint: b.noCck ? '(no CCK up here)' : '(CCK allowed)',
                semanticLabel: '${b.label} management basic rate',
                field: AppSelect<double>(
                  value: _rates[b]!,
                  semanticLabel: '${b.label} basic rate',
                  items: kBasicRates
                      .where((double r) => !(b.noCck && kDsssRates.contains(r)))
                      .map((double r) => (r, _rateLabel(r)))
                      .toList(growable: false),
                  onChanged: (double r) => setState(() => _rates[b] = r),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            LabeledField(
              label: 'Beacon length',
              hint: '(bytes, including the 4-byte FCS)',
              semanticLabel: 'Beacon length in bytes including FCS',
              field: TextField(
                controller: _beaconCtrl,
                focusNode: _beaconFocus,
                keyboardType: TextInputType.number,
                inputFormatters: _unsignedInt,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                style: mono.outputLarge
                    .copyWith(fontSize: AppTextSize.fieldNumeric),
                cursorColor: colors.textAccent,
                decoration:
                    InputDecoration(hintText: '331', errorText: _beaconError),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            LabeledField(
              label: 'Beacon interval',
              hint: '(TU, 1 TU = 1024 us)',
              semanticLabel: 'Beacon interval in time units',
              field: TextField(
                controller: _tuCtrl,
                focusNode: _tuFocus,
                keyboardType: TextInputType.number,
                inputFormatters: _unsignedInt,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                style: mono.outputLarge
                    .copyWith(fontSize: AppTextSize.fieldNumeric),
                cursorColor: colors.textAccent,
                decoration:
                    InputDecoration(hintText: '100', errorText: _tuError),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            LabeledField(
              label: 'Amendment',
              hint: '(sets beacon size estimates)',
              semanticLabel: 'Wi-Fi amendment',
              field: AppSelect<WifiAmendment>(
                value: _amendment,
                semanticLabel: 'Amendment',
                items: WifiAmendment.values
                    .map((WifiAmendment a) => (a, a.label))
                    .toList(growable: false),
                onChanged: (WifiAmendment a) => setState(() => _amendment = a),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppToggle<bool>(
              label: 'Airtime counted',
              value: _contention,
              expand: true,
              semanticLabel: 'Whether contention is counted',
              items: const <AppToggleItem<bool>>[
                (false, 'Occupancy'),
                (true, 'With contention'),
              ],
              onChanged: (bool v) => setState(() => _contention = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppToggle<bool>(
              label: 'Probe exchanges',
              value: _probes,
              expand: true,
              semanticLabel: 'Whether probe exchanges are counted',
              items: const <AppToggleItem<bool>>[
                (false, 'Not counted'),
                (true, 'Counted'),
              ],
              onChanged: (bool v) => setState(() => _probes = v),
            ),
          ],
        ),
      ),
    );
  }

  /// One band's result. The MARGINAL figure is the large type on purpose.
  Widget _bandCard(_Band band, TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final SsidAirtimeResult? r = _resultFor(band);
    final String rate = _rateLabel(_rates[band]!);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(band.label, style: text.titleMedium),
                Text(
                  '$rate basic',
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'One more SSID would cost',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  r == null ? '-' : r.marginalPercent.toStringAsFixed(2),
                  style: mono.outputXL.copyWith(
                    fontSize: AppTextSize.h1,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'points of channel time',
                  style:
                      text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _row(text, mono, colors, 'Management total',
                r == null ? '-' : '${r.total.toStringAsFixed(2)} %'),
            _row(text, mono, colors, 'Beacons',
                r == null ? '-' : '${r.beaconPercent.toStringAsFixed(2)} %'),
            if (_probes)
              _row(text, mono, colors, 'Probe exchanges',
                  r == null ? '-' : '${r.probePercent.toStringAsFixed(2)} %'),
            _row(
              text,
              mono,
              colors,
              'Longest transmit opportunity',
              r == null
                  ? '-'
                  : '${(r.longestTxopUs / 1000).toStringAsFixed(3)} ms',
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    TextTheme text,
    AppMonoText mono,
    AppColorScheme colors,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(value, style: mono.outputMedium),
        ],
      ),
    );
  }

  /// What the number is NOT. Same posture as the datetime-standards screen:
  /// where the app cannot answer, it says what it did not count and why.
  Widget _honestyCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('What this does not count', style: text.titleSmall),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Management frames only. No data traffic, no RTS/CTS or ERP '
              'protection, no retries, no DTIM or buffered multicast. Real '
              'channel utilisation is higher than the figure above, not lower.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _contention
                  ? 'Contention is counted: this includes DIFS plus average '
                      'backoff, so it is the channel time an AP consumes to win '
                      'the medium.'
                  : 'Occupancy only: the time the frames themselves are on the '
                      'air. No assumption is made about contention, which is '
                      'what makes this figure hard to argue with.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// Attribution in the UI, not a credits screen (Keith, 2026-08-30).
  Widget _attributionCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Where this model comes from', style: text.titleSmall),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'The airtime model is a port of the SSID Airtime Calculator by '
              'Jonathan Finney, used with his permission and MIT licensed. He '
              'built it because best-practice documents kept asking for three '
              'or four SSIDs without ever costing them.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
