import 'i18n.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'api.dart';
import 'ui.dart';

bool deviceAuthenticationActive = false;

class PinLock extends StatefulWidget {
  final Api api;
  final Widget child;
  final bool biometricsAllowed;
  const PinLock({
    super.key,
    required this.api,
    required this.child,
    this.biometricsAllowed = true,
  });
  @override
  State<PinLock> createState() => _PinLockState();
}

class _PinLockState extends State<PinLock> with WidgetsBindingObserver {
  final pin = TextEditingController(), confirmation = TextEditingController();
  final biometrics = LocalAuthentication();
  bool loading = true,
      creating = false,
      locked = true,
      busy = false,
      enabled = false;
  String? error;
  String get key => 'local-pin-${widget.api.user!['id']}';
  String hash(String salt, String value) =>
      sha256.convert(utf8.encode('$salt:$value')).toString();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  Future<void> load() async {
    try {
      final stored = await widget.api.storage.read(key: key);
      enabled =
          widget.biometricsAllowed &&
          !kIsWeb &&
          await widget.api.storage.read(key: '$key-biometrics') == 'yes';
      if (!mounted) return;
      setState(() {
        creating = stored == null;
        loading = false;
      });
      if (!creating && enabled) await biometric();
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Не удалось прочитать защищённые настройки. Войдите заново.';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (creating || loading) return;
    if ((state == AppLifecycleState.inactive &&
            !busy &&
            !deviceAuthenticationActive) ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (mounted) {
        setState(() {
          locked = true;
          pin.clear();
        });
      }
    } else if (state == AppLifecycleState.resumed &&
        locked &&
        !busy &&
        !deviceAuthenticationActive) {
      widget.api.storage.read(key: '$key-biometrics').then((value) {
        enabled = !kIsWeb && value == 'yes';
        if (enabled && mounted) biometric();
      });
    }
  }

  Future<void> biometric() async {
    if (kIsWeb || busy) return;
    setState(() => busy = true);
    try {
      await widget.api.get('/auth/me');
      if (!mounted || widget.api.user == null) return;
      final ok = await biometrics.authenticate(
        localizedReason: tx('Подтвердите вход в QAZAQMETAL'),
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (ok && mounted) {
        setState(() {
          locked = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Биометрия недоступна. Введите PIN-код.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy) return;
    if (!RegExp(r'^\d{6}$').hasMatch(pin.text)) {
      setState(() => error = 'Введите PIN-код из 6 цифр');
      return;
    }
    if (creating && pin.text != confirmation.text) {
      setState(() => error = 'PIN-коды должны совпадать');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.get('/auth/me');
      if (!mounted || widget.api.user == null) return;
      if (creating) {
        final salt = base64UrlEncode(
          List<int>.generate(32, (_) => Random.secure().nextInt(256)),
        );
        await widget.api.storage.write(
          key: key,
          value: jsonEncode({'salt': salt, 'hash': hash(salt, pin.text)}),
        );
        bool useBiometrics = false;
        bool available = false;
        if (widget.biometricsAllowed && !kIsWeb) {
          try {
            available =
                await biometrics.canCheckBiometrics &&
                (await biometrics.getAvailableBiometrics()).isNotEmpty;
          } catch (_) {}
        }
        if (available && mounted) {
          useBiometrics =
              await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const AppText('Включить биометрию?'),
                  content: const AppText(
                    'Следующий вход можно подтвердить отпечатком пальца или Face ID. PIN-код останется запасным способом.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const AppText('Пока PIN-код'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const AppText('Включить'),
                    ),
                  ],
                ),
              ) ??
              false;
        }
        if (useBiometrics) {
          try {
            useBiometrics = await biometrics.authenticate(
              localizedReason: tx('Подтвердите включение биометрии'),
              biometricOnly: true,
            );
          } catch (_) {
            useBiometrics = false;
          }
        }
        enabled = useBiometrics;
        await widget.api.storage.write(
          key: '$key-biometrics',
          value: enabled ? 'yes' : 'no',
        );
        if (mounted) {
          setState(() {
            creating = false;
            locked = false;
          });
        }
      } else {
        final blocked =
            int.tryParse(
              await widget.api.storage.read(key: '$key-blocked') ?? '',
            ) ??
            0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (blocked > now) {
          setState(
            () => error =
                'Слишком много попыток. Подождите ${((blocked - now) / 1000).ceil()} секунд',
          );
          return;
        }
        final stored =
            jsonDecode((await widget.api.storage.read(key: key))!) as Map;
        if (hash(stored['salt'] as String, pin.text) != stored['hash']) {
          final attempts =
              (int.tryParse(
                    await widget.api.storage.read(key: '$key-attempts') ?? '',
                  ) ??
                  0) +
              1;
          await widget.api.storage.write(
            key: '$key-attempts',
            value: '${attempts % 5}',
          );
          if (attempts >= 5) {
            await widget.api.storage.write(
              key: '$key-blocked',
              value: '${now + 30000}',
            );
          }
          setState(
            () => error = attempts >= 5
                ? 'Слишком много попыток. Подождите 30 секунд'
                : 'Неверный PIN-код',
          );
          pin.clear();
          return;
        }
        await widget.api.storage.delete(key: '$key-attempts');
        await widget.api.storage.delete(key: '$key-blocked');
        if (mounted) setState(() => locked = false);
      }
      pin.clear();
      confirmation.clear();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Не удалось проверить PIN-код. Повторите попытку.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reset() async {
    final prefix = key;
    try {
      await widget.api.logout();
    } catch (_) {
      if (widget.api.user != null) {
        if (mounted) {
          setState(
            () => error =
                'Для сброса PIN-кода нужно соединение с сервером. Повторите попытку.',
          );
        }
        return;
      }
    }
    for (final suffix in ['', '-biometrics', '-attempts', '-blocked']) {
      await widget.api.storage.delete(key: '$prefix$suffix');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pin.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!locked) return widget.child;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Brand(),
                  const SizedBox(height: 32),
                  Icon(
                    creating ? Icons.lock_outline : Icons.lock_person_outlined,
                    size: 52,
                    color: purple,
                  ),
                  const SizedBox(height: 20),
                  AppText(
                    creating ? 'Создайте PIN-код' : 'Введите PIN-код',
                    style: titleStyle(30),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  AppText(
                    creating
                        ? '6 цифр для быстрого входа на этом устройстве. Пароль аккаунта при этом сохраняется.'
                        : 'Ваша сессия сохранена. Подтвердите вход на этом устройстве.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: pin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: tx('PIN-код')),
                    onSubmitted: (_) => creating ? null : submit(),
                  ),
                  if (creating)
                    TextField(
                      controller: confirmation,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: tx('Повторите PIN-код'),
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppText(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ActionButton(
                    creating ? 'Сохранить PIN-код' : 'Открыть приложение',
                    onPressed: busy ? null : submit,
                  ),
                  if (enabled && !kIsWeb)
                    TextButton.icon(
                      onPressed: busy ? null : biometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const AppText('Войти по биометрии'),
                    ),
                  TextButton(
                    onPressed: busy ? null : reset,
                    child: const AppText('Забыли PIN? Войти заново'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PinSettingsPage extends StatefulWidget {
  final Api api;
  const PinSettingsPage({super.key, required this.api});
  @override
  State<PinSettingsPage> createState() => _PinSettingsPageState();
}

class _PinSettingsPageState extends State<PinSettingsPage> {
  final current = TextEditingController(),
      next = TextEditingController(),
      repeat = TextEditingController();
  bool busy = false, enabled = false;
  String? error;
  String get key => 'local-pin-${widget.api.user!['id']}';
  @override
  void initState() {
    super.initState();
    widget.api.storage.read(key: '$key-biometrics').then((value) {
      if (mounted) setState(() => enabled = value == 'yes');
    });
  }

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    repeat.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    if (!RegExp(r'^\d{6}$').hasMatch(next.text) || next.text != repeat.text) {
      setState(() => error = 'Введите 6 цифр и повторите PIN-код');
      return;
    }
    setState(() => busy = true);
    try {
      final raw = await widget.api.storage.read(key: key);
      if (raw == null) throw ApiError(0, 'Сначала настройте PIN-код');
      final old = jsonDecode(raw) as Map;
      final digest = sha256
          .convert(utf8.encode('${old['salt']}:${current.text}'))
          .toString();
      if (digest != old['hash']) throw ApiError(0, 'Неверный PIN-код');
      final salt = base64UrlEncode(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      );
      await widget.api.storage.write(
        key: key,
        value: jsonEncode({
          'salt': salt,
          'hash': sha256.convert(utf8.encode('$salt:${next.text}')).toString(),
        }),
      );
      if (mounted) {
        toast(context, 'PIN-код изменён');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggle(bool value) async {
    deviceAuthenticationActive = true;
    try {
      if (value) {
        final ok = await LocalAuthentication().authenticate(
          localizedReason: tx('Подтвердите включение биометрии'),
          biometricOnly: true,
        );
        if (!ok) return;
      }
      await widget.api.storage.write(
        key: '$key-biometrics',
        value: value ? 'yes' : 'no',
      );
      if (mounted) setState(() => enabled = value);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Биометрия недоступна. Используйте PIN-код.');
      }
    } finally {
      deviceAuthenticationActive = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('PIN-код и биометрия')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!kIsWeb)
          SwitchListTile(
            title: const AppText('Вход по биометрии'),
            subtitle: const AppText('Отпечаток пальца или Face ID'),
            value: enabled,
            onChanged: toggle,
          ),
        if (kIsWeb) const AppText('В браузере используется PIN-код.'),
        const SizedBox(height: 20),
        for (final entry in [
          (current, 'Текущий PIN-код'),
          (next, 'Новый PIN-код'),
          (repeat, 'Повторите PIN-код'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: entry.$1,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: tx(entry.$2)),
            ),
          ),
        if (error != null)
          AppText(error!, style: const TextStyle(color: Colors.red)),
        ActionButton('Сохранить PIN-код', onPressed: busy ? null : save),
      ],
    ),
  );
}
