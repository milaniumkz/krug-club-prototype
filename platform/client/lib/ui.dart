import 'i18n.dart';
import 'app_settings.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'package:url_launcher/url_launcher.dart';

const ink = Color(0xff211b29),
    muted = Color(0xff746a79),
    paleBorder = Color(0xffe6dfe6);
Color get purple => appSettings.accent;
Color get paper => appSettings.background;
Color get lavender => purple == const Color(0xff6e2ebd)
    ? const Color(0xffede0f7)
    : Color.alphaBlend(purple.withValues(alpha: .14), Colors.white);
Color get deepPurple => purple == const Color(0xff6e2ebd)
    ? const Color(0xff25182f)
    : HSLColor.fromColor(
        purple,
      ).withSaturation(.32).withLightness(.14).toColor();
TextStyle titleStyle([double size = 28]) => TextStyle(
  fontFamily: 'PTSerif',
  fontSize: size,
  fontWeight: FontWeight.bold,
  color: ink,
);

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Row(
      children: [
        if (appSettings.logoUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              appSettings.logoUrl,
              width: 38,
              height: 38,
              cacheWidth: 76,
              cacheHeight: 76,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Image.asset(
                'assets/qmetplus_icon.png',
                width: 38,
                height: 38,
                fit: BoxFit.contain,
              ),
            ),
          )
        else
          Image.asset(
            'assets/qmetplus_icon.png',
            width: 38,
            height: 38,
            cacheWidth: 76,
            cacheHeight: 76,
            fit: BoxFit.contain,
          ),
        const SizedBox(width: 10),
        const Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AppText(
              'QMET+',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
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
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Container(
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
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
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
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: onPressed == null
              ? [const Color(0xffb7a7c6), const Color(0xffa99ab8)]
              : [const Color(0xff874acb), const Color(0xff5522a0)],
        ),
        boxShadow: onPressed == null
            ? null
            : const [
                BoxShadow(
                  color: Color(0x246e2ebd),
                  blurRadius: 16,
                  offset: Offset(0, 7),
                ),
              ],
      ),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon ?? Icons.arrow_forward_rounded, size: 21),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: AppText(text, textAlign: TextAlign.center),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white70,
          shadowColor: Colors.transparent,
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

void toast(BuildContext context, Object text) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: AppText('$text')));
Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: AppText(title),
        content: AppText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const AppText('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const AppText('Продолжить'),
          ),
        ],
      ),
    ) ??
    false;
Future<void> route(BuildContext context, Widget page) =>
    Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));

class LoadView extends StatefulWidget {
  final Future<dynamic> Function() load;
  final Widget Function(dynamic, Future<void> Function()) builder;
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

  Future<void> refresh() async {
    if (!mounted) return;
    final next = widget.load();
    setState(() => future = next);
    try {
      await next;
    } catch (_) {
      /* FutureBuilder displays the error and retry. */
    }
  }

  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return FutureBuilder<dynamic>(
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
                  AppText('${snapshot.error}', textAlign: TextAlign.center),
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
}

class Empty extends StatelessWidget {
  final String text;
  const Empty(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 40, color: muted),
          const SizedBox(height: 14),
          AppText(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted),
          ),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: path.isEmpty
          ? Container(
              height: height,
              color: lavender,
              child: Center(
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
}

class MapCredits extends StatelessWidget {
  final String attribution;
  const MapCredits({
    super.key,
    this.attribution = '© OpenStreetMap contributors · Tiles OSM France',
  });
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Align(
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
                child: AppText(
                  attribution.replaceAll(' · ', '\n'),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 10, color: ink),
                ),
              ),
              if (attribution.contains('OSM France'))
                InkWell(
                  onTap: () =>
                      launchUrl(Uri.parse('https://www.openstreetmap.fr/')),
                  child: AppText(
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
}

bool membershipExpired(Json user) {
  if (user['can_redeem'] is bool) return user['can_redeem'] != true;
  final until = DateTime.tryParse(s(user['member_until']));
  return until != null && until.toUtc().isBefore(DateTime.now().toUtc());
}

String displayMoment(dynamic raw, {bool dateOnly = false}) {
  final value = DateTime.tryParse(s(raw));
  if (value == null) return s(raw);
  final kz = value.toUtc().add(const Duration(hours: 5));
  String pad(int n) => n.toString().padLeft(2, '0');
  final date = '${pad(kz.day)}.${pad(kz.month)}.${kz.year}';
  return dateOnly ? date : '$date · ${pad(kz.hour)}:${pad(kz.minute)}';
}

String displayDistance(dynamic km) {
  if (km is! num) return '';
  if (km < 1) return '${(km * 1000).round()} м';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} км';
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeading(this.title, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return Row(
      children: [
        Expanded(child: AppText(title, style: titleStyle(25))),
        if (action != null)
          TextButton(onPressed: onAction, child: AppText(action!)),
      ],
    );
  }
}

class MembershipStatus extends StatelessWidget {
  final Json user;
  const MembershipStatus({super.key, required this.user});
  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    final expired = membershipExpired(user);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: expired ? const Color(0xffffeadb) : const Color(0xffe3efd6),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Icon(
            expired ? Icons.info_outline_rounded : Icons.check_circle_rounded,
            color: expired ? const Color(0xff9e541d) : const Color(0xff36a448),
            size: 22,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: AppText(
              expired ? 'Членство требует продления' : 'Членство активно',
              style: const TextStyle(
                color: ink,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          if (!expired && user['member_until'] != null)
            AppText(
              'до ${displayMoment(user['member_until'], dateOnly: true)}',
              style: const TextStyle(fontSize: 10, color: ink),
            ),
        ],
      ),
    );
  }
}
