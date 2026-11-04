import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_calendar/app_controller.dart';
import 'package:warm_calendar/data/repository.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/domain/calendar_service.dart';
import 'package:warm_calendar/domain/calendar_layout.dart';
import 'package:warm_calendar/domain/recurrence.dart';
import 'package:warm_calendar/domain/time_axis.dart';
import 'package:warm_calendar/domain/schedule_sort.dart';
import 'package:warm_calendar/ui/calendar_page.dart';
import 'package:warm_calendar/ui/calendar_blocks.dart';
import 'package:warm_calendar/ui/event_editor.dart';
import 'package:warm_calendar/ui/theme.dart';
import 'package:warm_calendar/ui/components.dart' show showMessage, deleteEvent;
import 'prototype_test.dart' show MemoryRepository;

ScheduleEvent repeated({
  RepeatFrequency frequency = RepeatFrequency.daily,
  DateTime? start,
  DateTime? until,
  List<int> minutes = const [540, 660],
  List<int> weekdays = const [1, 3, 5],
  List<int> monthDays = const [29, 31],
  HolidayPolicy holiday = HolidayPolicy.ignore,
  bool point = false,
}) => ScheduleEvent(
  id: 'series-1',
  title: '重复事项',
  start: start ?? DateTime(2026, 1, 1, 9),
  end: (start ?? DateTime(2026, 1, 1, 9)).add(
    Duration(minutes: point ? 0 : 60),
  ),
  updatedAt: DateTime.utc(2026),
  color: 0xFFD26666,
  completedColor: 0xFF778899,
  reminderMinutes: 0,
  recurrence: RecurrenceRule(
    frequency: frequency,
    until: until ?? DateTime(2026, 1, 3),
    minutes: minutes,
    weekdays: weekdays,
    monthDays: monthDays,
    intervalDays: 3,
    holidayPolicy: holiday,
  ),
);

