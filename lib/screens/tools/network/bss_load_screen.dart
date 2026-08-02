// BSS Load (802.11 element ID 11) readout: the access point's own advertised
// view of how busy it is.
//
// THE FIRST NON-TEST CONSUMER of `bss_load_decoder.dart`. Everything the decoder
// was rewritten twice to preserve is preserved here or it is lost here, so read
// `bss_load_presentation.dart` before changing a string on this screen: the
// grouping decision, the reason there are eight headlines for seven enum
// members, and the rule about which copy may describe an access point all live
// there, next to the words they govern.
//
// WHAT THIS SCREEN WILL NOT DO, stated up front because each one is a mistake
// that was available and declined:
//
//   * IT COMPUTES NO VERDICT. The decoder returns three numbers and one
//     out-of-range flag. This screen renders three numbers and one out-of-range
//     flag. There is no "busy channel" grade, no station-count threshold and no
//     traffic-light, because the decoder never gave it one and inventing one
//     here would be a judgement wearing a measurement's clothes.
//   * IT SHOWS THE WIRE VALUE BESIDE EVERY CONVERTED FIGURE. A percentage is a
//     conversion; the octet it came from is the evidence
//     ([[feedback_a_derived_value_in_quotation_position]]).
//   * AN ALL-ZERO READING IS A READING. An idle access point on a quiet channel
//     advertises zeros, and they render as zeros in the same style as any other
//     number, never as a blank or a dash.
//   * IT NEVER BLAMES THE WI-FI FOR OUR OWN BLIND SPOT
//     ([[feedback_app_blames_the_wifi]]). Of the outcomes this screen renders,
//     exactly two describe the access point. The rest describe this device, this
//     capture, this build, or a gap in what we were told, and they say so in the
//     eyebrow above the headline.
//
// STATES (SOP-007 section 5):
//   - loading   -> progress indicator; Read again and Copy both disabled.
//   - success   -> the three numbers, each beside its wire value.
//   - "empty"   -> the eight named unavailable readings. NOT one grey wall.
//   - error     -> the read threw. The platform source swallows its own channel
//                  failures, so this is reachable through the injected seam.
//   - disabled  -> Read again while a read is in flight; Copy with nothing kept.
//   - web       -> NetworkUnavailableView.
//
// Build: Felix 2026-08-02, on Keith's direct ask.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/bss_load_decoder.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/wifi_info_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/status_chip.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'bss_load_presentation.dart';
import 'network_unavailable_view.dart';

/// One read: the decoder's answer, plus the platform facts the decoder cannot
/// see, plus which BSS the bytes belonged to.
class BssLoadSnapshot {
  const BssLoadSnapshot({
    required this.reading,
    required this.context,
    required this.bssid,
  });

  /// The decoder's answer. Sealed, so the screen must branch.
  final BssLoadReading reading;

  /// What the screen knows and the decoder does not.
  final BssLoadReadContext context;

  /// The BSS the information elements belonged to, echoed by the platform, or
  /// null when no match was made. Shown so a reader can tell which radio these
  /// numbers describe, never invented.
  final String? bssid;
}

/// Where a reading comes from. One seam, so a test can drive every state
/// without standing up a method channel or an access point.
abstract class BssLoadSource {
  /// Reads once. Implementations return an honest reading rather than throwing
  /// for an ordinary miss; a throw here is a genuine fault and surfaces as the
  /// error state.
  Future<BssLoadSnapshot> read();
}

/// The shipping source: macOS hands up raw beacon information elements, the
/// shared decoder walks them, and Location is consulted only where it gates
/// anything.
class PlatformBssLoadSource implements BssLoadSource {
  PlatformBssLoadSource({WifiInfoService? service})
    : _service = service ?? WifiInfoService();

  final WifiInfoService _service;

  @override
  Future<BssLoadSnapshot> read() async {
    final ApIeBlob blob = await _service.connectedApIeBlob();

    // A NULL BLOB IS NOT AN ABSENCE, and the decoder takes the null directly so
    // no null-handling at this call site can get that wrong.
    final BssLoadReading reading = decodeBssLoad(blob.ieBytes);

    // Location gates information elements on macOS only, and a platform that
    // exposes none has no grant worth reporting. Asking anyway would put a
    // Location sentence on a screen where Location is beside the point.
    final bool exposes = _service.connectedApIeBlobSupported;
    LocationAuthStatus? auth;
    if (exposes) {
      auth = await _service.locationAuthorizationStatus();
    }

    return BssLoadSnapshot(
      reading: reading,
      context: BssLoadReadContext(
        platformExposesInformationElements: exposes,
        locationAuth: auth,
      ),
      bssid: blob.bssid,
    );
  }
}

/// BSS Load readout for the connected access point.
class BssLoadScreen extends StatefulWidget {
  const BssLoadScreen({super.key, this.source, this.service});

  /// Test seam. Defaults to [PlatformBssLoadSource].
  final BssLoadSource? source;

  /// Used for the Location remedy actions (grant / open settings). Defaults to
  /// a real [WifiInfoService].
  final WifiInfoService? service;

