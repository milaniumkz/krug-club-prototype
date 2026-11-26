import 'map_style_cache.dart';
import 'app_settings.dart';
import 'i18n.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vector;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import 'api.dart';
import 'ui.dart';
import 'member.dart' show VenuePage;

class VenueMap extends StatefulWidget {
  final Api api;
  const VenueMap({super.key, required this.api});
  @override
  State<VenueMap> createState() => _VenueMapState();
}

class _SavedMapView {
  final LatLng center;
  final double zoom;
  final LatLng? position;
  final DateTime until;
  _SavedMapView(this.center, this.zoom, this.position)
    : until = DateTime.now().add(const Duration(minutes: 10));
}

class _VenueMapState extends State<VenueMap> {
  static final _views = <String, _SavedMapView>{};
  _SavedMapView? savedView;
  String get viewKey => '${widget.api.base}|${widget.api.user?['id']}';
  void saveView() {
    if (!ready) return;
    _views.remove(viewKey);
    _views[viewKey] = _SavedMapView(
      map.camera.center,
      map.camera.zoom,
      position,
    );
    while (_views.length > 8) {
      _views.remove(_views.keys.first);
    }
  }

  final map = MapController();
  List<Json> venues = [];
  String? error, locationMessage;
  bool ready = false, locating = false;
  LatLng? position;
  Timer? debounce;
  int generation = 0;
  vector.Style? vectorStyle;
  String attribution =
      '© OpenStreetMap contributors · OpenMapTiles · OpenFreeMap';
  bool loadingStyle = true, tilesLoaded = false;
  String? styleError, tileError;
  int styleGeneration = 0, layerRevision = 0;
  Timer? tileTimeout;
  StreamSubscription<vector.MapTileEvent>? tileSubscription;
  String? loadingBounds, lastBounds;
  DateTime? lastLoaded;
  bool queuedLoad = false;

  Future<void> loadStyle({bool refresh = false}) async {
    final current = ++styleGeneration;
    setState(() {
      loadingStyle = true;
      styleError = null;
      tileError = null;
    });
    try {
      final style = await MapStyleCache.shared.read(
        '${widget.api.base}/api/map-style?lang=${appLanguage.code}',
        refresh: refresh,
      );
      if (!mounted || current != styleGeneration) return;
      setState(() {
        vectorStyle = style;
        loadingStyle = false;
        tilesLoaded = false;
        layerRevision++;
      });
      startTileTimeout();
    } catch (_) {
      if (mounted && current == styleGeneration) {
        setState(() {
          loadingStyle = false;
          styleError = 'Карта временно недоступна. Повторите попытку';
        });
      }
    }
  }

  void startTileTimeout() {
    tileTimeout?.cancel();
    tileTimeout = Timer(const Duration(seconds: 18), () {
      if (mounted && !tilesLoaded) {
        setState(
          () => tileError =
              'Не удалось загрузить карту. Проверьте интернет и повторите попытку',
        );
      }
    });
  }

  void retryMap() {
    if (loadingStyle) return;
    vector.MapNetworkCache.shared.clearFailures();
    if (vectorStyle == null || styleError != null) {
      loadStyle(refresh: true);
    } else {
      setState(() {
        tileError = null;
        tilesLoaded = false;
        layerRevision++;
      });
      startTileTimeout();
    }
    load(force: true);
  }

  @override
  void initState() {
    super.initState();
    final previous = _views[viewKey];
    if (previous != null && previous.until.isAfter(DateTime.now())) {
      savedView = previous;
      position = previous.position;
    }
    appLanguage.addListener(loadStyle);
    tileSubscription = vector.MapNetworkCache.shared.events.listen((event) {
      if (!mounted || vectorStyle == null) return;
      if (event.loaded) {
        tileTimeout?.cancel();
        if (!tilesLoaded || tileError != null) {
          setState(() {
            tilesLoaded = true;
            tileError = null;
          });
        }
      } else {
        setState(
          () => tileError = event.statusCode == 429
              ? 'Сервис карты занят. Подождите немного и повторите попытку'
              : 'Часть карты не загрузилась. Проверьте интернет и повторите попытку',
        );
      }
    });
    loadStyle();
    init();
  }

  @override
  void dispose() {
    saveView();
    appLanguage.removeListener(loadStyle);
    debounce?.cancel();
    tileTimeout?.cancel();
    tileSubscription?.cancel();
    map.dispose();
    super.dispose();
  }

  Future<void> init() async {
    if (mounted && savedView == null) await locate();
  }

