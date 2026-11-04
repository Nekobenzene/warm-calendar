import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_calendar/app_controller.dart';
import 'package:warm_calendar/domain/calendar_service.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/ui/calendar_page.dart';
import 'package:warm_calendar/ui/calendar_blocks.dart';
import 'package:warm_calendar/ui/event_form.dart';
import 'package:warm_calendar/ui/settings_page.dart';
import 'package:warm_calendar/ui/shell.dart';
import 'prototype_test.dart' show MemoryRepository;
import 'recurrence_test.dart' show testApp;

Future<AppController> mountCalendar(
  WidgetTester tester, {
  bool phone = false,
  bool shell = false,
}) async {
  tester.view.physicalSize = Size(phone ? 390 : 1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = AppController(
    repository: MemoryRepository(),
    calendar: CalendarService(),
  );
  await tester.runAsync(() => c.initialize(startTimer: false));
  c.now = DateTime(2026, 1, 1, 8);
  await c.saveEvent(
    ScheduleEvent(
      id: 'one',
      title: '边界调整',
      notes: '查看详细备注',
      start: DateTime(2026, 1, 1, 9),
      end: DateTime(2026, 1, 1, 11),
      updatedAt: c.now,
    ),
  );
  await tester.pumpWidget(
    testApp(
      SingleChildScrollView(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => CalendarPage(
            controller: c,
            selectedDate: DateTime(2026, 1, 1),
            onSelect: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('周'));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  return c;
}

Finder get block => find.byKey(const ValueKey('interaction-one-2026-01-01'));
CalendarEventInteraction interaction(WidgetTester tester) =>
    tester.widget<CalendarEventInteraction>(block);

void main() {
  testWidgets('手机选中详情位于底栏上方，锁定后详情关闭', (tester) async {
    tester.view.physicalSize=const Size(390,844); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final c=AppController(repository:MemoryRepository(),calendar:CalendarService());
    await tester.runAsync(()=>c.initialize(startTimer:false));
    final today=dayOnly(DateTime.now()); c.now=today.add(const Duration(hours:8));
    await c.saveEvent(ScheduleEvent(id:'details',title:'详情标题',notes:'会议备注',start:today.add(const Duration(hours:9)),end:today.add(const Duration(hours:10)),updatedAt:c.now));
    await tester.pumpWidget(testApp(AppShell(controller:c))); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of:find.byType(NavigationBar),matching:find.text('日历'))); await tester.pumpAndSettle();
    await tester.tap(find.text('周')); await tester.pumpAndSettle();
    final event=find.byKey(ValueKey('interaction-details-${dateKey(today)}'));
    await tester.tap(event); await tester.pumpAndSettle();
    final details=find.byKey(const ValueKey('mobile-calendar-details'));
    expect(details,findsOneWidget); expect(find.descendant(of: details, matching: find.text('会议备注')),findsOneWidget);
    expect(tester.getBottomLeft(details).dy,lessThanOrEqualTo(tester.getTopLeft(find.byType(NavigationBar)).dy));
    await tester.tap(find.byKey(const ValueKey('calendar-lock'))); await tester.pumpAndSettle();
    expect(details,findsNothing); expect(find.text('拖动'),findsNothing);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox()); c.dispose();
  });
  testWidgets('桌面单击选中，再点编辑；空白退出选中', (tester) async {
    await mountCalendar(tester);
    expect(find.text('日'), findsNothing);
    await tester.tap(block);
    await tester.pumpAndSettle();
    expect(interaction(tester).selected, true);
    expect(find.byType(EventEditor), findsNothing);
    await tester.tap(block);
    await tester.pumpAndSettle();
    expect(find.byType(EventEditor), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(55, 650));
    await tester.pumpAndSettle();
    expect(interaction(tester).selected, false);
  });
  testWidgets('选中后移动和上下边界调整，锁定禁选且仍可缩放', (tester) async {
    final c = await mountCalendar(tester);
    await tester.tap(block);
    await tester.pumpAndSettle();
    expect(interaction(tester).enabled, true);
    await tester.drag(block, const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(c.events.single.start, DateTime(2026, 1, 1, 10));
    expect(c.events.single.end, DateTime(2026, 1, 1, 12));
    final bottom =
        tester.getBottomLeft(block) +
        Offset(tester.getSize(block).width / 2, -3);
    final g = await tester.startGesture(bottom, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(0, 30));
    await g.up();
    await tester.pumpAndSettle();
    expect(c.events.single.end, DateTime(2026, 1, 1, 12, 30));
    final top =
        tester.getTopLeft(block) + Offset(tester.getSize(block).width / 2, 3);
    final h = await tester.startGesture(top, kind: PointerDeviceKind.mouse);
    await h.moveBy(const Offset(0, 30));
    await h.up();
    await tester.pumpAndSettle();
    expect(c.events.single.start, DateTime(2026, 1, 1, 10, 30));
    await tester.tap(find.byKey(const ValueKey('calendar-lock')));
    await tester.pumpAndSettle();
    expect(c.settings.calendarLocked, true);
    await tester.tap(block);
    await tester.pumpAndSettle();
    expect(interaction(tester).selected, false);
    final before = tester
        .getSize(find.byKey(const ValueKey('time-axis')))
        .height;
    await tester.tap(find.byTooltip('放大时间轴'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('time-axis'))).height,
      greaterThan(before),
    );
  });
  testWidgets('任意七天连续浏览，箭头与今天缓动回完整周；月视图可滑动', (tester) async {
    await mountCalendar(tester);
    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('week-days-scroll')),
    );
    final controller = list.controller!;
    final old = controller.offset;
    await tester.drag(
      find.byKey(const ValueKey('week-header-scroll')),
      Offset(-list.itemExtent! * 2, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(old + list.itemExtent!));
    final from = controller.offset;
    await tester.tap(find.byTooltip('下一周'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, isNot(from));
    final middle = controller.offset;
    await tester.pumpAndSettle();
    expect(controller.offset, isNot(middle));
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(old, .1));
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    final pager = tester
        .widget<PageView>(find.byKey(const ValueKey('month-pager')))
        .controller!;
    final month = pager.page!;
    await tester.drag(
      find.byKey(const ValueKey('month-pager')),
      const Offset(-700, 0),
    );
    await tester.pumpAndSettle();
    expect(pager.page, greaterThan(month));
  });
  testWidgets('手机七列色块、Popover拖动授权、捏合与锁定', (tester) async {
    final c = await mountCalendar(tester, phone: true);
    expect(
      find.descendant(
        of: find.byType(SegmentedButton<CalendarView>),
        matching: find.text('日'),
      ),
      findsOneWidget,
    );
    expect(find.text('边界调整'), findsNothing);
    await tester.tap(block);
    await tester.pumpAndSettle();
    expect(interaction(tester).selected, true);
    expect(interaction(tester).enabled, false);
    expect(find.text('拖动'), findsOneWidget);
    await tester.tap(find.text('拖动'));
    await tester.pumpAndSettle();
    expect(interaction(tester).enabled, true);
    await tester.drag(block, const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(c.events.single.start, DateTime(2026, 1, 1, 10));
    await tester.tap(find.byKey(const ValueKey('calendar-lock')));
    await tester.pumpAndSettle();
    final axis = find.byKey(const ValueKey('time-axis'));
    final before = tester.getSize(axis).height;
    final region = tester.getTopLeft(
      find
          .ancestor(of: axis, matching: find.byType(SingleChildScrollView))
          .first,
    );
    final a = await tester.startGesture(
      region + const Offset(80, 250),
      pointer: 2,
    );
    final b = await tester.startGesture(
      region + const Offset(220, 250),
      pointer: 3,
    );
    await tester.pump();
    await a.moveBy(const Offset(-30, -40));
    await b.moveBy(const Offset(30, 40));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(tester.getSize(axis).height, greaterThan(before));
    expect(find.text('拖动'), findsNothing);
  });
  testWidgets('设备名可保存且空白有校验，手机设置为平铺', (tester) async {
    final c = await mountCalendar(tester, phone: true);
    await tester.pumpWidget(
      testApp(
        SingleChildScrollView(
          child: ListenableBuilder(
            listenable: c,
            builder: (_, _) => SettingsPage(controller: c),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-category')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('rename-device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-device')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('device-name-input'));
    await tester.enterText(field, '   ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入设备名称'), findsOneWidget);
    await tester.enterText(field, '我的手机');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(c.settings.deviceName, '我的手机');
  });
}
