import 'i18n.dart';
import 'tab_pin.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'transport.dart';

typedef Json = Map<String, dynamic>;
String s(dynamic value) => value?.toString() ?? '';
List<Json> rows(dynamic value) =>
    (value as List).map((e) => Json.from(e as Map)).toList();

class ApiError implements Exception {
  final int status;
  final String message;
  ApiError(this.status, this.message);
  @override
  String toString() => tx(message);
}

class Api extends ChangeNotifier {
  final http.Client client;
  final bool watchSessions;
  http.Client? _watchClient;
  int _watchGeneration = 0;
  final String base;
  final FlutterSecureStorage storage;
  String? token;
  Json? user;
  bool loading = true;
  bool notificationsRequested = false;
  void openNotifications() {
    notificationsRequested = true;
    notifyListeners();
  }

  String? bootError;
  Api({
    http.Client? client,
    String? base,
    FlutterSecureStorage? storage,
    bool? watchSessions,
  }) : watchSessions = watchSessions ?? client == null,
       client = client ?? makeClient(),
       base =
           base ??
           (kIsWeb
               ? Uri.base.origin
               : const String.fromEnvironment(
                   'API_BASE_URL',
                   defaultValue: 'http://10.0.2.2:8000',
                 )),
       storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.first_unlock_this_device,
             ),
           );
  bool get supportsPin =>
      user?['role'] == 'member' || (!kIsWeb && user?['role'] == 'partner');

  String get portal {
    if (kIsWeb) {
      final host = Uri.base.host.toLowerCase();
      if (host.startsWith('qazaqmetalpartners.')) return 'partner';
      if (host.startsWith('qazaqmetaladmin.')) return 'admin';
    }
    return const String.fromEnvironment('PORTAL', defaultValue: 'member');
  }

  Map<String, String> get headers => {
    'X-QM-Client': 'web',
    if (!kIsWeb && token != null) 'Authorization': 'Bearer $token',
  };
  Future<void> boot() async {
    loading = true;
    bootError = null;
    notifyListeners();
    try {
      if (!kIsWeb) {
        token = await storage.read(key: 'session');
      }
      user = Json.from(await get('/auth/me') as Map);
    } on ApiError catch (e) {
      if (e.status == 401 || e.status == 403) {
        await clear();
      } else {
        bootError = e.message;
      }
    } catch (_) {
      bootError = 'Не удалось прочитать защищённую сессию';
    }
    loading = false;
    if (user != null) _startWatch();
    notifyListeners();
  }

  void _startWatch() {
    if (!watchSessions) return;
    _watchClient?.close();
    final generation = ++_watchGeneration;
    final watcher = _watchClient = makeClient();
    () async {
      while (generation == _watchGeneration && user != null) {
        try {
          final response = await watcher
              .post(Uri.parse('$base/api/auth/watch'), headers: headers)
              .timeout(const Duration(seconds: 35));
          if (generation != _watchGeneration) break;
          if (response.statusCode >= 500) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
          if (response.statusCode == 401 ||
              response.statusCode == 403 ||
              (response.statusCode == 200 &&
                  jsonDecode(response.body)['active'] == false)) {
            await clear();
            break;
          }
        } catch (_) {
          if (generation != _watchGeneration) break;
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }();
  }

  @override
  void dispose() {
    ++_watchGeneration;
    _watchClient?.close();
    client.close();
    super.dispose();
  }

  Future<void> resetLocalPin(String userId) async {
    for (final suffix in ['', '-biometrics', '-attempts', '-blocked']) {
      await storage.delete(key: 'local-pin-$userId$suffix');
    }
  }

  Future<void> clear() async {
    notificationsRequested = false;
    clearTabUnlock();
    final previousUserId = user?['id']?.toString();
    ++_watchGeneration;
    _watchClient?.close();
    user = null;
    token = null;
    if (previousUserId != null) await resetLocalPin(previousUserId);
    if (!kIsWeb) {
      await storage.delete(key: 'session');
    }
    notifyListeners();
  }

  Future<dynamic> get(String path) => request('GET', path);
  Future<dynamic> post(String path, [Json? data]) =>
      request('POST', path, data);
  Future<dynamic> request(String method, String path, [Json? data]) async {
    try {
      final req = http.Request(method, Uri.parse('$base/api$path'))
        ..headers.addAll(headers);
      if (data != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(data);
      }
      final response = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(seconds: 60)),
      );
      final dynamic body = response.body.isEmpty
          ? {}
          : jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode >= 400) {
        final detail = body is Map ? body['detail'] : null;
        final closedAccess =
            response.statusCode == 403 &&
            detail is String &&
            (detail.startsWith('Доступ приостановлен') ||
                detail == 'Организация отключена' ||
                detail == 'Доступ партнёра приостановлен' ||
                detail.startsWith('Срок членства истёк'));
        if ((response.statusCode == 401 && path != '/auth/login') ||
            closedAccess) {
          await clear();
        }
        throw ApiError(
          response.statusCode,
          detail is String ? detail : 'Проверьте заполнение полей',
        );
      }
      return body;
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw ApiError(
        0,
        'Сервер не ответил. Проверьте интернет и повторите попытку',
      );
    } catch (_) {
      throw ApiError(0, 'Не удалось связаться с сервером. Повторите попытку');
    }
  }

  Future<void> accept(dynamic result) async {
    token = s(result['token']);
    user = Json.from(result['user'] as Map);
    if (!kIsWeb) {
      await storage.write(key: 'session', value: token);
    }
    user = Json.from(await get('/auth/me') as Map);
    _startWatch();
    notifyListeners();
  }

  Future<void> login(String id, String password, String org) async {
    final result = await post('/auth/login', {
      'identifier': id,
      'password': password,
      'organization_code': org,
      'portal': portal,
    });
    // A credential login starts a new PIN lifecycle. Boot and password rotation
    // retain the PIN belonging to the continuing authenticated session.
    clearTabUnlock();
    await resetLocalPin(s(result['user']['id']));
    await accept(result);
  }

  Future<void> password(String old, String value) async {
    ++_watchGeneration;
    _watchClient?.close();
    try {
      await accept(
        await post('/auth/password', {
          'old_password': old,
          'new_password': value,
        }),
      );
    } catch (_) {
      if (user != null) _startWatch();
      rethrow;
    }
  }

  Future<void> logout() async {
    await post('/auth/logout');
    await clear();
  }

  Future<String> upload(XFile file) async {
    final data = await file.readAsBytes();
    if (data.length > 8 * 1024 * 1024) {
      throw ApiError(413, 'Изображение не больше 8 МБ');
    }
    final request = http.MultipartRequest('POST', Uri.parse('$base/api/media'))
      ..headers.addAll(headers)
      ..files.add(
        http.MultipartFile.fromBytes('file', data, filename: file.name),
      );
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 60)),
    );
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 201) {
      throw ApiError(response.statusCode, s(body['detail']));
    }
    return s(body['path']);
  }

  Future<dynamic> importMembers(XFile file, String org) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > 1024 * 1024) {
      throw ApiError(413, 'CSV не больше 1 МБ');
    }
    final req =
        http.MultipartRequest(
            'POST',
            Uri.parse('$base/api/admin/accounts/import?organization_id=$org'),
          )
          ..headers.addAll(headers)
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: file.name),
          );
    final response = await http.Response.fromStream(
      await client.send(req).timeout(const Duration(seconds: 120)),
    );
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 400) {
      throw ApiError(response.statusCode, s(body['detail']));
    }
    return body;
  }
}

