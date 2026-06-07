// MCS Index reference — a read-only data table of 802.11 MCS rates, offline.
//
// Direct port of the RF Tools PWA `mcs` tool (index.html #tool-mcs +
// app.js buildMCSTable / MCS_N / MCS_AC / MCS_AX). The PWA shows one rate table
// per standard (802.11n / 802.11ac / 802.11ax); each table lists, per MCS index,
// the modulation, coding rate, and the single-spatial-stream data rate for each
// channel-width / guard-interval column. A spatial-streams selector multiplies
// every rate by the chosen SS count (PWA `r * ss`), exactly as the PWA does.
//
// The std/SS selectors use the shared AppSelect<T> (GL-003 §8.14) — the same
// control throughput_calc_screen.dart uses — because there are 3 standards and
// 8 spatial-stream options. Per-width rates are rendered as columns inside each
// MCS row card; the PWA's width/GI distinction lives in the column labels
// (e.g. "20 LGI", "80 SGI", "160 MHz"), so no width/GI filter is needed — the
// table shows every width at once, matching the PWA verbatim.
//
// States (SOP-007 §5):
//  - success → the chosen standard's MCS rows render, rates scaled by SS.
//  - empty   → not reachable: the datasets are bundled consts, never empty; a
//    the VHT MCS9 @ 20 and 40 MHz (1 SS) cells are honestly "N/A", not faked.
//  - loading / error → not applicable: no asset load, no network, no parse. The
//    data is compile-time const, so there is no failure surface to render.
//
// Pure data, no network, no platform APIs. The dataset and lookups are public
// statics so they unit-test against the PWA values.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'reference_row_semantics.dart';

/// 802.11 standard shown in the MCS table. n / ac / ax mirror the PWA tab
/// data-tab values; be is the 802.11be (Wi-Fi 7 / EHT) addition — 320 MHz and
/// 4096-QAM (MCS 12-13), which the PWA never carried.
enum McsStd { n, ac, ax, be }

/// One MCS index row: index, modulation, coding rate, and the per-column
/// single-spatial-stream data rates in Mbps. A null rate is an invalid cell
/// (PWA renders "N/A") — never zero, never fabricated.
class McsRow {
  const McsRow({
    required this.mcs,
    required this.modulation,
    required this.codeRate,
    required this.ratesPerSs,
  });

  /// MCS index (0-based).
  final int mcs;

  /// Modulation label, e.g. "64-QAM" (PWA MCS_* column 2).
  final String modulation;

  /// Coding rate label, e.g. "5/6" (PWA MCS_* column 3).
  final String codeRate;

  /// Single-spatial-stream rate per channel-width column, in Mbps, in the same
  /// order as the standard's [McsStdData.columns]. Null marks an invalid cell.
  final List<double?> ratesPerSs;
}

/// A standard's full MCS table: the column headers and the per-MCS rows.
class McsStdData {
  const McsStdData({required this.columns, required this.rows});

  /// Column headers in display order, e.g. ['20 LGI', '20 SGI', ...] (PWA cols).
  final List<String> columns;

  /// MCS rows, MCS 0 first (PWA MCS_N / MCS_AC / MCS_AX order).
  final List<McsRow> rows;
}

class McsIndexScreen extends StatefulWidget {
  const McsIndexScreen({super.key});

  // ─── Dataset (verbatim port of app.js MCS_N / MCS_AC / MCS_AX) ──────────────

  /// 802.11n (HT) — columns are [20 LGI, 20 SGI, 40 LGI, 40 SGI] (PWA MCS_N).
  static const McsStdData ht = McsStdData(
    columns: ['20 LGI', '20 SGI', '40 LGI', '40 SGI'],
    rows: [
      McsRow(
        mcs: 0,
        modulation: 'BPSK',
        codeRate: '1/2',
        ratesPerSs: [6.5, 7.2, 13.5, 15],
      ),
      McsRow(
        mcs: 1,
        modulation: 'QPSK',
        codeRate: '1/2',
        ratesPerSs: [13, 14.4, 27, 30],
      ),
      McsRow(
        mcs: 2,
        modulation: 'QPSK',
        codeRate: '3/4',
        ratesPerSs: [19.5, 21.7, 40.5, 45],
      ),
      McsRow(
        mcs: 3,
        modulation: '16-QAM',
        codeRate: '1/2',
        ratesPerSs: [26, 28.9, 54, 60],
      ),
      McsRow(
        mcs: 4,
        modulation: '16-QAM',
        codeRate: '3/4',
        ratesPerSs: [39, 43.3, 81, 90],
      ),
      McsRow(
        mcs: 5,
        modulation: '64-QAM',
        codeRate: '2/3',
        ratesPerSs: [52, 57.8, 108, 120],
      ),
      McsRow(
        mcs: 6,
        modulation: '64-QAM',
        codeRate: '3/4',
        ratesPerSs: [58.5, 65, 121.5, 135],
      ),
      McsRow(
        mcs: 7,
        modulation: '64-QAM',
        codeRate: '5/6',
        ratesPerSs: [65, 72.2, 135, 150],
      ),
    ],
  );

