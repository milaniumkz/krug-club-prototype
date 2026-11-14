import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'api.dart';
import 'ui.dart';
import 'member.dart';
import 'workspace.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl(
      '${Uri.base.origin}/zxing.min.js',
    );
    MobileScannerPlatform.instance.setWebBarcodeReader(
      WebBarcodeReader.zxingJs,
    );
  }
  runApp(QazaqMetalApp(api: Api()..boot()));
}

class QazaqMetalApp extends StatelessWidget {
  final Api api;
  const QazaqMetalApp({super.key, required this.api});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: api,
    builder: (context, _) => MaterialApp(
      key: ValueKey(api.user?['id'] ?? 'guest'),
      title: 'QAZAQMETAL KÁSIPODAǴY',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Manrope',
        scaffoldBackgroundColor: paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: purple,
          surface: paper,
        ).copyWith(primary: purple, onPrimary: Colors.white),
        appBarTheme: const AppBarTheme(
          backgroundColor: paper,
          foregroundColor: ink,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xffefe8e6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 50)),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: paper,
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
                      Text(api.bootError!, textAlign: TextAlign.center),
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
          : api.user!['role'] == 'member'
          ? MemberShell(key: ValueKey(api.user!['id']), api: api)
          : WorkspaceShell(key: ValueKey(api.user!['id']), api: api),
    ),
  );
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
  Widget build(BuildContext context) => Scaffold(
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
                  const Brand(),
                  const SizedBox(height: 48),
                  Text(
                    'Ваши привилегии.\nВаш профсоюз.',
                    style: titleStyle(35),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Войдите по табельному номеру и паролю. При первом входе используйте выданный временный пароль.',
                    style: TextStyle(color: muted, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: id,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'Табельный номер / телефон / логин',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: password,
                    autofillHints: const [AutofillHints.password],
                    obscureText: hide,
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      suffixIcon: IconButton(
                        tooltip: hide ? 'Показать пароль' : 'Скрыть пароль',
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
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Код организации, если требуется',
                      style: TextStyle(fontSize: 12),
                    ),
                    children: [
                      TextField(
                        controller: org,
                        decoration: const InputDecoration(
                          labelText: 'Код организации',
                        ),
                      ),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ActionButton(
                    busy ? 'Входим…' : 'Войти',
                    onPressed: busy ? null : login,
                    icon: Icons.login_rounded,
                  ),
                  const SizedBox(height: 20),
                  const Text(
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
    if (value.text.length < 12 || value.text != repeat.text) {
      setState(() => error = 'Минимум 12 символов; пароли должны совпадать');
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
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.mandatory,
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.mandatory,
        title: const Text('Личный пароль'),
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
                  const Icon(
                    Icons.lock_person_outlined,
                    size: 60,
                    color: purple,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.mandatory
                        ? 'Установите свой пароль'
                        : 'Изменить пароль',
                    style: titleStyle(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Пароль от 12 символов. После сохранения старые сессии будут закрыты, текущая сохранится.',
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: old,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: widget.mandatory
                          ? 'Временный пароль'
                          : 'Текущий пароль',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: value,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Новый пароль',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: repeat,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Повторите новый пароль',
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ActionButton(
                    busy ? 'Сохраняем…' : 'Сохранить пароль',
                    onPressed: busy ? null : save,
                  ),
                  if (widget.mandatory)
                    TextButton(
                      onPressed: () => widget.api.logout(),
                      child: const Text('Выйти'),
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
