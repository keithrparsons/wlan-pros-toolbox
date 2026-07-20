// QR Code Generator — Batch 4b, Wi-Fi mode added 2026-06-12.
//
// Two content modes, picked by a §8.14.1 AppToggle segmented control:
//   * URL / Text — the original behavior: any string → a QR code.
//   * Wi-Fi      — the "scan to join" headline feature: SSID + security +
//                  password + hidden toggle → the standard WIFI: payload
//                  (see lib/data/wifi_qr.dart), which a phone camera reads as a
//                  "join this network" offer.
//
// Uses `pretty_qr_code` (MIT; depends on `qr` BSD-3 — both pure-Dart, both
// MIT/BSD per the License gate).
//
// GL-003 §8.19 — QR CODE RENDERING (HARD RULE, a deliberate exception to the
// App Mode dark default):
//   * DARK modules on a WHITE (--color-neutral-0 / #FFFFFF) background, ALWAYS.
//     Never the inverted/on-brand lime-on-charcoal QR — many scanners fail on
//     inverted codes, and a QR is a machine target, not a brand surface. This
//     holds across every module SHAPE and SIZE option below — shape/size never
//     touch the color, which is locked dark-on-white.
//   * A mandatory ≥4-module quiet zone of the SAME white on all four sides,
//     never cropped — a QR with no quiet zone fails to scan.
//   * The white QR tile is a card (--app-radius-card / 12px) centered in the
//     content-max-width column, with --space-md (24px) padding between the dark
//     enclosing card and the white tile, which reinforces the quiet zone.
//   * Share via the existing share_plus path (§8.19 / §8.16).
//
// Offline / no network: QR generation is pure local computation. The only
// platform touch is the OS share sheet (share_plus), reused from the PDF cards.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../data/qr_share.dart';
import '../../../data/wifi_qr.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/tool_help_footer.dart';
import '../labeled_field.dart';

/// Which kind of content the tool is encoding.
enum QrContentMode { urlText, wifi }

/// The rendered module shape (§8.19 — shape never alters the dark-on-white
/// color contract; it only changes module geometry).
enum QrModuleShape { square, rounded, dots }

/// Preset export/render sizes. The value is the logical edge of the white tile;
/// the share PNG renders at 3× this for crisp scan resolution.
enum QrSize {
  small(220, 'Small'),
  medium(280, 'Medium'),
  large(340, 'Large');

  const QrSize(this.edge, this.label);

  /// Logical edge (px) of the white QR tile for this preset.
  final double edge;

  /// Display label for the size selector.
  final String label;
}

class QrGeneratorScreen extends StatefulWidget {
  const QrGeneratorScreen({super.key});

  @override
  State<QrGeneratorScreen> createState() => _QrGeneratorScreenState();
}

class _QrGeneratorScreenState extends State<QrGeneratorScreen> {
  // URL / Text mode.
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  // Wi-Fi mode.
  final TextEditingController _ssidCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  QrContentMode _mode = QrContentMode.urlText;
  WifiAuthType _auth = WifiAuthType.wpa;
  bool _hidden = false;
  bool _passwordObscured = true;

  QrModuleShape _shape = QrModuleShape.square;
  QrSize _size = QrSize.medium;

  // RepaintBoundary key so the rendered white tile can be captured to a PNG for
  // the share path (so the shared image is the SAME dark-on-white QR the user
  // sees, quiet zone and all — §8.19).
  final GlobalKey _qrBoundaryKey = GlobalKey();

  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(_onInputChanged);
    _ssidCtrl.addListener(_onInputChanged);
    _passwordCtrl.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _inputCtrl.removeListener(_onInputChanged);
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _ssidCtrl.removeListener(_onInputChanged);
    _ssidCtrl.dispose();
    _passwordCtrl.removeListener(_onInputChanged);
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onInputChanged() => setState(() {});

  // ─── Encoded payload ────────────────────────────────────────────────────────

  /// Whether the Wi-Fi field set has enough to encode (SSID is required; an open
  /// network needs no password).
  bool get _wifiReady => _ssidCtrl.text.trim().isNotEmpty;

