// Join a network from the WLAN Pi - the screen the endpoints have been waiting
// for.
//
// POST /toolboxapi/wifi-connect and /wifi-disconnect shipped in v0.2.0 and
// NOTHING in lib/ called either one. A throwaway HTML prototype was deployed to
// the R4 on 2026-08-29 and Keith drove it, and four rounds of feedback in ten
// minutes produced five requirements that this screen implements. Every one of
// them came from a real user failing to do the obvious thing, so they are
// requirements and not preferences:
//
//   1. THE ACTION PANEL GOES ABOVE THE LIST. Keith: "I can't find where to
//      ENTER the PSK?" ... "Found it, it was at the bottom of the page." The
//      list is as long as the RF environment is busy, 16 rows in a cabin and 60
//      in a conference hall, so anything under it is off-screen.
//   2. AN ABSENT CONTROL MUST SAY WHY IT IS ABSENT. An open network correctly
//      showed no passphrase field and the absence read as a broken page.
//      Hiding something silently is itself a message, and the message is "this
//      is broken".
//   3. THE VERDICT IS THE LARGEST ELEMENT. "The 'connected' could be bolder,
//      bigger, Green COlored - something to stand out." A result a user has to
//      read carefully is a result they will misread.
//   4. SSID AND BSSID LEAD. "Could we also add BSSID you are associated at the
//      same time?" On a multi-AP network the BSSID IS the answer: it says which
//      radio you landed on.
//   5. THE RESULT SCROLLS ITSELF INTO VIEW. Same class of bug as requirement 1.
//
// THE PATTERN ACROSS ALL FIVE, which is worth more than the list: every one is
// a TRUE THING RENDERED WHERE OR HOW NOBODY WOULD SEE IT. Nothing was factually
// wrong. Correct and unfindable is indistinguishable from broken.
//
// AND A SIXTH, ruled by Keith 2026-08-30 and implemented in the pure layer:
// dedupe by SSID *and band*. Keying on SSID alone let the louder 2.4 GHz BSS
// hide the 5 GHz one, which also hid a different security type.
//
// WHY THIS IS SAFE TO EXPOSE AT ALL. Reconfiguring Wi-Fi over the Wi-Fi you are
// using drops your own session mid-request, so you never learn whether it
// worked. Keith ruled on 2026-08-26 that the Pi is reached over ETHERNET for
// this round, and that ruling is what makes this a small screen instead of a
// hotspot-plus-auto-revert dance.

import 'package:flutter/material.dart';

import '../../../services/network/join_network_list.dart';
import '../../../services/network/pi_backend.dart';
import '../../../services/network/pi_backend_client.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../labeled_field.dart';

class JoinNetworkScreen extends StatefulWidget {
  const JoinNetworkScreen({super.key, this.client});

  final PiBackendClient? client;

  @override
  State<JoinNetworkScreen> createState() => _JoinNetworkScreenState();
}

class _JoinNetworkScreenState extends State<JoinNetworkScreen> {
  late final PiBackendClient _client = widget.client ?? PiBackendClient();
  final TextEditingController _psk = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _resultKey = GlobalKey();

  List<PiScanInterface> _radios = const <PiScanInterface>[];
  String? _radio;

  bool _scanning = false;
  String? _scanError;
  List<JoinCandidate> _candidates = const <JoinCandidate>[];
  JoinCandidate? _selected;

