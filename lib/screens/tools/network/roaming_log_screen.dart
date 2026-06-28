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

import 'package:flutter/material.dart';

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

/// The Roaming Log screen — a foreground roam recorder built on the shared live
/// sampler.
class RoamingLogScreen extends StatefulWidget {
  const RoamingLogScreen({
    super.key,
    this.sourceOverride,
    this.sampler,
    this.enableSampling = true,
  });

  /// Forces a specific Wi-Fi data source (tests). Defaults to the host platform
  /// via [WifiInfoSourceResolver].
  final WifiInfoSource? sourceOverride;

  /// Injectable live sampler (tests). Defaults to a real [WifiSignalSampler] on
  /// the resolved platform.
  final WifiSignalSampler? sampler;

  /// When false, no sampler is started (tests that drive the sampler manually).
  final bool enableSampling;

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

    if (widget.enableSampling &&
        (_source == WifiInfoSource.macosCoreWlan ||
            _source == WifiInfoSource.androidWifiManager ||
            _source == WifiInfoSource.iosShortcuts)) {
      _sampler = widget.sampler ?? WifiSignalSampler(source: _source);
      _sessionStart = DateTime.now();
      WidgetsBinding.instance.addObserver(this);
      _sampler!.load();
      // macOS / Android source the feed from NATIVE polling (no app switch), so
      // they auto-start on entry; iOS waits for the single deliberate Start tap
      // (firing the companion Shortcut would bounce the user out of the app).
      if (_source == WifiInfoSource.macosCoreWlan ||
          _source == WifiInfoSource.androidWifiManager) {
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
        // §8.16: copy is the sanctioned AppBar action on a results screen. The
        // closure serializes the session log on demand and returns null until at
        // least one roam exists, so the affordance is disabled (not focusable)
        // on the honest empty state — never copies a fake/empty log.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

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
          : 'Walk around with this open to record each time your device roams '
              'from one access point to another on the same network. macOS reads '
              'the link continuously while this screen is open.',
      style: text.bodyLarge?.copyWith(color: colors.textSecondary),
    );
  }
}

/// Builds the §8.16 copy payload: the recorded roam session as paste-ready plain
/// text. A short header (network · session-open time · roam count) then one
/// block per [RoamEvent] in chronological order, each carrying the timestamp,
/// the from→to BSSID pair, the signal read at the roam, and the dwell on the
/// prior AP (derived from consecutive roam timestamps).
///
/// Honesty (GL-005): a field a sample omitted prints as "unavailable", matching
/// the on-screen wording — never a fabricated value. Returns null (→ disabled
/// affordance) when [events] is empty; the empty session is not a "log to keep".
///
/// Pure and deterministic (no clock, no I/O), so it is unit-tested directly with
/// synthetic [RoamEvent]s — no live sampler required.
@visibleForTesting
String? buildRoamLogCopyText({
  required List<RoamEvent> events,
  required String network,
  DateTime? sessionStart,
}) {
  if (events.isEmpty) return null;

  final StringBuffer buf = StringBuffer()
    ..writeln('Roaming Log')
    ..writeln('Network: $network');
  if (sessionStart != null) {
    buf.writeln('Session started: ${_RoamRow._formatTime(sessionStart)}');
  }
  buf.writeln(
    events.length == 1 ? '1 roam recorded' : '${events.length} roams recorded',
  );

  for (int i = 0; i < events.length; i++) {
    final RoamEvent e = events[i];
    final String evNetwork =
        e.ssid != null && e.ssid!.trim().isNotEmpty ? e.ssid! : 'Wi-Fi';
    final String signal = e.rssiDbm != null ? '${e.rssiDbm} dBm' : 'unavailable';
    final String snr = e.snrDb != null ? ' · SNR ${e.snrDb} dB' : '';

    buf
      ..writeln()
      ..writeln('${i + 1}. ${_RoamRow._formatTime(e.at)} · $evNetwork')
      ..writeln('   ${e.fromBssid} -> ${e.toBssid}')
      ..writeln('   Signal at roam: $signal$snr');
    // Dwell on the AP just left = time between this roam and the prior one. The
    // first roam has no prior roam to measure from, so it is omitted rather than
    // guessed.
    if (i > 0) {
      final Duration dwell = e.at.difference(events[i - 1].at);
      buf.writeln('   Time on previous AP: ${_formatDwell(dwell)}');
    }
  }

  return buf.toString().trimRight();
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
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final String time = _formatTime(event.at);
    final String signal = event.rssiDbm != null
        ? '${event.rssiDbm} dBm'
        : 'Signal unavailable';
    final String snr = event.snrDb != null ? ' · SNR ${event.snrDb} dB' : '';
    final String network = event.ssid != null && event.ssid!.trim().isNotEmpty
        ? event.ssid!
        : 'Wi-Fi';

    return Semantics(
      container: true,
      label: 'Roam $index on $network at $time, from access point '
          '${event.fromBssid} to ${event.toBssid}, '
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
              // From → To BSSID pair (mono, identifiers).
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      event.fromBssid,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono.robotoMono.copyWith(
                        color: colors.textSecondary,
                      ),
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
                    child: Text(
                      event.toBssid,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono.robotoMono.copyWith(
                        color: colors.textPrimary,
                      ),
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
