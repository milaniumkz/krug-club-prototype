import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qazaqmetal/main.dart';
import 'package:qazaqmetal/pin_lock.dart';
import 'package:qazaqmetal/i18n.dart';
import 'system_test.dart' show fakeApi, member;

Future<void> enterPin(WidgetTester tester, String value) async {
  for (final digit in value.split('')) {
    final key = find.byKey(ValueKey('pin-digit-$digit'));
    await tester.ensureVisible(key);
    await tester.tap(key);
    await tester.pumpAndSettle();
  }
}

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
      expect(find.byType(TextField), findsNothing);
      await enterPin(tester, '123456');
      await enterPin(tester, '123456');
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
      await enterPin(tester, '000000');
      await tester.pumpAndSettle();
      expect(find.text('Неверный PIN-код'), findsOneWidget);
      expect(find.text('Защищённый экран'), findsNothing);
      await enterPin(tester, '123456');
      await tester.pumpAndSettle();
      expect(find.text('Защищённый экран'), findsOneWidget);
    },
  );
  test(
    'PIN lifecycle retains on boot and rotation, resets on logout and credential login',
    () async {
      final api = fakeApi()..user = member;
      for (final suffix in ['', '-biometrics', '-attempts', '-blocked']) {
        await api.storage.write(
          key: 'local-pin-member$suffix',
          value: 'stored',
        );
      }
      await api.boot();
      expect(await api.storage.read(key: 'local-pin-member'), 'stored');
      await api.password('old', 'new123');
      expect(await api.storage.read(key: 'local-pin-member'), 'stored');
      await api.logout();
      for (final suffix in ['', '-biometrics', '-attempts', '-blocked']) {
        expect(await api.storage.read(key: 'local-pin-member$suffix'), isNull);
      }
      await api.storage.write(
        key: 'local-pin-member',
        value: 'orphan-from-old-session',
      );
      await api.login('1042', 'new123', '');
      expect(await api.storage.read(key: 'local-pin-member'), isNull);
    },
  );
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets(
      'Custom keypad deletion, confirmation and no OS keyboard at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = fakeApi()..user = member;
        await tester.pumpWidget(
          MaterialApp(
            home: PinLock(
              api: api,
              biometricsAllowed: false,
              child: const Text('Unlocked'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(EditableText), findsNothing);
        expect(tester.testTextInput.isVisible, isFalse);
        await enterPin(tester, '12');
        await tester.tap(find.byKey(const ValueKey('pin-delete')));
        await tester.pump();
        expect(tester.widget<PinPad>(find.byType(PinPad)).value, '1');
        await enterPin(tester, '23456');
        await enterPin(tester, '000000');
        expect(find.text('PIN-коды должны совпадать'), findsOneWidget);
        expect(await api.storage.read(key: 'local-pin-member'), isNull);
        await enterPin(tester, '123456');
        expect(find.text('Unlocked'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
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
