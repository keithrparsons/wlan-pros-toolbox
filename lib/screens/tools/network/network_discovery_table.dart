// Network Discovery results table — the wide-viewport rendering of the host
// list (customer request, Peter, desktop: "have the results in a table").
//
// WHY THIS EXISTS
// The host list ships as a stacked card per host, which reads well on a phone
// and wastes most of the window on a desktop: the screen caps its content
// column at 560px, so a maximized Windows or macOS window shows one narrow
// ribbon of hosts in a sea of margin. On a wide viewport the same fields fit as
// one scannable row per host, which is what a network engineer comparing
// twenty hosts actually wants.
//
// The narrow layout is NOT replaced. The screen picks by available width, so a
// desktop window dragged narrow reflows back to cards exactly like a phone --
// width-based, never platform-based (the same rule AppSpacing.gridMaxWidth
// documents for the tile grids: a resized Mac window must behave like the width
// it actually is).
//
// COLUMNS ARE DERIVED FROM THE MODEL, NOT INVENTED
// Every column maps to a real LanHost field: ip, mdnsName/hostname, deviceType,
// mac, vendor, mdnsServices, openPorts. The engine measures no per-host timing,
// so there is deliberately NO "response time" column -- inventing one would
// mean fabricating a number the scan never took (GL-005).
//
// MAC and Vendor are omitted entirely when the ARP read was unavailable, rather
// than rendered as a column of blanks. That matches the honest ceiling note the
// screen already prints above the results: those fields are omitted, not empty.
//
// SORTING
// Sort state lives in the SCREEN, not in this widget, so the "Copy results"
// action can emit rows in the order the user is actually looking at. A table
// you sorted and a clipboard that ignored the sort are two different answers to
// the same question.
//
// IP sorts NUMERICALLY via ipSortKey (192.168.1.9 before 192.168.1.10), never
// as a string. Blank enrichment fields sort last in BOTH directions, so
// reversing a column never fills the top of the table with empty cells. Every
// sort tie-breaks on IP ascending, so the order is total and stable.

import 'package:flutter/material.dart';

import '../../../services/network/lan_discovery/device_type.dart';
import '../../../services/network/lan_discovery/lan_host.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../reference/reference_row_semantics.dart';

/// A Material glyph for each coarse device type -- a quiet leading affordance,
/// never the sole carrier of meaning (the worded label always sits beside it,
/// GL-003 section 8.4).
///
/// Defined here rather than in `device_type.dart` because that file is a pure
/// service model with no Flutter dependency, and here rather than in the screen
/// so the card layout and the table share ONE mapping instead of drifting apart.
IconData deviceTypeIcon(DeviceType type) => switch (type) {
  DeviceType.printer => Icons.print_outlined,
  DeviceType.camera => Icons.videocam_outlined,
  DeviceType.speaker => Icons.speaker_outlined,
  DeviceType.mediaStreamer => Icons.cast_outlined,
  DeviceType.appleDevice => Icons.devices_outlined,
  DeviceType.iosDevice => Icons.smartphone_outlined,
  DeviceType.windowsHost => Icons.desktop_windows_outlined,
  DeviceType.accessPoint => Icons.wifi_outlined,
  DeviceType.networkGear => Icons.router_outlined,
  DeviceType.webServer => Icons.dns_outlined,
  DeviceType.sshHost => Icons.terminal_outlined,
  DeviceType.mdnsDevice => Icons.lan_outlined,
  DeviceType.unknown => Icons.device_unknown_outlined,
};

/// The columns the discovered-host table can be sorted by. Each maps to a real
/// [LanHost] field; there is no column for data the engine does not produce.
enum DiscoverySortColumn { ip, name, type, mac, vendor, services, ports }

/// A sort selection: which column, and which direction.
@immutable
class DiscoverySort {
  const DiscoverySort({
    this.column = DiscoverySortColumn.ip,
    this.ascending = true,
  });

  final DiscoverySortColumn column;
  final bool ascending;

  /// Toggles direction when [column] is re-selected, otherwise switches to the
  /// new column ascending -- the conventional data-table behaviour.
  DiscoverySort select(DiscoverySortColumn next) => column == next
      ? DiscoverySort(column: column, ascending: !ascending)
      : DiscoverySort(column: next);
}

/// The display name of a host: the mDNS instance name if it advertised one,
/// else the reverse-DNS hostname, else null. Shared by the table, the card
/// layout, and the copy payload so all three agree on what "Name" means.
String? hostDisplayName(LanHost host) => host.mdnsName ?? host.hostname;

