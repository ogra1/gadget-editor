import 'dart:convert';
import 'dart:io';

/// Error thrown when a Snap Store request fails or returns an unusable
/// response.
class StoreException implements Exception {
  StoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Minimal HTTP surface the [SnapStoreService] needs.
///
/// Production uses the real [HttpClient]-backed implementation; tests can
/// substitute an in-memory one without faking `dart:io`.
abstract interface class SnapStoreHttpClient {
  Future<({int statusCode, List<int> bytes})> get(
      String url, Map<String, String> headers);
}

class _RealStoreHttpClient implements SnapStoreHttpClient {
  _RealStoreHttpClient(this._client);

  final HttpClient _client;

  @override
  Future<({int statusCode, List<int> bytes})> get(
      String url, Map<String, String> headers) async {
    final request = await _client.getUrl(Uri.parse(url));
    headers.forEach(request.headers.set);
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return (statusCode: response.statusCode, bytes: bytes);
  }
}

/// Talks to the Snap Store REST API: snap search (channel map) and snap file
/// downloads.
class SnapStoreService {
  SnapStoreService({SnapStoreHttpClient? httpClient})
      : _httpClient = httpClient ?? _RealStoreHttpClient(HttpClient());

  final SnapStoreHttpClient _httpClient;

  static const String _apiBase = 'https://api.snapcraft.io/v2';

  Map<String, String> get _commonHeaders => {
        'Snap-Device-Series': '16',
        'X-Ubuntu-Series': '16',
        'X-Ubuntu-Release': '20.04',
      };

  /// Returns the gadget snap channels available for [snapName].
  ///
  /// One entry is returned per (track, risk, architecture) group, keeping the
  /// highest revision of each group (store revisions are globally unique, so
  /// one entry per architecture must be kept). The result is sorted by
  /// track, then risk, then architecture.
  ///
  /// Each returned map has the shape:
  /// `{'channel': {...}, 'download': {'url': ...}, 'revision': n, 'version': '...'}`
  Future<List<Map<String, dynamic>>> searchGadgetChannels(
      String snapName) async {
    final response = await _httpClient
        .get(
          '$_apiBase/snaps/info/$snapName',
          {..._commonHeaders, 'Accept': 'application/json'},
        );
    if (response.statusCode != 200) {
      throw StoreException(
          'Snap not found: $snapName (${_describeResponseBody(response.bytes)})');
    }

    final data = jsonDecode(utf8.decode(response.bytes));
    final channelMap = (data['channel-map'] as List<dynamic>?) ?? [];
    if (channelMap.isEmpty) {
      throw StoreException('No channel map found in API response');
    }

    // Filter for gadget-type snaps on Ubuntu Core tracks (full numbers only,
    // not e.g. 24.04 or 26.04).
    final gadgetChannels = channelMap
        .where((channel) => channel['type'] == 'gadget')
        .where((channel) => channel['channel']['track'] != null)
        .where(
            (channel) => !channel['channel']['track'].toString().contains('.'))
        .toList();

    // Group by track/risk/architecture and select the highest revision in
    // each group.
    final channelGroups = <String, List<dynamic>>{};
    for (final channel in gadgetChannels) {
      final track = channel['channel']['track'] as String?;
      final risk = channel['channel']['risk'] as String?;
      final architecture = channel['channel']['architecture'] as String?;
      final key = '$track/$risk/$architecture';
      channelGroups.putIfAbsent(key, () => []).add(channel);
    }

    final uniqueChannels = <dynamic>[];
    for (final group in channelGroups.values) {
      dynamic maxRevisionChannel;
      int maxRevision = -1;
      for (final channel in group) {
        final revision = channel['revision'] as int?;
        if (revision != null && revision > maxRevision) {
          maxRevision = revision;
          maxRevisionChannel = channel;
        }
      }
      if (maxRevisionChannel != null) {
        uniqueChannels.add(maxRevisionChannel);
      }
    }

    // Stable, predictable ordering: track, then risk, then architecture.
    uniqueChannels.sort((a, b) {
      String part(dynamic channel, String key) =>
          (channel['channel'][key] as String?) ?? '';

      int result = part(a, 'track').compareTo(part(b, 'track'));
      if (result != 0) {
        return result;
      }
      result = part(a, 'risk').compareTo(part(b, 'risk'));
      if (result != 0) {
        return result;
      }
      return part(a, 'architecture').compareTo(part(b, 'architecture'));
    });

    return uniqueChannels
        .map((channel) => {
              'channel': channel['channel'],
              'download': channel['download'],
              'revision': channel['revision'],
              'version': channel['version'],
            })
        .toList();
  }

  /// Downloads the snap file for [channel] into [targetDirectory] and
  /// returns the written file.
  Future<File> downloadSnapFile(
      Map<String, dynamic> channel, String targetDirectory) async {
    final downloadUrl = channel['download']['url'] as String?;
    if (downloadUrl == null) {
      throw StoreException('No download URL found in selected channel');
    }

    final response = await _httpClient
        .get(
          downloadUrl,
          {..._commonHeaders, 'Accept': 'application/octet-stream'},
        );
    if (response.statusCode != 200) {
      throw StoreException('Failed to download snap: ${response.statusCode}');
    }

    final fileName = Uri.parse(downloadUrl).path.split('/').last;
    final outFile = File('$targetDirectory/$fileName');
    await outFile.writeAsBytes(response.bytes);
    return outFile;
  }

  /// Extracts a human-readable message from a store error response.
  ///
  /// The snap store reports errors as JSON with an `error-list`, e.g.
  /// `{"error-list":[{"code":"resource-not-found",
  /// "message":"No snap named 'x' found in series '16'."}]}`. When
  /// that structure is present the messages are returned (joined with
  /// `'; '` if several); otherwise the raw body text is used so nothing
  /// is ever lost.
  static String _describeResponseBody(List<int> bytes) {
    final body = utf8.decode(bytes, allowMalformed: true);
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final errorList = decoded['error-list'];
        if (errorList is List) {
          final messages = errorList
              .whereType<Map<String, dynamic>>()
              .map((entry) => entry['message'])
              .whereType<String>()
              .toList();
          if (messages.isNotEmpty) {
            return messages.join('; ');
          }
        }
      }
    } on FormatException {
      // Not JSON; fall through and show the raw body.
    }
    return body;
  }
}
