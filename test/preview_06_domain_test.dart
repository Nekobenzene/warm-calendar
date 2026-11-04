import 'package:flutter_test/flutter_test.dart';
import 'package:warm_calendar/app_controller.dart';
import 'package:warm_calendar/domain/calendar_service.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/domain/recurrence.dart';
import 'package:warm_calendar/domain/reminders.dart';
import 'prototype_test.dart' show MemoryRepository;

ScheduleEvent cycle({
  RepeatKind kind = RepeatKind.cycle,
  RepeatFrequency frequency = RepeatFrequency.interval,
  DateTime? start,
  DateTime? until,
  int? count = 2,
  bool weekLabels = false,
  int interval = 3,
  List<RecurrenceNode> nodes = const [
    RecurrenceNode(id: 'a', title: '晚班', minute: 1380, durationMinutes: 120),
    RecurrenceNode(id: 'b', dayOffset: 1, minute: 600, durationMinutes: 0),
  ],
}) => ScheduleEvent(
  id: 'cycle',
  title: '值班',
  notes: '全局备注',
  start: start ?? DateTime(2026, 1, 1),
  end: (start ?? DateTime(2026, 1, 1)).add(const Duration(hours: 2)),
  updatedAt: DateTime.utc(2026),
  recurrence: RecurrenceRule(
    kind: kind,
    frequency: frequency,
    until: until ?? DateTime(2026, 1, 31),
    intervalDays: interval,
    cycleCount: count,
    nodes: nodes,
    weekLabels: weekLabels,
    weekdays: const [1, 3],
    monthDays: const [1, 15],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('多日周期、跨午夜节点、独立提醒颜色以及组合文本往返', () {
    final root = cycle(
      nodes: const [
        RecurrenceNode(
          id: 'a',
          title: '晚班',
          notes: '节点备注',
          minute: 1380,
          durationMinutes: 120,
          color: 0x80778899,
          reminderOffsets: [30, 0],
        ),
        RecurrenceNode(id: 'b', dayOffset: 1, minute: 600, durationMinutes: 0),
      ],
    );
    final restored = ScheduleEvent.fromJson(root.toJson());
    final rows = expandSeries(restored, CalendarService(), validate: true);
    expect(rows, hasLength(4));
    expect(rows.first.title, '值班-晚班');
    expect(rows.first.notes, '节点备注\n全局备注');
    expect(rows.first.start, DateTime(2026, 1, 1, 23));
    expect(rows.first.end, DateTime(2026, 1, 2, 1));
    expect(rows[1].isPoint, true);
    expect(rows[2].start, DateTime(2026, 1, 4, 23));
    expect(rows.first.color, 0x80778899);
    expect(rows.first.reminderOffsets, [30, 0]);
    expect(
      reminderBody(
        rows.first,
        rows.first.start.subtract(const Duration(minutes: 30)),
      ),
      contains('节点备注\n全局备注'),
    );
    expect(ScheduleEvent.fromJson(rows.first.toJson()).nodeId, 'a');
  });
  test('每周周名、月末缺日、停止日期与轮数边界', () {
    final weekly = expandSeries(
      cycle(
        frequency: RepeatFrequency.weekly,
        start: DateTime(2026, 1, 7),
        weekLabels: true,
        nodes: const [
          RecurrenceNode(id: 'mon', minute: 540),
          RecurrenceNode(id: 'sun', dayOffset: 6, minute: 600),
        ],
      ),
      CalendarService(),
      validate: true,
    );
    expect(weekly.map((e) => dateKey(e.start)), [
      '2026-01-11',
      '2026-01-12',
      '2026-01-18',
    ]);
    final monthly = expandSeries(
      cycle(
        frequency: RepeatFrequency.monthly,
        start: DateTime(2026, 1, 1),
        until: DateTime(2026, 4, 30),
        count: 3,
        nodes: const [RecurrenceNode(id: 'end', dayOffset: 30, minute: 540)],
      ),
      CalendarService(),
      validate: true,
    );
    expect(monthly.map((e) => dateKey(e.start)), ['2026-01-31', '2026-03-31']);
    final stopped = expandSeries(
      cycle(until: DateTime(2026, 1, 4), count: null),
      CalendarService(),
      validate: true,
    );
    expect(stopped, hasLength(3));
  });
  test('新增继承设置但获得独立ID，编辑时间不复活已删除实例', () async {
    const old = RecurrenceNode(
      id: 'old',
      legacyMinute: 540,
      minute: 540,
      color: 0x80aabbcc,
      reminderOffsets: [60, 5],
    );
    final added = old.copyWith(id: 'new', title: '', notes: '');
    expect(added.legacyMinute, isNull);
    expect(added.color, old.color);
    expect(added.reminderOffsets, old.reminderOffsets);
    final root = cycle(
      kind: RepeatKind.event,
      frequency: RepeatFrequency.daily,
      nodes: [old, added],
    );
    final c = AppController(
      repository: MemoryRepository(),
      calendar: CalendarService(),
    );
    await c.initialize(startTimer: false);
    addTearDown(c.dispose);
    await c.saveEvent(root);
    expect(c.events.map((e) => e.id).toSet(), hasLength(4));
    final key = c.events.firstWhere((e) => e.nodeId == 'new').id;
    await c.deleteEvent(c.events.firstWhere((e) => e.id == key));
    await c.saveEvent(
      root.copyWith(
        recurrence: root.recurrence!.copyWith(
          nodes: [old, added.copyWith(minute: 800)],
        ),
      ),
    );
    expect(c.events.where((e) => e.id == key), isEmpty);
    expect(c.events.where((e) => e.nodeId == 'new'), hasLength(1));
  });
  test('七类假期筛选、重合归类与调休上班', () {
    final c = CalendarService()
      ..loadHolidayJson({
        'year': 2026,
        'days': [
          {'date': '2026-01-03', 'name': '元旦', 'isOffDay': true},
          {'date': '2026-01-04', 'name': '调休', 'isOffDay': false},
        ],
      });
    final saturday = DateTime(2026, 1, 3), sunday = DateTime(2026, 1, 4);
    for (final p in HolidayPolicy.values) {
      expect(
        c.allowsDate(saturday, p, WeekendHolidayPriority.holiday),
        switch (p) {
          HolidayPolicy.ignore ||
          HolidayPolicy.only ||
          HolidayPolicy.onlyHolidays ||
          HolidayPolicy.skipWeekends => true,
          _ => false,
        },
      );
      expect(
        c.allowsDate(saturday, p, WeekendHolidayPriority.weekend),
        switch (p) {
          HolidayPolicy.ignore ||
          HolidayPolicy.only ||
          HolidayPolicy.onlyWeekends ||
          HolidayPolicy.skipHolidays => true,
          _ => false,
        },
      );
    }
    expect(
      c.allowsDate(sunday, HolidayPolicy.skip, WeekendHolidayPriority.holiday),
      true,
    );
    expect(
      c.allowsDate(
        sunday,
        HolidayPolicy.onlyWeekends,
        WeekendHolidayPriority.weekend,
      ),
      false,
    );
  });
  test('节点范围、重复ID、超长跨日与未知假期不能静默通过', () {
    for (final kind in RepeatKind.values) {
      expect(
        () => expandSeries(
          cycle(
            kind: kind,
            nodes: const [RecurrenceNode(id: 'a', durationMinutes: 5000)],
          ),
          CalendarService(),
          validate: true,
        ),
        throwsFormatException,
      );
      expect(
        () => expandSeries(
          cycle(
            kind: kind,
            nodes: const [
              RecurrenceNode(id: 'a'),
              RecurrenceNode(id: 'a'),
            ],
          ),
          CalendarService(),
        ),
        throwsFormatException,
      );
      expect(
        () => expandSeries(
          cycle(
            kind: kind,
            frequency: RepeatFrequency.daily,
            start: DateTime(2026, 12, 31),
            until: DateTime(2027, 12, 31),
            count: 3,
            nodes: const [
              RecurrenceNode(
                id: 'a',
                holidayPolicy: HolidayPolicy.onlyHolidays,
              ),
            ],
          ),
          CalendarService()..holidayYears.add(2026),
          validate: true,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => const RecurrenceNode(id: 'bad', legacyMinute: 1440).validate(1),
      throwsFormatException,
    );
  });
  test('空的过滤节点不妨碍其他节点保存，周末规则可脱离未来假期表', () {
    final root = cycle(
      kind: RepeatKind.event,
      frequency: RepeatFrequency.daily,
      start: DateTime(2027, 1, 4),
      until: DateTime(2027, 1, 5),
      count: 2,
      nodes: const [
        RecurrenceNode(
          id: 'weekend',
          holidayPolicy: HolidayPolicy.onlyWeekends,
        ),
        RecurrenceNode(id: 'work'),
      ],
    );
    expect(
      expandSeries(
        root,
        CalendarService(),
        validate: true,
      ).map((e) => e.nodeId),
      ['work', 'work'],
    );
  });
  test('两类重复整组边界调整只改变目标节点时长，例外和原子失败保留', () async {
    for (final kind in RepeatKind.values) {
      final c = AppController(
        repository: MemoryRepository(),
        calendar: CalendarService(),
      );
      await c.initialize(startTimer: false);
      addTearDown(c.dispose);
      await c.saveEvent(
        cycle(
          kind: kind,
          nodes: const [
            RecurrenceNode(id: 'a', minute: 540),
            RecurrenceNode(id: 'b', minute: 660, durationMinutes: 120),
          ],
        ),
      );
      final second = c.events.firstWhere((e) => e.nodeId == 'b');
      await c.moveEvent(
        second,
        second.start,
        newEnd: second.end.add(const Duration(minutes: 30)),
        entireSeries: true,
      );
      expect(
        c.events
            .where((e) => e.nodeId == 'a')
            .every((e) => e.end.difference(e.start).inMinutes == 60),
        true,
      );
      expect(
        c.events
            .where((e) => e.nodeId == 'b')
            .every((e) => e.end.difference(e.start).inMinutes == 150),
        true,
      );
      final before = c.events.map((e) => e.toJson()).toList();
      await expectLater(
        c.moveEvent(
          c.events.first,
          c.events.first.start,
          newEnd: c.events.first.start.subtract(const Duration(minutes: 1)),
          entireSeries: true,
        ),
        throwsFormatException,
      );
      expect(c.events.map((e) => e.toJson()).toList(), before);
    }
  });
}
