import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qazaqmetal/api.dart';
import 'package:qazaqmetal/app_settings.dart';
import 'package:qazaqmetal/ui.dart';
import 'package:qazaqmetal/pin_lock.dart';
import 'package:qazaqmetal/remote_settings_ui.dart';
import 'package:qazaqmetal/i18n.dart';
import 'system_test.dart' show fakeApi, member;
import 'access_test.dart' show enterPin;

Json defaults() => Json.from(
  jsonDecode(File('assets/app_defaults.json').readAsStringSync()) as Map,
);
Json envelope(Json data, {int revision = 1, String portal = 'member'}) => {
  'schema_version': 1,
  'revision': revision,
  'portal': portal,
  'etag': '"test-$revision"',
  'settings': data,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'QMET+',
      packageName: 'kz.qazaqmetal.qazaqmetal',
      version: '2.4.0',
      buildNumber: '20',
      buildSignature: 'test',
    );
    appLanguage.code = 'ru';
    appSettings.apply(envelope(defaults(), revision: 0));
  });
  tearDown(() {
    appSettings.apply(envelope(defaults(), revision: 0));
    appLanguage.code = 'ru';
  });

  test(
    'Default native build sends requests to public production HTTPS, never an emulator',
    () async {
      var called = false;
      final api = Api(
        client: MockClient((request) async {
          called = true;
          expect(request.url.scheme, 'https');
          expect(request.url.host, 'qazaqmetal.109.235.119.144.sslip.io');
          expect(request.url.path, '/api/meta');
          return http.Response('{"brand":"QMET+"}', 200);
        }),
      );
      addTearDown(api.dispose);
      await api.get('/meta');
      expect(called, isTrue);
    },
  );

  test(
    'Configuration survives cache restart, conditional responses and offline refresh',
    () async {
      final config = AppSettings();
      addTearDown(config.dispose);
      await config.initialize(scope: 'https://cache-test.example');
      expect(config.buildNumber, 20);
      final data = defaults()..['brand_name'] = 'Remote Club';
      var calls = 0;
      String? received;
      await config.start((etag) async {
        calls++;
        received = etag;
        return calls == 1 ? envelope(data) : null;
      });
      expect(config.brandName, 'Remote Club');
      await config.refresh();
      expect(received, '"test-1"');
      expect(config.brandName, 'Remote Club');
      final second = AppSettings();
      addTearDown(second.dispose);
      await second.initialize(scope: 'https://cache-test.example');
      expect(second.brandName, 'Remote Club');
      await second.start((_) async => throw Exception('offline'));
      expect(second.brandName, 'Remote Club');
    },
  );

  test(
    'Malformed or unsupported configuration keeps the last working values',
    () {
      final config = AppSettings();
      addTearDown(config.dispose);
      expect(
        config.apply(envelope(defaults()..['brand_name'] = 'Working')),
        isTrue,
      );
      for (final bad in [
        {...defaults(), 'logo_path': 'https://evil.example/logo.svg'},
        {...defaults(), 'accent_color': 'script'},
        {...defaults(), 'labels_ru': 'not-a-map'},
        {
          ...defaults(),
          'faq': ['not-an-object'],
        },
        {
          ...defaults(),
          'home_sections': ['executable-code'],
        },
      ]) {
        expect(config.apply(envelope(bad)), isFalse);
        expect(config.brandName, 'Working');
      }
      expect(
        config.apply({...envelope(defaults()), 'schema_version': 2}),
        isFalse,
      );
      expect(config.brandName, 'Working');
    },
  );

  test('Version rules reject unsafe URLs and never lock administrators', () {
    final config = AppSettings()..buildNumber = 20;
    addTearDown(config.dispose);
    final data = defaults();
    data['versions']['member']['android'] = {
      'minimum_build': 21,
      'latest_build': 21,
      'store_url': 'https://github.com/milaniumkz/krug-club-prototype/releases',
    };
    expect(config.apply(envelope(data)), isTrue);
    expect(config.needsUpdate('member', 'android'), isTrue);
    expect(config.needsUpdate('admin', 'android'), isFalse);
    data['versions']['member']['android']['store_url'] = 'javascript:alert(1)';
    expect(config.apply(envelope(data)), isFalse);
  });

  testWidgets(
    'Remote branding, colour and maintenance preserve the unlocked PIN session',
    (tester) async {
      final apiLocked = fakeApi()
        ..user = member
        ..loading = false;
      addTearDown(apiLocked.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => SettingsScope(
            child: ListenableBuilder(
              listenable: appSettings,
              builder: (context, _) =>
                  RemotePolicyOverlay(api: apiLocked, child: child!),
            ),
          ),
          home: PinLock(
            api: apiLocked,
            biometricsAllowed: false,
            child: const Scaffold(body: Brand()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await enterPin(tester, '472918');
      await enterPin(tester, '472918');
      final stored = await apiLocked.storage.read(key: 'local-pin-member');
      final changed = defaults()
        ..['brand_name'] = 'Remote Club'
        ..['accent_color'] = '#234987';
      appSettings.apply(envelope(changed));
      await tester.pumpAndSettle();
      expect(find.text('Введите PIN-код'), findsNothing);
      expect(find.text('Создайте PIN-код'), findsNothing);
      expect(find.text('Remote Club'), findsWidgets);
      appSettings.apply(
        envelope({...changed, 'maintenance': true}, revision: 2),
      );
      await tester.pumpAndSettle();
      expect(find.text('Техническое обслуживание'), findsOneWidget);
      appSettings.apply(envelope(changed, revision: 3));
      await tester.pumpAndSettle();
      expect(find.text('Введите PIN-код'), findsNothing);
      expect(await apiLocked.storage.read(key: 'local-pin-member'), stored);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets('Administrator edits remote settings at ${width}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Json? submitted;
      final api =
          Api(
              base: 'https://admin.example',
              client: MockClient((r) async {
                if (r.method == 'PUT') {
                  submitted = Json.from(jsonDecode(r.body) as Map);
                }
                return http.Response(
                  jsonEncode(
                    envelope(
                      submitted?['settings'] as Json? ?? defaults(),
                      portal: 'admin',
                    ),
                  ),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                );
              }),
            )
            ..user = {...member, 'role': 'admin'}
            ..loading = false;
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminAppSettingsPage(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      final brand = find.byKey(const ValueKey('settings-1-brand_name'));
      await tester.scrollUntilVisible(
        brand,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(brand, 'QMET+ Edited');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('save-app-settings')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('save-app-settings')));
      await tester.pumpAndSettle();
      expect(submitted?['expected_revision'], 1);
      expect(submitted?['settings']['brand_name'], 'QMET+ Edited');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
