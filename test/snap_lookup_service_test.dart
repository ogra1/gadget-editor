import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/services/snap_lookup_service.dart';
import 'package:gadget_editor/services/snap_store_service.dart';

/// In-memory [SnapStoreHttpClient] serving canned responses, mirroring the
/// store-service test helper.
class FakeStoreHttp implements SnapStoreHttpClient {
  FakeStoreHttp(this.routes);

  final Map<String, (int, List<int>)> routes;
  final List<String> requestedUrls = [];

  @override
  Future<({int statusCode, List<int> bytes})> get(
      String url, Map<String, String> headers) async {
    requestedUrls.add(url);
    final route = routes[url] ?? (404, utf8.encode('no such route'));
    return (statusCode: route.$1, bytes: route.$2);
  }
}

/// A realistic `snaps/info` payload (subset of the real shape).
Map<String, dynamic> _info(String name, String id,
    {String? publisher, String? validation, String? summary}) {
  return {
    'name': name,
    'snap-id': id,
    'snap': {
      'name': name,
      if (summary != null) 'summary': summary,
      if (publisher != null)
        'publisher': {
          'display-name': publisher,
          if (validation != null) 'validation': validation,
        },
    },
  };
}

void main() {
  const kId = 'hJmReLmgXSUj4SF7WhyTVRV6IzUa4QUZ';
  const kUrl = 'https://api.snapcraft.io/v2/snaps/info/htop';

  group('SnapLookupService.lookup', () {
    test('resolves a name to its snap ID with publisher metadata', () async {
      final http = FakeStoreHttp({
        kUrl: (
          200,
          utf8.encode(jsonEncode(_info('htop', kId,
              publisher: 'Maximiliano Bertacchini',
              validation: 'starred',
              summary: 'Interactive processes viewer')))
        ),
      });
      final lookup = await SnapLookupService(httpClient: http)
          .lookup('htop');

      expect(lookup, isNotNull);
      expect(lookup!.name, 'htop');
      expect(lookup.snapId, kId);
      expect(lookup.publisher, 'Maximiliano Bertacchini');
      expect(lookup.validation, 'starred');
      expect(lookup.summary, 'Interactive processes viewer');
      expect(http.requestedUrls, [kUrl]);
    });

    test('returns null for an unknown snap (store 400/404)', () async {
      for (final code in [400, 404]) {
        final http = FakeStoreHttp({
          kUrl: (code, utf8.encode('not found')),
        });
        expect(await SnapLookupService(httpClient: http).lookup('htop'),
            isNull,
            reason: 'status $code must map to null');
      }
    });

    test('returns null for malformed payloads', () async {
      // Valid JSON but not an object.
      final notObject = FakeStoreHttp({
        kUrl: (200, utf8.encode('[1,2,3]')),
      });
      expect(await SnapLookupService(httpClient: notObject).lookup('htop'),
          isNull);

      // Object without a snap-id.
      final noId = FakeStoreHttp({
        kUrl: (200, utf8.encode(jsonEncode({'name': 'htop'}))),
      });
      expect(await SnapLookupService(httpClient: noId).lookup('htop'),
          isNull);

      // Empty snap-id.
      final emptyId = FakeStoreHttp({
        kUrl: (200, utf8.encode(jsonEncode({'name': 'htop', 'snap-id': ''}))),
      });
      expect(await SnapLookupService(httpClient: emptyId).lookup('htop'),
          isNull);

      // Not JSON at all.
      final garbage = FakeStoreHttp({
        kUrl: (200, utf8.encode('<html>nope</html>')),
      });
      expect(await SnapLookupService(httpClient: garbage).lookup('htop'),
          isNull);
    });

    test('tolerates missing publisher and summary', () async {
      final http = FakeStoreHttp({
        kUrl: (200, utf8.encode(jsonEncode(_info('htop', kId)))),
      });
      final lookup = await SnapLookupService(httpClient: http).lookup('htop');
      expect(lookup, isNotNull);
      expect(lookup!.publisher, isNull);
      expect(lookup.validation, isNull);
      expect(lookup.summary, isNull);
    });

    test('falls back to the requested name when the store omits it',
        () async {
      final http = FakeStoreHttp({
        kUrl: (
          200,
          utf8.encode(jsonEncode({
            'snap-id': kId,
            'snap': {
              'publisher': {
                'display-name': 'X'
              }
            }
          }))
        ),
      });
      final lookup = await SnapLookupService(httpClient: http).lookup('htop');
      expect(lookup, isNotNull);
      expect(lookup!.name, 'htop');
    });
  });
}
