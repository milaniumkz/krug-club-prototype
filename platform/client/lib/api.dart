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
  String toString() => message;
}

class Api extends ChangeNotifier {
  final http.Client client;
  final String base;
  final FlutterSecureStorage storage;
  String? token;
  Json? user;
  bool loading = true;
  String? bootError;
  Api({http.Client? client, String? base, FlutterSecureStorage? storage})
    : client = client ?? makeClient(),
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
    notifyListeners();
  }

  Future<void> clear() async {
    user = null;
    token = null;
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
        if (response.statusCode == 401 && path != '/auth/login') {
          await clear();
        }
        final detail = body is Map ? body['detail'] : null;
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
    notifyListeners();
  }

  Future<void> login(String id, String password, String org) async {
    await accept(
      await post('/auth/login', {
        'identifier': id,
        'password': password,
        'organization_code': org,
      }),
    );
  }

  Future<void> password(String old, String value) async {
    await accept(
      await post('/auth/password', {
        'old_password': old,
        'new_password': value,
      }),
    );
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
