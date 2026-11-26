import 'package:vector_map_tiles/vector_map_tiles.dart' as vector;

/// Reopening a map does not refetch style, tile metadata or sprites every time.
class MapStyleCache {
  static final shared = MapStyleCache();
  final _entries = <String, _StyleEntry>{};
  Future<vector.Style> read(String url, {bool refresh = false}) {
    final cached = _entries[url];
    if (!refresh && cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.future;
    }
    late Future<vector.Style> future;
    future = vector.StyleReader(uri: url)
        .read()
        .timeout(const Duration(seconds: 25))
        .catchError((Object error) {
          if (identical(_entries[url]?.future, future)) _entries.remove(url);
          throw error;
        });
    _entries.remove(url);
    _entries[url] = _StyleEntry(
      future,
      DateTime.now().add(const Duration(minutes: 10)),
    );
    while (_entries.length > 4) {
      _entries.remove(_entries.keys.first);
    }
    return future;
  }
}

class _StyleEntry {
  final Future<vector.Style> future;
  final DateTime expires;
  _StyleEntry(this.future, this.expires);
}
