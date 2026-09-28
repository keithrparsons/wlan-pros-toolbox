// InterfererCostStage: the picture half of the Wi-Fi Classroom tool What an
// Interferer Costs.
//
// The level meter (the 20 dB gap between preamble detect and energy detect,
// and where the selected source sits), how far away the same transmitter
// still makes you wait as Wi-Fi and as anything else, one 60 ms sample of
// your channel, and the source-level slider, which is the lesson's main
// control and so lives with the picture. It takes an
// InterfererCostController and knows nothing about the controls.
//
// PRESENTER: the three pictures fill the stage's height and IcHeadline (the
// cost readouts and the side-by-side table) stands beside them.
//
// THEME: context.colors (dark §8 / light §8.20) plus IcPalette (§8.15.2).
// Status hues only on computed verdicts and the timeline's two patterns,
// always with their words.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/interferer_cost_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../../../units/unit_system.dart';
import 'interferer_cost_controller.dart';
import 'interferer_cost_painters.dart';
import 'interferer_cost_parts.dart';
import 'rate_vs_range_parts.dart';

/// The label the corruption readouts carry everywhere.
const String kIcIllustrativeCorruption =
    'Corrupted-frame shares are illustrative: no measured curve of frame '
    'loss against level exists for these sources. The curve is shaped to '
    'agree with one 2011 measurement on a good link.';

/// The slider's label for [s].
String icLevelLabel(IcSource s) => switch (s) {
  IcSource.wifiNeighbor => 'Neighbor AP at your radio',
  IcSource.microwave => 'Oven at its strongest frequency',
  IcSource.bluetooth => 'Bluetooth at your radio',
  IcSource.videoSender => 'Video sender at your radio',
};

class InterfererCostStage extends StatelessWidget {
  const InterfererCostStage({super.key, required this.controller});

