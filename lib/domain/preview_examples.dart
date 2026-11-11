import '../data/repository.dart';
import 'models.dart';

/// One-off fixtures for the isolated preview database, including tombstones.
Future<void> seedPreviewData(
  ScheduleRepository repository,
  DateTime now,
) async {
  final existing = await repository.loadEvents();
  if (existing.any((e) => e.id.startsWith('preview074-demo-'))) return;
  final order = existing
      .where((e) => e.isTodo)
      .fold<int>(0, (v, e) => v > e.todoOrder + 10 ? v : e.todoOrder + 10);
  await repository.saveEvents(previewExamples(now, todoOrder: order));
}

List<ScheduleEvent> previewExamples(DateTime now, {int todoOrder = 0}) {
  final today = dayOnly(now), stamp = now.toUtc();
  DateTime at(int day, int hour, [int minute = 0]) =>
      DateTime(today.year, today.month, today.day + day, hour, minute);
  ScheduleEvent schedule(
    String id,
    String title,
    DateTime start,
    DateTime end, {
    int color = 0xFFE4EAD9,
    bool done = false,
    bool allDay = false,
    String notes = '预览示例，可自由编辑或删除。',
    RecurrenceRule? rule,
    ItemAutomation automation = const ItemAutomation(),
  }) => ScheduleEvent(
    id: 'preview074-demo-$id',
    title: '示例·$title',
    notes: notes,
    start: start,
    end: end,
    color: color,
    completed: done,
    allDay: allDay,
    updatedAt: stamp,
    reminderOffsets: const [],
    reminderSound: false,
    recurrence: rule,
    automation: automation,
  );
  ScheduleEvent todo(
    String id,
    String title, {
    DateTime? deadline,
    bool done = false,
    int offset = 0,
    TodoRepeatRule? rule,
    ItemAutomation automation = const ItemAutomation(),
  }) => ScheduleEvent(
    id: 'preview074-demo-$id',
    title: '示例·$title',
    notes: '预览示例。可以尝试完成、排序、复制及修改自动处理规则。',
    isTodo: true,
    hasDeadline: deadline != null,
    taskCreatedAt: stamp,
    todoOrder: todoOrder + offset,
    start: rule != null ? today : deadline ?? today,
    end: rule != null ? today : deadline ?? today,
    completed: done,
    color: 0xFFE8E0F0,
    updatedAt: stamp,
    reminderOffsets: const [],
    reminderSound: false,
    todoRepeat: rule,
    automation: automation,
  );
  return [
    schedule('overdue', '昨日未完成', at(-1, 14), at(-1, 15), color: 0xFFF1DED3),
    schedule('done', '已完成的晨间整理', at(0, 7), at(0, 8), done: true),
    schedule(
      'ongoing',
      '正在进行的阅读',
      now.subtract(const Duration(minutes: 20)),
      now.add(const Duration(minutes: 40)),
      notes: '这是进行中示例，包含较长备注，便于观察选中后的省略和详情显示。',
    ),
    schedule(
      'next',
      '下一场讨论',
      now.add(const Duration(minutes: 90)),
      now.add(const Duration(minutes: 150)),
      color: 0xFFDDE8F1,
      automation: const ItemAutomation(completeExpired: true),
    ),
    schedule(
      'overlap',
      '重叠的资料整理',
      now.add(const Duration(minutes: 110)),
      now.add(const Duration(minutes: 170)),
      color: 0xFFF2DFDC,
    ),
    schedule(
      'point',
      '寄出文件（时间点）',
      now.add(const Duration(minutes: 120)),
      now.add(const Duration(minutes: 120)),
      color: 0xFFF0E5C8,
    ),
    schedule('overnight', '跨日观测', at(0, 23), at(1, 1), color: 0xFFDEDDF0),
    schedule('allday', '全天外出', at(1, 0), at(2, 0), allDay: true),
    schedule(
      'repeat',
      '每日习惯',
      at(0, 9),
      at(0, 9, 30),
      notes: '组备注：每天两个节点，可以单独调整。',
      rule: RecurrenceRule(
        frequency: RepeatFrequency.daily,
        until: at(14, 23, 59),
        nodes: const [
          RecurrenceNode(
            id: 'morning',
            title: '晨间计划',
            minute: 540,
            durationMinutes: 30,
            notes: '节点备注：先安排最重要的事。',
            reminderOffsets: [],
            reminderSound: false,
          ),
          RecurrenceNode(
            id: 'evening',
            title: '晚间复盘',
            minute: 1260,
            durationMinutes: 20,
            color: 0xFFE8E0F0,
            reminderOffsets: [],
            reminderSound: false,
          ),
        ],
      ),
    ),
    schedule(
      'cycle',
      '三日学习周期',
      at(0, 10),
      at(0, 11),
      rule: RecurrenceRule(
        frequency: RepeatFrequency.interval,
        intervalDays: 3,
        kind: RepeatKind.cycle,
        until: at(14, 23, 59),
        nodes: const [
          RecurrenceNode(
            id: 'day1',
            title: '学习',
            minute: 600,
            reminderOffsets: [],
            reminderSound: false,
          ),
          RecurrenceNode(
            id: 'day2',
            title: '跨日练习',
            dayOffset: 1,
            minute: 1410,
            durationMinutes: 90,
            color: 0xFFDDE8F1,
            reminderOffsets: [],
            reminderSound: false,
          ),
        ],
      ),
    ),
    todo('todo-plain', '没有截止时间的购物清单'),
    todo(
      'todo-deadline',
      '提交报告',
      deadline: now.add(const Duration(hours: 3)),
      offset: 1,
      automation: const ItemAutomation(completeExpired: true),
    ),
    todo('todo-overdue', '逾期待处理资料', deadline: at(-1, 18), offset: 2),
    todo('todo-done', '已完成的备份', deadline: at(0, 8), done: true, offset: 3),
    todo(
      'todo-repeat',
      '每日维护',
      offset: 4,
      rule: const TodoRepeatRule(
        nodes: [
          TodoRepeatNode(
            deadlineMinutes: 18 * 60,
            item: RecurrenceNode(
              id: 'inbox',
              title: '清理收件箱',
              minute: 0,
              durationMinutes: 0,
              reminderOffsets: [],
              reminderSound: false,
              automation: ItemAutomation(completeExpired: true),
            ),
          ),
          TodoRepeatNode(
            removeAfterCycle: false,
            item: RecurrenceNode(
              id: 'review',
              title: '整理笔记',
              minute: 0,
              durationMinutes: 0,
              color: 0xFFDDE8F1,
              notes: '本项保留历史周期，可观察每项独立设置。',
              reminderOffsets: [],
              reminderSound: false,
            ),
          ),
        ],
      ),
    ),
    todo(
      'todo-weekly',
      '每周盘点',
      offset: 6,
      rule: const TodoRepeatRule(
        frequency: RepeatFrequency.weekly,
        nodes: [
          TodoRepeatNode(
            deadlineMinutes: 2 * 1440 + 17 * 60,
            item: RecurrenceNode(
              id: 'inventory',
              title: '补充耗材',
              minute: 0,
              durationMinutes: 0,
              reminderOffsets: [],
              reminderSound: false,
            ),
          ),
        ],
      ),
    ),
  ];
}
