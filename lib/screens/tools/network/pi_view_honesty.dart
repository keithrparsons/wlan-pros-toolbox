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
/// On the Pi the sensor measures only latency and packet loss (to the internet
/// and the gateway) and DNS resolution time, and it measures the PI, not "your
/// device." The Pi blurb must not promise the four dimensions the Pi cannot back
/// (jitter, download, upload, responsiveness) or a browser-side cloud-app
/// reachability sweep. Off the Pi, the full native blurb stands unchanged.
String netQualityBlurb(bool piBacked) => piBacked
    ? 'Measures latency and packet loss from the WLAN Pi hosting '
        'this page to the internet and its gateway, plus DNS '
        'resolution time. Jitter, download, upload, and '
        'responsiveness are not available from the Pi sensor. Each '
        'dimension is graded on its own; there is no single score.'
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
String piConntestCopyText(PiConntestResult ct) {
  const String tab = '\t';
  String status(bool reachable) => reachable ? 'reachable' : 'unreachable';
  String rtt(bool reachable, double? ms) =>
      reachable && ms != null ? '${ms.round()} ms' : '—';
  String loss(double? pct) => pct == null ? '' : '${pct.round()}%';
  String named(String base, String? id) =>
      (id == null || id.isEmpty) ? base : '$base ($id)';

  final bool dnsResolved = ct.dns.ms != null;
  return (StringBuffer()
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
        ].join(tab)))
      .toString()
      .trimRight();
}
