// Controls for the Wi-Fi Classroom tool Why Two Devices Disagree
// (devices-disagree): everything that is not the picture.
//
//   - DevicesDisagreeControls: Re-sample and Reset; Apply offsets; fading;
//     the device picker and the picked device's offset, grip, body, reporting
//     step, averaging and type; the spot (band, AP distance, spacing, how
//     many devices, body loss).
//   - DevicesDisagreeExplainer: what the numbers mean, and RCPI as a concept
//     card (no RCPI value is computed: its scale is not stated as fact).
//
// PRESENTER: the controls keep the buttons, the two teaching switches and
// the picked device's offset and grip open, and fold the rest of the device
// and the spot into PresenterDisclosures, with no phone prose, so the panel
// fits a projector. The readouts live on the stage.
//
// Every value marked illustrative in spec 31 says so on screen.
//
// THEME: context.colors (dark §8 / light §8.20); device hues only on the
// device badges (§8.15.2). No status hues. ASCII copy, no em dashes.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/devices_disagree_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import '../labeled_field.dart';
import 'devices_disagree_controller.dart';
import 'devices_disagree_parts.dart';

/// The one line that marks the illustrative values.
const String kDdIllustrativeNote =
    'Illustrative values: every device offset, grip and body loss, the AP '
    'power (14 dBm) and the path loss exponent (3) are examples for '
    'teaching, not measurements of any real device.';

