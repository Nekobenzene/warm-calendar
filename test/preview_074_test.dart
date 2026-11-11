import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/domain/todos.dart';
import 'package:warm_calendar/domain/recurrence.dart';
import 'package:warm_calendar/domain/calendar_service.dart';
import 'package:warm_calendar/domain/preview_examples.dart';
import 'package:warm_calendar/ui/todo_editor.dart';
import 'package:warm_calendar/ui/node_editor.dart';
import 'package:warm_calendar/ui/event_form.dart';
import 'package:warm_calendar/ui/calendar_page.dart';
import 'package:warm_calendar/ui/shell.dart';
import 'package:warm_calendar/ui/schedules_page.dart';
import 'package:warm_calendar/ui/item_context_menu.dart';
import 'package:warm_calendar/ui/motion.dart';
import 'calendar_interaction_test.dart' as calendar;
import 'recurrence_test.dart' show testApp;
import 'todos_test.dart' as todos;
import 'repeating_todos_test.dart' as repeat;

ScheduleEvent event(
  String id, {
  bool todo = false,
  ItemAutomation automation = const ItemAutomation(),
}) => ScheduleEvent(
  id: id,
  title: id,
  notes: '备注$id',
  start: DateTime(2026, 11, 4, 9),
  end: DateTime(2026, 11, 4, todo ? 9 : 10),
  taskCreatedAt: todo ? DateTime.utc(2026, 11, 4) : null,
  updatedAt: DateTime.utc(2026, 11, 4),
  isTodo: todo,
  hasDeadline: todo,
  automation: automation,
);
void main() {
  testWidgets('预览示例格式有效且仅加入一次，删除后不复活', (t) async {
    final c = await todos.controller([], t);
    addTearDown(c.dispose);
    final now = DateTime(2026, 11, 11, 15);
    await seedPreviewData(c.repository, now);
    final items = await c.repository.loadEvents();
    expect(items, hasLength(16));
    for (final item in items) {
      ScheduleEvent.fromJson(item.toJson());
      if (item.recurrence != null) {
        expandSeries(item, c.calendar, validate: true);
      }
    }
    expect(resolveTodos(items, c.calendar, now).length, greaterThan(5));
    await c.repository.saveEvents(
      items.map((e) => e.copyWith(deleted: true)).toList(),
    );
    await seedPreviewData(c.repository, now.add(const Duration(days: 1)));
    expect((await c.repository.loadEvents()).every((e) => e.deleted), true);
  });
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
  for (final phone in [false, true]) {
    testWidgets('${phone ? '手机' : '桌面'}首页新增查看日程与日历选中布局', (t) async {
      todos.viewport(t, Size(phone ? 390 : 1280, phone ? 844 : 800));
      final c = await todos.controller([], t);
      addTearDown(c.dispose);
      c.now = dayOnly(DateTime.now()).add(const Duration(hours: 8));
      await c.saveEvent(
        event('下一个日程').copyWith(
          start: c.now.add(const Duration(hours: 1)),
          end: c.now.add(const Duration(hours: 2)),
        ),
      );
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: testApp(AppShell(controller: c)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('新增日程'), findsOneWidget);
      expect(find.text('查看日程'), findsOneWidget);
      if (phone) expect(find.widgetWithText(FilledButton, '新建'), findsNothing);
      await repeat.capture(
        t,
        'preview-074-home-${phone ? 'mobile' : 'desktop'}',
      );
      if (!phone) {
        await t.tap(find.byKey(const ValueKey('desktop-new-todo')));
        await t.pumpAndSettle();
        expect(find.byType(TodoEditor), findsOneWidget);
        await t.tap(find.text('取消').last);
        await t.pumpAndSettle();
      }
      await t.tap(find.text('查看日程'));
      await t.pumpAndSettle();
      expect(find.byType(SchedulesPage), findsOneWidget);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: testApp(
            SingleChildScrollView(
              child: CalendarPage(
                controller: c,
                selectedDate: c.now,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('周'));
      await t.pumpAndSettle();
      final item = find.byKey(ValueKey('interaction-下一个日程-${dateKey(c.now)}'));
      await t.ensureVisible(item);
      await t.pumpAndSettle();
      await t.tap(item);
      await t.pumpAndSettle();
      await repeat.capture(
        t,
        'preview-074-calendar-${phone ? 'mobile' : 'desktop'}',
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  test('自动处理独立配置、重复节点与备份往返', () {
    const rule = ItemAutomation(completeExpired: true, deleteCompleted: true);
    final root = event('root').copyWith(
      recurrence: RecurrenceRule(
        frequency: RepeatFrequency.daily,
        until: DateTime(2026, 11, 5),
        nodes: [const RecurrenceNode(id: 'n', automation: rule)],
      ),
    );
    final loaded = ScheduleEvent.fromJson(root.toJson());
    expect(
      expandSeries(
        loaded,
        CalendarService(),
      ).every((e) => e.automation.deleteCompleted),
      true,
    );
    final group = repeat.group(
      nodes: [
        TodoRepeatNode(item: repeat.node('n').item.copyWith(automation: rule)),
      ],
    );
    expect(
      resolveTodos(
        [ScheduleEvent.fromJson(group.toJson())],
        CalendarService(),
        DateTime(2026, 11, 5),
      ).single.automation.completeExpired,
      true,
    );
    expect(
      ScheduleEvent.fromJson(
        event('old').toJson()..remove('automation'),
      ).automation.completeExpired,
      false,
    );
  });
  testWidgets('逐项逾期完成、完成删除、一次性逾期删除与重复例外', (t) async {
    final c = await todos.controller([], t);
    addTearDown(c.dispose);
    await c.saveEvent(event('keep'));
    await c.saveEvent(
      event('done', automation: const ItemAutomation(completeExpired: true)),
    );
    await c.saveEvent(
      event(
        'gone',
        todo: true,
        automation: const ItemAutomation(deleteExpired: true),
      ),
    );
    await c.saveEvent(
      event('manual', automation: const ItemAutomation(deleteCompleted: true)),
    );
    expect(c.events.singleWhere((e) => e.id == 'done').completed, true);
    expect(c.todos.any((e) => e.id == 'gone'), false);
    await c.toggleCompleted(c.events.singleWhere((e) => e.id == 'manual'));
    expect(c.events.any((e) => e.id == 'manual'), false);
    await c.saveEvent(
      repeat.group(
        start: DateTime(2026, 11, 4),
        nodes: [
          TodoRepeatNode(
            deadlineMinutes: 9 * 60,
            item: repeat
                .node('n', deadline: 9 * 60)
                .item
                .copyWith(
                  automation: const ItemAutomation(
                    completeExpired: true,
                    deleteCompleted: true,
                  ),
                ),
          ),
        ],
      ),
    );
    expect(c.todos, isEmpty);
    await c.refreshTime(at: DateTime(2026, 11, 5, 8));
    expect(c.todos, hasLength(1));
    expect(c.todos.single.completed, false);
    await c.reloadSyncedEvents();
    expect(c.events.singleWhere((e) => e.id == 'keep').completed, false);
  });
  testWidgets('两类剪贴板独立，剪切取消保留原项且保存原子删除单次', (t) async {
    final c = await todos.controller([], t);
    addTearDown(c.dispose);
    final a = event('a'), b = event('b', todo: true);
    await c.saveEvent(a);
    await c.saveEvent(b);
    c.copyItem(a);
    c.copyItem(b, cut: true);
    final schedule = c.pasteDraft(false)!;
    expect(schedule.title, 'a');
    expect(schedule.isTodo, false);
    final cancelled = c.pasteDraft(true)!;
    c.discardPaste(cancelled.id);
    expect(c.todos.any((e) => e.id == 'b'), true);
    final task = c.pasteDraft(true)!;
    await c.saveEvent(task);
    expect(c.todos.any((e) => e.id == 'b'), false);
    expect(c.todos.single.notes, b.notes);
    await c.saveEvent(schedule);
    expect(c.events, hasLength(2));
    await c.saveEvent(repeat.group(start: DateTime(2026, 11, 4)));
    final child = c.todos.firstWhere((e) => e.seriesId != null);
    c.copyItem(child, cut: true);
    final single = c.pasteDraft(true)!;
    expect(single.seriesId, isNull);
    expect(single.todoRepeat, isNull);
    await c.saveEvent(single);
    expect(c.todos.any((e) => e.id == child.id), false);
    await c.refreshTime(at: DateTime(2026, 11, 5));
    expect(c.todos.where((e) => e.seriesId != null), hasLength(2));
  });
  testWidgets('粘贴到组子项只映射兼容字段，剪切源变更时拒绝删除', (t) async {
    final c = await todos.controller([], t);
    addTearDown(c.dispose);
    final a = event('a');
    await c.saveEvent(a);
    c.copyItem(a, cut: true);
    final draft = c.pasteDraft(false)!;
    final root = event('root').copyWith(
      recurrence: RecurrenceRule(
        frequency: RepeatFrequency.daily,
        until: DateTime(2026, 11, 6),
        nodes: [
          RecurrenceNode(id: 'n', title: draft.title, pasteDraftId: draft.id),
        ],
      ),
    );
    await c.saveEvent(root);
    expect(c.events.any((e) => e.id == 'a'), false);
    final copiedAgain = c.pasteDraft(false)!;
    expect(copiedAgain.title, a.title);
    expect(copiedAgain.recurrence, isNull);
    c.discardPaste(copiedAgain.id);
    final source = c.events.first;
    c.copyItem(source, cut: true);
    final stale = c.pasteDraft(false)!;
    await c.saveEvent(source.copyWith(notes: '已修改'));
    await expectLater(c.saveEvent(stale), throwsFormatException);
    expect(c.events.any((e) => e.id == source.id), true);
    expect(c.events.any((e) => e.id == stale.id), false);
  });
  testWidgets('移动日历选中前后位置稳定，提供编辑完成且编辑器没有完成勾选', (t) async {
    await calendar.mountCalendar(t, phone: true);
    final grid = find.byKey(const ValueKey('time-grid-resolution'));
    final before = t.getTopLeft(calendar.block);
    await t.tap(calendar.block);
    await t.pumpAndSettle();
    expect(t.getTopLeft(calendar.block), before);
    expect(grid, findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-edit-selected')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-complete-selected')),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('calendar-edit-selected')));
    await t.pumpAndSettle();
    expect(find.byType(EventEditor), findsOneWidget);
    expect(find.text('已完成'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('重复节点时钟选择、固定所属日及自动处理设置可保存', (t) async {
    todos.viewport(t, const Size(390, 844));
    RecurrenceNode? saved;
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showAppDialog<RecurrenceNode>(
                  context: context,
                  builder: (_) => const NodeEditor(
                    initial: RecurrenceNode(id: 'n', dayOffset: 2),
                    days: 7,
                    fixedStartDay: true,
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
    expect(find.text('所属日'), findsOneWidget);
    final fixedDay = find.byKey(const ValueKey('node-fixed-start-day'));
    expect(fixedDay, findsOneWidget);
    expect(
      find.descendant(of: fixedDay, matching: find.text('Day3')),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    final time = find.widgetWithText(TextFormField, '开始时间');
    final endTime = find.widgetWithText(TextFormField, '结束时间');
    expect(t.getTopLeft(time).dx, t.getTopLeft(endTime).dx);
    expect(t.getSize(time).width, t.getSize(endTime).width);
    await repeat.capture(t, 'node-fixed-day-074-mobile');
    todos.viewport(t, const Size(1280, 800));
    await t.pumpAndSettle();
    expect(t.getTopLeft(time).dx, t.getTopLeft(endTime).dx);
    await repeat.capture(t, 'node-fixed-day-074-desktop');
    todos.viewport(t, const Size(390, 844));
    await t.pumpAndSettle();
    await t.ensureVisible(time);
    await t.tap(time);
    await t.pumpAndSettle();
    expect(
      t
          .widget<TimePickerDialog>(find.byType(TimePickerDialog))
          .initialEntryMode,
      TimePickerEntryMode.dial,
    );
    await t.tap(find.text('取消').last);
    await t.pumpAndSettle();
    final option = find.text('完成后自动删除');
    await t.ensureVisible(option);
    await t.tap(find.byType(Checkbox).at(1));
    await t.pumpAndSettle();
    await t.tap(find.text('保存节点'));
    await t.pumpAndSettle();
    expect(saved?.dayOffset, 2);
    expect(saved?.automation.deleteCompleted, true);
    expect(t.takeException(), isNull);
  });
  testWidgets('右键复制菜单与分类粘贴入口可用', (t) async {
    final c = await todos.controller([], t);
    addTearDown(c.dispose);
    final a = event('a');
    await c.saveEvent(a);
    await t.pumpWidget(
      testApp(
        ItemContextMenu(
          controller: c,
          event: a,
          child: const SizedBox(width: 300, height: 200, child: Text('卡片')),
        ),
      ),
    );
    final g = await t.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await g.down(t.getCenter(find.text('卡片')));
    await g.up();
    await t.pumpAndSettle();
    await t.tap(find.text('复制'));
    await t.pumpAndSettle();
    expect(c.clipboard.entry(false)?.item.id, 'a');
    expect(c.clipboard.entry(true), isNull);
    expect(t.takeException(), isNull);
  });
}