  /// 802.11ac (VHT) — columns are SGI rates per width [20, 40, 80, 160]
  /// (PWA MCS_AC). MCS9 is invalid at 20 and 40 MHz for 1 SS (null → "N/A").
  static const McsStdData vht = McsStdData(
    columns: ['20 SGI', '40 SGI', '80 SGI', '160 SGI'],
    rows: [
      McsRow(
        mcs: 0,
        modulation: 'BPSK',
        codeRate: '1/2',
        ratesPerSs: [7.2, 15, 32.5, 65],
      ),
      McsRow(
        mcs: 1,
        modulation: 'QPSK',
        codeRate: '1/2',
        ratesPerSs: [14.4, 30, 65, 130],
      ),
      McsRow(
        mcs: 2,
        modulation: 'QPSK',
        codeRate: '3/4',
        ratesPerSs: [21.7, 45, 97.5, 195],
      ),
      McsRow(
        mcs: 3,
        modulation: '16-QAM',
        codeRate: '1/2',
        ratesPerSs: [28.9, 60, 130, 260],
      ),
      McsRow(
        mcs: 4,
        modulation: '16-QAM',
        codeRate: '3/4',
        ratesPerSs: [43.3, 90, 195, 390],
      ),
      McsRow(
        mcs: 5,
        modulation: '64-QAM',
        codeRate: '2/3',
        ratesPerSs: [57.8, 120, 260, 520],
      ),
      McsRow(
        mcs: 6,
        modulation: '64-QAM',
        codeRate: '3/4',
        ratesPerSs: [65, 135, 292.5, 585],
      ),
      McsRow(
        mcs: 7,
        modulation: '64-QAM',
        codeRate: '5/6',
        ratesPerSs: [72.2, 150, 325, 650],
      ),
      McsRow(
        mcs: 8,
        modulation: '256-QAM',
        codeRate: '3/4',
        ratesPerSs: [86.7, 180, 390, 780],
      ),
      McsRow(
        mcs: 9,
        modulation: '256-QAM',
        codeRate: '5/6',
        ratesPerSs: [null, null, 433.3, 866.7],
      ), // MCS9 invalid at 20 and 40 MHz (1 SS)
    ],
  );

  /// 802.11ax (HE) — columns are 800 ns GI rates per width [20, 40, 80, 160]
  /// (PWA MCS_AX).
  static const McsStdData he = McsStdData(
    columns: ['20 MHz', '40 MHz', '80 MHz', '160 MHz'],
    rows: [
      McsRow(
        mcs: 0,
        modulation: 'BPSK',
        codeRate: '1/2',
        ratesPerSs: [8.6, 17.2, 36.0, 72.1],
      ),
      McsRow(
        mcs: 1,
        modulation: 'QPSK',
        codeRate: '1/2',
        ratesPerSs: [17.2, 34.4, 72.1, 144.1],
      ),
      McsRow(
        mcs: 2,
        modulation: 'QPSK',
        codeRate: '3/4',
        ratesPerSs: [25.8, 51.6, 108.1, 216.2],
      ),
      McsRow(
        mcs: 3,
        modulation: '16-QAM',
        codeRate: '1/2',
        ratesPerSs: [34.4, 68.8, 144.1, 288.2],
      ),
      McsRow(
        mcs: 4,
        modulation: '16-QAM',
        codeRate: '3/4',
        ratesPerSs: [51.6, 103.2, 216.2, 432.4],
      ),
      McsRow(
        mcs: 5,
        modulation: '64-QAM',
        codeRate: '2/3',
        ratesPerSs: [68.8, 137.6, 288.2, 576.5],
      ),
      McsRow(
        mcs: 6,
        modulation: '64-QAM',
        codeRate: '3/4',
        ratesPerSs: [77.4, 154.9, 324.3, 648.5],
      ),
      McsRow(
        mcs: 7,
        modulation: '64-QAM',
        codeRate: '5/6',
        ratesPerSs: [86.0, 172.1, 360.3, 720.6],
      ),
      McsRow(
        mcs: 8,
        modulation: '256-QAM',
        codeRate: '3/4',
        ratesPerSs: [103.2, 206.5, 432.4, 864.7],
      ),
      McsRow(
        mcs: 9,
        modulation: '256-QAM',
        codeRate: '5/6',
        ratesPerSs: [114.7, 229.4, 480.4, 960.8],
      ),
      McsRow(
        mcs: 10,
        modulation: '1024-QAM',
        codeRate: '3/4',
        ratesPerSs: [129.0, 258.1, 540.4, 1080.9],
      ),
      McsRow(
        mcs: 11,
        modulation: '1024-QAM',
        codeRate: '5/6',
        ratesPerSs: [143.4, 286.8, 600.4, 1200.9],
      ),
    ],
  );

