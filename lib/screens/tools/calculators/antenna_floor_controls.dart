// Controls and readouts for the Floor coverage view of the Wi-Fi Classroom
// "Antenna Pattern" tool (antenna-pattern), spec 46. They write
// FloorCoverageController (and, through a preset, the lab's antenna) and
// never draw, so the presenter layout can put them beside the stage.
//
// The antenna card, mounting and the rest stay in AntennaPatternControls,
// which the screen shows under these in the floor view: one antenna, two
// views of it.

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'antenna_floor_controller.dart';
import 'antenna_pattern_parts.dart';

/// The 3D pattern / Floor coverage switch.
class AntennaViewSwitch extends StatelessWidget {
  const AntennaViewSwitch({super.key, required this.floor});
  final FloorCoverageController floor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: floor,
      builder: (BuildContext context, _) => AppToggle<AntennaStageView>(
        value: floor.view,
        expand: true,
        semanticLabel: 'View',
        items: <AppToggleItem<AntennaStageView>>[
          for (final AntennaStageView v in AntennaStageView.values)
            (v, v.label),
        ],
        onChanged: floor.setView,
      ),
    );
  }
}

class FloorCoverageControls extends StatelessWidget {
  const FloorCoverageControls({super.key, required this.floor});
  final FloorCoverageController floor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: floor,
      builder: (BuildContext context, _) {
        const Widget gap = SizedBox(height: AppSpacing.sm);
        if (PresenterMode.isActive(context)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SetupCard(floor: floor, presenting: true),
              gap,
              PatternCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    PresenterDisclosure(
                      title: 'Readouts, both directions',
                      children: <Widget>[_ReadoutsCard(floor: floor)],
                    ),
                    PresenterDisclosure(
                      title: 'Power, band and client',
                      children: <Widget>[_LinkCard(floor: floor)],
                    ),
                    const PresenterDisclosure(
                      title: 'What you are seeing',
                      children: <Widget>[_ExplainerCard()],
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SetupCard(floor: floor),
            gap,
            _ReadoutsCard(floor: floor),
            gap,
            _LinkCard(floor: floor),
            gap,
            const _ExplainerCard(),
          ],
        );
      },
    );
  }
}

// ── Preset and height ─────────────────────────────────────────────────────

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.floor, this.presenting = false});
  final FloorCoverageController floor;
  final bool presenting;

  @override
  Widget build(BuildContext context) {
    final FloorPreset? p = floor.preset;
    return PatternCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabeledField(
            label: 'Start from',
            semanticLabel: 'Floor coverage preset',
            field: AppSelect<FloorPreset?>(
              value: p,
              semanticLabel: 'Floor coverage preset',
              items: <AppSelectItem<FloorPreset?>>[
                for (final FloorPreset x in FloorPreset.values) (x, x.label),
                if (p == null) (null, 'Your own settings'),
              ],
              onChanged: (FloorPreset? x) {
                if (x != null) floor.applyPreset(x);
              },
            ),
          ),
          if (!presenting) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            PatternCaption(
              p == null
                  ? 'Your own antenna, height and power. Pick a preset to '
                        'step through the warehouse story one change at a '
                        'time.'
                  : p.point,
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          PatternSlider(
            label: 'Mount height',
            valueText: fmtFloorLength(floor.heightM),
            value: floor.heightM,
            min: kMountHeightMinM,
            max: kMountHeightMaxM,
            divisions:
                ((kMountHeightMaxM - kMountHeightMinM) / kMountHeightStepM)
                    .round(),
            onChanged: floor.setHeight,
            semanticValue: fmtFloorLength,
          ),
          PatternSlider(
            label: 'AP transmit power',
            valueText: '${floor.apTxDbm.round()} dBm',
            value: floor.apTxDbm,
            min: kFloorApTxMin,
            max: kFloorApTxMax,
            divisions: (kFloorApTxMax - kFloorApTxMin).round(),
            onChanged: floor.setApTx,
            semanticValue: (double v) => '${v.round()} dBm',
          ),
          PatternSlider(
            label: 'Client position along the floor',
            valueText: fmtFloorLength(floor.clientXM),
            value: floor.clientXM,
            min: 0,
            max: kFloorClientMaxM,
            divisions: (kFloorClientMaxM * 2).round(),
            onChanged: floor.setClientX,
            semanticValue: fmtFloorLength,
          ),
        ],
      ),
    );
  }
}

// ── Readouts ──────────────────────────────────────────────────────────────

