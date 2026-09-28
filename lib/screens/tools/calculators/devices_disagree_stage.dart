// Stage for the Wi-Fi Classroom tool Why Two Devices Disagree
// (devices-disagree): the picture the instructor talks to.
//
// Top to bottom: the predict-then-reveal card; the floor (AP, distance, the
// devices side by side at one spot); one card per device with its live
// reading; the strip chart of every device's readings over the last few
// seconds with the true power dashed across it; and the readouts (true
// power, spread now, spread after offsets, average spread).
//
// PRESENTER: the stage fills its bounded box. The strip chart takes the
// height that is left, and the reveal text is shortened to one line so the
// chart keeps its room. On a phone everything stacks at fixed heights.
//
// Each painter is wrapped in a Semantics with a worded label; every number
// a painter shows is also a text readout here.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/devices_disagree_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter.dart';
import 'devices_disagree_controller.dart';
import 'devices_disagree_painters.dart';
import 'devices_disagree_parts.dart';

class DevicesDisagreeStage extends StatelessWidget {
  const DevicesDisagreeStage({super.key, required this.controller});

  final DevicesDisagreeController controller;

  static DdPaintStyle paintStyle(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return DdPaintStyle(
      sc: sc,
      deviceColors: <Color>[
        for (int i = 0; i < kMaxDevices; i++) ddDeviceStyle(i, colors).hue,
      ],
      onDevice: ddDeviceStyle(0, colors).onHue,
      primary: colors.textPrimary,
      secondary: colors.textSecondary,
      grid: colors.border,
      axis: colors.borderStrong,
      halo: colors.surface1,
      floor: colors.surface2,
      labelStyle: mono.inlineCode.copyWith(
        // Painted labels do not see MediaQuery's text scale.
        fontSize: sc.paintFont(AppTextSize.caption),
        height: 1.2,
        color: colors.textSecondary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final DdPaintStyle style = paintStyle(context);
        final bool presenting = PresenterMode.isActive(context);
        final double floorH = style.sc.markerSize(96);
        final List<Widget> top = <Widget>[
          _PredictCard(controller: controller, compact: presenting),
          SizedBox(height: presenting ? AppSpacing.xs : AppSpacing.sm),
          _Floor(controller: controller, style: style, height: floorH),
          const SizedBox(height: AppSpacing.xs),
          _DeviceCards(controller: controller),
          SizedBox(height: presenting ? AppSpacing.xs : AppSpacing.sm),
        ];
        if (presenting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ...top,
              Expanded(
                child: _StripCard(
                  controller: controller,
                  style: style,
                  fill: true,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              DevicesDisagreeReadouts(controller: controller),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ...top,
            _StripCard(controller: controller, style: style),
            const SizedBox(height: AppSpacing.sm),
            DevicesDisagreeReadouts(controller: controller),
          ],
        );
      },
    );
  }
}

/// Below this width the device cards and the readouts sit two to a row.
const double _kTwoUpBelow = 560;

/// [cells] in one row, or two to a row when the stage is narrow.
Widget _cellRows(List<Widget> cells) => LayoutBuilder(
  builder: (BuildContext context, BoxConstraints box) {
    final int perRow = box.maxWidth < _kTwoUpBelow ? 2 : cells.length;
    final List<Widget> rows = <Widget>[];
    for (int start = 0; start < cells.length; start += perRow) {
      final List<Widget> row = cells.sublist(
        start,
        (start + perRow).clamp(0, cells.length),
      );
      if (rows.isNotEmpty) rows.add(const SizedBox(height: AppSpacing.xs));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < perRow; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                Expanded(child: i < row.length ? row[i] : const SizedBox()),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  },
);

// ── Predict, then reveal ─────────────────────────────────────────────────

class _PredictCard extends StatelessWidget {
  const _PredictCard({required this.controller, required this.compact});
  final DevicesDisagreeController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final DevicesDisagreeController c = controller;
    final Widget prompt = Text(
      kDdPredictPrompt,
      style: text.titleMedium?.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
    return DdCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  header: true,
                  label: 'Predict, then reveal. $kDdPredictPrompt',
                  excludeSemantics: true,
                  child: prompt,
                ),
              ),
              if (!c.revealed) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                OutlinedButton(
                  onPressed: c.reveal,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textPrimary,
                    side: BorderSide(color: colors.borderStrong),
                    minimumSize: const Size(0, AppSpacing.minTouchTarget),
                  ),
                  child: const Text('Reveal'),
                ),
              ],
            ],
          ),
          if (c.revealed) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Semantics(
              liveRegion: true,
              child: Text(
                compact ? _shortReveal(c) : c.revealText,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The presenter keeps the answer to a line or two; the instructor says
  /// the rest.
  static String _shortReveal(DevicesDisagreeController c) =>
      'Neither, on its own. True power here is '
      '${DdFormat.dbmPrecise(c.result.trueDbm)}. Each device adds its own '
      'offset, grip, body and fading. Apply offsets removes only the fixed '
      'part.';
}

// ── Floor ────────────────────────────────────────────────────────────────

class _Floor extends StatelessWidget {
  const _Floor({
    required this.controller,
    required this.style,
    required this.height,
  });
  final DevicesDisagreeController controller;
  final DdPaintStyle style;
  final double height;

  @override
  Widget build(BuildContext context) {
    final DdConfig cfg = controller.config;
    final String devices = <String>[
      for (int i = 0; i < cfg.deviceCount; i++) deviceLetter(i),
    ].join(', ');
    return Semantics(
      label:
          'Floor: the AP is ${DdFormat.meters(cfg.distanceM, controller.units)} '
          'from one spot. Devices $devices stand side by side at that spot, '
          '${DdFormat.cm(cfg.spacingM, controller.units)} apart.',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: DdFloorPainter(
            distanceM: cfg.distanceM,
            spacingM: cfg.spacingM,
            deviceCount: cfg.deviceCount,
            style: style,
            units: controller.units,
          ),
        ),
      ),
    );
  }
}

