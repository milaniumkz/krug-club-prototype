import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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

class _VenueMapState extends State<VenueMap> {
  final map = MapController();
  List<Json> venues = [];
  String? error, locationMessage;
  bool ready = false, locating = false;
  LatLng? position;
  Timer? debounce;
  int generation = 0;
  String attribution = '© OpenStreetMap contributors · Tiles OSM France';
  String tiles = 'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png';
  @override
  void initState() {
    super.initState();
    init();
  }

  @override
  void dispose() {
    debounce?.cancel();
    map.dispose();
    super.dispose();
  }

  Future<void> init() async {
    try {
      final meta = await widget.api.get('/meta');
      if (mounted) {
        setState(() {
          tiles = s(meta['tiles']);
          attribution = s(meta['attribution']);
        });
      }
    } catch (_) {}
    if (!mounted) {
      return;
    }
    await locate();
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

  Future<void> load() async {
    if (!ready) return;
    final current = ++generation;
    final b = map.camera.visibleBounds;
    try {
      final data = await widget.api.get(
        '/catalog?limit=500&west=${b.west}&south=${b.south}&east=${b.east}&north=${b.north}${position == null ? '' : '&latitude=${position!.latitude}&longitude=${position!.longitude}'}',
      );
      if (mounted && current == generation) {
        setState(() {
          venues = rows(data['items']);
          error = null;
          if (data['total'] > 500) {
            error = 'На карте показаны первые 500 заведений. Увеличьте масштаб';
          }
        });
      }
    } catch (e) {
      if (mounted && current == generation) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Row(
          children: [
            Expanded(child: Text('На карте', style: titleStyle(30))),
            IconButton(
              tooltip: 'Обновить заведения',
              onPressed: load,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Моё местоположение',
              onPressed: locating ? null : locate,
              icon: locating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, color: purple),
            ),
          ],
        ),
      ),
      if (locationMessage != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Text(
            locationMessage!,
            style: const TextStyle(fontSize: 12, color: muted),
          ),
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(error!, style: const TextStyle(fontSize: 12)),
        ),
      Expanded(
        child: FlutterMap(
          mapController: map,
          options: MapOptions(
            initialCenter: position ?? const LatLng(52.287, 76.967),
            initialZoom: 13,
            minZoom: 3,
            maxZoom: 18,
            onMapReady: () {
              ready = true;
              if (position != null) map.move(position!, 14);
              load();
            },
            onPositionChanged: (_, gesture) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 500), load);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: tiles,
              userAgentPackageName: 'kz.qazaqmetal.qazaqmetal',
              maxZoom: 18,
            ),
            MarkerLayer(
              markers: [
                if (position != null)
                  Marker(
                    point: position!,
                    width: 28,
                    height: 28,
                    child: Semantics(
                      label: 'Вы здесь',
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
                          label: s(v['data']['name']),
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
                                  VenuePage(api: widget.api, id: s(v['id'])),
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
      ),
    ],
  );
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
  final manual = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    manual.dispose();
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
        () => error =
            'QR не относится к заведению QAZAQMETAL. Ссылки не открываются',
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
                Text(
                  'Скидка получена',
                  textAlign: TextAlign.center,
                  style: titleStyle(30),
                ),
                const SizedBox(height: 10),
                Text(s(data['venue_name']), textAlign: TextAlign.center),
                const SizedBox(height: 18),
                Panel(
                  color: lavender,
                  child: Text(
                    '−${data["percent"]}%',
                    textAlign: TextAlign.center,
                    style: titleStyle(44).copyWith(color: purple),
                  ),
                ),
                const SizedBox(height: 14),
                Text(s(data['offer_name']), textAlign: TextAlign.center),
                if (data['replay'] == true)
                  const Text(
                    'Эта операция уже сохранена. Повтор не увеличивает статистику.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                const SizedBox(height: 18),
                ActionButton('Понятно', onPressed: () => Navigator.pop(c)),
                const SizedBox(height: 8),
                SelectableText(
                  'Операция ${data["id"]}',
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
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xff211b29),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Сканирование QR',
            style: titleStyle(29).copyWith(color: Colors.white),
          ),
          const SizedBox(height: 10),
          const Text(
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
                              const Icon(
                                Icons.no_photography_outlined,
                                size: 48,
                                color: lavender,
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Камера недоступна. Разрешите доступ к камере в настройках телефона или браузера.',
                                style: TextStyle(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                              TextButton(
                                onPressed: Geolocator.openAppSettings,
                                child: const Text('Открыть настройки'),
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
          if (error != null) Panel(color: lavender, child: Text(error!)),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            children: [
              IconButton(
                tooltip: 'Фонарик',
                onPressed: () async {
                  try {
                    await controller.toggleTorch();
                  } catch (_) {
                    if (context.mounted) {
                      toast(context, 'Фонарик недоступен');
                    }
                  }
                },
                icon: const Icon(
                  Icons.flashlight_on_outlined,
                  color: Colors.white,
                ),
              ),
              IconButton(
                tooltip: 'Переключить камеру',
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
          ExpansionTile(
            collapsedTextColor: Colors.white,
            textColor: Colors.white,
            iconColor: Colors.white,
            collapsedIconColor: Colors.white,
            title: const Text(
              'Ввести QR-код вручную',
              style: TextStyle(fontSize: 13),
            ),
            children: [
              const Text(
                'Если камера недоступна, вставьте текст выданного QR-кода. Это ручной ввод, не сканирование.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: manual,
                maxLength: 256,
                decoration: const InputDecoration(labelText: 'Текст QR-кода'),
                style: const TextStyle(color: ink),
              ),
              ActionButton(
                'Применить код',
                onPressed: busy ? null : () => scan(manual.text.trim()),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
