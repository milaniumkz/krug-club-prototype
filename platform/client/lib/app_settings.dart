import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

final appSettings = AppSettings();

/// Public data only. Invalid/offline responses never clear session or PIN.
class AppSettings extends ChangeNotifier with WidgetsBindingObserver {
  final FlutterSecureStorage storage;
  AppSettings({FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();
  Map<String, dynamic> _defaults = {
    'brand_name': 'QMET+',
    'logo_path': '',
    'accent_color': '#6e2ebd',
    'background_color': '#f8f3ef',
    'features': {'qr': true, 'map': true, 'push': true, 'banners': true},
    'home_sections': ['promotions', 'partners'],
  };
  Map<String, dynamic> _data = {};
  Map<String, dynamic> get data =>
      jsonDecode(jsonEncode({..._defaults, ..._data})) as Map<String, dynamic>;
  String portal = '', base = '', version = '', _cacheKey = 'public-settings-v1';
  String? etag;
  int revision = 0, buildNumber = 0;
  bool busy = false, _started = false;
  Timer? _timer;
  Future<Map<String, dynamic>?> Function(String?)? _fetch;

  String get brandName =>
      (_data['brand_name'] ?? _defaults['brand_name']).toString();
  String get logoPath => (_data['logo_path'] ?? '').toString();
  String get logoUrl => logoPath.isEmpty ? '' : '$base$logoPath';
  Color get accent =>
      _color(_data['accent_color'] ?? _defaults['accent_color']);
  Color get background =>
      _color(_data['background_color'] ?? _defaults['background_color']);
  Color _color(dynamic value) =>
      Color(int.parse('ff${value.toString().substring(1)}', radix: 16));
  bool feature(String key) =>
      ((_data['features'] ?? _defaults['features']) as Map?)?[key] != false;
  bool get maintenance => _data['maintenance'] == true;
  String text(String key, String language, {String fallback = ''}) =>
      (_data['${key}_$language'] ?? _defaults['${key}_$language'] ?? fallback)
          .toString();
  String label(String key, String language, String fallback) =>
      ((_data['labels_$language'] ?? _defaults['labels_$language'])
              as Map?)?[key]
          ?.toString() ??
      fallback;
  List<String> get homeSections => List<String>.from(
    _data['home_sections'] ??
        _defaults['home_sections'] ??
        ['promotions', 'partners'],
  );
  List<Map<String, dynamic>> get faq => List<Map<String, dynamic>>.from(
    (_data['faq'] ?? _defaults['faq'] ?? []) as List,
  );
  String value(String key) => (_data[key] ?? _defaults[key] ?? '').toString();

  Map<String, dynamic> versionPolicy(String role, String platform) {
    final versions = _data['versions'] ?? _defaults['versions'];
    if (versions is! Map || versions[role] is! Map) return {};
    final result = versions[role][platform];
    return result is Map ? Map<String, dynamic>.from(result) : {};
  }

  bool needsUpdate(String role, String platform) =>
      role != 'admin' &&
      (versionPolicy(role, platform)['minimum_build'] as int? ?? 0) >
          buildNumber;
  String updateUrl(String role, String platform) =>
      versionPolicy(role, platform)['store_url']?.toString() ?? '';

  Future<void> initialize({required String scope}) async {
    base = scope;
    _cacheKey = 'public-settings-v1-${base64Url.encode(utf8.encode(scope))}';
    try {
      _defaults = Map<String, dynamic>.from(
        jsonDecode(await rootBundle.loadString('assets/app_defaults.json'))
            as Map,
      );
    } catch (_) {
      /* Bundled minimal defaults still work in tests or damaged cache. */
    }
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      /* An unknown version never affects credentials. */
    }
    try {
      final cached = await storage.read(key: _cacheKey);
      if (cached != null) {
        apply(Map<String, dynamic>.from(jsonDecode(cached) as Map));
      }
    } catch (_) {
      /* Keep packaged defaults. */
    }
  }

  Future<void> start(Future<Map<String, dynamic>?> Function(String?) fetch) {
    _fetch = fetch;
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addObserver(this);
      _timer = Timer.periodic(const Duration(minutes: 2), (_) => refresh());
    }
    return refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (busy || _fetch == null) return;
    busy = true;
    try {
      final reply = await _fetch!(etag);
      if (reply != null && apply(reply)) {
        try {
          await storage.write(key: _cacheKey, value: jsonEncode(reply));
        } catch (_) {}
      }
    } catch (_) {
      /* Offline: last known configuration stays in place. */
    } finally {
      busy = false;
    }
  }

