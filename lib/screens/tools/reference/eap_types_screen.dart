// 802.1X / EAP Types — read-only EAP method matrix.
//
// 802.1X is the IEEE port-based network access control framework; EAP (the
// Extensible Authentication Protocol) is the authentication transport that runs
// inside it. The single table below is the EAP *methods* a supplicant and
// authentication server negotiate, with the four security-relevant axes:
// credential type, server-cert requirement, client-cert requirement, mutual
// auth, plus the typical-use note.
//
// Data ported from the Pax reference dataset
// (Deliverables/2026-06-08-reference-batch/wifi-models-data.md, Page 1), with
// the RFC citations re-checked against the IANA EAP Method Types registry
// (2026-07-11). Confidence: High — each method's credential model and
// certificate requirement is defined in its own RFC (5216 EAP-TLS, 5281
// EAP-TTLS, 4851 EAP-FAST, 5931 EAP-PWD, 4186 EAP-SIM, 4187 EAP-AKA,
// 9048 EAP-AKA') and is not contested.
//
// CITATION DRIFT CORRECTED 2026-07-11 — both were pointing at superseded RFCs:
//   TEAP      is RFC 9930, not RFC 7170 (registry value 55).
//   EAP-AKA'  is RFC 9048, not RFC 5448 (registry value 50).
// EAP-FAST remains RFC 4851; TEAP is its standards-track successor, a different
// method. Also note: PEAP (25), EAP-MSCHAPv2 (29) and EAP-FAST (43) have no RFC
// of their own in the registry — they are vendor/individual registrations, so
// any RFC shown against PEAP would be invented.
//
// A persistent §8.20.4 warning callout calls out the single dominant real-world
// EAP misconfiguration: clients that skip server-certificate validation on a
// tunneled method (PEAP/TTLS/FAST) are exposed to evil-twin credential theft.
// This is the security fact the matrix exists to surface, so it is shown as a
// banner, not buried in a footnote.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const dataset always renders. No loading/empty/error path because
// nothing is fetched or parsed at runtime (GL-008 network/subprocess rules do
// not apply — nothing to fabricate, nothing to shell out to).
//
// Pattern: mirrors poe_reference_screen exactly — Scaffold + AppBar
// (toolbarHeight 64) with AppCopyAction, SafeArea(top: false), LayoutBuilder
// isDesktop @720, ConstrainedBox to calculatorMaxWidth, SingleChildScrollView,
// ConceptGraphicBand header, _TableCard (HorizontalScrollTable + IntrinsicWidth +
// fixed-width cells, the overflow-safe idiom), ReferenceRowSemantics per row,
// ToolHelpFooter. The §8.6.2 concept graphic resolves via the convention-based
// ToolAssets resolver under the explicit id `eap-8021x-flow` (asset name differs
// from the catalog id), degrading to nothing when the SVG is not yet bundled.
//
// Glyph note: "802.1X" (uppercase X, never "802.1x"); ASCII hyphen-minus only;
// no em dash; "Wi-Fi" never "WiFi". Apostrophe in AKA' is a straight ASCII '.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One row of the EAP method matrix. Field names + values mirror the Page 1
/// dataset columns exactly: [method, credential, serverCert, clientCert,
/// mutual, use].
@immutable
class EapMethod {
  const EapMethod({
    required this.method,
    required this.credential,
    required this.serverCert,
    required this.clientCert,
    required this.mutual,
    required this.use,
  });

  /// EAP method designation, e.g. `EAP-TLS`.
  final String method;

  /// Credential type the method carries, e.g. `X.509 certs (both sides)`.
  final String credential;

  /// Server X.509 certificate requirement, e.g. `Yes`, `No`, `Optional`.
  final String serverCert;

  /// Client X.509 certificate requirement, e.g. `Yes`, `No`, `Optional`.
  final String clientCert;

  /// Mutual-authentication property, e.g. `Yes`.
  final String mutual;

  /// Typical use / deployment note (full sentence, wraps).
  final String use;
}

class EapTypesScreen extends StatelessWidget {
  const EapTypesScreen({super.key});

  /// Stable catalog id — backs the route, the §8.6.2 concept graphic, and the
  /// help entry. The concept graphic asset is named `eap-8021x-flow` (not the
  /// catalog id), resolved explicitly via [graphicId].
  static const String toolId = 'eap-types';

  /// Explicit concept-graphic id for the 802.1X / EAP flow diagram. Differs from
  /// [toolId]; resolves to assets/tool-graphics/eap-8021x-flow.svg via the
  /// convention-based ToolAssets resolver, degrading to nothing when unbundled.
  static const String graphicId = 'eap-8021x-flow';

