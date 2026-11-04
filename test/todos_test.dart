import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_calendar/app_controller.dart';
import 'package:warm_calendar/data/repository.dart';
import 'package:warm_calendar/domain/calendar_service.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/domain/todos.dart';
import 'package:warm_calendar/sync/sync_store.dart';
import 'package:warm_calendar/ui/calendar_page.dart';
import 'package:warm_calendar/ui/calendar_blocks.dart';
import 'package:warm_calendar/ui/shell.dart';
import 'package:warm_calendar/ui/todo_editor.dart';
import 'package:warm_calendar/ui/todos_page.dart';
import 'package:warm_calendar/ui/components.dart';
import 'prototype_test.dart' show MemoryRepository;
import 'recurrence_test.dart' show testApp;

ScheduleEvent task(
  String id,
  int order, {
  DateTime? due,
  bool completed = false,
  int created = 1,
}) => ScheduleEvent(
  id: id,
  title: '待办$id',
  notes: '备注$id',
  isTodo: true,
  hasDeadline: due != null,
  taskCreatedAt: DateTime.utc(2026, 11, created),
  todoOrder: order,
  start: due ?? DateTime(2026, 11, created),
  end: due ?? DateTime(2026, 11, created),
  updatedAt: DateTime.utc(2026, 11, 4),
  completed: completed,
  reminderOffsets: const [],
);

Future<AppController> controller([
  List<ScheduleEvent> tasks = const [],
  WidgetTester? tester,
]) async {
  final repo = MemoryRepository();
  for (final e in tasks) {
    repo.rows[e.id] = e;
  }
  final c = AppController(repository: repo, calendar: CalendarService());
  if (tester == null) {
    await c.initialize(startTimer: false);
  } else {
    await tester.runAsync(() => c.initialize(startTimer: false));
  }
  c.now = DateTime(2026, 11, 4, 12);
  return c;
}

