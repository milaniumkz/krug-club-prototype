import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';
import 'app_settings.dart';
import 'firebase_web_loader.dart';
import 'i18n.dart';

/// One service per signed-in app; web permissions are requested on a user tap.
class PushService extends ChangeNotifier {
  static PushService? current;
  final Api api;
  final void Function(String) onForeground;
  bool busy = false, initialized = false, listened = false;
  String? registered, vapidKey;
  String status = 'Включите уведомления о новых заведениях и предложениях';
  bool pendingOpen = Uri.base.queryParameters.containsKey('notification');
  PushService(this.api, {required this.onForeground});
  String get platform => kIsWeb
      ? 'web'
      : defaultTargetPlatform == TargetPlatform.iOS
      ? 'ios'
      : 'android';
  void start() {
    current = this;
    api.addListener(sync);
    appLanguage.addListener(sync);
    appSettings.addListener(sync);
    unawaited(sync());
  }

  Future<void> sync({bool requestPermission = false}) async {
    if (api.user == null) {
      registered = null;
      onForeground('');
      return;
    }
    if (!appSettings.feature('push')) {
      status = 'Уведомления временно отключены';
      notifyListeners();
      return;
    }
    if (api.user!['role'] == 'admin' ||
        busy ||
        api.user!['must_change_password'] == true) {
      return;
    }
    final owner = s(api.user!['id']);
    busy = true;
    if (pendingOpen) {
      pendingOpen = false;
      api.openNotifications();
    }
    try {
      if (!initialized) {
        final config = await api.get('/push-config?platform=$platform');
        if (config['enabled'] != true) {
          status = 'Уведомления пока не подключены';
          return;
        }
        final d = Json.from(config['options'] as Map);
        vapidKey = config['vapidKey'] as String?;
        await prepareFirebaseWeb();
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: s(d['apiKey']),
            appId: s(d['appId']),
            messagingSenderId: s(d['messagingSenderId']),
            projectId: s(d['projectId']),
            storageBucket: d['storageBucket'] as String?,
            iosBundleId: d['iosBundleId'] as String?,
            authDomain: d['authDomain'] as String?,
          ),
        );
        initialized = true;
      }
      if (!await FirebaseMessaging.instance.isSupported()) {
        status =
            'Этот браузер не поддерживает push. Центр уведомлений доступен';
        return;
      }
      if (!listened) {
        listened = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((_) {
          registered = null;
          unawaited(sync());
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
          if (api.user != null) {
            api.openNotifications();
          } else {
            pendingOpen = true;
          }
        });
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) api.openNotifications();
      }
      var permission = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (permission.authorizationStatus == AuthorizationStatus.notDetermined &&
          (!kIsWeb || requestPermission)) {
        permission = await FirebaseMessaging.instance.requestPermission();
      }
      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        status = 'Разрешите уведомления в настройках устройства или браузера';
        return;
      }
      if (permission.authorizationStatus == AuthorizationStatus.notDetermined) {
        return;
      }
      if (!kIsWeb) {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
              alert: false,
              badge: true,
              sound: true,
            );
        if (platform == 'ios' &&
            await FirebaseMessaging.instance.getAPNSToken() == null) {
          status = 'Push для iOS будет доступен после подключения APNs';
          return;
        }
      }
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: vapidKey,
      );
      if (token == null || api.user?['id'] != owner) return;
      final key = '$owner:${appLanguage.code}:$token';
      if (registered != key) {
        await api.post('/me/push-devices', {
          'token': token,
          'platform': platform,
          'language': appLanguage.code,
        });
        registered = key;
      }
      status = 'Уведомления включены на этом устройстве';
    } catch (_) {
      status = 'Не удалось подключить уведомления. Попробуйте ещё раз';
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

class PushSettings extends StatelessWidget {
  final Api api;
  const PushSettings({super.key, required this.api});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    final service = PushService.current;
    if (service == null || api.user?['role'] == 'admin') {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppText(service.status, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: service.busy
                  ? null
                  : () => service.sync(requestPermission: true),
              icon: const Icon(Icons.notifications_active_outlined),
              label: AppText(
                service.registered == null
                    ? 'Включить уведомления'
                    : 'Проверить подключение',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
