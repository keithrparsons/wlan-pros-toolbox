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


import 'dart:io' show InternetAddress;

import 'package:flutter/material.dart';

import '../../../services/network/link_bind_probe.dart';
import '../../../services/network/link_info.dart';
import '../../../services/network/link_table_service.dart';
import '../../../services/network/transport_chooser.dart';
import '../../../services/network/transport_preference.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

class LinkInfoScreen extends StatefulWidget {
  const LinkInfoScreen({super.key, this.service, this.preference, this.probe});

  final LinkTableService? service;

  /// Injectable so a widget test can drive the chooser without a platform
  /// channel. Null means the real one.
  final TransportPreference? preference;

  /// Injectable so a widget test can settle "Try it now" without opening a
  /// socket. Null means the real one.
  final LinkBindProbe? probe;

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
          _Chooser(
            table: t,
            preference: widget.preference,
            probe: widget.probe,
          ),
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
/// IT IS NO LONGER READ-ONLY. Keith looked at three laid-out candidates on
/// 2026-09-04 and picked this one: **the card that already explains the paths
/// becomes the control that chooses between them.** The two rejected layouts
/// both moved the control away from the explanation - into the verdict card, or
/// into a card of its own above it - and both were rejected for the same
/// reason: they put a disabled row on one part of the screen and the sentence
/// explaining it on another. **That is the greyed-without-saying-why defect
/// with a scroll bar in the middle of it**, and it is precisely what this file
/// was written to prevent. Keeping choice and reason in one row is the whole
/// design, not a layout preference.
///
/// THREE THINGS THIS WIDGET REFUSES TO DO:
///
///  * It never shows a selected row without saying whether the choice is being
///    honoured. A stale preference gets a banner, because a radio button that
///    is filled in while the traffic goes elsewhere is a lie the user cannot
///    see. [ResolvedTransport.isStale] exists for exactly this.
///  * It never silently swallows a failed write. shared_preferences can fail,
///    and a selected radio that is gone next launch is worse than a refusal.
///  * It never leaves a row saying NOT TESTED with no way to test it. That was
///    the third thing Keith ruled on 2026-09-04, and it is the one that changes
///    behaviour rather than layout - see [_probe].
class _Chooser extends StatefulWidget {
  const _Chooser({required this.table, this.preference, this.probe});

  final LinkTable table;
  final TransportPreference? preference;
  final LinkBindProbe? probe;

  @override
  State<_Chooser> createState() => _ChooserState();
}

class _ChooserState extends State<_Chooser> {
  late final TransportPreference _pref =
      widget.preference ?? TransportPreference();
  late final LinkBindProbe _probe = widget.probe ?? LinkBindProbe();

  TransportKind? _chosen;
  bool _loaded = false;

  /// Interface name -> did a bound connection get through. Populated ONLY by
  /// [_probe]; an interface absent from this map has not been tested, which the
  /// rows render differently from one that was tested and failed.
  ///
  /// DELIBERATELY NOT PERSISTED. The answer belongs to how this machine is
  /// wired RIGHT NOW - a different dock, a different network, a cable moved,
  /// and it changes. A remembered "it worked" that is quietly six weeks old is
  /// the same class of claim as a negotiated speed printed beside a dead port.
  final Map<String, bool> _probed = <String, bool>{};

  /// The kind currently being probed, so its row can say so rather than
  /// appearing to do nothing for up to five seconds.
  TransportKind? _probing;

  /// Rows whose long reason the user has opened.
  final Set<TransportKind> _expanded = <TransportKind>{};

  /// Set when a write did not land. The UI says so; see [_choose].
  bool _writeFailed = false;

  TransportPlatform get _platform =>
      currentTransportPlatform(tableSource: widget.table.source);

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final TransportKind? k = await _pref.read();
    if (!mounted) return;
    setState(() {
      _chosen = k;
      _loaded = true;
    });
  }

