// Render the actual Flutter widgets with fictional, non-production fixtures.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qazaqmetal/main.dart';
import 'package:qazaqmetal/api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'system_test.dart' as fixtures;

void main() {
  testWidgets('Capture actual member and partner interfaces', (tester) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/Manrope.ttf'));
    await tester.runAsync(() => font.load());
    await tester.runAsync(() async {
      for (final entry in {
        'PTSerif': ['assets/PTSerif-Regular.ttf', 'assets/PTSerif-Bold.ttf'],
        'Roboto': ['assets/Roboto.ttf'],
        'MaterialIcons': [
          'packages/flutter_test/fonts/MaterialIcons-Regular.otf',
        ],
      }.entries) {
        final loader = FontLoader(entry.key);
        for (final asset in entry.value) {
          if (entry.key == 'MaterialIcons') {
            final sdk =
                Platform.environment['FLUTTER_ROOT'] ??
                '/Users/dmitriyshtrakhov/flutter-sdk/flutter';
            loader.addFont(
              File(
                '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
            );
          } else {
            loader.addFont(rootBundle.load(asset));
          }
        }
        await loader.load();
      }
    });
    FlutterSecureStorage.setMockInitialValues({});
    final directory = Directory('../../output/store-assets/screens');
    await tester.runAsync(() => directory.create(recursive: true));
    fixtures.venue['data']['name'] = 'ДЕМО · Кафе «Встреча»';
    fixtures.venue['data']['address'] = 'Демонстрационное заведение';
    for (final role in ['member', 'partner']) {
      final base = fixtures.fakeApi(user: {...fixtures.member, 'role': role});
      final api =
          Api(
              client: MockClient((request) async {
                if (request.url.path == '/api/workspace/resources') {
                  return fixtures.response([
                    {
                      ...fixtures.venue,
                      'kind': 'venue',
                      'version': 1,
                      'enabled': true,
                    },
                    {
                      ...fixtures.venue,
                      'id': 'venue-2',
                      'kind': 'venue',
                      'version': 1,
                      'enabled': true,
                      'data': {
                        ...fixtures.venue['data'],
                        'name': 'ДЕМО · Пространство «Вместе»',
                        'category': 'Другое',
                      },
                    },
                  ]);
                }
                final forwarded = http.Request(request.method, request.url)
                  ..headers.addAll(request.headers)
                  ..bodyBytes = request.bodyBytes;
                return http.Response.fromStream(
                  await base.client.send(forwarded),
                );
              }),
            )
            ..loading = false
            ..user = {...fixtures.member, 'role': role};
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: QazaqMetalApp(api: api),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String filename) async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${directory.path}/$filename.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture(role);
      for (final destination in [1, 4]) {
        await tester.tap(find.byType(NavigationDestination).at(destination));
        await tester.pumpAndSettle();
        await capture('$role-$destination');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    }
  });
}
