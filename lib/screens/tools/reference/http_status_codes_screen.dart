// HTTP Status Codes — an offline reference for the HTTP response status codes
// a network / Wi-Fi pro meets when checking a captive portal, a web service, a
// proxy, or an API. Read-only; no input beyond a free-text filter.
//
// DATA SOURCE: the IANA HTTP Status Code Registry
// (https://www.iana.org/assignments/http-status-codes), the authoritative
// registry. Code numbers and reason phrases are reproduced verbatim from that
// registry (fetched 2026-06-04); the registry's primary reference for most
// codes is RFC 9110 (HTTP Semantics). The plain-English meanings are written
// for this tool — accurate, customer-appropriate, and not invented codes.
// Codes marked "Unassigned" in the registry, the obsoleted 510, and the
// temporary 104 upload-resumption draft are intentionally excluded; what
// remains are the assigned, standard codes grouped by class.
//
// States (SOP-007 §5):
//  - success → the grouped class tables render (the default; the dataset is
//    bundled in source, so there is no load step).
//  - empty   → a filter query that matches nothing; an honest "no match" card,
//    never a fabricated row.
// There is no loading or error state: the dataset is a compile-time const, so
// it cannot fail to load. There is no NetworkUnavailableView — this tool is
// fully offline on every platform (pure const data, including web).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// One HTTP status code: the numeric code, its registered reason phrase, and a
/// plain-English meaning. Immutable.
class HttpStatusEntry {
  const HttpStatusEntry(this.code, this.reason, this.meaning);

  /// The numeric status code as it appears on the wire (100–599).
  final int code;

  /// The reason phrase, verbatim from the IANA registry (e.g. `Not Found`).
  final String reason;

  /// A short plain-language meaning written for this tool.
  final String meaning;
}

/// A class of status codes (1xx … 5xx) with its label and entries.
class HttpStatusClass {
  const HttpStatusClass(this.label, this.lowerBound, this.entries);

  /// The class heading (e.g. `4xx Client Error`).
  final String label;

  /// The inclusive lower bound of the class (100, 200, 300, 400, 500). Used to
  /// validate that every entry sits in the right century.
  final int lowerBound;

  final List<HttpStatusEntry> entries;
}

class HttpStatusCodesScreen extends StatefulWidget {
  const HttpStatusCodesScreen({super.key});

