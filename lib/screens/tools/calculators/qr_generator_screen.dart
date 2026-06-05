// QR Code Generator — Batch 4b.
//
// Text/URL input → a rendered QR code. Uses `pretty_qr_code` (MIT; depends on
// `qr` BSD-3 — both pure-Dart, both MIT/BSD per the License gate). Chosen over
// `qr_flutter` (4.1.0, ^2022) because pretty_qr_code is the actively maintained
// option (3.6.0) and exposes a clean per-module / per-background color API,
// which is exactly what GL-003 §8.19 requires us to control.
//
// GL-003 §8.19 — QR CODE RENDERING (HARD RULE, a deliberate exception to the
// App Mode dark default):
//   * DARK modules on a WHITE (--color-neutral-0 / #FFFFFF) background, ALWAYS.
//     Never the inverted/on-brand lime-on-charcoal QR — many scanners fail on
//     inverted codes, and a QR is a machine target, not a brand surface.
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
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../labeled_field.dart';

class QrGeneratorScreen extends StatefulWidget {
  const QrGeneratorScreen({super.key});

  @override
  State<QrGeneratorScreen> createState() => _QrGeneratorScreenState();
}

class _QrGeneratorScreenState extends State<QrGeneratorScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  // RepaintBoundary key so the rendered white tile can be captured to a PNG for
  // the share path (so the shared image is the SAME dark-on-white QR the user
  // sees, quiet zone and all — §8.19).
  final GlobalKey _qrBoundaryKey = GlobalKey();

  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _inputCtrl.removeListener(_onInputChanged);
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onInputChanged() => setState(() {});

  String get _data => _inputCtrl.text.trim();
  bool get _hasData => _data.isNotEmpty;

  /// §8.16 copy payload — the encoded text itself (so a user can copy what the
  /// QR contains). Null (→ disabled) when the field is empty.
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
                      _inputCard(text),
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

  Widget _inputCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
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

  /// The §8.19 white QR tile: dark modules on a WHITE tile with the QR widget's
  /// own ≥4-module quiet zone preserved (padding INSIDE the white area so the
  /// quiet zone is the same white, never cropped). The white tile is a 12px-
  /// radius card centered in the column, with 24px of dark-card padding around
  /// it (the RepaintBoundary wraps only the white tile so the captured PNG is
  /// white-on-white-quiet-zone, not the dark canvas).
  Widget _qrTile() {
    final AppColorScheme colors = context.colors;
    return Center(
      child: ConstrainedBox(
        // Cap the tile so it reads as a deliberate inset, not full-bleed.
        constraints: const BoxConstraints(maxWidth: 320),
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
                  decoration: const PrettyQrDecoration(
                    // §8.19: DARK modules (charcoal --color-secondary) on a
                    // WHITE background. NEVER inverted (lime-on-dark) —
                    // scannability beats brand here. roundFactor: 0 keeps the
                    // modules crisp squares (best scan reliability).
                    shape: PrettyQrSmoothSymbol(
                      color: Color(0xFF30302F), // §8.19 QR modules: charcoal, never inverted
                      roundFactor: 0,
                    ),
                    // Explicit white background so the modules always sit on
                    // --color-neutral-0, independent of the enclosing tile.
                    background: Color(0xFFFFFFFF), // §8.19 QR background: white, never inverted
                    // §8.19: mandatory ≥4-module quiet zone of the same white,
                    // never cropped to the module edge.
                    quietZone: PrettyQrQuietZone.modules(4),
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
              'Enter text or a URL above to generate a QR code.',
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
