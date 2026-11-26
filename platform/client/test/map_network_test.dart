import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

void main() {
  test(
    'Map requests coalesce, reuse cached bytes and honor cache expiry',
    () async {
      var calls = 0;
      var now = DateTime(2026, 11, 26);
      final gate = Completer<void>();
      final cache = MapNetworkCache(
        clock: () => now,
        client: MockClient((request) async {
          calls++;
          await gate.future;
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'cache-control': 'public, max-age=60'},
          );
        }),
      );
      final first = cache.fetch('https://map.test/one');
      final second = cache.fetch('https://map.test/one');
      gate.complete();
      expect(await first, [1, 2, 3]);
      expect(await second, [1, 2, 3]);
      expect(calls, 1);
      expect(cache.coalesced, 1);
      await cache.fetch('https://map.test/one');
      expect(calls, 1);
      now = now.add(const Duration(seconds: 61));
      await cache.fetch('https://map.test/one');
      expect(calls, 2);
      cache.dispose();
    },
  );
  test('Map cache bounds concurrency and memory during a burst', () async {
    final gates = <Completer<void>>[];
    final cache = MapNetworkCache(
      maximumBytes: 8,
      client: MockClient((request) async {
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        return http.Response.bytes([1, 2, 3, 4], 200);
      }),
    );
    final requests = List.generate(
      12,
      (i) => cache.fetch('https://map.test/$i'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(gates.length, 4);
    expect(cache.peakActive, 4);
    for (var batch = 0; batch < 3; batch++) {
      for (final gate in gates.where((g) => !g.isCompleted).toList()) {
        gate.complete();
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future.wait(requests);
    expect(cache.bytes, lessThanOrEqualTo(8));
    expect(cache.active, 0);
    cache.dispose();
  });
  test(
    'Map errors do not create an automatic retry storm, 429 cooldown survives manual retry',
    () async {
      var calls = 0;
      final cache = MapNetworkCache(
        client: MockClient((request) async {
          calls++;
          return http.Response('busy', 429, headers: {'retry-after': '60'});
        }),
        delay: (_) async {},
      );
      for (var i = 0; i < 10; i++) {
        await expectLater(
          cache.fetch('https://map.test/busy'),
          throwsA(isA<ProviderException>()),
        );
        cache.clearFailures();
      }
      expect(calls, 1);
      cache.dispose();
    },
  );
  test(
    'Transient map failure retries once, then recovers on explicit retry',
    () async {
      var calls = 0;
      var available = false;
      final cache = MapNetworkCache(
        client: MockClient((request) async {
          calls++;
          return available
              ? http.Response.bytes([7], 200)
              : http.Response('unavailable', 503);
        }),
        delay: (_) async {},
      );
      await expectLater(
        cache.fetch('https://map.test/transient'),
        throwsA(isA<ProviderException>()),
      );
      expect(calls, 2);
      await expectLater(
        cache.fetch('https://map.test/transient'),
        throwsA(isA<ProviderException>()),
      );
      expect(calls, 2);
      available = true;
      cache.clearFailures();
      expect(await cache.fetch('https://map.test/transient'), [7]);
      expect(calls, 3);
      cache.dispose();
    },
  );
  test('No-store map response is not kept in shared cache', () async {
    var calls = 0;
    final cache = MapNetworkCache(
      client: MockClient((request) async {
        calls++;
        return http.Response.bytes(
          [1],
          200,
          headers: {'cache-control': 'no-store'},
        );
      }),
    );
    await cache.fetch('https://map.test/no-store');
    await cache.fetch('https://map.test/no-store');
    expect(calls, 2);
    expect(cache.bytes, 0);
    cache.dispose();
  });
  test(
    'Private map headers are retained and responses are never shared',
    () async {
      final seen = <String>[];
      final cache = MapNetworkCache(
        client: MockClient((request) async {
          seen.add(request.headers['authorization']!);
          return http.Response.bytes([1], 200);
        }),
      );
      await cache.fetch(
        'https://map.test/private',
        headers: {'authorization': 'Bearer account-a'},
      );
      await cache.fetch(
        'https://map.test/private',
        headers: {'authorization': 'Bearer account-b'},
      );
      expect(seen, ['Bearer account-a', 'Bearer account-b']);
      expect(cache.bytes, 0);
      cache.dispose();
    },
  );
  test(
    'A stalled map response times out and releases its request slot',
    () async {
      final never = Completer<http.Response>();
      final cache = MapNetworkCache(
        timeout: const Duration(milliseconds: 5),
        client: MockClient((_) => never.future),
        delay: (_) async {},
      );
      await expectLater(
        cache.fetch('https://map.test/stalled'),
        throwsA(isA<ProviderException>()),
      );
      expect(cache.networkRequests, 2);
      expect(cache.active, 0);
      cache.dispose();
    },
  );
  test(
    'Map queue rejects excess work instead of growing without a bound',
    () async {
      final gates = <Completer<void>>[];
      final cache = MapNetworkCache(
        maximumConcurrent: 2,
        maximumQueued: 1,
        client: MockClient((_) async {
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
          return http.Response.bytes([1], 200);
        }),
      );
      final first = cache.fetch('https://map.test/queue-1');
      final second = cache.fetch('https://map.test/queue-2');
      final third = cache.fetch('https://map.test/queue-3');
      await expectLater(
        cache.fetch('https://map.test/queue-4'),
        throwsA(isA<ProviderException>()),
      );
      expect(cache.networkRequests, 2);
      for (final gate in gates) {
        gate.complete();
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      for (final gate in gates.where((g) => !g.isCompleted)) {
        gate.complete();
      }
      await Future.wait([first, second, third]);
      expect(cache.peakActive, 2);
      cache.dispose();
    },
  );
}
