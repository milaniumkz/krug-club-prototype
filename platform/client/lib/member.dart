import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'ui.dart';
import 'main.dart' show PasswordPage;
import 'map_scan.dart';

class MemberShell extends StatefulWidget {
  final Api api;
  const MemberShell({super.key, required this.api});
  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _MemberShellState extends State<MemberShell> {
  int tab = 0;
  void go(int value) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => tab = value);
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    final pages = [
      HomePage(api: api, go: go),
      CatalogPage(api: api),
      ScannerPage(api: api),
      VenueMap(api: api),
      ProfilePage(api: api),
    ];
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) go(0);
      },
      child: Scaffold(
        appBar: tab == 2
            ? null
            : AppBar(
                title: const SizedBox(width: 260, child: Brand()),
                actions: [
                  if (tab == 0)
                    IconButton(
                      tooltip: 'История скидок',
                      onPressed: () => route(context, HistoryPage(api: api)),
                      icon: const Icon(Icons.history_rounded),
                    ),
                ],
              ),
        body: SafeArea(child: pages[tab]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: go,
          height: 76,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Главная',
            ),
            const NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront_rounded),
              label: 'Партнёры',
            ),
            NavigationDestination(
              icon: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: purple,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white,
                ),
              ),
              label: 'QR',
            ),
            const NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: 'На карте',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }
}

class ClubCard extends StatelessWidget {
  final Json user;
  const ClubCard({super.key, required this.user});
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 190),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        colors: [Color(0xffeadcf0), Color(0xffb88fd7), Color(0xff7344a6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x307133bd),
          blurRadius: 22,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                'QAZAQMETAL',
                style: TextStyle(
                  fontFamily: 'PTSerif',
                  fontSize: 25,
                  letterSpacing: 3,
                  color: ink,
                ),
              ),
            ),
            Icon(Icons.contactless_outlined, color: Colors.white, size: 35),
          ],
        ),
        const Text('Карта члена профсоюза', style: TextStyle(color: ink)),
        const SizedBox(height: 32),
        Text(
          s(user['name']),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
        ),
        Text(
          'Табельный № ${s(user['employee_number'])}',
          style: const TextStyle(color: ink),
        ),
      ],
    ),
  );
}

