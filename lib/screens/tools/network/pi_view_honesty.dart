// Pure, platform-independent view decisions for the WLAN-Pi-hosted tool pages.
//
// The `_piBacked` branch each of these screens takes is only reachable under
// `kIsWeb` (a const `false` on the Dart VM), so a plain widget test cannot force
// it. Yet these three decisions carry the screenshot-must-match-prose honesty
// invariant (GL-005 / feedback_screenshot_text_match): on the Pi-hosted page the
// picture, the blurb, and the copy payload must not promise anything the Pi
// sensor cannot back, and must attribute what they DO show to the Pi, never to
// "your device."
//
// Extracting the decisions here as pure, `kIsWeb`-independent functions lets a
// VM unit test pin BOTH branches without a web harness, so the invariant can
// never silently regress (Vera MEDIUM-2, 2026-07-09). The screens call these;
// each decision and each user-visible string lives in exactly one place (SSOT).

import '../../../services/network/pi_backend_client.dart';

/// Whether the interface-info concept graphic may render.
///
/// The graphic depicts a SPECIFIC local device (en0, 192.168.1.42, a MAC). On
/// the Pi-hosted page the prose directly beneath it states a browser cannot read
/// this device's own interface table, so the illustration would have the picture
/// claim the visitor's live local interface while the text says that is
/// impossible. It is therefore omitted on the Pi view. The native view (never
/// Pi-backed) keeps it, where it is truthful.
bool showInterfaceConceptGraphic(bool piBacked) => !piBacked;

/// The net-quality run-card blurb, honest for the surface it renders on.
///
/// On the Pi the sensor measures latency, packet loss, and DNS resolution time,
/// plus TWO throughput numbers: the Pi's own uplink (Pi to the internet) and the
/// local hop between this device and the Pi over Wi-Fi. It measures the PI, not
/// "your device" — so the one thing it genuinely cannot see is the client's own
/// Wi-Fi RF. Off the Pi, the full native blurb stands unchanged.
String netQualityBlurb(bool piBacked) => piBacked
    ? 'Measures latency, packet loss, and DNS resolution time from '
        'the WLAN Pi hosting this page, plus two throughput numbers: '
        'the Pi uplink to the internet, and the local hop between '
        'this device and the Pi. Your own Wi-Fi RF is not visible to '
        'the Pi. Each dimension is graded on its own; there is no '
        'single score.'
    : 'Measures latency, jitter, loss, download, upload, and '
        'responsiveness over a TCP-connect probe and HTTPS '
        'transfers, then checks whether your device can reach a set '
        'of popular cloud apps right now. Each dimension is graded '
        'on its own; there is no single score.';

/// The §8.16 copy payload for the Pi front door (Test My Connection), built from
/// the Pi conntest reading. Same TSV shape as the three sibling Pi tools: a
/// labeled header attributing the run to the Pi, then one tab-separated row per
/// hop (gateway / internet / DNS) carrying reachability, latency, and loss —
/// exactly what the on-screen hop card shows, so what is on screen is what is
/// copied.
///
/// HONESTY (GL-005): an unreachable hop copies its honest "unreachable" word and
/// an em-dash latency placeholder, never a fabricated or zero-filled value. Loss
/// is carried only for the internet hop (the only hop the screen measures loss
/// for); the gateway and DNS loss cells stay blank rather than guessing. The DNS
/// hop is "reachable" when the Pi returned a resolution time.
///
/// THROUGHPUT (optional, mirrors Network Quality): when a Pi run has also
/// measured throughput, two clearly labeled sections are appended so the
/// clipboard carries what the screen shows — the Pi's own uplink (Pi -> internet)
/// download/upload from [throughput], and the local Wi-Fi hop between this device
/// and the Pi ([deviceToPiDownMbps] / [deviceToPiUpMbps]). The two are never
/// conflated (Keith decision + [[project_throughput_methodology]]). A leg that
/// failed copies "Unavailable" (or its error), never a fabricated number. When no
/// throughput evidence is passed the sections are omitted and the output is
/// byte-for-byte the original hop TSV.
String piConntestCopyText(
  PiConntestResult ct, {
  PiThroughputResult? throughput,
  double? deviceToPiDownMbps,
  double? deviceToPiUpMbps,
  String? deviceToPiError,
}) {
  const String tab = '\t';
  String status(bool reachable) => reachable ? 'reachable' : 'unreachable';
  String rtt(bool reachable, double? ms) =>
      reachable && ms != null ? '${ms.round()} ms' : '—';
  String loss(double? pct) => pct == null ? '' : '${pct.round()}%';
  String named(String base, String? id) =>
      (id == null || id.isEmpty) ? base : '$base ($id)';
  String mbps(double? v) => v != null ? '${v.toStringAsFixed(1)} Mbps' : 'Unavailable';

  final bool dnsResolved = ct.dns.ms != null;
  final StringBuffer buf = StringBuffer()
    ..writeln(
      'Connection test — measured on the WLAN Pi hosting this page',
    )
    ..writeln(<String>['Hop', 'Reachability', 'Latency', 'Loss'].join(tab))
    ..writeln(<String>[
      named('Gateway', ct.gateway.target),
      status(ct.gateway.reachable),
      rtt(ct.gateway.reachable, ct.gateway.avgMs),
      '',
    ].join(tab))
    ..writeln(<String>[
      named('Internet', ct.internet.target),
      status(ct.internet.reachable),
      rtt(ct.internet.reachable, ct.internet.avgMs),
      loss(ct.internet.lossPct),
    ].join(tab))
    ..writeln(<String>[
      named('DNS resolve', ct.dns.host),
      status(dnsResolved),
      rtt(dnsResolved, ct.dns.ms),
      '',
    ].join(tab));

  // Pi uplink throughput (Pi -> internet) — only when a probe landed. A leg with
  // an error copies "Unavailable", never a fabricated 0 (GL-005).
  if (throughput != null) {
    buf
      ..writeln()
      ..writeln('Pi to internet (throughput)')
      ..writeln('  Download: ${mbps(throughput.downloadMbps)}')
      ..writeln('  Upload: ${mbps(throughput.uploadMbps)}');
  }

  // Local Wi-Fi hop (this device <-> Pi) — the second, distinct throughput
  // number, kept clearly labeled so it is never read as the Pi's uplink.
  if (deviceToPiDownMbps != null ||
      deviceToPiUpMbps != null ||
      deviceToPiError != null) {
    buf
      ..writeln()
      ..writeln('This device to Pi (Wi-Fi hop)');
    if (deviceToPiError != null) {
      buf.writeln('  $deviceToPiError');
    } else {
      buf
        ..writeln('  Download: ${mbps(deviceToPiDownMbps)}')
        ..writeln('  Upload: ${mbps(deviceToPiUpMbps)}');
    }
  }

  return buf.toString().trimRight();
}