  final InterfererCostController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final bool presenter = PresenterMode.isActive(context);
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final IcResult r = controller.result;
    final IcPaintStyle style = _style(context);
    final UnitSystem units = UnitSystemScope.systemOf(context);
    final TextStyle small =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);

    final Widget meter = Semantics(
      label: _meterSemantics(r),
      excludeSemantics: true,
      child: _surface(
        context,
        CustomPaint(
          painter: IcMeterPainter(result: r, style: style),
          child: const SizedBox.expand(),
        ),
      ),
    );
    final Widget distance = Semantics(
      label: _distanceSemantics(r, units),
      excludeSemantics: true,
      child: _surface(
        context,
        CustomPaint(
          painter: IcDistancePainter(
            result: r,
            style: style,
            format: (double m) => IcFormat.dist(m, units),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    final Widget timeline = Semantics(
      label: _timelineSemantics(r),
      excludeSemantics: true,
      child: _surface(
        context,
        CustomPaint(
          painter: IcTimelinePainter(
            result: r,
            spans: icTimeline(r.config, r.config.source),
            style: style,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );

    final String ratioLine =
        '${r.widthScaled ? '${_widthRule(r)} ' : ''}'
        '${IcFormat.times(r.distanceRatio)} the distance, '
        '${IcFormat.times(r.areaRatio)} the area: '
        '10^(${r.gapDb.round()} / (10 x ${r.config.exponent.toStringAsFixed(1)})). '
        'The ratio comes from the gap alone; the distances assume a '
        '${kIcReferenceEirpDbm.round()} dBm transmitter (illustrative).';

    final Widget card = RvrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RvrSectionLabel(
            'How your radio hears the air (dBm in your channel)',
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (presenter)
            Expanded(flex: 5, child: meter)
          else
            SizedBox(height: 200, child: meter),
          _levelSlider(context),
          const SizedBox(height: AppSpacing.xxs),
          RvrSectionLabel(
            'Heard from how far, path-loss exponent '
            '${r.config.exponent.toStringAsFixed(1)}',
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (presenter)
            Expanded(flex: 3, child: distance)
          else
            SizedBox(height: 120, child: distance),
          const SizedBox(height: AppSpacing.xxs),
          Text(ratioLine, style: small),
          const SizedBox(height: AppSpacing.xs),
          const RvrSectionLabel('One 60 ms sample of your channel'),
          const SizedBox(height: AppSpacing.xxs),
          if (presenter)
            Expanded(flex: 4, child: timeline)
          else
            SizedBox(height: 150, child: timeline),
          const SizedBox(height: AppSpacing.xxs),
          _legend(context),
        ],
      ),
    );
    if (!presenter) return card;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double side = (box.maxWidth * 0.34).clamp(300.0, 460.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: card),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: side,
              // Shrinks as one piece rather than clip in a short window.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: side,
                  child: IcHeadline(controller: controller),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _surface(BuildContext context, Widget child) {
    final AppColorScheme colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: ColoredBox(color: colors.surface2, child: child),
    );
  }

  IcPaintStyle _style(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    // Painted text does not see MediaQuery's text scale; the presenter scale
    // reaches it here (1.0 outside presenter mode).
    final PresenterScale scale = PresenterMode.scaleOf(context);
    TextStyle up(TextStyle t) =>
        t.copyWith(fontSize: scale.paintFont(t.fontSize ?? AppTextSize.body));
    final Color source = IcPalette.source(colors);
    return IcPaintStyle(
      scale: scale,
      surface: colors.surface2,
      grid: colors.textTertiary,
      axis: colors.textPrimary,
      source: source,
      yours: IcPalette.yours(colors),
      wait: colors.statusWarning,
      hit: colors.statusDanger,
      label: up(
        mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.textSecondary,
        ),
      ),
      strongLabel: up(
        text.labelSmall!.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      sourceLabel: up(
        text.labelSmall!.copyWith(color: source, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _legend(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final double k = PresenterMode.scaleOf(context).marker;
    final TextStyle small =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    Widget item(Widget sw, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        sw,
        const SizedBox(width: AppSpacing.xxs),
        Flexible(child: Text(label, style: small)),
      ],
    );
    Widget box(Color fill, {Color? border, CustomPainter? painter}) =>
        Container(
          width: 16 * k,
          height: 11 * k,
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border ?? fill),
          ),
          child: painter == null ? null : CustomPaint(painter: painter),
        );
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        item(
          box(IcPalette.source(colors).withValues(alpha: 0.85)),
          'Source on the air',
        ),
        item(
          box(
            colors.surface2,
            border: colors.statusWarning,
            painter: _SwatchHatch(colors.statusWarning, cross: false),
          ),
          'Your radio waits',
        ),
        item(
          box(
            colors.surface2,
            border: colors.statusDanger,
            painter: _SwatchHatch(colors.statusDanger, cross: true),
          ),
          'Your radio sends into it',
        ),
        item(
          box(
            IcPalette.yours(colors).withValues(alpha: 0.18),
            border: colors.textTertiary,
          ),
          'Free to send',
        ),
      ],
    );
  }

  Widget _levelSlider(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final IcSource s = controller.config.source;
    final String label = icLevelLabel(s);
    final double v = controller.level;
    return Row(
      children: <Widget>[
        Flexible(
          flex: 2,
          child: ExcludeSemantics(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Slider(
            value: v.clamp(kIcLevelMinDbm, kIcLevelMaxDbm),
            min: kIcLevelMinDbm,
            max: kIcLevelMaxDbm,
            divisions: 70,
            onChanged: (double x) => controller.level = x,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: IcFormat.dbm(v),
            semanticFormatterCallback: (double x) =>
                '$label ${IcFormat.dbm(x)}',
          ),
        ),
        ExcludeSemantics(
          child: SizedBox(
            width: 78 * PresenterMode.scaleOf(context).text,
            child: Text(
              IcFormat.dbm(v),
              textAlign: TextAlign.right,
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
      ],
    );
  }

  String _meterSemantics(IcResult r) {
    final IcSourceResult s = r.selected;
    final String where = s.levelInChannelDbm == null
        ? '${s.source.label} is not on this band.'
        : '${s.source.label} in your channel at '
              '${IcFormat.dbm(s.levelInChannelDbm!)}.';
    return 'Level meter from -100 to -30 dBm. Noise floor -95 dBm, '
        'illustrative. Preamble detect ${IcFormat.dbm(r.preambleDetectDbm)} '
        'for other Wi-Fi; energy detect -62 dBm for anything. The gap is '
        '${r.gapDb.round()} dB, ${r.gapPowerRatio.round()} times the power. '
        '${r.widthScaled ? '${_widthRule(r)} ' : ''}'
        '$where';
  }

  String _distanceSemantics(IcResult r, UnitSystem u) =>
      'Another Wi-Fi radio makes you wait out to '
      '${IcFormat.dist(r.wifiHeardAtM, u)}; non-Wi-Fi energy of the same '
      'power only out to ${IcFormat.dist(r.energyHeardAtM, u)}, '
      '${IcFormat.times(r.distanceRatio)} less far.';

  String _timelineSemantics(IcResult r) {
    final IcSourceResult s = r.selected;
    if (s.heard == IcHeard.absent) {
      return '60 ms of your channel: ${s.source.label} is not on this band.';
    }
    return '60 ms of your channel. ${s.source.label} is on the air '
        '${IcFormat.pct(s.onAirShare)} of the time; your radio '
        '${s.heard.waits ? 'waits for it each time' : 'sends into it'}.';
  }
}

class _SwatchHatch extends CustomPainter {
  _SwatchHatch(this.color, {required this.cross});
  final Color color;
  final bool cross;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (double x = -size.height; x < size.width; x += 4) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
      if (cross) {
        canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
      }
    }
  }

  @override
  bool shouldRepaint(_SwatchHatch old) =>
      old.color != color || old.cross != cross;
}

/// The costs in headline type: what the selected source does to your radio,
/// airtime lost waiting beside airtime lost to corrupted frames, and every
/// source side by side at its current level. On the presenter stage, and on
/// the phone as the readouts card.
class IcHeadline extends StatelessWidget {
  const IcHeadline({super.key, required this.controller});

  final InterfererCostController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final IcResult r = controller.result;
    final IcSourceResult s = r.selected;
    final TextStyle cap =
        text.labelSmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    final TextStyle bigStyle = scale
        .headlineStyle(mono.outputLarge)
        .copyWith(color: colors.textAccent);
    Widget bigValue(String v) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(v, style: bigStyle),
    );
    // A table, so the two numbers share a baseline however the labels wrap.
    final Widget costs = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.bottom,
      columnWidths: const <int, TableColumnWidth>{
        0: FlexColumnWidth(),
        1: FixedColumnWidth(AppSpacing.sm),
        2: FlexColumnWidth(),
      },
      children: <TableRow>[
        TableRow(
          children: <Widget>[
            Text('Airtime lost waiting', style: cap),
            const SizedBox.shrink(),
            Text('Airtime lost to corrupted frames', style: cap),
          ],
        ),
        TableRow(
          children: <Widget>[
            bigValue(IcFormat.pct(s.deferralShare)),
            const SizedBox.shrink(),
            bigValue(IcFormat.pct(s.corruptionShare)),
          ],
        ),
        TableRow(
          children: <Widget>[
            Text('deferral', style: cap),
            const SizedBox.shrink(),
            Text('illustrative', style: cap),
          ],
        ),
      ],
    );

    return RvrCard(
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            RvrSectionLabel('What it costs: ${s.source.label}'),
            const SizedBox(height: AppSpacing.xxs),
            IcVerdictText(icHeardVerdict(s, colors)),
            const SizedBox(height: AppSpacing.xs),
            costs,
            const SizedBox(height: AppSpacing.xxs),
            Text(
              s.heard == IcHeard.absent
                  ? 'Left for your traffic: 100%'
                  : 'Left for your traffic: ${IcFormat.pct(1 - s.totalShare)}. '
                        'On the air ${IcFormat.pct(s.onAirShare)} of the time '
                        'in your channel.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Every source, side by side (dBm in your channel)',
              style: cap,
            ),
            const SizedBox(height: AppSpacing.xxs),
            IcCompareTable(result: r),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              kIcIllustrativeCorruption,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every source at its current level: in your channel, waiting, corrupted.
class IcCompareTable extends StatelessWidget {
  const IcCompareTable({super.key, required this.result});

  final IcResult result;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle head =
        text.labelSmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);
    TextStyle cell(bool sel) => mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
      color: sel ? colors.textPrimary : colors.textSecondary,
      fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
    );
    TextStyle name(bool sel) => (text.bodySmall ?? const TextStyle()).copyWith(
      color: sel ? colors.textPrimary : colors.textSecondary,
      fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
    );
    Widget pad(Widget w) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      child: w,
    );
    return Table(
      columnWidths: const <int, TableColumnWidth>{
        0: FlexColumnWidth(1.9),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.6),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(horizontalInside: BorderSide(color: colors.border)),
      children: <TableRow>[
        TableRow(
          children: <Widget>[
            pad(
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('Source', style: head),
              ),
            ),
            pad(
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('dBm', style: head),
              ),
            ),
            pad(
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('Waiting', style: head),
              ),
            ),
            pad(
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('Corrupted', style: head),
              ),
            ),
          ],
        ),
        for (final IcSource s in IcSource.values)
          _row(
            result.sources[s]!,
            s == result.config.source,
            colors.surface2,
            name,
            cell,
            pad,
          ),
      ],
    );
  }

  TableRow _row(
    IcSourceResult x,
    bool sel,
    Color selFill,
    TextStyle Function(bool) name,
    TextStyle Function(bool) cell,
    Widget Function(Widget) pad,
  ) {
    final bool absent = x.heard == IcHeard.absent;
    return TableRow(
      decoration: sel ? BoxDecoration(color: selFill) : null,
      children: <Widget>[
        pad(
          Semantics(
            label: sel ? '${x.source.label}, shown above' : x.source.label,
            excludeSemantics: true,
            child: Text(x.source.short, style: name(sel)),
          ),
        ),
        pad(
          Text(
            absent ? 'none' : IcFormat.n(x.levelInChannelDbm!),
            style: cell(sel),
          ),
        ),
        pad(Text(IcFormat.pct(x.deferralShare), style: cell(sel))),
        pad(Text(IcFormat.pct(x.corruptionShare), style: cell(sel))),
      ],
    );
  }
}

/// The width scaling in words, labeled as the 5 GHz rule (Keith,
/// 2026-09-27: "This is for 5GHz only, 6GHz works differently").
String _widthRule(IcResult r) =>
    'At ${r.config.widthMHz} MHz the gap narrows to ${r.gapDb.round()} dB. '
    'This widening applies to 5 GHz.';
