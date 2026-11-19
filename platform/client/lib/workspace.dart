import 'i18n.dart';
import 'date_field.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_selector/file_selector.dart';
import 'api.dart';
import 'ui.dart';
import 'member.dart' show ProfilePage, NotificationsPage;

const labels = {
  'overview': 'Обзор',
  'venue': 'Заведения',
  'offer': 'Скидки и акции',
  'banner': 'Баннеры',
  'moderation': 'Модерация',
  'accounts': 'Участники и доступ',
  'organizations': 'Организации',
  'partners': 'Партнёры',
  'tickets': 'Обращения',
  'audit': 'Журнал действий',
  'profile': 'Профиль',
  'notifications': 'Уведомления',
};
const icons = {
  'overview': Icons.bar_chart_rounded,
  'venue': Icons.storefront_outlined,
  'offer': Icons.local_offer_outlined,
  'banner': Icons.view_carousel_outlined,
  'moderation': Icons.fact_check_outlined,
  'accounts': Icons.groups_outlined,
  'organizations': Icons.apartment_outlined,
  'partners': Icons.handshake_outlined,
  'tickets': Icons.support_agent_outlined,
  'audit': Icons.history_outlined,
  'profile': Icons.person_outline,
  'notifications': Icons.notifications_none_rounded,
};