String human(dynamic value) =>
    const <String, String>{
      'member': 'Участник',
      'partner': 'Партнёр',
      'admin': 'Администратор',
      'active': 'Активен',
      'blocked': 'Заблокирован',
      'dismissed': 'Уволен',
      'open': 'Новое',
      'in_progress': 'В работе',
      'closed': 'Закрыто',
      'venue': 'Заведение',
      'offer': 'Скидка / акция',
      'banner': 'Баннер',
      'name': 'Название',
      'description': 'Описание',
      'category': 'Категория',
      'address': 'Адрес',
      'phone': 'Телефон',
      'hours': 'Режим работы',
      'image': 'Изображение',
      'latitude': 'Широта',
      'longitude': 'Долгота',
      'percent': 'Скидка, %',
      'terms': 'Условия',
      'starts_on': 'Начало',
      'ends_on': 'Окончание',
      'organization_ids': 'Доступные организации',
      'login': 'Вход в систему',
      'password_changed': 'Смена пароля',
      'password_reset': 'Выдан временный пароль',
      'content_submitted': 'Контент отправлен на модерацию',
      'moderation_approved': 'Изменения одобрены',
      'moderation_rejected': 'Изменения отклонены',
      'privilege_used': 'Получена скидка',
      'qr_rotated': 'Выдан новый QR-код',
      'account_created': 'Создан аккаунт',
      'account_status_changed': 'Изменён доступ',
      'organization_created': 'Создана организация',
      'organization_updated': 'Изменена организация',
      'partner_created': 'Добавлен партнёр',
      'partner_updated': 'Изменён партнёр',
      'visibility_changed': 'Изменена видимость',
      'ticket_created': 'Новое обращение',
      'ticket_replied': 'Ответ на обращение',
      'bootstrap_admin': 'Создан первый администратор',
      'reference_imported': 'Импортированы исходные сведения',
    }[s(value)] ??
    s(value);

Json localizedData(Json resource) {
  final data = Json.from(resource['data'] as Map);
  if (appLanguage.code == 'kk') {
    for (final key in [
      'name',
      'description',
      'category',
      'address',
      'hours',
      'terms',
    ]) {
      final translated = s(data['${key}_kk']);
      if (translated.isNotEmpty) data[key] = translated;
    }
  }
  return data;
}
