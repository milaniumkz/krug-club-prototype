import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';
import 'i18n.dart';

/// No prompts or Firebase startup until the owner configures a client project.
class PushService {
  final Api api;
  final void Function(String) onForeground;
  bool busy = false, initialized = false, listened = false;
  String? registered;
  PushService(this.api, {required this.onForeground});
  void start() {
    if (kIsWeb) {
      return;
    } // Browser inbox is available; Web Push requires VAPID later.
    api.addListener(sync);
    appLanguage.addListener(sync);
    unawaited(sync());
  }

  Future<void> sync() async {
    if (api.user == null) {
      registered = null;
      onForeground('');
      return;
    }
    if (busy || api.user!['must_change_password'] == true) return;
    final owner = s(api.user!['id']);
    busy = true;
    try {
      if (!initialized) {
        final config = await api.get(
          '/push-config?platform=${defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'}',
        );
        if (config['enabled'] != true) return;
        final d = Json.from(config['options'] as Map);
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: s(d['apiKey']),
            appId: s(d['appId']),
            messagingSenderId: s(d['messagingSenderId']),
            projectId: s(d['projectId']),
            storageBucket: d['storageBucket'] as String?,
            iosBundleId: d['iosBundleId'] as String?,
          ),
        );
        initialized = true;
      }
      if (!listened) {
        listened = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((_) {
          registered = null;
          sync();
        });
        FirebaseMessaging.onMessage.listen((message) {
          if (api.user == null) return;
          onForeground(
            [
              message.notification?.title,
              message.notification?.body,
            ].whereType<String>().join('\n'),
          );
        });
        FirebaseMessaging.onMessageOpenedApp.listen((_) {
          if (api.user != null) api.openNotifications();
        });
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) api.openNotifications();
      }
      final permission = await FirebaseMessaging.instance.requestPermission();
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: true,
            sound: true,
          );
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || api.user?['id'] != owner) return;
      final key = '$owner:${appLanguage.code}:$token';
      if (registered == key) return;
      await api.post('/me/push-devices', {
        'token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        'language': appLanguage.code,
      });
      registered = key;
    } catch (_) {
      // A missing project, denied permission or offline device must not prevent login.
    } finally {
      busy = false;
    }
  }
}