class HomePage extends StatelessWidget {
  final Api api;
  final void Function(int) go;
  const HomePage({super.key, required this.api, required this.go});
  @override
  Widget build(BuildContext context) => LoadView(
    load: () async => [
      await api.get('/catalog?limit=6'),
      await api.get('/banners'),
    ],
    builder: (data, refresh) {
      final venues = rows(data[0]['items']), banners = rows(data[1]);
      return RefreshIndicator(
        onRefresh: () async => refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text(
              'Добрый день,\n${s(api.user!['name'])}!',
              style: titleStyle(31),
            ),
            const SizedBox(height: 8),
            const Text(
              'Привилегии вашего профсоюза — рядом',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 24),
            ClubCard(user: api.user!),
            const SizedBox(height: 16),
            Panel(
              color: const Color(0xffe0edcf),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      api.user!['member_until'] == null
                          ? 'Членство активно'
                          : 'Членство до ${s(api.user!["member_until"]).split("T").first}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ActionButton(
              'Сканировать QR',
              onPressed: () => go(2),
              icon: Icons.qr_code_scanner_rounded,
            ),
            if (banners.isNotEmpty) ...[
              const SizedBox(height: 24),
              SizedBox(
                height: 230,
                child: PageView(
                  children: banners
                      .map(
                        (b) => Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: InkWell(
                            onTap: () => route(
                              context,
                              VenuePage(api: api, id: s(b['venue_id'])),
                            ),
                            child: Panel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: RemotePhoto(
                                      api: api,
                                      path: s(b['data']['image']),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    s(b['data']['name']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: titleStyle(19),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(child: Text('Партнёры клуба', style: titleStyle(23))),
                TextButton(onPressed: () => go(1), child: const Text('Все →')),
              ],
            ),
            if (venues.isEmpty) const Empty('Партнёры скоро появятся здесь'),
            ...venues.map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: VenueTile(api: api, venue: v),
              ),
            ),
            const SizedBox(height: 8),
            ActionButton(
              'Заведения на карте',
              onPressed: () => go(3),
              icon: Icons.map_outlined,
            ),
          ],
        ),
      );
    },
  );
}

class VenueTile extends StatelessWidget {
  final Api api;
  final Json venue;
  const VenueTile({super.key, required this.api, required this.venue});
  @override
  Widget build(BuildContext context) {
    final d = Json.from(venue['data'] as Map),
        offers = rows(venue['offers'] ?? []);
    return Semantics(
      button: true,
      label: s(d['name']),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => route(context, VenuePage(api: api, id: s(venue['id']))),
        child: Panel(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 92,
                child: RemotePhoto(api: api, path: s(d['image']), height: 116),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s(d['category']),
                      style: const TextStyle(
                        fontSize: 10,
                        color: purple,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(s(d['name']), style: titleStyle(20)),
                    const SizedBox(height: 6),
                    Text(
                      s(d['address']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 10,
                      children: [
                        if (offers.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: lavender,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '−${offers.map((o) => (o['data']['percent'] as num).toInt()).reduce((a, b) => a > b ? a : b)}%',
                              style: const TextStyle(
                                color: purple,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        if (venue['distance_km'] != null)
                          Text(
                            '${venue["distance_km"]} км',
                            style: const TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CatalogPage extends StatefulWidget {
  final Api api;
  final bool favorites;
  const CatalogPage({super.key, required this.api, this.favorites = false});
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  String q = '', category = '';
  Timer? timer;
  int offset = 0;
  final search = TextEditingController();
  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<dynamic> load() async {
    if (widget.favorites) {
      final ids = await widget.api.get('/me/favorites') as List;
      final list = <Json>[];
      for (final id in ids) {
        try {
          list.add(Json.from(await widget.api.get('/catalog/$id') as Map));
        } on ApiError catch (e) {
          if (e.status != 404) rethrow;
        }
      }
      return {'items': list, 'total': list.length};
    }
    return widget.api.get(
      '/catalog?q=${Uri.encodeQueryComponent(q)}&category=${Uri.encodeQueryComponent(category)}&offset=$offset&limit=30',
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.favorites ? 'Избранное' : 'Партнёры',
              style: titleStyle(32),
            ),
            const SizedBox(height: 14),
            if (!widget.favorites)
              TextField(
                controller: search,
                decoration: const InputDecoration(
                  hintText: 'Найти партнёра',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) {
                  timer?.cancel();
                  timer = Timer(
                    const Duration(milliseconds: 350),
                    () => setState(() {
                      q = v;
                      offset = 0;
                    }),
                  );
                },
              ),
            if (!widget.favorites)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children:
                      [
                            'Все',
                            'Рестораны',
                            'Кафе',
                            'Магазины',
                            'Красота',
                            'Спорт',
                            'Услуги',
                          ]
                          .map(
                            (c) => Padding(
                              padding: const EdgeInsets.only(right: 8, top: 12),
                              child: ChoiceChip(
                                label: Text(c),
                                selected: category == (c == 'Все' ? '' : c),
                                onSelected: (_) => setState(() {
                                  category = c == 'Все' ? '' : c;
                                  offset = 0;
                                }),
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: LoadView(
          key: ValueKey('$q|$category|$offset|${widget.favorites}'),
          load: load,
          builder: (data, refresh) {
            final items = rows(data['items']);
            return RefreshIndicator(
              onRefresh: () async => refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  if (items.isEmpty)
                    const Empty('Заведений пока нет. Попробуйте другой поиск'),
                  ...items.map(
                    (v) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: VenueTile(api: widget.api, venue: v),
                    ),
                  ),
                  if (!widget.favorites)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (offset > 0)
                          TextButton(
                            onPressed: () => setState(() => offset -= 30),
                            child: const Text('← Назад'),
                          ),
                        Text(
                          '${offset + 1}–${offset + items.length} / ${data["total"]}',
                        ),
                        if (offset + items.length < (data['total'] as num))
                          TextButton(
                            onPressed: () => setState(() => offset += 30),
                            child: const Text('Далее →'),
                          ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ],
  );
}

class VenuePage extends StatelessWidget {
  final Api api;
  final String id;
  const VenuePage({super.key, required this.api, required this.id});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Заведение')),
    body: SafeArea(
      child: LoadView(
        load: () async => [
          await api.get('/catalog/$id'),
          await api.get('/me/favorites'),
        ],
        builder: (data, refresh) {
          final v = Json.from(data[0] as Map),
              d = Json.from(v['data'] as Map),
              offers = rows(v['offers']),
              saved = (data[1] as List).contains(id);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              RemotePhoto(api: api, path: s(d['image']), height: 260),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(child: Text(s(d['name']), style: titleStyle(32))),
                  IconButton(
                    tooltip: saved ? 'Убрать из избранного' : 'В избранное',
                    icon: Icon(
                      saved ? Icons.bookmark : Icons.bookmark_border,
                      color: purple,
                    ),
                    onPressed: () async {
                      try {
                        await api.request(
                          saved ? 'DELETE' : 'PUT',
                          '/me/favorites/$id',
                        );
                        refresh();
                      } catch (e) {
                        if (context.mounted) toast(context, e);
                      }
                    },
                  ),
                ],
              ),
              Text(s(d['category']), style: const TextStyle(color: purple)),
              const SizedBox(height: 16),
              Text(s(d['description'])),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on_outlined),
                title: Text(s(d['address'])),
              ),
              if (s(d['hours']).isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(s(d['hours'])),
                ),
              if (s(d['phone']).isNotEmpty) SelectableText(s(d['phone'])),
              const SizedBox(height: 18),
              if (offers.isEmpty)
                const Panel(
                  child: Text(
                    'Сейчас нет действующих скидок для вашей организации',
                  ),
                ),
              ...offers.map(
                (o) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Panel(
                    color: lavender,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '−${o["data"]["percent"]}%',
                          style: titleStyle(40).copyWith(color: purple),
                        ),
                        Text(s(o['data']['name']), style: titleStyle(23)),
                        const SizedBox(height: 10),
                        Text(s(o['data']['terms'])),
                        if (o['data']['ends_on'] != null)
                          Text('До ${o["data"]["ends_on"]}'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ActionButton(
                'Сканировать QR',
                onPressed: () => route(
                  context,
                  Scaffold(
                    appBar: AppBar(title: const Text('Сканер QR')),
                    body: ScannerPage(api: api),
                  ),
                ),
                icon: Icons.qr_code_scanner_rounded,
              ),
            ],
          );
        },
      ),
    ),
  );
}

class HistoryPage extends StatelessWidget {
  final Api api;
  const HistoryPage({super.key, required this.api});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('История скидок')),
    body: LoadView(
      load: () => api.get('/me/history?limit=200'),
      builder: (data, refresh) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if ((data as List).isEmpty)
            const Empty('Здесь появятся полученные скидки'),
          ...rows(data).map(
            (v) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Panel(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: lavender,
                    child: Icon(Icons.redeem_rounded, color: purple),
                  ),
                  title: Text(s(v['venue_name']), style: titleStyle(20)),
                  subtitle: Text(
                    '${s(v["created_at"]).replaceFirst("T", " ").substring(0, 16)}\n${v["offer_name"]}',
                  ),
                  trailing: Text(
                    '−${v["percent"]}%',
                    style: const TextStyle(
                      color: purple,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () =>
                      route(context, VenuePage(api: api, id: s(v['venue_id']))),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class ProfilePage extends StatelessWidget {
  final Api api;
  const ProfilePage({super.key, required this.api});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Профиль', style: titleStyle(32)),
      const SizedBox(height: 20),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 30,
              backgroundColor: lavender,
              child: Icon(Icons.person_outline, size: 38, color: purple),
            ),
            const SizedBox(height: 16),
            Text(s(api.user!['name']), style: titleStyle(27)),
            if (api.user!['role'] == 'member')
              Text('Табельный номер: ${s(api.user!["employee_number"])}')
            else
              Text(
                api.user!['role'] == 'partner' ? 'Партнёр' : 'Администратор',
              ),
            Text(
              s(api.user!['organization_name'] ?? api.user!['partner_name']),
              style: const TextStyle(color: muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      if (api.user!['role'] == 'member') ...[
        profileTile(
          context,
          'Моя карта',
          Icons.credit_card_outlined,
          () => route(
            context,
            Scaffold(
              appBar: AppBar(title: const Text('Карта участника')),
              body: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(children: [ClubCard(user: api.user!)]),
              ),
            ),
          ),
        ),
        profileTile(
          context,
          'Избранное',
          Icons.favorite_outline,
          () => route(
            context,
            Scaffold(
              appBar: AppBar(title: const Text('Избранное')),
              body: CatalogPage(api: api, favorites: true),
            ),
          ),
        ),
        profileTile(
          context,
          'История скидок',
          Icons.history_rounded,
          () => route(context, HistoryPage(api: api)),
        ),
      ],
      profileTile(
        context,
        'Изменить пароль',
        Icons.lock_outline,
        () => route(context, PasswordPage(api: api)),
      ),
      profileTile(
        context,
        'Поддержка',
        Icons.headset_mic_outlined,
        () => route(context, TicketsPage(api: api)),
      ),
      profileTile(
        context,
        'Активные сессии',
        Icons.devices_outlined,
        () => route(context, SessionsPage(api: api)),
      ),
      profileTile(context, 'Выйти', Icons.logout_rounded, () async {
        if (await confirm(
          context,
          'Выйти из аккаунта?',
          'Сессии на всех устройствах будут закрыты',
        )) {
          try {
            await api.logout();
          } catch (e) {
            if (context.mounted) toast(context, e);
          }
        }
      }),
      const SizedBox(height: 16),
      const Text(
        'QAZAQMETAL KÁSIPODAǴY\nПривилегии только для членов профсоюза',
        style: TextStyle(color: muted, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    ],
  );
  Widget profileTile(
    BuildContext c,
    String label,
    IconData icon,
    VoidCallback tap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Panel(
      padding: const EdgeInsets.all(4),
      child: ListTile(
        leading: Icon(icon, color: purple),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: tap,
      ),
    ),
  );
}

class TicketsPage extends StatelessWidget {
  final Api api;
  const TicketsPage({super.key, required this.api});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Поддержка')),
    body: LoadView(
      load: () => api.get('/tickets'),
      builder: (data, refresh) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ActionButton(
            'Новое обращение',
            onPressed: () async {
              await route(context, TicketForm(api: api));
              refresh();
            },
            icon: Icons.add,
          ),
          const SizedBox(height: 20),
          if ((data as List).isEmpty) const Empty('У вас пока нет обращений'),
          ...rows(data).map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s(t['subject']), style: titleStyle(21)),
                    Text(s(t['message'])),
                    Text(
                      'Статус: ${human(t["status"])}',
                      style: const TextStyle(color: muted),
                    ),
                    if (s(t['reply']).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('Ответ: ${t["reply"]}'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class TicketForm extends StatefulWidget {
  final Api api;
  const TicketForm({super.key, required this.api});
  @override
  State<TicketForm> createState() => _TicketFormState();
}

class _TicketFormState extends State<TicketForm> {
  final subject = TextEditingController(), message = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    subject.dispose();
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Новое обращение')),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        TextField(
          controller: subject,
          maxLength: 240,
          decoration: const InputDecoration(labelText: 'Тема'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: message,
          maxLength: 4000,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(labelText: 'Сообщение'),
        ),
        const SizedBox(height: 20),
        ActionButton(
          busy ? 'Отправляем…' : 'Отправить',
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    await widget.api.post('/tickets', {
                      'subject': subject.text,
                      'message': message.text,
                    });
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) toast(context, e);
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
        ),
      ],
    ),
  );
}

class SessionsPage extends StatelessWidget {
  final Api api;
  const SessionsPage({super.key, required this.api});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Активные сессии')),
    body: LoadView(
      load: () => api.get('/auth/sessions'),
      builder: (data, refresh) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Сессия сохраняется до 30 дней. Смена пароля или выход закрывают старые сессии.',
          ),
          ...rows(data).map(
            (session) => ListTile(
              leading: const Icon(Icons.devices),
              title: Text('Вход: ${s(session["created_at"]).split("T").first}'),
              subtitle: Text('До ${s(session["expires_at"]).split("T").first}'),
              trailing: IconButton(
                tooltip: 'Закрыть сессию',
                icon: const Icon(Icons.close),
                onPressed: () async {
                  try {
                    await api.request(
                      'DELETE',
                      '/auth/sessions/${session["id"]}',
                    );
                    await api.boot();
                    refresh();
                  } catch (e) {
                    if (context.mounted) toast(context, e);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
