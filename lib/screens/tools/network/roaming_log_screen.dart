// Roaming Log — records BSSID transitions (roams) within the same SSID during a
// foreground monitoring session (Feature 2, Felix 2026-06-13, per Pax's gap
// brief Deliverables/2026-06-13-toolbox-gap-feasibility/feasibility-brief.md).
//
// REUSE, no new measurement / permission / plugin: it drives the SAME shared
// [WifiSignalSampler] the live "Wi-Fi signal" card uses (macOS CoreWLAN poll /
// iOS companion-Shortcut stream), and reads the roam log the sampler now keeps
// via its [RoamDetector]. macOS auto-polls continuously while the screen is open;
// iOS streams via the companion Shortcut behind a single deliberate Start tap
// (auto-firing it would bounce the user out of the app — GL-008).
//
// HONESTY (GL-005 / GL-008): on iOS this captures roams during an ACTIVE
// FOREGROUND session only — there is no public iOS API for background Wi-Fi /
// BSSID-change callbacks, the same ceiling Wi-Fi Check shares. The screen says
// so plainly. A roam is recorded only when both the prior and current BSSID are
// known; a network (SSID) switch is excluded; nothing is fabricated.
//
// STATES (all explicit): unsupported/web (NetworkUnavailableView), monitoring +
// no roams yet (honest "watching" empty state), monitoring + roams (the event
// list), iOS-not-started (Start control), iOS feed failed (honest retry note),
// stopped (last list frozen). LAYOUT: SafeArea + centered ConstrainedBox(560) +
// scroll; surface1 cards with the §8.1 hairline; help is the §8.16.1 footer.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/pdf_download.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/roam_detector.dart';
import '../../../services/network/wifi_info_adapter.dart';
import '../../../services/network/wifi_signal_sampler.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'network_unavailable_view.dart';

/// The share/download seam this screen calls to export the formatted roam
/// document. Matches the [shareBytes] signature so a test can inject a fake that
/// never touches a platform channel.
typedef RoamShareFn = Future<void> Function({
  required List<int> bytes,
  required String filename,
  required String mimeType,
  String? title,
  ShareOrigin? shareOrigin,
});

/// The Roaming Log screen — a foreground roam recorder built on the shared live
/// sampler.
class RoamingLogScreen extends StatefulWidget {
  const RoamingLogScreen({
    super.key,
    this.sourceOverride,
    this.sampler,
    this.enableSampling = true,
    this.shareFn = shareBytes,
  });

  /// Forces a specific Wi-Fi data source (tests). Defaults to the host platform
  /// via [WifiInfoSourceResolver].
  final WifiInfoSource? sourceOverride;

  /// Injectable live sampler (tests). Defaults to a real [WifiSignalSampler] on
  /// the resolved platform.
  final WifiSignalSampler? sampler;

  /// When false, no sampler is started (tests that drive the sampler manually).
  final bool enableSampling;

  /// The share seam for the §8.16 Share document action. Defaults to the real
  /// [shareBytes]; tests inject a fake so the platform share channel is never
  /// touched.
  final RoamShareFn shareFn;

  @override
  State<RoamingLogScreen> createState() => _RoamingLogScreenState();
}