// ── Device cards ─────────────────────────────────────────────────────────

class _DeviceCards extends StatelessWidget {
  const _DeviceCards({required this.controller});
  final DevicesDisagreeController controller;

  @override
  Widget build(BuildContext context) {
    final int n = controller.config.deviceCount;
    return _cellRows(<Widget>[
      for (int i = 0; i < n; i++) _DeviceCard(controller: controller, index: i),
    ]);
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.controller, required this.index});
  final DevicesDisagreeController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final DevicesDisagreeController c = controller;
    final DeviceSettings d = c.config.devices[index];
    final double shown = c.shownNow(index);
    final String sub = c.applyOffsets
        ? 'offset ${DdFormat.signedDb(d.offsetDb)} removed'
        : 'offset ${DdFormat.signedDb(d.offsetDb)}';
    return Semantics(
      label:
          '${c.deviceName(index)} '
          '${c.applyOffsets ? 'shows, with its offset applied,' : 'reports'} '
          '${DdFormat.dbm(shown)}',
      excludeSemantics: true,
      child: DdCard(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                DdDeviceBadge(index: index),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    d.kind.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                DdFormat.dbm(shown),
                style: sc.headlineStyle(mono.outputLarge),
              ),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Strip chart ──────────────────────────────────────────────────────────

class _StripCard extends StatelessWidget {
  const _StripCard({
    required this.controller,
    required this.style,
    this.fill = false,
  });
  final DevicesDisagreeController controller;
  final DdPaintStyle style;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final DevicesDisagreeController c = controller;
    final DdResult r = c.result;
    final String title = c.applyOffsets
        ? 'Readings with offsets applied, dBm, last $kStripSeconds seconds'
        : 'Readings, dBm, last $kStripSeconds seconds';
    final Widget chart = Semantics(
      label:
          'Strip chart of each device reading over the last $kStripSeconds '
          'seconds, with the true power of ${DdFormat.dbmPrecise(r.trueDbm)} '
          'as a dashed line. Average spread '
          '${DdFormat.db(r.meanSpread(corrected: c.applyOffsets), 1)}.',
      excludeSemantics: true,
      child: CustomPaint(
        painter: DdStripPainter(
          result: r,
          corrected: c.applyOffsets,
          style: style,
        ),
        child: const SizedBox.expand(),
      ),
    );
    return DdCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: DdSectionLabel(title)),
              Text(
                'Sample set ${c.sampleSet}',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (fill)
            Expanded(child: chart)
          else
            SizedBox(height: 240, child: chart),
        ],
      ),
    );
  }
}

// ── Readouts ─────────────────────────────────────────────────────────────

/// True power, spread now, spread after offsets and the average spread.
class DevicesDisagreeReadouts extends StatelessWidget {
  const DevicesDisagreeReadouts({super.key, required this.controller});
  final DevicesDisagreeController controller;

  @override
  Widget build(BuildContext context) {
    final DdResult r = controller.result;
    return _cellRows(<Widget>[
      _Readout(
        label: 'True power',
        value: DdFormat.dbmPrecise(r.trueDbm),
        note: 'the same for every device',
      ),
      _Readout(
        label: 'Spread now',
        value: DdFormat.db(r.spreadNow()),
        note: 'highest minus lowest',
      ),
      _Readout(
        label: 'After offsets',
        value: DdFormat.db(r.spreadNow(corrected: true)),
        note: 'spread now, offsets applied',
      ),
      _Readout(
        label: '$kStripSeconds s average',
        value: DdFormat.db(r.meanSpread(), 1),
        note:
            '${DdFormat.db(r.meanSpread(corrected: true), 1)} after '
            'offsets',
      ),
    ]);
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.label,
    required this.value,
    required this.note,
  });
  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      label: '$label $value, $note',
      excludeSemantics: true,
      child: DdCard(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: mono.outputMedium),
            ),
            Text(
              note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
