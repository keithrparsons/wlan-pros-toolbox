// SPIKE-HSD-01 — LAN Discovery THROWAWAY debug screen.
//
// This screen exists ONLY to exercise the lan_discovery engine on real devices
// so Keith can run the three validation gates (iOS Local Network permission,
// macOS sandboxed scan, Android ACCESS_LOCAL_NETWORK timing). It is DELETED
// when the real LAN Discovery build ticket (TICKET-HSD-02) starts.
//
// DELIBERATELY NOT GL-003: no design tokens, no concept graphic, no Vera gate,
// no accessibility pass. Plain Material widgets, raw fields, a Scan button, and
// a progress line. The spec calls for exactly this and warns against
// over-polishing a throwaway.
//
// It is registered as a dev-only route (AppRoutes.lanDiscoveryDebug) reachable
// by Navigator.pushNamed — NOT surfaced in the tool catalog, so it never shows
// in the shipped home grid. Keith launches it from the debug entry described in
// the handoff notes.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../services/network/lan_discovery/lan_discovery_engine.dart';
import '../../../services/network/lan_discovery/lan_host.dart';

/// Throwaway debug UI for the SPIKE-HSD-01 LAN Discovery engine.
class LanDiscoveryDebugScreen extends StatefulWidget {
  const LanDiscoveryDebugScreen({super.key, this.engineFactory});

  /// Engine factory seam so tests can inject a fake engine. Null in production,
  /// where a real [LanDiscoveryEngine] (isolate connect-scan) is built.
  final LanDiscoveryEngine Function()? engineFactory;

  @override
  State<LanDiscoveryDebugScreen> createState() =>
      _LanDiscoveryDebugScreenState();
}

class _LanDiscoveryDebugScreenState extends State<LanDiscoveryDebugScreen> {
  bool _running = false;
  DiscoveryPhase _phase = DiscoveryPhase.idle;
  double _fraction = 0;
  String? _note;
  DiscoveryResult? _result;
  String? _error;

  Future<void> _scan() async {
    setState(() {
      _running = true;
      _phase = DiscoveryPhase.idle;
      _fraction = 0;
      _note = null;
      _result = null;
      _error = null;
    });

    final LanDiscoveryEngine engine =
        widget.engineFactory?.call() ?? LanDiscoveryEngine();

    try {
      await for (final DiscoveryProgress p in engine.run()) {
        if (!mounted) return;
        setState(() {
          _phase = p.phase;
          _fraction = p.fraction;
          if (p.note != null) _note = p.note;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _result = engine.lastResult;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LAN Discovery (spike debug)')),
      body: kIsWeb
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'The scan engine needs dart:io sockets, which the web build '
                  'does not provide. Run this on iOS, Android, macOS, or '
                  'Windows.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _body(),
    );
  }

  Widget _body() {
    final DiscoveryResult? r = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'Throwaway spike screen. Tap Scan to derive the local subnet, '
                'run a bounded TCP connect-scan in a background isolate, then '
                'enrich with reverse DNS, mDNS, and a device-type heuristic. '
                'No MAC / vendor — out of scope for this spike.',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _running ? null : _scan,
                child: Text(_running ? 'Scanning…' : 'Scan local network'),
              ),
              if (_running || _note != null) ...<Widget>[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _fraction == 0 ? null : _fraction,
                ),
                const SizedBox(height: 6),
                Text(
                  '${_phase.name}'
                  '${_note == null ? '' : ' — $_note'}'
                  '  (${(_fraction * 100).round()}%)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_running) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'Scanning the local subnet. A full /24 sweep can take 10 '
                    'to 20 seconds.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text('Error: $_error',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (r?.error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text('Could not scan: ${r!.error}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (r != null && r.error == null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Subnet ${r.subnetLabel}  ·  self ${r.selfIp ?? '?'}  ·  '
                  'gateway ${r.gateway ?? '?'}  ·  ${r.hosts.length} host(s)',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: (r == null || r.hosts.isEmpty)
              ? Center(
                  child: Text(
                    r == null
                        ? 'No scan yet.'
                        : 'No hosts responded on the probed ports.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : ListView.separated(
                  itemCount: r.hosts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int i) =>
                      _hostTile(r.hosts[i]),
                ),
        ),
      ],
    );
  }

  Widget _hostTile(LanHost h) {
    final String ports = (h.openPorts.toList()..sort()).join(', ');
    final String services = (h.mdnsServices.toList()..sort()).join(', ');
    return ListTile(
      dense: true,
      title: Text('${h.ip}    [${h.deviceType.label}]'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (h.hostname != null) Text('PTR: ${h.hostname}'),
          if (h.mdnsName != null) Text('mDNS: ${h.mdnsName}'),
          if (services.isNotEmpty) Text('services: $services'),
          Text('ports: ${ports.isEmpty ? '—' : ports}'),
        ],
      ),
    );
  }
}
