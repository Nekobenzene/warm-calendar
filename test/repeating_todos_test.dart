import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/domain/todos.dart';
import 'package:warm_calendar/domain/recurrence.dart';
import 'package:warm_calendar/domain/reminders.dart';
import 'package:warm_calendar/domain/calendar_service.dart';
import 'package:warm_calendar/app_controller.dart';
import 'package:warm_calendar/ui/todo_editor.dart';
import 'package:warm_calendar/ui/todos_page.dart';
import 'package:warm_calendar/ui/components.dart';
import 'package:warm_calendar/ui/motion.dart';
import 'prototype_test.dart' show MemoryRepository;
import 'recurrence_test.dart' show testApp;
import 'todos_test.dart' show task, viewport;
import 'todos_test.dart' as fixtures;
import 'reminders_test.dart' show FakeNotifications;

TodoRepeatNode node(
  String id, {
  String title = '',
  int? deadline,
  List<int> reminders = const [10],
  int color = 0xffe4ead9,
}) => TodoRepeatNode(
  item: RecurrenceNode(
    id: id,
    title: title,
    notes: '节点备注$id',
    minute: 0,
    durationMinutes: 0,
    reminderOffsets: reminders,
    color: color,
  ),
  deadlineMinutes: deadline,
);
ScheduleEvent group({
  String title = '读书',
  List<TodoRepeatNode>? nodes,
  DateTime? start,
  RepeatFrequency frequency = RepeatFrequency.daily,
  int days = 1,
  HolidayPolicy holiday = HolidayPolicy.ignore,
}) => ScheduleEvent(
  id: 'todo-group',
  title: title,
  notes: '组备注',
  start: start ?? DateTime(2026, 11, 5),
  end: start ?? DateTime(2026, 11, 5),
  updatedAt: DateTime.utc(2026, 11, 5),
  taskCreatedAt: DateTime.utc(2026, 11, 5),
  todoOrder: 4,
  isTodo: true,
  reminderOffsets: const [],
  todoRepeat: TodoRepeatRule(
    frequency: frequency,
    intervalDays: days,
    holidayPolicy: holiday,
    nodes: nodes ?? [node('a', title: '一章'), node('b', deadline: 18 * 60)],
  ),
);
Future<AppController> controller(
  List<ScheduleEvent> rows, {
  FakeNotifications? notifications,
}) async {
  final repo = MemoryRepository();
  for (final row in rows) {
    repo.rows[row.id] = row;
  }
  final c = AppController(
    repository: repo,
    calendar: CalendarService(),
    notifications: notifications,
  );
  await c.initialize(startTimer: false);
  c.now = DateTime(2026, 11, 5, 12);
  return c;
}