  Future<void> locate() async {
    if (!mounted || locating) {
      return;
    }
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw ApiError(0, 'Включите геолокацию или перемещайте карту вручную');
      }
      var permission = await Geolocator.checkPermission();
      if (!mounted) {
        return;
      }
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw ApiError(
          0,
          'Доступ к местоположению закрыт. Можно выбрать заведение на карте вручную',
        );
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        position = LatLng(p.latitude, p.longitude);
        locationMessage = null;
      });
      if (ready) map.move(position!, 14);
    } catch (e) {
      if (mounted) {
        setState(
          () => locationMessage = e is ApiError
              ? e.message
              : 'Не удалось определить местоположение. Карта доступна для ручного поиска',
        );
      }
    } finally {
      if (mounted) {
        setState(() => locating = false);
        if (ready) load();
      }
    }
  }

  Future<void> load({bool force = false}) async {
    if (!mounted || !ready) return;
    final b = map.camera.visibleBounds;
    final bounds =
        '${b.west.toStringAsFixed(4)}|${b.south.toStringAsFixed(4)}|${b.east.toStringAsFixed(4)}|${b.north.toStringAsFixed(4)}|${position?.latitude.toStringAsFixed(4)}|${position?.longitude.toStringAsFixed(4)}';
    if (loadingBounds != null) {
      queuedLoad = queuedLoad || bounds != loadingBounds;
      return;
    }
    if (!force &&
        bounds == lastBounds &&
        lastLoaded != null &&
        DateTime.now().difference(lastLoaded!) < const Duration(seconds: 30)) {
      return;
    }
    loadingBounds = bounds;
    final current = ++generation;
    try {
      final data = await widget.api.get(
        '/catalog?limit=500&west=${b.west}&south=${b.south}&east=${b.east}&north=${b.north}${position == null ? '' : '&latitude=${position!.latitude}&longitude=${position!.longitude}'}',
      );
      if (mounted && current == generation) {
        setState(() {
          venues = rows(data['items']);
          lastBounds = bounds;
          lastLoaded = DateTime.now();
          error = null;
          if (data['total'] > 500) {
            error = 'На карте показаны первые 500 заведений. Увеличьте масштаб';
          }
        });
      }
    } catch (e) {
      if (mounted && current == generation) setState(() => error = '$e');
    } finally {
      loadingBounds = null;
      if (queuedLoad && mounted) {
        queuedLoad = false;
        unawaited(load());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(child: AppText('На карте', style: titleStyle(30))),
              IconButton(
                tooltip: tx('Обновить карту'),
                onPressed: loadingStyle ? null : retryMap,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: tx('Моё местоположение'),
                onPressed: locating ? null : locate,
                icon: locating
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.my_location, color: purple),
              ),
            ],
          ),
        ),
        if (locationMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: AppText(
              locationMessage!,
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: AppText(error!, style: const TextStyle(fontSize: 12)),
          ),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: map,
                options: MapOptions(
                  initialCenter:
                      savedView?.center ??
                      position ??
                      const LatLng(52.287, 76.967),
                  initialZoom: savedView?.zoom ?? 13,
                  minZoom: 3,
                  maxZoom: 18,
                  onMapReady: () {
                    ready = true;
                    if (position != null && savedView == null) {
                      map.move(position!, 14);
                    }
                    load();
                  },
                  onPositionChanged: (_, gesture) {
                    saveView();
                    debounce?.cancel();
                    debounce = Timer(
                      const Duration(milliseconds: 650),
                      () => load(),
                    );
                  },
                ),
                children: [
                  if (vectorStyle != null)
                    vector.VectorTileLayer(
                      key: ValueKey('vector-map-$layerRevision'),
                      theme: vectorStyle!.theme,
                      tileProviders: vectorStyle!.providers,
                      sprites: vectorStyle!.sprites,
                    ),
                  MarkerLayer(
                    markers: [
                      if (position != null)
                        Marker(
                          point: position!,
                          width: 28,
                          height: 28,
                          child: Semantics(
                            label: tx('Вы здесь'),
                            child: Icon(
                              Icons.my_location_rounded,
                              color: Colors.blue,
                              size: 28,
                            ),
                          ),
                        ),
                      ...venues
                          .where((v) => v['data']['latitude'] != null)
                          .map(
                            (v) => Marker(
                              point: LatLng(
                                (v['data']['latitude'] as num).toDouble(),
                                (v['data']['longitude'] as num).toDouble(),
                              ),
                              width: 48,
                              height: 48,
                              child: Semantics(
                                button: true,
                                label: tx(s(v['data']['name'])),
                                child: Tooltip(
                                  message: s(v['data']['name']),
                                  child: Material(
                                    color: purple,
                                    shape: const CircleBorder(),
                                    elevation: 4,
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () => route(
                                        context,
                                        VenuePage(
                                          api: widget.api,
                                          id: s(v['id']),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.storefront_outlined,
                                        color: Colors.white,
                                        size: 25,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                  MapCredits(attribution: attribution),
                ],
              ),
              if (loadingStyle || styleError != null || !tilesLoaded)
                Positioned.fill(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Panel(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (styleError == null && tileError == null) ...[
                              const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const AppText('Загружаем карту…'),
                            ] else ...[
                              Icon(Icons.map_outlined, color: purple, size: 34),
                              const SizedBox(height: 10),
                              AppText(
                                styleError ?? tileError!,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                key: const ValueKey('retry-map'),
                                onPressed: retryMap,
                                icon: const Icon(Icons.refresh),
                                label: const AppText('Повторить'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (tilesLoaded && tileError != null)
                Positioned(
                  left: 12,
                  right: 12,
                  top: 10,
                  child: Panel(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Expanded(
                          child: AppText(
                            tileError!,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        TextButton(
                          onPressed: retryMap,
                          child: const AppText('Повторить'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ScannerPage extends StatefulWidget {
  final Api api;
  const ScannerPage({super.key, required this.api});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  final controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool busy = false, paused = false;
  String? error, lastCode, requestId;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy && !paused) {
      controller.start().catchError((Object _) {});
    } else {
      controller.stop().catchError((Object _) {});
    }
  }

  Future<void> scan(String raw) async {
    if (busy) return;
    if (!RegExp(
      r'^QAZAQMETAL:1:[a-f0-9-]{36}:[A-Za-z0-9_-]{32,64}$',
    ).hasMatch(raw)) {
      setState(
        () =>
            error = 'QR не относится к заведению QMET+. Ссылки не открываются',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      paused = true;
    });
    try {
      await controller.stop();
    } catch (_) {}
    if (lastCode != raw) {
      lastCode = raw;
      requestId = const Uuid().v4();
    }
    try {
      final data = await widget.api.post('/scan', {
        'code': raw,
        'request_id': requestId,
      });
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: Color(0xffc2edb1),
                  child: Icon(
                    Icons.check_rounded,
                    size: 38,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 18),
                AppText(
                  'Скидка получена',
                  textAlign: TextAlign.center,
                  style: titleStyle(30),
                ),
                const SizedBox(height: 10),
                AppText(s(data['venue_name']), textAlign: TextAlign.center),
                const SizedBox(height: 18),
                Panel(
                  color: lavender,
                  child: AppText(
                    '−${data["percent"]}%',
                    textAlign: TextAlign.center,
                    style: titleStyle(44).copyWith(color: purple),
                  ),
                ),
                const SizedBox(height: 14),
                AppText(s(data['offer_name']), textAlign: TextAlign.center),
                if (data['replay'] == true)
                  const AppText(
                    'Эта операция уже сохранена. Повтор не увеличивает статистику.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                const SizedBox(height: 18),
                ActionButton('Понятно', onPressed: () => Navigator.pop(c)),
                const SizedBox(height: 8),
                SelectableText(
                  tx('Операция ${data["id"]}'),
                  style: const TextStyle(fontSize: 10, color: muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
      lastCode = null;
      requestId = null;
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> retry() async {
    setState(() {
      paused = false;
      error = null;
    });
    try {
      await controller.start();
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Камера недоступна. Разрешите доступ в настройках устройства',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return ColoredBox(
      color: const Color(0xff211b29),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppText(
              'Сканирование QR',
              style: titleStyle(29).copyWith(color: Colors.white),
            ),
            const SizedBox(height: 10),
            const AppText(
              'Наведите камеру на QR-код заведения. Партнёр определится автоматически.',
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
            const SizedBox(height: 24),
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: controller,
                      onDetect: (capture) {
                        if (paused || busy) return;
                        for (final b in capture.barcodes) {
                          if (b.rawValue != null) {
                            scan(b.rawValue!);
                            break;
                          }
                        }
                      },
                      errorBuilder: (context, error) => ColoredBox(
                        color: const Color(0xff362940),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.no_photography_outlined,
                                  size: 48,
                                  color: lavender,
                                ),
                                const SizedBox(height: 14),
                                const AppText(
                                  'Камера недоступна. Разрешите доступ к камере в настройках телефона или браузера.',
                                  style: TextStyle(color: Colors.white),
                                  textAlign: TextAlign.center,
                                ),
                                TextButton(
                                  onPressed: () async {
                                    try {
                                      final opened =
                                          await Geolocator.openAppSettings();
                                      if (!opened && context.mounted) {
                                        toast(
                                          context,
                                          'Разрешите камеру в настройках устройства или сайта',
                                        );
                                      }
                                    } catch (_) {
                                      if (context.mounted) {
                                        toast(
                                          context,
                                          'В браузере разрешите камеру через значок настроек рядом с адресом сайта',
                                        );
                                      }
                                    }
                                  },
                                  child: const AppText('Открыть настройки'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xffb771f1),
                            width: 4,
                          ),
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                    ),
                    if (busy) const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (error != null) Panel(color: lavender, child: AppText(error!)),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              children: [
                IconButton(
                  tooltip: tx('Переключить камеру'),
                  onPressed: () async {
                    try {
                      await controller.switchCamera();
                    } catch (_) {
                      if (context.mounted) {
                        toast(context, 'Камера недоступна');
                      }
                    }
                  },
                  icon: const Icon(
                    Icons.cameraswitch_outlined,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            if (paused || error != null)
              ActionButton(
                busy ? 'Проверяем…' : 'Сканировать ещё / повторить',
                onPressed: busy ? null : retry,
                icon: Icons.qr_code_scanner_rounded,
              ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}
