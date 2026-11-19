import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qazaqmetal/date_field.dart';

void main() {
  testWidgets('Calendar opens on tap, constrains dates, saves ISO and clears', (
    tester,
  ) async {
    final value = TextEditingController(text: '2027-01-15');
    final lower = TextEditingController(text: '2027-01-10');
    final upper = TextEditingController(text: '2027-01-20');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarDateField(
            controller: value,
            minimum: lower,
            maximum: upper,
            label: 'Дата окончания',
          ),
        ),
      ),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    expect(find.text('15.01.2027'), findsOneWidget);
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(picker.firstDate, DateTime(2027, 1, 10));
    expect(picker.lastDate, DateTime(2027, 1, 20));
    await tester.tap(find.text('16').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(value.text, '2027-01-16');
    expect(find.text('16.01.2027'), findsOneWidget);
    await tester.tap(find.byTooltip('Очистить дату'));
    await tester.pump();
    expect(value.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
    value.dispose();
    lower.dispose();
    upper.dispose();
  });
}
