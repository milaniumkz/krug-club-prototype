import 'i18n.dart';
import 'app_settings.dart';
import 'remote_settings_ui.dart';
import 'push_service.dart';
import 'date_field.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'ui.dart';
import 'main.dart' show PasswordPage;
import 'pin_lock.dart' show PinSettingsPage;
import 'map_scan.dart';

class MemberShell extends StatefulWidget {
  final Api api;
  const MemberShell({super.key, required this.api});
  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _ShellObserver extends NavigatorObserver {
  final VoidCallback changed;
  _ShellObserver(this.changed);
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      changed();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => changed();
}

class _MemberShellState extends State<MemberShell> {
  bool secondary = false;
  late final observer = _ShellObserver(() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => secondary = navigator.currentState?.canPop() ?? false);
      }
    });
  });

  @override
  void initState() {
    super.initState();
    widget.api.addListener(openPendingNotification);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => openPendingNotification(),
    );
  }

  void openPendingNotification() {
    if (mounted &&
        widget.api.notificationsRequested &&
        navigator.currentState != null) {
      widget.api.notificationsRequested = false;
      navigator.currentState!.push(
        MaterialPageRoute(builder: (_) => NotificationsPage(api: widget.api)),
      );
    }
  }

  int tab = 0;
  final navigator = GlobalKey<NavigatorState>();
  final selection = ValueNotifier<int>(0);
  @override
  void dispose() {
    widget.api.removeListener(openPendingNotification);
    selection.dispose();
    super.dispose();
  }

  void go(int value) {
    FocusManager.instance.primaryFocus?.unfocus();
    navigator.currentState?.popUntil((route) => route.isFirst);
    selection.value = value;
    setState(() => tab = value);
  }

  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    final api = widget.api;
    Widget pageFor(int index) => [
      HomePage(api: api, go: go),
      CatalogPage(api: api),
      appSettings.feature('qr')
          ? ScannerPage(api: api)
          : const FeatureUnavailable('QR'),
      appSettings.feature('map')
          ? VenueMap(api: api)
          : const FeatureUnavailable('На карте'),
      ProfilePage(api: api),
    ][index];
    return PopScope(
      canPop: tab == 0 && !(navigator.currentState?.canPop() ?? false),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (navigator.currentState?.canPop() ?? false) {
            navigator.currentState!.pop();
          } else {
            go(0);
          }
        }
      },
      child: Scaffold(
        appBar: secondary || tab == 2
            ? null
            : AppBar(
                backgroundColor: tab == 0 ? deepPurple : paper,
                foregroundColor: tab == 0 ? Colors.white : ink,
                title: const SizedBox(width: 250, child: Brand()),
                actions: [
                  if (tab == 0)
                    IconButton(
                      tooltip: tx('Уведомления'),
                      onPressed: () => navigator.currentState!.push(
                        MaterialPageRoute(
                          builder: (_) => NotificationsPage(api: api),
                        ),
                      ),
                      icon: const Icon(Icons.notifications_none_rounded),
                    ),
                ],
              ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: tab == 0 ? 1100 : 900),
              child: Navigator(
                key: navigator,
                observers: [observer],
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => ListenableBuilder(
                    listenable: Listenable.merge([selection, appSettings]),
                    builder: (_, _) => pageFor(selection.value),
                  ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: ColoredBox(
          color: const Color(0xfffffcf9),
          child: SafeArea(
            top: false,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: NavigationBar(
                  selectedIndex: tab,
                  onDestinationSelected: go,
                  height: 76,
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: appSettings.label(
                        'home',
                        appLanguage.code,
                        tx('Главная'),
                      ),
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.storefront_outlined),
                      selectedIcon: Icon(Icons.storefront_rounded),
                      label: appSettings.label(
                        'partners',
                        appLanguage.code,
                        tx('Партнёры'),
                      ),
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
                      label: appSettings.label(
                        'qr',
                        appLanguage.code,
                        tx('QR'),
                      ),
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.map_outlined),
                      selectedIcon: Icon(Icons.map_rounded),
                      label: appSettings.label(
                        'map',
                        appLanguage.code,
                        tx('На карте'),
                      ),
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: appSettings.label(
                        'profile',
                        appLanguage.code,
                        tx('Профиль'),
                      ),
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

class ClubCard extends StatelessWidget {
  final Json user;
  const ClubCard({super.key, required this.user});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 190),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x307133bd),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xfff2e6f3),
                      Color(0xffc7a6df),
                      Color(0xff9165ba),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            Positioned(
              right: -70,
              top: -75,
              child: Container(
                width: 240,
                height: 310,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .09),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .45),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -102,
              top: -85,
              child: Container(
                width: 240,
                height: 310,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .2),
                    width: 16,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: AppText(
                              'QMET+',
                              style: titleStyle(26).copyWith(letterSpacing: 2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Icon(
                        Icons.contactless_outlined,
                        color: Colors.white,
                        size: 32,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const AppText(
                    'Карта члена профсоюза',
                    style: TextStyle(color: ink, fontSize: 12),
                  ),
                  const SizedBox(height: 29),
                  AppText(
                    s(user['name']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: ink,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AppText(
                    'Табельный № ${s(user['employee_number'])}',
                    style: const TextStyle(color: ink, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  final Api api;
  final void Function(int) go;
  const HomePage({super.key, required this.api, required this.go});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return LoadView(
      load: () async {
        if (membershipExpired(api.user!)) {
          return [
            {'items': []},
            [],
          ];
        }
        final data = await Future.wait([
          api.get('/catalog?limit=6'),
          api.get('/banners'),
        ]);
        return data;
      },
      builder: (data, refresh) {
        final venues = rows(data[0]['items']), banners = rows(data[1]);
        final expired = membershipExpired(api.user!);
        final hero = Container(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
            gradient: LinearGradient(
              colors: [deepPurple, Color(0xff3c2552), Color(0xff201726)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppText(
                settingsText(
                  'eyebrow',
                  fallback: tx('ПРИВИЛЕГИИ ВАШЕГО ПРОФСОЮЗА'),
                ),
                style: TextStyle(
                  color: Color(0xffc9b3e5),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 13),
              AppText(
                settingsText(
                  'greeting',
                  fallback: tx('Добрый день,\n{name}!'),
                ).replaceAll('{name}', s(api.user!['name'])),
                style: titleStyle(
                  32,
                ).copyWith(color: Colors.white, height: 1.12),
              ),
              const SizedBox(height: 9),
              AppText(
                settingsText('tagline', fallback: tx('Выгодно быть вместе')),
                style: TextStyle(color: Color(0xffd7cddd), fontSize: 13),
              ),
              const SizedBox(height: 25),
              ClubCard(user: api.user!),
              const SizedBox(height: 17),

              ActionButton(
                'Сканировать QR',
                onPressed: expired || !appSettings.feature('qr')
                    ? null
                    : () => go(2),
                icon: Icons.qr_code_scanner_rounded,
              ),
              if (expired)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: AppText(
                    'Для продления обратитесь к представителю профсоюза через поддержку в профиле.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        );
        final nearby = Padding(
          padding: const EdgeInsets.fromLTRB(20, 17, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeading(
                settingsText('partners_title', fallback: tx('Партнёры клуба')),
                action: 'Смотреть все →',
                onAction: () => go(1),
              ),
              const SizedBox(height: 8),
              if (venues.isEmpty)
                Empty(
                  expired
                      ? 'Продлите членство, чтобы пользоваться предложениями'
                      : 'Партнёры скоро появятся здесь',
                ),
              ...venues.map(
                (v) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: VenueTile(api: api, venue: v),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 9,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => go(3),
                    icon: const Icon(Icons.map_outlined),
                    label: const AppText('На карте'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => route(context, HistoryPage(api: api)),
                    icon: const Icon(Icons.history_rounded),
                    label: const AppText('История скидок'),
                  ),
                ],
              ),
            ],
          ),
        );
        final promotions = banners.isEmpty || !appSettings.feature('banners')
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeading(
                      settingsText(
                        'offers_title',
                        fallback: tx('Особые предложения'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 225,
                      child: PageView(
                        children: banners
                            .map(
                              (b) => Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(24),
                                  onTap: () => route(
                                    context,
                                    VenuePage(api: api, id: s(b['venue_id'])),
                                  ),
                                  child: Panel(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: RemotePhoto(
                                            api: api,
                                            path: s(b['data']['image']),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(9),
                                          child: AppText(
                                            s(localizedData(b)['name']),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: titleStyle(19),
                                          ),
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
                ),
              );
        return LayoutBuilder(
          builder: (context, constraints) => RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (constraints.maxWidth >= 800 &&
                    appSettings.homeSections.join(',') == 'promotions,partners')
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Column(children: [hero, promotions])),
                      Expanded(child: nearby),
                    ],
                  )
                else ...[
                  hero,
                  for (final section in appSettings.homeSections)
                    section == 'promotions' ? promotions : nearby,
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class VenueTile extends StatelessWidget {
  final Api api;
  final Json venue;
  const VenueTile({super.key, required this.api, required this.venue});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    final d = localizedData(venue), offers = rows(venue['offers'] ?? []);
    return Semantics(
      button: true,
      label: tx(s(d['name'])),
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
                    AppText(
                      s(d['category']),
                      style: TextStyle(
                        fontSize: 10,
                        color: purple,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AppText(s(d['name']), style: titleStyle(20)),
                    const SizedBox(height: 6),
                    AppText(
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
                            child: AppText(
                              '−${offers.map((o) => (o['data']['percent'] as num).toInt()).reduce((a, b) => a > b ? a : b)}%',
                              style: TextStyle(
                                color: purple,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        if (venue['distance_km'] != null)
                          AppText(
                            displayDistance(venue['distance_km']),
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
  List<String> categories = [];
  Map<String, dynamic> categoryLabels = {};
  @override
  void initState() {
    super.initState();
    widget.api
        .get('/category-labels')
        .then((value) {
          if (mounted && value is Map) {
            setState(() => categoryLabels = Map<String, dynamic>.from(value));
          }
        })
        .catchError((Object _) {});
    widget.api
        .get('/categories')
        .then((value) {
          if (mounted) {
            setState(() => categories = List<String>.from(value as List));
          }
        })
        .catchError((Object _) {});
  }

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
    return widget.api.get(
      '/catalog?q=${Uri.encodeQueryComponent(q)}&category=${Uri.encodeQueryComponent(category)}&favorites_only=${widget.favorites}&offset=$offset&limit=30',
    );
  }

  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                widget.favorites ? 'Избранное' : 'Партнёры',
                style: titleStyle(32),
              ),
              const SizedBox(height: 14),
              if (!widget.favorites)
                TextField(
                  controller: search,
                  decoration: InputDecoration(
                    hintText: tx('Найти партнёра'),
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
                    children: ['Все', ...categories]
                        .map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(right: 8, top: 12),
                            child: ChoiceChip(
                              label: AppText(
                                appLanguage.code == 'kk'
                                    ? s(categoryLabels[c] ?? tx(c))
                                    : c,
                              ),
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
                      const Empty(
                        'Заведений пока нет. Попробуйте другой поиск',
                      ),
                    ...items.map(
                      (v) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: VenueTile(api: widget.api, venue: v),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (offset > 0)
                          TextButton(
                            onPressed: () => setState(() => offset -= 30),
                            child: const AppText('← Назад'),
                          ),
                        AppText(
                          items.isEmpty
                              ? '0 / ${data["total"]}'
                              : '${offset + 1}–${offset + items.length} / ${data["total"]}',
                        ),
                        if (offset + items.length < (data['total'] as num))
                          TextButton(
                            onPressed: () => setState(() => offset += 30),
                            child: const AppText('Далее →'),
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
}

class VenuePage extends StatelessWidget {
  final Api api;
  final String id;
  const VenuePage({super.key, required this.api, required this.id});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Scaffold(
      appBar: AppBar(title: const AppText('Заведение')),
      body: SafeArea(
        child: LoadView(
          load: () async => [
            await api.get('/catalog/$id'),
            await api.get('/me/favorites'),
          ],
          builder: (data, refresh) {
            final v = Json.from(data[0] as Map),
                d = localizedData(v),
                offers = rows(v['offers']),
                saved = (data[1] as List).contains(id);
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      RemotePhoto(api: api, path: s(d['image']), height: 260),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: AppText(s(d['name']), style: titleStyle(32)),
                          ),
                          IconButton(
                            tooltip: tx(
                              saved ? 'Убрать из избранного' : 'В избранное',
                            ),
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
                      AppText(
                        s(d['category']),
                        style: TextStyle(color: purple),
                      ),
                      const SizedBox(height: 16),
                      AppText(s(d['description'])),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.location_on_outlined),
                        title: AppText(s(d['address'])),
                      ),
                      if (s(d['hours']).isNotEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.schedule),
                          title: AppText(s(d['hours'])),
                        ),
                      if (s(d['phone']).isNotEmpty)
                        SelectableText(tx(s(d['phone']))),
                      const SizedBox(height: 18),
                      if (offers.isEmpty)
                        const Panel(
                          child: AppText(
                            'Сейчас нет действующих скидок для вашей организации',
                          ),
                        ),
                      ...rows(v['banners'] ?? []).map(
                        (banner) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 100,
                                      maxHeight: 600,
                                    ),
                                    child: Image.network(
                                      '${api.base}${s(banner['data']['image'])}',
                                      headers: api.headers,
                                      width: double.infinity,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.image_outlined,
                                        size: 48,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                AppText(
                                  s(localizedData(banner)['name']),
                                  style: titleStyle(21),
                                ),
                                AppText(
                                  s(localizedData(banner)['description']),
                                ),
                              ],
                            ),
                          ),
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
                                AppText(
                                  '−${o["data"]["percent"]}%',
                                  style: titleStyle(40).copyWith(color: purple),
                                ),
                                AppText(
                                  s(localizedData(o)['name']),
                                  style: titleStyle(23),
                                ),
                                const SizedBox(height: 10),
                                AppText(s(localizedData(o)['terms'])),
                                if (o['data']['ends_on'] != null)
                                  AppText(
                                    'До ${displayDate(o["data"]["ends_on"])}',
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 17),
                  decoration: BoxDecoration(
                    color: paper,
                    border: Border(top: BorderSide(color: paleBorder)),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ActionButton(
                      'Сканировать QR',
                      onPressed: offers.isEmpty
                          ? null
                          : () => route(
                              context,
                              Scaffold(
                                appBar: AppBar(
                                  title: const AppText('Сканер QR'),
                                ),
                                body: ScannerPage(api: api),
                              ),
                            ),
                      icon: Icons.qr_code_scanner_rounded,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class HistoryPage extends StatefulWidget {
  final Api api;
  const HistoryPage({super.key, required this.api});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  int offset = 0;
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Scaffold(
      appBar: AppBar(title: const AppText('История скидок')),
      body: LoadView(
        key: ValueKey(offset),
        load: () => widget.api.get('/me/history?limit=31&offset=$offset'),
        builder: (data, refresh) {
          final records = rows(data), page = records.take(30).toList();
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                AppText('Ваши привилегии', style: titleStyle(29)),
                const SizedBox(height: 8),
                const AppText(
                  'История посещений и полученных скидок',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 20),
                if (page.isEmpty)
                  const Empty('Здесь появятся полученные скидки'),
                ...page.map(
                  (v) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Panel(
                      padding: const EdgeInsets.all(14),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: lavender,
                          child: Icon(Icons.redeem_rounded, color: purple),
                        ),
                        title: AppText(
                          s(v['venue_name']),
                          style: titleStyle(20),
                        ),
                        subtitle: AppText(
                          '${displayMoment(v["created_at"])}\n${tx(s(v["offer_name"]))}',
                          style: const TextStyle(fontSize: 11, height: 1.5),
                        ),
                        trailing: AppText(
                          '−${v["percent"]}%',
                          style: TextStyle(
                            color: purple,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onTap: () => route(
                          context,
                          VenuePage(api: widget.api, id: s(v['venue_id'])),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (offset > 0)
                      TextButton.icon(
                        onPressed: () => setState(() => offset -= 30),
                        icon: const Icon(Icons.chevron_left),
                        label: const AppText('Новее'),
                      ),
                    if (page.isNotEmpty)
                      AppText(
                        '${offset + 1}–${offset + page.length}',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    if (records.length > 30)
                      TextButton.icon(
                        onPressed: () => setState(() => offset += 30),
                        icon: const Icon(Icons.chevron_right),
                        label: const AppText('Ранее'),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  final Api api;
  const ProfilePage({super.key, required this.api});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Align(alignment: Alignment.centerRight, child: LanguageSwitch()),
        const SizedBox(height: 12),
        AppText('Профиль', style: titleStyle(32)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(23),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            gradient: LinearGradient(
              colors: [deepPurple, Color(0xff4f3468)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1725182f),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: lavender,
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 34,
                  color: purple,
                ),
              ),
              const SizedBox(height: 17),
              AppText(
                s(api.user!['name']),
                style: titleStyle(27).copyWith(color: Colors.white),
              ),
              const SizedBox(height: 6),
              AppText(
                api.user!['role'] == 'member'
                    ? 'Табельный номер: ${s(api.user!["employee_number"])}'
                    : api.user!['role'] == 'partner'
                    ? 'Партнёр клуба'
                    : 'Администратор',
                style: const TextStyle(color: Color(0xffe7dbef), fontSize: 12),
              ),
              if (s(
                api.user!['organization_name'] ?? api.user!['partner_name'],
              ).isNotEmpty) ...[
                const SizedBox(height: 7),
                AppText(
                  s(
                    api.user!['organization_name'] ?? api.user!['partner_name'],
                  ),
                  style: const TextStyle(
                    color: Color(0xffd0bddf),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (api.user!['role'] == 'member') ...[
          const SizedBox(height: 13),
          MembershipStatus(user: api.user!),
        ],
        const SizedBox(height: 18),
        if (api.user!['role'] == 'member') ...[
          profileTile(
            context,
            'Моя карта',
            Icons.credit_card_outlined,
            () => route(
              context,
              Scaffold(
                appBar: AppBar(title: const AppText('Карта участника')),
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
                appBar: AppBar(title: const AppText('Избранное')),
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
          'Уведомления',
          Icons.notifications_none,
          () => route(context, NotificationsPage(api: api)),
        ),
        if (api.supportsPin)
          profileTile(
            context,
            'PIN-код и биометрия',
            Icons.fingerprint,
            () => route(context, PinSettingsPage(api: api)),
          ),
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
          'Политика конфиденциальности',
          Icons.privacy_tip_outlined,
          () => route(context, const RemoteLegalPage('privacy')),
        ),
        profileTile(
          context,
          'Условия использования',
          Icons.description_outlined,
          () => route(context, const RemoteLegalPage('terms')),
        ),
        profileTile(
          context,
          'Запрос об удалении данных',
          Icons.person_remove_outlined,
          () async {
            if (await confirm(
              context,
              'Отправить запрос?',
              'Запрос поступит администрации профсоюза. Статус членства и основания хранения данных проверяются отдельно.',
            )) {
              try {
                await api.post('/me/deletion-request');
                if (context.mounted) {
                  toast(
                    context,
                    'Запрос отправлен. Ответ появится в поддержке',
                  );
                }
              } catch (e) {
                if (context.mounted) toast(context, e);
              }
            }
          },
        ),
        if (appSettings.version.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${tx('Версия')} ${appSettings.version} (${appSettings.buildNumber})',
              style: const TextStyle(color: muted),
            ),
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
        const AppText(
          'QMET+\nПривилегии только для членов профсоюза',
          style: TextStyle(color: muted, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

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
        title: AppText(label),
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
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Scaffold(
      appBar: AppBar(title: const AppText('Поддержка')),
      body: LoadView(
        load: () => api.get('/tickets'),
        builder: (data, refresh) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const RemoteSupportInfo(),
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
                      AppText(s(t['subject']), style: titleStyle(21)),
                      AppText(s(t['message'])),
                      AppText(
                        'Статус: ${human(t["status"])}',
                        style: const TextStyle(color: muted),
                      ),
                      if (s(t['reply']).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: AppText('Ответ: ${t["reply"]}'),
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
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Scaffold(
      appBar: AppBar(title: const AppText('Новое обращение')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          TextField(
            controller: subject,
            maxLength: 240,
            decoration: InputDecoration(labelText: tx('Тема')),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: message,
            maxLength: 4000,
            minLines: 4,
            maxLines: 10,
            decoration: InputDecoration(labelText: tx('Сообщение')),
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
}

class SessionsPage extends StatelessWidget {
  final Api api;
  const SessionsPage({super.key, required this.api});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Scaffold(
      appBar: AppBar(title: const AppText('Активные сессии')),
      body: LoadView(
        load: () => api.get('/auth/sessions'),
        builder: (data, refresh) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const AppText(
              'Сессия сохраняется до 30 дней. Смена пароля или выход закрывают старые сессии.',
            ),
            ...rows(data).map(
              (session) => ListTile(
                leading: const Icon(Icons.devices),
                title: AppText(
                  'Вход: ${displayMoment(session["created_at"], dateOnly: true)}',
                ),
                subtitle: AppText(
                  'До ${displayMoment(session["expires_at"], dateOnly: true)}',
                ),
                trailing: IconButton(
                  tooltip: tx('Закрыть сессию'),
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
}

class NotificationsPage extends StatelessWidget {
  final Api api;
  const NotificationsPage({super.key, required this.api});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Scaffold(
      appBar: AppBar(title: const AppText('Уведомления')),
      body: Column(
        children: [
          PushSettings(api: api),
          Expanded(
            child: LoadView(
              load: () => api.get('/me/notifications'),
              builder: (data, refresh) {
                final notices = rows(data);
                if (notices.isEmpty) {
                  return const Empty(
                    'Здесь появятся новые акции и увеличенные скидки заведений из избранного',
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: notices
                      .map(
                        (n) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Panel(
                            child: ListTile(
                              leading: Icon(
                                n['read'] == true
                                    ? Icons.notifications_none
                                    : Icons.notifications_active_outlined,
                                color: purple,
                              ),
                              title: AppText(
                                s(
                                  n[appLanguage.code == 'kk'
                                      ? 'title_kk'
                                      : 'title'],
                                ),
                              ),
                              subtitle: AppText(
                                s(
                                  n[appLanguage.code == 'kk'
                                      ? 'body_kk'
                                      : 'body'],
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                try {
                                  await api.post(
                                    '/me/notifications/${n['id']}/read',
                                  );
                                  if (context.mounted) {
                                    if (api.user?['role'] == 'member') {
                                      await route(
                                        context,
                                        VenuePage(
                                          api: api,
                                          id: s(n['venue_id']),
                                        ),
                                      );
                                    } else {
                                      await showDialog<void>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: AppText(
                                            s(
                                              n[appLanguage.code == 'kk'
                                                  ? 'title_kk'
                                                  : 'title'],
                                            ),
                                          ),
                                          content: SingleChildScrollView(
                                            child: AppText(
                                              s(
                                                n[appLanguage.code == 'kk'
                                                    ? 'body_kk'
                                                    : 'body'],
                                              ),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const AppText('Понятно'),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  }
                                  await refresh();
                                } catch (e) {
                                  if (context.mounted) toast(context, e);
                                }
                              },
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
