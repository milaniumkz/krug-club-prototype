import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qazaqmetal/api.dart';
import 'package:qazaqmetal/main.dart';
import 'package:qazaqmetal/workspace.dart';

Json member = {
  'id': 'member',
  'name': 'Александра Орлова',
  'role': 'member',
  'status': 'active',
  'employee_number': '1042',
  'must_change_password': false,
  'organization_name': 'Профсоюзная организация',
  'member_until': null,
};
Json venue = {
  'id': 'venue',
  'data': {
    'name': 'Ресторан «Тест»',
    'category': 'Рестораны',
    'address': 'Улица, 1',
    'description': 'Условия скидки для участников',
    'image': '',
  },
  'offers': [
    {
      'id': 'offer',
      'data': {
        'name': 'Скидка на меню',
        'percent': 15,
        'terms': 'Без суммирования',
      },
    },
  ],
};
http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Api fakeApi({Json? user}) => Api(
  base: 'http://localhost',
  client: MockClient((request) async {
    switch (request.url.path) {
      case '/api/auth/me':
        return response(user ?? member);
      case '/api/auth/login':
        return response({
          'token': 'temporary',
          'user': {...member, 'must_change_password': true},
        });
      case '/api/auth/password':
        return response({'token': 'personal', 'user': member});
      case '/api/catalog':
        return response({
          'items': [venue],
          'total': 1,
        });
      case '/api/catalog/venue':
        return response(venue);
      case '/api/banners':
        return response([]);
      case '/api/me/favorites':
        return response([]);
      case '/api/workspace/stats':
        return response({
          'total_uses': 1,
          'unique_members': 1,
          'venues': [],
          'days': {},
          'operations': [],
        });
      case '/api/workspace/resources':
        return response([]);
      default:
        return response([]);
    }
  }),
);
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'Secure session persists across Api instances and is restored by /auth/me',
    () async {
      final first = fakeApi();
      await first.login('1042', 'temporary-password', '');
      expect(await first.storage.read(key: 'session'), 'temporary');
      final restored = fakeApi();
      await restored.boot();
      expect(restored.token, 'temporary');
      expect(restored.user!['employee_number'], '1042');
    },
  );
  test(
    'Password API sends current and new password and persists rotated session',
    () async {
      Json? sent;
      final api = Api(
        base: 'http://localhost',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/password')) {
            sent = Json.from(jsonDecode(request.body) as Map);
            return response({'token': 'new-session', 'user': member});
          }
          return response(member);
        }),
      );
      await api.password('old', 'new-secret-password');
      expect(sent!['old_password'], 'old');
      expect(api.token, 'new-session');
      expect(await api.storage.read(key: 'session'), 'new-session');
    },
  );
  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    testWidgets(
      'Five mobile destinations and catalog transition at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = fakeApi()
          ..loading = false
          ..user = member;
        await tester.pumpWidget(QazaqMetalApp(api: api));
        await tester.pumpAndSettle();
        for (final label in [
          'Главная',
          'Партнёры',
          'QR',
          'На карте',
          'Профиль',
        ]) {
          expect(find.text(label), findsWidgets);
        }
        await tester.tap(find.byType(NavigationDestination).at(1));
        await tester.pumpAndSettle();
        expect(find.text('Ресторан «Тест»'), findsOneWidget);
        await tester.tap(find.text('Ресторан «Тест»'));
        await tester.pumpAndSettle();
        expect(find.text('Скидка на меню'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Mandatory password screen prevents catalog access', (
    tester,
  ) async {
    final api = fakeApi()
      ..loading = false
      ..user = {...member, 'must_change_password': true};
    await tester.pumpWidget(QazaqMetalApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Установите свой пароль'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
  testWidgets('Partner workspace works in smartphone width', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = fakeApi()
      ..loading = false
      ..user = {...member, 'role': 'partner'};
    await tester.pumpWidget(QazaqMetalApp(api: api));
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceShell), findsOneWidget);
    expect(find.text('Получено скидок'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Login scrolls above keyboard on small screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final api = fakeApi()..loading = false;
    await tester.pumpWidget(QazaqMetalApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Войти'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