  /// The EAP method matrix. Ported verbatim from the Page 1 dataset.
  static const List<EapMethod> methods = [
    EapMethod(
      method: 'EAP-TLS',
      credential: 'X.509 certs (both sides)',
      serverCert: 'Yes',
      clientCert: 'Yes',
      mutual: 'Yes',
      use: 'Strongest, certificate-only. No password to phish or replay. '
          'Requires full PKI and per-device/user cert enrollment. Gold '
          'standard for enterprise and IoT-at-scale where PKI exists.',
    ),
    EapMethod(
      method: 'PEAP (MSCHAPv2)',
      credential: 'Username + password (inside TLS tunnel)',
      serverCert: 'Yes',
      clientCert: 'No',
      mutual: 'Yes',
      use: 'Most common Microsoft-ecosystem deployment. Server cert builds the '
          'tunnel; MSCHAPv2 carries the password inside it. Clients that do '
          'not validate the server cert are exposed to evil-twin credential '
          'theft. Enforce server-cert validation.',
    ),
    EapMethod(
      method: 'EAP-TTLS',
      credential: 'Username + password or legacy inner methods (PAP/CHAP/'
          'MSCHAPv2), inside TLS tunnel',
      serverCert: 'Yes',
      clientCert: 'No (optional)',
      mutual: 'Yes',
      use: 'Like PEAP but vendor-neutral, supporting a wider range of inner '
          'authentication methods including non-EAP legacy protocols (PAP). '
          'Common in mixed/non-Microsoft estates.',
    ),
    EapMethod(
      method: 'EAP-FAST',
      credential: 'Username + password protected by a PAC, inside TLS tunnel',
      serverCert: 'Optional',
      clientCert: 'No (optional)',
      mutual: 'Yes',
      // TEAP is RFC 9930 in the current IANA EAP Method Types registry (value
      // 55). RFC 7170 is superseded — citing it cites a dead document.
      use: 'Cisco-originated alternative to PEAP that avoids mandatory PKI by '
          'using a PAC. PAC provisioning (anonymous in-band Phase 0) is the '
          'weak point. Largely superseded by TEAP (RFC 9930).',
    ),
    EapMethod(
      method: 'EAP-PWD',
      credential: 'Username + shared password (no certificates)',
      serverCert: 'No',
      clientCert: 'No',
      mutual: 'Yes',
      use: 'Password-authenticated key exchange (dragonfly/SAE-family). '
          'Resists offline dictionary attack without any PKI. Niche adoption; '
          'useful where certificates are impractical.',
    ),
    EapMethod(
      method: 'EAP-SIM',
      credential: 'GSM SIM credentials (shared key on SIM)',
      serverCert: 'No',
      clientCert: 'No (SIM is the credential)',
      mutual: 'Yes',
      use: 'Carrier Wi-Fi / hotspot offload using the GSM SIM. Authenticates '
          'against the operator HLR/AuC. Legacy 2G/3G; weaker than AKA.',
    ),
    EapMethod(
      method: "EAP-AKA / AKA'",
      credential: 'USIM credentials (UMTS/LTE)',
      serverCert: 'No',
      clientCert: 'No (USIM is the credential)',
      mutual: 'Yes',
      // EAP-AKA' is RFC 9048 in the IANA registry (value 50). RFC 9048
      // obsoletes RFC 5448.
      use: "Carrier Wi-Fi offload using the USIM. AKA' (RFC 9048) hardens AKA "
          'with SHA-256 key derivation and network-name binding for 3GPP to '
          'non-3GPP interworking (Wi-Fi calling, Passpoint). Current '
          'carrier-offload method.',
    ),
  ];