  bool apply(Map<String, dynamic> reply) {
    try {
      if (reply['schema_version'] != 1 || reply['settings'] is! Map) {
        return false;
      }
      final input = Map<String, dynamic>.from(reply['settings'] as Map);
      final d = {..._defaults, ...input};
      if (d['brand_name'] is! String ||
          (d['brand_name'] as String).length > 24 ||
          (d['brand_name'] as String).trim().isEmpty) {
        return false;
      }
      for (final key in ['accent_color', 'background_color']) {
        if (d[key] is! String ||
            !RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(d[key] as String)) {
          return false;
        }
      }
      if (1.05 / (_color(d['accent_color']).computeLuminance() + .05) < 4.5 ||
          _color(d['background_color']).computeLuminance() < .72) {
        return false;
      }
      if (d['logo_path'] != '' &&
          !RegExp(
            r'^/media/[a-f0-9]{32}\.webp$',
          ).hasMatch(d['logo_path'].toString())) {
        return false;
      }
      if (d['features'] is! Map ||
          (d['features'] as Map).values.any((v) => v is! bool)) {
        return false;
      }
      if (d['home_sections'] is! List ||
          (d['home_sections'] as List).any(
            (v) => !['promotions', 'partners'].contains(v),
          )) {
        return false;
      }
      if ((d['home_sections'] as List).toSet().length !=
          (d['home_sections'] as List).length) {
        return false;
      }
      for (final role in ['member', 'partner']) {
        for (final platform in ['android', 'ios']) {
          final policy = ((d['versions'] as Map?)?[role] as Map?)?[platform];
          if (policy == null) continue;
          if (policy is! Map ||
              policy['minimum_build'] is! int ||
              policy['latest_build'] is! int ||
              policy['minimum_build'] < 0 ||
              policy['latest_build'] < policy['minimum_build']) {
            return false;
          }
          final url = Uri.tryParse(policy['store_url']?.toString() ?? '');
          if ((policy['minimum_build'] > 0 ||
                  (policy['store_url']?.toString() ?? '').isNotEmpty) &&
              (url == null ||
                  url.scheme != 'https' ||
                  ![
                    'play.google.com',
                    'apps.apple.com',
                    'github.com',
                  ].contains(url.host) ||
                  url.userInfo.isNotEmpty)) {
            return false;
          }
        }
      }
      for (final key in ['labels_ru', 'labels_kk']) {
        final labels = d[key];
        if (labels != null &&
            (labels is! Map ||
                labels.values.any(
                  (v) => v is! String || v.trim().isEmpty || v.length > 24,
                ))) {
          return false;
        }
      }
      if (d['faq'] != null &&
          (d['faq'] is! List ||
              (d['faq'] as List).length > 20 ||
              (d['faq'] as List).any(
                (q) =>
                    q is! Map ||
                    [
                      'question_ru',
                      'answer_ru',
                      'question_kk',
                      'answer_kk',
                    ].any((key) => q[key] is! String),
              ))) {
        return false;
      }
      if (reply['etag'] != null &&
          (reply['etag'] is! String ||
              (reply['etag'] as String).length > 128 ||
              RegExp(r'[\r\n]').hasMatch(reply['etag'] as String))) {
        return false;
      }
      if (RegExp(r'[\x00-\x1f]').hasMatch(d['brand_name'] as String)) {
        return false;
      }
      _data = d;
      portal = ['member', 'partner', 'admin'].contains(reply['portal'])
          ? reply['portal'] as String
          : portal;
      revision = reply['revision'] is int ? reply['revision'] as int : revision;
      etag = reply['etag'] as String?;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class SettingsScope extends InheritedNotifier<AppSettings> {
  SettingsScope({super.key, required super.child})
    : super(notifier: appSettings);
  static void watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<SettingsScope>();
  }
}