  /// The five status-code classes, each holding the IANA-registered codes for
  /// that century. Public + static so tests can assert known codes and class
  /// ranges without pumping the UI.
  static const List<HttpStatusClass> classes = <HttpStatusClass>[
    HttpStatusClass('1xx Informational', 100, <HttpStatusEntry>[
      HttpStatusEntry(
        100,
        'Continue',
        'The request headers are fine so far, so go ahead and send the body.',
      ),
      HttpStatusEntry(
        101,
        'Switching Protocols',
        'The server is switching protocols as the client asked (e.g. an '
            'upgrade to WebSocket).',
      ),
      HttpStatusEntry(
        102,
        'Processing',
        'The server has accepted the request and is still working on it '
            '(WebDAV).',
      ),
      HttpStatusEntry(
        103,
        'Early Hints',
        'Preliminary headers sent before the final response so the client can '
            'start preloading resources.',
      ),
    ]),
    HttpStatusClass('2xx Success', 200, <HttpStatusEntry>[
      HttpStatusEntry(
        200,
        'OK',
        'The request succeeded. The normal "all good" response.',
      ),
      HttpStatusEntry(
        201,
        'Created',
        'The request succeeded and a new resource was created.',
      ),
      HttpStatusEntry(
        202,
        'Accepted',
        'The request was accepted for processing, but is not finished yet.',
      ),
      HttpStatusEntry(
        203,
        'Non-Authoritative Information',
        'The response is a modified copy from a proxy, not the origin server.',
      ),
      HttpStatusEntry(
        204,
        'No Content',
        'The request succeeded but there is no body to return.',
      ),
      HttpStatusEntry(
        205,
        'Reset Content',
        'The request succeeded; the client should reset the form or view that '
            'sent it.',
      ),
      HttpStatusEntry(
        206,
        'Partial Content',
        'Only the requested byte range was returned (used for resumable '
            'downloads and streaming).',
      ),
      HttpStatusEntry(
        207,
        'Multi-Status',
        'The body carries multiple independent status codes, one per operation '
            '(WebDAV).',
      ),
      HttpStatusEntry(
        208,
        'Already Reported',
        'A member was already listed earlier in the response and is not '
            'repeated (WebDAV).',
      ),
      HttpStatusEntry(
        226,
        'IM Used',
        'The response is the result of applying instance manipulations to the '
            'resource (delta encoding).',
      ),
    ]),
    HttpStatusClass('3xx Redirection', 300, <HttpStatusEntry>[
      HttpStatusEntry(
        300,
        'Multiple Choices',
        'The resource has more than one representation; the client picks one.',
      ),
      HttpStatusEntry(
        301,
        'Moved Permanently',
        'The resource has a new permanent address. Use it from now on.',
      ),
      HttpStatusEntry(
        302,
        'Found',
        'The resource is temporarily at a different address; keep using the '
            'original.',
      ),
      HttpStatusEntry(
        303,
        'See Other',
        'Fetch the result from a different address using GET (common after a '
            'form post).',
      ),
      HttpStatusEntry(
        304,
        'Not Modified',
        'The cached copy is still current. Nothing changed, so no body is '
            'sent.',
      ),
      HttpStatusEntry(
        305,
        'Use Proxy',
        'The resource must be reached through a proxy. Deprecated and rarely '
            'used.',
      ),
      HttpStatusEntry(
        307,
        'Temporary Redirect',
        'Like 302, but the client must keep the same method (e.g. POST stays '
            'POST).',
      ),
      HttpStatusEntry(
        308,
        'Permanent Redirect',
        'Like 301, but the client must keep the same method on the redirect.',
      ),
    ]),
    HttpStatusClass('4xx Client Error', 400, <HttpStatusEntry>[
      HttpStatusEntry(
        400,
        'Bad Request',
        'The server could not understand the request (malformed syntax or '
            'parameters).',
      ),
      HttpStatusEntry(
        401,
        'Unauthorized',
        'Authentication is required and has failed or not been provided.',
      ),
      HttpStatusEntry(
        402,
        'Payment Required',
        'Reserved for future use; occasionally used by paid APIs.',
      ),
      HttpStatusEntry(
        403,
        'Forbidden',
        'The server understood the request but refuses to authorize it.',
      ),
      HttpStatusEntry(
        404,
        'Not Found',
        'The server has no resource at this address.',
      ),
      HttpStatusEntry(
        405,
        'Method Not Allowed',
        'The HTTP method is not allowed for this resource (e.g. POST to a '
            'read-only path).',
      ),
      HttpStatusEntry(
        406,
        'Not Acceptable',
        'The server cannot produce a response matching the client Accept '
            'headers.',
      ),
      HttpStatusEntry(
        407,
        'Proxy Authentication Required',
        'The client must authenticate with the proxy first.',
      ),
      HttpStatusEntry(
        408,
        'Request Timeout',
        'The client took too long to send the request and the server gave up.',
      ),
      HttpStatusEntry(
        409,
        'Conflict',
        'The request conflicts with the current state of the resource.',
      ),
      HttpStatusEntry(
        410,
        'Gone',
        'The resource was here but has been permanently removed.',
      ),
      HttpStatusEntry(
        411,
        'Length Required',
        'The server needs a Content-Length header and the request did not send '
            'one.',
      ),
      HttpStatusEntry(
        412,
        'Precondition Failed',
        'A condition the client set in the request headers was not met.',
      ),
      HttpStatusEntry(
        413,
        'Content Too Large',
        'The request body is larger than the server will accept.',
      ),
      HttpStatusEntry(
        414,
        'URI Too Long',
        'The requested URL is longer than the server will process.',
      ),
      HttpStatusEntry(
        415,
        'Unsupported Media Type',
        'The request body is in a format the server does not support.',
      ),
      HttpStatusEntry(
        416,
        'Range Not Satisfiable',
        'The requested byte range falls outside the size of the resource.',
      ),
      HttpStatusEntry(
        417,
        'Expectation Failed',
        'The server cannot meet the requirement in the Expect header.',
      ),
      HttpStatusEntry(
        418,
        '(Unused)',
        'Reserved and unused per the IANA registry. Widely known as the '
            '"I am a teapot" joke code from RFC 2324.',
      ),
      HttpStatusEntry(
        421,
        'Misdirected Request',
        'The request reached a server that cannot produce a response for this '
            'host.',
      ),
      HttpStatusEntry(
        422,
        'Unprocessable Content',
        'The syntax is valid but the server could not process the contained '
            'instructions (WebDAV / APIs).',
      ),
      HttpStatusEntry(
        423,
        'Locked',
        'The resource is locked and cannot be changed right now (WebDAV).',
      ),
      HttpStatusEntry(
        424,
        'Failed Dependency',
        'The request failed because an earlier request it depended on failed '
            '(WebDAV).',
      ),
      HttpStatusEntry(
        425,
        'Too Early',
        'The server will not risk processing a request that might be replayed.',
      ),
      HttpStatusEntry(
        426,
        'Upgrade Required',
        'The client must switch to a different protocol, such as upgrading to '
            'TLS.',
      ),
      HttpStatusEntry(
        428,
        'Precondition Required',
        'The server requires the request to be conditional to avoid a lost '
            'update.',
      ),
      HttpStatusEntry(
        429,
        'Too Many Requests',
        'The client has sent too many requests in a given time (rate '
            'limiting).',
      ),
      HttpStatusEntry(
        431,
        'Request Header Fields Too Large',
        'The request headers are too large for the server to process.',
      ),
      HttpStatusEntry(
        451,
        'Unavailable For Legal Reasons',
        'The resource is blocked for legal reasons (e.g. a takedown or '
            'censorship order).',
      ),
    ]),
    HttpStatusClass('5xx Server Error', 500, <HttpStatusEntry>[
      HttpStatusEntry(
        500,
        'Internal Server Error',
        'The server hit an unexpected error and could not complete the '
            'request.',
      ),
      HttpStatusEntry(
        501,
        'Not Implemented',
        'The server does not support the functionality the request needs.',
      ),
      HttpStatusEntry(
        502,
        'Bad Gateway',
        'A gateway or proxy got an invalid response from the upstream server.',
      ),
      HttpStatusEntry(
        503,
        'Service Unavailable',
        'The server is temporarily overloaded or down for maintenance.',
      ),
      HttpStatusEntry(
        504,
        'Gateway Timeout',
        'A gateway or proxy did not get a timely response from the upstream '
            'server.',
      ),
      HttpStatusEntry(
        505,
        'HTTP Version Not Supported',
        'The server does not support the HTTP version used in the request.',
      ),
      HttpStatusEntry(
        506,
        'Variant Also Negotiates',
        'A content-negotiation configuration error on the server.',
      ),
      HttpStatusEntry(
        507,
        'Insufficient Storage',
        'The server cannot store what is needed to complete the request '
            '(WebDAV).',
      ),
      HttpStatusEntry(
        508,
        'Loop Detected',
        'The server detected an infinite loop while processing the request '
            '(WebDAV).',
      ),
      HttpStatusEntry(
        511,
        'Network Authentication Required',
        'The client must authenticate to gain network access. The signature '
            'of a captive portal.',
      ),
    ]),
  ];