  /// The string actually fed to the QR for the active mode. Empty when the
  /// current mode has nothing to encode yet.
  String get _data {
    switch (_mode) {
      case QrContentMode.urlText:
        return _inputCtrl.text.trim();
      case QrContentMode.wifi:
        if (!_wifiReady) return '';
        return buildWifiQrPayload(
          ssid: _ssidCtrl.text,
          auth: _auth,
          password: _passwordCtrl.text,
          hidden: _hidden,
        );
    }
  }

  bool get _hasData => _data.isNotEmpty;

  /// §8.16 copy payload — the encoded string itself (the URL/text, or the WIFI:
  /// payload). Null (→ disabled) when there is nothing encoded.
  String? _buildCopyText() => _hasData ? _data : null;

  // ─── Share ────────────────────────────────────────────────────────────────

  Future<void> _share() async {
    if (!_hasData || _sharing) return;
    setState(() => _sharing = true);
    try {
      final Uint8List? png = await _capturePng();
      if (png == null) {
        _showSnack('Could not render the QR image to share.');
        return;
      }
      await shareQrPng(png: png, label: _data);
    } catch (_) {
      if (mounted) _showSnack('Sharing is unavailable on this platform.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Rasterize the white QR tile to a PNG via its RepaintBoundary. Returns null
  /// if the boundary is not yet laid out.
  Future<Uint8List?> _capturePng() async {
    final RenderObject? obj =
        _qrBoundaryKey.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) return null;
    // 3× pixel ratio so the shared PNG is crisp at scan resolution.
    final ui.Image image = await obj.toImage(pixelRatio: 3.0);
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Code Generator'),
        toolbarHeight: 64,
        // §8.16 / §8.19 — copy the encoded text.
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
                  maxWidth: AppSpacing.contentMaxWidth,
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
                    children: <Widget>[
                      _modeSelector(),
                      const SizedBox(height: AppSpacing.md),
                      _inputCard(text),
                      const SizedBox(height: AppSpacing.md),
                      _appearanceCard(text),
                      const SizedBox(height: AppSpacing.md),
                      if (_hasData) ...<Widget>[
                        _qrTile(),
                        const SizedBox(height: AppSpacing.md),
                        _shareButton(),
                      ] else
                        _emptyState(text),
                      ToolHelpFooter(toolId: 'qr-generator'),
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

  /// Content-mode picker — URL/Text vs Wi-Fi (§8.14.1 AppToggle).
  Widget _modeSelector() {
    return AppToggle<QrContentMode>(
      value: _mode,
      label: 'Content',
      semanticLabel: 'Content type to encode',
      expand: true,
      items: const <AppToggleItem<QrContentMode>>[
        (QrContentMode.urlText, 'URL / Text'),
        (QrContentMode.wifi, 'Wi-Fi'),
      ],
      onChanged: (QrContentMode m) {
        if (m == _mode) return;
        setState(() => _mode = m);
      },
    );
  }

  /// The input card for the active mode.
  Widget _inputCard(TextTheme text) {
    switch (_mode) {
      case QrContentMode.urlText:
        return _urlTextInputCard(text);
      case QrContentMode.wifi:
        return _wifiInputCard(text);
    }
  }

  Widget _cardShell({required Widget child}) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }

  Widget _urlTextInputCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return _cardShell(
      child: LabeledField(
        label: 'Text or URL',
        semanticLabel: 'Text or URL to encode',
        field: TextField(
          controller: _inputCtrl,
          focusNode: _inputFocus,
          keyboardType: TextInputType.url,
          minLines: 1,
          maxLines: 4,
          autocorrect: false,
          enableSuggestions: false,
          cursorColor: colors.textAccent,
          style: text.bodyLarge,
          decoration: const InputDecoration(
            hintText: 'https://wlanpros.com',
          ),
        ),
      ),
    );
  }

  /// Wi-Fi "scan to join" inputs: SSID, security, password (hidden when the
  /// network is open), and a hidden-network toggle.
  Widget _wifiInputCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    final bool open = _auth == WifiAuthType.none;

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabeledField(
            label: 'Network name (SSID)',
            semanticLabel: 'Wi-Fi network name',
            field: TextField(
              controller: _ssidCtrl,
              keyboardType: TextInputType.text,
              minLines: 1,
              maxLines: 1,
              autocorrect: false,
              enableSuggestions: false,
              cursorColor: colors.textAccent,
              style: text.bodyLarge,
              decoration: const InputDecoration(
                hintText: 'WLAN-Pros-Guest',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LabeledField(
            label: 'Security',
            semanticLabel: 'Wi-Fi security type',
            field: AppSelect<WifiAuthType>(
              value: _auth,
              semanticLabel: 'Wi-Fi security type',
              items: const <AppSelectItem<WifiAuthType>>[
                (WifiAuthType.wpa, 'WPA / WPA2 / WPA3'),
                (WifiAuthType.wep, 'WEP'),
                (WifiAuthType.none, 'None (open)'),
              ],
              onChanged: (WifiAuthType a) {
                setState(() => _auth = a);
              },
            ),
          ),
          // Password hidden entirely for an open network (no P: field).
          if (!open) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            LabeledField(
              label: 'Password',
              semanticLabel: 'Wi-Fi password',
              field: TextField(
                controller: _passwordCtrl,
                obscureText: _passwordObscured,
                keyboardType: TextInputType.visiblePassword,
                minLines: 1,
                maxLines: 1,
                autocorrect: false,
                enableSuggestions: false,
                cursorColor: colors.textAccent,
                style: text.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Network password',
                  // Explicit accessible name (WCAG 2.2 AA SC 4.1.2, GL-003
                  // §8.16): `tooltip:` maps to AXHelp, not AXTitle, so this
                  // icon-only toggle would read as `label="" button=true`. The
                  // label flips with state like the tooltip; `enabled:` is true
                  // because the toggle is always available.
                  suffixIcon: Semantics(
                    button: true,
                    enabled: true,
                    label: _passwordObscured ? 'Show password' : 'Hide password',
                    child: IconButton(
                      onPressed: () => setState(
                        () => _passwordObscured = !_passwordObscured,
                      ),
                      icon: Icon(
                        _passwordObscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      tooltip: _passwordObscured
                          ? 'Show password'
                          : 'Hide password',
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _hiddenToggleRow(text),
        ],
      ),
    );
  }

  /// The "Hidden network" on/off row. A Material [Switch] inherits the lime
  /// active track from the §8.10 ColorScheme mapping; the whole row is a single
  /// labeled, keyboard-operable control.
  Widget _hiddenToggleRow(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return MergeSemantics(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Hidden network',
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Turn on if this network does not broadcast its name.',
                  style: text.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Switch(
            value: _hidden,
            onChanged: (bool v) => setState(() => _hidden = v),
          ),
        ],
      ),
    );
  }

  /// Module-shape and size selectors. These never touch the dark-on-white color
  /// contract (§8.19) — shape changes module geometry, size changes render
  /// resolution.
  Widget _appearanceCard(TextTheme text) {
    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppToggle<QrModuleShape>(
            value: _shape,
            label: 'Module shape',
            semanticLabel: 'QR module shape',
            expand: true,
            items: const <AppToggleItem<QrModuleShape>>[
              (QrModuleShape.square, 'Square'),
              (QrModuleShape.rounded, 'Rounded'),
              (QrModuleShape.dots, 'Dots'),
            ],
            onChanged: (QrModuleShape s) => setState(() => _shape = s),
          ),
          const SizedBox(height: AppSpacing.md),
          AppToggle<QrSize>(
            value: _size,
            label: 'Size',
            semanticLabel: 'QR code size',
            expand: true,
            items: <AppToggleItem<QrSize>>[
              for (final QrSize s in QrSize.values) (s, s.label),
            ],
            onChanged: (QrSize s) => setState(() => _size = s),
          ),
        ],
      ),
    );
  }

  /// Resolve the active module shape to a `pretty_qr_code` symbol. Every shape
  /// keeps the dark charcoal module color — color is NEVER theme-flipped or
  /// shape-dependent (§8.19). `unifiedFinderPattern: true` on dots keeps the
  /// three finder squares solid so the code stays reliably scannable.
  PrettyQrShape _symbolFor(QrModuleShape shape) {
    switch (shape) {
      case QrModuleShape.square:
        return const PrettyQrSmoothSymbol(
          color: Color(0xFF30302F), // §8.19 QR modules: charcoal, never inverted
          roundFactor: 0,
        );
      case QrModuleShape.rounded:
        return const PrettyQrSmoothSymbol(
          color: Color(0xFF30302F),
          roundFactor: 1,
        );
      case QrModuleShape.dots:
        return const PrettyQrDotsSymbol(
          color: Color(0xFF30302F),
        );
    }
  }

  /// The §8.19 white QR tile: dark modules on a WHITE tile with the QR widget's
  /// own ≥4-module quiet zone preserved (padding INSIDE the white area so the
  /// quiet zone is the same white, never cropped). The white tile is a 12px-
  /// radius card centered in the column, sized by the active [_size] preset,
  /// with 24px of dark-card padding around it (the RepaintBoundary wraps only
  /// the white tile so the captured PNG is white-on-white-quiet-zone, not the
  /// dark canvas).
  Widget _qrTile() {
    final AppColorScheme colors = context.colors;
    return Center(
      child: ConstrainedBox(
        // The size preset caps the tile; it still shrinks on a narrow phone via
        // the parent column width, so it is never wider than the surface.
        constraints: BoxConstraints(maxWidth: _size.edge),
        child: Container(
          // §8.19: --space-md (24px) padding between the dark enclosing card and
          // the white tile — reinforces the quiet zone so the QR's light border
          // is never visually clipped by the dark surface.
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: colors.border, width: 1),
          ),
          child: RepaintBoundary(
            key: _qrBoundaryKey,
            child: Container(
              // §8.19: white --color-neutral-0 tile, card radius. The dark
              // modules need this light background to scan.
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF), // §8.19 QR tile: white, never theme-flipped
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              // Inner white padding = the same-white margin around the QR. This
              // sits OUTSIDE the QR widget's own quiet zone, so the white quiet
              // zone is doubly guaranteed and never cropped to the module edge.
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: AspectRatio(
                aspectRatio: 1,
                child: PrettyQrView.data(
                  data: _data,
                  // M-level: good scan robustness without bloating the modules.
                  errorCorrectLevel: QrErrorCorrectLevel.M,
                  decoration: PrettyQrDecoration(
                    // §8.19: DARK modules (charcoal --color-secondary) on a
                    // WHITE background. NEVER inverted (lime-on-dark) —
                    // scannability beats brand here. The shape varies (square /
                    // rounded / dots) but the color is locked dark-on-white.
                    shape: _symbolFor(_shape),
                    // Explicit white background so the modules always sit on
                    // --color-neutral-0, independent of the enclosing tile.
                    background: const Color(0xFFFFFFFF), // §8.19 QR background: white, never inverted
                    // §8.19: mandatory ≥4-module quiet zone of the same white,
                    // never cropped to the module edge.
                    quietZone: const PrettyQrQuietZone.modules(4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _shareButton() {
    return Center(
      child: FilledButton.icon(
        onPressed: _sharing ? null : _share,
        icon: _sharing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.ios_share),
        label: Text(_sharing ? 'Preparing…' : 'Share / Save'),
      ),
    );
  }

  Widget _emptyState(TextTheme text) {
    final AppColorScheme colors = context.colors;
    final String message = _mode == QrContentMode.wifi
        ? 'Enter a network name (SSID) above to generate a Wi-Fi join code.'
        : 'Enter text or a URL above to generate a QR code.';
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.qr_code_2,
            size: 24,
            color: colors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: text.bodyMedium?.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