  /// Persist a choice, or clear it when [kind] is null ("let the system
  /// decide").
  ///
  /// THE OPTIMISTIC UPDATE IS DELIBERATE AND SO IS THE ROLLBACK. The radio
  /// moves at once because a control that lags a tap feels broken, but a write
  /// that did not land puts the old value back and says so. Showing a selected
  /// radio for a preference that will be gone next launch is the failure this
  /// guards - and [TransportPreference.write] returns a bool precisely so a
  /// caller can tell the difference.
  Future<void> _choose(TransportKind? kind) async {
    final TransportKind? previous = _chosen;
    setState(() {
      _chosen = kind;
      _writeFailed = false;
    });
    final bool ok = await _pref.write(kind);
    if (!mounted || ok) return;
    setState(() {
      _chosen = previous;
      _writeFailed = true;
    });
  }

  /// Run one bound connection from [option]'s interface and record what
  /// happened.
  ///
  /// KEITH RULED THIS ON 2026-09-04, and it was not one of the two questions he
  /// was asked - it was the one underneath them. On macOS and Windows an
  /// internet-scope test is [SelectSupport.mustProbe]: the answer belongs to
  /// the machine, not the platform, so the honest state is NOT TESTED. The
  /// alternative considered was leaving that row greyed. **It was rejected
  /// because nothing else in the app would ever test it** - there is no other
  /// trigger - so the row would have read NOT TESTED forever, which is a dead
  /// end that looks like a bug.
  ///
  /// Both outcome strings already existed in `_supportRow` for
  /// `probed[name] == true` and `== false`, and the `probed` map has been a
  /// parameter of [buildTransportOptions] since it was written. **Nothing in
  /// the app populated it until this method.**
  ///
  /// cloudflare.com:443 is the destination because it is the first host in
  /// [DnsProbeService]'s own stable list, and the scope being tested here is
  /// the internet one. Probing a local address would answer a different
  /// question than the row is asking.
  Future<void> _runProbe(TransportOption option) async {
    final LinkInfo? link = option.link;
    if (link == null || _probing != null) return;

    LinkAddress? v4;
    for (final LinkAddress a in link.addresses) {
      if (a.isIPv4 && !a.isLinkLocal) {
        v4 = a;
        break;
      }
    }
    // No global v4 address means there is nothing to bind to. The row already
    // says why in that case, so this is a guard rather than a state.
    if (v4 == null) return;

    setState(() => _probing = option.kind);
    Map<String, bool> result = const <String, bool>{};
    try {
      result = await _probe.probe(
        sourceAddresses: <String, InternetAddress>{
          link.name: InternetAddress(v4.address)
        },
        host: 'cloudflare.com',
        port: 443,
      );
    } on Object {
      // LinkBindProbe does not throw, but an invalid address literal from a
      // link table we did not write could. A probe that could not run leaves
      // the row UNTESTED, which is true. It must never record a false.
      result = const <String, bool>{};
    }
    if (!mounted) return;
    setState(() {
      _probed.addAll(result);
      _probing = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    final List<TransportOption> rows = buildTransportOptions(
      platform: _platform,
      scope: TransportScope.internet,
      links: widget.table.links,
      probed: _probed,
    );

    // Can anything be chosen on this device at all? On iOS and on the web every
    // row is a refusal, and offering radio buttons that cannot do anything
    // would be the control-that-does-not-work defect in its purest form. The
    // same screen is therefore a CHOOSER on a Mac and a REPORT on a phone, and
    // that falls out of the capability table rather than a special case anyone
    // has to remember.
    final bool anyChoosable = rows.any((TransportOption o) => o.isChoosable);
    final bool anyProbable = rows.any(
        (TransportOption o) => o.state == TransportState.presentUntested);
    final bool interactive = _loaded && (anyChoosable || anyProbable);

    final ResolvedTransport resolved = resolveTransport(
      chosen: _chosen,
      options: rows,
      activeLink: selectDefaultLink(widget.table.links),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: interactive ? c.primary : c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(interactive ? 'Which path the tools use' : 'Which path a test would take',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary)),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            interactive
                ? 'One choice. Every tool in the app honours it.'
                : 'For a test that reaches the internet. A local-network test '
                    'can sometimes be pinned where an internet test cannot.',
            style: TextStyle(fontSize: 13, color: c.textTertiary),
          ),
          if (resolved.isStale) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _ChooserBanner(
              tone: c.statusWarning,
              text: _staleText(resolved),
            ),
          ],
          if (_writeFailed) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _ChooserBanner(
              tone: c.statusDanger,
              text: 'That choice could not be saved, so it has been put back. '
                  'The tools are still following the system.',
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          if (interactive)
            _PickRow(
              label: 'Let the system decide',
              shortReason: _systemSubtitle(resolved),
              selected: _chosen == null,
              enabled: true,
              onTap: () => _choose(null),
            ),
          for (final TransportOption o in rows) ...<Widget>[
            if (interactive)
              _PickRow(
                label: o.kind.label,
                badge: _badgeFor(o.state),
                badgeTone: _toneFor(o.state, c),
                shortReason: o.shortReason,
                longReason: o.reason,
                expanded: _expanded.contains(o.kind),
                onToggleReason: () => setState(() {
                  if (!_expanded.remove(o.kind)) _expanded.add(o.kind);
                }),
                selected: _chosen == o.kind,
                enabled: o.isChoosable,
                onTap: o.isChoosable ? () => _choose(o.kind) : null,
                onProbe: o.state == TransportState.presentUntested
                    ? () => _runProbe(o)
                    : null,
                probing: _probing == o.kind,
              )
            else
              _ChooserRow(option: o),
            const SizedBox(height: AppSpacing.xxs),
          ],
        ],
      ),
    );
  }

  /// What the "let the system decide" row says underneath itself.
  ///
  /// It reports the CURRENT default route rather than a generic sentence,
  /// because "the system decides" is not information and "right now that is
  /// Ethernet, en5" is.
  String _systemSubtitle(ResolvedTransport resolved) {
    final LinkInfo? active = selectDefaultLink(widget.table.links);
    if (active == null) {
      return 'The routing table picks. Nothing currently holds the default '
          'route.';
    }
    final TransportKind? kind = transportKindOf(active);
    final String named = kind == null ? active.name : '${kind.label}, ${active.name}';
    return 'The routing table picks. Right now that is $named.';
  }

  /// The stale-choice sentence. Every branch names BOTH what was chosen and
  /// what is actually carrying the traffic, because a banner that says only
  /// "unavailable" leaves the user not knowing what they are measuring.
  String _staleText(ResolvedTransport resolved) {
    final String want = resolved.chosen?.label ?? 'Your choice';
    final LinkInfo? on = resolved.link;
    final TransportKind? onKind = on == null ? null : transportKindOf(on);
    final String running = onKind?.label ?? on?.name ?? 'the system default';
    return switch (resolved.resolution) {
      TransportResolution.chosenUnavailable =>
        'You chose $want and it is not available. Tests are running over '
            '$running until it is back.',
      TransportResolution.chosenNotSelectable =>
        'You chose $want, and this device will not move a test onto it. Tests '
            'are running over $running.',
      TransportResolution.chosenUntested =>
        'You chose $want, and whether a test can be pinned to it has not been '
            'checked on this machine. Tests are running over $running until it '
            'is.',
      _ => 'Tests are running over $running.',
    };
  }
}

