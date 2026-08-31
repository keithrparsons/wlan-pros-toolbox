// Link Info - every network interface, described by what it IS.
//
// WHY THIS SCREEN EXISTS. link_info.dart landed with 45 passing tests and no
// consumer, and stayed that way. Keith, repeatedly: he asked to SEE the
// Ethernet work and there was nothing to look at. Phase 0 unblocked this
// screen; it did not build it.
//
// WHAT IT REFUSES TO DO, and each refusal is a measured trap:
//
//  * It never calls an interface up because the UP flag is set. `en2` on the
//    M5 is named "Ethernet Adapter", carries IFF_RUNNING permanently, and has
//    never had a cable in it. CARRIER decides.
//  * It never prints a negotiated speed beside a port with no carrier. A true
//    number in the wrong place is this project's whole failure history.
//  * It never hides a down interface. A wired port that is present and dead is
//    the single most useful thing this screen can show a person standing in a
//    plant room, and hiding it turns a diagnosis into a blank space.
//  * It never says "unavailable" without saying what would change it.
//
// THE ONE THING IT CANNOT DISTINGUISH, stated on screen rather than papered
// over: a cable into a dead switch is byte-identical to no cable. Both are
// `media: autoselect (none)` / `status: inactive`. So the copy says to check
// both ends.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../services/network/link_info.dart';
import '../../../services/network/link_table_service.dart';
import '../../../services/network/transport_chooser.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

class LinkInfoScreen extends StatefulWidget {
  const LinkInfoScreen({super.key, this.service});

  final LinkTableService? service;

  @override
  State<LinkInfoScreen> createState() => _LinkInfoScreenState();
}

class _LinkInfoScreenState extends State<LinkInfoScreen> {
  late final LinkTableService _service = widget.service ?? LinkTableService();
  LinkTableResult? _result;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final LinkTableResult r = await _service.read();
    if (!mounted) return;
    setState(() {
      _result = r;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Link Info'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Read again',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final LinkTableResult? r = _result;
    if (r == null || !r.hasTable) {
      return _Unavailable(
        reason: r?.unavailableReason ?? 'The link table could not be read.',
        onRetry: _load,
      );
    }

    final LinkTable t = r.table!;
    final List<LinkInfo> shown = t.links
        .where((LinkInfo l) => l.kind != LinkKind.loopback)
        .toList()
      ..sort(_byInterest);

    final LinkInfo? carrying = selectDefaultLink(t.links);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.sm),
        children: <Widget>[
          _Verdict(carrying: carrying, table: t),
          const SizedBox(height: AppSpacing.sm),
          _Chooser(table: t),
          const SizedBox(height: AppSpacing.sm),
          for (final LinkInfo l in shown) ...<Widget>[
            _LinkCard(link: l),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.xs),
          _Footnote(source: t.source),
        ],
      ),
    );
  }

  /// Live links first, then present-but-down, then everything else. A person
  /// opening this screen is looking for what is up, or for the wired port that
  /// should be up and is not. Both belong at the top.
  static int _byInterest(LinkInfo a, LinkInfo b) {
    int rank(LinkInfo l) {
      if (l.isDefaultRouteV4) return 0;
      if (l.carrier == true && l.addresses.isNotEmpty) return 1;
      if (l.kind == LinkKind.wired && l.carrier != true) return 2;
      if (l.carrier == true) return 3;
      return 4;
    }
    final int r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.name.compareTo(b.name);
  }
}

// ---------------------------------------------------------------------------

/// Which path is this test taking, and may you change it.
///
/// KEITH, 2026-08-31: "If I'm on an iPhone with Wi-Fi, Ethernet and Cellular -
/// I NEED to know which path is being tested. So the chooser needs to be aware
/// of platform, and capabilities before giving an option. Then explaining WHY
/// some don't work in certain situations."
///
/// So EVERY transport gets a row, including ones this device does not have, and
/// no row is ever greyed out in silence. A control that is unavailable without
/// saying why reads as a bug, which is the same rule as the join screen's
/// absent passphrase box and the same rule that produced NotOnWifiCard in June.
///
/// It is READ-ONLY here on purpose. Showing the chooser before wiring it into
/// the tools lets the design be judged on its own, and an interactive control
/// that silently failed to move the traffic would be worse than none.
class _Chooser extends StatelessWidget {
  const _Chooser({required this.table});

  final LinkTable table;

  TransportPlatform get _platform {
    if (kIsWeb) {
      return table.source != null && table.source!.contains('wlanpi')
          ? TransportPlatform.wlanPi
          : TransportPlatform.web;
    }
    if (Platform.isMacOS) return TransportPlatform.macos;
    if (Platform.isWindows) return TransportPlatform.windows;
    if (Platform.isLinux) return TransportPlatform.linux;
    if (Platform.isIOS) return TransportPlatform.ios;
    if (Platform.isAndroid) return TransportPlatform.android;
    return TransportPlatform.macos;
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    final List<TransportOption> rows = buildTransportOptions(
      platform: _platform,
      scope: TransportScope.internet,
      links: table.links,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Which path a test would take',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary)),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'For a test that reaches the internet. A local-network test can '
            'sometimes be pinned where an internet test cannot.',
            style: TextStyle(fontSize: 13, color: c.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final TransportOption o in rows) ...<Widget>[
            _ChooserRow(option: o),
            const SizedBox(height: AppSpacing.xxs),
          ],
        ],
      ),
    );
  }
}