class DevicesDisagreeControls extends StatelessWidget {
  const DevicesDisagreeControls({super.key, required this.controller});
  final DevicesDisagreeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: PresenterMode.isActive(context)
            ? _presenter(context)
            : _phone(context),
      ),
    );
  }

  List<Widget> _presenter(BuildContext context) {
    return <Widget>[
      _buttons(context),
      const SizedBox(height: AppSpacing.xs),
      _applyOffsets(),
      _fading(),
      const SizedBox(height: AppSpacing.xs),
      _devicePicker(context),
      ..._deviceMain(context),
      PresenterDisclosure(
        title: 'This device: body, step, averaging, type',
        children: _deviceMore(context),
      ),
      PresenterDisclosure(
        title: 'The spot: band, distance, spacing, devices',
        children: _spot(context),
      ),
      const SizedBox(height: AppSpacing.xs),
      _illustrative(context),
    ];
  }

  List<Widget> _phone(BuildContext context) {
    return <Widget>[
      _buttons(context),
      const SizedBox(height: AppSpacing.sm),
      _applyOffsets(),
      _fading(),
      const SizedBox(height: AppSpacing.md),
      const DdSectionLabel('Devices'),
      const SizedBox(height: AppSpacing.xs),
      _devicePicker(context),
      ..._deviceMain(context),
      ..._deviceMore(context),
      const SizedBox(height: AppSpacing.md),
      const DdSectionLabel('The spot'),
      ..._spot(context),
      const SizedBox(height: AppSpacing.sm),
      _illustrative(context),
    ];
  }

  // ── Pieces ───────────────────────────────────────────────────────────────

  Widget _buttons(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final DevicesDisagreeController c = controller;
    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Tooltip(
            message: 'Take the next few seconds of readings (Space)',
            child: FilledButton.icon(
              onPressed: c.resample,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Re-sample'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: c.reset,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textPrimary,
              side: BorderSide(color: colors.borderStrong),
              minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            ),
          ),
        ),
      ],
    );
  }

  Widget _applyOffsets() => DdSwitchRow(
    title: 'Apply offsets',
    subtitle:
        'Subtract each device offset, as a survey tool does once you enter '
        'it per adapter',
    value: controller.applyOffsets,
    onChanged: (bool v) => controller.applyOffsets = v,
  );

  Widget _fading() => DdSwitchRow(
    title: 'Fading',
    subtitle: 'Off shows only the fixed parts of each reading',
    value: controller.config.fadingOn,
    onChanged: (bool v) => controller.fadingOn = v,
  );

  /// One chip per device in use; the picked one is edited below.
  Widget _devicePicker(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final DevicesDisagreeController c = controller;
    return Semantics(
      label: 'Device to edit',
      container: true,
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          for (int i = 0; i < c.config.deviceCount; i++)
            ChoiceChip(
              avatar: _chipDot(context, i),
              label: Text('Device ${deviceLetter(i)}'),
              selected: i == c.selected,
              showCheckmark: false,
              selectedColor: colors.primary,
              labelStyle: TextStyle(
                color: i == c.selected ? colors.onPrimary : colors.textPrimary,
              ),
              backgroundColor: colors.surface2,
              side: BorderSide(color: colors.borderStrong),
              tooltip: 'Edit ${c.deviceName(i)}',
              onSelected: (_) => c.selectDevice(i),
            ),
        ],
      ),
    );
  }

  Widget _chipDot(BuildContext context, int i) {
    final WifiLabClientStyle s = ddDeviceStyle(i, context.colors);
    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: s.hue,
          shape: BoxShape.circle,
          border: Border.all(color: context.colors.borderStrong),
        ),
      ),
    );
  }

  /// The picked device's offset and grip: the two numbers the lesson turns.
  List<Widget> _deviceMain(BuildContext context) {
    final DevicesDisagreeController c = controller;
    final DeviceSettings d = c.selectedDevice;
    final String who = 'Device ${deviceLetter(c.selected)}';
    return <Widget>[
      _slider(
        context,
        label: '$who offset (illustrative)',
        valueText: DdFormat.signedDb(d.offsetDb),
        value: d.offsetDb,
        min: kMinOffsetDb,
        max: kMaxOffsetDb,
        divisions: (kMaxOffsetDb - kMinOffsetDb).round(),
        onChanged: (double v) =>
            c.editDevice((DeviceSettings s) => s.copyWith(offsetDb: v)),
        semantic: (double v) => '$who offset ${DdFormat.signedDb(v)}',
      ),
      _slider(
        context,
        label: '$who orientation and grip loss (illustrative)',
        valueText: DdFormat.db(d.gripLossDb),
        value: d.gripLossDb,
        min: 0,
        max: kMaxGripLossDb,
        divisions: kMaxGripLossDb.round(),
        onChanged: (double v) =>
            c.editDevice((DeviceSettings s) => s.copyWith(gripLossDb: v)),
        semantic: (double v) => '$who grip loss ${DdFormat.db(v)}',
      ),
    ];
  }

  /// The rest of the picked device.
  List<Widget> _deviceMore(BuildContext context) {
    final DevicesDisagreeController c = controller;
    final DeviceSettings d = c.selectedDevice;
    final String who = 'Device ${deviceLetter(c.selected)}';
    return <Widget>[
      DdSwitchRow(
        title: '$who held against a body',
        subtitle:
            'Adds the body loss set below (illustrative, '
            '${DdFormat.db(c.config.bodyLossDb)})',
        value: d.bodyOn,
        onChanged: (bool v) =>
            c.editDevice((DeviceSettings s) => s.copyWith(bodyOn: v)),
      ),
      const SizedBox(height: AppSpacing.xxs),
      AppToggle<int>(
        label: '$who reporting step',
        value: d.stepDb,
        expand: true,
        items: const <AppToggleItem<int>>[(1, '1 dB'), (2, '2 dB')],
        onChanged: (int v) =>
            c.editDevice((DeviceSettings s) => s.copyWith(stepDb: v)),
      ),
      _slider(
        context,
        label: '$who averages the last',
        valueText: d.averaging == 1 ? '1 reading' : '${d.averaging} readings',
        value: d.averaging.toDouble(),
        min: 1,
        max: kMaxAveraging.toDouble(),
        divisions: kMaxAveraging - 1,
        onChanged: (double v) => c.editDevice(
          (DeviceSettings s) => s.copyWith(averaging: v.round()),
        ),
        semantic: (double v) => '$who averages the last ${v.round()} readings',
      ),
      const SizedBox(height: AppSpacing.xs),
      LabeledField(
        label: '$who type',
        field: AppSelect<DeviceKind>(
          value: d.kind,
          semanticLabel: '$who type',
          items: <AppSelectItem<DeviceKind>>[
            for (final DeviceKind k in DeviceKind.values) (k, k.label),
          ],
          onChanged: (DeviceKind k) =>
              c.editDevice((DeviceSettings s) => s.copyWith(kind: k)),
        ),
      ),
    ];
  }

  /// Band, distance, spacing, device count and the body loss amount.
  List<Widget> _spot(BuildContext context) {
    final DevicesDisagreeController c = controller;
    final DdConfig cfg = c.config;
    final double half = cfg.band.wavelength / 2;
    return <Widget>[
      const SizedBox(height: AppSpacing.xs),
      AppToggle<DdBand>(
        label: 'Band',
        value: cfg.band,
        expand: true,
        items: <AppToggleItem<DdBand>>[
          for (final DdBand b in DdBand.values) (b, b.label),
        ],
        onChanged: (DdBand b) => c.band = b,
      ),
      _slider(
        context,
        label: 'AP distance',
        valueText: DdFormat.meters(cfg.distanceM),
        value: cfg.distanceM,
        min: kMinDistanceM,
        max: kMaxDistanceM,
        divisions: (kMaxDistanceM - kMinDistanceM).round(),
        onChanged: (double v) => c.distanceM = v.roundToDouble(),
        semantic: (double v) => 'AP distance ${v.round()} meters',
      ),
      _slider(
        context,
        label: 'Spacing between devices',
        valueText: DdFormat.cm(cfg.spacingM),
        value: cfg.spacingM,
        min: 0,
        max: kMaxSpacingM,
        divisions: (kMaxSpacingM * 100).round(),
        onChanged: (double v) => c.spacingM = (v * 100).roundToDouble() / 100,
        semantic: (double v) =>
            'Spacing between devices ${(v * 100).round()} centimeters',
      ),
      Text(
        'Half a wavelength at ${cfg.band.label} is '
        '${DdFormat.cmPrecise(half)}. Farther apart than that, each device '
        'sees its own fade.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.colors.textTertiary),
      ),
      const SizedBox(height: AppSpacing.xs),
      AppToggle<int>(
        label: 'Devices',
        value: cfg.deviceCount,
        expand: true,
        items: const <AppToggleItem<int>>[
          (2, 'Two'),
          (3, 'Three'),
          (4, 'Four'),
        ],
        onChanged: (int v) => c.deviceCount = v,
      ),
      _slider(
        context,
        label: 'Body loss when on (illustrative)',
        valueText: DdFormat.db(cfg.bodyLossDb),
        value: cfg.bodyLossDb,
        min: 0,
        max: kMaxBodyLossDb,
        divisions: kMaxBodyLossDb.round(),
        onChanged: (double v) => c.bodyLossDb = v,
        semantic: (double v) => 'Body loss ${DdFormat.db(v)}',
      ),
    ];
  }

  Widget _illustrative(BuildContext context) =>
      const DdNote(Icons.info_outline, kDdIllustrativeNote);

  Widget _slider(
    BuildContext context, {
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String Function(double) semantic,
  }) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.xs),
        ExcludeSemantics(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
              Text(
                valueText,
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: colors.primary,
          inactiveColor: colors.disabledFill,
          label: valueText,
          semanticFormatterCallback: semantic,
        ),
      ],
    );
  }
}

