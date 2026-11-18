import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qazaqmetal/main.dart';
import 'package:qazaqmetal/pin_lock.dart';
import 'package:qazaqmetal/i18n.dart';
import 'system_test.dart' show fakeApi, member;

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    appLanguage.code = 'ru';
  });
  tearDown(() => appLanguage.code = 'ru');
  testWidgets(
    'PIN is created, stored as salted hash, requested again and rejects a wrong code',
    (tester) async {
      final api = fakeApi()
        ..user = member
        ..loading = false;
      Widget app() => MaterialApp(
        home: PinLock(
          api: api,
          biometricsAllowed: false,
          child: const Scaffold(body: Text('Защищённый экран')),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Создайте PIN-код'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), '123456');
      await tester.enterText(find.byType(TextField).at(1), '123456');
      await tester.tap(find.text('Сохранить PIN-код'));
      await tester.pumpAndSettle();
      expect(find.text('Защищённый экран'), findsOneWidget);
      final stored = await api.storage.read(key: 'local-pin-member');
      expect(stored, isNotNull);
      expect(stored!.contains('123456'), isFalse);
      final value = jsonDecode(stored) as Map;
      expect(value['salt'], isNotEmpty);
      expect(value['hash'], hasLength(64));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Введите PIN-код'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('Открыть приложение'));
      await tester.pumpAndSettle();
      expect(find.text('Неверный PIN-код'), findsOneWidget);
      expect(find.text('Защищённый экран'), findsNothing);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Открыть приложение'));
      await tester.pumpAndSettle();
      expect(find.text('Защищённый экран'), findsOneWidget);
    },
  );
  testWidgets(
    'Login language switch translates fields and persists Kazakh preference',
    (tester) async {
      final api = fakeApi()..loading = false;
      await tester.pumpWidget(QazaqMetalApp(api: api));
      await tester.pumpAndSettle();
      expect(find.text('Табельный номер'), findsOneWidget);
      expect(find.text('Табельный номер / телефон / логин'), findsNothing);
      await tester.tap(find.text('ҚАЗ'));
      await tester.pumpAndSettle();
      expect(find.text('Табельдік нөмір'), findsOneWidget);
      expect(find.text('Құпиясөз'), findsOneWidget);
      expect(await const FlutterSecureStorage().read(key: 'ui-language'), 'kk');
    },
  );
  testWidgets('Secondary venue page retains five bottom destinations', (
    tester,
  ) async {
    final api = fakeApi()
      ..user = member
      ..loading = false;
    await tester.pumpWidget(QazaqMetalApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ресторан «Тест»').first);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    await tester.tap(find.byType(NavigationDestination).last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );
    await tester.scrollUntilVisible(find.text('Изменить пароль'), 300);
    expect(find.text('Изменить пароль'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