  bool _busy = false;
  PiJoinResult? _result;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _psk.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final List<PiScanInterface> radios = await _client.scanInterfaces();
      if (!mounted) return;
      setState(() {
        _radios = radios;
        _radio = radios.isEmpty ? null : radios.first.name;
      });
    } on Object {
      // A Pi that will not list its radios still scans on the default one.
    }
    await _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    try {
      final List<PiScanNet> nets =
          await _client.scan(interface: _radio ?? 'wlan0');
      if (!mounted) return;
      final List<JoinCandidate> rows = buildJoinCandidates(nets);
      setState(() {
        _candidates = rows;
        _scanning = false;
        // Keep the selection across a rescan when the same (SSID, band) is
        // still there. A list that clears the user's choice on every refresh
        // makes the refresh button hostile.
        final JoinCandidate? keep = _selected == null
            ? null
            : rows.where((JoinCandidate c) =>
                c.ssid == _selected!.ssid && c.band == _selected!.band).firstOrNull;
        _selected = keep;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scanError = e is PiBackendException ? e.toString() : 'The scan failed.';
      });
    }
  }

  Future<void> _join() async {
    final JoinCandidate? c = _selected;
    if (c == null || c.ssid == null) return;
    setState(() {
      _busy = true;
      _actionError = null;
      _result = null;
    });
    try {
      final PiJoinResult r = await _client.wifiConnect(
        ssid: c.ssid!,
        security: c.security,
        psk: c.security == PiJoinSecurity.open ? null : _psk.text,
        interface: _radio,
      );
      if (!mounted) return;
      setState(() {
        _result = r;
        _busy = false;
      });
      _scrollToResult();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _actionError = e is PiBackendException
            ? e.toString().replaceFirst('PiBackendException: ', '')
            : 'The join could not be sent to the Pi.';
      });
      _scrollToResult();
    }
  }

  Future<void> _disconnect() async {
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final PiJoinResult r = await _client.wifiDisconnect(interface: _radio);
      if (!mounted) return;
      setState(() {
        _result = r;
        _busy = false;
      });
      _scrollToResult();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _actionError = 'Disconnect failed: $e';
      });
    }
  }

  /// REQUIREMENT 5. A result rendered below the fold is the same defect as an
  /// action panel below the fold.
  void _scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? ctx = _resultKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 250),
          alignment: 0.1,
          curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final double edge = MediaQuery.sizeOf(context).width < 600
        ? AppSpacing.sm
        : AppSpacing.md;

    // NO PI, NO SCREEN (Keith, 2026-09-06, on Windows). This tool drives a WLAN
    // Pi's OWN radio through PiBackendClient, which only answers when a Pi is
    // serving the app. Off a Pi there was no guard at all: the screen built,
    // immediately scanned, and failed in front of the user.
    //
    // The tile already carries a badge, but a badge is not a gate -- the row
    // stays tappable, so the honest explanation has to live HERE as well. It
    // says what the tool needs rather than that something went wrong, because
    // nothing did: this machine simply is not a WLAN Pi.
    if (widget.client == null && !PiBackend.available) {
      return Scaffold(
        appBar: AppBar(title: const Text('Join a Network')),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(edge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Coming to this device',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Join a Network points a radio at a Wi-Fi network. Today only '
                  'the WLAN Pi edition has it wired up, and there it joins the '
                  'Pi\'s own radio rather than this one.\n\n'
                  'Joining THIS device, picked straight from the nearby-network '
                  'scan, is being built. Until then, open the Toolbox from a '
                  'WLAN Pi in your browser and the tool works there. Every '
                  'other tool works normally here.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join a Network'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Scan again',
            onPressed: _scanning || _busy ? null : _scan,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(edge, AppSpacing.sm, edge, edge * 2),
          children: <Widget>[
            if (_radios.length > 1) ...<Widget>[
              _RadioPicker(
                radios: _radios,
                selected: _radio!,
                enabled: !_busy && !_scanning,
                onChanged: (String v) {
                  setState(() => _radio = v);
                  _scan();
                },
              ),
              const SizedBox(height: AppSpacing.xs),
            ],

            // REQUIREMENT 1: the action panel is ABOVE the list, always.
            _ActionPanel(
              selected: _selected,
              psk: _psk,
              busy: _busy,
              error: _actionError,
              onJoin: _join,
              onDisconnect: _disconnect,
            ),

            if (_result != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              _ResultCard(key: _resultKey, result: _result!),
            ],

            const SizedBox(height: AppSpacing.sm),
            _ListHeader(
              count: _candidates.length,
              scanning: _scanning,
              radio: _radio,
            ),
            if (_scanError != null) _Banner(text: _scanError!, danger: true),
            for (final JoinCandidate c in _candidates)
              _NetworkRow(
                candidate: c,
                selected: identical(c, _selected) ||
                    (_selected != null &&
                        c.ssid == _selected!.ssid &&
                        c.band == _selected!.band),
                onTap: _busy
                    ? null
                    : () => setState(() {
                          _selected = c;
                          _psk.clear();
                          _result = null;
                          _actionError = null;
                        }),
              ),
            if (!_scanning && _candidates.isEmpty && _scanError == null)
              const _Banner(
                text: 'The scan finished and found no networks. That is a real '
                    'answer, not an error: check the radio is not in monitor '
                    'mode and that there is something on the air here.',
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Which radio associates. Keith on the Nearby AP Scan version of this control:
/// "I REALLY LIKE the NIC 'chooser' ... The ability to see which NIC is used
/// for scanning, which is used for association."
class _RadioPicker extends StatelessWidget {
  const _RadioPicker({
    required this.radios,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final List<PiScanInterface> radios;
  final String selected;
  final bool enabled;
  final ValueChanged<String> onChanged;

  /// A dropdown shows ONE name and hides the rest behind a tap. On the standard
  /// two-radio WLAN Pi that is the difference between "here are your radios"
  /// and "here is your radio".
  ///
  /// KEITH, 2026-09-04, on an R4 with two Panda (mt7921u) NICs:
  /// *"On the WLAN Pi it only offered me a single NIC, the WLAN0 to choose
  /// from. But this R4 has two of the same PANDA NICs plugged in."*
  ///
  /// **BOTH RADIOS WERE THERE THE WHOLE TIME.** The Pi's own access log shows
  /// `GET /toolboxapi/scan-interfaces 200 96` returning `wlan0` AND `wlan1`, and
  /// this widget was rendering with `radios.length == 2`. Nothing failed. The
  /// control simply displayed `wlan0 (mt7921u)` and said nothing about the
  /// second, and a user reading it concluded the Pi had one radio.
  ///
  /// **That is a real defect even though every layer below it was correct**, and
  /// it is the same failure as the rest of this session: the app knew something
  /// and did not say it. Two radios is the NORMAL WLAN Pi build, not an edge
  /// case, and choosing between them is most of the point of the tool.
  ///
  /// So: two or three radios render as a [SegmentedButton] with every name
  /// visible at once, matching the sort control on Nearby AP Scan. Four or more
  /// falls back to the dropdown, because segments stop fitting.
  static const int _maxSegments = 3;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    final bool asSegments =
        radios.length > 1 && radios.length <= _maxSegments;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LabeledField(
            label: 'Radio that scans and joins',
            semanticLabel: 'Radio that scans and joins',
            field: asSegments
                ? SegmentedButton<String>(
                    segments: radios
                        .map((PiScanInterface i) => ButtonSegment<String>(
                              value: i.name,
                              label: Text(i.name),
                              tooltip: i.label,
                            ))
                        .toList(growable: false),
                    selected: <String>{selected},
                    showSelectedIcon: false,
                    onSelectionChanged: enabled
                        ? (Set<String> s) => onChanged(s.first)
                        : null,
                  )
                : AppSelect<String>(
                    value: selected,
                    semanticLabel: 'Radio that scans and joins',
                    enabled: enabled,
                    items: radios
                        .map((PiScanInterface i) => (i.name, i.label))
                        .toList(growable: false),
                    onChanged: onChanged,
                  ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            radios.length > 1
                // Name the count, so a two-radio Pi never again reads as one.
                ? 'This Pi has ${radios.length} radios. The one you pick does '
                    'both the scanning and the joining; the other stays free '
                    'for scanning or capture, which is usually what you want.'
                : 'This radio does both. On a two-radio Pi the other one stays '
                    'free for scanning or capture, which is usually what you '
                    'want.',
            style: TextStyle(fontSize: 13, color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.selected,
    required this.psk,
    required this.busy,
    required this.error,
    required this.onJoin,
    required this.onDisconnect,
  });

  final JoinCandidate? selected;
  final TextEditingController psk;
  final bool busy;
  final String? error;
  final VoidCallback onJoin;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    final JoinCandidate? s = selected;

    if (s == null) {
      return _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Pick a network below',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary)),
            const SizedBox(height: 3),
            Text(
              'Everything you need to join it appears here, above the list, so '
              'you never have to scroll past sixty rows to find it.',
              style: TextStyle(fontSize: 13.5, color: c.textSecondary),
            ),
          ],
        ),
      );
    }

    final bool needsPsk = s.security == PiJoinSecurity.wpa2Psk ||
        s.security == PiJoinSecurity.wpa3Psk;
    final bool canJoin = !busy &&
        s.ssid != null &&
        s.security != PiJoinSecurity.unsupported &&
        (!needsPsk || psk.text.isNotEmpty);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(s.ssid ?? 'Hidden network',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary)),
          Text(
            '${s.bandLabel} · ${_securityLabel(s.security)}'
            '${s.bssCount > 1 ? " · ${s.bssCount} access points" : ""}',
            style: TextStyle(fontSize: 13.5, color: c.textSecondary),
          ),
          if (s.bssid != null)
            Text('Strongest: ${s.bssid}  ${s.signalDbm} dBm',
                style: TextStyle(fontSize: 13, color: c.textTertiary)),
          const SizedBox(height: AppSpacing.xs),

          if (needsPsk)
            LabeledField(
              label: 'Passphrase',
              semanticLabel: 'Passphrase',
              field: TextField(
                controller: psk,
                obscureText: true,
                enabled: !busy,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                    hintText: '8 to 63 characters, or a 64-character hex key'),
                onChanged: (_) => (context as Element).markNeedsBuild(),
              ),
            )
          else
            // REQUIREMENT 2. An absent control that explains itself. This
            // string is never empty for a non-PSK network.
            _Banner(
              text: absentPassphraseReason(s.security),
              danger: s.security == PiJoinSecurity.unsupported,
            ),

          if (s.ssid == null)
            const _Banner(
              text: 'This network does not broadcast its name, so it cannot be '
                  'joined by picking it from a list. Nothing here can be sent '
                  'without an SSID to send.',
              danger: true,
            ),

          if (error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _Banner(text: error!, danger: true),
          ],

          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              FilledButton(
                onPressed: canJoin ? onJoin : null,
                child: Text(busy ? 'Working...' : 'Join'),
              ),
              const SizedBox(width: AppSpacing.xs),
              TextButton(
                onPressed: busy ? null : onDisconnect,
                child: const Text('Disconnect'),
              ),
            ],
          ),
          if (busy)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'The Pi waits up to 25 seconds and will not report success off '
                'a stale association, so a real failure takes that long to be '
                'certain of.',
                style: TextStyle(fontSize: 12.5, color: c.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

/// REQUIREMENT 3 and 4: the verdict is the biggest thing on screen, and SSID
/// and BSSID lead above any detail.
class _ResultCard extends StatelessWidget {
  const _ResultCard({super.key, required this.result});

  final PiJoinResult result;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    final bool ok = result.joinedRequested;
    final PiWifiLink l = result.link;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
            color: ok ? c.statusSuccess : c.statusDanger, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            ok ? 'Connected' : 'Not connected',
            style: TextStyle(
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: ok ? c.statusSuccess : c.statusDanger,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),

          // SSID and BSSID lead. On a multi-AP network the BSSID is the answer.
          if (l.ssid != null)
            Text(l.ssid!,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary)),
          if (l.bssid != null)
            Text(l.bssid!,
                style: TextStyle(
                    fontSize: 15,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures()
                    ],
                    color: c.textSecondary)),

          if (!ok && l.reason != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(l.reason!,
                style: TextStyle(fontSize: 14.5, color: c.textSecondary)),
          ],

          if (ok) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _Detail(label: 'Interface', value: l.interface),
            if (l.freqMhz != null)
              _Detail(
                  label: 'Channel',
                  value: '${l.channel ?? "?"}  (${l.freqMhz} MHz'
                      '${l.widthMhz != null ? ", ${l.widthMhz} MHz wide" : ""})'),
            if (l.signalDbm != null)
              _Detail(label: 'Signal', value: '${l.signalDbm} dBm'),
            if (l.phyMode != null) _Detail(label: 'Mode', value: l.phyMode!),
            if (l.txRateMbps != null)
              _Detail(label: 'Tx rate', value: '${l.txRateMbps} Mbps'),
          ],

          // THE TRANSPORT HONESTY. A normal install is plain HTTP with
          // authentication off, and the endpoint deliberately does not refuse
          // it, so the honesty has to live here.
          const SizedBox(height: AppSpacing.xs),
          Text(
            result.secureTransport
                ? 'The passphrase reached the Pi over TLS.'
                : 'The passphrase was sent over plain HTTP. That is the normal '
                    'bench default and it is fine on your own bench. On a '
                    'client network, use the hardened image build.',
            style: TextStyle(
                fontSize: 12.5,
                color: result.secureTransport ? c.textTertiary : c.statusWarning),
          ),
        ],
      ),
    );
  }
}