// ── Explainer ────────────────────────────────────────────────────────────

/// What the numbers mean, and RCPI as a concept card. Phone and desktop
/// only; in presenter mode the instructor says it.
class DevicesDisagreeExplainer extends StatelessWidget {
  const DevicesDisagreeExplainer({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    TextStyle? body() => text.bodyMedium?.copyWith(color: colors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const DdSectionLabel('Why the numbers differ'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'RSSI (received signal strength indicator) is a number each '
                'chipset reports in its own way. Two devices at the same '
                'spot, hearing the same AP, commonly report different '
                'values.',
                style: body(),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'The difference has parts. A fixed device offset, from the '
                'antenna gain and how the chip is calibrated. How the device '
                'is turned and held. The body of the person holding it. And '
                'fading, which changes over a few centimeters and from '
                'moment to moment.',
                style: body(),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Survey tools let you enter an offset per adapter for exactly '
                'this reason. Comparing raw numbers across devices without it '
                'compares the devices, not the network. Apply offsets shows '
                'what that correction removes, and what it cannot.',
                style: body(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        DdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const DdSectionLabel('RCPI, the standardized measurement'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '802.11k defines RCPI (received channel power indicator) as a '
                'standardized measurement of received power, so readings are '
                'more comparable across devices that report it. Not every '
                'device reports it.',
                style: body(),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'This tool shows RCPI as a concept only. It does not compute '
                'RCPI values or state its scale.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