/// The columns the table renders, in display order.
///
/// MAC and Vendor exist only while the ARP read succeeded; when it did not they
/// are omitted entirely rather than rendered as a column of blanks, matching the
/// honest ceiling note the screen prints above the results.
List<DiscoverySortColumn> visibleDiscoveryColumns({
  required bool showMacColumns,
}) => <DiscoverySortColumn>[
  DiscoverySortColumn.ip,
  DiscoverySortColumn.name,
  DiscoverySortColumn.type,
  if (showMacColumns) DiscoverySortColumn.mac,
  if (showMacColumns) DiscoverySortColumn.vendor,
  DiscoverySortColumn.services,
  DiscoverySortColumn.ports,
];

/// The sort actually in force, given which columns are being rendered.
///
/// A sort selection can OUTLIVE its column: sort by MAC while the ARP read is
/// working, then re-scan on a run where it fails, and the selection still names
/// a column that is no longer in the header row. Ordering rows by a column the
/// user cannot see is not a defensible state -- there is no header to carry the
/// arrow, so the order becomes unexplainable -- so the sort falls back to the
/// default, IP ascending, which every column set contains.
///
/// Deriving this rather than mutating the stored selection is deliberate: it is
/// pure, it cannot fire a setState during build, and a MAC sort is restored
/// intact if a later scan reads the ARP cache again.
DiscoverySort effectiveDiscoverySort(
  DiscoverySort sort, {
  required bool showMacColumns,
}) => visibleDiscoveryColumns(showMacColumns: showMacColumns).contains(sort.column)
    ? sort
    : const DiscoverySort();

/// Returns [hosts] ordered by [sort]. Pure and total: never mutates the input,
/// always tie-breaks on IP ascending so equal keys keep a deterministic order.
///
/// Blank/absent values sort LAST in both directions. Reversing "Vendor" should
/// show the other end of the vendor list, not a screenful of hosts that have no
/// vendor at all.
List<LanHost> sortHosts(List<LanHost> hosts, DiscoverySort sort) {
  final List<LanHost> ordered = List<LanHost>.of(hosts);
  ordered.sort((LanHost a, LanHost b) {
    final int primary = _compare(a, b, sort);
    if (primary != 0) return primary;
    return ipSortKey(a.ip).compareTo(ipSortKey(b.ip));
  });
  return ordered;
}

int _compare(LanHost a, LanHost b, DiscoverySort sort) {
  final bool asc = sort.ascending;
  switch (sort.column) {
    case DiscoverySortColumn.ip:
      // The one that matters: pack the octets, never compare the strings.
      final int cmp = ipSortKey(a.ip).compareTo(ipSortKey(b.ip));
      return asc ? cmp : -cmp;
    case DiscoverySortColumn.name:
      return _text(hostDisplayName(a), hostDisplayName(b), asc);
    case DiscoverySortColumn.type:
      // Device type is always present (defaults to unknown), so no blank rule.
      final int cmp = a.deviceType.label.compareTo(b.deviceType.label);
      return asc ? cmp : -cmp;
    case DiscoverySortColumn.mac:
      return _text(a.mac, b.mac, asc);
    case DiscoverySortColumn.vendor:
      return _text(a.vendor, b.vendor, asc);
    case DiscoverySortColumn.services:
      return _text(_servicesOf(a), _servicesOf(b), asc);
    case DiscoverySortColumn.ports:
      // Order by the LOWEST open port, which is the one the cell shows first.
      return _number(_lowestPort(a), _lowestPort(b), asc);
  }
}

/// Case-insensitive text compare with blanks pinned last in both directions.
int _text(String? a, String? b, bool ascending) {
  final bool aBlank = a == null || a.isEmpty;
  final bool bBlank = b == null || b.isEmpty;
  if (aBlank && bBlank) return 0;
  if (aBlank) return 1;
  if (bBlank) return -1;
  final int cmp = a.toLowerCase().compareTo(b.toLowerCase());
  return ascending ? cmp : -cmp;
}

/// Numeric compare with absent values (null) pinned last in both directions.
int _number(int? a, int? b, bool ascending) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  final int cmp = a.compareTo(b);
  return ascending ? cmp : -cmp;
}

int? _lowestPort(LanHost host) =>
    host.openPorts.isEmpty ? null : host.openPorts.reduce((int a, int b) => a < b ? a : b);

String _servicesOf(LanHost host) =>
    (host.mdnsServices.toList()..sort()).join(', ');

String _portsOf(LanHost host) => (host.openPorts.toList()..sort()).join(', ');

