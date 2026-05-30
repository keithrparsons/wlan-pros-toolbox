// MAC OUI / Vendor Lookup tool — turn a MAC address into its registered vendor,
// fully offline against a bundled IEEE registry table.
//
// States (SOP-007 §5):
//  - idle      → form only; the registry asset loads in the background.
//  - loading   → the one-time registry parse (only on first open, ~50k rows).
//  - success   → matched vendor + OUI + registry block.
//  - empty     → valid MAC but no registry match ("not in registry"), OR a
//                locally-administered / multicast MAC (honest: no vendor to
//                show, with the reason). Neither is an error.
//  - error     → asset failed to load, or malformed MAC input.
//  - disabled  → "Look up" disabled until a MAC is entered.
//
// NOTE ON PLATFORM: this tool does NO network I/O — it reads a bundled asset and
// does integer math — so it runs on every platform INCLUDING web. There is no
// NetworkUnavailableView path here; that surface is for socket/HTTP tools only.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/mac_oui_service.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

class MacOuiScreen extends StatefulWidget {
  const MacOuiScreen({super.key, this.service});

  /// Inject a pre-built service in tests so no asset load is required. In app
  /// code this is null and the registry asset is loaded on first build.
  final MacOuiService? service;

  @override
  State<MacOuiScreen> createState() => _MacOuiScreenState();
}

class _MacOuiScreenState extends State<MacOuiScreen> {
  final TextEditingController _macCtrl = TextEditingController();
  final FocusNode _macFocus = FocusNode();

  MacOuiService? _service;
  bool _loadingTable = false;
  String? _loadError;
  bool _canRun = false;
  OuiResult? _result;

  @override
  void initState() {
    super.initState();
    _macCtrl.addListener(_recomputeCanRun);
    if (widget.service != null) {
      _service = widget.service;
    } else {
      _loadTable();
    }
  }

  Future<void> _loadTable() async {
    setState(() => _loadingTable = true);
    try {
      final String raw =
          await rootBundle.loadString('assets/oui/oui_table.tsv');
      final Map<String, String> table = MacOuiService.parseTable(raw);
      if (!mounted) return;
      setState(() {
        _service = MacOuiService.fromTable(table);
        _loadingTable = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingTable = false;
        _loadError = 'Could not load the vendor database: $e';
      });
    }
  }

  void _recomputeCanRun() {
    final bool can = _macCtrl.text.trim().isNotEmpty;
    if (can != _canRun) setState(() => _canRun = can);
  }

  @override
  void dispose() {
    _macCtrl.dispose();
    _macFocus.dispose();
    super.dispose();
  }

  void _run() {
    final MacOuiService? svc = _service;
    if (svc == null || !_canRun) return;
    _macFocus.unfocus();
    final OuiResult result = svc.lookup(_macCtrl.text);
    setState(() => _result = result);

    // WCAG 4.1.3 — announce the outcome to assistive tech.
    final String announcement;
    if (!result.isValid) {
      announcement = 'Invalid MAC address';
    } else if (result.isLocal) {
      announcement = 'Locally administered address, no vendor';
    } else if (result.isMulticast) {
      announcement = 'Multicast address, no vendor';
    } else if (result.matched) {
      announcement = 'Vendor: ${result.vendor}';
    } else {
      announcement = 'OUI not in registry';
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      announcement,
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MAC Vendor Lookup'), toolbarHeight: 64),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
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
                  ConceptGraphicBand(
                    toolId: 'mac-oui-lookup',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('mac-oui-lookup'))
                    const SizedBox(height: AppSpacing.md),
                  _formCard(context),
                  if (_loadError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _MessageCard(
                      icon: Icons.error_outline,
                      title: 'Vendor database unavailable',
                      body: _loadError!,
                    ),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _resultCard(context, _result!),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _formCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool ready = _service != null && _loadError == null;
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
          LabeledField(
            label: 'MAC address',
            field: TextField(
              controller: _macCtrl,
              focusNode: _macFocus,
              enabled: _loadError == null,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _run(),
              inputFormatters: <TextInputFormatter>[
                // Only hex + the separators a MAC can use. The service still
                // validates length and content.
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F:\-.\s]')),
              ],
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: 'B8:27:EB:01:23:45'),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Colons, hyphens, Cisco dots, or no separators all work.',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: (!ready || !_canRun) ? null : _run,
            child: _loadingTable
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: Semantics(
                      label: 'Loading vendor database…',
                      liveRegion: true,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.secondary,
                      ),
                    ),
                  )
                : const Text('Look up'),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(BuildContext context, OuiResult r) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    // Invalid input is an error card, not a result card.
    if (!r.isValid) {
      return _MessageCard(
        icon: Icons.edit_outlined,
        title: 'Check your input',
        body: r.errorMessage ?? 'That is not a valid MAC address.',
      );
    }

    // Locally-administered / multicast — honest "no vendor" with the reason.
    if (r.isLocal || r.isMulticast) {
      final String reason = r.isLocal
          ? 'This is a locally-administered (randomized) address. The U/L bit '
              'is set, so it was assigned by software, not from an IEEE vendor '
              'block — modern phones randomize their Wi-Fi MAC this way. There '
              'is no real vendor to look up.'
          : 'This is a multicast / group address (the I/G bit is set), not a '
              'single device NIC, so it has no vendor.';
      return _NoVendorCard(
        mac: r.normalizedMac!,
        oui: r.oui!,
        title: r.isLocal ? 'Locally administered' : 'Multicast address',
        reason: reason,
        mono: mono,
      );
    }

    final bool matched = r.matched;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: matched ? AppColors.borderStrong : AppColors.border,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // §8.4 status colors are v1.1-deferred — neutral icon + text.
              Icon(
                matched ? Icons.verified_outlined : Icons.help_outline,
                size: 24,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  matched ? r.vendor! : 'Not in registry',
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (!matched) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'This OUI is not in the bundled IEEE registry. It may be an '
              'unassigned block, or the table may need a refresh.',
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _row(context, 'MAC', r.normalizedMac!, mono),
          _row(context, 'OUI', r.oui!, mono),
          if (matched && r.registry != null)
            _row(context, 'Registry', r.registry!.label, mono),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value,
    AppMonoText mono,
  ) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: SelectableText(
              value,
              style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "no vendor, here's why" card for locally-administered and multicast MACs.
class _NoVendorCard extends StatelessWidget {
  const _NoVendorCard({
    required this.mac,
    required this.oui,
    required this.title,
    required this.reason,
    required this.mono,
  });

  final String mac;
  final String oui;
  final String title;
  final String reason;
  final AppMonoText mono;

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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.shuffle, size: 24, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            reason,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    'MAC',
                    style: text.labelMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: SelectableText(
                    mac,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textPrimary,
                    ),
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

/// Shared neutral message card (error / unavailable), mirroring the pattern used
/// by Wake-on-LAN. Color-free per §8.4 — meaning carried by title + body text.
class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

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
          Icon(icon, size: 20, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.labelMedium
                      ?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