class WorkspaceShell extends StatefulWidget {
  final Api api;
  const WorkspaceShell({super.key, required this.api});
  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  String page = 'overview';
  @override
  void initState() {
    super.initState();
    widget.api.addListener(openPendingNotification);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => openPendingNotification(),
    );
  }

  void openPendingNotification() {
    if (mounted && widget.api.notificationsRequested) {
      widget.api.notificationsRequested = false;
      setState(() => page = 'notifications');
    }
  }

  @override
  void dispose() {
    widget.api.removeListener(openPendingNotification);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admin = widget.api.user!['role'] == 'admin';
    final menu = [
      'overview',
      'venue',
      'banner',
      if (admin) ...[
        'moderation',
        'accounts',
        'organizations',
        'partners',
        'tickets',
        'audit',
      ],
      'notifications',
      'profile',
    ];
    Widget content() {
      switch (page) {
        case 'notifications':
          return NotificationsPage(api: widget.api);
        case 'overview':
          return StatsPage(api: widget.api);
        case 'venue':
        case 'offer':
        case 'banner':
          return ResourceList(api: widget.api, kind: page);
        case 'moderation':
          return ModerationPage(api: widget.api);
        case 'accounts':
          return AccountsPage(api: widget.api);
        case 'organizations':
        case 'partners':
          return EntitiesPage(api: widget.api, kind: page);
        case 'tickets':
          return AdminTickets(api: widget.api);
        case 'audit':
          return AuditPage(api: widget.api);
        default:
          return ProfilePage(api: widget.api);
      }
    }

    void navigate(String key) {
      setState(() => page = key);
    }

    final wide = MediaQuery.sizeOf(context).width >= 950;
    Widget nav() => ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(0, 14, 0, 28),
          child: Brand(),
        ),
        AppText(
          admin ? 'Администрирование' : 'Кабинет партнёра',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        ...menu.map(
          (key) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              selected: page == key,
              selectedTileColor: lavender,
              leading: Icon(icons[key], color: page == key ? purple : muted),
              title: AppText(labels[key]!),
              onTap: () {
                if (!wide) Navigator.pop(context);
                navigate(key);
              },
            ),
          ),
        ),
      ],
    );
    final mobile = admin
        ? ['overview', 'venue', 'moderation', 'accounts', 'profile']
        : ['overview', 'venue', 'notifications', 'banner', 'profile'];
    return Scaffold(
      appBar: AppBar(
        title: AppText(
          labels[page] ?? '',
          style: titleStyle(wide ? 23 : 20),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: tx('Уведомления'),
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () => navigate('notifications'),
          ),
          if (MediaQuery.sizeOf(context).width >= 600)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Chip(label: AppText(admin ? 'Администратор' : 'Партнёр')),
            ),
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: nav())),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) SizedBox(width: 240, child: nav()),
            if (wide) const VerticalDivider(width: 1),
            Expanded(child: content()),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: mobile.contains(page) ? mobile.indexOf(page) : 0,
              onDestinationSelected: (i) => navigate(mobile[i]),
              destinations: mobile
                  .map(
                    (key) => NavigationDestination(
                      icon: Icon(icons[key]),
                      label: tx(
                        key == 'accounts'
                            ? 'Участники'
                            : key == 'moderation'
                            ? 'Модерация'
                            : key == 'venue'
                            ? 'Заведения'
                            : key == 'offer'
                            ? 'Акции'
                            : labels[key]!,
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

String revisionStatus(Json row) {
  final r = row['revision'];
  if (r == null) return row['data'] == null ? 'Черновик' : 'Опубликовано';
  switch (r['status']) {
    case 'pending':
      return r['action'] == 'delete' ? 'Удаление на модерации' : 'На модерации';
    case 'rejected':
      return 'Отклонено: ${r["reason"]}';
    default:
      return row['deleted'] == true ? 'Удалено' : 'Опубликовано';
  }
}

Json editData(Json row) {
  final data = Json.from(
    (row['revision']?['data'] ?? row['data'] ?? {}) as Map,
  );
  if (row['kind'] == 'venue' &&
      data['percent'] == null &&
      row['legacy_discount'] is Map) {
    for (final key in [
      'percent',
      'terms',
      'terms_kk',
      'starts_on',
      'ends_on',
    ]) {
      data[key] = row['legacy_discount'][key];
    }
  }
  return data;
}

class ResourceList extends StatelessWidget {
  final Api api;
  final String kind;
  const ResourceList({super.key, required this.api, required this.kind});
  @override
  Widget build(BuildContext context) => LoadView(
    key: ValueKey(kind),
    load: () async {
      if (kind != 'venue') return api.get('/workspace/resources?kind=$kind');
      final all = rows(await api.get('/workspace/resources'));
      final discounts = <String, Json>{};
      for (final row in all) {
        if (row['kind'] == 'offer' &&
            row['deleted'] != true &&
            row['enabled'] != false &&
            row['data'] is Map) {
          final id = s(row['venue_id']);
          if ((row['data']['percent'] as num? ?? 0) >
              (discounts[id]?['percent'] as num? ?? 0)) {
            discounts[id] = Json.from(row['data'] as Map);
          }
        }
      }
      return all
          .where((r) => r['kind'] == 'venue')
          .map((r) => {...r, 'legacy_discount': discounts[s(r['id'])]})
          .toList();
    },
    builder: (data, refresh) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: AppText(labels[kind]!, style: titleStyle(30))),
            FilledButton.icon(
              onPressed: () async {
                await route(context, ResourceEditor(api: api, kind: kind));
                refresh();
              },
              icon: const Icon(Icons.add),
              label: const AppText('Добавить'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const AppText(
          'Новые объекты, изменения и удаление публикуются только после модерации. До одобрения участники видят прежнюю версию.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 20),
        if ((data as List).isEmpty)
          const Empty('Пока ничего нет. Добавьте первый объект.'),
        ...rows(data).map((row) {
          final d = editData(row),
              pending = row['revision']?['status'] == 'pending';
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppText(s(d['name']), style: titleStyle(23)),
                      ),
                      if (row['deleted'] != true)
                        IconButton(
                          tooltip: tx('Редактировать'),
                          onPressed: pending
                              ? null
                              : () async {
                                  await route(
                                    context,
                                    ResourceEditor(
                                      api: api,
                                      kind: kind,
                                      row: row,
                                    ),
                                  );
                                  refresh();
                                },
                          icon: const Icon(Icons.edit_outlined),
                        ),
                    ],
                  ),
                  if (d['percent'] != null)
                    AppText(
                      'Скидка: ${d['percent']}%',
                      style: const TextStyle(
                        color: purple,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  AppText(
                    revisionStatus(row),
                    style: TextStyle(
                      color: pending ? Colors.orange.shade900 : purple,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AppText(
                    s(
                      d[kind == 'venue'
                          ? 'address'
                          : kind == 'offer'
                          ? 'terms'
                          : 'description'],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (kind == 'venue' &&
                          row['data'] != null &&
                          row['deleted'] != true)
                        TextButton.icon(
                          onPressed: () async {
                            if (!await confirm(
                              context,
                              'Выдать новый QR-код?',
                              'Предыдущий код этого заведения перестанет работать',
                            )) {
                              return;
                            }
                            try {
                              final result = await api.post(
                                '/workspace/resources/${row["id"]}/qr',
                              );
                              if (context.mounted) {
                                await route(
                                  context,
                                  QrPrintPage(
                                    name: s(d['name']),
                                    code: s(result['code']),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) toast(context, e);
                            }
                          },
                          icon: const Icon(Icons.qr_code),
                          label: const AppText('Выдать QR'),
                        ),
                      if (!pending && row['deleted'] != true)
                        TextButton.icon(
                          onPressed: () async {
                            if (!await confirm(
                              context,
                              'Отправить удаление на модерацию?',
                              'До одобрения объект останется опубликован',
                            )) {
                              return;
                            }
                            try {
                              await api.post(
                                '/workspace/resources/${row["id"]}/revisions',
                                {'action': 'delete', 'data': d},
                              );
                              refresh();
                            } catch (e) {
                              if (context.mounted) toast(context, e);
                            }
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const AppText('Удалить'),
                        ),
                      if (api.user!['role'] == 'admin' &&
                          row['data'] != null &&
                          row['deleted'] != true)
                        TextButton(
                          onPressed: () async {
                            final reason = await askText(
                              context,
                              'Причина изменения доступности',
                            );
                            if (reason == null) return;
                            try {
                              await api.post(
                                '/admin/resources/${row["id"]}/visibility',
                                {
                                  'enabled': row['enabled'] != true,
                                  'reason': reason,
                                },
                              );
                              refresh();
                            } catch (e) {
                              if (context.mounted) toast(context, e);
                            }
                          },
                          child: AppText(
                            row['enabled'] == true
                                ? 'Скрыть срочно'
                                : 'Показать',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    ),
  );
}

class ResourceEditor extends StatefulWidget {
  final Api api;
  final String kind;
  final Json? row;
  const ResourceEditor({
    super.key,
    required this.api,
    required this.kind,
    this.row,
  });
  @override
  State<ResourceEditor> createState() => _ResourceEditorState();
}

class _ResourceEditorState extends State<ResourceEditor> {
  final controllers = <String, TextEditingController>{};
  String image = '', partner = '', venue = '';
  List<String> organizations = [];
  bool busy = false, loaded = false;
  String? error;
  List<Json> partners = [], venues = [], orgs = [];
  final names = {
    'name': 'Название',
    'description': 'Описание',
    'name_kk': 'Название — қазақша',
    'description_kk': 'Описание — қазақша',
    'category_kk': 'Категория — қазақша',
    'address_kk': 'Адрес — қазақша',
    'hours_kk': 'Режим работы — қазақша',
    'terms_kk': 'Условия — қазақша',
    'category': 'Категория',
    'address': 'Адрес',
    'phone': 'Телефон заведения',
    'hours': 'Режим работы',
    'latitude': 'Широта',
    'longitude': 'Долгота',
    'percent': 'Скидка, %',
    'terms': 'Условия и ограничения',
    'starts_on': 'Дата начала',
    'ends_on': 'Дата окончания',
  };
  @override
  void initState() {
    super.initState();
    final d = widget.row == null ? <String, dynamic>{} : editData(widget.row!);
    for (final key in names.keys) {
      controllers[key] = TextEditingController(text: s(d[key]));
    }
    image = s(d['image']);
    partner = s(widget.row?['partner_id']);
    venue = s(widget.row?['venue_id']);
    organizations = (d['organization_ids'] as List? ?? []).map(s).toList();
    init();
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> init() async {
    try {
      final all = rows(await widget.api.get('/workspace/resources'));
      venues = all
          .where((v) => v['kind'] == 'venue' && v['deleted'] != true)
          .toList();
      if (widget.kind == 'venue' &&
          widget.row != null &&
          controllers['percent']!.text.isEmpty) {
        final legacy = all
            .where(
              (r) =>
                  r['kind'] == 'offer' &&
                  r['venue_id'] == widget.row!['id'] &&
                  r['deleted'] != true &&
                  r['enabled'] != false &&
                  r['data'] != null,
            )
            .toList();
        legacy.sort(
          (a, b) => ((b['data']['percent'] as num?) ?? 0).compareTo(
            (a['data']['percent'] as num?) ?? 0,
          ),
        );
        if (legacy.isNotEmpty) {
          for (final key in [
            'percent',
            'terms',
            'terms_kk',
            'starts_on',
            'ends_on',
          ]) {
            controllers[key]!.text = s(legacy.first['data'][key]);
          }
        }
      }
      final options = await widget.api.get('/workspace/options');
      orgs = rows(options['organizations']);
      partners = rows(options['partners']);
      if (partner.isEmpty && partners.length == 1) {
        partner = s(partners.first['id']);
      }
      if (mounted) setState(() => loaded = true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.kind == 'venue' &&
          controllers['percent']!.text.trim().isEmpty) {
        throw ApiError(422, 'Укажите скидку в заведении');
      }
      final d = <String, dynamic>{};
      for (final key in names.keys) {
        final text = controllers[key]!.text.trim();
        if (['latitude', 'longitude'].contains(key)) {
          if (text.isNotEmpty &&
              double.tryParse(text.replaceAll(',', '.')) == null) {
            throw ApiError(422, 'Проверьте координаты');
          }
          d[key] = text.isEmpty
              ? null
              : double.parse(text.replaceAll(',', '.'));
        } else if (key == 'percent') {
          if (text.isNotEmpty && int.tryParse(text) == null) {
            throw ApiError(422, 'Процент должен быть целым числом');
          }
          if (text.isNotEmpty &&
              (int.parse(text) < 1 || int.parse(text) > 100)) {
            throw ApiError(422, 'Скидка должна быть от 1 до 100%');
          }
          d[key] = text.isEmpty ? null : int.parse(text);
        } else if (key.endsWith('_on')) {
          if (text.isNotEmpty &&
              (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
                  DateTime.tryParse(text) == null ||
                  !DateTime.parse(text).toIso8601String().startsWith(text))) {
            throw ApiError(422, 'Выберите дату в календаре');
          }
          d[key] = text.isEmpty ? null : text;
        } else {
          d[key] = text;
        }
      }
      d['image'] = image;
      d['organization_ids'] = organizations;
      if (widget.row == null) {
        await widget.api.post('/workspace/resources', {
          'kind': widget.kind,
          'partner_id': partner.isEmpty ? null : partner,
          'venue_id': widget.kind == 'venue' ? null : venue,
          'data': d,
        });
      } else {
        await widget.api.post(
          '/workspace/resources/${widget.row!["id"]}/revisions',
          {'action': 'publish', 'data': d},
        );
      }
      if (mounted) {
        toast(context, 'Отправлено на модерацию');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: AppText(
        widget.row == null ? 'Добавить: ${labels[widget.kind]}' : 'Изменить',
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              if (!loaded && error == null) const LinearProgressIndicator(),
              if (widget.api.user!['role'] == 'admin')
                DropdownButtonFormField<String>(
                  initialValue: partners.any((p) => p['id'] == partner)
                      ? partner
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tx('Партнёр')),
                  items: partners
                      .map(
                        (p) => DropdownMenuItem(
                          value: s(p['id']),
                          child: AppText(s(p['name'])),
                        ),
                      )
                      .toList(),
                  onChanged: widget.row == null
                      ? (v) => setState(() {
                          partner = v ?? '';
                          venue = '';
                        })
                      : null,
                ),
              if (widget.kind != 'venue')
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(partner),
                    initialValue:
                        venues.any(
                          (v) =>
                              v['id'] == venue &&
                              (partner.isEmpty || v['partner_id'] == partner),
                        )
                        ? venue
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tx('Заведение')),
                    items: venues
                        .where(
                          (v) => partner.isEmpty || v['partner_id'] == partner,
                        )
                        .map(
                          (v) => DropdownMenuItem(
                            value: s(v['id']),
                            child: AppText(s(editData(v)['name'])),
                          ),
                        )
                        .toList(),
                    onChanged: widget.row == null
                        ? (v) => setState(() => venue = v ?? '')
                        : null,
                  ),
                ),
              ...names.keys
                  .where(
                    (k) => widget.kind == 'venue'
                        ? ![
                            // Venue discounts are edited here, not as separate offers.
                          ].contains(k.replaceFirst('_kk', ''))
                        : ![
                                'category',
                                'address',
                                'phone',
                                'hours',
                                'latitude',
                                'longitude',
                              ].contains(k.replaceFirst('_kk', '')) &&
                              (widget.kind == 'offer' ||
                                  ![
                                    'percent',
                                    'terms',
                                  ].contains(k.replaceFirst('_kk', ''))),
                  )
                  .map(
                    (key) => Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: key.endsWith('_on')
                          ? CalendarDateField(
                              key: ValueKey('date-$key'),
                              controller: controllers[key]!,
                              label: names[key]!,
                              minimum: key == 'ends_on'
                                  ? controllers['starts_on']
                                  : null,
                              maximum: key == 'starts_on'
                                  ? controllers['ends_on']
                                  : null,
                            )
                          : TextField(
                              controller: controllers[key],
                              decoration: InputDecoration(
                                labelText: tx(names[key]),
                              ),
                              maxLines:
                                  [
                                    'description',
                                    'terms',
                                  ].contains(key.replaceFirst('_kk', ''))
                                  ? 4
                                  : 1,
                              maxLength:
                                  [
                                    'description',
                                    'terms',
                                  ].contains(key.replaceFirst('_kk', ''))
                                  ? 4000
                                  : null,
                              keyboardType:
                                  [
                                    'latitude',
                                    'longitude',
                                    'percent',
                                  ].contains(key)
                                  ? const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    )
                                  : TextInputType.text,
                            ),
                    ),
                  ),
              if (widget.kind == 'venue')
                TextButton.icon(
                  onPressed: () async {
                    final point = await Navigator.push<LatLng>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LocationPicker(api: widget.api),
                      ),
                    );
                    if (point != null) {
                      controllers['latitude']!.text = point.latitude
                          .toStringAsFixed(6);
                      controllers['longitude']!.text = point.longitude
                          .toStringAsFixed(6);
                    }
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const AppText('Указать координаты на карте'),
                ),
              const SizedBox(height: 20),
              if (image.isNotEmpty) RemotePhoto(api: widget.api, path: image),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final picked = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 2400,
                        );
                        if (picked == null) return;
                        setState(() => busy = true);
                        try {
                          final path = await widget.api.upload(picked);
                          if (mounted) setState(() => image = path);
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const AppText('Загрузить фотографию / баннер'),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const AppText('Доступность для организаций'),
                subtitle: AppText(
                  organizations.isEmpty
                      ? 'Все подключённые организации'
                      : 'Выбрано: ${organizations.length}',
                ),
                children: orgs
                    .map(
                      (o) => CheckboxListTile(
                        title: AppText(s(o['name'])),
                        value: organizations.contains(o['id']),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            organizations.add(s(o['id']));
                          } else {
                            organizations.remove(o['id']);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              if (error != null)
                AppText(error!, style: const TextStyle(color: Colors.red)),
              ActionButton(
                busy ? 'Сохраняем…' : 'Отправить на модерацию',
                onPressed: busy || !loaded ? null : save,
                icon: Icons.fact_check_outlined,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ),
  );
}

class LocationPicker extends StatefulWidget {
  final Api api;
  const LocationPicker({super.key, required this.api});
  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  LatLng? selected;
  String tiles = 'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
      attribution = '© OpenStreetMap contributors · Tiles OSM France';
  @override
  void initState() {
    super.initState();
    widget.api.get('/meta').then((m) {
      if (mounted) {
        setState(() {
          tiles = s(m['tiles']);
          attribution = s(m['attribution']);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('Нажмите на точку на карте')),
    body: FlutterMap(
      options: MapOptions(
        initialCenter: const LatLng(52.287, 76.967),
        initialZoom: 13,
        maxZoom: 18,
        onTap: (_, p) => setState(() => selected = p),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
          userAgentPackageName: 'kz.qazaqmetal.qazaqmetal',
        ),
        MarkerLayer(
          markers: [
            if (selected != null)
              Marker(
                point: selected!,
                child: const Icon(Icons.location_on, size: 40, color: purple),
              ),
          ],
        ),
        MapCredits(attribution: attribution),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: ActionButton(
          'Выбрать точку',
          onPressed: selected == null
              ? null
              : () => Navigator.pop(context, selected),
        ),
      ),
    ),
  );
}

class QrPrintPage extends StatefulWidget {
  final String name, code;
  const QrPrintPage({super.key, required this.name, required this.code});
  @override
  State<QrPrintPage> createState() => _QrPrintPageState();
}

class _QrPrintPageState extends State<QrPrintPage> {
  final poster = GlobalKey();
  bool busy = false;
  Future<void> export(BuildContext buttonContext) async {
    if (busy) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => busy = true);
    ui.Image? image;
    try {
      final boundary =
          poster.currentContext!.findRenderObject() as RenderRepaintBoundary;
      image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('PNG conversion failed');
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes.buffer.asUint8List(),
              mimeType: 'image/png',
              name: 'QazaqMetal_QR.png',
            ),
          ],
          fileNameOverrides: ['QazaqMetal_QR.png'],
          sharePositionOrigin: origin,
          downloadFallbackEnabled: true,
        ),
      );
    } catch (_) {
      if (mounted) {
        toast(
          context,
          'Не удалось сохранить QR. Повторите попытку или скопируйте текст кода.',
        );
      }
    } finally {
      image?.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('QR-код заведения')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Panel(
            child: Column(
              children: [
                RepaintBoundary(
                  key: poster,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          const Brand(),
                          const SizedBox(height: 24),
                          AppText(
                            widget.name,
                            style: titleStyle(),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (c, constraints) => QrImageView(
                              data: widget.code,
                              size: constraints.maxWidth.clamp(100, 340),
                              padding: const EdgeInsets.all(18),
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const AppText(
                            'Отсканируйте в приложении QAZAQMETAL, чтобы получить скидку',
                            style: TextStyle(
                              color: ink,
                              fontSize: 13,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Builder(
                  builder: (buttonContext) => ActionButton(
                    busy ? 'Готовим изображение…' : 'Сохранить / поделиться QR',
                    icon: Icons.ios_share_rounded,
                    onPressed: busy ? null : () => export(buttonContext),
                  ),
                ),
                const SizedBox(height: 15),
                SelectableText(
                  tx(widget.code),
                  style: const TextStyle(fontSize: 10),
                ),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.code));
                    toast(context, 'QR-код скопирован');
                  },
                  icon: const Icon(Icons.copy),
                  label: const AppText('Скопировать текст QR'),
                ),
                const AppText(
                  'Сохраните PNG для печати или передачи заведению. Следующая выдача QR отменит этот код.',
                  style: TextStyle(color: muted, fontSize: 12, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ModerationPage extends StatelessWidget {
  final Api api;
  const ModerationPage({super.key, required this.api});
  @override
  Widget build(BuildContext context) => LoadView(
    load: () => api.get('/admin/moderation'),
    builder: (data, refresh) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AppText('Очередь модерации', style: titleStyle(30)),
        const SizedBox(height: 18),
        if ((data as List).isEmpty) const Empty('Все изменения рассмотрены'),
        ...rows(data).map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(s(r['data']['name']), style: titleStyle(25)),
                  AppText(
                    '${human(r["resource"]["kind"])} · ${r["action"] == "delete" ? "Запрос удаления" : "Изменение / публикация"}',
                    style: const TextStyle(color: purple),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (c, size) => Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final pair in [
                          ('Было', r['resource']['data']),
                          ('Станет', r['data']),
                        ])
                          SizedBox(
                            width: size.maxWidth > 650
                                ? (size.maxWidth - 16) / 2
                                : size.maxWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText(
                                  pair.$1,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (pair.$2 == null)
                                  const AppText('Ещё не опубликовано')
                                else
                                  ...Json.from(pair.$2 as Map).entries
                                      .where(
                                        (e) =>
                                            s(e.value).isNotEmpty &&
                                            s(e.value) != '[]',
                                      )
                                      .map(
                                        (e) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 5,
                                          ),
                                          child: AppText(
                                            '${human(e.key)}: ${e.value}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                if (pair.$2 != null &&
                                    s(pair.$2['image']).isNotEmpty)
                                  RemotePhoto(
                                    api: api,
                                    path: s(pair.$2['image']),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          if (!await confirm(
                            context,
                            'Одобрить публикацию?',
                            'Изменения станут видны участникам',
                          )) {
                            return;
                          }
                          try {
                            await api.post('/admin/moderation/${r["id"]}', {
                              'decision': 'approve',
                            });
                            refresh();
                          } catch (e) {
                            if (context.mounted) toast(context, e);
                          }
                        },
                        icon: const Icon(Icons.check),
                        label: const AppText('Одобрить'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final reason = await askText(
                            context,
                            'Причина отклонения',
                          );
                          if (reason == null) return;
                          try {
                            await api.post('/admin/moderation/${r["id"]}', {
                              'decision': 'reject',
                              'reason': reason,
                            });
                            refresh();
                          } catch (e) {
                            if (context.mounted) toast(context, e);
                          }
                        },
                        icon: const Icon(Icons.close),
                        label: const AppText('Отклонить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class StatsPage extends StatefulWidget {
  final Api api;
  const StatsPage({super.key, required this.api});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  DateTime? start, end;
  String venue = '';
  Future<void> choose(bool first) async {
    final d = await showDatePicker(
      context: context,
      initialDate:
          (first ? start : end) ?? (first ? end : start) ?? DateTime.now(),
      firstDate: first ? DateTime(2020) : (start ?? DateTime(2020)),
      lastDate: first
          ? (end ?? DateTime.now().add(const Duration(days: 1)))
          : DateTime.now().add(const Duration(days: 1)),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (d == null || !mounted) return;
    final nextStart = first ? d : start, nextEnd = first ? end : d;
    if (nextStart != null && nextEnd != null && nextEnd.isBefore(nextStart)) {
      toast(context, 'Дата окончания раньше начала');
      return;
    }
    setState(() {
      if (first) {
        start = d;
      } else {
        end = d;
      }
    });
  }

  @override
  Widget build(BuildContext context) => LoadView(
    key: ValueKey('$start|$end|$venue'),
    load: () async => [
      await widget.api.get(
        '/workspace/stats?venue_id=$venue${start == null ? '' : '&start=${start!.toIso8601String().split('T').first}'}${end == null ? '' : '&end=${end!.toIso8601String().split('T').first}'}',
      ),
      await widget.api.get('/workspace/resources'),
    ],
    builder: (data, refresh) {
      final stats = Json.from(data[0] as Map);
      final venues = rows(data[1]);
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppText(
            widget.api.user!['role'] == 'partner'
                ? 'Результаты заведений'
                : 'Результаты клуба',
            style: titleStyle(30),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final metric in [
                ('Получено скидок', stats['total_uses'], Icons.redeem_outlined),
                (
                  'Уникальных участников',
                  stats['unique_members'],
                  Icons.people_outline,
                ),
                (
                  'Заведений со скидками',
                  (stats['venues'] as List).length,
                  Icons.storefront_outlined,
                ),
              ])
                SizedBox(
                  width: 245,
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(metric.$3, color: purple),
                        const SizedBox(height: 18),
                        AppText('${metric.$2}', style: titleStyle(34)),
                        AppText(
                          metric.$1,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => choose(true),
                child: AppText(start == null ? 'Дата от' : displayDate(start)),
              ),
              OutlinedButton(
                onPressed: () => choose(false),
                child: AppText(end == null ? 'Дата до' : displayDate(end)),
              ),
              TextButton(
                onPressed: () => setState(() {
                  start = null;
                  end = null;
                  venue = '';
                }),
                child: const AppText('Сбросить'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: venue,
            isExpanded: true,
            decoration: InputDecoration(labelText: tx('Заведение')),
            items: [
              const DropdownMenuItem(
                value: '',
                child: AppText('Все заведения'),
              ),
              ...venues.map(
                (v) => DropdownMenuItem(
                  value: s(v['id']),
                  child: AppText(s(editData(v)['name'])),
                ),
              ),
            ],
            onChanged: (v) => setState(() => venue = v ?? ''),
          ),
          const SizedBox(height: 22),
          AppText('По заведениям', style: titleStyle(23)),
          ...rows(stats['venues']).map(
            (v) => ListTile(
              leading: const Icon(Icons.storefront_outlined, color: purple),
              title: AppText(s(v['name'])),
              trailing: AppText(
                '${v["uses"]} скидок',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 18),
          AppText('Операции', style: titleStyle(23)),
          if ((stats['operations'] as List).isEmpty)
            const Empty('Применений за выбранный период нет'),
          ...rows(stats['operations']).map(
            (o) => ListTile(
              title: AppText(s(o['venue_name'])),
              subtitle: AppText(
                '${displayMoment(o["created_at"])}\n${tx(s(o["offer_name"]))}',
              ),
              trailing: AppText(
                '−${o["percent"]}%',
                style: const TextStyle(
                  color: purple,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              final csv =
                  'id,venue,offer,percent,created_at\n${rows(stats["operations"]).map((r) => [r["id"], r["venue_name"], r["offer_name"], r["percent"], r["created_at"]].map((v) => '"${s(v).replaceAll('"', '""')}"').join(',')).join('\n')}';
              Clipboard.setData(ClipboardData(text: csv));
              toast(context, 'CSV операций скопирован');
            },
            icon: const Icon(Icons.copy),
            label: const AppText('Скопировать CSV операций'),
          ),
        ],
      );
    },
  );
}

Future<String?> askText(BuildContext context, String title) async {
  final c = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: AppText(title),
      content: TextField(
        controller: c,
        maxLength: 1000,
        minLines: 2,
        maxLines: 5,
        decoration: InputDecoration(labelText: tx('Комментарий')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const AppText('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (c.text.trim().length >= 3) Navigator.pop(ctx, c.text.trim());
          },
          child: const AppText('Продолжить'),
        ),
      ],
    ),
  );
  c.dispose();
  return result;
}

class EntitiesPage extends StatelessWidget {
  final Api api;
  final String kind;
  const EntitiesPage({super.key, required this.api, required this.kind});
  @override
  Widget build(BuildContext context) => LoadView(
    key: ValueKey(kind),
    load: () => api.get('/admin/$kind'),
    builder: (data, refresh) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: AppText(labels[kind]!, style: titleStyle(30))),
            FilledButton.icon(
              onPressed: () async {
                await route(context, EntityForm(api: api, kind: kind));
                refresh();
              },
              icon: const Icon(Icons.add),
              label: const AppText('Добавить'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ...rows(data).map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  kind == 'organizations'
                      ? Icons.apartment
                      : Icons.handshake_outlined,
                  color: purple,
                ),
                title: AppText(s(e['name']), style: titleStyle(22)),
                subtitle: AppText(
                  '${s(e["code"])} · ${e["active"] == true ? "Активна" : "Отключена"}',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  await route(
                    context,
                    EntityForm(api: api, kind: kind, row: e),
                  );
                  refresh();
                },
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class EntityForm extends StatefulWidget {
  final Api api;
  final String kind;
  final Json? row;
  const EntityForm({
    super.key,
    required this.api,
    required this.kind,
    this.row,
  });
  @override
  State<EntityForm> createState() => _EntityFormState();
}

class _EntityFormState extends State<EntityForm> {
  late final name = TextEditingController(text: s(widget.row?['name'])),
      code = TextEditingController(text: s(widget.row?['code']));
  late bool active = widget.row?['active'] != false;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: AppText(widget.row == null ? 'Добавить' : 'Изменить'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        TextField(
          controller: name,
          decoration: InputDecoration(labelText: tx('Название')),
        ),
        if (widget.kind == 'organizations')
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: TextField(
              controller: code,
              decoration: InputDecoration(
                labelText: tx('Код организации (латиница / цифры)'),
              ),
            ),
          ),
        SwitchListTile(
          title: const AppText('Доступ разрешён'),
          subtitle: const AppText(
            'Отключение закрывает доступ связанных аккаунтов',
          ),
          value: active,
          onChanged: (v) => setState(() => active = v),
        ),
        const SizedBox(height: 20),
        if (error != null)
          AppText(error!, style: const TextStyle(color: Colors.red)),
        ActionButton(
          busy ? 'Сохраняем…' : 'Сохранить',
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    final d = {
                      'name': name.text,
                      'active': active,
                      if (widget.kind == 'organizations') 'code': code.text,
                    };
                    await widget.api.request(
                      widget.row == null ? 'POST' : 'PUT',
                      '/admin/${widget.kind}${widget.row == null ? '' : '/${widget.row!["id"]}'}',
                      d,
                    );
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) setState(() => error = '$e');
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
        ),
      ],
    ),
  );
}

class AccountsPage extends StatefulWidget {
  final Api api;
  const AccountsPage({super.key, required this.api});
  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  String q = '', status = '';
  int offset = 0;
  final search = TextEditingController();
  bool importing = false;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> showCredentials(BuildContext context, String text) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const AppText('Сохраните данные для первого входа'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppText(
                'Пароли показываются один раз. Передавайте их каждому работнику отдельно. Не публикуйте общий список.',
              ),
              const SizedBox(height: 14),
              SelectableText(tx(text)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              toast(ctx, 'Скопировано');
            },
            child: const AppText('Скопировать'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const AppText('Сохранено'),
          ),
        ],
      ),
    );
  }

  Future<void> importCsv(VoidCallback refresh) async {
    try {
      final orgs = rows(await widget.api.get('/admin/organizations'));
      if (!mounted) return;
      final org = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const AppText('Организация для импорта'),
          children: orgs
              .map(
                (o) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, s(o['id'])),
                  child: AppText(s(o['name'])),
                ),
              )
              .toList(),
        ),
      );
      if (org == null) return;
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'CSV', extensions: ['csv']),
        ],
      );
      if (file == null) return;
      setState(() => importing = true);
      final result = await widget.api.importMembers(file, org);
      if (!mounted) return;
      final text =
          'employee_number,temporary_password\n${rows(result["credentials"]).map((c) => '${c["employee_number"]},${c["temporary_password"]}').join('\n')}';
      await showCredentials(context, text);
      refresh();
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  Widget build(BuildContext context) => LoadView(
    key: ValueKey('$q|$status|$offset'),
    load: () => widget.api.get(
      '/admin/accounts?q=${Uri.encodeQueryComponent(q)}&status=$status&offset=$offset&limit=50',
    ),
    builder: (data, refresh) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AppText('Участники и доступ', style: titleStyle(30)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: () async {
                await route(context, AccountForm(api: widget.api));
                refresh();
              },
              icon: const Icon(Icons.person_add_outlined),
              label: const AppText('Добавить'),
            ),
            OutlinedButton.icon(
              onPressed: importing ? null : () => importCsv(refresh),
              icon: const Icon(Icons.upload_file_outlined),
              label: AppText(importing ? 'Загрузка…' : 'Импорт CSV'),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: AppText(
            'CSV UTF-8: employee_number,name,phone. Телефон необязателен. До 500 работников за загрузку. Удаление из клуба — только при увольнении; за нарушение правил — блокировка.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
        TextField(
          controller: search,
          decoration: InputDecoration(
            labelText: tx('Имя или табельный номер'),
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: (v) => setState(() {
            q = v;
            offset = 0;
          }),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: ['', 'active', 'blocked', 'dismissed']
              .map(
                (v) => ChoiceChip(
                  label: AppText(
                    {
                      '': 'Все',
                      'active': 'Активные',
                      'blocked': 'Заблокированы',
                      'dismissed': 'Уволены',
                    }[v]!,
                  ),
                  selected: status == v,
                  onSelected: (_) => setState(() {
                    status = v;
                    offset = 0;
                  }),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 18),
        ...rows(data['items']).map(
          (person) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(s(person['name']), style: titleStyle(22)),
                  AppText(
                    '${human(person["role"])} · ${human(person["status"])} · № ${s(person["employee_number"])}',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          if (!await confirm(
                            context,
                            'Сбросить пароль?',
                            'Текущие сессии будут закрыты. Выдайте новый временный пароль лично',
                          )) {
                            return;
                          }
                          try {
                            final r = await widget.api.post(
                              '/admin/accounts/${person["id"]}/reset-password',
                            );
                            if (context.mounted) {
                              await showCredentials(
                                context,
                                'Временный пароль: ${r["temporary_password"]}',
                              );
                            }
                          } catch (e) {
                            if (context.mounted) toast(context, e);
                          }
                        },
                        icon: const Icon(Icons.lock_reset),
                        label: const AppText('Временный пароль'),
                      ),
                      for (final target in [
                        'active',
                        'blocked',
                        if (person['role'] == 'member') 'dismissed',
                      ])
                        if (person['status'] != target)
                          TextButton(
                            onPressed: () async {
                              final reason = await askText(
                                context,
                                target == 'dismissed'
                                    ? 'Причина увольнения'
                                    : target == 'blocked'
                                    ? 'Нарушение правил / причина блокировки'
                                    : 'Причина восстановления доступа',
                              );
                              if (reason == null) return;
                              try {
                                await widget.api.post(
                                  '/admin/accounts/${person["id"]}/status',
                                  {'status': target, 'reason': reason},
                                );
                                refresh();
                              } catch (e) {
                                if (context.mounted) toast(context, e);
                              }
                            },
                            child: AppText(
                              {
                                'active': 'Восстановить',
                                'blocked': 'Блокировать',
                                'dismissed': 'Удалить: уволен',
                              }[target]!,
                            ),
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (offset > 0)
              TextButton(
                onPressed: () => setState(() => offset -= 50),
                child: const AppText('← Назад'),
              ),
            AppText('Всего: ${data["total"]}'),
            if (offset + 50 < (data['total'] as num))
              TextButton(
                onPressed: () => setState(() => offset += 50),
                child: const AppText('Далее →'),
              ),
          ],
        ),
      ],
    ),
  );
}

class AccountForm extends StatefulWidget {
  final Api api;
  const AccountForm({super.key, required this.api});
  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  final name = TextEditingController(),
      number = TextEditingController(),
      phone = TextEditingController(),
      login = TextEditingController();
  String role = 'member', org = '', partner = '';
  bool busy = false, loaded = false;
  List<Json> orgs = [], partners = [];
  String? error;
  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    try {
      final o = rows(await widget.api.get('/admin/organizations')),
          p = rows(await widget.api.get('/admin/partners'));
      if (mounted) {
        setState(() {
          orgs = o;
          partners = p;
          loaded = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    name.dispose();
    number.dispose();
    phone.dispose();
    login.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final r = await widget.api.post('/admin/accounts', {
        'name': name.text,
        'role': role,
        'organization_id': role == 'member' ? org : null,
        'partner_id': role == 'partner' ? partner : null,
        'employee_number': role == 'member' ? number.text : null,
        'phone': role == 'member' && phone.text.isNotEmpty ? phone.text : null,
        'username': role != 'member' ? login.text : null,
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const AppText('Аккаунт создан'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppText(
                  'Пароль показывается один раз. При первом входе его нужно заменить.',
                ),
                const SizedBox(height: 16),
                SelectableText(
                  tx(
                    'Вход: ${role == "member" ? number.text : login.text}\nВременный пароль: ${r["temporary_password"]}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const AppText('Сохранено'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('Новый доступ')),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        DropdownButtonFormField<String>(
          initialValue: role,
          decoration: InputDecoration(labelText: tx('Роль')),
          items: const [
            DropdownMenuItem(
              value: 'member',
              child: AppText('Участник профсоюза'),
            ),
            DropdownMenuItem(value: 'partner', child: AppText('Партнёр')),
            DropdownMenuItem(value: 'admin', child: AppText('Администратор')),
          ],
          onChanged: (v) => setState(() => role = v!),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: name,
          decoration: InputDecoration(labelText: tx('Имя')),
        ),
        const SizedBox(height: 14),
        if (role == 'member') ...[
          DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: tx('Организация')),
            isExpanded: true,
            items: orgs
                .map(
                  (o) => DropdownMenuItem(
                    value: s(o['id']),
                    child: AppText(s(o['name'])),
                  ),
                )
                .toList(),
            onChanged: (v) => org = v ?? '',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: number,
            decoration: InputDecoration(labelText: tx('Табельный номер')),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: phone,
            decoration: InputDecoration(
              labelText: tx('Телефон, необязательно (+7…)'),
            ),
          ),
        ] else ...[
          TextField(
            controller: login,
            decoration: InputDecoration(labelText: tx('Логин (латиница)')),
          ),
          if (role == 'partner')
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: tx('Партнёр')),
                isExpanded: true,
                items: partners
                    .map(
                      (p) => DropdownMenuItem(
                        value: s(p['id']),
                        child: AppText(s(p['name'])),
                      ),
                    )
                    .toList(),
                onChanged: (v) => partner = v ?? '',
              ),
            ),
        ],
        const SizedBox(height: 24),
        if (error != null)
          AppText(error!, style: const TextStyle(color: Colors.red)),
        ActionButton(
          busy ? 'Создаём…' : 'Создать и выдать временный пароль',
          onPressed: busy || !loaded ? null : save,
        ),
      ],
    ),
  );
}

class AdminTickets extends StatelessWidget {
  final Api api;
  const AdminTickets({super.key, required this.api});
  @override
  Widget build(BuildContext context) => LoadView(
    load: () => api.get('/tickets'),
    builder: (data, refresh) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AppText('Обращения', style: titleStyle(30)),
        const SizedBox(height: 16),
        if ((data as List).isEmpty) const Empty('Новых обращений нет'),
        ...rows(data).map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(s(t['subject']), style: titleStyle(23)),
                  AppText(s(t['message'])),
                  AppText(
                    'Статус: ${human(t["status"])}',
                    style: const TextStyle(color: muted),
                  ),
                  if (s(t['reply']).isNotEmpty) AppText('Ответ: ${t["reply"]}'),
                  TextButton(
                    onPressed: () async {
                      final reply = await askText(context, 'Ответ участнику');
                      if (reply == null) return;
                      try {
                        await api.post('/admin/tickets/${t["id"]}', {
                          'status': 'closed',
                          'reply': reply,
                        });
                        refresh();
                      } catch (e) {
                        if (context.mounted) toast(context, e);
                      }
                    },
                    child: const AppText('Ответить и закрыть'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class AuditPage extends StatelessWidget {
  final Api api;
  const AuditPage({super.key, required this.api});
  @override
  Widget build(BuildContext context) => LoadView(
    load: () => api.get('/admin/audit?limit=200'),
    builder: (data, refresh) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AppText('Журнал действий', style: titleStyle(30)),
        const SizedBox(height: 18),
        ...rows(data).map(
          (a) => ListTile(
            leading: const Icon(Icons.history, color: purple),
            title: AppText(human(a['action'])),
            subtitle: SelectableText(
              tx(
                '${displayMoment(a["created_at"])}\nОбъект: ${a["target"]}\n${jsonEncode(a["detail"])}',
              ),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    ),
  );
}