/// The discovered hosts as a sortable table, for wide viewports only. The
/// screen keeps rendering the stacked card list below its table breakpoint.
///
/// [hosts] must already be ordered by [sort] (the screen sorts once and shares
/// that list with the copy action, so the clipboard and the table never
/// disagree). [showMacColumns] is the ARP-availability gate: false drops the
/// MAC and Vendor columns rather than printing a column of blanks.
class NetworkDiscoveryTable extends StatelessWidget {
  const NetworkDiscoveryTable({
    super.key,
    required this.hosts,
    required this.sort,
    required this.onSort,
    required this.showMacColumns,
  });

  final List<LanHost> hosts;
  final DiscoverySort sort;
  final ValueChanged<DiscoverySortColumn> onSort;
  final bool showMacColumns;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    // The visible columns, in display order. Built from the shared helper so the
    // MAC/vendor gate cannot desynchronise the header row from the cell rows, or
    // from the sort resolution the screen ran against the same list.
    final List<DiscoverySortColumn> columns = visibleDiscoveryColumns(
      showMacColumns: showMacColumns,
    );

    // The screen already resolves the sort against the visible column set, but
    // resolve again here rather than trusting the caller: handing DataTable an
    // index of -1 for a column that is not rendered trips its own assertion in
    // debug and silently unsorts every header in release. This widget owns that
    // invariant, so it enforces it at its own boundary.
    final DiscoverySort active = effectiveDiscoverySort(
      sort,
      showMacColumns: showMacColumns,
    );
    final int sortIndex = columns.indexOf(active.column);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      // The table scrolls sideways INSIDE this card when the columns exceed the
      // card width, so the page itself never scrolls horizontally. Same idiom
      // as the reference tables, and it carries the always-visible scrollbar
      // that signals "more columns to the right" on desktop.
      child: HorizontalScrollTable(
        child: DataTable(
          headingRowHeight: 44,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 56,
          columnSpacing: AppSpacing.md,
          horizontalMargin: 0,
          dividerThickness: 1,
          headingTextStyle: (text.labelMedium ?? const TextStyle()).copyWith(
            color: colors.textTertiary,
            letterSpacing: 0.4,
          ),
          // Null, never -1: "no column is sorted" is a state DataTable accepts,
          // an out-of-range index is not.
          sortColumnIndex: sortIndex < 0 ? null : sortIndex,
          sortAscending: active.ascending,
          columns: <DataColumn>[
            for (final DiscoverySortColumn column in columns)
              DataColumn(
                label: _headerLabel(column, active),
                // Ports is the only right-aligned column; the rest read as
                // text. IP and MAC are numeric-ish but are identifiers, so they
                // stay left-aligned like every other identifier in the app.
                numeric: column == DiscoverySortColumn.ports,
                tooltip: _tooltipFor(column),
                // DataTable hands back the index and direction it thinks are
                // next; the screen owns the real sort state, so we ignore both
                // and just report which column was activated.
                onSort: (int columnIndex, bool ascending) => onSort(column),
              ),
          ],
          rows: <DataRow>[
            for (final LanHost host in hosts)
              _rowFor(context, host, columns, colors, text, mono),
          ],
        ),
      ),
    );
  }

  DataRow _rowFor(
    BuildContext context,
    LanHost host,
    List<DiscoverySortColumn> columns,
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
  ) {
    final TextStyle cellStyle = (text.bodyMedium ?? const TextStyle()).copyWith(
      color: colors.textPrimary,
    );
    final TextStyle quietStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textSecondary);
    // Roboto Mono for IP, MAC, and ports so the digits sit on a common grid and
    // a column of addresses aligns octet-under-octet (GL-003 section 8.5
    // identifier register).
    final TextStyle monoStyle = mono.robotoMono.copyWith(
      color: colors.textPrimary,
    );

    // A DataTable renders every DataCell as its own accessibility node, so a
    // screen reader would otherwise announce seven disconnected fragments per
    // host with no signal about where a row starts. Give the FIRST cell the
    // whole row summary and exclude the rest, exactly as the reference tables
    // do (Vera F-02).
    final String summary = rowLabel('Host ${host.ip}', <String?>[
      host.deviceType.label,
      hostDisplayName(host) == null ? null : 'named ${hostDisplayName(host)}',
      if (showMacColumns) host.mac == null ? null : 'MAC ${host.mac}',
      if (showMacColumns) host.vendor == null ? null : 'vendor ${host.vendor}',
      _servicesOf(host).isEmpty ? null : 'services ${_servicesOf(host)}',
      _portsOf(host).isEmpty ? 'no open ports' : 'open ports ${_portsOf(host)}',
    ]);

    return DataRow(
      cells: <DataCell>[
        for (int i = 0; i < columns.length; i++)
          DataCell(
            i == 0
                ? Semantics(
                    label: summary,
                    excludeSemantics: true,
                    child: _cellFor(
                      columns[i],
                      host,
                      cellStyle,
                      quietStyle,
                      monoStyle,
                      colors,
                    ),
                  )
                : ExcludeSemantics(
                    child: _cellFor(
                      columns[i],
                      host,
                      cellStyle,
                      quietStyle,
                      monoStyle,
                      colors,
                    ),
                  ),
          ),
      ],
    );
  }

  /// One cell's content. An absent enrichment field renders as "n/a" in the
  /// quiet text colour -- the app's existing placeholder for a value it does not
  /// have (roaming_log_screen.dart, cloud_apps_panel.dart) -- never a guessed
  /// value.
  Widget _cellFor(
    DiscoverySortColumn column,
    LanHost host,
    TextStyle cellStyle,
    TextStyle quietStyle,
    TextStyle monoStyle,
    AppColorScheme colors,
  ) {
    switch (column) {
      case DiscoverySortColumn.ip:
        return Text(host.ip, style: monoStyle);
      case DiscoverySortColumn.name:
        return _valueOrBlank(hostDisplayName(host), cellStyle, colors);
      case DiscoverySortColumn.type:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              deviceTypeIcon(host.deviceType),
              size: 16,
              color: colors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(host.deviceType.label, style: quietStyle),
          ],
        );
      case DiscoverySortColumn.mac:
        return _valueOrBlank(host.mac, monoStyle, colors);
      case DiscoverySortColumn.vendor:
        return _valueOrBlank(host.vendor, cellStyle, colors);
      case DiscoverySortColumn.services:
        return _valueOrBlank(_servicesOf(host), quietStyle, colors);
      case DiscoverySortColumn.ports:
        final String ports = _portsOf(host);
        return ports.isEmpty
            ? Text('none open', style: quietStyle)
            : Text(ports, style: monoStyle);
    }
  }

  Widget _valueOrBlank(String? value, TextStyle style, AppColorScheme colors) =>
      (value == null || value.isEmpty)
      ? Text('n/a', style: style.copyWith(color: colors.textTertiary))
      : Text(value, style: style);

  /// A column header, carrying its sort state to assistive tech.
  ///
  /// The sort arrow is the only VISUAL signal of which column is active and
  /// which way it runs, and a screen reader gets no arrow: it would hear a bare
  /// "IP" whether the table was sorted by IP or not (WCAG 2.2 SC 1.3.1 and
  /// 4.1.2). Flutter's Semantics exposes no aria-sort equivalent, so the state
  /// goes into the header's accessible NAME, which every platform announces.
  ///
  /// The visible [Text] is kept as the child so the header still reads and
  /// measures exactly as before; only what AT hears changes.
  Widget _headerLabel(DiscoverySortColumn column, DiscoverySort active) {
    final String header = _headerFor(column);
    final String state = column == active.column
        ? ', sorted ${active.ascending ? 'ascending' : 'descending'}'
        : ', sortable';
    return Semantics(
      label: '$header$state',
      child: ExcludeSemantics(child: Text(header)),
    );
  }

  String _headerFor(DiscoverySortColumn column) => switch (column) {
    DiscoverySortColumn.ip => 'IP',
    DiscoverySortColumn.name => 'Name',
    DiscoverySortColumn.type => 'Type',
    DiscoverySortColumn.mac => 'MAC',
    DiscoverySortColumn.vendor => 'Vendor',
    DiscoverySortColumn.services => 'Services',
    DiscoverySortColumn.ports => 'Open ports',
  };

  /// Header tooltips double as the screen-reader description of what the column
  /// holds, since the visible headers are abbreviated.
  String _tooltipFor(DiscoverySortColumn column) => switch (column) {
    DiscoverySortColumn.ip => 'IPv4 address, sorted numerically',
    DiscoverySortColumn.name => 'mDNS name, or reverse-DNS hostname',
    DiscoverySortColumn.type => 'Device type inferred from ports and services',
    DiscoverySortColumn.mac => 'Link-layer MAC address from the ARP cache',
    DiscoverySortColumn.vendor => 'Vendor registered to the MAC address OUI',
    DiscoverySortColumn.services => 'Services advertised over mDNS',
    DiscoverySortColumn.ports => 'Open TCP ports found by the connect-scan',
  };
}
