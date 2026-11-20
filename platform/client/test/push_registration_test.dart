import 'dart:async';
import 'dart:convert';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qazaqmetal/api.dart';
import 'package:qazaqmetal/push_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'iOS registration proceeds while launch-message discovery is pending',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      setupFirebaseCoreMocks();
      final launch = Completer<Map<String, dynamic>?>();
      addTearDown(() {
        if (!launch.isCompleted) launch.complete(null);
      });
      final calls = <String>[];
      const channel = MethodChannel('plugins.flutter.io/firebase_messaging');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            switch (call.method) {
              case 'Messaging#getInitialMessage':
                return launch.future;
              case 'Messaging#getNotificationSettings':
                return {'authorizationStatus': -1};
              case 'Messaging#requestPermission':
                return {'authorizationStatus': 1};
              case 'Messaging#getAPNSToken':
                return {'token': 'test-apns-token'};
              case 'Messaging#getToken':
                return {'token': 'test-fcm-token'};
              default:
                return null;
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      Map<String, dynamic>? registration;
      final api =
          Api(
              base: 'https://review.example',
              client: MockClient((request) async {
                if (request.url.path == '/api/push-config') {
                  return http.Response(
                    jsonEncode({
                      'enabled': true,
                      'options': {
                        'apiKey': '123',
                        'appId': '123',
                        'messagingSenderId': '123',
                        'projectId': '123',
                      },
                    }),
                    200,
                  );
                }
                if (request.url.path == '/api/me/push-devices') {
                  registration =
                      jsonDecode(request.body) as Map<String, dynamic>;
                  return http.Response('{}', 200);
                }
                return http.Response('{}', 404);
              }),
            )
            ..user = {
              'id': 'review-member',
              'role': 'member',
              'must_change_password': false,
            };
      addTearDown(api.dispose);
      final service = PushService(api, onForeground: (_) {});
      await service.sync().timeout(const Duration(seconds: 3));
      expect(launch.isCompleted, isFalse);
      expect(calls, contains('Messaging#getInitialMessage'));
      expect(calls, contains('Messaging#requestPermission'));
      expect(registration, containsPair('token', 'test-fcm-token'));
      expect(registration, containsPair('platform', 'ios'));
      expect(service.busy, isFalse);
      expect(service.status, 'Уведомления включены на этом устройстве');
      launch.complete(null);
    },
  );
}
