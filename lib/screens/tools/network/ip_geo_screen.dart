// IP Geolocation tool — locate an IP (or your own public IP) via ipinfo.io
// with a geojs.io fallback (both keyless, HTTPS — see IpGeoService).
//
// States (SOP-007 §5):
//  - idle     → form only; an empty query means "my public IP".
//  - loading  → query in flight; button shows progress, input disabled.
//  - success  → location, coordinates, timezone, ISP/org, ASN.
//  - error    → bad IP / timeout / rate-limit / transport, precise message.
//  - disabled → never fully disabled (blank = my IP), but progress locks input.
//  - web      → NetworkUnavailableView (native-only; CORS unverified).
//
// MAP: a full interactive map is OUT of scope this session. Coordinates render
// as selectable mono data with a copyable "lat,long" pair and a copyable
// OpenStreetMap URL the user can open. Interactive map = documented future item.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/ip_geo_service.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/network_target.dart';
import '../../../services/network/pi_backend.dart';
import '../../../services/network/pi_backend_client.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'error_card.dart';
import 'network_unavailable_view.dart';
import 'value_row.dart';

class IpGeoScreen extends StatefulWidget {
  const IpGeoScreen({super.key, this.service});

  final IpGeoService? service;

  @override
  State<IpGeoScreen> createState() => _IpGeoScreenState();
}

class _IpGeoScreenState extends State<IpGeoScreen> {
  late final IpGeoService _service;
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  bool _loading = false;
  IpGeoResult? _result;

  /// True when this build is served FROM a WLAN Pi (Pi-hosted web): the lookup
  /// runs ON the Pi via `/toolboxapi/ipgeo` (keyless ipinfo / geojs proxy),
  /// returning the SAME [IpGeoResult] the native path builds, so the existing
  /// location / coordinates cards render it unchanged. Only when no test service
  /// is injected, on web, with a Pi backend that serves this tool — otherwise
  /// the native path is byte-for-byte unchanged.
  late final bool _piBacked;