void viewport(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('排序箭头在200毫秒内平滑旋转并响应连续切换', (t) async {
    var descending = false;
    late StateSetter update;
    await t.pumpWidget(
      testApp(
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return SortDirectionIcon(descending: descending);
          },
        ),
      ),
    );
    update(() => descending = true);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final rotation = find.descendant(
      of: find.byType(SortDirectionIcon),
      matching: find.byType(RotationTransition),
    );
    expect(
      t.widget<RotationTransition>(rotation).turns.value,
      inExclusiveRange(0, .5),
    );
    update(() => descending = false);
    await t.pumpAndSettle();
    expect(t.widget<RotationTransition>(rotation).turns.value, 0);
  });
  test('三种排序的正反序、无截止任务与稳定创建时间', () {
    final tasks = [
      task('a', 2, due: DateTime(2026, 11, 6)),
      task('b', 0, due: DateTime(2026, 11, 5), created: 3),
      task('c', 1, created: 2),
    ];
    final expected = {
      TodoSort.created: ['a', 'c', 'b'],
      TodoSort.importance: ['b', 'c', 'a'],
      TodoSort.deadline: ['b', 'a', 'c'],
    };
    for (final sort in TodoSort.values) {
      for (final reverse in [false, true]) {
        final values = orderedTodos(
          tasks,
          AppSettings(todoSort: sort, todoSortDescending: reverse),
        );
        expect(
          values.map((e) => e.id),
          reverse ? expected[sort]!.reversed : expected[sort],
        );
      }
    }
    final saved = ScheduleEvent.fromJson(
      tasks.first.copyWith(title: '新名称').toJson(),
    );
    expect(saved.createdAt, tasks.first.createdAt);
    expect(saved.isTodo, true);
    expect(task('x', 0).statusAt(DateTime(2099)), ScheduleStatus.pending);
  });

  test('待办备份往返和非法待办拒绝，旧日程兼容', () {
    final e = task('a', 0, due: DateTime(2026, 11, 7));
    final backup = BackupData([
      e,
    ], const AppSettings(todoSort: TodoSort.deadline, autoCompleteTodos: true));
    final restored = BackupData.decode(backup.encode());
    expect(restored.events.single.toJson(), e.toJson());
    expect(restored.settings.autoCompleteTodos, true);
    expect(
      () => ScheduleEvent.fromJson({...e.toJson(), 'todoOrder': -1}),
      throwsFormatException,
    );
    expect(
      () => ScheduleEvent.fromJson({
        ...e.toJson(),
        'reminderOffsets': [0],
      }),
      throwsFormatException,
    );
  });

  test('重排保持隐藏已完成任务位置，重载顺序一致，失败不改内存', () async {
    final c = await controller([
      task('a', 0),
      task('done', 1, completed: true),
      task('b', 2),
      task('c', 3),
    ]);
    addTearDown(c.dispose);
    await c.reorderTodos(['c', 'a', 'b']);
    expect(c.todos.map((e) => e.id), ['c', 'done', 'a', 'b']);
    await c.reloadSyncedEvents();
    expect(c.todos.map((e) => e.id), ['c', 'done', 'a', 'b']);
    (c.repository as MemoryRepository).failWrites = true;
    await expectLater(c.reorderTodos(['b', 'a', 'c']), throwsStateError);
    expect(c.todos.map((e) => e.id), ['c', 'done', 'a', 'b']);
  });

  test('截止待办只投影为日历时间点，拖动和批量操作不会创建日程', () async {
    final due = DateTime(2026, 11, 5, 10);
    final c = await controller([
      task('dated', 0, due: due),
      task('undated', 1),
    ]);
    addTearDown(c.dispose);
    expect(c.events, isEmpty);
    expect(c.onDay(due).map((e) => e.id), ['dated']);
    final created = c.todos.first.createdAt;
    await c.moveEvent(
      c.todos.first,
      due.add(const Duration(days: 1)),
      newEnd: due.add(const Duration(days: 1)),
    );
    expect(c.onDay(due), isEmpty);
    expect(c.todos.first.createdAt, created);
    expect(c.todos.first.isPoint, true);
    await c.changeTodos({'dated', 'undated'}, completed: true);
    expect(c.todos.every((e) => e.completed), true);
    await c.changeTodos({'undated'}, delete: true);
    expect(c.todos.map((e) => e.id), ['dated']);
  });

  test('自动完成只作用于有截止且到期的待办，设置独立', () async {
    final c = await controller([
      task('late', 0, due: DateTime(2026, 11, 3)),
      task('no-date', 1),
      task('future', 2, due: DateTime(2026, 11, 8)),
    ]);
    addTearDown(c.dispose);
    await c.updateSettings(c.settings.copyWith(autoCompleteTodos: true));
    expect(c.todos.where((e) => e.completed).map((e) => e.id), ['late']);
    expect(c.settings.autoCompleteExpired, false);
  });

  test('SQLite持久化待办顺序、共享自动完成及旧共享设置兼容', () async {
    final db = CalendarDatabase(NativeDatabase.memory());
    final repo = SqliteScheduleRepository(db);
    final store = SqliteSyncStore(db);
    addTearDown(db.close);
    await store.initialize();
    await repo.saveEvents([task('a', 1), task('b', 0)]);
    expect(
      orderedTodos(
        await repo.loadEvents(),
        const AppSettings(),
      ).map((e) => e.id),
      ['b', 'a'],
    );
    await repo.saveSettings(const AppSettings(autoCompleteTodos: true));
    final sent = await store.pendingPreferences();
    expect(sent!['autoCompleteTodos'], true);
    await store.applyPreferences({'autoCompleteExpired': true}, sent);
    expect((await repo.loadSettings()).autoCompleteTodos, true);
    await store.applyPreferences({
      'autoCompleteExpired': false,
      'autoCompleteTodos': false,
    }, null);
    expect((await repo.loadSettings()).autoCompleteTodos, false);
  });

  testWidgets('手机创建无时间待办、颜色与备注一屏表单', (t) async {
    viewport(t, const Size(390, 844));
    final c = await controller([], t);
    addTearDown(c.dispose);
    await t.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openTodoEditor(context, c),
            child: const Text('创建'),
          ),
        ),
      ),
    );
    await t.tap(find.text('创建'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, '名称'), '整理材料');
    await t.enterText(find.widgetWithText(TextFormField, '备注'), '无固定时间');
    expect(find.text('未完成颜色'), findsOneWidget);
    await t.tap(find.text('保存'));
    await t.pumpAndSettle();
    expect(c.todos.single.title, '整理材料');
    expect(c.todos.single.deadline, isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('手机六项底栏、首页待办与设置入口无溢出', (t) async {
    viewport(t, const Size(390, 844));
    final c = await controller([task('a', 0)], t);
    addTearDown(c.dispose);
    await t.pumpWidget(testApp(AppShell(controller: c)));
    await t.pumpAndSettle();
    expect(find.text('下一项待办'), findsOneWidget);
    final nav = find.byType(NavigationBar);
    expect((t.widget<NavigationBar>(nav)).destinations.length, 6);
    await t.tap(find.descendant(of: nav, matching: find.text('待办')));
    await t.pumpAndSettle();
    expect(find.text('排序方式'), findsOneWidget);
    expect(find.text('待办a'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('批量混合选择禁用完成状态按钮，筛选后可操作', (t) async {
    viewport(t, const Size(900, 800));
    final c = await controller([
      task('a', 0),
      task('b', 1, completed: true),
    ], t);
    addTearDown(c.dispose);
    await t.pumpWidget(
      testApp(
        AnimatedBuilder(
          animation: c,
          builder: (_, _) => TodosPage(controller: c),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('全部'));
    await t.pumpAndSettle();
    await t.tap(find.text('多选'));
    await t.pumpAndSettle();
    await t.tap(find.text('全选'));
    await t.pumpAndSettle();
    expect(
      t.widget<TextButton>(find.widgetWithText(TextButton, '完成')).onPressed,
      isNull,
    );
    expect(
      t.widget<TextButton>(find.widgetWithText(TextButton, '未完成')).onPressed,
      isNull,
    );
    await t.tap(find.widgetWithText(ChoiceChip, '未完成'));
    await t.pumpAndSettle();
    await t.tap(find.text('全选'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, '完成'));
    await t.pumpAndSettle();
    expect(c.todos.every((e) => e.completed), true);
    expect(t.takeException(), isNull);
  });

  testWidgets('首页全部待办弹窗跳转并动画定位远处事项', (t) async {
    viewport(t, const Size(1280, 800));
    final c = await controller([for (var i = 0; i < 40; i++) task('$i', i)], t);
    addTearDown(c.dispose);
    await t.pumpWidget(testApp(AppShell(controller: c)));
    await t.pumpAndSettle();
    await t.tap(find.text('查看待办'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('待办35'),
      450,
      scrollable: find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.tap(find.text('待办35'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('待办35'), findsOneWidget);
    expect(t.getCenter(find.text('待办35')).dy, inInclusiveRange(150, 700));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('目标待办滚动到深处、长备注及大字布局', (t) async {
    viewport(t, const Size(390, 844));
    final c = await controller([for (var i = 0; i < 40; i++) task('$i', i)], t);
    addTearDown(c.dispose);
    final key = GlobalKey<TodosPageState>();
    await t.pumpWidget(
      testApp(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.6),
          ),
          child: TodosPage(key: key, controller: c),
        ),
      ),
    );
    await t.pumpAndSettle();
    key.currentState!.focusTask('35');
    await t.pumpAndSettle();
    expect(find.text('待办35'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });

  for (final mode in ['月', '周']) {
    testWidgets('连续快速十次$mode翻页不丢失或回跳', (t) async {
      viewport(t, const Size(1280, 1000));
      final c = await controller([], t);
      addTearDown(c.dispose);
      var selected = DateTime(2026, 1, 1);
      await t.pumpWidget(
        testApp(
          StatefulBuilder(
            builder: (_, setState) => SingleChildScrollView(
              child: CalendarPage(
                controller: c,
                selectedDate: selected,
                onSelect: (day) => setState(() => selected = day),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      if (mode == '周') {
        await t.tap(find.text('周'));
        await t.pumpAndSettle();
      }
      final next = find.byIcon(Icons.chevron_right);
      for (var i = 0; i < 10; i++) {
        await t.tap(next);
        await t.pump(const Duration(milliseconds: 35));
      }
      await t.pumpAndSettle();
      expect(
        find.text(mode == '月' ? '2026年11月' : '2026年3月9日—3月15日'),
        findsOneWidget,
      );
      for (var i = 0; i < 10; i++) {
        await t.tap(find.byIcon(Icons.chevron_left));
        await t.pump(const Duration(milliseconds: 20));
      }
      await t.pumpAndSettle();
      expect(
        find.text(mode == '月' ? '2026年1月' : '2025年12月29日—1月4日'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });
  }

  for (final phone in [false, true]) {
    testWidgets('${phone ? '手机长按' : '桌面开关'}拖动重排，边缘滚动及倒序保存', (t) async {
      viewport(t, Size(phone ? 390 : 1000, 844));
      final c = await controller([
        for (var i = 0; i < 15; i++) task('$i', i),
      ], t);
      addTearDown(c.dispose);
      await t.pumpWidget(
        testApp(
          AnimatedBuilder(
            animation: c,
            builder: (_, _) => TodosPage(controller: c),
          ),
        ),
      );
      await t.pumpAndSettle();
      if (!phone) {
        await t.tap(find.byType(Switch));
        await t.pumpAndSettle();
      }
      final first = find.byKey(const ValueKey('todo-row-0'));
      final gesture = await t.startGesture(
        t.getCenter(first),
        kind: phone ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
      );
      await t.pump(Duration(milliseconds: phone ? 600 : 50));
      await gesture.moveBy(const Offset(0, 180));
      await t.pump(const Duration(milliseconds: 400));
      final list = find.byKey(const ValueKey('todos-list'));
      await gesture.moveTo(
        Offset(t.getCenter(first).dx, t.getBottomLeft(list).dy - 8),
      );
      await t.pump(const Duration(milliseconds: 900));
      await gesture.up();
      await t.pumpAndSettle();
      expect(c.todos.first.id, isNot('0'));
      expect(c.todos.indexWhere((e) => e.id == '0'), greaterThan(3));
      final ascending = c.todos.map((e) => e.id).toList();
      await t.tap(find.byTooltip('正序，点击切换倒序'));
      await t.pumpAndSettle();
      expect(c.todos.map((e) => e.id), ascending.reversed);
      await c.reloadSyncedEvents();
      expect(c.todos.map((e) => e.id), ascending.reversed);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('有截止待办日历可选中显示备注、无边界手柄', (t) async {
    viewport(t, const Size(1280, 1000));
    final c = await controller([
      task('a', 0, due: DateTime(2026, 11, 5, 10)),
    ], t);
    addTearDown(c.dispose);
    await t.pumpWidget(
      testApp(
        SingleChildScrollView(
          child: CalendarPage(
            controller: c,
            selectedDate: DateTime(2026, 11, 5),
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('周'));
    await t.pumpAndSettle();
    final block = find.byKey(const ValueKey('interaction-a-2026-11-05'));
    await t.ensureVisible(block);
    await t.tap(block);
    await t.pumpAndSettle();
    expect(find.textContaining('备注a'), findsWidgets);
    final interaction = t.widget<CalendarEventInteraction>(block);
    expect(interaction.point, true);
    expect(interaction.resizable, false);
    expect(
      find.byKey(const ValueKey('calendar-delete-selected')),
      findsOneWidget,
    );
    final gesture = await t.startGesture(
      t.getCenter(block),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 60));
    await t.pump();
    await gesture.up();
    await t.pumpAndSettle();
    expect(c.todos.single.deadline, DateTime(2026, 11, 5, 11));
    expect(t.takeException(), isNull);
  });
}
