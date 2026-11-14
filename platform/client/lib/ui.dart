import 'package:flutter/material.dart';
import 'api.dart';
import 'package:url_launcher/url_launcher.dart';

const ink = Color(0xff211b29),
    purple = Color(0xff6e2ebd),
    paper = Color(0xfff8f3ef),
    lavender = Color(0xffede0f7),
    muted = Color(0xff746a79);
TextStyle titleStyle([double size = 28]) => TextStyle(
  fontFamily: 'PTSerif',
  fontSize: size,
  fontWeight: FontWeight.bold,
  color: ink,
);

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipOval(child: Image.asset('assets/logo.png', width: 38, height: 38)),
      const SizedBox(width: 10),
      const Expanded(
        child: Text(
          'QAZAQMETAL\nKÁSIPODAǴY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
    ],
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? Colors.white.withValues(alpha: .85),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xffe6dfe6)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x08000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

class ActionButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  const ActionButton(
    this.text, {
    super.key,
    required this.onPressed,
    this.icon,
  });
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon ?? Icons.arrow_forward_rounded, size: 20),
    label: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(text),
    ),
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
    ),
  );
}

void toast(BuildContext context, Object text) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text('$text')));
Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    ) ??
    false;
Future<void> route(BuildContext context, Widget page) =>
    Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));

class LoadView extends StatefulWidget {
  final Future<dynamic> Function() load;
  final Widget Function(dynamic, VoidCallback) builder;
  const LoadView({super.key, required this.load, required this.builder});
  @override
  State<LoadView> createState() => _LoadViewState();
}

class _LoadViewState extends State<LoadView> {
  late Future<dynamic> future;
  @override
  void initState() {
    super.initState();
    future = widget.load();
  }

  void refresh() {
    if (mounted) {
      setState(() => future = widget.load());
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, size: 40),
                const SizedBox(height: 16),
                Text('${snapshot.error}', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ActionButton('Повторить', onPressed: refresh),
              ],
            ),
          ),
        );
      }
      return widget.builder(snapshot.data, refresh);
    },
  );
}

class Empty extends StatelessWidget {
  final String text;
  const Empty(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.inbox_outlined, size: 40, color: muted),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
      ],
    ),
  );
}

class RemotePhoto extends StatelessWidget {
  final Api api;
  final String path;
  final double height;
  const RemotePhoto({
    super.key,
    required this.api,
    required this.path,
    this.height = 160,
  });
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(17),
    child: path.isEmpty
        ? Container(
            height: height,
            color: lavender,
            child: const Center(
              child: Icon(Icons.storefront_outlined, size: 42, color: purple),
            ),
          )
        : Image.network(
            '${api.base}$path',
            headers: api.headers,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, e, st) => Container(
              height: height,
              color: lavender,
              child: const Icon(Icons.image_not_supported_outlined),
            ),
          ),
  );
}

class MapCredits extends StatelessWidget {
  final String attribution;
  const MapCredits({
    super.key,
    this.attribution = '© OpenStreetMap contributors · Tiles OSM France',
  });
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomRight,
    child: ColoredBox(
      color: Colors.white.withValues(alpha: .92),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            InkWell(
              onTap: () => launchUrl(
                Uri.parse('https://www.openstreetmap.org/copyright'),
              ),
              child: Text(
                attribution.replaceAll(' · ', '\n'),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 10, color: ink),
              ),
            ),
            if (attribution.contains('OSM France'))
              InkWell(
                onTap: () =>
                    launchUrl(Uri.parse('https://www.openstreetmap.fr/')),
                child: const Text(
                  'openstreetmap.fr',
                  style: TextStyle(fontSize: 10, color: purple),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