Future<void> capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_TODO_UI')) return;
  final box = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await t.runAsync(() async {
    final img = await box.toImage();
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await File(
      'verification/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    img.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('完成待办确认后显示右下toast，取消不提示', (t) async {
    viewport(t, const Size(1280, 800));
    final c = await fixtures.controller([task('toast', 0)], t);
    addTearDown(c.dispose);
    await t.pumpWidget(
      testApp(
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => completeEvent(ctx, c, c.todos.single),
            child: const Text('操作'),
          ),
        ),
      ),
    );
    await t.tap(find.text('操作'));
    await t.pumpAndSettle();
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(find.text('待办已完成'), findsNothing);
    expect(c.todos.single.completed, false);
    await t.tap(find.text('操作'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '完成'));
    await t.pumpAndSettle();
    expect(find.text('待办已完成'), findsOneWidget);
    expect(c.todos.single.completed, true);
    expect(t.getCenter(find.text('待办已完成')).dx, greaterThan(640));
    expect(t.getCenter(find.text('待办已完成')).dy, greaterThan(600));
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
  });
  for (final phone in [false, true]) {
    testWidgets('${phone ? '手机' : '桌面'}组内截止天数输入下拉与钟表选择校验', (t) async {
      viewport(t, Size(phone ? 390 : 1280, phone ? 844 : 800));
      final c = await fixtures.controller([], t);
      addTearDown(c.dispose);
      TodoRepeatNode? saved;
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: testApp(
            Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  saved = await showAppDialog<TodoRepeatNode>(
                    context: ctx,
                    builder: (_) => TodoEditor(
                      controller: c,
                      nodeMode: true,
                      groupTitle: '每周待办',
                      periodDays: 7,
                      repeatNode: node('node', deadline: 13 * 60 + 20),
                    ),
                  );
                },
                child: const Text('节点'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('节点'));
      await t.pumpAndSettle();
      final day = find.widgetWithText(TextFormField, '周期第几天');
      expect(
        t.getSize(day).height,
        t.getSize(find.byKey(const ValueKey('node-deadline-time'))).height,
      );
      await t.enterText(day, '8');
      await t.pumpAndSettle();
      expect(find.text('输入1—7天'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, '保存'));
      await t.pumpAndSettle();
      expect(saved, isNull);
      await t.tap(find.byTooltip('选择天数'));
      await t.pumpAndSettle();
      expect(find.text('第 8 天'), findsNothing);
      await t.tap(find.text('第 7 天'));
      await t.pumpAndSettle();
      expect(find.text('输入1—7天'), findsNothing);
      await t.tap(find.byKey(const ValueKey('node-deadline-time')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TimePickerDialog>(find.byType(TimePickerDialog))
            .initialEntryMode,
        TimePickerEntryMode.dial,
      );
      await t.tap(find.byIcon(Icons.keyboard_outlined));
      await t.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await t.enterText(fields.at(0), '16');
      await t.enterText(fields.at(1), '45');
      await t.tap(find.text('确定'));
      await t.pumpAndSettle();
      expect(find.text('截止 16:45'), findsOneWidget);
      await capture(t, 'todo-deadline-072p2-${phone ? 'mobile' : 'desktop'}');
      await t.tap(find.widgetWithText(FilledButton, '保存'));
      await t.pumpAndSettle();
      expect(saved?.deadlineMinutes, 6 * 1440 + 16 * 60 + 45);
      expect(t.takeException(), isNull);
    });
  }
  setUpAll(() async {
    if (const bool.fromEnvironment('CAPTURE_TODO_UI')) {
      await (FontLoader(
        'NotoSansSC',
      )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  test('本周期展开、默认截止、组标题备注和配置往返', () async {
    final cal = CalendarService();
    final root = group();
    final rows = resolveTodos(
      [ScheduleEvent.fromJson(root.toJson())],
      cal,
      DateTime(2026, 11, 5, 12),
    );
    expect(rows.map((e) => e.title), ['读书-一章', '读书']);
    expect(rows.first.deadline, DateTime(2026, 11, 6));
    expect(rows.last.deadline, DateTime(2026, 11, 5, 18));
    expect(rows.first.notes, '节点备注a\n组备注');
    expect(rows.first.todoOrder, 4);
    expect(rows.last.todoOrder, 5);
    expect(resolveTodos([root], cal, DateTime(2026, 11, 4)), isEmpty);
    expect(
      resolveTodos([root], cal, DateTime(2026, 11, 6)).first.id,
      isNot(rows.first.id),
    );
    for (final e in rows) {
      expect(ScheduleEvent.fromJson(e.toJson()).toJson(), e.toJson());
    }
    expect(
      BackupData.decode(
        BackupData([root, ...rows], const AppSettings()).encode(),
      ).events.length,
      3,
    );
  });
  test('每周、自定义周期和月末边界无累计漂移', () {
    final weekly = group(frequency: RepeatFrequency.weekly);
    expect(
      todoCycleAt(weekly, DateTime(2026, 11, 12))!.start,
      DateTime(2026, 11, 12),
    );
    final custom = group(frequency: RepeatFrequency.interval, days: 3);
    expect(
      todoCycleAt(custom, DateTime(2026, 11, 9))!.end,
      DateTime(2026, 11, 11),
    );
    final monthly = group(
      start: DateTime(2026, 1, 31),
      frequency: RepeatFrequency.monthly,
    );
    expect(
      todoCycleAt(monthly, DateTime(2026, 2, 28))!.end,
      DateTime(2026, 3, 31),
    );
    final feb = resolveTodos(
      [monthly],
      CalendarService(),
      DateTime(2026, 2, 20),
    );
    expect(feb.first.deadline, DateTime(2026, 2, 28));
  });
  test('节假日按截止日和默认周期最后一天筛选，未知年份显式拒绝', () {
    final cal = CalendarService();
    final root = group(holiday: HolidayPolicy.onlyWeekends, nodes: [node('a')]);
    expect(resolveTodos([root], cal, DateTime(2026, 11, 5)), isEmpty);
    expect(resolveTodos([root], cal, DateTime(2026, 11, 7)), hasLength(1));
    final unknown = group(
      start: DateTime(2050, 1, 1),
      holiday: HolidayPolicy.onlyHolidays,
    );
    expect(
      () => resolveTodos([unknown], cal, DateTime(2050, 1, 1), validate: true),
      throwsFormatException,
    );
  });
  test('待办与日程组标题二选一校验，组合标题没有多余连字符', () {
    final good = group(
      title: '',
      nodes: [node('a', title: '独立标题')],
    );
    expect(ScheduleEvent.fromJson(good.toJson()).title, '');
    expect(
      resolveTodos(
        [good],
        CalendarService(),
        DateTime(2026, 11, 5),
      ).single.title,
      '独立标题',
    );
    expect(
      () => ScheduleEvent.fromJson(group(title: '').toJson()),
      throwsFormatException,
    );
    final schedule = ScheduleEvent(
      id: 'schedule',
      title: '',
      start: DateTime(2026, 11, 5),
      end: DateTime(2026, 11, 5),
      updatedAt: DateTime.utc(2026),
      recurrence: RecurrenceRule(
        kind: RepeatKind.cycle,
        frequency: RepeatFrequency.daily,
        until: DateTime(2026, 11, 6),
        nodes: [node('n', title: '节点').item],
      ),
    );
    expect(ScheduleEvent.fromJson(schedule.toJson()).title, '');
    expect(expandSeries(schedule, CalendarService()).first.title, '节点');
    expect(
      () => ScheduleEvent.fromJson(
        schedule
            .copyWith(
              recurrence: schedule.recurrence!.copyWith(
                nodes: [node('empty').item],
              ),
            )
            .toJson(),
      ),
      throwsFormatException,
    );
  });
  test('单项完成、删除、跨日改期与重要性重排在重载后保留且不影响下周期', () async {
    final c = await controller([task('single', 0), group()]);
    addTearDown(c.dispose);
    var items = c.todos;
    expect(items.map((e) => e.title), ['待办single', '读书-一章', '读书']);
    final a = items[1], b = items[2];
    await c.reorderTodos([b.id, 'single', a.id]);
    expect(c.todos.map((e) => e.id), [b.id, 'single', a.id]);
    await c.moveEvent(a, DateTime(2026, 11, 7, 10));
    await c.toggleCompleted(b);
    await c.reloadSyncedEvents();
    expect(c.todos.first.completed, true);
    expect(c.todos.last.deadline, DateTime(2026, 11, 7, 10));
    await c.changeTodos({a.id}, delete: true);
    expect(c.todos.map((e) => e.id), [b.id, 'single']);
    await c.refreshTime(at: DateTime(2026, 11, 6, 12));
    expect(c.todos.length, 3);
    expect(c.todos.every((e) => !e.completed), true);
    expect(c.todos.any((e) => e.id == a.id || e.id == b.id), false);
    await c.deleteEvent(
      c.todos.firstWhere((e) => e.seriesId != null),
      entireSeries: true,
    );
    expect(c.todos.map((e) => e.id), ['single']);
  });
  test('重复待办整组改截止仅影响目标节点，单独修改继续保留', () async {
    final c = await controller([group()]);
    addTearDown(c.dispose);
    final a = c.todos.first, b = c.todos.last;
    await c.moveEvent(a, DateTime(2026, 11, 5, 19), entireSeries: true);
    expect(c.todos.first.deadline, DateTime(2026, 11, 5, 19));
    expect(c.todos.last.deadline, b.deadline);
    await c.refreshTime(at: DateTime(2026, 11, 6, 12));
    expect(c.todos.first.deadline, DateTime(2026, 11, 6, 19));
  });
  test('截止提醒进入系统队列、应用内提醒和未来周期，完成后撤销', () async {
    final backend = FakeNotifications();
    final c = await controller([
      group(
        nodes: [
          node('a', deadline: 13 * 60, reminders: [60, 0]),
        ],
      ),
      task(
        'single',
        1,
        due: DateTime(2026, 11, 5, 13),
      ).copyWith(reminderOffsets: [60]),
    ], notifications: backend);
    addTearDown(c.dispose);
    await c.refreshTime(at: DateTime(2026, 11, 5, 12));
    expect(c.dueReminders.map((e) => e.title), containsAll(['读书', '待办single']));
    expect(
      backend.planned.any(
        (r) => r.event.title == '读书' && r.at == DateTime(2026, 11, 6, 12),
      ),
      true,
    );
    expect(backend.planned.first.body, contains('截止'));
    expect(backend.planned.first.body, isNot(contains('开始')));
    final current = c.todos.firstWhere((e) => e.seriesId != null);
    await c.toggleCompleted(current);
    expect(backend.planned.any((r) => r.event.id == current.id), false);
    final early = group(
      nodes: [
        node('a', deadline: 60, reminders: [120]),
      ],
    );
    expect(
      planReminders(
        todoReminderEvents([early], CalendarService(), DateTime(2026, 11, 5)),
        const AppSettings(),
        DateTime(2026, 11, 5),
      ),
      isEmpty,
    );
    final boundary = await controller([
      group(
        nodes: [
          node('end', reminders: [0]),
        ],
      ),
    ]);
    addTearDown(boundary.dispose);
    await boundary.refreshTime(at: DateTime(2026, 11, 6));
    expect(boundary.dueReminders, hasLength(1));
    expect(boundary.dueReminders.single.start, DateTime(2026, 11, 6));
    expect(boundary.todos.single.start, DateTime(2026, 11, 7));
  });
  for (final phone in [false, true]) {
    testWidgets('${phone ? '手机' : '桌面'}重复待办表单、节点配置与保存', (t) async {
      viewport(t, Size(phone ? 390 : 1280, phone ? 844 : 800));
      final c = await fixtures.controller([], t);
      c.now = DateTime(2026, 11, 5, 12);
      addTearDown(c.dispose);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: testApp(
            Builder(
              builder: (ctx) => TextButton(
                onPressed: () => openTodoEditor(ctx, c),
                child: const Text('新建'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('新建'));
      await t.pumpAndSettle();
      await t.tap(find.text('重复'));
      await t.pumpAndSettle();
      expect(find.text('重复日程'), findsNothing);
      await t.enterText(find.widgetWithText(TextFormField, '组标题（可留空）'), '每日阅读');
      await t.tap(find.byTooltip('编辑组内待办').first);
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextFormField, '标题'), '读一章');
      await t.tap(find.text('截止提醒'));
      await t.pumpAndSettle();
      expect(find.text('截止时'), findsOneWidget);
      await t.tap(find.text('截止时'));
      await t.pumpAndSettle();
      await t.tap(find.text('应用提醒'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '保存').last);
      await t.pumpAndSettle();
      await capture(t, 'todo-repeat-072-${phone ? 'mobile' : 'desktop'}');
      await t.ensureVisible(find.widgetWithText(FilledButton, '保存').last);
      await t.tap(find.widgetWithText(FilledButton, '保存').last);
      await t.pumpAndSettle();
      expect(
        c.todoGroups,
        hasLength(1),
        reason: t
            .widgetList<Text>(find.byType(Text))
            .map((e) => e.data)
            .join('|'),
      );
      expect(c.todos.single.title, '每日阅读-读一章');
      expect(c.todos.single.reminderOffsets, [0]);
      expect(c.todos.single.deadline, DateTime(2026, 11, 6));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('组内长按改变节点顺序，空组标题规则及隐藏组管理入口', (t) async {
    viewport(t, const Size(1280, 800));
    final root = group(
      title: '',
      nodes: [
        node('a', title: '第一项'),
        node('b', title: '第二项'),
      ],
    );
    final c = await fixtures.controller([root], t);
    c.now = DateTime(2026, 11, 5, 12);
    addTearDown(c.dispose);
    await t.pumpWidget(
      testApp(
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => openTodoEditor(ctx, c, task: root),
            child: const Text('编辑组'),
          ),
        ),
      ),
    );
    await t.tap(find.text('编辑组'));
    await t.pumpAndSettle();
    final gesture = await t.startGesture(t.getCenter(find.text('第一项')));
    await t.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 8));
      await t.pump(const Duration(milliseconds: 16));
    }
    await t.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '保存'));
    await t.pumpAndSettle();
    expect(
      c.todos.map((e) => e.title),
      ['第二项', '第一项'],
      reason:
          '${c.todoGroups.single.todoRepeat!.nodes.map((e) => e.item.id).toList()} ${t.widgetList<Text>(find.byType(Text)).map((e) => e.data).join('|')}',
    );
    expect(c.todoGroups.single.title, '');
    await t.pumpWidget(testApp(TodosPage(controller: c)));
    await t.tap(find.text('重复组'));
    await t.pumpAndSettle();
    expect(find.text('重复待办组'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
