// Wi-Fi Information tool — shows the live CoreWLAN link state on macOS.
//
// Reads a snapshot from the already-built, tested WifiInfoService (native
// CoreWLAN bridge → Dart service). This screen only consumes that service; it
// never touches the channel or the native code directly.
//
// macOS is the only platform with a Wi-Fi info bridge today. Per GL-008 the
// honest answer off macOS is a NetworkUnavailableView naming what is missing
// and why, never a fabricated reading.
//
// Two readings macOS CoreWLAN does not expose are shown as explicit
// "Unavailable" rows rather than dropped, so the absence is visible and never
// reads as a bug:
//   - Rx (receive) rate.
//   - Tx power.
//
// States (SOP-007 §5):
//  - unavailable → NetworkUnavailableView (web, and any non-macOS native).
//  - loading     → labeled spinner while the snapshot reads (announced).
//  - success     → grouped cards: optional location card, then metric rows.
//  - wifi-off    → leads with a "Wi-Fi is off" state, still shows the payload.
//  - error       → in-flow info/error card with the channel detail + retry.
//
// Layout matches interface_info_screen and net_quality_screen: SafeArea +
// LayoutBuilder + centered ConstrainedBox + scroll, surface1 cards with a
// hairline border, mono for addresses/numerics, the concept-graphic band
// degrades to nothing when the tool has no graphic asset yet.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/wifi_info_service.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../concept_graphic_band.dart';
import 'network_unavailable_view.dart';

/// The Wi-Fi Information tool screen.
///
/// Reads live link metrics from [WifiInfoService]. The [service] seam is
/// injectable so widget tests can drive the screen with a fake invoker and a
/// platform override, without a real platform channel.
class WifiInfoScreen extends StatefulWidget {
  const WifiInfoScreen({super.key, this.service});

  /// Injectable for tests; defaults to the real service for the host platform.
  final WifiInfoService? service;

  @override
  State<WifiInfoScreen> createState() => _WifiInfoScreenState();
}

class _WifiInfoScreenState extends State<WifiInfoScreen> {
  late final WifiInfoService _service;

  /// True once a snapshot read is in flight.
  bool _loading = false;

  /// The most recent successful snapshot, or null before the first read.
  WifiInfo? _info;

  /// The most recent channel error, or null when the last read succeeded.
  WifiInfoUnavailable? _error;

