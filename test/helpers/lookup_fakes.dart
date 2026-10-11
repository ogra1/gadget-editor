import 'package:gadget_editor/services/snap_lookup_service.dart';
import 'package:gadget_editor/services/snap_store_service.dart';

/// HTTP client that is never called; placeholder for fakes that override
/// [SnapLookupService.lookup] directly.
class _NeverHttp implements SnapStoreHttpClient {
  @override
  Future<({int statusCode, List<int> bytes})> get(
          String url, Map<String, String> headers) async =>
      (statusCode: 200, bytes: <int>[]);
}

/// A [SnapLookupService] that resolves nothing.
///
/// Keeps widget tests hermetic (no real store HTTP) while exercising the
/// manual snap-ID fallback path: anything name-like stays as-is.
class NoopLookupService extends SnapLookupService {
  NoopLookupService() : super(httpClient: _NeverHttp());

  @override
  Future<SnapLookup?> lookup(String name) async => null;
}

/// A [SnapLookupService] resolving a fixed set of snap names to IDs.
class MapLookupService extends SnapLookupService {
  MapLookupService(this.byName) : super(httpClient: _NeverHttp());

  /// snap name -> snap ID; missing names are unresolvable.
  final Map<String, String> byName;

  @override
  Future<SnapLookup?> lookup(String name) async {
    final id = byName[name];
    if (id == null) return null;
    return SnapLookup(name: name, snapId: id);
  }
}
