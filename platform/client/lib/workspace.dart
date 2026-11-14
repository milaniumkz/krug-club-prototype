import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_selector/file_selector.dart';
import 'api.dart';
import 'ui.dart';
import 'member.dart' show ProfilePage;

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
  Widget build(BuildContext context) {
    final admin = widget.api.user!['role'] == 'admin';
    final menu = [
      'overview',
      'venue',
      'offer',
      'banner',
      if (admin) ...[
        'moderation',
        'accounts',
        'organizations',
        'partners',
        'tickets',
        'audit',
      ],
      'profile',
    ];
    Widget content() {
      switch (page) {
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
        Text(
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
              title: Text(labels[key]!),
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
        : ['overview', 'venue', 'offer', 'banner', 'profile'];
    return Scaffold(
      appBar: AppBar(
        title: Text(labels[page] ?? '', style: titleStyle(23)),
        actions: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Chip(label: Text(admin ? 'Администратор' : 'Партнёр')),
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
                      label: key == 'accounts'
                          ? 'Участники'
                          : key == 'moderation'
                          ? 'Модерация'
                          : key == 'venue'
                          ? 'Заведения'
                          : key == 'offer'
                          ? 'Акции'
                          : labels[key]!,
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

Json editData(Json row) =>
    Json.from((row['revision']?['data'] ?? row['data'] ?? {}) as Map);

class ResourceList extends StatelessWidget {
  final Api api;
  final String kind;
  const ResourceList({super.key, required this.api, required this.kind});
  @override
  Widget build(BuildContext context) => LoadView(
    key: ValueKey(kind),
    load: () => api.get('/workspace/resources?kind=$kind'),
    builder: (data, refresh) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: Text(labels[kind]!, style: titleStyle(30))),
            FilledButton.icon(
              onPressed: () async {
                await route(context, ResourceEditor(api: api, kind: kind));
                refresh();
              },
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
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
                        child: Text(s(d['name']), style: titleStyle(23)),
                      ),
                      if (row['deleted'] != true)
                        IconButton(
                          tooltip: 'Редактировать',
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
                  Text(
                    revisionStatus(row),
                    style: TextStyle(
                      color: pending ? Colors.orange.shade900 : purple,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
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
                          label: const Text('Выдать QR'),
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
                          label: const Text('Удалить'),
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
                          child: Text(
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
    'category': 'Категория',
    'address': 'Адрес',
    'phone': 'Телефон заведения',
    'hours': 'Режим работы',
    'latitude': 'Широта',
    'longitude': 'Долгота',
    'percent': 'Скидка, %',
    'terms': 'Условия и ограничения',
    'starts_on': 'Начало, ГГГГ-ММ-ДД',
    'ends_on': 'Окончание, ГГГГ-ММ-ДД',
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
      final all = rows(await widget.api.get('/workspace/resources?kind=venue'));
      venues = all.where((v) => v['deleted'] != true).toList();
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
          d[key] = text.isEmpty ? null : int.parse(text);
        } else if (key.endsWith('_on')) {
          if (text.isNotEmpty &&
              (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
                  DateTime.tryParse(text) == null)) {
            throw ApiError(422, 'Дата: ГГГГ-ММ-ДД');
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
      title: Text(
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
                  decoration: const InputDecoration(labelText: 'Партнёр'),
                  items: partners
                      .map(
                        (p) => DropdownMenuItem(
                          value: s(p['id']),
                          child: Text(s(p['name'])),
                        ),
                      )
                      .toList(),
                  onChanged: widget.row == null
                      ? (v) => setState(() => partner = v ?? '')
                      : null,
                ),
              if (widget.kind != 'venue')
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: DropdownButtonFormField<String>(
                    initialValue: venues.any((v) => v['id'] == venue)
                        ? venue
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Заведение'),
                    items: venues
                        .where(
                          (v) => partner.isEmpty || v['partner_id'] == partner,
                        )
                        .map(
                          (v) => DropdownMenuItem(
                            value: s(v['id']),
                            child: Text(s(editData(v)['name'])),
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
                            'percent',
                            'terms',
                            'starts_on',
                            'ends_on',
                          ].contains(k)
                        : ![
                                'category',
                                'address',
                                'phone',
                                'hours',
                                'latitude',
                                'longitude',
                              ].contains(k) &&
                              (widget.kind == 'offer' ||
                                  !['percent', 'terms'].contains(k)),
                  )
                  .map(
                    (key) => Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: TextField(
                        controller: controllers[key],
                        decoration: InputDecoration(labelText: names[key]),
                        maxLines: ['description', 'terms'].contains(key)
                            ? 4
                            : 1,
                        maxLength: ['description', 'terms'].contains(key)
                            ? 4000
                            : null,
                        keyboardType:
                            ['latitude', 'longitude', 'percent'].contains(key)
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
                  label: const Text('Указать координаты на карте'),
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
                label: const Text('Загрузить фотографию / баннер'),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Доступность для организаций'),
                subtitle: Text(
                  organizations.isEmpty
                      ? 'Все подключённые организации'
                      : 'Выбрано: ${organizations.length}',
                ),
                children: orgs
                    .map(
                      (o) => CheckboxListTile(
                        title: Text(s(o['name'])),
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
                Text(error!, style: const TextStyle(color: Colors.red)),
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
      if (mounted)
        setState(() {
          tiles = s(m['tiles']);
          attribution = s(m['attribution']);
        });
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Нажмите на точку на карте')),
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

class QrPrintPage extends StatelessWidget {
  final String name, code;
  const QrPrintPage({super.key, required this.name, required this.code});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('QR-код заведения')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Panel(
            child: Column(
              children: [
                const Brand(),
                const SizedBox(height: 24),
                Text(name, style: titleStyle(), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (c, constraints) => QrImageView(
                    data: code,
                    size: constraints.maxWidth.clamp(100, 340),
                    backgroundColor: Colors.white,
                  ),
                ),
                const Text(
                  'Отсканируйте в приложении QAZAQMETAL, чтобы получить скидку',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                SelectableText(code, style: const TextStyle(fontSize: 10)),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    toast(context, 'QR-код скопирован');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Скопировать текст QR'),
                ),
                const Text(
                  'Сохраните этот экран или распечатайте. Следующая выдача QR отменит этот код.',
                  style: TextStyle(color: muted, fontSize: 12),
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
        Text('Очередь модерации', style: titleStyle(30)),
        const SizedBox(height: 18),
        if ((data as List).isEmpty) const Empty('Все изменения рассмотрены'),
        ...rows(data).map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s(r['data']['name']), style: titleStyle(25)),
                  Text(
                    '${r["resource"]["kind"]} · ${r["action"] == "delete" ? "Запрос удаления" : "Изменение / публикация"}',
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
                                Text(
                                  pair.$1,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (pair.$2 == null)
                                  const Text('Ещё не опубликовано')
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
                                          child: Text(
                                            '${e.key}: ${e.value}',
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
                        label: const Text('Одобрить'),
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
                        label: const Text('Отклонить'),
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
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) {
      setState(() {
        if (first) {
          start = d;
        } else {
          end = d;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => LoadView(
    key: ValueKey('$start|$end|$venue'),
    load: () async => [
      await widget.api.get(
        '/workspace/stats?venue_id=$venue${start == null ? '' : '&start=${start!.toIso8601String().split('T').first}'}${end == null ? '' : '&end=${end!.toIso8601String().split('T').first}'}',
      ),
      await widget.api.get('/workspace/resources?kind=venue'),
    ],
    builder: (data, refresh) {
      final stats = Json.from(data[0] as Map);
      final venues = rows(data[1]);
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Результаты клуба', style: titleStyle(30)),
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
                        Text('${metric.$2}', style: titleStyle(34)),
                        Text(
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
                child: Text(
                  start == null
                      ? 'Дата от'
                      : start!.toIso8601String().split('T').first,
                ),
              ),
              OutlinedButton(
                onPressed: () => choose(false),
                child: Text(
                  end == null
                      ? 'Дата до'
                      : end!.toIso8601String().split('T').first,
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  start = null;
                  end = null;
                  venue = '';
                }),
                child: const Text('Сбросить'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: venue,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Заведение'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Все заведения')),
              ...venues.map(
                (v) => DropdownMenuItem(
                  value: s(v['id']),
                  child: Text(s(editData(v)['name'])),
                ),
              ),
            ],
            onChanged: (v) => setState(() => venue = v ?? ''),
          ),
          const SizedBox(height: 22),
          Text('По заведениям', style: titleStyle(23)),
          ...rows(stats['venues']).map(
            (v) => ListTile(
              leading: const Icon(Icons.storefront_outlined, color: purple),
              title: Text(s(v['name'])),
              trailing: Text(
                '${v["uses"]} скидок',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Операции', style: titleStyle(23)),
          if ((stats['operations'] as List).isEmpty)
            const Empty('Применений за выбранный период нет'),
          ...rows(stats['operations']).map(
            (o) => ListTile(
              title: Text(s(o['venue_name'])),
              subtitle: Text('${o["created_at"]}\n${o["offer_name"]}'),
              trailing: Text(
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
            label: const Text('Скопировать CSV операций'),
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
      title: Text(title),
      content: TextField(
        controller: c,
        maxLength: 1000,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(labelText: 'Комментарий'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (c.text.trim().length >= 3) Navigator.pop(ctx, c.text.trim());
          },
          child: const Text('Продолжить'),
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
            Expanded(child: Text(labels[kind]!, style: titleStyle(30))),
            FilledButton.icon(
              onPressed: () async {
                await route(context, EntityForm(api: api, kind: kind));
                refresh();
              },
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
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
                title: Text(s(e['name']), style: titleStyle(22)),
                subtitle: Text(
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
    appBar: AppBar(title: Text(widget.row == null ? 'Добавить' : 'Изменить')),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        if (widget.kind == 'organizations')
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: TextField(
              controller: code,
              decoration: const InputDecoration(
                labelText: 'Код организации (латиница / цифры)',
              ),
            ),
          ),
        SwitchListTile(
          title: const Text('Доступ разрешён'),
          subtitle: const Text(
            'Отключение закрывает доступ связанных аккаунтов',
          ),
          value: active,
          onChanged: (v) => setState(() => active = v),
        ),
        const SizedBox(height: 20),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
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
        title: const Text('Сохраните данные для первого входа'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Пароли показываются один раз. Передавайте их каждому работнику отдельно. Не публикуйте общий список.',
              ),
              const SizedBox(height: 14),
              SelectableText(text),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              toast(ctx, 'Скопировано');
            },
            child: const Text('Скопировать'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Сохранено'),
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
          title: const Text('Организация для импорта'),
          children: orgs
              .map(
                (o) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, s(o['id'])),
                  child: Text(s(o['name'])),
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
        Text('Участники и доступ', style: titleStyle(30)),
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
              label: const Text('Добавить'),
            ),
            OutlinedButton.icon(
              onPressed: importing ? null : () => importCsv(refresh),
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(importing ? 'Загрузка…' : 'Импорт CSV'),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Text(
            'CSV UTF-8: employee_number,name,phone. Телефон необязателен. До 500 работников за загрузку. Удаление из клуба — только при увольнении; за нарушение правил — блокировка.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
        TextField(
          controller: search,
          decoration: const InputDecoration(
            labelText: 'Имя или табельный номер',
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
                  label: Text(
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
                  Text(s(person['name']), style: titleStyle(22)),
                  Text(
                    '${person["role"]} · ${person["status"]} · № ${s(person["employee_number"])}',
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
                        label: const Text('Временный пароль'),
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
                            child: Text(
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
                child: const Text('← Назад'),
              ),
            Text('Всего: ${data["total"]}'),
            if (offset + 50 < (data['total'] as num))
              TextButton(
                onPressed: () => setState(() => offset += 50),
                child: const Text('Далее →'),
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
          title: const Text('Аккаунт создан'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Пароль показывается один раз. При первом входе его нужно заменить.',
                ),
                const SizedBox(height: 16),
                SelectableText(
                  'Вход: ${role == "member" ? number.text : login.text}\nВременный пароль: ${r["temporary_password"]}',
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Сохранено'),
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
    appBar: AppBar(title: const Text('Новый доступ')),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        DropdownButtonFormField<String>(
          initialValue: role,
          decoration: const InputDecoration(labelText: 'Роль'),
          items: const [
            DropdownMenuItem(
              value: 'member',
              child: Text('Участник профсоюза'),
            ),
            DropdownMenuItem(value: 'partner', child: Text('Партнёр')),
            DropdownMenuItem(value: 'admin', child: Text('Администратор')),
          ],
          onChanged: (v) => setState(() => role = v!),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Имя'),
        ),
        const SizedBox(height: 14),
        if (role == 'member') ...[
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Организация'),
            isExpanded: true,
            items: orgs
                .map(
                  (o) => DropdownMenuItem(
                    value: s(o['id']),
                    child: Text(s(o['name'])),
                  ),
                )
                .toList(),
            onChanged: (v) => org = v ?? '',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: number,
            decoration: const InputDecoration(labelText: 'Табельный номер'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: phone,
            decoration: const InputDecoration(
              labelText: 'Телефон, необязательно (+7…)',
            ),
          ),
        ] else ...[
          TextField(
            controller: login,
            decoration: const InputDecoration(labelText: 'Логин (латиница)'),
          ),
          if (role == 'partner')
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Партнёр'),
                isExpanded: true,
                items: partners
                    .map(
                      (p) => DropdownMenuItem(
                        value: s(p['id']),
                        child: Text(s(p['name'])),
                      ),
                    )
                    .toList(),
                onChanged: (v) => partner = v ?? '',
              ),
            ),
        ],
        const SizedBox(height: 24),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
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
        Text('Обращения', style: titleStyle(30)),
        const SizedBox(height: 16),
        if ((data as List).isEmpty) const Empty('Новых обращений нет'),
        ...rows(data).map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s(t['subject']), style: titleStyle(23)),
                  Text(s(t['message'])),
                  Text(
                    'Статус: ${t["status"]}',
                    style: const TextStyle(color: muted),
                  ),
                  if (s(t['reply']).isNotEmpty) Text('Ответ: ${t["reply"]}'),
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
                    child: const Text('Ответить и закрыть'),
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
        Text('Журнал действий', style: titleStyle(30)),
        const SizedBox(height: 18),
        ...rows(data).map(
          (a) => ListTile(
            leading: const Icon(Icons.history, color: purple),
            title: Text(s(a['action'])),
            subtitle: SelectableText(
              '${a["created_at"]}\nОбъект: ${a["target"]}\n${jsonEncode(a["detail"])}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    ),
  );
}