  /// 802.11be (EHT / Wi-Fi 7) — columns are 800 ns GI rates per width
  /// [20, 40, 80, 160, 320]. MCS 0-11 share HE's modulation/rates; EHT adds the
  /// 320 MHz column and two 4096-QAM indices (MCS 12-13). Single-stream,
  /// GI 0.8 us, per the 802.11be EHT PHY MCS table.
  static const McsStdData eht = McsStdData(
    columns: ['20 MHz', '40 MHz', '80 MHz', '160 MHz', '320 MHz'],
    rows: [
      McsRow(
        mcs: 0,
        modulation: 'BPSK',
        codeRate: '1/2',
        ratesPerSs: [8.6, 17.2, 36.0, 72.1, 144.1],
      ),
      McsRow(
        mcs: 1,
        modulation: 'QPSK',
        codeRate: '1/2',
        ratesPerSs: [17.2, 34.4, 72.1, 144.1, 288.2],
      ),
      McsRow(
        mcs: 2,
        modulation: 'QPSK',
        codeRate: '3/4',
        ratesPerSs: [25.8, 51.6, 108.1, 216.2, 432.4],
      ),
      McsRow(
        mcs: 3,
        modulation: '16-QAM',
        codeRate: '1/2',
        ratesPerSs: [34.4, 68.8, 144.1, 288.2, 576.5],
      ),
      McsRow(
        mcs: 4,
        modulation: '16-QAM',
        codeRate: '3/4',
        ratesPerSs: [51.6, 103.2, 216.2, 432.4, 864.7],
      ),
      McsRow(
        mcs: 5,
        modulation: '64-QAM',
        codeRate: '2/3',
        ratesPerSs: [68.8, 137.6, 288.2, 576.5, 1152.9],
      ),
      McsRow(
        mcs: 6,
        modulation: '64-QAM',
        codeRate: '3/4',
        ratesPerSs: [77.4, 154.9, 324.3, 648.5, 1297.1],
      ),
      McsRow(
        mcs: 7,
        modulation: '64-QAM',
        codeRate: '5/6',
        ratesPerSs: [86.0, 172.1, 360.3, 720.6, 1441.2],
      ),
      McsRow(
        mcs: 8,
        modulation: '256-QAM',
        codeRate: '3/4',
        ratesPerSs: [103.2, 206.5, 432.4, 864.7, 1729.4],
      ),
      McsRow(
        mcs: 9,
        modulation: '256-QAM',
        codeRate: '5/6',
        ratesPerSs: [114.7, 229.4, 480.4, 960.8, 1921.6],
      ),
      McsRow(
        mcs: 10,
        modulation: '1024-QAM',
        codeRate: '3/4',
        ratesPerSs: [129.0, 258.1, 540.4, 1080.9, 2161.8],
      ),
      McsRow(
        mcs: 11,
        modulation: '1024-QAM',
        codeRate: '5/6',
        ratesPerSs: [143.4, 286.8, 600.4, 1200.9, 2401.9],
      ),
      McsRow(
        mcs: 12,
        modulation: '4096-QAM',
        codeRate: '3/4',
        ratesPerSs: [154.9, 309.7, 648.5, 1297.1, 2594.1],
      ),
      McsRow(
        mcs: 13,
        modulation: '4096-QAM',
        codeRate: '5/6',
        ratesPerSs: [172.1, 344.1, 720.6, 1441.2, 2882.4],
      ),
    ],
  );

