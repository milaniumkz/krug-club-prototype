import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'app_settings.dart';
import 'i18n.dart';
import 'ui.dart';

String settingsText(String key, {String fallback = ''}) =>
    appSettings.text(key, appLanguage.code, fallback: fallback);

class RemotePolicyOverlay extends StatelessWidget {
  final Api api;
  final Widget child;
  const RemotePolicyOverlay({
    super.key,
    required this.api,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    final role = api.user?['role']?.toString() ?? api.portal;
    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios'
        : 'android';
    final update = !kIsWeb && appSettings.needsUpdate(role, platform);
    final maintenance = role == 'member' && appSettings.maintenance;
    final blocked = role != 'admin' && (update || maintenance);
    return Stack(
      children: [
        ExcludeSemantics(
          excluding: blocked,
          child: IgnorePointer(ignoring: blocked, child: child),
        ),
        if (blocked)
          Positioned.fill(
            child: Scaffold(
              body: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Brand(),
                          const SizedBox(height: 32),
                          Icon(
                            update
                                ? Icons.system_update_rounded
                                : Icons.engineering_outlined,
                            size: 56,
                            color: purple,
                          ),
                          const SizedBox(height: 20),
                          AppText(
                            update
                                ? 'Обновление приложения'
                                : 'Техническое обслуживание',
                            style: titleStyle(26),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          AppText(
                            settingsText(update ? 'update' : 'maintenance'),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          if (update)
                            ActionButton(
                              'Обновить приложение',
                              onPressed: () async {
                                final uri = Uri.tryParse(
                                  appSettings.updateUrl(role, platform),
                                );
                                if (uri != null && uri.scheme == 'https') {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                            ),
                          TextButton(
                            onPressed: () async {
                              await appSettings.refresh();
                              if (api.bootError != null) await api.boot();
                            },
                            child: const AppText('Проверить ещё раз'),
                          ),
                          const SizedBox(height: 12),
                          const RemoteSupportInfo(compact: true),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class FeatureUnavailable extends StatelessWidget {
  final String title;
  const FeatureUnavailable(this.title, {super.key});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty_rounded, color: purple, size: 42),
            const SizedBox(height: 16),
            AppText(title, style: titleStyle(24)),
            const SizedBox(height: 12),
            const AppText(
              'Раздел временно недоступен. Попробуйте позже',
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: appSettings.refresh,
              child: const AppText('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class RemoteLegalPage extends StatelessWidget {
  final String kind;
  const RemoteLegalPage(this.kind, {super.key});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([appSettings, appLanguage]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: AppText(
            kind == 'privacy'
                ? 'Политика конфиденциальности'
                : 'Условия использования',
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: SelectableText(
            settingsText(kind),
            style: const TextStyle(height: 1.6, fontSize: 16),
          ),
        ),
      ),
    );
  }
}

class RemoteSupportInfo extends StatelessWidget {
  final bool compact;
  const RemoteSupportInfo({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([appSettings, appLanguage]),
      builder: (context, _) {
        final phone = appSettings.value('support_phone'),
            email = appSettings.value('support_email'),
            link = appSettings.value('support_url');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (phone.isNotEmpty || email.isNotEmpty || link.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (phone.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri(
                          scheme: 'tel',
                          path: phone.replaceAll(RegExp(r'[^+0-9]'), ''),
                        ),
                      ),
                      icon: const Icon(Icons.call_outlined),
                      label: Text(phone),
                    ),
                  if (email.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () =>
                          launchUrl(Uri(scheme: 'mailto', path: email)),
                      icon: const Icon(Icons.mail_outline),
                      label: Text(email),
                    ),
                  if (link.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final uri = Uri.tryParse(link);
                        if (uri != null && uri.scheme == 'https') {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const AppText('Связаться с поддержкой'),
                    ),
                ],
              ),
            if (!compact && appSettings.faq.isNotEmpty) ...[
              const SizedBox(height: 16),
              const AppText(
                'Частые вопросы',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              ...appSettings.faq.map(
                (row) => ExpansionTile(
                  title: Text(s(row['question_${appLanguage.code}'])),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        s(row['answer_${appLanguage.code}']),
                        style: const TextStyle(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
        );
      },
    );
  }
}

class AdminAppSettingsPage extends StatefulWidget {
  final Api api;
  const AdminAppSettingsPage({super.key, required this.api});
  @override
  State<AdminAppSettingsPage> createState() => _AdminAppSettingsPageState();
}

class _AdminAppSettingsPageState extends State<AdminAppSettingsPage> {
  final form = GlobalKey<FormState>();
  Json? data;
  int revision = 0, generation = 0;
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final reply = Json.from(await widget.api.get('/admin/app-config') as Map);
      if (mounted) {
        setState(() {
          data = Json.from(reply['settings'] as Map);
          revision = reply['revision'] as int;
          generation++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  dynamic read(String path) {
    dynamic current = data;
    for (final key in path.split('.')) {
      current = (current as Map)[key];
    }
    return current;
  }

  void write(String path, dynamic value) {
    final keys = path.split('.');
    Map current = data!;
    for (final key in keys.take(keys.length - 1)) {
      current = current[key] as Map;
    }
    current[keys.last] = value;
  }

  Widget field(
    String path,
    String label, {
    int maxLength = 160,
    int lines = 1,
    bool required = false,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: ValueKey('settings-$generation-$path'),
      initialValue: s(read(path)),
      maxLength: maxLength,
      maxLines: lines,
      minLines: lines > 2 ? 3 : lines,
      keyboardType: numeric
          ? TextInputType.number
          : lines > 1
          ? TextInputType.multiline
          : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      decoration: InputDecoration(labelText: tx(label)),
      validator: (value) {
        if (required && (value ?? '').trim().isEmpty) {
          return tx('Заполните поле');
        }
        if (path.endsWith('_color') &&
            !RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(value ?? '')) {
          return tx('Цвет: #RRGGBB');
        }
        return null;
      },
      onChanged: (value) =>
          write(path, numeric ? int.tryParse(value) ?? 0 : value),
    ),
  );
  Widget pair(String key, String label, {int maxLength = 160, int lines = 2}) =>
      Column(
        children: [
          field(
            '${key}_ru',
            '${tx(label)} · РУС',
            maxLength: maxLength,
            lines: lines,
          ),
          field(
            '${key}_kk',
            '${tx(label)} · ҚАЗ',
            maxLength: maxLength,
            lines: lines,
          ),
        ],
      );
  Widget group(String title, List<Widget> children, {bool open = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Panel(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ExpansionTile(
            initiallyExpanded: open,
            title: AppText(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            children: children,
          ),
        ),
      );
  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final response = await widget.api.request('PUT', '/admin/app-config', {
        'expected_revision': revision,
        'settings': data,
      });
      final reply = Json.from(response as Map);
      appSettings.apply(reply);
      if (mounted) {
        setState(() => revision = reply['revision'] as int);
        toast(
          context,
          'Настройки сохранены. Приложения получат изменения с сервера',
        );
      }
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> logo() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (image == null) return;
      final path = await widget.api.upload(image);
      if (mounted) setState(() => data!['logo_path'] = path);
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    if (loading) return const Center(child: CircularProgressIndicator());
    if (data == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText(error ?? 'Не удалось загрузить настройки'),
            TextButton(onPressed: load, child: const AppText('Повторить')),
          ],
        ),
      );
    }
    final sections = List<String>.from(data!['home_sections'] as List);
    final faqs = data!['faq'] as List;
    return Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionHeading('Настройки приложения'),
          const AppText(
            'Содержимое, оформление и готовые разделы обновляются с сервера. Новые функции устройства требуют новой версии приложения.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('save-app-settings'),
                onPressed: busy ? null : save,
                icon: const Icon(Icons.save_outlined),
                label: const AppText('Сохранить настройки'),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        if (await confirm(
                          context,
                          'Обновить настройки?',
                          'Несохранённые изменения будут заменены данными сервера',
                        )) {
                          await load();
                        }
                      },
                icon: const Icon(Icons.refresh),
                label: const AppText('Обновить с сервера'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          group('Название, логотип и цвета', [
            field(
              'brand_name',
              'Название приложения',
              required: true,
              maxLength: 24,
            ),
            if (s(data!['logo_path']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Image.network(
                  '${widget.api.base}${data!['logo_path']}',
                  height: 64,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.image_not_supported_outlined),
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: logo,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const AppText('Загрузить логотип'),
                ),
                if (s(data!['logo_path']).isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => data!['logo_path'] = ''),
                    child: const AppText('Убрать логотип'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            field(
              'accent_color',
              'Основной цвет',
              maxLength: 7,
              required: true,
            ),
            field(
              'background_color',
              'Цвет фона',
              maxLength: 7,
              required: true,
            ),
            const AppText(
              'Название и иконка на рабочем столе телефона меняются только с новой сборкой.',
            ),
          ], open: true),
          group('Тексты входа и главной', [
            pair('login_intro', 'Вход участника', maxLength: 1000, lines: 4),
            pair(
              'partner_login_intro',
              'Вход партнёра',
              maxLength: 1000,
              lines: 3,
            ),
            pair('eyebrow', 'Подпись на главной', maxLength: 100),

            pair('tagline', 'Слоган', maxLength: 160),
            pair('partners_title', 'Заголовок партнёров', maxLength: 100),
            pair('offers_title', 'Заголовок предложений', maxLength: 100),
          ]),
          group('Разделы главной и нижнее меню', [
            const AppText(
              'Карта участника и быстрый QR остаются на главной. Дополнительные блоки можно скрыть и переставить.',
            ),
            ...['promotions', 'partners'].map(
              (key) => CheckboxListTile(
                title: AppText(
                  key == 'promotions' ? 'Особые предложения' : 'Партнёры клуба',
                ),
                value: sections.contains(key),
                onChanged: (value) => setState(() {
                  final items = List<String>.from(data!['home_sections']);
                  if (value == true) {
                    items.add(key);
                  } else {
                    items.remove(key);
                  }
                  data!['home_sections'] = items;
                }),
              ),
            ),
            if (sections.length == 2)
              TextButton.icon(
                onPressed: () => setState(
                  () => data!['home_sections'] = sections.reversed.toList(),
                ),
                icon: const Icon(Icons.swap_vert),
                label: const AppText('Поменять порядок блоков'),
              ),
            const Divider(),
            for (final language in ['ru', 'kk']) ...[
              AppText(
                language == 'ru' ? 'Нижнее меню · РУС' : 'Нижнее меню · ҚАЗ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final key in ['home', 'partners', 'qr', 'map', 'profile'])
                field(
                  'labels_$language.$key',
                  {
                    'home': 'Главная',
                    'partners': 'Партнёры',
                    'qr': 'QR',
                    'map': 'На карте',
                    'profile': 'Профиль',
                  }[key]!,
                  maxLength: 24,
                  required: true,
                ),
            ],
          ]),
          group('Доступность разделов', [
            for (final entry in {
              'qr': 'QR-сканер',
              'map': 'Карта заведений',
              'push': 'Push-уведомления',
              'banners': 'Рекламные баннеры',
            }.entries)
              SwitchListTile(
                title: AppText(entry.value),
                value: (data!['features'] as Map)[entry.key] == true,
                onChanged: (value) => setState(
                  () => (data!['features'] as Map)[entry.key] = value,
                ),
              ),
            const AppText(
              'Авторизация, PIN, проверка членства и права доступа продолжают действовать независимо от этих переключателей.',
            ),
          ]),
          group('Поддержка и частые вопросы', [
            field('support_phone', 'Телефон поддержки', maxLength: 30),
            field('support_email', 'Email поддержки', maxLength: 254),
            field('support_url', 'HTTPS-ссылка поддержки', maxLength: 1000),
            ...faqs.map((dynamic raw) {
              final row = raw as Map;
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  children: [
                    for (final entry in {
                      'question_ru': 'Вопрос · РУС',
                      'answer_ru': 'Ответ · РУС',
                      'question_kk': 'Вопрос · ҚАЗ',
                      'answer_kk': 'Ответ · ҚАЗ',
                    }.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextFormField(
                          key: ValueKey(
                            'faq-$generation-${identityHashCode(row)}-${entry.key}',
                          ),
                          initialValue: s(row[entry.key]),
                          maxLength: entry.key.startsWith('answer')
                              ? 4000
                              : 200,
                          maxLines: entry.key.startsWith('answer') ? 4 : 2,
                          decoration: InputDecoration(
                            labelText: tx(entry.value),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? tx('Заполните поле')
                              : null,
                          onChanged: (value) => row[entry.key] = value,
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => setState(() => faqs.remove(row)),
                      icon: const Icon(Icons.delete_outline),
                      label: const AppText('Удалить вопрос'),
                    ),
                  ],
                ),
              );
            }),
            if (faqs.length < 20)
              OutlinedButton.icon(
                onPressed: () => setState(
                  () => faqs.add({
                    'question_ru': '',
                    'answer_ru': '',
                    'question_kk': '',
                    'answer_kk': '',
                  }),
                ),
                icon: const Icon(Icons.add),
                label: const AppText('Добавить вопрос'),
              ),
          ]),
          group('Документы', [
            pair(
              'privacy',
              'Политика конфиденциальности',
              maxLength: 25000,
              lines: 7,
            ),
            pair('terms', 'Условия использования', maxLength: 25000, lines: 7),
          ]),
          group('Техническое обслуживание', [
            SwitchListTile(
              title: const AppText('Временно закрыть доступ участникам'),
              value: data!['maintenance'] == true,
              onChanged: (value) =>
                  setState(() => data!['maintenance'] = value),
            ),
            const AppText(
              'Кабинеты администрации и партнёров остаются доступны. Сессии и PIN участников сохраняются.',
            ),
            pair(
              'maintenance',
              'Сообщение участникам',
              maxLength: 1000,
              lines: 4,
            ),
          ]),
          group('Версии мобильных приложений', [
            const AppText(
              'Номер сборки — число в скобках у версии приложения. 0 отключает требование обновления. Сначала опубликуйте новую сборку и укажите ссылку, затем повышайте минимальную версию.',
            ),
            for (final role in ['member', 'partner'])
              for (final platform in ['android', 'ios']) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: AppText(
                    '${role == 'member' ? 'Участник' : 'Партнёр'} · ${platform == 'android' ? 'Android' : 'iOS'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                field(
                  'versions.$role.$platform.latest_build',
                  'Последняя опубликованная сборка',
                  numeric: true,
                  maxLength: 10,
                ),
                field(
                  'versions.$role.$platform.minimum_build',
                  'Минимальная поддерживаемая сборка',
                  numeric: true,
                  maxLength: 10,
                ),
                field(
                  'versions.$role.$platform.store_url',
                  'Ссылка Google Play, App Store или GitHub',
                  maxLength: 1000,
                ),
              ],
            pair(
              'update',
              'Сообщение об обновлении',
              maxLength: 1000,
              lines: 4,
            ),
          ]),
          FilledButton.icon(
            onPressed: busy ? null : save,
            icon: const Icon(Icons.save_outlined),
            label: const AppText('Сохранить настройки'),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