  @override
  void initState() {
    super.initState();
    _piBacked =
        kIsWeb && PiBackend.canServe('ip-geo') && widget.service == null;
    // On the Pi path the native geolocation service is never constructed — the
    // lookup runs server-side on the Pi through PiBackendClient.
    if (!_piBacked) {
      _service = widget.service ?? IpGeoService();
    }
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_loading) return;
    _queryFocus.unfocus();
    setState(() => _loading = true);
    final IpGeoResult result = _piBacked
        ? await _runPi()
        : await _service.lookup(rawQuery: _queryCtrl.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });

    SemanticsService.sendAnnouncement(
      View.of(context),
      result.isError
          ? 'Geolocation lookup failed'
          : 'Location retrieved for ${result.locationLine ?? result.ip ?? 'the address'}',
      TextDirection.ltr,
    );
  }

  /// Pi-hosted lookup: the geolocation query runs ON the WLAN Pi hosting this
  /// page and comes back as the SAME [IpGeoResult] the native path builds, so
  /// [_resultsSection] renders the location and coordinate cards identically.
  /// A pasted URL is reduced to its host with the shared
  /// [NetworkTarget.hostFromUserInput]; a blank query stays blank, which the Pi
  /// resolves to its OWN public IP (not this browser's — see the query note). A
  /// transport failure — including a [PiBackendException] from an unreachable
  /// Pi — is folded into the model's failure state and surfaced by the existing
  /// error card. Never throws.
  Future<IpGeoResult> _runPi() async {
    final String query = NetworkTarget.hostFromUserInput(_queryCtrl.text);
    try {
      return await PiBackendClient().ipGeo(query: query);
    } on PiBackendException catch (e) {
      return IpGeoResult.failure(query: query, message: e.message);
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('$label copied')));
    // SnackBars are not reliably announced by screen readers; send an explicit
    // polite announcement so VoiceOver/TalkBack confirm the copy. (Vera MEDIUM-2.)
    SemanticsService.sendAnnouncement(
      View.of(context),
      '$label copied',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IP Geolocation'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a successful
        // lookup exists; copies the location/coordinates as a labeled text
        // block. Copy leads; this screen has no help icon.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the geolocation result as a labeled plain-text block.
  ///
  /// Returns null (→ disabled affordance) while loading, before any lookup, or
  /// when the last lookup errored — an error has no result to keep. Absent
  /// fields are omitted (GL-005 honest blanks), matching the on-screen
  /// `ValueRow` treatment that hides null rows.
  String? _buildCopyText() {
    final IpGeoResult? r = _result;
    if (_loading || r == null || r.isError) return null;

    final StringBuffer buf = StringBuffer()..writeln('IP Geolocation');
    void line(String label, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        buf.writeln('$label: ${value.trim()}');
      }
    }

    line('IP', r.ip);
    line('IP version', r.ipVersion);
    line('Location', r.locationLine);
    line('Postal code', r.postal);
    line('Timezone', r.timezone);
    line('UTC offset', r.utcOffset);
    line('ISP', r.isp);
    line('Organization', r.org);
    line('ASN', r.asn);
    if (r.hasCoordinates) {
      line('Latitude', r.latitude?.toStringAsFixed(6));
      line('Longitude', r.longitude?.toStringAsFixed(6));
      line('Map link', r.mapsUrl);
    }

    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.ipGeoSupported) {
      return NetworkUnavailableView(
        toolName: 'IP Geolocation',
        reason:
            NetworkSupport.unavailableReason ?? NetworkUnavailableReason.web,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
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
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConceptGraphicBand(toolId: 'ip-geo', isDesktop: isDesktop),
                  if (ToolAssets.hasGraphic('ip-geo'))
                    const SizedBox(height: AppSpacing.md),
                  _queryCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _resultsSection(context),
                  ToolHelpFooter(toolId: 'ip-geo'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _queryCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
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
          LabeledField(
            label: 'IP address',
            field: TextField(
              controller: _queryCtrl,
              focusNode: _queryFocus,
              enabled: !_loading,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              cursorColor: colors.textAccent,
              decoration: InputDecoration(
                hintText: _piBacked
                    ? "Leave blank for the Pi's public IP"
                    : 'Leave blank for my public IP',
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Data from the ipinfo.io API, with geojs.io as a fallback. '
            'No account or key required. IP geolocation is approximate '
            '(city-level) and can be wrong for some ISPs.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          if (_piBacked) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'The lookup runs on the WLAN Pi hosting this page. A blank query '
              "returns the Pi's public IP, not this browser's.",
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _loading ? null : _run,
            child: _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: Semantics(
                      label: 'Locating…',
                      liveRegion: true,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onPrimary,
                      ),
                    ),
                  )
                : const Text('Locate'),
          ),
        ],
      ),
    );
  }

  Widget _resultsSection(BuildContext context) {
    final IpGeoResult? r = _result;
    if (r == null) return const SizedBox.shrink();
    if (r.isError) {
      return LookupErrorCard(
        errorKind: r.errorKind,
        message: r.errorMessage!,
        onRetry: _run,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailsCard(context, r),
        if (r.hasCoordinates) ...[
          const SizedBox(height: AppSpacing.sm),
          _coordinatesCard(context, r),
        ],
      ],
    );
  }

  Widget _detailsCard(BuildContext context, IpGeoResult r) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Location',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ValueRow(label: 'IP', value: r.ip, identifier: true, emphasize: true),
          ValueRow(label: 'IP version', value: r.ipVersion),
          ValueRow(label: 'Location', value: r.locationLine),
          ValueRow(label: 'Postal code', value: r.postal, mono: true),
          ValueRow(label: 'Timezone', value: r.timezone),
          ValueRow(label: 'UTC offset', value: r.utcOffset, mono: true),
          ValueRow(label: 'ISP', value: r.isp),
          ValueRow(label: 'Organization', value: r.org),
          ValueRow(label: 'ASN', value: r.asn, identifier: true),
        ],
      ),
    );
  }

  Widget _coordinatesCard(BuildContext context, IpGeoResult r) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final String coords = r.coordinatePair!;
    final String? url = r.mapsUrl;

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
            'Coordinates',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ValueRow(
            label: 'Latitude',
            value: r.latitude?.toStringAsFixed(6),
            mono: true,
          ),
          ValueRow(
            label: 'Longitude',
            value: r.longitude?.toStringAsFixed(6),
            mono: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Map link',
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 4),
          if (url != null)
            SelectableText(
              url,
              style: mono.inlineCode.copyWith(
                color: colors.textPrimary,
                fontSize: AppTextSize.caption,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copy(coords, 'Coordinates'),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy lat,long'),
                ),
              ),
              if (url != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copy(url, 'Map link'),
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Copy map link'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'An interactive in-app map is a planned future addition.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