  /// Lookup table keyed by standard.
  static const Map<McsStd, McsStdData> dataset = {
    McsStd.n: ht,
    McsStd.ac: vht,
    McsStd.ax: he,
    McsStd.be: eht,
  };

  // ─── Lookups (pure, testable) ───────────────────────────────────────────────

  /// The MCS table for [std].
  static McsStdData dataFor(McsStd std) => dataset[std]!;

  /// The data rate in Mbps for a given standard, MCS index, column index, and
  /// spatial-stream count — single-SS rate × ss (PWA `r * ss`). Null when the
  /// cell is invalid (PWA "N/A"), the MCS index is out of range, the column is
  /// out of range, or ss < 1.
  static double? rate({
    required McsStd std,
    required int mcs,
    required int columnIndex,
    required int spatialStreams,
  }) {
    if (spatialStreams < 1) return null;
    final McsStdData data = dataset[std]!;
    McsRow? row;
    for (final McsRow r in data.rows) {
      if (r.mcs == mcs) {
        row = r;
        break;
      }
    }
    if (row == null) return null;
    if (columnIndex < 0 || columnIndex >= row.ratesPerSs.length) return null;
    final double? base = row.ratesPerSs[columnIndex];
    if (base == null) return null;
    return base * spatialStreams;
  }

  @override
  State<McsIndexScreen> createState() => _McsIndexScreenState();
}

class _McsIndexScreenState extends State<McsIndexScreen> {
  McsStd _std = McsStd.n; // PWA default tab (802.11n active).
  int _ss = 1; // PWA default spatial streams (1 SS).

  static String _stdLabel(McsStd std) {
    switch (std) {
      case McsStd.n:
        return '802.11n — Wi-Fi 4 (HT)';
      case McsStd.ac:
        return '802.11ac — Wi-Fi 5 (VHT)';
      case McsStd.ax:
        return '802.11ax — Wi-Fi 6 (HE)';
      case McsStd.be:
        return '802.11be — Wi-Fi 7 (EHT)';
    }
  }

  /// PWA fmt: single-stream rates render at fixed 1-decimal ((r*ss).toFixed(1)),
  /// invalid cells render "N/A".
  static String _formatRate(double? n) {
    if (n == null) return 'N/A';
    return n.toStringAsFixed(1);
  }