  /// Footnote — reading guidance for the certificate columns.
  static const String footnote =
      'Every tunneled method (PEAP, TTLS, FAST) authenticates the server by '
      'certificate and the client by an inner credential. That asymmetry is '
      'why client-side server-cert validation is the single most important '
      'deployment setting. EAP-TLS is the only common method requiring a '
      'client certificate; SIM/AKA derive mutual trust from the SIM shared key, '
      'so no server cert is needed.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('802.1X / EAP Types'),
        toolbarHeight: 64,
        // §8.16 — copy the matrix as TSV. Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the EAP matrix as a single-section TSV (method,
  /// credential, server cert, client cert, mutual, use), plus the
  /// server-cert-validation caution as a trailing note. Always non-null
  /// (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('802.1X / EAP Types')
      ..writeln()
      ..writeln(
        <String>[
          'EAP method',
          'Credential',
          'Server cert?',
          'Client cert?',
          'Mutual?',
          'Typical use / notes',
        ].join(tab),
      );
    for (final EapMethod m in methods) {
      buf.writeln(
        <String>[
          m.method,
          m.credential,
          m.serverCert,
          m.clientCert,
          m.mutual,
          m.use,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(
        'Risk: a client that skips server-certificate validation on a '
        'tunneled method (PEAP / TTLS / FAST) can be lured onto an evil-twin '
        'authentication server and surrender its inner credentials. Enforce '
        'server-cert validation (trusted CA + server name) on every supplicant.',
      );
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return LayoutBuilder(
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
                  // §8.6.2 concept graphic, resolved under the explicit
                  // `eap-8021x-flow` id (asset name differs from the catalog
                  // id). Degrades to SizedBox.shrink() when not yet bundled.
                  ConceptGraphicBand(
                    toolId: graphicId,
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic(graphicId))
                    const SizedBox(height: AppSpacing.md),
                  const _ServerCertCaution(),
                  const SizedBox(height: AppSpacing.md),
                  _matrixCard(colors, text, mono),
                  ToolHelpFooter(toolId: toolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _matrixCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'EAP method matrix',
      footnote: footnote,
      header: const Row(
        children: [
          _HeaderCell('Method', width: 132),
          _HeaderCell('Credential', width: 200),
          _HeaderCell('Server cert', width: 96),
          _HeaderCell('Client cert', width: 132),
          _HeaderCell('Mutual', width: 56),
          _HeaderCell('Typical use / notes', width: 320),
        ],
      ),
      rows: methods.map((EapMethod m) {
        return ReferenceRowSemantics(
          label: rowLabel(m.method, <String?>[
            m.credential,
            'server cert ${m.serverCert}',
            'client cert ${m.clientCert}',
            'mutual ${m.mutual}',
            m.use,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 132,
                  child: Text(
                    m.method,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: Text(
                    m.credential,
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    m.serverCert,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 132,
                  child: Text(
                    m.clientCert,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    m.mutual,
                    style: mono.inlineCode.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Text(
                    m.use,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Persistent §8.20.4 warning callout: the dominant real-world EAP
/// misconfiguration. Mirrors the freeradius `_LabCaution` idiom (left-accent
/// border, warning tint fill in light / faint amber wash in dark, warning icon
/// + title + body). Marked as one Semantics container so a screen reader reads
/// the whole caution as a single node.
class _ServerCertCaution extends StatelessWidget {
  const _ServerCertCaution();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color warn = colors.statusWarning;

    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          // Light: §8.20.4 warning tint fill. Dark: a faint amber wash (the
          // dark scheme resolves statusWarningFill to surface2, so derive the
          // wash from the warning hue directly for the on-dark callout).
          color: colors.isLight
              ? colors.statusWarningFill
              : warn.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border(
            top: BorderSide(color: warn),
            right: BorderSide(color: warn),
            bottom: BorderSide(color: warn),
            left: BorderSide(color: warn, width: 6),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.rowPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, size: 24, color: warn),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'ENFORCE SERVER-CERT VALIDATION',
                    style: (text.labelMedium ?? const TextStyle()).copyWith(
                      color: warn,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'On the tunneled methods (PEAP, TTLS, FAST) the client '
                    'authenticates the server by certificate and sends its '
                    'inner credential inside that tunnel. A supplicant that '
                    'skips server-cert validation can be lured onto an '
                    'evil-twin authentication server and surrender those '
                    'credentials. Pin a trusted CA and the expected server '
                    'name on every device. This is the dominant real-world '
                    'EAP misconfiguration.',
                    style: (text.bodyMedium ?? const TextStyle()).copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card surface wrapping a wide table: title (full-width, wraps) over a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align), with an optional full-width footnote beneath. Matches the
/// poe_reference_screen / wifi_channels_screen overflow-safe idiom.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.header,
    required this.rows,
    this.footnote,
  });

  final String title;
  final Widget header;
  final List<Widget> rows;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
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
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // The grid sizes to its intrinsic content width and scrolls
          // horizontally when that exceeds the card. Children of a horizontal
          // SingleChildScrollView get unbounded width, so IntrinsicWidth lets
          // each Row shrink-wrap its fixed-width cells while sharing one common
          // width — columns align, nothing overflows. Title + footnote stay
          // full-width and wrap.
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  Divider(color: colors.border, height: AppSpacing.sm),
                  ...rows,
                ],
              ),
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              footnote!,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One column-header label, caption-styled to align with the data cells.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: colors.textTertiary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
