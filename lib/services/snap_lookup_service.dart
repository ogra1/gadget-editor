import 'dart:convert';
import 'dart:io';

import 'package:gadget_editor/services/snap_store_service.dart';

/// The result of resolving a snap name to its store identity.
class SnapLookup {
  const SnapLookup({
    required this.name,
    required this.snapId,
    this.publisher,
    this.validation,
    this.summary,
  });

  /// The canonical snap name as the store reports it.
  final String name;

  /// The 32-character snap ID.
  final String snapId;

  /// Publisher display name, when the store provides one.
  final String? publisher;

  /// Store validation level of the publisher (e.g. `verified`, `starred`).
  final String? validation;

  /// Short description, when the store provides one.
  final String? summary;
}

/// Resolves snap names to snap IDs via the store's `snaps/info` endpoint.
///
/// Gadget snap files reference other snaps by their 32-character snap ID,
/// which is impractical to remember; this service lets the user type the
/// human-readable name instead and obtain the ID from the store. Snaps that
/// are not in the store (e.g. private builds) simply cannot be resolved and
/// must be entered by ID as before.
///
/// The HTTP surface is the same [SnapStoreHttpClient] the download path
/// uses, so tests can substitute an in-memory client.
class SnapLookupService {
  SnapLookupService({SnapStoreHttpClient? httpClient})
      : _httpClient = httpClient ?? _RealStoreHttpClient(HttpClient());

  final SnapStoreHttpClient _httpClient;

  static const String _apiBase = 'https://api.snapcraft.io/v2';

  Map<String, String> get _commonHeaders => {
        'Snap-Device-Series': '16',
        'X-Ubuntu-Series': '16',
        'X-Ubuntu-Release': '20.04',
      };

  /// Resolves [name] to its snap ID.
  ///
  /// Returns `null` when the name cannot be resolved: the store does not
  /// know the snap (unsearchable / private) or the request fails for any
  /// reason. A `null` result is not an error condition for the caller — the
  /// raw text the user typed stays valid as a manually pasted snap ID.
  Future<SnapLookup?> lookup(String name) async {
    final response = await _httpClient.get(
      '$_apiBase/snaps/info/$name',
      {..._commonHeaders, 'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      return null;
    }

    final dynamic data;
    try {
      data = jsonDecode(utf8.decode(response.bytes));
    } on FormatException {
      return null;
    }
    if (data is! Map<String, dynamic>) {
      return null;
    }

    final snapId = data['snap-id']?.toString() ?? '';
    if (snapId.isEmpty) {
      return null;
    }

    final snap = data['snap'] is Map<String, dynamic>
        ? data['snap'] as Map<String, dynamic>
        : null;
    final publisher = snap?['publisher'] is Map<String, dynamic>
        ? snap!['publisher'] as Map<String, dynamic>
        : null;

    return SnapLookup(
      name: data['name']?.toString() ?? name,
      snapId: snapId,
      publisher: publisher?['display-name']?.toString(),
      validation: publisher?['validation']?.toString(),
      summary: snap?['summary']?.toString(),
    );
  }
}

/// Production HTTP client for [SnapLookupService]; mirrors the download
/// path so both talk to the store with the same request shape.
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
