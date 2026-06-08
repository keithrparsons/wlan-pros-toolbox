// HTTP Methods & Headers — a read-only reference for the HTTP request methods
// (with their safe / idempotent properties) and the common request and response
// headers a network / Wi-Fi pro meets checking a captive portal, a web service,
// a proxy, or an API.
//
// DATA SOURCE: the IANA HTTP Method Registry and HTTP Field Name Registry
// (iana.org/assignments/http-methods, .../http-fields); RFC 9110 (HTTP
// Semantics) for method semantics and the safe/idempotent definitions; PATCH
// per RFC 5789. "Safe" = read-only, no intended state change. "Idempotent" =
// repeating the request has the same effect as making it once. Values are
// reproduced verbatim from the verified dataset
// Deliverables/2026-06-08-reference-batch/protocols-data.md, Page 3.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. No loading/empty/error path.
//
// Pattern: mirrors poe_reference_screen — Scaffold + AppBar (toolbarHeight 64,
// AppCopyAction), SafeArea(top: false), LayoutBuilder isDesktop @720,
// ConstrainedBox to calculatorMaxWidth, SingleChildScrollView,
// ConceptGraphicBand, three wide tables (methods, request headers, response
// headers), each a HorizontalScrollTable + IntrinsicWidth grid of fixed-width
// cells, ToolHelpFooter. Each row is wrapped in ReferenceRowSemantics.
//
// Glyph note: ASCII only; no em dash. Method names + header names render in the
// mono family (identifiers).

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One HTTP method: name, whether it is safe, whether it is idempotent, and a
/// plain-English purpose. `safe` / `idempotent` are booleans so the UI renders
/// the Yes/No words consistently and tests can assert them directly.
@immutable
class HttpMethod {
  const HttpMethod({
    required this.method,
    required this.safe,
    required this.idempotent,
    required this.purpose,
  });

  /// Method name, e.g. `GET`, `POST`.
  final String method;

  /// Read-only, no intended state change (RFC 9110).
  final bool safe;

  /// Repeating the request has the same effect as making it once (RFC 9110).
  final bool idempotent;

  /// Plain-English summary of what the method does.
  final String purpose;
}

/// One common HTTP header: name and plain-English purpose. Shared shape for the
/// request and response header tables.
@immutable
class HttpHeader {
  const HttpHeader({required this.name, required this.purpose});

  /// Header field name, e.g. `Authorization`.
  final String name;

  /// Plain-English summary of what the header carries / does.
  final String purpose;
}

class HttpMethodsScreen extends StatelessWidget {
  const HttpMethodsScreen({super.key});

  /// HTTP methods with safe/idempotent flags per RFC 9110 (PATCH per RFC 5789).
  static const List<HttpMethod> methods = <HttpMethod>[
    HttpMethod(
      method: 'GET',
      safe: true,
      idempotent: true,
      purpose: 'Retrieve a representation of the target resource.',
    ),
    HttpMethod(
      method: 'HEAD',
      safe: true,
      idempotent: true,
      purpose: 'Like GET, but returns headers only, no body.',
    ),
    HttpMethod(
      method: 'POST',
      safe: false,
      idempotent: false,
      purpose:
          'Submit data for the resource to process (create, append, '
          'trigger).',
    ),
    HttpMethod(
      method: 'PUT',
      safe: false,
      idempotent: true,
      purpose:
          'Create or fully replace the target resource with the request '
          'body.',
    ),
    HttpMethod(
      method: 'PATCH',
      safe: false,
      idempotent: false,
      purpose: 'Apply a partial modification to the resource.',
    ),
    HttpMethod(
      method: 'DELETE',
      safe: false,
      idempotent: true,
      purpose: 'Remove the target resource.',
    ),
    HttpMethod(
      method: 'CONNECT',
      safe: false,
      idempotent: false,
      purpose:
          'Establish a tunnel to the target host (typically for HTTPS via a '
          'proxy).',
    ),
    HttpMethod(
      method: 'OPTIONS',
      safe: true,
      idempotent: true,
      purpose:
          'Ask which methods/options the resource or server supports.',
    ),
    HttpMethod(
      method: 'TRACE',
      safe: true,
      idempotent: true,
      purpose: 'Loop the request back along the path for diagnostics.',
    ),
  ];

  /// Common request headers. Verbatim from the verified dataset.
  static const List<HttpHeader> requestHeaders = <HttpHeader>[
    HttpHeader(
      name: 'Host',
      purpose: 'Target host and port; required in HTTP/1.1.',
    ),
    HttpHeader(
      name: 'Authorization',
      purpose:
          'Carries credentials (e.g. Bearer token, Basic auth) for the '
          'request.',
    ),
    HttpHeader(
      name: 'Accept',
      purpose: 'Media types the client will accept in the response.',
    ),
    HttpHeader(
      name: 'Content-Type',
      purpose: 'Media type of the request body (e.g. application/json).',
    ),
    HttpHeader(
      name: 'User-Agent',
      purpose: 'Identifies the client software making the request.',
    ),
    HttpHeader(
      name: 'Cookie',
      purpose: 'Returns stored cookies to the server.',
    ),
    HttpHeader(
      name: 'Cache-Control',
      purpose: 'Caching directives the client imposes on the request chain.',
    ),
    HttpHeader(
      name: 'Content-Length',
      purpose: 'Size of the request body, in bytes.',
    ),
    HttpHeader(
      name: 'If-None-Match',
      purpose:
          "Conditional request: act only if the resource's ETag has "
          'changed.',
    ),
  ];