class _ReadoutsCard extends StatelessWidget {
  const _ReadoutsCard({required this.floor});
  final FloorCoverageController floor;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final FloorLink? link = floor.link;
    final FloorCell? cell = floor.cell;
    if (link == null || cell == null) {
      return const PatternCard(
        child: PatternNote(
          icon: Icons.hourglass_empty,
          message:
              'Waiting for a pattern. The readouts appear once the antenna '
              'has one.',
        ),
      );
    }
    final TextStyle head = Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(color: colors.textSecondary);
    final TextStyle val = patternMono(
      context,
    ).inlineCode.copyWith(color: colors.textPrimary);
    final FloorPoint below = link.at(0);
    final double? hole = cell.holeM;
    final FloorPoint? cp = floor.client;

    TableRow row(String where, FloorPoint p, {bool accent = false}) => TableRow(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(
            where,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(
            fmtFloorLevelDb(p.downlinkDbm, inNull: floorInNull(p)),
            textAlign: TextAlign.right,
            style: val.copyWith(
              color: accent ? colors.textAccent : colors.textPrimary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(
            fmtFloorLevelDb(p.uplinkDbm, inNull: floorInNull(p)),
            textAlign: TextAlign.right,
            style: val,
          ),
        ),
      ],
    );

    return PatternCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PatternSectionLabel('On the floor'),
          const SizedBox(height: AppSpacing.xs),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(1.25),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <TableRow>[
              TableRow(
                children: <Widget>[
                  Text('Where', style: head),
                  Text(
                    'AP to client, dBm',
                    textAlign: TextAlign.right,
                    style: head,
                  ),
                  Text(
                    'Client to AP, dBm',
                    textAlign: TextAlign.right,
                    style: head,
                  ),
                ],
              ),
              for (final double x in kFloorReadoutsM)
                row(fmtFloorWhere(x), link.at(x), accent: x == 0),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          PatternReadoutRow(
            label: 'Floor cell radius at $fmtFloorTarget',
            value: floorCellWords(cell),
            emphasize: true,
          ),
          PatternReadoutRow(
            label: 'Hole under the AP',
            value: hole == null
                ? (cell.isEmpty ? 'the whole floor' : 'none')
                : 'out to ${fmtFloorLength(hole)}',
          ),
          if (cell.gaps > 0)
            PatternReadoutRow(
              label: 'Weak rings farther out',
              value:
                  '${cell.gaps}, where the pattern\'s nulls land on the '
                  'floor',
            ),
          if (link.nullBelow) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            PatternNote(
              icon: Icons.info_outline,
              message:
                  'Straight down is ${fmtFloorDb(below.belowPeakDb)} dB under '
                  'this antenna\'s peak. A dipole or collinear has a true '
                  'null there, which the model holds 60 dB under the peak; '
                  'the omni-by-gain envelope stops 30 dB under it. A real '
                  'antenna\'s depth varies with its build and mounting, so '
                  '${floorUnreadable(below) ? 'the model\'s figures here, ${fmtFloorDbm(below.downlinkDbm)} AP to client and ${fmtFloorDbm(below.uplinkDbm)} client to AP, are its floor, not levels. No client or AP reads under about ${fmtFloorDbm(kFloorReadableDbm).replaceFirst('.0', '')} (a 20 MHz noise floor is about \u221294 dBm), so the readouts say below it.' : 'read this number as very weak, not as a measurement.'}',
            ),
          ],
          if (cp != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const PatternSectionLabel('At the client'),
            const SizedBox(height: AppSpacing.xxs),
            PatternReadoutRow(
              label: 'Along the floor',
              value:
                  '${fmtFloorLength(cp.xM)}; ${fmtFloorLength(cp.slantM)} '
                  'from the AP',
            ),
            PatternReadoutRow(
              label: 'AP gain toward it',
              value:
                  '${fmtFloorDb(cp.gainDbi)} dBi, '
                  '${fmtFloorDb(cp.belowPeakDb)} dB under the peak',
            ),
            PatternReadoutRow(
              label: 'AP to client',
              value: fmtFloorLevelDbm(cp.downlinkDbm, inNull: floorInNull(cp)),
            ),
            PatternReadoutRow(
              label: 'Client to AP',
              value: fmtFloorLevelDbm(cp.uplinkDbm, inNull: floorInNull(cp)),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          PatternCaption(
            'Both directions use the same antenna gain toward the client '
            '(an antenna receives with the pattern it transmits with), so '
            'client to AP is always AP to client plus '
            '${fmtFloorDb(floor.clientTxDbm - floor.apTxDbm)} dB: the '
            'client\'s transmit power minus the AP\'s.',
          ),
        ],
      ),
    );
  }
}