  @override
  State<BssLoadScreen> createState() => _BssLoadScreenState();
}

class _BssLoadScreenState extends State<BssLoadScreen> {
  late final BssLoadSource _source;
  late final WifiInfoService _service;

  bool _reading = false;
  String? _error;
  BssLoadSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? WifiInfoService();
    _source = widget.source ?? PlatformBssLoadSource(service: _service);
    if (NetworkSupport.bssLoadSupported) {
      // Snapshot on open, like Wi-Fi Information. Nothing here is a scan and
      // nothing leaves the device.
      _read();
    }
  }

  Future<void> _read() async {
    if (_reading) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final BssLoadSnapshot snapshot = await _source.read();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _reading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reading = false;
        // The last good snapshot is deliberately kept: a failed re-read does not
        // erase a reading we really took.
        _error = 'The read failed before it produced anything: $e';
      });
    }
  }

  Future<void> _applyRemedy(BssLoadRemedy remedy) async {
    switch (remedy) {
      case BssLoadRemedy.none:
        return;
      case BssLoadRemedy.requestLocationPermission:
        await _service.requestLocationPermission();
      case BssLoadRemedy.openLocationSettings:
        await _service.openLocationSettings();
    }
    if (!mounted) return;
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BSS Load'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// Section 8.16 copy payload. Null (so the affordance renders disabled) until
  /// a read has produced something, and never while one is in flight.
  ///
  /// THE EXPORT CARRIES THE SAME ATTRIBUTION THE SCREEN SHOWS. A copied result
  /// that dropped the "About this read" line would be the collapse this screen
  /// refuses, happening one paste later.
  String? _buildCopyText() {
    if (_reading) return null;
    final BssLoadSnapshot? snapshot = _snapshot;
    if (snapshot == null) return null;

    final StringBuffer buf = StringBuffer()..writeln('BSS Load (element 11)');
    if (snapshot.bssid != null) buf.writeln('BSSID: ${snapshot.bssid}');

    final BssLoadReading reading = snapshot.reading;
    switch (reading) {
      case BssLoadDecoded(:final BssLoad load):
        final BssLoadNumbers n = BssLoadNumbers.of(load);
        buf
          ..writeln('Associated stations: ${n.stationCount}')
          ..writeln(
            'Channel utilization: ${n.channelUtilization} '
            '(${n.channelUtilizationRaw} on the wire)',
          )
          ..writeln(
            'Available admission capacity: ${n.admissionCapacity} '
            '(${n.admissionCapacityMicroseconds}, raw '
            '${n.admissionCapacityRaw})',
          );
        if (n.admissionCapacityExceedsFullScale) {
          buf.writeln(
            'Admission capacity is above full scale, shown as read and never '
            'capped.',
          );
        }
      case BssLoadUnavailable():
        final BssLoadUnavailableCopy copy = bssLoadUnavailableCopy(
          reading,
          context: snapshot.context,
        );
        buf
          ..writeln('No reading. ${copy.attribution.label}.')
          ..writeln(copy.headline)
          ..writeln(copy.body);
        if (copy.octetDiagnostic != null) buf.writeln(copy.octetDiagnostic);
    }
    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.bssLoadSupported) {
      return NetworkUnavailableView(
        toolName: 'BSS Load',
        reason: NetworkSupport.unavailableReason ?? NetworkUnavailableReason.web,
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.contentMaxWidth,
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
                children: _children(context, isDesktop),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _children(BuildContext context, bool isDesktop) {
    return <Widget>[
      ConceptGraphicBand(toolId: 'bss-load', isDesktop: isDesktop),
      if (ToolAssets.hasGraphic('bss-load')) const SizedBox(height: AppSpacing.md),
      _whatThisIsCard(context),
      const SizedBox(height: AppSpacing.sm),
      _controlCard(context),
      if (_error != null) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        _ErrorCard(message: _error!),
      ],
      if (_snapshot != null) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        _resultCard(context, _snapshot!),
      ],
      const ToolHelpFooter(toolId: 'bss-load'),
    ];
  }

  Widget _whatThisIsCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.groups_outlined, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'The access point\'s own view of its load',
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'BSS Load is element 11 of the beacon: how many stations are '
                  'associated, how busy the access point senses the medium to '
                  'be, and how much admission capacity is left. These are the '
                  'access point\'s numbers about itself, not measurements this '
                  'device made, so two access points on one channel can '
                  'honestly disagree. The element is optional and many access '
                  'points never send it.',
                  style: text.labelMedium?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Reads the beacon information elements of the access point you are '
            'connected to.',
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          if (_reading) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              label: 'Reading the beacon information elements',
              child: LinearProgressIndicator(
                backgroundColor: colors.surface0,
                color: colors.isLight ? colors.textAccent : colors.primary,
                minHeight: 6,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            // Disabled while a read is in flight: a second read would race the
            // first and the button would be a control with no honest meaning.
            onPressed: _reading ? null : _read,
            child: const Text('Read again'),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(BuildContext context, BssLoadSnapshot snapshot) {
    final BssLoadReading reading = snapshot.reading;
    switch (reading) {
      case BssLoadDecoded(:final BssLoad load):
        return _DecodedCard(load: load, bssid: snapshot.bssid);
      case BssLoadUnavailable():
        return _UnavailableCard(
          copy: bssLoadUnavailableCopy(reading, context: snapshot.context),
          bssid: snapshot.bssid,
          onRemedy: _applyRemedy,
        );
    }
  }
}

/// The three numbers, each beside the wire value it was converted from.
class _DecodedCard extends StatelessWidget {
  const _DecodedCard({required this.load, required this.bssid});

  final BssLoad load;
  final String? bssid;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final BssLoadNumbers n = BssLoadNumbers.of(load);

    return _Card(
      strongBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              'Advertised by this access point',
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (bssid != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            _BssidLine(bssid: bssid!),
          ],
          const SizedBox(height: AppSpacing.xs),
          // ZERO IS A READING. Nothing below special-cases it, so an idle access
          // point on a quiet channel prints 0 in the same register as any other
          // number rather than reading as an absence.
          _LoadRow(
            label: 'Associated stations',
            value: n.stationCount,
            wire: 'the access point\'s own count',
          ),
          _LoadRow(
            label: 'Channel utilization',
            value: n.channelUtilization,
            wire: '${n.channelUtilizationRaw} on the wire',
          ),
          _LoadRow(
            label: 'Available admission capacity',
            value: n.admissionCapacity,
            wire:
                '${n.admissionCapacityMicroseconds}, raw '
                '${n.admissionCapacityRaw}',
          ),
          if (n.admissionCapacityExceedsFullScale) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            // A SANCTIONED STATUS HUE under GL-003 section 8.13's
            // computed-verdict-only hard rule, cited by name rather than by
            // position: this is the DECODER's own out-of-range flag, and if the
            // advertised value changed the hue would go with it. It is not
            // decoration.
            const StatusChip(
              kind: StatusChipKind.headsUp,
              word: 'Above full scale',
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'This access point advertised more than one full second of medium '
              'time available, which is not physically meaningful. The figure is '
              'shown exactly as it was read and is never capped.',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One label, one value, and the wire evidence under it.
class _LoadRow extends StatelessWidget {
  const _LoadRow({
    required this.label,
    required this.value,
    required this.wire,
  });

  final String label;
  final String value;

  /// The raw value or provenance the [value] was derived from. Always present:
  /// a converted figure with nothing beside it is a claim a reader cannot check.
  final String wire;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Semantics(
      container: true,
      label: '$label, $value, $wire',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      style: text.labelMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  SelectableText(
                    value,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                wire,
                style: text.labelSmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One named unavailable reading: the attribution eyebrow, the headline, the
/// paragraph, the octet diagnostic where one exists, and a remedy where one
/// honestly exists.
class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({
    required this.copy,
    required this.bssid,
    required this.onRemedy,
  });

  final BssLoadUnavailableCopy copy;
  final String? bssid;
  final Future<void> Function(BssLoadRemedy) onRemedy;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return _Card(
      strongBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // THE ATTRIBUTION IS A WORD, NOT A HUE. See the presentation file: a
          // grouping carried by color would fail WCAG 2.2 SC 1.4.1 and would
          // misuse the section 8.13 status tokens, which are verdicts only.
          Text(
            copy.attribution.label,
            style: text.labelSmall?.copyWith(
              color: colors.textTertiary,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            header: true,
            child: Text(
              copy.headline,
              style: text.bodyLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            copy.body,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          if (copy.octetDiagnostic != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              // Labeled as ours, because it is: these counts describe the
              // element we refused, never this access point's load.
              'What our read saw: ${copy.octetDiagnostic}',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          if (bssid != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _BssidLine(bssid: bssid!),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The label above says which side of the read this reason is on.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          if (copy.remedy != BssLoadRemedy.none) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => onRemedy(copy.remedy),
              child: Text(
                copy.remedy == BssLoadRemedy.requestLocationPermission
                    ? 'Grant Location access'
                    : 'Open Location settings',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Which BSS these bytes belonged to. An identifier, so Roboto Mono per the
/// GL-003 section 8.5 identifier rule.
class _BssidLine extends StatelessWidget {
  const _BssidLine({required this.bssid});

  final String bssid;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      container: true,
      label: 'BSSID $bssid',
      child: ExcludeSemantics(
        child: SelectableText(
          'BSSID $bssid',
          style: mono.robotoMono.copyWith(
            color: colors.textTertiary,
            fontSize: AppTextSize.caption,
          ),
        ),
      ),
    );
  }
}

/// The read itself failed. Distinct from every unavailable reading: those are
/// answers, this is the absence of one.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 20, color: colors.statusDanger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    'The read did not complete',
                    style: text.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  message,
                  style: text.labelMedium?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The shared card shell, so every surface on this screen takes the same
/// section 8.1 surface, section 8.11 radius and section 4 padding.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.strongBorder = false});

  final Widget child;

  /// Use the section 8.1 `borderStrong` token on a card that carries the
  /// screen's answer, matching the results cards on the sibling network tools.
  final bool strongBorder;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: strongBorder ? colors.borderStrong : colors.border,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}
