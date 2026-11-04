import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_calendar/app_controller.dart';
import 'package:warm_calendar/domain/calendar_service.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/domain/app_update.dart';
import 'package:warm_calendar/ui/update_panel.dart';
import 'package:warm_calendar/ui/calendar_blocks.dart';
import 'package:warm_calendar/ui/cycle_editor.dart';
import 'package:warm_calendar/ui/event_form.dart';
import 'package:warm_calendar/ui/node_editor.dart';
import 'prototype_test.dart' show MemoryRepository;
import 'recurrence_test.dart' show testApp;
import 'calendar_interaction_test.dart' show mountCalendar;
import 'preview_06_domain_test.dart' show cycle;

void main() {
  testWidgets('窄屏大字的更新提示与下载进度保持可见', (tester) async {
    tester.view.physicalSize = const Size(360, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final updates = AppUpdateController(target: 'android')
      ..release = UpdateRelease(
        'v0.7.0',
        'test.apk',
        Uri.parse('https://github.com/asset'),
        100,
        'a' * 64,
      );
    final c = AppController(
      repository: MemoryRepository(),
      calendar: CalendarService(),
      updates: updates,
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(testApp(UpdatePanel(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('下载并安装'), findsOneWidget);
    expect(tester.takeException(), isNull);
    updates.downloading = true;
    updates.received = 33;
    await tester.pumpWidget(
      testApp(UpdatePanel(key: const ValueKey('progress'), controller: c)),
    );
    await tester.pump();
    expect(find.textContaining('33.0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets('周期编辑首节点、跨日及新增继承，宽度$width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController(
        repository: MemoryRepository(),
        calendar: CalendarService(),
      );
      await tester.runAsync(() => c.initialize(startTimer: false));
      addTearDown(c.dispose);
      await tester.pumpWidget(
        testApp(EventEditor(controller: c, event: cycle())),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CycleEditor), findsOneWidget);
      expect(find.text('Day1'), findsWidgets);
      await tester.tap(find.text('晚班'));
      await tester.pumpAndSettle();
      expect(find.byType(NodeEditor), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, '节点标题（可留空）'),
        '值夜班',
      );
      await tester.tap(find.text('保存节点'));
      await tester.pumpAndSettle();
      expect(find.text('值夜班'), findsOneWidget);
      await tester.tap(find.text('添加节点'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, '开始时间'))
            .controller!
            .text,
        '10:00',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, '节点标题（可留空）'),
            )
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存周期'));
      await tester.pumpAndSettle();
      expect(c.events, hasLength(4));
      expect(c.events.first.title, '值班-值夜班');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('手机大字模式的三模式切换无溢出且保留草稿标题', (tester) async {
    tester.view.physicalSize = const Size(360, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = AppController(
      repository: MemoryRepository(),
      calendar: CalendarService(),
    );
    await tester.runAsync(() => c.initialize(startTimer: false));
    addTearDown(c.dispose);
    await tester.pumpWidget(testApp(EventEditor(controller: c)));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '标题'), '手机草稿');
    await tester.tap(find.text('重复周期'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '组标题'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('不重复'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '标题'), '更新草稿');
    await tester.tap(find.text('重复周期'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, '组标题'))
          .controller!
          .text,
      '更新草稿',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('点型线标签可移动、无边界手柄，选中删除和最小缩放', (tester) async {
    final c = await mountCalendar(tester);
    await c.saveEvent(
      ScheduleEvent(
        id: 'point',
        title: '时间点',
        start: DateTime(2026, 1, 1, 12),
        end: DateTime(2026, 1, 1, 12),
        updatedAt: c.now,
      ),
    );
    await tester.pumpAndSettle();
    final block = find.byKey(const ValueKey('interaction-point-2026-01-01'));
    await tester.ensureVisible(block);
    await tester.tap(block);
    await tester.pumpAndSettle();
    final w = tester.widget<CalendarEventInteraction>(block);
    expect(w.point, true);
    expect(w.resizable, false);
    expect(w.enabled, true);
    expect(find.byKey(const ValueKey('point-tag-point')), findsOneWidget);
    await tester.drag(block, const Offset(0, 30));
    await tester.pumpAndSettle();
    final moved = c.events.firstWhere((e) => e.id == 'point');
    expect(moved.isPoint, true);
    expect(moved.start, DateTime(2026, 1, 1, 12, 30));
    await tester.tap(find.byKey(const ValueKey('calendar-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.text('删除日程'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(c.events.where((e) => e.id == 'point'), isEmpty);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('缩小时间轴'));
      await tester.pumpAndSettle();
    }
    expect(find.text('分度 120分钟'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('time-axis'))).height,
      lessThan(400),
    );
    expect(tester.takeException(), isNull);
  });
}