class _NetworkRow extends StatelessWidget {
  const _NetworkRow({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final JoinCandidate candidate;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    final JoinCandidate x = candidate;
    final bool blocked = x.security == PiJoinSecurity.unsupported;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Material(
        color: selected ? c.surface2 : c.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                  color: selected ? c.primary : c.border,
                  width: selected ? 1.5 : 1),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        x.ssid ?? 'Hidden network',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          fontStyle:
                              x.isHidden ? FontStyle.italic : FontStyle.normal,
                          color: blocked ? c.textTertiary : c.textPrimary,
                        ),
                      ),
                      Text(
                        '${x.bandLabel} · ${_securityLabel(x.security)}'
                        '${x.bssCount > 1 ? " · ${x.bssCount} APs" : ""}',
                        style:
                            TextStyle(fontSize: 12.5, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${x.signalDbm} dBm',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures()
                    ],
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader(
      {required this.count, required this.scanning, required this.radio});
  final int count;
  final bool scanning;
  final String? radio;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Text(
            scanning
                ? 'Scanning...'
                : '$count network${count == 1 ? "" : "s"}'
                    '${radio == null ? "" : " on $radio"}',
            style: TextStyle(
                fontSize: 12.5,
                letterSpacing: 0.9,
                fontWeight: FontWeight.w700,
                color: c.textTertiary),
          ),
          if (scanning) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
              width: 84,
              child: Text(label,
                  style: TextStyle(fontSize: 13.5, color: c.textTertiary))),
          Expanded(
              child: Text(value,
                  style: TextStyle(fontSize: 13.5, color: c.textPrimary))),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.danger = false});
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.xxs),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs + 2, vertical: 10),
      decoration: BoxDecoration(
        color: danger ? c.statusDangerFill : c.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border:
            Border.all(color: danger ? c.statusDanger : c.border),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 13.5,
              color: danger ? c.textPrimary : c.textSecondary)),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }
}

String _securityLabel(PiJoinSecurity s) => switch (s) {
      PiJoinSecurity.open => 'Open',
      PiJoinSecurity.wpa2Psk => 'WPA2-PSK',
      PiJoinSecurity.wpa3Psk => 'WPA3-SAE',
      PiJoinSecurity.unsupported => '802.1X / OWE',
    };