  @override
  State<HttpStatusCodesScreen> createState() => _HttpStatusCodesScreenState();
}

class _HttpStatusCodesScreenState extends State<HttpStatusCodesScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  /// True when [entry] matches the trimmed, lower-cased [q] by code number,
  /// reason phrase, or plain-English meaning. An empty query matches everything.
  bool _matches(HttpStatusEntry entry, String q) {
    if (q.isEmpty) return true;
    if (entry.code.toString().contains(q)) return true;
    if (entry.reason.toLowerCase().contains(q)) return true;
    return entry.meaning.toLowerCase().contains(q);
  }

  /// Apply the current filter to a class; returns null when nothing matches so
  /// the heading is dropped along with its (empty) table.
  HttpStatusClass? _filterClass(HttpStatusClass c, String q) {
    if (q.isEmpty) return c;
    final List<HttpStatusEntry> kept = c.entries
        .where((HttpStatusEntry e) => _matches(e, q))
        .toList();
    if (kept.isEmpty) return null;
    return HttpStatusClass(c.label, c.lowerBound, kept);
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    // WCAG 4.1.3 — announce the live match count so AT users hear the tables
    // change as they type, without focus leaving the field.
    final String q = value.trim().toLowerCase();
    int n = 0;
    for (final HttpStatusClass c in HttpStatusCodesScreen.classes) {
      n += c.entries.where((HttpStatusEntry e) => _matches(e, q)).length;
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching codes' : '$n matching code${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HTTP Status Codes'),
        toolbarHeight: 64,
        // §8.16 — copy the status-code reference as TSV, one section per class.
        // Copies the FULL reference (not the filtered view) so "copy the
        // reference" is predictable and consistent with the other filterable
        // reference tables. Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the status-code reference as a multi-section TSV. Each
  /// class (the same headings the screen renders) is its own section: class
  /// label subtitle + header + one tab-separated row per code. Columns: Code,
  /// Name, Meaning. Copies the FULL reference, not the filtered view. Always
  /// non-null (static data).
  String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()..writeln('HTTP Status Codes');
    for (final HttpStatusClass c in HttpStatusCodesScreen.classes) {
      buf
        ..writeln()
        ..writeln(c.label)
        ..writeln(<String>['Code', 'Name', 'Meaning'].join(tab));
      for (final HttpStatusEntry e in c.entries) {
        buf.writeln(<String>['${e.code}', e.reason, e.meaning].join(tab));
      }
    }
    return buf.toString().trimRight();
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
                    toolId: 'http-status-codes',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('http-status-codes'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _searchCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  ..._results(context),
                  ToolHelpFooter(toolId: 'http-status-codes'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _introCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        'HTTP response status codes grouped by class. These are the codes you '
        'meet checking a captive portal, a web service, a proxy, or an API. '
        'The first digit sets the class: 1xx informational, 2xx success, 3xx '
        'redirection, 4xx client error, 5xx server error.',
        style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
      ),
    );
  }

  Widget _searchCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LabeledField(
        label: 'Filter',
        hint: 'code number or keyword',
        semanticLabel: 'Filter status codes by number, name, or keyword',
        field: TextField(
          controller: _queryCtrl,
          focusNode: _queryFocus,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          cursorColor: AppColors.primary,
          decoration: const InputDecoration(hintText: 'e.g. 404 or redirect'),
        ),
      ),
    );
  }

  /// Build the filtered class cards plus the footnote. An all-empty result
  /// yields a single "no match" card.
  List<Widget> _results(BuildContext context) {
    final String q = _query.trim().toLowerCase();

    final List<Widget> cards = <Widget>[];
    for (final HttpStatusClass c in HttpStatusCodesScreen.classes) {
      final HttpStatusClass? filtered = _filterClass(c, q);
      if (filtered != null) {
        cards.add(_ClassCard(statusClass: filtered));
        cards.add(const SizedBox(height: AppSpacing.sm));
      }
    }

    if (cards.isEmpty) {
      return <Widget>[
        _MessageCard(
          icon: Icons.search_off,
          title: 'No match',
          body: 'No status code matches "${_query.trim()}".',
        ),
      ];
    }

    cards.add(_footnote(context));
    return cards;
  }

  Widget _footnote(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      'Codes and names are from the IANA HTTP Status Code Registry; most are '
      'defined by RFC 9110 (HTTP Semantics). Unassigned and obsoleted codes are '
      'omitted.',
      style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
    );
  }
}

/// One class: a heading line followed by its code rows in a bordered card.
class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.statusClass});

  final HttpStatusClass statusClass;

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
            statusClass.label,
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...statusClass.entries.map(
            (HttpStatusEntry e) => _StatusRow(entry: e),
          ),
        ],
      ),
    );
  }
}

/// One status row: the numeric code in a fixed-width mono gutter, the reason
/// phrase, and the plain-English meaning beneath. The code and reason are
/// neutral primary/secondary text — the class is conveyed by the section
/// heading, not by a status color (HTTP class is a category, not a computed
/// verdict, so §8.13 status hues do not apply here).
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.entry});

  final HttpStatusEntry entry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    // Merge code + reason + meaning into one semantic node so AT reads
    // "404, Not Found, The server has no resource at this address" as a single
    // row instead of three fragments.
    return Semantics(
      container: true,
      label: '${entry.code}, ${entry.reason}. ${entry.meaning}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              child: Text(
                '${entry.code}',
                style: mono.robotoMono.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.reason,
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.meaning,
                    style: text.labelMedium?.copyWith(
                      color: AppColors.textTertiary,
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

/// Empty-state card — mirrors the reason-codes "no match" surface.
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
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
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
