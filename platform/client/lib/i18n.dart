import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'translations.dart';

class AppLanguage extends ChangeNotifier {
  String code = 'ru';
  Future<void> load() async {
    try {
      code = await const FlutterSecureStorage().read(key: 'ui-language') == 'kk'
          ? 'kk'
          : 'ru';
    } catch (_) {}
  }

  Future<void> set(String value) async {
    if (!['ru', 'kk'].contains(value)) return;
    code = value;
    notifyListeners();
    try {
      await const FlutterSecureStorage().write(key: 'ui-language', value: code);
    } catch (_) {}
  }
}

final appLanguage = AppLanguage();
final _patterns = <MapEntry<RegExp, String>>[];
String tx(String? value) {
  if (value == null) return '';
  value = value
      .replaceAll('QAZAQMETAL KÁSIPODAǴY', 'QMET+')
      .replaceAll('QAZAQMETAL', 'QMET+')
      .replaceAll('КазахМетал', 'QMET+');
  if (appLanguage.code == 'ru') return value;
  final exact = kkTranslations[value];
  if (exact != null) return exact;
  if (_patterns.isEmpty) {
    for (final entry in kkTranslations.entries) {
      if (!entry.key.contains(RegExp(r'\{\d+\}'))) continue;
      final parts = entry.key.split(RegExp(r'\{\d+\}'));
      _patterns.add(
        MapEntry(
          RegExp('^${parts.map(RegExp.escape).join('(.*?)')}\$', dotAll: true),
          entry.value,
        ),
      );
    }
  }
  for (final entry in _patterns) {
    final match = entry.key.firstMatch(value);
    if (match == null) continue;
    var result = entry.value;
    for (var i = 1; i <= match.groupCount; i++) {
      result = result.replaceAll('{${i - 1}}', tx(match.group(i) ?? ''));
    }
    return result;
  }
  return value;
}

class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appLanguage,
    builder: (context, _) => SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'ru', label: Text('РУС')),
        ButtonSegment(value: 'kk', label: Text('ҚАЗ')),
      ],
      selected: {appLanguage.code},
      onSelectionChanged: (value) => appLanguage.set(value.first),
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    ),
  );
}

class AppText extends Text {
  const AppText(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.semanticsIdentifier,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  });
  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final translated = tx(data);
    if (translated == data) return super.build(context);
    return Text(
      translated,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel == null ? null : tx(semanticsLabel),
      semanticsIdentifier: semanticsIdentifier,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
