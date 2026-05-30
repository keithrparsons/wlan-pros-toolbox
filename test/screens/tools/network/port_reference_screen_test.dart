// Widget overflow regression for the Well-Known Ports screen.
//
// The screen's parsing/search logic is covered by
// test/services/port_reference_service_test.dart. This file adds the
// rendered-pixel guard: pump the screen at 320/375/768/1280 widths and assert
// no RenderFlex overflow. A pre-built service is injected so the test does not
// depend on the bundled asset load (PortReferenceScreen.service hook).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/port_reference_screen.dart';
import 'package:wlan_pros_toolbox/services/network/port_reference_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _fixture = '''
{
  "ports": [
    { "port": 22, "protocols": ["tcp"], "name": "ssh", "description": "Secure Shell" },
    { "port": 53, "protocols": ["tcp", "udp"], "name": "dns", "description": "Domain Name System" },
    { "port": 443, "protocols": ["tcp", "udp"], "name": "https", "description": "HTTP over TLS; UDP carries HTTP/3 (QUIC)" },
    { "port": 1812, "protocols": ["udp"], "name": "radius", "description": "RADIUS authentication (802.1X / WPA2-Enterprise)" },
    { "port": 5060, "protocols": ["udp", "tcp"], "name": "sip", "description": "Session Initiation Protocol" }
  ]
}
''';

void main() {
  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    // Multi-width overflow regression: the port results list must not
    // RenderFlex overflow at small phone (320), phone (375), tablet (768), or
    // desktop (1280). Tall height so vertical scroll content never
    // false-triggers. The injected service shows the full (longest) list so
    // every row is laid out.
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final PortReferenceService svc = PortReferenceService.fromJson(_fixture);
    for (final double width in <double>[320, 375, 768, 1280]) {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: PortReferenceScreen(service: svc),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
    }
  });
}
