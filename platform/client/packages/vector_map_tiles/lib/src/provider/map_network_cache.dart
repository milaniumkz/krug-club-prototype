import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../provider_exception.dart';

class MapTileEvent {
  final bool loaded;
  final int? statusCode;
  const MapTileEvent(this.loaded, this.statusCode);
}

/// Bounded, coalesced map requests. No authentication or participant data is cached.
class MapNetworkCache {
  static final shared = MapNetworkCache();
  final http.Client client;
  final int maximumBytes, maximumConcurrent, maximumQueued;
  final Duration timeout;
  final DateTime Function() clock;
  final Future<void> Function(Duration) delay;
  final _entries = LinkedHashMap<String, _Entry>();
  final _failures = LinkedHashMap<String, _Failure>();
  final _pending = <String, Future<Uint8List>>{};
  final _waiting = Queue<Completer<void>>();
  final _events = StreamController<MapTileEvent>.broadcast();
  int _bytes = 0, _active = 0, _privateNonce = 0;
  int networkRequests = 0, cacheHits = 0, coalesced = 0, peakActive = 0;
  Stream<MapTileEvent> get events => _events.stream;
  int get bytes => _bytes;
  int get active => _active;
  MapNetworkCache({
    http.Client? client,
    this.maximumBytes = 16 * 1024 * 1024,
    this.maximumConcurrent = 4,
    this.maximumQueued = 24,
    this.timeout = const Duration(seconds: 8),
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
  })  : client = client ?? http.Client(),
        clock = clock ?? DateTime.now,
        delay = delay ?? ((d) => Future<void>.delayed(d));

  Future<Uint8List> fetch(String resourceUrl,
      {bool tile = false, Map<String, String>? headers}) async {
    // Explicit authenticated requests retain their headers and never share cached data.
    final private = headers != null && headers.isNotEmpty;
    final url =
        private ? '$resourceUrl|request-${++_privateNonce}' : resourceUrl;
    try {
      final cached = _entries.remove(url);
      if (cached != null) {
        if (cached.expires.isAfter(clock())) {
          _entries[url] = cached;
          cacheHits++;
          if (tile) _events.add(const MapTileEvent(true, 200));
          return cached.bytes;
        }
        _bytes -= cached.bytes.length;
      }
      final failed = _failures[url];
      if (failed != null && failed.until.isAfter(clock())) throw failed.error;
      _failures.remove(url);
      var pending = _pending[url];
      if (pending == null) {
        pending = _load(resourceUrl, cacheKey: url, headers: headers);
        _pending[url] = pending;
      } else {
        coalesced++;
      }
      try {
        final bytes = await pending;
        if (tile) _events.add(const MapTileEvent(true, 200));
        return bytes;
      } finally {
        if (identical(_pending[url], pending)) _pending.remove(url);
      }
    } catch (e) {
      if (tile)
        _events.add(
          MapTileEvent(false, e is ProviderException ? e.statusCode : null),
        );
      rethrow;
    }
  }

  Future<void> _acquire() async {
    if (_active < maximumConcurrent) {
      _active++;
      if (_active > peakActive) peakActive = _active;
      return;
    }
    if (_waiting.length >= maximumQueued) {
      throw ProviderException(
          message: 'Map request queue is full', retryable: Retryable.none);
    }
    final queuedAt = clock();
    final waiter = Completer<void>();
    _waiting.add(waiter);
    await waiter.future;
    if (clock().difference(queuedAt) > const Duration(seconds: 5)) {
      _release();
      throw ProviderException(
          message: 'Obsolete queued map request', retryable: Retryable.none);
    }
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _active--;
    }
  }

  Future<Uint8List> _load(String url,
      {String? cacheKey, Map<String, String>? headers}) async {
    final key = cacheKey ?? url;
    await _acquire();
    ProviderException? failure;
    var cooldown = const Duration(seconds: 15);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final abort = Completer<void>();
        final timer = Timer(timeout, () {
          if (!abort.isCompleted) abort.complete();
        });
        try {
          networkRequests++;
          final request = http.AbortableRequest(
            'GET',
            Uri.parse(url),
            abortTrigger: abort.future,
          );
          if (headers != null) request.headers.addAll(headers);
          final response = await client
              .send(request)
              .then(http.Response.fromStream)
              .timeout(timeout + const Duration(milliseconds: 100));
          if (response.statusCode == 200 &&
              response.bodyBytes.isNotEmpty &&
              response.bodyBytes.length <= 4 * 1024 * 1024) {
            final bytes = response.bodyBytes;
            final cc = response.headers['cache-control'] ?? '';
            final maxAge = int.tryParse(
                  RegExp(r'max-age=(\d+)').firstMatch(cc)?.group(1) ?? '1800',
                ) ??
                1800;
            final seconds = maxAge.clamp(0, 1800);
            if ((headers == null || headers.isEmpty) &&
                !cc.contains('no-store') &&
                !cc.contains('no-cache') &&
                seconds > 0 &&
                bytes.length <= maximumBytes) {
              final previous = _entries.remove(key);
              if (previous != null) _bytes -= previous.bytes.length;
              _entries[key] = _Entry(
                bytes,
                clock().add(Duration(seconds: seconds)),
              );
              _bytes += bytes.length;
              while (_bytes > maximumBytes || _entries.length > 512) {
                final removed = _entries.remove(_entries.keys.first)!;
                _bytes -= removed.bytes.length;
              }
            }
            _failures.remove(key);
            return bytes;
          }
          failure = ProviderException(
            message: 'Map resource unavailable',
            statusCode: response.statusCode,
            retryable: Retryable.none,
          );
          if (response.statusCode == 429) {
            final retryAfter =
                int.tryParse(response.headers['retry-after'] ?? '') ?? 30;
            cooldown = Duration(seconds: retryAfter.clamp(10, 86400));
          }
          if (![408, 502, 503, 504].contains(response.statusCode) ||
              attempt == 1) break;
        } catch (_) {
          failure = ProviderException(
            message: 'Map connection interrupted',
            retryable: Retryable.none,
          );
          if (attempt == 1) break;
        } finally {
          timer.cancel();
        }
        await delay(const Duration(milliseconds: 250));
      }
      final error = failure ??
          ProviderException(
            message: 'Map resource unavailable',
            retryable: Retryable.none,
          );
      _failures[key] = _Failure(error, clock().add(cooldown));
      while (_failures.length > 512) {
        _failures.remove(_failures.keys.first);
      }
      throw error;
    } finally {
      _release();
    }
  }

  void clearFailures() {
    _failures.removeWhere((_, value) => value.error.statusCode != 429);
  }

  void dispose() {
    client.close();
    _events.close();
  }
}

class _Entry {
  final Uint8List bytes;
  final DateTime expires;
  _Entry(this.bytes, this.expires);
}

class _Failure {
  final ProviderException error;
  final DateTime until;
  _Failure(this.error, this.until);
}
