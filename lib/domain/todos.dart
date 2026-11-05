import 'models.dart';
import 'calendar_service.dart';

// Calendar-day arithmetic avoids shifting deadlines at DST boundaries.
({DateTime start, DateTime end})? todoCycleAt(ScheduleEvent root, DateTime at) {
  final rule = root.todoRepeat!;
  final first = dayOnly(root.start);
  if (at.isBefore(first)) return null;
  if (rule.frequency == RepeatFrequency.monthly) {
    DateTime boundary(int index) {
      final month = DateTime(first.year, first.month + index);
      final lastDay = DateTime(month.year, month.month + 1, 0).day;
      return DateTime(month.year, month.month, first.day.clamp(1, lastDay));
    }

    var index = (at.year - first.year) * 12 + at.month - first.month;
    if (boundary(index).isAfter(at)) index--;
    return (start: boundary(index), end: boundary(index + 1));
  }
  final days = DateTime.utc(
    at.year,
    at.month,
    at.day,
  ).difference(DateTime.utc(first.year, first.month, first.day)).inDays;
  final offset = days ~/ rule.periodDays * rule.periodDays;
  return (
    start: DateTime(first.year, first.month, first.day + offset),
    end: DateTime(
      first.year,
      first.month,
      first.day + offset + rule.periodDays,
    ),
  );
}

List<ScheduleEvent> resolveTodos(
  List<ScheduleEvent> records,
  CalendarService calendar,
  DateTime at, {
  bool validate = false,
  bool includeSingles = true,
  bool includePastCycles = true,
}) {
  final overrides = {
    for (final e in records.where((e) => e.isTodo && e.seriesId != null))
      e.id: e,
  };
  final result = <ScheduleEvent>[
    if (includeSingles)
      ...records.where(
        (e) =>
            e.isTodo &&
            !e.deleted &&
            e.todoRepeat == null &&
            e.seriesId == null,
      ),
  ];
  for (final root in records.where(
    (e) => e.isTodo && !e.deleted && e.todoRepeat != null,
  )) {
    final currentCycle = todoCycleAt(root, at);
    if (currentCycle == null) continue;
    final rule = root.todoRepeat!;
    final cycles = [currentCycle];
    if (includePastCycles && rule.nodes.any((n) => !n.removeAfterCycle)) {
      var previous = todoCycleAt(root, dayOnly(root.start))!;
      while (previous.start.isBefore(currentCycle.start)) {
        cycles.add(previous);
        previous = todoCycleAt(root, previous.end)!;
      }
    }
    for (final cycle in cycles) {
      for (var i = 0; i < rule.nodes.length; i++) {
        final node = rule.nodes[i], n = node.item;
        if (cycle.start != currentCycle.start && node.removeAfterCycle) {
          continue;
        }
        final key = '${dateKey(cycle.start)}T0000~${n.id}';
        final id = '${root.id}::$key';
        final offset = node.deadlineMinutes;
        final requested = offset == null
            ? cycle.end
            : DateTime(
                cycle.start.year,
                cycle.start.month,
                cycle.start.day + offset ~/ 1440,
                offset % 1440 ~/ 60,
                offset % 60,
              );
        final deadline = requested.isAfter(cycle.end) ? cycle.end : requested;
        if (deadline.year > 2099) continue;
        final holidayDate = deadline == cycle.end
            ? DateTime(cycle.end.year, cycle.end.month, cycle.end.day - 1)
            : deadline;
        final allowed = calendar.allowsDate(
          holidayDate,
          rule.holidayPolicy,
          rule.weekendHolidayPriority,
        );
        if (allowed == null && validate) {
          throw FormatException('${holidayDate.year}年节假日未收录，请选择无视节假日或补充数据');
        }
        // Explicitly handled items remain stable if holiday data changes.
        final exception = overrides[id];
        if (exception != null) {
          if (!exception.deleted) result.add(exception);
          continue;
        }
        if (allowed != true) continue;
        result.add(
          ScheduleEvent(
            id: id,
            isTodo: true,
            hasDeadline: true,
            taskCreatedAt: root.createdAt.isAfter(cycle.start.toUtc())
                ? root.createdAt
                : cycle.start.toUtc(),
            todoOrder: root.todoOrder + i,
            todoCycleStart: cycle.start,
            title: combinedTitle(root.title, n.title),
            notes: [n.notes, root.notes].where((s) => s.isNotEmpty).join('\n'),
            start: deadline,
            end: deadline,
            updatedAt: root.updatedAt,
            revision: root.revision,
            seriesId: root.id,
            occurrenceKey: key,
            nodeId: n.id,
            color: n.color,
            completedColor: n.completedColor,
            reminderOffsets: n.reminderOffsets,
            reminderSound: n.reminderSound,
          ),
        );
      }
    }
  }
  return result;
}

List<ScheduleEvent> todoReminderEvents(
  List<ScheduleEvent> records,
  CalendarService calendar,
  DateTime now,
) {
  final result = {
    for (final e in resolveTodos(records, calendar, now)) e.id: e,
  };
  // System queues must include future cycles even if the app is closed.
  final horizon = now.add(const Duration(days: 30));
  for (final root in records.where(
    (e) => e.isTodo && e.todoRepeat != null && !e.deleted,
  )) {
    var at = now.isBefore(root.start) ? dayOnly(root.start) : now;
    while (!at.isAfter(horizon) && at.year <= 2099) {
      for (final e in resolveTodos(
        [root, ...records.where((e) => e.seriesId == root.id)],
        calendar,
        at,
        includeSingles: false,
        includePastCycles: false,
      )) {
        result[e.id] = e;
      }
      at = todoCycleAt(root, at)!.end;
    }
  }
  return result.values.toList();
}

enum TodoFilter { pending, completed, overdue, all }

extension TodoFilterLabel on TodoFilter {
  String get label => switch (this) {
    TodoFilter.pending => '未完成',
    TodoFilter.completed => '已完成',
    TodoFilter.overdue => '已逾期',
    TodoFilter.all => '全部',
  };
}

List<ScheduleEvent> orderedTodos(
  Iterable<ScheduleEvent> tasks,
  AppSettings settings,
) {
  final result = tasks.where((e) => e.isTodo && !e.deleted).toList();
  result.sort((a, b) {
    var c = switch (settings.todoSort) {
      TodoSort.created => a.createdAt.compareTo(b.createdAt),
      TodoSort.importance => a.todoOrder.compareTo(b.todoOrder),
      TodoSort.deadline =>
        a.deadline == null
            ? b.deadline == null
                  ? 0
                  : 1
            : b.deadline == null
            ? -1
            : a.deadline!.compareTo(b.deadline!),
    };
    if (c == 0) c = a.createdAt.compareTo(b.createdAt);
    if (c == 0) c = a.id.compareTo(b.id);
    return settings.todoSortDescending ? -c : c;
  });
  return result;
}

bool matchesTodo(ScheduleEvent e, TodoFilter filter, DateTime now) =>
    switch (filter) {
      TodoFilter.pending => !e.completed,
      TodoFilter.completed => e.completed,
      TodoFilter.overdue => e.statusAt(now) == ScheduleStatus.overdue,
      TodoFilter.all => true,
    };