  /// Set true once a location-permission request has completed at least once.
  /// Drives the post-grant ("may need a relaunch") copy so the Grant button
  /// does not invite an endless re-tap loop (macOS often needs an app
  /// relaunch before the SSID appears even after authorization).
  bool _locationGrantAttempted = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? WifiInfoService();
    // Off macOS (and on web) the service has no bridge. Do not call fetch();
    // the build path renders NetworkUnavailableView instead.
    if (!kIsWeb && _service.isSupportedPlatform) {
      _fetch();
    }
  }

  /// Reads a fresh snapshot.
  ///
  /// WCAG 4.1.3 — the loading state is announced by the `liveRegion` on the
  /// `_LoadingCard` (same approach as interface_info_screen's labeled
  /// liveRegion spinner), so assistive tech speaks "Reading Wi-Fi link state…"
  /// when the card appears. No imperative `SemanticsService` announce here: the
  /// first read fires from `initState`, and an imperative announce on that path
  /// races widget teardown (the binding can be disposed before the async
  /// completes). The liveRegion is the robust, declarative equivalent.
  /// Reads a fresh snapshot. [manual] is true for a user-initiated refresh
  /// (the app-bar button), which shows a brief confirmation so the action is
  /// never silent: a live read often returns identical values, so without a
  /// snackbar a successful refresh would look like nothing happened.
  Future<void> _fetch({bool manual = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final WifiInfo info = await _service.fetch();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
      if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wi-Fi information updated'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on WifiInfoUnavailable catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } catch (e) {
      // Defensive: any unexpected error must still clear the loading state so
      // the screen can never sit on a spinner forever.
      if (!mounted) return;
      setState(() {
        _error = WifiInfoUnavailable(
          WifiInfoUnavailableReason.channelError,
          e.toString(),
        );
        _loading = false;
      });
    }
  }

  /// Requests Location Services authorization, then re-reads regardless of the
  /// result. macOS gates SSID and BSSID behind Location; re-fetching surfaces
  /// the newly-authorized fields (or the post-grant relaunch state).
  Future<void> _grantLocation() async {
    await _service.requestLocationPermission();
    if (!mounted) return;
    _locationGrantAttempted = true;
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Information'),
        toolbarHeight: 64,
        actions: [
          if (!kIsWeb && _service.isSupportedPlatform)
            // While a read is in flight the icon becomes a spinner so a refresh
            // is visibly working even when the values come back unchanged.
            _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  )
                : Semantics(
                    button: true,
                    label: 'Refresh Wi-Fi information',
                    child: IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh',
                      onPressed: () => _fetch(manual: true),
                    ),
                  ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    // Web and any non-macOS native target: honest unavailable view. CoreWLAN
    // link details come only from the macOS Wi-Fi framework and only macOS is
    // implemented so far.
    if (kIsWeb || !_service.isSupportedPlatform) {
      return const NetworkUnavailableView(
        toolName: 'Wi-Fi Information',
        reason: NetworkUnavailableReason.platformApiMissing,
        icon: Icons.wifi_off,
        headline: 'Wi-Fi Information is macOS-only for now',
        message:
            'Live Wi-Fi link details come from the operating system Wi-Fi '
            'framework, and only macOS is implemented so far. Windows and '
            'Android are planned. iOS does not expose these link details to '
            'apps.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            edge,
            AppSpacing.sm,
            edge,
            edge + AppSpacing.sm,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _content(isDesktop),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the scrolling content for the supported (macOS) path.
  List<Widget> _content(bool isDesktop) {
    final List<Widget> children = <Widget>[
      // Concept graphic degrades to nothing while 'wifi-info' has no asset.
      ConceptGraphicBand(toolId: 'wifi-info', isDesktop: isDesktop),
      if (ToolAssets.hasGraphic('wifi-info'))
        const SizedBox(height: AppSpacing.md),
    ];

    // Loading: before the first snapshot resolves there is nothing to show.
    if (_loading && _info == null && _error == null) {
      children.add(const _LoadingCard());
      return children;
    }

    // Channel error with no prior payload: an in-flow info/error card. Not a
    // false-error affordance — it reports the channel detail and offers retry.
    if (_error != null && _info == null) {
      children.add(_ErrorCard(error: _error!, onRetry: _loading ? null : _fetch));
      return children;
    }

    final WifiInfo? info = _info;
    if (info == null) {
      // Defensive: no payload, no error (e.g. first frame race). Offer retry.
      children.add(_ErrorCard(error: null, onRetry: _loading ? null : _fetch));
      return children;
    }

    // Wi-Fi powered off: lead with a clear state, still show whatever the
    // payload carries below it.
    if (!info.poweredOn) {
      children
        ..add(const _WifiOffCard())
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    // Location card (three states) sits above the Network card when relevant.
    final Widget? locationCard = _buildLocationCard(info);
    if (locationCard != null) {
      children
        ..add(locationCard)
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    // A stale-channel error after a prior success: show it inline but keep the
    // last good payload visible.
    if (_error != null) {
      children
        ..add(_ErrorCard(error: _error!, onRetry: _loading ? null : _fetch))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    children
      ..add(_networkCard(info))
      ..add(const SizedBox(height: AppSpacing.sm))
      ..add(_signalCard(info))
      ..add(const SizedBox(height: AppSpacing.sm))
      ..add(_rateCard(info))
      ..add(const SizedBox(height: AppSpacing.sm))
      ..add(_channelCard(info))
      ..add(const SizedBox(height: AppSpacing.sm))
      ..add(_radioCard(info))
      ..add(const SizedBox(height: AppSpacing.sm))
      ..add(_statusCard(info));

    return children;
  }

  // ---- Location card (three states) ----

  /// Returns the location card for the current snapshot, or null when the
  /// network name is present and no card is needed.
  ///
  /// State (a): not authorized → original copy + Grant button.
  /// State (b): authorized, ssid still null, a grant was attempted →
  ///            post-grant relaunch copy, no Grant button.
  /// State (c): ssid present → no card.
  Widget? _buildLocationCard(WifiInfo info) {
    final bool nameMissing = info.ssid == null && info.bssid == null;

    // State (c): we have a network name — nothing to prompt.
    if (info.ssid != null) return null;

    // State (b): granted, but the SSID is still hidden and we already asked.
    if (info.locationAuthorized &&
        info.ssid == null &&
        _locationGrantAttempted) {
      return const _LocationCard(
        message:
            'Permission granted. macOS may need an app relaunch before the '
            'network name appears. The signal and channel details below are '
            'unaffected.',
        onGrant: null,
      );
    }

    // State (a): not authorized, or name missing without authorization.
    if (!info.locationAuthorized || nameMissing) {
      return _LocationCard(
        message:
            'Network name needs Location permission. macOS requires Location '
            'Services authorization to read the SSID and BSSID. The signal '
            'and channel details below do not need it.',
        onGrant: _loading ? null : _grantLocation,
      );
    }

    return null;
  }

  // ---- Metric cards ----

  Widget _networkCard(WifiInfo info) {
    return _Card(
      title: 'Network',
      child: Column(
        children: [
          _MetricRow(label: 'SSID', value: info.ssid),
          _MetricRow(label: 'BSSID', value: info.bssid, mono: true),
        ],
      ),
    );
  }

  Widget _signalCard(WifiInfo info) {
    return _Card(
      title: 'Signal',
      child: Column(
        children: [
          _MetricRow(
            label: 'RSSI',
            value: info.rssiDbm?.toString(),
            unit: 'dBm',
            mono: true,
          ),
          _MetricRow(
            label: 'Noise',
            value: info.noiseDbm?.toString(),
            unit: 'dBm',
            mono: true,
          ),
          _MetricRow(
            label: 'SNR',
            value: info.snrDb?.toString(),
            unit: 'dB',
            mono: true,
          ),
        ],
      ),
    );
  }

  Widget _rateCard(WifiInfo info) {
    return _Card(
      title: 'Rate',
      child: Column(
        children: [
          _MetricRow(
            label: 'Tx Rate',
            value: _formatRate(info.txRateMbps),
            unit: 'Mbps',
            mono: true,
          ),
          // Rx Rate and Tx Power are NOT exposed by macOS CoreWLAN. Keith asked
          // for Rx rate explicitly, so these are hard-coded visibly-unavailable
          // rows — they never read from data and never silently disappear. No
          // unit is shown because there is no value to attach it to.
          const _MetricRow(
            label: 'Rx Rate',
            value: null,
            mono: true,
            note: 'Not exposed by macOS CoreWLAN',
          ),
          const _MetricRow(
            label: 'Tx Power',
            value: null,
            mono: true,
            note: 'Not exposed by macOS CoreWLAN',
          ),
        ],
      ),
    );
  }

  Widget _channelCard(WifiInfo info) {
    final bool isPsc = _isPscChannel(info.channel, info.band);
    return _Card(
      title: 'Channel',
      child: Column(
        children: [
          _MetricRow(
            label: 'Channel',
            value: info.channel?.toString(),
            mono: true,
            marker: isPsc ? '*' : null,
            note: isPsc ? 'Preferred Scanning Channel (PSC)' : null,
          ),
          _MetricRow(
            label: 'Width',
            value: info.channelWidthMhz?.toString(),
            unit: 'MHz',
            mono: true,
          ),
          _MetricRow(label: 'Band', value: info.band),
        ],
      ),
    );
  }

  Widget _radioCard(WifiInfo info) {
    return _Card(
      title: 'Radio',
      child: Column(
        children: [
          _MetricRow(
            label: 'Wi-Fi Standard',
            value: _wifiStandardLabel(info.phyMode, info.band),
          ),
          _MetricRow(label: 'Country', value: info.countryCode),
          _MetricRow(label: 'Interface', value: info.interfaceName, mono: true),
          _MetricRow(
            label: 'Hardware Address',
            value: info.hardwareAddress,
            mono: true,
          ),
        ],
      ),
    );
  }

  /// Whether [channel] is a 6 GHz Preferred Scanning Channel (PSC).
  ///
  /// PSC channels are a 6 GHz concept (802.11ax/6E and later): the every-fourth
  /// 80 MHz channels that 6 GHz APs beacon on so clients find them quickly, per
  /// IEEE 802.11ax. They are channels 5, 21, 37, ... 229, i.e. (ch - 5) is a
  /// multiple of 16 across the 6 GHz range. Returns false for 2.4 and 5 GHz,
  /// where PSC does not apply.
  static bool _isPscChannel(int? channel, String? band) {
    if (channel == null || band != '6 GHz') return false;
    if (channel < 5 || channel > 233) return false;
    return (channel - 5) % 16 == 0;
  }

  /// Renders the link standard with both its 802.11 designation and its Wi-Fi
  /// generation, e.g. "802.11be (Wi-Fi 7)". Many readers think in Wi-Fi version
  /// numbers first, so both vocabularies appear to reinforce that each is valid.
  /// The 6 GHz band distinguishes Wi-Fi 6E from Wi-Fi 6 (both are 802.11ax).
  /// Pre-branding modes (a/b/g) have no Wi-Fi number, so only the 802.11 name is
  /// shown. Returns null (renders "Unavailable") when the PHY mode is unknown.
  static String? _wifiStandardLabel(String? phyMode, String? band) {
    if (phyMode == null) return null;
    final String? generation = switch (phyMode) {
      '802.11be' => 'Wi-Fi 7',
      '802.11ax' => band == '6 GHz' ? 'Wi-Fi 6E' : 'Wi-Fi 6',
      '802.11ac' => 'Wi-Fi 5',
      '802.11n' => 'Wi-Fi 4',
      _ => null,
    };
    return generation == null ? phyMode : '$phyMode ($generation)';
  }

  Widget _statusCard(WifiInfo info) {
    return _Card(
      title: 'Status',
      child: Column(
        children: [
          _MetricRow(
            label: 'Wi-Fi Power',
            value: info.poweredOn ? 'On' : 'Off',
          ),
        ],
      ),
    );
  }

  /// Formats the Tx rate without a trailing ".0" on whole numbers, or returns
  /// null so the row renders "Unavailable".
  static String? _formatRate(double? mbps) {
    if (mbps == null) return null;
    if (mbps == mbps.roundToDouble()) return mbps.toStringAsFixed(0);
    return mbps.toStringAsFixed(1);
  }
}

// ---- Reusable card shell (matches interface_info_screen._Card) ----

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

// ---- Single metric row ----
//
// One label → value row. A null/empty value renders the word "Unavailable" in
// textSecondary (muted but clears WCAG 4.5:1 — NOT textTertiary for value text,
// NOT a dash glyph, NOT a fake 0). Live values render in textPrimary. Each row
// is a single semantic node so a screen reader speaks "label, value" (or
// "label, Unavailable", with the honesty note appended) as one unit.

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.note,
    this.unit,
    this.marker,
  });

  /// The left-hand field name.
  final String label;

  /// The right-hand value. Null or empty renders "Unavailable".
  final String? value;

  /// Render the value in a monospaced face — for addresses and numerics.
  final bool mono;

  /// Optional note shown under the value. For an Unavailable value it explains
  /// why (e.g. "Not exposed by macOS CoreWLAN"); for a present value it is a
  /// footnote tied to [marker] (e.g. the PSC explanation).
  final String? note;

  /// Unit appended to the value (e.g. "dBm", "Mbps"), tied to the number rather
  /// than the label so a reading scans as "-50 dBm". Omitted when unavailable.
  final String? unit;

  /// Optional marker glyph appended to the value (e.g. "*") and used to prefix
  /// the [note] footnote, tying the two together. Shown only when the value is
  /// present. Excluded from the spoken value so screen readers do not say
  /// "star"; the [note] carries the meaning in speech instead.
  final String? marker;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasValue = value != null && value!.trim().isNotEmpty;
    final String shown = hasValue
        ? (unit == null ? value! : '${value!} $unit')
        : 'Unavailable';
    // The marker glyph rides on the visible value only (never spoken).
    final String displayValue =
        (hasValue && marker != null) ? '$shown $marker' : shown;
    // The footnote shows whenever a note exists. When a marker is present it
    // prefixes the footnote so the asterisk on the value visually ties to it.
    final bool showNote = note != null;
    final String footnote = note == null
        ? ''
        : (marker != null ? '$marker $note' : note!);

    // Compose the single accessible label. The spoken value omits the marker;
    // the note (without the glyph) carries the meaning.
    final String semanticLabel =
        showNote ? '$label, $shown, $note' : '$label, $shown';

    // Live values: primary. Unavailable: secondary (clears 4.5:1), never
    // tertiary for value text. Mono values use the shared Roboto Mono token, a
    // monospaced SANS-SERIF for identifiers (IP, MAC, subnet masks): hex columns
    // stay aligned without DM Mono's flared terminals that read as serifs at
    // small sizes. Sourced from the theme so it is consistent app-wide.
    final AppMonoText monoText =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final Color valueColor =
        hasValue ? AppColors.textPrimary : AppColors.textSecondary;
    final TextStyle? valueStyle = (mono && hasValue)
        ? monoText.robotoMono.copyWith(color: valueColor)
        : text.bodyMedium?.copyWith(color: valueColor);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Semantics(
        container: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    label,
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 3,
                  child: Text(
                    displayValue,
                    textAlign: TextAlign.end,
                    style: valueStyle,
                  ),
                ),
              ],
            ),
            if (showNote) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                footnote,
                textAlign: TextAlign.end,
                style: text.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- Location card ----

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.message, required this.onGrant});

  final String message;

  /// When null, the card is informational (post-grant state) and hides the
  /// Grant button to avoid an endless re-tap loop.
  final VoidCallback? onGrant;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (onGrant != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label: 'Grant Location permission',
                child: FilledButton(
                  onPressed: onGrant,
                  child: const Text('Grant Location permission'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- Wi-Fi off card ----

class _WifiOffCard extends StatelessWidget {
  const _WifiOffCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.wifi_off,
            size: 20,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wi-Fi is off',
                  style: text.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Turn Wi-Fi on to read live link details. Any values still '
                  'reported by the system are shown below.',
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Loading card ----

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Reading Wi-Fi link state…',
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Error card ----
//
// Shown when the channel returns an error (e.g. no Wi-Fi interface). This is an
// honest in-flow report with the channel detail, not a hard error page — the
// detail may simply be "no interface", so it reads as informational with a
// retry rather than a failure affordance.

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final WifiInfoUnavailable? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? detail = error?.detail;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline,
                size: 20,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No Wi-Fi reading available',
                      style: text.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detail != null && detail.trim().isNotEmpty
                          ? detail
                          : 'The system did not return a Wi-Fi snapshot. '
                              'There may be no active Wi-Fi interface.',
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label: 'Retry reading Wi-Fi information',
                child: FilledButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
