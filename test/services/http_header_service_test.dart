// HttpHeaderService unit tests — exercise redirect-chain assembly, the
// HEAD→GET fallback on 405, relative/absolute Location resolution, URL parsing,
// header normalization, and the redirect-loop cap, all via the injectable
// HttpProbe seam so no live server is touched.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/http_header_service.dart';

/// Builds a probe from a map of URL → response so a multi-hop chain can be
/// scripted deterministically.
HttpProbe scripted(Map<String, RawHttpResponse> Function() table) {
  return (HttpMethod method, Uri url, Duration timeout) async {
    final RawHttpResponse? r = table()[url.toString()];
    if (r == null) {
      throw StateError('no scripted response for $url');
    }
    return r;
  };
}

RawHttpResponse resp(
  int code,
  String reason, {
  String? location,
  List<HeaderEntry> headers = const <HeaderEntry>[],
}) =>
    RawHttpResponse(
      statusCode: code,
      reasonPhrase: reason,
      location: location,
      headers: headers,
    );

void main() {
  group('single-hop', () {
    test('200 with headers → one hop, success, headers preserved', () async {
      final HttpHeaderService svc = HttpHeaderService(
        opener: (method, url, timeout) async => resp(
          200,
          'OK',
          headers: const <HeaderEntry>[
            HeaderEntry(name: 'Content-Type', value: 'text/html'),
            HeaderEntry(name: 'Server', value: 'nginx'),
          ],
        ),
      );
      final HttpHeaderResult r =
          await svc.inspect(rawUrl: 'https://example.com');
      expect(r.isError, isFalse);
      expect(r.hops.length, 1);
      expect(r.finalHop!.statusCode, 200);
      expect(r.finalHop!.statusLine, '200 OK');
      expect(r.finalHop!.headers.length, 2);
      expect(r.redirectLimitHit, isFalse);
      expect(r.headFellBackToGet, isFalse);
    });

    test('bare host gets https:// prepended', () async {
      Uri? seen;
      final HttpHeaderService svc = HttpHeaderService(
        opener: (method, url, timeout) async {
          seen = url;
          return resp(200, 'OK');
        },
      );
      await svc.inspect(rawUrl: 'example.com');
      expect(seen!.scheme, 'https');
      expect(seen!.host, 'example.com');
    });
  });

  group('redirect chain', () {
    test('301 → 302 → 200 records every hop in order', () async {
      final HttpHeaderService svc = HttpHeaderService(
        opener: scripted(() => <String, RawHttpResponse>{
              'http://a.example/': resp(301, 'Moved Permanently',
                  location: 'https://a.example/'),
              'https://a.example/': resp(302, 'Found',
                  location: 'https://www.a.example/'),
              'https://www.a.example/': resp(200, 'OK'),
            }),
      );
      final HttpHeaderResult r =
          await svc.inspect(rawUrl: 'http://a.example/');
      expect(r.isError, isFalse);
      expect(r.hops.length, 3);
      expect(r.hops[0].statusCode, 301);
      expect(r.hops[0].location, 'https://a.example/');
      expect(r.hops[1].statusCode, 302);
      expect(r.hops[2].statusCode, 200);
      expect(r.finalHop!.statusCode, 200);
    });

    test('relative Location resolves against the current URL', () async {
      final HttpHeaderService svc = HttpHeaderService(
        opener: scripted(() => <String, RawHttpResponse>{
              'https://h.example/old': resp(301, 'Moved Permanently',
                  location: '/new'),
              'https://h.example/new': resp(200, 'OK'),
            }),
      );
      final HttpHeaderResult r =
          await svc.inspect(rawUrl: 'https://h.example/old');
      expect(r.hops.length, 2);
      expect(r.hops[1].url, 'https://h.example/new');
      expect(r.finalHop!.statusCode, 200);
    });

    test('redirect loop is capped, flagged, and never hangs', () async {
      final HttpHeaderService svc = HttpHeaderService(
        // Always redirects to itself.
        opener: (method, url, timeout) async =>
            resp(302, 'Found', location: url.toString()),
      );
      final HttpHeaderResult r = await svc.inspect(
        rawUrl: 'https://loop.example/',
        maxRedirects: 3,
      );
      expect(r.isError, isFalse);
      expect(r.redirectLimitHit, isTrue);
      // maxRedirects + 1 attempts.
      expect(r.hops.length, 4);
    });
  });

  group('HEAD → GET fallback', () {
    test('405 on HEAD retries the same URL with GET', () async {
      final List<String> calls = <String>[];
      final HttpHeaderService svc = HttpHeaderService(
        opener: (method, url, timeout) async {
          calls.add(method.label);
          if (method == HttpMethod.head) return resp(405, 'Method Not Allowed');
          return resp(
            200,
            'OK',
            headers: const <HeaderEntry>[
              HeaderEntry(name: 'Allow', value: 'GET, POST'),
            ],
          );
        },
      );
      final HttpHeaderResult r = await svc.inspect(
        rawUrl: 'https://strict.example/',
        method: HttpMethod.head,
      );
      expect(calls, <String>['HEAD', 'GET']);
      expect(r.headFellBackToGet, isTrue);
      // Only the successful GET hop is recorded for that step.
      expect(r.hops.length, 1);
      expect(r.finalHop!.statusCode, 200);
      expect(r.finalHop!.method, HttpMethod.get);
    });

    test('explicit GET does NOT trigger a fallback retry on 405', () async {
      int calls = 0;
      final HttpHeaderService svc = HttpHeaderService(
        opener: (method, url, timeout) async {
          calls++;
          return resp(405, 'Method Not Allowed');
        },
      );
      final HttpHeaderResult r = await svc.inspect(
        rawUrl: 'https://strict.example/',
        method: HttpMethod.get,
      );
      expect(calls, 1);
      expect(r.headFellBackToGet, isFalse);
      expect(r.finalHop!.statusCode, 405);
    });
  });

  group('URL validation', () {
    test('empty URL → failure', () async {
      final HttpHeaderService svc = HttpHeaderService(
        opener: (method, url, timeout) async => resp(200, 'OK'),
      );
      final HttpHeaderResult r = await svc.inspect(rawUrl: '   ');
      expect(r.isError, isTrue);
    });

    test('non-http scheme → failure, no request issued', () async {
      bool called = false;
      final HttpHeaderService svc = HttpHeaderService(
        opener: (method, url, timeout) async {
          called = true;
          return resp(200, 'OK');
        },
      );
      final HttpHeaderResult r =
          await svc.inspect(rawUrl: 'ftp://files.example/');
      expect(r.isError, isTrue);
      expect(called, isFalse);
    });
  });

  group('empty headers', () {
    test('final 204 with no headers → success, empty header list', () async {
      final HttpHeaderService svc = HttpHeaderService(
        opener: (method, url, timeout) async => resp(204, 'No Content'),
      );
      final HttpHeaderResult r =
          await svc.inspect(rawUrl: 'https://empty.example/');
      expect(r.isError, isFalse);
      expect(r.finalHop!.headers, isEmpty);
      expect(r.finalHop!.statusCode, 204);
    });
  });
}
