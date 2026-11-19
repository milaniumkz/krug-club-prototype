import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qazaqmetal/api.dart';
import 'package:qazaqmetal/main.dart';
import 'package:qazaqmetal/workspace.dart';

void main() {
  for (final role in ['admin', 'partner']) {
    for (final width in [320.0, 390.0]) {
      testWidgets('$role workspace, tabs and venue calendar fit $width', (
        tester,
      ) async {
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final venue = {
          'id': 'venue',
          'kind': 'venue',
          'partner_id': 'partner',
          'enabled': true,
          'deleted': false,
          'data': {
            'name': 'Тестовое заведение с длинным названием',
            'description': 'Описание',
            'address': 'Адрес',
            'category': 'Еда и напитки',
            'percent': 15,
            'terms': 'Условия',
          },
        };
        final api =
            Api(
                client: MockClient((r) async {
                  final Object body = switch (r.url.path) {
                    '/api/workspace/stats' => {
                      'total_uses': 1,
                      'unique_members': 1,
                      'venues': [],
                      'days': {},
                      'operations': [],
                    },
                    '/api/workspace/resources' => [venue],
                    '/api/workspace/options' => {
                      'organizations': [],
                      'partners': [
                        {'id': 'partner', 'name': 'Демо партнёр'},
                      ],
                    },
                    '/api/admin/accounts' => {'items': [], 'total': 0},
                    _ => [],
                  };
                  return http.Response(
                    jsonEncode(body),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  );
                }),
              )
              ..loading = false
              ..user = {
                'id': 'staff',
                'role': role,
                'name': 'Тестовый сотрудник',
                'must_change_password': false,
              };
        await tester.pumpWidget(QazaqMetalApp(api: api));
        await tester.pumpAndSettle();
        expect(find.text('Скидки и акции'), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);
        for (var i = 0; i < 5; i++) {
          await tester.tap(find.byType(NavigationDestination).at(i));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.byType(NavigationDestination).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Добавить').first);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('date-starts_on')),
          300,
          scrollable: find
              .descendant(
                of: find.byType(ResourceEditor),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('date-starts_on')),
        );
        await tester.tap(find.byKey(const ValueKey('date-starts_on')));
        await tester.pumpAndSettle();
        expect(find.byType(CalendarDatePicker), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        api.dispose();
      });
    }
  }
}