Widget testApp(Widget child) => MaterialApp(
  theme: appTheme(),
  locale: const Locale('zh', 'CN'),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [Locale('zh', 'CN')],
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('整组调整边界保留单次例外，短例外导致负时长时原子拒绝', () async {
    final c = AppController(
      repository: MemoryRepository(),
      calendar: CalendarService(),
    );
    await c.initialize(startTimer: false);
    await c.saveEvent(repeated());
    var first = c.events.first;
    await c.moveEvent(
      first,
      first.start,
      newEnd: first.start.add(const Duration(minutes: 10)),
    );
    first = c.events.first;
    final untouched = c.events.map((e) => e.toJson()).toList();
    final second = c.events[1];
    await expectLater(
      c.moveEvent(
        second,
        second.start,
        newEnd: second.end.subtract(const Duration(minutes: 30)),
        entireSeries: true,
      ),
      throwsFormatException,
    );
    expect(c.events.map((e) => e.toJson()).toList(), untouched);
    await c.moveEvent(
      second,
      second.start,
      newEnd: second.end.add(const Duration(minutes: 30)),
      entireSeries: true,
    );
    expect(
      c.events.first.end.difference(c.events.first.start),
      const Duration(minutes: 40),
    );
    expect(
      c.events[1].end.difference(c.events[1].start),
      const Duration(minutes: 90),
    );
    c.dispose();
  });
  test('日/周/月/间隔、多时间点、闰日与短月', () {
    final calendar = CalendarService();
    final daily = expandSeries(repeated(), calendar);
    expect(daily, hasLength(6));
    expect(daily.map((e) => e.id).toSet(), hasLength(6));
    expect(daily.first.color, 0xFFD26666);
    expect(daily.first.completedColor, 0xFF778899);
    final weekly = expandSeries(
      repeated(
        frequency: RepeatFrequency.weekly,
        start: DateTime(2026, 1, 5, 9),
        until: DateTime(2026, 1, 11),
      ),
      calendar,
    );
    expect(weekly, hasLength(6));
    expect(weekly.map((e) => e.start.weekday).toSet(), {1, 3, 5});
    final monthly = expandSeries(
      repeated(
        frequency: RepeatFrequency.monthly,
        start: DateTime(2028, 1, 31, 9),
        until: DateTime(2028, 3, 31),
        minutes: [540],
      ),
      calendar,
    );
    expect(monthly.map((e) => dateKey(e.start)), [
      '2028-01-31',
      '2028-02-29',
      '2028-03-29',
      '2028-03-31',
    ]);
    final cycle = expandSeries(
      repeated(
        frequency: RepeatFrequency.interval,
        until: DateTime(2026, 1, 10),
        minutes: [540],
      ),
      calendar,
    );
    expect(cycle.map((e) => e.start.day), [1, 4, 7, 10]);
    expect(expandSeries(repeated(minutes: [480, 540]), calendar), hasLength(5));
  });
  test('节假日含周末、调休优先，未知年份/空选择/超量规则拒绝保存', () async {
    final calendar = CalendarService();
    await calendar.load();
    final skip = expandSeries(
      repeated(
        until: DateTime(2026, 1, 5),
        holiday: HolidayPolicy.skip,
        minutes: [540],
      ),
      calendar,
      validate: true,
    );
    expect(skip.map((e) => e.start.day), [4, 5]);
    final only = expandSeries(
      repeated(
        until: DateTime(2026, 1, 5),
        holiday: HolidayPolicy.only,
        minutes: [540],
      ),
      calendar,
      validate: true,
    );
    expect(only.map((e) => e.start.day), [1, 2, 3]);
    expect(
      () => expandSeries(
        repeated(until: DateTime(2027, 1, 1), holiday: HolidayPolicy.skip),
        calendar,
        validate: true,
      ),
      throwsFormatException,
    );
    expect(
      () => expandSeries(
        repeated(frequency: RepeatFrequency.weekly, weekdays: []),
        calendar,
      ),
      throwsFormatException,
    );
    expect(
      () => expandSeries(repeated(until: DateTime(2099)), calendar),
      throwsFormatException,
    );
  });
  test('独立完成、改期、删除；规则和例外备份重开，删除整组不复活', () async {
    final repo = MemoryRepository();
    var c = AppController(repository: repo, calendar: CalendarService());
    await c.initialize(startTimer: false);
    await c.saveEvent(repeated());
    final first = c.events[0], second = c.events[1], third = c.events[2];
    await c.toggleCompleted(first);
    await c.moveEvent(second, second.start.add(const Duration(minutes: 20)));
    await c.deleteEvent(third);
    expect(c.events, hasLength(5));
    expect(c.events.where((e) => e.completed), hasLength(1));
    expect(c.events.singleWhere((e) => e.id == second.id).start.minute, 20);
    expect(BackupData.decode(c.exportBackup()).events, hasLength(4));
    c.dispose();
    c = AppController(repository: repo, calendar: CalendarService());
    await c.initialize(startTimer: false);
    expect(c.events, hasLength(5));
    expect(c.events.first.completed, true);
    await c.deleteEvent(c.events.first, entireSeries: true);
    await c.refreshTime(at: DateTime(2026, 1, 2));
    expect(c.events, isEmpty);
    expect(
      BackupData.decode(
        c.exportBackup(),
      ).events.where((e) => e.recurrence != null).single.deleted,
      true,
    );
    c.dispose();
  });
  test('跨午夜整体平移保持ID及处理状态，批量写失败不改变数据', () async {
    final repo = MemoryRepository();
    final c = AppController(repository: repo, calendar: CalendarService());
    await c.initialize(startTimer: false);
    await c.saveEvent(repeated(minutes: [540, 1380]));
    final first = c.events[0], second = c.events[1];
    await c.toggleCompleted(first);
    await c.deleteEvent(second);
    final before = {for (final e in c.events) e.id: e.start};
    final moving = c.events.last;
    repo.failWrites = true;
    await expectLater(
      c.moveEvent(
        moving,
        moving.start.add(const Duration(hours: 2)),
        entireSeries: true,
      ),
      throwsStateError,
    );
    expect({for (final e in c.events) e.id: e.start}, before);
    repo.failWrites = false;
    await c.moveEvent(
      moving,
      moving.start.add(const Duration(hours: 2)),
      entireSeries: true,
    );
    for (final e in c.events) {
      expect(e.start, before[e.id]!.add(const Duration(hours: 2)));
    }
    expect(c.events.first.completed, true);
    expect(c.events.any((e) => e.id == second.id), false);
    expect(c.events.any((e) => e.start.hour == 1), true);
    expect(
      resolveEvents(
        BackupData.decode(c.exportBackup()).events,
        c.calendar,
      ).map((e) => e.id),
      c.events.map((e) => e.id),
    );
    c.dispose();
  });
  test('整体移动后的假日筛选使用实际发生日期', () async {
    final c = AppController(
      repository: MemoryRepository(),
      calendar: CalendarService(),
    );
    await c.initialize(startTimer: false);
    await c.saveEvent(
      repeated(
        start: DateTime(2026, 1, 5, 9),
        until: DateTime(2026, 1, 12),
        minutes: [540],
        holiday: HolidayPolicy.skip,
      ),
    );
    final first = c.events.first;
    await c.moveEvent(
      first,
      first.start.add(const Duration(days: 1)),
      entireSeries: true,
    );
    expect(c.events.every((e) => c.calendar.isRestDay(e.start) == false), true);
    c.dispose();
  });
  test('零时长当日归属、到时逾期，自动完成不吞掉时间点提醒', () async {
    final c = AppController(
      repository: MemoryRepository(),
      calendar: CalendarService(),
    );
    await c.initialize(startTimer: false);
    c.now = DateTime(2026, 1, 1, 8);
    await c.saveEvent(
      repeated(point: true, minutes: [540], until: DateTime(2026, 1, 1)),
    );
    final point = c.events.single;
    expect(point.isPoint, true);
    expect(point.occursOn(DateTime(2026, 1, 1)), true);
    expect(point.occursOn(DateTime(2026, 1, 2)), false);
    expect(point.statusAt(point.start), ScheduleStatus.overdue);
    await c.updateSettings(c.settings.copyWith(autoCompleteExpired: true));
    await c.refreshTime(at: point.start);
    expect(c.dueReminders.map((e) => e.id), contains(point.id));
    expect(c.events.single.completed, true);
    expect(BackupData.decode(c.exportBackup()).events.last.isPoint, true);
    c.dispose();
  });
  test('SQLite重开保留规则、例外、颜色和新设置，兼容旧备份', () async {
    final file = File(
      '${Directory.systemTemp.path}/repeat-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    var repo = SqliteScheduleRepository(CalendarDatabase(NativeDatabase(file)));
    final root = repeated(point: true);
    final one = expandSeries(
      root,
      CalendarService(),
    ).first.copyWith(completed: true);
    await repo.saveEvents([root, one]);
    await repo.saveSettings(
      const AppSettings(
        calendarDragEnabled: true,
        snapToGrid: false,
        scheduleSort: ScheduleSort.title,
        sortDescending: true,
      ),
    );
    await repo.close();
    repo = SqliteScheduleRepository(CalendarDatabase(NativeDatabase(file)));
    addTearDown(() async {
      await repo.close();
      await file.delete();
    });
    final events = resolveEvents(await repo.loadEvents(), CalendarService());
    expect(events, hasLength(6));
    expect(events.first.displayColor, 0xFF778899);
    await repo.db.customStatement(
      "CREATE TRIGGER reject_instance BEFORE INSERT ON events WHEN NEW.id LIKE '%::%' BEGIN SELECT RAISE(ABORT, 'test write failure'); END",
    );
    await expectLater(
      repo.saveEvents([
        root.copyWith(start: root.start.add(const Duration(minutes: 1))),
        one.copyWith(completed: false),
      ]),
      throwsA(anything),
    );
    expect(
      (await repo.loadEvents()).singleWhere((e) => e.id == root.id).start,
      root.start,
    );
    final s = await repo.loadSettings();
    expect(s.calendarDragEnabled, true);
    expect(s.snapToGrid, false);
    expect(s.scheduleSort, ScheduleSort.title);
    expect(s.sortDescending, true);
    final old = BackupData.decode(
      '{"format":"warm-calendar","version":1,"events":[],"settings":{"upcomingRows":2}}',
    );
    expect(old.settings.snapToGrid, true);
    expect(old.settings.calendarDragEnabled, false);
  });
  test('连续多列重叠、红色转黄、同色相邻分隔；吸附精度与排序', () {
    final day = DateTime(2026, 1, 1);
    ScheduleEvent e(String id, int start, int end, {int color = 0xFFCBDFF0}) =>
        ScheduleEvent(
          id: id,
          title: id,
          start: day.add(Duration(minutes: start)),
          end: day.add(Duration(minutes: end)),
          updatedAt: day,
          color: color,
        );
    final rows = [
      e('a', 540, 720),
      e('b', 540, 600),
      e('c', 600, 660),
      e('d', 630, 690, color: 0xFFD26666),
      e('e', 900, 960),
      e('f', 960, 1000),
    ];
    final layout = layoutDay(rows, day);
    expect(layout.items, hasLength(6));
    expect(layout.items.take(4).every((p) => p.columns == 3), true);
    expect(layout.items.first.lane, 0);
    expect(layout.items.last.columns, 1);
    expect(layout.items.last.separator, true);
    expect(layout.overlaps.any((p) => p.yellow), true);
    expect(layout.overlaps.any((p) => !p.yellow), true);
    expect(layout.overlaps.every((p) => p.start >= 540 && p.end <= 690), true);
    final start = DateTime(2026, 1, 1, 9);
    expect(
      draggedStart(
        start,
        dx: 100,
        dy: 22,
        dayWidth: 100,
        hourHeight: 60,
        step: 30,
        snap: true,
      ),
      DateTime(2026, 1, 2, 9, 30),
    );
    expect(
      draggedStart(
        start,
        dx: 0,
        dy: 22,
        dayWidth: 100,
        hourHeight: 60,
        step: 30,
        snap: false,
      ),
      DateTime(2026, 1, 1, 9, 22),
    );
    for (final sort in ScheduleSort.values) {
      final sorted = sortSchedules(
        rows,
        AppSettings(scheduleSort: sort),
        start,
      );
      expect(sorted, hasLength(6));
    }
    expect(
      sortSchedules(
        rows,
        const AppSettings(scheduleSort: ScheduleSort.end, sortDescending: true),
        start,
      ).first.id,
      'f',
    );
  });
  for (final width in [1366.0, 390.0]) {
    testWidgets('创建多时间点零时长重复日程与自定义完成颜色，宽度$width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController(
        repository: MemoryRepository(),
        calendar: CalendarService(),
      );
      await tester.runAsync(() => c.initialize(startTimer: false));
      c.now = DateTime(2026, 1, 1, 8);
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => openEventEditor(context, c),
              child: const Text('新建'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('新建'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '标题'),
        '每日两个时间点',
      );
      await tester.tap(find.text(width < 600 ? '仅时间点' : '仅时间点（无时长）'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '结束日期'), findsNothing);
      expect(find.widgetWithText(TextFormField, '开始日期'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, '开始时间'),
        '09:00',
      );
      final repeat = find.byKey(const ValueKey('event-repeat'));
      await tester.ensureVisible(find.text('重复日程'));
      await tester.tap(find.text('重复日程'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(repeat);
      await tester.tap(repeat);
      await tester.pumpAndSettle();
      await tester.tap(find.text('每日').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('添加节点'));
      await tester.tap(find.text('添加节点'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '开始时间').last,
        '11:00',
      );
      await tester.tap(find.text('保存节点'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(TextFormField, '停止日期'));
      await tester.enterText(
        find.widgetWithText(TextFormField, '停止日期'),
        '2026-01-03',
      );
      await tester.ensureVisible(find.text('应用重复规则'));
      await tester.tap(find.text('应用重复规则'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已完成颜色'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('color-code-input')),
        '#777777',
      );
      await tester.ensureVisible(find.text('应用颜色'));
      await tester.tap(find.text('应用颜色'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存日程'));
      await tester.tap(find.text('保存日程'));
      await tester.pumpAndSettle();
      expect(c.events, hasLength(6));
      expect(c.events.every((e) => e.isPoint), true);
      expect(c.events.first.completedColor, 0xFF777777);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  testWidgets('提示框具有可测的进出位移与透明度', (tester) async {
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showMessage(context, '动效验证'),
            child: const Text('提示'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('提示'));
    await tester.pump();
    final message = find.text('动效验证');
    final opacity = find
        .ancestor(of: message, matching: find.byType(Opacity))
        .first;
    final entryY = tester.getCenter(message).dy;
    expect(tester.widget<Opacity>(opacity).opacity, 0);
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.widget<Opacity>(opacity).opacity, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pumpAndSettle();
    final steadyY = tester.getCenter(message).dy;
    expect(steadyY, lessThan(entryY - 20));
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(message, findsOneWidget);
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(tester.getCenter(message).dy, greaterThan(steadyY));
    expect(tester.widget<Opacity>(opacity).opacity, lessThan(1));
    await tester.pumpAndSettle();
    expect(message, findsNothing);
  });
  testWidgets('重复删除确认可取消、仅删除本次和删除整个日程', (tester) async {
    final c = AppController(
      repository: MemoryRepository(),
      calendar: CalendarService(),
    );
    await tester.runAsync(() => c.initialize(startTimer: false));
    await c.saveEvent(repeated());
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => deleteEvent(context, c, c.events.first),
            child: const Text('删除测试'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('删除测试'));
    await tester.pumpAndSettle();
    expect(find.text('仅删除本次'), findsOneWidget);
    expect(find.text('删除整个日程'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(c.events, hasLength(6));
    await tester.tap(find.text('删除测试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅删除本次'));
    await tester.pumpAndSettle();
    expect(c.events, hasLength(5));
    await tester.tap(find.text('删除测试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除整个日程'));
    await tester.pumpAndSettle();
    expect(c.events, isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('Shift滚轮缩放及选中拖动；重复日程拖动取消、本次、全部', (tester) async {
    tester.view.physicalSize = const Size(1366, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AppController(
      repository: MemoryRepository(),
      calendar: CalendarService(),
    );
    await tester.runAsync(() => c.initialize(startTimer: false));
    c.now = DateTime(2026, 1, 1, 8);
    await c.saveEvent(repeated());
    final original = c.events.first;
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
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<CalendarView>),
        matching: find.text('周'),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(
      ValueKey('calendar-event-${original.id}-2026-01-01'),
    );
    await tester.ensureVisible(card);
    final axis = find.byKey(const ValueKey('time-axis'));
    final oldHeight = tester.getSize(axis).height;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(card),
        scrollDelta: const Offset(0, -120),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(tester.getSize(axis).height, greaterThan(oldHeight));
    expect(find.text('分度 15分钟'), findsOneWidget);
    await tester.ensureVisible(card);
    await tester.drag(card, const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(c.events.first.start, original.start);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CalendarEventInteraction>(
            find.byKey(ValueKey('interaction-${original.id}-2026-01-01')),
          )
          .selected,
      true,
    );
    await tester.ensureVisible(card);
    await tester.drag(card, const Offset(0, 96));
    await tester.pumpAndSettle();
    expect(find.text('移动重复日程'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(c.events.first.start, original.start);
    await tester.ensureVisible(card);
    await tester.drag(card, const Offset(0, 96));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅本次'));
    await tester.pumpAndSettle();
    final moved = c.events.singleWhere((e) => e.id == original.id);
    expect(moved.start.isAfter(original.start), true);
    expect(moved.start.minute % 15, 0);
    await tester.ensureVisible(card);
    await tester.drag(card, const Offset(0, 96));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(
      c.seriesFor(c.events.first)!.recurrence!.shiftMinutes,
      greaterThan(0),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
