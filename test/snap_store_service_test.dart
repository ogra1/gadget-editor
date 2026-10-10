import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/services/snap_store_service.dart';

/// In-memory [SnapStoreHttpClient] that serves canned responses.
class FakeStoreHttp implements SnapStoreHttpClient {
  FakeStoreHttp(this.routes);

  /// url -> (statusCode, body bytes)
  final Map<String, (int, List<int>)> routes;
  final List<(String url, Map<String, String> headers)> requests = [];

  @override
  Future<({int statusCode, List<int> bytes})> get(
      String url, Map<String, String> headers) async {
    requests.add((url, headers));
    final route = routes[url] ?? (404, utf8.encode('no such route'));
    return (statusCode: route.$1, bytes: route.$2);
  }
}

/// Builds a minimal store channel-map payload.
Map<String, dynamic> _storeResponse(List<Map<String, dynamic>> channelMap) =>
    {
      'name': 'pc',
      'channel-map': channelMap,
    };

Map<String, dynamic> _channel(
  String track,
  String risk,
  String architecture,
  int revision, {
  String version = '1.0',
  String type = 'gadget',
  String? url,
}) {
  return {
    'type': type,
    'channel': {
      'track': track,
      'risk': risk,
      'architecture': architecture,
    },
    'revision': revision,
    'version': version,
    'download': {
      'url': url ??
          'https://example.com/$track-$risk-$architecture.snap'
    },
  };
}

void main() {
  group('SnapStoreService.searchGadgetChannels', () {
    test(
        'groups by track/risk/architecture and keeps highest revision per arch',
        () async {
      final http = FakeStoreHttp({
        'https://api.snapcraft.io/v2/snaps/info/pc': (
          200,
          utf8.encode(jsonEncode(_storeResponse([
            _channel('26', 'stable', 'amd64', 10),
            _channel('26', 'stable', 'amd64', 42), // older, same arch
            _channel('26', 'stable', 'arm64', 41),
            _channel('24', 'stable', 'amd64', 50),
          ])))
        ),
      });
      final service = SnapStoreService(httpClient: http);

      final channels = await service.searchGadgetChannels('pc');

      // One channel per (track/risk/arch): amd64@42 and arm64@41 on
      // 26/stable, amd64@50 on 24/stable.
      expect(channels, hasLength(3));
      expect(
        channels.map((c) =>
            '${c['channel']['track']}/${c['channel']['risk']}/${c['channel']['architecture']}/rev${c['revision']}'),
        unorderedEquals([
          '26/stable/amd64/rev42',
          '26/stable/arm64/rev41',
          '24/stable/amd64/rev50',
        ]),
      );
      // Shape of each entry is what the UI consumes.
      expect(channels.first.keys,
          unorderedEquals(['channel', 'download', 'revision', 'version']));
    });

    test('sorts by track, risk, then architecture', () async {
      final http = FakeStoreHttp({
        'https://api.snapcraft.io/v2/snaps/info/pc': (
          200,
          utf8.encode(jsonEncode(_storeResponse([
            _channel('26', 'candidate', 'arm64', 3),
            _channel('26', 'stable', 'amd64', 1),
            _channel('24', 'stable', 'amd64', 2),
          ])))
        ),
      });
      final service = SnapStoreService(httpClient: http);

      final channels = await service.searchGadgetChannels('pc');

      expect(
        channels.map((c) =>
            '${c['channel']['track']}/${c['channel']['risk']}/${c['channel']['architecture']}'),
        [
          '24/stable/amd64',
          '26/candidate/arm64',
          '26/stable/amd64',
        ],
      );
    });

    test('filters out non-gadget types and non-core tracks', () async {
      final http = FakeStoreHttp({
        'https://api.snapcraft.io/v2/snaps/info/pc': (
          200,
          utf8.encode(jsonEncode(_storeResponse([
            _channel('26', 'stable', 'amd64', 1, type: 'app'), // not gadget
            _channel('24.04', 'stable', 'amd64', 2), // dotted track
            _channel('26', 'stable', 'amd64', 3), // keep
          ])))
        ),
      });
      final service = SnapStoreService(httpClient: http);

      final channels = await service.searchGadgetChannels('pc');

      expect(channels, hasLength(1));
      expect(channels.first['revision'], 3);
    });

    test('throws StoreException with body on non-200', () async {
      final http = FakeStoreHttp({
        'https://api.snapcraft.io/v2/snaps/info/nope': (
          404,
          utf8.encode('{"error":"not found"}')
        ),
      });
      final service = SnapStoreService(httpClient: http);

      expect(
        () => service.searchGadgetChannels('nope'),
        throwsA(isA<StoreException>().having(
            (e) => e.message, 'message', contains('Snap not found: nope'))),
      );
    });

    test('throws StoreException on empty channel-map', () async {
      final http = FakeStoreHttp({
        'https://api.snapcraft.io/v2/snaps/info/pc': (
          200,
          utf8.encode(jsonEncode(_storeResponse([])))
        ),
      });
      final service = SnapStoreService(httpClient: http);

      expect(
        () => service.searchGadgetChannels('pc'),
        throwsA(isA<StoreException>().having(
            (e) => e.message, 'message', contains('No channel map'))),
      );
    });

    test('sends the snap store headers', () async {
      final http = FakeStoreHttp({
        'https://api.snapcraft.io/v2/snaps/info/pc': (
          200,
          utf8.encode(jsonEncode(_storeResponse([])))
        ),
      });
      final service = SnapStoreService(httpClient: http);

      try {
        await service.searchGadgetChannels('pc');
      } catch (_) {}

      final (url, headers) = http.requests.first;
      expect(url, 'https://api.snapcraft.io/v2/snaps/info/pc');
      expect(headers['Snap-Device-Series'], '16');
      expect(headers['X-Ubuntu-Series'], '16');
      expect(headers['X-Ubuntu-Release'], '20.04');
      expect(headers['Accept'], 'application/json');
    });
  });

  group('SnapStoreService.downloadSnapFile', () {
    test('writes the body to <dir>/<basename>', () async {
      final body = utf8.encode('snap-bytes-\u03c0');
      final http = FakeStoreHttp({
        'https://example.com/pc_26_amd64.snap': (200, body),
      });
      final service = SnapStoreService(httpClient: http);
      final dir = await Directory.systemTemp.createTemp('dl_test_');

      final file = await service.downloadSnapFile(
        {'download': {'url': 'https://example.com/pc_26_amd64.snap'}},
        dir.path,
      );

      expect(file.path, '${dir.path}/pc_26_amd64.snap');
      expect(await file.readAsBytes(), body);
      await dir.delete(recursive: true);
    });

    test('throws StoreException when there is no URL', () async {
      final service = SnapStoreService(httpClient: FakeStoreHttp({}));

      expect(
        () => service.downloadSnapFile({'download': {}}, '/tmp'),
        throwsA(isA<StoreException>()),
      );
    });

    test('throws StoreException on non-200', () async {
      final http = FakeStoreHttp({
        'https://example.com/x.snap': (500, utf8.encode('oops')),
      });
      final service = SnapStoreService(httpClient: http);

      expect(
        () => service.downloadSnapFile(
            {'download': {'url': 'https://example.com/x.snap'}}, '/tmp'),
        throwsA(
            isA<StoreException>().having((e) => e.message, 'message', contains('500'))),
      );
    });
  });
}