class _RoamingLogScreenState extends State<RoamingLogScreen>
    with WidgetsBindingObserver {
  late final WifiInfoSource _source;
  WifiSignalSampler? _sampler;

  /// Wall-clock time this foreground recording session opened — stamped when the
  /// sampler is wired (macOS auto-polls from here; iOS begins on the Start tap,
  /// so this is the honest "log opened" time, never a fabricated reading). Feeds
  /// the §8.16 copy export header. Null when no sampler is active.
  DateTime? _sessionStart;

  @override
  void initState() {
    super.initState();
    _source = widget.sourceOverride ?? WifiInfoSourceResolver.resolve();

    // Delegate the "can this platform monitor at all?" decision to the shared
    // SSOT [WifiSignalSampler.isSupportedSource] rather than repeating an inline
    // four-source list here (Vera LOW finding, 2026-06-30). The inline list is
    // exactly what let the roam log drift from the sampler and darken Windows
    // (bug C3); anchoring to the predicate means a new native source the sampler
    // learns to poll lights up here automatically with no edit, and can never
    // fall out of sync.
    if (widget.enableSampling && WifiSignalSampler.isSupportedSource(_source)) {
      _sampler = widget.sampler ?? WifiSignalSampler(source: _source);
      _sessionStart = DateTime.now();
      WidgetsBinding.instance.addObserver(this);
      _sampler!.load();
      // Every supported NON-iOS source (macOS / Android / Windows, and any future
      // native adapter) reads the feed from NATIVE polling with no app switch, so
      // it auto-starts on entry. iOS alone waits for the single deliberate Start
      // tap — firing the companion Shortcut on entry would bounce the user out of
      // the app (GL-008). Expressed as "supported and not iOS" so it, too, tracks
      // the SSOT instead of re-listing platforms.
      if (_source != WifiInfoSource.iosShortcuts) {
        _sampler!.start();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final WifiSignalSampler? sampler = _sampler;
    if (sampler == null) return;
    if (state == AppLifecycleState.resumed) {
      sampler.load();
      sampler.resumeMac();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      sampler.pauseMac();
    }
  }

  @override
  void dispose() {
    if (_sampler != null) {
      WidgetsBinding.instance.removeObserver(this);
      if (widget.sampler == null) _sampler!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roaming Log'),
        toolbarHeight: 64,
        // §8.16: copy leads, then the Share document export. Both serialize the
        // session on demand and are disabled (not focusable) on the honest empty
        // state, so neither ever exports a fake/empty log.
        //
        // The sampler is a ChangeNotifier: new roams fire notifyListeners(),
        // which without this wrapper would only rebuild the roam-list card,
        // NEVER these AppBar actions — so AppCopyAction, which resolves its
        // enabled state from textBuilder() at BUILD time, would latch to the
        // disabled state it had at screen-open (zero roams) for the whole
        // session (the dead-Copy-button bug). Wrapping them in an AnimatedBuilder
        // bound to the sampler re-resolves enabled as roams land. The null /
        // unsupported branch keeps a static disabled copy action, matching the
        // prior behavior.
        actions: <Widget>[
          if (_sampler != null)
            AnimatedBuilder(
              animation: _sampler!,
              builder: (BuildContext context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppCopyAction(textBuilder: _buildCopyText),
                  _RoamShareAction(
                    htmlBuilder: _buildShareHtml,
                    shareFn: widget.shareFn,
                  ),
                ],
              ),
            )
          else
            AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// The capture platform, resolved from the same [WifiInfoSource] the screen
  /// already uses. Stamped into the Copy report and the Share document so three
  /// side-by-side captures (iPhone + Android + macOS) are each self-identifying.
  String get _capturePlatform => capturePlatformLabel(_source);

  /// §8.16 copy payload — delegates to the pure [buildRoamLogCopyText] so the
  /// serialization is unit-testable without a live sampler. Returns null
  /// (→ disabled affordance) when no sampler is active or no roam is recorded.
  String? _buildCopyText() {
    final WifiSignalSampler? s = _sampler;
    if (s == null) return null;
    final List<RoamEvent> events = s.roamEvents;
    return buildRoamLogCopyText(
      events: events,
      network: _sessionNetwork(s, events),
      sessionStart: _sessionStart,
      capturePlatform: _capturePlatform,
    );
  }

  /// §8.16 Share document payload — delegates to the pure [buildRoamLogShareHtml]
  /// so the HTML is unit-testable without a live sampler. Returns null (→ disabled
  /// Share affordance) when no sampler is active or no roam is recorded.
  String? _buildShareHtml() {
    final WifiSignalSampler? s = _sampler;
    if (s == null) return null;
    final List<RoamEvent> events = s.roamEvents;
    return buildRoamLogShareHtml(
      events: events,
      network: _sessionNetwork(s, events),
      sessionStart: _sessionStart,
      capturePlatform: _capturePlatform,
    );
  }

  /// The network the session belongs to: the live SSID where the platform still
  /// exposes it, else the most recent roam's SSID, else the honest "Wi-Fi"
  /// fallback the rows use when no name was read.
  String _sessionNetwork(WifiSignalSampler s, List<RoamEvent> events) {
    final String? live = s.latest?.ssid;
    if (live != null && live.trim().isNotEmpty) return live;
    for (final RoamEvent e in events.reversed) {
      final String? ssid = e.ssid;
      if (ssid != null && ssid.trim().isNotEmpty) return ssid;
    }
    return 'Wi-Fi';
  }

  Widget _body() {
    if (!NetworkSupport.activeNetworkSupported ||
        _source == WifiInfoSource.web) {
      return const NetworkUnavailableView(
        toolName: 'Roaming Log',
        reason: NetworkUnavailableReason.web,
      );
    }
    if (_source == WifiInfoSource.unsupported) {
      return const NetworkUnavailableView(
        toolName: 'Roaming Log',
        reason: NetworkUnavailableReason.platformApiMissing,
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
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.md,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _intro(context),
                  const SizedBox(height: AppSpacing.md),
                  if (_sampler != null)
                    _RoamLogCard(sampler: _sampler!)
                  else
                    _RoamLogCard.disabled(context),
                  const ToolHelpFooter(toolId: 'roaming-log'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _intro(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final bool isIos = _source == WifiInfoSource.iosShortcuts;
    return Text(
      isIos
          ? 'Walk around with this open to record each time your device roams '
              'from one access point to another on the same network. iOS records '
              'roams while this screen is open and running. There is no '
              'background Wi-Fi monitoring on iOS.'
          // macOS / Android / Windows all auto-poll the link natively — keep the
          // copy platform-neutral so it stays true on each (it previously said
          // "macOS" for every non-iOS platform, wrong on Android and Windows).
          : 'Walk around with this open to record each time your device roams '
              'from one access point to another on the same network. Your device '
              'reads the link continuously while this screen is open.',
      style: text.bodyLarge?.copyWith(color: colors.textSecondary),
    );
  }
}

/// The last two octets (last 4 hex digits) of a BSSID, e.g. ":3a:10" — the part
/// that identifies the AP on a same-brand deployment where the OUI (the first
/// three octets) is shared across every radio. Falls back to the whole value for
/// a short / malformed BSSID that has fewer than two colon-separated octets, so
/// a non-standard identifier is shown in full rather than mangled (GL-005).
@visibleForTesting
String lastOctets(String bssid) {
  final String trimmed = bssid.trim();
  final List<String> parts = trimmed.split(':');
  if (parts.length < 2) return trimmed.isEmpty ? bssid : trimmed;
  return ':${parts.sublist(parts.length - 2).join(':')}';
}

/// The capture platform label for a [WifiInfoSource], stamped into the exported
/// reports so three side-by-side captures (iPhone + Android + macOS laptop) are
/// each self-identifying. macOS / Android / Windows report the band directly;
/// iOS derives it from the channel (see [ConnectedAp.bandDerived]).
@visibleForTesting
String capturePlatformLabel(WifiInfoSource source) {
  switch (source) {
    case WifiInfoSource.macosCoreWlan:
      return 'macOS';
    case WifiInfoSource.iosShortcuts:
      return 'iOS';
    case WifiInfoSource.androidWifiManager:
      return 'Android';
    case WifiInfoSource.windowsNativeWifi:
      return 'Windows';
    case WifiInfoSource.unsupported:
    case WifiInfoSource.web:
      return 'this device';
  }
}

/// The channel-first band/channel descriptor for one side of a roam, e.g.
/// "ch 44 · 5 GHz". Channel LEADS because it is exact on every platform; band
/// is the derived companion on iOS, where a bare channel number mislabels 6 GHz
/// APs (channels 36 to 177 read as "5 GHz", channels 1 to 14 as "2.4 GHz"). A
/// [derived] band carries the trailing "*" that the report's footnote explains.
/// Omits any null part honestly; returns "" when neither is known.
@visibleForTesting
String bandChannelLabel(int? channel, String? band, {bool derived = false}) {
  final List<String> parts = <String>[];
  if (channel != null) parts.add('ch $channel');
  if (band != null && band.trim().isNotEmpty) {
    parts.add(derived ? '$band*' : band);
  }
  return parts.join(' · ');
}

/// True when any roam in the session carried a band that was derived app-side
/// (iOS). Drives the "band derived" footnote so it appears only when relevant.
bool _anyBandDerived(List<RoamEvent> events) => events.any(
      (RoamEvent e) =>
          (e.fromBandDerived && e.fromBand != null) ||
          (e.toBandDerived && e.toBand != null),
    );

/// The one-line derived-band caveat. Kept identical between the Copy report and
/// the Share document so both read the same honest way.
const String _kDerivedBandNote =
    '* Band derived from the channel number on iOS; it can disagree with a '
    'device that reads the band directly, notably in 6 GHz. The channel is '
    'exact on every platform.';

/// The foreground caveat, matched to the capture platform so a macOS / Android
/// report does not carry an iOS-specific note. iOS states the hard ceiling (no
/// background Wi-Fi callbacks exist); the others state the plainer truth.
String _foregroundNote(String capturePlatform) => capturePlatform == 'iOS'
    ? 'iOS records roams only while this screen is open and running. There is no '
        'background Wi-Fi monitoring on iOS.'
    : 'Roams are recorded while this screen is open.';

/// Builds the §8.16 copy payload: the recorded roam session as a clean,
/// monospace-aligned, paste-anywhere plain-text report. A header (network,
/// capture platform, session window, roam count, and a signal summary) then a
/// fixed-column table, one row per [RoamEvent] in chronological order, each
/// leading with the CHANNEL (exact everywhere) and carrying the last-octet AP
/// identifiers, the band (marked derived on iOS), the signal + SNR, and the
/// dwell on the prior AP.
///
/// Honesty (GL-005): a field a sample omitted prints as "n/a" or is dropped from
/// the summary — never a fabricated value. Returns null (→ disabled affordance)
/// when [events] is empty; the empty session is not a "log to keep".
///
/// Pure and deterministic (no clock, no I/O). ASCII-safe arrows ("->") and no em
/// dashes, so the voice guard passes. Unit-tested directly with synthetic
/// [RoamEvent]s, no live sampler required.
@visibleForTesting
String? buildRoamLogCopyText({
  required List<RoamEvent> events,
  required String network,
  String capturePlatform = 'this device',
  DateTime? sessionStart,
}) {
  if (events.isEmpty) return null;

  final StringBuffer buf = StringBuffer()
    ..writeln('Roaming Log')
    ..writeln('Network: $network')
    ..writeln('Captured on: $capturePlatform');

  // Session window: opened at sessionStart (or the first roam if none), through
  // the last roam.
  final DateTime windowStart = sessionStart ?? events.first.at;
  final DateTime windowEnd = events.last.at;
  buf.writeln(
    'Session: ${_RoamRow._formatTime(windowStart)} to '
    '${_RoamRow._formatTime(windowEnd)} '
    '(${_formatDwell(windowEnd.difference(windowStart))})',
  );
  buf.writeln(
    events.length == 1 ? '1 roam recorded' : '${events.length} roams recorded',
  );
  buf.writeln(_signalSummary(events));

  // Build the table cells, then size each column to its widest cell so the
  // report aligns in any monospace context (a code block, Notes, a terminal).
  const List<String> headers = <String>[
    '#',
    'Time',
    'From',
    'To',
    'Signal',
    'On prev AP',
  ];
  final List<List<String>> rows = <List<String>>[];
  for (int i = 0; i < events.length; i++) {
    final RoamEvent e = events[i];
    rows.add(<String>[
      '${i + 1}',
      _RoamRow._formatTime(e.at),
      _apCell(e.fromBssid, e.fromChannel, e.fromBand, e.fromBandDerived),
      _apCell(e.toBssid, e.toChannel, e.toBand, e.toBandDerived),
      _signalCell(e),
      // The first roam has no prior roam to measure dwell from, so it is honestly
      // "n/a" rather than a guessed 0.
      i == 0 ? 'n/a' : _formatDwell(e.at.difference(events[i - 1].at)),
    ]);
  }

  final List<int> widths = List<int>.generate(headers.length, (int c) {
    int w = headers[c].length;
    for (final List<String> r in rows) {
      if (r[c].length > w) w = r[c].length;
    }
    return w;
  });

  String pad(String cell, int col) {
    // Right-align the ordinal column, left-align the rest.
    return col == 0
        ? cell.padLeft(widths[col])
        : cell.padRight(widths[col]);
  }

  String line(List<String> cells) {
    final List<String> padded = <String>[
      for (int c = 0; c < cells.length; c++) pad(cells[c], c),
    ];
    return padded.join('  ').trimRight();
  }

  buf
    ..writeln()
    ..writeln(line(headers));
  for (final List<String> r in rows) {
    buf.writeln(line(r));
  }

  // Honesty footnotes.
  buf.writeln();
  if (_anyBandDerived(events)) buf.writeln(_kDerivedBandNote);
  buf.write(_foregroundNote(capturePlatform));

  return buf.toString().trimRight();
}

/// One from/to table cell: last-octet identifier, then the channel-first band
/// descriptor (e.g. ":3a:10 ch 44 · 5 GHz").
String _apCell(String bssid, int? channel, String? band, bool derived) {
  final String tail = lastOctets(bssid);
  final String bc = bandChannelLabel(channel, band, derived: derived);
  return bc.isEmpty ? tail : '$tail $bc';
}

/// The signal cell for the table: "-67 dBm" plus " SNR 30 dB" when present, or
/// the honest "signal n/a" when the platform omitted RSSI.
String _signalCell(RoamEvent e) {
  if (e.rssiDbm == null) return 'signal n/a';
  final String snr = e.snrDb != null ? ' SNR ${e.snrDb} dB' : '';
  return '${e.rssiDbm} dBm$snr';
}

/// The header signal-summary line: average, strongest, and weakest RSSI across
/// the roams that carried one. "Signal: not reported" when none did (GL-005).
String _signalSummary(List<RoamEvent> events) {
  final List<int> rssi = <int>[
    for (final RoamEvent e in events)
      if (e.rssiDbm != null) e.rssiDbm!,
  ];
  if (rssi.isEmpty) return 'Signal: not reported';
  final int sum = rssi.reduce((int a, int b) => a + b);
  final int avg = (sum / rssi.length).round();
  // RSSI is negative dBm: the strongest is the greatest (closest to zero).
  final int strongest = rssi.reduce((int a, int b) => a > b ? a : b);
  final int weakest = rssi.reduce((int a, int b) => a < b ? a : b);
  return 'Signal: avg $avg dBm, strongest $strongest dBm, weakest $weakest dBm';
}

/// "45s" / "2m" / "2m 5s" — dwell between consecutive roams, no intl dependency.
/// Negative/zero clamps to "0s".
String _formatDwell(Duration d) {
  final int total = d.inSeconds;
  if (total <= 0) return '0s';
  if (total < 60) return '${total}s';
  final int minutes = total ~/ 60;
  final int seconds = total % 60;
  return seconds == 0 ? '${minutes}m' : '${minutes}m ${seconds}s';
}

/// Builds the §8.16 Share document: a self-contained HTML report that visually
/// echoes the Copy report (title header, a summary block, the full roam table,
/// and the honesty notes). Shared to the platform sheet as a file (Mail
/// attachment / Files / AirDrop). Unlike the compact on-screen rows, the table
/// carries the COMPLETE BSSIDs alongside the channel and band, because a
/// document has room for them.
///
/// The layout is identical across iOS / macOS / Android (only the "Captured on"
/// stamp and the derived-band footnote differ), so three captures read as one
/// tool. Pure and deterministic; returns null when [events] is empty. No em
/// dashes; every interpolated value is HTML-escaped.
@visibleForTesting
String? buildRoamLogShareHtml({
  required List<RoamEvent> events,
  required String network,
  String capturePlatform = 'this device',
  DateTime? sessionStart,
}) {
  if (events.isEmpty) return null;

  final DateTime windowStart = sessionStart ?? events.first.at;
  final DateTime windowEnd = events.last.at;
  final String countLabel =
      events.length == 1 ? '1 roam recorded' : '${events.length} roams recorded';

  String esc(String s) => const HtmlEscape().convert(s);

  final StringBuffer rowsHtml = StringBuffer();
  for (int i = 0; i < events.length; i++) {
    final RoamEvent e = events[i];
    final String dwell =
        i == 0 ? 'n/a' : _formatDwell(e.at.difference(events[i - 1].at));
    rowsHtml.writeln(
      '<tr>'
      '<td class="num">${i + 1}</td>'
      '<td>${esc(_RoamRow._formatTime(e.at))}</td>'
      '<td>${_apCellHtml(e.fromBssid, e.fromChannel, e.fromBand, e.fromBandDerived, esc)}</td>'
      '<td>${_apCellHtml(e.toBssid, e.toChannel, e.toBand, e.toBandDerived, esc)}</td>'
      '<td>${esc(_signalCell(e))}</td>'
      '<td>${esc(dwell)}</td>'
      '</tr>',
    );
  }

  final StringBuffer notes = StringBuffer();
  if (_anyBandDerived(events)) {
    notes.writeln('<p class="note">${esc(_kDerivedBandNote)}</p>');
  }
  notes.writeln(
      '<p class="note">${esc(_foregroundNote(capturePlatform))}</p>');

  return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Roaming Log</title>
<style>
  body { font-family: -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
         color: #1a1a1a; margin: 24px; line-height: 1.4; }
  h1 { font-size: 22px; margin: 0 0 4px; }
  .summary { margin: 0 0 16px; color: #444; }
  .summary div { margin: 2px 0; }
  table { border-collapse: collapse; width: 100%; font-size: 13px; }
  th, td { border: 1px solid #d0d0d0; padding: 6px 8px; text-align: left;
           vertical-align: top; }
  th { background: #f2f2f2; }
  td.num, th.num { text-align: right; white-space: nowrap; }
  code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
  .note { font-size: 12px; color: #666; margin: 12px 0 0; }
</style>
</head>
<body>
<h1>Roaming Log</h1>
<div class="summary">
<div><strong>Network:</strong> ${esc(network)}</div>
<div><strong>Captured on:</strong> ${esc(capturePlatform)}</div>
<div><strong>Session:</strong> ${esc(_RoamRow._formatTime(windowStart))} to ${esc(_RoamRow._formatTime(windowEnd))} (${esc(_formatDwell(windowEnd.difference(windowStart)))})</div>
<div><strong>${esc(countLabel)}</strong></div>
<div>${esc(_signalSummary(events))}</div>
</div>
<table>
<thead>
<tr><th class="num">#</th><th>Time</th><th>From AP</th><th>To AP</th><th>Signal</th><th>On prev AP</th></tr>
</thead>
<tbody>
${rowsHtml.toString().trimRight()}
</tbody>
</table>
${notes.toString().trimRight()}
</body>
</html>
''';
}

/// One from/to document cell: the FULL BSSID (there is room in a document) as
/// mono code, then the channel-first band descriptor beneath.
String _apCellHtml(
  String bssid,
  int? channel,
  String? band,
  bool derived,
  String Function(String) esc,
) {
  final String bc = bandChannelLabel(channel, band, derived: derived);
  final String code = '<code>${esc(bssid)}</code>';
  return bc.isEmpty ? code : '$code<br>${esc(bc)}';
}

/// The roam-log card: a header with the live/Start control + roam count, then
/// the roam-events list (or an honest empty / not-started state).
class _RoamLogCard extends StatelessWidget {
  const _RoamLogCard({required this.sampler}) : _disabledMessage = null;

  /// The web/unsupported branch never reaches a card, but keep a graceful
  /// non-null fallback so the screen never renders a bare hole.
  const _RoamLogCard._disabled(this._disabledMessage) : sampler = null;

  factory _RoamLogCard.disabled(BuildContext context) =>
      const _RoamLogCard._disabled(
        'Live Wi-Fi monitoring is off on this device.',
      );

  final WifiSignalSampler? sampler;
  final String? _disabledMessage;

  @override
  Widget build(BuildContext context) {
    final WifiSignalSampler? s = sampler;
    if (s == null) {
      return _Card(
        child: Text(
          _disabledMessage ?? 'Unavailable.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: context.colors.textSecondary),
        ),
      );
    }
    return AnimatedBuilder(
      animation: s,
      builder: (BuildContext context, _) {
        final TextTheme text = Theme.of(context).textTheme;
        final AppColorScheme colors = context.colors;
        final List<RoamEvent> events = s.roamEvents;
        final Color liveColor =
            colors.isLight ? colors.textAccent : colors.primary;

        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Header(sampler: s, liveColor: liveColor, roamCount: events.length),
              const SizedBox(height: AppSpacing.sm),
              if (s.isIos && s.triggerError)
                _Note(
                  message:
                      'Could not start the live Wi-Fi feed. The companion '
                      '"WLAN Pros Live" Shortcut may not be installed. Install '
                      'it, then tap Start.',
                )
              else if (s.isIos && !s.isStreaming)
                _Note(
                  message:
                      'Tap Start to begin recording roams from the companion '
                      'Shortcut. Then walk your space with this screen open.',
                )
              else if (events.isEmpty)
                _Note(
                  message:
                      'Watching for roams… none recorded yet. Move around your '
                      'space. A roam is logged each time your device switches '
                      'to a different access point on the same network.',
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int i = events.length - 1; i >= 0; i--)
                      _RoamRow(
                        event: events[i],
                        index: i + 1,
                      ),
                  ],
                ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                s.isIos
                    ? 'Foreground session only on iOS. Roams that happen with '
                        'the app closed or your phone in your pocket are not '
                        'recorded. No app can do that on iOS.'
                    : 'Records roams while this screen is open.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Card header: title + roam count, plus the iOS Start/LIVE/Stop control (macOS
/// shows a passive LIVE indicator since it auto-polls).
class _Header extends StatelessWidget {
  const _Header({
    required this.sampler,
    required this.liveColor,
    required this.roamCount,
  });

  final WifiSignalSampler sampler;
  final Color liveColor;
  final int roamCount;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final String countLabel =
        roamCount == 1 ? '1 roam' : '$roamCount roams';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              'Roams this session',
              style: text.labelMedium?.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
        // Roam count badge — always carries the number as a word, never color.
        Text(
          countLabel,
          style: text.labelMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _control(context),
      ],
    );
  }

  Widget _control(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    // iOS, not streaming → Start. iOS, streaming → LIVE + Stop. macOS → LIVE.
    if (sampler.isIos && !sampler.isStreaming) {
      return Semantics(
        button: true,
        label: 'Start recording roams',
        child: OutlinedButton.icon(
          onPressed: sampler.start,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Start'),
        ),
      );
    }
    if (sampler.isIos && sampler.isStreaming) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _LiveDot(color: liveColor),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            'LIVE',
            style: text.labelMedium?.copyWith(
              color: liveColor,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Semantics(
            button: true,
            label: 'Stop recording roams',
            child: IconButton(
              icon: const Icon(Icons.stop, size: 20),
              tooltip: 'Stop',
              visualDensity: VisualDensity.compact,
              onPressed: sampler.stop,
            ),
          ),
        ],
      );
    }
    // macOS / Android — passive LIVE indicator (auto-poll, no Start/Stop).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _LiveDot(color: liveColor),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          'LIVE',
          style: text.labelMedium?.copyWith(
            color: liveColor,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// One roam event: ordinal + timestamp, the from→to BSSID pair, and the signal
/// at the roam. The whole row is one SR node.
class _RoamRow extends StatelessWidget {
  const _RoamRow({required this.event, required this.index});

  final RoamEvent event;
  final int index;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;

    final String time = _formatTime(event.at);
    final String signal = event.rssiDbm != null
        ? '${event.rssiDbm} dBm'
        : 'Signal unavailable';
    final String snr = event.snrDb != null ? ' · SNR ${event.snrDb} dB' : '';
    final String network = event.ssid != null && event.ssid!.trim().isNotEmpty
        ? event.ssid!
        : 'Wi-Fi';

    // The a11y label keeps the FULL BSSID (the visible row shows only the
    // identifying last octets) plus the channel-first band for each AP.
    final String fromSpoken = _spokenAp(
      event.fromBssid, event.fromChannel, event.fromBand, event.fromBandDerived);
    final String toSpoken = _spokenAp(
      event.toBssid, event.toChannel, event.toBand, event.toBandDerived);

    return Semantics(
      container: true,
      label: 'Roam $index on $network at $time, from access point '
          '$fromSpoken to access point $toSpoken, '
          '${event.rssiDbm != null ? 'signal ${event.rssiDbm} dBm' : 'signal unavailable'}'
          '${event.snrDb != null ? ', SNR ${event.snrDb} dB' : ''}.',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Time + network + ordinal.
              Row(
                children: <Widget>[
                  Icon(
                    Icons.swap_horiz,
                    size: 16,
                    color: colors.textAccent,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      '$time · $network',
                      style: text.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '#$index',
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              // From -> To APs. The identifier is the LAST TWO OCTETS (the OUI is
              // shared across a same-brand deployment; the tail is what tells the
              // radios apart), never truncated. Beneath each: the channel-first
              // band descriptor (channel is exact on every platform; band is the
              // derived companion on iOS).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Flexible(
                    child: _ApBlock(
                      bssid: event.fromBssid,
                      channel: event.fromChannel,
                      band: event.fromBand,
                      bandDerived: event.fromBandDerived,
                      color: colors.textSecondary,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: colors.textTertiary,
                    ),
                  ),
                  Flexible(
                    child: _ApBlock(
                      bssid: event.toBssid,
                      channel: event.toChannel,
                      band: event.toBand,
                      bandDerived: event.toBandDerived,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              // Signal at the roam.
              Text(
                'Signal at roam: $signal$snr',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "2:14:07 PM" — 12-hour clock with seconds (roams cluster, so seconds help
  /// distinguish them), no intl dependency.
  static String _formatTime(DateTime at) {
    final int hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final String minute = at.minute.toString().padLeft(2, '0');
    final String second = at.second.toString().padLeft(2, '0');
    final String meridiem = at.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute:$second $meridiem';
  }
}

/// The spoken form of an AP for the row's a11y label: the FULL BSSID (so screen
/// readers announce the whole address, not just the visible tail) plus the
/// channel and band, with the honest "derived" note when the band was computed
/// app-side.
String _spokenAp(String bssid, int? channel, String? band, bool bandDerived) {
  final StringBuffer b = StringBuffer(bssid);
  if (channel != null) b.write(' on channel $channel');
  if (band != null && band.trim().isNotEmpty) {
    b.write(', $band band${bandDerived ? ' derived' : ''}');
  }
  return b.toString();
}

/// The on-screen channel-first band descriptor beneath an AP identifier, e.g.
/// "ch 44 · 5 GHz". Channel LEADS (exact on every platform); band is the derived
/// companion on iOS and carries the app-standard "(derived)" caption then. Omits
/// null parts honestly; returns "" when neither is known.
String _rowBandChannel(int? channel, String? band, bool derived) {
  final List<String> parts = <String>[];
  if (channel != null) parts.add('ch $channel');
  if (band != null && band.trim().isNotEmpty) {
    parts.add(derived ? '$band (derived)' : band);
  }
  return parts.join(' · ');
}

/// One AP in a roam row: the identifying last two octets (mono, never
/// truncated), and beneath it the channel-first band descriptor.
class _ApBlock extends StatelessWidget {
  const _ApBlock({
    required this.bssid,
    required this.channel,
    required this.band,
    required this.bandDerived,
    required this.color,
  });

  final String bssid;
  final int? channel;
  final String? band;
  final bool bandDerived;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final String meta = _rowBandChannel(channel, band, bandDerived);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          lastOctets(bssid),
          softWrap: false,
          style: mono.robotoMono.copyWith(color: color),
        ),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              meta,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
      ],
    );
  }
}

/// The §8.16 "Share document" AppBar action: exports the session as a formatted
/// HTML document to the platform share sheet (Mail attachment / Files / AirDrop).
/// Mirrors [AppCopyAction]'s enabled/disabled contract — [htmlBuilder] returns
/// null when there is no roam to export, and the affordance then renders disabled
/// and drops from focus traversal. Placed AFTER copy per the §8.16 order rule.
class _RoamShareAction extends StatelessWidget {
  const _RoamShareAction({
    required this.htmlBuilder,
    required this.shareFn,
  });

  /// Returns the full HTML document to share, or null when there is nothing to
  /// export yet (→ disabled). Evaluated at tap time to serialize on demand, and
  /// its null-ness is read at build time to resolve the enabled state.
  final String? Function() htmlBuilder;

  /// The share seam. Defaults to the real [shareBytes]; tests inject a fake so
  /// the platform share channel is never touched.
  final RoamShareFn shareFn;

  Future<void> _handleTap(BuildContext context) async {
    final String? html = htmlBuilder();
    if (html == null) return;

    // Anchor the iPad/macOS share popover to this button's rect, or the platform
    // throws (mirrors the PDF-card share path).
    ShareOrigin? origin;
    final RenderObject? box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final Offset topLeft = box.localToGlobal(Offset.zero);
      origin = ShareOrigin(
        topLeft.dx,
        topLeft.dy,
        box.size.width,
        box.size.height,
      );
    }

    await shareFn(
      bytes: utf8.encode(html),
      filename: 'roaming-log.html',
      mimeType: 'text/html',
      title: 'Roaming Log',
      shareOrigin: origin,
    );

    if (context.mounted) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Sharing roaming log',
        TextDirection.ltr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool enabled = htmlBuilder() != null;
    const String label = 'Share roaming log';

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: IconButton(
          onPressed: enabled ? () => _handleTap(context) : null,
          iconSize: 24,
          tooltip: enabled ? label : null,
          icon: Icon(
            Icons.ios_share,
            size: 24,
            color: enabled ? colors.textSecondary : colors.textDisabled,
          ),
        ),
      ),
    );
  }
}

/// An honest status note inside the card (empty / not-started / failed states).
class _Note extends StatelessWidget {
  const _Note({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      message,
      style: text.bodyMedium?.copyWith(color: context.colors.textSecondary),
    );
  }
}

/// The "LIVE" dot — lime is the §8.3 active-state accent, resolved by the parent
/// so it stays visible on white (§8.20.2).
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// A surface1 card with the §8.1 hairline border, matching the sibling result
/// cards across the network tools.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}
