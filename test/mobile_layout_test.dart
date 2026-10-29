import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_calendar/app_controller.dart';
import 'package:warm_calendar/domain/calendar_service.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/platform/notification_api.dart';
import 'package:warm_calendar/ui/shell.dart';
import 'package:warm_calendar/ui/event_form.dart';
import 'prototype_test.dart' show MemoryRepository;
import 'recurrence_test.dart' show testApp;

void main() {
  for (final scenario in [
    (360.0, 1.0),
    (390.0, 1.0),
    (390.0, 1.6),
    (1280.0, 1.0),
  ]) {
    testWidgets('导航、七列周视图、平铺设置与表单 ${scenario.$1}/${scenario.$2}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(scenario.$1, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = MemoryRepository();
      final handler = FlutterError.onError!;
      FlutterError.onError = (details) {
        debugPrint(details.toString());
        handler(details);
      };
      addTearDown(() => FlutterError.onError = handler);
      final now = DateTime.now();
      repo.rows['mobile'] = ScheduleEvent(
        id: 'mobile',
        title: '手机布局验证日程',
        start: now.add(const Duration(hours: 1)),
        end: now.add(const Duration(hours: 2)),
        updatedAt: now,
      );
      final controller = AppController(
        repository: repo,
        calendar: CalendarService(),
        notifications: NotificationBackend(),
      );
      await tester.runAsync(() => controller.initialize(startTimer: false));
      await tester.pumpWidget(testApp(AppShell(controller: controller)));
      await tester.pumpAndSettle();
      final phone = scenario.$1 < 600;
      expect(find.byType(NavigationBar), phone ? findsOneWidget : findsNothing);
      if (phone) {
        expect(
          tester.getTopLeft(find.byType(NavigationBar)).dy,
          greaterThan(700),
        );
      }
      Future<void> navigate(String label) async {
        final target = phone
            ? find.descendant(
                of: find.byType(NavigationBar),
                matching: find.text(label),
              )
            : find.text(label).first;
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await navigate('日历');
      await tester.tap(find.text('周'));
      await tester.pumpAndSettle();
      if (phone) {
        final week = tester.widget<ListView>(
          find.byKey(const ValueKey('week-days-scroll')),
        );
        expect(week.itemExtent! * 7, closeTo(scenario.$1 - 24 - 40, 4));
        await tester.tap(find.byTooltip('放大时间轴'));
        await tester.pumpAndSettle();
        expect(find.text('分度 15分钟'), findsOneWidget);
      }
      await navigate('日程');
      expect(find.text('手机布局验证日程'), findsWidgets);
      await navigate('链接');
      await navigate('设置');
      if (phone) {
        expect(find.byKey(const ValueKey('settings-category')), findsNothing);
        expect(find.text('启用提醒'), findsOneWidget);
        expect(find.text('周一作为每周第一天'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(testApp(EventEditor(controller: controller)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('保存日程'), findsOneWidget);
      final save = tester.getRect(find.text('保存日程'));
      expect(save.bottom, lessThan(844));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }
}
