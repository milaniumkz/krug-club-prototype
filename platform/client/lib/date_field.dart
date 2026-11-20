import 'app_settings.dart';
import 'package:flutter/material.dart';
import 'i18n.dart';

String displayDate(dynamic raw) {
  final date = raw is DateTime ? raw : DateTime.tryParse('$raw');
  if (date == null) return raw?.toString() ?? '';
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(date.day)}.${pad(date.month)}.${date.year.toString().padLeft(4, '0')}';
}

/// The stored value remains ISO for the API; users choose it using a calendar.
class CalendarDateField extends StatelessWidget {
  final TextEditingController controller;
  final TextEditingController? minimum, maximum;
  final String label;
  const CalendarDateField({
    super.key,
    required this.controller,
    required this.label,
    this.minimum,
    this.maximum,
  });

  Future<void> pick(BuildContext context) async {
    final lower = DateTime.tryParse(minimum?.text ?? '') ?? DateTime(1900);
    final upper =
        DateTime.tryParse(maximum?.text ?? '') ?? DateTime(2200, 12, 31);
    var initial =
        DateTime.tryParse(controller.text) ??
        DateUtils.dateOnly(DateTime.now());
    if (initial.isBefore(lower)) initial = lower;
    if (initial.isAfter(upper)) initial = upper;
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: lower,
      lastDate: upper,
      helpText: tx(label),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (value != null) {
      controller.text =
          '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    SettingsScope.watch(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextFormField(
        key: ValueKey(value.text),
        initialValue: value.text.isEmpty ? '' : displayDate(value.text),
        enableInteractiveSelection: false,
        readOnly: true,
        showCursor: false,
        onTap: () => pick(context),
        decoration: InputDecoration(
          labelText: tx(label),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value.text.isNotEmpty)
                IconButton(
                  tooltip: tx('Очистить дату'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: controller.clear,
                ),
              IconButton(
                tooltip: tx('Выбрать дату'),
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: () => pick(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