  /// §8.16 copy payload — the live MCS rate table as TSV. The title records the
  /// selected standard and spatial-stream count because the rates are scaled by
  /// SS (PWA `r * ss`). One header row (MCS, Modulation, Code, then one column
  /// per channel-width); one tab-separated row per MCS index. Invalid cells
  /// copy as "N/A" (never fabricated). Always non-null (static data).
  String _buildCopyText() {
    const String tab = '\t';
    final McsStdData data = McsIndexScreen.dataFor(_std);
    final StringBuffer buf = StringBuffer()
      ..writeln('MCS Index — ${_stdLabel(_std)} · $_ss SS (Mbps)')
      ..writeln(
        <String>['MCS', 'Modulation', 'Code', ...data.columns].join(tab),
      );
    for (final McsRow row in data.rows) {
      final List<String> cells = <String>[
        '${row.mcs}',
        row.modulation,
        row.codeRate,
      ];
      for (int i = 0; i < data.columns.length; i++) {
        final double? scaled = McsIndexScreen.rate(
          std: _std,
          mcs: row.mcs,
          columnIndex: i,
          spatialStreams: _ss,
        );
        cells.add(_formatRate(scaled));
      }
      buf.writeln(cells.join(tab));
    }
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('MCS Index'),
        toolbarHeight: 64,
        // §8.16 — copy the live MCS rate table as TSV, with the selected
        // standard and spatial-stream count recorded in the title (rates are
        // scaled by SS, so the params matter). Static data, always enabled.
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

            return Center(
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
                        toolId: 'mcs-index',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('mcs-index'))
                        const SizedBox(height: AppSpacing.md),
                      _controlsCard(),
                      const SizedBox(height: AppSpacing.md),
                      _tableCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _notesCard(text),
                      ToolHelpFooter(toolId: 'mcs-index'),
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

  Widget _controlsCard() {
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
          _stdSelector(),
          const SizedBox(height: AppSpacing.sm),
          _ssSelector(),
        ],
      ),
    );
  }

  Widget _stdSelector() {
    return LabeledField(
      label: '802.11 standard',
      field: AppSelect<McsStd>(
        value: _std,
        semanticLabel: '802.11 standard',
        items: McsStd.values.map((McsStd s) => (s, _stdLabel(s))).toList(),
        onChanged: (McsStd s) => setState(() => _std = s),
      ),
    );
  }

  Widget _ssSelector() {
    // PWA offers 1–8 spatial streams for every standard.
    final List<AppSelectItem<int>> items = [
      for (int i = 1; i <= 8; i++) (i, '$i SS'),
    ];
    return LabeledField(
      label: 'Spatial streams',
      field: AppSelect<int>(
        value: _ss,
        semanticLabel: 'Spatial streams',
        items: items,
        onChanged: (int s) => setState(() => _ss = s),
      ),
    );
  }

  Widget _tableCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final McsStdData data = McsIndexScreen.dataFor(_std);
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
            '${data.rows.length} MCS indices  ·  ×$_ss SS (Mbps)',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Horizontal scroll: the per-width rate columns can exceed phone
          // width, so the data table scrolls sideways inside the fixed card.
          // HorizontalScrollTable adds the always-visible scrollbar so the
          // sideways scroll is signalled on web (Vera web-demo gate,
          // 2026-06-02).
          HorizontalScrollTable(child: _dataTable(data, text, mono)),
        ],
      ),
    );
  }

  Widget _dataTable(McsStdData data, TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);

    return DataTable(
      headingRowHeight: 44,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 48,
      columnSpacing: AppSpacing.md,
      horizontalMargin: 0,
      dividerThickness: 1,
      headingTextStyle: headStyle,
      columns: [
        const DataColumn(label: Text('MCS')),
        const DataColumn(label: Text('Modulation')),
        const DataColumn(label: Text('Code')),
        for (final String c in data.columns)
          DataColumn(label: Text(c), numeric: true),
      ],
      rows: data.rows.map((McsRow row) {
        // DataTable renders each cell as its own column node; without grouping
        // a screen reader reads "0", "BPSK", "1/2", "8.6"… as disconnected
        // nodes and can't tell which rates belong to which MCS. Label the first
        // (MCS) cell with the full row summary and exclude the rest. (Vera
        // F-02.) The rate clause reflects the live std + spatial-stream choice.
        final List<String?> rateClauses = <String?>[];
        for (int i = 0; i < data.columns.length; i++) {
          final double? scaled = McsIndexScreen.rate(
            std: _std,
            mcs: row.mcs,
            columnIndex: i,
            spatialStreams: _ss,
          );
          if (scaled == null) continue;
          rateClauses.add('${data.columns[i]} ${_formatRate(scaled)} megabits');
        }
        final String summary = rowLabel('MCS ${row.mcs}', <String?>[
          row.modulation,
          'code rate ${row.codeRate}',
          ...rateClauses,
        ]);
        return DataRow(
          cells: [
            DataCell(
              Semantics(
                label: summary,
                container: true,
                child: ExcludeSemantics(
                  child: Text(
                    '${row.mcs}',
                    style: mono.outputMedium.copyWith(color: colors.textAccent),
                  ),
                ),
              ),
            ),
            DataCell(
              ExcludeSemantics(
                child: Text(
                  row.modulation,
                  style: text.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
            DataCell(
              ExcludeSemantics(
                child: Text(
                  row.codeRate,
                  style: mono.inlineCode.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
            for (int i = 0; i < row.ratesPerSs.length; i++)
              _rateCell(row, i, mono),
          ],
        );
      }).toList(),
    );
  }

  DataCell _rateCell(McsRow row, int columnIndex, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final double? scaled = McsIndexScreen.rate(
      std: _std,
      mcs: row.mcs,
      columnIndex: columnIndex,
      spatialStreams: _ss,
    );
    final bool na = scaled == null;
    return DataCell(
      ExcludeSemantics(
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            _formatRate(scaled),
            style: mono.outputMedium.copyWith(
              color: na ? colors.textTertiary : colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _notesCard(TextTheme text) {
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
            'Notes',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Rates are per-stream values multiplied by the spatial-stream count '
            'above. 802.11n: LGI = 800 ns long guard interval, SGI = 400 ns '
            'short. 802.11ac: short guard interval. 802.11ax and 802.11be: '
            '800 ns guard interval. 802.11be (Wi-Fi 7 / EHT) adds the 320 MHz '
            'channel width and 4096-QAM (MCS 12 and 13). 802.11ac MCS 9 is '
            'invalid at 20 and 40 MHz for a single stream (N/A). Actual '
            'throughput is typically 50 to 65 percent of the PHY rate.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