// ── Power, band, client, and the link out ─────────────────────────────────

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.floor});
  final FloorCoverageController floor;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final FloorPoint? cp = floor.client;
    return PatternCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PatternSlider(
            label: 'Client transmit power',
            valueText: '${floor.clientTxDbm.round()} dBm',
            value: floor.clientTxDbm,
            min: kFloorClientTxMin,
            max: kFloorClientTxMax,
            divisions: (kFloorClientTxMax - kFloorClientTxMin).round(),
            onChanged: floor.setClientTx,
            semanticValue: (double v) => '${v.round()} dBm',
          ),
          PatternSlider(
            label: 'Path-loss exponent',
            valueText: floor.exponent.toStringAsFixed(1),
            value: floor.exponent,
            min: kFloorExponentMin,
            max: kFloorExponentMax,
            divisions: ((kFloorExponentMax - kFloorExponentMin) * 10).round(),
            onChanged: floor.setExponent,
            semanticValue: (double v) => v.toStringAsFixed(1),
          ),
          const SizedBox(height: AppSpacing.xxs),
          AppToggle<WifiBand>(
            label: 'Band',
            value: floor.band,
            expand: true,
            items: <AppToggleItem<WifiBand>>[
              for (final WifiBand b in WifiBand.values) (b, b.label),
            ],
            onChanged: floor.setBand,
          ),
          const SizedBox(height: AppSpacing.xs),
          PatternCaption(
            'The starting powers are illustrative (AP 20 dBm, client 14 dBm), '
            'as is the client\'s ${fmtFloorDb(floor.clientGainDbi)} dBi '
            'phone-class antenna, held 1 m above the floor. Path loss is FSPL at 1 m plus '
            '10 n log10 of the distance at the band\'s channel '
            '(2.4 GHz ch 6, 5 GHz ch 100, 6 GHz ch 37), a model, not a '
            'measurement. No walls, racks or people.',
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: cp == null
                ? null
                : () => Navigator.of(context).pushNamed(
                    AppRouter.uplinkDownlink,
                    arguments: floor.uplinkDownlinkConfig,
                  ),
            icon: const Icon(Icons.swap_vert, size: 20),
            label: const Text('Open in Uplink vs Downlink'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textPrimary,
              side: BorderSide(color: colors.borderStrong, width: 1.5),
              minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          PatternCaption(
            cp == null
                ? 'Available once the antenna has a pattern.'
                : floor.carriedGainClamped
                ? 'Opens this client\'s link there: the band, both powers, '
                      'the exponent and the ${fmtFloorLength(cp.slantM)} '
                      'distance. Its AP gain slider runs 0 to 8 dBi, so the '
                      '${fmtFloorDb(cp.gainDbi)} dBi toward this client goes '
                      'over as ${fmtFloorDb(floor.carriedApGainDbi!)} dBi and '
                      'its numbers will differ from these.'
                : 'Opens this client\'s link there: the band, both powers, '
                      'the exponent, the ${fmtFloorLength(cp.slantM)} distance '
                      'and the ${fmtFloorDb(cp.gainDbi)} dBi the AP antenna '
                      'has toward this client.',
          ),
        ],
      ),
    );
  }
}

// ── Explainer ─────────────────────────────────────────────────────────────

class _ExplainerCard extends StatelessWidget {
  const _ExplainerCard();

  @override
  Widget build(BuildContext context) {
    return const PatternCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PatternSectionLabel('Why height matters'),
          SizedBox(height: AppSpacing.xs),
          PatternCaption(
            'The floor is not at one angle to the antenna. Right under the '
            'AP it is straight down; far away it is nearly at the horizon. '
            'Raise the AP and every spot on the floor moves to a steeper '
            'angle of the pattern. A dipole or a collinear omni has a null '
            'straight down, and a higher-gain omni squeezes more of its '
            'energy toward the horizon, so on a high ceiling both leave the '
            'floor under them weak. A directional aimed down puts its gain '
            'where the clients are.',
          ),
          SizedBox(height: AppSpacing.xs),
          PatternCaption(
            'Turning the AP up does not fix a weak uplink. The client\'s '
            'transmit power and the same antenna pattern set what the AP '
            'hears, and neither changed.',
          ),
          SizedBox(height: AppSpacing.xs),
          PatternCaption(
            'Vendor guidance, not a standard: ordinary omnis are commonly '
            'advised only up to about 25 ft (7.6 m). An HPE Aruba Airheads '
            'Community thread, Warehouse high ceiling (2018), quotes a '
            'vendor presentation to use downtilt omnis above 25 ft; a Cisco '
            'Community thread, High Ceilings (2013), has a Cisco employee '
            'putting an omni\'s limit at about 20 to 25 ft and advising '
            'patch antennas higher up.',
          ),
        ],
      ),
    );
  }
}