class _ChooserRow extends StatelessWidget {
  const _ChooserRow({required this.option});
  final TransportOption option;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    final (Color tone, String badge) = switch (option.state) {
      TransportState.active => (c.statusSuccess, 'IN USE'),
      TransportState.selectable => (c.textPrimary, 'AVAILABLE'),
      TransportState.presentUntested => (c.statusWarning, 'NOT TESTED'),
      TransportState.presentNotSelectable => (c.textTertiary, 'CANNOT PIN'),
      TransportState.presentNoLink => (c.textTertiary, 'NO LINK'),
      TransportState.absent => (c.textTertiary, 'NOT PRESENT'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 92,
                child: Text(option.kind.label,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tone)),
              ),
              _Chip(label: badge, tone: tone),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 92, top: 2),
            child: Text(option.reason,
                style: TextStyle(fontSize: 13, color: c.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.carrying, required this.table});

  final LinkInfo? carrying;
  final LinkTable table;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    final LinkInfo? l = carrying;

    final String head = l == null
        ? 'No single link is carrying traffic'
        : '${_kindLabel(l.kind)} is carrying traffic';
    final String sub = l == null
        ? 'Nothing claims the default route, and more than one interface could '
            'qualify. That is a real state, not an error, and the app will not '
            'pick one for you.'
        : '${l.name}'
            '${l.speedMbps != null ? ' at ${_speed(l.speedMbps!)}' : ''}'
            '${l.duplex != null ? ', ${l.duplex} duplex' : ''}'
            '${table.defaultGatewayV4 != null ? ', via ${table.defaultGatewayV4}' : ''}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: l == null ? c.statusWarning : c.statusSuccess,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The verdict is the largest element. Same rule Keith earned on the
          // join prototype: a result a user has to read carefully is a result
          // they will misread.
          Text(
            head,
            style: TextStyle(
              fontSize: 24,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: l == null ? c.statusWarning : c.statusSuccess,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(sub, style: TextStyle(fontSize: 15, color: c.textSecondary)),
        ],
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.link});

  final LinkInfo link;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    final bool up = link.carrier == true;
    final List<LinkAddress> real = link.addresses
        .where((LinkAddress a) => !a.isLinkLocal)
        .toList(growable: false);
    final bool apipa =
        link.addresses.any((LinkAddress a) => a.isIPv4 && a.isLinkLocal);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                link.name,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: up ? c.textPrimary : c.textTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _Chip(label: _kindLabel(link.kind), tone: c.textSecondary),
              if (link.isDefaultRouteV4) ...<Widget>[
                const SizedBox(width: AppSpacing.xxs),
                _Chip(label: 'DEFAULT ROUTE', tone: c.statusSuccess),
              ],
              const Spacer(),
              _Chip(
                label: up ? 'LINK UP' : 'NO LINK',
                tone: up ? c.statusSuccess : c.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // Speed and duplex ONLY when there is a carrier. A negotiated rate
          // printed beside a dead port is a true fact in a place that makes it
          // a lie.
          if (up && link.speedMbps != null)
            _Row(label: 'Speed', value: _speed(link.speedMbps!))
          else if (up)
            _Row(
              label: 'Speed',
              value: 'not reported',
              muted: true,
            ),
          if (up && link.duplex != null)
            _Row(label: 'Duplex', value: link.duplex!),
          if (link.mac != null) _Row(label: 'MAC', value: link.mac!),
          if (link.driver != null) _Row(label: 'Driver', value: link.driver!),
          if (link.mtu != null) _Row(label: 'MTU', value: '${link.mtu}'),

          for (final LinkAddress a in real)
            _Row(
              label: a.isIPv4 ? 'IPv4' : 'IPv6',
              value: a.prefixLength == null
                  ? a.address
                  : '${a.address}/${a.prefixLength}',
            ),

          // An APIPA address is a DIAGNOSIS, not an address.
          if (apipa)
            _Note(
              text: 'This interface has a 169.254 address, which means the '
                  'link came up and DHCP never answered. That is a finding, '
                  'not an address.',
              tone: c.statusWarning,
            ),

          if (!up)
            _Note(
              text: link.kind == LinkKind.wired
                  ? 'Present with no link. A cable into a dead switch looks '
                      'exactly like no cable at all, so check both ends.'
                  : link.kind == LinkKind.wifi
                      ? 'Present but not associated to a network.'
                      : 'Present with no carrier.',
              tone: c.textTertiary,
            ),

          if (up && real.isEmpty && !apipa)
            _Note(
              text: 'The link is up but has no address, so nothing can be sent '
                  'over it yet.',
              tone: c.statusWarning,
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.muted = false});
  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(label,
                style: TextStyle(fontSize: 14, color: c.textTertiary)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                color: muted ? c.textTertiary : c.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.tone});
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: tone.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: tone),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.tone});
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(text, style: TextStyle(fontSize: 13.5, color: tone)),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.reason, required this.onRetry});
  final String reason;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('No link table here',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(reason,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: c.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(onPressed: onRetry, child: const Text('Check again')),
          ],
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({this.source});
  final String? source;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    return Text(
      source == null
          ? ''
          : 'Read from $source. Speed and duplex are shown only where the '
              'system reports them for a link that is actually up.',
      style: TextStyle(fontSize: 12.5, color: c.textTertiary),
    );
  }
}

String _kindLabel(LinkKind k) => switch (k) {
      LinkKind.wired => 'Ethernet',
      LinkKind.wifi => 'Wi-Fi',
      LinkKind.monitor => 'Monitor',
      LinkKind.virtual => 'Virtual',
      LinkKind.loopback => 'Loopback',
      LinkKind.other => 'Other',
    };

String _speed(int mbps) =>
    mbps >= 1000 && mbps % 1000 == 0 ? '${mbps ~/ 1000} Gbps' : '$mbps Mbps';
