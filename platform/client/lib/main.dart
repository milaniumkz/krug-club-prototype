import 'dart:async';
import 'i18n.dart';
import 'app_settings.dart';
import 'remote_settings_ui.dart';
import 'push_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'api.dart';
import 'pin_lock.dart';
import 'ui.dart';
import 'member.dart';
import 'workspace.dart';

final appMessenger = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl(
      '${Uri.base.origin}/zxing.min.js',
    );
    MobileScannerPlatform.instance.setWebBarcodeReader(
      WebBarcodeReader.zxingJs,
    );
  }
  await appLanguage.load();
  final api = Api();
  await appSettings.initialize(scope: api.base);
  unawaited(appSettings.start(api.fetchAppConfig));
  PushService(
    api,
    onForeground: (message) {
      if (message.isEmpty) {
        appMessenger.currentState?.hideCurrentSnackBar();
        return;
      }
      appMessenger.currentState?.showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: tx('Открыть'),
            onPressed: api.openNotifications,
          ),
        ),
      );
    },
  ).start();
  runApp(QazaqMetalApp(api: api..boot()));
}

class QazaqMetalApp extends StatelessWidget {
  final Api api;
  const QazaqMetalApp({super.key, required this.api});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([api, appLanguage, appSettings]),
      builder: (context, _) => MaterialApp(
        key: ValueKey(api.user?['id'] ?? 'guest'),
        title: appSettings.brandName,
        builder: (context, child) => SettingsScope(
          child: RemotePolicyOverlay(
            api: api,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        scaffoldMessengerKey: appMessenger,
        debugShowCheckedModeBanner: false,
        locale: Locale(appLanguage.code),
        supportedLocales: const [Locale('ru'), Locale('kk'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Manrope',
          splashFactory: InkSparkle.splashFactory,
          scaffoldBackgroundColor: paper,
          dividerTheme: const DividerThemeData(color: paleBorder, thickness: 1),
          colorScheme: ColorScheme.fromSeed(
            seedColor: purple,
            surface: paper,
          ).copyWith(primary: purple, onPrimary: Colors.white),
          appBarTheme: AppBarTheme(
            backgroundColor: paper,
            foregroundColor: ink,
            scrolledUnderElevation: 0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xfff0e9ec),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 50)),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Color(0xfffffcf9),
            indicatorColor: lavender,
            labelTextStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        home: api.loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : api.bootError != null
            ? Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppText(api.bootError!, textAlign: TextAlign.center),
                        ActionButton(
                          'Повторить подключение',
                          onPressed: api.boot,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : api.user == null
            ? LoginPage(api: api)
            : api.user!['must_change_password'] == true
            ? PasswordPage(api: api, mandatory: true)
            : api.watchSessions && api.supportsPin
            ? PinLock(
                api: api,
                child: api.user!['role'] == 'member'
                    ? MemberShell(key: ValueKey(api.user!['id']), api: api)
                    : WorkspaceShell(key: ValueKey(api.user!['id']), api: api),
              )
            : api.user!['role'] == 'member'
            ? MemberShell(key: ValueKey(api.user!['id']), api: api)
            : WorkspaceShell(key: ValueKey(api.user!['id']), api: api),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  final Api api;
  const LoginPage({super.key, required this.api});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final id = TextEditingController(),
      password = TextEditingController(),
      org = TextEditingController();
  bool busy = false, hide = true;
  String? error;
  @override
  void dispose() {
    id.dispose();
    password.dispose();
    org.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.login(id.text.trim(), password.text, org.text.trim());
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerRight,
                      child: LanguageSwitch(),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(
                          colors: [Color(0xfff1e6f6), Color(0xffe5d1f0)],
                        ),
                      ),
                      child: const Brand(),
                    ),
                    const SizedBox(height: 32),
                    AppText(
                      widget.api.portal == 'member'
                          ? 'Ваши привилегии.\nВаш профсоюз.'
                          : widget.api.portal == 'partner'
                          ? 'Кабинет партнёра'
                          : 'Кабинет администрации',
                      style: titleStyle(35),
                    ),
                    const SizedBox(height: 10),
                    AppText(
                      widget.api.portal == 'member'
                          ? appSettings.text(
                              'login_intro',
                              appLanguage.code,
                              fallback: tx(
                                'Войдите по табельному номеру и паролю. Личный номер телефона не нужен. При первом входе используйте выданный временный пароль.',
                              ),
                            )
                          : appSettings.text(
                              'partner_login_intro',
                              appLanguage.code,
                              fallback: tx(
                                'Войдите по логину и паролю, выданным администрацией профсоюза.',
                              ),
                            ),
                      style: TextStyle(color: muted, height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: id,
                      autofillHints: const [AutofillHints.username],
                      decoration: InputDecoration(
                        labelText: tx(
                          widget.api.portal == 'member'
                              ? 'Табельный номер'
                              : 'Логин',
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: password,
                      autofillHints: const [AutofillHints.password],
                      obscureText: hide,
                      decoration: InputDecoration(
                        labelText: tx('Пароль'),
                        suffixIcon: IconButton(
                          tooltip: tx(
                            hide ? 'Показать пароль' : 'Скрыть пароль',
                          ),
                          onPressed: () => setState(() => hide = !hide),
                          icon: Icon(
                            hide
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => login(),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: AppText(
                          error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ActionButton(
                      busy ? 'Входим…' : 'Войти',
                      onPressed: busy ? null : login,
                      icon: Icons.login_rounded,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () =>
                              route(context, const RemoteLegalPage('privacy')),
                          child: const AppText('Политика конфиденциальности'),
                        ),
                        TextButton(
                          onPressed: () =>
                              route(context, const RemoteLegalPage('terms')),
                          child: const AppText('Условия использования'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const AppText(
                      'Доступ выдаёт ответственное лицо профсоюза. Нет пароля или забыли его? Обратитесь к нему для восстановления.',
                      style: TextStyle(color: muted, fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PasswordPage extends StatefulWidget {
  final Api api;
  final bool mandatory;
  const PasswordPage({super.key, required this.api, this.mandatory = false});
  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  final old = TextEditingController(),
      value = TextEditingController(),
      repeat = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    old.dispose();
    value.dispose();
    repeat.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (value.text.runes.length < 6 || value.text != repeat.text) {
      setState(() => error = 'Минимум 6 символов; пароли должны совпадать');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.password(old.text, value.text);
      if (mounted && !widget.mandatory) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return PopScope(
      canPop: !widget.mandatory,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.mandatory,
          title: const AppText('Личный пароль'),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.lock_person_outlined, size: 60, color: purple),
                    const SizedBox(height: 20),
                    AppText(
                      widget.mandatory
                          ? 'Установите свой пароль'
                          : 'Изменить пароль',
                      style: titleStyle(),
                    ),
                    const SizedBox(height: 12),
                    const AppText(
                      'Пароль от 6 символов. После сохранения старые сессии будут закрыты, текущая сохранится.',
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: old,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: tx(
                          widget.mandatory
                              ? 'Временный пароль'
                              : 'Текущий пароль',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: value,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: tx('Новый пароль'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: repeat,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: tx('Повторите новый пароль'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (error != null)
                      AppText(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ActionButton(
                      busy ? 'Сохраняем…' : 'Сохранить пароль',
                      onPressed: busy ? null : save,
                    ),
                    if (widget.mandatory)
                      TextButton(
                        onPressed: () => widget.api.logout(),
                        child: const AppText('Выйти'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