  /// Common response headers. Verbatim from the verified dataset.
  static const List<HttpHeader> responseHeaders = <HttpHeader>[
    HttpHeader(
      name: 'Content-Type',
      purpose: 'Media type of the response body.',
    ),
    HttpHeader(
      name: 'Set-Cookie',
      purpose: 'Asks the client to store a cookie.',
    ),
    HttpHeader(
      name: 'Cache-Control',
      purpose:
          'Caching directives for the response (max-age, no-store, etc.).',
    ),
    HttpHeader(
      name: 'ETag',
      purpose:
          'Version/validator token for the resource, used for conditional '
          'requests.',
    ),
    HttpHeader(
      name: 'Location',
      purpose:
          'Target URL for a redirect (3xx) or a newly created resource '
          '(201).',
    ),
    HttpHeader(
      name: 'Content-Length',
      purpose: 'Size of the response body, in bytes.',
    ),
    HttpHeader(
      name: 'Server',
      purpose: 'Identifies the origin server software.',
    ),
    HttpHeader(
      name: 'WWW-Authenticate',
      purpose: 'Challenges the client to authenticate (sent with 401).',
    ),
  ];

  /// Footnote — registry + RFC provenance.
  static const String footnote =
      'Methods and headers are from the IANA HTTP Method and HTTP Field Name '
      'registries; method semantics and the safe / idempotent definitions are '
      'from RFC 9110 (HTTP Semantics), PATCH from RFC 5789. Safe = read-only, '
      'no intended state change. Idempotent = repeating has the same effect as '
      'once.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HTTP Methods & Headers'),
        toolbarHeight: 64,
        // §8.16 — copy all three tables as a three-section TSV. Static data,
        // always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — three sections: methods (Method, Safe, Idempotent,
  /// Purpose), request headers (Header, Purpose), response headers (Header,
  /// Purpose). Boolean flags render as Yes/No. Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    String yn(bool b) => b ? 'Yes' : 'No';
    final StringBuffer buf = StringBuffer()
      ..writeln('HTTP Methods & Headers')
      ..writeln()
      ..writeln('Methods')
      ..writeln(
        <String>['Method', 'Safe?', 'Idempotent?', 'Purpose'].join(tab),
      );
    for (final HttpMethod m in methods) {
      buf.writeln(
        <String>[m.method, yn(m.safe), yn(m.idempotent), m.purpose].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Common request headers')
      ..writeln(<String>['Header', 'Purpose'].join(tab));
    for (final HttpHeader h in requestHeaders) {
      buf.writeln(<String>[h.name, h.purpose].join(tab));
    }
    buf
      ..writeln()
      ..writeln('Common response headers')
      ..writeln(<String>['Header', 'Purpose'].join(tab));
    for (final HttpHeader h in responseHeaders) {
      buf.writeln(<String>[h.name, h.purpose].join(tab));
    }
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
                children: <Widget>[
                  ConceptGraphicBand(
                    toolId: 'http-methods',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('http-methods'))
                    const SizedBox(height: AppSpacing.md),
                  _methodsCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _headersCard(
                    colors,
                    text,
                    mono,
                    title: 'Common request headers',
                    headers: requestHeaders,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _headersCard(
                    colors,
                    text,
                    mono,
                    title: 'Common response headers',
                    headers: responseHeaders,
                  ),
                  ToolHelpFooter(toolId: 'http-methods'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _methodsCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'Methods',
      footnote: footnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Method', width: 96),
          _HeaderCell('Safe?', width: 56),
          _HeaderCell('Idempotent?', width: 96),
          _HeaderCell('Purpose', width: 320),
        ],
      ),
      rows: methods.map((HttpMethod m) {
        final String safe = m.safe ? 'Yes' : 'No';
        final String idem = m.idempotent ? 'Yes' : 'No';
        return ReferenceRowSemantics(
          label: rowLabel(m.method, <String?>[
            'safe ${safe.toLowerCase()}',
            'idempotent ${idem.toLowerCase()}',
            m.purpose,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 96,
                  child: Text(
                    m.method,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    safe,
                    // The Yes/No WORD is the carrier (SC 1.4.1); a true safe
                    // method gets the accent, otherwise neutral tertiary —
                    // color reinforces, never replaces, the word.
                    style: text.labelMedium?.copyWith(
                      color: m.safe ? colors.textAccent : colors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    idem,
                    style: text.labelMedium?.copyWith(
                      color: m.idempotent
                          ? colors.textAccent
                          : colors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Text(
                    m.purpose,
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

  Widget _headersCard(
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono, {
    required String title,
    required List<HttpHeader> headers,
  }) {
    return _TableCard(
      title: title,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Header', width: 160),
          _HeaderCell('Purpose', width: 360),
        ],
      ),
      rows: headers.map((HttpHeader h) {
        return ReferenceRowSemantics(
          label: rowLabel(h.name, <String?>[h.purpose]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 160,
                  child: Text(
                    h.name,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: Text(
                    h.purpose,
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

/// Card surface wrapping a wide table: title (full-width, wraps) over a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align), with an optional full-width footnote beneath. Matches the
/// poe_reference_screen overflow-safe idiom.
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
        children: <Widget>[
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  header,
                  Divider(color: colors.border, height: AppSpacing.sm),
                  ...rows,
                ],
              ),
            ),
          ),
          if (footnote != null) ...<Widget>[
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