String _badgeFor(TransportState s) => switch (s) {
      TransportState.active => 'IN USE',
      TransportState.selectable => 'AVAILABLE',
      TransportState.presentUntested => 'NOT TESTED',
      TransportState.presentNotSelectable => 'CANNOT PIN',
      TransportState.presentNoLink => 'NO LINK',
      TransportState.absent => 'NOT PRESENT',
    };

Color _toneFor(TransportState s, AppColorScheme c) => switch (s) {
      TransportState.active => c.statusSuccess,
      TransportState.selectable => c.textPrimary,
      TransportState.presentUntested => c.statusWarning,
      TransportState.presentNotSelectable => c.textTertiary,
      TransportState.presentNoLink => c.textTertiary,
      TransportState.absent => c.textTertiary,
    };

/// A selectable transport row.
///
/// THE SHORT REASON IS ALWAYS RENDERED. Keith ruled on 2026-09-04 between three
/// treatments, and the one he rejected outright was hiding the whole
/// explanation behind a "Why?" link: a person who does not tap sees greyed rows
/// and no explanation, which is the exact reading this feature exists to
/// prevent. So [shortReason] is unconditional and [longReason] is the extra.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.shortReason,
    required this.selected,
    required this.enabled,
    this.badge,
    this.badgeTone,
    this.longReason,
    this.expanded = false,
    this.onToggleReason,
    this.onTap,
    this.onProbe,
    this.probing = false,
  });

  final String label;
  final String shortReason;
  final String? longReason;
  final bool expanded;
  final VoidCallback? onToggleReason;
  final bool selected;
  final bool enabled;
  final String? badge;
  final Color? badgeTone;
  final VoidCallback? onTap;
  final VoidCallback? onProbe;
  final bool probing;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    // A row that cannot be chosen is dimmed and outlined rather than removed.
    // It still carries its reason, and it still occupies the place a person
    // expects to find it.
    final Color bg = selected ? c.surface2 : c.surface0;
    final Color edge = selected
        ? c.primary
        : enabled
            ? c.border
            : c.borderStrong.withValues(alpha: 0.35);
    // The long form is only worth offering when it says more than the short
    // one. Identical strings would give the user a control that does nothing.
    final bool hasMore = longReason != null && longReason != shortReason;

    return Semantics(
      button: enabled,
      selected: selected,
      label: '$label. ${badge ?? ''} $shortReason',
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: edge),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs + 3, vertical: AppSpacing.xs + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Radio(selected: selected, enabled: enabled),
                  const SizedBox(width: AppSpacing.xs + 3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xxs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(label,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: enabled
                                        ? c.textPrimary
                                        : c.textDisabled)),
                            if (badge != null)
                              _Chip(
                                  label: badge!,
                                  tone: badgeTone ?? c.textTertiary),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          expanded && hasMore ? longReason! : shortReason,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: enabled ? c.textSecondary : c.textTertiary),
                        ),
                        if (hasMore)
                          GestureDetector(
                            onTap: onToggleReason,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(expanded ? 'Less' : 'More',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: c.primary)),
                            ),
                          ),
                        if (onProbe != null) ...<Widget>[
                          const SizedBox(height: AppSpacing.xs),
                          _TryItNow(onPressed: probing ? null : onProbe,
                              busy: probing),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Try it now" affordance on a NOT TESTED row.
///
/// It says what it will do rather than naming a verb with no object. "Try it
/// now" on its own could mean "try the network"; the busy state names the one
/// action actually taken, which is a single connection.
class _TryItNow extends StatelessWidget {
  const _TryItNow({required this.onPressed, required this.busy});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    if (busy) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text('Trying one connection...',
              style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
        ],
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: c.primary,
        side: BorderSide(color: c.primary),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
      child: const Text('Try it now',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    final Color edge = selected
        ? c.primary
        : enabled
            ? c.borderStrong
            : c.textDisabled;
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: edge, width: 2),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: c.primary),
              ),
            )
          : null,
    );
  }
}

class _ChooserBanner extends StatelessWidget {
  const _ChooserBanner({required this.tone, required this.text});

  final Color tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs + 4, vertical: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: tone),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 13, height: 1.45, color: c.textSecondary)),
    );
  }
}

/// The READ-ONLY row, still used on every platform that cannot choose.
///
/// iOS and the web keep exactly the screen they shipped with: both scopes are
/// [SelectSupport.no] there, so no row is choosable and none is probable. **A
/// radio button that cannot do anything is worse than no radio button**, so the
/// card stays a report. This is the part of the original design that the
/// 2026-09-04 ruling did not change.
class _ChooserRow extends StatelessWidget {
  const _ChooserRow({required this.option});
  final TransportOption option;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    final Color tone = _toneFor(option.state, c);
    final String badge = _badgeFor(option.state);

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
